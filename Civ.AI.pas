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
    Civ.Units,
    Civ.Tables;

type
    { Injected dependencies to avoid circular references and allow testing. }
    TCityCreateMethod  = function(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer of object;
    TFindSlotMethod    = function(ParaCiv, ParaCity: Integer): Integer of object;
    TAdvanceValueMethod = function(ParaCiv, ParaAdvance: Integer): Integer of object;
    TSetGovernmentMethod = procedure(ParaCiv, ParaGov: Integer) of object;

    TCivAI = class
    private
        mWorld  : TCivWorld;
        mState  : TCivilizationGameState;
        mUnits  : TCivUnitManager;
        mCombat : TCivCombat;
        mRng    : TCivRandom;

        mNearHuman   : Integer;
        mInAtWar     : Boolean;

        mCap         : Integer;
        mSlots       : array[0..31] of Integer;

        { Injected hooks. }
        mCityCreate    : TCityCreateMethod;
        mFindSlot      : TFindSlotMethod;
        mAdvanceValue  : TAdvanceValueMethod;
        mSetGovernment : TSetGovernmentMethod;

        procedure BuildContinentTables(ParaPlayer: Integer);
        procedure DecideContinentPlans(ParaPlayer: Integer);
        procedure AssignUnitsToTargets(ParaPlayer: Integer);

        function  ExecuteDirection(ParaPlayer, ParaUnit, ParaDirection: Integer): Boolean;
        procedure ExecuteFoundCity(ParaPlayer, ParaUnit: Integer);
        procedure ExecuteTerraform(ParaPlayer, ParaUnit, ParaOrder: Integer);

        function  HasTech(ParaCiv, ParaAdv: Integer): Boolean;
        function  IsWonderActive(ParaCiv, ParaWonder: Integer): Boolean;
    public
        constructor Create(ParaWorld: TCivWorld; ParaUnits: TCivUnitManager;
                           ParaCombat: TCivCombat; ParaRng: TCivRandom);
        destructor Destroy; override;

        procedure SetHooks(ParaCityCreate: TCityCreateMethod;
                           ParaFindSlot: TFindSlotMethod;
                           ParaAdvanceValue: TAdvanceValueMethod;
                           ParaSetGovernment: TSetGovernmentMethod);

        procedure UnitPhase(ParaPlayer: Integer);
        procedure UnitCleanup(ParaPlayer: Integer);
        function  AiOrder(ParaPlayer, ParaUnit: Integer): Integer;
        procedure AiTurn(ParaPlayer: Integer);
        function  UnitAiMove(ParaPlayer, ParaUnit: Integer): Integer;

        procedure AddTarget(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
        procedure SiteAdd(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
        procedure SiteClear(ParaPlayer: Integer);
        procedure ClearSitesNear(ParaPlayer, ParaKind, ParaX, ParaY, ParaRange: Integer);
        procedure Retarget(ParaOwner, ParaRegion: Integer);
        procedure CityRetarget(ParaCity: Integer);
        function  OceanEdge(ParaPlayer, ParaX, ParaY: Integer): Integer;
        procedure CityCaptured(ParaCity: Integer);

        property NearHuman: Integer read mNearHuman;
        property InAtWar:   Boolean read mInAtWar;
    end;

implementation

uses
    Civ.Pathfinding;

constructor TCivAI.Create(ParaWorld: TCivWorld; ParaUnits: TCivUnitManager;
    ParaCombat: TCivCombat; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mUnits := ParaUnits;
    mCombat := ParaCombat;
    mRng := ParaRng;
end;

destructor TCivAI.Destroy;
begin
    inherited;
end;

procedure TCivAI.SetHooks(ParaCityCreate: TCityCreateMethod;
    ParaFindSlot: TFindSlotMethod;
    ParaAdvanceValue: TAdvanceValueMethod;
    ParaSetGovernment: TSetGovernmentMethod);
begin
    mCityCreate := ParaCityCreate;
    mFindSlot := ParaFindSlot;
    mAdvanceValue := ParaAdvanceValue;
    mSetGovernment := ParaSetGovernment;
end;

function TCivAI.HasTech(ParaCiv, ParaAdv: Integer): Boolean;
var
    vWord : Integer;
begin
    if (ParaAdv < 0) or (ParaAdv >= 72) or (ParaCiv < 0) or (ParaCiv > 7) then Exit(False);
    vWord := ParaAdv div 16;
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and
               SmallInt(1 shl (ParaAdv mod 16))) <> 0;
end;

function TCivAI.IsWonderActive(ParaCiv, ParaWonder: Integer): Boolean;
var
    vI : Integer;
begin
    for vI := 1 to 7 do
        if HasTech(vI, ParaWonder) then Exit(False);
    if mState.mData.MarvelSite[ParaWonder] = -1 then Exit(False);
    Result := mState.mData.TownBuf[mState.mData.MarvelSite[ParaWonder]].Owner = ParaCiv;
end;

procedure TCivAI.BuildContinentTables(ParaPlayer: Integer);
var
    vI, vType, vRegion : Integer;
    vUnit : TUnit;
begin
    for vI := 0 to 15 do
    begin
        mState.mData.DefendersIsland[ParaPlayer, vI]  := 0;
        mState.mData.CivContAttackers[ParaPlayer, vI] := 0;
        mState.mData.AiContinentTowns[ParaPlayer, vI] := 0;
    end;
    mState.mData.TroopsTotal[ParaPlayer]  := 0;
    mState.mData.CivSettlersN[ParaPlayer] := 0;
    mState.mData.MilitaryTable[ParaPlayer] := 0;

    for vI := 0 to 127 do
    begin
        vUnit := mState.mData.ArmyData[ParaPlayer, vI];
        if (vUnit.UnitType = -1) or (vUnit.UnitType = 25) then Continue;
        if vUnit.UnitType = 0 then Inc(mState.mData.CivSettlersN[ParaPlayer])
        else Inc(mState.mData.TroopsTotal[ParaPlayer]);
        vType := vUnit.UnitType;
        mState.mData.MilitaryTable[ParaPlayer] := mState.mData.MilitaryTable[ParaPlayer] +
            mState.mData.UtTypes[vType].Attack + mState.mData.UtTypes[vType].Defense;
        mState.mData.ArmyData[ParaPlayer, vI].Status :=
            ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status and not ConstUnitBusy);
        if mUnits.UnitBlocked(ParaPlayer, vUnit.X, vUnit.Y) then
            mState.mData.ArmyData[ParaPlayer, vI].Status :=
                ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status or ConstUnitBusy);
        if not mWorld.IsOcean(vUnit.X, vUnit.Y) then
        begin
            vRegion := mWorld.RegionKey(vUnit.X, vUnit.Y);
            mState.mData.DefendersIsland[ParaPlayer, vRegion] :=
                mState.mData.DefendersIsland[ParaPlayer, vRegion] + mState.mData.UtTypes[vType].Defense;
            mState.mData.CivContAttackers[ParaPlayer, vRegion] :=
                mState.mData.CivContAttackers[ParaPlayer, vRegion] + mState.mData.UtTypes[vType].Attack;
        end else if mState.mData.UtTypes[vType].Domain = 0 then
            mState.mData.ArmyData[ParaPlayer, vI].Status :=
                ShortInt(mState.mData.ArmyData[ParaPlayer, vI].Status or ConstUnitBusy);
    end;
end;

procedure TCivAI.DecideContinentPlans(ParaPlayer: Integer);
var
    vI, vJ, vStrong, vDanger, vTotalAttackers, vFriends, vFlags,
    vPrevPlan, vCurrentPlan : Integer;
begin
    mInAtWar := False;
    for vJ := 1 to 7 do
        if (mState.mData.Treaties[ParaPlayer, vJ] and 3) = 1 then
            mInAtWar := True;

    for vJ := 1 to 14 do
    begin
        vStrong := 0; vDanger := 0; vTotalAttackers := 0; vFriends := 0; vFlags := 0;
        vPrevPlan := mState.mData.CivAreaPlan[ParaPlayer, vJ];

        for vI := 1 to 7 do
        begin
            if (mState.mData.DefendersIsland[vI, vJ] <> 0) and
               ((mState.mData.CivContAttackers[ParaPlayer, vJ] div 4 < mState.mData.CivContAttackers[vI, vJ]) or
                (mState.mData.AiContinentTowns[vI, vJ] <> 0)) and
               (((mState.mData.Treaties[ParaPlayer, vI] and 3) = 1) or
                ((mState.mData.Treaties[ParaPlayer, vI] and $100) <> 0)) then
            begin
                if (mState.mData.DefendersIsland[vI, vJ] < mState.mData.CivContAttackers[ParaPlayer, vJ]) or
                   (mState.mData.CivContAttackers[vI, vJ] < mState.mData.DefendersIsland[ParaPlayer, vJ]) or
                   (mState.mData.AiContinentTowns[ParaPlayer, vJ] = 0) then
                    Inc(vStrong)
                else
                    Inc(vDanger);
            end;
            if (mState.mData.DefendersIsland[vI, vJ] <> 0) and
               (mState.mData.CivNow = vI) and
               ((mState.mData.Treaties[ParaPlayer, vI] and 2) <> 0) and
               (mState.mData.CivContAttackers[ParaPlayer, vJ] div 2 +
                mState.mData.DefendersIsland[ParaPlayer, vJ] < mState.mData.CivContAttackers[vI, vJ]) then
                Inc(vDanger);
            vTotalAttackers := vTotalAttackers + mState.mData.DefendersIsland[vI, vJ];
            vFriends := vFriends + mState.mData.AiContinentTowns[vI, vJ];
            if mState.mData.DefendersIsland[vI, vJ] <> 0 then
                if (mState.mData.Treaties[ParaPlayer, vI] and 2) <> 0 then
                    vFlags := vFlags or 1
                else
                    vFlags := vFlags or 2;
        end;

        if mState.mData.AiContinentTowns[0, vJ] <> 0 then Inc(vStrong);

        vCurrentPlan := 0;
        if ((mState.mData.DefendersIsland[ParaPlayer, vJ] + vTotalAttackers) * 2 > mState.mData.ContinentSpan[0, vJ]) or
           ((mState.mData.AiContinentTowns[ParaPlayer, vJ] + vFriends) * 6 + 2 > mState.mData.AiZonePlaces[vJ]) then
            if HasTech(ParaPlayer, 7) then vCurrentPlan := 5;
        if vStrong > 0 then vCurrentPlan := 1;
        if vDanger > 0 then vCurrentPlan := 2;
        if (mState.mData.DefendersIsland[ParaPlayer, vJ] = 0) and
           (mState.mData.AiContinentTowns[ParaPlayer, vJ] = 0) and
           (vFlags <> 1) then vCurrentPlan := 1;

        mState.mData.CivAreaPlan[ParaPlayer, vJ] := vCurrentPlan;
        if (vCurrentPlan <> vPrevPlan) and
           ((mState.mData.HumanSet and (1 shl ParaPlayer)) = 0) then
            Retarget(ParaPlayer, vJ);
        if (mState.mData.DefendersIsland[ParaPlayer, vJ] <> 0) and
           (mState.mData.AiContinentTowns[mState.mData.CivNow, vJ] > 1) then
            mNearHuman := mNearHuman or (1 shl ParaPlayer);
    end;
end;

procedure TCivAI.UnitPhase(ParaPlayer: Integer);
var
    vI, vJ, vBestCost, vChosenSlot, vRating, vIsland : Integer;
begin
    BuildContinentTables(ParaPlayer);
    mCap := Clamp(mState.mData.TroopsTotal[ParaPlayer] div 8, 3, 99);

    mState.mData.CityCount[ParaPlayer] := 0;
    mState.mData.Citizens[ParaPlayer]  := 0;
    for vI := 0 to 27 do
        mState.mData.CivUnitsOrdered[ParaPlayer, vI] := 0;

    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then Continue;
        if ParaPlayer <> mState.mData.TownBuf[vI].Owner then
        begin
            if (mState.mData.TurnTick * mState.mData.CurTier > 200) or
               mWorld.IsExplored(ParaPlayer, mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y) or
               (mState.mData.CivNow <> mState.mData.TownBuf[vI].Owner) then
            begin
                if (mState.mData.Treaties[ParaPlayer, mState.mData.TownBuf[vI].Owner] and $102 <> 2) and
                   (((vI + mState.mData.TurnTick) and 3) <> 0) then
                    if (Integer(mState.mData.TownBuf[vI].Buildings) and ConstBldCityWalls) <> 0 then
                        AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y, 1, 3)
                    else
                        AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y, 1, 5);
            end;
        end else
        begin
            Inc(mState.mData.CityCount[ParaPlayer]);
            Inc(mState.mData.AiContinentTowns[ParaPlayer, mWorld.RegionKey(mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y)]);
            Inc(mState.mData.Citizens[ParaPlayer], mState.mData.TownBuf[vI].Size);
            if mState.mData.TownBuf[vI].Production >= 0 then
                Inc(mState.mData.CivUnitsOrdered[ParaPlayer, mState.mData.TownBuf[vI].Production]);
        end;
        if (mUnits.MapStack(mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y, vJ) = -1) and
           (mState.mData.TownBuf[vI].Garrison[0] = -1) then
        begin
            if mState.mData.TownBuf[vI].Owner = ParaPlayer then
                AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y, 2, 4)
            else
                AddTarget(ParaPlayer, mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y, 2, 2);
        end;
    end;

    DecideContinentPlans(ParaPlayer);

    if (ParaPlayer = 0) or
       ((mState.mData.HumanSet and (1 shl ParaPlayer)) <> 0) then
        Exit;

    if ((ParaPlayer + mState.mData.TurnTick) and 7) = 0 then
    begin
        if mState.mData.TroopOver <= 0 then
        begin
            if HasTech(ParaPlayer, $2c) and (mState.mData.MarginDemocracy >= 0) then
            begin if Assigned(mSetGovernment) then mSetGovernment(ParaPlayer, 4); end
            else if HasTech(ParaPlayer, $2b) and (mState.mData.CityCount[ParaPlayer] > 10) then
            begin if Assigned(mSetGovernment) then mSetGovernment(ParaPlayer, 3); end
            else if HasTech(ParaPlayer, 5) then
            begin if Assigned(mSetGovernment) then mSetGovernment(ParaPlayer, 2); end;
        end else
            if Assigned(mSetGovernment) then mSetGovernment(ParaPlayer, 1);
    end;

    AssignUnitsToTargets(ParaPlayer);
