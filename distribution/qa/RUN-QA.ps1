# FRAIHA Distribution · QA Windows REAL com o FRAIHA ATUAL (exports A = R45 b389849, B = R46 voz recebida).
# 1) remonta os exports e confere SHA256  2) build + suíte mock (29+ grupos)  3) prepara exports reais + pins
# 4) aceitação real: instala A, launcher detecta B, baixa, valida hash, aplica, abre o FRAIHA até a Home,
#    smoke de jogo no binário real, update inválido rejeitado, rollback, retry, jogo aberto, launcher normal.
# Tudo fica nesta pasta; nada vai para a internet (servidor só em 127.0.0.1:8765). Resultado: qa-output.txt
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Start-Transcript -Path (Join-Path $root 'qa-output.txt') -Force | Out-Null
try {
  Write-Output ("=== FRAIHA Distribution QA " + [DateTime]::UtcNow.ToString('u') + " em " + $root)
  Write-Output ("Windows: " + [Environment]::OSVersion.VersionString + " | .NET release: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release)
  $sums = Get-Content -LiteralPath (Join-Path $root 'exports\SHA256.txt')
  function Join-Parts([string]$prefix, [string]$dest) {
    $parts = @(Get-ChildItem -Path ($prefix + '.part*') | Sort-Object Name)
    if ($parts.Count -eq 0) { throw "Partes ausentes: $prefix" }
    $out = [IO.File]::Create($dest); try { foreach ($p in $parts) { $b = [IO.File]::ReadAllBytes($p.FullName); $out.Write($b, 0, $b.Length) } } finally { $out.Close() }
  }
  $map = @{ 'winA/FRAIHA.pck' = 'exports\A\FRAIHA.pck'; 'winB/FRAIHA.pck' = 'exports\B\FRAIHA.pck'; 'winB/FRAIHA.exe' = 'exports\FRAIHA.exe' }
  foreach ($line in $sums) {
    $hash, $name = $line -split '\s+', 2
    $dest = Join-Path $root $map[$name]
    if (!(Test-Path -LiteralPath $dest)) { Join-Parts ($dest) $dest }
    $got = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    if ($got -ne $hash) { throw "$name corrompido ($got <> $hash)" }
    Write-Output "OK $name $hash"
  }
  foreach ($x in @('A', 'B')) { $e = Join-Path $root "exports\$x\FRAIHA.exe"; if (!(Test-Path -LiteralPath $e)) { Copy-Item -LiteralPath (Join-Path $root 'exports\FRAIHA.exe') -Destination $e } }
  Get-ChildItem -Path (Join-Path $root 'exports\A\*.part*'), (Join-Path $root 'exports\B\*.part*') | Remove-Item
  if (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue) { throw 'Porta 8765 ocupada: feche o que estiver usando e rode de novo (nada foi encerrado).' }
  if (Get-Process -Name 'FRAIHA' -ErrorAction SilentlyContinue) { throw 'Feche o FRAIHA antes do QA (o teste confere jogo aberto).' }
  $dist = Join-Path $root 'distribution'
  Write-Output '=== [1/3] build + suite mock'
  & (Join-Path $dist 'build.ps1') -Test
  Write-Output '=== [2/3] exports reais A/B + pins locais'
  & (Join-Path $dist 'prepare-real-exports.ps1') -ExportA (Join-Path $root 'exports\A') -ExportB (Join-Path $root 'exports\B') -LabelA 'R45 b389849' -LabelB 'R46 voz recebida'
  Write-Output '=== [3/3] aceitacao real (FRAIHA atual)'
  & (Join-Path $dist 'build.ps1') -RealTest
  Write-Output '=== QA CONCLUIDO SEM FALHAS'
} catch { Write-Output ("=== QA FALHOU: " + $_) }
finally {
  Get-ChildItem -Path (Join-Path $root 'distribution\.local') -Directory -Filter 'rqa-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { Write-Output ("EVIDENCIA: " + $_.FullName) }
  Stop-Transcript | Out-Null
}
