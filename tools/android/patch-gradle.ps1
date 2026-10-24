$f = 'C:\Android\fxbuild\build\build.gradle'
$t = Get-Content $f -Raw
if ($t -notmatch 'R183 agora excludes') {
  $add = @"
        exclude 'META-INF/NOTICE'
        // R183 agora excludes: so a voz basica (sem extensoes de IA/efeitos/midia) para o app ficar menor
        jniLibs { excludes += ['**/libagora-fdkaac.so', '**/libagora-ffmpeg.so', '**/libagora-soundtouch.so', '**/libagora_ai_echo_cancellation_extension.so', '**/libagora_ai_echo_cancellation_ll_extension.so', '**/libagora_ai_noise_suppression_extension.so', '**/libagora_ai_noise_suppression_ll_extension.so', '**/libagora_audio_beauty_extension.so', '**/libagora_lip_sync_extension.so', '**/libagora_spatial_audio_extension.so'] }
"@
  $t = $t.Replace("        exclude 'META-INF/NOTICE'", $add.TrimEnd())
  Set-Content -Path $f -Value $t -Encoding ascii
  'patched'
} else { 'ja estava' }
