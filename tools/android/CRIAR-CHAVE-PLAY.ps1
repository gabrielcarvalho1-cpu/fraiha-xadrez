# FRAIHA R194 · cria a CHAVE DE ENVIO da Google Play (upload key) — rode UMA vez, no seu PC, você mesmo.
# A Google assina o app final com a chave dela (Assinatura de apps do Google Play); esta é só a chave que prova
# que o pacote enviado veio de você. Se um dia ela se perder, dá para pedir a troca no Play Console.
# Fica em C:\Android\fxkey-play (fora do Git e fora da pasta do jogo). FAÇA UMA CÓPIA em um pendrive ou na nuvem.
# A senha você digita aqui; ela fica só no arquivo senha.txt dessa pasta (o montar-aab-play.ps1 lê de lá).
$ErrorActionPreference = 'Stop'
$kd = 'C:\Android\fxkey-play'
$key = Join-Path $kd 'upload.keystore'
if (Test-Path $key) { Write-Host "A chave já existe em $key — nada foi feito." -ForegroundColor Yellow; exit 0 }
$kt = $null
foreach ($c in @("$env:JAVA_HOME\bin\keytool.exe", 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe')) { if ($c -and (Test-Path $c)) { $kt = $c; break } }
if (-not $kt) { $cmd = Get-Command keytool -ErrorAction SilentlyContinue; if ($cmd) { $kt = $cmd.Source } }
if (-not $kt) { Write-Host "Não achei o keytool (vem com o Java/JDK que o Gradle já usa). Avise o Claude." -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Force -Path $kd | Out-Null
$s1 = Read-Host 'Crie uma senha para a chave (mínimo 8 caracteres)' -AsSecureString
$s2 = Read-Host 'Digite a senha de novo' -AsSecureString
$p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
$p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
if ($p1 -ne $p2) { Write-Host 'As senhas não batem. Rode de novo.' -ForegroundColor Red; exit 1 }
if ($p1.Length -lt 8) { Write-Host 'Senha curta demais (mínimo 8).' -ForegroundColor Red; exit 1 }
& $kt -genkeypair -v -keystore $key -alias fraihaupload -keyalg RSA -keysize 2048 -validity 10000 `
  -storepass $p1 -keypass $p1 -dname 'CN=FRAIHA Xadrez, O=FRAIHA, C=BR'
if ($LASTEXITCODE -ne 0) { Write-Host 'O keytool falhou.' -ForegroundColor Red; exit 1 }
Set-Content -Path (Join-Path $kd 'senha.txt') -Value $p1 -Encoding ascii -NoNewline
Set-Content -Path (Join-Path $kd 'alias.txt') -Value 'fraihaupload' -Encoding ascii -NoNewline
Write-Host "PRONTO: chave criada em $key. Faça uma CÓPIA da pasta C:\Android\fxkey-play em lugar seguro." -ForegroundColor Green
