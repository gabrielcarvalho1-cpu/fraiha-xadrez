# FRAIHA __TAG__ - CONFERENCIA FORTE do site publicado (so leitura; nao envia nada).
# Baixa CADA arquivo de ARQUIVOS-SHA256.txt do site (sem cache) e compara TAMANHO e SHA-256 com a entrega.
# Separa os arquivos em dois grupos (o pacote index-p e o splash index-s tem o SHA-256 do PROPRIO arquivo no nome;
# os 4 arquivos do motor index-e compartilham o SHA-256 do conjunto):
#   - FINGERPRINT (index-e*/index-p*/index-s*): o nome carrega o SHA-256; o conteudo tambem tem que bater com o nome.
#   - URL ESTAVEL (index.html, icones, engines/, voice/...): o mesmo endereco serve versoes diferentes; so o SHA-256
#     prova que e a versao desta entrega (o tamanho igual nao basta).
# O index.html publico tem que ser EXATAMENTE o desta entrega e citar exatamente o motor/pacote desta entrega.
# FAIL-CLOSED: "TUDO NO AR" so aparece com 100% dos arquivos com o SHA-256 da entrega (exit 0). Qualquer
# arquivo faltando, diferente, inacessivel ou manifesto ausente/incompleto = exit 1 e relatorio do que fazer.
# Serve tambem para conferir um ROLLBACK: rode a copia deste script que fica dentro da pasta ROLLBACK-*.
param([string]$Site = 'https://jogar.fraihaxadrez.com', [int]$TimeoutSec = 300)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$root = $PSScriptRoot
$manifest = Join-Path $root 'ARQUIVOS-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Write-Host 'ERRO: ARQUIVOS-SHA256.txt nao encontrado nesta pasta.' -ForegroundColor Red; exit 1 }
$all = @(Get-Content -LiteralPath $manifest)
$rows = @($all | Where-Object { $_ -match '^[^#\s]\S*\s+\d+\s+[0-9A-Fa-f]{64}$' })
$minRows = 15
if ($all | Where-Object { $_ -match '^# ROLLBACK ' }) { $minRows = 2 }
if ($rows.Count -lt $minRows) { Write-Host "ERRO: ARQUIVOS-SHA256.txt incompleto ($($rows.Count) linhas)." -ForegroundColor Red; exit 1 }
$ambLine = @($all | Where-Object { $_ -match '^# AMBIENTE ' }) | Select-Object -First 1
if ($ambLine) { Write-Host ("ENTREGA: " + $ambLine.Substring(2)) -ForegroundColor Cyan }

Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$http = New-Object System.Net.Http.HttpClient($handler)
$http.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
$sha = [System.Security.Cryptography.SHA256]::Create()
$stamp = [DateTime]::UtcNow.Ticks
function Baixar([string]$rel) {
  $url = $Site.TrimEnd('/') + '/' + $rel + '?conferir=' + $stamp
  $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
  $req.Headers.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
  $req.Headers.CacheControl.NoCache = $true
  $res = $http.SendAsync($req).GetAwaiter().GetResult()
  $bytes = $res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
  $cc = ''; if ($res.Headers.CacheControl) { $cc = $res.Headers.CacheControl.ToString() }
  return @{ status = [int]$res.StatusCode; bytes = $bytes; cc = $cc }
}
function Hex([byte[]]$b) { return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '').ToUpper() }

