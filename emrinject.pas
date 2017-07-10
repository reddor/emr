unit emrinject;

{$mode delphi}

interface

uses
  Classes, SysUtils, winhooks;

const
{$IFDEF CPUX86}
  HookDLLName = 'emrhook.dll';
{$ELSE}
  HookDLLName = 'emrhook64.dll';
{$ENDIF}
  AppTitle = 'Exemusic Recorder';

type

  { TEMRThread }

  TEMRThread = class(TThread)
  private
    FFinished: Boolean;
    FTargetExe,
    FTargetArgs,
    FError: ansistring;
    FSimpleInject: Boolean;
    FSettings: THookSettings;
  protected
    procedure Execute; override;
  public
    constructor Create(TargetExe, TargetArgs: ansistring; Settings: THookSettings; SimpleInject: Boolean = False);
    property Error: ansistring read FError;
    property Finished: Boolean read FFinished;
  end;

  { return values for GetHookDLLStatus }
  THookDLLStatus = (dtUsable, dtNotFound, dtInvalidVersion);

function GetHookDLLStatus: THookDLLStatus;


implementation

uses
  dllinject,
  Windows;

type
  THookDLLVersionProc = function: longword; cdecl;

function GetHookDLLStatus: THookDLLStatus;
var
  Handle: HINST;
  VersionProc: THookDLLVersionProc;
  s: ansistring;
begin
  result:=dtNotFound;
  s:=ExtractFilePath(Paramstr(0)) + HookDLLName;
  Handle:=LoadLibrary(PChar(s));
  if Handle = 0 then
    Exit;
  result:=dtInvalidVersion;

  VersionProc:=GetProcAddress(Handle, 'GetVersion');
  if Assigned(VersionProc) then
  begin
    if VersionProc() = WinHookVersion then
      result:=dtUsable;
  end;
  FreeLibrary(Handle);
end;

{ TEMRThread }

procedure TEMRThread.Execute;
begin
  try
    if Trim(FTargetExe) = '' then
      raise Exception.Create('No target exe specified');

    injectLoader(FTargetExe, FTargetArgs, ExtractFilePath(Paramstr(0))+HookDLLName, 'StartHook', @FSettings, SizeOf(FSettings), FSimpleInject);
  except
    on e: Exception do
      FError:=e.Message;
  end;
  FFinished:=True;
end;

constructor TEMRThread.Create(TargetExe, TargetArgs: ansistring;
  Settings: THookSettings; SimpleInject: Boolean);
begin
  FFinished:=False;
  FTargetExe:=TargetExe;
  FTargetArgs:=TargetArgs;
  FSettings:=Settings;
  FreeOnTerminate:=False;
  FSimpleInject:=SimpleInject;
  inherited Create(False);
end;

end.

