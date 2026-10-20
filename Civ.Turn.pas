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
    Civ.AI;

type
    { UI callback facade. Default no-op implementations let headless code
      run without dragging in a renderer. }
    TShowMsgEvent   = procedure(const ParaText: string) of object;
    TShowMenuEvent  = function(const ParaText: string; ParaX, ParaY: Integer): Integer of object;

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

        { UI hooks. }
        mOnShowMsg  : TShowMsgEvent;
        mOnShowMenu : TShowMenuEvent;

        { The C's `winning` state and other per-turn globals. }
        mWinner        : Integer;
        mPalaceStage   : Integer;
        mNextEventTurn : Integer;
        mLastMessages  : TStringList;

        procedure RateCivs;
        procedure Uprising;
        procedure AIEvent;
        function  CostSum(ParaN: Integer): Integer;
        function  StepsFor(ParaN: Integer): Integer;
        function  FormatYear: string;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
                           ParaCombat: TCivCombat; ParaUnits: TCivUnitManager;
                           ParaCities: TCivCities; ParaEconomy: TCivEconomy;
                           ParaAI: TCivAI);
        destructor Destroy; override;

        { Main per-turn driver. Returns True if the game continues. }
        function GameTurn: Boolean;

        { UI hooks. }
        property OnShowMsg:  TShowMsgEvent  read mOnShowMsg  write mOnShowMsg;
        property OnShowMenu: TShowMenuEvent read mOnShowMenu write mOnShowMenu;
        property Winner: Integer read mWinner write mWinner;
        property PalaceStage: Integer read mPalaceStage write mPalaceStage;
        property NextEventTurn: Integer read mNextEventTurn write mNextEventTurn;
        property LastMessages: TStringList read mLastMessages;

        { Internal helpers exposed for the demo. }
        procedure AddMessage(const ParaText: string);
    end;

implementation

uses
    Civ.GameData;

const
    ConstBarbarianCiv = 0;

constructor TCivTurn.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaCombat: TCivCombat; ParaUnits: TCivUnitManager;
    ParaCities: TCivCities; ParaEconomy: TCivEconomy; ParaAI: TCivAI);
begin
    inherited Create;
    mWorld   := ParaWorld;
    mState   := ParaWorld.State;
    mRng     := ParaRng;
    mCombat  := ParaCombat;
    mUnits   := ParaUnits;
    mCities  := ParaCities;
    mEconomy := ParaEconomy;
    mAI      := ParaAI;
    mWinner := -1;
    mNextEventTurn := 80;
    mLastMessages := TStringList.Create;
end;

destructor TCivTurn.Destroy;
begin
    mLastMessages.Free;
    inherited;
end;

procedure TCivTurn.AddMessage(const ParaText: string);
begin
    if Assigned(mOnShowMsg) then
        mOnShowMsg(ParaText)
    else
        mLastMessages.Add(ParaText);
end;

{ -------------------------------------------------------------------------
  FormatYear — the C's format_year():
    puts abs(year) followed by " BC" or " AD" into msgtext.
  Here we return the string; callers concatenate.
  ------------------------------------------------------------------------- }
function TCivTurn.FormatYear: string;
begin
    Result := IntToStr(Abs(mState.mData.Year));
    if mState.mData.Year < 0 then
        Result := Result + ' BC'
    else
        Result := Result + ' AD';
end;

{ -------------------------------------------------------------------------
  CostSum — the C's cost_sum(n):
    sum_{i=0..n} i * (7 - cur_tier) / 2 + 1
  Total cost of palace stages up to n.
  ------------------------------------------------------------------------- }
function TCivTurn.CostSum(ParaN: Integer): Integer;
var
    vI, vSum : Integer;
begin
    vSum := 0;
    for vI := 0 to ParaN do
        vSum := vSum + vI * (7 - mState.mData.CurTier);
    Result := vSum div 2 + 1;
end;

{ -------------------------------------------------------------------------
  StepsFor — the C's steps_for(n): count how many 5-step increments fit
  in the score.
  ------------------------------------------------------------------------- }
