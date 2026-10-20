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
        function  AttackOk(ParaDefenderCiv: Integer): Integer;
        procedure DropUnit(ParaGroup, ParaIndex: Integer);
        procedure EachStack(ParaGroup, ParaIndex: Integer);
        function  StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
        destructor Destroy; override;
        function  Battle(ParaAttackerCiv, ParaAttackerUnit,
                         ParaDefenderCiv, ParaDefenderUnit,
                         ParaFlag: Integer): Integer;
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
    vA, vD                  : TUnit;
    vTerrainType            : Integer;
    vAttackerType, vDefenderType : Integer;
    vAttack, vDef           : Integer;
    vBarbarianReroll        : Boolean;
    vCityIdx                : Integer;
    vCityFlags              : LongInt;
    vVet                    : ShortInt;
    vAttackerWins           : Boolean;
    vStackLosses            : Integer;
    vIsCity                 : Boolean;
    vDefenderIsAir, vDefenderIsShip : Boolean;
begin
    vA := mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit];
    vD := mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit];
    vAttackerType := vA.UnitType;
    vDefenderType := vD.UnitType;
    vTerrainType  := mWorld.TerrainAt(vD.X, vD.Y);
    if vTerrainType < 0 then
        Exit(0);

    vBarbarianReroll := False;
    vAttack := mState.mData.UtTypes[vAttackerType].Attack * 8;
    vDefenderIsAir  := mState.mData.UtTypes[vDefenderType].Domain = 1;
    vDefenderIsShip := mState.mData.UtTypes[vDefenderType].Domain = 2;

    if (mWorld.MapFlags(vD.X, vD.Y) and ConstTileFortress) <> 0 then
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 8
    else if (vD.Status and ConstUnitFortified) <> 0 then
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 6
    else
        vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 4;

    if ParaAttackerCiv = ConstBarbarianCiv then
    begin
        if ParaDefenderCiv = mState.mData.CivNow then
            vAttack := vAttack * (mState.mData.CurTier + 1) div 4
        else
            vAttack := vAttack div 2;
    end;

    if vDefenderIsAir or vDefenderIsShip then
        vDef := mState.mData.UtTypes[vDefenderType].Defense * 8;

    vIsCity := mWorld.IsCityTile(vD.X, vD.Y);
    if vIsCity then
    begin
        vCityIdx := mWorld.CityAtTile(vD.X, vD.Y);
        if vCityIdx = -1 then
            raise ECivCombatError.Create('City flag set but no city record found');
        vCityFlags := mState.mData.TownBuf[vCityIdx].Buildings;
        if ((vCityFlags and ConstBldCityWalls) <> 0) and
           (mState.mData.UtTypes[vAttackerType].Attack <> 12) and
           (mState.mData.UtTypes[vDefenderType].Domain <> 1) then
            vDef := TerrainEntry(vTerrainType).Defense * mState.mData.UtTypes[vDefenderType].Defense * 12;

        if ParaAttackerCiv = ConstBarbarianCiv then
        begin
            if mState.mData.CityCount[ParaDefenderCiv] = 1 then
                vAttack := 0;
            if (vCityFlags and ConstBldPalace) <> 0 then
                vAttack := vAttack div 2;
            vBarbarianReroll := True;
        end;
    end;

    if (vA.Status and ConstUnitVeteran) <> 0 then
        vAttack := vAttack + vAttack div 2;
    if (vD.Status and ConstUnitVeteran) <> 0 then
        vDef := vDef + vDef div 2;

    vVet := vA.Moves;
    if vVet < 3 then
        vAttack := vVet * vAttack div 3;

    if ParaFlag = 0 then
    begin
        Result := vAttack * 8 div (vDef + 1);
        Exit;
    end;

    if ParaAttackerCiv <> ConstBarbarianCiv then
    begin
        if (mState.mData.CurTier <= 1) and (ParaDefenderCiv = mState.mData.CivNow) then
            vAttack := vAttack div 2;
        if (mState.mData.CurTier = 0) and (ParaAttackerCiv = mState.mData.CivNow) then
            vAttack := vAttack * 2;
    end;

    if ParaAttackerCiv = mState.mData.CivNow then
        if AttackOk(ParaDefenderCiv) = -1 then
        begin
            mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit].GotoX := -1;
            Exit(-1);
        end;

    vAttackerWins := mRng.Scaled(vAttack) > mRng.Scaled(vDef);
    if vBarbarianReroll and vAttackerWins then
        if mRng.Scaled(vAttack) < mRng.Scaled(vDef) then
            vAttackerWins := False;

    mState.mData.Treaties[ParaAttackerCiv, ParaDefenderCiv] :=
        mState.mData.Treaties[ParaAttackerCiv, ParaDefenderCiv] or $20;
    mState.mData.Treaties[ParaDefenderCiv, ParaAttackerCiv] :=
        mState.mData.Treaties[ParaDefenderCiv, ParaAttackerCiv] or $20;
    if (ParaAttackerCiv <> ConstBarbarianCiv) and (ParaDefenderCiv <> ConstBarbarianCiv) then
        mState.mData.PlayerPeaceRun := 0;

    { Nuclear unit: delegate to atom; not modelled here. }
    if vAttackerType = 25 then
        Exit(1);

    if vAttackerWins then
    begin
        if not vIsCity then
        begin
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
                ShortInt(mState.mData.ArmyData[ParaAttackerCiv, ParaAttackerUnit].Status or ConstUnitVeteran);
        Result := 1;
    end else
    begin
        mState.mData.Killed[ParaDefenderCiv, ParaAttackerCiv] :=
            mState.mData.Killed[ParaDefenderCiv, ParaAttackerCiv] + 1;
        DropUnit(ParaAttackerCiv, ParaAttackerUnit);
        if mRng.Scaled(2) <> 0 then
            mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit].Status :=
                ShortInt(mState.mData.ArmyData[ParaDefenderCiv, ParaDefenderUnit].Status or ConstUnitVeteran);
        Result := 0;
    end;
