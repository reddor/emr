unit winhooks;

{ Exemusic Recorder hooks - this could be cleaned up at some point... meh }

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows, syncobjs, variants, mmsystem, gl, glext, winsock,
  Direct3D9, unSuperFastHash, msacm, jwaNative;

type
  PHookSettings = ^THookSettings;
  THookSettings = packed record
    Version: Longword;
    CreateLog: Boolean;
    DenyFileWriting: Boolean;
    DenySpawnProcesses: Boolean;
    RecordAudio: Boolean;
    DumpACM: Boolean;
    SpeedFactor: Integer;
    Windowed: Boolean;
    ShowCursor: Boolean;
    LogWglProcs: Boolean;
    LogGetProcAddress: Boolean;
    LogCreateFile: Boolean;
    LogCreateProcess: Boolean;
    DisableSockets: Boolean;
    GetShaders: Boolean;
    Inject: Boolean;
    TraceAll: Boolean;
    SlowWaveWrite: Boolean;
    OutputPath: array[0..MaxPathLen-1] of Char;
    HookInNewProcesses: Boolean;
    HookDLLLocation: array[0..MaxPathLen-1] of Char;
  end;

const
  WinHookVersion = $01030000 + SizeOf(THookSettings);


procedure StartHook(Settings: PHookSettings); stdcall;
procedure LOG(s: ansistring);

implementation

uses
  apitrace,
  wavewrite,
  contnrs,
  exereader,
  ddraw,
  directsound,
  dllinject,
  DDetours;

var
  f: Textfile;
  Config: THookSettings;
  CanLog: Boolean = false;
  cs: TCriticalSection = nil;
  cs2:TCriticalSection = nil;
  Items: TFPHashList;
  LibNames: TFPStringHashTable;
  BasePath,
  BaseName: ansistring;

procedure LOG(s: ansistring);
begin
  if not Assigned(Cs) then
    Exit;

  cs.Enter;
  try
    if CanLog then
    begin
      Writeln(f, s);
      Flush(f);
    end;
  finally
    cs.Leave;
  end;
end;

procedure RegisterLibrary(h: THandle; name: string);
begin
  if not Assigned(cs) then
    Exit;
  cs.Enter;
  try
    LibNames.Add(IntToHex(h, 8), name);
  except

  end;
  cs.Leave;
end;

function GetLibraryName(h: THandle): string;
begin
  if not Assigned(cs) then
    Exit;
  cs.Enter;
  try
    result:=IntToHex(h, 8);
    if Assigned(LibNames.Find(result)) then
      result:='"'+LibNames[result]+'"'
  except
    result:='???';
  end;
  cs.Leave;
end;

procedure RegisterHandleObj(h: THandle; const subSystem: string; data: TObject);
begin
  if Assigned(cs) then
  begin
    cs.Enter;
    try
      Items.Add(subSystem+IntToHex(h, 8), data);
    except
      LOG('Error registering handle for '+subSystem);
    end;
    cs.Leave;
  end;
end;

function GetHandleObj(h: THandle; const subSystem: string): Pointer;
begin
  if Assigned(Cs) then
  begin
    cs.Enter;
    try
      result:=Items.Find(subSystem+IntToHex(h, 8));
    finally
      cs.Leave;
    end;
  end;
end;

procedure RemoveHandleObj(h: THandle; const subSystem: string);
var
  i: Integer;
begin
  if Assigned(Cs) then
  begin
    cs.Enter;
    try
      i:=Items.FindIndexOf(subSystem+IntToHex(h, 8));
      Items.Delete(i);
    finally
      cs.Leave;
    end;
  end;
end;

function GetUniqueFilename(const path: widestring; basename, extension: widestring): widestring;
begin
  repeat
    result:=path+basename+IntToHex(Random($FFFFFF), 6)+extension;
  until not FileExists(result);
end;

procedure StartLog;
begin
  Assignfile(f, BasePath + BaseName + '_hooklog_'+IntToHex(Random($FFFFFF), 6)+'.txt');
  {$I-}Rewrite(f); {$I+}
  if ioresult = 0 then
  begin
    CanLog:=True;
  end;
end;

var
  TrampolineCreateFileA: function(lpFileName:LPCSTR; dwDesiredAccess:DWORD;
    dwShareMode:DWORD; lpSecurityAttributes:LPSECURITY_ATTRIBUTES;
    dwCreationDisposition:DWORD;dwFlagsAndAttributes:DWORD;
    hTemplateFile:HANDLE):HANDLE; stdcall = nil;
  TrampolineCreateFileW: function(lpFileName:LPCWSTR; dwDesiredAccess:DWORD;
    dwShareMode:DWORD; lpSecurityAttributes:LPSECURITY_ATTRIBUTES;
    dwCreationDisposition:DWORD;dwFlagsAndAttributes:DWORD;
    hTemplateFile:HANDLE):HANDLE; stdcall = nil;

function CreateFileABounce(lpFileName:LPCSTR; dwDesiredAccess:DWORD;
    dwShareMode:DWORD; lpSecurityAttributes:LPSECURITY_ATTRIBUTES;
    dwCreationDisposition:DWORD;dwFlagsAndAttributes:DWORD;
    hTemplateFile:HANDLE):HANDLE; stdcall;
var
  s: widestring;
begin
  if Assigned(TrampolineCreateFileA) then
  begin
    s:='CreateFileA("'+lpFileName+'", ';
    case dwDesiredAccess of
      GENERIC_READ: s:=s+'READ';
      GENERIC_WRITE: s:=s+'WRITE';
      GENERIC_READ or GENERIC_WRITE: s:=s+'READWRITE';
    end;

    s:=s+', ';
    case dwShareMode of
      FILE_SHARE_DELETE: s:=s+'SHARE_DELETE';
      FILE_SHARE_READ: s:=s+'SHARE_READ';
      FILE_SHARE_WRITE: s:=s+'SHARE_WRITE';
      else
        s:=s+IntToHex(dwShareMode, 8);
    end;

    s:=s+', ';
    case dwCreationDisposition of
      CREATE_ALWAYS: s:=s+'CREATE_ALWAYS';
      CREATE_NEW: s:=s+'CREATE_NEW';
      OPEN_ALWAYS: s:=s+'OPEN_ALWAYS';
      OPEN_EXISTING: s:=s+'OPEN_EXISTING';
      TRUNCATE_EXISTING: s:=s+'TRUNCATE_EXISTING';
    end;

    if config.DenyFileWriting and (dwDesiredAccess and Generic_Write = Generic_Write) then
        result:=INVALID_HANDLE_VALUE
    else
    result:=TrampolineCreateFileA(lpFileName, dwDesiredAccess, dwShareMode,
                          lpSecurityAttributes, dwCreationDisposition,
                          dwFlagsAndAttributes, hTemplateFile);

    s:=s+') = '+ IntToHex(NativeInt(result), 8);

    if result = INVALID_HANDLE_VALUE then
      if config.DenyFileWriting and (dwDesiredAccess and Generic_Write = Generic_Write) then
        s := s + ' (Denied)'
      else
        s := s + ' (Invalid Handle)';

    if Config.LogCreateFile then
      LOG(s);
  end;
end;

function CreateFileWBounce(lpFileName:LPCWSTR; dwDesiredAccess:DWORD;
    dwShareMode:DWORD; lpSecurityAttributes:LPSECURITY_ATTRIBUTES;
    dwCreationDisposition:DWORD;dwFlagsAndAttributes:DWORD;
    hTemplateFile:HANDLE):HANDLE; stdcall;
var
  s: string;
begin
  if Assigned(TrampolineCreateFileW) then
  begin
    s:='CreateFileW("'+lpFileName+'", ';
    case dwDesiredAccess of
      GENERIC_READ: s:=s+'READ';
      GENERIC_WRITE: s:=s+'WRITE';
      GENERIC_READ or GENERIC_WRITE: s:=s+'READWRITE';
    end;

    s:=s+', ';
    case dwShareMode of
      FILE_SHARE_DELETE: s:=s+'SHARE_DELETE';
      FILE_SHARE_READ: s:=s+'SHARE_READ';
      FILE_SHARE_WRITE: s:=s+'SHARE_WRITE';
      else
        s:=s+IntToHex(dwShareMode, 8);
    end;

    s:=s+', ';
    case dwCreationDisposition of
      CREATE_ALWAYS: s:=s+'CREATE_ALWAYS';
      CREATE_NEW: s:=s+'CREATE_NEW';
      OPEN_ALWAYS: s:=s+'OPEN_ALWAYS';
      OPEN_EXISTING: s:=s+'OPEN_EXISTING';
      TRUNCATE_EXISTING: s:=s+'TRUNCATE_EXISTING';
    end;

    if config.DenyFileWriting and (dwDesiredAccess and Generic_Write = Generic_Write) then
    begin
        result:=INVALID_HANDLE_VALUE;
        SetLastError(ERROR_ACCESS_DENIED);
    end
    else
    result:=TrampolineCreateFileW(lpFileName, dwDesiredAccess, dwShareMode,
                          lpSecurityAttributes, dwCreationDisposition,
                          dwFlagsAndAttributes, hTemplateFile);

    s:=s+') = '+ IntToHex(NativeInt(result), 8);
    if result = INVALID_HANDLE_VALUE then
      s := s + ' (Invalid Handle)';
    if Config.LogCreateFile then
      LOG(s);
  end;
