unit Civ.NewGame;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.World,
    Civ.GameState,
    Civ.Tables,
    Civ.WorldGen,
    Civ.Cities,
    Civ.Units;

type
    TNewGameParams = record
        Difficulty  : Integer;
        NumCivs     : Integer;
        PlayerTribe : Integer;
        WorldParams : TWorldGenParams;
        ShowStory   : Boolean;
    end;

    TCivNewGame = class
    private
        mWorld  : TCivWorld;
        mState  : TCivilizationGameState;
        mRng    : TCivRandom;
        mGen    : TCivWorldGen;
        mCities : TCivCities;
        mUnits  : TCivUnitManager;
        function  HasTech(ParaCiv, ParaAdv: Integer): Boolean;
        procedure GiveAdvance(ParaCiv, ParaAdv, ParaSource: Integer);
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
                           ParaGen: TCivWorldGen;
                           ParaCities: TCivCities;
                           ParaUnits: TCivUnitManager);
        procedure Setup(ParaParams: TNewGameParams);
        function  InitCiv(ParaCiv: Integer): Boolean;
        procedure KillCiv(ParaCiv, ParaBy: Integer);
    end;

implementation

constructor TCivNewGame.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom;
    ParaGen: TCivWorldGen; ParaCities: TCivCities; ParaUnits: TCivUnitManager);
begin
    inherited Create;
    mWorld := ParaWorld; mState := ParaWorld.State; mRng := ParaRng;
    mGen := ParaGen; mCities := ParaCities; mUnits := ParaUnits;
end;

procedure TCivNewGame.Setup(ParaParams: TNewGameParams);
var
    vI, vPlayer : Integer;
begin
    mState.Clear;
    mState.mData.TurnTick := 0;
    mState.mData.Year := -4000;
    mState.mData.CurTier := ShortInt(ParaParams.Difficulty);
    mState.mData.CivTotal := ShortInt(ParaParams.NumCivs);
    mState.mData.Players := SmallInt(255 shr (6 - ParaParams.NumCivs));
    mState.mData.RuleOptions := 15;
    mState.mData.SelectedIndex := -1;
    mState.mData.NextEventTurn := 80;

    mGen.MakeWorld(ParaParams.WorldParams, ParaParams.ShowStory);

    if ParaParams.PlayerTribe = 0 then
        mState.mData.CivNow := ShortInt(mRng.Scaled(ParaParams.NumCivs) + 1)
    else if ParaParams.PlayerTribe > 7 then
        mState.mData.CivNow := ShortInt(ParaParams.PlayerTribe - 8)
    else mState.mData.CivNow := ShortInt(ParaParams.PlayerTribe);

    if ParaParams.PlayerTribe = 0 then
        mState.mData.CivTribeOf[mState.mData.CivNow] := mState.mData.CivNow
    else
        mState.mData.CivTribeOf[mState.mData.CivNow] := ParaParams.PlayerTribe;

    mState.mData.HumanSet := SmallInt(1 shl mState.mData.CivNow);
    for vI := 1 to ParaParams.NumCivs + 1 do
        InitCiv(vI);

    mState.mData.Sci[mState.mData.CivNow] := 5;
    mState.mData.CivToll[mState.mData.CivNow] := 5;
    if ParaParams.Difficulty = 0 then
        mState.mData.Money[mState.mData.CivNow] := 50;

    vPlayer := mState.mData.CivNow;
    for vI := 1 to ParaParams.NumCivs + 1 do
        if (vI <> vPlayer) and (mState.mData.CivTribeOf[vI] = 0) then
            mState.mData.CivTribeOf[vI] := vI;
end;

function TCivNewGame.HasTech(ParaCiv, ParaAdv: Integer): Boolean;
var
    vWord : Integer;
begin
    if (ParaAdv < 0) or (ParaAdv >= 72) then Exit(False);
    vWord := ParaAdv div 16;
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and
               SmallInt(1 shl (ParaAdv mod 16))) <> 0;
end;

procedure TCivNewGame.GiveAdvance(ParaCiv, ParaAdv, ParaSource: Integer);
var
    vWord : Integer;
begin
    if HasTech(ParaCiv, ParaAdv) then Exit;
    if ParaAdv <> 71 then
    begin
        vWord := ParaAdv div 16;
        mState.mData.AdvancesKnown[ParaCiv, vWord] :=
            SmallInt(mState.mData.AdvancesKnown[ParaCiv, vWord] or
                     SmallInt(1 shl (ParaAdv mod 16)));
        mState.mData.AdvSource[ParaCiv, ParaAdv] := ShortInt(ParaSource);
    end;
    if mState.mData.TurnTick <> 0 then
        Inc(mState.mData.TechCount[ParaCiv]);
