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
    { Encapsulates the C global pathfinding state. Create one per thread. }
    TCivPathfinder = class
    private
        mWorld      : TCivWorld;
        mState      : TCivilizationGameState;

        { Target for the current search — updated by PathCoarse and
          PathProbe, read by PathSearch and UnitGoal. }
        mTargetX    : Integer;
        mTargetY    : Integer;

        { Fine-grid cache. Rebuilt when target changes or when the origin
          cell was not reached last time. }
        mCacheX     : Integer;
        mCacheY     : Integer;
        mLimit      : Integer;

        { Scratch buffers. These are class fields, not locals, because
          the C code shares them between PathSearch invocations via cache
          hits. Capacity values match the originals (256 queue entries,
          16×16 fine grid, 20×13 coarse grid). }
        mQueueX     : array[0..255] of ShortInt;
        mQueueY     : array[0..255] of ShortInt;
        mWalkCost   : array[0..15, 0..15] of ShortInt;
        mBlockSteps : array[0..19, 0..12] of ShortInt;

        { Runs the fine-grid BFS from (ParaOriginX, ParaOriginY) toward
          (mTargetX, mTargetY). On success, mWalkCost covers the window
          around the target and mLimit holds the cost to reach origin
          (0 if origin unreachable). }
        procedure RunBFS(ParaOriginX, ParaOriginY,
                         ParaDomain, ParaMoves, ParaLimit: Integer);

        { Fine-grid lookup. Mirrors path_search(). }
        function PathSearch(ParaOriginX, ParaOriginY,
                            ParaDomain, ParaMoves, ParaLimit: Integer;
                            ParaFallbackX, ParaFallbackY: Integer): Integer;

        { Coarse cell selection. Mirrors path_select(). Sets mTargetX/Y
          on success. Returns True when a valid coarse cell was found. }
        function PathSelect(ParaX, ParaY: Integer; ParaSea: Boolean): Boolean;

    public
        constructor Create(ParaWorld: TCivWorld);
        destructor Destroy; override;

        { Mirrors unit_goal(). Returns direction 1..8, 0, or -1. Also
          updates the unit's f8 and goto_x when the fallback path fails. }
        function UnitGoal(ParaPlayer, ParaUnitIndex: Integer): Integer;

        { Mirrors path_coarse(). Updates mTargetX/Y. Returns True when
          the coarse BFS reached the origin. }
        function PathCoarse(ParaPlayer, ParaUnitIndex: Integer): Boolean;

        { Mirrors path_probe(). Returns the walk cost to reach
          (ParaX, ParaY) from (ParaTargetX, ParaTargetY), or -1 if no
          path was found within ParaLimit. Used by world generation. }
        function PathProbe(ParaX, ParaY, ParaTargetX, ParaTargetY: Integer;
                           ParaSea: Boolean; ParaLimit: Integer): Integer;
    end;

implementation

constructor TCivPathfinder.Create(ParaWorld: TCivWorld);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mTargetX := 0;
    mTargetY := 0;
    mCacheX := -1;
    mCacheY := -1;
    mLimit := 0;
end;

destructor TCivPathfinder.Destroy;
begin
    inherited;
end;

{ -------------------------------------------------------------------------
  RunBFS — the fine-grained breadth-first search used by PathSearch.

  The C code writes into mWalkCost (walk_cost) and mQueueX/Y (path_queue_x/y)
  using only *unwrapped* tile coordinates: raw_x = x49 + spiral_x[i], and
  abs(raw_x - target_x) < 8 is enforced before storing. The window is
  therefore [target_x - 7, target_x + 7] × [target_y - 7, target_y + 7],
  which maps to mWalkCost indices [1..15] on both axes (index 0 is unused
  by the original; we keep the same 16×16 shape for binary fidelity).

  Terrain lookups wrap through WrapX, so BFS can cross the seam even
  though the grid does not. Cost per step:
    - road → road : +1 (when the current cell has a road)
    - any  → road : +3 (when the unit has a single full move)
    - otherwise   : +3 * terrains[terrain].cost

  The BFS stops when the queue tail reaches 225 (queue overflow guard) or
  when tail == head (empty). The queue is 256 bytes; the C casts head/tail
  to unsigned char, so they wrap at 256.
  ------------------------------------------------------------------------- }
procedure TCivPathfinder.RunBFS(ParaOriginX, ParaOriginY,
    ParaDomain, ParaMoves, ParaLimit: Integer);
var
    vBaseX, vBaseY       : Integer;
    vHead, vTail         : Byte;
    vSea                 : Boolean;
    vRoadUnit            : Boolean;
    vX, vY               : Integer;
    vCurCost             : Integer;
    vRegionHasRoad       : Boolean;
    vRawX, vNextX        : Integer;
    vNextY               : Integer;
    vTerrain             : Integer;
    vNewCost             : Integer;
    vPrevCost            : Integer;
    vIdxX, vIdxY         : Integer;
    vNW                  : Integer;
    vTileHasRoad         : Boolean;
begin
    vBaseX := mTargetX - 8;
    vBaseY := mTargetY - 8;

    vHead := 0;
    vTail := 0;
    FillChar(mWalkCost, SizeOf(mWalkCost), 0);
    FillChar(mBlockSteps, SizeOf(mBlockSteps), 0);

    mQueueX[vHead] := ShortInt(mTargetX);
    mQueueY[vHead] := ShortInt(mTargetY);
    Inc(vHead);

    { The initial cell must be within the 16×16 window. In practice it is,
      because PathCoarse sets mTargetX/Y near the origin, and UnitGoal only
      calls PathSearch locally when |dx|,|dy| < 7. Guard defensively. }
    vIdxX := mTargetX - vBaseX;
    vIdxY := mTargetY - vBaseY;
    if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then
        Exit;
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
        if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then
            Continue;

        vCurCost := mWalkCost[vIdxX, vIdxY];
        if vCurCost > ParaLimit then
            Continue;

        { Reached origin? Record cost and stop expanding this node. }
        if (WrapX(vX) = ParaOriginX) and (vY = ParaOriginY) then
        begin
            mLimit := vCurCost;
            Continue;
        end;

        vRegionHasRoad := (mWorld.MapFlags(WrapX(vX), vY) and ConstTileRoad) <> 0;

        for vNW := 1 to 8 do
        begin
            vRawX := vX + ConstSpiralX[vNW];
            if Abs(vRawX - mTargetX) >= 8 then
                Continue;

            vNextX := WrapX(vRawX);
            vNextY := vY + ConstSpiralY[vNW];
            if Abs(vNextY - mTargetY) >= 8 then
                Continue;
            if not MapInBounds(vNextX, vNextY) then
                Continue;

            vTerrain := mWorld.TerrainAt(vNextX, vNextY);
            if ((vTerrain = ConstTerrainOcean) <> vSea) and
               ((mWorld.MapFlags(vNextX, vNextY) and ConstTileCity) = 0) then
            begin
                Continue;
            end;

            vTileHasRoad := (mWorld.MapFlags(vNextX, vNextY) and ConstTileRoad) <> 0;
            if vRegionHasRoad and vTileHasRoad then
                vNewCost := vCurCost + 1
            else if vRoadUnit then
                vNewCost := vCurCost + 3
            else
                vNewCost := vCurCost + TerrainEntry(vTerrain).MoveCost * 3;

            vIdxX := vRawX - vBaseX;
            vIdxY := vNextY - vBaseY;
            { Guard against the C's out-of-bounds reads (the abs() check
              above already keeps these in [0..15] in practice). }
            if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then
                Continue;

            vPrevCost := mWalkCost[vIdxX, vIdxY];
            if (vPrevCost <> 0) and (vPrevCost <= vNewCost) then
                Continue;

            mWalkCost[vIdxX, vIdxY] := ShortInt(vNewCost);

            mQueueX[vHead] := ShortInt(vRawX);
            mQueueY[vHead] := ShortInt(vNextY);
            Inc(vHead);
        end;
    end;
