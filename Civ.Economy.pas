unit Civ.Economy;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.GameData,
    Civ.World,
    Civ.GameState,
    Civ.Cities;

type
    TCivEconomy = class
    private
        mWorld  : TCivWorld;
        mState  : TCivilizationGameState;
        mRng    : TCivRandom;
        mCities : TCivCities;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
                           ParaCities: TCivCities);

        procedure CivEconomy(ParaCiv: Integer);

        function HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
        function AdvanceValue(ParaCiv, ParaAdvance: Integer): Integer;

        { Chooses the best advance for an AI civ. Uses advance_value and the
          civ's trait. Human choice goes through the interactive path, which
          is deferred. }
        function PickAITech(ParaCiv: Integer): Integer;

        { Grants an advance. Mirrors give_advance(); the "message" and
          "pedia" side effects are left to callbacks. }
        procedure GiveAdvance(ParaCiv, ParaAdvance, ParaSource: Integer);

        { Simple damage model: reduce tech by n% for a conquered civ. Mirrors
          the steal_advance path without the interactive menu. }
        function StealAdvance(ParaCiv, ParaFromCiv: Integer): Integer;
    end;

implementation

constructor TCivEconomy.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaCities: TCivCities);
begin
    inherited Create;
    mWorld  := ParaWorld;
    mState  := ParaWorld.State;
    mRng    := ParaRng;
    mCities := ParaCities;
end;

{ -------------------------------------------------------------------------
  CivEconomy — per-civ turn pass. Mirrors civ_economy() in ECONOMY.C.
  Flags:
    bit 0: some city reported a happiness problem at size > 5
    bit 1: some city was in disorder after the pass
  The AI governor uses those to adjust science and tax rates.
  ------------------------------------------------------------------------- }
procedure TCivEconomy.CivEconomy(ParaCiv: Integer);
var
    vI, vRate, vFlags, vRateTotal : Integer;
    vSci, vToll, vRateSpare       : Integer;
    vHappy                        : Boolean;
begin
    vFlags := 0;
    for vI := 0 to 127 do
    begin
        if (mState.mData.TownBuf[vI].Status <> -1) and
           (mState.mData.TownBuf[vI].Owner = ParaCiv) then
        begin
            vHappy := mCities.CityProcess(vI, 0) > 0;
            if (not vHappy) and (mState.mData.TownBuf[vI].Size > 5) then
                vFlags := vFlags or 1;
            if (mState.mData.TownBuf[vI].Status and 1) <> 0 then
                vFlags := vFlags or 2;
        end;
    end;

    if (ParaCiv <> mState.mData.CivNow) and
       ((mState.mData.RuleOptions and 4) <> 0) then
    begin
        vRate := 10 - (mState.mData.Sci[ParaCiv] + mState.mData.CivToll[ParaCiv]);
        if ((vFlags and 2) <> 0) and
           (mState.mData.Sci[ParaCiv] + mState.mData.CivToll[ParaCiv] > 6) then
            Inc(vRate);
        if ((mState.mData.TurnTick and 3) = 0) and (vFlags = 0) and
           (mState.mData.CivToll[ParaCiv] + mState.mData.Sci[ParaCiv] < 8) then
            Dec(vRate);
        vRate := Clamp(vRate, 0, 4);

        { Base rate from the leader's "civilized" trait (f2) + tech. }
        vSci := CivLeaderF2(ParaCiv) + (10 - vRate) div 2;
        if mState.mData.Money[ParaCiv] > mState.mData.TurnTick + 100 then
            Inc(vSci);
        if HasTech(ParaCiv, 63) then
            vSci := 0;
        vToll := -(vSci + vRate - 10);
        mState.mData.Sci[ParaCiv] := SmallInt(vSci);
        mState.mData.CivToll[ParaCiv] := SmallInt(vToll);
    end;
end;

function HasTech(ParaCiv, ParaAdvance: Integer): Boolean; forward;

{ -------------------------------------------------------------------------
  HasTech / AdvanceValue / CivLeaderF2 — small helpers.
  ------------------------------------------------------------------------- }
function TCivEconomy.HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
    vBit  : SmallInt;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then
        Exit(False);
    vWord := ParaAdvance div 16;
    vBit  := SmallInt(1 shl (ParaAdvance mod 16));
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and vBit) <> 0;
end;

function CivLeaderF2(ParaCiv: Integer): Integer;
var
    vTribeSlot : Integer;
    vAttr      : Pointer;
begin
    vTribeSlot := mState.mData.CivTribeOf[ParaCiv] - 1;
    if vTribeSlot >= 7 then
        Dec(vTribeSlot);
    if (vTribeSlot < 0) or (vTribeSlot > 15) then
        Exit(0);
    { CivTable()[slot].F2 — the "civilized / militaristic" trait. }
    vAttr := Pointer(NativeInt(CivTable) + vTribeSlot * SizeOf(TCivType) + 52);
    Result := PSmallInt(vAttr)^;
end;

