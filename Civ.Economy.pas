unit Civ.Economy;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.GameData,
    Civ.Tables,
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
        function PickAITech(ParaCiv: Integer): Integer;
        procedure GiveAdvance(ParaCiv, ParaAdvance, ParaSource: Integer);
        function StealAdvance(ParaCiv, ParaFromCiv: Integer): Integer;
    end;

implementation

constructor TCivEconomy.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaCities: TCivCities);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mRng := ParaRng;
    mCities := ParaCities;
end;

procedure TCivEconomy.CivEconomy(ParaCiv: Integer);
var
    vI, vRate, vFlags : Integer;
    vSci, vToll : Integer;
    vHappy : Boolean;
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

        vSci := TCivTables.LeaderF2(ParaCiv) + (10 - vRate) div 2;
        if mState.mData.Money[ParaCiv] > mState.mData.TurnTick + 100 then
            Inc(vSci);
        if HasTech(ParaCiv, 63) then
            vSci := 0;
        vToll := -(vSci + vRate - 10);
        mState.mData.Sci[ParaCiv] := SmallInt(vSci);
        mState.mData.CivToll[ParaCiv] := SmallInt(vToll);
    end;
end;

function TCivEconomy.HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then Exit(False);
    vWord := ParaAdvance div 16;
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and
               SmallInt(1 shl (ParaAdvance mod 16))) <> 0;
end;

function TCivEconomy.AdvanceValue(ParaCiv, ParaAdvance: Integer): Integer;
var
    vAttr : TAdvanceAttr;
begin
    vAttr := TCivTables.AdvanceAttr(ParaAdvance);
    Result := vAttr.A + TCivTables.LeaderF2(ParaCiv) * vAttr.B;
end;

function TCivEconomy.PickAITech(ParaCiv: Integer): Integer;
var
    vI, vRating, vBest, vBestIdx : Integer;
begin
    vBest := -1; vBestIdx := -1;
    for vI := 0 to 71 do
    begin
        if HasTech(ParaCiv, vI) then Continue;
        if (AdvanceEntryPrereq1(vI) >= 0) and (not HasTech(ParaCiv, AdvanceEntryPrereq1(vI))) then Continue;
        if (AdvanceEntryPrereq2(vI) >= 0) and (not HasTech(ParaCiv, AdvanceEntryPrereq2(vI))) then Continue;
        vRating := mRng.Scaled(AdvanceValue(ParaCiv, vI) * 4);
        if vRating > vBest then
        begin vBest := vRating; vBestIdx := vI; end;
    end;
    Result := vBestIdx;
end;

function AdvanceEntryPrereq1(ParaIndex: Integer): Integer;
begin
    if (ParaIndex < 0) or (ParaIndex > 71) then Exit(-1);
    Result := AdvanceTable[ParaIndex].Prereq1;
end;

function AdvanceEntryPrereq2(ParaIndex: Integer): Integer;
begin
    if (ParaIndex < 0) or (ParaIndex > 71) then Exit(-1);
    Result := AdvanceTable[ParaIndex].Prereq2;
end;

procedure TCivEconomy.GiveAdvance(ParaCiv, ParaAdvance, ParaSource: Integer);
var
    vWord : Integer;
    vBit  : SmallInt;
    vI : Integer;
begin
    if HasTech(ParaCiv, ParaAdvance) then Exit;
    if ParaAdvance <> 71 then
    begin
        vWord := ParaAdvance div 16;
        vBit  := SmallInt(1 shl (ParaAdvance mod 16));
        mState.mData.AdvancesKnown[ParaCiv, vWord] :=
            SmallInt(mState.mData.AdvancesKnown[ParaCiv, vWord] or vBit);
        mState.mData.AdvSource[ParaCiv, ParaAdvance] := ShortInt(ParaSource);
    end;
    if mState.mData.TurnTick = 0 then Exit;
    Inc(mState.mData.TechCount[ParaCiv]);

    if (ParaAdvance = 34) or (ParaAdvance = 37) then
    begin
        for vI := 0 to 127 do
            if (mState.mData.TownBuf[vI].Status <> -1) and
               (mState.mData.TownBuf[vI].Owner = ParaCiv) then
                mState.mData.TownBuf[vI].Buildings :=
                    mState.mData.TownBuf[vI].Buildings and not 2;
    end;

    if (mState.mData.AdvanceOwners[ParaAdvance] and 7) = 0 then
        mState.mData.AdvanceOwners[ParaAdvance] :=
            SmallInt(mState.mData.AdvanceOwners[ParaAdvance] or ParaCiv);
end;

function TCivEconomy.StealAdvance(ParaCiv, ParaFromCiv: Integer): Integer;
var
    vI, vBest, vBestIdx, vRating : Integer;
begin
    vBest := -1; vBestIdx := -1;
    for vI := 0 to 71 do
        if HasTech(ParaFromCiv, vI) and (not HasTech(ParaCiv, vI)) then
        begin
            vRating := AdvanceValue(ParaCiv, vI);
            if vRating > vBest then
            begin vBest := vRating; vBestIdx := vI; end;
        end;
    if vBestIdx <> -1 then
        GiveAdvance(ParaCiv, vBestIdx, ParaFromCiv);
    Result := vBestIdx;
end;

end.