unit wavewrite;

{$mode delphi}

interface

uses
  Classes, SysUtils, mmsystem;

type
  TWaveHeader = record
    RIFF,
    filesize,
    WAVE,
    fmt,
    fmtSize: UInt32;
    waveFormat: PCMWAVEFORMAT;
    data,
    datasize: Uint32;
  end;

  { TWaveRecorder }

  TWaveRecorder = class
  private
    FFile: file;
    FHeader: TWaveHeader;
    FCanWrite: Boolean;
  public
    constructor Create(filename: string; format: WAVEFORMATEX);
    destructor Destroy; override;

    procedure WriteData(data: Pointer; size: Integer);
  end;

implementation

{ TWaveRecorder }

function Encode4(const s: string): UInt32;
begin
  PByteArray(@result)^[0]:=Ord(s[1]);
  PByteArray(@result)^[1]:=Ord(s[2]);
  PByteArray(@result)^[2]:=Ord(s[3]);
  PByteArray(@result)^[3]:=Ord(s[4]);
end;

constructor TWaveRecorder.Create(filename: string; format: WAVEFORMATEX);
begin
  Fillchar(FHeader, SizeOf(FHeader), #0);

  FHeader.datasize:=0;
  FHeader.filesize:=sizeOf(FHeader)-8;

  FHeader.RIFF:=Encode4('RIFF');
  FHeader.WAVE:=Encode4('WAVE');
  FHeader.fmt :=Encode4('fmt ');

  FHeader.data:=Encode4('data');

  FHeader.fmtSize:=sizeOf(FHeader.waveFormat);
  FHeader.waveFormat.wf.wFormatTag:=format.wFormatTag;
  FHeader.waveFormat.wf.nChannels:=format.nChannels;
  FHeader.waveFormat.wf.nBlockAlign:=format.nBlockAlign;
  FHeader.waveFormat.wf.nSamplesPerSec:=format.nSamplesPerSec;
  FHeader.waveFormat.wf.nAvgBytesPerSec:=format.nAvgBytesPerSec;
  FHeader.waveFormat.wBitsPerSample:=format.wBitsPerSample;

  Assignfile(FFile, filename);
  {$I-}Rewrite(FFile,1);{$I+}
  if ioresult = 0 then
  begin
    FCanWrite:=True;
    Blockwrite(FFile, FHeader, SizeOf(FHeader));
  end else
    FCanWrite:=False;
end;

destructor TWaveRecorder.Destroy;
begin
  if FCanWrite then
  begin
    Seek(FFile, 0);
    Blockwrite(FFile, FHeader, SizeOf(FHeader));
    Closefile(FFile);
  end;
  inherited Destroy;
end;

procedure TWaveRecorder.WriteData(data: Pointer; size: Integer);
var
  op: Integer;
begin
  if FCanWrite and Assigned(data) then
  begin
    Inc(FHeader.filesize, size);
    Inc(FHeader.datasize, size);
    op:=FilePos(FFile);
    Seek(FFile, 0);
    Blockwrite(FFile, FHeader, SizeOf(FHeader));
    Seek(FFIle, op);
    Blockwrite(FFile, data^, size);
  end;
end;

end.

