unit dosheader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  IMAGE_SIZEOF_SHORT_NAME            = 8;
  IMAGE_NUMBEROF_DIRECTORY_ENTRIES   = 16;

  IMAGE_FILE_RELOCS_STRIPPED     = $0001;
  IMAGE_FILE_EXECUTABLE_IMAGE    = $0002;
  IMAGE_FILE_LINE_NUMS_STRIPPED  = $0004;
  IMAGE_FILE_LOCAL_SYMS_STRIPPED = $0008;
  IMAGE_FILE_AGGRESIVE_WS_TRIM   = $0010;
  IMAGE_FILE_LARGE_ADDRESS_AWARE = $0020;
  IMAGE_FILE_BYTES_REVERSED_LO   = $0080;
  IMAGE_FILE_32BIT_MACHINE       = $0100;
  IMAGE_FILE_DEBUG_STRIPPED      = $0200;
  IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP = $0400;
  IMAGE_FILE_NET_RUN_FROM_SWAP   = $0800;
  IMAGE_FILE_SYSTEM              = $1000;
  IMAGE_FILE_DLL                 = $2000;
  IMAGE_FILE_UP_SYSTEM_ONLY      = $4000;
  IMAGE_FILE_BYTES_REVERSED_HI   = $8000;

  IMAGE_ORDINAL_FLAG32 = DWORD($80000000);
  IMAGE_ORDINAL_FLAG64 = QWORD($8000000000000000);

  IMAGE_SIZEOF_BASE_RELOCATION = 8;
  IMAGE_REL_BASED_HIGHLOW = 3;
  IMAGE_SCN_MEM_DISCARDABLE = $02000000;
  IMAGE_SCN_MEM_NOT_CACHED = $04000000;
  IMAGE_SCN_CNT_INITIALIZED_DATA = $00000040;
  IMAGE_SCN_CNT_UNINITIALIZED_DATA = $00000080;
  IMAGE_SCN_MEM_EXECUTE = $20000000;
  IMAGE_SCN_MEM_READ = $40000000;
  IMAGE_SCN_MEM_WRITE = DWORD($80000000);


  cDOSRelocOffset = $18;  // offset of "pointer" to DOS relocation table
  cWinHeaderOffset = $3C; // offset of "pointer" to windows header in file
  cNEAppTypeOffset = $0D; // offset in NE windows header of app type field
  cDOSMagic = $5A4D;      // magic number for a DOS executable
  cNEMagic = $454E;       // magic number for a NE executable (Win 16)
  cPEMagic = $4550;       // magic nunber for a PE executable (Win 32)
  cLEMagic = $454C;       // magic number for a Virtual Device Driver
  cNEDLLFlag = $80;       // flag in NE app type field indicating a DLL

