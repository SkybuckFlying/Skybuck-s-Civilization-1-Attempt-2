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
    Civ.Combat,
    Civ.Units,
    Civ.Pathfinding,
    Civ.TileYields,
    Civ.Cities,
    Civ.Economy,
    Civ.AI,
    Civ.Turn;

const
    ConstTurns = 20;

type
    { Console logger. Every ShowMsg ends up here. }
    TDemoTurn = class(TCivTurn)
    public
        procedure Log(const ParaText: string);
    end;

procedure TDemoTurn.Log(const ParaText: string);
begin
    Writeln('  > ', ParaText);
end;

var
    gState   : TCivilizationGameState;
    gMap     : TMapPage;
    gWorld   : TCivWorld;
    gRng     : TCivRandom;
    gCombat  : TCivCombat;
    gUnits   : TCivUnitManager;
    gPath    : TCivPathfinder;
    gYields  : TCivTileYields;
    gCities  : TCivCities;
    gEconomy : TCivEconomy;
    gAI      : TCivAI;
    gTurn    : TDemoTurn;
    gI       : Integer;
    gMessage : string;
    gSaveFile: string;
    gMapFile : string;
begin
    if ParamCount < 1 then
    begin
        Writeln('Usage: Civ.Demo <file.SVE>');
        Halt(2);
    end;
    gSaveFile := ParamStr(1);

    { Layout check. }
    if not TCivilizationGameState.VerifyLayout(gMessage) then
    begin
        Writeln('Layout FAILURE: ', gMessage);
        Halt(1);
    end;
    Writeln('Layout OK. Loading ', ExtractFileName(gSaveFile));

    gState := TCivilizationGameState.Create;
    gMap   := TMapPage.Create;
    try
        gState.LoadFromFile(gSaveFile);
        gMapFile := ChangeFileExt(gSaveFile, '.MAP');
        try
            gMap.LoadFromFile(gMapFile);
        except
            on E: Exception do
            begin
                Writeln('Warning: MAP file not loaded (', E.Message, ')');
                gMap.Clear;
            end;
        end;

        gWorld   := TCivWorld.Create(gState, gMap);
        gRng     := TCivRandom.Create(gState.mData.MapRngState);
        gCombat  := TCivCombat.Create(gWorld, gRng);
        gUnits   := TCivUnitManager.Create(gWorld, gRng);
        gPath    := TCivPathfinder.Create(gWorld);
        gYields  := TCivTileYields.Create(gWorld);
        gCities  := TCivCities.Create(gWorld, gRng);
        gEconomy := TCivEconomy.Create(gWorld, gRng, gCities);
        gAI      := TCivAI.Create(gWorld, gUnits, gCombat, gRng);
        gTurn    := TDemoTurn.Create(gWorld, gRng, gCombat, gUnits,
                                     gCities, gEconomy, gAI);

        Writeln(Format('Loaded: turn=%d, year=%d, you=%s, players=$%s',
            [gState.mData.TurnTick, gState.mData.Year,
             gState.CivName(gState.mData.CivNow),
             IntToHex(gState.mData.Players, 4)]));

        for gI := 1 to ConstTurns do
        begin
            Writeln;
            Writeln(Format('=== Turn %d (year %d) ===',
                [gState.mData.TurnTick, gState.mData.Year]));

            if not gTurn.GameTurn then
            begin
                Writeln('Game ended.');
                Break;
            end;

            { Print post-turn summary. }
            Writeln(Format('  You now have: $%d, %d cities, %d techs',
                [gState.mData.Money[gState.mData.CivNow],
                 gState.mData.CityCount[gState.mData.CivNow],
                 gState.mData.TechCount[gState.mData.CivNow]]));

            var vLeaderCount := 0;
            for var vCiv := 1 to 7 do
            begin
                if (gState.mData.Players and (1 shl vCiv)) <> 0 then
                begin
                    Inc(vLeaderCount);
                    Writeln(Format('    [%d] %-14s cities=%d techs=%d $%d',
                        [vCiv,
                         gState.LeaderName(vCiv),
                         gState.ActiveCities(vCiv),
                         gState.mData.TechCount[vCiv],
                         gState.mData.Money[vCiv]]));
                end;
            end;
            if vLeaderCount = 0 then
                Writeln('  (no active civs)');
        end;

        Writeln;
        Writeln('Done. Final state: turn=', gState.mData.TurnTick,
                ' year=', gState.mData.Year);
    finally
        gTurn.Free;
        gAI.Free;
        gEconomy.Free;
        gCities.Free;
        gYields.Free;
        gPath.Free;
        gUnits.Free;
        gCombat.Free;
        gRng.Free;
        gWorld.Free;
        gMap.Free;
        gState.Free;
    end;
end.