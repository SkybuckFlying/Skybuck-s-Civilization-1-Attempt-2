unit Civ.Tables;

// Style: semantic-prefixes v2.0

interface

uses
    Civ.GameData;

type
    TAdvanceAttr = record
        A : Byte;
        B : ShortInt;
    end;

    TTribeCursorFunc = function(ParaCiv: Integer): Integer;

    TCivTables = class
    public
        class function CivEntry(ParaIndex: Integer): TCivType;
        class function AdvanceEntry(ParaIndex: Integer): TAdvance;
        class function ImprovementEntry(ParaIndex: Integer): TImprovement;
        class function AdvanceAttr(ParaIndex: Integer): TAdvanceAttr;
        class function LeaderF0(ParaCiv: Integer): Integer;
        class function LeaderF1(ParaCiv: Integer): Integer;
        class function LeaderF2(ParaCiv: Integer): Integer;
        class function TribeSlot(ParaCiv: Integer): Integer;
        class procedure SetTribeCursor(ParaFunc: TTribeCursorFunc);
    end;

implementation

type
    TAdvanceAttrRec = packed record
        A : Byte;
        B : ShortInt;
    end;

const
    ConstAdvanceAttrs: array[0..71] of TAdvanceAttrRec = (
        (A: 5; B:  0), (A: 4; B:  1), (A: 4; B:  1), (A: 4; B:  0),
        (A: 3; B:  2), (A: 6; B:  1), (A: 4; B:  0), (A: 6; B: -1),
        (A: 6; B: -1), (A: 6; B: -1), (A: 4; B:  0), (A: 3; B:  0),
        (A: 4; B:  0), (A: 3; B:  1), (A: 3; B: -2), (A: 3; B:  0),
        (A: 3; B:  1), (A: 6; B: -1), (A: 5; B: -2), (A: 3; B:  0),
        (A: 4; B:  0), (A: 3; B:  0), (A: 3; B:  1), (A: 4; B: -1),
        (A: 4; B:  1), (A: 5; B:  0), (A: 4; B:  0), (A: 8; B: -2),
        (A: 3; B:  1), (A: 3; B:  2), (A: 3; B:  2), (A: 4; B: -1),
        (A: 5; B: -1), (A: 4; B: -2), (A: 8; B: -2), (A: 5; B: -1),
        (A: 5; B: -1), (A: 6; B: -1), (A: 4; B: -1), (A: 5; B: -1),
        (A: 4; B:  1), (A: 6; B:  0), (A: 6; B:  1), (A: 2; B:  0),
        (A: 5; B:  1), (A: 4; B:  0), (A: 6; B: -2), (A: 4; B:  0),
        (A: 6; B: -2), (A: 4; B:  0), (A: 3; B:  0), (A: 3; B:  1),
        (A: 4; B: -1), (A: 4; B:  1), (A: 3; B:  1), (A: 4; B:  0),
        (A: 5; B: -1), (A: 2; B:  1), (A: 8; B: -1), (A: 2; B:  2),
        (A: 4; B:  1), (A: 2; B:  1), (A: 5; B: -2), (A: 5; B: -1),
        (A: 6; B: -1), (A: 4; B: -1), (A: 3; B:  0), (A: 0; B:  0),
        (A: 0; B:  0), (A: 0; B:  0), (A: 0; B:  0), (A: 0; B:  0)
    );

var
    mTribeCursorFn : TTribeCursorFunc;

class function TCivTables.CivEntry(ParaIndex: Integer): TCivType;
begin
    if (ParaIndex < 0) or (ParaIndex > 15) then
    begin
        FillChar(Result, SizeOf(Result), 0);
        Exit;
    end;
    Result := CivTable[ParaIndex];
end;

class function TCivTables.AdvanceEntry(ParaIndex: Integer): TAdvance;
begin
    if (ParaIndex < 0) or (ParaIndex > 71) then
    begin
        FillChar(Result, SizeOf(Result), 0);
        Exit;
    end;
    Result := AdvanceTable[ParaIndex];
end;

class function TCivTables.ImprovementEntry(ParaIndex: Integer): TImprovement;
begin
    if (ParaIndex < 0) or (ParaIndex > 45) then
    begin
        FillChar(Result, SizeOf(Result), 0);
        Exit;
    end;
    Result := ImprovementTable[ParaIndex];
end;

class function TCivTables.AdvanceAttr(ParaIndex: Integer): TAdvanceAttr;
begin
    if (ParaIndex < 0) or (ParaIndex > 71) then
    begin
        Result.A := 0;
        Result.B := 0;
        Exit;
    end;
    Result.A := ConstAdvanceAttrs[ParaIndex].A;
    Result.B := ConstAdvanceAttrs[ParaIndex].B;
end;

class function TCivTables.TribeSlot(ParaCiv: Integer): Integer;
var
    vRaw : Integer;
begin
    if Assigned(mTribeCursorFn) then vRaw := mTribeCursorFn(ParaCiv)
    else vRaw := ParaCiv;
    if vRaw >= 8 then vRaw := vRaw - 8;
    Result := vRaw;
end;

class function TCivTables.LeaderF0(ParaCiv: Integer): Integer;
var
    vSlot : Integer;
begin
    vSlot := TribeSlot(ParaCiv);
    if (vSlot < 0) or (vSlot > 15) then Exit(0);
    Result := CivEntry(vSlot).F0;
end;

class function TCivTables.LeaderF1(ParaCiv: Integer): Integer;
var
    vSlot : Integer;
begin
    vSlot := TribeSlot(ParaCiv);
    if (vSlot < 0) or (vSlot > 15) then Exit(0);
    Result := CivEntry(vSlot).F1;
end;

class function TCivTables.LeaderF2(ParaCiv: Integer): Integer;
var
    vSlot : Integer;
begin
    vSlot := TribeSlot(ParaCiv);
    if (vSlot < 0) or (vSlot > 15) then Exit(0);
    Result := CivEntry(vSlot).F2;
end;

class procedure TCivTables.SetTribeCursor(ParaFunc: TTribeCursorFunc);
begin
    mTribeCursorFn := ParaFunc;
end;

end.