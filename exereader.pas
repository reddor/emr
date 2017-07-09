unit exereader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Math,
  dosheader;

type
  TExeFileKind = (
    fkUnknown,
    fkDOS,
    fkExe16,
    fkExe32,
    fkExe64,
    fkExeArm,
    fkDll16,
    fkDll32,
    fkDll64,
    fkDllArm,
    fkVXD
  );

  PLongword = ^Longword;

  TExeFile = class;

  TImportFuncEntry = record
      case IsOrdinal: Boolean of
        true: (
          Ordinal: Word;
        );
        false: (
          Hint: Word;
          Name: PAnsiChar;
        );
    end;

  { TExeImportDLL }

  TExeImportDLL = class
  private
    FHandle: THandle;
    FParent: TExeFile;
    FDLLName: PChar;
    FDescriptor: PIMAGE_IMPORT_DESCRIPTOR;
    FEntries: array of TImportFuncEntry;
    function GetCount: Integer;
    function GetDLLName: string;
    function GetEntry(Index: Integer): TImportFuncEntry;
  public
    constructor Create(AParent: TExeFile; DLL: PIMAGE_IMPORT_DESCRIPTOR);
    function Read: Boolean;
    function Read64: Boolean;

    property Descriptor: PIMAGE_IMPORT_DESCRIPTOR read FDescriptor;
    property DLLName: string read GetDLLName;
    property Count: Integer read GetCount;
    property Entries[Index: Integer]: TImportFuncEntry read GetEntry;

    property Handle: THandle read FHandle write FHandle;
  end;

  TExeExportFunc = record
    Name: PChar;
    Ordinal: Word;
    EntryPoint: longword;
  end;

  TDWordArray = array[0..0] of DWord;
  PDWordArray = ^TDWordArray;

  TExeRelocTable = record
    VirtualAddress: UInt64;
    Count: Integer;
    Items: PWordarray;
  end;

  { TExeFile }

  TExeFile = class
  private
    FDataSize: longword;
    FData: PByteArray;
    FDOSHeader: PIMAGE_DOS_HEADER;
    FNTHeaders64: PIMAGE_NT_HEADERS64;
    FNTHeaders: PIMAGE_NT_HEADERS;
    FSections: array of PIMAGE_SECTION_HEADER;
    FImports: array of TExeImportDLL;
    FExports: array of TExeExportFunc;
    FRelocations: array of TExeRelocTable;
    FDOSFileSize: longword;
    FStatus: string;
    FExportName: PChar;
    FFileType: TExeFileKind;
    function GetExport(Index: Integer): TExeExportFunc;
    function GetExportCount: Integer;
    function GetImport(Index: Integer): TExeImportDLL;
    function GetImportCount: Integer;
    function GetRelocation(Index: Integer): TExeRelocTable;
    function GetRelocationCount: Integer;
    function GetSection(Index: Integer): PIMAGE_SECTION_HEADER;
    function GetSectionCount: Integer;
  protected
    function ResolveVirtualAddress32(VirtualAddress: UInt64): UInt64;
    procedure ReadImports(VirtualAddress: UInt64; is64Bit: Boolean);
    procedure ReadExports(VirtualAddress: UInt64);
    procedure ReadRelocations(VirtualAddress: UInt64);

    function ReadDOSHeader: Boolean;
    function ReadWin32Header: Boolean;
    function ReadWin64Header: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function LoadFile(aFilename: string; ReadFull: Boolean = True): Boolean;
    function GetRawAddress(Address: UInt64): Pointer;
    function GetVirtualAddress(VirtualAddress: UInt64): Pointer;
    function IsValidVirtualAddress(VirtualAddress: UInt64): Boolean;
    property Status: string read FStatus;
    property FileType: TExeFileKind read FFileType;
    property DOSHeader: PIMAGE_DOS_HEADER read FDOSHeader;
    property NTHeader: PIMAGE_NT_HEADERS read FNTHeaders;
    property NTHeader64: PIMAGE_NT_HEADERS64 read FNTHeaders64;
    property SectionCount: Integer read GetSectionCount;
    property Sections[Index: Integer]: PIMAGE_SECTION_HEADER read GetSection;
    property ImportCount: Integer read GetImportCount;
    property Imports[Index: Integer]: TExeImportDLL read GetImport;
    property ExportName: PChar read FExportName;
    property ExportCount: Integer read GetExportCount;
    property ExportFuncs[Index: Integer]: TExeExportFunc read GetExport;
    property RelocationCount: Integer read GetRelocationCount;
    property Relocations[Index: Integer]: TExeRelocTable read GetRelocation;
  end;