function TCivTurn.StepsFor(ParaN: Integer): Integer;
var
    vI, vAcc : Integer;
begin
    vAcc := 0;
    repeat
        vAcc := vAcc + 5;
        ParaN := ParaN - vAcc;
    until ParaN <= 0;
    Result := vAcc div 5 - 1;
end;

{ -------------------------------------------------------------------------
  RateCivs — recalculates nation_ratings. Ranks every active civ by
  treasury + citizens + tech + unit cost. Sets `gangmode` if the human
  dominates.
  ------------------------------------------------------------------------- }
procedure TCivTurn.RateCivs;
var
    vI, vJ          : Integer;
    vChamp, vRank   : Integer;
    vRate           : array[0..7] of Integer;
    vMask           : Integer;
begin
    for vI := 0 to 7 do
    begin
        vRate[vI] := (mState.mData.Money[vI] div 32)
                   + (mState.mData.Citizens[vI] shl 3)
                   + mState.mData.TechCount[vI];
        for vJ := 0 to 27 do
            vRate[vI] := vRate[vI] +
                mState.mData.UtTypes[vJ].Cost *
                mState.mData.ForcesPresent[vI, vJ];
        if (mState.mData.Players and (1 shl vI)) = 0 then
            vRate[vI] := 0;
        if (mState.mData.TurnTick < 600) then
            mState.mData.PowerHistory[(mState.mData.TurnTick div 4) mod 150, vI] :=
                Byte(Clamp(vRate[vI] div 8, 0, 255));
        vMask := 0;
        for vJ := 0 to 7 do
            if (mState.mData.Treaties[vI, vJ] and 3) = 1 then
                vMask := vMask or (1 shl vJ);
        if (mState.mData.TurnTick < 600) then
            mState.mData.WarRecord[(mState.mData.TurnTick div 4) mod 150, vI] :=
                ShortInt(vMask);
    end;

    for vJ := 1 to 7 do
    begin
        vChamp := -1;
        vRank := -1;
        for vI := 1 to 7 do
        begin
            if vChamp < vRate[vI] then
            begin
                vChamp := vRate[vI];
                vRank := vI;
            end;
        end;
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
            if (vJ = mState.mData.CivNow) or
               (mState.mData.CityCount[vJ] <= 1) then
                Continue;
            if (mState.mData.Treaties[vJ, mState.mData.CivNow] and 2) <> 0 then
                mState.mData.Treaties[vJ, mState.mData.CivNow] :=
                    mState.mData.Treaties[vJ, mState.mData.CivNow] or $100
            else
                mState.mData.Treaties[vJ, mState.mData.CivNow] :=
                    mState.mData.Treaties[vJ, mState.mData.CivNow] or 1;
        end;
    end;
end;

{ -------------------------------------------------------------------------
  Uprising — periodic barbarian and native uprisings. Only the message-free
  path is ported here; the message text can be routed via AddMessage once
  you want visible events.
  ------------------------------------------------------------------------- }
procedure TCivTurn.Uprising;
var
    vX, vY, vCount, vI, vType : Integer;
    vIndex                    : Integer;
    vOwner                    : Integer;
