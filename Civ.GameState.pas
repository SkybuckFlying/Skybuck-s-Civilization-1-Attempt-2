unit Civ.GameState;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes,
    Civ.Types;

type
    ECivSaveFileError = class(Exception);

const
    ConstCivCount        = 8;
    ConstCitySlots       = 128;
    ConstUnitSlots       = 128;
    ConstUnitTypeCount   = 28;
    ConstTechCount       = 72;
    ConstImprovementCount= 46;
    ConstWonderCount     = 21;
    ConstMapWidth        = 80;
    ConstMapHeight       = 50;
    ConstContinentCount  = 16;

    ConstSaveFileSize    = 37856;   { 0x93e0 }

type
    { Byte-for-byte SVE layout. `packed record` prevents the compiler from
      inserting padding; VerifyLayout checks the offsets that matter most. }
    TGameStateData = packed record
        // --- Header (16 bytes @ 0x0000)
        TurnTick            : SmallInt;
        CivNow              : SmallInt;
        HumanSet            : SmallInt;
        MapRngState         : SmallInt;
        Year                : SmallInt;
        CurTier             : SmallInt;
        Players             : SmallInt;
        SelectedIndex       : SmallInt;

        // --- Names (296 bytes @ 0x0010)
        LeaderNames         : array[0..7] of TCStr14;
        CivNames            : array[0..7] of TCStr12;
        CivAdjectives       : array[0..7] of array[0..10] of AnsiChar;

        // --- Per-civ scalar arrays
        Money               : array[0..7] of SmallInt;
        CivResearchTally    : array[0..7] of SmallInt;
        ForcesPresent       : array[0..7, 0..27] of SmallInt;
        CivUnitsOrdered     : array[0..7, 0..27] of SmallInt;
        TechCount           : array[0..7] of SmallInt;
        AdvancesKnown       : array[0..7, 0..4] of SmallInt;
        CivGov              : array[0..7] of SmallInt;
        CivAreaPlan         : array[0..7, 0..15] of SmallInt;
        Treaties            : array[0..7, 0..7] of SmallInt;
        CityCount           : array[0..7] of SmallInt;
        TroopsTotal         : array[0..7] of SmallInt;
        CivHeldCells        : array[0..7] of SmallInt;
        CivSettlersN        : array[0..7] of SmallInt;
        Citizens            : array[0..7] of SmallInt;
        MilitaryTable       : array[0..7] of SmallInt;
        NationRatings       : array[0..7] of SmallInt;
        CivToll             : array[0..7] of SmallInt;
        CivRatings          : array[0..7] of SmallInt;
        LastMetTurn         : array[0..7] of SmallInt;
        XCap                : array[0..7] of SmallInt;
        CivTribeOf          : array[0..7] of SmallInt;
        DefendersIsland     : array[0..7, 0..15] of SmallInt;
        CivContAttackers    : array[0..7, 0..15] of SmallInt;
        AiContinentTowns    : array[0..7, 0..15] of SmallInt;
        ContinentSpan       : array[0..1, 0..63] of SmallInt;
        AiZonePlaces        : array[0..15] of SmallInt;

        // --- Far arrays
        PowerHistory        : array[0..149, 0..7] of Byte;
        WarRecord           : array[0..149, 0..7] of Byte;

        // --- Core record arrays
        TownBuf             : array[0..127] of TCity;
        UtTypes             : array[0..27] of TUnitType;
        ArmyData            : array[0..7, 0..127] of TUnit;

        // --- Exploration + AI memory
        MapVisibleTo        : array[0..79, 0..49] of ShortInt;
        SpotClasses         : array[0..7, 0..15] of ShortInt;
        AiCampSiteWeights   : array[0..7, 0..15] of ShortInt;
        CampXPos            : array[0..7, 0..15] of ShortInt;
        CivLotY             : array[0..7, 0..15] of ShortInt;
        AdvanceOwners       : array[0..71] of SmallInt;
        Killed              : array[0..7, 0..7] of SmallInt;
        PlaceName           : array[0..255] of TCStr13;
        ReplayLength        : SmallInt;
        ReplayLog           : array[0..4095] of ShortInt;
        MarvelSite          : array[0..21] of SmallInt;
        UnitLosses          : array[0..7, 0..27] of SmallInt;
        AdvSource           : array[0..7, 0..71] of ShortInt;

        // --- Environment / globals
        Polluted            : SmallInt;
        WarmLevels          : SmallInt;
        Warming             : SmallInt;
        Debug               : SmallInt;
        BlockGroundWay      : array[0..19, 0..12] of Byte;   { unsigned in C }
        MaxRating           : SmallInt;
        AdvancesFuture      : SmallInt;
        RuleOptions         : SmallInt;
        Sci                 : array[0..7] of SmallInt;
        NextEventTurn       : SmallInt;
        HistoryRating       : array[0..7] of SmallInt;

        // --- Spaceship
        Spaceships          : array[0..7, 0..14, 0..11] of ShortInt;
        GameFlags           : SmallInt;
        ShipSuccess         : SmallInt;
        AiShipSuccess       : SmallInt;
        SpaceshipArriveDates: array[0..7] of SmallInt;
        FloorsPalace        : array[0..11] of SmallInt;
        SectionGrades       : array[0..11] of SmallInt;
        CitySiteX           : array[0..255] of ShortInt;
        CitySiteY           : array[0..255] of ShortInt;
        PalaceStage         : SmallInt;
        PlayerPeaceRun      : SmallInt;
        CivTotal            : SmallInt;
        SpaceShipHabitation : array[0..7] of SmallInt;
        LiftoffWhen         : array[0..7] of SmallInt;
        CivFlagsBits        : SmallInt;
    end;

    TCivilizationGameState = class
    public
        { Public because it is a raw record container, not a service; adding
          per-field properties would be pure boilerplate. }
        mData : TGameStateData;

        constructor Create;
        procedure Clear;

        procedure LoadFromFile(const ParaFileName: string);
        procedure SaveToFile(const ParaFileName: string);
        procedure LoadFromStream(ParaStream: TStream);
        procedure SaveToStream(ParaStream: TStream);

        function LeaderName(ParaCiv: Integer): string;
        function CivName(ParaCiv: Integer): string;
        function CivAdjective(ParaCiv: Integer): string;
        function HasAdvance(ParaCiv, ParaAdvance: Integer): Boolean;
        function ActiveCities(ParaCiv: Integer): Integer;

        class function VerifyLayout(out ParaMessage: string): Boolean;
    end;