end;

var
  TrampolineCreateProcessA: function(lpApplicationName: LPCSTR; lpCommandLine: LPCSTR;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: LPCSTR;
    const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation):
    BOOL; stdcall = nil;
  TrampolineCreateProcessW: function(lpApplicationName: LPWSTR; lpCommandLine: LPWSTR;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: LPWSTR;
    const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation): BOOL; stdcall = nil;

function CreateProcessABounce(lpApplicationName: LPCSTR; lpCommandLine: LPCSTR;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: LPCSTR;
    const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation):
    BOOL; stdcall;
var
  s: widestring;
begin
  if Assigned(TrampolineCreateProcessA) then
  begin
    s:=('CreateProcessA("'+lpApplicationName+'", "'+lpCommandLine+'", "'+ lpCurrentDirectory+'")');
    if Config.DenySpawnProcesses then
    begin
      result:=BOOL(1);
      //SetLastError(ERROR_ACCESS_DENIED);
    end else
    result:=TrampolineCreateProcessA(lpApplicationName, lpCommandLine, lpProcessAttributes,
              lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment,
              lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
    s:=s+' = '+ IntToHex(NativeInt(result), 8);
    if Config.LogCreateProcess then
      LOG(s);
  end;
end;

function getEntryPoint(AFilename: widestring): PtrUInt;
var
  f: TExeFile;
begin
  f:=TExeFile.Create;
  try
    if f.LoadFile(AFilename) then
    begin
      case f.FileType of
        fkExe32:
        begin
          result:=f.NTHeader.OptionalHeader.ImageBase + f.NTHeader.OptionalHeader.AddressOfEntryPoint;
          // Writeln('Image Base: '+IntToHex(f.NTHeader.OptionalHeader.ImageBase, 8)+', Entry point: '+IntToHex(entry, 8));
        end;
        fkExe64:
        begin
          result:=f.NTHeader64.OptionalHeader.ImageBase + f.NTHeader64.OptionalHeader.AddressOfEntryPoint;
          raise Exception.Create('Only 32 bit supported at this time');
        end;
        else
          result:=0;
      end;
    end else
      result:=0;
  finally
    f.Free;
  end;
end;

function CreateProcessWBounce(lpApplicationName: LPWSTR; lpCommandLine: LPWSTR;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: LPWSTR;
    const lpStartupInfo: TStartupInfo; lpProcessInformation: PProcessInformation): BOOL; stdcall;
var
  s: widestring;
begin
  if Assigned(TrampolineCreateProcessW) then
  begin
    s:=('CreateProcessW("'+lpApplicationName+'", "'+lpCommandLine+'", "'+ lpCurrentDirectory+'")');
    if Config.DenySpawnProcesses then
    begin
      result:=Bool(1);
      //SetLastError(ERROR_ACCESS_DENIED);
    end else
    if Config.HookInNewProcesses then
    try
      result:=TrampolineCreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes,
                lpThreadAttributes, bInheritHandles, dwCreationFlags  or CREATE_SUSPENDED, lpEnvironment,
                lpCurrentDirectory, lpStartupInfo, lpProcessInformation^);

      if Assigned(lpProcessInformation) then
      begin
        LOG('Hooking into new process...');

        if InjectDLL(lpProcessInformation.hProcess, Config.HookDLLLocation, 'StartHook', @Config, SizeOf(Config)) then
        begin
          LOG('Injected!');
        end else
          LOG('Injection failed!');

         if (dwCreationFlags and CREATE_SUSPENDED = 0) then
         begin
           ResumeThread(lpProcessInformation.hThread);
         end;

      end else
      LOG('CreateProcess Failed!');
    except
      on e: Exception do
        Log('Exception in hooking child process: '+e.Message);
    end else
    result:=TrampolineCreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes,
              lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment,
              lpCurrentDirectory, lpStartupInfo, lpProcessInformation^);

    s:=s + ' = '+ IntToHex(NativeInt(result), 8);
    if Config.LogCreateProcess then
      LOG(s);
  end;
end;

var
  TrampolineCreateProcessAsUserA: function(_para1:HANDLE; _para2:LPCTSTR; _para3:LPTSTR;
    _para4:LPSECURITY_ATTRIBUTES; _para5:LPSECURITY_ATTRIBUTES;_para6:WINBOOL;
    _para7:DWORD; _para8:LPVOID; _para9:LPCTSTR;  _para10:LPSTARTUPINFO;
    _para11:LPPROCESS_INFORMATION):WINBOOL; stdcall = nil;

  TrampolineCreateProcessAsUserW: function(_para1:HANDLE; _para2:LPCWSTR; _para3:LPWSTR;
    _para4:LPSECURITY_ATTRIBUTES; _para5:LPSECURITY_ATTRIBUTES;_para6:WINBOOL;
    _para7:DWORD; _para8:LPVOID; _para9:LPCWSTR; _para10:LPSTARTUPINFO;
    _para11:LPPROCESS_INFORMATION):WINBOOL; stdcall = nil;

function CreateProcessAsUserABounce(_para1:HANDLE; _para2:LPCTSTR; _para3:LPTSTR;
    _para4:LPSECURITY_ATTRIBUTES; _para5:LPSECURITY_ATTRIBUTES;_para6:WINBOOL;
    _para7:DWORD; _para8:LPVOID; _para9:LPCTSTR;  _para10:LPSTARTUPINFO;
    _para11:LPPROCESS_INFORMATION):WINBOOL; stdcall;
begin
  if Assigned(TrampolineCreateProcessAsUserA) then
  begin
    LOG('CreateProcessAsUserA('+_para2+' '+_para3+')');
    if Config.DenySpawnProcesses then
    begin
      result:=Bool(1);
      SetLastError(ERROR_ACCESS_DENIED);
    end else
    result:=TrampolineCreateProcessAsUserA(_para1, _para2, _para3, _para4, _para5, _para6,
      _para7, _para8, _para9, _para10, _para11);

    if Config.LogCreateProcess then
      LOG('CreateProcessAsUserA='+ IntToHex(NativeInt(result), 8));
  end;
end;

function CreateProcessAsUserWBounce(_para1:HANDLE; _para2:LPCWSTR; _para3:LPWSTR;
    _para4:LPSECURITY_ATTRIBUTES; _para5:LPSECURITY_ATTRIBUTES;_para6:WINBOOL;
    _para7:DWORD; _para8:LPVOID; _para9:LPCWSTR; _para10:LPSTARTUPINFO;
    _para11:LPPROCESS_INFORMATION):WINBOOL; stdcall;
begin
  if Assigned(TrampolineCreateProcessAsUserW) then
  begin
    LOG('CreateProcessAsUserW('+_para2+' '+_para3+')');
    if Config.DenySpawnProcesses then
    begin
      result:=Bool(1);
      SetLastError(ERROR_ACCESS_DENIED);
    end else
    result:=TrampolineCreateProcessAsUserW(_para1, _para2, _para3, _para4, _para5, _para6,
      _para7, _para8, _para9, _para10, _para11);
    if Config.LogCreateProcess then
      LOG('CreateProcessAsUserW='+ IntToHex(NativeInt(result), 8));
  end;
end;

var
  TrampolineChangeDisplaySettingsA: function(var lpDevMode: TDeviceModeA; dwFlags: DWORD): Longint; stdcall = nil;
  TrampolineChangeDisplaySettingsW: function(var lpDevMode: TDeviceModeW; dwFlags: DWORD): Longint; stdcall = nil;


function ChangeDisplaySettingsABounce(var lpDevMode: TDeviceModeA; dwFlags: DWORD): Longint; stdcall;
begin
  if Assigned(TrampolineChangeDisplaySettingsA) then
  begin
    if Config.Windowed then
      result:=DISP_CHANGE_SUCCESSFUL
    else
      result:=TrampolineChangeDisplaySettingsA(lpDevMode, dwFlags);
  end;
end;

function ChangeDisplaySettingsWBounce(var lpDevMode: TDeviceModeW; dwFlags: DWORD): Longint; stdcall;
begin
  if Assigned(TrampolineChangeDisplaySettingsW) then
  begin
    if Config.Windowed then
      result:=DISP_CHANGE_SUCCESSFUL
    else
      result:=TrampolineChangeDisplaySettingsW(lpDevMode, dwFlags);
  end;
