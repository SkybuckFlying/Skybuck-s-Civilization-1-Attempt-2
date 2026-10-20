program Civ.Demo;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    System.Classes,
    Civ.Types,
    Civ.Core,
    Civ.GameState,
    Civ.MapFile,
    Civ.World,
    Civ.Terrains,
    Civ.Combat,
    Civ.Units,
    Civ.Pathfinding,
    Civ.TileYields,
    Civ.Cities,
    Civ.Economy,
    Civ.AI,
    Civ.Turn,
    Civ.WorldGen,
    Civ.NewGame,
    Civ.Tables,
    Civ.Diplomacy;

type
    { Wraps TCivCities so that its CityCreate and FindSlotAI methods can be
      passed to Civ.AI (which needs them for settler-found and AI production
      retargeting) and to Civ.Units (which needs CityCreate for the hut's
      "advanced tribe" reward). The wrapper exists because both methods must
      arrive as method-of-object pointers on the *same* instance. }
    TCityHooks = class
    public
        FCities : TCivCities;
        function CityCreate(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
        function FindSlot(ParaCiv, ParaCity: Integer): Integer;
    end;

var
    { Single, process-wide state cursor. Set once after TCivilizationGameState
      is constructed; cleared at program end. The Tribes table uses it to look
      up civ-tribe indices without every table accessor needing a state param.
      A process-wide cursor is safe here because the demo runs single-threaded
      and constructs exactly one game. Multi-game hosts should refactor
      Civ.Tables to take the state explicitly. }
    gStateCursor : TCivilizationGameState = nil;

{ -------------------------------------------------------------------------
  TribeCursor — installed once via TCivTables.SetTribeCursor. Reads from the
  process-wide state. Falls back to identity if called before registration.
  ------------------------------------------------------------------------- }
function TribeCursor(ParaCiv: Integer): Integer;
begin
    if Assigned(gStateCursor) then
        Result := gStateCursor.mData.CivTribeOf[ParaCiv]
    else
        Result := ParaCiv;
end;

{ -------------------------------------------------------------------------
  TCityHooks — forwards to the wrapped TCivCities.
  ------------------------------------------------------------------------- }
function TCityHooks.CityCreate(
    ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
begin
    Result := FCities.CityCreate(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize);
end;

function TCityHooks.FindSlot(ParaCiv, ParaCity: Integer): Integer;
begin
    Result := FCities.FindSlotAI(ParaCiv, ParaCity);
end;

{ -------------------------------------------------------------------------
  PrintMap — ASCII dump of the world. Ocean is a space, terrain uses single
  characters, so a 320×50 block is legible in any console.
  ------------------------------------------------------------------------- }
procedure PrintMap(ParaWorld: TCivWorld);
var
    vX, vY : Integer;
    vLine : string;
begin
    Writeln;
    for vY := 0 to 49 do
    begin
        SetLength(vLine, 80);
        for vX := 0 to 79 do
        begin
            case ParaWorld.TerrainAt(vX, vY) of
                ConstTerrainOcean     : vLine[vX + 1] := ' ';
                ConstTerrainDesert    : vLine[vX + 1] := '.';
                ConstTerrainPlains    : vLine[vX + 1] := ',';
                ConstTerrainGrassland : vLine[vX + 1] := '"';
                ConstTerrainForest    : vLine[vX + 1] := '#';
                ConstTerrainHills     : vLine[vX + 1] := 'n';
                ConstTerrainMountains : vLine[vX + 1] := 'M';
                ConstTerrainTundra    : vLine[vX + 1] := '~';
                ConstTerrainArctic    : vLine[vX + 1] := '*';
                ConstTerrainSwamp     : vLine[vX + 1] := 's';
                ConstTerrainJungle    : vLine[vX + 1] := 'j';
                ConstTerrainRiver     : vLine[vX + 1] := '/';
            else
                vLine[vX + 1] := '?';
            end;
        end;
        Writeln(vLine);
    end;
    Writeln;
end;

{ -------------------------------------------------------------------------
  PrintCivSummary — one line for the human, one line per living rival.
  Government is shown as the numeric ID (0=Anarchy … 5=Democracy) so the
  output stays legible without needing the government_names table here.
  ------------------------------------------------------------------------- }
procedure PrintCivSummary(ParaState: TCivilizationGameState);
var
    vCiv, vActive : Integer;
begin
    Writeln(Format('  You: %-16s gov=%d $%d cities=%d techs=%d',
        [ParaState.CivName(ParaState.mData.CivNow),
         ParaState.mData.CivGov[ParaState.mData.CivNow],
         ParaState.mData.Money[ParaState.mData.CivNow],
         ParaState.mData.CityCount[ParaState.mData.CivNow],
         ParaState.mData.TechCount[ParaState.mData.CivNow]]));

    vActive := 0;
    for vCiv := 1 to 7 do
    begin
        if (ParaState.mData.Players and (1 shl vCiv)) = 0 then
            Continue;
        if vCiv = ParaState.mData.CivNow then
            Continue;
        Inc(vActive);
        Writeln(Format('    [%d] %-16s gov=%d $%d cities=%d techs=%d',
            [vCiv,
             ParaState.CivName(vCiv),
             ParaState.mData.CivGov[vCiv],
             ParaState.mData.Money[vCiv],
             ParaState.mData.CityCount[vCiv],
             ParaState.mData.TechCount[vCiv]]));
    end;
    if vActive = 0 then
        Writeln('    (no rival civs remain)');
end;

{ -------------------------------------------------------------------------
  Usage — printed on missing arguments or bad flags.
  ------------------------------------------------------------------------- }
procedure PrintUsage;
begin
    Writeln('Civ.Demo — headless driver for the Delphi 13 Civilization port');
    Writeln;
    Writeln('Usage:');
    Writeln('  Civ.Demo <file.SVE>              run N turns on an existing save');
    Writeln('  Civ.Demo --new-game              generate a fresh world and run N turns');
    Writeln;
    Writeln('Options:');
    Writeln('  --turns N        number of turns to run (default 20)');
    Writeln('  --show-map       print an ASCII dump of the world after setup');
    Writeln('  --save FILE.SVE  write the final state to FILE.SVE and FILE.MAP');
end;

{ -------------------------------------------------------------------------
  Main.
  ------------------------------------------------------------------------- }
var
    { Full object graph. Nil-initialised before the try so that partial
      construction (e.g. LoadFromFile raising) leaves the finally block
      safe to run. }
    vState   : TCivilizationGameState = nil;
    vMap     : TMapPage               = nil;
    vWorld   : TCivWorld              = nil;
    vRng     : TCivRandom             = nil;
    vGen     : TCivWorldGen           = nil;
    vPath    : TCivPathfinder         = nil;
    vCombat  : TCivCombat             = nil;
    vUnits   : TCivUnitManager        = nil;
    vYields  : TCivTileYields         = nil;
    vCities  : TCivCities             = nil;
    vEconomy : TCivEconomy            = nil;
    vAI      : TCivAI                 = nil;
    vDiplo   : TCivDiplomacy          = nil;
    vTurn    : TCivTurn               = nil;
    vNewGame : TCivNewGame            = nil;
    vHooks   : TCityHooks             = nil;

    vTurns       : Integer;
    vNewGameMode : Boolean;
    vShowMap     : Boolean;
    vSaveFile    : string;
    vSaveOut     : string;
    vMsg         : string;
    vI           : Integer;
    vContinued   : Boolean;
begin
    { ---- Argument parsing. ---------------------------------------------- }
    vTurns := 20;
    vNewGameMode := False;
    vShowMap := False;
    vSaveFile := '';
    vSaveOut := '';

    vI := 1;
    while vI <= ParamCount do
    begin
        if ParamStr(vI) = '--new-game' then
            vNewGameMode := True
        else if ParamStr(vI) = '--show-map' then
            vShowMap := True
        else if (ParamStr(vI) = '--turns') and (vI < ParamCount) then
        begin
            Inc(vI);
            vTurns := StrToIntDef(ParamStr(vI), 20);
        end
        else if (ParamStr(vI) = '--save') and (vI < ParamCount) then
        begin
            Inc(vI);
            vSaveOut := ParamStr(vI);
        end
        else if (ParamStr(vI) = '--help') or (ParamStr(vI) = '-h') then
        begin
            PrintUsage;
            Halt(0);
        end
        else if (Length(ParamStr(vI)) > 0) and (ParamStr(vI)[1] <> '-') then
            vSaveFile := ParamStr(vI)
        else
        begin
            Writeln('Unknown option: ', ParamStr(vI));
            PrintUsage;
            Halt(2);
        end;
        Inc(vI);
    end;

    if (not vNewGameMode) and (vSaveFile = '') then
    begin
        PrintUsage;
        Halt(2);
    end;
    if vTurns < 0 then
        vTurns := 0;

    { ---- Layout verification. ------------------------------------------- }
    if not TCivilizationGameState.VerifyLayout(vMsg) then
    begin
        Writeln('Layout FAILURE: ', vMsg);
        Writeln;
        Writeln('The packed record does not match the SVE offset table.');
        Writeln('Common causes:');
        Writeln('  - BlockGroundWay declared as ShortInt instead of Byte');
        Writeln('  - packed record missing on one of the record types');
        Writeln('  - {$ALIGN} directive altering the default');
        Halt(1);
    end;
    Writeln('Layout OK (SizeOf(TGameStateData) = ', ConstSaveFileSize, ').');

    try
        { ---- Build the graph. ------------------------------------------- }
        vState := TCivilizationGameState.Create;
        gStateCursor := vState;
        vMap := TMapPage.Create;
        vWorld := TCivWorld.Create(vState, vMap);

        if vNewGameMode then
        begin
            { Deterministic for the demo so that repeated runs produce the
              same map and can be diffed. Change the seed for variety. }
            vRng := TCivRandom.Create(12345);
        end
        else
        begin
            Writeln('Loading ', ExtractFileName(vSaveFile), '...');
            vState.LoadFromFile(vSaveFile);
            try
                vMap.LoadFromFile(ChangeFileExt(vSaveFile, '.MAP'));
            except
                on E: Exception do
                begin
                    Writeln('  warning: MAP file not loaded: ', E.Message);
                    vMap.Clear;
                end;
            end;
            vRng := TCivRandom.Create(vState.mData.MapRngState);
        end;

        vPath := TCivPathfinder.Create(vWorld);
        vGen  := TCivWorldGen.Create(vWorld, vRng, vPath);

        if not vNewGameMode then
        begin
            { Coarse ocean connectivity is runtime state; it is not in the
              SVE. The land connectivity (BlockGroundWay) *is* saved, so
              only LinkSeas needs to run. }
            vGen.LinkSeas(False);
        end;

        { Services. Order is informational: they hold references but do
          not call each other during construction. }
        vCombat  := TCivCombat.Create(vWorld, vRng);
        vUnits   := TCivUnitManager.Create(vWorld, vRng);
        vYields  := TCivTileYields.Create(vWorld);
        vCities  := TCivCities.Create(vWorld, vRng);
        vEconomy := TCivEconomy.Create(vWorld, vRng, vCities);
        vAI      := TCivAI.Create(vWorld, vUnits, vCombat, vRng);
        vDiplo   := TCivDiplomacy.Create(vWorld, vRng);
        vTurn    := TCivTurn.Create(vWorld, vRng, vCombat, vUnits,
                                    vCities, vEconomy, vAI, vDiplo);

        { ---- Wire every callback before any turn can run. --------------- }
        vHooks := TCityHooks.Create;
        vHooks.FCities := vCities;

        TCivTables.SetTribeCursor(TribeCursor);
        vCities.SetUnitHooks(vUnits.CreateUnit, vUnits.DropUnit);
        vUnits.RegisterCityCreate(vHooks.CityCreate);
        vAI.SetHooks(vHooks.CityCreate, vHooks.FindSlot,
                     vEconomy.AdvanceValue, vDiplo.SetGovernment);

        { ---- New-game setup (needs the services above to be alive). ----- }
        if vNewGameMode then
        begin
            Writeln('Generating new world...');
            vNewGame := TCivNewGame.Create(vWorld, vRng, vGen, vCities, vUnits);

            var vParams : TNewGameParams;
            vParams.Difficulty  := 1;      { Warlord }
            vParams.NumCivs     := 4;      { 5 total civs (you + 4 rivals) }
            vParams.PlayerTribe := 1;      { Romans }
            vParams.WorldParams.LandMass    := 1;
            vParams.WorldParams.Temperature := 1;
            vParams.WorldParams.Climate     := 1;
            vParams.WorldParams.Age         := 1;
            vParams.ShowStory   := False;

            vNewGame.Setup(vParams);
            Writeln('World generated.');
        end;

        { ---- Optional map dump. ----------------------------------------- }
        if vShowMap then
            PrintMap(vWorld);

        { ---- Run. ------------------------------------------------------- }
        Writeln;
        Writeln(Format('=== Turn %d (year %d) ===',
            [vState.mData.TurnTick, vState.mData.Year]));
        PrintCivSummary(vState);

        vContinued := True;
        for vI := 1 to vTurns do
        begin
            if not vTurn.GameTurn then
            begin
                Writeln;
                Writeln('*** GAME ENDED at turn ', vState.mData.TurnTick, ' ***');
                vContinued := False;
                Break;
            end;

            Writeln;
            Writeln(Format('=== Turn %d (year %d) ===',
                [vState.mData.TurnTick, vState.mData.Year]));
            PrintCivSummary(vState);

            if vTurn.LastMessages.Count > 0 then
            begin
                for var vMsgLine := 0 to vTurn.LastMessages.Count - 1 do
                    Writeln('    * ', vTurn.LastMessages[vMsgLine]);
                vTurn.LastMessages.Clear;
            end;
        end;

        { ---- Wrap up. --------------------------------------------------- }
        Writeln;
        Writeln(Format('Final: turn=%d, year=%d, you=%s, %d cities, %d techs, $%d',
            [vState.mData.TurnTick,
             vState.mData.Year,
             vState.CivName(vState.mData.CivNow),
             vState.mData.CityCount[vState.mData.CivNow],
             vState.mData.TechCount[vState.mData.CivNow],
             vState.mData.Money[vState.mData.CivNow]]));
        if not vContinued then
            Writeln('Game ended (ship arrival or dynasty end).');

        { ---- Optional save-out. ----------------------------------------- }
        if vSaveOut <> '' then
        begin
            Writeln;
            Writeln('Saving final state to ', vSaveOut, '...');
            try
                vState.SaveToFile(vSaveOut);
                vMap.SaveToFile(ChangeFileExt(vSaveOut, '.MAP'));
                Writeln('  wrote ', vSaveOut);
                Writeln('  wrote ', ChangeFileExt(vSaveOut, '.MAP'));
            except
                on E: Exception do
                    Writeln('  save failed: ', E.Message);
            end;
        end;
    finally
        { Free in reverse dependency order. Every field is either assigned
          or still nil; TObject.Free handles nil gracefully. }
        vHooks.Free;
        vNewGame.Free;
        vTurn.Free;
        vDiplo.Free;
        vAI.Free;
        vEconomy.Free;
        vCities.Free;
        vYields.Free;
        vGen.Free;
        vPath.Free;
        vUnits.Free;
        vCombat.Free;
        vRng.Free;
        vWorld.Free;
        vMap.Free;
        vState.Free;
        gStateCursor := nil;
    end;
end.