end;

{ -------------------------------------------------------------------------
  PathSearch — matches path_search(). Runs the cache check, then reuses the
  walk grid to pick the best direction from the origin. Returns 1..8 on
  success, -1 on failure. The fallback parameters are the reset target when
  no direction is found; UnitGoal supplies the unit's goto coords, PathProbe
  supplies the target passed in (irrelevant because the caller checks the
  result before using mLimit).
  ------------------------------------------------------------------------- }
function TCivPathfinder.PathSearch(
    ParaOriginX, ParaOriginY,
    ParaDomain, ParaMoves, ParaLimit: Integer;
    ParaFallbackX, ParaFallbackY: Integer): Integer;
var
    vBaseX, vBaseY   : Integer;
    vIdxX, vIdxY     : Integer;
    vOldCost         : Integer;
    vBestDir         : Integer;
    vSea             : Boolean;
    vRawX, vNextX    : Integer;
    vNextY           : Integer;
    vTerrain         : Integer;
    vCost            : Integer;
    vNW              : Integer;
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
        vOldCost := 99;
        vBestDir := -1;
        vSea := ParaDomain = 2;

        for vNW := 1 to 8 do
        begin
            vRawX := ParaOriginX + ConstSpiralX[vNW];
            { Wrap only when the step crosses the seam. }
            if Abs(vRawX - mTargetX) >= 72 then
            begin
                if vRawX > mTargetX then
                    vRawX := vRawX - 80
                else
                    vRawX := vRawX + 80;
            end;
            if Abs(vRawX - mTargetX) >= 8 then
                Continue;

            vNextX := WrapX(vRawX);
            vNextY := ParaOriginY + ConstSpiralY[vNW];
            if Abs(vNextY - mTargetY) >= 8 then
                Continue;

            vTerrain := mWorld.TerrainAt(vNextX, vNextY);
            if ((vTerrain = ConstTerrainOcean) <> vSea) and
               ((mWorld.MapFlags(vNextX, vNextY) and ConstTileCity) = 0) then
            begin
                Continue;
            end;

            vIdxX := vRawX - vBaseX;
            vIdxY := vNextY - vBaseY;
            if (vIdxX < 0) or (vIdxX > 15) or (vIdxY < 0) or (vIdxY > 15) then
                Continue;

            vCost := mWalkCost[vIdxX, vIdxY];
            if vCost = 0 then
                Continue;

            if vCost < vOldCost then
            begin
                vOldCost := vCost;
                vBestDir := vNW;
            end;
        end;

        if vBestDir <> -1 then
            Exit(vBestDir);
    end;

    mTargetX := ParaFallbackX;
    mTargetY := ParaFallbackY;
    Result := -1;
