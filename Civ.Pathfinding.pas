unit Civ.Pathfinding;

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
    TCivPathfinder = class
    private
        mWorld  : TCivWorld;
        mState  : TCivilizationGameState;

        mTargetX, mTargetY : Integer;
        mCacheX,  mCacheY  : Integer;
        mLimit             : Integer;

        mQueueX     : array[0..255] of ShortInt;
        mQueueY     : array[0..255] of ShortInt;
        mWalkCost   : array[0..15, 0..15] of SmallInt;
        mBlockSteps : array[0..19, 0..12] of SmallInt;

        procedure RunBFS(ParaOriginX, ParaOriginY,
                         ParaDomain, ParaMoves, ParaLimit: Integer);
        function  PathSearch(ParaOriginX, ParaOriginY,
                             ParaDomain, ParaMoves, ParaLimit: Integer;
                             ParaFallbackX, ParaFallbackY: Integer): Integer;
        function  PathSelect(ParaX, ParaY: Integer; ParaSea: Boolean): Boolean;
    public
        constructor Create(ParaWorld: TCivWorld);
        destructor Destroy; override;

        function  UnitGoal(ParaPlayer, ParaUnitIndex: Integer): Integer;
        function  PathCoarse(ParaPlayer, ParaUnitIndex: Integer): Boolean;
        function  PathProbe(ParaX, ParaY, ParaTargetX, ParaTargetY: Integer;
                            ParaSea: Boolean; ParaLimit: Integer): Integer;
    end;

implementation

constructor TCivPathfinder.Create(ParaWorld: TCivWorld);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mCacheX := -1;
    mCacheY := -1;
    mLimit := 0;
end;

destructor TCivPathfinder.Destroy;
begin
    inherited;
end;

procedure TCivPathfinder.RunBFS(ParaOriginX, ParaOriginY,
    ParaDomain, ParaMoves, ParaLimit: Integer);
var
    vBaseX, vBaseY, vHead, vTail, vX, vY, vIdxX, vIdxY : Integer;
    vCurCost, vNewCost, vPrevCost, vRawX, vNextX, vNextY, vTerrain, vNW : Integer;
    vSea, vRoadUnit, vRegionHasRoad, vTileHasRoad : Boolean;
begin
    vBaseX := mTargetX - 8;
    vBaseY := mTargetY - 8;
    vHead := 0; vTail := 0;
    FillChar(mWalkCost, SizeOf(mWalkCost), 0);
    FillChar(mBlockSteps, SizeOf(mBlockSteps), 0);

    vIdxX := mTargetX - vBaseX;
    vIdxY := mTargetY - vBaseY;
    if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then
        Exit;
    mQueueX[vHead] := ShortInt(mTargetX);
    mQueueY[vHead] := ShortInt(mTargetY);
    Inc(vHead);
    mWalkCost[vIdxX, vIdxY] := 1;

    mLimit := 0;
    vSea := ParaDomain = 2;
    vRoadUnit := ParaMoves = 1;

    while (vTail <> vHead) and (vTail < 225) do
    begin
        vX := mQueueX[vTail];
        vY := mQueueY[vTail];
        Inc(vTail);
        vIdxX := vX - vBaseX;
        vIdxY := vY - vBaseY;
        if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then Continue;

        vCurCost := mWalkCost[vIdxX, vIdxY];
        if vCurCost > ParaLimit then Continue;

        if (WrapX(vX) = ParaOriginX) and (vY = ParaOriginY) then
        begin
            mLimit := vCurCost;
            Continue;
        end;

        vRegionHasRoad := (mWorld.MapFlags(WrapX(vX), vY) and ConstTileRoad) <> 0;

        for vNW := 1 to 8 do
        begin
            vRawX := vX + ConstSpiralX[vNW];
            if Abs(vRawX - mTargetX) >= 8 then Continue;
            vNextX := WrapX(vRawX);
            vNextY := vY + ConstSpiralY[vNW];
            if Abs(vNextY - mTargetY) >= 8 then Continue;
            if not MapInBounds(vNextX, vNextY) then Continue;

            vTerrain := mWorld.TerrainAt(vNextX, vNextY);
            if ((vTerrain = ConstTerrainOcean) <> vSea) and
               (not mWorld.IsCityTile(vNextX, vNextY)) then
                Continue;

            vTileHasRoad := (mWorld.MapFlags(vNextX, vNextY) and ConstTileRoad) <> 0;
            if vRegionHasRoad and vTileHasRoad then
                vNewCost := vCurCost + 1
            else if vRoadUnit then
                vNewCost := vCurCost + 3
            else
                vNewCost := vCurCost + mWorld.TerrainMoveCost(vNextX, vNextY) * 3;

            vIdxX := vRawX - vBaseX;
            vIdxY := vNextY - vBaseY;
            if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then Continue;
            vPrevCost := mWalkCost[vIdxX, vIdxY];
            if (vPrevCost <> 0) and (vPrevCost <= vNewCost) then Continue;
            mWalkCost[vIdxX, vIdxY] := SmallInt(vNewCost);
            mQueueX[vHead] := ShortInt(vRawX);
            mQueueY[vHead] := ShortInt(vNextY);
            Inc(vHead);
        end;
    end;
