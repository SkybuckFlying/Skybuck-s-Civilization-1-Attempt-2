unit Civ.Terrains;

// Style: semantic-prefixes v2.0

interface

uses
    Civ.Types;

type
    TTerrainWorkRule = packed record
        IrrigationChange : SmallInt;
        IrrigationTurns  : SmallInt;
        MiningChange     : SmallInt;
        MiningTurns      : SmallInt;
        RoadChange       : SmallInt;
        RoadTurns        : SmallInt;
    end;

    { Named pointer type — Delphi does not accept `^T` as an inline return
      or variable type. Every caller uses this name. }
    PTerrainWorkRule = ^TTerrainWorkRule;

function TerrainEntry(ParaIndex: Integer): TTerrainType;
function WorkRule(ParaTerrain: Integer): PTerrainWorkRule;

{ Tile-work helpers, ported from CONTROL.C. Used by the AI and by
  Ctrl-side worker actions. TCivWorld is passed as an opaque pointer to
  avoid a circular uses: Civ.World imports Civ.Terrains, not the reverse. }
function WorkTileKind(ParaWorld: Pointer; ParaX, ParaY: Integer): Integer;
function BuildOkTiles(ParaWorld: Pointer; ParaX, ParaY: Integer): Boolean;

implementation

uses
    Civ.Core,
    Civ.World;

const
    ConstTerrains: array[0..23] of TTerrainType = (
        (Name: 'Desert';    MoveCost: 1; Defense: 2; Food: 0; Shields: 1; Trade: 0; F5: 1; F6: 14),
        (Name: 'Plains';    MoveCost: 1; Defense: 2; Food: 1; Shields: 1; Trade: 0; F5: 1; F6:  6),
        (Name: 'Grassland'; MoveCost: 1; Defense: 2; Food: 2; Shields: 1; Trade: 0; F5: 1; F6: 10),
        (Name: 'Forest';    MoveCost: 2; Defense: 3; Food: 1; Shields: 2; Trade: 0; F5: 2; F6:  2),
        (Name: 'Hills';     MoveCost: 2; Defense: 4; Food: 1; Shields: 0; Trade: 0; F5: 2; F6: 12),
        (Name: 'Mountains'; MoveCost: 3; Defense: 6; Food: 0; Shields: 1; Trade: 0; F5: 3; F6: 13),
        (Name: 'Tundra';    MoveCost: 1; Defense: 2; Food: 1; Shields: 0; Trade: 0; F5: 0; F6:  7),
        (Name: 'Arctic';    MoveCost: 2; Defense: 2; Food: 0; Shields: 0; Trade: 0; F5: 0; F6: 15),
        (Name: 'Swamp';     MoveCost: 2; Defense: 3; Food: 1; Shields: 0; Trade: 0; F5: 0; F6:  3),
        (Name: 'Jungle';    MoveCost: 2; Defense: 3; Food: 1; Shields: 0; Trade: 0; F5: 0; F6: 11),
        (Name: 'Ocean';     MoveCost: 1; Defense: 2; Food: 1; Shields: 0; Trade: 2; F5: 0; F6:  1),
        (Name: 'River';     MoveCost: 1; Defense: 3; Food: 2; Shields: 1; Trade: 1; F5: 2; F6:  9),
        (Name: 'Oasis';     MoveCost: 1; Defense: 2; Food: 3; Shields: 1; Trade: 0; F5: 1; F6: 14),
        (Name: 'Horses';    MoveCost: 1; Defense: 2; Food: 1; Shields: 3; Trade: 0; F5: 1; F6:  6),
        (Name: 'Grassland'; MoveCost: 1; Defense: 2; Food: 2; Shields: 1; Trade: 0; F5: 1; F6: 10),
        (Name: 'Game';      MoveCost: 2; Defense: 3; Food: 3; Shields: 2; Trade: 0; F5: 2; F6:  2),
        (Name: 'Coal';      MoveCost: 2; Defense: 4; Food: 1; Shields: 2; Trade: 0; F5: 2; F6: 12),
        (Name: 'Gold';      MoveCost: 3; Defense: 6; Food: 0; Shields: 1; Trade: 6; F5: 3; F6: 13),
        (Name: 'Game';      MoveCost: 1; Defense: 2; Food: 3; Shields: 0; Trade: 0; F5: 0; F6:  7),
        (Name: 'Seals';     MoveCost: 2; Defense: 2; Food: 2; Shields: 0; Trade: 0; F5: 0; F6: 15),
        (Name: 'Oil';       MoveCost: 2; Defense: 3; Food: 1; Shields: 4; Trade: 0; F5: 0; F6:  3),
        (Name: 'Gems';      MoveCost: 2; Defense: 3; Food: 1; Shields: 0; Trade: 4; F5: 0; F6: 11),
        (Name: 'Fish';      MoveCost: 1; Defense: 2; Food: 3; Shields: 0; Trade: 2; F5: 0; F6:  1),
        (Name: 'River';     MoveCost: 1; Defense: 3; Food: 2; Shields: 1; Trade: 1; F5: 2; F6:  9)
    );

    ConstWorkRules: array[0..17] of TTerrainWorkRule = (
        (IrrigationChange: -2; IrrigationTurns:  5; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  2; IrrigationTurns: 15; MiningChange:  1; MiningTurns:  1; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -2; IrrigationTurns:  5; MiningChange:  2; MiningTurns: 10; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  0; IrrigationTurns:  1; MiningChange:  6; MiningTurns:  5; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -1; IrrigationTurns:  5; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -2; IrrigationTurns: 10; MiningChange: -4; MiningTurns: 10; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  1; IrrigationTurns:  1; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -2; IrrigationTurns: 10; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: 10; IrrigationTurns: 15; MiningChange:  2; MiningTurns: 15; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: 10; MiningTurns: 15; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  2; IrrigationTurns: 15; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0),
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange:  0; MiningTurns:  1; RoadChange: 0; RoadTurns: 0)
    );

