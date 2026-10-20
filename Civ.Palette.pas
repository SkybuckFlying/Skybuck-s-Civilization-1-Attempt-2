unit Civ.Palette;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Generics.Collections,
    Civ.ImageFormat;

type
    { One cycling slot from PALETTE.INC. The original cycles up to 16 DAC
      entries per slot at a rate that fits the display refresh. On Windows
      this becomes a per-frame palette shift applied to the TBitmap palette
      (or the equivalent for the target renderer). }
    TCycleSlot = record
        Active    : Boolean;
        Rate      : Integer;   { frames per tick }
        Phase     : Integer;   { current offset into Colors }
        Countdown : Integer;
        StartIdx  : Integer;
        EndIdx    : Integer;
        Colors    : TArray<TCivPaletteEntry>;
    end;

    { Palette manager for the port. Call SetCycle once per slot with the
      colors read from the source picture, then StartCycle. Call Tick once
      per displayed frame. }
    TCivPaletteManager = class
    private
        mSlots : array[0..7] of TCycleSlot;
    public
        constructor Create;

        procedure SetCycle(ParaSlot, ParaRate, ParaStartIdx, ParaEndIdx: Integer;
            const ParaColors: array of TCivPaletteEntry);
        procedure StartCycle(ParaSlot: Integer);
        procedure StopCycle(ParaSlot: Integer);
        procedure StopAll;

        { Advance every active cycle by one tick. When Countdown reaches
          zero, Phase advances by one entry. The caller is expected to read
          Phase and re-apply the palette. }
        procedure Tick;

        { Snapshot the current palette state for a picture that uses cycling.
          The array must have room for the full 256 entries. }
        procedure Snapshot(ParaBase: TCivPalette);
    end;

implementation

constructor TCivPaletteManager.Create;
begin
    inherited;
end;

procedure TCivPaletteManager.SetCycle(ParaSlot, ParaRate, ParaStartIdx,
    ParaEndIdx: Integer; const ParaColors: array of TCivPaletteEntry);
var
    vLen, vI : Integer;
begin
    if (ParaSlot < 0) or (ParaSlot > 7) then
        Exit;
    vLen := ParaEndIdx - ParaStartIdx + 1;
    if (vLen <= 0) or (vLen > 16) or (vLen > Length(ParaColors)) then
        Exit;

    SetLength(mSlots[ParaSlot].Colors, vLen);
    for vI := 0 to vLen - 1 do
        mSlots[ParaSlot].Colors[vI] := ParaColors[vI];
    mSlots[ParaSlot].StartIdx  := ParaStartIdx;
    mSlots[ParaSlot].EndIdx    := ParaEndIdx;
    mSlots[ParaSlot].Rate      := ParaRate;
    mSlots[ParaSlot].Phase     := 0;
    mSlots[ParaSlot].Countdown := ParaRate;
    mSlots[ParaSlot].Active    := False;
end;

procedure TCivPaletteManager.StartCycle(ParaSlot: Integer);
begin
    if (ParaSlot >= 0) and (ParaSlot <= 7) then
        mSlots[ParaSlot].Active := True;
end;

procedure TCivPaletteManager.StopCycle(ParaSlot: Integer);
begin
    if (ParaSlot >= 0) and (ParaSlot <= 7) then
        mSlots[ParaSlot].Active := False;
end;

procedure TCivPaletteManager.StopAll;
var
    vI : Integer;
begin
    for vI := 0 to 7 do
        mSlots[vI].Active := False;
end;

procedure TCivPaletteManager.Tick;
var
    vSlot : ^TCycleSlot;
    vLen  : Integer;
begin
    for var vI := 0 to 7 do
    begin
        vSlot := @mSlots[vI];
        if not vSlot.Active then
            Continue;
        if vSlot.Countdown > 0 then
        begin
            Dec(vSlot.Countdown);
            Continue;
        end;
        vSlot.Countdown := vSlot.Rate;
        vLen := Length(vSlot.Colors);
        if vLen < 2 then
            Continue;
        vSlot.Phase := (vSlot.Phase + 1) mod vLen;
    end;
end;

procedure TCivPaletteManager.Snapshot(ParaBase: TCivPalette);
var
    vSlot  : ^TCycleSlot;
    vI, vK : Integer;
    vEntry : TCivPaletteEntry;
begin
    if ParaBase = nil then
        Exit;
    for vI := 0 to 7 do
    begin
        vSlot := @mSlots[vI];
        if not vSlot.Active then
            Continue;
        for vK := 0 to Length(vSlot.Colors) - 1 do
        begin
            vEntry := vSlot.Colors[(vK + vSlot.Phase) mod Length(vSlot.Colors)];
            ParaBase.SetEntry(vSlot.StartIdx + vK, vEntry);
        end;
    end;
end;

end.