end;

function TCivPathfinder.PathSearch(ParaOriginX, ParaOriginY,
    ParaDomain, ParaMoves, ParaLimit: Integer;
    ParaFallbackX, ParaFallbackY: Integer): Integer;
var
    vBaseX, vBaseY, vIdxX, vIdxY : Integer;
    vOldCost, vBestDir, vRawX, vNextX, vNextY, vTerrain, vCost, vNW : Integer;
    vSea : Boolean;
begin
    vBaseX := mTargetX - 8;
    vBaseY := mTargetY - 8;
    mLimit := 0;
    vIdxX := ParaOriginX - vBaseX;
    vIdxY := ParaOriginY - vBaseY;

    if (mTargetX <> mCacheX) or (mTargetY <> mCacheY) or
       (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) or
       (mWalkCost[vIdxX, vIdxY] = 0) then
    begin
        RunBFS(ParaOriginX, ParaOriginY, ParaDomain, ParaMoves, ParaLimit);
        mCacheX := mTargetX;
        mCacheY := mTargetY;
    end;

    if ParaLimit > mLimit then
    begin
        vOldCost := 99; vBestDir := -1;
        vSea := ParaDomain = 2;
        for vNW := 1 to 8 do
        begin
            vRawX := ParaOriginX + ConstSpiralX[vNW];
            if Abs(vRawX - mTargetX) >= 72 then
            begin
                if vRawX > mTargetX then vRawX := vRawX - 80
                else vRawX := vRawX + 80;
            end;
            if Abs(vRawX - mTargetX) >= 8 then Continue;
            vNextX := WrapX(vRawX);
            vNextY := ParaOriginY + ConstSpiralY[vNW];
            if Abs(vNextY - mTargetY) >= 8 then Continue;
            vTerrain := mWorld.TerrainAt(vNextX, vNextY);
            if ((vTerrain = ConstTerrainOcean) <> vSea) and
               (not mWorld.IsCityTile(vNextX, vNextY)) then
                Continue;
            vIdxX := vRawX - vBaseX;
            vIdxY := vNextY - vBaseY;
            if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then Continue;
            vCost := mWalkCost[vIdxX, vIdxY];
            if vCost = 0 then Continue;
            if vCost < vOldCost then
            begin
                vOldCost := vCost; vBestDir := vNW;
            end;
        end;
        if vBestDir <> -1 then Exit(vBestDir);
    end;

    mTargetX := ParaFallbackX;
    mTargetY := ParaFallbackY;
    Result := -1;
end;

function TCivPathfinder.PathSelect(ParaX, ParaY: Integer; ParaSea: Boolean): Boolean;
var
    vCoarseX, vCoarseY, vNX, vNY, vDir, vDistance, vBestDist, vBestDir : Integer;
    vTileX, vTileY, vPathFound : Integer;
