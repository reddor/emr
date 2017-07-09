unit apitrace;

{$mode delphi}

interface

uses
  Windows, Classes, SysUtils, SyncObjs, exereader;


type

  { TCallerPool }

  TCallerPool = class
  private
    FMaxFunctions,
    FCount: Integer;
    FMemory: PByteArray;
    FThreads: array of record id: DWORD; RefCount: Integer; end;
    FCS: TCriticalSection;
    FFiles: array of string;
  public
    constructor Create(AMaxFunctions: Integer);
    destructor Destroy; override;

    function PushIt(ThreadID: DWORD): Integer;
    procedure PopIt(ThreadID: DWORD);
    procedure AttachEverything(AFilename: string);
    function AttachToProc(Proc: Pointer; Name: string): Boolean;
  end;

procedure callproc(foo: Integer); assembler;

function GenerateProc86(Target: PByteArray; Ident: Integer; LogCall, OriginalProc: Pointer): Pointer;

implementation

uses
  winhooks,
  DDetours;

var
  finale: Boolean;
  Pool: TCallerPool;
  FunctionNames: array[0..1024*1024-1] of ansistring;
  Hnkh: Cardinal;

const
  ProcSize = 32;

function GenerateProc86(Target: PByteArray; Ident: Integer; LogCall, OriginalProc: Pointer): Pointer;
var
  Ofs: Integer;
begin
  (*
  Writeln('Target ', IntToHex(Cardinal(Target), 8), ' Ident ', IntToHex(Cardinal(Ident), 8), ' LogCall ', IntToHex(Cardinal(LogCall), 8),
          'OriginalProc ', IntToHex(Cardinal(OriginalProc), 8));     *)
  Ofs := 0;
  Target[Ofs] := $60;  // pusha
  Inc(Ofs, 1);
  Target[Ofs] := $68;  // push ident
  Inc(Ofs, 1);

  // Target[Ofs] := $C3;  // int 3
  // Inc(Ofs, 1);

  PInteger(@Target[Ofs])^ := Ident; // 2 3 4 5
  Inc(Ofs, 4);

  (*
  Target[Ofs] := $9A;
  Inc(Ofs);
  PPointer(@Target[Ofs])^ := LogCall;
  Inc(Ofs, 4);      *)

  Target[Ofs] := $e8; // call log
  Inc(Ofs, 1);
  // 7 8 9 10
  PInteger(@Target[Ofs])^ := PtrUInt(LogCall) - PtrUInt(@Target[Ofs+4]);
  Inc(Ofs, 4);

  Target[Ofs] := $61; // popa
  Inc(Ofs);

  (*
  Target[Ofs] := $68; // push addr
  Inc(Ofs);
  PPointer(@Target[Ofs])^ := OriginalProc;
  Inc(Ofs, 4);
  Target[Ofs] := $cb; // $9A;
  Inc(Ofs); *)

  Target[Ofs] := $e9; // call original proc
  Inc(Ofs);
  // 13 14 15 16
  PInteger(@Target[Ofs])^ := PtrUInt(OriginalProc) - PtrUInt(@Target[Ofs+4]);
  Inc(Ofs, 4);

  Target[Ofs] := $cb; // ret
  Inc(Ofs, 1);


  // fuck yeah alignment!
  while Ofs < ProcSize do
  begin
    Target[Ofs] := $90;
    inc(Ofs);
  end;

  result:=@Target[0];
end;

procedure logcall(id: Cardinal); stdcall;
var
  i, j: Integer;
  thrid: DWORD;
begin
  if finale then
    Exit;

  try
  LOG(FunctionNames[Cardinal(id mod Length(FunctionNames))]);
  except
  end;
  (*  Pool.FCS.Enter;
  try
    Inc(Hnkh);
    if Hnkh = 1 then
    begin
      if id < Length(FunctionNames) then
        Writeln(FunctionNames[id])
      else
        Writeln('CORRUPTED CORE');
    end;
    Dec(Hnkh);
  finally
    Pool.FCS.Leave;
  end; *)
end;

procedure fakeproc(bar: Integer); stdcall;
begin
  // Writeln('I AM ORIGINAL PROC ',bar);
end;

procedure callproc(foo: Integer); stdcall; assembler;
asm
  pushad
  push $FF00FF1
  mov eax, logcall
  call logcall
  popad
  jmp fakeproc