end;

procedure TCivAI.AssignUnitsToTargets(ParaPlayer: Integer);
var
    vI, vJ, vBestCost, vChosenSlot, vRating, vIsland : Integer;
    vUnit : TUnit;
    vType : Integer;
begin
    for vJ := 0 to 31 do mSlots[vJ] := mCap;

    for vI := 0 to 127 do
    begin
        vUnit := mState.mData.ArmyData[ParaPlayer, vI];
        if (vUnit.UnitType = -1) or ((vUnit.Status and ConstUnitBusy) <> 0) or (vUnit.UnitType = 25) then Continue;

        vType := vUnit.UnitType;
        vBestCost := 9999; vChosenSlot := -1;
        vIsland := mWorld.RegionKey(vUnit.X, vUnit.Y);

        if ((vI + mState.mData.TurnTick) and 15) = 0 then
            if HasTech(ParaPlayer, mState.mData.UtTypes[vType].ObsoleteBy) or
               (((mState.mData.CivGov[ParaPlayer] > 1) or (mState.mData.CivAreaPlan[ParaPlayer, vIsland] = 5)) and (vType = 1)) then
                if (not mUnits.UnitBlocked(ParaPlayer, vUnit.X, vUnit.Y)) and
                   (not (mWorld.IsCityTile(vUnit.X, vUnit.Y) and (vUnit.Next = -1))) and
                   (not mWorld.IsOcean(vUnit.X, vUnit.Y)) and
                   (mState.mData.CivAreaPlan[ParaPlayer, vIsland] <> 2) then
                begin
                    mUnits.DropUnit(ParaPlayer, vI);
                    Continue;
                end;

        for vJ := 0 to 31 do
        begin
            if mState.mData.ObjectivesType[ParaPlayer, vJ] = -1 then Continue;
            if (mState.mData.UtTypes[vType].Role <> mState.mData.ObjectivesType[ParaPlayer, vJ]) or
               (mWorld.RegionKey(mState.mData.CivTargetsX[ParaPlayer, vJ], mState.mData.CivTargetsY[ParaPlayer, vJ]) <> vIsland) then
                Continue;

            if vType = 15 then
            begin
                if ((mState.mData.AimCount[ParaPlayer, vJ] and 1) <> 0) and
                   (((vJ + (mState.mData.TurnTick shr 1)) and 1) <> 0) then
                begin
                    vRating := MapDist(vUnit.X, mState.mData.CivTargetsX[ParaPlayer, vJ],
                                       vUnit.Y, mState.mData.CivTargetsY[ParaPlayer, vJ]);
                    if mState.mData.UtTypes[vType].Moves >= vRating then
                        vRating := 2 * vRating div (mState.mData.AimCount[ParaPlayer, vJ] + 1)
                    else
                        vRating := 4 * vRating div (mState.mData.AimCount[ParaPlayer, vJ] + 1);
                end else Continue;
            end else
                vRating := mSlots[vJ] * MapDist(vUnit.X, mState.mData.CivTargetsX[ParaPlayer, vJ],
                                                vUnit.Y, mState.mData.CivTargetsY[ParaPlayer, vJ]) div
                           (mState.mData.AimCount[ParaPlayer, vJ] + 1);

            if (vUnit.Status and $0C) <> 0 then
            begin
                if (mState.mData.AimCount[ParaPlayer, vJ] < 2) or
                   (vRating > mState.mData.AimCount[ParaPlayer, vJ] * mCap) then Continue;
                if mWorld.IsCityTile(vUnit.X, vUnit.Y) then Continue;
            end;

            if vRating >= vBestCost then Continue;
            if 4 * mState.mData.AimCount[ParaPlayer, vJ] < vRating div mCap then Continue;
            vBestCost := vRating;
            vChosenSlot := vJ;
        end;

        if vChosenSlot = -1 then Continue;
        mState.mData.ArmyData[ParaPlayer, vI].GotoX := mState.mData.CivTargetsX[ParaPlayer, vChosenSlot];
        mState.mData.ArmyData[ParaPlayer, vI].GotoY := mState.mData.CivTargetsY[ParaPlayer, vChosenSlot];
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
        if (mState.mData.SpotClasses[ParaPlayer, vI] <> -1) and
           (mState.mData.SpotClasses[ParaPlayer, vI] <= 2) then
            AddTarget(ParaPlayer,
                mState.mData.CampXPos[ParaPlayer, vI],
                mState.mData.CivLotY[ParaPlayer, vI],
                mState.mData.SpotClasses[ParaPlayer, vI],
                mState.mData.AiCampSiteWeights[ParaPlayer, vI]);
