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
    { Tile flag bits — from memory_layout.md }
    ConstTileCity       = $01;
    ConstTileIrrigation = $02;
    ConstTileMine       = $04;
    ConstTileRoad       = $08;
    ConstTileRailroad   = $10;
    ConstTileFortress   = $20;
    ConstTilePollution  = $40;

    { Terrain IDs — from enum_unit_terrain.md }
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
    { Reads/writes the map database through a TMapPage. Mirrors MAP.C. }
    TCivWorld = class
    private
        mState : TCivilizationGameState;
        mMap   : TMapPage;
    public
        constructor Create(ParaState: TCivilizationGameState; ParaMap: TMapPage);
        destructor Destroy; override;

        property State: TCivilizationGameState read mState;
        property Map:   TMapPage                read mMap;

        { MAP.C accessors. }
        function TerrainAt(ParaX, ParaY: Integer): Integer;
        function MapCity(ParaX, ParaY: Integer): Integer;
        function MapOwner(ParaX, ParaY: Integer): Integer;
        function MapFlags(ParaX, ParaY: Integer): Integer;
        function KnownFlags(ParaX, ParaY: Integer): Integer;
        function RegionKey(ParaX, ParaY: Integer): Integer;
        function MapRegion(ParaX, ParaY: Integer): Integer;
        function SiteValue(ParaX, ParaY: Integer): Integer;
        function PatternedCell(ParaUnused, ParaX, ParaY: Integer): Boolean;
        function HasHut(ParaTerrain, ParaX, ParaY: Integer): Boolean;

        { Flag maintenance. }
        procedure MapMark(ParaX, ParaY: Integer);
        procedure FlagTile(ParaFlag, ParaX, ParaY: Integer);
        procedure Unflag(ParaFlag, ParaX, ParaY: Integer);

        { Exploration mask helpers. }
        function  IsExplored(ParaCiv, ParaX, ParaY: Integer): Boolean;
        procedure SetExplored(ParaCiv, ParaX, ParaY: Integer; ParaValue: Boolean);

        { Read raw byte from the map database; exposed for tests and
          binary reconstruction. }
        function RawPixel(ParaX, ParaY: Integer): Byte;
        
        // to be done ?
property CoarseOceanMap: ... // field, built by LinkSeas
function ScoreGroupRecord(ParaGroup, ParaIndex: Integer): Integer; // the exact scoring        
    end;

implementation

const
    ConstTerrainMap: array[0..15] of ShortInt = (
        -1, 10, 3, 8, -1, -1, 1, 6, -1, 11, 2, 9, 4, 5, 0, 7
    );

constructor TCivWorld.Create(ParaState: TCivilizationGameState; ParaMap: TMapPage);
begin
    inherited Create;
    mState := ParaState;
    mMap   := ParaMap;
end;

destructor TCivWorld.Destroy;
begin
    { Caller owns mState and mMap. }
    inherited;
end;

function TCivWorld.RawPixel(ParaX, ParaY: Integer): Byte;
begin
    Result := mMap.Pixel(ParaX, ParaY);
end;

function TCivWorld.TerrainAt(ParaX, ParaY: Integer): Integer;
var
    vByte : Byte;
begin
    vByte := mMap.Pixel(ParaX, ParaY);
    Result := ConstTerrainMap[vByte];
end;

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

function TCivWorld.RegionKey(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX, ParaY + 50);
end;

function TCivWorld.MapRegion(ParaX, ParaY: Integer): Integer;
var
    vKey : Integer;
    vSea : Integer;
begin
    vKey := RegionKey(ParaX, ParaY);
    vSea := Ord(TerrainAt(ParaX, ParaY) = ConstTerrainOcean);
    if vKey < 0 then vKey := 0;
    if vKey > 63 then vKey := 63;
    Result := mState.mData.ContinentSpan[vSea, vKey];
end;

function TCivWorld.SiteValue(ParaX, ParaY: Integer): Integer;
begin
    Result := mMap.Pixel(ParaX + 80, ParaY + 50);
end;

function TCivWorld.PatternedCell(ParaUnused, ParaX, ParaY: Integer): Boolean;
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

end.