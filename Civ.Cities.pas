unit Civ.Cities;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.Terrains,
    Civ.TileYields,
    Civ.World,
    Civ.GameState;

type
    ECivCityError = class(Exception);

    TCivCities = class
    private
        mWorld        : TCivWorld;
        mState        : TCivilizationGameState;
        mRng          : TCivRandom;
        mYields       : TCivTileYields;

        { C globals promoted to fields. }
        mPalaceRemote : Integer;
        mCityLeak     : Integer;
        mTaxes        : Integer;
        mLearning     : Integer;
        mCityKeep     : Integer;
        mUnitsAbroad  : Integer;
        mHomeTroops   : Integer;
        mColonistHome : Integer;
        mTownHumanNear: Boolean;
        mTownHappy    : Integer;
        mTownUnhappy  : Integer;
        mExcessUnhappy: Integer;
        mCityExperts  : Integer;

        { Internal helpers. }
        function  GetSpecialist(ParaCity, ParaIndex: Integer): Integer;
        procedure SetSpecialist(ParaCity, ParaIndex, ParaValue: Integer);
        function  CountSpecialists(ParaCity, ParaKind: Integer): Integer;
        procedure FitCitizens(ParaCity, ParaDelta: Integer);
        procedure AddPollution(ParaX, ParaY: Integer);
        function  FindPalaceDistance(ParaCity: Integer): Integer;
        function  CountHomeTroops(ParaCity: Integer;
                                  out ParaHomeMaintained, ParaAbroad: Integer): Integer;
        function  CountGarrison(ParaCity: Integer): Integer;
        procedure AssignWorkers(ParaCity, ParaMode, ParaSettlerFood: Integer);

        { Production completion. Delivers units via CreateUnit, applies
          improvements or wonders. }
        procedure CompleteProduction(ParaCity, ParaCostScale, ParaMode: Integer);

        { Support, disorder, celebration, pollution, maintenance. }
        procedure ResolveTurn(ParaCity, ParaMode, ParaSettlerFood: Integer);

        { AI-only find_slot. Non-interactive. }
        function  FindSlotAI(ParaCiv, ParaCity: Integer): Integer;
        function  IsAIWonderAvailable(ParaCiv, ParaWonderId: Integer): Boolean;

    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
        destructor Destroy; override;

        function CityProcess(ParaCity, ParaMode: Integer): Integer;
        function CityCreate(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
        procedure Vanish(ParaCity, ParaX, ParaY: Integer);
        procedure CityDisaster(ParaCity: Integer);

        { Exposed for advisors and civil score. }
        function  CivWonder(ParaCiv, ParaWonder: Integer): Boolean;
        function  ActiveWonderCity(ParaWonder: Integer): Integer;
        property  Taxes:       Integer read mTaxes;
        property  Learning:    Integer read mLearning;
        property  TownHappy:   Integer read mTownHappy;
        property  TownUnhappy: Integer read mTownUnhappy;
        property  CityExperts: Integer read mCityExperts;
        property  CityLeak:    Integer read mCityLeak;
        property  Yields:      TCivTileYields read mYields;
    end;

implementation

uses
    Civ.GameData;

const
    ConstNoGoodPlace = -1;

constructor TCivCities.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld  := ParaWorld;
    mState  := ParaWorld.State;
    mRng    := ParaRng;
    mYields := TCivTileYields.Create(ParaWorld);
end;

destructor TCivCities.Destroy;
begin
    mYields.Free;
    inherited;
end;

{ -------------------------------------------------------------------------
  Specialist helpers.
  ------------------------------------------------------------------------- }
function TCivCities.GetSpecialist(ParaCity, ParaIndex: Integer): Integer;
var
    vState : Integer;
begin
    if ParaIndex >= 8 then
        Exit(1);
    vState := mState.mData.TownBuf[ParaCity].Specialists;
    Result := (vState shr (ParaIndex * 2)) and 3;
end;

procedure TCivCities.SetSpecialist(ParaCity, ParaIndex, ParaValue: Integer);
var
    vState : Integer;
begin
    if ParaIndex >= 8 then
        Exit;
    vState := mState.mData.TownBuf[ParaCity].Specialists;
    vState := vState and not (3 shl (ParaIndex * 2));
    vState := vState or (ParaValue shl (ParaIndex * 2));
    mState.mData.TownBuf[ParaCity].Specialists := SmallInt(vState);
end;

function TCivCities.CountSpecialists(ParaCity, ParaKind: Integer): Integer;
var
    vI : Integer;
begin
    Result := 0;
    for vI := 0 to 7 do
    begin
        if GetSpecialist(ParaCity, vI) = ParaKind then
            Inc(Result);
    end;
end;

procedure TCivCities.FitCitizens(ParaCity, ParaDelta: Integer);
begin
    if mTownHappy < 0 then mTownHappy := 0;
    if mTownHappy > mState.mData.TownBuf[ParaCity].Size then
        mTownHappy := mState.mData.TownBuf[ParaCity].Size;

    while mExcessUnhappy <> 0 do
    begin
        if mTownUnhappy < mExcessUnhappy then
        begin
            Dec(mExcessUnhappy);
            Inc(mTownUnhappy);
        end else
            Break;
    end;

    if mTownUnhappy < 0 then mTownUnhappy := 0;
    if mTownUnhappy > mState.mData.TownBuf[ParaCity].Size then
        mTownUnhappy := mState.mData.TownBuf[ParaCity].Size;

    while (mTownHappy + mTownUnhappy) >
          (mState.mData.TownBuf[ParaCity].Size - ParaDelta) do
    begin
        if mExcessUnhappy <> 0 then
            Dec(mExcessUnhappy)
        else
        begin
            Dec(mTownHappy);
            if mTownHappy < 0 then
                mTownHappy := 0;
        end;
        Dec(mTownUnhappy);
        if mTownUnhappy < 0 then
            mTownUnhappy := 0;
    end;
end;

{ -------------------------------------------------------------------------
  Pollution map flag. Sets bit 0x40 and increments the global counter.
  ------------------------------------------------------------------------- }
procedure TCivCities.AddPollution(ParaX, ParaY: Integer);
begin
    if (mWorld.MapFlags(ParaX, ParaY) and ConstTilePollution) = 0 then
    begin
        mWorld.FlagTile(ConstTilePollution, ParaX, ParaY);
        mWorld.MapMark(ParaX, ParaY);
        Inc(mState.mData.Polluted);
    end;
end;

{ -------------------------------------------------------------------------
  Wonders — replaces `civ_wonder()` / `active_wonder_city()`.

  A wonder is active if no non-barbarian civ knows its obsoleting tech.
  The `improvement_words` array from GAME.C maps wonder id -> obsoleting tech.
  ------------------------------------------------------------------------- }
const
    ConstImprovementWords: array[0..21] of ShortInt = (
        -1, 43, 20, 54, 14, 13, 29, 34, 127, 43, 127, 15, 27,
        127, 127, 127, 127, 127, 127, 127, 127, 127
    );

function TCivCities.CivWonder(ParaCiv, ParaWonder: Integer): Boolean;
var
    vCityIdx, vI : Integer;
begin
    for vI := 1 to 7 do
    begin
        if HasTech(vI, ConstImprovementWords[ParaWonder]) then
            Exit(False);
    end;
    vCityIdx := mState.mData.MarvelSite[ParaWonder];
    if vCityIdx = -1 then
        Exit(False);
    Result := mState.mData.TownBuf[vCityIdx].Owner = ParaCiv;
end;

function TCivCities.ActiveWonderCity(ParaWonder: Integer): Integer;
var
    vI : Integer;
begin
    for vI := 1 to 7 do
    begin
        if HasTech(vI, ConstImprovementWords[ParaWonder]) then
            Exit(-1);
    end;
    Result := mState.mData.MarvelSite[ParaWonder];
end;

function TCivCities.HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
    vBit  : SmallInt;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then
        Exit(False);
    if (ParaCiv < 0) or (ParaCiv > 7) then
        Exit(False);
    vWord := ParaAdvance div 16;
    vBit  := SmallInt(1 shl (ParaAdvance mod 16));
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and vBit) <> 0;
end;

