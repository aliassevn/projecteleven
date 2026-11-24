; Installatieprogramma voor Cyberpad op Windows 10/11 (Inno Setup 6).
; Bouwen: eerst  dotnet publish windows/Cyberpad -c Release -o windows/build/app
;         dan    ISCC.exe /DAppVersion=0.1.0 windows/installer/Cyberpad.iss
; GitHub Actions doet dit automatisch (.github/workflows/windows.yml).

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{32CC0E60-F30A-43C6-9A44-325996ED5C87}
AppName=Cyberpad
AppVersion={#AppVersion}
AppVerName=Cyberpad {#AppVersion}
AppPublisher=Project Eleven
AppPublisherURL=https://github.com/aliassevn/projecteleven
AppSupportURL=https://github.com/aliassevn/projecteleven/issues
DefaultDirName={autopf}\Cyberpad
DefaultGroupName=Cyberpad
DisableProgramGroupPage=yes
OutputDir=..\build
OutputBaseFilename=CyberpadSetup-{#AppVersion}
SetupIconFile=..\Cyberpad\app.ico
UninstallDisplayIcon={app}\Cyberpad.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
; Beheerdersrechten alleen voor de installatie zelf (Program Files en de firewallregel); Cyberpad draait daarna gewoon.
PrivilegesRequired=admin
; Draait Cyberpad nog? Dan vraagt de installer om het eerst te sluiten.
AppMutex=ProjectEleven.Cyberpad
CloseApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[CustomMessages]
en.Autostart=Start Cyberpad when I sign in to Windows
nl.Autostart=Cyberpad starten als ik me aanmeld bij Windows
es.Autostart=Iniciar Cyberpad al iniciar sesión en Windows
en.Firewall=Allow tablets on my home network to connect (Windows Firewall, private networks only)
nl.Firewall=Tablets op mijn thuisnetwerk toelaten (Windows Firewall, alleen privénetwerken)
es.Firewall=Permitir que las tabletas de mi red doméstica se conecten (Firewall de Windows, solo redes privadas)
en.Launch=Start Cyberpad
nl.Launch=Cyberpad starten
es.Launch=Iniciar Cyberpad

[Tasks]
Name: "firewall"; Description: "{cm:Firewall}"
Name: "autostart"; Description: "{cm:Autostart}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Cyberpad"; Filename: "{app}\Cyberpad.exe"
Name: "{autodesktop}\Cyberpad"; Filename: "{app}\Cyberpad.exe"; Tasks: desktopicon
Name: "{userstartup}\Cyberpad"; Filename: "{app}\Cyberpad.exe"; Tasks: autostart

[Run]
; Poort 7420 openzetten voor Cyberpad, alleen op privé- en domeinnetwerken (niet op openbare wifi).
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Cyberpad"""; Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Cyberpad"" dir=in action=allow program=""{app}\Cyberpad.exe"" enable=yes profile=private,domain"; Flags: runhidden; Tasks: firewall
Filename: "{app}\Cyberpad.exe"; Description: "{cm:Launch}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Cyberpad"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"
Filename: "{cmd}"; Parameters: "/c taskkill /im Cyberpad.exe /f"; Flags: runhidden; RunOnceId: "StopCyberpad"

; Je layout, gekoppelde tablets en instellingen in %APPDATA%\Cyberpad blijven staan bij verwijderen.