//  push eip
  db $ff, $15, $01, $02, $03, $04
end;

{ TCallerPool }

destructor TCallerPool.Destroy;
begin
  inherited Destroy;
end;

function TCallerPool.PushIt(ThreadID: DWORD): Integer;
var
  i: Integer;
begin
  FCS.Enter;
  for i:=0 to Length(FThreads)-1 do
  begin
    if FThreads[i].id = ThreadID then
    begin
      result:=FThreads[i].RefCount;
      Inc(FThreads[i].RefCount);
      Exit;
    end;
  end;
  i:=Length(FThreads);
  Setlength(FThreads, i+1);
  FThreads[i].id := ThreadID;
  FThreads[i].RefCount:=1;
  result := 0;
  FCS.Leave;
end;

procedure TCallerPool.PopIt(ThreadID: DWORD);
var
  i: Integer;
begin
  FCS.Enter;
  for i:=0 to Length(FThreads)-1 do
  if FThreads[i].id = ThreadID then
  begin
    if FThreads[i].RefCount>0 then
      Dec(FThreads[i].RefCount);
  end;
end;

var
  wglGetProcAddrBounce: function(aProcName: PChar): Pointer; stdcall = nil;
  GetProcAddressBounce: function(Handle: THandle; ProcName: PChar): Pointer; stdcall = nil;


function TrampolineGetProcAddress(Handle: THandle; ProcName: PChar): Pointer; stdcall;
var
  name: string;
begin

  result := GetProcAddressBounce(Handle, ProcName);
  if Assigned(result) then
  begin
    Pool.FCS.Enter;
    Setlength(Name, 1000);
    Setlength(Name, GetModuleFileName(Handle, @name[1], Length(Name)));

    if Cardinal(ProcName)>$10000 then
      LOG('GetProcAddress("'+Name+ '", "'+ ProcName+'")')
    else
      LOG('GetProcAddress("'+ Name+'", '+ IntToStr(Cardinal(ProcName))+')');

    Name := lowercase(Extractfilename(Name));

    if (Name = 'kernel32.dll')or(Name = 'kernelbase.dll')or(Name = 'ntdll.dll')or(Name = 'gdi32.dll')or(Name = 'user32.dll')or
       (Name = 'msvbvm60.dll')or(Name = 'oleaut32.dll') then
    begin
      Pool.FCS.Leave;
      Exit;
    end;


    if Cardinal(ProcName)<$10000 then
    begin
      Name := Name + '.' +IntToHex(Cardinal(ProcName), 4);
    end else
    begin
      Name := Name + '.' + ProcName;
      if (name = 'oleaut32.dll.varcmp') or (name = 'msvbvm60.dll.__vbavaradd') or
         (name = 'oleaut32.dll.varadd') or (name = 'msvbvm60.dll.__vbavarmove') or
         (name = 'msvbvm60.dll.__vbavartstgt') then
      begin
        Pool.FCS.Leave;
        Exit;
      end;
    end;
    Pool.FCS.Leave;
    Pool.AttachToProc(result, Name);
  end;
end;

function TrampolinewglGetProcAddr(aProcName: PChar): Pointer; stdcall;
begin
  if Assigned(wglGetProcAddrBounce) then
  begin
    Pool.FCS.Enter;
    LOG('wglGetProcAddr('+ aProcName+ ')');
    Pool.FCS.Leave;
    result := wglGetProcAddrBounce(aProcName);
    if Assigned(result) then
      Pool.AttachToProc(result, 'opengl32.dll.'+aProcName);
  end;
end;

constructor TCallerPool.Create(AMaxFunctions: Integer);
begin
  if Assigned(Pool) then
    raise Exception.Create('only a single instance allowed');

  Pool := Self;
  FCount := 0;
  FMaxFunctions := AMaxFunctions;

  FMemory := VirtualAlloc(nil, AMaxFunctions * 20, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);

  if not Assigned(FMemory) then
  raise Exception.Create('Could not allocate memory');

  GetProcAddressBounce :=  InterceptCreate(GetProcAddress(GetModuleHandle('kernel32.dll'), 'GetProcAddress'), @TrampolineGetProcAddress);
  // Setlength(FunctionNames, AMaxFunctions);
  FCS := TCriticalSection.Create;
end;