implementation

{ TExeImportDLL }

function TExeImportDLL.GetDLLName: string;
begin
  result:=FDLLName;
end;

function TExeImportDLL.GetCount: Integer;
begin
  result:=Length(FEntries);
end;

function TExeImportDLL.GetEntry(Index: Integer): TImportFuncEntry;
begin
  if(Index>=0)and(Index<Length(FEntries)) then
    result:=FEntries[Index]
  else
  begin
    result.IsOrdinal:=False;
    result.Hint:=0;
    result.Name:=nil;
  end;
end;

constructor TExeImportDLL.Create(AParent: TExeFile;
  DLL: PIMAGE_IMPORT_DESCRIPTOR);
begin
  FParent:=AParent;
  FDescriptor:=DLL;
end;

function TExeImportDLL.Read: Boolean;
var
  p: Pointer;
  ThunkData: PIMAGE_IMPORT_BY_NAME;
  ThunkRef: PDWord;
  ACount: Integer;

begin
  result:=False;
  if FDescriptor^.Name = 0 then
    raise Exception.Create('Invalid Image Import Descriptor!');

  FDLLName:=PChar(FParent.GetVirtualAddress(FDescriptor^.Name));

  if FDescriptor^.OriginalFirstThunk <> 0 then
    p := FParent.GetVirtualAddress(FDescriptor^.OriginalFirstThunk)
  else
    p := FParent.GetVirtualAddress(FDescriptor^.FirstThunk);

  ACount:=0;
  ThunkRef:=p;
  while ThunkRef^ <> 0 do
  begin
    Inc(ACount);
    Inc(ThunkRef);
  end;

  Setlength(FEntries, ACount);

  ThunkRef:=p;
  ACount:=0;
  while ThunkRef^ <> 0 do
  begin
    if (ThunkRef^ and IMAGE_ORDINAL_FLAG32 = IMAGE_ORDINAL_FLAG32) then
    begin
      FEntries[ACount].IsOrdinal:=True;
      FEntries[ACount].Ordinal:=ThunkRef^ and $FFFF;
    end else
    begin
      FEntries[ACount].IsOrdinal:=False;
      ThunkData:=FParent.GetVirtualAddress(ThunkRef^);
      FEntries[ACount].Name:=PChar(@ThunkData^.Name[0]);
      FEntries[ACount].Hint:=ThunkData^.Hint;
    end;
    Inc(ACount);
    Inc(ThunkRef);
  end;
  result:=True;
end;

function TExeImportDLL.Read64: Boolean;
var
  p: Pointer;
  ThunkData: PIMAGE_IMPORT_BY_NAME;
  ThunkRef: PQWord;
  ACount: Integer;