end;
(*
type
     tACMSTREAMHEADER = record
       cbStruct:DWORD;               // sizeof(ACMSTREAMHEADER)
       fdwStatus:DWORD;              // ACMSTREAMHEADER_STATUSF_*
       dwUser:DWORD;                 // user instance data for hdr
       pbSrc:LPBYTE;
       cbSrcLength:DWORD;
       cbSrcLengthUsed:DWORD;
       dwSrcUser:DWORD;              // user instance data for src
       pbDst:LPBYTE;
       cbDstLength:DWORD;
       cbDstLengthUsed:DWORD;
       dwDstUser:DWORD;              // user instance data for dst
       dwReservedDriver:array[0..9] of DWORD;   // driver reserved work space
     end;
     ACMSTREAMHEADER = tACMSTREAMHEADER;
     PACMSTREAMHEADER = ^tACMSTREAMHEADER;
     LPACMSTREAMHEADER = ^tACMSTREAMHEADER;

LPHACMDRIVER = pointer;
  HACMDRIVERID  = THandle;
  HACMOBJ = THandle;
  HACMSTREAM = Pointer;
  HACMDRIVER = Pointer;
  LPACMFORMATDETAILS = Pointer;
  ACMFORMATENUMCB = Pointer;
  ACMDRIVERENUMCB = Pointer;   *)

var
  TrampolineCreateWindowExA: function(dwExStyle:DWORD; lpClassName:LPCSTR; lpWindowName:LPCSTR;
      dwStyle:DWORD; X:longint;Y:longint; nWidth:longint; nHeight:longint; hWndParent:HWND; hMenu:HMENU;hInstance:HINST; lpParam:LPVOID):HWND; stdcall = nil;
  TrampolineCreateWindowExW: function(dwExStyle:DWORD; lpClassName:LPCWSTR; lpWindowName:LPCWSTR;
      dwStyle:DWORD; X:longint;Y:longint; nWidth:longint; nHeight:longint; hWndParent:HWND; hMenu:HMENU;hInstance:HINST; lpParam:LPVOID):HWND; stdcall = nil;
  TrampolineShowCursor: function (bShow:WINBOOL):longint; stdcall = nil;

  TrampolineacmStreamConvert: function(has: THandle; p: Pointer; fdwConvert: DWORD): MMRESULT; stdcall = nil;
  TrampolineacmStreamOpen: function(phas:PHandle;       // pointer to stream handle
                       had:THandle;        // optional driver handle
                       pwfxSrc:LPWAVEFORMATEX;    // source format to convert
                       pwfxDst:LPWAVEFORMATEX;    // required destination format
                       pwfltr:Pointer;     // optional filter
                       dwCallback:DWORD; // callback
                       dwInstance:DWORD; // callback instance data
                       fdwOpen:DWORD     // ACM_STREAMOPENF_* and CALLBACK_*
                      ):MMRESULT; stdcall = nil;
  TrampolineacmStreamClose: function(has:THandle;
                        fdwClose:DWORD):MMRESULT; stdcall = nil;

  TrampolineAcmMetrics: function(hao: HACMOBJ; uMetric: UINT; pMetric: LPVOID): MMResult; stdcall = nil;
  TrampolineAcmDriveropen: function(phad: LPHACMDRIVER; HACMDRIVERID: HACMDRIVERID; fdwOpen: DWORD): MMResult; stdcall = nil;
  TrampolineAcmDriverclose: function(had:HACMDRIVER; fdwClose:DWORD):MMRESULT; stdcall = nil;
  TrampolineacmStreamPrepareHeader: function(
                        has: HACMSTREAM;
                        pash: LPACMSTREAMHEADER;
                        fdwPrepare: DWORD
                        ): MMResult; stdcall = nil;
  TrampolineacmFormatEnum: function(
                        had:HACMDRIVER;
                        pafd:LPACMFORMATDETAILS;
                        fnCallback:ACMFORMATENUMCB;
                        dwInstance: DWORD_PTR;
                        fdwEnum: DWORD
                        ): MMResult; stdcall = nil;
  TrampolineacmDriverEnum: function(
                           fnCallback: ACMDRIVERENUMCB;
                           dwInstance: DWORD_PTR;
                           fdwEnum:DWORD           ): MMResult; stdcall = nil;


function acmDriverCloseBounce(had:HACMDRIVER; fdwClose:DWORD):MMRESULT; stdcall;
begin
  //Log('acmDriverClose('+IntToHex(had, 8)+', '+IntToStr(fdwClose)+')');
  result:=TrampolineAcmDriverclose(had, fdwClose);
end;

function acmMetricsBounce(hao: HACMOBJ; uMetric: UINT; pMetric: LPVOID): MMResult; stdcall;
begin
  result:=TrampolineAcmMetrics(hao, uMetric, pMetric);
  //log('acmMetrics('+IntToHex(NativeUInt(hao), 8)+', '+ IntToStr(uMetric)+', '+IntToHex(NativeUInt(pMetric), 8)+') = '+IntToStr(result));
end;

function acmDriverOpenBounce(phad: LPHACMDRIVER; HACMDRIVERID: HACMDRIVERID; fdwOpen: DWORD): MMResult; stdcall;
begin
  result:=TrampolineAcmDriveropen(phad, HACMDRIVERID, fdwOpen);
  //log('acmDriverOpen('+IntToHex(NativeUInt(phad), 8)+', '+IntToHex(HACMDRIVERID, 8)+', '+IntTOStr(fdwOpen)+') = '+IntToStr(result));
end;

function acmStreamPrepareHeaderBounce(has: HACMSTREAM;
                        pash: LPACMSTREAMHEADER;
                        fdwPrepare: DWORD
                        ): MMResult; stdcall;
begin
  //log('acmStreamPrepareHeader');
  result:=TrampolineacmStreamPrepareHeader(has, pash, fdwPrepare);
end;

procedure LogFormat(Name: string; Format: LPWAVEFORMATEX);
begin
  LOG('WaveFormat '+Name);
  LOG('cbSize: '+IntToHex(Format^.cbSize, 4));
  LOG('nAvgBytesPerSec: '+IntToStr(Format^.nAvgBytesPerSec));
  LOG('nBlockAlign: '+IntToStr(Format^.nBlockAlign));
  LOG('nChannels: '+IntToStr(Format^.nChannels));
  LOG('nSamplesPerSec: '+IntToStr(Format^.nSamplesPerSec));
  LOG('wBitsPerSample: '+IntToStr(Format^.wBitsPerSample));
  LOG('wFormatTag: '+IntToHex(Format^.wFormatTag, 2));
  LOG('----');
end;

var
  originalacmDriverEnumCallback: ACMDRIVERENUMCB;
  originalacmFormatEnumCallback: ACMFORMATENUMCB;

function myacmDriverEnumCallback(hadid:HACMDRIVERID; dwInstance:DWORD; fdwSupport:DWORD):BOOL; stdcall;
begin
  //log('acmDriverEnumCallback('+IntToHex(hadid, 8)+', '+ IntToStr(dwInstance) + ', '+IntToStr(fdwSupport)+') start');
  result:=originalacmDriverEnumCallback(hadid, dwInstance, fdwSupport);
  //log('acmDriverEnumCallback('+IntToHex(hadid, 8)+', '+ IntToStr(dwInstance) + ', '+IntToStr(fdwSupport)+') = '+BoolToStr(result, 'True', 'False'));
end;

function myacmFormatEnumCallback(hadid:HACMDRIVERID;
                                pafd:LPACMFORMATDETAILS;
                                dwInstance:DWORD;
                                fdwSupport:DWORD):BOOL; stdcall;
begin
  result:=originalacmFormatEnumCallback(hadid, pafd, dwInstance, fdwSupport);
  //log('acmFormatEnumCallback('+IntToStr(pafd.cbStruct)+', '+IntToStr(pafd.cbwfx)+', '+IntToStr(pafd.dwFormatIndex)+
  // ', '+IntToStr(pafd.dwFormatTag)+', '+IntToStr(pafd.fdwSupport)+', "'+pafd.szFormat+'"), ..., '+IntToHex(dwInstance, 8)+', '+IntToStr(fdwSupport)+') = '+BoolToStr(result, 'True', 'False'));
  // LogFormat('pafd fmt', pafd.pwfx);
end;

function acmDriverEnumBounce(fnCallback: ACMDRIVERENUMCB;
                           dwInstance: DWORD_PTR;
                           fdwEnum:DWORD           ): MMResult; stdcall;
