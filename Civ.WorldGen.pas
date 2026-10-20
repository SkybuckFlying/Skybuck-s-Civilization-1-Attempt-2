unit Civ.WorldGen;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes,
    Civ.Types,
    Civ.Core,
    Civ.Terrains,
    Civ.World,
    Civ.GameState,
    Civ.Pathfinding;

type
    TWorldGenParams = record
        LandMass    : Integer;
        Temperature : Integer;
        Climate     : Integer;
        Age         : Integer;
    end;

    TCivWorldGen = class
    private
        mWorld     : TCivWorld;
        mState     : TCivilizationGameState;
        mRng       : TCivRandom;
        mPath      : TCivPathfinder;
        mLandCount : Integer;
        mShowStory : Boolean;

        procedure GrowLand;
        procedure WalkLand(ParaX, ParaY: Integer);
        procedure MakeRivers;
        procedure NumberRegions;
        procedure ScoreSites;
        function  LandCorner(ParaX, ParaY: Integer): Integer;
        function  GenTerrainAt(ParaX, ParaY: Integer): Integer;
        function  GenRegionAt(ParaX, ParaY: Integer): Integer;
        function  TerrainAt(ParaX, ParaY: Integer): Integer;
        function  SiteValue(ParaX, ParaY: Integer): Integer;
        function  CoarseValid(ParaX, ParaY: Integer): Boolean;
        procedure ClearScratch;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
                           ParaPath: TCivPathfinder);
        destructor Destroy; override;

        procedure MakeWorld(ParaParams: TWorldGenParams;
                            ParaShowStory: Boolean = False);
        procedure GlobalWarming(ParaSeverity: Integer);
        procedure LinkLand(ParaShow: Boolean);
        procedure LinkSeas(ParaShow: Boolean);
        function  StoryStep: Boolean;
    end;

implementation

const
    ConstMinLandBase = 640;
    ConstRiverBase   = 6;

constructor TCivWorldGen.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaPath: TCivPathfinder);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mRng   := ParaRng;
    mPath  := ParaPath;
    mLandCount := 0;
    mShowStory := False;
end;

destructor TCivWorldGen.Destroy;
begin
    inherited;
end;

function TCivWorldGen.GenTerrainAt(ParaX, ParaY: Integer): Integer;
begin
    Result := TerrainAt(ParaX, ParaY);
end;

function TCivWorldGen.GenRegionAt(ParaX, ParaY: Integer): Integer;
begin
    Result := mWorld.RegionKey(ParaX, ParaY);
end;

function TCivWorldGen.TerrainAt(ParaX, ParaY: Integer): Integer;
begin
    Result := mWorld.TerrainAt(ParaX, ParaY);
end;

function TCivWorldGen.SiteValue(ParaX, ParaY: Integer): Integer;
begin
    Result := mWorld.SiteValue(ParaX, ParaY);
end;

function TCivWorldGen.CoarseValid(ParaX, ParaY: Integer): Boolean;
begin
    Result := (ParaX >= 0) and (ParaX < 20) and (ParaY >= 0) and (ParaY < 13);
end;

procedure TCivWorldGen.ClearScratch;
begin
    mWorld.ClearCoarseOceanMap;
end;

procedure TCivWorldGen.MakeWorld(ParaParams: TWorldGenParams;
    ParaShowStory: Boolean);
var
    vX, vY, vI, vT, vLat, vRain, vMaxLand, vMaxAge : Integer;