begin
    vCoarseX := ParaX div 4;
    vCoarseY := ParaY div 4;
    if vCoarseX < 0 then vCoarseX := 0;
    if vCoarseX > 19 then vCoarseX := 19;
    if vCoarseY < 0 then vCoarseY := 0;
    if vCoarseY > 12 then vCoarseY := 12;

    if ParaSea then
    begin
        if mWorld.CoarseOceanMap[vCoarseX, vCoarseY] <> 0 then
        begin
            mTargetX := vCoarseX; mTargetY := vCoarseY;
            Exit(True);
        end;
    end else
    begin
        if mWorld.CoarseGroundWay[vCoarseX, vCoarseY] <> 0 then
        begin
            mTargetX := vCoarseX; mTargetY := vCoarseY;
            Exit(True);
        end;
    end;

    vBestDist := 99; vBestDir := -1;
    for vDir := 1 to 8 do
    begin
        vNX := vCoarseX + ConstSpiralX[vDir];
        vNY := vCoarseY + ConstSpiralY[vDir];
        if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then Continue;

        if ParaSea then
        begin
            if mWorld.CoarseOceanMap[vNX, vNY] = 0 then Continue;
        end else
        begin
            if mWorld.CoarseGroundWay[vNX, vNY] = 0 then Continue;
        end;

        vDistance := HalfDist(ParaX - vNX * 4 - 1, ParaY - vNY * 4 - 1);
        if vDistance >= vBestDist then Continue;

        vTileX := vNX * 4 + 1; vTileY := vNY * 4 + 1;
        vPathFound := -1;
        for var vAttempt := 0 to 3 do
        begin
            case vAttempt of
                1 : Inc(vTileX);
                2 : Inc(vTileY);
                3 : Dec(vTileX);
            end;
            if (mWorld.IsOcean(vTileX, vTileY)) = ParaSea then
            begin
                vPathFound := PathProbe(vTileX, vTileY, ParaX, ParaY, ParaSea, 18);
                if vPathFound <> -1 then Break;
            end;
        end;

        if vPathFound <> -1 then
        begin
            vBestDist := vDistance;
            vBestDir := vDir;
        end;
    end;

    if vBestDir <> -1 then
    begin
        mTargetX := vCoarseX + ConstSpiralX[vBestDir];
        mTargetY := vCoarseY + ConstSpiralY[vBestDir];
        Exit(True);
    end;
    Result := False;
end;

function TCivPathfinder.PathCoarse(ParaPlayer, ParaUnitIndex: Integer): Boolean;
var
    vUnitX, vUnitY, vDomain, vCoarseX, vCoarseY : Integer;
    vHead, vTail : Byte;
    vFound : Boolean;
    vMask : Byte;
    vDir, vNX, vNY, vCurCost, vBestDist, vBestDir, vTileX, vTileY, vOrigX, vOrigY : Integer;
    vSea : Boolean;
