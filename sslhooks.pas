unit sslhooks;

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows, ctypes, Winsock;

procedure SSLHookIt;

implementation

uses
  syncobjs,
  DDetours;


var
  sendToBounce: function(s:TSocket; buf:pchar; len:tOS_INT; flags:tOS_INT;toaddr:PSockAddr; tolen:tOS_INT):tOS_INT;stdcall;
  sendBounce: function(s:TSocket;buf: Pointer; len:tOS_INT; flags:tOS_INT):tOS_INT;stdcall;
  recvBounce: function(s:TSocket;buf:pchar; len:tOS_INT; flags:tOS_INT):tOS_INT;stdcall;
  connectBounce:function(s:TSocket; addr:PSockAddr; namelen:tOS_INT):tOS_INT;stdcall;
  shutdownBounce:function(s: TSocket; how:tOS_INT):tOS_INT;stdcall;
  bindBounce:function(s:TSocket; addr: PSockaddr;namelen:tOS_INT):tOS_INT;stdcall;
  closeBounce:function(s:TSocket):tOS_INT;stdcall;
  cs: TCriticalSection;

procedure WriteStr(var ff: File; str: ansistring);
begin
  Blockwrite(ff, str[1], Length(str));
end;

procedure WriteFoo(sock: TSocket; Name: ansistring; buf: Pointer; Len: Integer; Len2: Integer);
var
  s: string;
  f: File;
begin
  s:=ParamStr(0)+'_'+IntToHex(sock, 8)+'_.txt';
  cs.Enter;
  try
  Assignfile(f, s);
  filemode:=2;
  if FileExists(s) then
  begin
    Reset(f, 1);
    Seek(f, FileSize(f));
  end
  else
    Rewrite(f, 1);
  WriteStr(f, Name+'='+IntToStr(Len)+'('+IntToStr(Len2)+')'+#13#10);
  if len>0 then
  begin
    Blockwrite(f, buf^, Len);
    WriteStr(f, #13#10+'-----------'+#13#10);
  end;
  Closefile(f);
  finally
    cs.Leave;
  end;
end;

function myclosesocket(s:TSocket):tOS_INT;stdcall;
begin
  result:=closeBounce(s);
  WriteFoo(s, 'close', nil, 0, result);
end;

function Myconnect(s:TSocket; addr:PSockAddr; namelen:tOS_INT):tOS_INT;stdcall;
begin
  result:=connectBounce(s, addr, namelen);
  WriteFoo(S, 'connect', addr, SizeOf(TSockAddr), result);
end;

function myshutdown(s:TSocket; how:tOS_INT):tOS_INT;stdcall;
begin
  result:=shutdownBounce(s, how);
  WriteFoo(S, 'shutdown', nil, 0, result);
end;

function mybind(s:TSocket; addr: PSockaddr;namelen:tOS_INT):tOS_INT;stdcall;
begin
  result:=bindBounce(s, addr, namelen);
  WriteFoo(s, 'bind', addr, SizeOf(TSockAddr), result);
end;

function Mysend(s:TSocket; buf: Pointer; len:tOS_INT; flags:tOS_INT):tOS_INT;stdcall;
begin
  result:=sendBounce(s, buf, len, flags);
  WriteFoo(S, 'send', buf, len, result);
end;

function MyRecv(s:TSocket;buf:pchar; len:tOS_INT; flags:tOS_INT):tOS_INT;stdcall;
begin
  result:=recvBounce(s, buf, len, flags);
  WriteFoo(S, 'recv', buf, result, len);
end;

function Mysendto(s:TSocket; buf:pchar; len:tOS_INT; flags:tOS_INT;toaddr:PSockAddr; tolen:tOS_INT):tOS_INT;stdcall;
begin
  result:=sendToBounce(s, buf, len, flags, toaddr, tolen);
  WriteFoo(S, 'sendto', buf, len, result);
end;

var
  SleepBounce: procedure(l: Cardinal); stdcall;

procedure MySleep(l: Cardinal); stdcall;
begin
  SleepBounce(1);
end;


(*
const SSLDLL = 'ssleay32.dll';

function sread(ssl: Pointer; buf: PChar; num: cInt): cInt; cdecl; external SSLDLL name 'SSL_read';

function MySSLRead(ssl: Pointer; buf: PChar; num: cInt):cInt; cdecl;
begin
  WriteStr('read'#13#10);
  result:=sslReadBounce(ssl, buf, num);
  cs.Enter;
  try
    WriteStr('read('+IntToHex(NativeUInt(ssl), 8)+', '+IntToStr(num)+')='+IntToStr(result)+#13#10);
    if result>0 then
    begin
      Blockwrite(ff, buf, result);
      WriteStr(#13#10+'-----------'+#13#10);
    end;
  finally
    cs.Leave;
  end;
end;

function swrite(ssl: Pointer; const buf: PChar; num: cInt):cInt;external SSLDLL name 'SSL_write';

function MySSLWrite(ssl: Pointer; const buf: PChar; num: cInt):cInt; cdecl;
begin
  WriteStr('write'#13#10);
  result:=sslWriteBounce(ssl, buf, num);
  cs.Enter;
  try
    WriteStr('write('+IntToHex(NativeUInt(ssl), 8)+', '+IntToStr(num)+')='+IntToStr(result)+#13#10);
    if num>0 then
    begin
      Blockwrite(ff, buf, num);
      WriteStr(#13#10+'-----------'+#13#10);
    end;
  finally
    cs.Leave;
  end;
end;    *)

procedure SSLHookIt;
begin
  cs:=TCriticalSection.Create;

  sendBounce:= InterceptCreate(@send, @Mysend);
  sendtoBounce:= InterceptCreate(@sendto, @Mysendto);
  recvBounce:= InterceptCreate(@recv, @MyRecv);
  bindBounce:=InterceptCreate(@bind, @mybind);
  connectBounce:=InterceptCreate(@connect, @Myconnect);
  closeBounce:=InterceptCreate(@closesocket, @myclosesocket);
  shutdownBounce:=InterceptCreate(@shutdown, @myshutdown);
  SleepBounce:=InterceptCreate(@sleep, @MySleep);
end;

end.

