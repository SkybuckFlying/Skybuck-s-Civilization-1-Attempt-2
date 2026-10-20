unit Civ.ImageFormat;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes;

type
    ECivImageError = class(Exception);

const
    ConstRLEEscape = $90;

{ Decode an RLE stream into ParaDest. Encoder rules from IMAGE.C:
  - A literal 0x90 becomes "0x90, 0".
  - A run of >= 4 identical bytes V becomes "V, 0x90, count"
    (count is the total number of V's).
  - Shorter runs are written as raw bytes.
  The decoder inverse handles "0x90, n" as n+1 literal 0x90's. }
procedure DecodeRLE(ParaSource: TStream; ParaDest: PByte; ParaLength: Integer);

{ Encode ParaLength bytes from ParaSource into ParaDest stream.
  Mirrors image_run/image_byte in IMAGE.C. }
procedure EncodeRLE(ParaSource: PByte; ParaLength: Integer; ParaDest: TStream);

{ Reads the image framing used by the game's picture loading path.
  Format (best-effort inference; PICTURE.INC is not in the source):
    [width:  Word, LE]
    [height: Word, LE]
    [RLE data]
  Returns True if the header was read; populates ParaWidth and ParaHeight. }
function ReadImageHeader(ParaStream: TStream;
    out ParaWidth, ParaHeight: Word): Boolean;

procedure WriteImageHeader(ParaStream: TStream;
    ParaWidth, ParaHeight: Word);

implementation

procedure DecodeRLE(ParaSource: TStream; ParaDest: PByte; ParaLength: Integer);
var
    vPos        : Integer;
    vCur        : Byte;
    vNext       : Byte;
    vCount      : Integer;
    vHasPending : Boolean;
begin
    vPos        := 0;
    vHasPending := False;
    vCur        := 0;

    while (vPos < ParaLength) and (ParaSource.Position < ParaSource.Size) do
    begin
        if not vHasPending then
        begin
            vCur        := ParaSource.ReadByte;
            vHasPending := True;
            Continue;
        end;

        if vCur = ConstRLEEscape then
        begin
            { Literal 0x90 run: "0x90, n" => n+1 copies. }
            if ParaSource.Position >= ParaSource.Size then
            begin
                { Trailing escape with no count - emit one. }
                ParaDest[vPos] := ConstRLEEscape;
                Inc(vPos);
                vHasPending := False;
                Continue;
            end;
            vCount := ParaSource.ReadByte;
            { Emit count+1 total. }
            while (vCount >= 0) and (vPos < ParaLength) do
            begin
                ParaDest[vPos] := ConstRLEEscape;
                Inc(vPos);
                Dec(vCount);
                if vCount < 0 then
                begin
                    Break;
                end;
            end;
            vHasPending := False;
        end else
        begin
            if ParaSource.Position >= ParaSource.Size then
            begin
                ParaDest[vPos] := vCur;
                Inc(vPos);
                vHasPending := False;
                Continue;
            end;
            vNext := ParaSource.ReadByte;
            if vNext = ConstRLEEscape then
            begin
                if ParaSource.Position >= ParaSource.Size then
                begin
                    ParaDest[vPos] := vCur;
                    Inc(vPos);
                    vHasPending := False;
                    Continue;
                end;
                vCount := ParaSource.ReadByte;
                while (vCount > 0) and (vPos < ParaLength) do
                begin
                    ParaDest[vPos] := vCur;
                    Inc(vPos);
                    Dec(vCount);
                end;
                vHasPending := False;
            end else
            begin
                ParaDest[vPos] := vCur;
                Inc(vPos);
                vCur := vNext;
            end;
        end;
    end;

    { Pad with zeroes if we ran short (encoder should not do this). }
    while vPos < ParaLength do
    begin
        ParaDest[vPos] := 0;
        Inc(vPos);
    end;
end;

procedure EncodeRLE(ParaSource: PByte; ParaLength: Integer; ParaDest: TStream);
var
    vPos      : Integer;
    vValue    : Byte;
    vRunLen   : Integer;
    vRemaining: Integer;
    vChunk    : Integer;
    vI        : Integer;
begin
    vPos := 0;
    while vPos < ParaLength do
    begin
        vValue  := ParaSource[vPos];
        vRunLen := 1;
        while (vPos + vRunLen < ParaLength) and
              (ParaSource[vPos + vRunLen] = vValue) do
        begin
            Inc(vRunLen);
        end;

        if vValue = ConstRLEEscape then
        begin
            for vI := 1 to vRunLen do
            begin
                ParaDest.WriteByte(ConstRLEEscape);
                ParaDest.WriteByte(0);
            end;
        end else if vRunLen >= 4 then
        begin
            vRemaining := vRunLen;
            while vRemaining >= 4 do
            begin
                if vRemaining > 255 then
                begin
                    vChunk := 255;
                end else
                begin
                    vChunk := vRemaining;
                end;
                ParaDest.WriteByte(vValue);
                ParaDest.WriteByte(ConstRLEEscape);
                ParaDest.WriteByte(Byte(vChunk));
                Dec(vRemaining, vChunk);
            end;
            while vRemaining > 0 do
            begin
                ParaDest.WriteByte(vValue);
                Dec(vRemaining);
            end;
        end else
        begin
            for vI := 1 to vRunLen do
            begin
                ParaDest.WriteByte(vValue);
            end;
        end;

        Inc(vPos, vRunLen);
    end;
end;

function ReadImageHeader(ParaStream: TStream;
    out ParaWidth, ParaHeight: Word): Boolean;
var
    vBuf : array[0..3] of Byte;
begin
    ParaWidth  := 0;
    ParaHeight := 0;
    if ParaStream.Size < 4 then
    begin
        Exit(False);
    end;
    ParaStream.Position := 0;
    if ParaStream.Read(vBuf, 4) <> 4 then
    begin
        Exit(False);
    end;
    ParaWidth  := Word(vBuf[0]) or (Word(vBuf[1]) shl 8);
    ParaHeight := Word(vBuf[2]) or (Word(vBuf[3]) shl 8);
    { Sane check for game graphics. }
    Result := (ParaWidth > 0) and (ParaWidth <= 320) and
              (ParaHeight > 0) and (ParaHeight <= 200);
end;

procedure WriteImageHeader(ParaStream: TStream;
    ParaWidth, ParaHeight: Word);
var
    vBuf : array[0..3] of Byte;
begin
    vBuf[0] := Byte(ParaWidth and $FF);
    vBuf[1] := Byte(ParaWidth shr 8);
    vBuf[2] := Byte(ParaHeight and $FF);
    vBuf[3] := Byte(ParaHeight shr 8);
    ParaStream.WriteBuffer(vBuf, 4);
end;

end.