begin
    mLandCount := 0;
    mShowStory := ParaShowStory;

    mWorld.Map.Clear;
    mWorld.ClearCoarseOceanMap;
    for vX := 0 to 79 do
        for vY := 0 to 49 do
            mWorld.SetExplorationByte(vX, vY, 0);

    vMaxLand := ConstMinLandBase + 320 * ParaParams.LandMass;

    repeat
        GrowLand;
        if mShowStory then StoryStep;
    until mLandCount >= vMaxLand;

    for vX := 1 to 78 do
    begin
        for vY := 1 to 48 do
        begin
            vT := 0;
            if mWorld.RawPixel(vX, vY) <> 0 then vT := vT or 1;
            if mWorld.RawPixel(vX + 1, vY) <> 0 then vT := vT or 2;
            if mWorld.RawPixel(vX, vY + 1) <> 0 then vT := vT or 4;
            if mWorld.RawPixel(vX + 1, vY + 1) <> 0 then vT := vT or 8;
            if (vT = 6) or (vT = 9) then
            begin
                mWorld.SetTerrainByte(vX + 1, vY, 1);
                mWorld.SetTerrainByte(vX, vY + 1, 1);
                mWorld.SetTerrainByte(vX + 1, vY + 1, 1);
                if vX <> 0 then Dec(vX);
                if vY <> 0 then Dec(vY);
            end;
        end;
        if mShowStory then StoryStep;
    end;

    for vX := 0 to 79 do
    begin
        for vY := 0 to 49 do
        begin
            vT := mWorld.RawPixel(vX, vY);
            case vT of
                0: mWorld.SetTerrainByte(vX, vY, 1);
                1:
                begin
                    vLat := Abs(29 - (mRng.Scaled(8) + vY));
                    vLat := vLat + 1 - ParaParams.Temperature;
                    case vLat div 6 of
                        -1, 0 : mWorld.SetTerrainByte(vX, vY, 14);
                        1, 2  : mWorld.SetTerrainByte(vX, vY, 6);
                        3, 4  : mWorld.SetTerrainByte(vX, vY, 7);
                        5, 6  : mWorld.SetTerrainByte(vX, vY, 15);
                    end;
                end;
                2 : mWorld.SetTerrainByte(vX, vY, 12);
            else
                mWorld.SetTerrainByte(vX, vY, 13);
            end;
        end;
        if mShowStory then StoryStep;
    end;

    for vY := 0 to 49 do
    begin
        vLat := Abs(25 - vY);
        vRain := 0;
        for vX := 0 to 79 do
        begin
            vT := mWorld.RawPixel(vX, vY);
            if vT = 1 then
            begin
                if vRain < Abs(12 - vLat) + ParaParams.Climate * 4 then Inc(vRain);
            end else if vRain > 0 then
            begin
                vRain := vRain - mRng.Scaled(7 - ParaParams.Climate * 2);
                case vT of
                    14: mWorld.SetTerrainByte(vX, vY, 6);
                    6 : mWorld.SetTerrainByte(vX, vY, 10);
                    12: mWorld.SetTerrainByte(vX, vY, 2);
                    7 : mWorld.SetTerrainByte(vX, vY, 15);
                    13: vRain := vRain - 3;
                end;
            end;
        end;
        vRain := 0;
        for vX := 79 downto 0 do
        begin
            vT := mWorld.RawPixel(vX, vY);
            if vT = 1 then
            begin
                if vRain < (vLat div 2) + ParaParams.Climate then Inc(vRain);
            end else if vRain > 0 then
            begin
                vRain := vRain - mRng.Scaled(7 - ParaParams.Climate * 2);
                case vT of
                    14: mWorld.SetTerrainByte(vX, vY, 6);
                    6 : mWorld.SetTerrainByte(vX, vY, 10);
                    10: mWorld.SetTerrainByte(vX, vY, (vLat < 10) ? 11 : 3);
                    13: vRain := vRain - 3;
                    3, 12: mWorld.SetTerrainByte(vX, vY, 2);
                end;
            end;
        end;
        if mShowStory then StoryStep;
    end;

    vMaxAge := ParaParams.Age * 800 + 800;
    vX := 0; vY := 0;
    for vI := 0 to vMaxAge - 1 do
    begin
        if (vI and 1) <> 0 then
        begin
            vT := mRng.Scaled(8) + 1;
            vX := vX + ConstSpiralX[vT];
            vY := vY + ConstSpiralY[vT];
        end else
        begin
            vX := mRng.Scaled(80);
            vY := mRng.Scaled(50);
        end;
        if (vX < 0) or (vX > 79) or (vY < 0) or (vY > 49) then Continue;
        vT := mWorld.RawPixel(vX, vY);
        case vT of
            14: mWorld.SetTerrainByte(vX, vY, 6);
            13: LandCorner(vX, vY);
            10: mWorld.SetTerrainByte(vX, vY, 2);
            2 : mWorld.SetTerrainByte(vX, vY, 11);
            6, 7: mWorld.SetTerrainByte(vX, vY, 12);
            12, 15: mWorld.SetTerrainByte(vX, vY, 13);
            3 : mWorld.SetTerrainByte(vX, vY, 10);
            11: mWorld.SetTerrainByte(vX, vY, 3);
        end;
    end;

    MakeRivers;
    NumberRegions;
    mShowStory := False;
