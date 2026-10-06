# FRAIHA __TAG__ — monta a pasta UPLOAD com EXATAMENTE os arquivos do bucket R2 (fraiha-xadrez-web).
# Lê ARQUIVOS-SHA256.txt (lista completa: index.*, engines/, voice/), junta as partes e confere
# tamanho + SHA256 de CADA arquivo (decodifica as imagens .png.b64). Se faltar qualquer um (ex.: a pasta voice/), PARA com erro.
# Não envia nada para a internet.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$up = Join-Path $root 'UPLOAD'
try {
  if (Test-Path -LiteralPath $up) { Remove-Item -LiteralPath $up -Recurse -Force }
  New-Item -ItemType Directory -Path $up | Out-Null
  $rows = Get-Content -LiteralPath (Join-Path $root 'ARQUIVOS-SHA256.txt') | Where-Object { $_ -match '^[^#\s]\S*\s+\d+\s+[0-9A-Fa-f]{64}$' }
  if ($rows.Count -lt 15) { throw "ARQUIVOS-SHA256.txt incompleto ($($rows.Count) linhas)." }
  $count = @{ 'raiz' = 0; 'engines' = 0; 'voice' = 0 }
  foreach ($row in $rows) {
    $rel, $size, $hash = $row -split '\s+'
    $winRel = $rel -replace '/', '\'
    $dest = Join-Path $up $winRel
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $src = Join-Path $root $winRel
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dest }
    elseif (Test-Path -LiteralPath ($src + '.b64')) {
      # imagens vêm em base64 (a cópia para o PC recomprime PNG e mudaria o SHA256)
      $bytes = [Convert]::FromBase64String([System.IO.File]::ReadAllText($src + '.b64'))
      [System.IO.File]::WriteAllBytes($dest, $bytes)
    }
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
  if ($count['voice'] -lt 3) { throw 'A pasta voice/ esta incompleta: a voz daria 404 no site.' }
  if ($count['engines'] -lt 3) { throw 'A pasta engines/ esta incompleta: a analise daria 404 no site.' }
  Write-Host ''
  Write-Host ('CONFERIDO (tamanho + SHA256): raiz {0} | engines/ {1} | voice/ {2} | total {3}' -f $count['raiz'], $count['engines'], $count['voice'], $rows.Count) -ForegroundColor Green
  Write-Host ''
  Write-Host 'ENVIE PARA O BUCKET fraiha-xadrez-web O CONTEUDO INTEIRO DE:' -ForegroundColor Yellow
  Write-Host "  $up"
  Write-Host '  -> os arquivos index.* na raiz do bucket'
  Write-Host '  -> a PASTA engines/ como engines/ (3 arquivos)'
  Write-Host '  -> a PASTA voice/  como voice/   (3 arquivos)   <- sem ela a voz da 404'
  Write-Host ''
  Write-Host 'Depois do upload: rode CONFERIR-SITE-__TAG__.cmd (confere no site publicado).'
  Start-Process explorer.exe $up
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }
