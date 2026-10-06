param([switch]$Test,[switch]$RealTest)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$compiler = 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'Existing .NET Framework compiler required; no install performed.' }
$output = Join-Path $taskRoot '.local/bin'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$common = @('/nologo', '/warnaserror+', '/r:System.Web.Extensions.dll', '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll', (Join-Path $taskRoot 'src/Contracts.cs'), (Join-Path $taskRoot 'src/Updater.cs'), (Join-Path $taskRoot 'src/LauncherFlow.cs'))
& $compiler '/target:winexe' '/r:System.Windows.Forms.dll' '/r:System.Drawing.dll' ("/out:" + (Join-Path $output 'FRAIHA.Launcher.exe')) @common (Join-Path $taskRoot 'src/Launcher.cs')
if ($LASTEXITCODE) { throw 'Launcher compilation failed' }
& $compiler '/target:exe' ("/out:" + (Join-Path $output 'FRAIHA.Package.exe')) @common (Join-Path $taskRoot 'src/Tool.cs')
if ($LASTEXITCODE) { throw 'Package tool compilation failed' }
if ($Test) {
  & $compiler '/target:exe' '/r:System.Windows.Forms.dll' '/r:System.Drawing.dll' '/main:Fraiha.Distribution.Tests' ("/out:" + (Join-Path $output 'FRAIHA.Tests.exe')) @common (Join-Path $taskRoot 'src/Tool.cs') (Join-Path $taskRoot 'src/Launcher.cs') (Join-Path $taskRoot 'tests/Tests.cs')
  if ($LASTEXITCODE) { throw 'Test compilation failed' }
  & $compiler '/nologo' '/target:exe' ("/out:" + (Join-Path $output 'FRAIHA.exe')) (Join-Path $taskRoot 'tests/GameStub.cs')
  if ($LASTEXITCODE) { throw 'Stub compilation failed' }
  & (Join-Path $output 'FRAIHA.Tests.exe')
  if ($LASTEXITCODE) { throw 'Tests failed' }
}
if ($RealTest) {
  & $compiler '/target:exe' '/r:System.Windows.Forms.dll' '/r:System.Drawing.dll' '/main:Fraiha.Distribution.RealTests' ("/out:" + (Join-Path $output 'FRAIHA.RealTests.exe')) @common (Join-Path $taskRoot 'src/Tool.cs') (Join-Path $taskRoot 'src/Launcher.cs') (Join-Path $taskRoot 'tests/Tests.cs') (Join-Path $taskRoot 'tests/RealTests.cs')
  if ($LASTEXITCODE) { throw 'Real test compilation failed' }
  & (Join-Path $output 'FRAIHA.RealTests.exe')
  if ($LASTEXITCODE) { throw 'Real export tests failed' }
}
Write-Output "Local binaries: $output (generated, do not stage)"