end;

function TCivAI.AiOrder(ParaPlayer, ParaUnit: Integer): Integer;
var
    vUnit : TUnit;
    vType, vRole, vUnitX, vUnitY, vHome, vCityDist, vNearDist, vRegion, vPlan, vSiteScore : Integer;
    vBlocked : Boolean;
    vI, vDir, vNX, vNY, vBestScore, vResultDir, vEnemyCiv, vEnemyUnit, vOdds : Integer;
    vFreem, vNearEnemyShip : Boolean;
    vTmp, vTmp2, vTempType, vSavedStatus, vBestDist, vDist : Integer;
    vTargetCity, vArmyCount, vDivisor, vStackStrength, vAttackersCount, vRoles : Integer;
    vNukeScore, vNukeBest, vNukeCity : Integer;
begin
    if ParaPlayer = 0 then
        Exit(UnitAiMove(ParaPlayer, ParaUnit));

    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vType := vUnit.UnitType;

    if (vType = 15) and (vUnit.Fuel <= 0) then Exit(Ord('h'));
    if (vType = 14) and (vUnit.GotoX = -1) then
    begin
        if mState.mData.UtTypes[vType].Moves * 3 div 2 >= vUnit.Moves then Exit(Ord('h'));
        vBestDist := 999; vTargetCity := -1;
        for vI := 0 to 127 do
            if (mState.mData.ArmyData[mState.mData.CivNow, vI].UnitType = 15) and
               ((mState.mData.ArmyData[mState.mData.CivNow, vI].Visibility and (1 shl ParaPlayer)) <> 0) then
            begin
                vDist := MapDist(vUnit.X, mState.mData.ArmyData[mState.mData.CivNow, vI].X,
                                 vUnit.Y, mState.mData.ArmyData[mState.mData.CivNow, vI].Y);
                if vDist < vBestDist then begin vBestDist := vDist; vTargetCity := vI; end;
            end;
        if (vTargetCity <> -1) and (vBestDist > 1) then
            if mState.mData.UtTypes[vType].Moves > vBestDist then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX :=
                    mState.mData.ArmyData[mState.mData.CivNow, vTargetCity].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY :=
                    mState.mData.ArmyData[mState.mData.CivNow, vTargetCity].Y;
            end else
                Exit(Ord('h'));
    end;

    vUnitX := vUnit.X; vUnitY := vUnit.Y;
    vBlocked := mUnits.IfOpen(ParaPlayer, vUnitX, vUnitY);
    vHome := -1; vCityDist := 999;
    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then Continue;
        vDist := MapDist(vUnitX, mState.mData.TownBuf[vI].X, vUnitY, mState.mData.TownBuf[vI].Y);
        if vDist < vCityDist then begin vHome := vI; vCityDist := vDist; end;
    end;
    vNearDist := vCityDist;
    vRegion := mWorld.RegionKey(vUnitX, vUnitY);
    vPlan := mState.mData.CivAreaPlan[ParaPlayer, vRegion];
    vRole := mState.mData.UtTypes[vType].Role;

    if vType = 25 then
    begin
        vNukeBest := -1; vNukeCity := -1;
        for vI := 0 to 127 do
        begin
            if (mState.mData.TownBuf[vI].Status = -1) or
               ((Integer(mState.mData.TownBuf[vI].Buildings) and ConstBldSDI) <> 0) or
               (mState.mData.TownBuf[vI].Size <= 4) then Continue;
            vNukeScore := 0;
            for vDir := 0 to 8 do
            begin
                vNX := mState.mData.TownBuf[vI].X + ConstSpiralX[vDir];
                vNY := mState.mData.TownBuf[vI].Y + ConstSpiralY[vDir];
                vEnemyCiv := mUnits.MapOwner(vNX, vNY);
                if (vEnemyCiv <> -1) and ((mState.mData.Treaties[ParaPlayer, vEnemyCiv] and $82) = $80) then
                    Inc(vNukeScore)
                else if vEnemyCiv = ParaPlayer then Dec(vNukeScore, 2)
                else if vEnemyCiv <> -1 then Dec(vNukeScore, 99);
            end;
            vNukeScore := vNukeScore + mState.mData.TownBuf[vI].Size div 2;
            if vNukeScore > vNukeBest then begin vNukeBest := vNukeScore; vNukeCity := vI; end;
        end;
        if (vNukeBest >= 10) and (mState.mData.ForcesPresent[ParaPlayer, 25] > 1) then
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
        Exit(Ord('h'));
    end;

    if vType = 26 then
    begin
        if mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX <> -1 then Exit(0);
        if (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner <> ParaPlayer) then
        begin
            mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := mState.mData.TownBuf[vHome].X;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY := mState.mData.TownBuf[vHome].Y;
            Exit(0);
        end;
        mUnits.DropUnit(ParaPlayer, ParaUnit);
        Exit(Ord(' '));
    end;

    if vRole = 0 then ClearSitesNear(ParaPlayer, 0, vUnitX, vUnitY, 0);

    vSiteScore := mWorld.SiteValue(vUnitX, vUnitY);
    if (vSiteScore <> 0) and (vRole < 3) then
    begin
        vResultDir := 0;
        for vI := 1 to 8 do
        begin
            vNX := WrapX(vUnitX + ConstSpiralX[vI]);
            vNY := vUnitY + ConstSpiralY[vI];
            vTmp2 := mWorld.SiteValue(vNX, vNY);
            if vTmp2 > vSiteScore then begin vSiteScore := vTmp2; vResultDir := vI; end;
            if mWorld.HasHut(mWorld.TerrainAt(vNX, vNY), vNX, vNY) and (vRole <> 0) then
                Exit(vI);
        end;
        if (mState.mData.TurnTick = 0) and (mState.mData.BeginnerHelp <> 0) then
        begin vSiteScore := 15; vResultDir := 0; end;
        if (vSiteScore >= 8) and (15 - vCityDist <= vSiteScore) and (not vBlocked) then
        begin
            if vRole = 0 then
            begin
                if vResultDir <> 0 then Exit(vResultDir);
                Exit(Ord('b'));
            end;
            SiteAdd(ParaPlayer, vUnitX, vUnitY, 0, 2);
        end;
    end;

    if (vRole = 0) and (mState.mData.CurTier <> 0) and
       (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = mState.mData.CivNow) and
       (not vBlocked) and (vCityDist > 1) and
       (ParaPlayer <> mState.mData.TownBuf[vHome].Owner) and
       (mState.mData.TechCount[ParaPlayer] < mState.mData.TechCount[mState.mData.CivNow]) then
    begin
        vTmp2 := mWorld.SiteValue(vUnitX, vUnitY);
        if (vTmp2 >= 9) and (14 - vCityDist <= vTmp2) then Exit(Ord('b'));
    end;

    if mWorld.IsCityTile(vUnitX, vUnitY) then
    begin
        if vRole = 2 then
        begin
            if mState.mData.ArmyData[ParaPlayer, ParaUnit].Next = -1 then Exit(Ord('f'));

            vTempType := mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType := 26;
            vTmp := mUnits.StackOther(ParaPlayer, ParaUnit);
            mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType := vTempType;
            if (vTmp <> ParaUnit) and
               (mState.mData.UtTypes[mState.mData.ArmyData[ParaPlayer, vTmp].UnitType].Defense <
                mState.mData.UtTypes[vType].Defense) then
                Exit(Ord('f'));

            vDivisor := 4;
            if mUnits.UnitBlocked(ParaPlayer, vUnitX, vUnitY) then vDivisor := 3;
            if (Integer(mState.mData.TownBuf[vHome].Buildings) and ConstBldPalace) <> 0 then Dec(vDivisor)
            else if vPlan = 0 then Inc(vDivisor);
            vStackStrength := mUnits.StackLen(ParaPlayer, ParaUnit, 1);
            if mState.mData.TownBuf[vHome].Size div vDivisor + 1 > vStackStrength then
                AddTarget(ParaPlayer, vUnitX, vUnitY, 2, 2);
            if mState.mData.TownBuf[vHome].Size div vDivisor + 1 >= vStackStrength then
                Exit(Ord('f'));

            vSavedStatus := mState.mData.ArmyData[ParaPlayer, ParaUnit].Status;
            mState.mData.ArmyData[ParaPlayer, ParaUnit].Status := ShortInt(vSavedStatus or ConstUnitFortified);
            if (mUnits.StackOther(ParaPlayer, ParaUnit) = ParaUnit) and
               (mState.mData.TownBuf[vHome].Size div vDivisor + 1 > mUnits.StackLen(ParaPlayer, ParaUnit, 4)) then
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

    if (vRole = 5) or (vRole = 3) then
    begin
        vArmyCount := 0; vRoles := 0;
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[ParaPlayer, vI].UnitType = -1) or (vI = ParaUnit) then Continue;
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
            vBestDist := 999; vTargetCity := -1;
            for vI := 0 to 127 do
            begin
                if (mState.mData.TownBuf[vI].Status = -1) or
                   (mState.mData.TownBuf[vI].Owner <> ParaPlayer) or
                   ((mState.mData.TownBuf[vI].Status and 2) = 0) then Continue;
                vDist := MapDist(vUnitX, mState.mData.TownBuf[vI].X, vUnitY, mState.mData.TownBuf[vI].Y);
                if mState.mData.DefendersIsland[ParaPlayer, mWorld.RegionKey(mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y)] < 16 then
                    Continue;
                if vDist < vBestDist then begin vBestDist := vDist; vTargetCity := vI; end;
            end;
            if vTargetCity <> -1 then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := mState.mData.TownBuf[vTargetCity].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY := mState.mData.TownBuf[vTargetCity].Y;
            end;
        end;
    end;

    if (mState.mData.UtTypes[vType].Moves < 2) and (vCityDist < 4) and
       (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = mState.mData.CivNow) and
       ((mState.mData.Treaties[mState.mData.CivNow, ParaPlayer] and 2) = 0) and
       ((mWorld.MapFlags(vUnitX, vUnitY) and $06) <> 0) and
       (mState.mData.TownBuf[vHome].Owner <> ParaPlayer) then
        Exit(Ord('P'));

    if vRole = 0 then
    begin
        if not mWorld.IsOcean(vUnitX, vUnitY) then
        begin
            if vNearDist >= 2 then AddTarget(ParaPlayer, vUnitX, vUnitY, 2, 2);
            if (vPlan = 5) or
               (mWorld.MapFlags(vUnitX, vUnitY) and $06 <> 0) or
               (mWorld.MapFlags(vUnitX, vUnitY) and $08 <> 0) then
            begin
                if (vCityDist > 0) and (vCityDist <= 2) and (vHome <> -1) and
                   (mState.mData.TownBuf[vHome].Owner = ParaPlayer) and
                   ((mState.mData.RuleOptions and 2) <> 0) then
                begin
                    if (mWorld.MapFlags(vUnitX, vUnitY) and ConstTilePollution) <> 0 then Exit(Ord('p'));
                    mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := -1;
                    case WorkTile(mWorld, vUnitX, vUnitY) of
                        1: Exit(Ord('i'));
                        2: Exit(Ord('m'));
                    end;
                end;
            end;
            if (mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX <> -1) and
               ((TCivTables.LeaderF1(ParaPlayer) + 1) * mState.mData.AiZonePlaces[vRegion] >
                mState.mData.AiContinentTowns[ParaPlayer, vRegion] shl 4) then
                Exit(0);
        end;
        if mState.mData.AiContinentTowns[ParaPlayer, vRegion] > mState.mData.AiZonePlaces[vRegion] div 8 then
        begin
            if (vCityDist = 0) and (mState.mData.TownBuf[vHome].Size < 10) then Exit(Ord('b'));
            if (vHome <> -1) and (mState.mData.TownBuf[vHome].Owner = ParaPlayer) and
               (mState.mData.TownBuf[vHome].Size < 10) then
            begin
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoX := mState.mData.TownBuf[vHome].X;
                mState.mData.ArmyData[ParaPlayer, ParaUnit].GotoY := mState.mData.TownBuf[vHome].Y;
                Exit(0);
            end;
        end;
    end;

    if (vRole = 2) and (not mWorld.IsOcean(vUnitX, vUnitY)) then
    begin
        if (vNearDist > 1) and (vCityDist <= 3) and (vHome <> -1) and
           (mState.mData.TownBuf[vHome].Owner = ParaPlayer) then
            Exit(Ord('f'));
        if vBlocked and (vNearDist > 0) then Exit(Ord('f'));
    end;

    vBestScore := -999; vResultDir := 0;
    vFreem := not mUnits.UnitBlocked(ParaPlayer, vUnitX, vUnitY);
    if vFreem then
        mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := -1;
    if (vType = 1) and (vPlan = 1) then vRole := 1;

    for vDir := 1 to 8 do
    begin
        vNX := WrapX(vUnitX + ConstSpiralX[vDir]);
        vNY := vUnitY + ConstSpiralY[vDir];
        if not MapInBounds(vNX, vNY) then Continue;

        vEnemyCiv := mUnits.MapOwner(vNX, vNY);
        if (vEnemyCiv = ParaPlayer) and (mState.mData.ArmyData[ParaPlayer, ParaUnit].Next <> -1) then Continue;
        vEnemyUnit := -1;
        if vEnemyCiv <> -1 then vEnemyUnit := mUnits.MapStack(vNX, vNY, vEnemyCiv);

        vTmp := mRng.Scaled(5);
        if vTmp < 0 then vTmp := 0;

        if (vEnemyUnit <> -1) and (vEnemyCiv <> ParaPlayer) and
           ((mState.mData.Treaties[ParaPlayer, vEnemyCiv] and 2) = 0) then
        begin
            vOdds := mCombat.Battle(ParaPlayer, ParaUnit, vEnemyCiv, vEnemyUnit, 0);
            vOdds := vOdds * (mUnits.StackLen(vEnemyCiv, vEnemyUnit, 0) + 1) div mState.mData.UtTypes[vType].Cost;
            if mWorld.IsCityTile(vNX, vNY) then vOdds := vOdds * 3;
            if (vRole = 1) and (vPlan = 1) then vOdds := vOdds * 3;
            if (vRole = 1) and (mState.mData.UtTypes[vType].Attack * 2 < mUnits.StackLen(ParaPlayer, ParaUnit, 3)) then
                vOdds := vOdds * 2;
            if vOdds >= 6 then vTmp := vTmp + 4 * vOdds else vTmp := -999;
        end else
        begin
            if mWorld.HasHut(mWorld.TerrainAt(vNX, vNY), vNX, vNY) then vTmp := vTmp + 20;
            if vFreem then vTmp := vTmp + 4 * mWorld.TerrainDefense(vNX, vNY);
        end;

        if vTmp > vBestScore then
        begin
            vBestScore := vTmp;
            vResultDir := vDir;
        end;
    end;

    if (mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves < 3) and (vResultDir <> 0) then
        vResultDir := 0;

    mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := vResultDir;
    Result := vResultDir;
