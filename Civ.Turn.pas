unit Civ.Turn;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes,
    Civ.Types,
    Civ.Core,
    Civ.World,
    Civ.GameState,
    Civ.Combat,
    Civ.Units,
    Civ.Cities,
    Civ.Economy,
    Civ.AI,
    Civ.Diplomacy;

type
    TShowMsgEvent = procedure(const ParaText: string) of object;

    TCivTurn = class
    private
        mWorld   : TCivWorld;
        mState   : TCivilizationGameState;
        mRng     : TCivRandom;
        mCombat  : TCivCombat;
        mUnits   : TCivUnitManager;
        mCities  : TCivCities;
        mEconomy : TCivEconomy;
        mAI      : TCivAI;
        mDiplo   : TCivDiplomacy;

        mWinner        : Integer;
        mPalaceStage   : Integer;
        mNextEventTurn : Integer;
        mMessages      : TStringList;

        mOnShowMsg : TShowMsgEvent;

        procedure RateCivs;
        procedure Uprising;
        procedure AIEvent;
        procedure AddMessage(const ParaText: string);
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
                           ParaCombat: TCivCombat; ParaUnits: TCivUnitManager;
                           ParaCities: TCivCities; ParaEconomy: TCivEconomy;
                           ParaAI: TCivAI; ParaDiplomacy: TCivDiplomacy);
        destructor Destroy; override;

        function  GameTurn: Boolean;

        property  OnShowMsg: TShowMsgEvent read mOnShowMsg write mOnShowMsg;
        property  Winner: Integer read mWinner write mWinner;
        property  PalaceStage: Integer read mPalaceStage write mPalaceStage;
        property  NextEventTurn: Integer read mNextEventTurn write mNextEventTurn;
        property  LastMessages: TStringList read mMessages;
    end;

implementation

constructor TCivTurn.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaCombat: TCivCombat; ParaUnits: TCivUnitManager;
    ParaCities: TCivCities; ParaEconomy: TCivEconomy;
    ParaAI: TCivAI; ParaDiplomacy: TCivDiplomacy);
begin
    inherited Create;
    mWorld := ParaWorld; mState := ParaWorld.State; mRng := ParaRng;
    mCombat := ParaCombat; mUnits := ParaUnits; mCities := ParaCities;
    mEconomy := ParaEconomy; mAI := ParaAI; mDiplo := ParaDiplomacy;
    mWinner := -1; mNextEventTurn := 80;
    mMessages := TStringList.Create;
end;

destructor TCivTurn.Destroy;
begin
    mMessages.Free;
    inherited;
end;

procedure TCivTurn.AddMessage(const ParaText: string);
begin
    if Assigned(mOnShowMsg) then mOnShowMsg(ParaText)
    else mMessages.Add(ParaText);
end;

procedure TCivTurn.RateCivs;
var
    vI, vJ, vChamp, vRank, vMask : Integer;
    vRate : array[0..7] of Integer;
begin
    for vI := 0 to 7 do
    begin
        vRate[vI] := mState.mData.Money[vI] div 32 + (mState.mData.Citizens[vI] shl 3) + mState.mData.TechCount[vI];
        for vJ := 0 to 27 do
            Inc(vRate[vI], mState.mData.UtTypes[vJ].Cost * mState.mData.ForcesPresent[vI, vJ]);
        if (mState.mData.Players and (1 shl vI)) = 0 then vRate[vI] := 0;
        if mState.mData.TurnTick < 600 then
            mState.mData.PowerHistory[(mState.mData.TurnTick div 4) mod 150, vI] :=
                Byte(Clamp(vRate[vI] div 8, 0, 255));
        vMask := 0;
        for vJ := 0 to 7 do
            if (mState.mData.Treaties[vI, vJ] and 3) = 1 then vMask := vMask or (1 shl vJ);
        if mState.mData.TurnTick < 600 then
            mState.mData.WarRecord[(mState.mData.TurnTick div 4) mod 150, vI] := ShortInt(vMask);
    end;
    for vJ := 1 to 7 do
    begin
        vChamp := -1; vRank := -1;
        for vI := 1 to 7 do
            if vChamp < vRate[vI] then begin vChamp := vRate[vI]; vRank := vI; end;
        if vRank <> -1 then
        begin
            mState.mData.NationRatings[vRank] := 8 - vJ;
            vRate[vRank] := -1;
        end;
    end;
    mState.mData.Gangmode := 0;
    if (mState.mData.NationRatings[mState.mData.CivNow] = 7) and
       (mState.mData.CityCount[mState.mData.CivNow] > 4) and
       (mState.mData.ForcesPresent[mState.mData.CivNow, 25] = 0) and
       (mState.mData.TurnTick > 200) then
    begin
        mState.mData.Gangmode := 1;
        for vJ := 1 to 7 do
        begin
            if (vJ = mState.mData.CivNow) or (mState.mData.CityCount[vJ] <= 1) then Continue;
            if (mState.mData.Treaties[vJ, mState.mData.CivNow] and 2) <> 0 then
                mState.mData.Treaties[vJ, mState.mData.CivNow] :=
                    mState.mData.Treaties[vJ, mState.mData.CivNow] or $100
            else
                mState.mData.Treaties[vJ, mState.mData.CivNow] :=
                    mState.mData.Treaties[vJ, mState.mData.CivNow] or 1;
        end;
    end;