begin
  //log('acmDriverEnum('+IntToHex(NativeUInt(@fnCallback), 8)+', '+IntToHex(DwInstance, 8)+', '+IntToStr(fdwEnum)+') start');
  //if Assigned(originalacmDriverEnumCallback) then
  //log('acmDriverEnum is being used multithreaded (or this code is broken). Either way, crap');
  if not Assigned(fnCallback) then
  begin
    //log('acmDriverEnum no callback');
    result:=TrampolineacmDriverEnum(fnCallback, dwInstance, fdwEnum);
    Exit;
  end;
  cs2.Enter;
  try
    originalacmDriverEnumCallback:=fnCallback;
    result:=TrampolineacmDriverEnum(myacmDriverEnumCallback, dwInstance, fdwEnum);
  finally
    originalacmDriverEnumCallback:=nil;
    cs2.Leave;
  end;
  //log('acmDriverEnum done');
end;


function acmFormatEnumBounce(had:HACMDRIVER;
                        pafd:LPACMFORMATDETAILS;
                        fnCallback:ACMFORMATENUMCB;
                        dwInstance: DWORD_PTR;
                        fdwEnum: DWORD
                        ): MMResult; stdcall;
begin
  //log('acmFormatEnum('+IntToHex(had, 8)+', ('+IntToStr(pafd.cbStruct)+', '+IntToStr(pafd.cbwfx)+', '+IntToStr(pafd.dwFormatIndex)+
  //', '+IntToStr(pafd.dwFormatTag)+', '+IntToStr(pafd.fdwSupport)+', "'+pafd.szFormat+'"), ..., '+IntToStr(dwInstance)+', '+IntToStr(fdwEnum)+') start');

  if not Assigned(fnCallback) then
  begin
    result:=TrampolineacmFormatEnum(had, pafd, fnCallback, dwInstance, fdwEnum);
    //log('no callback in acmFormatEnum');
  end else
  begin
    //if Assigned(originalacmFormatEnumCallback) then
    //  log('acmFormatEnum is being used multithreaded (or this code is broken). Either way, crap');

    originalacmFormatEnumCallback:=fnCallback;
    result:=TrampolineacmFormatEnum(had, pafd, @myacmFormatEnumCallback, dwInstance, fdwEnum);
    originalacmFormatEnumCallback:=nil;
  end;
  //log('acmFormatEnum('+IntToHex(had, 8)+', ('+IntToStr(pafd.cbStruct)+', '+IntToStr(pafd.cbwfx)+', '+IntToStr(pafd.dwFormatIndex)+
  //', '+IntToStr(pafd.dwFormatTag)+', '+IntToStr(pafd.fdwSupport)+', "'+pafd.szFormat+'"), ..., '+IntToStr(dwInstance)+', '+IntToStr(fdwEnum)+') = '+IntToStr(result));
  //LogFormat('pafd fmt', pafd.pwfx);
end;


function acmStreamCloseBounce(has:THandle; fdwClose:DWORD):MMRESULT; stdcall;
var
  r: TWaveRecorder;
begin
  //log('acmStreamClose');
  if Assigned(TrampolineacmStreamClose) then
  begin
    result := TrampolineacmStreamClose(has, fdwClose);
    r := GetHandleObj(has, 'acm');
    if Assigned(r) then
    begin
      RemoveHandleObj(has, 'acm');
      r.Free;
    end;
  end;
end;

function acmStreamOpenBounce(phas:PHandle;       // pointer to stream handle
                       had:THandle;        // optional driver handle
                       pwfxSrc:LPWAVEFORMATEX;    // source format to convert
                       pwfxDst:LPWAVEFORMATEX;    // required destination format
                       pwfltr:Pointer;     // optional filter
                       dwCallback:DWORD; // callback
                       dwInstance:DWORD; // callback instance data
                       fdwOpen:DWORD     // ACM_STREAMOPENF_* and CALLBACK_*
                      ):MMRESULT; stdcall;
var
  s: string;
begin
  //log('acmStreamOpen('+IntToHex(NativeUInt(phas), 8)+', '+IntToHex(had, 8)+', ..., ..., '+IntToHex(NativeUInt(pwfltr), 8)+', '+IntToHex(dwCallback, 8)+', '+IntToStr(dwInstance)+', '+IntToStr(fdwOpen)+')');
  //LogFormat('pwfxSrc', pwfxSrc);
  //LogFormat('pwfxDst', pwfxDst);
  if Assigned(TrampolineacmStreamOpen) then
  begin
    result := TrampolineacmStreamOpen(phas, had, pwfxSrc, pwfxDst, pwfltr, dwCallback, dwInstance, fdwOpen);

    if Config.DumpACM then
    if Assigned(phas) then
    begin
      s:=GetUniqueFilename(ExtractFilePath(BasePath), BaseName+'_acm_','.wav');
      LOG('Recording acm compressed wave file '+s);
      RegisterHandleObj(phas^, 'acm', TWaveRecorder.Create(s, pwfxDst^));
    end;
  end;
end;

function acmStreamConvertBounce(has: THandle; p: LPACMSTREAMHEADER; fdwConvert: DWORD): MMRESULT; stdcall;
var
  r: TWaveRecorder;
begin
  if Assigned(TrampolineacmStreamConvert) then
  begin
    result := TrampolineacmStreamConvert(has, p, fdwConvert);

    log('acmStreamConvert(): '+IntToStr(p^.cbSrcLengthUsed)+' => '+IntToStr(p^.cbDstLengthUsed));
    r := GetHandleObj(has, 'acm');
    if Assigned(r) then
    begin
      if Assigned(p^.pbDst) then
        r.WriteData(p^.pbDst, p^.cbDstLengthUsed);
    end;
  end;
end;

function ShowCursorBounce(bShow:WINBOOL):longint; stdcall;
begin
  if Assigned(TrampolineShowCursor) then
  begin
    if Config.ShowCursor then
      result:=TrampolineShowCursor(True)
    else
      result:=TrampolineShowCursor(bShow);
  end;
end;

function CreateWindowExABounce(dwExStyle:DWORD; lpClassName:LPCSTR; lpWindowName:LPCSTR;
      dwStyle:DWORD; X:longint;Y:longint; nWidth:longint; nHeight:longint; hWndParent:HWND; hMenu:HMENU;hInstance:HINST; lpParam:LPVOID):HWND; stdcall;
begin
  if Assigned(TrampolineCreateWindowExA) then
  begin
    if Config.Windowed then
    begin
      dwStyle:=(dwStyle and (not ws_maximize)) or WS_CAPTION or WS_MINIMIZEBOX or WS_SYSMENU;
    end;
    result := TrampolineCreateWindowExA(dwExStyle, lpClassName, lpWindowName, dwStyle, X, Y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam);
  end;
end;

function CreateWindowExWBounce(dwExStyle:DWORD; lpClassName:LPCWSTR; lpWindowName:LPCWSTR;
      dwStyle:DWORD; X:longint;Y:longint; nWidth:longint; nHeight:longint; hWndParent:HWND; hMenu:HMENU;hInstance:HINST; lpParam:LPVOID):HWND; stdcall;
begin
  if Assigned(TrampolineCreateWindowExW) then
  begin
    if Config.Windowed then
    begin
      dwStyle:=(dwStyle and (not ws_maximize)) or WS_CAPTION or WS_MINIMIZEBOX or WS_SYSMENU;
    end;
    result := TrampolineCreateWindowExW(dwExStyle, lpClassName, lpWindowName, dwStyle, X, Y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam);
  end;
end;

var
  TrampolineWaveOutOpen: function(x1: LPHWAVEOUT; x2: UINT; x3: LPCWAVEFORMATEX;
      x4: DWORD_PTR; x5: DWORD_PTR; x6: DWORD): MMRESULT; stdcall = nil;
  TrampolinewaveOutClose: function(x1: HWAVEOUT): MMRESULT; stdcall = nil;
  TrampolinewaveOutWrite: function(x1: HWAVEOUT; x2: LPWAVEHDR; x3: UINT): MMRESULT; stdcall = nil;

function WaveOutOpenBounce(x1: LPHWAVEOUT; x2: UINT; x3: LPCWAVEFORMATEX;
      x4: DWORD_PTR; x5: DWORD_PTR; x6: DWORD): MMRESULT; stdcall;
var
  s: widestring;
  origFmt: TWAVEFORMATEX;