begin
    Result := False;
    vUnitX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].X;
    vUnitY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Y;
    vDomain := mState.mData.UtTypes[
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].UnitType].Domain;
    vSea := vDomain = 2;

    mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
    mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;

    if not PathSelect(vUnitX, vUnitY, vSea) then
    begin
        mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
        mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
        Exit(False);
    end;

    vCoarseX := mTargetX;
    vCoarseY := mTargetY;

    PathSelect(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX,
               mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY, vSea);

    FillChar(mBlockSteps, SizeOf(mBlockSteps), 0);
    vHead := 0; vTail := 0;
    mQueueX[vHead] := ShortInt(mTargetX);
    mQueueY[vHead] := ShortInt(mTargetY);
    Inc(vHead);
    mBlockSteps[mTargetX, mTargetY] := 1;

    vFound := False;
    while vTail <> vHead do
    begin
        vOrigX := mQueueX[vTail];
        vOrigY := mQueueY[vTail];
        if (vOrigX = vCoarseX) and (vOrigY = vCoarseY) then
        begin
            vFound := True; Break;
        end;
        vCurCost := mBlockSteps[vOrigX, vOrigY];
        Inc(vTail);

        if vSea then
            vMask := mWorld.CoarseOceanMap[vOrigX, vOrigY]
        else
            vMask := mWorld.CoarseGroundWay[vOrigX, vOrigY];

        for vDir := 1 to 8 do
        begin
            if ((1 shl (vDir - 1)) and vMask) = 0 then Continue;
            vNX := vOrigX + ConstSpiralX[vDir];
            if vNX = 20 then vNX := 0;
            if vNX = -1 then vNX := 19;
            vNY := vOrigY + ConstSpiralY[vDir];
            if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then Continue;
            if mBlockSteps[vNX, vNY] <> 0 then Continue;
            mBlockSteps[vNX, vNY] := SmallInt(vCurCost + 1);
            mQueueX[vHead] := ShortInt(vNX);
            mQueueY[vHead] := ShortInt(vNY);
            Inc(vHead);
        end;
    end;

    mTargetX := -1;
    if vFound then
    begin
        vBestDist := 99; vBestDir := -1;
        if vSea then
            vMask := mWorld.CoarseOceanMap[vCoarseX, vCoarseY]
        else
            vMask := mWorld.CoarseGroundWay[vCoarseX, vCoarseY];

        for vDir := 1 to 8 do
        begin
            if ((1 shl (vDir - 1)) and vMask) = 0 then Continue;
            vNX := vCoarseX + ConstSpiralX[vDir];
            if vNX = 20 then vNX := 0;
            if vNX = -1 then vNX := 19;
            vNY := vCoarseY + ConstSpiralY[vDir];
            if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then Continue;
            vCurCost := mBlockSteps[vNX, vNY];
            if vCurCost = 0 then Continue;

            vOrigX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
            vOrigY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
            vBestDist := MapDist(vOrigX, vNX * 4 + 1, vOrigY, vNY * 4 + 1);
            if (vBestDir = -1) or (vBestDist <
                MapDist(vOrigX, (mTargetX) * 4 + 1, vOrigY, (mTargetY) * 4 + 1)) then
                vBestDir := vDir;
        end;

        if vBestDir <> -1 then
        begin
            mTargetX := WrapX((vCoarseX + ConstSpiralX[vBestDir]) * 4 + 1);
            mTargetY := (vCoarseY + ConstSpiralY[vBestDir]) * 4 + 1;
            if mWorld.IsOcean(mTargetX, mTargetY) <> vSea then
            begin
                Inc(mTargetX);
                if mWorld.IsOcean(mTargetX, mTargetY) <> vSea then Inc(mTargetY);
            end;
        end;
    end;

    if mTargetX = -1 then
    begin
        mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
        mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
    end;

    Result := vFound;
end;

function TCivPathfinder.UnitGoal(ParaPlayer, ParaUnitIndex: Integer): Integer;
var
    vUnitX, vUnitY, vUnitType, vDomain, vMoves, vTx, vTy : Integer;
    vClose, vFailed : Boolean;
    vBestDir, vOldDistance, vBestCost, vNX, vNY, vRemX, vRemY : Integer;
    vNewDistance, vTerrain, vTileOwner, vMoveCost, vTurnPenalty, vDir : Integer;
