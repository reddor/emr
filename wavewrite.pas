unit wavewrite;

{$mode delphi}

interface

uses
  Classes, SysUtils, mmsystem, syncobjs;

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
    FCurrent: LPWAVEHDR;
    FCurrentWritten: longword;
    FLastTimestamp: longword;
  public
    constructor Create(filename: string; format: WAVEFORMATEX);
    destructor Destroy; override;

    procedure Flush;
    procedure WriteData(data: Pointer; size: Integer);
    procedure WriteWaveHdr(data: LPWAVEHDR; Timestamp: longword);
    procedure WritePartially(Timestamp: longword);
  end;

  { TSlowWriterThread }

  TSlowWriterThread = class(TThread)
  private
    FRecorders: array of TWaveRecorder;
    FCS: TCriticalSection;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterRecorder(Rec: TWaveRecorder);
    procedure UnregisterRecorder(Rec: TWaveRecorder);
  end;

var
  SlowWriterThread: TSlowWriterThread;

implementation

uses
  winhooks;

{ TWaveRecorder }

function Encode4(const s: string): UInt32;
begin
  PByteArray(@result)^[0]:=Ord(s[1]);
  PByteArray(@result)^[1]:=Ord(s[2]);
  PByteArray(@result)^[2]:=Ord(s[3]);
  PByteArray(@result)^[3]:=Ord(s[4]);
end;

{ TSlowWriterThread }

procedure TSlowWriterThread.Execute;
var
  i: Integer;
  t: longword;
begin
  while not Terminated do
  begin
    t:=GetTickCount;
    fcs.Enter;
    for i:=0 to Length(FRecorders)-1 do
      FRecorders[i].WritePartially(t);
    FCS.Leave;
    Sleep(1000);
  end;
end;

constructor TSlowWriterThread.Create;
begin
  FCS:=TCriticalSection.Create;
  Setlength(FRecorders, 0);
  inherited Create(False);
end;

destructor TSlowWriterThread.Destroy;
begin
  inherited Destroy;
end;

procedure TSlowWriterThread.RegisterRecorder(Rec: TWaveRecorder);
var
  i: Integer;
begin
  FCS.Enter;
  i:=Length(FRecorders);
  Setlength(FRecorders, i+1);
  FRecorders[i]:=Rec;
  FCS.Leave;
end;

procedure TSlowWriterThread.UnregisterRecorder(Rec: TWaveRecorder);
var
  i: Integer;
begin
  FCS.Enter;
  for i:=0 to Length(FRecorders)-1 do
  if FRecorders[i] = Rec then
  begin
    FRecorders[i]:=FRecorders[Length(FRecorders)-1];
    Setlength(FRecorders, LEngth(FRecorders)-1);
    Break;
  end;
  FCS.Leave;
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

  FCurrent:=nil;

  Assignfile(FFile, filename);
  {$I-}Rewrite(FFile,1);{$I+}
  if ioresult = 0 then
  begin
    FCanWrite:=True;
    Blockwrite(FFile, FHeader, SizeOf(FHeader));
  end else
    FCanWrite:=False;

  if Assigned(SlowWriterThread) then
    SlowWriterThread.RegisterRecorder(Self);
end;

destructor TWaveRecorder.Destroy;
begin
  if Assigned(SlowWriterThread) then
    SlowWriterThread.UnregisterRecorder(Self);

  if FCanWrite then
  begin
    Flush;
    Seek(FFile, 0);
    Blockwrite(FFile, FHeader, SizeOf(FHeader));
    Closefile(FFile);
  end;
  inherited Destroy;
end;

procedure TWaveRecorder.Flush;
begin
  if not Assigned(FCurrent) then
    Exit;
  WriteData(@FCurrent^.lpData[FCurrentWritten], FCurrent^.dwBufferLength - FCurrentWritten);
  FCurrent:=nil;
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

procedure TWaveRecorder.WriteWaveHdr(data: LPWAVEHDR; Timestamp: longword);
begin
  Flush;

  // for short buffers we assume that they are properly filled and can be immediately written to file
  if data^.dwBufferLength div FHeader.waveFormat.wf.nSamplesPerSec < 5 then
  begin
    WriteData(data^.lpData, data^.dwBufferLength);
    Exit;
  end;

  // for longer buffers, we can try to write the buffer over time
  FCurrent:=data;
  FCurrentWritten:=0;
  FLastTimestamp:=Timestamp;
end;

procedure TWaveRecorder.WritePartially(Timestamp: longword);
var
  dataToWrite: longword;
begin
  if not Assigned(FCurrent) then
    Exit;

  if Timestamp - FLastTimestamp >= 1000 then
  begin
    datatowrite:=((Timestamp - FLastTimestamp) * FHeader.waveFormat.wf.nAvgBytesPerSec) div 1000;

    if datatowrite > FCurrent^.dwBufferLength - FCurrentWritten then
      datatowrite:=FCurrent^.dwBufferLength - FCurrentWritten;
    WriteData(@FCurrent^.lpData[FCurrentWritten], dataToWrite);
    Inc(FCurrentWritten, dataToWrite);
    if FCurrentWritten = FCurrent^.dwBufferLength then
      FCurrent:=nil;
    FLastTimestamp:=Timestamp;
  end;
end;

initialization
  SlowWriterThread:=nil;
end.

