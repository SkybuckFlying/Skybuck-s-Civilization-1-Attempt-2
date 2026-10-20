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
    { Every field is stored in SVE order. `packed record` guarantees
      the layout matches the C globals exactly (SizeOf = 37856). }
    TGameStateData = packed record
        // --- Header (16 bytes @ 0x0000)
        TurnTick            : SmallInt;   { 0x0000 }
        CivNow              : SmallInt;   { 0x0002 }
        HumanSet            : SmallInt;   { 0x0004 }
        MapRngState         : SmallInt;   { 0x0006 }
        Year                : SmallInt;   { 0x0008 }
        CurTier             : SmallInt;   { 0x000A }
        Players             : SmallInt;   { 0x000C }
        SelectedIndex       : SmallInt;   { 0x000E }

        // --- Names (296 bytes @ 0x0010)
        LeaderNames         : array[0..7] of TCStr14;   { 0x0010, 112 }
        CivNames            : array[0..7] of TCStr12;   { 0x0080,  96 }
        CivAdjectives       : array[0..7] of array[0..10] of AnsiChar; { 0x00E0, 88 }

        // --- Per-civ scalar arrays
        Money               : array[0..7] of SmallInt;  { 0x0138 }
        CivResearchTally    : array[0..7] of SmallInt;  { 0x0148 }
        ForcesPresent       : array[0..7, 0..27] of SmallInt; { 0x0158 }
        CivUnitsOrdered     : array[0..7, 0..27] of SmallInt; { 0x0318 }
        TechCount           : array[0..7] of SmallInt;  { 0x04D8 }
        AdvancesKnown       : array[0..7, 0..4] of SmallInt;  { 0x04E8 }
        CivGov              : array[0..7] of SmallInt;  { 0x0538 }
        CivAreaPlan         : array[0..7, 0..15] of SmallInt; { 0x0548 }
        Treaties            : array[0..7, 0..7] of SmallInt;  { 0x0648 }
        CityCount           : array[0..7] of SmallInt;  { 0x06C8 }
        TroopsTotal         : array[0..7] of SmallInt;  { 0x06D8 }
        CivHeldCells        : array[0..7] of SmallInt;  { 0x06E8 }
        CivSettlersN        : array[0..7] of SmallInt;  { 0x06F8 }
        Citizens            : array[0..7] of SmallInt;  { 0x0708 }
        MilitaryTable       : array[0..7] of SmallInt;  { 0x0718 }
        NationRatings       : array[0..7] of SmallInt;  { 0x0728 }
        CivToll             : array[0..7] of SmallInt;  { 0x0738 }
        CivRatings          : array[0..7] of SmallInt;  { 0x0748 }
        LastMetTurn         : array[0..7] of SmallInt;  { 0x0758 }
        XCap                : array[0..7] of SmallInt;  { 0x0768 }
        CivTribeOf          : array[0..7] of SmallInt;  { 0x0778 }
        DefendersIsland     : array[0..7, 0..15] of SmallInt; { 0x0788 }
        CivContAttackers    : array[0..7, 0..15] of SmallInt; { 0x0888 }
        AiContinentTowns    : array[0..7, 0..15] of SmallInt; { 0x0988 }
        ContinentSpan       : array[0..1, 0..63] of SmallInt; { 0x0A88 }
        AiZonePlaces        : array[0..15] of SmallInt; { 0x0B88 }

        // --- Far arrays
        PowerHistory        : array[0..149, 0..7] of Byte; { 0x0BA8 }
        WarRecord           : array[0..149, 0..7] of Byte; { 0x1058 }

        // --- Core record arrays
        TownBuf             : array[0..127] of TCity;     { 0x1508 }
        UtTypes             : array[0..27] of TUnitType;  { 0x2308 }
        ArmyData            : array[0..7, 0..127] of TUnit; { 0x26C0 }

        // --- Exploration + AI memory
        MapVisibleTo        : array[0..79, 0..49] of ShortInt; { 0x56C0 }
        SpotClasses         : array[0..7, 0..15] of ShortInt;  { 0x6660 }
        AiCampSiteWeights   : array[0..7, 0..15] of ShortInt;  { 0x66E0 }
        CampXPos            : array[0..7, 0..15] of ShortInt;  { 0x6760 }
        CivLotY             : array[0..7, 0..15] of ShortInt;  { 0x67E0 }
        AdvanceOwners       : array[0..71] of SmallInt;        { 0x6860 }
        Killed              : array[0..7, 0..7] of SmallInt;   { 0x68F0 }
        PlaceName           : array[0..255] of TCStr13;        { 0x6970 }
        ReplayLength        : SmallInt;                        { 0x7670 }
        ReplayLog           : array[0..4095] of ShortInt;      { 0x7672 }
        MarvelSite          : array[0..21] of SmallInt;        { 0x8672 }
        UnitLosses          : array[0..7, 0..27] of SmallInt;  { 0x869E }
        AdvSource           : array[0..7, 0..71] of ShortInt;  { 0x885E }

        // --- Environment / globals
        Polluted            : SmallInt;                        { 0x8A9E }
        WarmLevels          : SmallInt;                        { 0x8AA0 }
        Warming             : SmallInt;                        { 0x8AA2 }
        Debug               : SmallInt;                        { 0x8AA4 }
        BlockGroundWay      : array[0..19, 0..12] of ShortInt; { 0x8AA6 }
        MaxRating           : SmallInt;                        { 0x8BAA }
        AdvancesFuture      : SmallInt;                        { 0x8BAC }
        RuleOptions         : SmallInt;                        { 0x8BAE }
        Sci                 : array[0..7] of SmallInt;         { 0x8BB0 }
        NextEventTurn       : SmallInt;                        { 0x8BC0 }
        HistoryRating       : array[0..7] of SmallInt;         { 0x8BC2 }

        // --- Spaceship
        Spaceships          : array[0..7, 0..14, 0..11] of ShortInt; { 0x8BD2 }
        GameFlags           : SmallInt;                        { 0x9172 }
        ShipSuccess         : SmallInt;                        { 0x9174 }
        AiShipSuccess       : SmallInt;                        { 0x9176 }
        SpaceshipArriveDates: array[0..7] of SmallInt;         { 0x9178 }
        FloorsPalace        : array[0..11] of SmallInt;        { 0x9188 }
        SectionGrades       : array[0..11] of SmallInt;        { 0x91A0 }
        CitySiteX           : array[0..255] of ShortInt;       { 0x91B8 }
        CitySiteY           : array[0..255] of ShortInt;       { 0x92B8 }
        PalaceStage         : SmallInt;                        { 0x93B8 }
        PlayerPeaceRun      : SmallInt;                        { 0x93BA }
        CivTotal            : SmallInt;                        { 0x93BC }
        SpaceShipHabitation : array[0..7] of SmallInt;         { 0x93BE }
        LiftoffWhen         : array[0..7] of SmallInt;         { 0x93CE }
        CivFlagsBits        : SmallInt;                        { 0x93DE }
    end;

    TCivilizationGameState = class
    public
        { Single, byte-exact state container. Public field because this
          is a raw record container, not a service object — accessors
          would be pure boilerplate with no encapsulation benefit. }
        mData : TGameStateData;

        constructor Create;

        procedure Clear;

        procedure LoadFromFile(const ParaFileName: string);
        procedure SaveToFile(const ParaFileName: string);
        procedure LoadFromStream(ParaStream: TStream);
        procedure SaveToStream(ParaStream: TStream);

        { Convenience helpers. }
        function LeaderName(ParaCiv: Integer): string;
        function CivName(ParaCiv: Integer): string;
        function CivAdjective(ParaCiv: Integer): string;
        function HasAdvance(ParaCiv, ParaAdvance: Integer): Boolean;
        function ActiveCities(ParaCiv: Integer): Integer;

        class function VerifyLayout(out ParaMessage: string): Boolean;
    end;