begin
  result:=False;
  if FDescriptor^.Name = 0 then
    //raise Exception.Create('Invalid Image Import Descriptor!');
    Exit;

  FDLLName:=PChar(FParent.GetVirtualAddress(FDescriptor^.Name));

  if FDescriptor^.OriginalFirstThunk <> 0 then
    p := FParent.GetVirtualAddress(FDescriptor^.OriginalFirstThunk)
  else
    p := FParent.GetVirtualAddress(FDescriptor^.FirstThunk);

  ACount:=0;
  ThunkRef:=p;
  while ThunkRef^ <> 0 do
  begin
    Inc(ACount);
    Inc(ThunkRef);
  end;

  Setlength(FEntries, ACount);

  ThunkRef:=p;
  ACount:=0;
  while ThunkRef^ <> 0 do
  begin
    if (ThunkRef^ and IMAGE_ORDINAL_FLAG64 = IMAGE_ORDINAL_FLAG64) then
    begin
      FEntries[ACount].IsOrdinal:=True;
      FEntries[ACount].Ordinal:=ThunkRef^ and $FFFFFFFF;
    end else
    begin
      FEntries[ACount].IsOrdinal:=False;
      ThunkData:=FParent.GetVirtualAddress(ThunkRef^);
      FEntries[ACount].Name:=PChar(@ThunkData^.Name[0]);
      FEntries[ACount].Hint:=ThunkData^.Hint;
    end;
    Inc(ACount);
    Inc(ThunkRef);
  end;
  result:=True;
end;

{ TExeFile }

function TExeFile.GetSection(Index: Integer): PIMAGE_SECTION_HEADER;
begin
  if (Index>=0)and(Index<Length(FSections)) then
    result:=FSections[Index]
  else
    result:=nil;
end;

function TExeFile.GetImport(Index: Integer): TExeImportDLL;
begin
  if (Index>=0)and(Index<Length(FImports)) then
    result:=FImports[Index]
  else
    result:=nil;
end;

function TExeFile.GetExport(Index: Integer): TExeExportFunc;
begin
  if(Index>=0)and(Index<Length(FExports)) then
    result:=FExports[Index]
  else begin
    result.EntryPoint:=0;
    result.Name:=nil;
    result.Ordinal:=0;
  end;
end;

function TExeFile.GetExportCount: Integer;
begin
  result:=Length(FExports);
end;

function TExeFile.GetImportCount: Integer;
begin
  result:=Length(FImports);
end;

function TExeFile.GetRelocation(Index: Integer): TExeRelocTable;
begin
  if (Index>=0)and(Index<Length(FRelocations)) then
    result:=FRelocations[Index]
  else
  begin
    result.Count:=0;
    result.Items:=nil;
    result.VirtualAddress:=0;
  end;
end;

function TExeFile.GetRelocationCount: Integer;
begin
  result:=Length(FRelocations);
end;

function TExeFile.GetSectionCount: Integer;
begin
  result:=Length(FSections);
end;

function TExeFile.IsValidVirtualAddress(VirtualAddress: UInt64): Boolean;
var
  i: Integer;
begin
  result:=False;

  if VirtualAddress = 0 then
    Exit;

  for i:=0 to Length(FSections)-1 do
    if (VirtualAddress >= FSections[i]^.VirtualAddress) and
       (VirtualAddress < FSections[i]^.VirtualAddress + UInt64(FSections[i]^.PhysicalAddress)) // PhysicalAddress == VirtualSize!
       then
    begin
      result:= ((VirtualAddress - FSections[i]^.VirtualAddress) + FSections[i]^.PointerToRawData) < FDataSize;
      Exit;
    end;

  if VirtualAddress<FDataSize then
    result:=True;
end;

function TExeFile.ResolveVirtualAddress32(VirtualAddress: UInt64): UInt64;
var
  i: Integer;
begin
  result:=0;

  if VirtualAddress = 0 then
    Exit;

  for i:=0 to Length(FSections)-1 do
    if (VirtualAddress >= FSections[i]^.VirtualAddress) and
       (VirtualAddress < UInt64(FSections[i]^.VirtualAddress) + UInt64(FSections[i]^.PhysicalAddress)) // PhysicalAddress == VirtualSize!
       then
    begin
      result:= ((VirtualAddress - FSections[i]^.VirtualAddress) + FSections[i]^.PointerToRawData);

      if result>=FDataSize then
        raise Exception.Create('Virtual address out of bounds');

      Exit;
    end;
  // not sure if this is right behaviour, but it'srequired for some versions
  // of kkrunchy
  result:=VirtualAddress;

  if result>=FDataSize then
    raise Exception.Create('Virtual address out of bounds');
