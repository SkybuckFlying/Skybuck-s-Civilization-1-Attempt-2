unit Civ.TileYields;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.Terrains,
    Civ.World,
    Civ.GameState;

type
    { Pure tile-yield and accumulation logic from CITYMGT.C. State that the
      C kept in DGROUP globals lives on this object:
        - working_tiles : set while computing a tile's yield
        - mSelectedCity : the city whose radius we are computing
        - mSelectedOwner: its owner
        - mTownResSums  : food / shields / trade / luxury accumulators
        - mCityRevelSums: alias for mTownResSums[3]
        - mTroopOver    : support overflow accumulator (AI government)
        - mMarginDemocracy: drops for units abroad (AI government)
      The `working_tiles` flag is only set in the intermediate call; it is
      there because tile_yield reads it to decide whether to apply the
      Republic trade bonus and Despotism support penalty. }
    TCivTileYields = class
    private
        mWorld        : TCivWorld;
        mState        : TCivilizationGameState;
        mSelectedCity : Integer;
        mSelectedOwner: Integer;
        mWorkingTiles : Boolean;
        mTownResSums  : array[0..3] of Integer;
        mTroopOver    : Integer;
        mMarginDemo   : Integer;
    public
        constructor Create(ParaWorld: TCivWorld);

        { Mirrors tile_yield(x, y, kind). kind: 0 = food, 1 = shields,
          2 = trade. Returns the pre-government yield. }
        function TileYield(ParaX, ParaY, ParaKind: Integer): Integer;

        { Mirrors add_tile_yield(city, index, mode). When mode = 1, draws
          tile icons; when mode <> 1, only accumulates yields and updates
          the "known tile" bits. Our port skips the drawing branch and
          keeps the pure-accumulate branch. }
        procedure AddTileYield(ParaCity, ParaIndex, ParaMode: Integer);

        { Reset the accumulators for a new city pass. }
        procedure BeginCity(ParaCity, ParaOwner: Integer);
        function  EndCityFood:    Integer;
        function  EndCityShields: Integer;
        function  EndCityTrade:   Integer;
        function  EndCityLuxury:  Integer;
        function  EndCityTroopOver: Integer;
        function  EndCityMarginDemo: Integer;
        procedure SetLuxury(ParaValue: Integer);

        property TownResFood:    Integer read (mTownResSums[0]);
        property TownResShields: Integer read (mTownResSums[1]);
        property TownResTrade:   Integer read (mTownResSums[2]);
    end;

implementation

constructor TCivTileYields.Create(ParaWorld: TCivWorld);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
end;

function TCivTileYields.TileYield(ParaX, ParaY, ParaKind: Integer): Integer;
var
    vTerrain, vTileFlags : Integer;
    vYield               : Integer;
    vKnownFlags          : Integer;
    vCityFlags           : Integer;
    vGov                 : Integer;