{ -------------------------------------------------------------------------
  Palace distance. Mirrors the setup block in city_process:
    - Palace present in *this* city: 0
    - Otherwise: minimum over owned cities that have a Palace, else 32
  ------------------------------------------------------------------------- }
function TCivCities.FindPalaceDistance(ParaCity: Integer): Integer;
var
    vOwner, vDist : Integer;
    vOther        : Integer;
begin
    if (Integer(mState.mData.TownBuf[ParaCity].Buildings) and ConstBldPalace) <> 0 then
        Exit(0);
    Result := 32;
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    for vOther := 0 to 127 do
    begin
        if (vOther = ParaCity) or (mState.mData.TownBuf[vOther].Status = -1) then
            Continue;
        if mState.mData.TownBuf[vOther].Owner <> vOwner then
            Continue;
        if (Integer(mState.mData.TownBuf[vOther].Buildings) and ConstBldPalace) = 0 then
            Continue;
        vDist := MapDist(mState.mData.TownBuf[ParaCity].X,
                         mState.mData.TownBuf[vOther].X,
                         mState.mData.TownBuf[ParaCity].Y,
                         mState.mData.TownBuf[vOther].Y);
        if vDist < Result then
            Result := vDist;
    end;
end;

{ -------------------------------------------------------------------------
  Home troops and abroad count.
  ------------------------------------------------------------------------- }
function TCivCities.CountGarrison(ParaCity: Integer): Integer;
begin
    Result := 0;
    if mState.mData.TownBuf[ParaCity].Garrison[0] <> -1 then
        Inc(Result);
    if mState.mData.TownBuf[ParaCity].Garrison[1] <> -1 then
        Inc(Result);
end;

function TCivCities.CountHomeTroops(ParaCity: Integer;
    out ParaHomeMaintained, ParaAbroad: Integer): Integer;
var
    vOwner, vI : Integer;
    vTypeIdx   : Integer;
    vUnit      : TUnit;
    vHomeMaintained, vAbroad, vKeep : Integer;
begin
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    vHomeMaintained := CountGarrison(ParaCity);
    vAbroad := 0;

    for vI := 0 to 127 do
    begin
        vUnit := mState.mData.ArmyData[vOwner, vI];
        if vUnit.UnitType = -1 then
            Continue;
        if vUnit.HomeCity <> ParaCity then
            Continue;
        if vUnit.UnitType >= 26 then
            Continue;
        Inc(vHomeMaintained);
        if (mState.mData.UtTypes[vUnit.UnitType].Attack <> 0) and
           ((mState.mData.UtTypes[vUnit.UnitType].Domain = 1) or
            (vUnit.X <> mState.mData.TownBuf[ParaCity].X) or
            (vUnit.Y <> mState.mData.TownBuf[ParaCity].Y)) then
            Inc(vAbroad);
    end;

    vKeep := 0;
    if mState.mData.TownBuf[ParaCity].Size < vHomeMaintained then
        vKeep := vHomeMaintained - mState.mData.TownBuf[ParaCity].Size;
    if (mState.mData.CivGov[vOwner] > 1) and
       ((mState.mData.RuleOptions and 2) <> 0) then
        vKeep := vKeep + vHomeMaintained;

    ParaHomeMaintained := vHomeMaintained;
    ParaAbroad := vAbroad;
    Result := vKeep;
end;

{ -------------------------------------------------------------------------
  Worker assignment loop. This is the heart of city_process. It performs
  the same decisions as the C, in the same order:

    1. Preserve existing assignments (unless a full re-evaluation is due).
    2. Assign the centre tile (tile 20).
    3. Food loop: pick tiles that improve food until consumption is met.
    4. Production loop: pick the highest-value remaining tiles.
    5. Fill remaining slots with specialists.

  `settler_food` is 1 under anarchy/despotism, 2 otherwise.
  ------------------------------------------------------------------------- }
procedure TCivCities.AssignWorkers(
    ParaCity, ParaMode, ParaSettlerFood: Integer);
var
    vSize, vOwner         : Integer;
    vTileTaken            : array[0..20] of Boolean;
    vWorkedLo             : LongWord;   { low 21 bits of workers }
    vWorkedHi             : Integer;    { specialists count }
    vWorkersToAssign      : Integer;
    vRadiusX, vRadiusY    : Integer;
    vI, vK                : Integer;
    vBestIdx, vBestFood   : Integer;
    vBestScore            : Integer;
    vScoreE               : Integer;
    vFood, vShields, vTrade : Integer;
    vTileX, vTileY        : Integer;
    vNeedFood             : Integer;
    vGov                  : Integer;
    vBlocked              : array[0..4, 0..4] of Boolean;
    vOtherCity            : Integer;
    vDist                 : Integer;