end;

procedure TExeFile.ReadImports(VirtualAddress: UInt64; is64Bit: Boolean);
var
  ImportDesc: PIMAGE_IMPORT_DESCRIPTOR_ARRAY;
  i: Integer;
begin
  if not IsValidVirtualAddress(VirtualAddress) then
    Exit;

  ImportDesc:=GetVirtualAddress(VirtualAddress);
  i:=0;

  while (ImportDesc^[i].Name<>0) do
  begin
    Setlength(FImports, i + 1);
    FImports[i]:=TExeImportDLL.Create(Self, @ImportDesc^[i]);

    if is64Bit then
      FImports[i].Read64
    else
      FImports[i].Read;

    Inc(i);
  end;

end;

procedure TExeFile.ReadExports(VirtualAddress: UInt64);
var
  ExportDesc: PIMAGE_EXPORT_DIRECTORY;
  expInfo: PDWord;
  ordInfo: PWord;
  addrInfo: PDWord;
  j: Integer;
begin
  if not IsValidVirtualAddress(VirtualAddress) then
    Exit;

  ExportDesc:=GetVirtualAddress(VirtualAddress);
  if ExportDesc^.Name <> 0 then
  begin
    FExportName:=GetVirtualAddress(ExportDesc^.Name);

    expInfo:=GEtVirtualAddress(ExportDesc^.AddressOfNames);
    ordInfo:=GEtVirtualAddress(ExportDesc^.AddressOfNameOrdinals);
    addrInfo:=GetVirtualAddress(ExportDesc^.AddressOfFunctions);

    Setlength(FExports, ExportDesc^.NumberOfNames);

    for j:=0 to ExportDesc^.NumberOfNames -1 do
    begin
      FExports[j].Name:=GetVirtualAddress(expInfo^);
      FExports[j].Ordinal:=OrdInfo^;
      FExports[j].EntryPoint:=AddrInfo^;
      inc(expInfo);
      inc(ordInfo);
      inc(addrInfo);
    end;
  end;
end;

procedure TExeFile.ReadRelocations(VirtualAddress: UInt64);
var
  Reloc:PIMAGE_BASE_RELOCATION;
  i: Integer;
begin
  if not IsValidVirtualAddress(VirtualAddress) then
    Exit;

  reloc:=GetVirtualAddress(VirtualAddress);

  while reloc^.VirtualAddress>0 do
  begin
    if reloc^.SizeOfBlock>0 then
    begin
      i:=Length(FRelocations);
      Setlength(FRelocations, i+1);
      FRelocations[i].VirtualAddress:=reloc^.VirtualAddress;
      FRelocations[i].Count:=(reloc^.SizeOfBlock - IMAGE_SIZEOF_BASE_RELOCATION) div 2;
      FRelocations[i].Items:=Pointer((Reloc)+ IMAGE_SIZEOF_BASE_RELOCATION);
    end;
    reloc:=Pointer(UInt64(reloc)+reloc^.SizeOfBlock);
  end;
end;

function TExeFile.ReadDOSHeader: Boolean;
var
  HeaderOFfset: longword;
  NEFlags: Byte;
