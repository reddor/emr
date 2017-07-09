unit afxCodeHook;
{
  Delphi Hooking Library by Aphex  //Delphiע���ļ��� By Aphex
  http://www.iamaphex.cjb.net/
  unremote@knology.net
}

{$IMAGEBASE $13140000}

interface

uses
  SysUtils,
  Windows; 
 
function SizeOfCode(Code: pointer): dword; 
function SizeOfProc(Proc: pointer): dword; 
 
function InjectString(Process: LongWord; Text: pchar): Pointer; //����ԭ����Pchar 
function InjectMemory(Process: LongWord; Memory: pointer; Len: dword): pointer; 
function InjectThread(Process: dword; Thread: pointer; Info: pointer; InfoLen: dword; Results: boolean): THandle; 
function InjectLibrary(Process: LongWord; ModulePath: string): boolean; overload; 
function InjectLibrary(Process: LongWord; Src: pointer): boolean; overload; 
function InjectExe(Process: LongWord; EntryPoint: pointer): boolean; 
function UninjectLibrary(Process: LongWord; ModulePath: string): boolean; 
 
function CreateProcessEx(lpApplicationName: pchar; lpCommandLine: pchar; lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: boolean; dwCreationFlags: longword; lpEnvironment: pointer; lpCurrentDirectory: pchar; const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation; ModulePath:  string): boolean; overload; 
function CreateProcessEx(lpApplicationName: pchar; lpCommandLine: pchar; lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: boolean; dwCreationFlags: longword; lpEnvironment: pointer; lpCurrentDirectory: pchar; const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation; Src: pointer): boolean; overload; 
 
function HookCode(TargetModule, TargetProc: string; NewProc: pointer; var OldProc: pointer): boolean; 
function UnhookCode(OldProc: pointer): boolean; 
 
function DeleteFileEx(FilePath: pchar): boolean; 
function DisableSFC: boolean; 
 
implementation 
 
type 
  TModuleList = array of cardinal; 
 
  PImageImportDescriptor = ^TImageImportDescriptor; 
  TImageImportDescriptor = packed record 
    OriginalFirstThunk: longword; 
    TimeDateStamp: longword; 
    ForwarderChain: longword; 
    Name: longword; 
    FirstThunk: longword; 
  end; 
 
  PImageBaseRelocation = ^TImageBaseRelocation; 
  TImageBaseRelocation = packed record 
    VirtualAddress: cardinal; 
    SizeOfBlock: cardinal; 
  end; 
 
  TDllEntryProc = function(hinstDLL: HMODULE; dwReason: longword; lpvReserved: pointer): boolean; stdcall; 
 
  TStringArray = array of string; 
 
  TLibInfo = record 
    ImageBase: pointer; 
    ImageSize: longint; 
    DllProc: TDllEntryProc; 
    DllProcAddress: pointer; 
    LibsUsed: TStringArray; 
  end; 
 
  PLibInfo = ^TLibInfo; 
  Ppointer = ^pointer; 
 
  TSections = array [0..0] of TImageSectionHeader; 
 