end;

procedure TCivAI.AiTurn(ParaPlayer: Integer);
var
    vUnitIdx, vOrder, vOrders, vAttempts : Integer;
begin
    for vUnitIdx := 0 to 127 do
        if mState.mData.ArmyData[ParaPlayer, vUnitIdx].UnitType <> -1 then
            mState.mData.ArmyData[ParaPlayer, vUnitIdx].Moves :=
                ShortInt(3 * mState.mData.UtTypes[mState.mData.ArmyData[ParaPlayer, vUnitIdx].UnitType].Moves);

    for vUnitIdx := 0 to 127 do
    begin
        vOrders := 0; vAttempts := 0;
        repeat
            if mState.mData.ArmyData[ParaPlayer, vUnitIdx].UnitType = -1 then Break;
            if mState.mData.ArmyData[ParaPlayer, vUnitIdx].Moves = 0 then Break;
            if (mState.mData.ArmyData[ParaPlayer, vUnitIdx].Status and
                (ConstUnitSentry or ConstUnitFortified)) <> 0 then Break;

            vOrder := AiOrder(ParaPlayer, vUnitIdx);
            Inc(vOrders);
            if vOrders > 4 then Break;

            if (vOrder >= 1) and (vOrder <= 8) then
            begin
                if not ExecuteDirection(ParaPlayer, vUnitIdx, vOrder) then Break;
            end else if vOrder = 0 then
            begin
                if mState.mData.ArmyData[ParaPlayer, vUnitIdx].GotoX = -1 then Break;
                Inc(vAttempts);
                if vAttempts > 3 then Break;
            end else if vOrder = Ord(' ') then Break
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
            end else if vOrder = Ord('h') then Break
            else if (vOrder = Ord('i')) or (vOrder = Ord('m')) or (vOrder = Ord('r')) or (vOrder = Ord('p')) then
            begin
                ExecuteTerraform(ParaPlayer, vUnitIdx, vOrder);
                Break;
            end else Break;
        until False;
    end;