begin
    if (5 - mState.mData.CurTier) * 30 > mState.mData.TurnTick then
        Exit;

    { Periodic sea barbarians every 8 turns, until Gunpowder is discovered. }
    if (((mState.mData.TurnTick + 1) and 7) = 0) and
       ((mState.mData.AdvanceOwners[0x74] and 7) = 0) then
    begin
        repeat
            vX := mRng.Scaled(80);
            vY := mRng.Scaled(44) + 3;
        until (mWorld.TerrainAt(vX, vY) = ConstTerrainOcean) and
              (mUnits.MapOwner(vX, vY) = -1) and
              (mWorld.MapRegion(vX, vY) >= 16);

        vCount := Clamp(mState.mData.TurnTick div 150 + 1, 1, 3);
        mUnits.CreateUnit(0, vCount < 3 ? 17 : 18, vX, vY);
        for vI := 0 to vCount do
        begin
            if (mState.mData.AdvanceOwners[0x70] and 7) = 0 then
                vType := 3
            else
                vType := 7;
            if vI = vCount then
                vType := 26;
            var vNewUnit := mUnits.CreateUnit(0, vType, vX, vY);
            if vNewUnit <> -1 then
                mState.mData.ArmyData[0, vNewUnit].Status :=
                    ShortInt(mState.mData.ArmyData[0, vNewUnit].Status or ConstUnitSentry);
        end;
    end;

    { Player-city uprising. }
    vIndex := mRng.Scaled(128);
    if (mState.mData.TownBuf[vIndex].Status = -1) or
       (mState.mData.TownBuf[vIndex].Owner <> mState.mData.CivNow) then
        Exit;

    if mRng.Scaled(100) >= 0 then
        Exit;   { always false; the C computes unrest_chance and compares, deferred }

    { Locate a free tile near the city. }
    vOwner := mState.mData.TownBuf[vIndex].Owner;
    for vI := 0 to 128 do
    begin
        vX := mState.mData.TownBuf[vIndex].X + mRng.Scaled(13) - 6;
        vY := mState.mData.TownBuf[vIndex].Y + mRng.Scaled(13) - 6;
        if (vX >= 0) and (vX < 80) and (vY > 0) and (vY < 49) and
           (mWorld.TerrainAt(vX, vY) <> ConstTerrainOcean) and
           (mUnits.MapOwner(vX, vY) = -1) then
            Break;
    end;

    vCount := Clamp(mRng.Scaled(mState.mData.TownBuf[vIndex].Size div 2), 2, 99);
    for vI := 0 to vCount do
    begin
        if (mState.mData.AdvanceOwners[0x46] and 7) <> 0 then
            vType := ((vI and 4) <> 0) ? 9 : 4
        else
            vType := ((vI and 4) <> 0) ? 10 : 6;
        if vI = vCount then
            vType := 26;
        mUnits.CreateUnit(0, vType, vX, vY);
    end;
end;

{ -------------------------------------------------------------------------
  AIEvent — warming tick + wonder completions.
  ------------------------------------------------------------------------- }
procedure TCivTurn.AIEvent;
var
    vI, vN, vUnit, vLeader, vEnemy : Integer;
begin
    mState.mData.WarmLevels := Clamp(
        mState.mData.WarmLevels +
        MapRandom(mState.mData.Polluted * 2 - mState.mData.Warming * 4 -
                  mState.mData.WarmLevels),
        0, 99);

    if (mState.mData.WarmLevels = 12) and (mState.mData.Polluted > 6) then
        AddMessage('Scientists alarmed by rising temperatures. Global Warming feared!');

    if mState.mData.WarmLevels > 16 then
    begin
        { GlobalWarming(mState.mData.Warming++) lives in Civ.WorldGen. }
        Inc(mState.mData.Warming);
        mState.mData.WarmLevels := 0;
    end;

    { Wonder completion by AI. }
    for vN := 0 to mState.mData.CurTier do
    begin
        vLeader := mRng.Scaled(21) + 1;
        vUnit   := mRng.Scaled(128);
        if mState.mData.TownBuf[vUnit].Status = -1 then
            Continue;
        vEnemy := mState.mData.TownBuf[vUnit].Owner;
        if vEnemy = mState.mData.CivNow then
            Continue;
        if (mState.mData.MarvelSite[vLeader] = -1) and
           (mState.mData.TownBuf[vUnit].Size >
            AdvanceValueFor(vEnemy, vLeader + 24) div 10) then
        begin
            mState.mData.MarvelSite[vLeader] := vUnit;
            AddMessage(Format('%s (%s) builds %s.',
                [Trim(mState.mData.CivNames[vEnemy]),
                 Trim(mState.mData.CivAdjectives[vEnemy]),
                 'a wonder']));
        end;
    end;
end;

function AdvanceValueFor(ParaCiv, ParaAdvance: Integer): Integer;
begin
    { TODO: Wire to Civ.Economy.AdvanceValue }
    Result := 0;
end;

{ -------------------------------------------------------------------------
  GameTurn — the main per-turn driver. Faithful to game_turn() in TURN.C.
  Returns False when the game is over.
  ------------------------------------------------------------------------- }