function TCivEconomy.AdvanceValue(ParaCiv, ParaAdvance: Integer): Integer;
var
    vF2, vA, vB : Integer;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then
        Exit(0);
    vF2 := CivLeaderF2(ParaCiv);
    vA  := Integer(AdvanceTable[ParaAdvance].Prereq1);  { packed: attribute a = prereq1 in the reconstruction }
    vB  := Integer(AdvanceTable[ParaAdvance].Prereq2);
    Result := vA + vF2 * vB;
end;

{ -------------------------------------------------------------------------
  PickAITech — mirrors reduce_attitude()'s AI path. Returns the index of the
  advance the AI should research next, or -1 if none available.
  ------------------------------------------------------------------------- }
function TCivEconomy.PickAITech(ParaCiv: Integer): Integer;
var
    vI, vRating, vBest : Integer;
    vBestIdx           : Integer;
begin
    vBest := -1;
    vBestIdx := -1;
    for vI := 0 to 71 do
    begin
        if not HasTech(ParaCiv, vI) and
           (AdvanceTable[vI].Prereq1 < 0) or
           ((AdvanceTable[vI].Prereq1 >= 0) and
            HasTech(ParaCiv, AdvanceTable[vI].Prereq1)) then
        begin
            if (AdvanceTable[vI].Prereq2 < 0) or
               HasTech(ParaCiv, AdvanceTable[vI].Prereq2) then
            begin
                vRating := mRng.Scaled(AdvanceValue(ParaCiv, vI) * 4);
                if vRating > vBest then
                begin
                    vBest := vRating;
                    vBestIdx := vI;
                end;
            end;
        end;
    end;
    Result := vBestIdx;
end;

{ -------------------------------------------------------------------------
  GiveAdvance — mirrors give_advance(). Sets the advance-known bit, updates
  the discovery count, applies the "obsolete Barracks" rule, handles the
  Great Library case, and posts a replay event.
  ------------------------------------------------------------------------- }
procedure TCivEconomy.GiveAdvance(ParaCiv, ParaAdvance, ParaSource: Integer);
var
    vWord, vI, vK : Integer;
    vBit          : SmallInt;
    vLibraryCiv   : Integer;
    vLibraryCity  : Integer;
    vHasTechCount : Integer;
begin
    if HasTech(ParaCiv, ParaAdvance) then
        Exit;

    if ParaAdvance <> 71 then
    begin
        vWord := ParaAdvance div 16;
        vBit  := SmallInt(1 shl (ParaAdvance mod 16));
        mState.mData.AdvancesKnown[ParaCiv, vWord] :=
            SmallInt(mState.mData.AdvancesKnown[ParaCiv, vWord] or vBit);
        mState.mData.AdvSource[ParaCiv, ParaAdvance] := ShortInt(ParaSource);
    end;

    if mState.mData.TurnTick = 0 then
        Exit;

    Inc(mState.mData.TechCount[ParaCiv]);

    { Obsolete Barracks. }
    if (ParaAdvance = 34) or (ParaAdvance = 37) then
    begin
        for vI := 0 to 127 do
        begin
            if (mState.mData.TownBuf[vI].Status <> -1) and
               (mState.mData.TownBuf[vI].Owner = ParaCiv) then
                mState.mData.TownBuf[vI].Buildings :=
                    mState.mData.TownBuf[vI].Buildings and not 2;
        end;
    end;

    { Great Library transfer: if another civ (the library holder) already
      had this advance, and one more civ does, copy it. }
    vLibraryCiv := mState.mData.MarvelSite[5];
    if vLibraryCiv <> -1 then
    begin
        if mState.mData.TownBuf[vLibraryCiv].Owner <> ParaCiv then
        begin
            if (mState.mData.AdvanceOwners[ParaAdvance] and 7) <> 0 then
            begin
                vHasTechCount := 0;
                for vK := 1 to 7 do
                begin
                    if HasTech(vK, ParaAdvance) then
                        Inc(vHasTechCount);
                end;
                if vHasTechCount >= 2 then
                    GiveAdvance(mState.mData.TownBuf[vLibraryCiv].Owner,
                                ParaAdvance, -2);
            end;
        end;
    end;

    { Record first discoverer. }
    if (mState.mData.AdvanceOwners[ParaAdvance] and 7) = 0 then
        mState.mData.AdvanceOwners[ParaAdvance] :=
            SmallInt(mState.mData.AdvanceOwners[ParaAdvance] or ParaCiv);
end;

{ -------------------------------------------------------------------------
  StealAdvance — the AI-side version of the "which tech should this civ
  take?" question. Returns the chosen advance index, or -1 if none.
  ------------------------------------------------------------------------- }
function TCivEconomy.StealAdvance(ParaCiv, ParaFromCiv: Integer): Integer;
var
    vI, vBest, vBestIdx : Integer;
begin
    vBest := -1;
    vBestIdx := -1;
    for vI := 0 to 71 do
    begin
        if HasTech(ParaFromCiv, vI) and not HasTech(ParaCiv, vI) then
        begin
            var vRating := AdvanceValue(ParaCiv, vI);
            if vRating > vBest then
            begin
                vBest := vRating;
                vBestIdx := vI;
            end;
        end;
    end;
    if vBestIdx <> -1 then
        GiveAdvance(ParaCiv, vBestIdx, ParaFromCiv);
    Result := vBestIdx;
end;

end.