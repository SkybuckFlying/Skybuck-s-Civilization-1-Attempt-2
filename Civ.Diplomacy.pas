unit Civ.Diplomacy;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    Civ.Types,
    Civ.Core,
    Civ.World,
    Civ.GameState,
    Civ.Tables;

type
    TCivDiplomacy = class
    private
        mWorld : TCivWorld;
        mState : TCivilizationGameState;
        mRng   : TCivRandom;
        function  CivWonderActive(ParaCiv, ParaWonder: Integer): Boolean;
        function  HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
        function  LeaderF0(ParaCiv: Integer): Integer;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);

        procedure RelationSet(ParaCivA, ParaCivB, ParaFlag: Integer);
        procedure Accord(ParaCivA, ParaCivB, ParaFlag: Integer);
        procedure SetGovernment(ParaCiv, ParaGov: Integer);
        procedure CityPhase(ParaCiv: Integer);
        function  DiplomacyEvent(ParaCivA, ParaCivB, ParaX, ParaY: Integer): Integer;
        function  AllianceOk(ParaCivA, ParaCivB: Integer): Boolean;
        function  TradeAdvances(ParaCivA, ParaCivB: Integer): Boolean;
        function  NearestUnitDistance(ParaCiv, ParaX, ParaY: Integer): Integer;
        function  ScoreOf(ParaCiv, ParaContinent, ParaAgainst: Integer): Integer;
        function  ValueOf(ParaCiv, ParaContinent: Integer): Integer;
        function  PowerOf(ParaCiv: Integer): Integer;
    end;

implementation

constructor TCivDiplomacy.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mRng := ParaRng;
end;

function TCivDiplomacy.HasTech(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then Exit(False);
    vWord := ParaAdvance div 16;
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and
               SmallInt(1 shl (ParaAdvance mod 16))) <> 0;
end;

function TCivDiplomacy.CivWonderActive(ParaCiv, ParaWonder: Integer): Boolean;
var
    vCity : Integer;
begin
    if mState.mData.MarvelSite[ParaWonder] = -1 then Exit(False);
    vCity := mState.mData.MarvelSite[ParaWonder];
    Result := mState.mData.TownBuf[vCity].Owner = ParaCiv;
end;

function TCivDiplomacy.LeaderF0(ParaCiv: Integer): Integer;
begin
    Result := TCivTables.LeaderF0(ParaCiv);
end;

procedure TCivDiplomacy.RelationSet(ParaCivA, ParaCivB, ParaFlag: Integer);
begin
    mState.mData.Treaties[ParaCivA, ParaCivB] := mState.mData.Treaties[ParaCivA, ParaCivB] or ParaFlag;
    mState.mData.Treaties[ParaCivB, ParaCivA] := mState.mData.Treaties[ParaCivB, ParaCivA] or ParaFlag;
    if ParaFlag = 2 then
    begin
        mState.mData.Treaties[ParaCivA, ParaCivB] := mState.mData.Treaties[ParaCivA, ParaCivB] and not $20;
        mState.mData.Treaties[ParaCivB, ParaCivA] := mState.mData.Treaties[ParaCivB, ParaCivA] and not $20;
    end;
end;

procedure TCivDiplomacy.Accord(ParaCivA, ParaCivB, ParaFlag: Integer);
begin
    mState.mData.Treaties[ParaCivA, ParaCivB] := mState.mData.Treaties[ParaCivA, ParaCivB] and not ParaFlag;
    mState.mData.Treaties[ParaCivB, ParaCivA] := mState.mData.Treaties[ParaCivB, ParaCivA] and not ParaFlag;
    if (ParaFlag and 2) <> 0 then
    begin
        mState.mData.Treaties[ParaCivA, ParaCivB] := mState.mData.Treaties[ParaCivA, ParaCivB] and not 4;
        mState.mData.Treaties[ParaCivB, ParaCivA] := mState.mData.Treaties[ParaCivB, ParaCivA] and not 4;
    end;
end;

procedure TCivDiplomacy.SetGovernment(ParaCiv, ParaGov: Integer);
var
    vOg, vI : Integer;
begin
    vOg := mState.mData.CivGov[ParaCiv];
    mState.mData.CivGov[ParaCiv] := ShortInt(ParaGov);
    if (mState.mData.HumanSet and (1 shl ParaCiv)) = 0 then
        mState.mData.CivToll[ParaCiv] := ShortInt(4 - ParaGov div 2);
    if vOg <> mState.mData.CivGov[ParaCiv] then
        for vI := 0 to 7 do
            mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] and not 8;
end;

