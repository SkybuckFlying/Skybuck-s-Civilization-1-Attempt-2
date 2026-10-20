unit Civ.Units;

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
    { Unit creation, stacking, movement, and the exploration/contact sweep.
      Mirrors UNITS.C. Does not own the world or the state; both are passed
      in and remain the caller's responsibility.

      The one piece of mutable module state is the `mCityCreate` hook, which
      is registered once via RegisterCityCreate and used by EnterHut's
      "advanced tribe" branch. This is a callback, not an ownership
      relationship — the caller owns the TCivCities instance. }
    TCivUnitManager = class
    private
        mWorld : TCivWorld;
        mState : TCivilizationGameState;
        mRng   : TCivRandom;

        procedure EachStack(ParaGroup, ParaIndex: Integer;
                            ParaCallback: TProc<Integer, Integer>);
        procedure KillStackCb(ParaGroup, ParaIndex: Integer);
        procedure ValidateRecord(ParaGroup, ParaIndex: Integer);
        function  HasAdvance(ParaCiv, ParaAdvance: Integer): Boolean;
    public
        constructor Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
        destructor Destroy; override;

        { --- Creation / removal ----------------------------------------- }
        function  CreateUnit(ParaOwner, ParaType, ParaX, ParaY: Integer): Integer;
        procedure DropUnit(ParaGroup, ParaIndex: Integer);

        { --- Map occupancy ---------------------------------------------- }
        { Delegations to TCivWorld. MapStack stays here because it needs
          the unit array. }
        function  MapOwner(ParaX, ParaY: Integer): Integer;
        function  MapStack(ParaX, ParaY: Integer; out ParaCiv: Integer): Integer;
        procedure PutUnit(ParaGroup, ParaIndex, ParaX, ParaY: Integer);
        procedure LiftUnit(ParaGroup, ParaIndex, ParaOldX, ParaOldY: Integer);
        procedure Occupy(ParaX, ParaY: Integer);
        procedure ClearOccupied(ParaX, ParaY: Integer);
        function  FindUnitAt(ParaGroup, ParaX, ParaY: Integer): Integer;

        { --- Stack ring -------------------------------------------------- }
        procedure StackAdd(ParaGroup, ParaIndex, ParaHead: Integer);
        procedure StackRemove(ParaGroup, ParaIndex: Integer);
        function  StackOther(ParaGroup, ParaIndex: Integer): Integer;
        function  StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;
        function  StackCap(ParaGroup, ParaIndex: Integer): Integer;
        function  CountU(ParaGroup, ParaIndex, ParaType: Integer): Integer;
        function  StackStrength(ParaGroup, ParaIndex, ParaRole: Integer): Integer;

        { --- Visibility, contact, movement ------------------------------- }
        procedure UnitSight(ParaX, ParaY, ParaOwner, ParaIndex: Integer);
        function  UnitBlocked(ParaGroup, ParaX, ParaY: Integer): Boolean;
        function  IfOpen(ParaGroup, ParaX, ParaY: Integer): Boolean;
        function  AdjGrp(ParaGroup, ParaX, ParaY: Integer): Boolean;

        { --- Huts -------------------------------------------------------- }
        procedure EnterHut(ParaOwner, ParaIndex: Integer);
    end;

{ Registers the city-creation callback that EnterHut uses for the
  "advanced tribe" reward. Call once at startup. }
procedure RegisterCityCreate(ParaFunc: TCityCreateMethod);

implementation

uses
    Civ.GameData;

const
    ConstBarbarianCiv = 0;

    { GAME.C `improvements[46]` — indices 0..45. Kept local because only
      the hut's terrain-cost comparison and Civ.WorldGen use it, and the
      former reaches it via the caller-provided mCityCreate. }
    ConstCityBuildCost: array[0..45] of Integer = (
        8, 20, 4, 6, 4, 8, 8, 8, 12, 12, 12, 16, 16, 16, 10, 20,
        32, 20, 20, 16, 24, 16, 8, 16, 32, 30, 30, 20, 20, 30,
        30, 30, 40, 30, 30, 40, 40, 40, 30, 60, 60, 60, 60, 60, 60, 60
    );