type
  LIST_ENTRY = record
       Flink : ^_LIST_ENTRY;
       Blink : ^_LIST_ENTRY;
    end;
  _LIST_ENTRY = LIST_ENTRY;
  TLISTENTRY = LIST_ENTRY;
  PLISTENTRY = ^LIST_ENTRY;

  IMAGE_BASE_RELOCATION = packed record
    VirtualAddress: DWORD;
    SizeOfBlock: DWORD;
  end;

  PIMAGE_BASE_RELOCATION = ^IMAGE_BASE_RELOCATION;

  IMAGE_EXPORT_DIRECTORY = packed record
    Characteristics: DWORD;
    TimeDateStamp: DWORD;
    MajorVersion: WORD;
    MinorVersion: WORD;
    Name: DWORD;
    Base: DWORD;
    NumberOfFunctions: DWORD;
    NumberOfNames: DWORD;
    AddressOfFunctions: DWORD;
    AddressOfNames: DWORD;
    AddressOfNameOrdinals: DWORD;
  end;

  PIMAGE_EXPORT_DIRECTORY = ^IMAGE_EXPORT_DIRECTORY;

  IMAGE_EXPORT_DIRECTORY_ARRAY = array[0..0] of IMAGE_EXPORT_DIRECTORY;

  PIMAGE_EXPORT_DIRECTORY_ARRAY = ^IMAGE_EXPORT_DIRECTORY_ARRAY;

  IMAGE_IMPORT_DESCRIPTOR = packed record
    OriginalFirstThunk: DWORD;
    TimeDateStamp: DWORD;
    ForwarderChain: DWORD;
    Name: DWORD;
    FirstThunk: DWORD;
  end;
  PIMAGE_IMPORT_DESCRIPTOR = ^IMAGE_IMPORT_DESCRIPTOR;

  TImageImportDescriptor = IMAGE_IMPORT_DESCRIPTOR;

  IMAGE_IMPORT_DESCRIPTOR_ARRAY = packed array[0..0] of IMAGE_IMPORT_DESCRIPTOR;
  PIMAGE_IMPORT_DESCRIPTOR_ARRAY = ^IMAGE_IMPORT_DESCRIPTOR_ARRAY;

  PImageImportByName = ^TImageImportByName;

  IMAGE_IMPORT_BY_NAME = packed record
    Hint: Word;
    Name: array [0 .. 255] of Byte; // original: "Name: array [0..0] of Byte;"
  end;

  TImageImportByName = IMAGE_IMPORT_BY_NAME;
  PIMAGE_IMPORT_BY_NAME = ^IMAGE_IMPORT_BY_NAME;

  IMAGE_DATA_DIRECTORY = packed record
    VirtualAddress  : DWORD;
    Size            : DWORD;
  end;
  PIMAGE_DATA_DIRECTORY = ^IMAGE_DATA_DIRECTORY;

  IMAGE_SECTION_HEADER = packed record
      Name     : packed array [0..IMAGE_SIZEOF_SHORT_NAME-1] of Char;
      PhysicalAddress : DWORD; // or VirtualSize (union);
      VirtualAddress  : DWORD;
      SizeOfRawData   : DWORD;
      PointerToRawData : DWORD;
      PointerToRelocations : DWORD;
      PointerToLinenumbers : DWORD;
      NumberOfRelocations : WORD;
      NumberOfLinenumbers : WORD;
      Characteristics : DWORD;
  end;
  PIMAGE_SECTION_HEADER = ^IMAGE_SECTION_HEADER;

  IMAGE_OPTIONAL_HEADER = packed record
   { Standard fields. }
      Magic           : WORD;
      MajorLinkerVersion : Byte;
      MinorLinkerVersion : Byte;
      SizeOfCode      : DWORD;
      SizeOfInitializedData : DWORD;
      SizeOfUninitializedData : DWORD;
      AddressOfEntryPoint : DWORD;
      BaseOfCode      : DWORD;
      BaseOfData      : DWORD;
     { NT additional fields. }
      ImageBase       : DWORD;
      SectionAlignment : DWORD;
      FileAlignment   : DWORD;
      MajorOperatingSystemVersion : WORD;
      MinorOperatingSystemVersion : WORD;
      MajorImageVersion : WORD;
      MinorImageVersion : WORD;
      MajorSubsystemVersion : WORD;
      MinorSubsystemVersion : WORD;
      Reserved1       : DWORD;
      SizeOfImage     : DWORD;
      SizeOfHeaders   : DWORD;
      CheckSum        : DWORD;
      Subsystem       : WORD;
      DllCharacteristics : WORD;
      SizeOfStackReserve : DWORD;
      SizeOfStackCommit : DWORD;
      SizeOfHeapReserve : DWORD;
      SizeOfHeapCommit : DWORD;
      LoaderFlags     : DWORD;
      NumberOfRvaAndSizes : DWORD;
      DataDirectory: packed array[0..IMAGE_NUMBEROF_DIRECTORY_ENTRIES-1] of IMAGE_DATA_DIRECTORY;
  end;
  PIMAGE_OPTIONAL_HEADER = ^IMAGE_OPTIONAL_HEADER;

  IMAGE_OPTIONAL_HEADER64 = packed record
   { Standard fields. }
      Magic           : WORD;
      MajorLinkerVersion : Byte;
      MinorLinkerVersion : Byte;
      SizeOfCode      : DWORD;
      SizeOfInitializedData : DWORD;
      SizeOfUninitializedData : DWORD;
      AddressOfEntryPoint : DWORD;
      BaseOfCode      : DWORD;
