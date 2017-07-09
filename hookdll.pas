library hookdll;

{$mode objfpc}{$H+}

uses
  Windows,
  winhooks,
  Classes,
  fasthash
  //sslhooks
  { you can add units after this };

procedure starthook(data: pointer); stdcall;
begin
  //SSLHookIt;
  HookIt(data);
end;

exports
  starthook;
initialization

end.

