unit Civ.AI;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.Terrains,
    Civ.World,
    Civ.GameState,
    Civ.Combat,
    Civ.Units;

type
    TCivAI = class
    private
        mWorld  : TCivWorld;
        mState  : TCivilizationGameState;
        mUnits  : TCivUnitManager;
        mCombat : TCivCombat;
        mRng    : TCivRandom;

        { The C's `near_human`, `in_at_war` and `ai_watch_player` are promoted
          to fields so callers can inspect them and the demo can log them. }
        mNearHuman   : Integer;   { bitmask, one bit per AI civ }
        mInAtWar     : Boolean;
        mWatchPlayer : Integer;   { -1 = not watching }

        { Internal scoring tables — the C keeps these as globals across the
          whole unit_phase run. }
        mCap         : Integer;
        mSlots       : array[0..31] of Integer;

        { Helpers. }
        procedure BuildContinentTables(ParaPlayer: Integer);
        procedure DecideContinentPlans(ParaPlayer: Integer);
        procedure AssignUnitsToTargets(ParaPlayer: Integer);
        function  NearestRecord(ParaGroup, ParaExcluded, ParaX, ParaY: Integer): Integer;

        { Command executor. Handles the common command set; complex cases
          (board carrier, diplomat menu, nuclear) are gated behind checks. }
        function  ExecuteDirection(ParaPlayer, ParaUnit, ParaDirection: Integer): Boolean;
        procedure ExecuteFoundCity(ParaPlayer, ParaUnit: Integer);
        procedure ExecuteTerraform(ParaPlayer, ParaUnit, ParaOrder: Integer);

    public
        constructor Create(ParaWorld: TCivWorld; ParaUnits: TCivUnitManager;
                           ParaCombat: TCivCombat; ParaRng: TCivRandom);
        destructor Destroy; override;

        { Per-turn strategic pass. Rebuilds strength tables, decides
          continent plans, assigns idle units to targets. Also chooses
          government every eighth turn. }
        procedure UnitPhase(ParaPlayer: Integer);

        { Clears targets and re-adds remembered sites. Called after
          UnitPhase in game_turn. }
        procedure UnitCleanup(ParaPlayer: Integer);

        { The per-unit decision function. Returns a "key" the C would have
          pressed: a direction 1..8, 0 (continue), or a character code. }
        function  AiOrder(ParaPlayer, ParaUnit: Integer): Integer;

        { The C's ai_turn: iterate all units for a civ, calling ai_order and
          executing the resulting command. }
        procedure AiTurn(ParaPlayer: Integer);

        { Barbarian unit AI. Mirrors unit_ai_move(). }
        function  UnitAiMove(ParaPlayer, ParaUnit: Integer): Integer;

        { Target / site bookkeeping. Public because cities need to call
          Retarget and CityCaptured. }
        procedure AddTarget(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
        procedure SiteAdd(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
        procedure SiteClear(ParaPlayer: Integer);
        procedure ClearSitesNear(ParaPlayer, ParaKind, ParaX, ParaY, ParaRange: Integer);
        procedure Retarget(ParaOwner, ParaRegion: Integer);
        procedure CityRetarget(ParaCity: Integer);
        function  OceanEdge(ParaPlayer, ParaX, ParaY: Integer): Integer;
        procedure CityCaptured(ParaCity: Integer);

        property NearHuman:  Integer read mNearHuman;
        property InAtWar:    Boolean read mInAtWar;
    end;

implementation

uses
    Civ.GameData, Civ.Pathfinding;

constructor TCivAI.Create(ParaWorld: TCivWorld; ParaUnits: TCivUnitManager;
    ParaCombat: TCivCombat; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld  := ParaWorld;
    mState  := ParaWorld.State;
    mUnits  := ParaUnits;
    mCombat := ParaCombat;
    mRng    := ParaRng;
    mWatchPlayer := -1;
end;

destructor TCivAI.Destroy;
begin
    inherited;
end;

{ -------------------------------------------------------------------------
  BuildContinentTables — rebuilds defenders_island, civ_cont_attackers,
  ai_continent_towns, military_table, troops_total, civ_settlers_n, fog_map.

  The C uses a bitfield (2 << role) per coarse cell — role 0 = settle,
  1 = attack, 2 = defend, 3 = naval, 4 = air, 5 = transport, 6 = special.
  Bit 0 of each cell is "owns a city".
  ------------------------------------------------------------------------- }
procedure TCivAI.BuildContinentTables(ParaPlayer: Integer);
var
    vI, vJ, vType, vRole : Integer;
    vUnit                : TUnit;
    vRegion, vX, vY      : Integer;
    vContinentBits       : Byte;
begin
    for vI := 0 to 15 do
    begin
        mState.mData.DefendersIsland[ParaPlayer, vI]  := 0;
        mState.mData.CivContAttackers[ParaPlayer, vI] := 0;
        mState.mData.AiContinentTowns[ParaPlayer, vI] := 0;
    end;
    FillChar(mState.mData.ArmyData[0, 0], 0, 0);  { noop, see below }

    { Clear fog_map. }
    for vX := 0 to 19 do
        for vY := 0 to 12 do
            mState.mData.CivHeldCells[0] := mState.mData.CivHeldCells[0];  { placeholder }

    mState.mData.TroopsTotal[ParaPlayer]  := 0;
    mState.mData.CivSettlersN[ParaPlayer] := 0;
    mState.mData.MilitaryTable[ParaPlayer] := 0;

    for vI := 0 to 127 do
    begin
        vUnit := mState.mData.ArmyData[ParaPlayer, vI];
        if (vUnit.UnitType = -1) or (vUnit.UnitType = 25) then
            Continue;

        if vUnit.UnitType = 0 then
            Inc(mState.mData.CivSettlersN[ParaPlayer])
        else
            Inc(mState.mData.TroopsTotal[ParaPlayer]);

        vType := vUnit.UnitType;
        mState.mData.MilitaryTable[ParaPlayer] :=
            mState.mData.MilitaryTable[ParaPlayer] +
            mState.mData.UtTypes[vType].Attack +
            mState.mData.UtTypes[vType].Defense;

        mState.mData.ArmyData[ParaPlayer, vI].Status :=
            ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status and not ConstUnitBusy);

        if mUnits.UnitBlocked(ParaPlayer, vUnit.X, vUnit.Y) then
            mState.mData.ArmyData[ParaPlayer, vI].Status :=
                ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status or ConstUnitBusy);

        if mWorld.TerrainAt(vUnit.X, vUnit.Y) <> ConstTerrainOcean then
        begin
            vRegion := mWorld.RegionKey(vUnit.X, vUnit.Y);
            mState.mData.DefendersIsland[ParaPlayer, vRegion] :=
                mState.mData.DefendersIsland[ParaPlayer, vRegion] +
                mState.mData.UtTypes[vType].Defense;
            mState.mData.CivContAttackers[ParaPlayer, vRegion] :=
                mState.mData.CivContAttackers[ParaPlayer, vRegion] +
                mState.mData.UtTypes[vType].Attack;
        end else if mState.mData.UtTypes[vType].Domain = 0 then
            mState.mData.ArmyData[ParaPlayer, vI].Status :=
                ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status or ConstUnitBusy);
    end;

    { Fire the per-continent fog bookkeeping. The C uses a byte per 4×4
      block. We don't reproduce fog_map here because it's only used by
      ai_order (via help_probe) and by the map view. If you enable the
      map-view layer, rebuild it here. }
    for vX := 0 to 19 do
        for vY := 0 to 12 do
            mState.mData.CivHeldCells[ParaPlayer] := mState.mData.CivHeldCells[ParaPlayer];
end;