begin
  if Assigned(TrampolineWaveOutOpen) then
  begin
    //s:='waveOutOpen('+IntToHex(NativeUint(x1), 8)+', '+IntToHex(x2, 8)+ ', ?, '+IntToHex(x4, 8)+', '+IntToHex(x5, 8)+', '+IntToHex(x6, 8);

    if Assigned(x1) and (x6 and WAVE_FORMAT_QUERY <> WAVE_FORMAT_QUERY) and Assigned(x3) then
    begin
      origFmt := x3^;
      case config.SpeedFactor of
        1:begin
          x3^.nSamplesPerSec:=x3^.nSamplesPerSec div 2;
          x3^.nAvgBytesPerSec:=x3^.nAvgBytesPerSec div 2;
        end;
        2:begin
          x3^.nSamplesPerSec:=x3^.nSamplesPerSec * 2;
          x3^.nAvgBytesPerSec:=x3^.nAvgBytesPerSec * 2;
        end;
      end;
    end;

    result:=TrampolineWaveOutOpen(x1, x2, x3, x4, x5, x6);

    //s:=s + ' = ' + IntToHex(result, 8);
    //LOG(s);

    if Assigned(x1) and (x6 and WAVE_FORMAT_QUERY <> WAVE_FORMAT_QUERY) then
    begin
      if (result = MMSYSERR_NOERROR) and Config.RecordAudio then
      begin
        s:=GetUniqueFilename(BasePath, BaseName+'_record_','.wav');
        LOG('Recording wave file '+s);
        RegisterHandleObj(x1^, 'wave', TWaveRecorder.Create(s, origFmt));
      end;
    end;
  end;
end;

function waveOutCloseBounce(x1: HWAVEOUT): MMRESULT; stdcall;
var
  p: TWaveRecorder;
begin
  if Assigned(TrampolinewaveOutClose) then
  begin
    result:=TrampolinewaveOutClose(x1);
    if Config.RecordAudio then
    begin
      p:=GetHandleObj(x1, 'wave');
      if Assigned(p) then
      begin
        RemoveHandleObj(x1, 'wave');
        p.Free;
      end;
    end;
  end;
end;

function waveOutWriteBounce(x1: HWAVEOUT; x2: LPWAVEHDR; x3: UINT): MMRESULT;stdcall;
var
  p: TWaveRecorder;
begin
  if Assigned(TrampolinewaveOutWrite) then
  begin
    result:=TrampolinewaveOutWrite(x1, x2, x3);
    if Config.RecordAudio then
    begin
      p:=GetHandleObj(x1, 'wave');
      if Assigned(p) and Assigned(x2) then
      begin
        if Config.SlowWaveWrite then
          p.WriteWaveHdr(x2, GetTickCount)
        else
          p.WriteData(x2^.lpData, x2^.dwBufferLength);
      end;
    end;
  end;
end;

var
  TrampolineglShaderSource: procedure(shader: GLuint; count: GLsizei; const _string: PGLchar; const length: PGLint); stdcall = nil;
  TrampolinewglGetProcAddress: function(proc: PChar): Pointer; stdcall = nil;
  TrampolineglCreateShaderProgramv: function(AType: GLenum; count: GLsizei; _string: PGLchar): GLuint; stdcall = nil;
  ShaderWritten: Integer;

function glCreateShaderProgramvBounce(AType: GLenum; count: GLsizei; _string: PGLchar): GLuint; stdcall;
var
  i: Integer;
  p: PChar;
  hash: Cardinal;
  pa: PPointerArray;
  s: string;
  len: glint;
  f: File;
  return: Word;
begin
  if Assigned(TrampolineglCreateShaderProgramv) then
  begin
    if Assigned(_string) then
    begin
      pa := Pointer(_string);
      hash := 0;
      for i:=0 to count - 1 do
      begin
        if Assigned(pa[i]) then
        begin
          hash := hash + SuperfastHash(pa[i], System.Length(pchar(pa[i])));
        end;
      end;

      s:=BasePath + BaseName+'_shader_'+IntToHex(hash, 8)+'.txt';
      InterLockedIncrement(ShaderWritten);

      if Config.Inject and FileExists(s) then
      begin
        assignfile(F, s);
        {$i-}reset(f, 1);{$i+}
        if ioresult = 0 then
        begin
          LOG('Replacing shader '+s);
          i:=0;
          len:=FileSize(f);
          GetMem(p, len);
          Blockread(f, p^, len);
          closefile(f);

          result:=TrampolineglCreateShaderProgramv(AType, 1, @p);
          Freemem(p);
          Exit;
        end;
      end;

      if Config.GetShaders then
      begin
        Assignfile(f, s);
        {$i-}rewrite(f, 1);{$i+}
        if ioresult = 0 then
        begin
          return:=$0a0d;
          for i := 0 to count - 1 do
          begin
            len:=0;
            while PChar(pa[i])[len] <> #0 do inc(len);
            BlockWrite(f, pa[i]^, len);
            Blockwrite(f, return, SizeOf(return));
          end;
          closefile(f);
        end else
          LOG('Could not write shader to disk!');
      end;
    end;
    result:=TrampolineglCreateShaderProgramv(AType, count, _string);
    if Config.GetShaders then
      LOG('Dumped shader '+s+', glCreateShaderProgramv() = '+IntToHex(result, 8));

  end else
    result:=0;
end;

procedure glShaderSourceBounce(shader: GLuint; count: GLsizei; _string: PGLchar; length: PGLint); stdcall;
var
  f: File;
  s: string;
  i: Integer;
  pa: PPointerArray;
  pl: PIntegerArray;
  return: Word;
  hash: Cardinal;
  p: Pointer;
  len: glint;
begin
  if Assigned(TrampolineglShaderSource) then
  begin
    if Assigned(_string) then
    begin
      pa := Pointer(_string);
      pl := Pointer(length);

      hash := 0;
      for i:=0 to count - 1 do
        if Assigned(length) then
        hash := hash + SuperfastHash(pa[i], pl[i])
       else
        hash := hash + SuperfastHash(pa[i], System.Length(pchar(pa[i])));

      s:=BasePath + BaseName+'_shader_'+IntToHex(hash, 8)+'.txt';
      InterLockedIncrement(ShaderWritten);

      if Config.Inject and FileExists(s) then
      begin
        assignfile(F, s);
        {$i-}reset(f, 1);{$i+}
        if ioresult = 0 then
        begin
          LOG('Replacing shader '+s);
          i:=0;
          len:=FileSize(f);
          GetMem(p, len);
          Blockread(f, p^, len);
          closefile(f);

          TrampolineglShaderSource(shader, 1, @p, @len);
          Freemem(p);
          Exit;
        end;
      end;

      if Config.GetShaders then
      begin
        Assignfile(f, s);
        {$i-}rewrite(f, 1);{$i+}
        if ioresult = 0 then
        begin

          return:=$0a0d;

          for i := 0 to count - 1 do
          begin
            if Assigned(length) then
              len:=pl[i]
            else begin
              len:=0;
              while PChar(pa[i])[len] <> #0 do inc(len);
            end;
            BlockWrite(f, pa[i]^, len);
            Blockwrite(f, return, SizeOf(return));
          end;
          closefile(f);
        end else
          LOG('Could not write shader to disk!');
      end;
    end;
    TrampolineglShaderSource(shader, count, _string, length);
    if Config.GetShaders then
      LOG('Dumped shader '+s+' id '+IntToHex(shader, 8));

  end;
end;

var
  TrampolineglCompileShader: procedure(shader:GLUint); stdcall = nil;

procedure glCompileShaderBounce(shader: GLUInt); stdcall;
var
  AResult: GLUint;
  TextLen: Integer;
  InfoText: string;
begin
  if Assigned(TrampolineglCompileShader) then
  begin
    TrampolineglCompileShader(shader);

    if not Assigned(glGetShaderiv) then
      glGetShaderiv := wglGetProcAddress('glGetShaderiv');
    glGetShaderiv(Shader, GL_COMPILE_STATUS, @AResult);
    if AResult <> GL_TRUE then
    begin
      glGetShaderiv(Shader, GL_INFO_LOG_LENGTH, @TextLen);
      if TextLen>1 then
      begin
        setlength(Infotext, TextLen);
        if not Assigned(glGetShaderInfoLog) then
          glGetShaderInfoLog := wglGetProcAddress('glGetShaderInfoLog');
        glGetShaderInfoLog(Shader, TextLen, nil, @Infotext[1]);
        LOG('glCompileShader('+IntToHex(shader, 8)+'): '+InfoText);
      end;
    end;
  end;
end;

function wglGetProcAddressBounce(proc: PChar): Pointer; stdcall;
begin
  if Assigned(TrampolinewglGetProcAddress) then
  begin
    result:=TrampolinewglGetProcAddress(proc);

    if Assigned(proc) and Config.LogWglProcs then
      LOG('wglGetProcAddress("'+proc+'") = '+IntToHex(NativeUInt(result), 8));

    if (proc = 'glShaderSource')or(proc = 'glShaderSourceARB') then
    begin
      if not Assigned(TrampolineglShaderSource) then
        TrampolineglShaderSource:=result;
      result:=@glShaderSourceBounce;
    end else if (proc = 'glCreateShaderProgramv') then
    begin
      if not Assigned(TrampolineglCreateShaderProgramv) then
        TrampolineglCreateShaderProgramv:=result;
      result:=@glCreateShaderProgramvBounce;
    end else if (proc = 'glCompileShader') then
    begin
      if not Assigned(TrampolineglCompileShader) then
        TrampolineglCompileShader := result;
      result:=@glCompileShaderBounce;
    end else if proc = 'glGetShaderiv' then
      glGetShaderiv := result
    else if proc = 'glGetShaderInfoLog' then
      glGetShaderInfoLog := result;
  end;