//      BaseOfData      : DWORD;
     { NT additional fields. }
      ImageBase       : UInt64;
      SectionAlignment : DWORD;
      FileAlignment   : DWORD;
      MajorOperatingSystemVersion : WORD;
      MinorOperatingSystemVersion : WORD;
      MajorImageVersion : WORD;
      MinorImageVersion : WORD;
      MajorSubsystemVersion : WORD;
      MinorSubsystemVersion : WORD;
      Win32VersionValue : DWORD;
      SizeOfImage     : DWORD;
      SizeOfHeaders   : DWORD;
      CheckSum        : DWORD;
      Subsystem       : WORD;
      DllCharacteristics : WORD;
      SizeOfStackReserve : UInt64;
      SizeOfStackCommit : UInt64;
      SizeOfHeapReserve : UInt64;
      SizeOfHeapCommit : UInt64;
      LoaderFlags     : DWORD;
      NumberOfRvaAndSizes : DWORD;
      DataDirectory: packed array[0..IMAGE_NUMBEROF_DIRECTORY_ENTRIES-1] of IMAGE_DATA_DIRECTORY;
  end;
  PIMAGE_OPTIONAL_HEADER64 = ^IMAGE_OPTIONAL_HEADER64;

  IMAGE_FILE_HEADER = packed record
      Machine              : WORD;
      NumberOfSections     : WORD;
      TimeDateStamp        : DWORD;
      PointerToSymbolTable : DWORD;
      NumberOfSymbols      : DWORD;
      SizeOfOptionalHeader : WORD;
      Characteristics      : WORD;
    end;
    PIMAGE_FILE_HEADER = ^IMAGE_FILE_HEADER;

  IMAGE_NT_HEADERS = packed record
    Signature       : DWORD;
    FileHeader      : IMAGE_FILE_HEADER;
    OptionalHeader  : IMAGE_OPTIONAL_HEADER;
  end;
  PIMAGE_NT_HEADERS = ^IMAGE_NT_HEADERS;

  IMAGE_NT_HEADERS64 = packed record
    Signature       : DWORD;
    FileHeader      : IMAGE_FILE_HEADER;
    OptionalHeader  : IMAGE_OPTIONAL_HEADER64;
  end;
  PIMAGE_NT_HEADERS64 = ^IMAGE_NT_HEADERS64;


  LOADED_IMAGE = record
    ModuleName:pchar;//name of module
    hFile:thandle;//handle of file
    MappedAddress:pchar;// the base address of mapped file
    FileHeader:PIMAGE_NT_HEADERS;//The Header of the file.
    LastRvaSection:PIMAGE_SECTION_HEADER;
    NumberOfSections:integer;
    Sections:PIMAGE_SECTION_HEADER ;
    Characteristics:integer;
    fSystemImage:boolean;
    fDOSImage:boolean;
    Links:LIST_ENTRY;
    SizeOfImage:integer;
  end;
  PLOADED_IMAGE= ^LOADED_IMAGE;

  IMAGE_DOS_HEADER = packed record
    e_magic   : Word;               // Magic number ("MZ")
    e_cblp    : Word;               // Bytes on last page of file
    e_cp      : Word;               // Pages in file
    e_crlc    : Word;               // Relocations
    e_cparhdr : Word;               // Size of header in paragraphs
    e_minalloc: Word;               // Minimum extra paragraphs needed
    e_maxalloc: Word;               // Maximum extra paragraphs needed
    e_ss      : Word;               // Initial (relative) SS value
    e_sp      : Word;               // Initial SP value
    e_csum    : Word;               // Checksum
    e_ip      : Word;               // Initial IP value
    e_cs      : Word;               // Initial (relative) CS value
    e_lfarlc  : Word;               // Address of relocation table
    e_ovno    : Word;               // Overlay number
    e_res     : packed array [0..3] of Word;  // Reserved words
    e_oemid   : Word;               // OEM identifier (for e_oeminfo)
    e_oeminfo : Word;               // OEM info; e_oemid specific
    e_res2    : packed array [0..9] of Word;  // Reserved words
    e_lfanew  : Longint;            // File address of new exe header
  end;
  PIMAGE_DOS_HEADER = ^IMAGE_DOS_HEADER;


implementation

end.