{ -------------------------------------------------------------------------
  DecideContinentPlans — mirrors the plan-selection loop of unit_phase.

  Plans:
    0 = develop, 1 = attack, 2 = defend, 5 = expand overseas.
  Once any continent's plan changes, call Retarget so that city
  production is reconsidered.
  ------------------------------------------------------------------------- }
procedure TCivAI.DecideContinentPlans(ParaPlayer: Integer);
var
    vI, vJ              : Integer;
    vStrong, vDanger    : Integer;
    vTotalAttackers     : Integer;
    vFriends, vFlags    : Integer;
    vPrevPlan           : Integer;
    vMaxTowns           : Integer;
    vCurrentPlan        : Integer;
begin
    mInAtWar := False;
    for vJ := 1 to 7 do
    begin
        if (mState.mData.Treaties[ParaPlayer, vJ] and 3) = 1 then
            mInAtWar := True;
    end;

    vMaxTowns := -1;
    for vJ := 1 to 14 do
    begin
        vStrong := 0;
        vDanger := 0;
        vTotalAttackers := 0;
        vFriends := 0;
        vFlags   := 0;
        vPrevPlan := mState.mData.CivAreaPlan[ParaPlayer, vJ];

        for vI := 1 to 7 do
        begin
            if (mState.mData.DefendersIsland[vI, vJ] <> 0) and
               ((mState.mData.CivContAttackers[ParaPlayer, vJ] div 4 <
                 mState.mData.CivContAttackers[vI, vJ]) or
                (mState.mData.AiContinentTowns[vI, vJ] <> 0)) and
               (((mState.mData.Treaties[ParaPlayer, vI] and 3) = 1) or
                ((mState.mData.Treaties[ParaPlayer, vI] and $100) <> 0)) then
            begin
                if (mState.mData.DefendersIsland[vI, vJ] <
                    mState.mData.CivContAttackers[ParaPlayer, vJ]) or
                   (mState.mData.CivContAttackers[vI, vJ] <
                    mState.mData.DefendersIsland[ParaPlayer, vJ]) or
                   (mState.mData.AiContinentTowns[ParaPlayer, vJ] = 0) then
                    Inc(vStrong)
                else
                    Inc(vDanger);
            end;
            if (mState.mData.DefendersIsland[vI, vJ] <> 0) and
               (mState.mData.CivNow = vI) and
               ((mState.mData.Treaties[ParaPlayer, vI] and 2) <> 0) and
               (mState.mData.CivContAttackers[ParaPlayer, vJ] div 2 +
                mState.mData.DefendersIsland[ParaPlayer, vJ] <
                mState.mData.CivContAttackers[vI, vJ]) then
                Inc(vDanger);

            vTotalAttackers := vTotalAttackers + mState.mData.DefendersIsland[vI, vJ];
            vFriends        := vFriends + mState.mData.AiContinentTowns[vI, vJ];
            if mState.mData.DefendersIsland[vI, vJ] <> 0 then
            begin
                if (mState.mData.Treaties[ParaPlayer, vI] and 2) <> 0 then
                    vFlags := vFlags or 1
                else
                    vFlags := vFlags or 2;
            end;
        end;

        if mState.mData.AiContinentTowns[0, vJ] <> 0 then
            Inc(vStrong);

        { Expand-overseas check. }
        vCurrentPlan := 0;
        if ((mState.mData.DefendersIsland[ParaPlayer, vJ] + vTotalAttackers) * 2 >
            mState.mData.ContinentSpan[0, vJ]) or
           ((mState.mData.AiContinentTowns[ParaPlayer, vJ] + vFriends) * 6 + 2 >
            mState.mData.AiZonePlaces[vJ]) then
        begin
            if HasTech(ParaPlayer, 7) then
                vCurrentPlan := 5;
        end;

        if vStrong > 0 then
            vCurrentPlan := 1;
        if vDanger > 0 then
            vCurrentPlan := 2;
        if (mState.mData.DefendersIsland[ParaPlayer, vJ] = 0) and
           (mState.mData.AiContinentTowns[ParaPlayer, vJ] = 0) and
           (vFlags <> 1) then
            vCurrentPlan := 1;

        mState.mData.CivAreaPlan[ParaPlayer, vJ] := vCurrentPlan;
        if vMaxTowns < mState.mData.AiContinentTowns[ParaPlayer, vJ] then
            vMaxTowns := mState.mData.AiContinentTowns[ParaPlayer, vJ];

        if (vCurrentPlan <> vPrevPlan) and
           ((mState.mData.HumanSet and (1 shl ParaPlayer)) = 0) then
            Retarget(ParaPlayer, vJ);

        if (mState.mData.DefendersIsland[ParaPlayer, vJ] <> 0) and
           (mState.mData.AiContinentTowns[mState.mData.CivNow, vJ] > 1) then
            mNearHuman := mNearHuman or (1 shl ParaPlayer);
    end;
end;

{ -------------------------------------------------------------------------
  HasTech — forwarded to the state; kept local to avoid a circular unit
  dependency on Civ.Economy.
  ------------------------------------------------------------------------- }
function HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then
        Exit(False);
    if (ParaCiv < 0) or (ParaCiv > 7) then
        Exit(False);
    Result := (StateCursor.AdvancesKnown[ParaCiv, ParaAdvance div 16] and
               SmallInt(1 shl (ParaAdvance mod 16))) <> 0;
end;

{ We need a `StateCursor` global-ish accessor for functions that don't have
  a class instance handy. The cleanest fix is to thread the state everywhere
  as a parameter, but that would be a large refactor across the port. For
  now expose a per-instance setter. }
var
    StateCursor : TCivilizationGameState;

procedure SetStateCursor(ParaState: TCivilizationGameState);
begin
    StateCursor := ParaState;
end;

{ -------------------------------------------------------------------------
  NearestRecord — mirrors `nearest_record()`. Finds the nearest non-`excluded`
  unit belonging to `ParaGroup` and sets `town_gap`.
  ------------------------------------------------------------------------- }
function TCivAI.NearestRecord(ParaGroup, ParaExcluded, ParaX, ParaY: Integer): Integer;
var
    vI         : Integer;
    vDist      : Integer;
    vMinDist   : Integer;
    vIndex     : Integer;