procedure TCivDiplomacy.CityPhase(ParaCiv: Integer);
var
    vI, vFlags : Integer;
begin
    if mState.mData.CivGov[ParaCiv] = 0 then
    begin
        if (ParaCiv = mState.mData.CivNow) and ((mState.mData.TurnTick and 3) = 0) then
        begin
            if (mState.mData.Treaties[ParaCiv, 0] and 4) <> 0 then
                mState.mData.Treaties[ParaCiv, 0] := mState.mData.Treaties[ParaCiv, 0] and not 4
            else SetGovernment(ParaCiv, 1);
        end else if ((mState.mData.TurnTick and 3) = 0) or CivWonderActive(ParaCiv, 1) then
        begin
            SetGovernment(ParaCiv, 1);
            if ParaCiv = mState.mData.CivNow then
                mState.mData.Treaties[ParaCiv, 0] := mState.mData.Treaties[ParaCiv, 0] and not 4;
        end;
    end;
    if (ParaCiv <> mState.mData.CivNow) and
       ((mState.mData.Treaties[ParaCiv, 0] and 4) <> 0) then
        SetGovernment(ParaCiv, mState.mData.CivGov[ParaCiv]);
    for vI := 1 to 7 do
    begin
        if (mState.mData.Treaties[ParaCiv, vI] and $100) <> 0 then
            if mRng.Scaled(3) = 0 then
            begin
                mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] and not $100;
                mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] and not 2;
                mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] or $200;
            end;
        if (mState.mData.TurnTick and $F) <> 0 then Continue;
        vFlags := mState.mData.Treaties[ParaCiv, vI];
        if (vFlags and $10) = 0 then
        begin
            mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] and not 1;
            mState.mData.Treaties[vI, ParaCiv] := mState.mData.Treaties[vI, ParaCiv] and not 1;
        end;
        mState.mData.Treaties[ParaCiv, vI] := mState.mData.Treaties[ParaCiv, vI] and not $10;
        mState.mData.Treaties[vI, ParaCiv] := mState.mData.Treaties[vI, ParaCiv] and not $10;
    end;
end;

function TCivDiplomacy.DiplomacyEvent(ParaCivA, ParaCivB, ParaX, ParaY: Integer): Integer;
var
    vOldFlags : Integer;
begin
    Result := 0;
    if (ParaCivA = 0) or (ParaCivB = 0) then Exit;
    vOldFlags := mState.mData.Treaties[ParaCivA, ParaCivB];
    mState.mData.Treaties[ParaCivA, ParaCivB] := mState.mData.Treaties[ParaCivA, ParaCivB] or $11;
    mState.mData.Treaties[ParaCivB, ParaCivA] := mState.mData.Treaties[ParaCivB, ParaCivA] or $11;
    if (ParaCivA = mState.mData.CivNow) or (ParaCivB = mState.mData.CivNow) then Exit;
    if (((ParaCivA + ParaCivB + mState.mData.TurnTick) and 3) <> 0) and ((vOldFlags and 1) <> 0) then Exit;
    if (mState.mData.Treaties[ParaCivA, ParaCivB] and 8) <> 0 then Exit;
    if (mState.mData.Treaties[ParaCivB, ParaCivA] and 8) <> 0 then Exit;
    if not ((AllianceOk(ParaCivA, ParaCivB) and (not CivWonderActive(ParaCivB, 7)) and
             (mState.mData.CivGov[ParaCivA] < 4)) or
            (AllianceOk(ParaCivB, ParaCivA) and (not CivWonderActive(ParaCivA, 7)) and
             (mState.mData.CivGov[ParaCivB] < 4))) then
    begin
        if TradeAdvances(ParaCivA, ParaCivB) then Result := 3;
        if (mState.mData.Treaties[ParaCivA, ParaCivB] and 2) = 0 then
        begin
            RelationSet(ParaCivA, ParaCivB, 2);
            Result := 1;
        end;
    end else
    begin
        if (mState.mData.Treaties[ParaCivA, ParaCivB] and 2) = 0 then Exit;
        Accord(ParaCivA, ParaCivB, 2);
        Result := 2;
    end;
end;

function TCivDiplomacy.AllianceOk(ParaCivA, ParaCivB: Integer): Boolean;
var
    vWC, vJ, vT, vDen, vX, vWv : Integer;