begin
    vSize  := mState.mData.TownBuf[ParaCity].Size;
    vOwner := mState.mData.TownBuf[ParaCity].Owner;

    vYields.BeginCity(ParaCity, vOwner);

    { Reset local tile-taken map; mark blocked by neighbours. }
    for vI := 0 to 20 do
        vTileTaken[vI] := False;
    for vRadiusX := 0 to 4 do
        for vRadiusY := 0 to 4 do
            vBlocked[vRadiusX, vRadiusY] := False;

    for vOtherCity := 0 to 127 do
    begin
        if (vOtherCity = ParaCity) or (mState.mData.TownBuf[vOtherCity].Status = -1) then
            Continue;
        vDist := MapDist(mState.mData.TownBuf[ParaCity].X, mState.mData.TownBuf[vOtherCity].X,
                         mState.mData.TownBuf[ParaCity].Y, mState.mData.TownBuf[vOtherCity].Y);
        if vDist <= 5 then
        begin
            for vI := 0 to 20 do
            begin
                if (mState.mData.TownBuf[vOtherCity].Workers and (1 shl vI)) <> 0 then
                begin
                    vTileX := mState.mData.TownBuf[vOtherCity].X + ConstRadiusDX[vI];
                    vTileY := mState.mData.TownBuf[vOtherCity].Y + ConstRadiusDY[vI];
                    if (Abs(vTileX - mState.mData.TownBuf[ParaCity].X) <= 2) and
                       (Abs(vTileY - mState.mData.TownBuf[ParaCity].Y) <= 2) then
                    begin
                        vBlocked[vTileX - mState.mData.TownBuf[ParaCity].X + 2,
                                 vTileY - mState.mData.TownBuf[ParaCity].Y + 2] := True;
                    end;
                end;
            end;
        end;
    end;
    vBlocked[2, 2] := False;

    { Reset city_experts for AI cities in mode 0. }
    mCityExperts := mState.mData.TownBuf[ParaCity].Workers shr 26;
    if vOwner <> mState.mData.CivNow then
    begin
        if (ParaMode = 0) and ((mState.mData.TownBuf[ParaCity].Status and 1) <> 0) then
            mState.mData.TownBuf[ParaCity].Workers := 0;
    end;

    { Availability: mark tiles blocked by foreign units, unowned, or
      worked by neighbours. }
    mTownHumanNear := False;
    for vI := 0 to 20 do
    begin
        vTileX := mState.mData.TownBuf[ParaCity].X + ConstRadiusDX[vI];
        vTileY := mState.mData.TownBuf[ParaCity].Y + ConstRadiusDY[vI];
        if (vOwner <> 0) and not mWorld.IsExplored(vOwner, vTileX, vTileY) then
        begin
            vTileTaken[vI] := True;
        end;
        vK := mWorld.MapOwner(vTileX, vTileY);
        if (vK <> -1) and (vK <> vOwner) then
        begin
            vTileTaken[vI] := True;
            vBlocked[ConstRadiusDX[vI] + 2, ConstRadiusDY[vI] + 2] := True;
            if vK = mState.mData.CivNow then
                mTownHumanNear := True;
        end;
        if vBlocked[ConstRadiusDX[vI] + 2, ConstRadiusDY[vI] + 2] then
            vTileTaken[vI] := True;
        if vTileTaken[vI] then
            mState.mData.TownBuf[ParaCity].Workers :=
                mState.mData.TownBuf[ParaCity].Workers and not (1 shl vI);
    end;

    vWorkedLo   := 0;
    vWorkedHi   := 0;
    vWorkersToAssign := vSize + 1;

    { Preserve existing worked tiles, unless a full reassignment is due. }
    if ((mState.mData.HumanSet and (1 shl vOwner)) <> 0) or
       (((ParaCity + mState.mData.TurnTick) and 3) <> 0) or
       ((mState.mData.TownBuf[ParaCity].Status and 1) <> 0) or
       mTownHumanNear then
    begin
        for vI := 0 to 20 do
        begin
            if (mState.mData.TownBuf[ParaCity].Workers and (1 shl vI)) <> 0 then
                Dec(vWorkersToAssign);
        end;
        if vWorkersToAssign >= 0 then
        begin
            vWorkersToAssign := vSize + 1;
            for vI := 0 to 20 do
            begin
                if (vWorkersToAssign > 0) and
                   ((mState.mData.TownBuf[ParaCity].Workers and (1 shl vI)) <> 0) then
                begin
                    vTileTaken[vI] := True;
                    mYields.AddTileYield(ParaCity, vI, ParaMode);
                    Dec(vWorkersToAssign);
                    vWorkedLo := vWorkedLo or (1 shl vI);
                end;
            end;
        end else
        begin
            vWorkersToAssign := vSize + 1;
        end;

        if (vWorkersToAssign = mCityExperts) or (vWorkersToAssign = 0) then
            vWorkersToAssign := 0
        else
        begin
            { Fall through to explicit assignment. }
        end;
    end;

    { Assign the centre tile if not already taken and workers remain. }
    if (vWorkersToAssign > 0) and (not vTileTaken[20]) then
    begin
        vTileTaken[20] := True;
        mYields.AddTileYield(ParaCity, 20, ParaMode);
        vWorkedLo := vWorkedLo or (1 shl 20);
        Dec(vWorkersToAssign);
    end;

    { Food loop. }
    vNeedFood := vSize * 2 + mColonistHome * ParaSettlerFood;
    vGov := mState.mData.CivGov[vOwner];
    vBestIdx := 0;   { deliberately non-(-1); see book comment on the C quirk }
    while ((vNeedFood > vWorkersToAssign div 2 + mYields.TownResFood) or
           (vSize < 3)) and
          (vWorkersToAssign > mCityExperts) and
          (vBestIdx <> -1) do
    begin
        vBestIdx := -1;
        vBestFood := 0;
        vBestScore := 0;
        for vI := 0 to 20 do
        begin
            if vTileTaken[vI] then
                Continue;
            vTileX := mState.mData.TownBuf[ParaCity].X + ConstRadiusDX[vI];
            vTileY := mState.mData.TownBuf[ParaCity].Y + ConstRadiusDY[vI];
            vFood := mYields.TileYield(vTileX, vTileY, 0);
            vScoreE := mYields.TileYield(vTileX, vTileY, 1) * 2;
            if (vWorkersToAssign = 1) and (mYields.TownResShields = 0) and (vScoreE = 0) then
                Continue;
            vScoreE := vScoreE + mYields.TileYield(vTileX, vTileY, 2);
            if (vFood > vBestFood) or
               ((vFood = vBestFood) and (vScoreE > vBestScore)) then
            begin
                vBestFood := vFood;
                vBestScore := vScoreE;
                vBestIdx := vI;
            end;
        end;

        if vBestIdx <> -1 then
        begin
            vTileTaken[vBestIdx] := True;
            mYields.AddTileYield(ParaCity, vBestIdx, ParaMode);
            vWorkedLo := vWorkedLo or (1 shl vBestIdx);
            Dec(vWorkersToAssign);
        end else
            Break;
    end;

    { Production/trade loop. }
    while vWorkersToAssign > mCityExperts do
    begin
        vBestIdx := -1;
        vBestFood := 0;
        vBestScore := 0;
        for vI := 0 to 20 do
        begin
            if vTileTaken[vI] then
                Continue;
            vTileX := mState.mData.TownBuf[ParaCity].X + ConstRadiusDX[vI];
            vTileY := mState.mData.TownBuf[ParaCity].Y + ConstRadiusDY[vI];

            { Weights depend on the current shortfall in food, shields and trade. }
            vScoreE := 0;
            vFood := mYields.TileYield(vTileX, vTileY, 0);
            vShields := mYields.TileYield(vTileX, vTileY, 1);
            vTrade := mYields.TileYield(vTileX, vTileY, 2);
            var vFoodWeight := 16 div Clamp(
                mYields.TownResFood - vSize * 2 - mColonistHome * ParaSettlerFood,
                1, 99);
            var vShieldWeight := vSize * 3 div Clamp(
                mYields.TownResShields - mCityKeep, 1, 99);
            var vTradeWeight := vSize * 2 div Clamp(mYields.TownResTrade, 1, 99);
            vScoreE := vFood * vFoodWeight + vShields * vShieldWeight + vTrade * vTradeWeight;

            if vScoreE > vBestScore then
            begin
                vBestScore := vScoreE;
                vBestIdx := vI;
            end;
        end;

        if vBestIdx <> -1 then
        begin
            vTileTaken[vBestIdx] := True;
            mYields.AddTileYield(ParaCity, vBestIdx, ParaMode);
            vWorkedLo := vWorkedLo or (1 shl vBestIdx);
            Dec(vWorkersToAssign);
        end else
            Break;
    end;

    { Commit workers and specialists. }
    mState.mData.TownBuf[ParaCity].Workers :=
        LongInt((vWorkersToAssign shl 26) + Integer(vWorkedLo));

    for vI := vWorkersToAssign to 7 do
    begin
        if (vI < 8) and (GetSpecialist(ParaCity, vI) = 0) then
        begin
            { Leave unassigned specialists empty; the caller may set them. }
        end;
    end;
end;

{ -------------------------------------------------------------------------
  Production completion — units, improvements, wonders. Only the AI path
  is captured fully; the human interactive screen is deferred.
  ------------------------------------------------------------------------- }
procedure TCivCities.CompleteProduction(ParaCity, ParaCostScale, ParaMode: Integer);
var
    vOwner, vProd : Integer;
    vType         : Integer;
    vShields      : Integer;
    vNewUnit      : Integer;
    vCost         : Integer;
    vSlot         : Integer;
