# Montar o APK do app Android (R183, com voz nativa)

A voz usa o SDK Android da Agora (plugin `android_plugin/fraiha_voice/FraihaVoicePlugin.kt`), então o APK sai
de um **build Gradle**. O Godot prepara a pasta e o Gradle monta no PC (Android SDK + JDK 17+ + internet).

1. Nuvem/Linux (Godot 4.5.1 + templates): `godot --headless --install-android-build-template --export-release "Android" x.apk`
   — monta `android/build` (assets, manifesto, plugin registrado pelo addon `addons/fraiha_voice_android`) e para no
   passo do Gradle (sem SDK). Copie `android_plugin/fraiha_voice/FraihaVoicePlugin.kt` para
   `android/build/src/com/fraiha/voice/`.
2. Leve `android/build` para o PC (ex.: `C:\Android\fxbuild\build`, caminho SEM acento).
3. `patch-gradle.ps1` (tira as extensões opcionais da Agora: IA, efeitos, mídia → APK menor).
4. `montar-apk.ps1` (Gradle `assembleStandardRelease` com as mesmas propriedades que o Godot passa, via
   `ORG_GRADLE_PROJECT_*`; a senha da chave de teste é lida do arquivo da pasta CHAVE-DE-TESTE, nunca no código).

Versão: `version/code` do preset Android = `APP_CODE` em `ui_v022/app_update.gd` = `export_version_code` do script.