end;

var
  TrampolineDXSetCooperativeLevel: function (foo: Pointer; hWnd: HWND; dwFlags: DWORD): HRESULT; stdcall = nil;
  TrampolineDirectDrawCreate: function(lpGUID: PGUID; out lplpDD: IDirectDraw; pUnkOuter: IUnknown): HRESULT; stdcall = nil;
  TrampolineDirectSoundCreate8: function(lpcGuidDevice: LPGUID; out ppDS8: IUnknown; pUnkOuter: IUnknown): HRESULT; stdcall = nil;
  TrampolineCreateSoundBuffer: function(self: Pointer; const pcDSBufferDesc: TDSBufferDesc; out ppDSBuffer: IDirectSoundBuffer; pUnkOuter: IUnknown): HResult; stdcall = nil;

  TrampolineDSB8Lock: function(self: Pointer; dwOffset, dwBytes: DWORD; ppvAudioPtr1: PPointer; pdwAudioBytes1: PDWORD;
      ppvAudioPtr2: PPointer; pdwAudioBytes2: PDWORD; dwFlags: DWORD): HResult; stdcall = nil;

  TrampolineDSB8Unlock: function(self: Pointer; pvAudioPtr1: Pointer; dwAudioBytes1: DWORD; pvAudioPtr2: Pointer; dwAudioBytes2: DWORD): HResult; stdcall = nil;

  TrampolineDuplicateSoundbuffer: function(self: Pointer; pDSBufferOriginal: IDirectSoundBuffer; out ppDSBufferDuplicate: IDirectSoundBuffer): HResult; stdcall = nil;

  TrampolineDirect3dCreate9:function(SDKVersion: LongWord): Pointer; stdcall = nil;

  TrampolineD3d9CreateDevice: function(self: Pointer; Adapter: LongWord; DeviceType: TD3DDevType; hFocusWindow: HWND;
      BehaviorFlags: DWord; pPresentationParameters: PD3DPresentParameters; out ppReturnedDeviceInterface: IDirect3DDevice9): HResult; stdcall = nil;



function D3d9CreateDeviceBounce(self: Pointer; Adapter: LongWord; DeviceType: TD3DDevType; hFocusWindow: HWND;
          BehaviorFlags: DWord; pPresentationParameters: PD3DPresentParameters; out ppReturnedDeviceInterface: IDirect3DDevice9): HResult; stdcall;
var
  orig: TD3DPresentParameters;
begin
  if Assigned(TrampolineD3d9CreateDevice) then
  begin
    LOG('d3d9.CreateDevice');
    if config.Windowed and Assigned(pPresentationParameters) then
    begin
      LOG('d3d9 windowed?');
      orig:=pPresentationParameters^;
      pPresentationParameters^.Windowed:=True;
    end;
    result:=TrampolineD3d9CreateDevice(self, Adapter, DeviceType, hFocusWindow, BehaviorFlags, pPresentationParameters, ppReturnedDeviceInterface);
    if config.Windowed and Assigned(pPresentationParameters) then
      pPresentationParameters^ := orig;
  end;
end;

function Direct3dCreate9Bounce(SDKVersion: LongWord): Pointer; stdcall;
begin
  if Assigned(TrampolineDirect3dCreate9) then
  begin
    LOG('Direct3dCreate9');
    result := TrampolineDirect3dCreate9(SDKVersion);
    TrampolineD3d9CreateDevice := InterceptCreate(IInterface(result), 16, @D3d9CreateDeviceBounce);
  end;
end;

function DuplicateSoundbufferTrampoline(self: Pointer; pDSBufferOriginal: IDirectSoundBuffer; out ppDSBufferDuplicate: IDirectSoundBuffer): HResult; stdcall;
begin
  LOG('DUPLICATESOUNDBUFFER');
  if Assigned(TrampolineDuplicateSoundbuffer) then
  begin
    result := TrampolineDuplicateSoundbuffer(self, pDSBufferOriginal, ppDSBufferDuplicate);
  end;
end;

function DSB8Unlock(self: Pointer; pvAudioPtr1: Pointer; dwAudioBytes1: DWORD; pvAudioPtr2: Pointer; dwAudioBytes2: DWORD): HResult; stdcall;
var
  t: TWaveRecorder;
  s: string;
begin
  if Assigned(TrampolineDSB8Unlock) then
  begin
    result := TrampolineDSB8Unlock(self, pvAudioPtr1, dwAudioBytes1, pvAudioPtr2, dwAudioBytes2);
    if Config.RecordAudio then
    begin
      t:=GetHandleObj(Handle(self), 'dsound');
      if Assigned(t) then
      begin
        if Assigned(pvAudioPtr1) then
          t.WriteData(pvAudioPtr1, dwAudioBytes1);
        if Assigned(pvAudioPtr2) then
          t.WriteData(pvAudioPtr2, dwAudioBytes2);
      end;
    end;
  end;
end;

function CreateSoundBufferBounce(this: Pointer; const pcDSBufferDesc: TDSBufferDesc; out ppDSBuffer: IDirectSoundBuffer; pUnkOuter: IUnknown): HResult; stdcall;
var
  s: string;
  origFmt: TWAVEFORMATEX;
begin
  if Assigned(TrampolineCreateSoundBuffer) then
  begin
    if Assigned(pcDSBufferDesc.lpwfxFormat) then
    begin
      origFmt := pcDSBufferDesc.lpwfxFormat^;
      case Config.SpeedFactor of
        1:begin
          pcDSBufferDesc.lpwfxFormat^.nSamplesPerSec:=pcDSBufferDesc.lpwfxFormat^.nSamplesPerSec div 2;
          pcDSBufferDesc.lpwfxFormat^.nAvgBytesPerSec:=pcDSBufferDesc.lpwfxFormat^.nAvgBytesPerSec div 2;
        end;
        2:begin
          pcDSBufferDesc.lpwfxFormat^.nSamplesPerSec:=pcDSBufferDesc.lpwfxFormat^.nSamplesPerSec * 2;
          pcDSBufferDesc.lpwfxFormat^.nAvgBytesPerSec:=pcDSBufferDesc.lpwfxFormat^.nAvgBytesPerSec * 2;
        end;
      end;
    end;
    result := TrampolineCreateSoundBuffer(this, pcDSBufferDesc, ppDSBuffer, pUnkOuter);

    if Assigned(pcDSBufferDesc.lpwfxFormat) then
      pcDSBufferDesc.lpwfxFormat^ := origFmt;

    if Assigned(ppDSBuffer) then
      TrampolineDSB8Unlock := InterceptCreate(ppDSBuffer, 19, @DSB8Unlock);

    if Config.RecordAudio and Assigned(ppDSBuffer) and Assigned(pcDSBufferDesc.lpwfxFormat) then
    begin
      s:=GetUniqueFilename(BasePath, BaseName+'_record_','.wav');
      RegisterHandleObj(Handle(ppDSBuffer), 'dsound', TWaveRecorder.Create(s, origFmt));
    end;

  end;
end;

function DirectSoundCreate8Bounce(lpcGuidDevice: LPGUID; out ppDS8: IUnknown; pUnkOuter: IUnknown): HRESULT; stdcall;
begin
  if Assigned(TrampolineDirectSoundCreate8) then
  begin
    result:=TrampolineDirectSoundCreate8(lpcGuidDevice, ppDS8, pUnkOuter);
    if Assigned(ppDS8) then
    begin
      TrampolineCreateSoundBuffer := InterceptCreate(ppDS8, 3, @CreateSoundBufferBounce);
      TrampolineDuplicateSoundbuffer := InterceptCreate(ppDS8, 5, @DuplicateSoundbufferTrampoline);
    end;
  end;
end;

function DXSetCooperativeLevelBounce(foo: Pointer; hWnd: HWND; dwFlags: DWORD): HRESULT; stdcall;
begin
  if Assigned(TrampolineDXSetCooperativeLevel) then
  begin
    result:=TrampolineDXSetCooperativeLevel(foo, hWnd, (dwFlags and (not (DDSCL_EXCLUSIVE or DDSCL_FULLSCREEN))));
  end;
end;

