unit Civ.Core;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils;

const
    { Directions 1..8: north, then clockwise. Index 0 is the centre.
      Indices 9..48 are the outer rings used by wide-sight and city-radius
      checks. Values match GAME.C spiral_x[] and spiral_y[] exactly. }
    ConstSpiralX: array[0..48] of ShortInt = (
         0,  0,  1,  1,  1,  0, -1, -1, -1,  0,  1,  2,  2,  2,  1,  0,
        -1, -2, -2, -2, -1,  2,  2, -2, -2,  0,  1,  2,  3,  3,  3,  3,
         3,  2,  1,  0, -1, -2, -3, -3, -3, -3, -3, -2, -1,  3,  3, -3,
        -3
    );

    ConstSpiralY: array[0..48] of ShortInt = (
         0, -1, -1,  0,  1,  1,  1,  0, -1, -2, -2, -1,  0,  1,  2,  2,
         2,  1,  0, -1, -2,  2, -2, -2,  2, -3, -3, -3, -2, -1,  0,  1,
         2,  3,  3,  3,  3,  3,  2,  1,  0, -1, -2, -3, -3,  3, -3,  3,
        -3
    );

    { City work radius: 21 tiles (5×5 minus corners), tile 20 is the centre. }
    ConstRadiusDX: array[0..20] of ShortInt = (
         0,  1,  0, -1,  1,  1, -1, -1,  0,  2,  0, -2, -1,  1,  2,  2,
         1, -1, -2, -2,  0
    );
    ConstRadiusDY: array[0..20] of ShortInt = (
        -1,  0,  1,  0, -1,  1,  1, -1, -2,  0,  2,  0, -2, -2, -1,  1,
         2,  2,  1, -1,  0
    );

type
    { Microsoft C 5.1 rand(): holdrand = holdrand * 214013 + 2531011;
      return (holdrand >> 16) & 0x7FFF.
      Preserving this is required for world regeneration to match the
      original binary; the save file records only the seed. }
    TCivRandom = class
    private
        mHoldRand : LongWord;
    public
        constructor Create(ParaSeed: Integer = 1);
        procedure Reseed(ParaSeed: Integer);
        function Next15: SmallInt;
        { rand_scaled(value) = ((long)value * rand()) >> 15. }
        function Scaled(ParaValue: Integer): Integer;
    end;

function Clamp(ParaValue, ParaLower, ParaUpper: Integer): Integer;
function WrapX(ParaX: Integer): Integer;
function MapDist(ParaX1, ParaX2, ParaY1, ParaY2: Integer): Integer;
function HalfDist(ParaX, ParaY: Integer): Integer;
function DistanceTwice(ParaX, ParaY: Integer): Integer;
function MapInBounds(ParaX, ParaY: Integer): Boolean;
function MapRandom(ParaValue: Integer): Integer;

implementation

function Clamp(ParaValue, ParaLower, ParaUpper: Integer): Integer;
begin
    Result := ParaValue;
    if Result < ParaLower then Result := ParaLower;
    if Result > ParaUpper then Result := ParaUpper;
end;

function WrapX(ParaX: Integer): Integer;
begin
    if ParaX < 0 then
        Result := ParaX + 80
    else if ParaX >= 80 then
        Result := ParaX - 80
    else
        Result := ParaX;
end;

function HalfDist(ParaX, ParaY: Integer): Integer;
var
    vX, vY : Integer;
begin
    vX := Abs(ParaX);
    vY := Abs(ParaY);
    if vX > vY then
        Result := vX + vY div 2
    else
        Result := vY + vX div 2;
end;

function MapDist(ParaX1, ParaX2, ParaY1, ParaY2: Integer): Integer;
var
    vX, vY : Integer;
begin
    vX := Abs(ParaX1 - ParaX2);
    if vX > 40 then
        vX := 80 - vX;
    vY := Abs(ParaY1 - ParaY2);
    Result := HalfDist(vX, vY);
end;

function DistanceTwice(ParaX, ParaY: Integer): Integer;
var
    vX, vY : Integer;
begin
    vX := Abs(ParaX);
    if vX > 40 then
        vX := 80 - vX;
    vY := Abs(ParaY);
    if vX > vY then
        Result := vX * 2 + vY
    else
        Result := vY * 2 + vX;
end;

function MapInBounds(ParaX, ParaY: Integer): Boolean;
begin
    Result := (ParaX >= 0) and (ParaX < 80) and
              (ParaY >= 0) and (ParaY < 50);
end;

function MapRandom(ParaValue: Integer): Integer;
begin
    if ParaValue > 0 then
        Result := 1
    else if ParaValue < 0 then
        Result := -1
    else
        Result := 0;
end;

{ TCivRandom }

constructor TCivRandom.Create(ParaSeed: Integer);
begin
    inherited Create;
    Reseed(ParaSeed);
end;

procedure TCivRandom.Reseed(ParaSeed: Integer);
begin
    mHoldRand := LongWord(ParaSeed);
end;

function TCivRandom.Next15: SmallInt;
begin
    mHoldRand := LongWord(UInt64(mHoldRand) * 214013 + 2531011);
    Result := SmallInt((mHoldRand shr 16) and $7FFF);
end;

function TCivRandom.Scaled(ParaValue: Integer): Integer;
begin
    Result := Integer(Int64(ParaValue) * Next15) shr 15;
end;

end.