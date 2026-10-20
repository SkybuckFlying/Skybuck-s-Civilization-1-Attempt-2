unit Civ.Types;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils;

type
    { Fixed-size string buffer as stored in SVE / DGROUP.
      C `char name[12]` becomes `array[0..11] of AnsiChar`. }
    TCStr12 = array[0..11] of AnsiChar;
    TCStr13 = array[0..12] of AnsiChar;
    TCStr14 = array[0..13] of AnsiChar;
    TCStr16 = array[0..15] of AnsiChar;
    TCStr20 = array[0..19] of AnsiChar;
    TCStr24 = array[0..23] of AnsiChar;

    { Terrain type — DGROUP 0x0282, 19 bytes. Matches C struct terrain_type. }
    TTerrainType = packed record
        Name     : TCStr12;
        MoveCost : Byte;
        Defense  : ShortInt;   { halves: 2,3,4,6 }
        Food     : Byte;
        Shields  : Byte;
        Trade    : Byte;
        F5       : Byte;
        F6       : Byte;
    end;

    { Unit type — DGROUP 0x112A, 34 bytes. Matches C struct unit_type. }
    TUnitType = packed record
        Name       : TCStr12;
        ObsoleteBy : SmallInt;
        Domain     : SmallInt;  { 0 land, 1 air, 2 sea }
        Moves      : SmallInt;
        Fuel       : SmallInt;
        Attack     : SmallInt;
        Defense    : SmallInt;
        Cost       : SmallInt;
        Sight      : SmallInt;
        Capacity   : SmallInt;
        Role       : SmallInt;
        Prereq     : SmallInt;
    end;

    { City — DGROUP 0x70EC, 28 bytes. Matches C struct city. }
    TCity = packed record
        Buildings   : LongInt;
        X, Y        : Byte;
        Status      : ShortInt;
        Size        : ShortInt;
        VisibleSize : ShortInt;
        Production  : ShortInt;   { >=0: unit id; <0: -improvement id }
        Trade       : ShortInt;
        Owner       : ShortInt;
        FoodBox     : SmallInt;
        ShieldBox   : SmallInt;
        Workers     : LongInt;    { bits 0..20 tiles, 26..31 specialists }
        Specialists : SmallInt;   { 8 two-bit specialist types }
        NameId      : ShortInt;   { unsigned index into place_name }
        Routes      : array[0..2] of ShortInt;
        Garrison    : array[0..1] of ShortInt;  { bit 0x40 = veteran }
    end;

    { Unit — DGROUP 0x81D4, 12 bytes. Matches C struct unit. }
    TUnit = packed record
        Status     : ShortInt;
        X, Y       : Byte;
        UnitType   : ShortInt;   { index into utypes; -1 means free }
        Moves      : ShortInt;   { thirds; 3 = one full move }
        Fuel       : ShortInt;
        GotoX      : ShortInt;
        GotoY      : ShortInt;
        F8         : ShortInt;
        Visibility : ShortInt;
        Next       : ShortInt;   { stack ring link; -1 alone }
        HomeCity   : ShortInt;
    end;

    PUnit = ^TUnit;
    PCity = ^TCity;

const
    { Unit status bits. }
    ConstUnitSentry    = $01;
    ConstUnitBuild     = $02;   { settler road/rail; aircraft return }
    ConstUnitFortifying= $04;
    ConstUnitFortified = $08;
    ConstUnitBusy      = $10;   { AI: assigned this turn }
    ConstUnitVeteran   = $20;
    ConstUnitIrrigate  = $40;   { settler irrigate }
    ConstUnitMine      = $80;   { settler mine }

    { City building mask (improvement n uses bit n-1). }
    ConstBldPalace     = $00000001;
    ConstBldCityWalls  = $00000080;
    ConstBldSDI        = $00010000;

    { Treaty bits. }
    ConstTreatyContact       = $0001;
    ConstTreatyPeace         = $0002;
    ConstTreatyAlliance      = $0004;
    ConstTreatyGrievance     = $0008;
    ConstTreatyMetThisPeriod = $0010;
    ConstTreatyFoughtThisTurn= $0020;
    ConstTreatyEmbassy       = $0040;
    ConstTreatyNuclear       = $0080;
    ConstTreatyPlanCancel    = $0100;
    ConstTreatySneakAttack   = $0200;

    { Specialists — two bits per slot in TCity.Specialists. }
    ConstSpecialistUnused    = 0;
    ConstSpecialistTaxman    = 1;
    ConstSpecialistScientist = 2;
    ConstSpecialistEntertain = 3;

{ Converts a fixed-width char array to a Unicode string up to the first NUL.
  Trailing spaces are preserved (binary fidelity). }
function FixedCharsToString(const ParaChars: array of AnsiChar): string;

{ Same but trims trailing spaces — useful for display. }
function FixedCharsToStringTrim(const ParaChars: array of AnsiChar): string;

{ Writes a string into a fixed-width buffer; null-pads and does not
  overflow. Returns the number of bytes written (excluding the final NUL). }
function StringToFixedChars(const ParaText: string;
    var ParaDest: array of AnsiChar): Integer;

implementation

function FixedCharsToString(const ParaChars: array of AnsiChar): string;
var
    vAnsi : AnsiString;
    vLen  : Integer;
    vI    : Integer;
begin
    vLen := Length(ParaChars);
    vI   := 0;
    while (vI < vLen) and (ParaChars[vI] <> #0) do
    begin
        Inc(vI);
    end;
    SetLength(vAnsi, vI);
    for var vK := 0 to vI - 1 do
    begin
        vAnsi[vK + 1] := ParaChars[vK];
    end;
    Result := string(vAnsi);
end;

function FixedCharsToStringTrim(const ParaChars: array of AnsiChar): string;
begin
    Result := FixedCharsToString(ParaChars).TrimRight;
end;

function StringToFixedChars(const ParaText: string;
    var ParaDest: array of AnsiChar): Integer;
var
    vAnsi : AnsiString;
    vLen  : Integer;
begin
    vAnsi := AnsiString(ParaText);
    vLen  := Length(vAnsi);
    if vLen > Length(ParaDest) - 1 then
    begin
        vLen := Length(ParaDest) - 1;
    end;
    for var vI := 0 to Length(ParaDest) - 1 do
    begin
        ParaDest[vI] := #0;
    end;
    for var vI := 0 to vLen - 1 do
    begin
        ParaDest[vI] := vAnsi[vI + 1];
    end;
    Result := vLen;
end;

end.