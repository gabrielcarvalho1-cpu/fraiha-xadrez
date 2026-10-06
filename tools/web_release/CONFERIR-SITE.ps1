# FRAIHA __TAG__ — confere no SITE PUBLICADO se todos os arquivos da build estão no ar (só leitura).
# Para cada caminho de ARQUIVOS-SHA256.txt faz um pedido HEAD e compara o tamanho.
# Pega o erro do R45: voice/ não enviada → 404 → "Não foi possível carregar a voz".
param([string]$Site = 'https://jogar.fraihaxadrez.com')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$rows = Get-Content -LiteralPath (Join-Path $root 'ARQUIVOS-SHA256.txt') | Where-Object { $_ -match '^[^#\s]\S*\s+\d+\s+[0-9A-Fa-f]{64}$' }
$bad = 0
foreach ($row in $rows) {
  $rel, $size, $hash = $row -split '\s+'
  $url = $Site.TrimEnd('/') + '/' + $rel + '?conferir=' + [DateTime]::UtcNow.Ticks
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 30
    $len = [int64]($r.Headers['Content-Length'] | Select-Object -First 1)
    if ($len -gt 0 -and $len -ne [int64]$size) { Write-Host "TAMANHO DIFERENTE  $rel  (site $len, build $size) - versao antiga no bucket/cache?" -ForegroundColor Yellow; $bad++ }
    else { Write-Host "OK  $rel" }
  } catch {
    Write-Host "FALTANDO NO SITE  $rel  ($($_.Exception.Message))" -ForegroundColor Red; $bad++
  }
}
if ($bad -eq 0) { Write-Host "`nTUDO NO AR: $($rows.Count) arquivos conferidos em $Site" -ForegroundColor Green }
else { Write-Host "`n$bad problema(s). Reenvie os arquivos marcados (pastas engines/ e voice/ inclusive)." -ForegroundColor Red }
