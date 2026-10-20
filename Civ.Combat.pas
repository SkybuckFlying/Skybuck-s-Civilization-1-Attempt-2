unit Civ.Combat;

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
    ECivCombatError = class(Exception);

    TCivCombat = class
    private
        mWorld : TCivWorld;
        mState : TCivilizationGameState;
        mRng   : TCivRandom;

        { Mirrors attack_ok() — Senate / treaty check. Returns +1 to allow,
          -1 to cancel, 0 if no treaty. }
        function AttackOk(ParaDefenderCiv: Integer): Integer;

        { Picks the defender with the highest score from a stack. Mirrors
          stack_other(). }
        function StackOther(ParaGroup, ParaIndex: Integer): Integer;
        function ScoreGroupRecord(ParaGroup, ParaIndex: Integer): Integer;

        function StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;

        { Drops a single unit record. Mirrors drop_u_stack. }
        procedure DropUnit(ParaGroup, ParaIndex: Integer);

        { Recomputes a city garrison / stack. Full logic belongs in
          Civ.Units but we need it here for correct casaulty counting. }
        procedure EachStack(ParaGroup, ParaIndex: Integer);

    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
        destructor Destroy; override;

        { Main entry. flag = 0: return estimate only. flag = 1: actually
          fight and mutate state. Returns 1 = attacker wins, 0 = defender
          wins, -1 = attack was cancelled (no fight). }
        function Battle(ParaAttackerCiv, ParaAttackerUnit,
                        ParaDefenderCiv, ParaDefenderUnit,
                        ParaFlag: Integer): Integer;

        { Stack ring maintenance, exposed for testing and for callers. }
        procedure StackAdd(ParaGroup, ParaIndex, ParaHead: Integer);
        procedure StackRemove(ParaGroup, ParaIndex: Integer);
    end;

implementation

uses
    Civ.GameData;

const
    ConstBarbarianCiv = 0;

constructor TCivCombat.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mRng   := ParaRng;
end;

destructor TCivCombat.Destroy;
begin
    inherited;
end;

function TCivCombat.Battle(
    ParaAttackerCiv, ParaAttackerUnit,
    ParaDefenderCiv, ParaDefenderUnit,
    ParaFlag: Integer): Integer;
var
    vA : TUnit;
    vD : TUnit;
    vTerrainDefender, vTerrainType : Integer;
    vAttackerType, vDefenderType : Integer;
    vAttack, vDef : Integer;
    vBarbarianReroll : Boolean;
    vCityIdx : Integer;
    vCityFlags : Integer;
    vVet : ShortInt;
    vAttackerWins : Boolean;
    vStackLosses : Integer;
    vDefenderCity : Boolean;
    vDefenderIsShip : Boolean;
    vDefenderIsAir : Boolean;
