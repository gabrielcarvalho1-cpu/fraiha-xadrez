$ErrorActionPreference='Stop'
$runtime=Get-Command node -ErrorAction SilentlyContinue
$nodePath=if($runtime){$runtime.Source}else{Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'}
if(-not (Test-Path -LiteralPath $nodePath)){Write-Host 'Instale Node.js para iniciar o servidor local.'; Read-Host 'Enter para sair'; exit 1}
Write-Host 'Abra http://127.0.0.1:8129 no Chrome ou Edge. Nao abra index.html diretamente.'
& $nodePath (Join-Path $PSScriptRoot 'server.cjs')