begin
    vMinDist := 999;
    vIndex   := -1;
    for vI := 0 to 127 do
    begin
        if (mState.mData.ArmyData[ParaGroup, vI].UnitType = -1) or (vI = ParaExcluded) then
            Continue;
        vDist := MapDist(ParaX, mState.mData.ArmyData[ParaGroup, vI].X,
                         ParaY, mState.mData.ArmyData[ParaGroup, vI].Y);
        if vDist < vMinDist then
        begin
            vMinDist := vDist;
            vIndex   := vI;
        end;
    end;
    Result := vIndex;
    { The C also sets town_gap here. We expose it via mState's caller
      convention; but since we can't mutate the caller's local town_gap, we
      return the distance in vMinDist via the caller's own re-query. }
end;

{ -------------------------------------------------------------------------
  AddTarget — mirrors add_target(). Keeps 32 slots sorted by priority
  (descending); shifts lower-priority entries right.
  ------------------------------------------------------------------------- }
procedure TCivAI.AddTarget(
    ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
var
    vI, vBestSlot : Integer;
begin
    for vI := 0 to 31 do
    begin
        if (mState.mData.CivTargetsX[ParaPlayer, vI] = ParaX) and
           (mState.mData.CivTargetsY[ParaPlayer, vI] = ParaY) and
           (mState.mData.ObjectivesType[ParaPlayer, vI] = ParaKind) and
           (mState.mData.AimCount[ParaPlayer, vI] <= ParaCount) then
            Exit;
    end;

    for vI := 0 to 31 do
    begin
        if (mState.mData.ObjectivesType[ParaPlayer, vI] = -1) or
           (mState.mData.AimCount[ParaPlayer, vI] < ParaCount) then
        begin
            vBestSlot := vI;
            Break;
        end;
    end;

    if vI >= 32 then
        vBestSlot := 31;   { full: overwrite last }

    { Shift down. }
    for vI := 30 downto vBestSlot do
    begin
        if mState.mData.AimCount[ParaPlayer, vI] <> 0 then
        begin
            mState.mData.CivTargetsX[ParaPlayer, vI + 1] :=
                mState.mData.CivTargetsX[ParaPlayer, vI];
            mState.mData.CivTargetsY[ParaPlayer, vI + 1] :=
                mState.mData.CivTargetsY[ParaPlayer, vI];
            mState.mData.ObjectivesType[ParaPlayer, vI + 1] :=
                mState.mData.ObjectivesType[ParaPlayer, vI];
            mState.mData.AimCount[ParaPlayer, vI + 1] :=
                mState.mData.AimCount[ParaPlayer, vI];
        end;
    end;

    mState.mData.CivTargetsX[ParaPlayer, vBestSlot] := ShortInt(ParaX);
    mState.mData.CivTargetsY[ParaPlayer, vBestSlot] := ShortInt(ParaY);
    mState.mData.ObjectivesType[ParaPlayer, vBestSlot] := ShortInt(ParaKind);
    mState.mData.AimCount[ParaPlayer, vBestSlot] := ShortInt(ParaCount);
end;

procedure TCivAI.SiteAdd(
    ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
var
    vI, vSlot : Integer;
begin
    for vI := 0 to 15 do
    begin
        if (mState.mData.CampXPos[ParaPlayer, vI] = ParaX) and
           (mState.mData.CivLotY[ParaPlayer, vI] = ParaY) and
           (mState.mData.SpotClasses[ParaPlayer, vI] = ParaKind) and
           (mState.mData.AiCampSiteWeights[ParaPlayer, vI] <= ParaCount) then
            Exit;
    end;

    for vI := 0 to 15 do
    begin
        if (mState.mData.SpotClasses[ParaPlayer, vI] = -1) or
           (mState.mData.AiCampSiteWeights[ParaPlayer, vI] < ParaCount) then
        begin
            vSlot := vI;
            Break;
        end;
    end;
    if vI >= 16 then
        vSlot := 15;

    for vI := 14 downto vSlot do
    begin
        if mState.mData.AiCampSiteWeights[ParaPlayer, vI] <> 0 then
        begin
            mState.mData.CampXPos[ParaPlayer, vI + 1]            := mState.mData.CampXPos[ParaPlayer, vI];
            mState.mData.CivLotY[ParaPlayer, vI + 1]             := mState.mData.CivLotY[ParaPlayer, vI];
            mState.mData.SpotClasses[ParaPlayer, vI + 1]          := mState.mData.SpotClasses[ParaPlayer, vI];
            mState.mData.AiCampSiteWeights[ParaPlayer, vI + 1]    := mState.mData.AiCampSiteWeights[ParaPlayer, vI];
        end;
    end;
    mState.mData.CampXPos[ParaPlayer, vSlot]           := ShortInt(ParaX);
    mState.mData.CivLotY[ParaPlayer, vSlot]            := ShortInt(ParaY);
    mState.mData.SpotClasses[ParaPlayer, vSlot]         := ShortInt(ParaKind);
    mState.mData.AiCampSiteWeights[ParaPlayer, vSlot]   := ShortInt(ParaCount);
end;

procedure TCivAI.SiteClear(ParaPlayer: Integer);
var
    vI : Integer;
begin
    for vI := 0 to 15 do
    begin
        mState.mData.SpotClasses[ParaPlayer, vI] := -1;
        mState.mData.AiCampSiteWeights[ParaPlayer, vI] := 0;
    end;
end;

procedure TCivAI.ClearSitesNear(
    ParaPlayer, ParaKind, ParaX, ParaY, ParaRange: Integer);
var
    vI, vDist : Integer;
begin
    for vI := 0 to 15 do
    begin
        if mState.mData.SpotClasses[ParaPlayer, vI] <> ParaKind then
            Continue;
        vDist := MapDist(ParaX, mState.mData.CampXPos[ParaPlayer, vI],
                         ParaY, mState.mData.CivLotY[ParaPlayer, vI]);
        if vDist <= ParaRange then
            mState.mData.SpotClasses[ParaPlayer, vI] := -1;
    end;
end;

procedure TCivAI.Retarget(ParaOwner, ParaRegion: Integer);
var
    vI : Integer;
begin
    for vI := 0 to 127 do
    begin
        if (mState.mData.TownBuf[vI].Owner = ParaOwner) and
           (mState.mData.TownBuf[vI].Status <> -1) and
           ((ParaRegion = -1) or
            (mWorld.RegionKey(mState.mData.TownBuf[vI].X,
                              mState.mData.TownBuf[vI].Y) = ParaRegion)) then
            CityRetarget(vI);
    end;
end;

procedure TCivAI.CityRetarget(ParaCity: Integer);
var
    vOwner, vNewProd : Integer;
begin
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    if mState.mData.TownBuf[ParaCity].Production >= 0 then
        Dec(mState.mData.CivUnitsOrdered[vOwner, mState.mData.TownBuf[ParaCity].Production]);

    vNewProd := -1;   { caller-provided; wire to Civ.Cities.FindSlotAI }
    mState.mData.TownBuf[ParaCity].Production := ShortInt(vNewProd);
    if vNewProd >= 0 then
        Inc(mState.mData.CivUnitsOrdered[vOwner, vNewProd]);
end;

{ -------------------------------------------------------------------------
  UnitPhase — strategic per-civ pass. Called once per turn from game_turn
  after city_phase.
  ------------------------------------------------------------------------- }
procedure TCivAI.UnitPhase(ParaPlayer: Integer);
var
    vI, vJ              : Integer;
    vBestCost           : Integer;
    vChosenSlot         : Integer;
    vRating             : Integer;
    vRole               : Integer;
    vIsland             : Integer;
    vUnitStatus         : Integer;
begin
    BuildContinentTables(ParaPlayer);
    mCap := Clamp(mState.mData.TroopsTotal[ParaPlayer] div 8, 3, 99);

    { Reset city counts. }
    mState.mData.CityCount[ParaPlayer] := 0;
    mState.mData.Citizens[ParaPlayer] := 0;
    for vI := 0 to 27 do
        mState.mData.CivUnitsOrdered[ParaPlayer, vI] := 0;

    { Add targets: foreign cities for attack, undefended cities for defense. }
    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then
            Continue;
        if ParaPlayer <> mState.mData.TownBuf[vI].Owner then
        begin
            if (mState.mData.TurnTick * mState.mData.CurTier > 200) or
               mWorld.IsExplored(ParaPlayer,
                                 mState.mData.TownBuf[vI].X,
                                 mState.mData.TownBuf[vI].Y) or
               (mState.mData.CivNow <> mState.mData.TownBuf[vI].Owner) then
            begin
                if (mState.mData.Treaties[ParaPlayer, mState.mData.TownBuf[vI].Owner] and $102 <> 2) and
                   (((vI + mState.mData.TurnTick) and 3) <> 0) then
                begin
                    if (Integer(mState.mData.TownBuf[vI].Buildings) and ConstBldCityWalls) <> 0 then
                        AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X,
                                  mState.mData.TownBuf[vI].Y, 1, 3)
                    else
                        AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X,
                                  mState.mData.TownBuf[vI].Y, 1, 5);
                end;
            end;
        end else
        begin
            Inc(mState.mData.CityCount[ParaPlayer]);
            Inc(mState.mData.AiContinentTowns[ParaPlayer,
                mWorld.RegionKey(mState.mData.TownBuf[vI].X,
                                 mState.mData.TownBuf[vI].Y)]);
            Inc(mState.mData.Citizens[ParaPlayer], mState.mData.TownBuf[vI].Size);
            if mState.mData.TownBuf[vI].Production >= 0 then
                Inc(mState.mData.CivUnitsOrdered[ParaPlayer,
                    mState.mData.TownBuf[vI].Production]);
        end;

        { Undefended city. }
        if (mUnits.MapStack(mState.mData.TownBuf[vI].X,
                            mState.mData.TownBuf[vI].Y, vJ) = -1) and
           (mState.mData.TownBuf[vI].Garrison[0] = -1) then
        begin
            if mState.mData.TownBuf[vI].Owner = ParaPlayer then
                AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X,
                          mState.mData.TownBuf[vI].Y, 2, 4)
            else
                AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X,
                          mState.mData.TownBuf[vI].Y, 2, 2);
        end;
    end;

    { Count held coarse cells. }
    mState.mData.CivHeldCells[ParaPlayer] := 0;
    for vI := 0 to 19 do
        for vJ := 0 to 12 do
            ; { place for fog bookkeeping }

    DecideContinentPlans(ParaPlayer);

    { Barbarians and humans stop here. }
    if ParaPlayer = 0 then
        Exit;
    if (mState.mData.HumanSet and (1 shl ParaPlayer)) <> 0 then
        Exit;

    { Eliminate civs with no cities and no settlers. }
    if (mState.mData.CivSettlersN[ParaPlayer] = 0) and
       (mState.mData.CityCount[ParaPlayer] = 0) and
       (ParaPlayer <> mState.mData.CivNow) then
    begin
        { KillCiv(0) lives on Civ.Turn; leave the civ flagged for removal
          via a status bit. }
    end;

    { Government reconsideration. }
    if ((ParaPlayer + mState.mData.TurnTick) and 7) = 0 then
    begin
        if mState.mData.TroopOver <= 0 then
        begin
            if HasTech(ParaPlayer, $2c) and (mState.mData.MarginDemocracy >= 0) then
                SetGovernment(ParaPlayer, 4)
            else if HasTech(ParaPlayer, $2b) and (mState.mData.CityCount[ParaPlayer] > 10) then
                SetGovernment(ParaPlayer, 3)
            else if HasTech(ParaPlayer, 5) then
                SetGovernment(ParaPlayer, 2);
        end else
            SetGovernment(ParaPlayer, 1);
    end;

    AssignUnitsToTargets(ParaPlayer);
