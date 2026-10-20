program Civ.Demo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Civ.AI in 'Civ.AI.pas',
  Civ.Cities in 'Civ.Cities.pas',
  Civ.Combat in 'Civ.Combat.pas',
  Civ.Core in 'Civ.Core.pas',
  Civ.Diplomacy in 'Civ.Diplomacy.pas',
  Civ.Economy in 'Civ.Economy.pas',
  Civ.FileCheck in 'Civ.FileCheck.pas',
  Civ.GameData in 'Civ.GameData.pas',
  Civ.GameState in 'Civ.GameState.pas',
  Civ.ImageFormat in 'Civ.ImageFormat.pas',
  Civ.MapFile in 'Civ.MapFile.pas',
  Civ.Mouse in 'Civ.Mouse.pas',
  Civ.NewGame in 'Civ.NewGame.pas',
  Civ.Palette in 'Civ.Palette.pas',
  Civ.Pathfinding in 'Civ.Pathfinding.pas',
  Civ.Raster in 'Civ.Raster.pas',
  Civ.Tables in 'Civ.Tables.pas',
  Civ.Terrains in 'Civ.Terrains.pas',
  Civ.TileYields in 'Civ.TileYields.pas',
  Civ.Timer in 'Civ.Timer.pas',
  Civ.Turn in 'Civ.Turn.pas',
  Civ.Types in 'Civ.Types.pas',
  Civ.Units in 'Civ.Units.pas',
  Civ.World in 'Civ.World.pas',
  Civ.WorldGen in 'Civ.WorldGen.pas';

type
    { Wraps TCivCities so its methods can be passed as method-of-object
      pointers to Civ.AI and Civ.Units. }
    TCityHooks = class
    public
        FCities : TCivCities;
        function CityCreate(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
        function FindSlot(ParaCiv, ParaCity: Integer): Integer;
    end;

var
    gStateCursor : TCivilizationGameState = nil;

function TribeCursor(ParaCiv: Integer): Integer;
begin
    if Assigned(gStateCursor) then
        Result := gStateCursor.mData.CivTribeOf[ParaCiv]
    else
        Result := ParaCiv;
end;

function TCityHooks.CityCreate(
    ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize: Integer): Integer;
begin
    Result := FCities.CityCreate(ParaPlayer, ParaUnused, ParaX, ParaY, ParaSize);
end;

function TCityHooks.FindSlot(ParaCiv, ParaCity: Integer): Integer;
begin
    Result := FCities.FindSlotAI(ParaCiv, ParaCity);
end;

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
        if (ParaState.mData.Players and (1 shl vCiv)) = 0 then Continue;
        if vCiv = ParaState.mData.CivNow then Continue;
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
    Writeln('  --save FILE.SVE  write the final state to FILE.SVE');
end;

var
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

    if not TCivilizationGameState.VerifyLayout(vMsg) then
    begin
        Writeln('Layout FAILURE: ', vMsg);
        Writeln;
        Writeln('Common causes:');
        Writeln('  - BlockGroundWay declared as ShortInt instead of Byte');
        Writeln('  - packed record missing on one of the record types');
        Writeln('  - {$ALIGN} directive altering the default');
        Halt(1);
    end;
    Writeln('Layout OK (SizeOf(TGameStateData) = ', ConstSaveFileSize, ').');

    try
        vState := TCivilizationGameState.Create;
        gStateCursor := vState;
        vMap := TMapPage.Create;
        vWorld := TCivWorld.Create(vState, vMap);

        if vNewGameMode then
            vRng := TCivRandom.Create(12345)
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
            { Coarse sea connectivity is runtime-only; rebuild it after load. }
            vGen.LinkSeas(False);
        end;

        vCombat  := TCivCombat.Create(vWorld, vRng);
        vUnits   := TCivUnitManager.Create(vWorld, vRng);
        vYields  := TCivTileYields.Create(vWorld);
        vCities  := TCivCities.Create(vWorld, vRng);
        vEconomy := TCivEconomy.Create(vWorld, vRng, vCities);
        vAI      := TCivAI.Create(vWorld, vUnits, vCombat, vRng);
        vDiplo   := TCivDiplomacy.Create(vWorld, vRng);
        vTurn    := TCivTurn.Create(vWorld, vRng, vCombat, vUnits,
                                    vCities, vEconomy, vAI, vDiplo);

        { Wire all callbacks. }
        vHooks := TCityHooks.Create;
        vHooks.FCities := vCities;
        TCivTables.SetTribeCursor(TribeCursor);
        vCities.SetUnitHooks(vUnits.CreateUnit, vUnits.DropUnit);
        RegisterCityCreate(vHooks.CityCreate);
        vAI.SetHooks(vHooks.CityCreate, vHooks.FindSlot,
                     vEconomy.AdvanceValue, vDiplo.SetGovernment);

        if vNewGameMode then
        begin
            Writeln('Generating new world...');
            vNewGame := TCivNewGame.Create(vWorld, vRng, vGen, vCities, vUnits);
            var vParams : TNewGameParams;
            vParams.Difficulty  := 1;
            vParams.NumCivs     := 4;
            vParams.PlayerTribe := 1;
            vParams.WorldParams.LandMass    := 1;
            vParams.WorldParams.Temperature := 1;
            vParams.WorldParams.Climate     := 1;
            vParams.WorldParams.Age         := 1;
            vParams.ShowStory   := False;
            vNewGame.Setup(vParams);
            Writeln('World generated.');
        end;

        if vShowMap then
            PrintMap(vWorld);

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

        Writeln;
        Writeln(Format('Final: turn=%d, year=%d, you=%s, %d cities, %d techs, $%d',
            [vState.mData.TurnTick,
             vState.mData.Year,
             vState.CivName(vState.mData.CivNow),
             vState.mData.CityCount[vState.mData.CivNow],
             vState.mData.TechCount[vState.mData.CivNow],
             vState.mData.Money[vState.mData.CivNow]]));
        if not vContinued then
            Writeln('Game ended.');

        if vSaveOut <> '' then
        begin
            Writeln;
            Writeln('Saving final state to ', vSaveOut, '...');
            try
                vState.SaveToFile(vSaveOut);
                Writeln('  wrote ', vSaveOut);
                try
                    vMap.SaveToFile(ChangeFileExt(vSaveOut, '.MAP'));
                    Writeln('  wrote ', ChangeFileExt(vSaveOut, '.MAP'));
                except
                    on E: Exception do
                        Writeln('  MAP save skipped: ', E.Message);
                end;
            except
                on E: Exception do
                    Writeln('  save failed: ', E.Message);
            end;
        end;
    finally
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