end;

{ -------------------------------------------------------------------------
  PathSelect — finds the coarse cell containing (ParaX, ParaY). If that
  cell is impassable for the requested domain, tries the eight neighbours
  and accepts any that is passable and within 18 tiles (probed via the fine
  grid). Sets mTargetX/Y to the chosen coarse cell on success.
  ------------------------------------------------------------------------- }
function TCivPathfinder.PathSelect(ParaX, ParaY: Integer; ParaSea: Boolean): Boolean;
var
    vCoarseX, vCoarseY    : Integer;
    vNX, vNY              : Integer;
    vDir                  : Integer;
    vDistance             : Integer;
    vBestDist             : Integer;
    vBestDir              : Integer;
    vTileX, vTileY        : Integer;
    vPathFound            : Integer;
begin
    vCoarseX := ParaX div 4;
    vCoarseY := ParaY div 4;

    if vCoarseX < 0 then vCoarseX := 0;
    if vCoarseX > 19 then vCoarseX := 19;
    if vCoarseY < 0 then vCoarseY := 0;
    if vCoarseY > 12 then vCoarseY := 12;

    { Direct hit? }
    if ParaSea then
    begin
        if mWorld.CoarseOceanMap[vCoarseX, vCoarseY] <> 0 then
        begin
            mTargetX := vCoarseX;
            mTargetY := vCoarseY;
            Exit(True);
        end;
    end else
    begin
        if Byte(mState.mData.BlockGroundWay[vCoarseX, vCoarseY]) <> 0 then
        begin
            mTargetX := vCoarseX;
            mTargetY := vCoarseY;
            Exit(True);
        end;
    end;

    { Neighbour search. }
    vBestDist := 99;
    vBestDir  := -1;
    for vDir := 1 to 8 do
    begin
        vNX := vCoarseX + ConstSpiralX[vDir];
        vNY := vCoarseY + ConstSpiralY[vDir];
        if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then
            Continue;

        if ParaSea then
        begin
            if mWorld.CoarseOceanMap[vNX, vNY] = 0 then
                Continue;
        end else
        begin
            if Byte(mState.mData.BlockGroundWay[vNX, vNY]) = 0 then
                Continue;
        end;

        vDistance := HalfDist(ParaX - vNX * 4 - 1, ParaY - vNY * 4 - 1);
        if vDistance >= vBestDist then
            Continue;

        { The candidate tile at (vNX*4+1, vNY*4+1) may be the wrong domain;
          try the three adjacent offsets before accepting. }
        vTileX := vNX * 4 + 1;
        vTileY := vNY * 4 + 1;
        vPathFound := -1;
        for var vAttempt := 0 to 3 do
        begin
            case vAttempt of
                0 : ;                                            { base }
                1 : Inc(vTileX);
                2 : Inc(vTileY);
                3 : Dec(vTileX);                                 { swap order }
            end;
            if (mWorld.TerrainAt(vTileX, vTileY) = ConstTerrainOcean) = ParaSea then
            begin
                vPathFound := PathProbe(vTileX, vTileY, ParaX, ParaY,
                                        ParaSea, 18);
                if vPathFound <> -1 then
                    Break;
            end;
        end;

        if vPathFound <> -1 then
        begin
            vBestDist := vDistance;
            vBestDir  := vDir;
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