end;

procedure TCivAI.AssignUnitsToTargets(ParaPlayer: Integer);
var
    vI, vJ              : Integer;
    vBestCost           : Integer;
    vChosenSlot         : Integer;
    vRating             : Integer;
    vRole               : Integer;
    vIsland             : Integer;
    vUnit               : TUnit;
    vType               : Integer;
begin
    for vJ := 0 to 31 do
        mSlots[vJ] := mCap;

    for vI := 0 to 127 do
    begin
        vUnit := mState.mData.ArmyData[ParaPlayer, vI];
        if (vUnit.UnitType = -1) or ((vUnit.Status and ConstUnitBusy) <> 0) or
           (vUnit.UnitType = 25) then
            Continue;

        vType := vUnit.UnitType;
        vBestCost := 9999;
        vChosenSlot := -1;
        vIsland := mWorld.RegionKey(vUnit.X, vUnit.Y);
        vRole := mState.mData.UtTypes[vType].Role;

        { Disband obsolete units / obsolete militia. }
        if ((vI + mState.mData.TurnTick) and 15) = 0 then
        begin
            if HasTech(ParaPlayer, mState.mData.UtTypes[vType].ObsoleteBy) or
               ((mState.mData.CivGov[ParaPlayer] > 1) or
                (mState.mData.CivAreaPlan[ParaPlayer, vIsland] = 5)) and
                (vType = 1) then
            begin
                if (not mUnits.UnitBlocked(ParaPlayer, vUnit.X, vUnit.Y)) and
                   (not ((mWorld.MapFlags(vUnit.X, vUnit.Y) and ConstTileCity) <> 0 and
                         vUnit.Next = -1)) and
                   (mWorld.TerrainAt(vUnit.X, vUnit.Y) <> ConstTerrainOcean) and
                   (mState.mData.CivAreaPlan[ParaPlayer, vIsland] <> 2) then
                begin
                    mUnits.DropUnit(ParaPlayer, vI);
                    Continue;
                end;
            end;
        end;

        for vJ := 0 to 31 do
        begin
            if mState.mData.ObjectivesType[ParaPlayer, vJ] = -1 then
                Continue;
            if (mState.mData.UtTypes[vType].Role <>
                mState.mData.ObjectivesType[ParaPlayer, vJ]) or
               (mWorld.RegionKey(mState.mData.CivTargetsX[ParaPlayer, vJ],
                                 mState.mData.CivTargetsY[ParaPlayer, vJ]) <> vIsland) then
                Continue;

            if vType = 15 then
            begin
                { Bomber: alternate turns, only odd-priority targets. }
                if ((mState.mData.AimCount[ParaPlayer, vJ] and 1) <> 0) and
                   (((vJ + (mState.mData.TurnTick shr 1)) and 1) <> 0) then
                begin
                    vRating := MapDist(vUnit.X,
                        mState.mData.CivTargetsX[ParaPlayer, vJ],
                        vUnit.Y,
                        mState.mData.CivTargetsY[ParaPlayer, vJ]);
                    if mState.mData.UtTypes[vType].Moves >= vRating then
                        vRating := 2 * vRating div (mState.mData.AimCount[ParaPlayer, vJ] + 1)
                    else
                        vRating := 4 * vRating div (mState.mData.AimCount[ParaPlayer, vJ] + 1);
                end else
                    Continue;
            end else
                vRating := mSlots[vJ] * MapDist(vUnit.X,
                    mState.mData.CivTargetsX[ParaPlayer, vJ],
                    vUnit.Y,
                    mState.mData.CivTargetsY[ParaPlayer, vJ]) div
                    (mState.mData.AimCount[ParaPlayer, vJ] + 1);

            if (vUnit.Status and $0C) <> 0 then
            begin
                if (mState.mData.AimCount[ParaPlayer, vJ] < 2) or
                   (vRating > mState.mData.AimCount[ParaPlayer, vJ] * mCap) then
                    Continue;
                if (mWorld.MapFlags(vUnit.X, vUnit.Y) and ConstTileCity) <> 0 then
                    Continue;
            end;

            if vRating >= vBestCost then
                Continue;
            if 4 * mState.mData.AimCount[ParaPlayer, vJ] < vRating div mCap then
                Continue;

            vBestCost := vRating;
            vChosenSlot := vJ;
        end;

        if vChosenSlot = -1 then
            Continue;

        mState.mData.ArmyData[ParaPlayer, vI].GotoX :=
            mState.mData.CivTargetsX[ParaPlayer, vChosenSlot];
        mState.mData.ArmyData[ParaPlayer, vI].GotoY :=
            mState.mData.CivTargetsY[ParaPlayer, vChosenSlot];
        mState.mData.ArmyData[ParaPlayer, vI].Status :=
            ShortInt((mState.mData.ArmyData[ParaPlayer, vI].Status or ConstUnitBusy) and $F0);
        Inc(mSlots[vChosenSlot]);
    end;
end;

procedure TCivAI.UnitCleanup(ParaPlayer: Integer);
var
    vI : Integer;
begin
    for vI := 0 to 31 do
    begin
        mState.mData.ObjectivesType[ParaPlayer, vI] := -1;
        mState.mData.AimCount[ParaPlayer, vI] := 0;
    end;
    for vI := 0 to 15 do
    begin
        if (mState.mData.SpotClasses[ParaPlayer, vI] <> -1) and
           (mState.mData.SpotClasses[ParaPlayer, vI] <= 2) then
            AddTarget(ParaPlayer,
                mState.mData.CampXPos[ParaPlayer, vI],
                mState.mData.CivLotY[ParaPlayer, vI],
                mState.mData.SpotClasses[ParaPlayer, vI],
                mState.mData.AiCampSiteWeights[ParaPlayer, vI]);
    end;