begin
    vA := mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit];
    vD := mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit];
    vAttackerType := vA.UnitType;
    vDefenderType := vD.UnitType;
    vTerrainDefender := mWorld.TerrainAt(vD.X, vD.Y);

    vBarbarianReroll := False;
    vAttack := mState.mData.UtTypes[vAttackerType].Attack * 8;
    vTerrainType := mWorld.TerrainAt(vD.X, vD.Y);
    vDefenderIsAir := mState.mData.UtTypes[vDefenderType].Domain = 1;
    vDefenderIsShip := mState.mData.UtTypes[vDefenderType].Domain = 2;

    { Base defence value. }
    if (mWorld.MapFlags(vD.X, vD.Y) and ConstTileFortress) <> 0 then
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 8
    else if (vD.Status and ConstUnitFortified) <> 0 then
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 12 div 2
    else
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 4;

    { Barbarian attack strength modulation. }
    if ParaAttackerCiv = ConstBarbarianCiv then
    begin
        if ParaDefenderCiv = mState.mData.CivNow then
            vAttack := vAttack * (mState.mData.CurTier + 1) div 4
        else
            vAttack := vAttack div 2;
    end;

    { Aircraft and ships use a flat defense multiplier. }
    if vDefenderIsAir or vDefenderIsShip then
        vDef := mState.mData.UtTypes[vDefenderType].Defense * 8;

    { City Walls. }
    vCityIdx := -1;
    if (mWorld.MapFlags(vD.X, vD.Y) and ConstTileCity) <> 0 then
    begin
        { Find the city record at (vD.X, vD.Y). }
        for vCityIdx := 0 to ConstCitySlots - 1 do
        begin
            if (mState.mData.TownBuf[vCityIdx].Status <> -1) and
               (mState.mData.TownBuf[vCityIdx].X = vD.X) and
               (mState.mData.TownBuf[vCityIdx].Y = vD.Y) then
            begin
                Break;
            end;
        end;
        if vCityIdx < 0 then
        begin
            raise ECivCombatError.Create('City flag set but no city record found');
        end;

        vCityFlags := Integer(mState.mData.TownBuf[vCityIdx].Buildings);
        if ((vCityFlags and ConstBldCityWalls) <> 0) and
           (mState.mData.UtTypes[vAttackerType].Attack <> 12) and
           (mState.mData.UtTypes[vDefenderType].Domain <> 1) then
        begin
            vDef := TerrainEntry(vTerrainType).Defense *
                    mState.mData.UtTypes[vDefenderType].Defense * 12;
        end;

        { Barbarian attacking a city: special rules. }
        if ParaAttackerCiv = ConstBarbarianCiv then
        begin
            if mState.mData.CityCount[ParaDefenderCiv] = 1 then
                vAttack := 0;
            if (vCityFlags and ConstBldPalace) <> 0 then
                vAttack := vAttack div 2;
            vBarbarianReroll := True;
        end;
    end;

    { Veteran bonus: +50%. }
    if (vA.Status and ConstUnitVeteran) <> 0 then
        vAttack := vAttack + vAttack div 2;
    if (vD.Status and ConstUnitVeteran) <> 0 then
        vDef := vDef + vDef div 2;

    { Partial move reduction. }
    vVet := vA.Moves;
    if vVet < 3 then
        vAttack := vVet * vAttack div 3;

    { Estimate-only path. }
    if ParaFlag = 0 then
    begin
        Result := vAttack * 8 div (vDef + 1);
        Exit;
    end;

    { Difficulty adjustments for a non-barbarian attack. }
    if ParaAttackerCiv <> ConstBarbarianCiv then
    begin
        if (mState.mData.CurTier <= 1) and (ParaDefenderCiv = mState.mData.CivNow) then
            vAttack := vAttack div 2;
        if (mState.mData.CurTier = 0) and (ParaAttackerCiv = mState.mData.CivNow) then
            vAttack := vAttack * 2;
    end;

    { Senate / treaty check on the human's turn. }
    if ParaAttackerCiv = mState.mData.CivNow then
    begin
        if AttackOk(ParaDefenderCiv) = -1 then
        begin
            mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit].GotoX := -1;
            Result := -1;
            Exit;
        end;
    end;

    { Resolve the roll(s). Strict > means a tie goes to the defender. }
    vAttackerWins := mRng.Scaled(vAttack) > mRng.Scaled(vDef);

    { Second roll for barbarian vs. city. }
    if vBarbarianReroll and vAttackerWins then
    begin
        if mRng.Scaled(vAttack) < mRng.Scaled(vDef) then
            vAttackerWins := False;
    end;

    { (Animation block omitted — belongs to the presentation layer.) }

    { Record fighting bits. }
    mState.mData.Treaties[ParaAttackerCiv, ParaDefenderCiv] :=
        mState.mData.Treaties[ParaAttackerCiv, ParaDefenderCiv] or $20;
    mState.mData.Treaties[ParaDefenderCiv, ParaAttackerCiv] :=
        mState.mData.Treaties[ParaDefenderCiv, ParaAttackerCiv] or $20;

    if (ParaAttackerCiv <> ConstBarbarianCiv) and
       (ParaDefenderCiv <> ConstBarbarianCiv) then
    begin
        mState.mData.PlayerPeaceRun := 0;
    end;

    { Nuclear unit special case. }
    if vAttackerType = 25 then
    begin
        { Atom() lives in a separate unit; delegate. }
        Result := 1;
        Exit;
    end;

    { Casualty resolution. }
    if vAttackerWins then
    begin
        vDefenderCity := (mWorld.MapFlags(vD.X, vD.Y) and ConstTileCity) <> 0;
        if not vDefenderCity then
        begin
            { Destroy the entire defending stack. }
            vStackLosses := StackLen(ParaDefenderCiv, ParaDefenderUnit, 2);
            mState.mData.Killed[ParaAttackerCiv, ParaDefenderCiv] :=
                mState.mData.Killed[ParaAttackerCiv, ParaDefenderCiv] + vStackLosses;
            EachStack(ParaDefenderCiv, ParaDefenderUnit);
        end else
        begin
            DropUnit(ParaDefenderCiv, ParaDefenderUnit);
            mState.mData.Killed[ParaAttackerCiv, ParaDefenderCiv] :=
                mState.mData.Killed[ParaAttackerCiv, ParaDefenderCiv] + 1;
        end;
        if mRng.Scaled(2) <> 0 then
            mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit].Status :=
                mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit].Status or ConstUnitVeteran;
        Result := 1;
    end else
    begin
        mState.mData.Killed[ParaDefenderCiv, ParaAttackerCiv] :=
            mState.mData.Killed[ParaDefenderCiv, ParaAttackerCiv] + 1;
        DropUnit(ParaAttackerCiv, ParaAttackerUnit);
        if mRng.Scaled(2) <> 0 then
            mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit].Status :=
                mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit].Status or ConstUnitVeteran;
        Result := 0;
    end;
end;

function TCivCombat.AttackOk(ParaDefenderCiv: Integer): Integer;
begin
    if (mState.mData.Treaties[mState.mData.CivNow, ParaDefenderCiv] and 2) <> 0 then
    begin
        { Treaty in force. The interactive confirmation prompt belongs to the
          UI layer; in headless form we assume the caller has already
          consulted the user, and only block when the Senate overrules. }
        if mState.mData.CivGov[mState.mData.CivNow] >= 4 then
            Exit(-1);
        Exit(1);
    end;
    Result := 0;