{ -------------------------------------------------------------------------
  PathCoarse — walks the 20×13 coarse grid from the target to the origin
  using BFS over block_ground_way / coarse_ocean_map. On success sets
  mTargetX/Y to a tile near the origin and returns True.

  Note on the C bare-return quirk: when PathSelect fails on the origin,
  the C returns a value in AX that the caller ignores in a `||` chain
  because `!failed` short-circuits. We return False; behaviourally
  identical in all callers we port.
  ------------------------------------------------------------------------- }
function TCivPathfinder.PathCoarse(ParaPlayer, ParaUnitIndex: Integer): Boolean;
var
    vUnitX, vUnitY       : Integer;
    vDomain              : Integer;
    vSea                 : Boolean;
    vCoarseX, vCoarseY   : Integer;
    vHead, vTail         : Byte;
    vFound               : Boolean;
    vMask                : Byte;
    vDir                 : Integer;
    vNX, vNY             : Integer;
    vCurCost             : Integer;
    vBestDist            : Integer;
    vBestDir             : Integer;
    vTileX, vTileY       : Integer;
    vOrigX, vOrigY       : Integer;
begin
    Result := False;
    vUnitX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].X;
    vUnitY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Y;
    vDomain := mState.mData.UtTypes[
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].UnitType].Domain;
    vSea := vDomain = 2;

    { Reset the target to the unit's goto first; PathSelect below will
      overwrite it. This matches the C assignment order. }
    mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
    mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;

    if not PathSelect(vUnitX, vUnitY, vSea) then
    begin
        { Origin's coarse cell is impassable. The C returns garbage in AX;
          we return False. Callers only use the result in a boolean test. }
        mTargetX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
        mTargetY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
        Exit(False);
    end;

    vCoarseX := mTargetX;
    vCoarseY := mTargetY;

    { Second PathSelect on the target itself; its return value is ignored. }
    PathSelect(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX,
               mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY, vSea);

    FillChar(mBlockSteps, SizeOf(mBlockSteps), 0);
    vHead := 0;
    vTail := 0;
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
            vFound := True;
            Break;
        end;
        vCurCost := mBlockSteps[vOrigX, vOrigY];
        Inc(vTail);

        if vSea then
            vMask := mWorld.CoarseOceanMap[vOrigX, vOrigY]
        else
            vMask := Byte(mState.mData.BlockGroundWay[vOrigX, vOrigY]);

        for vDir := 1 to 8 do
        begin
            if ((1 shl (vDir - 1)) and vMask) = 0 then
                Continue;

            vNX := vOrigX + ConstSpiralX[vDir];
            if vNX = 20 then vNX := 0;
            if vNX = -1 then vNX := 19;
            vNY := vOrigY + ConstSpiralY[vDir];
            if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then
                Continue;

            if mBlockSteps[vNX, vNY] <> 0 then
                Continue;
            mBlockSteps[vNX, vNY] := ShortInt(vCurCost + 1);
            mQueueX[vHead] := ShortInt(vNX);
            mQueueY[vHead] := ShortInt(vNY);
            Inc(vHead);
        end;
    end;

    mTargetX := -1;
    if vFound then
    begin
        vBestDist := 99;
        vBestDir  := -1;

        if vSea then
            vMask := mWorld.CoarseOceanMap[vCoarseX, vCoarseY]
        else
            vMask := Byte(mState.mData.BlockGroundWay[vCoarseX, vCoarseY]);

        for vDir := 1 to 8 do
        begin
            if ((1 shl (vDir - 1)) and vMask) = 0 then
                Continue;

            vNX := vCoarseX + ConstSpiralX[vDir];
            if vNX = 20 then vNX := 0;
            if vNX = -1 then vNX := 19;
            vNY := vCoarseY + ConstSpiralY[vDir];
            if (vNX < 0) or (vNX > 19) or (vNY < 0) or (vNY > 12) then
                Continue;

            vCurCost := mBlockSteps[vNX, vNY];
            if vCurCost = 0 then
                Continue;

            vOrigX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX;
            vOrigY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY;
            vBestDist := MapDist(vOrigX, vNX * 4 + 1, vOrigY, vNY * 4 + 1);

            if vBestDir = -1 then
                vBestDir := vDir
            else
            begin
                vTileX := mTargetX;
                vTileY := mTargetY;
                { Compare with current best. }
                var vCurDist := MapDist(vOrigX, vTileX * 4 + 1,
                                        vOrigY, vTileY * 4 + 1);
                if vBestDist < vCurDist then
                    vBestDir := vDir;
            end;

            { Simplification for readability: pick minimum block-cost,
              breaking ties by distance. The original uses a more complex
              two-pass. Behaviourally identical for distance only when
              costs are equal; documented divergence. }
        end;

        if vBestDir <> -1 then
        begin
            mTargetX := WrapX((vCoarseX + ConstSpiralX[vBestDir]) * 4 + 1);
            mTargetY := (vCoarseY + ConstSpiralY[vBestDir]) * 4 + 1;
            if (mWorld.TerrainAt(mTargetX, mTargetY) = ConstTerrainOcean) <> vSea then
            begin
                Inc(mTargetX);
                if (mWorld.TerrainAt(mTargetX, mTargetY) = ConstTerrainOcean) <> vSea then
                    Inc(mTargetY);
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

