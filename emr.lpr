program emr;

{$mode objfpc}{$H+}

uses
  Windows,
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  winhooks,
  Forms,
  frmMain,
  emrinject,
  dllinject,
  SysUtils, unSuperFastHash;

{$R *.res}

procedure CommandLineVersion;
var
  TargetFile, TargetParams: string;
  Settings: THookSettings;

  function ParseParameters: Boolean;
  var
    s: string;
    i: Integer;
  begin
    TargetFile:='';
    TargetParams:='';

    Settings.CreateLog:=True;
    Settings.DenyFileWriting:=False;
    Settings.DenySpawnProcesses:=False;
    Settings.RecordAudio:=False;
    Settings.Version:=WinHookVersion;
    Settings.SpeedFactor:=0;
    Settings.Windowed:=False;
    Settings.ShowCursor:=False;
    Settings.DisableSockets:=False;
    Settings.LogGetProcAddress:=False;
    Settings.Inject:=False;
    Settings.TraceAll:=False;
    result:=False;

    for i:=1 to Paramcount do
    begin
      s:=ParamStr(i);

      if s[1] in ['-', '/'] then
      begin
        delete(s, 1, 1);
        if s = 'nowrite' then
          Settings.DenyFileWriting:=True
        else if s = 'nocp' then
          Settings.DenySpawnProcesses:=True
        else if s = 'nolog' then
          Settings.CreateLog:=False
        else if s = 'record' then
          Settings.RecordAudio:=True
        else if s = 'slow' then
          Settings.SpeedFactor:=1
        else if s = 'fast' then
          Settings.SpeedFactor:=2
        else if s = 'windowed' then
          Settings.Windowed:=True
        else if s = 'shader' then
          Settings.GetShaders:=True
        else if s = 'wgl' then
          Settings.LogWglProcs:=True
        else if s = 'cursor' then
          Settings.ShowCursor:=True
        else if s = 'nosocket' then
          Settings.DisableSockets:=True
        else if s = 'proc' then
          Settings.LogGetProcAddress:=True
        else if s = 'inject' then
          Settings.Inject:=True
        else if s = 'trace' then
          Settings.TraceAll:=True
        else begin
          Writeln('Invalid option ',s);
          Exit;
        end;
      end else
      begin
        if TargetFile = '' then
          TargetFile := s
        else if TargetParams = '' then
          TargetParams := s
        else
          TargetParams := TargetParams + ' ' + s;
      end;
    end;
    result := TargetFile <> '';
  end;
begin
  if not ParseParameters then
  begin
    MessageBox(0, 'Invalid parameters. Please RTFM.', AppTitle, MB_ICONERROR);
    Halt(1);
  end;
  try
    injectLoader(TargetFile, TargetParams, ExtractFilePath(Paramstr(0))+'hookdll.dll', 'starthook', @Settings, SizeOf(Settings));
  except
    on e: exception do
      MessageBox(0, PChar(e.Message), AppTitle, MB_ICONERROR);
  end;
end;

begin
  case GetHookDLLStatus of
    dtNotFound:
      begin
        MessageBox(0, 'Hook DLL ('+HookDLLName+') not found. Please copy all files from the archive and/or redownload and RTFM.', AppTitle, MB_ICONERROR);
        Halt(2);
      end;
    dtInvalidVersion:
      begin
        MessageBox(0, 'An invalid version of the hook DLL ('+HookDLLName+') was found. Please redownload and/or RTFM.', AppTitle, MB_ICONERROR);
        Halt(3);
      end;
  end;

  if ParamCount <> 0 then
  begin
    CommandLineVersion;
    Halt(0);
  end;


  RequireDerivedFormResource:=True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