function DirectDrawCreateBounce(lpGUID: PGUID; out lplpDD: IDirectDraw; pUnkOuter: IUnknown): HRESULT; stdcall;
begin
  if Assigned(TrampolineDirectDrawCreate) then
  begin
    result:=TrampolineDirectDrawCreate(lpGUID, lplpDD, punkOuter);
    if not Assigned(TrampolineDXSetCooperativeLevel) then
    begin
      TrampolineDXSetCooperativeLevel := InterceptCreate(lplpDD, 17, @DXSetCooperativeLevelBounce);
    end;
  end;
end;

var
  TrampolineWSAStartup: function(wVersionRequired:word;var WSAData:TWSADATA):tOS_INT; stdcall = nil;
  Trampolinesocket:function (af:tOS_INT; t:tOS_INT; protocol:tOS_INT):TSocket;stdcall = nil;

function WSAStartupBounce(wVersionRequired:word;var WSAData:TWSADATA):tOS_INT; stdcall;
begin
  if Assigned(TrampolineWSAStartup) then
  begin
    if Config.DisableSockets then
    begin
      result:=WSASYSNOTREADY
    end else
      result:=TrampolineWSAStartup(wVersionRequired, WSAData);
  end;
end;

function socketBounce(af:tOS_INT; t:tOS_INT; protocol:tOS_INT):TSocket;stdcall;
begin
  if Assigned(Trampolinesocket) then
  begin
    if Config.DisableSockets then
    begin
      result:=INVALID_SOCKET
    end else
      result:=Trampolinesocket(af, t, protocol);
  end;
end;

var
  TrampolineD3DCompile: function(pSrcData: LPCVOID; srcDataSize: SIZE_T; x3,x4,x5,x6,x7,x8,x9,x10,x11: Pointer): HRESULT; stdcall = nil;
  TrampolineD3dIncludeOpen: function(self: Pointer; includeType: Integer; filename: Pointer; parentData: pointer; ppData: Pointer; pBytes: PCardinal): HRESULT; stdcall = nil;

function D3dIncludeOpenBounce(self: Pointer; includeType: Integer; filename: Pointer; parentData: pointer; ppData: Pointer; pBytes: PCardinal):HRESULT; stdcall;
var
  s: string;
  hash: Cardinal;
  f: File;
  size: SIZE_T;
begin
  if Assigned(TrampolineD3dIncludeOpen) then
  begin
    result:=TrampolineD3dIncludeOpen(self, includeType, filename, parentData, ppData, pBytes);

    if result = S_OK then
    begin
      if Assigned((PPointer(ppdata^)^)) then
      hash:=SuperFastHash(PPointer(ppdata)^, pBytes^);
      if Assigned(filename) then
        s:=BasePath + BaseName + '_shader_'+PChar(filename)+'.txt'
      else
        s:=BasePath + BaseName + '_shader_'+IntToHex(hash, 8)+'.txt';
      InterLockedIncrement(ShaderWritten);

      Assignfile(f, s);
      {$i-}rewrite(f,1);{$I+}
      if ioresult = 0 then
      begin
        Blockwrite(f, PPointer(ppData)^^, pBytes^);
        closefile(f);
      end;
    end;
  end;
end;

function D3DCompileBounce(pSrcData: LPCVOID; srcDataSize: SIZE_T; x3,x4,x5,x6,x7,x8,x9,x10,x11: Pointer): HRESULT; stdcall;
var
  f: File;
  s: string;
  p: Pointer;
  hash: Cardinal;
  size: SIZE_T;
begin
  if Assigned(TrampolineD3DCompile) then
  begin
    if Config.GetShaders then
    if Assigned(pSrcData) then
    begin
      hash := SuperfastHash(pSrcData, srcDataSize);

      if Assigned(x3) and (PChar(x3) <> '') then
        s:=BasePath + BaseName +'_shader_'+PChar(x3)+'_'+IntToHex(hash, 8)+'.txt'
      else
        s:=BasePath + BaseName +'_shader_'+IntToHex(hash, 8)+'.txt';
      InterLockedIncrement(ShaderWritten);

      if Config.Inject and FileExists(s) then
      begin
        LOG('D3dCompile Inject');
        Assignfile(f, s);
        {$i-}rewrite(f, 1);{$i+}
        if ioresult = 0 then
        begin
          size:=Filesize(f);
          Getmem(p, size);
          Blockread(f, p^, size);
          closefile(f);
          result:=TrampolineD3DCompile(p, size, x3, x4, x5, x6, x7, x8, x9, x10, x11);
          LOG('D3dCompile('+ExtractFilename(s)+') = '+IntToHex(NativeUInt(result), 8));
          Freemem(p);
          Exit;
        end;
      end else
      begin
        LOG('Saving shader...');
        Assignfile(f, s);
        {$i-}rewrite(f, 1);{$i+}
        if ioresult = 0 then
        begin
          Blockwrite(f, pSrcData^, srcDataSize);
          closefile(f);
        end;
      end;
    end;
    result:=TrampolineD3DCompile(pSrcData, srcDataSize, x3, x4, x5, x6, x7, x8, x9, x10, x11);
    LOG('D3dCompile('+ExtractFilename(s)+') = '+IntToHex(NativeUInt(result), 8));
  end;
end;

var
  TrampolineGetProcAddress: function(hModule:HINST; lpProcName:LPCSTR):FARPROC; stdcall = nil;
  TrampolineLoadLibraryA: function(lpDllName: LPCSTR): HINST; stdcall = nil;
  TrampolineLoadLibraryW: function(lpDllName: LPCWSTR): HINST; stdcall = nil;
  TrampolineTimeGetTime: function: DWORD; stdcall = nil;
  TrampolineGetTickCount: function: DWORD; stdcall = nil;
  TrampolineGetTickCount64: function: UInt64; stdcall = nil;
  TrampolineQueryPerformanceFrequency: function(var freq: Int64): Boolean; stdcall = nil;
  dsoundHandle: pointer = nil;


function QueryPerformanceFrequencyBounce(var freq: Int64): Boolean; stdcall;
begin
  if Assigned(TrampolineQueryPerformanceFrequency) then
  begin
    result := TrampolineQueryPerformanceFrequency(freq);

    case Config.SpeedFactor of
      1: freq:=freq * 2;
      2: freq:=freq div 2;
    end;
  end;
end;

function GetTickCountBounce: DWORD; stdcall;
begin
  if Assigned(TrampolineGetTickCount) then
  begin
    result:=TrampolineGetTickCount;
    case Config.SpeedFactor of
      1: result:=result div 2;
      2: result:=result * 2;
    end;
  end;
end;

function GetTickCount64Bounce: UInt64; stdcall;
begin
  if Assigned(TrampolineGetTickCount64) then
  begin
    result:=TrampolineGetTickCount64;
    case Config.SpeedFactor of
      1: result:=result div 2;
      2: result:=result * 2;
    end;
  end;
end;


function TimeGetTimeBounce: DWORD; stdcall;
begin
  if Assigned(TrampolineTimeGetTime) then
  begin
    result:=TrampolineTimeGetTime;
    case Config.SpeedFactor of
      1: result:=result div 2;
      2: result:=result * 2;
    end;
  end;
end;

function LoadLibraryABounce(lpDllName: LPCSTR): HINST; stdcall;
begin
  if Assigned(TrampolineLoadLibraryA) then
  begin
    result:=TrampolineLoadLibraryA(lpDllName);
    if Config.LogGetProcAddress then
    if Assigned(lpDllName) then
    begin
      RegisterLibrary(result, lpDllName);
      LOG('LoadLibraryA("'+lpDllName+'") = '+IntToHex(result, 8));
    end
    else
      LOG('LoadLibraryA(0) = '+IntToHex(result, 8));

    if Uppercase(ExtractFilename(lpDllName)) = 'DSOUND.DLL' then
    begin
      dsoundHandle := pointer(result);
    end;
  end;
end;

function LoadLibraryWBounce(lpDllName: LPCWSTR): HINST; stdcall;
begin
  if Assigned(TrampolineLoadLibraryA) then
  begin
    result:=TrampolineLoadLibraryW(lpDllName);
    if Config.LogGetProcAddress then
    if Assigned(lpDllName) then
    begin
      RegisterLibrary(result, lpDllName);
      LOG('LoadLibraryW("'+lpDllName+'") = '+IntToHex(result, 8));
    end
    else
      LOG('LoadLibraryW(0) = '+IntToHex(result, 8));

    if Uppercase(ExtractFilename(lpDllName)) = 'DSOUND.DLL' then
    begin
      dsoundHandle := pointer(result);
    end;
  end;