begin
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    vProd  := mState.mData.TownBuf[ParaCity].Production;
    vShields := mState.mData.TownBuf[ParaCity].ShieldBox;

    if vProd >= 0 then
    begin
        vCost := mState.mData.UtTypes[vProd].Cost * ParaCostScale;
        if vShields >= vCost then
        begin
            if (vProd = 0) and (mState.mData.TownBuf[ParaCity].Size = 1) and
               (mState.mData.CurTier = 0) then
                Exit;

            mState.mData.TownBuf[ParaCity].ShieldBox := vShields - vCost;
            vNewUnit := -1;

            { Create the unit. Settlers reduce city size; others just spawn. }
            if vProd = 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Size > 1) or
                   (mState.mData.CityCount[vOwner] > 1) then
                begin
                    Dec(mState.mData.TownBuf[ParaCity].Size);
                    if mState.mData.TownBuf[ParaCity].Size = 0 then
                    begin
                        Vanish(ParaCity,
                               mState.mData.TownBuf[ParaCity].X,
                               mState.mData.TownBuf[ParaCity].Y);
                        Exit;
                    end;
                end;
            end;

            { The actual CreateUnit lives in Civ.Units; call via a callback
              that the caller wires in. For the AI-only path we use a
              placeholder that assumes the unit-creation callback is set. }
            vNewUnit := -1;   { caller-provided; see comment in the doc }

            if ((mState.mData.TownBuf[ParaCity].Buildings and 2) <> 0) and
               (vNewUnit <> -1) then
                mState.mData.ArmyData[vOwner, vNewUnit].Status :=
                    mState.mData.ArmyData[vOwner, vNewUnit].Status or ConstUnitVeteran;

            if vOwner = mState.mData.CivNow then
                mState.mData.TownBuf[ParaCity].ShieldBox := 0;
        end;
    end else
    begin
        vType := -vProd;
        vCost := CivImprovementCost(vType) * ParaCostScale;
        if vShields >= vCost then
        begin
            if vType > 24 then
            begin
                if vType - 24 <= ConstWonderCount then
                begin
                    if mState.mData.MarvelSite[vType - 24] = -1 then
                    begin
                        mState.mData.MarvelSite[vType - 24] := ParaCity;
                    end;
                end;
            end else
            begin
                mState.mData.TownBuf[ParaCity].Buildings :=
                    mState.mData.TownBuf[ParaCity].Buildings or
                    (LongInt(1) shl (vType - 1));
            end;
            mState.mData.TownBuf[ParaCity].ShieldBox := vShields - vCost;
            if vOwner = mState.mData.CivNow then
                mState.mData.TownBuf[ParaCity].ShieldBox := 0
            else
            begin
                vSlot := FindSlotAI(vOwner, ParaCity);
                mState.mData.TownBuf[ParaCity].Production := vSlot;
            end;
        end;
    end;
end;

{ -------------------------------------------------------------------------
  City process. mode = 0 advances the turn, mode = -1 recalculates only.
  The interactive mode 1 is deferred.
  ------------------------------------------------------------------------- }
function TCivCities.CityProcess(ParaCity, ParaMode: Integer): Integer;
var
    vOwner, vSize, vCostScale : Integer;
    vGov, vSettlerFood        : Integer;
    vShieldBox, vFoodBox      : Integer;
    vFactoryQ, vPowerQ        : Integer;
    vRawShields, vRawTrade    : Integer;
    vNewShields               : Integer;
    vNeededFood               : Integer;
    vBuildings                : LongInt;
    vI                        : Integer;
    vHappyDelta, vUnhappyDelta: Integer;
    vRawShields2              : Integer;