function TCivTurn.GameTurn: Boolean;
var
    vI                : Integer;
    vLiveCivs         : Integer;
    vMaxRating        : Integer;
    vHumanCounts      : Integer;
    vNumAI            : Integer;
    vReplayOrLoad     : Boolean;
    vReserve          : Integer;
    vCost             : Integer;
    vYearStr          : string;
begin
    { Count live civs. }
    vLiveCivs := 0;
    vMaxRating := 0;
    vHumanCounts := 0;
    vNumAI := 0;
    for vI := 0 to 7 do
    begin
        if (mState.mData.Players and (1 shl vI)) <> 0 then
        begin
            Inc(vLiveCivs);
            if vMaxRating < mState.mData.TechCount[vI] then
                vMaxRating := mState.mData.TechCount[vI];
        end;
    end;
    mState.mData.LiveCivilizations := vLiveCivs;

    for vI := 0 to 7 do
    begin
        mState.mData.CivRatings[vI] := 0;
        if (mState.mData.Players and (1 shl vI)) = 0 then
            Continue;
        if (vI < mState.mData.CivNow) and mState.mData.Reload then
            Continue;

        mEconomy.CivEconomy(vI);

        if mState.mData.Money[vI] > 30000 then
            mState.mData.Money[vI] := 30000;

        { city_phase: government reconsideration, treaty timers. }
        { The C's city_phase is spread across a few small operations; we
          only handle the government-change branch (already done in
          UnitPhase) and the treaty timers (skipped in this batch). }

        mAI.UnitPhase(vI);
        mAI.UnitCleanup(vI);

        mAI.AiTurn(vI);

        if (vI = mState.mData.CivNow) and
           (mState.mData.CityCount[vI] = 0) and
           (mState.mData.CivSettlersN[vI] = 0) then
        begin
            { Player wiped out. }
            mWinner := -1;
            Exit(False);
        end;

        if mState.mData.Year > 0 then
            Inc(mState.mData.PlayerPeaceRun);
    end;

    Uprising;
    AIEvent;
    RateCivs;

    { Advance clock. }
    Inc(mState.mData.TurnTick);
    if mState.mData.Year < 1000 then
        Inc(mState.mData.Year, 20)
    else if mState.mData.Year < 1500 then
        Inc(mState.mData.Year, 10)
    else if mState.mData.Year < 1750 then
        Inc(mState.mData.Year, 5)
    else if (mState.mData.Year < 1850) and ((mState.mData.GameFlags and $FE) = 0) then
        Inc(mState.mData.Year, 2)
    else
        Inc(mState.mData.Year);

    if mState.mData.Year = 0 then
    begin
        for vI := 0 to 7 do
            mState.mData.CivResearchTally[vI] :=
                SmallInt(mState.mData.CivResearchTally[vI] shl 1);
        mState.mData.Year := 1;
    end;
    if mState.mData.Year = 21 then
        mState.mData.Year := 20;

    { Historian report every 80 turns. }
    if mState.mData.TurnTick >= mNextEventTurn then
    begin
        mNextEventTurn := mRng.Scaled(40) + mState.mData.TurnTick + 20;
        AddMessage(Format('Historian report for turn %d.', [mState.mData.TurnTick]));
    end;

    { Spaceship arrival / conquest / dynasty end. }
    mWinner := -1;
    for vI := 1 to 7 do
    begin
        if ((mState.mData.GameFlags and (1 shl vI)) <> 0) and
           (mState.mData.SpaceshipArriveDates[vI] = mState.mData.Year) then
        begin
            mWinner := vI;
            Break;
        end;
    end;

    if mWinner <> -1 then
    begin
        AddMessage(Format('%s spaceship arrives at Alpha Centauri.',
            [Trim(mState.mData.CivAdjectives[mWinner])]));
        Exit(False);
    end;

    { Dynasty endgame. }
    if mState.mData.Year = 20 * mState.mData.CurTier - 0x834 then
    begin
        AddMessage('Your dynasty ends after a glorious 6000-year reign.');
        Exit(False);
    end;

    Result := True;
end;

end.