$fp = @(); $est = @()
foreach ($row in $rows) { $rel = ($row -split '\s+')[0]; if ($rel -match '^index-[eps][0-9a-f]{16}\.') { $fp += $row } else { $est += $row } }
$bad = 0; $semCache = 0; $problemas = @(); $htmlPublico = $null; $htmlRow = $null
foreach ($grupo in @(@{ nome = 'FINGERPRINT (nome com SHA-256; ficam no bucket entre versoes)'; lista = $fp }, @{ nome = 'URL ESTAVEL (mesmo endereco em toda versao: so o SHA-256 prova a versao)'; lista = $est })) {
  if ($grupo.lista.Count -eq 0) { continue }
  Write-Host ''; Write-Host $grupo.nome -ForegroundColor Cyan
  foreach ($row in $grupo.lista) {
    $rel, $size, $hash = $row -split '\s+'
    $hash = $hash.ToUpper()
    if ($rel -eq 'index.html') { $htmlRow = @{ size = [int64]$size; hash = $hash } }
    try { $r = Baixar $rel } catch { Write-Host "INACESSIVEL  $rel  ($($_.Exception.Message))" -ForegroundColor Red; $bad++; $problemas += "$rel : inacessivel"; continue }
    if ($r.status -ne 200) { Write-Host "FALTANDO NO SITE  $rel  (HTTP $($r.status))" -ForegroundColor Red; $bad++; $problemas += "$rel : HTTP $($r.status) (nao subiu ou upload interrompido)"; continue }
    $got = Hex $r.bytes
    if ($rel -eq 'index.html') { $htmlPublico = [System.Text.Encoding]::UTF8.GetString($r.bytes) }
    if ([int64]$r.bytes.Length -ne [int64]$size -or $got -ne $hash) {
      $why = if ([int64]$r.bytes.Length -ne [int64]$size) { "tamanho $($r.bytes.Length), esperado $size" } else { 'MESMO tamanho, conteudo diferente' }
      Write-Host "SHA-256 DIFERENTE  $rel  ($why; site $($got.Substring(0,16)) entrega $($hash.Substring(0,16)))" -ForegroundColor Red
      $bad++; $problemas += "$rel : versao publicada NAO e a desta entrega ($why)"; continue
    }
    if ($rel -match '^index-[ps]([0-9a-f]{16})\.' -and $got.Substring(0, 16).ToLower() -ne $Matches[1]) {
      Write-Host "NOME x CONTEUDO  $rel  (SHA-256 nao comeca com $($Matches[1]))" -ForegroundColor Red; $bad++; $problemas += "$rel : conteudo nao corresponde ao nome"; continue
    }
    Write-Host "OK  $rel  ($($got.Substring(0,16)))"
    if ($rel -match '^index-[eps][0-9a-f]{16}\.' -and $r.cc -notmatch 'immutable') { $semCache++ }
  }
}
# o index.html publicado cita exatamente o motor/pacote da entrega (index novo com assets antigos / mistura)
if ($htmlPublico -ne $null) {
  $m = [regex]::Match($htmlPublico, 'const GODOT_CONFIG = (\{.*?\});')
  if ($m.Success) {
    $cfg = $m.Groups[1].Value | ConvertFrom-Json
    $nomes = @($rows | ForEach-Object { ($_ -split '\s+')[0] })
    $citados = @([string]$cfg.mainPack, ([string]$cfg.executable + '.wasm'), ([string]$cfg.executable + '.js'))
    foreach ($c in $citados) { if ($nomes -notcontains $c) { Write-Host "INDEX CITA ARQUIVO FORA DA ENTREGA  $c" -ForegroundColor Red; $bad++; $problemas += "index.html publico cita $c, que nao e desta entrega" } }
  }
}
if ($htmlRow -eq $null) { Write-Host 'AVISO: o manifesto nao lista index.html.' -ForegroundColor Yellow }
if ($semCache -gt 0) { Write-Host "`nAVISO: $semCache arquivo(s) com SHA-256 no nome sem Cache-Control immutable. Ver docs/web/R55_5_CACHE_WEB.md (Worker)." -ForegroundColor Yellow }
if ($bad -eq 0) {
  Write-Host "`nTUDO NO AR: $($rows.Count) arquivos com o SHA-256 da entrega em $Site (fingerprint $($fp.Count) | URL estavel $($est.Count))" -ForegroundColor Green
  exit 0
}
Write-Host "`nNAO CONFERE: $bad problema(s). O site publico NAO corresponde a esta entrega:" -ForegroundColor Red
foreach ($p in $problemas) { Write-Host "  - $p" -ForegroundColor Red }
Write-Host 'O que fazer: reenvie os arquivos marcados (UPLOAD primeiro; index.html por ultimo) e rode de novo.' -ForegroundColor Red
Write-Host 'Se for voltar a versao anterior: use a pasta ROLLBACK-* gerada ANTES de publicar (ver LEIA-ME-ROLLBACK.txt).' -ForegroundColor Red
exit 1