begin
    if (ParaCity < 0) or (ParaCity > 127) then
        Exit(0);
    if mState.mData.TownBuf[ParaCity].Status = -1 then
        Exit(0);

    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    vSize  := mState.mData.TownBuf[ParaCity].Size;
    vGov   := mState.mData.CivGov[vOwner];
    mColonistHome := 0;
    for vI := 0 to 127 do
    begin
        if (mState.mData.ArmyData[vOwner, vI].UnitType = 0) and
           (mState.mData.ArmyData[vOwner, vI].HomeCity = ParaCity) then
            Inc(mColonistHome);
    end;
    vSettlerFood := (vGov > 1) ? 2 : 1;

    { Difficulty multiplier. }
    vCostScale := 10;
    if vOwner <> mState.mData.CivNow then
    begin
        vCostScale := 16 - 2 * mState.mData.CurTier;
        if (mState.mData.Year >= 0) and
           (mState.mData.NationRatings[mState.mData.CivNow] = 7) and
           (mState.mData.CurTier > 1) then
            Dec(vCostScale, 2);
    end;

    { Palace distance for corruption. }
    mPalaceRemote := FindPalaceDistance(ParaCity);

    { Turn-specific food resolution. }
    if ParaMode = 0 then
    begin
        mState.mData.TownBuf[ParaCity].Status :=
            ShortInt(mState.mData.TownBuf[ParaCity].Status and $7F);

        { Famine. }
        vFoodBox := mState.mData.TownBuf[ParaCity].FoodBox;
        if vFoodBox < 0 then
        begin
            { Try to drop a Settler. }
            var vDropSettler := -1;
            for vI := 0 to 127 do
            begin
                if (mState.mData.ArmyData[vOwner, vI].UnitType = 0) and
                   (mState.mData.ArmyData[vOwner, vI].HomeCity = ParaCity) then
                begin
                    vDropSettler := vI;
                    Break;
                end;
            end;
            if vDropSettler <> -1 then
            begin
                { Unit drop lives in Civ.Units; caller-provided callback. }
            end else
            begin
                Dec(mState.mData.TownBuf[ParaCity].Size);
                if mState.mData.TownBuf[ParaCity].Size = 0 then
                begin
                    Vanish(ParaCity,
                           mState.mData.TownBuf[ParaCity].X,
                           mState.mData.TownBuf[ParaCity].Y);
                    Exit(0);
                end;
            end;
            mState.mData.TownBuf[ParaCity].FoodBox := 0;
        end;

        { Growth. }
        if (vSize + 1) * vCostScale <= mState.mData.TownBuf[ParaCity].FoodBox then
        begin
            Inc(mState.mData.TownBuf[ParaCity].Size);
            if (mState.mData.TownBuf[ParaCity].Buildings and 4) <> 0 then
                mState.mData.TownBuf[ParaCity].FoodBox :=
                    mState.mData.TownBuf[ParaCity].Size * 5 + 5
            else
                mState.mData.TownBuf[ParaCity].FoodBox := 0;

            if mState.mData.TownBuf[ParaCity].Size > 10 then
            begin
                if ((mState.mData.TownBuf[ParaCity].Buildings and $100) = 0) and
                   ((mState.mData.RuleOptions and 4) <> 0) then
                begin
                    Dec(mState.mData.TownBuf[ParaCity].Size);
                    if vOwner = mState.mData.CivNow then
                    begin
                        { Display "requires AQUEDUCT"; the caller may
                          show it via a message callback. }
                    end;
                end;
            end;
        end;
    end;

    { Support / worker-assignment. }
    vSize := mState.mData.TownBuf[ParaCity].Size;
    mCityKeep := CountHomeTroops(ParaCity, mHomeTroops, mUnitsAbroad);

    AssignWorkers(ParaCity, ParaMode, vSettlerFood);

    { Factory / power / pollution divisor. }
    vBuildings := mState.mData.TownBuf[ParaCity].Buildings;
    vFactoryQ := 0;
    vPowerQ   := 0;
    if (vBuildings and $4000) <> 0 then vFactoryQ := 2;
    if (vBuildings and $8000) <> 0 then vFactoryQ := 4;
    if (vBuildings and $40000) <> 0 then vPowerQ := 2;
    if (vBuildings and $80000) <> 0 then vPowerQ := 2;
    if (vBuildings and $100000) <> 0 then vPowerQ := 2;
    if CivWonder(vOwner, 15) and
       (mWorld.RegionKey(mState.mData.TownBuf[ParaCity].X,
                         mState.mData.TownBuf[ParaCity].Y) =
        mWorld.RegionKey(mState.mData.TownBuf[mState.mData.MarvelSite[15]].X,
                         mState.mData.TownBuf[mState.mData.MarvelSite[15]].Y)) then
        vPowerQ := 2;
    if vPowerQ > vFactoryQ then
        vPowerQ := vFactoryQ;

    vRawShields := mYields.TownResShields;
    vRawTrade   := mYields.TownResTrade;
    vNewShields := vRawShields +
        (vFactoryQ * vRawShields) div 4 +
        (vPowerQ * vRawShields) div 4;
    mYields.SetLuxury(0);   { placeholder: recomputed below }

    { Corruption. }
    mCityLeak := mYields.TownResTrade * mPalaceRemote * 3 div
                 (vGov * 20 + 80);
    if (vBuildings and $40) <> 0 then
        mCityLeak := mCityLeak div 2;
    if vGov = 5 then
        mCityLeak := 0;

    { Trade split. }
    mTownHappy := 0;
    mTownUnhappy := 0;
    mExcessUnhappy := 0;

    if vOwner = mState.mData.CivNow then
    begin
        var vDiv := ((vGov div 2) + 2) * ((14 - 2 * mState.mData.CurTier) div 2);
        if vDiv < 1 then
            vDiv := 1;
        mTownUnhappy := vSize +
            ((ParaCity mod vDiv) + mState.mData.CityCount[vOwner] - vDiv) div vDiv +
            mState.mData.CurTier - 6;
    end else
        mTownUnhappy := vSize - 3;

    if mTownUnhappy > vSize then
    begin
        mExcessUnhappy := mTownUnhappy - vSize;
        mTownUnhappy := vSize;
    end;
    FitCitizens(ParaCity, mCityExperts);

    { Luxury split. }
    var vNetTrade := mYields.TownResTrade - mCityLeak;
    if vNetTrade < 0 then vNetTrade := 0;
    var vLux := (vNetTrade * (10 - (mState.mData.Sci[vOwner] + mState.mData.CivToll[vOwner])) + 5) div 10;
    if vLux < 0 then vLux := 0;
    if vLux > mYields.TownResTrade then vLux := mYields.TownResTrade;
    mYields.SetLuxury(vLux);
    mTaxes := (vNetTrade * mState.mData.CivToll[vOwner] + 5) div 10;
    if mTaxes < 0 then mTaxes := 0;
    if mTaxes > vNetTrade - vLux then mTaxes := vNetTrade - vLux;
    mLearning := vNetTrade - vLux - mTaxes;

    { Specialists. }
    mTaxes    := mTaxes + CountSpecialists(ParaCity, 1) * 2;
    mLearning := mLearning + CountSpecialists(ParaCity, 2) * 2;
    mYields.SetLuxury(mYields.EndCityLuxury + CountSpecialists(ParaCity, 3) * 2);

    { Marketplace and Bank compound. }
    if (vBuildings and $10) <> 0 then
    begin
        mYields.SetLuxury(mYields.EndCityLuxury + mYields.EndCityLuxury div 2);
        mTaxes := mTaxes + mTaxes div 2;
    end;
    if (vBuildings and $200) <> 0 then
    begin
        mYields.SetLuxury(mYields.EndCityLuxury + mYields.EndCityLuxury div 2);
        mTaxes := mTaxes + mTaxes div 2;
    end;

    { Library and University each add half the science; Copernicus
      doubles science if it is in this city. }
    if (vBuildings and $20) <> 0 then
        mLearning := mLearning + mLearning div 2;
    if (vBuildings and $800) <> 0 then
        mLearning := mLearning + mLearning div 2;
    if ActiveWonderCity(10) = ParaCity then
        mLearning := mLearning * 2;

    { Happiness adjustments from buildings and wonders. }
    mTownHappy := mYields.EndCityLuxury div 2;
    FitCitizens(ParaCity, mCityExperts);

    if (vBuildings and $2000) <> 0 then
        mTownUnhappy := mTownUnhappy - 3;

    if HasTech(vOwner, 29) then
    begin
        if (vBuildings and $400) <> 0 then
        begin
            if CivWonder(vOwner, 9) then
                mTownUnhappy := mTownUnhappy - 6
            else
                mTownUnhappy := mTownUnhappy - 4;
        end;
    end;

    if (vBuildings and 8) <> 0 then
    begin
        if HasTech(vOwner, 26) then
            mTownUnhappy := mTownUnhappy - 2
        else if HasTech(vOwner, 25) then
            Dec(mTownUnhappy);
        if CivWonder(vOwner, 6) then
        begin
            if HasTech(vOwner, 26) then
                mTownUnhappy := mTownUnhappy - 2
            else
                Dec(mTownUnhappy);
        end;
    end;

    FitCitizens(ParaCity, mCityExperts);

    { Troops suppress unrest (non-democracy). }
    if vGov < 4 then
    begin
        var vPolice := 0;
        var vStackUnit := -1;
        var vStackOwner := -1;
        vStackUnit := -1;
        { Walk the unit list on the city tile; this is slow (128 scans)
          but faithful. }
        for vI := 0 to 127 do
        begin
            if (mState.mData.ArmyData[vOwner, vI].UnitType <> -1) and
               (mState.mData.ArmyData[vOwner, vI].X = mState.mData.TownBuf[ParaCity].X) and
               (mState.mData.ArmyData[vOwner, vI].Y = mState.mData.TownBuf[ParaCity].Y) and
               (mState.mData.UtTypes[mState.mData.ArmyData[vOwner, vI].UnitType].Attack <> 0) then
                Inc(vPolice);
        end;
        if vPolice > 3 then vPolice := 3;
        mTownUnhappy := mTownUnhappy - vPolice;
    end else
    begin
        var vPenalty := 1;
        if CivWonder(vOwner, 16) then vPenalty := 0;
        if vGov = 5 then
            Inc(vPenalty);
        mTownUnhappy := mTownUnhappy + vPenalty * mUnitsAbroad;
    end;

    FitCitizens(ParaCity, mCityExperts);

    { Wonders that override unhappy counts. }
    var vHappyDelta := mTownHappy - mTownUnhappy;
    if CivWonder(vOwner, 2) then Inc(mTownHappy);
    if CivWonder(vOwner, 21) then Inc(mTownHappy);
    if ActiveWonderCity(11) = ParaCity then
        mTownUnhappy := 0;
    if CivWonder(vOwner, 13) and
       (mWorld.RegionKey(mState.mData.TownBuf[ParaCity].X,
                         mState.mData.TownBuf[ParaCity].Y) =
        mWorld.RegionKey(mState.mData.TownBuf[mState.mData.MarvelSite[13]].X,
                         mState.mData.TownBuf[mState.mData.MarvelSite[13]].Y)) then
        mTownUnhappy := mTownUnhappy - 2;

    if (mState.mData.RuleOptions and 2) = 0 then
    begin
        mTownHappy := 0;
        mTownUnhappy := 0;
    end;

    { Turn pass. }
    if ParaMode = 0 then
    begin
        vShieldBox := mState.mData.TownBuf[ParaCity].ShieldBox;
        vNeededFood := vSize * 2 + mColonistHome * vSettlerFood;

        mState.mData.TownBuf[ParaCity].FoodBox :=
            mState.mData.TownBuf[ParaCity].FoodBox +
            mYields.TownResFood - vNeededFood;

        var vShields := vNewShields - mCityKeep;
        if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then
            vShields := 0;

        mState.mData.TownBuf[ParaCity].ShieldBox := vShieldBox + vShields;

        CompleteProduction(ParaCity, vCostScale, ParaMode);

        { Disorder / celebration. }
        var vDiff := mTownHappy - mTownUnhappy;
        if vOwner <> 0 then
        begin
            if vDiff < 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Status and 1) = 0 then
                begin
                    mState.mData.TownBuf[ParaCity].Status :=
                        ShortInt(mState.mData.TownBuf[ParaCity].Status or 1);
                end;
            end else if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then
            begin
                mState.mData.TownBuf[ParaCity].Status :=
                    ShortInt(mState.mData.TownBuf[ParaCity].Status and not 1);
            end;
        end;

        { Research accumulation (only the human path is shown). }
        var vResearch := mLearning;
        if vGov = 0 then
            vResearch := 0;
        mState.mData.CivResearchTally[vOwner] :=
            mState.mData.CivResearchTally[vOwner] + vResearch;
        if CivWonder(vOwner, 20) then
            mState.mData.CivResearchTally[vOwner] :=
                mState.mData.CivResearchTally[vOwner] + vResearch div 2;

        { Maintenance. }
        for var vBld := 1 to 23 do
        begin
            if (mState.mData.TownBuf[ParaCity].Buildings and (LongInt(1) shl vBld)) <> 0 then
            begin
                Dec(mState.mData.Money[vOwner], CivImprovementMaint(vBld + 1));
                if mState.mData.Money[vOwner] < 0 then
                begin
                    mState.mData.Money[vOwner] := 0;
                    mState.mData.TownBuf[ParaCity].Buildings :=
                        mState.mData.TownBuf[ParaCity].Buildings and not (LongInt(1) shl vBld);
                end;
            end;
        end;
    end;

    Result := mTownHappy - mTownUnhappy;