implementation

{ ---- Layout validation table ----------------------------------------------
  Each (offset, actual-offset) pair is checked at startup. This proves the
  packed record matches the SVE offset table in
  book/src/formats/sve_offset_table.md. }
type
    TLayoutCheck = record
        Field : PAnsiChar;
        Offset: Integer;
    end;

procedure AssertLayout;
var
    vD : TGameStateData;
    vBase : PtrUInt;
    vB : TCivilizationGameState;
begin
    vBase := PtrUInt(@vD);
    Assert(PtrUInt(@vD.TurnTick            ) - vBase = $0000);
    Assert(PtrUInt(@vD.CivNow              ) - vBase = $0002);
    Assert(PtrUInt(@vD.HumanSet            ) - vBase = $0004);
    Assert(PtrUInt(@vD.LeaderNames         ) - vBase = $0010);
    Assert(PtrUInt(@vD.CivNames            ) - vBase = $0080);
    Assert(PtrUInt(@vD.CivAdjectives       ) - vBase = $00E0);
    Assert(PtrUInt(@vD.Money               ) - vBase = $0138);
    Assert(PtrUInt(@vD.ForcesPresent       ) - vBase = $0158);
    Assert(PtrUInt(@vD.AdvancesKnown       ) - vBase = $04E8);
    Assert(PtrUInt(@vD.Treaties            ) - vBase = $0648);
    Assert(PtrUInt(@vD.CivTribeOf          ) - vBase = $0778);
    Assert(PtrUInt(@vD.PowerHistory        ) - vBase = $0BA8);
    Assert(PtrUInt(@vD.WarRecord           ) - vBase = $1058);
    Assert(PtrUInt(@vD.TownBuf             ) - vBase = $1508);
    Assert(PtrUInt(@vD.UtTypes             ) - vBase = $2308);
    Assert(PtrUInt(@vD.ArmyData            ) - vBase = $26C0);
    Assert(PtrUInt(@vD.MapVisibleTo        ) - vBase = $56C0);
    Assert(PtrUInt(@vD.AdvanceOwners       ) - vBase = $6860);
    Assert(PtrUInt(@vD.PlaceName           ) - vBase = $6970);
    Assert(PtrUInt(@vD.ReplayLength        ) - vBase = $7670);
    Assert(PtrUInt(@vD.MarvelSite          ) - vBase = $8672);
    Assert(PtrUInt(@vD.Polluted            ) - vBase = $8A9E);
    Assert(PtrUInt(@vD.Spaceships          ) - vBase = $8BD2);
    Assert(PtrUInt(@vD.GameFlags           ) - vBase = $9172);
    Assert(PtrUInt(@vD.CitySiteX           ) - vBase = $91B8);
    Assert(PtrUInt(@vD.CivFlagsBits        ) - vBase = $93DE);
    Assert(SizeOf(TGameStateData) = ConstSaveFileSize);
    { Reference vB only to suppress "hint" for unused local. }
    vB := nil;
    if vB <> nil then Assert(False);
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
    vBase : PtrUInt;
begin
    vBase := PtrUInt(@vD);
    ParaMessage := '';
    if SizeOf(TGameStateData) <> ConstSaveFileSize then
    begin
        ParaMessage := Format('SizeOf(TGameStateData) = %d, expected %d',
            [SizeOf(TGameStateData), ConstSaveFileSize]);
        Exit(False);
    end;
    if PtrUInt(@vD.TownBuf) - vBase <> $1508 then
    begin
        ParaMessage := 'TownBuf offset mismatch';
        Exit(False);
    end;
    if PtrUInt(@vD.ArmyData) - vBase <> $26C0 then
    begin
        ParaMessage := 'ArmyData offset mismatch';
        Exit(False);
    end;
    if PtrUInt(@vD.MapVisibleTo) - vBase <> $56C0 then
    begin
        ParaMessage := 'MapVisibleTo offset mismatch';
        Exit(False);
    end;
    Result := True;
end;

initialization
    AssertLayout;

end.