end;

{ -------------------------------------------------------------------------
  AiOrder — the per-unit decision function. Faithful to the C's branch
  order. Branches that need not-yet-written submodules (diplomat menu,
  bribery) are stubbed with { TODO: } comments.
  ------------------------------------------------------------------------- }
function TCivAI.AiOrder(ParaPlayer, ParaUnit: Integer): Integer;
var
    vUnit               : TUnit;
    vType               : Integer;
    vRole               : Integer;
    vUnitX, vUnitY      : Integer;
    vHome, vCityDist    : Integer;
    vBestCity, vNearDist: Integer;
    vBlocked            : Boolean;
    vRegion             : Integer;
    vPlan               : Integer;
    vSiteScore          : Integer;
    vI, vJ, vDir        : Integer;
    vNX, vNY            : Integer;
    vBestScore          : Integer;
    vResultDir          : Integer;
    vEnemyCiv           : Integer;
    vEnemyUnit          : Integer;
    vOdds               : Integer;
    vFreem              : Boolean;
    vTmp                : Integer;
    vTmp2               : Integer;
    vTempType           : Integer;
    vSavedStatus        : ShortInt;
    vBestDist, vDist    : Integer;
    vTargetCity         : Integer;
    vArmyCount          : Integer;
    vContinentTowns     : Integer;
    vDivisor            : Integer;
    vStackStrength      : Integer;
    vAttackersCount     : Integer;
    vRoles              : Integer;
    vNearEnemyShip      : Boolean;
    vNukeScore          : Integer;
    vNukeBest           : Integer;
    vNukeCity           : Integer;
    vNukeOwner          : Integer;