end;

function TCivWorldGen.LandCorner(ParaX, ParaY: Integer): Integer;
begin
    if mWorld.TerrainAt(ParaX - 1, ParaY - 1) <> ConstTerrainOcean then Exit(0);
    if mWorld.TerrainAt(ParaX - 1, ParaY + 1) <> ConstTerrainOcean then Exit(0);
    if mWorld.TerrainAt(ParaX + 1, ParaY - 1) <> ConstTerrainOcean then Exit(0);
    if mWorld.TerrainAt(ParaX + 1, ParaY + 1) <> ConstTerrainOcean then Exit(0);
    mWorld.SetTerrainByte(ParaX, ParaY, 1);
    Result := 1;
end;

procedure TCivWorldGen.GrowLand;
var
    vX, vY : Integer;
begin
    vX := mRng.Scaled(72) + 4;
    vY := mRng.Scaled(34) + 8;
    WalkLand(vX, vY);
    for vX := 0 to 79 do
    begin
        for vY := 0 to 49 do
        begin
            if mWorld.RawPixel(vX + 160, vY) = 0 then Continue;
            mWorld.SetTerrainByte(vX, vY, mWorld.RawPixel(vX, vY) + 1);
            Inc(mLandCount);
        end;
    end;
end;

procedure TCivWorldGen.WalkLand(ParaX, ParaY: Integer);
var
    vLeft, vDir : Integer;
begin
    vLeft := mRng.Scaled(64) + 1;
    repeat
        mWorld.SetRawPixel(ParaX + 160, ParaY, 15);
        mWorld.SetRawPixel(ParaX + 161, ParaY, 15);
        mWorld.SetRawPixel(ParaX + 160, ParaY + 1, 15);
        vDir := mRng.Scaled(4) * 2 + 1;
        ParaX := ParaX + ConstSpiralX[vDir];
        ParaY := ParaY + ConstSpiralY[vDir];
        Dec(vLeft);
    until (vLeft <= 0) or (ParaX <= 2) or (ParaX >= 77) or (ParaY <= 2) or (ParaY >= 46);
end;

procedure TCivWorldGen.MakeRivers;
var
    vDir, vOld, vTries, vRivers, vPrev, vStartX, vStartY : Integer;
    vNeighbor, vY, vX, vNearWater, vTile : Integer;
    vSave : TBytes;
begin
    vTries := 0; vRivers := 0;
    SetLength(vSave, 64000);
    repeat
        Move(mWorld.Map.Bytes^, vSave[0], 64000);
        vOld := 0;
        repeat
            vX := mRng.Scaled(80);
            vY := mRng.Scaled(50);
        until mWorld.RawPixel(vX, vY) = 12;
        vStartX := vX; vStartY := vY;
        vDir := mRng.Scaled(4) * 2; vPrev := vDir;
        repeat
            mWorld.SetTerrainByte(vX, vY, 9);
            vNearWater := 0;
            for vNeighbor := 1 to 7 do
            begin
                if (vNeighbor and 1) = 0 then Continue;
                if mWorld.TerrainAt(vX + ConstSpiralX[vNeighbor], vY + ConstSpiralY[vNeighbor]) = ConstTerrainOcean then
                    vNearWater := 1;
            end;
            vPrev := vDir;
            vDir := (vDir + (mRng.Scaled(2) - (vOld and 1)) * 2) and 7;
            if (vPrev xor 4) > vDir then
                mWorld.SetSavedSiteValue(vX, vY, 8);
            vX := vX + ConstSpiralX[vDir + 1];
            vY := vY + ConstSpiralY[vDir + 1];
            vTile := mWorld.RawPixel(vX, vY);
            Inc(vOld);
        until (vNearWater <> 0) or (vTile = 13) or (vTile = 1) or (vTile = 9);
        if ((vNearWater = 0) and (vTile <> 9)) or (vOld < 5) then
            Move(vSave[0], mWorld.Map.Bytes^, 64000)
        else
        begin
            Inc(vRivers);
            for vNeighbor := 1 to 21 do
            begin
                vX := vStartX + ConstSpiralX[vNeighbor];
                vY := vStartY + ConstSpiralY[vNeighbor];
                if mWorld.TerrainAt(vX, vY) = ConstTerrainPlains then
                    mWorld.SetTerrainByte(vX, vY, 11);
            end;
        end;
        Inc(vTries);
    until (vTries >= 256) or (vRivers >= ConstRiverBase);