begin
    vUnitX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].X;
    vUnitY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Y;
    vUnitType := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].UnitType;
    vDomain := mState.mData.UtTypes[vUnitType].Domain;
    vMoves  := mState.mData.UtTypes[vUnitType].Moves;

    vTx := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX - vUnitX;
    vTy := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY - vUnitY;
    if (Abs(vTx) <= 1) and (Abs(vTy) <= 1) then
    begin
        if Abs(vTx) < 40 then vTx := MapRandom(vTx) else vTx := -MapRandom(vTx);
        vTy := MapRandom(vTy);
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX := -1;
        for vDir := 1 to 8 do
            if (ConstSpiralX[vDir] = vTx) and (ConstSpiralY[vDir] = vTy) then
                Exit(vDir);
        Exit(0);
    end;

    if vDomain = 1 then
    begin
        mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
        mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
    end else
    begin
        vFailed := False;
        vClose := (Abs(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX - vUnitX) < 7)
               or (Abs(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX - vUnitX) > 73);
        if vClose and
           (Abs(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY - vUnitY) < 7) then
        begin
            mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
            mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
            vBestDir := PathSearch(vUnitX, vUnitY, vDomain, vMoves, 999,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY);
            if vBestDir <> -1 then Exit(vBestDir);
            vFailed := True;
        end;
        if PathCoarse(ParaPlayer, ParaUnitIndex) or (not vFailed) then
        begin
            vBestDir := PathSearch(vUnitX, vUnitY, vDomain, vMoves, 999,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY);
            if vBestDir <> -1 then Exit(vBestDir);
        end;
    end;

    vTx := mTargetX - vUnitX;
    vTy := mTargetY - vUnitY;
    vOldDistance := Abs(vTx) + Abs(vTy) + Integer(Abs(vTx) > Abs(vTy) ? Abs(vTx) : Abs(vTy));
    if (vTx = 0) and (vTy = 0) then
    begin
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX := -1;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 := -1;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Moves := 0;
        Exit(-1);
    end;

    vBestCost := 9999; vBestDir := 0;
    for vDir := 1 to 8 do
    begin
        vNX := vUnitX + ConstSpiralX[vDir];
        vNY := vUnitY + ConstSpiralY[vDir];
        vRemX := vTx - ConstSpiralX[vDir];
        vRemY := vTy - ConstSpiralY[vDir];
        vNewDistance := Abs(vRemX) + Abs(vRemY) + Integer(Abs(vRemX) > Abs(vRemY) ? Abs(vRemX) : Abs(vRemY));
        if (ParaPlayer = mState.mData.CivNow) and (vNewDistance > vOldDistance) then Continue;

        vTerrain := mWorld.TerrainAt(vNX, vNY);
        vTileOwner := mWorld.MapOwner(vNX, vNY);
        if ((vTileOwner <> -1) and (vTileOwner <> ParaPlayer)) or
           (((vTerrain = ConstTerrainOcean) <> (vDomain = 2)) and (vDomain <> 1)) then
        begin
            if not mWorld.IsCityTile(vNX, vNY) then Continue;
            if mWorld.MapCity(vNX, vNY) <> ParaPlayer then Continue;
        end;

        if (vTerrain = ConstTerrainOcean) and (mWorld.MapRegion(vNX, vNY) < 5) then Continue;
        if (vMoves > 1) and ((vTerrain <> ConstTerrainOcean) or (vDomain = 2)) then
            vMoveCost := mWorld.TerrainMoveCost(vNX, vNY) * 3
        else if (mWorld.MapFlags(vUnitX, vUnitY) and ConstTileRoad) <> 0 then
            vMoveCost := 1
        else
            vMoveCost := 3;

        vMoveCost := vMoveCost + vNewDistance * 4 + Abs(vRemX) + Abs(vRemY);
        if mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 <> -1 then
        begin
            vTurnPenalty := Abs(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 - vDir);
            if vTurnPenalty > 4 then vTurnPenalty := 8 - vTurnPenalty;
            vMoveCost := vMoveCost + vTurnPenalty * vTurnPenalty;
        end;

        if vMoveCost < vBestCost then
        begin
            vBestDir := vDir; vBestCost := vMoveCost;
        end;
    end;

    if (mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 <> -1) and
       ((mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 xor 4) = vBestDir) then
    begin
        vBestDir := 0;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Moves := 0;
    end;

    if vBestDir = 0 then
    begin
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX := -1;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 := -1;
        vBestDir := -1;
    end else
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 := vBestDir;

    Result := vBestDir;
end;

function TCivPathfinder.PathProbe(ParaX, ParaY, ParaTargetX, ParaTargetY: Integer;
    ParaSea: Boolean; ParaLimit: Integer): Integer;
var
    vDomain, vMoves, vResult : Integer;
begin
    if (Abs(ParaX - ParaTargetX) <= 7) or (Abs(ParaY - ParaTargetY) <= 7) then
    begin
        if ParaSea then begin vDomain := 2; vMoves := 3; end
        else begin vDomain := 0; vMoves := 1; end;
        mTargetX := ParaTargetX;
        mTargetY := ParaTargetY;
        vResult := PathSearch(ParaX, ParaY, vDomain, vMoves, ParaLimit, ParaTargetX, ParaTargetY);
        if vResult <> -1 then Exit(mLimit);
    end;
    Result := -1;
end;

end.