begin
    if (mState.mData.RuleOptions and 1) = 0 then Exit(True);
    if (mState.mData.Treaties[ParaCivA, mState.mData.CivNow] and 3 = 1) and
       (mState.mData.MilitaryTable[ParaCivB] < mState.mData.MilitaryTable[mState.mData.CivNow]) and
       ((mState.mData.Treaties[ParaCivB, mState.mData.CivNow] and 4) = 0) then Exit(False);
    if (mState.mData.Treaties[ParaCivB, mState.mData.CivNow] and 3 = 1) and
       (mState.mData.MilitaryTable[ParaCivA] < mState.mData.MilitaryTable[mState.mData.CivNow]) and
       ((mState.mData.Treaties[ParaCivA, mState.mData.CivNow] and 4) = 0) then Exit(False);
    if mState.mData.ForcesPresent[ParaCivA, 25] < PowerOf(ParaCivB) then Exit(False);
    vWC := 0;
    for vJ := 1 to 7 do
        if (vJ <> ParaCivA) and (vJ <> ParaCivB) and
           ((mState.mData.Treaties[ParaCivA, vJ] and 3) = 1) then Inc(vWC);
    if (mState.mData.Treaties[ParaCivA, ParaCivB] and 2) <> 0 then Inc(vWC);
    vWC := vWC - LeaderF0(ParaCivA);
    vX := 0; vT := 0; vDen := 1;
    for vJ := 1 to 14 do
    begin
        if (mState.mData.AiContinentTowns[ParaCivA, vJ] <> 0) and
           (mState.mData.CivContAttackers[ParaCivA, vJ] div 2 + mState.mData.DefendersIsland[ParaCivA, vJ] <
            ScoreOf(ParaCivB, vJ, ParaCivA)) then Exit(False);
        if mState.mData.CivContAttackers[ParaCivA, vJ] <> 0 then
        begin
            vWv := mState.mData.DefendersIsland[ParaCivB, vJ];
            if vWv <> 0 then
            begin
                vX := vX + mState.mData.CivContAttackers[ParaCivA, vJ];
                vDen := vDen + ScoreOf(ParaCivB, vJ, ParaCivA) div 2 + vWv;
                vT := vT + mState.mData.AiContinentTowns[ParaCivA, vJ];
            end;
        end;
    end;
    if (vX * 4 div vDen) < (vWC + 4) then
        if vT <> 0 then Exit(False);
    Result := True;
end;

function TCivDiplomacy.TradeAdvances(ParaCivA, ParaCivB: Integer): Boolean;
var
    vK, vP, vQ, vFlags, vWord : Integer;
begin
    vFlags := 0;
    for vK := 0 to 71 do
    begin
        vWord := vK div 16;
        if (not HasTech(ParaCivA, vK)) and HasTech(ParaCivB, vK) then
        begin vFlags := vFlags or 1; vP := vK; end;
        if (not HasTech(ParaCivB, vK)) and HasTech(ParaCivA, vK) then
        begin vFlags := vFlags or 2; vQ := vK; end;
    end;
    if vFlags = 3 then
    begin
        mState.mData.AdvancesKnown[ParaCivA, vP div 16] :=
            SmallInt(mState.mData.AdvancesKnown[ParaCivA, vP div 16] or SmallInt(1 shl (vP mod 16)));
        mState.mData.AdvancesKnown[ParaCivB, vQ div 16] :=
            SmallInt(mState.mData.AdvancesKnown[ParaCivB, vQ div 16] or SmallInt(1 shl (vQ mod 16)));
        Exit(True);
    end;
    Result := False;
end;

function TCivDiplomacy.NearestUnitDistance(ParaCiv, ParaX, ParaY: Integer): Integer;
var
    vI, vDist, vMin : Integer;
begin
    vMin := 16;
    for vI := 0 to 127 do
        if (mState.mData.ArmyData[ParaCiv, vI].UnitType <> -1) and
           ((mState.mData.ArmyData[ParaCiv, vI].Status and 1) <> 0) then
        begin
            vDist := MapDist(ParaX, mState.mData.ArmyData[ParaCiv, vI].X,
                             ParaY, mState.mData.ArmyData[ParaCiv, vI].Y);
            if vDist < vMin then vMin := vDist;
        end;
    Result := vMin;
end;

function TCivDiplomacy.ScoreOf(ParaCiv, ParaContinent, ParaAgainst: Integer): Integer;
begin
    Result := mState.mData.CivContAttackers[ParaCiv, ParaContinent];
end;

function TCivDiplomacy.ValueOf(ParaCiv, ParaContinent: Integer): Integer;
begin
    Result := mState.mData.DefendersIsland[ParaCiv, ParaContinent];
end;

function TCivDiplomacy.PowerOf(ParaCiv: Integer): Integer;
begin
    Result := mState.mData.ForcesPresent[ParaCiv, 25];
end;

end.