begin
  FStatus:='Invalid file';
  FFileType:=fkUnknown;

  result:=False;
  if not Assigned(FData) then
    Exit;

  if FDataSize<SizeOf(IMAGE_DOS_HEADER) then
    Exit;

  FDOSHeader:=@FData[0];

  if FDOSHeader^.e_magic <> cDOSMagic then
  begin
    FStatus:='Not an executable file';
    Exit;
  end;

  // DOS files have length >= size indicated at offset $02 and $04
  // (offset $02 indicates length of file mod 512 and offset $04
  // indicates no. of 512 pages in file)
  if FDOSHeader^.e_cblp = 0 then
    FDOSFileSize:=512 * FDOSHeader^.e_cp
  else
    FDOSFileSize:=512 * (FDOSHeader^.e_cp - 1) + FDOSHeader^.e_cblp;

  // DOS file relocation offset must be within DOS file size.
  if FDOSHeader^.e_lfarlc > FDOSFileSize then
    Exit;

  FFileType:=fkDOS;
  FSTatus:='';
  result:=True;

  if FDataSize <= cWinHeaderOffset + SizeOf(LongInt) then
    Exit;

  HeaderOffset:=FDOSHeader^.e_lfanew;
  if FDataSize< HeaderOffset + SizeOf(IMAGE_NT_HEADERS) then
    Exit;

  FNTHeaders:=@FData^[HeaderOffset];
  case FNTHeaders^.Signature of
    cPEMagic:
    begin
      // 32 bit/64 bit
      if FDataSize>=HeaderOffset + SizeOf(FNTHeaders^) then
      begin
        case FNTHeaders^.FileHeader.Machine of
          $01c4: begin
            // arm 32 bit
            if (FNTHeaders^.FileHeader.Characteristics and IMAGE_FILE_DLL) = IMAGE_FILE_DLL then
              FFileType:=fkDllArm
            else
              FFileType:=fkExeArm;
          end;
          $014c: begin
            // 32 bit
            if (FNTHeaders^.FileHeader.Characteristics and IMAGE_FILE_DLL) = IMAGE_FILE_DLL then
              FFileType:=fkDll32
            else
              FFileType:=fkExe32;
          end;
          $8664: begin
            // 64 bit
            FNTHeaders64:=PIMAGE_NT_HEADERS64(FNTHeaders);
            FNTHeaders:=nil;
            if (FNTHeaders64^.FileHeader.Characteristics and IMAGE_FILE_DLL) = IMAGE_FILE_DLL then
              FFileType:=fkDll64
            else
              FFileType:=fkExe64;
          end;
          else begin
            result:=False;
            FFileType:=fkUnknown;
            FStatus:='Unknown Machine Type '+IntToHex(FNTHeaders^.FileHeader.Machine, 4);
            FNTHeaders:=nil;
          end;
        end;
      end;
    end;
    cNEMagic:
    begin
      // 16 bit
      FNTHeaders:=nil;

      if FDataSize>=HeaderOffset + cNEAppTypeOffset + SizeOf(NEFlags) then
      begin
        NEFlags:=FData^[HeaderOffset + cNEAppTypeOffset];
        if (NEFlags and cNEDLLFlag) = cNEDLLFlag then
          FFileType:=fkDll16
        else
          FFileType:=fkExe16;
      end;
      Exit;
    end;

    cLEMagic:
    begin
      FNTHeaders:=nil;
      FFileType:=fkVXD;
    end;

    else
    begin
      FStatus:='Unknown NT Header Signature';
      Exit;
    end;
  end;

end;

function TExeFile.ReadWin32Header: Boolean;
var
  i: Integer;
  p: longword;
begin
  result:=False;

  if FNTHeaders^.OptionalHeader.Magic <> $10b then
  begin
    FStatus:='OptionalHeader Magic is not Win32';
    Exit;
  end;

  // read sections
  if FNTHeaders^.FileHeader.NumberOfSections<=96 then
  begin
    Setlength(FSections, FNTHeaders^.FileHeader.NumberOfSections);
    p:=FDOSHeader^.e_lfanew + SizeOf(FNTHeaders^);

    for i:=0 to FNTHeaders^.FileHeader.NumberOfSections-1 do
    begin
      FSections[i]:=@FData^[p];
      p:=p+SizeOf(FSections[i]^);
    end;
  end else
  begin
    FStatus:='Number of sections exceeds maximum';
    Exit;
  end;

  if FNTHeaders^.OptionalHeader.DataDirectory[0].VirtualAddress <> 0 then
    ReadExports(FNTHeaders^.OptionalHeader.DataDirectory[0].VirtualAddress);

  if FNTHeaders^.OptionalHeader.DataDirectory[1].VirtualAddress <> 0 then
    ReadImports(FNTHeaders^.OptionalHeader.DataDirectory[1].VirtualAddress, false);

  if FNTHeaders^.OptionalHeader.DataDirectory[5].Size >= SizeOf(IMAGE_BASE_RELOCATION) then
    ReadRelocations(FNTHeaders^.OptionalHeader.DataDirectory[5].VirtualAddress);

  result:=True;
