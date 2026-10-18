; JT-Streaming-installer. Afgeleid van upstream windows/windows_setup.iss (Fladder, GPL-3.0);
; het upstream-bestand blijft ongewijzigd. Bouwen: pwsh tool/jt/build-windows.ps1.
; Verschillen met upstream: naam/exe/pictogram JT-Streaming, eigen AppId (staat naast Fladder),
; Nederlands + Engels, wizardafbeeldingen uit build/jt-installer/ (door het bouwscript gemaakt),
; app-data alleen wissen na een expliciete "Ja" (stil deïnstalleren laat data staan).

#define SourcePath "..\.."

#ifndef JT_VERSION
  #define JT_VERSION "0.0.0-jt.0"
#endif
#ifndef JT_OUTPUT_DIR
  #define JT_OUTPUT_DIR SourcePath + "\dist"
#endif
#ifndef JT_OUTPUT_NAME
  #define JT_OUTPUT_NAME "JT-Streaming-Windows-" + JT_VERSION + "-Setup"
#endif

#define JtName "JT-Streaming"
#define JtExe "JT-Streaming.exe"
; Map van path_provider (Runner.rc: CompanyName\ProductName), zie CUSTOMIZING.md.
#define JtDataDir "JT-Streaming (fam. Thoelen)"

[Setup]
AppId={{8185C3AD-F774-4D54-AD50-F8ABAB744181}
AppName={#JtName}
AppVersion={#JT_VERSION}
AppVerName={#JtName} {#JT_VERSION}
AppPublisher=fam. Thoelen (gebaseerd op Fladder van DonutWare)
AppPublisherURL=https://github.com/Xantar-86/JT-Streaming
AppSupportURL=https://github.com/Xantar-86/JT-Streaming
AppUpdatesURL=https://github.com/Xantar-86/JT-Streaming
DefaultDirName={localappdata}\Programs\{#JtName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#JT_OUTPUT_DIR}
OutputBaseFilename={#JT_OUTPUT_NAME}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=auto

SetupLogging=yes
UninstallLogging=yes
UninstallDisplayName={#JtName}
UninstallDisplayIcon={app}\{#JtExe}
SetupIconFile="{#SourcePath}\windows\runner\resources\app_icon.ico"
LicenseFile="{#SourcePath}\LICENSE"
WizardImageFile={#SourcePath}\build\jt-installer\jt-installer-100.bmp,{#SourcePath}\build\jt-installer\jt-installer-125.bmp,{#SourcePath}\build\jt-installer\jt-installer-150.bmp

[Languages]
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
dutch.DeleteAppData=Wil je ook de gegevens van JT-Streaming (instellingen, aanmelding, downloads) verwijderen? Dit kan niet ongedaan gemaakt worden.
english.DeleteAppData=Would you like to delete the application's data (settings, login, downloads)? This action cannot be undone.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourcePath}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourcePath}\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#JtName}"; Filename: "{app}\{#JtExe}"
Name: "{autodesktop}\{#JtName}"; Filename: "{app}\{#JtExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#JtExe}"; Description: "{cm:LaunchProgram,{#JtName}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Dir: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Standaard (ook bij /SUPPRESSMSGBOXES) "Nee": data blijft staan. }
    if SuppressibleMsgBox(CustomMessage('DeleteAppData'), mbConfirmation, MB_YESNO, IDNO) = IDYES then
    begin
      Dir := ExpandConstant('{userappdata}\{#JtDataDir}');
      if DirExists(Dir) and not DelTree(Dir, True, True, True) then
        Log(Dir + ' kon niet verwijderd worden, overgeslagen.');
      Dir := ExpandConstant('{localappdata}\{#JtDataDir}');
      if DirExists(Dir) and not DelTree(Dir, True, True, True) then
        Log(Dir + ' kon niet verwijderd worden, overgeslagen.');
    end;
  end;
end;