var
    mCityCreate : TCityCreateMethod = nil;

procedure RegisterCityCreate(ParaFunc: TCityCreateMethod);
begin
    mCityCreate := ParaFunc;
end;

{ -------------------------------------------------------------------------
  Construction / teardown.
  ------------------------------------------------------------------------- }
constructor TCivUnitManager.Create(ParaWorld: TCivWorld; ParaRng: TCivRandom);
begin
    inherited Create;
    mWorld := ParaWorld;
    mState := ParaWorld.State;
    mRng   := ParaRng;
end;

destructor TCivUnitManager.Destroy;
begin
    inherited;
end;

{ -------------------------------------------------------------------------
  Helper: adv check, duplicate-free.
  ------------------------------------------------------------------------- }
function TCivUnitManager.HasAdvance(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
    vBit  : SmallInt;
begin
    if (ParaAdvance < 0) or (ParaAdvance >= 72) then Exit(False);
    if (ParaCiv < 0) or (ParaCiv > 7) then Exit(False);
    vWord := ParaAdvance div 16;
    vBit  := SmallInt(1 shl (ParaAdvance mod 16));
    Result := (mState.mData.AdvancesKnown[ParaCiv, vWord] and vBit) <> 0;
end;

{ -------------------------------------------------------------------------
  Stack ring.
  ------------------------------------------------------------------------- }
procedure TCivUnitManager.StackAdd(ParaGroup, ParaIndex, ParaHead: Integer);
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

procedure TCivUnitManager.StackRemove(ParaGroup, ParaIndex: Integer);
var
    vHead, vPrev, vGuard : Integer;
begin
    vHead := mState.mData.ArmyData[ParaGroup, ParaIndex].Next;
    if vHead = -1 then Exit;
    if mState.mData.ArmyData[ParaGroup, vHead].Next = ParaIndex then
        mState.mData.ArmyData[ParaGroup, vHead].Next := -1
    else
    begin
        vPrev  := vHead;
        vGuard := 0;
        while (vGuard < 32) and (vPrev <> -1) and
              (mState.mData.ArmyData[ParaGroup, vPrev].Next <> ParaIndex) do
        begin
            vPrev := mState.mData.ArmyData[ParaGroup, vPrev].Next;
            Inc(vGuard);
        end;
        if (vGuard < 32) and (vPrev <> -1) then
            mState.mData.ArmyData[ParaGroup, vPrev].Next :=
                mState.mData.ArmyData[ParaGroup, ParaIndex].Next;
    end;
    mState.mData.ArmyData[ParaGroup, ParaIndex].Next := -1;
end;

{ Walks up to 10 members of a stack ring. The C's each_stack caps at 10;
  we preserve that. }
procedure TCivUnitManager.EachStack(ParaGroup, ParaIndex: Integer;
    ParaCallback: TProc<Integer, Integer>);
var
    vStart, vCur, vCount : Integer;
begin
    vStart := ParaIndex;
    vCur   := ParaIndex;
    vCount := 0;
    repeat
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        ParaCallback(ParaGroup, vCur);
        vCur := vNext;
        Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
end;

function TCivUnitManager.StackLen(ParaGroup, ParaIndex, ParaMode: Integer): Integer;
var
    vStart, vCur, vCount, vTotal, vLimitUnit : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0;
    vTotal := 0; vLimitUnit := ParaIndex;
    repeat
        var vType := mState.mData.ArmyData[ParaGroup, vCur].UnitType;
        case ParaMode of
            0 : vTotal := vTotal + mState.mData.UtTypes[vType].Cost;
            1 : vTotal := vTotal + mState.mData.UtTypes[vType].Defense;
            2 : Inc(vTotal);
            3 : vTotal := vTotal + mState.mData.UtTypes[vType].Attack;
            4 : if (vCur < vLimitUnit) and
                   (mState.mData.UtTypes[vType].Role = 2) then
                    Inc(vTotal);
        end;
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        vCur := vNext;
        Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
    Result := vTotal;
end;

function TCivUnitManager.StackCap(ParaGroup, ParaIndex: Integer): Integer;
var
    vStart, vCur, vCount, vTotal : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0; vTotal := 0;
    repeat
        var vType := mState.mData.ArmyData[ParaGroup, vCur].UnitType;
        if mState.mData.UtTypes[vType].Domain = 0 then Dec(vTotal);
        if mState.mData.UtTypes[vType].Role = 5 then
            vTotal := vTotal + mState.mData.UtTypes[vType].Capacity;
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        vCur := vNext; Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
    Result := vTotal;
end;

function TCivUnitManager.CountU(ParaGroup, ParaIndex, ParaType: Integer): Integer;
var
    vStart, vCur, vCount, vTotal : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0; vTotal := 0;
    repeat
        if mState.mData.ArmyData[ParaGroup, vCur].UnitType = ParaType then
            Inc(vTotal);
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        vCur := vNext; Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
    Result := vTotal;
end;

function TCivUnitManager.StackStrength(ParaGroup, ParaIndex, ParaRole: Integer): Integer;
var
    vStart, vCur, vCount, vTotal : Integer;
begin
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0; vTotal := 0;
    repeat
        if mState.mData.UtTypes[mState.mData.ArmyData[ParaGroup, vCur].UnitType].Role = ParaRole then
            Inc(vTotal);
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        vCur := vNext; Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
    Result := vTotal;
end;

{ Best defender in the stack. Delegates scoring to TCivWorld so the
  combat-resolver and unit-manager share one definition. }
function TCivUnitManager.StackOther(ParaGroup, ParaIndex: Integer): Integer;
var
    vStart, vCur, vCount, vBest, vBestScore, vScore : Integer;
begin
    if mState.mData.ArmyData[ParaGroup, ParaIndex].Next = -1 then
        Exit(ParaIndex);
    vStart := ParaIndex; vCur := ParaIndex; vCount := 0;
    vBest := ParaIndex; vBestScore := -1;
    repeat
        vScore := mWorld.ScoreGroupRecord(ParaGroup, vCur);
        if vScore > vBestScore then
        begin
            vBestScore := vScore;
            vBest := vCur;
        end;
        var vNext := mState.mData.ArmyData[ParaGroup, vCur].Next;
        vCur := vNext; Inc(vCount);
    until (vCur = -1) or (vCur = vStart) or (vCount >= 10);
    Result := vBest;
end;

{ -------------------------------------------------------------------------
  Creation / removal.
  ------------------------------------------------------------------------- }
function TCivUnitManager.CreateUnit(
    ParaOwner, ParaType, ParaX, ParaY: Integer): Integer;
var
    vIndex, vCityIdx : Integer;
    vBit : Byte;
begin
    { Slot 127 is reserved by the pathfinder as a probe. }
    for vIndex := 0 to 126 do
    begin
        if mState.mData.ArmyData[ParaOwner, vIndex].UnitType <> -1 then
            Continue;

        mState.mData.ArmyData[ParaOwner, vIndex].X := -1;
        mState.mData.ArmyData[ParaOwner, vIndex].Next := -1;
        mState.mData.ArmyData[ParaOwner, vIndex].Status := 0;
        mState.mData.ArmyData[ParaOwner, vIndex].X := ParaX;
        mState.mData.ArmyData[ParaOwner, vIndex].Y := ParaY;
        mState.mData.ArmyData[ParaOwner, vIndex].UnitType := ParaType;
        mState.mData.ArmyData[ParaOwner, vIndex].GotoX := -1;
        mState.mData.ArmyData[ParaOwner, vIndex].F8 := -1;
        mState.mData.ArmyData[ParaOwner, vIndex].Fuel :=
            mState.mData.UtTypes[ParaType].Fuel;
        if mState.mData.ArmyData[ParaOwner, vIndex].Fuel <> 0 then
            Dec(mState.mData.ArmyData[ParaOwner, vIndex].Fuel);

        vCityIdx := mWorld.CityAtTile(ParaX, ParaY);
        if (vCityIdx <> -1) and
           (mState.mData.TownBuf[vCityIdx].Owner = ParaOwner) then
            mState.mData.ArmyData[ParaOwner, vIndex].HomeCity := vCityIdx
        else
            mState.mData.ArmyData[ParaOwner, vIndex].HomeCity := -1;

        vBit := Byte(1 shl ParaOwner);
        mState.mData.ArmyData[ParaOwner, vIndex].Visibility := ShortInt(vBit);

        Inc(mState.mData.ForcesPresent[ParaOwner, ParaType]);

        PutUnit(ParaOwner, vIndex, ParaX, ParaY);
        mWorld.SetExplored(ParaOwner, ParaX, ParaY, True);

        UnitSight(ParaX, ParaY, ParaOwner, vIndex);

        Exit(vIndex);
    end;
    Result := -1;
end;

procedure TCivUnitManager.DropUnit(ParaGroup, ParaIndex: Integer);
var
    vType : Integer;
    vSea  : Boolean;
begin
    if (ParaGroup < 0) or (ParaGroup > 7) or
       (ParaIndex < 0) or (ParaIndex > 127) then
        Exit;
    vType := mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType;
    if vType = -1 then Exit;

    vSea := mWorld.IsOcean(mState.mData.ArmyData[ParaGroup, ParaIndex].X,
                           mState.mData.ArmyData[ParaGroup, ParaIndex].Y);

    { Sea cargo: a ship at sea takes its land cargo with it, and a Carrier
      at sea takes its aircraft. Only one EachStack fires in practice,
      because carriers have Capacity = 0. }
    if vSea and (mState.mData.ArmyData[ParaGroup, ParaIndex].Next <> -1) then
    begin
        if mState.mData.UtTypes[vType].Capacity > 0 then
            EachStack(ParaGroup, ParaIndex, KillStackCb);
        if vType = 23 then
            EachStack(ParaGroup, ParaIndex, KillStackCb);
    end;

    Dec(mState.mData.ForcesPresent[ParaGroup, vType]);
    mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType := -1;
    mState.mData.ArmyData[ParaGroup, ParaIndex].Moves := 0;

    LiftUnit(ParaGroup, ParaIndex,
             mState.mData.ArmyData[ParaGroup, ParaIndex].X,
             mState.mData.ArmyData[ParaGroup, ParaIndex].Y);
end;

procedure TCivUnitManager.KillStackCb(ParaGroup, ParaIndex: Integer);
begin
    DropUnit(ParaGroup, ParaIndex);
end;

procedure TCivUnitManager.ValidateRecord(ParaGroup, ParaIndex: Integer);
begin
    if mWorld.IsOcean(mState.mData.ArmyData[ParaGroup, ParaIndex].X,
                      mState.mData.ArmyData[ParaGroup, ParaIndex].Y) and
       (mState.mData.UtTypes[mState.mData.ArmyData[ParaGroup, ParaIndex].UnitType].Domain = 0) then
        Exit;
    mState.mData.ArmyData[ParaGroup, ParaIndex].Status :=
        mState.mData.ArmyData[ParaGroup, ParaIndex].Status and not ConstUnitSentry;
end;

{ -------------------------------------------------------------------------
  Map occupancy — delegations plus the unit-scan variant.
  ------------------------------------------------------------------------- }
function TCivUnitManager.MapOwner(ParaX, ParaY: Integer): Integer;
begin
    Result := mWorld.MapOwner(ParaX, ParaY);
end;

procedure TCivUnitManager.Occupy(ParaX, ParaY: Integer);
begin
    mWorld.Occupy(ParaX, ParaY);
end;

procedure TCivUnitManager.ClearOccupied(ParaX, ParaY: Integer);
begin
    mWorld.ClearOccupied(ParaX, ParaY);
end;

function TCivUnitManager.MapStack(
    ParaX, ParaY: Integer; out ParaCiv: Integer): Integer;
var
    vCiv, vIdx : Integer;
begin
    vCiv := mWorld.MapOwner(ParaX, ParaY);
    ParaCiv := vCiv;
    if vCiv = -1 then Exit(-1);
    for vIdx := 0 to 127 do
        if (mState.mData.ArmyData[vCiv, vIdx].UnitType <> -1) and
           (mState.mData.ArmyData[vCiv, vIdx].X = ParaX) and
           (mState.mData.ArmyData[vCiv, vIdx].Y = ParaY) then
            Exit(vIdx);
    { Stale occupancy byte: clear the flag. }
    mWorld.ClearOccupied(ParaX, ParaY);
    Result := -1;
end;

function TCivUnitManager.FindUnitAt(
    ParaGroup, ParaX, ParaY: Integer): Integer;
var
    vIdx : Integer;
begin
    for vIdx := 0 to 127 do
        if (mState.mData.ArmyData[ParaGroup, vIdx].UnitType <> -1) and
           (mState.mData.ArmyData[ParaGroup, vIdx].X = ParaX) and
           (mState.mData.ArmyData[ParaGroup, vIdx].Y = ParaY) then
            Exit(vIdx);
    Result := -1;
end;

procedure TCivUnitManager.PutUnit(
    ParaGroup, ParaIndex, ParaX, ParaY: Integer);
var
    vExisting, vCiv : Integer;
begin
    vExisting := MapStack(ParaX, ParaY, vCiv);
    if vExisting <> -1 then
        StackAdd(ParaGroup, ParaIndex, vExisting);
    mWorld.Occupy(ParaX, ParaY);
    mWorld.SetRawPixel(ParaX + 160, ParaY,
        Byte((Byte(ParaGroup) and 7) or $08));
end;

procedure TCivUnitManager.LiftUnit(
    ParaGroup, ParaIndex, ParaOldX, ParaOldY: Integer);
begin
    if mState.mData.ArmyData[ParaGroup, ParaIndex].Next <> -1 then
        StackRemove(ParaGroup, ParaIndex)
    else
        mWorld.ClearOccupied(ParaOldX, ParaOldY);
end;

{ -------------------------------------------------------------------------
  Predicates.
  ------------------------------------------------------------------------- }
function TCivUnitManager.UnitBlocked(
    ParaGroup, ParaX, ParaY: Integer): Boolean;
var
    vDir, vNX, vNY, vTileOwner, vRecordIndex : Integer;
    vVisBit : Byte;
    vCurrentOcean : Boolean;
begin
    vCurrentOcean := mWorld.IsOcean(ParaX, ParaY);
    for vDir := 1 to 8 do
    begin
        vNX := WrapX(ParaX + ConstSpiralX[vDir]);
        vNY := ParaY + ConstSpiralY[vDir];
        if vCurrentOcean <> mWorld.IsOcean(vNX, vNY) then Continue;
        vTileOwner := MapOwner(vNX, vNY);
        if (vTileOwner = -1) or (vTileOwner = ParaGroup) then Continue;

        if ParaGroup = mState.mData.CivNow then
        begin
            vRecordIndex := MapStack(vNX, vNY, vTileOwner);
            if vRecordIndex = -1 then Continue;

            vVisBit := Byte(1 shl mState.mData.CivNow);
            if (Byte(mState.mData.ArmyData[vTileOwner, vRecordIndex].Visibility) and vVisBit) = 0 then
            begin
                mState.mData.ArmyData[vTileOwner, vRecordIndex].Visibility :=
                    ShortInt(Byte(mState.mData.ArmyData[vTileOwner, vRecordIndex].Visibility) or vVisBit);
                mWorld.SetExplored(mState.mData.CivNow, vNX, vNY, True);
            end;

            if mWorld.IsCityTile(vNX, vNY) then
            begin
                var vCityIdx := mWorld.CityAtTile(vNX, vNY);
                if vCityIdx <> -1 then
                    mState.mData.TownBuf[vCityIdx].VisibleSize :=
                        mState.mData.TownBuf[vCityIdx].Size;
                mWorld.MapMark(vNX, vNY);
            end;
        end;

        Exit(True);
    end;
    Result := False;
end;

function TCivUnitManager.IfOpen(ParaGroup, ParaX, ParaY: Integer): Boolean;
begin
    if mWorld.IsCityTile(ParaX, ParaY) then
        Exit(False);
    Result := UnitBlocked(ParaGroup, ParaX, ParaY);
end;

function TCivUnitManager.AdjGrp(ParaGroup, ParaX, ParaY: Integer): Boolean;
begin
    Result := mWorld.AdjacentForeignTile(ParaGroup, ParaX, ParaY);
end;

{ -------------------------------------------------------------------------
  UnitSight — reveal, contact detection, contact resolution.

  Preserves the C's structure exactly:
    1. Primary 5×5 reveal (rows 0..24 of the spiral).
    2. Contact sweep for the eight immediate neighbours.
    3. Secondary 5×5 sweep for wider-sight units.
    4. Redraw pass for the human.
  The diplomacy_event() call is deferred: it needs the TCivDiplomacy
  instance, which lives one layer up. The C source has this call at a
  specific position (after the two goto-clear branches); we preserve
  that position with a `{ TODO: wire }` comment.
  ------------------------------------------------------------------------- }
procedure TCivUnitManager.UnitSight(
    ParaX, ParaY, ParaOwner, ParaIndex: Integer);
var
    vDir, vNX, vNY, vTileFlags, vUnitType, vExistingOwner, vExisting : Integer;
    vVisBit, vMapFlags, vTerrainAt, vCityIdx : Integer;
begin
    vUnitType := mState.mData.ArmyData[ParaOwner, ParaIndex].UnitType;
    vTerrainAt := mWorld.TerrainAt(ParaX, ParaY);

    { 1. Primary 5×5 reveal. }
    for vDir := 0 to 24 do
    begin
        vNX := WrapX(ParaX + ConstSpiralX[vDir]);
        vNY := ParaY + ConstSpiralY[vDir];
        if (vDir >= 9) and
           (((mState.mData.UtTypes[vUnitType].Sight and 2) = 0) or
            ((mState.mData.UtTypes[vUnitType].Domain = 2) and
             (mWorld.TerrainAt(vNX, vNY) <> ConstTerrainOcean))) then
            Continue;
        if MapInBounds(vNX, vNY) then
        begin
            mWorld.SetExplored(ParaOwner, vNX, vNY, True);
            mWorld.MapMark(vNX, vNY);
        end;
    end;

    { 2. Contact sweep — eight immediate neighbours. }
    vMapFlags := mWorld.MapFlags(ParaX, ParaY);
    vVisBit   := Byte(1 shl ParaOwner);
    for vDir := 1 to 8 do
    begin
        vNX := WrapX(ParaX + ConstSpiralX[vDir]);
        vNY := ParaY + ConstSpiralY[vDir];
        if not MapInBounds(vNX, vNY) then Continue;

        mWorld.SetExplored(ParaOwner, vNX, vNY, True);
        vTileFlags := mWorld.MapFlags(vNX, vNY);

        { Foreign city: mark it visible and register the owner. }
        if (vTileFlags and ConstTileCity) <> 0 then
        begin
            vExistingOwner := mWorld.MapCity(vNX, vNY);
            if vExistingOwner <> ParaOwner then
            begin
                vCityIdx := mWorld.CityAtTile(vNX, vNY);
                if vCityIdx <> -1 then
                    mState.mData.TownBuf[vCityIdx].VisibleSize :=
                        mState.mData.TownBuf[vCityIdx].Size;
                if mState.mData.UtTypes[vUnitType].Domain = 0 then
                    mState.mData.ArmyData[ParaOwner, ParaIndex].Visibility :=
                        ShortInt(Byte(mState.mData.ArmyData[ParaOwner, ParaIndex].Visibility)
                                 or Byte(1 shl vExistingOwner));
            end;
        end;

        { Adjacent enemy stack: mark visible, clear goto. }
        vExisting := MapStack(vNX, vNY, vExistingOwner);
        if (vExisting <> -1) and (ParaOwner <> vExistingOwner) then
        begin
            if (vMapFlags and ConstTileCity) = 0 then
                mState.mData.ArmyData[ParaOwner, ParaIndex].Visibility :=
                    ShortInt(Byte(mState.mData.ArmyData[ParaOwner, ParaIndex].Visibility)
                             or Byte(1 shl vExistingOwner));

            EachStack(vExistingOwner, vExisting, ValidateRecord);

            if (vTerrainAt = ConstTerrainOcean) or
               (mWorld.TerrainAt(vNX, vNY) <> ConstTerrainOcean) then
                if mState.mData.ArmyData[vExistingOwner, vExisting].GotoX <> -1 then
                    mState.mData.ArmyData[vExistingOwner, vExisting].GotoX := -1;

            if (vTileFlags and ConstTileCity) = 0 then
                mState.mData.ArmyData[vExistingOwner, vExisting].Visibility :=
                    ShortInt(Byte(mState.mData.ArmyData[vExistingOwner, vExisting].Visibility)
                             or vVisBit);

            { TODO: wire to TCivDiplomacy.DiplomacyEvent(ParaOwner, vExistingOwner,
              ParaX, ParaY) once the demo has a diplomacy instance available
              to UnitSight. The C calls this here, before the two gotos below. }
        end;
    end;

    { 3. Wider 5×5 sweep for sight&2 units. }
    for vDir := 9 to 24 do
    begin
        vNX := WrapX(ParaX + ConstSpiralX[vDir]);
        vNY := ParaY + ConstSpiralY[vDir];
        if not MapInBounds(vNX, vNY) then Continue;
        if ((mState.mData.UtTypes[vUnitType].Sight and 2) = 0) then Continue;
        if (mState.mData.UtTypes[vUnitType].Domain = 2) and
           (mWorld.TerrainAt(vNX, vNY) <> ConstTerrainOcean) then Continue;

        mWorld.SetExplored(ParaOwner, vNX, vNY, True);
        mWorld.MapMark(vNX, vNY);

        vExisting := MapStack(vNX, vNY, vExistingOwner);
        vTileFlags := mWorld.MapFlags(vNX, vNY);
        if (vExisting <> -1) and (ParaOwner <> vExistingOwner) then
        begin
            if (vTileFlags and ConstTileCity) = 0 then
                mState.mData.ArmyData[vExistingOwner, vExisting].Visibility :=
                    ShortInt(Byte(mState.mData.ArmyData[vExistingOwner, vExisting].Visibility)
                             or vVisBit);
        end;
    end;

    { 4. Redraw pass (headless: no-op). }
end;

{ -------------------------------------------------------------------------
  EnterHut — the four-way reward roll. The message text is handled by the
  caller via display callbacks; the branch structure is preserved.
  ------------------------------------------------------------------------- }
procedure TCivUnitManager.EnterHut(ParaOwner, ParaIndex: Integer);
var
    vOwnerType, vHomeCity, vDistance, vHutValue, vRoll, vAmount : Integer;
    vBarType, vBarCiv, vBarX, vBarY : Integer;
    vTech, vTries, vNewUnit : Integer;
begin
    if ParaOwner = ConstBarbarianCiv then Exit;
    vOwnerType := mState.mData.ArmyData[ParaOwner, ParaIndex].UnitType;
    if mState.mData.UtTypes[vOwnerType].Domain = 1 then Exit;

    vHomeCity := mWorld.CityAtTile(
        mState.mData.ArmyData[ParaOwner, ParaIndex].X,
        mState.mData.ArmyData[ParaOwner, ParaIndex].Y);
    if (vHomeCity <> -1) and
       (mState.mData.TownBuf[vHomeCity].Owner = ParaOwner) then
        vDistance := 0
    else
        vDistance := 999;

    vHutValue := mWorld.SiteValue(
        mState.mData.ArmyData[ParaOwner, ParaIndex].X,
        mState.mData.ArmyData[ParaOwner, ParaIndex].Y);
    vRoll := mRng.Scaled(4);

    case vRoll of
        0:
        begin
            { Mercenaries, gold, or an advanced tribe. }
            if vDistance < 4 then
            begin
                vNewUnit := CreateUnit(ParaOwner,
                    IfThen(mRng.Scaled(2) <> 0, 3, 6),
                    mState.mData.ArmyData[ParaOwner, ParaIndex].X,
                    mState.mData.ArmyData[ParaOwner, ParaIndex].Y);
                if vNewUnit = -1 then Exit;
            end else if vHutValue <= 4 then
            begin
                mState.mData.Money[ParaOwner] := mState.mData.Money[ParaOwner] + 50;
            end else if Assigned(mCityCreate) then
            begin
                mCityCreate(ParaOwner, 0,
                    mState.mData.ArmyData[ParaOwner, ParaIndex].X,
                    mState.mData.ArmyData[ParaOwner, ParaIndex].Y, 1);
            end;
        end;

        1:
        begin
            { Scrolls of ancient wisdom, or gold on turn zero / after AD 1000. }
            if (mState.mData.TurnTick = 0) or (mState.mData.Year > 1000) then
                mState.mData.Money[ParaOwner] := mState.mData.Money[ParaOwner] + 50
            else
            begin
                vTries := 0;
                repeat
                    vTech := mRng.Scaled(72);
                    { The C's condition here is: not already known AND
                      neither prereq known. Our simplified version accepts
                      any advance the owner has not yet learned; the caller
                      can refine. }
                    if (vTech <> 71) and (not HasAdvance(ParaOwner, vTech)) then
                    begin
                        { give_advance lives on Civ.Economy; the mCityCreate
                          closure covers city creation only. Leave the tech
                          reward to be granted via a second callback if you
                          need it, or drop the branch to gold. }
                        mState.mData.AdvancesKnown[ParaOwner, vTech div 16] :=
                            SmallInt(mState.mData.AdvancesKnown[ParaOwner, vTech div 16]
                                     or SmallInt(1 shl (vTech mod 16)));
                        if mState.mData.TurnTick <> 0 then
                            Inc(mState.mData.TechCount[ParaOwner]);
                        Break;
                    end;
                    Inc(vTries);
                until vTries >= 999;
            end;
        end;

        2:
        begin
            { Valuable metal deposits. }
            mState.mData.Money[ParaOwner] := mState.mData.Money[ParaOwner] + 50;
        end;

        3:
        begin
            { Barbarian horde. }
            if (vDistance < 4) or (mState.mData.CityCount[ParaOwner] = 0) then
            begin
                vNewUnit := CreateUnit(ParaOwner,
                    IfThen(mRng.Scaled(2) <> 0, 3, 6),
                    mState.mData.ArmyData[ParaOwner, ParaIndex].X,
                    mState.mData.ArmyData[ParaOwner, ParaIndex].Y);
                if vNewUnit = -1 then Exit;
            end else
            begin
                vBarCiv := ConstBarbarianCiv;
                for vBarType := 1 to 8 do
                begin
                    vBarX := WrapX(mState.mData.ArmyData[ParaOwner, ParaIndex].X
                                   + ConstSpiralX[vBarType]);
                    vBarY := mState.mData.ArmyData[ParaOwner, ParaIndex].Y
                             + ConstSpiralY[vBarType];
                    if (mWorld.MapOwner(vBarX, vBarY) = -1) and
                       (not mWorld.IsCityTile(vBarX, vBarY)) and
                       (mWorld.TerrainAt(vBarX, vBarY) <> ConstTerrainOcean) then
                    begin
                        if mWorld.TerrainMoveCost(vBarX, vBarY) > 2 then
                            vNewUnit := CreateUnit(vBarCiv, 3, vBarX, vBarY)
                        else
                            vNewUnit := CreateUnit(vBarCiv, 6, vBarX, vBarY);
                        if vNewUnit <> -1 then
                            mState.mData.ArmyData[vBarCiv, vNewUnit].Visibility :=
                                ShortInt(Byte(mState.mData.ArmyData[vBarCiv, vNewUnit].Visibility)
                                         or Byte(1 shl ParaOwner));
                    end;
                end;
            end;
        end;
    end;
end;

end.