end;

function TCivNewGame.InitCiv(ParaCiv: Integer): Boolean;
var
    vTribe, vX, vY, vI, vJ, vTrial, vOtherDist : Integer;
    vGood, vPosOK : Boolean;
begin
    if (ParaCiv = mState.mData.CivNow) and (mState.mData.TurnTick <> 0) then Exit(False);
    mState.mData.Money[ParaCiv] := 0;
    mState.mData.CivResearchTally[ParaCiv] := 0;
    mState.mData.TechCount[ParaCiv] := 0;
    mState.mData.CivGov[ParaCiv] := 1;
    mState.mData.CivToll[ParaCiv] := 4;
    mState.mData.Sci[ParaCiv] := 4;
    mState.mData.CityCount[ParaCiv] := 0;
    mState.mData.TroopsTotal[ParaCiv] := 0;
    mState.mData.CivHeldCells[ParaCiv] := 1;
    mState.mData.CivSettlersN[ParaCiv] := 1;
    mState.mData.LastMetTurn[ParaCiv] := -1;
    for vI := 0 to 71 do
        mState.mData.AdvSource[ParaCiv, vI] := -1;
    for vI := 0 to 127 do
    begin
        mState.mData.ArmyData[ParaCiv, vI].UnitType := -1;
        mState.mData.ArmyData[ParaCiv, vI].Status := 0;
    end;
    mState.mData.CivRatings[ParaCiv] := 0;
    for vI := 0 to 7 do
    begin
        mState.mData.Treaties[vI, ParaCiv] := 0;
        mState.mData.Treaties[ParaCiv, vI] := 0;
    end;
    for vI := 0 to 4 do
        mState.mData.AdvancesKnown[ParaCiv, vI] := 0;

    if (ParaCiv = 0) or ((mState.mData.Players and (1 shl ParaCiv)) = 0) then Exit(True);

    if ParaCiv <> mState.mData.CivNow then
    begin
        if mState.mData.TurnTick = 0 then
        begin
            vJ := 0;
            repeat
                vTribe := mRng.Scaled(16);
                vGood := ((vTribe and 7) = ParaCiv);
                for vI := 0 to 7 do
                    if (vI <> ParaCiv) and (mState.mData.CivTribeOf[vI] = vTribe) then
                        vGood := False;
                Inc(vJ);
            until vGood or (vJ >= 500);
            mState.mData.CivTribeOf[ParaCiv] := ShortInt(vTribe);
        end else
            mState.mData.CivTribeOf[ParaCiv] := ShortInt(mState.mData.CivTribeOf[ParaCiv] xor 8);
    end;

    vTrial := 0;
    repeat
        vX := mRng.Scaled(64) + 8;
        vY := mRng.Scaled(34) + 8;
        vOtherDist := 30;
        if mState.mData.TurnTick = 0 then
            for vJ := 1 to ParaCiv - 1 do
            begin
                var vDist := MapDist(vX, mState.mData.ArmyData[vJ, 0].X, vY, mState.mData.ArmyData[vJ, 0].Y);
                if vDist < vOtherDist then vOtherDist := vDist;
            end;
        vPosOK := (not mWorld.IsOcean(vX, vY)) and
                  (mWorld.SiteValue(vX, vY) >= 12 - vTrial div 32) and
                  (vOtherDist >= 10 - vTrial div 64) and
                  (mState.mData.AiZonePlaces[mWorld.RegionKey(vX, vY)] >=
                   32 - mState.mData.TurnTick div 16 - vTrial div 64) and
                  (not mWorld.HasHut(mWorld.TerrainAt(vX, vY), vX, vY));
        Inc(vTrial);
    until vPosOK or (vTrial > 2000);

    mState.mData.XCap[ParaCiv] := ShortInt(vX);
    if Assigned(mUnits) then
        mUnits.CreateUnit(ParaCiv, 0, vX, vY);
    if not HasTech(ParaCiv, 0) then
        GiveAdvance(ParaCiv, 0, ParaCiv);
    Result := True;
end;

procedure TCivNewGame.KillCiv(ParaCiv, ParaBy: Integer);
var
    vI : Integer;
begin
    if ParaCiv = 0 then Exit;
    if ParaCiv = mState.mData.CivNow then Exit;
    for vI := 0 to 127 do
        if (mState.mData.TownBuf[vI].Status <> -1) and
           (mState.mData.TownBuf[vI].Owner = ParaCiv) then Exit;
    for vI := 0 to 127 do
        if mState.mData.ArmyData[ParaCiv, vI].UnitType <> -1 then
            mUnits.DropUnit(ParaCiv, vI);
    mWorld.ClearExploration(ParaCiv);
    InitCiv(ParaCiv);
end;

end.