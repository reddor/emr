unit dllinject;

{$mode delphi}

interface

uses
  Classes, SysUtils, exereader, Windows, JwaWinType, InstDecode;

type
  { This buffer will be injected into the spawned process. This will be used to
    load a dll (target) and execute a function inside it (procname)

    See "PayloadProc" proc for more
  }
  PInjectionBuffer = ^TInjectionBuffer;
  TInjectionBuffer = record
    LoadLibrary: function(lpLibFileName:LPCSTR):HINST; stdcall; // 00
    GetProcAddr: function(hModule:HINST; lpProcName:LPCSTR):FARPROC; stdcall; // 4
    CustomData: Pointer; // 8
    target: array[0..511] of Char;  // dll path + name // 12
    procName: array[0..63] of Char; // dll proc name // 524
  end;

procedure injectLoader(target, params: string; dll, funcname: string; CustomData: Pointer; CustomDataSize: Integer; SimpleInject: Boolean = False);
function InjectDLL(PID: Cardinal; sDll, CallProc: string;CustomData: Pointer; CustomDataSize: Integer): boolean;

implementation

type
  TCallFunc = procedure(Data: Pointer); stdcall;

{ the payload function - directly copied from here into the target process. }
procedure PayloadProc(data: PInjectionBuffer); stdcall;
begin
  TCallFunc(data^.GetProcAddr(data^.LoadLibrary(@data^.target[0]), @data^.procName[0]))(data^.CustomData);
end;

function GetEntryPoint(aFilename: string): Integer;
var
  f: TExeFile;
begin
  result:=0;
  f:=TExeFile.Create;
  try
    if f.LoadFile(aFilename) then
    begin
      case f.FileType of
        fkExe32:
        begin
          result:=f.NTHeader.OptionalHeader.ImageBase + f.NTHeader.OptionalHeader.AddressOfEntryPoint;
        end;
        fkExe64:
        begin
          result:=f.NTHeader64.OptionalHeader.ImageBase + f.NTHeader64.OptionalHeader.AddressOfEntryPoint;
        end;
      end;
    end;
  finally
    f.Free;
  end;
end;

function SizeOfProc(Proc: pointer): longword;
var
  Length: longword;
  Inst: TInstruction;
begin
  FillChar(Inst, SizeOf(Inst), 0);
  {$ifdef CPUX86}
  Inst.Archi:=CPUX32;
  {$ELSE}
  Inst.Archi:=CPUX64;
  {$ENDIF}
  Inst.Addr:=Proc;
  Result := 0;
  repeat
    Length := DecodeInst(@Inst);
    Inst.Addr := Inst.NextInst;
    Inc(Result, Length);
    if Inst.OpType = otRET then
      Break;
  until Length = 0;
end;

function InjectDLL(PID: Cardinal; sDll, CallProc: string; CustomData: Pointer;
  CustomDataSize: Integer): boolean;
var
  hThread: THandle;
  pMod, pCode: Pointer;
  dWritten: NativeUInt;
  ThreadID: Cardinal;
  buffer: TInjectionBuffer;
  i: Integer;
