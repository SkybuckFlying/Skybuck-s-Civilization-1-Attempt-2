unit Civ.World;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.MapFile,
    Civ.GameState;

const
    { Tile flag bits — memory_layout.md }
    ConstTileCity       = $01;
    ConstTileIrrigation = $02;
    ConstTileMine       = $04;
    ConstTileRoad       = $08;
    ConstTileRailroad   = $10;
    ConstTileFortress   = $20;
    ConstTilePollution  = $40;

    { Terrain IDs — enum_unit_terrain.md }
    ConstTerrainDesert    = 0;
    ConstTerrainPlains    = 1;
    ConstTerrainGrassland = 2;
    ConstTerrainForest    = 3;
    ConstTerrainHills     = 4;
    ConstTerrainMountains = 5;
    ConstTerrainTundra    = 6;
    ConstTerrainArctic    = 7;
    ConstTerrainSwamp     = 8;
    ConstTerrainJungle    = 9;
    ConstTerrainOcean     = 10;
    ConstTerrainRiver     = 11;

type
    { Reads and writes the map database (page 2). Owns the *tile data* layer.
      Unit-stack bookkeeping (put_unit, lift_unit, map_stack) lives on
      TCivUnitManager because it needs armydata; ScoreGroupRecord lives here
      because it only needs state. }
    TCivWorld = class
    private
        mState : TCivilizationGameState;
        mMap   : TMapPage;

        { Runtime-only coarse sea connectivity — 20×13 grid. Populated by
          LinkSeas during generation; read by TCivPathfinder. Not in the SVE
          file, so it must be rebuilt when loading a save. }
        mCoarseOceanMap : array[0..19, 0..12] of Byte;

        function  GetCoarseOceanMap(ParaX, ParaY: Integer): Byte;
        procedure SetCoarseOceanMap(ParaX, ParaY: Integer; ParaValue: Byte);
        function  GetCoarseGroundWay(ParaX, ParaY: Integer): Byte;
        procedure SetCoarseGroundWay(ParaX, ParaY: Integer; ParaValue: Byte);
    public
        constructor Create(ParaState: TCivilizationGameState; ParaMap: TMapPage);
        destructor Destroy; override;

        property State: TCivilizationGameState read mState;
        property Map:   TMapPage                read mMap;

        { --- Raw page access ---------------------------------------------- }
        function  RawPixel(ParaX, ParaY: Integer): Byte;
        procedure SetRawPixel(ParaX, ParaY: Integer; ParaValue: Byte);

        { --- Terrain ------------------------------------------------------ }
        function  TerrainAt(ParaX, ParaY: Integer): Integer;
        procedure SetTerrainByte(ParaX, ParaY: Integer; ParaValue: Byte);
        function  IsOcean(ParaX, ParaY: Integer): Boolean;
        function  IsLand(ParaX, ParaY: Integer): Boolean;
        function  TerrainMoveCost(ParaX, ParaY: Integer): Integer;
        function  TerrainDefense(ParaX, ParaY: Integer): Integer;

        { --- Ownership / city -------------------------------------------- }
        function  MapCity(ParaX, ParaY: Integer): Integer;
        function  MapOwner(ParaX, ParaY: Integer): Integer;
        function  IsCityTile(ParaX, ParaY: Integer): Boolean;
        function  CityAtTile(ParaX, ParaY: Integer): Integer;

        { --- Flags -------------------------------------------------------- }
        function  MapFlags(ParaX, ParaY: Integer): Integer;
        function  KnownFlags(ParaX, ParaY: Integer): Integer;
        procedure MapMark(ParaX, ParaY: Integer);
        procedure FlagTile(ParaFlag, ParaX, ParaY: Integer);
        procedure Unflag(ParaFlag, ParaX, ParaY: Integer);

        { --- Site values -------------------------------------------------- }
        function  SiteValue(ParaX, ParaY: Integer): Integer;
        procedure SetSiteValue(ParaX, ParaY, ParaValue: Integer);
        function  SavedSiteValue(ParaX, ParaY: Integer): Integer;
        procedure SetSavedSiteValue(ParaX, ParaY, ParaValue: Integer);

        { --- Regions ------------------------------------------------------ }
        function  RegionKey(ParaX, ParaY: Integer): Integer;
        function  MapRegion(ParaX, ParaY: Integer): Integer;
        function  ContinentSpan(ParaIsSea: Boolean; ParaRegion: Integer): Integer;

        { --- Coarse connectivity (20×13) --------------------------------- }
        property CoarseOceanMap[ParaX, ParaY: Integer]: Byte
            read GetCoarseOceanMap write SetCoarseOceanMap;
        property CoarseGroundWay[ParaX, ParaY: Integer]: Byte
            read GetCoarseGroundWay write SetCoarseGroundWay;
        procedure ClearCoarseOceanMap;

        { --- Exploration -------------------------------------------------- }
        function  IsExplored(ParaCiv, ParaX, ParaY: Integer): Boolean;
        procedure SetExplored(ParaCiv, ParaX, ParaY: Integer; ParaValue: Boolean);
        procedure RevealRadius(ParaCiv, ParaX, ParaY, ParaRadius: Integer);
        procedure ClearExploration(ParaCiv: Integer);
        function  ExplorationByte(ParaX, ParaY: Integer): Byte;
        procedure SetExplorationByte(ParaX, ParaY: Integer; ParaValue: Byte);

        { --- Occupancy ---------------------------------------------------- }
        function  OccupancyByte(ParaX, ParaY: Integer): Byte;
        procedure Occupy(ParaX, ParaY: Integer);
        procedure ClearOccupied(ParaX, ParaY: Integer);

        { --- Predicates --------------------------------------------------- }
        function  PatternedCell(ParaX, ParaY: Integer): Boolean;
        function  HasHut(ParaTerrain, ParaX, ParaY: Integer): Boolean;

        { --- Combat scoring ---------------------------------------------- }
        { Score of a defender candidate. Returns 0 if the unit is ineligible
          (land unit at sea, or empty slot). Caller keeps the running max. }
        function  ScoreGroupRecord(ParaGroup, ParaIndex: Integer): Integer;

        { --- Neighbourhood ----------------------------------------------- }
        function  AdjacentForeignTile(ParaCiv, ParaX, ParaY: Integer): Boolean;
        function  CountNeighbours(ParaX, ParaY: Integer;
            ParaPredicate: TFunc<Integer, Integer, Boolean>): Integer;
    end;

