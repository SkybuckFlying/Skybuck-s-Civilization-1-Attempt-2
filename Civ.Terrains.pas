unit Civ.Terrains;

// Style: semantic-prefixes v2.0

interface

uses
    Civ.Types;

{ Entry points so callers can index `[TerrainId]` without exposing
  the raw array. Index 0..11 = base terrain; 12..23 = special resource. }
function TerrainEntry(ParaIndex: Integer): TTerrainType;
function WorkRule(ParaTerrain: Integer): Pointer;

type
    TTerrainWorkRule = packed record
        IrrigationChange : SmallInt;
        IrrigationTurns  : SmallInt;
        MiningChange     : SmallInt;
        MiningTurns      : SmallInt;
        RoadChange       : SmallInt;   { 0 by default (see below) }
        RoadTurns        : SmallInt;
    end;

implementation

{ Original GAME.C data. The first four SmallInts are the initializers
  printed in GAME.C; the trailing two were zero-initialized BSS bytes.
  Two facts confirm the 12-byte layout:
    - CONTROL.C declares struct terrain_work_rule with all six fields.
    - CITYMGT.C reads .value[0] and .value[2] — which is exactly
      irrigation_change and mining_change under the 6-int layout. }
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
        (IrrigationChange: -2; IrrigationTurns:  5; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0), { 0 Desert    }
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0), { 1 Plains    }
        (IrrigationChange:  2; IrrigationTurns: 15; MiningChange:  1; MiningTurns:  1; RoadChange: 0; RoadTurns: 0), { 2 Grassland }
        (IrrigationChange: -2; IrrigationTurns:  5; MiningChange:  2; MiningTurns: 10; RoadChange: 0; RoadTurns: 0), { 3 Forest    }
        (IrrigationChange:  0; IrrigationTurns:  1; MiningChange:  6; MiningTurns:  5; RoadChange: 0; RoadTurns: 0), { 4 Hills     }
        (IrrigationChange: -1; IrrigationTurns:  5; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 5 Mountains }
        (IrrigationChange: -2; IrrigationTurns: 10; MiningChange: -4; MiningTurns: 10; RoadChange: 0; RoadTurns: 0), { 6 Tundra    }
        (IrrigationChange:  1; IrrigationTurns:  1; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 7 Arctic    }
        (IrrigationChange: -2; IrrigationTurns: 10; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 8 Swamp     }
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 9 Jungle    }
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 10 Ocean    }
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 11 River    }
        (IrrigationChange: 10; IrrigationTurns: 15; MiningChange:  2; MiningTurns: 15; RoadChange: 0; RoadTurns: 0), { 12 Oasis    }
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: 10; MiningTurns: 15; RoadChange: 0; RoadTurns: 0), { 13 Horses   }
        (IrrigationChange:  2; IrrigationTurns: 15; MiningChange:  0; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 14 Grassland}
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange: -1; MiningTurns:  0; RoadChange: 0; RoadTurns: 0), { 15 Game     }
        (IrrigationChange:  0; IrrigationTurns:  0; MiningChange: -2; MiningTurns:  5; RoadChange: 0; RoadTurns: 0), { 16 Coal     }
        (IrrigationChange: -1; IrrigationTurns:  0; MiningChange:  0; MiningTurns:  1; RoadChange: 0; RoadTurns: 0)  { 17 Gold     }
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

function WorkRule(ParaTerrain: Integer): Pointer;
begin
    if (ParaTerrain < 0) or (ParaTerrain > 17) then
    begin
        Result := nil;
        Exit;
    end;
    Result := @ConstWorkRules[ParaTerrain];
end;

end.