end;

procedure TCivTurn.Uprising;
var
    vX, vY, vCount, vI, vType : Integer;
    vIndex : Integer;
    vNewUnit : Integer;
begin
    if (5 - mState.mData.CurTier) * 30 > mState.mData.TurnTick then Exit;
    if (((mState.mData.TurnTick + 1) and 7) = 0) and ((mState.mData.AdvanceOwners[$74] and 7) = 0) then
    begin
        repeat
            vX := mRng.Scaled(80); vY := mRng.Scaled(44) + 3;
        until mWorld.IsOcean(vX, vY) and (mWorld.MapOwner(vX, vY) = -1);
        vCount := Clamp(mState.mData.TurnTick div 150 + 1, 1, 3);
        mUnits.CreateUnit(0, vCount < 3 ? 17 : 18, vX, vY);
        for vI := 0 to vCount do
        begin
            if (mState.mData.AdvanceOwners[$70] and 7) = 0 then vType := 3 else vType := 7;
            if vI = vCount then vType := 26;
            vNewUnit := mUnits.CreateUnit(0, vType, vX, vY);
            if vNewUnit <> -1 then
                mState.mData.ArmyData[0, vNewUnit].Status :=
                    ShortInt(mState.mData.ArmyData[0, vNewUnit].Status or ConstUnitSentry);
        end;
    end;
    vIndex := mRng.Scaled(128);
    if (mState.mData.TownBuf[vIndex].Status = -1) or
       (mState.mData.TownBuf[vIndex].Owner <> mState.mData.CivNow) then Exit;
    for vI := 0 to 128 do
    begin
        vX := mState.mData.TownBuf[vIndex].X + mRng.Scaled(13) - 6;
        vY := mState.mData.TownBuf[vIndex].Y + mRng.Scaled(13) - 6;
        if MapInBounds(vX, vY) and (not mWorld.IsOcean(vX, vY)) and (mWorld.MapOwner(vX, vY) = -1) then Break;
    end;
    vCount := Clamp(mRng.Scaled(mState.mData.TownBuf[vIndex].Size div 2), 2, 99);
    for vI := 0 to vCount do
    begin
        if (mState.mData.AdvanceOwners[$46] and 7) <> 0 then
            vType := ((vI and 4) <> 0) ? 9 : 4
        else vType := ((vI and 4) <> 0) ? 10 : 6;
        if vI = vCount then vType := 26;
        mUnits.CreateUnit(0, vType, vX, vY);
    end;
end;

procedure TCivTurn.AIEvent;
var
    vN, vLeader, vUnit, vEnemy : Integer;
