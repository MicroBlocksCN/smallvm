[Setup]
AppId={{20638B6B-EDD6-46A7-975B-A5B867243D9A}
AppName=microBlocks
AppVerName=microBlocks-0.1.14
AppPublisher=microBlocks
AppPublisherURL=http://microblocks.fun
AppSupportURL=http://microblocks.fun
AppUpdatesURL=http://microblocks.fun
DefaultDirName={pf}\microBlocks
DefaultGroupName=microBlocks
AllowNoIcons=no
OutputDir=.
OutputBaseFilename=microBlocks setup
SetupIconFile=microBlocks.ico
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 0,6.1

[Files]
Source: "*.*"; Excludes: "install-config.iss,ublocks-linux32bit,ublocks-linux64bit,ublocks-raspberryPi,ublocks-mac.app"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\microBlocks"; Filename: "{app}\ublocks-win.exe"; IconFilename: "{app}\microBlocks.ico"; WorkingDir: "{app}"
Name: "{group}\{cm:ProgramOnTheWeb,microBlocks}"; Filename: "http://microblocks.fun"
Name: "{group}\{cm:UninstallProgram,microBlocks}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\microBlocks"; Filename: "{app}\ublocks-win.exe"; IconFilename: "{app}\microBlocks.ico"; Tasks: desktopicon; WorkingDir: "{app}"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\microBlocks"; Filename: "{app}\ublocks-win.exe"; Tasks: quicklaunchicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\ublocks-win.exe"; Description: "{cm:LaunchProgram,microBlocks}"; Flags: nowait postinstall skipifsilent
