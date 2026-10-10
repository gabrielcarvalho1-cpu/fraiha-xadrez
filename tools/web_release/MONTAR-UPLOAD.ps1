# FRAIHA __TAG__ — monta a pasta UPLOAD com EXATAMENTE os arquivos do bucket R2 (fraiha-xadrez-web).
# Lê ARQUIVOS-SHA256.txt (lista completa: index.*, engines/, voice/), junta as partes e confere
# tamanho + SHA256 de CADA arquivo (decodifica as imagens .png.b64). Se faltar qualquer um (ex.: a pasta voice/), PARA com erro.
# Não envia nada para a internet.
# R55.5 (cache Web): arquivos com SHA-256 no nome (index-e…/index-p…/index-s…) vão em UPLOAD; o index.html vai
# SOZINHO em UPLOAD-2-POR-ULTIMO e só deve subir DEPOIS que o UPLOAD terminar (o html novo cita os arquivos novos).
# FAIL-CLOSED (auditoria R46): sucesso real = exit 0; QUALQUER falha = exit 1 e a pasta UPLOAD parcial
# é removida (nada incompleto fica pronto para subir).
# AMBIENTE (QA × produção): o ARQUIVOS-SHA256.txt diz "# AMBIENTE staging|producao · servidor ..." (conferido no
# PCK pelo empacotador) e o index.html tem <meta name="fraiha-ambiente">. Sem isso, ou se divergirem, PARA.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$up = Join-Path $root 'UPLOAD'
$up2 = Join-Path $root 'UPLOAD-2-POR-ULTIMO'
$sep = [IO.Path]::DirectorySeparatorChar
$rc = 1
try {
  $manifest = Join-Path $root 'ARQUIVOS-SHA256.txt'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'ARQUIVOS-SHA256.txt nao encontrado nesta pasta (copie a pasta inteira de novo).' }
  foreach ($d in @($up, $up2)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
  New-Item -ItemType Directory -Path $up | Out-Null
  $all = @(Get-Content -LiteralPath $manifest)
  $hashed = [bool]($all | Where-Object { $_ -match '^# R55\.5 ' })
  if ($hashed) { New-Item -ItemType Directory -Path $up2 | Out-Null }
  $ambLine = @($all | Where-Object { $_ -match '^# AMBIENTE (staging|producao) - servidor (wss://\S+)$' })
  if ($ambLine.Count -ne 1) { throw 'ARQUIVOS-SHA256.txt sem a linha de AMBIENTE (build antiga ou alterada): gere de novo.' }
  $null = $ambLine[0] -match '^# AMBIENTE (staging|producao) - servidor (wss://\S+)$'
  $amb = $Matches[1]; $servidor = $Matches[2]
  if ($amb -eq 'producao' -and $servidor -match 'staging') { throw "build marcada como PRODUCAO aponta para STAGING ($servidor)." }
  if ($amb -eq 'staging' -and $servidor -notmatch 'staging') { throw "build marcada como STAGING aponta para fora do staging ($servidor)." }
  $ambNome = if ($amb -eq 'producao') { 'PRODUCAO (jogadores reais)' } else { 'STAGING (QA/testes) - NAO e producao' }
  $ambCor = if ($amb -eq 'producao') { 'Magenta' } else { 'Cyan' }
  Write-Host ''
  Write-Host "AMBIENTE DESTA BUILD: $ambNome" -ForegroundColor $ambCor
  Write-Host "SERVIDOR: $servidor" -ForegroundColor $ambCor
  $rows = @($all | Where-Object { $_ -match '^[^#\s]\S*\s+\d+\s+[0-9A-Fa-f]{64}$' })
  if ($rows.Count -lt 15) { throw "ARQUIVOS-SHA256.txt incompleto ($($rows.Count) linhas)." }
  $count = @{ 'raiz' = 0; 'engines' = 0; 'voice' = 0 }
  foreach ($row in $rows) {
    $rel, $size, $hash = $row -split '\s+'
    $winRel = $rel -replace '/', $sep
    $dest = if ($hashed -and $rel -eq 'index.html') { Join-Path $up2 $winRel } else { Join-Path $up $winRel }
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $src = Join-Path $root $winRel
    if (Test-Path -LiteralPath ($src + '.b64')) {
      # imagens vêm em base64 (a cópia para o PC recomprime PNG e mudaria o SHA256); o .b64 tem prioridade
      $bytes = [Convert]::FromBase64String([System.IO.File]::ReadAllText($src + '.b64'))
      [System.IO.File]::WriteAllBytes($dest, $bytes)
    }
    elseif (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dest }
    else {
      $parts = @(Get-ChildItem -LiteralPath (Split-Path -Parent $src) -Filter ((Split-Path -Leaf $src) + '.part*') -ErrorAction SilentlyContinue | Sort-Object Name)
      if ($parts.Count -eq 0) { throw "FALTANDO: $rel (copie a pasta inteira de novo)." }
      $out = [System.IO.File]::Create($dest)
      try { foreach ($p in $parts) { $b = [System.IO.File]::ReadAllBytes($p.FullName); $out.Write($b, 0, $b.Length) } } finally { $out.Close() }
    }
    $item = Get-Item -LiteralPath $dest
    if ($item.Length -ne [int64]$size) { throw "$rel com tamanho errado ($($item.Length), esperado $size)." }
    $got = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    if ($got -ne $hash.ToUpper()) { throw "$rel corrompido (SHA256 $got, esperado $hash)." }
    $top = if ($rel.Contains('/')) { $rel.Split('/')[0] } else { 'raiz' }
    $count[$top] = $count[$top] + 1
  }
  $htmlFinal = if ($hashed) { Join-Path $up2 'index.html' } else { Join-Path $up 'index.html' }
  $htmlText = [System.IO.File]::ReadAllText($htmlFinal)
  if ($htmlText -notmatch ('<meta name="fraiha-ambiente" content="' + $amb + '">')) { throw "o index.html nao esta marcado como $amb (mistura de builds?)." }
  if ($count['voice'] -lt 3) { throw 'A pasta voice/ esta incompleta: a voz daria 404 no site.' }
  if ($count['engines'] -lt 3) { throw 'A pasta engines/ esta incompleta: a analise daria 404 no site.' }
  Write-Host ''
  Write-Host "AMBIENTE: $ambNome - servidor $servidor" -ForegroundColor $ambCor
  Write-Host ('CONFERIDO (tamanho + SHA256): raiz {0} | engines/ {1} | voice/ {2} | total {3}' -f $count['raiz'], $count['engines'], $count['voice'], $rows.Count) -ForegroundColor Green
  Write-Host ''
  Write-Host 'PASSO 1 - ENVIE PARA O BUCKET fraiha-xadrez-web O CONTEUDO INTEIRO DE:' -ForegroundColor Yellow
  Write-Host "  $up"
  Write-Host '  -> os arquivos index* na raiz do bucket'
  Write-Host '  -> a PASTA engines/ como engines/ (3 arquivos)'
  Write-Host '  -> a PASTA voice/  como voice/   (3 arquivos)   <- sem ela a voz da 404'
  Write-Host '  NAO apague do bucket os arquivos index-e* / index-p* / index-s* antigos (abas abertas ainda usam).'
  Write-Host ''
  if ($hashed) {
    Write-Host 'PASSO 2 - SO DEPOIS QUE O PASSO 1 TERMINAR (barra do upload em 100%), envie o index.html de:' -ForegroundColor Yellow
    Write-Host "  $up2"
    Write-Host '  -> ele substitui o index.html da raiz do bucket. E isso que troca a versao do jogo.'
    Write-Host ''
  }
  Write-Host 'Depois do upload: rode CONFERIR-SITE-__TAG__.cmd (confere no site publicado).'
  $rc = 0
  if ($env:OS -eq 'Windows_NT' -and -not $env:FRAIHA_NO_EXPLORER) { try { Start-Process explorer.exe $up } catch {} }
} catch {
  Write-Host "ERRO: $_" -ForegroundColor Red
  Write-Host 'NADA PRONTO PARA SUBIR: a pasta UPLOAD incompleta foi removida.' -ForegroundColor Red
  foreach ($d in @($up, $up2)) { try { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } } catch {} }
}
exit $rc