end;

procedure TCivWorldGen.NumberRegions;
var
    vX, vY, vPass, vId, vLabel, vRunning, vPos, vNeighbor, vRank : Integer;
    vTerrain : Integer;
    vRanked : array[0..15] of Integer;
    vOrder  : array[0..63] of Integer;
begin
    FillChar(mState.mData.ContinentSpan, SizeOf(mState.mData.ContinentSpan), 0);
    for vPass := 0 to 1 do
    begin
        for vX := 0 to 79 do
            for vY := 0 to 49 do
                mWorld.SetExplorationByte(vX, vY, 0);
        vId := 0;
        for vY := 0 to 49 do
        begin
            vLabel := -1; vRunning := 0;
            for vX := 0 to 79 do
            begin
                vTerrain := mWorld.TerrainAt(vX, vY);
                if ((vTerrain <> ConstTerrainOcean) = (vPass = 0)) then
                begin
                    if vY > 0 then
                    begin
                        vPos := -1;
                        if vX = 0 then vPos := 0;
                        while vPos <= IfThen(vX < 79, 1, 0) do
                        begin
                            vNeighbor := mWorld.ExplorationByte(vX + vPos, vY - 1);
                            if vNeighbor <> 0 then
                            begin
                                if (vLabel <> -1) and (vLabel <> vNeighbor) then
                                begin
                                    for var vCY := 0 to vY do
                                        for var vCX := 0 to 79 do
                                            if mWorld.ExplorationByte(vCX, vCY) = vLabel then
                                                mWorld.SetExplorationByte(vCX, vCY, vNeighbor);
                                    mState.mData.ContinentSpan[vPass, vNeighbor] :=
                                        mState.mData.ContinentSpan[vPass, vNeighbor] +
                                        mState.mData.ContinentSpan[vPass, vLabel];
                                    mState.mData.ContinentSpan[vPass, vLabel] := 0;
                                end;
                                vLabel := vNeighbor;
                            end;
                            Inc(vPos);
                        end;
                    end;
                    if vLabel = -1 then
                    begin
                        if vRunning = 0 then
                        begin
                            vId := 0;
                            while mState.mData.ContinentSpan[vPass, vId + 1] <> 0 do
                                Inc(vId);
                        end;
                        vLabel := vId;
                    end;
                    mWorld.SetExplorationByte(vX, vY, vLabel);
                    mState.mData.ContinentSpan[vPass, vLabel] :=
                        mState.mData.ContinentSpan[vPass, vLabel] + 1;
                    vRunning := 1;
                end else
                begin
                    vRunning := 0; vLabel := -1;
                end;
            end;
            if mShowStory then StoryStep;
        end;

        for var vI := 0 to 15 do vRanked[vI] := 0;
        vOrder[0] := 0;
        for var vCX := 1 to 63 do
        begin
            vOrder[vCX] := 15;
            for vY := 1 to 15 do
                if mState.mData.ContinentSpan[vPass, vCX] >
                   mState.mData.ContinentSpan[vPass, vRanked[vY]] then
                begin
                    for var vP := 15 downto vY + 1 do
                    begin
                        vOrder[vRanked[vP - 1]] := vP;
                        vRanked[vP] := vRanked[vP - 1];
                    end;
                    vOrder[vCX] := vY;
                    vRanked[vY] := vCX;
                    Break;
                end;
        end;
        for vX := 0 to 79 do
            for vY := 0 to 49 do
            begin
                vRank := vOrder[mWorld.ExplorationByte(vX, vY)];
                if vRank <> 0 then
                    mWorld.SetRawPixel(vX, vY + 50, Byte(vRank));
            end;
        for var vI := 1 to 15 do
            vRanked[vI] := mState.mData.ContinentSpan[vPass, vRanked[vI]];
        for var vI := 1 to 15 do
            mState.mData.ContinentSpan[vPass, vI] := vRanked[vI];
        mState.mData.ContinentSpan[vPass, 0] := 0;
        mState.mData.ContinentSpan[vPass, 15] := 1;
    end;

    LinkLand(mShowStory);
    LinkSeas(mShowStory);
    ScoreSites;

    for vX := 0 to 79 do
        for vY := 0 to 49 do
            mWorld.SetExplorationByte(vX, vY, 0);
