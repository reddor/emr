library emrhook;

{$mode objfpc}{$H+}

uses
  Classes,
  winhooks
  { you can add units after this };

function GetVersion: longword; stdcall;
begin
  result:=WinHookVersion;
end;

exports
  GetVersion,
  StartHook;

end.