end;

function TCivCombat.AttackOk(ParaDefenderCiv: Integer): Integer;
begin
    if (mState.mData.Treaties[mState.mData.CivNow, ParaDefenderCiv] and 2) <> 0 then
    begin
        if mState.mData.CivGov[mState.mData.CivNow] >= 4 then
            Exit(-1);
        Exit(1);
    end;
    Result := 0;
end;

procedure TCivCombat.DropUnit(ParaGroup, ParaIndex: Integer);
begin
    if (ParaGroup < 0) or (ParaGroup > 7) or (ParaIndex < 0) or (ParaIndex > 127) then Exit;
    if mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType = -1 then Exit;
    Dec(mState.mData.ForcesPresent[ParaGroup,
        mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType]);
    StackRemove(ParaGroup, ParaIndex);
    mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType := -1;
end;

procedure TCivCombat.EachStack(ParaGroup, ParaIndex: Integer);
var
    vStart, vCur, vCount : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0;
    while (vCur <> -1) and (vCount < 10) do
    begin
        DropUnit(ParaGroup, vCur);
        Inc(vCount);
        vCur := mState.mData.ArmyData[ParaGroup, vCur].Next;
        if vCur = vStart then Break;
    end;
end;

function TCivCombat.StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;
var
    vStart, vCur, vCount : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0;
    while (vCur <> -1) and (vCount < 10) do
    begin
        if vCur = vStart then Inc(vCount);
        case ParaMode of
            2 : Inc(vCount);
        end;
        vCur := mState.mData.ArmyData[ParaGroup, vCur].Next;
        if vCur = vStart then Break;
    end;
    Result := vCount;
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
    if vHead = -1 then Exit;
    if mState.mData.ArmyData[ParaGroup, vHead].Next = ParaIndex then
        mState.mData.ArmyData[ParaGroup, vHead].Next := -1
    else
    begin
        vPrev := vHead; vCount := 0;
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