end;

procedure TCivWorldGen.LinkLand(ParaShow: Boolean);
var
    vCoarseX, vCoarseY, vDir, vNX, vNY, vRepX, vRepY, vRepX2, vRepY2 : Integer;
    vCost, vSrcID, vDstID, vDstX, vDstY : Integer;
begin
    for vCoarseX := 0 to 19 do
        for vCoarseY := 0 to 12 do
            mWorld.CoarseGroundWay[vCoarseX, vCoarseY] := 0;

    for vCoarseX := 0 to 19 do
        for vCoarseY := 0 to 12 do
        begin
            vRepX := vCoarseX * 4 + 1;
            vRepY := vCoarseY * 4 + 1;
            vSrcID := -1; vRepX2 := 0; vRepY2 := 0;
            if mWorld.TerrainAt(vRepX, vRepY) <> ConstTerrainOcean then
            begin vSrcID := mWorld.RegionKey(vRepX, vRepY); vRepX2 := vRepX; vRepY2 := vRepY; end
            else if mWorld.TerrainAt(vRepX + 1, vRepY) <> ConstTerrainOcean then
            begin vSrcID := mWorld.RegionKey(vRepX + 1, vRepY); vRepX2 := vRepX + 1; vRepY2 := vRepY; end
            else if mWorld.TerrainAt(vRepX, vRepY + 1) <> ConstTerrainOcean then
            begin vSrcID := mWorld.RegionKey(vRepX, vRepY + 1); vRepX2 := vRepX; vRepY2 := vRepY + 1; end
            else if mWorld.TerrainAt(vRepX + 1, vRepY + 1) <> ConstTerrainOcean then
            begin vSrcID := mWorld.RegionKey(vRepX + 1, vRepY + 1); vRepX2 := vRepX + 1; vRepY2 := vRepY + 1; end;
            if vSrcID = -1 then Continue;

            for vDir := 1 to 4 do
            begin
                vNX := vRepX + ConstSpiralX[vDir] * 4;
                vNY := vRepY + ConstSpiralY[vDir] * 4;
                vDstID := -1;
                vDstX := vNX; vDstY := vNY;
                if mWorld.TerrainAt(vNX, vNY) <> ConstTerrainOcean then
                    vDstID := mWorld.RegionKey(vNX, vNY)
                else if mWorld.TerrainAt(vNX + 1, vNY) <> ConstTerrainOcean then
                begin vDstID := mWorld.RegionKey(vNX + 1, vNY); vDstX := vNX + 1; end
                else if mWorld.TerrainAt(vNX, vNY + 1) <> ConstTerrainOcean then
                begin vDstID := mWorld.RegionKey(vNX, vNY + 1); vDstY := vNY + 1; end
                else if mWorld.TerrainAt(vNX + 1, vNY + 1) <> ConstTerrainOcean then
                begin vDstID := mWorld.RegionKey(vNX + 1, vNY + 1); vDstX := vNX + 1; vDstY := vNY + 1; end;
                if (vDstID = -1) or (vSrcID <> vDstID) then Continue;

                vCost := mPath.PathProbe(vRepX2, vRepY2, vDstX, vDstY, False, 20);
                if (vCost = -1) or (vCost >= 20) then Continue;

                mWorld.CoarseGroundWay[vCoarseX, vCoarseY] :=
                    Byte(mWorld.CoarseGroundWay[vCoarseX, vCoarseY] or (1 shl (vDir - 1)));
                vNX := vCoarseX + ConstSpiralX[vDir];
                vNY := vCoarseY + ConstSpiralY[vDir];
                if (vNX >= 0) and (vNX < 20) and (vNY >= 0) and (vNY < 13) then
                    mWorld.CoarseGroundWay[vNX, vNY] :=
                        Byte(mWorld.CoarseGroundWay[vNX, vNY] or (1 shl ((vDir + 3) and 7)));
            end;
        end;
end;

procedure TCivWorldGen.LinkSeas(ParaShow: Boolean);
var
    vCX, vCY, vDir, vNX, vNY, vSrcID, vDstID, vX, vY, vLandCount, vStep : Integer;
