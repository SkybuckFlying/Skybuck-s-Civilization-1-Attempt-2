unit Civ.Types;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils;

type
    TCStr12 = array[0..11] of AnsiChar;
    TCStr13 = array[0..12] of AnsiChar;
    TCStr14 = array[0..13] of AnsiChar;
    TCStr16 = array[0..15] of AnsiChar;
    TCStr20 = array[0..19] of AnsiChar;
    TCStr24 = array[0..23] of AnsiChar;

    TCityCreateMethod     = function(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer of object;
    TCreateUnitMethod     = function(ParaOwner, ParaType, ParaX, ParaY: Integer): Integer of object;
    TDropUnitMethod       = procedure(ParaGroup, ParaIndex: Integer) of object;
    TFindSlotMethod       = function(ParaCiv, ParaCity: Integer): Integer of object;
    TAdvanceValueMethod   = function(ParaCiv, ParaAdvance: Integer): Integer of object;
    TSetGovernmentMethod  = procedure(ParaCiv, ParaGov: Integer) of object;

    TTerrainType = packed record
        Name     : TCStr12;
        MoveCost : Byte;
        Defense  : ShortInt;
        Food     : Byte;
        Shields  : Byte;
        Trade    : Byte;
        F5       : Byte;
        F6       : Byte;
    end;

    TUnitType = packed record
        Name       : TCStr12;
        ObsoleteBy : SmallInt;
        Domain     : SmallInt;
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

    TCity = packed record
        Buildings   : LongInt;
        X, Y        : Byte;
        Status      : ShortInt;
        Size        : ShortInt;
        VisibleSize : ShortInt;
        Production  : ShortInt;
        Trade       : ShortInt;
        Owner       : ShortInt;
        FoodBox     : SmallInt;
        ShieldBox   : SmallInt;
        Workers     : LongInt;
        Specialists : SmallInt;
        NameId      : ShortInt;
        Routes      : array[0..2] of ShortInt;
        Garrison    : array[0..1] of ShortInt;
    end;

    { Status and Visibility are bitfields, treated as unsigned throughout.
      The C declared them `signed char` but every operation is bitwise on
      the full byte, so `Byte` is the correct analogue. }
    TUnit = packed record
        Status     : Byte;
        X, Y       : Byte;
        UnitType   : ShortInt;
        Moves      : ShortInt;
        Fuel       : ShortInt;
        GotoX      : ShortInt;
        GotoY      : ShortInt;
        F8         : ShortInt;
        Visibility : Byte;
        Next       : ShortInt;
        HomeCity   : ShortInt;
    end;

const
    ConstUnitSentry     = $01;
    ConstUnitBuild      = $02;
    ConstUnitFortifying = $04;
    ConstUnitFortified  = $08;
    ConstUnitBusy       = $10;
    ConstUnitVeteran    = $20;
    ConstUnitIrrigate   = $40;
    ConstUnitMine       = $80;

    ConstBldPalace     = $00000001;
    ConstBldCityWalls  = $00000080;
    ConstBldSDI        = $00010000;

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

function FixedCharsToString(const ParaChars: array of AnsiChar): string;
function FixedCharsToStringTrim(const ParaChars: array of AnsiChar): string;
function StringToFixedChars(const ParaText: string; var ParaDest: array of AnsiChar): Integer;

implementation

function FixedCharsToString(const ParaChars: array of AnsiChar): string;
var
    vAnsi : AnsiString;
    vLen, vI : Integer;
begin
    vLen := Length(ParaChars);
    vI := 0;
    while (vI < vLen) and (ParaChars[vI] <> #0) do Inc(vI);
    SetLength(vAnsi, vI);
    for var vK := 0 to vI - 1 do vAnsi[vK + 1] := ParaChars[vK];
    Result := string(vAnsi);
end;

function FixedCharsToStringTrim(const ParaChars: array of AnsiChar): string;
begin
    Result := FixedCharsToString(ParaChars).TrimRight;
end;

function StringToFixedChars(const ParaText: string; var ParaDest: array of AnsiChar): Integer;
var
    vAnsi : AnsiString;
    vLen : Integer;
begin
    vAnsi := AnsiString(ParaText);
    vLen := Length(vAnsi);
    if vLen > Length(ParaDest) - 1 then vLen := Length(ParaDest) - 1;
    for var vI := 0 to Length(ParaDest) - 1 do ParaDest[vI] := #0;
    for var vI := 0 to vLen - 1 do ParaDest[vI] := vAnsi[vI + 1];
    Result := vLen;
end;

end.