begin
    mState.mData.WarmLevels := Clamp(mState.mData.WarmLevels +
        MapRandom(mState.mData.Polluted * 2 - mState.mData.Warming * 4 - mState.mData.WarmLevels), 0, 99);
    if (mState.mData.WarmLevels = 12) and (mState.mData.Polluted > 6) then
        AddMessage('Scientists alarmed by rising temperatures. Global Warming feared!');
    if mState.mData.WarmLevels > 16 then
    begin
        Inc(mState.mData.Warming);
        mState.mData.WarmLevels := 0;
    end;
    for vN := 0 to mState.mData.CurTier do
    begin
        vLeader := mRng.Scaled(21) + 1;
        vUnit := mRng.Scaled(128);
        if mState.mData.TownBuf[vUnit].Status = -1 then Continue;
        vEnemy := mState.mData.TownBuf[vUnit].Owner;
        if vEnemy = mState.mData.CivNow then Continue;
        if (mState.mData.MarvelSite[vLeader] = -1) and
           (mState.mData.TownBuf[vUnit].Size >
            mEconomy.AdvanceValue(vEnemy, vLeader + 24) div 10) then
        begin
            mState.mData.MarvelSite[vLeader] := vUnit;
            AddMessage(Format('%s builds a wonder.',
                [Trim(mState.mData.CivNames[vEnemy])]));
        end;
    end;
end;

function TCivTurn.GameTurn: Boolean;
var
    vI, vLiveCivs, vMaxRating, vHumanCounts, vNumAI : Integer;
begin
    vLiveCivs := 0; vMaxRating := 0; vHumanCounts := 0; vNumAI := 0;
    for vI := 0 to 7 do
        if (mState.mData.Players and (1 shl vI)) <> 0 then
        begin
            Inc(vLiveCivs);
            if vMaxRating < mState.mData.TechCount[vI] then
                vMaxRating := mState.mData.TechCount[vI];
        end;
    mState.mData.LiveCivilizations := vLiveCivs;

    for vI := 0 to 7 do
    begin
        mState.mData.CivRatings[vI] := 0;
        if (mState.mData.Players and (1 shl vI)) = 0 then Continue;
        if (vI < mState.mData.CivNow) and mState.mData.Reload then Continue;

        mEconomy.CivEconomy(vI);
        mDiplo.CityPhase(vI);
        mAI.UnitPhase(vI);
        mAI.UnitCleanup(vI);
        mAI.AiTurn(vI);

        if (vI = mState.mData.CivNow) and
           (mState.mData.CityCount[vI] = 0) and
           (mState.mData.CivSettlersN[vI] = 0) then
        begin
            mWinner := -1;
            Exit(False);
        end;
        if mState.mData.Year > 0 then Inc(mState.mData.PlayerPeaceRun);
    end;

    Uprising;
    AIEvent;
    RateCivs;

    Inc(mState.mData.TurnTick);
    if mState.mData.Year < 1000 then Inc(mState.mData.Year, 20)
    else if mState.mData.Year < 1500 then Inc(mState.mData.Year, 10)
    else if mState.mData.Year < 1750 then Inc(mState.mData.Year, 5)
    else if (mState.mData.Year < 1850) and ((mState.mData.GameFlags and $FE) = 0) then
        Inc(mState.mData.Year, 2)
    else Inc(mState.mData.Year);
    if mState.mData.Year = 0 then
    begin
        for vI := 0 to 7 do
            mState.mData.CivResearchTally[vI] := SmallInt(mState.mData.CivResearchTally[vI] shl 1);
        mState.mData.Year := 1;
    end;
    if mState.mData.Year = 21 then mState.mData.Year := 20;

    if mState.mData.TurnTick >= mNextEventTurn then
    begin
        mNextEventTurn := mRng.Scaled(40) + mState.mData.TurnTick + 20;
        AddMessage(Format('Historian report for turn %d.', [mState.mData.TurnTick]));
    end;

    mWinner := -1;
    for vI := 1 to 7 do
        if ((mState.mData.GameFlags and (1 shl vI)) <> 0) and
           (mState.mData.SpaceshipArriveDates[vI] = mState.mData.Year) then
        begin mWinner := vI; Break; end;
    if mWinner <> -1 then
    begin
        AddMessage(Format('%s spaceship arrives at Alpha Centauri.',
            [Trim(mState.mData.CivAdjectives[mWinner])]));
        Exit(False);
    end;
    if mState.mData.Year = 20 * mState.mData.CurTier - $834 then
    begin
        AddMessage('Your dynasty ends.');
        Exit(False);
    end;
    Result := True;
end;

end.