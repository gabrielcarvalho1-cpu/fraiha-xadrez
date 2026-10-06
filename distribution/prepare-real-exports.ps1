param(
  [Parameter(Mandatory=$true)][string]$ExportA,
  [Parameter(Mandatory=$true)][string]$ExportB,
  [string]$LabelA = 'A',
  [string]$LabelB = 'B'
)
# DEV · prepara dois exports Windows REAIS do FRAIHA atual (A = versão instalada, B = atualização) para o
# launcher/updater. Cada pasta de origem tem exatamente FRAIHA.exe + FRAIHA.pck (export do preset
# "Windows Desktop"). Só LÊ as origens; escreve apenas em distribution/.local:
#   .local/real-A-dev-export, .local/real-B-dev-export  (EXE/PCK + online.cfg DEV com endpoint vazio + LEIA-ME)
#   .local/bin/dev-reviewed-exports.txt                  (pins locais: exe/pck/cfg aprovados pelo operador)
# CONTRATO OFFLINE (auditoria R46): o online.cfg do export DEV é SEMPRE exatamente o perfil offline
#   [online]\nserver_url=""\n   (UTF-8 sem BOM). Um online.cfg já existente com qualquer outro conteúdo
#   (ex.: endpoint de servidor) NÃO é aceito nem fixado nos pins: o script PARA (exit != 0) sem sobrescrever.
# Sem export/import do Godot, sem download, sem apagar nada. (Substitui a versão do Orca presa aos exports
# históricos V029/V030 — ver docs/FRAIHA_DISTRIBUTION_INTEGRATION_R46.md.)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
function Assert-NoReparse([string]$Path) {
  $p = [IO.Path]::GetFullPath($Path)
  while ($p) {
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Reparse path refused: $p" }
    $p = Split-Path -Parent $p
  }
}
function Sha([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() }
Assert-NoReparse (Join-Path $taskRoot '.local')
$cfgBytes = [Text.UTF8Encoding]::new($false).GetBytes("[online]`nserver_url=`"`"`n")
$offlineCfgSha = 'ffaee9060a72096d914fc15346a3021d316c2ace6e9f36b780c956c7d325606e'   # SHA256 desses bytes (igual em ReviewedPins.OfflineCfgSha)
$sha = [Security.Cryptography.SHA256]::Create()
if ((-join ($sha.ComputeHash($cfgBytes) | ForEach-Object { $_.ToString('x2') })) -ne $offlineCfgSha) { throw 'Perfil offline DEV interno inconsistente.' }
$readme = "FRAIHA DEV (launcher Windows) - build de TESTE offline.`r`nEndpoint vazio: nao conecta em servidor nenhum. Nao distribuir.`r`n"
$pins = @("# FRAIHA DEV - exports reais revisados (gerado por prepare-real-exports.ps1 em " + [DateTime]::UtcNow.ToString('u') + ")")
$inventory = @()
foreach ($pair in @(@($ExportA, 'A', $LabelA), @($ExportB, 'B', $LabelB))) {
  $src = (Resolve-Path -LiteralPath $pair[0]).Path
  Assert-NoReparse $src
  $entries = @(Get-ChildItem -LiteralPath $src -Force)
  $exe = Join-Path $src 'FRAIHA.exe'; $pck = Join-Path $src 'FRAIHA.pck'
  if (!(Test-Path -LiteralPath $exe -PathType Leaf) -or !(Test-Path -LiteralPath $pck -PathType Leaf)) { throw "Export $($pair[1]) precisa de FRAIHA.exe e FRAIHA.pck: $src" }
  $extra = $entries | Where-Object { $_.Name -notin @('FRAIHA.exe', 'FRAIHA.pck', 'FRAIHA.console.exe') }
  if ($extra) { throw "Export $($pair[1]) tem arquivos extras (DLL/engine?) que o formato fraiha-flat-zip-v2 nao cobre: $($extra.Name -join ', ')" }
  $dest = Join-Path $taskRoot (".local/real-" + $pair[1] + "-dev-export")
  Assert-NoReparse $dest
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  foreach ($f in @(@($exe, 'FRAIHA.exe'), @($pck, 'FRAIHA.pck'))) {
    $t = Join-Path $dest $f[1]
    if (Test-Path -LiteralPath $t) { if ((Sha $t) -ne (Sha $f[0])) { throw "Ja existe $t diferente; preserve e investigue (nada foi sobrescrito)." } }
    else { Copy-Item -LiteralPath $f[0] -Destination $t }
  }
  $cfg = Join-Path $dest 'online.cfg'
  if (!(Test-Path -LiteralPath $cfg)) { [IO.File]::WriteAllBytes($cfg, $cfgBytes) }
  elseif ((Sha $cfg) -ne $offlineCfgSha) { throw "online.cfg existente em $dest NAO e o perfil offline DEV (endpoint vazio). Nada foi aprovado nem sobrescrito: confira/remova esse arquivo e rode de novo." }
  if ((Sha $cfg) -ne $offlineCfgSha) { throw "online.cfg gerado em $dest diverge do perfil offline DEV." }
  $rd = Join-Path $dest 'LEIA-ME.txt'; if (!(Test-Path -LiteralPath $rd)) { [IO.File]::WriteAllText($rd, $readme, [Text.UTF8Encoding]::new($false)) }
  $pins += "exe " + (Sha (Join-Path $dest 'FRAIHA.exe'))
  $pins += "pck " + (Sha (Join-Path $dest 'FRAIHA.pck'))
  $pins += "cfg " + (Sha $cfg)
  foreach ($n in @('FRAIHA.exe', 'FRAIHA.pck', 'online.cfg', 'LEIA-ME.txt')) {
    $f = Join-Path $dest $n
    $inventory += [pscustomobject]@{ export = $pair[1]; label = $pair[2]; file = $n; source = $src; size = (Get-Item -LiteralPath $f).Length; sha256 = (Sha $f) }
  }
}
$bin = Join-Path $taskRoot '.local/bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null
$pinFile = Join-Path $bin 'dev-reviewed-exports.txt'
[IO.File]::WriteAllLines($pinFile, [string[]]($pins | Select-Object -Unique), [Text.UTF8Encoding]::new($false))
$report = Join-Path $taskRoot ('.local/real-export-inventory-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
$inventory | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $report -Encoding UTF8
Write-Output "OK: exports A/B preparados (endpoint DEV vazio); pins em $pinFile; inventario $report"
