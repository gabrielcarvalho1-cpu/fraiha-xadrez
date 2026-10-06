param([ValidateRange(1,2100000000)][int]$Build = 1, [ValidateRange(1024,65535)][int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $taskRoot 'build.ps1')
$compiler = 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$localBin = Join-Path $taskRoot '.local/bin'
& $compiler '/nologo' '/target:exe' ("/out:" + (Join-Path $localBin 'FRAIHA.exe')) (Join-Path $taskRoot 'tests/GameStub.cs')
if ($LASTEXITCODE) { throw 'DEV stub compilation failed' }
$fixture = Join-Path $taskRoot ('.local/mock-feed/' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$output = Join-Path $fixture 'feed'
New-Item -ItemType Directory -Force -Path $source | Out-Null
Copy-Item -LiteralPath (Join-Path $localBin 'FRAIHA.exe') -Destination (Join-Path $source 'FRAIHA.exe')
[IO.File]::WriteAllText((Join-Path $source 'FRAIHA.pck'), 'DEV C# STUB; NOT A GODOT EXPORT')
$version = Get-Content -LiteralPath (Join-Path $taskRoot 'version.json') -Raw | ConvertFrom-Json
if ($version.release_channel -ne 'DEV' -or !$version.development_only -or $version.platform -ne 'windows_site') { throw 'Central source must be DEV windows_site' }
$version.build_number = $Build
$versionPath = Join-Path $fixture 'version.json'
[IO.File]::WriteAllText($versionPath, ($version | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$zipName = 'fraiha-' + $version.game_version + '-' + $Build + '.zip'
& (Join-Path $localBin 'FRAIHA.Package.exe') 'package' $versionPath $source $output ("http://127.0.0.1:$Port/$zipName") 'LOCAL DEV C# stub, not the FRAIHA Godot game. No authentication or online service integration.' '--dev-only'
if ($LASTEXITCODE) { throw 'DEV package failed' }
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Output "DEV mock only: http://127.0.0.1:$Port/manifest.json ; build $Build ; Ctrl+C to stop"
Write-Output "In another terminal: & '$localBin/FRAIHA.Launcher.exe' --dev-mock"
try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $stream.ReadTimeout = 5000
      $header = New-Object Text.StringBuilder
      while ($header.Length -lt 8192) {
        $nextByte = $stream.ReadByte()
        if ($nextByte -lt 0) { break }
        [void]$header.Append([char]$nextByte)
        if ($header.ToString().EndsWith("`r`n`r`n")) { break }
      }
      $line = $header.ToString().Split("`r`n")[0]
      $resource = $null
      if ($line -eq 'GET /manifest.json HTTP/1.1') { $resource = Join-Path $output 'manifest.json' }
      if ($line -eq "GET /$zipName HTTP/1.1") { $resource = Join-Path $output $zipName }
      $body = [byte[]]@()
      $status = '404 Not Found'
      if ($resource) { $body = [IO.File]::ReadAllBytes($resource); $status = '200 OK' }
      $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n")
      $stream.Write($response, 0, $response.Length)
      $stream.Write($body, 0, $body.Length)
    } catch [IO.IOException] { Write-Output 'DEV client disconnected or timed out.' }
    finally { $client.Dispose() }
  }
} finally { $listener.Stop() }