end;
function GetProcAddressBounce(hModule:HINST; lpProcName:LPCSTR):FARPROC;stdcall;
begin
  if Assigned(TrampolineGetProcAddress) then
  begin
    result:=TrampolineGetProcAddress(hModule, lpProcName);

    if(pointer(hModule) = dsoundHandle) then
    begin
      if ((Cardinal(lpProcName)<$10000)and((lpProcName = pointer(11) ) or (lpProcName = pointer(1)))) or
         ((Cardinal(lpProcName)>$10000) and ((lpProcName = 'DirectSoundCreate8') or (lpProcName = 'DirectSoundCreate'))) then
      begin
        TrampolineDirectSoundCreate8:=result;
        result:=@DirectSOundCreate8Bounce;
      end;
    end;

    if Config.LogGetProcAddress then
    begin
      if Cardinal(lpProcName)<$10000 then
        LOG('GetProcAddress('+GetLibraryName(hModule)+', '+IntToStr(Cardinal(lpProcName))+') = '+IntToHex(NativeUInt(result), 8))
      else
        LOG('GetProcAddress('+GetLibraryName(hModule)+', "'+lpProcName+'") = '+IntToHex(NativeUInt(result), 8));
    end;

    if Cardinal(lpProcName)>=$10000 then
    if (lpProcName = 'D3DCompile') then
    begin
      TrampolineD3DCompile:=result;
      result:=@D3DCompileBounce;
    end;

  end;
end;

var
  TrampolineExitProcess: procedure(ExitCode: UInt); stdcall;

procedure ItemHouseKeeping(data,arg:pointer);
begin
  //LOG('Housekeeping for '+TObject(data).ClassName);
  TObject(data).free;
end;

procedure ExitProcessBounce(ExitCode: UInt); stdcall;
begin
  Log('ExitProcess('+IntToStr(ExitCode)+')');
  // housekeeping
  cs.Enter;
  try
    Items.ForEachCall(ItemHouseKeeping, nil);
    Items.Clear;
  finally
    cs.Leave;
  end;
  Log('Housekeeping done, good bye!');
  if Assigned(TrampolineExitProcess) then
    TrampolineExitProcess(ExitCode);
end;

procedure StartHook(Settings: PHookSettings); stdcall;
var
  p: Pointer;
  hng: THANDLE;
begin
  if Assigned(cs) then
    Exit;

  Randomize;

  if not Assigned(Settings) then
  begin
    MessageBoxA(0, 'No parameters!', 'Hook Error', MB_ICONERROR);
    ExitProcess(-1);
    Exit;
  end;

  Config := Settings^;

  if Config.Version <> WinHookVersion then
  begin
    MessageBoxA(0, 'Incompatible Version!', 'Hook Error', MB_ICONERROR);
    ExitProcess(-1);
    Exit;
  end;

  //RegisterLibrary(LoadLibrary('kernel32.dll'), 'kernel32.dll');

  BasePath:=Config.OutputPath;
  if Length(BasePath)=0 then
    BasePath:=ExtractFilePath(Paramstr(0));
  if BasePath[Length(BasePath)]<>'\' then
    BasePath:=BasePath + '\';

  BaseName:=ExtractFileName(Paramstr(0));

  while (Length(BaseName)>0)and(BaseName[Length(BaseName)]<>'.') do
    Delete(BaseName, Length(BaseName), 1);
  Delete(BaseName, Length(BaseName), 1);

  if BaseName = '' then
    BaseName:=ExtractFileName(Paramstr(0));

  cs := TCriticalSection.Create;
  cs2 := TCriticalSection.Create;

  Items := TFPHashList.Create;
  LibNames := TFPStringHashTable.Create;

  if Config.CreateLog then
  begin
    StartLog;
    LOG('Exemusic Recorder v' + IntToHex(WinHookVersion, 8) );
    {$IFNDEF CPUX86}
    LOG('Experimental 64 bit version');
    {$ENDIF}
  end;


  if Config.TraceAll then
  begin
    LOG('EMR: Logging ALL process calls!');
    with TCallerPool.Create(1024*1024) do
      AttachEverything(paramstr(0));
  end;

  LOG('EMR: Output directory: ' + BasePath);
  LOG('EMR: Base filename ' + BaseName);

  if Config.SlowWaveWrite then
  begin
    LOG('EMR: Creating Thread for writing wave buffers slowly...');
    SlowWriterThread:=TSlowWriterThread.Create;
  end;

  LoadDirect3D9;

  TrampolineExitProcess := InterceptCreate(@ExitProcess, @ExitProcessBounce);

  if Config.DumpACM then
  begin
    hng := LoadLibrary('MSACM32.dll');
    TrampolineacmStreamOpen := InterceptCreate(GetProcAddress(hng, 'acmStreamOpen'), @acmStreamOpenBounce);
    TrampolineacmStreamClose := InterceptCreate(GetProcAddress(hng, 'acmStreamClose'), @acmStreamCloseBounce);
    TrampolineacmStreamConvert := InterceptCreate(GetProcAddress(hng, 'acmStreamConvert'), @acmStreamConvertBounce);

    //TrampolineacmDriverEnum:=InterceptCreate(GetProcAddress(hng, 'acmDriverEnum'), @acmDriverEnumBounce);
    //TrampolineacmFormatEnum:=InterceptCreate(GetProcAddress(hng, 'acmFormatEnumW'), @acmFormatEnumBounce);
    //TrampolineacmStreamPrepareHeader:=InterceptCreate(GetProcAddress(hng, 'acmStreamPrepareHeader'), @acmStreamPrepareHeaderBounce);
    //TrampolineAcmDriveropen:=InterceptCreate(GetProcAddress(hng, 'acmDriverOpen'), @acmDriverOpenBounce);
    //TrampolineAcmDriverclose:=InterceptCreate(GetProcAddress(hng, 'acmDriverClose'), @acmDriverCloseBounce);
    //TrampolineAcmMetrics:=InterceptCreate(GetProcAddress(hng, 'acmMetrics'), @acmMetricsBounce);
  end;

  TrampolineCreateFileA := InterceptCreate(@CreateFileA, @CreateFileABounce);
  TrampolineCreateFileW := InterceptCreate(@CreateFileW, @CreateFileWBounce);

  TrampolineCreateProcessA := InterceptCreate(@CreateProcessA, @CreateProcessABounce);
  TrampolineCreateProcessW := InterceptCreate(@CreateProcessW, @CreateProcessWBounce);

  TrampolineCreateProcessAsUserA := InterceptCreate(@CreateProcessAsUserA, @CreateProcessAsUserABounce);
  TrampolineCreateProcessAsUserW := InterceptCreate(@CreateProcessAsUserW, @CreateProcessAsUserWBounce);

  TrampolinewaveOutOpen := InterceptCreate(@waveOutOpen, @waveOutOpenBounce);
  TrampolinewaveOutClose := InterceptCreate(@waveOutClose, @waveOutCloseBounce);
  TrampolinewaveOutWrite := InterceptCreate(@waveOutWrite, @waveOutWriteBounce);

  TrampolineChangeDisplaySettingsA := InterceptCreate(@ChangeDisplaySettingsA, @ChangeDisplaySettingsABounce);
  TrampolineChangeDisplaySettingsW := InterceptCreate(@ChangeDisplaySettingsW, @ChangeDisplaySettingsWBounce);

  TrampolineCreateWindowExA := InterceptCreate(@CreateWindowExA, @CreateWindowExABounce);
  TrampolineCreateWindowExW := InterceptCreate(@CreateWindowExW, @CreateWindowExWBounce);

  TrampolinewglGetProcAddress := InterceptCreate(@wglGetProcAddress, @wglGetProcAddressBounce);

  TrampolineShowCursor := InterceptCreate(@ShowCursor, @ShowCursorBounce);

  // TrampolineDirectDrawCreate := InterceptCreate(@DirectDrawCreate, @DirectDrawCreateBounce);
  // TrampolineDirect3dCreate9 := InterceptCreate(@_Direct3DCreate9, @Direct3dCreate9Bounce);
  // TrampolineWSAStartup := InterceptCreate(@WSAStartup, @WSAStartupBounce);

  Trampolinesocket := InterceptCreate(@socket, @socketBounce);

  TrampolineLoadLibraryA := InterceptCreate(@LoadLibraryA, @LoadLibraryABounce);
  TrampolineLoadLibraryW := InterceptCreate(@LoadLibraryW, @LoadLibraryWBounce);
  TrampolineGetProcAddress := InterceptCreate(@GetProcAddress, @GetProcAddressBounce);

  TrampolineTimeGetTime := InterceptCreate(@timeGetTime, @TimeGetTimeBounce);
  TrampolineGetTickCount := InterceptCreate(@GetTickCount, @GetTickCountBounce);
  TrampolineGetTickCount64 := InterceptCreate(@GetTickCount64, @GetTickCount64Bounce);
  TrampolineQueryPerformanceFrequency := InterceptCreate(@QueryPerformanceFrequency, @QueryPerformanceFrequencyBounce);
end;

end.