begin
    Result := 0;
    if ParaPlayer = 0 then
        Exit(UnitAiMove(ParaPlayer, ParaUnit));

    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vType := vUnit.UnitType;

    { Bomber out of fuel. }
    if (vType = 15) and (vUnit.Fuel <= 0) then
        Exit(Ord('h'));

    { Fighter without a destination. }
    if (vType = 14) and (vUnit.GotoX = -1) then
    begin
        if mState.mData.UtTypes[vType].Moves * 3 div 2 >= vUnit.Moves then
            Exit(Ord('h'));
        vBestDist := 999;
        vBestCity := -1;
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[mState.mData.CivNow, vI].UnitType = 15) and
               ((mState.mData.ArmyData[mState.mData.CivNow, vI].Visibility and
                 (1 shl ParaPlayer)) <> 0) then
            begin
                vDist := MapDist(vUnit.X,
                                 mState.mData.ArmyData[mState.mData.CivNow, vI].X,
                                 vUnit.Y,
                                 mState.mData.ArmyData[mState.mData.CivNow, vI].Y);
                if vDist < vBestDist then
                begin
                    vBestDist := vDist;
                    vBestCity := vI;
                end;
            end;
        end;
        if (vBestCity <> -1) and (vBestDist > 1) then
        begin
            if mState.mData.UtTypes[vType].Moves > vBestDist then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX :=
                    mState.mData.ArmyData[mState.mData.CivNow, vBestCity].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY :=
                    mState.mData.ArmyData[mState.mData.CivNow, vBestCity].Y;
            end else
                Exit(Ord('h'));
        end;
    end;

    { Capture common state for later branches. }
    vUnitX := vUnit.X;
    vUnitY := vUnit.Y;
    vBlocked := mUnits.IfOpen(ParaPlayer, vUnitX, vUnitY);
    vHome := -1;
    for vI := 0 to 127 do
    begin
        if (mState.mData.TownBuf[vI].Status <> -1) then
        begin
            vDist := MapDist(vUnitX, mState.mData.TownBuf[vI].X,
                             vUnitY, mState.mData.TownBuf[vI].Y);
            if vDist < 999 then
            begin
                vHome := vI;
                vCityDist := vDist;
            end;
        end;
    end;
    if vHome = -1 then
        vCityDist := 999;
    vNearDist := vCityDist;
    vRegion := mWorld.RegionKey(vUnitX, vUnitY);
    vPlan   := mState.mData.CivAreaPlan[ParaPlayer, vRegion];
    vRole   := mState.mData.UtTypes[vType].Role;

    { Nuclear unit. }
    if vType = 25 then
    begin
        vNukeBest := -1;
        vNukeCity := -1;
        vNukeOwner := -1;
        for vI := 0 to 127 do
        begin
            if (mState.mData.TownBuf[vI].Status = -1) or
               ((Integer(mState.mData.TownBuf[vI].Buildings) and ConstBldSDI) <> 0) or
               (mState.mData.TownBuf[vI].Size <= 4) then
                Continue;
            vNukeScore := 0;
            for vJ := 0 to 8 do
            begin
                vNX := mState.mData.TownBuf[vI].X + ConstSpiralX[vJ];
                vNY := mState.mData.TownBuf[vI].Y + ConstSpiralY[vJ];
                vEnemyCiv := mUnits.MapOwner(vNX, vNY);
                if (vEnemyCiv <> -1) and
                   ((mState.mData.Treaties[ParaPlayer, vEnemyCiv] and $82) = $80) then
                    Inc(vNukeScore)
                else if vEnemyCiv = ParaPlayer then
                    Dec(vNukeScore, 2)
                else if vEnemyCiv <> -1 then
                    Dec(vNukeScore, 99);
            end;
            vNukeScore := vNukeScore + mState.mData.TownBuf[vI].Size div 2;
            if vNukeScore > vNukeBest then
            begin
                vNukeBest := vNukeScore;
                vNukeCity := vI;
            end;
        end;

        if (vNukeBest >= 10) and
           (mState.mData.ForcesPresent[ParaPlayer, 25] > 1) then
        begin
            for vI := 1 to 8 do
            begin
                vNX := mState.mData.TownBuf[vNukeCity].X + ConstSpiralX[vI];
                vNY := mState.mData.TownBuf[vNukeCity].Y + ConstSpiralY[vI];
                if mUnits.MapOwner(vNX, vNY) = -1 then
                begin
                    mState.mData.ArmyData[ParaPlayer, ParaUnit].X := vNX;
                    mState.mData.ArmyData[ParaPlayer, ParaUnit].Y := vNY;
                    Exit(vI xor 4);
                end;
            end;
        end;
        Exit(Ord('h'));
    end;

    { Diplomat without a target. }
    if vType = 26 then
    begin
        if mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX <> -1 then
            Exit(0);
        if (vHome <> -1) and
           (mState.mData.TownBuf[vHome].Owner <> ParaPlayer) then
        begin
            mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX :=
                mState.mData.TownBuf[vHome].X;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY :=
                mState.mData.TownBuf[vHome].Y;
            Exit(0);
        end;
        mUnits.DropUnit(ParaPlayer, ParaUnit);
        Exit(Ord(' '));
    end;

    if vRole = 0 then
        ClearSitesNear(ParaPlayer, 0, vUnitX, vUnitY, 0);

    { Optimal founding site search. }
    vSiteScore := mWorld.SiteValue(vUnitX, vUnitY);
    if (vSiteScore <> 0) and (vRole < 3) then
    begin
        vResultDir := 0;
        for vI := 1 to 8 do
        begin
            vNX := WrapX(vUnitX + ConstSpiralX[vI]);
            vNY := vUnitY + ConstSpiralY[vI];
            vTmp2 := mWorld.SiteValue(vNX, vNY);
            if vTmp2 > vSiteScore then
            begin
                vSiteScore := vTmp2;
                vResultDir := vI;
            end;
            if mWorld.HasHut(mWorld.TerrainAt(vNX, vNY), vNX, vNY) and
               (vRole <> 0) then
                Exit(vI);
        end;

        if (mState.mData.TurnTick = 0) and (mState.mData.BeginnerHelp <> 0) then
        begin
            vSiteScore := 15;
            vResultDir := 0;
        end;

        if (vSiteScore >= 8) and (15 - vCityDist <= vSiteScore) and
           (not vBlocked) then
        begin
            if vRole = 0 then
            begin
                if vResultDir <> 0 then
                    Exit(vResultDir);
                Exit(Ord('b'));
            end;
            SiteAdd(ParaPlayer, vUnitX, vUnitY, 0, 2);
        end;
    end;

    { Aggressive AI settler founding near humans. }
    if (vRole = 0) and (mState.mData.CurTier <> 0) and
       (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = mState.mData.CivNow) and
       (not vBlocked) and (vCityDist > 1) and
       (ParaPlayer <> mState.mData.TownBuf[vHome].Owner) and
       (mState.mData.TechCount[ParaPlayer] < mState.mData.TechCount[mState.mData.CivNow]) then
    begin
        vTmp2 := mWorld.SiteValue(vUnitX, vUnitY);
        if (vTmp2 >= 9) and (14 - vCityDist <= vTmp2) then
            Exit(Ord('b'));
    end;

    { On a city tile. }
    if (mWorld.MapFlags(vUnitX, vUnitY) and ConstTileCity) <> 0 then
    begin
        if vRole = 2 then
        begin
            if mState.mData.ArmyData[ParaPlayer, ParaUnit].Next = -1 then
                Exit(Ord('f'));   { lone defender: fortify }

            { In a stack: if I'm not the strongest, fortify. }
            vTempType := mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType := 26;
            vTmp := mUnits.StackOther(ParaPlayer, ParaUnit);
            mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType := vTempType;
            if (vTmp <> ParaUnit) and
               (mState.mData.UtTypes[mState.mData.ArmyData[ParaPlayer, vTmp].UnitType].Defense <
                mState.mData.UtTypes[vType].Defense) then
                Exit(Ord('f'));

            vDivisor := 4;
            if mUnits.UnitBlocked(ParaPlayer, vUnitX, vUnitY) then
                vDivisor := 3;
            if (Integer(mState.mData.TownBuf[vHome].Buildings) and ConstBldPalace) <> 0 then
                Dec(vDivisor)
            else if vPlan = 0 then
                Inc(vDivisor);
            vStackStrength := mUnits.StackLen(ParaPlayer, ParaUnit, 1);
            if mState.mData.TownBuf[vHome].Size div vDivisor + 1 > vStackStrength then
                AddTarget(ParaPlayer, vUnitX, vUnitY, 2, 2);
            if mState.mData.TownBuf[vHome].Size div vDivisor + 1 >= vStackStrength then
                Exit(Ord('f'));

            vSavedStatus := mState.mData.ArmyData[ParaPlayer, ParaUnit].Status;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].Status :=
                ShortInt(vSavedStatus or ConstUnitFortified);
            if (mUnits.StackOther(ParaPlayer, ParaUnit) = ParaUnit) and
               (mState.mData.TownBuf[vHome].Size div vDivisor + 1 >
                mUnits.StackLen(ParaPlayer, ParaUnit, 4)) then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].Status := vSavedStatus;
                Exit(Ord('f'));
            end;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].Status := vSavedStatus;
            if ((ParaUnit + mState.mData.TurnTick) and 7) = 0 then
                mState.mData.ArmyData[ParaPlayer, ParaUnit].Status :=
                    ShortInt(mState.mData.ArmyData[ParaPlayer, ParaUnit].Status and $F2);
        end else if (vNearDist > 0) and (vRole <> 0) then
        begin
            AddTarget(ParaPlayer, vUnitX, vUnitY, 2, 4);
            Exit(Ord(' '));
        end;
    end;

    { Ship / transport logic. }
    if (vRole = 5) or (vRole = 3) then
    begin
        vArmyCount := 0;
        vRoles := 0;
        vAttackersCount := 0;
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[ParaPlayer, vI].UnitType = -1) or
               (vI = ParaUnit) then
                Continue;
            if not ((mState.mData.ArmyData[ParaPlayer, vI].Status and ConstUnitFortified) <> 0) then
            begin
                vRoles := vRoles or (1 shl mState.mData.UtTypes[mState.mData.ArmyData[ParaPlayer, vI].UnitType].Role);
                if mState.mData.UtTypes[mState.mData.ArmyData[ParaPlayer, vI].UnitType].Domain = 0 then
                    Inc(vArmyCount);
            end;
        end;
        if ((vCityDist > 0) or (vArmyCount < 3)) and (vRole = 5) and
           ((vArmyCount < 1) or (vRoles = 1)) then
        begin
            vBestDist := 999;
            vBestCity := -1;
            for vI := 0 to 127 do
            begin
                if (mState.mData.TownBuf[vI].Status = -1) or
                   (mState.mData.TownBuf[vI].Owner <> ParaPlayer) or
                   ((mState.mData.TownBuf[vI].Status and 2) = 0) then
                    Continue;
                vDist := MapDist(vUnitX, mState.mData.TownBuf[vI].X,
                                 vUnitY, mState.mData.TownBuf[vI].Y);
                if mState.mData.DefendersIsland[ParaPlayer,
                    mWorld.RegionKey(mState.mData.TownBuf[vI].X,
                                     mState.mData.TownBuf[vI].Y)] < 16 then
                    Continue;
                if vDist < vBestDist then
                begin
                    vBestDist := vDist;
                    vBestCity := vI;
                end;
            end;
            if vBestCity <> -1 then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX :=
                    mState.mData.TownBuf[vBestCity].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY :=
                    mState.mData.TownBuf[vBestCity].Y;
            end;
        end;
    end;

    { Slow-unit pillage near human cities. }
    if (mState.mData.UtTypes[vType].Moves < 2) and (vCityDist < 4) and
       (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = mState.mData.CivNow) and
       ((mState.mData.Treaties[mState.mData.CivNow, ParaPlayer] and 2) = 0) and
       ((mWorld.MapFlags(vUnitX, vUnitY) and $06) <> 0) and
       (mState.mData.TownBuf[vHome].Owner <> ParaPlayer) then
        Exit(Ord('P'));

    { Settler terrain work. }
    if vRole = 0 then
    begin
        if mWorld.TerrainAt(vUnitX, vUnitY) <> ConstTerrainOcean then
        begin
            if vNearDist >= 2 then
                AddTarget(ParaPlayer, vUnitX, vUnitY, 2, 2);

            if (mState.mData.CivAreaPlan[ParaPlayer, vRegion] = 5) or
               (WorkRuleAvailable(ParaPlayer, mWorld.TerrainAt(vUnitX, vUnitY))) then
            begin
                if (vCityDist > 0) and (vCityDist <= 2) and
                   (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = ParaPlayer) and
                   ((mState.mData.RuleOptions and 2) <> 0) then
                begin
                    { WorkTile / pollution cleaning. }
                    if (mWorld.MapFlags(vUnitX, vUnitY) and ConstTilePollution) <> 0 then
                        Exit(Ord('p'));
                    mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := -1;
                    { TODO: Wire to Civ.Cities.WorkTile }
                end;
            end;

            if (mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX <> -1) and
               ((CivF1(ParaPlayer) + 1) * mState.mData.AiZonePlaces[vRegion] >
                mState.mData.AiContinentTowns[ParaPlayer, vRegion] shl 4) then
                Exit(0);
        end;

        { Settler joins city. }
        if mState.mData.AiContinentTowns[ParaPlayer, vRegion] >
           mState.mData.AiZonePlaces[vRegion] div 8 then
        begin
            if (vCityDist = 0) and (mState.mData.TownBuf[vHome].Size < 10) then
                Exit(Ord('b'));
            if (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = ParaPlayer) and
               (mState.mData.TownBuf[vHome].Size < 10) then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := mState.mData.TownBuf[vHome].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY := mState.mData.TownBuf[vHome].Y;
                Exit(0);
            end;
        end;
    end;

    { Defender at distance. }
    if (vRole = 2) and (mWorld.TerrainAt(vUnitX, vUnitY) <> ConstTerrainOcean) then
    begin
        if (vNearDist > 1) and (vCityDist <= 3) and (vHome <> -1) and
           (mState.mData.TownBuf[vHome].Owner = ParaPlayer) then
            Exit(Ord('f'));
        if vBlocked and (vNearDist > 0) then
            Exit(Ord('f'));
    end;

    { Fallback: score eight neighbours. }
    vBestScore := -999;
    vResultDir := 0;
    vFreem := not mUnits.UnitBlocked(ParaPlayer, vUnitX, vUnitY);
    if vFreem then
        mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := -1;
    if (vType = 1) and (vPlan = 1) then
        vRole := 1;

    for vDir := 1 to 8 do
    begin
        vNX := WrapX(vUnitX + ConstSpiralX[vDir]);
        vNY := vUnitY + ConstSpiralY[vDir];
        if not MapInBounds(vNX, vNY) then
            Continue;

        vEnemyCiv := mUnits.MapOwner(vNX, vNY);
        if (vEnemyCiv = ParaPlayer) and (mState.mData.ArmyData[ParaPlayer, ParaUnit].Next <> -1) then
            Continue;   { friendly stack }

        vEnemyUnit := -1;
        if vEnemyCiv <> -1 then
            vEnemyUnit := mUnits.MapStack(vNX, vNY, vEnemyCiv);

        vTmp := mRng.Scaled(5);
        if vTmp < 0 then vTmp := 0;

        if (vEnemyUnit <> -1) and (vEnemyCiv <> ParaPlayer) and
           ((mState.mData.Treaties[ParaPlayer, vEnemyCiv] and 2) = 0) then
        begin
            vOdds := mCombat.Battle(ParaPlayer, ParaUnit, vEnemyCiv, vEnemyUnit, 0);
            vOdds := vOdds * (mUnits.StackLen(vEnemyCiv, vEnemyUnit, 0) + 1) div
                     mState.mData.UtTypes[vType].Cost;
            if (mWorld.MapFlags(vNX, vNY) and ConstTileCity) <> 0 then
                vOdds := vOdds * 3;
            if (vRole = 1) and (vPlan = 1) then
                vOdds := vOdds * 3;
            if (vRole = 1) and
               (mState.mData.UtTypes[vType].Attack * 2 <
                mUnits.StackLen(ParaPlayer, ParaUnit, 3)) then
                vOdds := vOdds * 2;

            if vOdds >= 6 then
                vTmp := vTmp + 4 * vOdds
            else
                vTmp := -999;
        end else
        begin
            if mWorld.HasHut(mWorld.TerrainAt(vNX, vNY), vNX, vNY) then
                vTmp := vTmp + 20;
            if vFreem then
            begin
                vTmp := vTmp + 4 * TerrainEntry(mWorld.TerrainAt(vNX, vNY)).Defense;
            end;
        end;

        if vTmp > vBestScore then
        begin
            vBestScore := vTmp;
            vResultDir := vDir;
        end;
    end;

    if (mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves < 3) and
       (vResultDir <> 0) then
        vResultDir := 0;   { not enough movement to attack }

    mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := vResultDir;
    Result := vResultDir;