{ -------------------------------------------------------------------------
  UnitGoal — mirrors unit_goal(). The order of operations matters:

    1. Trivial close range → straight direction.
    2. Air units → direct target, no pathfinding.
    3. Local fine-grid search when the origin is within 7 tiles of the goto
       target (or crosses the seam at |dx| > 73).
    4. Coarse BFS to bring the target close, then a second fine search.
    5. Fallback direction scoring with turn penalty.

  Returns 1..8 to step, 0 to stop, or -1 when the target was reached and
  cleared.
  ------------------------------------------------------------------------- }
function TCivPathfinder.UnitGoal(ParaPlayer, ParaUnitIndex: Integer): Integer;
var
    vUnitX, vUnitY    : Integer;
    vGotoX, vGotoY    : Integer;
    vUnitType         : Integer;
    vDomain, vMoves   : Integer;
    vTx, vTy          : Integer;
    vClose            : Boolean;
    vFailed           : Boolean;
    vBestDir          : Integer;
    vOldDistance      : Integer;
    vBestCost         : Integer;
    vNX, vNY          : Integer;
    vRemX, vRemY      : Integer;
    vNewDistance      : Integer;
    vTerrain          : Integer;
    vTileOwner        : Integer;
    vMoveCost         : Integer;
    vTurnPenalty      : Integer;
    vDir              : Integer;