end;

function TCivAI.ExecuteDirection(ParaPlayer, ParaUnit, ParaDirection: Integer): Boolean;
var
    vUnit : TUnit;
    vNX, vNY, vEnemyCiv, vEnemyUnt, vTileCost : Integer;
begin
    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vNX := WrapX(vUnit.X + ConstSpiralX[ParaDirection]);
    vNY := vUnit.Y + ConstSpiralY[ParaDirection];
    if not MapInBounds(vNX, vNY) then Exit(False);

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

    vTileCost := mWorld.TerrainMoveCost(vNX, vNY) * 3;
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

    if mState.mData.ArmyData[ParaPlayer, ParaUnit].UnitType = -1 then Exit(False);
    Exit(True);
end;

procedure TCivAI.ExecuteFoundCity(ParaPlayer, ParaUnit: Integer);
begin
    if Assigned(mCityCreate) then
        mCityCreate(ParaPlayer, 0,
            mState.mData.ArmyData[ParaPlayer, ParaUnit].X,
            mState.mData.ArmyData[ParaPlayer, ParaUnit].Y, 1);
    mUnits.DropUnit(ParaPlayer, ParaUnit);
end;

procedure TCivAI.ExecuteTerraform(ParaPlayer, ParaUnit, ParaOrder: Integer);
begin
    mState.mData.ArmyData[ParaPlayer, ParaUnit].Moves := 0;