implementation

{ `VerifyLayout` is called by the demo before anything else. `AssertLayout`
  runs once at unit initialization so layout errors surface even in debug
  builds that fail early. Both use NativeUInt to compute offsets —
  PtrUInt / PtrInt are not declared in Delphi 13's System unit. }
procedure AssertLayout;
var
    vD : TGameStateData;
    vBase : NativeUInt;
    vB : TCivilizationGameState;
begin
    vBase := NativeUInt(@vD);
    Assert(NativeUInt(@vD.TurnTick            ) - vBase = $0000);
    Assert(NativeUInt(@vD.CivNow              ) - vBase = $0002);
    Assert(NativeUInt(@vD.HumanSet            ) - vBase = $0004);
    Assert(NativeUInt(@vD.LeaderNames         ) - vBase = $0010);
    Assert(NativeUInt(@vD.CivNames            ) - vBase = $0080);
    Assert(NativeUInt(@vD.CivAdjectives       ) - vBase = $00E0);
    Assert(NativeUInt(@vD.Money               ) - vBase = $0138);
    Assert(NativeUInt(@vD.ForcesPresent       ) - vBase = $0158);
    Assert(NativeUInt(@vD.AdvancesKnown       ) - vBase = $04E8);
    Assert(NativeUInt(@vD.Treaties            ) - vBase = $0648);
    Assert(NativeUInt(@vD.CivTribeOf          ) - vBase = $0778);
    Assert(NativeUInt(@vD.PowerHistory        ) - vBase = $0BA8);
    Assert(NativeUInt(@vD.WarRecord           ) - vBase = $1058);
    Assert(NativeUInt(@vD.TownBuf             ) - vBase = $1508);
    Assert(NativeUInt(@vD.UtTypes             ) - vBase = $2308);
    Assert(NativeUInt(@vD.ArmyData            ) - vBase = $26C0);
    Assert(NativeUInt(@vD.MapVisibleTo        ) - vBase = $56C0);
    Assert(NativeUInt(@vD.AdvanceOwners       ) - vBase = $6860);
    Assert(NativeUInt(@vD.PlaceName           ) - vBase = $6970);
    Assert(NativeUInt(@vD.ReplayLength        ) - vBase = $7670);
    Assert(NativeUInt(@vD.MarvelSite          ) - vBase = $8672);
    Assert(NativeUInt(@vD.Polluted            ) - vBase = $8A9E);
    Assert(NativeUInt(@vD.Spaceships          ) - vBase = $8BD2);
    Assert(NativeUInt(@vD.GameFlags           ) - vBase = $9172);
    Assert(NativeUInt(@vD.CitySiteX           ) - vBase = $91B8);
    Assert(NativeUInt(@vD.CivFlagsBits        ) - vBase = $93DE);
    Assert(SizeOf(TGameStateData) = ConstSaveFileSize);
    vB := nil;
    if vB <> nil then
        Assert(False);
end;

constructor TCivilizationGameState.Create;
begin
    inherited Create;
    Clear;
end;

procedure TCivilizationGameState.Clear;
begin
    FillChar(mData, SizeOf(mData), 0);
end;

procedure TCivilizationGameState.LoadFromFile(const ParaFileName: string);
var
    vStream : TFileStream;
begin
    vStream := TFileStream.Create(ParaFileName, fmOpenRead or fmShareDenyNone);
    try
        LoadFromStream(vStream);
    finally
        vStream.Free;
    end;
end;

procedure TCivilizationGameState.SaveToFile(const ParaFileName: string);
var
    vStream : TFileStream;
begin
    vStream := TFileStream.Create(ParaFileName, fmCreate);
    try
        SaveToStream(vStream);
    finally
        vStream.Free;
    end;
end;

procedure TCivilizationGameState.LoadFromStream(ParaStream: TStream);
var
    vRead : Int64;
begin
    if ParaStream.Size <> ConstSaveFileSize then
    begin
        raise ECivSaveFileError.CreateFmt(
            'SVE file size mismatch: expected %d bytes, got %d',
            [ConstSaveFileSize, ParaStream.Size]);
    end;
    ParaStream.Position := 0;
    vRead := ParaStream.Read(mData, ConstSaveFileSize);
    if vRead <> ConstSaveFileSize then
    begin
        raise ECivSaveFileError.CreateFmt(
            'SVE short read: got %d of %d bytes',
            [vRead, ConstSaveFileSize]);
    end;
end;

procedure TCivilizationGameState.SaveToStream(ParaStream: TStream);
begin
    ParaStream.WriteBuffer(mData, ConstSaveFileSize);
end;

function TCivilizationGameState.LeaderName(ParaCiv: Integer): string;
begin
    Result := FixedCharsToStringTrim(mData.LeaderNames[ParaCiv]);
end;

function TCivilizationGameState.CivName(ParaCiv: Integer): string;
begin
    Result := FixedCharsToStringTrim(mData.CivNames[ParaCiv]);
end;

function TCivilizationGameState.CivAdjective(ParaCiv: Integer): string;
begin
    Result := FixedCharsToStringTrim(mData.CivAdjectives[ParaCiv]);
end;

function TCivilizationGameState.HasAdvance(ParaCiv, ParaAdvance: Integer): Boolean;
var
    vWord : Integer;
    vBit  : SmallInt;
begin
    if (ParaCiv < 0) or (ParaCiv > 7) or (ParaAdvance < 0) or
       (ParaAdvance >= ConstTechCount) then
    begin
        Result := False;
        Exit;
    end;
    vWord := ParaAdvance div 16;
    vBit  := SmallInt(1 shl (ParaAdvance mod 16));
    Result := (mData.AdvancesKnown[ParaCiv, vWord] and vBit) <> 0;
end;

function TCivilizationGameState.ActiveCities(ParaCiv: Integer): Integer;
var
    vI : Integer;
begin
    Result := 0;
    for vI := 0 to ConstCitySlots - 1 do
    begin
        if (mData.TownBuf[vI].Status <> -1) and
           (mData.TownBuf[vI].Owner = ParaCiv) then
        begin
            Inc(Result);
        end;
    end;
end;

class function TCivilizationGameState.VerifyLayout(out ParaMessage: string): Boolean;
var
    vD : TGameStateData;
    vBase : NativeUInt;
begin
    vBase := NativeUInt(@vD);
    ParaMessage := '';
    if SizeOf(TGameStateData) <> ConstSaveFileSize then
    begin
        ParaMessage := Format('SizeOf(TGameStateData) = %d, expected %d',
            [SizeOf(TGameStateData), ConstSaveFileSize]);
        Exit(False);
    end;
    if NativeUInt(@vD.TownBuf) - vBase <> $1508 then
    begin
        ParaMessage := 'TownBuf offset mismatch';
        Exit(False);
    end;
    if NativeUInt(@vD.ArmyData) - vBase <> $26C0 then
    begin
        ParaMessage := 'ArmyData offset mismatch';
        Exit(False);
    end;
    if NativeUInt(@vD.MapVisibleTo) - vBase <> $56C0 then
    begin
        ParaMessage := 'MapVisibleTo offset mismatch';
        Exit(False);
    end;
    Result := True;
end;

initialization
    AssertLayout;

end.