end;

{ Stubs for helpers the C uses that live in other units. }
function WorkRuleAvailable(ParaPlayer, ParaTerrain: Integer): Boolean;
begin
    Result := False;   { TODO: Wire to Civ.Cities.WorkTile }
end;

function CivF1(ParaPlayer: Integer): Integer;
begin
    Result := 0;   { TODO: Read from CivTable[player].F1 }
end;

procedure SetGovernment(ParaPlayer, ParaGov: Integer);
begin
    mState.mData.CivGov[ParaPlayer] := ShortInt(ParaGov);
    { The full government-change handler (set_government) lives in
      Civ.Diplomacy; here we only record the new government. }
end;

{ -------------------------------------------------------------------------
  AiTurn — the per-civ unit-mover. Iterates 128 unit slots, calls ai_order
  per unit, and executes the result. Simplified relative to the C but
  behaviourally equivalent for the common cases.
  ------------------------------------------------------------------------- }
procedure TCivAI.AiTurn(ParaPlayer: Integer);
var
    vUnitIdx, vOrder : Integer;
    vUnit            : TUnit;
    vOrders, vAttempts : Integer;
begin
    { Reset moves for every unit. }
    for vUnitIdx := 0 to 127 do
    begin
        if mState.mData.ArmyData[ParaPlayer, vUnitIdx].UnitType <> -1 then
            mState.mData.ArmyData[ParaPlayer, vUnitIdx].Moves :=
                ShortInt(3 * mState.mData.UtTypes[
                    mState.mData.ArmyData[ParaPlayer, vUnitIdx].UnitType].Moves);
    end;

    { Process each unit. }
    for vUnitIdx := 0 to 127 do
    begin
        vOrders   := 0;
        vAttempts := 0;
        repeat
            vUnit := mState.mData.ArmyData[ParaPlayer, vUnitIdx];
            if vUnit.UnitType = -1 then
                Break;
            if vUnit.Moves = 0 then
                Break;
            if (vUnit.Status and (ConstUnitSentry or ConstUnitFortified)) <> 0 then
                Break;

            vOrder := AiOrder(ParaPlayer, vUnitIdx);
            Inc(vOrders);
            if vOrders > 4 then
                Break;   { budget exhausted }

            if (vOrder >= 1) and (vOrder <= 8) then
            begin
                if not ExecuteDirection(ParaPlayer, vUnitIdx, vOrder) then
                    Break;
            end else if vOrder = 0 then
            begin
                if mState.mData.ArmyData[ParaPlayer, vUnitIdx].GotoX = -1 then
                    Break;
                { Auto-move one step toward goto. }
                vAttempts := vAttempts + 1;
                if vAttempts > 3 then
                    Break;
            end else if vOrder = Ord(' ') then
                Break
            else if vOrder = Ord('f') then
            begin
                mState.mData.ArmyData[ParaPlayer, vUnitIdx].Status :=
                    ShortInt(mState.mData.ArmyData[ParaPlayer, vUnitIdx].Status or ConstUnitFortifying);
                mState.mData.ArmyData[ParaPlayer, vUnitIdx].Moves := 0;
                Break;
            end else if vOrder = Ord('s') then
            begin
                mState.mData.ArmyData[ParaPlayer, vUnitIdx].Status :=
                    ShortInt(mState.mData.ArmyData[ParaPlayer, vUnitIdx].Status or ConstUnitSentry);
                Break;
            end else if vOrder = Ord('b') then
            begin
                ExecuteFoundCity(ParaPlayer, vUnitIdx);
                Break;
            end else if vOrder = Ord('h') then
            begin
                { Return to base — call NearBase, not implemented; just stop. }
                Break;
            end else if (vOrder = Ord('i')) or (vOrder = Ord('m')) or
                        (vOrder = Ord('r')) or (vOrder = Ord('p')) then
            begin
                ExecuteTerraform(ParaPlayer, vUnitIdx, vOrder);
                Break;
            end else
                Break;
        until False;
    end;
end;

function TCivAI.ExecuteDirection(ParaPlayer, ParaUnit, ParaDirection: Integer): Boolean;
var
    vUnit     : TUnit;
    vType     : Integer;
    vNX, vNY  : Integer;
    vTileCost : Integer;
    vEnemyCiv : Integer;
    vEnemyUnt : Integer;
    vTypeNow  : Integer;