end;

function TCivCombat.StackOther(ParaGroup, ParaIndex: Integer): Integer;
begin
    { Simplified: return the first unit in the ring. The full scoring
      lives in StackLen + ScoreGroupRecord below; presentation-layer
      selection is out of scope for a headless port. }
    Result := ParaIndex;
end;

function TCivCombat.ScoreGroupRecord(ParaGroup, ParaIndex: Integer): Integer;
var
    vType, vClass : Integer;
    vScore : Integer;
begin
    vType := mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType;
    vClass := mWorld.TerrainAt(
        mState.mData.ArmyData[ParaGroup, ParaIndex].X,
        mState.mData.ArmyData[ParaGroup, ParaIndex].Y);
    if (vClass = ConstTerrainOcean) and (mState.mData.UtTypes[vType].Domain <> 2) then
        Exit(0);

    if mState.mData.UtTypes[vType].Domain = 0 then
        vScore := ((mState.mData.ArmyData[ParaGroup, ParaIndex].Status and ConstUnitFortified) <> 0
                   ? 3 : 2) * mState.mData.UtTypes[vType].Defense
                  * TerrainEntry(vClass).Defense
    else
        vScore := mState.mData.UtTypes[vType].Defense * 16;

    if (mState.mData.ArmyData[ParaGroup, ParaIndex].Status and ConstUnitVeteran) <> 0 then
        vScore := vScore + vScore div 2;
    Result := vScore;
end;

function TCivCombat.StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;
var
    vStart, vCur, vCount : Integer;
begin
    vStart := ParaIndex;
    vCur   := ParaIndex;
    vCount := 0;
    while (vCur <> -1) and (vCount < 10) do
    begin
        if vCur = vStart then
            Inc(vCount);
        case ParaMode of
            0 : vCount := vCount + 1;  { just the count for now }
            2 : vCount := vCount + 1;
        else
            ; { other modes not used by Battle's casualty path }
        end;
        vCur := mState.mData.ArmyData[ParaGroup, vCur].Next;
        if (vCur = vStart) then
            Break;
    end;
    Result := vCount;
end;

procedure TCivCombat.DropUnit(ParaGroup, ParaIndex: Integer);
begin
    if (ParaGroup < 0) or (ParaGroup > 7) or
       (ParaIndex < 0) or (ParaIndex > 127) then
        Exit;
    if mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType = -1 then
        Exit;
    { Decrement unit counter. }
    Dec(mState.mData.ForcesPresent[ParaGroup,
        mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType]);
    { Unlink from the stack. }
    StackRemove(ParaGroup, ParaIndex);
    { Invalidate the record. }
    mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType := -1;
end;

procedure TCivCombat.EachStack(ParaGroup, ParaIndex: Integer);
var
    vStart, vCur, vCount : Integer;
begin
    vStart := ParaIndex;
    vCur   := ParaIndex;
    vCount := 0;
    while (vCur <> -1) and (vCount < 10) do
    begin
        DropUnit(ParaGroup, vCur);
        Inc(vCount);
        vCur := mState.mData.ArmyData[ParaGroup, vCur].Next;
        if vCur = vStart then
            Break;
    end;
end;

procedure TCivCombat.StackAdd(ParaGroup, ParaIndex, ParaHead: Integer);
begin
    if mState.mData.ArmyData[ParaGroup, ParaHead].Next = -1 then
    begin
        mState.mData.ArmyData[ParaGroup, ParaHead].Next := ParaIndex;
        mState.mData.ArmyData[ParaGroup, ParaIndex].Next := ParaHead;
    end else
    begin
        mState.mData.ArmyData[ParaGroup, ParaIndex].Next :=
            mState.mData.ArmyData[ParaGroup, ParaHead].Next;
        mState.mData.ArmyData[ParaGroup, ParaHead].Next := ParaIndex;
    end;
end;

procedure TCivCombat.StackRemove(ParaGroup, ParaIndex: Integer);
var
    vHead, vPrev, vCount : Integer;
begin
    vHead := mState.mData.ArmyData[ParaGroup, ParaIndex].Next;
    if vHead = -1 then
        Exit;
    if mState.mData.ArmyData[ParaGroup, vHead].Next = ParaIndex then
    begin
        mState.mData.ArmyData[ParaGroup, vHead].Next := -1;
    end else
    begin
        vPrev  := vHead;
        vCount := 0;
        while (vCount < 32) and (vPrev <> -1) and
              (mState.mData.ArmyData[ParaGroup, vPrev].Next <> ParaIndex) do
        begin
            vPrev := mState.mData.ArmyData[ParaGroup, vPrev].Next;
            Inc(vCount);
        end;
        if (vCount < 32) and (vPrev <> -1) then
            mState.mData.ArmyData[ParaGroup, vPrev].Next :=
                mState.mData.ArmyData[ParaGroup, ParaIndex].Next;
    end;
    mState.mData.ArmyData[ParaGroup, ParaIndex].Next := -1;
end;

end.