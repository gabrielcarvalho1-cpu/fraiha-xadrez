# FRAIHA - monta o APK com Gradle (voz nativa). Temporario. Log em C:\Android\fxbuild.log
$ErrorActionPreference = 'Continue'
$log = 'C:\Android\fxbuild.log'
"inicio $(Get-Date -Format s)" | Out-File $log -Encoding utf8
$src = Join-Path $PSScriptRoot 'build\abuild.zip'
$dst = 'C:\Android\fxbuild'
if ($args -contains 'extrair') {
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($src, $dst)
  "extraido" | Out-File $log -Append -Encoding utf8
}
$key = 'C:\Android\fxkey\fraiha-teste.keystore'
New-Item -ItemType Directory -Force -Path 'C:\Android\fxkey', 'C:\Android\fxout', 'C:\Android\gradle-home' | Out-Null
$chave = Join-Path (Split-Path $PSScriptRoot -Parent) 'FRAIHA_R182_APP_ANDROID\CHAVE-DE-TESTE'
Copy-Item (Join-Path $chave 'fraiha-teste.keystore') $key -Force
$pw = (Get-Content (Join-Path $chave 'senha-da-chave-de-teste.txt') -Raw).Trim()
$env:ANDROID_HOME = 'C:\Android\Sdk'; $env:ANDROID_SDK_ROOT = 'C:\Android\Sdk'
$env:GRADLE_USER_HOME = 'C:\Android\gradle-home'
$env:TEMP = 'C:\Android\tmp'; $env:TMP = 'C:\Android\tmp'
"sdk.dir=C\:\\Android\\Sdk" | Out-File "$dst\build\local.properties" -Encoding ascii
Set-Location "$dst\build"
$props = @{ addons_directory = "$dst\addons_vazio"; export_package_name = 'com.fraihaxadrez.app'; export_version_code = '5';
  export_version_name = '1.0.4-teste'; export_version_min_sdk = '24'; export_version_target_sdk = '35';
  export_enabled_abis = 'armeabi-v7a|arm64-v8a'; plugins_local_binaries = ''; plugins_remote_binaries = 'io.agora.rtc:voice-sdk:4.5.2';
  plugins_maven_repos = ''; perform_zipalign = 'true'; perform_signing = 'true'; compress_native_libraries = 'true';
  release_keystore_file = $key; release_keystore_alias = 'fraihateste'; release_keystore_password = $pw }
foreach ($k in $props.Keys) { Set-Item -Path ("env:ORG_GRADLE_PROJECT_" + $k) -Value $props[$k] }
$a = @('validateJavaVersion', 'assembleStandardRelease', '--no-daemon', '--console=plain')
New-Item -ItemType Directory -Force -Path "$dst\addons_vazio" | Out-Null
& "$dst\build\gradlew.bat" @a 2>&1 | ForEach-Object { "$_" } | Out-File $log -Append -Encoding utf8
"gradle exit=$LASTEXITCODE" | Out-File $log -Append -Encoding utf8
Get-ChildItem "$dst\build\build\outputs\apk" -Recurse -Filter *.apk -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName 'C:\Android\fxout\' -Force; "apk: $($_.FullName) $($_.Length)" } | Out-File $log -Append -Encoding utf8
"fim $(Get-Date -Format s)" | Out-File $log -Append -Encoding utf8