function TerrainEntry(ParaIndex: Integer): TTerrainType;
begin
    if (ParaIndex < 0) or (ParaIndex > 23) then
    begin
        FillChar(Result, SizeOf(Result), 0);
        Exit;
    end;
    Result := ConstTerrains[ParaIndex];
end;

function WorkRule(ParaTerrain: Integer): PTerrainWorkRule;
begin
    if (ParaTerrain < 0) or (ParaTerrain > 17) then
        Exit(nil);
    Result := @ConstWorkRules[ParaTerrain];
end;

function WorkTileKind(ParaWorld: Pointer; ParaX, ParaY: Integer): Integer;
var
    vWorld : TCivWorld;
    vRule  : PTerrainWorkRule;
    vTerrain : Integer;
begin
    vWorld := TCivWorld(ParaWorld);
    if (vWorld.MapFlags(ParaX, ParaY) and 7) <> 0 then
        Exit(0);
    vTerrain := vWorld.TerrainAt(ParaX, ParaY);
    vRule := WorkRule(vTerrain);
    if vRule = nil then
        Exit(0);
    if vRule^.MiningChange <= -3 then
        Exit(2);
    if (vRule^.IrrigationChange = -2) and BuildOkTiles(ParaWorld, ParaX, ParaY) then
        Exit(1);
    Result := 0;
end;

function BuildOkTiles(ParaWorld: Pointer; ParaX, ParaY: Integer): Boolean;
var
    vWorld : TCivWorld;
    vDir, vNX, vNY, vT, vF : Integer;
begin
    vWorld := TCivWorld(ParaWorld);
    if vWorld.TerrainAt(ParaX, ParaY) = ConstTerrainRiver then
        Exit(True);
    for vDir := 1 to 8 do
    begin
        if (vDir and 1) = 0 then
            Continue;
        vNX := WrapX(ParaX + ConstSpiralX[vDir]);
        vNY := ParaY + ConstSpiralY[vDir];
        vT := vWorld.TerrainAt(vNX, vNY);
        vF := vWorld.MapFlags(vNX, vNY);
        if (vF and ConstTileCity) <> 0 then
            Continue;
        if (vT = ConstTerrainRiver) or (vT = ConstTerrainOcean) then
            Exit(True);
        if (vF and ConstTileIrrigation) <> 0 then
            Exit(True);
    end;
    Result := False;
end;

end.