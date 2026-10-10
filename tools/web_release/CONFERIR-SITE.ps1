# FRAIHA __TAG__ — confere no SITE PUBLICADO se todos os arquivos da build estão no ar (só leitura).
# Para cada caminho de ARQUIVOS-SHA256.txt faz um pedido HEAD e compara o tamanho.
# Pega o erro do R45: voice/ não enviada → 404 → "Não foi possível carregar a voz".
param([string]$Site = 'https://jogar.fraihaxadrez.com')
# FAIL-CLOSED (auditoria R46): tudo no ar = exit 0; manifesto ausente/incompleto ou qualquer arquivo
# faltando/diferente = exit 1.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Join-Path $root 'ARQUIVOS-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Write-Host 'ERRO: ARQUIVOS-SHA256.txt nao encontrado nesta pasta.' -ForegroundColor Red; exit 1 }
$rows = @(Get-Content -LiteralPath $manifest | Where-Object { $_ -match '^[^#\s]\S*\s+\d+\s+[0-9A-Fa-f]{64}$' })
if ($rows.Count -lt 15) { Write-Host "ERRO: ARQUIVOS-SHA256.txt incompleto ($($rows.Count) linhas)." -ForegroundColor Red; exit 1 }
$bad = 0
$semCache = 0
foreach ($row in $rows) {
  $rel, $size, $hash = $row -split '\s+'
  $url = $Site.TrimEnd('/') + '/' + $rel + '?conferir=' + [DateTime]::UtcNow.Ticks
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 30
    $len = [int64]($r.Headers['Content-Length'] | Select-Object -First 1)
    if ($len -gt 0 -and $len -ne [int64]$size) { Write-Host "TAMANHO DIFERENTE  $rel  (site $len, build $size) - versao antiga no bucket/cache?" -ForegroundColor Yellow; $bad++ }
    else { Write-Host "OK  $rel" }
    # R55.5: arquivo com SHA-256 no nome deve ter cache longo (Worker novo). Sem isso o jogo funciona,
    # mas o PCK continua sendo pedido de novo no reload (so o cache local do index.html evita).
    if ($rel -match '^index-[eps][0-9a-f]{16}\.') {
      $cc = [string]($r.Headers['Cache-Control'] | Select-Object -First 1)
      if ($cc -notmatch 'immutable') { Write-Host "  AVISO: $rel sem Cache-Control immutable (recebido: '$cc') - Worker antigo?" -ForegroundColor Yellow; $semCache++ }
    }
  } catch {
    Write-Host "FALTANDO NO SITE  $rel  ($($_.Exception.Message))" -ForegroundColor Red; $bad++
  }
}
if ($semCache -gt 0) { Write-Host "`nAVISO: $semCache arquivo(s) sem cache longo. Ver docs/web/R55_5_CACHE_WEB.md (Worker)." -ForegroundColor Yellow }
if ($bad -eq 0) { Write-Host "`nTUDO NO AR: $($rows.Count) arquivos conferidos em $Site" -ForegroundColor Green; exit 0 }
Write-Host "`n$bad problema(s). Reenvie os arquivos marcados (pastas engines/ e voice/ inclusive)." -ForegroundColor Red
exit 1