begin
    mWorld.ClearCoarseOceanMap;

    for vCX := 0 to 19 do
    begin
        for vCY := 0 to 11 do
        begin
            vX := vCX * 4 + 1; vY := vCY * 4 + 1;
            vSrcID := -1;
            if mWorld.TerrainAt(vX, vY) = ConstTerrainOcean then
                vSrcID := mWorld.RegionKey(vX, vY)
            else if mWorld.TerrainAt(vX + 1, vY) = ConstTerrainOcean then
                vSrcID := mWorld.RegionKey(vX + 1, vY)
            else if mWorld.TerrainAt(vX, vY + 1) = ConstTerrainOcean then
                vSrcID := mWorld.RegionKey(vX, vY + 1)
            else if mWorld.TerrainAt(vX + 1, vY + 1) = ConstTerrainOcean then
                vSrcID := mWorld.RegionKey(vX + 1, vY + 1);
            if vSrcID = -1 then Continue;

            for vDir := 1 to 8 do
            begin
                vNX := vCX * 4 + 1 + ConstSpiralX[vDir] * 4;
                vNY := vCY * 4 + 1 + ConstSpiralY[vDir] * 4;
                vDstID := -1;
                if mWorld.TerrainAt(vNX, vNY) = ConstTerrainOcean then
                    vDstID := mWorld.RegionKey(vNX, vNY)
                else if mWorld.TerrainAt(vNX + 1, vNY) = ConstTerrainOcean then
                    vDstID := mWorld.RegionKey(vNX + 1, vNY)
                else if mWorld.TerrainAt(vNX, vNY + 1) = ConstTerrainOcean then
                    vDstID := mWorld.RegionKey(vNX, vNY + 1)
                else if mWorld.TerrainAt(vNX + 1, vNY + 1) = ConstTerrainOcean then
                    vDstID := mWorld.RegionKey(vNX + 1, vNY + 1);
                if (vDstID = -1) or (vSrcID <> vDstID) then Continue;

                vNX := vCX * 4 + 1; vNY := vCY * 4 + 1;
                vLandCount := 4;
                for vStep := 0 to 4 do
                begin
                    vNX := vNX + ConstSpiralX[vDir];
                    vNY := vNY + ConstSpiralY[vDir];
                    if (mWorld.TerrainAt(vNX, vNY) <> ConstTerrainOcean) or (not MapInBounds(vNX, vNY)) then Dec(vLandCount);
                    if (mWorld.TerrainAt(vNX + 1, vNY) <> ConstTerrainOcean) or (not MapInBounds(vNX + 1, vNY)) then Dec(vLandCount);
                    if (mWorld.TerrainAt(vNX, vNY + 1) <> ConstTerrainOcean) or (not MapInBounds(vNX, vNY + 1)) then Dec(vLandCount);
                    if (mWorld.TerrainAt(vNX + 1, vNY + 1) <> ConstTerrainOcean) or (not MapInBounds(vNX + 1, vNY + 1)) then Dec(vLandCount);
                    if vLandCount < 2 then Break;
                end;
                if (vLandCount < 2) and not ((vCY = 11) and (vDir = 3)) then Continue;

                if ConstSpiralY[vDir] + vCY < 12 then
                begin
                    mWorld.CoarseOceanMap[vCX, vCY] :=
                        Byte(mWorld.CoarseOceanMap[vCX, vCY] or (1 shl (vDir - 1)));
                    vNX := ConstSpiralX[vDir] + vCX;
                    vNY := ConstSpiralY[vDir] + vCY;
                    if (vNX >= 0) and (vNX < 20) and (vNY >= 0) and (vNY < 13) then
                        mWorld.CoarseOceanMap[vNX, vNY] :=
                            Byte(mWorld.CoarseOceanMap[vNX, vNY] or (1 shl ((vDir + 3) and 7)));
                end;
            end;
        end;
        if ParaShow then StoryStep;
    end;

    for vCY := 0 to 11 do
    begin
        mWorld.CoarseOceanMap[0, vCY] := Byte(mWorld.CoarseOceanMap[0, vCY] or $E0);
        mWorld.CoarseOceanMap[19, vCY] := Byte(mWorld.CoarseOceanMap[19, vCY] or $0E);
    end;
    mWorld.CoarseOceanMap[0, 0] := Byte(mWorld.CoarseOceanMap[0, 0] and $7F);
    mWorld.CoarseOceanMap[0, 11] := Byte(mWorld.CoarseOceanMap[0, 11] and $DF);
    mWorld.CoarseOceanMap[19, 0] := Byte(mWorld.CoarseOceanMap[19, 0] and $FD);
    mWorld.CoarseOceanMap[19, 11] := Byte(mWorld.CoarseOceanMap[19, 11] and $F7);