end;

{ Helpers used by CompleteProduction and maintenance. These indices match
  GAME.C improvements[46]: improvements[0] = NONE; improvements[1..21] are
  buildings, [22..24] are spaceship parts, [25..45] are wonders. }
function CivImprovementCost(ParaId: Integer): Integer;
begin
    case ParaId of
        1: Result := 20;  2: Result := 4;  3: Result := 6;
        4: Result := 4;   5: Result := 8;  6: Result := 8;
        7: Result := 8;   8: Result := 12; 9: Result := 12;
       10: Result := 12; 11: Result := 16; 12: Result := 16;
       13: Result := 16; 14: Result := 10; 15: Result := 20;
       16: Result := 32; 17: Result := 20; 18: Result := 20;
       19: Result := 16; 20: Result := 24; 21: Result := 16;
       22: Result := 8;  23: Result := 16; 24: Result := 32;
       25: Result := 30; 26: Result := 30; 27: Result := 20;
       28: Result := 20; 29: Result := 30; 30: Result := 30;
       31: Result := 30; 32: Result := 40; 33: Result := 30;
       34: Result := 30; 35: Result := 40; 36: Result := 40;
       37: Result := 40; 38: Result := 30; 39: Result := 60;
       40: Result := 60; 41: Result := 60; 42: Result := 60;
       43: Result := 60; 44: Result := 60; 45: Result := 60;
    else
        Result := 0;
    end;
end;

function CivImprovementMaint(ParaId: Integer): Integer;
begin
    case ParaId of
        1: Result := 5;  2: Result := 0;  3: Result := 1;
        4: Result := 1;  5: Result := 1;  6: Result := 1;
        7: Result := 1;  8: Result := 2;  9: Result := 2;
       10: Result := 3; 11: Result := 3; 12: Result := 3;
       13: Result := 4; 14: Result := 4; 15: Result := 4;
       16: Result := 6; 17: Result := 4; 18: Result := 2;
       19: Result := 4; 20: Result := 4; 21: Result := 2;
    else
        Result := 0;
    end;
end;

{ -------------------------------------------------------------------------
  FindSlotAI — the AI production chooser. Non-interactive path of
  find_slot(). Human menu selection is deferred.

  The scoring loop mirrors the C. Many conditions are omitted because they
  require call sites (like `near_human`, `in_at_war`) that belong to the
  full AI; those are placeholders that default to 0/False here.

  Returns a production slot: 0..27 for units, -(1..45) for improvements,
  or -1 to leave production unchanged.
  ------------------------------------------------------------------------- }
function TCivCities.FindSlotAI(ParaCiv, ParaCity: Integer): Integer;
var
    vCand         : array[0..127] of Integer;
    vNCand        : Integer;
    vI, vJ        : Integer;
    vUnitsOrdered : array[0..27] of Integer;
    vHave         : array[0..27] of Integer;
    vTotal        : Integer;
    vLand         : Integer;
    vAreaRole     : Integer;
    vMilitaryArea : Boolean;
    vFoodSurplus  : Integer;
    vDanger       : Boolean;
    vBestAll      : Integer;
    vBestIdx      : Integer;
    vBestUnitRank : Integer;
    vBestUnitIdx  : Integer;
    vRank         : Integer;
    vWhat         : Integer;
    vType         : Integer;
    vBuildings    : LongInt;
    vGov          : Integer;