const 
  IMPORTED_NAME_OFFSET = $00000002; 
  IMAGE_ORDINAL_FLAG32 = $80000000; 
  IMAGE_ORDINAL_MASK32 = $0000FFFF; 
 
  Opcodes1: array [0..255] of word = 
  ( 
    (16913),(17124),(8209),(8420),(33793),(35906),(0),(0),(16913),(17124),(8209),(8420),(33793),(35906),(0),(0),(16913), 
    (17124),(8209),(8420),(33793),(35906),(0),(0),(16913),(17124),(8209),(8420),(33793),(35906),(0),(0),(16913), 
    (17124),(8209),(8420),(33793),(35906),(0),(32768),(16913),(17124),(8209),(8420),(33793),(35906),(0),(32768),(16913), 
    (17124),(8209),(8420),(33793),(35906),(0),(32768),(529),(740),(17),(228),(1025),(3138),(0),(32768),(24645), 
    (24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(69), 
    (69),(69),(69),(69),(69),(69),(69),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(24645),(0), 
    (32768),(228),(16922),(0),(0),(0),(0),(3072),(11492),(1024),(9444),(0),(0),(0),(0),(5120), 
    (5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(5120),(1296), 
    (3488),(1296),(1440),(529),(740),(41489),(41700),(16913),(17124),(8209),(8420),(17123),(8420),(227),(416),(0), 
    (57414),(57414),(57414),(57414),(57414),(57414),(57414),(32768),(0),(0),(0),(0),(0),(0),(32768),(33025), 
    (33090),(769),(834),(0),(0),(0),(0),(1025),(3138),(0),(0),(32768),(32768),(0),(0),(25604), 
    (25604),(25604),(25604),(25604),(25604),(25604),(25604),(27717),(27717),(27717),(27717),(27717),(27717),(27717),(27717),(17680), 
    (17824),(2048),(0),(8420),(8420),(17680),(19872),(0),(0),(2048),(0),(0),(1024),(0),(0),(16656), 
    (16800),(16656),(16800),(33792),(33792),(0),(32768),(8),(8),(8),(8),(8),(8),(8),(8),(5120), 
    (5120),(5120),(5120),(33793),(33858),(1537),(1602),(7168),(7168),(0),(5120),(32775),(32839),(519),(583),(0), 
    (0),(0),(0),(0),(0),(8),(8),(0),(0),(0),(0),(0),(0),(16656),(416) 
  ); 
 
  Opcodes2: array [0..255] of word = 
  ( 
    (280),(288),(8420),(8420),(65535),(0),(0),(0),(0),(0),(65535),(65535),(65535),(272),(0),(1325),(63), 
    (575),(63),(575),(63),(63),(63),(575),(272),(65535),(65535),(65535),(65535),(65535),(65535),(65535),(16419), 
    (16419),(547),(547),(65535),(65535),(65535),(65535),(63),(575),(47),(575),(61),(61),(63),(63),(0), 
    (32768),(32768),(32768),(0),(0),(65535),(65535),(65535),(65535),(65535),(65535),(65535),(65535),(65535),(65535),(8420), 
    (8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(8420),(16935), 
    (63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(63),(237), 
    (237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(101),(237),(1261), 
    (1192),(1192),(1192),(237),(237),(237),(0),(65535),(65535),(65535),(65535),(65535),(65535),(613),(749),(7168), 
    (7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(7168),(16656), 
    (16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(16656),(0), 
    (0),(32768),(740),(18404),(17380),(49681),(49892),(0),(0),(0),(17124),(18404),(17380),(32),(8420),(49681), 
    (49892),(8420),(17124),(8420),(8932),(8532),(8476),(65535),(65535),(1440),(17124),(8420),(8420),(8532),(8476),(41489), 
    (41700),(1087),(548),(1125),(9388),(1087),(33064),(24581),(24581),(24581),(24581),(24581),(24581),(24581),(24581),(65535), 
    (237),(237),(237),(237),(237),(749),(8364),(237),(237),(237),(237),(237),(237),(237),(237),(237), 
    (237),(237),(237),(237),(237),(63),(749),(237),(237),(237),(237),(237),(237),(237),(237),(65535), 
    (237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(237),(0) 
  ); 
 
  Opcodes3: array [0..9] of array [0..15] of word = 
  ( 
    ((1296),(65535),(16656),(16656),(33040),(33040),(33040),(33040),(1296),(65535),(16656),(16656),(33040),(33040),(33040),(33040)), 
    ((3488),(65535),(16800),(16800),(33184),(33184),(33184),(33184),(3488),(65535),(16800),(16800),(33184),(33184),(33184),(33184)), 
    ((288),(288),(288),(288),(288),(288),(288),(288),(54),(54),(48),(48),(54),(54),(54),(54)), 
    ((288),(65535),(288),(288),(272),(280),(272),(280),(48),(48),(0),(48),(0),(0),(0),(0)), 
    ((288),(288),(288),(288),(288),(288),(288),(288),(54),(54),(54),(54),(65535),(0),(65535),(65535)), 
    ((288),(65535),(288),(288),(65535),(304),(65535),(304),(54),(54),(54),(54),(0),(54),(54),(0)), 
    ((296),(296),(296),(296),(296),(296),(296),(296),(566),(566),(48),(48),(566),(566),(566),(566)), 
    ((296),(65535),(296),(296),(272),(65535),(272),(280),(48),(48),(48),(48),(48),(48),(65535),(65535)), 
    ((280),(280),(280),(280),(280),(280),(280),(280),(566),(566),(48),(566),(566),(566),(566),(566)), 
    ((280),(65535),(280),(280),(304),(296),(304),(296),(48),(48),(48),(48),(0),(54),(54),(65535)) 
  ); 
 
function SaveOldFunction(Proc: pointer; Old: pointer): longword; forward; 
function GetProcAddressEx(Process: LongWord; lpModuleName, lpProcName: pchar): pointer; forward; 
function MapLibrary(Process: LongWord; Dest, Src: pointer): TLibInfo; forward; 
 
function SizeOfCode(Code: pointer): longword; 
var 
  Opcode: word; 
  Modrm: byte; 
  Fixed, AddressOveride: boolean; 
  Last, OperandOveride, Flags, Rm, Size, Extend: longword; 
begin 
  try 
    Last := longword(Code); 
    if Code <> nil then 
    begin 
      AddressOveride := False; 
      Fixed := False; 
      OperandOveride := 4; 
      Extend := 0; 
      repeat 
        Opcode := byte(Code^); 
        Code := pointer(longword(Code) + 1); 
        if Opcode = $66 then 
        begin 
          OperandOveride := 2; 
        end 
        else if Opcode = $67 then 
        begin 
          AddressOveride := True; 
        end 
        else 
        begin 
          if not ((Opcode and $E7) = $26) then 
          begin 
            if not (Opcode in [$64..$65]) then 
            begin 
              Fixed := True; 
            end; 
          end; 
        end; 
      until Fixed; 
      if Opcode = $0f then 
      begin 
        Opcode := byte(Code^); 
        Flags := Opcodes2[Opcode]; 
        Opcode := Opcode + $0f00; 
        Code := pointer(longword(Code) + 1); 
      end 
      else 
      begin 
        Flags := Opcodes1[Opcode]; 
      end; 
      if ((Flags and $0038) <> 0) then 
      begin 
        Modrm := byte(Code^); 
        Rm := Modrm and $7; 
        Code := pointer(longword(Code) + 1); 
        case (Modrm and $c0) of 
          $40: Size := 1; 
          $80: 
            begin 
              if AddressOveride then 
              begin 
                Size := 2; 
              end 
              else 
                Size := 4; 
              end; 
          else 
          begin 
            Size := 0; 
          end; 
        end; 
        if not (((Modrm and $c0) <> $c0) and AddressOveride) then 
        begin 
          if (Rm = 4) and ((Modrm and $c0) <> $c0) then 
          begin 
            Rm := byte(Code^) and $7; 
          end; 
          if ((Modrm and $c0 = 0) and (Rm = 5)) then 
          begin 
            Size := 4; 
          end; 
          Code := pointer(longword(Code) + Size); 
        end; 
        if ((Flags and $0038) = $0008) then 
        begin 
          case Opcode of 
            $f6: Extend := 0; 
            $f7: Extend := 1; 
            $d8: Extend := 2; 
            $d9: Extend := 3; 
            $da: Extend := 4; 
            $db: Extend := 5; 
            $dc: Extend := 6; 
            $dd: Extend := 7; 
            $de: Extend := 8; 
            $df: Extend := 9; 
          end; 
          if ((Modrm and $c0) <> $c0) then 
          begin 
            Flags := Opcodes3[Extend][(Modrm shr 3) and $7]; 
          end 
          else 
          begin 
            Flags := Opcodes3[Extend][((Modrm shr 3) and $7) + 8]; 
          end; 
        end; 
      end; 
      case (Flags and $0C00) of 
        $0400: Code := pointer(longword(Code) + 1); 
        $0800: Code := pointer(longword(Code) + 2); 
        $0C00: Code := pointer(longword(Code) + OperandOveride); 
        else 
        begin 
          case Opcode of 
            $9a, $ea: Code := pointer(longword(Code) + OperandOveride + 2); 
            $c8: Code := pointer(longword(Code) + 3); 
            $a0..$a3: 
              begin 
                if AddressOveride then 
                begin 
                  Code := pointer(longword(Code) + 2) 
                end 
                else 
                begin 
                  Code := pointer(longword(Code) + 4); 
                end; 
              end; 
          end; 
        end; 
      end; 
    end; 
    Result := longword(Code) - Last; 
  except 
    Result := 0; 
  end; 
end; 
 
function SizeOfProc(Proc: pointer): longword; 
var 
  Length: longword; 
begin 
  Result := 0; 
  repeat 
    Length := SizeOfCode(Proc); 
    Inc(Result, Length); 
    if ((Length = 1) and (byte(Proc^) = $C3)) then Break; 
    Proc := pointer(longword(Proc) + Length); 
  until Length = 0; 
end; 
                                                              //ע�ⷵ��ֵ�Ƿ�������? 
function InjectString(Process: LongWord; Text: pchar): Pointer;//��ָ��������ע���ַ��� 
var 
  BytesWritten: longword; 
begin 
  Result := VirtualAllocEx(Process, nil, Length(Text) + 1, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);//��Ŀ������п��ٿռ� 
  WriteProcessMemory(Process, Result, Text, Length(Text) + 1, BytesWritten);//��Ŀ�������д���ַ��� 
end; 
 
function InjectMemory(Process: LongWord; Memory: pointer; Len: longword): pointer;//��Ŀ�������ע���Զ�����Ϣ(���Զ���ṹ,ָ���) 
var 
  BytesWritten: longword; 
begin 
  Result := VirtualAllocEx(Process, nil, Len, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);//��Ŀ������п��ٿռ� 

  WriteProcessMemory(Process, Result, Memory, Len, BytesWritten);//��Ŀ�������д����Ϣ
end; 
 
function InjectThread(Process: longword; Thread: pointer; Info: pointer; InfoLen: longword; Results: boolean): THandle; 
var                                  //ע���̺߳��� 
  pThread, pInfo: pointer; 
  BytesRead, TID: longword; 
begin 
  pInfo := InjectMemory(Process, Info, InfoLen);//��ָ�����ͱ���Infoע�뵽Ŀ���ֳ���,���ڴ���Զ���̵߳Ĳ��� 
  pThread := InjectMemory(Process, Thread, SizeOfProc(Thread)); //��ָ�����ͱ���Threadע�뵽Ŀ�������,����Զ�̴����̵߳���ڵ� 
  Result := CreateRemoteThread(Process, nil, 0, pThread, pInfo, 0, TID);//����Զ���߳�
  if results then
  if Result<>0 then  //�������ֵ��Ϊ0
  begin 
    WaitForSingleObject(Result, INFINITE); //�ȴ�Զ���߳�ִ����� 
    ReadProcessMemory(Process, pInfo, Info, InfoLen, BytesRead);  //��ȡԶ���̵߳�ִ�н�� 
  end else                                                            //��GetExitCodeThread()���ܻ����һ�
  MessageBoxA(0, PChar(SysErrorMessage(GetLastError)), '', 0);
end;
 
function InjectLibrary(Process: LongWord; ModulePath: string): boolean;//ע��һ��DLL��ָ��������(ModulePath����ָ��DLL�ļ���·��) 
type 
  TInjectLibraryInfo = record //�����Զ���ṹ���ڱ���ע��DLL��Ϣ 
    pLoadLibrary: pointer;//ָ��Ҫע���DLL�ļ�·�� 
    lpModuleName: pointer;//ָ��ϵͳAPI����LoadLibrary�ĵ�ַ 
    pSleep: pointer;      //ָ��ϵͳAPI����Sleep�ĵ�ַ 
  end; 
var 
  InjectLibraryInfo: TInjectLibraryInfo; //����TInjectLibraryInfo���͵ı��� 
  Thread: THandle;                       //����Thread�������ڱ���ע�뵽Ŀ������е��߳̾�� 
 
  procedure InjectLibraryThread(lpParameter: pointer); stdcall; //��������Զ��ע��DLL�Ĺ��� 
  var 
    InjectLibraryInfo: TInjectLibraryInfo; //����TInjectLibraryInfo���͵ı��� 
  begin 
    InjectLibraryInfo := TInjectLibraryInfo(lpParameter^); //�����ݽ����Ĳ���ת����TInjectLibraryInfo���� 
    asm                             //ʹ��Delphi�е���Ƕ��� 
      push InjectLibraryInfo.lpModuleName //��Ҫע���DLL·����Ϊ����ѹ��Ѽ� 
      call InjectLibraryInfo.pLoadLibrary //����ϵͳAPI����LoadLibrary������ָ��DLL�ļ� 
      @noret:   //����һ������noret 
        mov eax, $FFFFFFFF   //��$FFFFFFFF���ݸ��Ĵ���eax 
        push eax             //��eax��ֵ��������ѹ��Ѽ��� 
        call InjectLibraryInfo.pSleep  //����ϵͳAPI����Sleep��ֹͣһ��ʱ�� 
      jmp @noret  //��ת������noret�� 
    end; 
  end; 
 
begin 
  Result := False; 
  InjectLibraryInfo.pSleep := GetProcAddress(GetModuleHandle('kernel32'), 'Sleep'); //��ȡϵͳAPI����Sleep�ĵ�ַ 
  InjectLibraryInfo.pLoadLibrary := GetProcAddress(GetModuleHandle('kernel32'), 'LoadLibraryA'); //��ȡϵͳAPI����LoadLibrary�ĵ�ַ 
  InjectLibraryInfo.lpModuleName := InjectString(Process, pchar(ModulePath)); //��DLL�ļ���·��ע�뵽Ŀ������� 
  Thread := InjectThread(Process, @InjectLibraryThread, @InjectLibraryInfo, SizeOf(TInjectLibraryInfo), False); //ע��Զ���̺߳���InjectLibraryThread���ڼ���ָ��DLL�ļ� 
  if Thread = 0 then Exit; //���Զ���̺߳�������ʧ�����˳� 
  CloseHandle(Thread);  //�ر�Զ��ע���߳� 
  Result := True; 
end; 
 
function InjectLibrary(Process: LongWord; Src: pointer): boolean; //ע��һ��DLL��ָ��������(Srcָ��DLL�ļ�������) 
type 
  TDllLoadInfo = record     //�����Զ���ṹ���ڱ���ע��DLL��Ϣ 
    Module: pointer;    //ָ��Ҫע���DLL�ļ�·�� 
    EntryPoint: pointer;//ָ��Ҫע���DLL�ļ�����ں��� 
  end; 
var 
  Lib: TLibInfo; 
  DllLoadInfo: TDllLoadInfo; 
  BytesWritten: longword; 
  ImageNtHeaders: PImageNtHeaders; 
  pModule: pointer; 
  Offset: longword; 
 
  procedure DllEntryPoint(lpParameter: pointer); stdcall;  //��������Զ��ע��DLL�Ĺ��� 
  var 
    LoadInfo: TDllLoadInfo; 
  begin 
    LoadInfo := TDllLoadInfo(lpParameter^); //�����ݽ����Ĳ���ת����TDllLoadInfo���� 
    asm  //ʹ��Delphi�е���Ƕ��� 
      xor eax, eax                //�������ָ�� 
      push eax                    //��eaxѹ��Ѽ� 
      push DLL_PROCESS_ATTACH     //��DLL_PROCESS_ATTACH ѹ��Ѽ� 
      push LoadInfo.Module        //��Ҫע���DLL·����Ϊ����ѹ��Ѽ� 
      call LoadInfo.EntryPoint    //����Ҫע��DLL�ļ�����ں��� 
    end; 
  end; 
           //����Ķ���������~~!�� 
begin 
  Result := False; 
  ImageNtHeaders := pointer(int64(cardinal(Src)) + PImageDosHeader(Src)._lfanew); 
  Offset := $10000000; 
  repeat 
    Inc(Offset, $10000); //Offset:=Offset+1 
    pModule := VirtualAlloc(pointer(ImageNtHeaders.OptionalHeader.ImageBase + Offset), ImageNtHeaders.OptionalHeader.SizeOfImage, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE); 
    if pModule <> nil then 
    begin 
      VirtualFree(pModule, 0, MEM_RELEASE); 
      pModule := VirtualAllocEx(Process, pointer(ImageNtHeaders.OptionalHeader.ImageBase + Offset), ImageNtHeaders.OptionalHeader.SizeOfImage, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE); 
    end; 
  until ((pModule <> nil) or (Offset > $30000000)); 
  Lib := MapLibrary(Process, pModule, Src); 
  if Lib.ImageBase = nil then Exit; 
  DllLoadInfo.Module := Lib.ImageBase; 
  DllLoadInfo.EntryPoint := Lib.DllProcAddress; 
  WriteProcessMemory(Process, pModule, Lib.ImageBase, Lib.ImageSize, BytesWritten); 
  if InjectThread(Process, @DllEntryPoint, @DllLoadInfo, SizeOf(TDllLoadInfo), False) <> 0 then Result := True 
end; 
 
function InjectExe(Process: LongWord; EntryPoint: pointer): boolean;  //ע��һ��EXE�ļ���ָ�������� 
var 
  Module, NewModule: pointer; 
  Size, TID: longword; 
begin 
  Result := False; 
  Module := pointer(GetModuleHandle(nil));//����õ���ֵΪһ������ָ���ͱ���,ָ�����ݰ����������ļ�ӳ��Ļ�ַ 
  Size := PImageOptionalHeader(pointer(integer(Module) + PImageDosHeader(Module)._lfanew + SizeOf(longword) + SizeOf(TImageFileHeader))).SizeOfImage;//�õ��ڴ�ӳ��ĳ��� 
  VirtualFreeEx(Process, Module, 0, MEM_RELEASE); //��Ŀ����̵��ڴ淶Χ�ڷ���һ���㹻���ȵ��ڴ� 
  NewModule := InjectMemory(Process, Module, Size);//�������ļ�ע�뵽Ŀ������� 
  if CreateRemoteThread(Process, nil, 0, EntryPoint, NewModule, 0, TID) <> 0 then Result := True; //��Ŀ�������ִ��Զ�̺��� 
end; 
 
function UninjectLibrary(Process: LongWord; ModulePath: string): boolean; //���һ��DLLע��(��Ŀ�������ж��ָ��DLL�ļ�) 
type 
  TUninjectLibraryInfo = record      //�����Զ���ṹ���ڱ���ж��DLL��Ϣ 
    pFreeLibrary: pointer;      //ָ��ϵͳAPI����FreeLibrary�ĵ�ַ 
    pGetModuleHandle: pointer;  //ָ��ϵͳAPI����GetModuleHandle�ĵ�ַ 
    lpModuleName: pointer;      //ָ��Ҫж�ص�DLL�ļ�·�� 
    pExitThread: pointer;       //ָ��ϵͳAPI����ExitThread�ĵ�ַ 
  end; 
var 
  UninjectLibraryInfo: TUninjectLibraryInfo;  //����TUninjectLibraryInfo���͵ı��� 
  Thread: THandle;                            //����Thread�������ڱ���ע�뵽Ŀ������е��߳̾�� 
 
  procedure UninjectLibraryThread(lpParameter: pointer); stdcall;  //��������Զ��ж��DLL�Ĺ��� 
  var 
    UninjectLibraryInfo: TUninjectLibraryInfo;    //����TUninjectLibraryInfo���͵ı��� 
  begin 
    UninjectLibraryInfo := TUninjectLibraryInfo(lpParameter^);//�����ݽ����Ĳ���ת����TUninjectLibraryInfo���� 
    asm  //ʹ��Delphi�е���Ƕ��� 
      @1:      //����һ������ 1 
      inc ecx      //�Ĵ���ECX��ֵ��1 
      push UninjectLibraryInfo.lpModuleName     //��Ҫж�ص�DLL·����Ϊ����ѹ��Ѽ� 
      call UninjectLibraryInfo.pGetModuleHandle //����ϵͳAPI����GetModuleHandle����ȡָ��DLL�ļ��ڽ����еľ�� 
      cmp eax, 0  //�ж��Ƿ�Ƕ��ɹ���ȡDLL���(��������ֵ�����EAX��) 
      je @2       //���ʧ��,����������2,�����߳� 
      push eax    //�ѼĴ���EAX��ֵ(��DLL�ļ��ľ��)ѹ��Ѽ� 
      call UninjectLibraryInfo.pFreeLibrary     //����ϵͳAPI����FreeLibrary���ͷ�ָ��DLL�ļ� 
      jmp @1            //���غ��� 1 
      @2:      //����һ������ 2 
      push eax //��EAX��ֵѹ��Ѽ�(ֵΪ0) 
      call UninjectLibraryInfo.pExitThread //����API����ExitThread�˳��߳�===ExitThread(0) 
    end; 
  end; 
 
begin 
  Result := False; 
  UninjectLibraryInfo.pGetModuleHandle := GetProcAddress(GetModuleHandle('kernel32'), 'GetModuleHandleA'); //��ȡAPI����GetModuleHandleA�ĵ�ַ 
  UninjectLibraryInfo.pFreeLibrary := GetProcAddress(GetModuleHandle('kernel32'), 'FreeLibrary');          //��ȡAPI����FreeLibrary�ĵ�ַ 
  UninjectLibraryInfo.pExitThread := GetProcAddress(GetModuleHandle('kernel32'), 'ExitThread');            //��ȡAPI����ExitThread�ĵ�ַ 
  UninjectLibraryInfo.lpModuleName := InjectString(Process, pchar(ModulePath)); //��ָ��DLL·��ע�뵽Ŀ������� 
  Thread := InjectThread(Process, @UninjectLibraryThread, @UninjectLibraryInfo, SizeOf(TUninjectLibraryInfo), False); //������ж��DLL���߳�ע�뵽ָ�������� 
  if Thread = 0 then Exit; //����߳�ע��ʧ�����˳� 
  CloseHandle(Thread);     //�ر��߳̾�� 
  Result := True;           
end; 
 
function CreateProcessEx(lpApplicationName: pchar; lpCommandLine: pchar; lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: boolean; dwCreationFlags: longword; lpEnvironment: pointer; lpCurrentDirectory: pchar; const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation; ModulePath: string): boolean; //�������̵ĺ���(�����ڴ���ʱע��DLL�ļ�) 
begin 
  Result := False; 
  if not CreateProcess(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags or CREATE_SUSPENDED, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation) then Exit; //��API����CreateProcess����һ������,���ҽ����̹���,�������ʧ�����˳����� 
  Result := InjectLibrary(lpProcessInformation.hProcess, ModulePath); //ע��ָ��DLL�ļ����ոմ����Ľ����� 
  ResumeThread(lpProcessInformation.hThread); //�ָ�����,�ý��̼������� 
end; 
 
function CreateProcessEx(lpApplicationName: pchar; lpCommandLine: pchar; lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: boolean; dwCreationFlags: longword; lpEnvironment: pointer; lpCurrentDirectory: pchar; const lpStartupInfo: TStartupInfo; var lpProcessInformation: TProcessInformation; Src: pointer): boolean;//�������̵ĺ���(�����ڴ���ʱע��DLL�ļ�) 
begin 
  Result := False; 
  if not CreateProcess(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags or CREATE_SUSPENDED, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation) then Exit; //��API����CreateProcess����һ������,���ҽ����̹���,�������ʧ�����˳����� 
  Result := InjectLibrary(lpProcessInformation.hProcess, Src);  //ע��ָ��DLL�ļ����ոմ����Ľ����� 
  ResumeThread(lpProcessInformation.hThread); //�ָ�����,�ý��̼������� 
end; 
 
function HookCode(TargetModule, TargetProc: string; NewProc: pointer; var OldProc: pointer): boolean; //Hook API�ĺ��� 
var 
  Address: longword; 
  OldProtect: longword; 
  OldFunction: pointer; 
  Proc: pointer; 
  hModule: longword; 
begin 
  Result := False; 
  try 
    hModule := LoadLibrary(pchar(TargetModule));
    Proc := GetProcAddress(hModule, pchar(TargetProc));
    Address := longword(NewProc) - longword(Proc) - 5;
    if not VirtualProtect(Proc, 5, PAGE_EXECUTE_READWRITE, OldProtect) then
    asm
      nop
    end;
    GetMem(OldFunction, 255);
    longword(OldFunction^) := longword(Proc);
    byte(pointer(longword(OldFunction) + 4)^) := SaveOldFunction(Proc, pointer(longword(OldFunction) + 5));
    byte(pointer(Proc)^) := $e9;
    longword(pointer(longword(Proc) + 1)^) := Address;
    if not VirtualProtect(Proc, 5, OldProtect, OldProtect) then
    asm
      nop
    end;

    OldProc := pointer(longword(OldFunction) + 5);
    if not VirtualProtect(OldProc, 32, PAGE_EXECUTE_READWRITE, OldProtect) then
    asm
      nop
    end;
    FreeLibrary(hModule);
  except 
    Exit; 
  end; 
  Result := True; 
end; 
 
function UnhookCode(OldProc: pointer): boolean; 
var 
  OldProtect: longword; 
  Proc: pointer; 
  SaveSize: longword; 
begin 
  Result := True; 
  try 
    Proc := pointer(longword(pointer(longword(OldProc) - 5)^)); 
    SaveSize := byte(pointer(longword(OldProc) - 1)^); 
    VirtualProtect(Proc, 5, PAGE_EXECUTE_READWRITE, OldProtect); 
    CopyMemory(Proc, OldProc, SaveSize); 
    VirtualProtect(Proc, 5, OldProtect, OldProtect); 
    FreeMem(pointer(longword(OldProc) - 5)); 
  except 
    Result := False; 
  end; 
end; 
 
function DeleteFileEx(FilePath: pchar): boolean; 
type 
  TDeleteFileExInfo = record 
    pSleep: pointer; 
    lpModuleName: pointer; 
    pDeleteFile: pointer; 
    pExitThread: pointer; 
  end; 
var 
  DeleteFileExInfo: TDeleteFileExInfo; 
  Thread: THandle; 
  Process: longword; 
  PID: longword; 
 
 
  procedure DeleteFileExThread(lpParameter: pointer); stdcall; 
  var 
    DeleteFileExInfo: TDeleteFileExInfo; 
  begin 
    DeleteFileExInfo := TDeleteFileExInfo(lpParameter^); 
    asm 
      @1: 
      push 1000 
      call DeleteFileExInfo.pSleep 
      push DeleteFileExInfo.lpModuleName 
      call DeleteFileExInfo.pDeleteFile 
      cmp eax, 0 
      je @1 
      push eax 
      call DeleteFileExInfo.pExitThread 
    end; 
  end; 
 
begin 
  Result := False; 
  GetWindowThreadProcessID(FindWindow('Shell_TrayWnd', nil), @PID); 
  Process := OpenProcess(PROCESS_ALL_ACCESS, False, PID); 
  DeleteFileExInfo.pSleep := GetProcAddress(GetModuleHandle('kernel32'), 'Sleep'); 
  DeleteFileExInfo.pDeleteFile := GetProcAddress(GetModuleHandle('kernel32'), 'DeleteFileA'); 
  DeleteFileExInfo.pExitThread := GetProcAddress(GetModuleHandle('kernel32'), 'ExitThread'); 
  DeleteFileExInfo.lpModuleName := InjectString(Process, FilePath); 
  Thread := InjectThread(Process, @DeleteFileExThread, @DeleteFileExInfo, SizeOf(TDeleteFileExInfo), False); 
  if Thread = 0 then Exit; 
  CloseHandle(Thread); 
  CloseHandle(Process); 
  Result := True; 
end; 
 
function DisableSFC: boolean; 
var 
  Process, SFC, PID, Thread, ThreadID: longword; 
begin 
  Result := False; 
  SFC := LoadLibrary('sfc.dll'); 
  GetWindowThreadProcessID(FindWindow('NDDEAgnt', nil), @PID); 
  Process := OpenProcess(PROCESS_ALL_ACCESS, False, PID); 
  Thread := CreateRemoteThread(Process, nil, 0, GetProcAddress(SFC, pchar(2 and $ffff)), nil, 0, ThreadId); 
  if Thread = 0 then Exit; 
  CloseHandle(Thread); 
  CloseHandle(Process); 
  FreeLibrary(SFC); 
  Result := True; 
end; 
 
function SaveOldFunction(Proc: pointer; Old: pointer): longword; 
var 
  SaveSize, Size: longword; 
  Next: pointer; 
begin 
  SaveSize := 0; 
  Next := Proc; 
  while SaveSize < 5 do 
  begin 
    Size := SizeOfCode(Next); 
    Next := pointer(longword(Next) + Size); 
    Inc(SaveSize, Size); 
  end; 
  CopyMemory(Old, Proc, SaveSize); 
  byte(pointer(longword(Old) + SaveSize)^) := $e9; 
  longword(pointer(longword(Old) + SaveSize + 1)^) := longword(Next) - longword(Old) - SaveSize - 5; 
  Result := SaveSize; 
end; 
 
function GetProcAddressEx(Process: LongWord; lpModuleName, lpProcName: pchar): pointer; 
type 
  TGetProcAddrExInfo = record 
    pExitThread: pointer; 
    pGetProcAddress: pointer; 
    pGetModuleHandle: pointer; 
    lpModuleName: pointer; 
    lpProcName: pointer; 
  end; 
var 
  GetProcAddrExInfo: TGetProcAddrExInfo; 
  ExitCode: longword; 
  Thread: THandle; 
 
  procedure GetProcAddrExThread(lpParameter: pointer); stdcall; 
  var 
    GetProcAddrExInfo: TGetProcAddrExInfo; 
  begin 
    GetProcAddrExInfo := TGetProcAddrExInfo(lpParameter^); 
    asm 
      push GetProcAddrExInfo.lpModuleName 
      call GetProcAddrExInfo.pGetModuleHandle 
      push GetProcAddrExInfo.lpProcName 
      push eax 
      call GetProcAddrExInfo.pGetProcAddress 
      push eax 
      call GetProcAddrExInfo.pExitThread 
    end; 
  end; 
 
begin 
  Result := nil; 
  GetProcAddrExInfo.pGetModuleHandle := GetProcAddress(GetModuleHandle('kernel32'), 'GetModuleHandleA'); 
  GetProcAddrExInfo.pGetProcAddress := GetProcAddress(GetModuleHandle('kernel32'), 'GetProcAddress'); 
  GetProcAddrExInfo.pExitThread := GetProcAddress(GetModuleHandle('kernel32'), 'ExitThread'); 
  GetProcAddrExInfo.lpProcName := InjectString(Process, lpProcName); 
  GetProcAddrExInfo.lpModuleName := InjectString(Process, lpModuleName); 
  Thread := InjectThread(Process, @GetProcAddrExThread, @GetProcAddrExInfo, SizeOf(GetProcAddrExInfo), False); 
  if Thread <> 0 then 
  begin 
    WaitForSingleObject(Thread, INFINITE); 
    GetExitCodeThread(Thread, ExitCode); 
    Result := pointer(ExitCode); 
  end; 
end; 
 
function MapLibrary(Process: LongWord; Dest, Src: pointer): TLibInfo; 
var 
  ImageBase: pointer; 
  ImageBaseDelta: integer; 
  ImageNtHeaders: PImageNtHeaders; 
  PSections: ^TSections; 
  SectionLoop: integer; 
  SectionBase: pointer; 
  VirtualSectionSize, RawSectionSize: cardinal; 
  OldProtect: cardinal; 
  NewLibInfo: TLibInfo; 
 
  function StrToInt(S: string): integer; 
  begin 
   Val(S, Result, Result); 
  end; 
 
  procedure Add(Strings: TStringArray; Text: string); 
  begin 
    SetLength(Strings, Length(Strings) + 1); 
    Strings[Length(Strings) - 1] := Text; 
  end; 
 
  function Find(Strings: array of string; Text: string; var Index: integer): boolean; 
  var 
    StringLoop: integer; 
  begin 
    Result := False; 
    for StringLoop := 0 to Length(Strings) - 1 do 
    begin 
      if lstrcmpi(pchar(Strings[StringLoop]), pchar(Text)) = 0 then 
      begin 
        Index := StringLoop; 
        Result := True; 
      end; 
    end; 
  end; 
 
  function GetSectionProtection(ImageScn: cardinal): cardinal; 
  begin 
    Result := 0; 
    if (ImageScn and IMAGE_SCN_MEM_NOT_CACHED) <> 0 then 
    begin 
    Result := Result or PAGE_NOCACHE; 
    end; 
    if (ImageScn and IMAGE_SCN_MEM_EXECUTE) <> 0 then 
    begin 
      if (ImageScn and IMAGE_SCN_MEM_READ)<> 0 then 
      begin 
        if (ImageScn and IMAGE_SCN_MEM_WRITE)<> 0 then 
        begin 
          Result := Result or PAGE_EXECUTE_READWRITE 
        end 
        else 
        begin 
          Result := Result or PAGE_EXECUTE_READ 
        end; 
      end 
      else if (ImageScn and IMAGE_SCN_MEM_WRITE) <> 0 then 
      begin 
        Result := Result or PAGE_EXECUTE_WRITECOPY 
      end 
      else 
      begin 
        Result := Result or PAGE_EXECUTE 
      end; 
    end 
    else if (ImageScn and IMAGE_SCN_MEM_READ)<> 0 then 
    begin 
      if (ImageScn and IMAGE_SCN_MEM_WRITE) <> 0 then 
      begin 
        Result := Result or PAGE_READWRITE 
      end 
      else 
      begin 
        Result := Result or PAGE_READONLY 
      end 
    end 
    else if (ImageScn and IMAGE_SCN_MEM_WRITE) <> 0 then 
    begin 
      Result := Result or PAGE_WRITECOPY 
    end 
    else 
    begin 
      Result := Result or PAGE_NOACCESS; 
    end; 
  end; 
 
  procedure ProcessRelocs(PRelocs:PImageBaseRelocation); 
  var 
    PReloc: PImageBaseRelocation; 
    RelocsSize: cardinal; 
    Reloc: PWord; 
    ModCount: cardinal; 
    RelocLoop: cardinal; 
  begin 
    PReloc := PRelocs; 
    RelocsSize := ImageNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].Size; 
    while cardinal(PReloc) - cardinal(PRelocs) < RelocsSize do 
    begin 
      ModCount := (PReloc.SizeOfBlock - Sizeof(PReloc^)) div 2; 
      Reloc := pointer(cardinal(PReloc) + sizeof(PReloc^)); 
      for RelocLoop := 0 to ModCount - 1 do 
      begin 
        if Reloc^ and $f000 <> 0 then Inc(plongword(cardinal(ImageBase) + PReloc.VirtualAddress + (Reloc^ and $0fff))^, ImageBaseDelta); 
        Inc(Reloc); 
      end; 
      PReloc := pointer(Reloc); 
    end; 
  end; 
 
  procedure ProcessImports(PImports: PImageImportDescriptor); 
  var 
    PImport: PImageImportDescriptor; 
    Import: plongword; 
    PImportedName: pchar; 
    ProcAddress: pointer; 
    PLibName: pchar; 
    ImportLoop: integer; 
 
    function IsImportByOrdinal(ImportDescriptor: longword): boolean; 
    begin 
      Result := (ImportDescriptor and IMAGE_ORDINAL_FLAG32) <> 0; 
    end; 
 
  begin 
    PImport := PImports; 
    while PImport.Name <> 0 do 
    begin 
      PLibName := pchar(cardinal(PImport.Name) + cardinal(ImageBase)); 
      if not Find(NewLibInfo.LibsUsed, PLibName, ImportLoop) then 
      begin 
        InjectLibrary(Process, string(PLibName)); 
        Add(NewLibInfo.LibsUsed, PLibName); 
      end; 
      if PImport.TimeDateStamp = 0 then 
      begin 
        Import := plongword(pImport.FirstThunk + cardinal(ImageBase)) 
      end 
      else 
      begin 
        Import := plongword(pImport.OriginalFirstThunk + cardinal(ImageBase)); 
      end; 
      while Import^ <> 0 do 
      begin 
        if IsImportByOrdinal(Import^) then 
        begin 
          ProcAddress := GetProcAddressEx(Process, PLibName, pchar(Import^ and $ffff)) 
        end 
        else 
        begin 
          PImportedName := pchar(Import^ + cardinal(ImageBase) + IMPORTED_NAME_OFFSET); 
          ProcAddress := GetProcAddressEx(Process, PLibName, PImportedName); 
        end; 
        Ppointer(Import)^ := ProcAddress; 
        Inc(Import); 
      end; 
      Inc(PImport); 
    end; 
  end; 
 
begin   (*
  ImageNtHeaders := pointer(int64(cardinal(Src)) + PImageDosHeader(Src)._lfanew); 
  ImageBase := VirtualAlloc(Dest, ImageNtHeaders.OptionalHeader.SizeOfImage, MEM_RESERVE, PAGE_NOACCESS); 
  ImageBaseDelta := cardinal(ImageBase) - ImageNtHeaders.OptionalHeader.ImageBase; 
  SectionBase := VirtualAlloc(ImageBase, ImageNtHeaders.OptionalHeader.SizeOfHeaders, MEM_COMMIT, PAGE_READWRITE); 
  Move(Src^, SectionBase^, ImageNtHeaders.OptionalHeader.SizeOfHeaders); 
  VirtualProtect(SectionBase, ImageNtHeaders.OptionalHeader.SizeOfHeaders, PAGE_READONLY, OldProtect); 
  PSections := pointer(pchar(@(ImageNtHeaders.OptionalHeader)) + ImageNtHeaders.FileHeader.SizeOfOptionalHeader); 
  for SectionLoop := 0 to ImageNtHeaders.FileHeader.NumberOfSections - 1 do 
  begin 
    VirtualSectionSize := PSections[SectionLoop].Misc.VirtualSize; 
    RawSectionSize := PSections[SectionLoop].SizeOfRawData; 
    if VirtualSectionSize < RawSectionSize then 
    begin 
      VirtualSectionSize := VirtualSectionSize xor RawSectionSize; 
      RawSectionSize := VirtualSectionSize xor RawSectionSize; 
      VirtualSectionSize := VirtualSectionSize xor RawSectionSize; 
    end; 
    SectionBase := VirtualAlloc(PSections[SectionLoop].VirtualAddress + Pointer(ImageBase), VirtualSectionSize, MEM_COMMIT, PAGE_READWRITE);
    FillChar(SectionBase^, VirtualSectionSize, 0); 
    Move((pchar(src) + PSections[SectionLoop].pointerToRawData)^, SectionBase^, RawSectionSize); 
  end; 
  NewLibInfo.DllProc := TDllEntryProc(ImageNtHeaders.OptionalHeader.AddressOfEntryPoint + cardinal(ImageBase)); 
  NewLibInfo.DllProcAddress := pointer(ImageNtHeaders.OptionalHeader.AddressOfEntryPoint + cardinal(ImageBase)); 
  NewLibInfo.ImageBase := ImageBase; 
  NewLibInfo.ImageSize := ImageNtHeaders.OptionalHeader.SizeOfImage; 
  SetLength(NewLibInfo.LibsUsed, 0); 
  if ImageNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress <> 0 then ProcessRelocs(pointer(ImageNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress + cardinal(ImageBase))); 
  if ImageNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress <> 0 then ProcessImports(pointer(ImageNtHeaders.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress + cardinal(ImageBase))); 
  for SectionLoop := 0 to ImageNtHeaders.FileHeader.NumberOfSections - 1 do 
  begin 
    VirtualProtect(PSections[SectionLoop].VirtualAddress + pchar(ImageBase), PSections[SectionLoop].Misc.VirtualSize, GetSectionProtection(PSections[SectionLoop].Characteristics), OldProtect); 
  end; 
  Result := NewLibInfo;  *)
end;
 
end. 
 

