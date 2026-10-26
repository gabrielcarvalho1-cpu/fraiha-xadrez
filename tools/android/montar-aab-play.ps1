# FRAIHA R194 - monta o pacote da GOOGLE PLAY (.aab) com Gradle: voz nativa (Agora) + compras pelo Google Play (Billing 8),
# Android 16 (API 36, exigência da Play para apps novos desde 31/08/2026). Log em C:\Android\fxbuild-play.log
# Uso:  montar-aab-play.ps1 [extrair] [teste]
#   extrair : descompacta build\abuild_play.zip em C:\Android\fxbuild-play (pasta android/build exportada pelo Godot, preset "Android Play")
#   teste   : assina com a CHAVE DE TESTE (só para conferir se compila; NÃO serve para enviar à Play)
# Sem "teste": assina com a CHAVE DE ENVIO da Play (C:\Android\fxkey-play\upload.keystore + alias/senha em arquivos dessa
# pasta, criados pelo dono com CRIAR-CHAVE-PLAY.cmd). A senha nunca fica no código nem no Git.
$ErrorActionPreference = 'Continue'
$log = 'C:\Android\fxbuild-play.log'
"inicio $(Get-Date -Format s)" | Out-File $log -Encoding utf8
$src = Join-Path $PSScriptRoot 'build\abuild_play.zip'
$dst = 'C:\Android\fxbuild-play'
if ($args -contains 'extrair') {
  # (vem em partes .partNN: junta antes)
  $parts = @(Get-ChildItem -Path (Split-Path $src) -Filter 'abuild_play.zip.part*' | Sort-Object Name)
  if ($parts.Count -gt 0) {
    $out = [IO.File]::Create($src)
    try { foreach ($part in $parts) { $bytes = [IO.File]::ReadAllBytes($part.FullName); $out.Write($bytes, 0, $bytes.Length) } } finally { $out.Close() }
  }
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($src, $dst)
  # a biblioteca do Godot (godot-lib, 100 MB) não vem no zip: é a mesma da montagem do APK (mesma versão do Godot)
  New-Item -ItemType Directory -Force -Path "$dst\build\libs\release" | Out-Null
  Copy-Item 'C:\Android\fxbuild\build\libs\release\*' "$dst\build\libs\release\" -Force
  "extraido" | Out-File $log -Append -Encoding utf8
}
New-Item -ItemType Directory -Force -Path 'C:\Android\fxkey', 'C:\Android\fxout', 'C:\Android\gradle-home' | Out-Null
if ($args -contains 'teste') {
  $key = 'C:\Android\fxkey\fraiha-teste.keystore'
  $chave = Join-Path (Split-Path $PSScriptRoot -Parent) 'FRAIHA_R182_APP_ANDROID\CHAVE-DE-TESTE'
  Copy-Item (Join-Path $chave 'fraiha-teste.keystore') $key -Force
  $pw = (Get-Content (Join-Path $chave 'senha-da-chave-de-teste.txt') -Raw).Trim()
  $alias = 'fraihateste'
  $nome = 'FRAIHA-Play-TESTE-NAO-ENVIAR.aab'
} else {
  $kd = 'C:\Android\fxkey-play'
  $key = Join-Path $kd 'upload.keystore'
  if (-not (Test-Path $key)) { "ERRO: chave de envio da Play nao encontrada ($key). Rode CRIAR-CHAVE-PLAY.cmd primeiro." | Out-File $log -Append -Encoding utf8; exit 1 }
  $pw = (Get-Content (Join-Path $kd 'senha.txt') -Raw).Trim()
  $alias = (Get-Content (Join-Path $kd 'alias.txt') -Raw).Trim()
  $nome = 'FRAIHA-Xadrez-Play.aab'
}
$env:ANDROID_HOME = 'C:\Android\Sdk'; $env:ANDROID_SDK_ROOT = 'C:\Android\Sdk'
$env:GRADLE_USER_HOME = 'C:\Android\gradle-home'
$env:TEMP = 'C:\Android\tmp'; $env:TMP = 'C:\Android\tmp'
"sdk.dir=C\:\\Android\\Sdk" | Out-File "$dst\build\local.properties" -Encoding ascii
# Android 16 (API 36): compileSdk/targetSdk/buildTools do modelo do Godot 4.5.1 (35) sobem para 36
$cfg = "$dst\build\config.gradle"
$c = Get-Content $cfg -Raw
$c = $c -replace "compileSdk\s*:\s*35", "compileSdk         : 36" -replace "targetSdk\s*:\s*35", "targetSdk          : 36" -replace "buildTools\s*:\s*'35\.0\.0'", "buildTools         : '36.0.0'"
Set-Content -Path $cfg -Value $c -Encoding ascii
# plugin nativo FRAIHA (voz + foto + compras) na pasta de código do Gradle
$plug = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'android_plugin\fraiha_voice\FraihaVoicePlugin.kt'
if (Test-Path "$PSScriptRoot\FraihaVoicePlugin.kt") { $plug = "$PSScriptRoot\FraihaVoicePlugin.kt" }
New-Item -ItemType Directory -Force -Path "$dst\build\src\com\fraiha\voice" | Out-Null
Copy-Item $plug "$dst\build\src\com\fraiha\voice\FraihaVoicePlugin.kt" -Force
Set-Location "$dst\build"
$props = @{ addons_directory = "$dst\addons_vazio"; export_package_name = 'com.fraihaxadrez.app'; export_version_code = '6';
  export_version_name = '1.1.0'; export_version_min_sdk = '24'; export_version_target_sdk = '36';
  export_enabled_abis = 'armeabi-v7a|arm64-v8a'; plugins_local_binaries = ''; plugins_remote_binaries = 'io.agora.rtc:voice-sdk:4.5.2|com.android.billingclient:billing:8.0.0';
  plugins_maven_repos = ''; perform_zipalign = 'true'; perform_signing = 'true'; compress_native_libraries = 'true';
  release_keystore_file = $key; release_keystore_alias = $alias; release_keystore_password = $pw }
foreach ($k in $props.Keys) { Set-Item -Path ("env:ORG_GRADLE_PROJECT_" + $k) -Value $props[$k] }
$a = @('validateJavaVersion', 'bundleStandardRelease', '--no-daemon', '--console=plain')
New-Item -ItemType Directory -Force -Path "$dst\addons_vazio" | Out-Null
& "$dst\build\gradlew.bat" @a 2>&1 | ForEach-Object { "$_" } | Out-File $log -Append -Encoding utf8
"gradle exit=$LASTEXITCODE" | Out-File $log -Append -Encoding utf8
Get-ChildItem "$dst\build\build\outputs\bundle" -Recurse -Filter *.aab -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName (Join-Path 'C:\Android\fxout' $nome) -Force; "aab: $($_.FullName) $($_.Length) -> $nome" } | Out-File $log -Append -Encoding utf8
"fim $(Get-Date -Format s)" | Out-File $log -Append -Encoding utf8
