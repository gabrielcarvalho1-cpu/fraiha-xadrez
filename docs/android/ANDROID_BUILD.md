# Android — como gerar o APK debug (Android 01)

Fluxo **padrão do Godot, sem custom build Gradle**: a pasta `android/` não é gerada e não vai para o Git.
APK/AAB/keystore nunca entram no Git (`.gitignore`).

## Toolchain usada na Android 01 (verificada no ambiente real)

| Item | Valor |
|---|---|
| GODOT | 4.5.1.stable.official `f62fdbde1` (linux x86_64, headless) |
| ANDROID EXPORT TEMPLATE | `android_debug.apk` do `Godot_v4.5.1-stable_export_templates.tpz` (SHA-512 conferido com o `SHA512-SUMS.txt` oficial) |
| JDK | OpenJDK 21.0.12 (a doc do Godot 4.5 recomenda 17; versões maiores são suportadas) |
| SDK ROOT | estrutura mínima local, sem SDK do Google. Na nuvem, `dl.google.com` é bloqueado |
| PLATFORM TOOLS / ADB | `adb` do Ubuntu (`android-tools`), sem aparelho conectado |
| BUILD TOOLS | `apksigner` 0.9 + `zipalign` do Ubuntu, expostos como `build-tools/34.0.0` |
| ANDROID PLATFORM | não é necessária sem Gradle (o template já vem compilado: compileSdk 35) |
| GRADLE | não usado |

> O APK debug da nuvem serve como prova de viabilidade. **No seu PC use o SDK oficial do Google.**

## Preparar no PC (Windows) — doc oficial Godot 4.5

1. Godot **4.5.1** + export templates 4.5.1 (Editor → Gerenciar modelos de exportação).
2. OpenJDK **17**.
3. Android SDK (Android Studio ou cmdline-tools):
   `sdkmanager --sdk_root=<sdk> "platform-tools" "build-tools;35.0.0" "platforms;android-35" "cmdline-tools;latest"`
   (CMake/NDK só para custom build: não é preciso agora).
4. Editor → Configurações do Editor → Exportar → Android: `Java SDK Path` e `Android SDK Path`.
   A keystore **debug** é criada pelo editor. Nunca crie keystore de release nesta fase.

## Exportar

```
godot --headless --path <worktree> --import
godot --headless --path <worktree> --export-debug "Android Dev" <fora-do-repo>/FRAIHA-android-dev-debug.apk
```

Preset **Android Dev** (`export_presets.cfg`):
- `com.fraiha.xadrez.dev` — ID **temporário**, só DEV; não é o package da Play;
- arm64-v8a apenas, sem Gradle, permissão **INTERNET** apenas, imersivo;
- `custom_features="staging"` → servidor `[staging]` do `online.cfg`, nunca produção por padrão;
- mesmo filtro de exclusão do preset Web, mais `package.json`.

Instalar num aparelho (USB debugging ligado): `adb devices` → `adb install -r FRAIHA-android-dev-debug.apk`
→ `adb logcat -s godot` para ver os logs.

## Testes sem aparelho

```
godot --headless --path . --script res://tests/android_platform_test.gd   # exit != 0 se falhar
```
Cobre: escala dp, safe area nativa, Voltar (= Esc: fecha diálogo / volta à Home / pede confirmação em partida),
`quit_on_go_back=false`, orientação sensor, ETC2/ASTC e a sanidade do preset (ABI, permissões, sem senha, staging).
