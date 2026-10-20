unit Civ.FileCheck;

// Style: semantic-prefixes v2.0

interface

{ Mirrors _file_exists from FCHECK.INC. Returns 0 when the file exists,
  -1 otherwise (matching the DOS convention the game's call sites use). }
function file_exists(const ParaFileName: string; ParaMode: Integer): Integer;

implementation

uses
    System.SysUtils;

function file_exists(const ParaFileName: string; ParaMode: Integer): Integer;
begin
    if ParaMode < 0 then
        Exit(-1);   { invalid mode, matches DOS behaviour }
    if FileExists(ParaFileName) then
        Result := 0
    else
        Result := -1;
end;

end.