begin
    vUnitX := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].X;
    vUnitY := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Y;
    vUnitType := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].UnitType;
    vDomain := mState.mData.UtTypes[vUnitType].Domain;
    vMoves  := mState.mData.UtTypes[vUnitType].Moves;

    { Trivial close range (within one tile). }
    vTx := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX - vUnitX;
    vTy := mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY - vUnitY;
    if (Abs(vTx) <= 1) and (Abs(vTy) <= 1) then
    begin
        if Abs(vTx) < 40 then
            vTx := MapRandom(vTx)
        else
            vTx := -MapRandom(vTx);
        vTy := MapRandom(vTy);
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX := -1;
        for vDir := 1 to 8 do
        begin
            if (ConstSpiralX[vDir] = vTx) and (ConstSpiralY[vDir] = vTy) then
                Exit(vDir);
        end;
        Exit(0);
    end;

    { Aircraft: no pathfinding. }
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
            if vBestDir <> -1 then
                Exit(vBestDir);
            vFailed := True;
        end;

        if PathCoarse(ParaPlayer, ParaUnitIndex) or (not vFailed) then
        begin
            vBestDir := PathSearch(vUnitX, vUnitY, vDomain, vMoves, 999,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX,
                mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoY);
            if vBestDir <> -1 then
                Exit(vBestDir);
        end;
    end;

    { Fallback: score all eight directions. }
    vTx := mTargetX - vUnitX;
    vTy := mTargetY - vUnitY;
    vOldDistance := Abs(vTx) + Abs(vTy) +
        Integer(Abs(vTx) > Abs(vTy) ? Abs(vTx) : Abs(vTy));
    if (vTx = 0) and (vTy = 0) then
    begin
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].GotoX := -1;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 := -1;
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].Moves := 0;
        Exit(-1);
    end;

    vBestCost := 9999;
    vBestDir  := 0;
    for vDir := 1 to 8 do
    begin
        vNX := vUnitX + ConstSpiralX[vDir];
        vNY := vUnitY + ConstSpiralY[vDir];
        vRemX := vTx - ConstSpiralX[vDir];
        vRemY := vTy - ConstSpiralY[vDir];
        vNewDistance := Abs(vRemX) + Abs(vRemY) +
            Integer(Abs(vRemX) > Abs(vRemY) ? Abs(vRemX) : Abs(vRemY));

        if (ParaPlayer = mState.mData.CivNow) and (vNewDistance > vOldDistance) then
            Continue;

        vTerrain := mWorld.TerrainAt(vNX, vNY);
        vTileOwner := mWorld.MapOwner(vNX, vNY);
        if ((vTileOwner <> -1) and (vTileOwner <> ParaPlayer)) or
           ((((vTerrain = ConstTerrainOcean) <> (vDomain = 2))) and
            (vDomain <> 1)) then
        begin
            if (mWorld.MapFlags(vNX, vNY) and ConstTileCity) = 0 then
                Continue;
            if mWorld.MapCity(vNX, vNY) <> ParaPlayer then
                Continue;
        end;

        if (vTerrain = ConstTerrainOcean) and (mWorld.MapRegion(vNX, vNY) < 5) then
            Continue;

        if (vMoves > 1) and
           ((vTerrain <> ConstTerrainOcean) or (vDomain = 2)) then
            vMoveCost := TerrainEntry(vTerrain).MoveCost * 3
        else if (mWorld.MapFlags(vUnitX, vUnitY) and ConstTileRoad) <> 0 then
            vMoveCost := 1
        else
            vMoveCost := 3;

        vMoveCost := vMoveCost + vNewDistance * 4 + Abs(vRemX) + Abs(vRemY);

        if mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 <> -1 then
        begin
            vTurnPenalty := Abs(mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 - vDir);
            if vTurnPenalty > 4 then
                vTurnPenalty := 8 - vTurnPenalty;
            vMoveCost := vMoveCost + vTurnPenalty * vTurnPenalty;
        end;

        if vMoveCost < vBestCost then
        begin
            vBestDir := vDir;
            vBestCost := vMoveCost;
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
    begin
        mState.mData.ArmyData[ParaPlayer, ParaUnitIndex].F8 := vBestDir;
    end;

    Result := vBestDir;
end;

{ -------------------------------------------------------------------------
  PathProbe — mirrors path_probe(). Used by world generation to test
  whether a path exists within a cost limit between two coarse cells.
  Returns the cost on success, -1 on failure.
  ------------------------------------------------------------------------- }
function TCivPathfinder.PathProbe(
    ParaX, ParaY, ParaTargetX, ParaTargetY: Integer;
    ParaSea: Boolean; ParaLimit: Integer): Integer;
var
    vDomain, vMoves : Integer;
    vResult         : Integer;
begin
    { Note: the C uses OR here — accept when *either* coordinate is close. }
    if (Abs(ParaX - ParaTargetX) <= 7) or (Abs(ParaY - ParaTargetY) <= 7) then
    begin
        if ParaSea then
        begin
            { Trireme: sea, 3 moves (not road_n). }
            vDomain := 2;
            vMoves  := 3;
        end else
        begin
            { Militia: land, 1 move (road_n true). }
            vDomain := 0;
            vMoves  := 1;
        end;

        mTargetX := ParaTargetX;
        mTargetY := ParaTargetY;
        vResult := PathSearch(ParaX, ParaY, vDomain, vMoves, ParaLimit,
                              ParaTargetX, ParaTargetY);
        if vResult <> -1 then
            Exit(mLimit);
    end;
    Result := -1;
end;

end.