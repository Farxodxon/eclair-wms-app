; Eclair WMS - Windows Setup (Inno Setup 6)
[Setup]
AppName=Eclair WMS
AppVersion=1.0.3
AppPublisher=Eclair
DefaultDirName={autopf}\Eclair WMS
DefaultGroupName=Eclair WMS
DisableProgramGroupPage=yes
OutputDir=C:\Users\Farxod3376\Documents\Default Project\eclair-wms-app\dist
OutputBaseFilename=WMS_Setup_1.0.3
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile=
UninstallDisplayName=Eclair WMS
UninstallDisplayIcon={app}\wms_app.exe

[Files]
Source: "C:\Users\Farxod3376\Documents\Default Project\eclair-wms-app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "C:\Users\FARXOD~1\AppData\Local\Temp\opencode\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Eclair WMS"; Filename: "{app}\wms_app.exe"
Name: "{autodesktop}\Eclair WMS"; Filename: "{app}\wms_app.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Ish stoliga qisqartma yaratish"; Flags: unchecked

[Run]
Filename: "{app}\wms_app.exe"; Description: "Eclair WMS ni hozir ishga tushirish"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: files; Name: "{app}\server.txt"

[Code]
var
  ServerPage: TInputQueryWizardPage;

const
  WebView2Guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function IsWebView2Installed(): Boolean;
var
  Ver: String;
begin
  Result := False;
  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Guid, 'pv', Ver) then
    Result := True
  else if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Guid, 'pv', Ver) then
    Result := True;
end;

procedure InitializeWizard;
begin
  ServerPage := CreateInputQueryPage(wpSelectDir,
    'Server manzili',
    'Ilova qaysi serverga ulanadi?',
    'Server kompyuterining IP manzili va portini kiriting (masalan: 192.168.1.50:8080)');
  ServerPage.Add('Server manzili:', False);
  ServerPage.Values[0] := 'https://eclair-wms-backend.onrender.com';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Url: String;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    Url := Trim(ServerPage.Values[0]);
    if (Pos('http://', Url) <> 1) and (Pos('https://', Url) <> 1) then
      Url := 'http://' + Url;
    SaveStringToFile(ExpandConstant('{app}\server.txt'), Url, False);

    if not IsWebView2Installed() then
    begin
      if Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'),
              '/silent /install', '', SW_SHOW, ewWaitUntilTerminated, ResultCode)
              and (ResultCode = 0) then
        MsgBox('WebView2 Runtime muvaffaqiyatli ornatildi.', mbInformation, MB_OK)
      else
        MsgBox('WebView2 Runtime ornatilmadi (internet mavjud emas bolishi mumkin). '
               + 'Kamera skaneri ishlashi uchun uni qolda ornating:' + #13#10
               + 'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
               mbInformation, MB_OK);
    end;
  end;
end;