end;

function TCivAI.UnitAiMove(ParaPlayer, ParaUnit: Integer): Integer;
var
    vUnit : TUnit;
    vTypeCode, vI, vNX, vNY, vHome, vCityDist, vLand, vBestValue, vBestDir : Integer;
    vTmp, vScore, vBestScore : Integer;
begin
    vUnit := mState.mData.ArmyData[ParaPlayer, ParaUnit];
    vTypeCode := vUnit.UnitType;
    if (vUnit.Y < 2) or (vUnit.Y >= $30) then
    begin
        mUnits.DropUnit(ParaPlayer, ParaUnit);
        Exit(Ord(' '));
    end;
    if (vTypeCode = 0) or (vTypeCode = 26) then Exit(Ord(' '));

    vHome := -1; vCityDist := 999;
    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then Continue;
        vTmp := MapDist(vUnit.X, mState.mData.TownBuf[vI].X, vUnit.Y, mState.mData.TownBuf[vI].Y);
        if vTmp < vCityDist then begin vHome := vI; vCityDist := vTmp; end;
    end;

    vBestScore := -999; vBestDir := 0;
    for vI := 1 to 8 do
    begin
        vNX := WrapX(vUnit.X + ConstSpiralX[vI]);
        vNY := vUnit.Y + ConstSpiralY[vI];
        if not MapInBounds(vNX, vNY) then Continue;
        vLand := mWorld.TerrainAt(vNX, vNY);
        if (vLand = ConstTerrainOcean) and (mState.mData.UtTypes[vTypeCode].Domain <> 2) then Continue;
        vScore := mRng.Scaled(6) + mWorld.TerrainDefense(vNX, vNY) * 4;
        if mWorld.IsCityTile(vNX, vNY) then
            if mWorld.MapCity(vNX, vNY) <> ParaPlayer then vScore := vScore + 50;
        if (vCityDist > 1) and (vHome <> -1) then
        begin
            vTmp := MapDist(vNX, mState.mData.TownBuf[vHome].X, vNY, mState.mData.TownBuf[vHome].Y);
            vScore := vScore + (vCityDist - vTmp) * 5;
        end;
        if vScore > vBestScore then begin vBestScore := vScore; vBestDir := vI; end;
    end;
    if vBestDir = 0 then Exit(Ord(' '));
    mState.mData.ArmyData[ParaPlayer, ParaUnit].F8 := vBestDir;
    Result := vBestDir;
