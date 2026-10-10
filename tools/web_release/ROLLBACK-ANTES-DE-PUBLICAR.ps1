# FRAIHA __TAG__ - ROLLBACK ANTES DE PUBLICAR (so leitura no site; nao envia nada).
# Rode ANTES de subir esta entrega. Baixa do site a versao que esta NO AR agora e guarda uma copia completa e
# conferida (SHA-256) numa pasta ROLLBACK-<data>, pronta para voltar atras:
#   - index.html anterior e TODOS os arquivos que ele cita (motor/pacote/splash com SHA-256 no nome);
#   - os arquivos de URL ESTAVEL (icones, engines/, voice/...) como estao no ar agora. Restaurar so o index.html
#     NAO basta quando um arquivo estavel muda nesta entrega: o rollback tem que repor tambem esses.
# Gera: ROLLBACK-*/ARQUIVOS-SHA256.txt (manifesto da versao anterior), UPLOAD/ + UPLOAD-2-POR-ULTIMO/ (para voltar),
# CONFERIR-SITE-__TAG__.ps1/.cmd (confere o rollback no site) e LEIA-ME-ROLLBACK.txt (o que preservar no bucket e
# o que esta entrega vai sobrescrever).
# FAIL-CLOSED: qualquer falha de download/conferencia = exit 1 e a pasta parcial e apagada.
param([string]$Site = 'https://jogar.fraihaxadrez.com', [int]$TimeoutSec = 300)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$root = $PSScriptRoot
$rc = 1
$dest = Join-Path $root ('ROLLBACK-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
try {
  $manifest = Join-Path $root 'ARQUIVOS-SHA256.txt'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'ARQUIVOS-SHA256.txt desta entrega nao encontrado.' }
  $novo = @{}
  foreach ($l in @(Get-Content -LiteralPath $manifest)) { if ($l -match '^([^#\s]\S*)\s+(\d+)\s+([0-9A-Fa-f]{64})$') { $novo[$Matches[1]] = $Matches[3].ToUpper() } }
  if ($novo.Count -lt 15) { throw "ARQUIVOS-SHA256.txt desta entrega incompleto ($($novo.Count) linhas)." }

  Add-Type -AssemblyName System.Net.Http
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
  $http = New-Object System.Net.Http.HttpClient($handler)
  $http.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stamp = [DateTime]::UtcNow.Ticks
  function Baixar([string]$rel) {
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, ($Site.TrimEnd('/') + '/' + $rel + '?rollback=' + $stamp))
    $req.Headers.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
    $req.Headers.CacheControl.NoCache = $true
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    return @{ status = [int]$res.StatusCode; bytes = $res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult() }
  }
  function Hex([byte[]]$b) { return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '').ToUpper() }

  Write-Host "Lendo a versao NO AR em $Site ..." -ForegroundColor Cyan
  $idx = Baixar 'index.html'
  New-Item -ItemType Directory -Path $dest | Out-Null
  $up = Join-Path $dest 'UPLOAD'; $up2 = Join-Path $dest 'UPLOAD-2-POR-ULTIMO'
  New-Item -ItemType Directory -Path $up, $up2 | Out-Null
  $linhas = @(); $preservar = @(); $sobrescreve = @(); $iguais = @(); $ausentes = @()
  if ($idx.status -eq 404) {
    $linhas += "# ROLLBACK de $Site em $(Get-Date -Format s) - SITE VAZIO (primeira publicacao): nao ha versao anterior."
    Write-Host 'Site sem index.html: primeira publicacao, nada a preservar.' -ForegroundColor Yellow
  } else {
    if ($idx.status -ne 200) { throw "index.html do site respondeu HTTP $($idx.status)." }
    $html = [System.Text.Encoding]::UTF8.GetString($idx.bytes)
    $m = [regex]::Match($html, 'const GODOT_CONFIG = (\{.*?\});')
    if (-not $m.Success) { throw 'index.html do site sem GODOT_CONFIG: nao da para saber quais arquivos ele usa.' }
    $cfg = $m.Groups[1].Value | ConvertFrom-Json
    $exe = [string]$cfg.executable; $pck = [string]$cfg.mainPack
    if (-not $exe -or -not $pck) { throw 'GODOT_CONFIG do site sem executable/mainPack.' }
    $amb = [regex]::Match($html, '<meta name="fraiha-ambiente" content="([a-z]+)">')
    $ambTxt = if ($amb.Success) { $amb.Groups[1].Value } else { 'sem marca (build anterior a R59)' }
    $linhas += "# ROLLBACK de $Site em $(Get-Date -Format s) - versao anterior: motor $exe, pacote $pck, ambiente $ambTxt"
    $citados = @($pck, "$exe.js", "$exe.wasm", "$exe.audio.worklet.js", "$exe.audio.position.worklet.js")
    foreach ($s in [regex]::Matches($html, '(index-s[0-9a-f]{16}\.png|index\.png)')) { if ($citados -notcontains $s.Value) { $citados += $s.Value } }
    foreach ($s in [regex]::Matches($html, 'src="([A-Za-z0-9_./-]+\.js)"')) { $v = $s.Groups[1].Value; if ($v -notmatch '^(https?:)?//' -and $citados -notcontains $v) { $citados += $v } }
    $estaveis = @($novo.Keys | Where-Object { $_ -ne 'index.html' -and $_ -notmatch '^index-[eps][0-9a-f]{16}\.' })
    $lista = @($citados) + @($estaveis | Where-Object { $citados -notcontains $_ })
    $lista = @($lista | Select-Object -Unique)
    $salvar = { param($rel, $bytes)
      $p = Join-Path $up ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
      $d = Split-Path -Parent $p; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
      [System.IO.File]::WriteAllBytes($p, $bytes) }
    foreach ($rel in $lista) {
      $r = Baixar $rel
      if ($r.status -eq 404) {
        if ($citados -contains $rel) { throw "a versao NO AR cita $rel, mas ele nao esta no site (a versao atual ja esta quebrada; rollback para ela nao e confiavel)." }
        $ausentes += $rel; continue
      }
      if ($r.status -ne 200) { throw "$rel respondeu HTTP $($r.status)." }
      $h = Hex $r.bytes
      if ($rel -match '^index-[ps]([0-9a-f]{16})\.' -and $h.Substring(0, 16).ToLower() -ne $Matches[1]) { throw "$rel no ar com conteudo que nao corresponde ao nome (SHA-256 $($h.Substring(0,16)))." }
      & $salvar $rel $r.bytes
      $linhas += "$rel  $($r.bytes.Length)  $h"
      $fp = $rel -match '^index-[eps][0-9a-f]{16}\.'
      if ($fp) { $preservar += $rel }
      elseif ($novo.ContainsKey($rel)) { if ($novo[$rel] -ne $h) { $sobrescreve += $rel } else { $iguais += $rel } }
      else { $preservar += $rel }
      Write-Host "OK  $rel  ($($h.Substring(0,16)))"
    }
    [System.IO.File]::WriteAllBytes((Join-Path $up2 'index.html'), $idx.bytes)
    $linhas += "index.html  $($idx.bytes.Length)  $(Hex $idx.bytes)"
  }
  $linhas | Set-Content -LiteralPath (Join-Path $dest 'ARQUIVOS-SHA256.txt') -Encoding ASCII
  # conferidor do rollback (o mesmo script de conferencia, lendo o manifesto DESTA pasta)
  foreach ($n in @('CONFERIR-SITE-__TAG__.ps1', 'CONFERIR-SITE-__TAG__.cmd')) {
    $src = Join-Path $root $n
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $dest $n) }
  }
  $txt = @()
  $txt += "FRAIHA - ROLLBACK da versao que estava no ar ANTES da entrega __TAG__"
  $txt += "Gerado em $(Get-Date -Format s) a partir de $Site"
  $txt += ''
  if ($idx.status -eq 404) { $txt += 'SITE VAZIO: nao havia versao anterior. Rollback = remover o index.html da entrega.' }
  else {
    $txt += "PRESERVAR NO BUCKET (NAO apague; a versao anterior usa estes enderecos):"
    foreach ($p in $preservar) { $txt += "  $p" }
    $txt += ''
    $txt += "URL ESTAVEL QUE ESTA ENTREGA VAI SOBRESCREVER (o rollback PRECISA repor estes, nao basta o index.html):"
    if ($sobrescreve.Count) { foreach ($p in $sobrescreve) { $txt += "  $p" } } else { $txt += '  (nenhum: os estaveis sao identicos)' }
    $txt += ''
    $txt += "URL ESTAVEL IDENTICA nas duas versoes: $($iguais.Count) arquivo(s)."
    if ($ausentes.Count) { $txt += "Novos nesta entrega (nao existiam no ar): $($ausentes -join ', ')" }
    $txt += ''
    $txt += 'COMO VOLTAR (se a entrega nova der problema):'
    $txt += '  1. Suba TODO o conteudo de UPLOAD desta pasta no bucket fraiha-xadrez-web (substitui os estaveis).'
    $txt += '  2. Depois que o passo 1 chegar a 100%, suba o index.html de UPLOAD-2-POR-ULTIMO.'
    $txt += "  3. Rode CONFERIR-SITE-__TAG__.cmd DESTA pasta: tem que dar TUDO NO AR (SHA-256 da versao anterior)."
  }
  $txt | Set-Content -LiteralPath (Join-Path $dest 'LEIA-ME-ROLLBACK.txt') -Encoding UTF8
  Write-Host ''
  Write-Host "ROLLBACK PRONTO: $dest" -ForegroundColor Green
  if ($idx.status -ne 404) {
    Write-Host "  preservar no bucket: $($preservar.Count) | estaveis que esta entrega sobrescreve: $($sobrescreve.Count) | estaveis iguais: $($iguais.Count)" -ForegroundColor Green
    foreach ($p in $sobrescreve) { Write-Host "  SOBRESCREVE: $p" -ForegroundColor Yellow }
  }
  $rc = 0
} catch {
  Write-Host "ERRO: $_" -ForegroundColor Red
  Write-Host 'ROLLBACK NAO GERADO (pasta parcial apagada). NAO publique sem ele.' -ForegroundColor Red
  try { if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force } } catch {}
}
exit $rc