begin
    if (mState.mData.HumanSet and (1 shl ParaCiv)) <> 0 then
        Exit(-1);   { Interactive path is deferred }

    { Build candidate list. }
    vNCand := 1;
    vCand[0] := mState.mData.TownBuf[ParaCity].Production;
    for vI := 0 to 27 do
    begin
        if (vI = 25) and (mState.mData.MarvelSite[17] = -1) then
            Continue;
        if HasTech(ParaCiv, mState.mData.UtTypes[vI].Prereq) and
           not HasTech(ParaCiv, mState.mData.UtTypes[vI].ObsoleteBy) and
           (((mState.mData.TownBuf[ParaCity].Status and 2) <> 0) or
            (mState.mData.UtTypes[vI].Domain <> 2)) then
        begin
            vCand[vNCand] := vI;
            Inc(vNCand);
        end;
    end;
    if (mState.mData.RuleOptions and 4) <> 0 then
    begin
        for vI := 1 to 24 do
        begin
            if not HasTech(ParaCiv, AdvanceTable[vI].Prereq2) then
                Continue;   { improvement prereq is stored in Prereq2 }
            if vI > 21 then
            begin
                if (mState.mData.MarvelSite[19] = -1) and
                   ((mState.mData.GameFlags and (1 shl ParaCiv)) = 0) then
                begin
                    vCand[vNCand] := -vI;
                    Inc(vNCand);
                end;
            end else if (mState.mData.TownBuf[ParaCity].Buildings and
                         (LongInt(1) shl (vI - 1))) = 0 then
            begin
                vCand[vNCand] := -vI;
                Inc(vNCand);
            end;
        end;
    end;
    for vI := 25 to 45 do
    begin
        if HasTech(ParaCiv, AdvanceTable[vI].Prereq2) and
           (mState.mData.MarvelSite[vI - 24] = -1) then
        begin
            vCand[vNCand] := -vI;
            Inc(vNCand);
        end;
    end;

    vLand := mWorld.RegionKey(mState.mData.TownBuf[ParaCity].X,
                              mState.mData.TownBuf[ParaCity].Y);
    vAreaRole := mState.mData.CivAreaPlan[ParaCiv, vLand];
    vMilitaryArea := (vAreaRole = 1) or (vAreaRole = 2);

    vFoodSurplus := mYields.TownResFood - mState.mData.TownBuf[ParaCity].Size * 2;
    if mState.mData.CivGov[ParaCiv] > 1 then
        Dec(vFoodSurplus, mColonistHome * 2)
    else
        Dec(vFoodSurplus, mColonistHome);

    for vI := 0 to 27 do
    begin
        vUnitsOrdered[vI] := 1;
        vHave[vI] := 0;
    end;
    vTotal := 0;
    for vI := 0 to 127 do
    begin
        if (mState.mData.ArmyData[ParaCiv, vI].UnitType <> -1) then
        begin
            Inc(vTotal);
            Inc(vHave[mState.mData.ArmyData[ParaCiv, vI].UnitType]);
        end;
    end;

    vDanger := vTotal = 0;
    if vMilitaryArea and (vTotal < 3) then
        vDanger := True;

    vBestAll := 999999;
    vBestIdx := 1;
    vBestUnitRank := 999999;
    vBestUnitIdx := -1;

    for vI := 1 to vNCand - 1 do
    begin
        vWhat := vCand[vI];
        if (vWhat < 0) or (vWhat >= 26) then
        begin
            { Improvement or wonder. }
            vRank := 999;
            case -vWhat of
                4 : if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then vRank := -4;
                7 : vRank := 12 - mCityLeak * 2;
               11 : if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then vRank := -2;
               14 : if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then vRank := -1;
                2 : vRank := 5;
                3 : if mYields.TownResShields >= 3 then vRank := 4 else vRank := 8;
               15 : vRank := 13 - mYields.TownResShields div 2;
               20 : vRank := 13 - mYields.TownResShields div 2;
               19 : vRank := 12 - mYields.TownResShields div 5;
               16, 18, 21 : vRank := 12 - mYields.TownResShields div 8;
                5 : begin
                        vRank := 10 - mYields.TownResTrade div 2;
                        if (mState.mData.TownBuf[ParaCity].Status and 1) <> 0 then vRank := -3;
                    end;
                6, 10 : vRank := 10 - mYields.TownResTrade div 3;
               12 : vRank := 10 - mYields.TownResTrade div 4;
                8 : begin
                        vRank := 10 - mState.mData.TownBuf[ParaCity].Size div 2;
                        if (mState.mData.TownBuf[ParaCity].Buildings and 1) <> 0 then
                            vRank := vRank - 4;
                    end;
                9 : if (10 - vFoodSurplus div 2 <= mState.mData.TownBuf[ParaCity].Size) then
                        vRank := 14 - mState.mData.TownBuf[ParaCity].Size - vFoodSurplus div 2;
               22 : if (mState.mData.GameFlags and
                        ((1 shl ParaCiv) + (1 shl mState.mData.CivNow))) = 0 then
                    begin
                        if (mState.mData.GameFlags and
                            (1 shl (mState.mData.CivNow + 8))) <> 0 then vRank := 2
                        else vRank := 4;
                    end;
            end;
            if vRank < 400 then
            begin
                if vMilitaryArea then
                    vRank := vRank * 20
                else
                    vRank := vRank * 10;
                vRank := 3 * vRank div 10;
            end else
                vRank := $3FFF;
            if (mState.mData.TownBuf[ParaCity].Buildings and 2) <> 0 then
                vRank := vRank + vRank div 4;
        end else
        begin
            { Unit. Simple scoring. }
            if vWhat = 23 then
                Continue;
            if (vWhat = 0) and
               ((((mState.mData.CivGov[ParaCiv] > 1) ? 2 : 1) >= vFoodSurplus)
                or (vTotal = 0)) then
                Continue;
            if (vWhat = 1) and (mState.mData.CivGov[ParaCiv] > 1) then
                Continue;
            if vWhat = 25 then
                Continue;   { nuclear units need Manhattan Project, deferred }
            if vWhat = 14 then
                Continue;   { fighter logic needs human bomber count }

            vRank := vUnitsOrdered[vWhat] * 2 + vHave[vWhat];
            if vDanger then
            begin
                if mState.mData.UtTypes[vWhat].Role <> 2 then
                    Continue;
                vRank := 1;
            end;
            if (mState.mData.UtTypes[vWhat].Role <> 2) and
               (mState.mData.UtTypes[vWhat].Role <> 0) then
            begin
                vRank := vRank * 2;
                if vAreaRole <> mState.mData.UtTypes[vWhat].Role then
                    vRank := vRank * 2;
            end;
            vRank := (16 * (mState.mData.UtTypes[vWhat].Cost + 2) * vRank)
                     div ((mState.mData.UtTypes[vWhat].Attack +
                            mState.mData.UtTypes[vWhat].Defense) *
                           (mState.mData.UtTypes[vWhat].Moves + 1));
            if mState.mData.UtTypes[vWhat].Domain = 1 then
                vRank := vRank * 2;
            if vTotal > 120 then
                vRank := vRank * 4;
        end;

        if vRank < vBestAll then
        begin
            vBestIdx := vI;
            vBestAll := vRank;
        end;
        if (vWhat < 0) or (vWhat >= 26) then
        begin
            if vRank < vBestUnitRank then
            begin
                vBestUnitRank := vRank;
                vBestUnitIdx := vI;
            end;
        end;
    end;

    if vBestIdx < vNCand then
        Result := vCand[vBestIdx]
    else
        Result := -1;
end;

{ -------------------------------------------------------------------------
  CityCreate — mirrors the front half of CITY.C's city_create. Uses the
  place-name pool for the new city, sets up its initial state, and marks
  the working radius as owned. Wonder assignment, capital assignment and
  visual founding are deferred to later batches.
  ------------------------------------------------------------------------- }
