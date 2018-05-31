[Setup]
AppId={{F9B1596E-4B24-422F-A26E-1250242BF93C}
AppName=microBlocks connector
AppVerName=microBlocks-connector-1.0
AppPublisher=microBlocks
AppPublisherURL=http://microblocks.fun
AppSupportURL=http://microblocks.fun
AppUpdatesURL=http://microblocks.fun
DefaultDirName={pf}\microBlocks
DisableProgramGroupPage=yes
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
OutputBaseFilename=microBlocks setup
OutputDir=.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Dirs]
Name: "{app}\icons"

[Files]
Source: "ublocks-win.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "daemon.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "serialport.node"; DestDir: "{app}"; Flags: ignoreversion
Source: "icons\*"; DestDir: "{app}\icons"; Flags: ignoreversion

[Icons]
Name: "{userstartup}\microBlocks"; Filename: "{app}\daemon.vbs"; WorkingDir: "{app}"

[Run]
Filename: "{app}\ublocks-win.exe"; Description: "{cm:LaunchProgram,microBlocks connector}"; Flags: nowait runascurrentuser runhidden