const
    { The 16-entry terrain translation table from MAP.C. Bytes 0, 4, 5 and 8
      map to -1; callers that need a valid terrain must check for that. }
    ConstTerrainMap: array[0..15] of ShortInt = (
        -1, 10, 3, 8, -1, -1, 1, 6, -1, 11, 2, 9, 4, 5, 0, 7
    );

implementation

uses
    Civ.Terrains;   { TerrainEntry }

constructor TCivWorld.Create(ParaState: TCivilizationGameState; ParaMap: TMapPage);
begin
    inherited Create;
    mState := ParaState;
    mMap   := ParaMap;
    ClearCoarseOceanMap;
end;

destructor TCivWorld.Destroy;
begin
    { Caller owns mState and mMap. }
    inherited;
end;

{ -------------------------------------------------------------------------
  Raw page access.
  ------------------------------------------------------------------------- }
function TCivWorld.RawPixel(ParaX, ParaY: Integer): Byte;
begin
    Result := mMap.Pixel(ParaX, ParaY);
end;

procedure TCivWorld.SetRawPixel(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    mMap.SetPixel(ParaX, ParaY, ParaValue);
end;

{ -------------------------------------------------------------------------
  Terrain.
  ------------------------------------------------------------------------- }
function TCivWorld.TerrainAt(ParaX, ParaY: Integer): Integer;
var
    vByte : Byte;
begin
    vByte := mMap.Pixel(ParaX, ParaY);
    Result := ConstTerrainMap[vByte];
end;

procedure TCivWorld.SetTerrainByte(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    mMap.SetPixel(ParaX, ParaY, ParaValue);
end;

function TCivWorld.IsOcean(ParaX, ParaY: Integer): Boolean;
begin
    Result := TerrainAt(ParaX, ParaY) = ConstTerrainOcean;
end;

function TCivWorld.IsLand(ParaX, ParaY: Integer): Boolean;
begin
    Result := not IsOcean(ParaX, ParaY);
end;

function TCivWorld.TerrainMoveCost(ParaX, ParaY: Integer): Integer;
begin
    Result := TerrainEntry(TerrainAt(ParaX, ParaY)).MoveCost;
end;

function TCivWorld.TerrainDefense(ParaX, ParaY: Integer): Integer;
begin
    Result := TerrainEntry(TerrainAt(ParaX, ParaY)).Defense;
end;

{ -------------------------------------------------------------------------
  Ownership and city tiles.
  ------------------------------------------------------------------------- }
function TCivWorld.MapCity(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX + 160, ParaY) and 7;
end;

function TCivWorld.MapOwner(ParaX, ParaY: Integer): Integer;
var
    v : Byte;
begin
    v := mMap.Pixel(ParaX + 160, ParaY);
    if (v and 8) <> 0 then
        Result := v and 7
    else
        Result := -1;
end;

function TCivWorld.IsCityTile(ParaX, ParaY: Integer): Boolean;
begin
    Result := (MapFlags(ParaX, ParaY) and ConstTileCity) <> 0;
end;

function TCivWorld.CityAtTile(ParaX, ParaY: Integer): Integer;
var
    vI : Integer;
begin
    if not IsCityTile(ParaX, ParaY) then
        Exit(-1);
    for vI := 0 to 127 do
    begin
        if (mState.mData.TownBuf[vI].Status <> -1) and
           (mState.mData.TownBuf[vI].X = ParaX) and
           (mState.mData.TownBuf[vI].Y = ParaY) then
            Exit(vI);
    end;
    Result := -1;
end;

{ -------------------------------------------------------------------------
  Flags.
  ------------------------------------------------------------------------- }
function TCivWorld.MapFlags(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX, ParaY + 100) or
             (mMap.Pixel(ParaX, ParaY + 150) shl 4);
end;

function TCivWorld.KnownFlags(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX + 80, ParaY + 100) or
             (mMap.Pixel(ParaX + 80, ParaY + 150) shl 4);
end;

procedure TCivWorld.MapMark(ParaX, ParaY: Integer);
begin
    mMap.SetPixel(ParaX + 80, ParaY + 100, mMap.Pixel(ParaX, ParaY + 100));
    mMap.SetPixel(ParaX + 80, ParaY + 150, mMap.Pixel(ParaX, ParaY + 150));
end;

procedure TCivWorld.FlagTile(ParaFlag, ParaX, ParaY: Integer);
begin
    if ParaFlag <> 0 then
    begin
        if ParaFlag < 16 then
            mMap.SetPixel(ParaX, ParaY + 100,
                mMap.Pixel(ParaX, ParaY + 100) or Byte(ParaFlag))
        else
            mMap.SetPixel(ParaX, ParaY + 150,
                mMap.Pixel(ParaX, ParaY + 150) or Byte(ParaFlag shr 4));
    end else
    begin
        mMap.SetPixel(ParaX, ParaY + 100, 0);
        mMap.SetPixel(ParaX, ParaY + 150, 0);
    end;
end;

procedure TCivWorld.Unflag(ParaFlag, ParaX, ParaY: Integer);
begin
    if (ParaFlag and $0F) <> 0 then
        mMap.SetPixel(ParaX, ParaY + 100,
            mMap.Pixel(ParaX, ParaY + 100) and not Byte(ParaFlag));
    if (ParaFlag and $F0) <> 0 then
        mMap.SetPixel(ParaX, ParaY + 150,
            mMap.Pixel(ParaX, ParaY + 150) and not Byte(ParaFlag shr 4));
end;

{ -------------------------------------------------------------------------
  Site values — the "current" and "saved original" tiers.
  ------------------------------------------------------------------------- }
function TCivWorld.SiteValue(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX + 80, ParaY);
end;

procedure TCivWorld.SetSiteValue(ParaX, ParaY, ParaValue: Integer);
begin
    mMap.SetPixel(ParaX + 80, ParaY, Byte(ParaValue));
end;

function TCivWorld.SavedSiteValue(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX + 80, ParaY + 50);
end;

procedure TCivWorld.SetSavedSiteValue(ParaX, ParaY, ParaValue: Integer);
begin
    mMap.SetPixel(ParaX + 80, ParaY + 50, Byte(ParaValue));
end;

{ -------------------------------------------------------------------------
  Regions. RegionKey returns the byte at (x, y+50): 0..15 in practice
  (NumberRegions writes only ranks 0..15). MapRegion clamps and indexes the
  correct span array.
  ------------------------------------------------------------------------- }
function TCivWorld.RegionKey(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX, ParaY + 50);
    if Result > 15 then Result := 15;   { defensive; the C returns raw byte }
end;

function TCivWorld.MapRegion(ParaX, ParaY: Integer): Integer;
var
    vKey : Integer;
    vSea : Boolean;
begin
    vKey := RegionKey(ParaX, ParaY);
    vSea := IsOcean(ParaX, ParaY);
    Result := ContinentSpan(vSea, vKey);
end;

function TCivWorld.ContinentSpan(ParaIsSea: Boolean; ParaRegion: Integer): Integer;
begin
    if (ParaRegion < 0) or (ParaRegion > 63) then
        Exit(0);
    Result := mState.mData.ContinentSpan[Ord(ParaIsSea), ParaRegion];
end;

{ -------------------------------------------------------------------------
  Coarse connectivity — 20×13 grid. CoarseGroundWay lives in the SVE file
  (mState.mData.BlockGroundWay). CoarseOceanMap is runtime-only, rebuilt on
  load.
  ------------------------------------------------------------------------- }
function TCivWorld.GetCoarseOceanMap(ParaX, ParaY: Integer): Byte;
begin
    if (ParaX < 0) or (ParaX > 19) or (ParaY < 0) or (ParaY > 12) then
        Exit(0);
    Result := mCoarseOceanMap[ParaX, ParaY];
end;

procedure TCivWorld.SetCoarseOceanMap(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    if (ParaX < 0) or (ParaX > 19) or (ParaY < 0) or (ParaY > 12) then
        Exit;
    mCoarseOceanMap[ParaX, ParaY] := ParaValue;
end;

procedure TCivWorld.ClearCoarseOceanMap;
begin
    FillChar(mCoarseOceanMap, SizeOf(mCoarseOceanMap), 0);
end;

function TCivWorld.GetCoarseGroundWay(ParaX, ParaY: Integer): Byte;
begin
    if (ParaX < 0) or (ParaX > 19) or (ParaY < 0) or (ParaY > 12) then
        Exit(0);
    Result := mState.mData.BlockGroundWay[ParaX, ParaY];
end;

procedure TCivWorld.SetCoarseGroundWay(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    if (ParaX < 0) or (ParaX > 19) or (ParaY < 0) or (ParaY > 12) then
        Exit;
    mState.mData.BlockGroundWay[ParaX, ParaY] := ParaValue;
end;

{ -------------------------------------------------------------------------
  Exploration.
  ------------------------------------------------------------------------- }
function TCivWorld.IsExplored(ParaCiv, ParaX, ParaY: Integer): Boolean;
begin
    if not MapInBounds(ParaX, ParaY) then
        Exit(False);
    Result := (Byte(mState.mData.MapVisibleTo[ParaX, ParaY]) and
               Byte(1 shl ParaCiv)) <> 0;
end;

procedure TCivWorld.SetExplored(ParaCiv, ParaX, ParaY: Integer; ParaValue: Boolean);
var
    vByte : Byte;
begin
    if not MapInBounds(ParaX, ParaY) then
        Exit;
    vByte := Byte(mState.mData.MapVisibleTo[ParaX, ParaY]);
    if ParaValue then
        vByte := vByte or Byte(1 shl ParaCiv)
    else
        vByte := vByte and not Byte(1 shl ParaCiv);
    mState.mData.MapVisibleTo[ParaX, ParaY] := ShortInt(vByte);
end;

procedure TCivWorld.RevealRadius(ParaCiv, ParaX, ParaY, ParaRadius: Integer);
var
    vDX, vDY : Integer;
begin
    for vDY := -ParaRadius to ParaRadius do
        for vDX := -ParaRadius to ParaRadius do
            SetExplored(ParaCiv, WrapX(ParaX + vDX), ParaY + vDY, True);
end;

procedure TCivWorld.ClearExploration(ParaCiv: Integer);
var
    vX, vY : Integer;
    vMask : Byte;
begin
    vMask := Byte(not (1 shl ParaCiv));
    for vX := 0 to 79 do
        for vY := 0 to 49 do
            mState.mData.MapVisibleTo[vX, vY] :=
                ShortInt(Byte(mState.mData.MapVisibleTo[vX, vY]) and vMask);
end;

function TCivWorld.ExplorationByte(ParaX, ParaY: Integer): Byte;
begin
    if not MapInBounds(ParaX, ParaY) then
        Exit(0);
    Result := Byte(mState.mData.MapVisibleTo[ParaX, ParaY]);
end;

procedure TCivWorld.SetExplorationByte(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    if not MapInBounds(ParaX, ParaY) then
        Exit;
    mState.mData.MapVisibleTo[ParaX, ParaY] := ShortInt(ParaValue);
end;

{ -------------------------------------------------------------------------
  Occupancy.
  ------------------------------------------------------------------------- }
function TCivWorld.OccupancyByte(ParaX, ParaY: Integer): Byte;
begin
    Result := mMap.Pixel(ParaX + 160, ParaY);
end;

procedure TCivWorld.Occupy(ParaX, ParaY: Integer);
var
    v : Byte;
begin
    v := mMap.Pixel(ParaX + 160, ParaY);
    mMap.SetPixel(ParaX + 160, ParaY, Byte((v and 7) or $08));
end;

procedure TCivWorld.ClearOccupied(ParaX, ParaY: Integer);
var
    v : Byte;
begin
    v := mMap.Pixel(ParaX + 160, ParaY);
    mMap.SetPixel(ParaX + 160, ParaY, Byte(v and 7));
end;

{ -------------------------------------------------------------------------
  Predicates.

  PatternedCell and HasHut are pure functions of (x, y, map_rng_state). The
  first parameter of the C's has_hut is the terrain at (x, y); the caller
  passes it to avoid a redundant TerrainAt call.
  ------------------------------------------------------------------------- }
function TCivWorld.PatternedCell(ParaX, ParaY: Integer): Boolean;
var
    vSeed : Integer;
begin
    if (ParaY <= 1) or (ParaY >= 48) then
    begin
        Result := False;
        Exit;
    end;
    vSeed := (ParaX div 4) * 13 + (ParaY div 4) * 11 + mState.mData.MapRngState;
    Result := ((ParaX and 3) * 4 + (ParaY and 3)) = (Byte(vSeed) and 15);
end;

function TCivWorld.HasHut(ParaTerrain, ParaX, ParaY: Integer): Boolean;
var
    vSeed : Integer;
begin
    if (ParaTerrain = ConstTerrainOcean) or
       ((Byte(mState.mData.MapVisibleTo[ParaX, ParaY]) and 1) <> 0) or
       (ParaY <= 1) or (ParaY >= 48) then
    begin
        Result := False;
        Exit;
    end;
    vSeed := (ParaX div 4) * 13 + (ParaY div 4) * 11 + mState.mData.MapRngState + 8;
    Result := ((ParaX and 3) * 4 + (ParaY and 3) = (Byte(vSeed) and 31))
              and ((MapFlags(ParaX, ParaY) and ConstTileCity) = 0);
end;

{ -------------------------------------------------------------------------
  ScoreGroupRecord — the defender-selection scorer from UNITS.C. Returns 0
  for ineligible candidates (empty slot, or a land unit at sea). The caller
  keeps the running maximum and the corresponding unit index. Both
  TCivCombat and TCivUnitManager now call this single implementation.
  ------------------------------------------------------------------------- }
function TCivWorld.ScoreGroupRecord(ParaGroup, ParaIndex: Integer): Integer;
var
    vType, vClass, vScore : Integer;
    vUnit : TUnit;
begin
    vUnit := mState.mData.ArmyData[ParaGroup, ParaIndex];
    vType := vUnit.UnitType;
    if vType = -1 then
        Exit(0);

    vClass := TerrainAt(vUnit.X, vUnit.Y);
    if (vClass = ConstTerrainOcean) and
       (mState.mData.UtTypes[vType].Domain <> 2) then
        Exit(0);

    if mState.mData.UtTypes[vType].Domain = 0 then
    begin
        if (vUnit.Status and ConstUnitFortified) <> 0 then
            vScore := 3 * mState.mData.UtTypes[vType].Defense *
                      TerrainEntry(vClass).Defense * 8
        else
            vScore := 2 * mState.mData.UtTypes[vType].Defense *
                      TerrainEntry(vClass).Defense * 8;
    end else
        vScore := mState.mData.UtTypes[vType].Defense * 16;

    if (vUnit.Status and ConstUnitVeteran) <> 0 then
        vScore := vScore + vScore div 2;

    Result := vScore;
end;

{ -------------------------------------------------------------------------
  Neighbourhood helpers.
  ------------------------------------------------------------------------- }
function TCivWorld.AdjacentForeignTile(ParaCiv, ParaX, ParaY: Integer): Boolean;
var
    vDir, vOwner : Integer;
begin
    for vDir := 1 to 8 do
    begin
        vOwner := MapOwner(WrapX(ParaX + ConstSpiralX[vDir]),
                           ParaY + ConstSpiralY[vDir]);
        if (vOwner <> -1) and (vOwner <> ParaCiv) then
            Exit(True);
    end;
    Result := False;
end;

function TCivWorld.CountNeighbours(ParaX, ParaY: Integer;
    ParaPredicate: TFunc<Integer, Integer, Boolean>): Integer;
var
    vDir : Integer;
begin
    Result := 0;
    for vDir := 1 to 8 do
    begin
        if ParaPredicate(WrapX(ParaX + ConstSpiralX[vDir]),
                         ParaY + ConstSpiralY[vDir]) then
            Inc(Result);
    end;
end;

end.