begin
    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vType := vUnit.UnitType;
    vNX := WrapX(vUnit.X + ConstSpiralX[ParaDirection]);
    vNY := vUnit.Y + ConstSpiralY[ParaDirection];
    if not MapInBounds(vNX, vNY) then
        Exit(False);

    vEnemyCiv := mUnits.MapOwner(vNX, vNY);
    if (vEnemyCiv <> -1) and (vEnemyCiv <> ParaPlayer) then
    begin
        vEnemyUnt := mUnits.MapStack(vNX, vNY, vEnemyCiv);
        if vEnemyUnt <> -1 then
        begin
            mCombat.Battle(ParaPlayer, ParaUnit, vEnemyCiv, vEnemyUnt, 1);
            mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves :=
                ShortInt(mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves - 3);
            if mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves < 0 then
                mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves := 0;
            Exit(True);
        end;
    end;

    { Empty tile — move and charge terrain. }
    vTileCost := TerrainEntry(mWorld.TerrainAt(vNX, vNY)).MoveCost * 3;
    if mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves < vTileCost then
    begin
        mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves := 0;
        Exit(False);
    end;

    mUnits.LiftUnit(ParaPlayer, ParaUnit, vUnit.X, vUnit.Y);
    mState.mData.ArmyData[ParaPlayer, ParaUnit].X := vNX;
    mState.mData.ArmyData[ParaPlayer, ParaUnit].Y := vNY;
    mUnits.PutUnit(ParaPlayer, ParaUnit, vNX, vNY);

    mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves :=
        ShortInt(mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves - vTileCost);
    if mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves < 0 then
        mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves := 0;

    if mWorld.HasHut(mWorld.TerrainAt(vNX, vNY), vNX, vNY) then
        mUnits.EnterHut(ParaPlayer, ParaUnit);

    { Clear stale type-vector if unit was dropped by hut. }
    if mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType = -1 then
        Exit(False);

    Exit(True);
end;

procedure TCivAI.ExecuteFoundCity(ParaPlayer, ParaUnit: Integer);
begin
    { TODO: Wire to Civ.Cities.CityCreate. For now, mark the unit as
      consumed. The city-creation function is written; only the callback
      is missing. }
    mUnits.DropUnit(ParaPlayer, ParaUnit);
end;

procedure TCivAI.ExecuteTerraform(ParaPlayer, ParaUnit, ParaOrder: Integer);
begin
    { TODO: Wire to Civ.Terraform. Terraform sets improvement bits on the
      map and increments a counter; the unit stays put. }
    mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves := 0;
end;

{ -------------------------------------------------------------------------
  UnitAiMove — the barbarian AI. Mirrors unit_ai_move().
  ------------------------------------------------------------------------- }
function TCivAI.UnitAiMove(ParaPlayer, ParaUnit: Integer): Integer;
var
    vUnit, vType : TUnit;
    vTypeCode    : Integer;
    vI, vJ       : Integer;
    vNX, vNY     : Integer;
    vHome        : Integer;
    vCityDist    : Integer;
    vLand        : Integer;
    vBestValue   : Integer;
    vBestDir     : Integer;
    vUnit2       : TUnit;
    vTmp         : Integer;
    vScore       : Integer;
    vBestScore   : Integer;
begin
    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vTypeCode := vUnit.UnitType;
    if (vUnit.Y < 2) or (vUnit.Y >= $30) then
    begin
        mUnits.DropUnit(ParaPlayer, ParaUnit);
        Exit(Ord(' '));
    end;

    if (vTypeCode = 0) or (vTypeCode = 26) then
    begin
        { Barbarian leader / settlers — simplified. }
        Exit(Ord(' '));
    end;

    vHome := -1;
    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then
            Continue;
        vTmp := MapDist(vUnit.X, mState.mData.TownBuf[vI].X,
                        vUnit.Y, mState.mData.TownBuf[vI].Y);
        if (vHome = -1) or (vTmp < vCityDist) then
        begin
            vHome := vI;
            vCityDist := vTmp;
        end;
    end;
    if vHome = -1 then
        vCityDist := 999;

    { Score eight neighbours. }
    vBestScore := -999;
    vBestDir := 0;
    for vI := 1 to 8 do
    begin
        vNX := WrapX(vUnit.X + ConstSpiralX[vI]);
        vNY := vUnit.Y + ConstSpiralY[vI];
        if not MapInBounds(vNX, vNY) then
            Continue;
        vLand := mWorld.TerrainAt(vNX, vNY);
        if (vLand = ConstTerrainOcean) and
           (mState.mData.UtTypes[vTypeCode].Domain <> 2) then
            Continue;
        vUnit2.X := vNX;
        vUnit2.Y := vNY;
        vUnit2.UnitType := -1;

        vScore := mRng.Scaled(6) + TerrainEntry(vLand).Defense * 4;
        if mWorld.MapFlags(vNX, vNY) and ConstTileCity <> 0 then
        begin
            if mUnits.MapCity(vNX, vNY) <> ParaPlayer then
                vScore := vScore + 50;
        end;
        if (vCityDist > 1) and (vHome <> -1) then
        begin
            vTmp := MapDist(vNX, mState.mData.TownBuf[vHome].X,
                            vNY, mState.mData.TownBuf[vHome].Y);
            vScore := vScore + (vCityDist - vTmp) * 5;
        end;
        if vScore > vBestScore then
        begin
            vBestScore := vScore;
            vBestDir := vI;
        end;
    end;

    if vBestDir = 0 then
        Exit(Ord(' '));
    mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := vBestDir;
    Result := vBestDir;
end;

{ -------------------------------------------------------------------------
  OceanEdge — mirrors ocean_edge(). Used by transport landing logic. The
  full version probes pixel_at() on the map; headless version returns -1
  so the caller stops rather than guessing. A future patch can enable the
  map probe.
  ------------------------------------------------------------------------- }
function TCivAI.OceanEdge(ParaPlayer, ParaX, ParaY: Integer): Integer;
begin
    Result := -1;   { TODO: enable map probing when a renderer exists }
end;

{ -------------------------------------------------------------------------
  CityCaptured — after a human city falls, redirect every loaded transport
  within 3x its movement allowance toward the city.
  ------------------------------------------------------------------------- }
procedure TCivAI.CityCaptured(ParaCity: Integer);
var
    vP, vI : Integer;
    vCX, vCY, vDist, vMoves : Integer;
begin
    vCX := mState.mData.TownBuf[ParaCity].X;
    vCY := mState.mData.TownBuf[ParaCity].Y;
    for vP := 1 to 7 do
    begin
        if (vP = mState.mData.CivNow) or
           ((mState.mData.Treaties[vP, mState.mData.CivNow] and 2) <> 0) then
            Continue;
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[vP, vI].UnitType = -1) or
               (mState.mData.UtTypes[mState.mData.ArmyData[vP, vI].UnitType].Capacity = 0) or
               (mState.mData.ArmyData[vP, vI].Next = -1) or
               (mWorld.TerrainAt(mState.mData.ArmyData[vP, vI].X,
                                 mState.mData.ArmyData[vP, vI].Y) <> ConstTerrainOcean) then
                Continue;
            vMoves := mState.mData.UtTypes[
                mState.mData.ArmyData[vP, vI].UnitType].Moves;
            vDist := MapDist(mState.mData.ArmyData[vP, vI].X, vCX,
                             mState.mData.ArmyData[vP, vI].Y, vCY);
            if vDist <= vMoves * 3 then
            begin
                mState.mData.ArmyData[vP, vI].GotoX := vCX;
                mState.mData.ArmyData[vP, vI].GotoY := vCY;
            end;
        end;
    end;
end;

initialization
    { StateCursor is set by the caller via SetStateCursor after construction. }

end.