end;

function TExeFile.ReadWin64Header: Boolean;
var
  i: Integer;
  p: longword;
begin
  result:=False;

  if FNTHeaders64^.OptionalHeader.Magic <> $20b then
  begin
    FStatus:='Not Win32/x86';
    Exit;
  end;

  // read sections
  if FNTHeaders64^.FileHeader.NumberOfSections<=96 then
  begin
    Setlength(FSections, FNTHeaders64^.FileHeader.NumberOfSections);
    p:=FDOSHeader^.e_lfanew + SizeOf(FNTHeaders64^);

    for i:=0 to FNTHeaders64^.FileHeader.NumberOfSections-1 do
    begin
      FSections[i]:=@FData^[p];
      p:=p+SizeOf(FSections[i]^);
    end;

  end else
  begin
    FStatus:='Number of sections exceeds maximum';
    Exit;
  end;

  if FNTHeaders64^.OptionalHeader.DataDirectory[0].Size <> 0 then
    ReadExports(FNTHeaders64^.OptionalHeader.DataDirectory[0].VirtualAddress);

  if FNTHeaders64^.OptionalHeader.DataDirectory[1].Size <> 0 then
    ReadImports(FNTHeaders64^.OptionalHeader.DataDirectory[1].VirtualAddress, true);

  if FNTHeaders64^.OptionalHeader.DataDirectory[5].Size >= SizeOf(IMAGE_BASE_RELOCATION) then
    ReadRelocations(FNTHeaders64^.OptionalHeader.DataDirectory[5].VirtualAddress);


  result:=True;
end;

constructor TExeFile.Create;
begin
  FData:=nil;
end;

destructor TExeFile.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TExeFile.GetVirtualAddress(VirtualAddress: UInt64): Pointer;
begin
  result:=@FData^[ResolveVirtualAddress32(VirtualAddress)];
end;

function TExeFile.LoadFile(aFilename: string; ReadFull: Boolean): Boolean;
var
  f: File;
begin
  result:=False;
  Clear;
  Assignfile(f, aFilename);
  Filemode:=0;
  {$i-}reset(f,1);{$i+}
  if ioresult=0 then
  begin
    FDataSize := Filesize(f);
    if not ReadFull then
      FDataSize := Min(4 * 1024, FdataSize);

    Getmem(FData, FDataSize);
    Blockread(f, FData^, FDataSize);
    CloseFile(f);
  end else
  begin
    FStatus:='Could not open file';
    Exit;
  end;

  result:=ReadDOSHeader;

  case FFileType of
    fkExe32,
    fkExeArm,
    fkDll32,
    fkDllArm: ReadWin32Header;
    fkExe64,
    fkDLL64: ReadWin64Header;
  end;

end;

function TExeFile.GetRawAddress(Address: UInt64): Pointer;
begin
  result:=@FData^[Address];
end;

procedure TExeFile.Clear;
var
  i: Integer;
begin
  for i:=0 to Length(FImports)-1 do
    FImports[i].Free;

  Setlength(FImports, 0);
  Setlength(FExports, 0);
  Setlength(FSections, 0);

  FDOSHeader:=nil;
  FNTHeaders:=nil;
  FNTHeaders64:=nil;
  FExportName:=nil;

  if Assigned(FData) then
    Freemem(FData);

  FDataSize:=0;
  FData:=nil;
end;

end.
