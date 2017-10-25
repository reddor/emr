unit frmMain;

interface

uses
  Windows, Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, winhooks, emrinject;

type

  { TForm1 }

  TForm1 = class(TForm)
    BrowseExe: TButton;
    BrowseOutDir: TButton;
    CheckBox1: TCheckBox;
    UseSimpleInjector: TCheckBox;
    HookInProcesses: TCheckBox;
    GroupBox4: TGroupBox;
    StartButton: TButton;
    ExitButton: TButton;
    InjectShaders: TCheckBox;
    LogWGLProcs: TCheckBox;
    VersionStr: TLabel;
    LogCreateFile: TCheckBox;
    LogCreateProc: TCheckBox;
    DumpAudio: TCheckBox;
    PreventLogs: TCheckBox;
    DumpACMSamples: TCheckBox;
    PreventFullscreen: TCheckBox;
    DumpShaders: TCheckBox;
    LogGetProcAddr: TCheckBox;
    LogAPICalls: TCheckBox;
    PreventCreateFile: TCheckBox;
    PreventSocket: TCheckBox;
    PreventCreateProc: TCheckBox;
    ProgressBar1: TProgressBar;
    TargetExe: TEdit;
    TargetArgs: TEdit;
    OutputDir: TEdit;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    GroupBox3: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    OpenDialog1: TOpenDialog;
    SlowSpeed: TRadioButton;
    NormalSpeed: TRadioButton;
    DoubleSpeed: TRadioButton;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    Timer1: TTimer;
    procedure BrowseExeClick(Sender: TObject);
    procedure BrowseOutDirClick(Sender: TObject);
    procedure GroupBox2Click(Sender: TObject);
    procedure Label1Click(Sender: TObject);
    procedure StartButtonClick(Sender: TObject);
    procedure ExitButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure TargetExeChange(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { private declarations }
    FSettings: THookSettings;
    FThread: TEMRThread;
    FSecretCounter: Integer;
  public
    { public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.BrowseExeClick(Sender: TObject);
var
  b: Boolean;
begin
  Opendialog1.FileName:=TargetExe.Text;
  b:=ExtractFilePath(TargetExe.Text) = OutputDir.Text;
  if Opendialog1.Execute then
  begin
    TargetExe.Text:=Opendialog1.FileName;
    if b then
      OutputDir.Text:=ExtractFilePath(Opendialog1.FileName);
  end;
end;

procedure TForm1.BrowseOutDirClick(Sender: TObject);
begin
  SelectDirectoryDialog1.Filename:=OutputDir.Text;
  if SelectDirectoryDialog1.Execute then
  begin
    OutputDir.Text:=SelectDirectoryDialog1.FileName;
  end;
end;

procedure TForm1.GroupBox2Click(Sender: TObject);
begin

end;

procedure TForm1.Label1Click(Sender: TObject);
begin
  inc(FSecretCounter);
  if FSecretCounter = 5 then
  begin
    Form1.ClientHeight:=GroupBox4.Top + GroupBox4.Height + 8;
  end;
end;

procedure TForm1.StartButtonClick(Sender: TObject);
begin
  if Assigned(FThread) then
    Exit;

  if TargetExe.Text = '' then
    Exit;

  // be annoying about this
  if LogAPICalls.Checked then
    if Application.MessageBox('You selected to log all DLL calls. Please be aware that this is *VERY* slow and will generate a huge logfile (easily 100+ MB), as all DLL calls will be logged (recursively), with the exception of certain kernel functions. Are you sure you want to start?', 'Warning', MB_ICONWARNING + MB_YESNO) <> IDYES then
      Exit;

  // confirm user's stupidity
  if PreventLogs.Checked and (LogCreateProc.Checked or LogGetProcAddr.Checked or
     LogCreateFile.Checked or LogWGLProcs.Checked or LogAPICalls.Checked) then
       if Application.MessageBox('You selected some logging but disabled writing to a log file. Do you still think this is a good idea?', AppTitle, MB_ICONQUESTION + MB_YESNO) <> IDYES then
         Exit;

  FSettings.Version:=WinHookVersion;
  FSettings.CreateLog:=not PreventLogs.Checked;
  FSettings.DenyFileWriting:=PreventCreateFile.Checked;
  FSettings.DenySpawnProcesses:=PreventCreateProc.Checked;
  FSettings.DisableSockets:=PreventSocket.Checked;
  FSettings.GetShaders:=DumpShaders.Checked;
  FSettings.LogGetProcAddress:=LogGetProcAddr.Checked;
  FSettings.LogWglProcs:=LogWGLProcs.Checked;
  FSettings.RecordAudio:=DumpAudio.Checked;
  FSettings.ShowCursor:=PreventFullscreen.Checked;
  FSettings.Windowed:=PreventFullscreen.Checked;
  FSettings.TraceAll:=LogAPICalls.Checked;
  FSettings.DumpACM:=DumpACMSamples.Checked;
  FSettings.LogCreateFile:=LogCreateFile.Checked;
  FSettings.LogCreateProcess:=LogCreateProc.Checked;
  FSettings.Inject:=InjectShaders.Checked;
  FSettings.OutputPath:=OutputDir.Text;
  FSettings.HookDLLLocation:=ExtractFilePath(Paramstr(0)) + HookDLLName;
  FSettings.HookInNewProcesses:=HookInProcesses.Checked;
  FSettings.SlowWaveWrite:=Checkbox1.Checked;
  if SlowSpeed.Checked then
    Fsettings.SpeedFactor:=1
  else if DoubleSpeed.Checked then
    Fsettings.SpeedFactor:=2
  else
    FSettings.SpeedFactor:=0;

  // if there's literally nothing to do, complain
  with FSettings do
  if (not (CreateLog or DenyFileWriting or DenySpawnProcesses or DisableSockets or
     GetShaders or LogGetProcAddress or LogWglProcs or RecordAudio or ShowCursor or
     Windowed or TraceAll or DumpACM or LogCreateFile or LogCreateProcess or Inject))
     and (SpeedFactor = 0) then
  begin
    Application.MessageBox('You know, with that configuration you just might start the binary yourself.', AppTitle, MB_ICONSTOP);
    Exit;
  end;

  GroupBox1.Enabled:=False;
  GroupBox2.Enabled:=False;
  GroupBox3.Enabled:=False;
  StartButton.Enabled:=False;
  ExitButton.Enabled:=False;

  { as injecting might take a few seconds, we do that in a separate thread
    to keep the gui responsive and all }
  FThread:=TEMRThread.Create(TargetExe.Text, TargetArgs.Text, FSettings, UseSimpleInjector.Checked);
  Timer1.Enabled:=True;
  ProgressBar1.Style:=pbstMarquee;
end;

procedure TForm1.ExitButtonClick(Sender: TObject);
begin
  Close;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Form1.Caption:=AppTitle;
  Application.Title:=AppTitle;
  VersionStr.Caption:='v'+IntToHex(WinHookVersion, 8);
  FSecretCounter:=0;
  ClientHeight:=StartButton.Top + StartButton.Height + 8;
  {$IFNDEF CPUX86}
  UseSimpleInjector.Enabled:=False;
  // LogAPICalls.Enabled:=False;
  {$ENDIF}
end;

procedure TForm1.TargetExeChange(Sender: TObject);
begin
  if not Assigned(FThread) then
    StartButton.Enabled:=Trim(TargetExe.Text) <> '';
end;

procedure TForm1.Timer1Timer(Sender: TObject);
var
  AThread: TEMRThread;
begin
  if not Assigned(FThread) then
    Exit;

  if FThread.Finished then
  begin
    Timer1.Enabled:=False;
    AThread:=FThread;
    FThread:=nil;
    ProgressBar1.Style:=pbstNormal;
    if AThread.Error <> '' then
      Application.MessageBox(PChar(AThread.Error), 'Error', MB_IconError);

    Form1.Close;
  end;
end;

end.