begin
    if not MapInBounds(ParaX, ParaY) then
        Exit(0);

    vTerrain := mWorld.TerrainAt(ParaX, ParaY);
    if mWorld.PatternedCell(vTerrain, ParaX, ParaY) then
        vYield := TerrainEntry(vTerrain + 12).Food   // note: uses +12 for the special record
    else
        vYield := TerrainEntry(vTerrain).Food;
    // Fix up per kind.
    case ParaKind of
        0 : if mWorld.PatternedCell(vTerrain, ParaX, ParaY) then
                vYield := TerrainEntry(vTerrain + 12).Food
            else
                vYield := TerrainEntry(vTerrain).Food;
        1 : if mWorld.PatternedCell(vTerrain, ParaX, ParaY) then
                vYield := TerrainEntry(vTerrain + 12).Shields
            else
                vYield := TerrainEntry(vTerrain).Shields;
        2 : if mWorld.PatternedCell(vTerrain, ParaX, ParaY) then
                vYield := TerrainEntry(vTerrain + 12).Trade
            else
                vYield := TerrainEntry(vTerrain).Trade;
    else
        vYield := 0;
    end;

    vTileFlags := mWorld.MapFlags(ParaX, ParaY);
    vKnownFlags := mWorld.KnownFlags(ParaX, ParaY);
    if (mState.mData.RuleOptions and 2) = 0 then
    begin
        if vTerrain <= 2 then
            vKnownFlags := 2
        else
            vKnownFlags := 4;
        if vTerrain <> 1 then
            vKnownFlags := vKnownFlags or 8;
    end;

    if vTerrain <> ConstTerrainOcean then
    begin
        if (ParaKind = 0) and ((vKnownFlags and 2) <> 0) then
            vYield := vYield + (-1 - Byte(WorkRule(vTerrain).IrrigationChange));
        if (ParaKind = 1) and ((vKnownFlags and 4) <> 0) then
            vYield := vYield + (-1 - Byte(WorkRule(vTerrain).MiningChange));
        if (ParaKind = 2) and ((vKnownFlags and 8) <> 0) and (vTerrain <= 2) then
            Inc(vYield);
    end;

    { Grassland and river shields: remove on coordinate pattern. }
    if (ParaKind = 1) and ((vTerrain = ConstTerrainGrassland) or
                           (vTerrain = ConstTerrainRiver)) and
       (((ParaX * 7 + ParaY * 11) and 2) <> 0) then
        vYield := 0;

    { Colossus. }
    if (vYield <> 0) and (ParaKind = 2) and
       (mState.mData.MarvelSite[3] = mSelectedCity) then
        Inc(vYield);

    { Railroad. }
    if (vTileFlags and ConstTileRailroad) <> 0 then
        vYield := vYield + vYield div 2;

    { Despotism / anarchy penalty, unless celebrating. }
    vCityFlags := mState.mData.TownBuf[mSelectedCity].Status;
    if (vYield > 2) and ((vCityFlags and $40) = 0) then
    begin
        vGov := mState.mData.CivGov[mSelectedOwner];
        if vGov <= 1 then
            Dec(vYield);
        if mWorkingTiles then
            mTroopOver := mTroopOver - 2;
    end;

    { Republic / democracy trade bonus. }
    if (vYield <> 0) and (ParaKind = 2) then
    begin
        if mWorkingTiles then
            mMarginDemo := mMarginDemo + 1;
        if (vCityFlags and $40) <> 0 then
        begin
            if mState.mData.CivGov[mSelectedOwner] >= 2 then
                Inc(vYield);
        end else if mState.mData.CivGov[mSelectedOwner] >= 4 then
            Inc(vYield);
    end;

    { Pollution halves, rounding up. }
    if (vTileFlags and ConstTilePollution) <> 0 then
        vYield := (vYield + 1) div 2;

    if vYield < 0 then
        vYield := 0;
    Result := vYield;
end;

procedure TCivTileYields.AddTileYield(ParaCity, ParaIndex, ParaMode: Integer);
var
    vTileX, vTileY : Integer;
    vKind          : Integer;
    vLeft          : Integer;
begin
    vTileX := mState.mData.TownBuf[ParaCity].X + ConstRadiusDX[ParaIndex];
    vTileY := mState.mData.TownBuf[ParaCity].Y + ConstRadiusDY[ParaIndex];

    { The C in mode 1 also draws icons here; deferred to Civ.CityScreen. }
    mWorkingTiles := ParaMode <> 1;

    for vKind := 0 to 2 do
    begin
        vLeft := TileYield(vTileX, vTileY, vKind);
        mTownResSums[vKind] := mTownResSums[vKind] + vLeft;
    end;

    mWorkingTiles := False;
end;

procedure TCivTileYields.BeginCity(ParaCity, ParaOwner: Integer);
begin
    mSelectedCity  := ParaCity;
    mSelectedOwner := ParaOwner;
    mTownResSums[0] := 0;
    mTownResSums[1] := 0;
    mTownResSums[2] := 0;
    mTownResSums[3] := 0;
    mTroopOver      := 0;
    mMarginDemo     := 0;
    mWorkingTiles   := False;
end;

function TCivTileYields.EndCityFood:    Integer; begin Result := mTownResSums[0]; end;
function TCivTileYields.EndCityShields: Integer; begin Result := mTownResSums[1]; end;
function TCivTileYields.EndCityTrade:   Integer; begin Result := mTownResSums[2]; end;
function TCivTileYields.EndCityLuxury:  Integer; begin Result := mTownResSums[3]; end;
function TCivTileYields.EndCityTroopOver: Integer; begin Result := mTroopOver; end;
function TCivTileYields.EndCityMarginDemo: Integer; begin Result := mMarginDemo; end;

procedure TCivTileYields.SetLuxury(ParaValue: Integer);
begin
    mTownResSums[3] := ParaValue;
end;

end.