procedure TCallerPool.AttachEverything(AFilename: string);
var
  el: TImportFuncEntry;
  i, j: Integer;
  Exe: TExefile;
  h: THandle;
  s: string;
begin
  s:=Lowercase(ExtractFileName(AFilename));

  if (s = 'kernel32.dll')or(s = 'kernelbase.dll')or(s = 'ntdll.dll')or(s = 'gdi32.dll')or(s = 'user32.dll') then
    Exit;

  for i:=0 to Length(FFiles)-1 do
  if FFiles[i] = s then
   Exit;

  i:=Length(FFiles);
  Setlength(FFiles,i+1);
  FFiles[i] := s;

  Exe := TExeFile.Create;
  if Exe.LoadFile(AFilename) then
  begin
    if Exe.ImportCount>0 then
    begin
      // Writeln('DLL imports: ', Exe.ImportCount);
      for i:=0 to Exe.ImportCount-1 do
      begin
        // Writeln('  ', Exe.Imports[i].DLLName);
        h:=LoadLibrary(PChar(Exe.Imports[i].DLLName));
        setlength(s, 1000);
        Setlength(s, GetModuleFileName(h, @s[1], 1000));
        s := Lowercase(ExtractFileName(Exe.Imports[i].DLLName));
        if (s = 'kernel32.dll')or(s = 'kernelbase.dll')or(s = 'ntdll.dll')or(s = 'gdi32.dll')or(s = 'user32.dll') then
        begin

        end else
        for j:=0 to Exe.Imports[i].Count-1 do
        begin
          el:=Exe.Imports[i].Entries[j];
          (*
          if el.IsOrdinal then
          begin
            // Writeln('    ', IntToHex(el.Ordinal, 4));
            AttachToProc(GetProcAddress(h, Pointer(el.Ordinal)), Exe.Imports[i].DLLName + '.'+IntToHex(el.Ordinal, 4))
          end
          else *)
          begin
            (*
            Writeln('    ', el.Name);
            if (el.Name <> 'CloseHandle')and(el.Name <> 'FlushInstructionCache')and(el.Name <> 'GetCurrentProcess') and
               (el.Name <> 'ResumeThread')and(el.Name <> 'VirtualProtect')and(el.Name <> 'TerminateThread')and
               (el.Name <> 'TlsAlloc') and (el.Name <> 'GetCurrentProcessId')and(el.Name <> 'GetCurrentThreadId')and
               (el.Name <> 'SuspendThread') and (el.Name <> 'ReadProcessMemory') and (el.Name <> 'WriteProcessMemory')and
               (el.Name <> 'VirtualAlloc') and (el.Name <> 'WriteFile') and (el.Name <> 'EnterCriticalSection')and
               (el.Name <> 'LeaveCriticalSection') then *)
            if (Exe.Imports[i].DLLName ='opengl32.dll') and (el.Name = 'wglGetProcAddress') then
            begin
              wglGetProcAddrBounce := InterceptCreate(GetProcAddress(h, PChar(el.Name)), @TrampolinewglGetProcAddr);
            end else
            begin
              //Write('.');
              GetProcAddress(h, PChar(el.Name));
              //Writeln('!');
            end;
  //          AttachToProc(GetProcAddress(h, PChar(el.Name)), Exe.Imports[i].DLLName + '.'+el.Name);
          end;
        end;
        // AttachEverything(s);

      end;
    end;
  end;
  Exe.Free;
end;

function TCallerPool.AttachToProc(Proc: Pointer; Name: string): Boolean;
var
  p: Pointer;
  i: Integer;
begin
  FCS.Enter;

  for i:=0 to FCount-1 do
  if FunctionNames[i] = Name then
  begin
    result := False;
    FCS.Leave;
    Exit;
  end;

  try
    if FCount < FMaxFunctions then
    begin
      FunctionNames[FCount]:=lowercase(Extractfilename(Name));
      GenerateProc86(@FMemory[FCount * ProcSize], FCount, @logcall, nil);
      try
        p := InterceptCreate(Proc, @FMemory[FCount * ProcSize]);
        GenerateProc86(@FMemory[FCount * ProcSize], FCount, @logcall, p);
        Inc(FCount);
        result := True;
      except
        result := False;
      end;
    end else
    begin
      LOG('trolololol');
      result := False;
    end;
  finally
    FCS.Leave;
  end;
end;

initialization
finale := False;
finalization
finale := True;
end.

