param([Parameter(Mandatory=$true)][string]$SourceRoot)
# Read-only access to the two already approved historical export directories.
# No Godot export/import, script execution in source, downloads or cleanup.
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
function Assert-NoReparse([string]$Path) {
  $taskCurrent=[IO.Path]::GetFullPath($Path)
  while ($taskCurrent) {
    if ((Test-Path -LiteralPath $taskCurrent) -and ((Get-Item -LiteralPath $taskCurrent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Reparse path refused: $taskCurrent" }
    $taskCurrent=Split-Path -Parent $taskCurrent
  }
}
Assert-NoReparse $SourceRoot
Assert-NoReparse (Join-Path $taskRoot '.local')
$taskExpected=@{
  '029'='351a00c43297bf3feaad8cab7e28ea2974e7238589d050db09b8eb8018c3733c'
  '030'='011137a3d88709cf5f2ab128648ebe5c325783824160939904b1860f74ab5433'
}
$taskInventory=@()
foreach ($taskVersion in @('029','030')) {
  $taskSource=Join-Path $SourceRoot ("v$taskVersion/release/windows-test")
  $taskDest=Join-Path $taskRoot (".local/real-v$taskVersion-dev-export")
  Assert-NoReparse $taskSource
  Assert-NoReparse $taskDest
  $taskExe=Join-Path $taskSource ("FRAIHA-Xadrez-V$taskVersion-Teste.exe")
  $taskPck=Join-Path $taskSource ("FRAIHA-Xadrez-V$taskVersion-Teste.pck")
  foreach ($taskFile in @($taskExe,$taskPck,(Join-Path $taskSource 'online.cfg'),(Join-Path $taskSource 'LEIA-ME.txt'))) { Assert-NoReparse $taskFile; if (!(Test-Path -LiteralPath $taskFile -PathType Leaf)) { throw "Missing complete export file: $taskFile" } }
  if ((Get-FileHash -LiteralPath $taskExe).Hash.ToLowerInvariant() -ne '3bba9f68131498157e02ec44c296f996dd0a4d64c8fdb582d2794bd59feb4465') { throw 'Unreviewed EXE refused' }
  if ((Get-FileHash -LiteralPath $taskPck).Hash.ToLowerInvariant() -ne $taskExpected[$taskVersion]) { throw 'Unreviewed PCK refused' }
  New-Item -ItemType Directory -Force -Path $taskDest | Out-Null
  foreach ($taskPair in @(@($taskExe,'FRAIHA.exe'),@($taskPck,'FRAIHA.pck'),@((Join-Path $taskSource 'LEIA-ME.txt'),'LEIA-ME.txt'))) {
    $taskTarget=Join-Path $taskDest $taskPair[1]
    Assert-NoReparse $taskTarget
    if (Test-Path -LiteralPath $taskTarget) { if ((Get-FileHash -LiteralPath $taskTarget).Hash -ne (Get-FileHash -LiteralPath $taskPair[0]).Hash) { throw 'Existing DEV payload conflicts; preserve and investigate' } }
    else { Copy-Item -LiteralPath $taskPair[0] -Destination $taskTarget }
  }
  $taskCfg=Join-Path $taskDest 'online.cfg'
  Assert-NoReparse $taskCfg
  if (Test-Path -LiteralPath $taskCfg) { if ((Get-FileHash -LiteralPath $taskCfg).Hash.ToLowerInvariant() -ne 'ffaee9060a72096d914fc15346a3021d316c2ace6e9f36b780c956c7d325606e') { throw 'Existing DEV config conflicts' } }
  else { [IO.File]::WriteAllText($taskCfg,"[online]`nserver_url=`"`"`n",[Text.UTF8Encoding]::new($false)) }
  foreach ($taskFile in @($taskExe,$taskPck,(Join-Path $taskSource 'online.cfg'),(Join-Path $taskSource 'LEIA-ME.txt'))) {
    $taskItem=Get-Item -LiteralPath $taskFile
    $taskInventory += [pscustomobject]@{ historical_version=$taskVersion; source=$taskFile; size=$taskItem.Length; sha256=(Get-FileHash -LiteralPath $taskFile).Hash.ToLowerInvariant(); role='original approved export' }
  }
  foreach ($taskName in @('FRAIHA.exe','FRAIHA.pck','online.cfg','LEIA-ME.txt')) {
    $taskFile=Join-Path $taskDest $taskName
    $taskInventory += [pscustomobject]@{ historical_version=$taskVersion; source=$taskFile; size=(Get-Item -LiteralPath $taskFile).Length; sha256=(Get-FileHash -LiteralPath $taskFile).Hash.ToLowerInvariant(); role='DEV copy; EXE/PCK renamed, sidecar endpoint intentionally empty' }
  }
}
$taskReport=Join-Path $taskRoot ('.local/real-export-inventory-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')
$taskInventory | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskReport -Encoding UTF8
Write-Output "Preserved complete approved exports, DEV-only empty sidecar; evidence: $taskReport"