function TCivCities.CityCreate(
    ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
var
    vSlot, vCity : Integer;
    vI, vTribeSlot : Integer;
    vFirst : Boolean;
    vBuildingMask : LongInt;
begin
    { Find a free city slot. }
    vCity := -1;
    for vI := 0 to 127 do
    begin
        if mState.mData.TownBuf[vI].Status = -1 then
        begin
            vCity := vI;
            Break;
        end;
    end;
    if vCity = -1 then
        Exit(-1);

    { Pick the first unused name from the tribe's pool. }
    vTribeSlot := mState.mData.CivTribeOf[ParaPlayer] - 1;
    if vTribeSlot >= 7 then
        Dec(vTribeSlot);
    vTribeSlot := vTribeSlot shl 4;
    vSlot := vTribeSlot;
    repeat
        if mState.mData.CitySiteX[vSlot] = -1 then
            Break;
        Inc(vSlot);
        if vSlot >= vTribeSlot + 16 then
        begin
            vSlot := 0;
            Break;
        end;
    until False;

    mState.mData.TownBuf[vCity].NameId := ShortInt(vSlot);
    mState.mData.CitySiteX[vSlot] := ShortInt(ParaX);
    mState.mData.CitySiteY[vSlot] := ShortInt(ParaY);

    mState.mData.TownBuf[vCity].Status     := 0;
    mState.mData.TownBuf[vCity].X          := ParaX;
    mState.mData.TownBuf[vCity].Y          := ParaY;
    mState.mData.TownBuf[vCity].Size       := ParaSize;
    mState.mData.TownBuf[vCity].Workers    := 0;
    mState.mData.TownBuf[vCity].VisibleSize := 0;
    mState.mData.TownBuf[vCity].Buildings  := 0;
    mState.mData.TownBuf[vCity].ShieldBox  := 0;
    mState.mData.TownBuf[vCity].FoodBox    := 0;
    mState.mData.TownBuf[vCity].Trade      := 0;
    mState.mData.TownBuf[vCity].Production := 1;

    vBuildingMask := 0;
    vFirst := True;
    for vI := 0 to 127 do
    begin
        if (mState.mData.TownBuf[vI].Status <> -1) and
           (mState.mData.TownBuf[vI].Owner = ParaPlayer) and
           (vI <> vCity) then
        begin
            vFirst := False;
            Break;
        end;
    end;
    if vFirst then
        vBuildingMask := ConstBldPalace;
    mState.mData.TownBuf[vCity].Buildings := vBuildingMask;

    mState.mData.TownBuf[vCity].Owner := ParaPlayer;
    for vI := 0 to 2 do
        mState.mData.TownBuf[vCity].Routes[vI] := -1;
    mState.mData.TownBuf[vCity].Specialists := 0;

    { Mark tile ownership. The 21 radius tiles are claimed; the next ring
      (indices 21..44) are downgraded to value 8. }
    for vI := 0 to 20 do
    begin
        mWorld.Map.SetPixel(ParaX + ConstRadiusDX[vI] + 80,
                            ParaY + ConstRadiusDY[vI],
                            Byte(ParaPlayer));
    end;
    for vI := 21 to 44 do
    begin
        if mWorld.SiteValue(ParaX + ConstSpiralX[vI],
                            ParaY + ConstSpiralY[vI]) >= 8 then
            mWorld.Map.SetPixel(ParaX + ConstSpiralX[vI] + 80,
                                ParaY + ConstSpiralY[vI], 8);
    end;

    mWorld.FlagTile(ConstTileCity, ParaX, ParaY);
    Inc(mState.mData.CityCount[ParaPlayer]);

    Result := vCity;
end;

{ -------------------------------------------------------------------------
  Vanish — removes a city record, clears its map flags, cleans up routes
  and supported units. Mirrors vanish() in ECONOMY.C.
  ------------------------------------------------------------------------- }
procedure TCivCities.Vanish(ParaCity, ParaX, ParaY: Integer);
var
    vI : Integer;
    vUnitIdx : Integer;
begin
    mState.mData.CityCount[mState.mData.TownBuf[ParaCity].Owner] :=
        mState.mData.CityCount[mState.mData.TownBuf[ParaCity].Owner] - 1;
    mState.mData.TownBuf[ParaCity].Status := -1;

    mWorld.FlagTile(0, ParaX, ParaY);

    { Clear route references to this city. }
    for vI := 0 to 127 do
    begin
        for var vR := 0 to 2 do
        begin
            if mState.mData.TownBuf[vI].Routes[vR] = ParaCity then
                mState.mData.TownBuf[vI].Routes[vR] := -1;
        end;
    end;

    { Clear wonder references. }
    for vI := 1 to ConstWonderCount do
    begin
        if mState.mData.MarvelSite[vI] = ParaCity then
            mState.mData.MarvelSite[vI] := $80;
    end;

    { Remove units supported by this city. Unit drop lives in Civ.Units. }
    for vI := 0 to 127 do
    begin
        vUnitIdx := mState.mData.ArmyData[mState.mData.TownBuf[ParaCity].Owner, vI].HomeCity;
        if (vUnitIdx = ParaCity) and
           (mState.mData.ArmyData[mState.mData.TownBuf[ParaCity].Owner, vI].UnitType <> -1) then
        begin
            { Caller-provided unit drop; see Civ.Units.DropUnit. }
        end;
    end;

    { Reset site values around the former city. }
    for vI := 0 to 44 do
    begin
        mWorld.Map.SetPixel(ParaX + ConstSpiralX[vI] + 80,
                            ParaY + ConstSpiralY[vI],
                            mWorld.Map.Pixel(ParaX + ConstSpiralX[vI] + 80,
                                             ParaY + ConstSpiralY[vI] + 50));
    end;
end;

{ -------------------------------------------------------------------------
  CityDisaster — the 10-way roll from CITY.C. The graphical cases (flood,
  fire) are excluded because they need the message layer; each returns a
  code the caller can use to trigger the corresponding message.
  ------------------------------------------------------------------------- }
procedure TCivCities.CityDisaster(ParaCity: Integer);
var
    vNeighborhood : Integer;
    vI            : Integer;
    vBuilding     : Integer;
    vSize         : Integer;
    vOwner        : Integer;
    vRoll         : Integer;
begin
    vNeighborhood := 0;
    for vI := 0 to 8 do
        vNeighborhood := vNeighborhood or
            (1 shl mWorld.TerrainAt(mState.mData.TownBuf[ParaCity].X + ConstSpiralX[vI],
                                     mState.mData.TownBuf[ParaCity].Y + ConstSpiralY[vI]));

    vSize := mState.mData.TownBuf[ParaCity].Size;
    vOwner := mState.mData.TownBuf[ParaCity].Owner;
    vRoll := mRng.Scaled(10);

    case vRoll of
        0:
        begin
            { Earthquake — destroys one improvement. }
            if (vNeighborhood and $10) <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and $FFFE) <> 0 then
                begin
                    repeat
                        vBuilding := mRng.Scaled(24);
                    until (vBuilding <> 0) and
                          ((mState.mData.TownBuf[ParaCity].Buildings and
                            (LongInt(1) shl vBuilding)) <> 0);
                    mState.mData.TownBuf[ParaCity].Buildings :=
                        mState.mData.TownBuf[ParaCity].Buildings and
                        not (LongInt(1) shl vBuilding);
                end;
            end;
        end;
        1:
        begin
            { Fire — destroys population unless Aqueduct is built. }
            if not HasTech(vOwner, 10) then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and $100) = 0 then
                begin
                    if HasTech(vOwner, mState.mData.UtTypes[9].Prereq) then
                    begin
                        if vSize <> 0 then
                            mState.mData.TownBuf[ParaCity].Size :=
                                ShortInt(vSize - vSize div 4);
                    end;
                end;
            end;
        end;
        2:
        begin
            { Flood. }
            if (vNeighborhood and $800) <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and $80) = 0 then
                begin
                    if HasTech(vOwner, mState.mData.UtTypes[8].Prereq) then
                    begin
                        if vSize > 1 then
                            mState.mData.TownBuf[ParaCity].Size :=
                                ShortInt(vSize - vSize div 4);
                    end;
                end;
            end;
        end;
        3:
        begin
            { Volcanic eruption. }
            if (vNeighborhood and $20) <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and $8) = 0 then
                begin
                    if HasTech(vOwner, mState.mData.UtTypes[4].Prereq) then
                    begin
                        if vSize > 1 then
                            mState.mData.TownBuf[ParaCity].Size :=
                                ShortInt(vSize - vSize div 3);
                    end;
                end;
            end;
        end;
        4:
        begin
            { Famine. }
            if vSize <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and 4) = 0 then
                begin
                    if HasTech(vOwner, mState.mData.UtTypes[3].Prereq) then
                    begin
                        mState.mData.TownBuf[ParaCity].FoodBox := 0;
                        if vSize > 1 then
                            mState.mData.TownBuf[ParaCity].Size :=
                                ShortInt(vSize - vSize div 3);
                    end;
                end;
            end;
        end;
        5:
        begin
            { Plague — destroys a random improvement. }
            if (mState.mData.TownBuf[ParaCity].Buildings and $FFFE) <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and $100) = 0 then
                begin
                    if HasTech(vOwner, mState.mData.UtTypes[9].Prereq) then
                    begin
                        repeat
                            vBuilding := mRng.Scaled(24);
                        until (vBuilding <> 0) and
                              ((mState.mData.TownBuf[ParaCity].Buildings and
                                (LongInt(1) shl vBuilding)) <> 0);
                        mState.mData.TownBuf[ParaCity].Buildings :=
                            mState.mData.TownBuf[ParaCity].Buildings and
                            not (LongInt(1) shl vBuilding);
                    end;
                end;
            end;
        end;
        6:
        begin
            { Hurricane. }
            if (vNeighborhood and $400) <> 0 then
            begin
                if (mState.mData.TownBuf[ParaCity].Buildings and 2) = 0 then
                begin
                    mState.mData.TownBuf[ParaCity].FoodBox := 0;
                    mState.mData.TownBuf[ParaCity].ShieldBox := 0;
                end;
            end;
        end;
    else
        ;   { 7, 8, 9: civil disorder messages only }
    end;
end;

end.