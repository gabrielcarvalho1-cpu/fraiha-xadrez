; PREPARED ONLY: no Inno compiler found, no installer built or run.
; Inno Setup 6. Pass /DGameVersion from distribution/version.json, approved publisher and official ICO.
#ifndef GameVersion
  #error GameVersion must come from the central version source
#endif
#ifndef Publisher
  #error Publisher legal identity requires human confirmation
#endif
#ifndef OfficialIcon
  #error OfficialIcon requires approved existing ICO; splash is not an installer icon
#endif
#if !FileExists(OfficialIcon)
  #error OfficialIcon file does not exist
#endif

[Setup]
AppId={{23D6D918-180D-42DD-8BE1-24D754AF901B}
AppName=FRAIHA DEV
AppVersion={#GameVersion}
AppPublisher={#Publisher}
DefaultDirName={localappdata}\Programs\FRAIHA-DEV
DefaultGroupName=FRAIHA DEV
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
MinVersion=10.0
SetupIconFile={#OfficialIcon}
UninstallDisplayIcon={app}\FRAIHA.Launcher.exe
OutputDir=..\.local\installer
OutputBaseFilename=FRAIHA-DEV-Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Files]
Source: "..\.local\bin\FRAIHA.Launcher.exe"; DestDir: "{app}"; Flags: ignoreversion

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{group}\FRAIHA DEV"; Filename: "{app}\FRAIHA.Launcher.exe"; Parameters: "--dev-mock"; IconFilename: "{app}\FRAIHA.Launcher.exe"
Name: "{userdesktop}\FRAIHA DEV"; Filename: "{app}\FRAIHA.Launcher.exe"; Parameters: "--dev-mock"; Tasks: desktopicon

; No post-install auto-run and no recursive uninstall-delete through updater data.
; Inno removes installed launcher/shortcuts; updated payloads require audited, reparse-safe cleanup.