end;

procedure TCivWorldGen.ScoreSites;
var
    vX, vY, vT, vTotal, vValue, vNX, vNY, vI, vType : Integer;
    vWeights : array[0..23] of Integer;
    vEntry   : TTerrainType;
begin
    for var vS := 0 to 15 do
        mState.mData.AiZonePlaces[vS] := 0;

    { Build the yield-weight table exactly as WORLDGEN.C does. }
    for vI := 0 to 23 do
    begin
        vEntry := TerrainEntry(vI);
        vWeights[vI] := vEntry.Food * 3 + vEntry.Trade;
        vType := vI mod 12;
        if (vType <> 2) and (vType <> 11) then
            vWeights[vI] := vWeights[vI] + vEntry.Shields * 2;
    end;

    for vX := 2 to 77 do
    begin
        for vY := 2 to 47 do
        begin
            vT := mWorld.TerrainAt(vX, vY);
            if (vT <> ConstTerrainRiver) and (vT <> ConstTerrainGrassland) and
               (vT <> ConstTerrainPlains) then
            begin
                mWorld.SetSiteValue(vX, vY, 0);
                mWorld.SetSavedSiteValue(vX, vY, 0);
                Continue;
            end;

            vTotal := 0;
            for vI := 0 to 20 do
            begin
                vValue := 0;
                vNX := vX + ConstRadiusDX[vI];
                vNY := vY + ConstRadiusDY[vI];
                vT := mWorld.TerrainAt(vNX, vNY);
                if ((vT = ConstTerrainGrassland) or (vT = ConstTerrainRiver)) and
                   (((vNX * 7 + vNY * 11) and 2) = 0) then
                    Inc(vValue, 2);
                if mWorld.PatternedCell(vNX, vNY) then
                    Inc(vT, 12);
                vValue := vValue + vWeights[vT];
                if vI < 9 then
                    vValue := vValue * 2;
                if vI = 0 then
                    vValue := vValue * 2;
                vTotal := vTotal + vValue;
            end;

            vT := mWorld.TerrainAt(vX, vY);
            if (vT <> ConstTerrainPlains) and
               (((vX * 7 + vY * 11) and 2) <> 0) then
                Dec(vTotal, 16);

            vValue := Clamp((vTotal - 120) div 8, 1, 15);
            vValue := vValue div 2 + 8;
            mWorld.SetSiteValue(vX, vY, vValue);
            mWorld.SetSavedSiteValue(vX, vY, vValue);
            Inc(mState.mData.AiZonePlaces[mWorld.RegionKey(vX, vY)]);
        end;
    end;
end;

procedure TCivWorldGen.GlobalWarming(ParaSeverity: Integer);
var
    vX, vY, vI, vTerrain, vSeaCount : Integer;
begin
    for vX := 0 to 79 do
        for vY := 0 to 49 do
        begin
            vTerrain := mWorld.TerrainAt(vX, vY);
            if vTerrain > 3 then Continue;
            vSeaCount := 0;
            for vI := 1 to 8 do
                if mWorld.IsOcean(vX + ConstSpiralX[vI], vY + ConstSpiralY[vI]) then
                    Inc(vSeaCount);
            if vSeaCount >= 7 - ParaSeverity then
            begin
                mWorld.SetExplorationByte(vX, vY, mWorld.ExplorationByte(vX, vY) or 1);
                if vTerrain = ConstTerrainForest then
                    mWorld.SetTerrainByte(vX, vY, 11)
                else
                    mWorld.SetTerrainByte(vX, vY, 3);
                mWorld.Unflag(6, vX, vY);
            end else if (((vX * 11 + vY * 13) and 7) = ParaSeverity) then
            begin
                mWorld.SetExplorationByte(vX, vY, mWorld.ExplorationByte(vX, vY) or 1);
                if vTerrain <= 1 then
                    mWorld.SetTerrainByte(vX, vY, 14)
                else
                    mWorld.SetTerrainByte(vX, vY, 6);
            end;
        end;
end;

function TCivWorldGen.StoryStep: Boolean;
begin
    Result := False;
end;

end.