begin
  Result := False;
  Fillchar(buffer, SizeOF(TInjectionBuffer), #0);
  dWritten:=0;

  if PID <> INVALID_HANDLE_VALUE then
  begin
    // fill payload structure
    buffer.LoadLibrary:=GetProcAddress(GetModuleHandle(PChar('KERNEL32.dll')), 'LoadLibraryA');
    buffer.GetProcAddr:=GetProcAddress(GetModuleHandle(PChar('KERNEL32.dll')), 'GetProcAddress');
    for i:=1 to Length(sDll) do
      buffer.target[i-1]:=sDll[i];
    for i:=1 to Length(CallProc) do
      buffer.procName[i-1]:=CallProc[i];

    result:=True;

    // allocate memory for custom data & copy if required
    if Assigned(CustomData) then
    begin
      buffer.CustomData:=VirtualAllocEx(PID, nil, CustomDataSize, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);

      if WriteProcessMemory(PID, buffer.CustomData, CustomData, CustomDataSize, dWritten) then
        Result := result and TRUE;
    end else
      buffer.CustomData:=nil;

    // allocate memory & copy payload proc
    pCode := VirtualAllocEx(PID, nil, SizeOfProc(@PayloadProc), MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if WriteProcessMemory(PID, pCode, @PayloadProc, SizeOfProc(@PayloadProc), dWritten) then
      Result := result and TRUE;

    // allocate memory & copy payload buffer
    pMod := VirtualAllocEx(PID, nil, SizeOf(TInjectionBuffer), MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if WriteProcessMemory(PID, pMod, @Buffer, SizeOf(TInjectionBuffer), dWritten) then
      Result := result and TRUE;

    if result then
    begin
      ThreadID:=0;
      hThread := CreateRemoteThread(PID, nil, 0, pCode, pMod, 0, ThreadID);
      WaitForSingleObject(hThread, INFINITE);
      CloseHandle(hThread);
    end;
  end;
end;

procedure injectLoader(target, params: string; dll, funcname: string;
  CustomData: Pointer; CustomDataSize: Integer; SimpleInject: Boolean);
var
  StartupInfo: TSTARTUPINFO;
  ProcessInformation: PROCESS_INFORMATION;
  hProcess: THANDLE;
  entry: PtrUInt;
  oldProtect: DWORD;
  bytesRead: PTRUINT;
  original,
  patch: array[0..1] of Byte;
  i: Integer;
  AContext: CONTEXT;
  f: TExeFile;
  IsRelocatable: Boolean;
  s: string;
begin
  f:=TExeFile.Create;
  IsRelocatable:=False;
  bytesRead:=0;
  try
    if f.LoadFile(target) then
    begin
      IsRelocatable:=False;
      for i:=0 to f.SectionCount-1 do
        if (f.Sections[i].Name='.reloc')and(f.Sections[i].NumberOfRelocations>0) then
          IsRelocatable:=True;

      case f.FileType of
        fkExe32:
        begin
          entry:=f.NTHeader.OptionalHeader.ImageBase + f.NTHeader.OptionalHeader.AddressOfEntryPoint;
          {$ifndef CPUX86}
          raise Exception.Create('This is a 32 bit executable - please use the 32 bit flavour of this program!');
          {$endif}
        end;
        fkExe64:
        begin
          entry:=f.NTHeader64.OptionalHeader.ImageBase + f.NTHeader64.OptionalHeader.AddressOfEntryPoint;
          {$ifdef CPUX86}
          raise Exception.Create('This is a 64 bit executable - please use the 64 bit flavour of this program!');
          {$endif}
        end;
        fkExeArm:
        begin
          raise Exception.Create('LOL Windows ARM Binary!');
        end;
        else
          raise Exception.Create('Executable required');
      end;
    end else
      raise Exception.Create(f.Status);
  finally
    f.Free;
  end;

  Fillchar(StartupInfo, SizeOf(StartupInfo), #0);
  FIllchar(ProcessInformation, SizeOf(ProcessInformation), #0);
  StartupInfo.cb:=SizeOf(StartupInfo);

  // change to same directory as target
  chdir(ExtractFilePath(target));   
  
  // create new process with target

  s:= target + ' ' + params;
  if (CreateProcessA(nil, PChar(s), nil, nil, False, CREATE_SUSPENDED, nil, nil, StartupInfo, ProcessInformation)) then
  begin
    hProcess:=ProcessInformation.hProcess;

    try
      {$IFDEF CPUX86}
      if SimpleInject or IsRelocatable then
      {$ENDIF}
      begin
        { just inject while running without all that fancy patching...
          the more I test this, the more reasonable this approach seems - it just
          works, no problems with ASLR/relocatable images.. but tested with win10 only.

          I think the whole reason behind patching the entry point was to make
          sure the process was properly initialized so a dll can be injected without
          interfering with the rest of the process. }
        if not InjectDLL(hProcess, dll, funcname, CustomData, CustomDataSize) then
        begin
          //if not InjectLibrary2(hProcess, dll, funcname, CustomData, CustomDataSize) then
          raise Exception.Create('Could not inject dll');
        end;
        ResumeThread(ProcessInformation.hThread);
        Exit;
      end;

      {$IFDEF CPUX86}
      if not VirtualProtectEx(hProcess, LPVOID(entry), 2, PAGE_EXECUTE_READWRITE, @oldProtect)  then
      begin
        raise Exception.Create('Cannot unprotect entrypoint (relocatable? ALSR?)');
      end;

      // save original entry point instructions
      if not ReadProcessMemory(hProcess, LPVOID(entry), @original[0], 2, bytesRead) then
      begin
        raise Exception.Create('Read from process memory failed: '+SysErrorMessage(GetLastError));
      end;

      // patch entry point with jmp -2 => force process into an infinite loop once it's
      // reached it's entry point
      patch[0]:=$EB;
      patch[1]:=$FE;
      if not WriteProcessMemory(hProcess, Pointer(entry), @patch[0], 2, @bytesRead) then
      begin
        raise Exception.Create('Write to process memory failed: '+SysErrorMessage(GetLastError));
      end;

      // resume process and wait a reasonable time until it has instruction pointer is at entry point
      ResumeThread(ProcessInformation.hThread);

      for i:=0 to 49 do
      begin
        Sleep(100);
        AContext.ContextFlags:=CONTEXT_CONTROL;
        GetThreadContext(ProcessInformation.hThread, AContext);

        if AContext.Eip = Entry then
          Break;
      end;

      if AContext.Eip <> Entry then
      begin
        // wait timeout, this happens with ASLR
      end;

      // finally, inject the payload

      if not InjectDLL(hProcess, dll, funcname, CustomData, CustomDataSize) then
      begin
        //if not InjectLibrary2(hProcess, dll, funcname, CustomData, CustomDataSize) then
        raise Exception.Create('Could not inject dll');
      end;

      // suspend the thread again
      SuspendThread(ProcessInformation.hThread);

      // restore original entry point instructions
      if not WriteProcessMemory(hProcess, Pointer(entry), @original[0], 2, @bytesRead) then
      begin
        // if this fails, it usually means that the process has terminated in the meantime
        // (this e.g. happens when the injected dll throws an error and quits)
        // raise Exception.Create('Write to process memory (2) failed: '+SysErrorMessage(GetLastError));
      end;

      // resume process
      ResumeThread(ProcessInformation.hThread);
      {$ENDIF}
    except
      // terminate process and throw again
      TerminateProcess(hProcess, UINT(-1));
      raise;
    end;
  end else
    raise Exception.Create('Could not create process: '+SysErrorMessage(GetLastError));
end;

end.