end;

procedure TCivAI.AddTarget(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
var
    vI, vSlot : Integer;
begin
    for vI := 0 to 31 do
        if (mState.mData.CivTargetsX[ParaPlayer, vI] = ParaX) and
           (mState.mData.CivTargetsY[ParaPlayer, vI] = ParaY) and
           (mState.mData.ObjectivesType[ParaPlayer, vI] = ParaKind) and
           (mState.mData.AimCount[ParaPlayer, vI] <= ParaCount) then
            Exit;
    vSlot := -1;
    for vI := 0 to 31 do
        if (mState.mData.ObjectivesType[ParaPlayer, vI] = -1) or
           (mState.mData.AimCount[ParaPlayer, vI] < ParaCount) then
        begin vSlot := vI; Break; end;
    if vSlot = -1 then vSlot := 31;
    for vI := 30 downto vSlot do
        if mState.mData.AimCount[ParaPlayer, vI] <> 0 then
        begin
            mState.mData.CivTargetsX[ParaPlayer, vI + 1] := mState.mData.CivTargetsX[ParaPlayer, vI];
            mState.mData.CivTargetsY[ParaPlayer, vI + 1] := mState.mData.CivTargetsY[ParaPlayer, vI];
            mState.mData.ObjectivesType[ParaPlayer, vI + 1] := mState.mData.ObjectivesType[ParaPlayer, vI];
            mState.mData.AimCount[ParaPlayer, vI + 1] := mState.mData.AimCount[ParaPlayer, vI];
        end;
    mState.mData.CivTargetsX[ParaPlayer, vSlot] := ShortInt(ParaX);
    mState.mData.CivTargetsY[ParaPlayer, vSlot] := ShortInt(ParaY);
    mState.mData.ObjectivesType[ParaPlayer, vSlot] := ShortInt(ParaKind);
    mState.mData.AimCount[ParaPlayer, vSlot] := ShortInt(ParaCount);
end;

procedure TCivAI.SiteAdd(ParaPlayer, ParaX, ParaY, ParaKind, ParaCount: Integer);
var
    vI, vSlot : Integer;
begin
    for vI := 0 to 15 do
        if (mState.mData.CampXPos[ParaPlayer, vI] = ParaX) and
           (mState.mData.CivLotY[ParaPlayer, vI] = ParaY) and
           (mState.mData.SpotClasses[ParaPlayer, vI] = ParaKind) and
           (mState.mData.AiCampSiteWeights[ParaPlayer, vI] <= ParaCount) then
            Exit;
    vSlot := -1;
    for vI := 0 to 15 do
        if (mState.mData.SpotClasses[ParaPlayer, vI] = -1) or
           (mState.mData.AiCampSiteWeights[ParaPlayer, vI] < ParaCount) then
        begin vSlot := vI; Break; end;
    if vSlot = -1 then vSlot := 15;
    for vI := 14 downto vSlot do
        if mState.mData.AiCampSiteWeights[ParaPlayer, vI] <> 0 then
        begin
            mState.mData.CampXPos[ParaPlayer, vI + 1] := mState.mData.CampXPos[ParaPlayer, vI];
            mState.mData.CivLotY[ParaPlayer, vI + 1] := mState.mData.CivLotY[ParaPlayer, vI];
            mState.mData.SpotClasses[ParaPlayer, vI + 1] := mState.mData.SpotClasses[ParaPlayer, vI];
            mState.mData.AiCampSiteWeights[ParaPlayer, vI + 1] := mState.mData.AiCampSiteWeights[ParaPlayer, vI];
        end;
    mState.mData.CampXPos[ParaPlayer, vSlot] := ShortInt(ParaX);
    mState.mData.CivLotY[ParaPlayer, vSlot] := ShortInt(ParaY);
    mState.mData.SpotClasses[ParaPlayer, vSlot] := ShortInt(ParaKind);
    mState.mData.AiCampSiteWeights[ParaPlayer, vSlot] := ShortInt(ParaCount);
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

procedure TCivAI.ClearSitesNear(ParaPlayer, ParaKind, ParaX, ParaY, ParaRange: Integer);
var
    vI, vDist : Integer;
begin
    for vI := 0 to 15 do
        if mState.mData.SpotClasses[ParaPlayer, vI] = ParaKind then
        begin
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
        if (mState.mData.TownBuf[vI].Owner = ParaOwner) and
           (mState.mData.TownBuf[vI].Status <> -1) and
           ((ParaRegion = -1) or
            (mWorld.RegionKey(mState.mData.TownBuf[vI].X, mState.mData.TownBuf[vI].Y) = ParaRegion)) then
            CityRetarget(vI);
end;

procedure TCivAI.CityRetarget(ParaCity: Integer);
var
    vOwner, vNewProd : Integer;
begin
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    if mState.mData.TownBuf[ParaCity].Production >= 0 then
        Dec(mState.mData.CivUnitsOrdered[vOwner, mState.mData.TownBuf[ParaCity].Production]);
    vNewProd := -1;
    if Assigned(mFindSlot) then
        vNewProd := mFindSlot(vOwner, ParaCity);
    mState.mData.TownBuf[ParaCity].Production := ShortInt(vNewProd);
    if vNewProd >= 0 then
        Inc(mState.mData.CivUnitsOrdered[vOwner, vNewProd]);
end;

function TCivAI.OceanEdge(ParaPlayer, ParaX, ParaY: Integer): Integer;
begin
    Result := -1;
end;

procedure TCivAI.CityCaptured(ParaCity: Integer);
var
    vP, vI, vCX, vCY, vDist, vMoves : Integer;
begin
    vCX := mState.mData.TownBuf[ParaCity].X;
    vCY := mState.mData.TownBuf[ParaCity].Y;
    for vP := 1 to 7 do
    begin
        if (vP = mState.mData.CivNow) or ((mState.mData.Treaties[vP, mState.mData.CivNow] and 2) <> 0) then
            Continue;
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[vP, vI].UnitType = -1) or
               (mState.mData.UtTypes[mState.mData.ArmyData[vP, vI].UnitType].Capacity = 0) or
               (mState.mData.ArmyData[vP, vI].Next = -1) or
               (not mWorld.IsOcean(mState.mData.ArmyData[vP, vI].X, mState.mData.ArmyData[vP, vI].Y)) then
                Continue;
            vMoves := mState.mData.UtTypes[mState.mData.ArmyData[vP, vI].UnitType].Moves;
            vDist := MapDist(mState.mData.ArmyData[vP, vI].X, vCX, mState.mData.ArmyData[vP, vI].Y, vCY);
            if vDist <= vMoves * 3 then
            begin
                mState.mData.ArmyData[vP, vI].GotoX := vCX;
                mState.mData.ArmyData[vP, vI].GotoY := vCY;
            end;
        end;
    end;
end;

end.