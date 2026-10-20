unit Civ.ImageFormat;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes;

type
    ECivImageError = class(Exception);

    TCivPaletteEntry = packed record
        R, G, B : Byte;
    end;

    { A 256-entry palette. On Windows, ApplyToBitmap or similar converts
      this into a TRGPalette for TBitmap. }
    TCivPalette = class
    private
        mColors : array[0..255] of TCivPaletteEntry;
    public
        StartIdx : Integer;
        EndIdx   : Integer;
        Loaded   : Boolean;

        constructor Create;
        procedure Reset;
        function  Entry(ParaIndex: Integer): TCivPaletteEntry;
        procedure SetEntry(ParaIndex: Integer; const ParaEntry: TCivPaletteEntry);
    end;

    { A decoded image. Pixels are one byte per pixel (palette index), stored
      row-major starting at (0, 0). NibbleMode records whether the source
      stream used EGA nibble packing. }
    TCivImage = class
    public
        Width      : Integer;
        Height     : Integer;
        NibbleMode : Boolean;
        Pixels     : TBytes;
        Palette    : TCivPalette;

        constructor Create;
        destructor Destroy; override;
    end;

    { Streams a Civ picture file: one or more tagged chunks, each either an
      "M0" palette or an "X" image. Palette chunks are applied in place;
      the image chunk produces the returned TCivImage. }
    TPictureReader = class
    private
        mStream      : TStream;
        mPalette     : TCivPalette;

        { LZW decoder state. }
        mCodeBits    : Integer;
        mCodeMask    : Integer;
        mNextCode    : Integer;
        mPrevCode    : Integer;
        mFirstByte   : Byte;
        mDecodeLimit : Integer;
        mBitBuffer   : Byte;
        mBitCount    : Integer;

        { Code table. 8192 = 2^13 entries. }
        mPrefix      : array[0..8191] of SmallInt;
        mSuffix      : array[0..8191] of Byte;

        { Pending LZW expansion. }
        mPendingBytes : array[0..8191] of Byte;
        mPendingPos   : Integer;
        mPendingLen   : Integer;

        { RLE state on top of LZW. The escape byte 0x90 encodes
          "N-1 more copies of the previous byte". }
        mRepeatByte  : Byte;
        mRepeatCount : Integer;

        { Nibble mode: each post-RLE byte is two pixels. }
        mNibbleMode  : Boolean;
        mNibbleHigh  : Boolean;
        mNibbleByte  : Byte;

        procedure ResetLZW;
        function  ReadBits(ParaCount: Integer; out ParaCode: Integer): Boolean;
        function  ReadLZWCode(out ParaCode: Integer): Boolean;
        function  ExpandLZWCode(ParaCode: Integer): Boolean;
        function  GetNextLZWByte(out ParaByte: Byte): Boolean;
        function  GetNextRLEByte(out ParaByte: Byte): Boolean;
        function  NextOutputByte(out ParaByte: Byte): Boolean;

        function  ReadPaletteChunk(ParaLength: Integer): Boolean;
        function  ReadImageChunk(ParaNibbleMode: Boolean;
                                 out ParaImage: TCivImage): Boolean;
    public
        constructor Create(ParaStream: TStream; ParaPalette: TCivPalette);
        function  ReadPicture: TCivImage;
    end;

{ Convenience wrapper. Returns nil on malformed files. }
function ReadCivImage(const ParaFileName: string;
    ParaPalette: TCivPalette): TCivImage;

implementation

const
    ConstTagX         = $58;   { 'X' }
    ConstTagM         = $4D;   { 'M' }
    ConstTagZero      = $30;   { '0' }
    ConstClearCode    = 256;
    ConstEOI          = 257;
    ConstFirstCompound= 257;
    ConstMaxCodes     = 8192;
    ConstRLEEscape    = $90;
    ConstMaxCodeBits  = 12;
    ConstMinCodeBits  = 9;

{ TCivPalette }

constructor TCivPalette.Create;
begin
    inherited;
    Reset;
end;

procedure TCivPalette.Reset;
var
    vI : Integer;
begin
    for vI := 0 to 255 do
    begin
        mColors[vI].R := Byte(vI);
        mColors[vI].G := Byte(vI);
        mColors[vI].B := Byte(vI);
    end;
    StartIdx := 0;
    EndIdx   := 255;
    Loaded   := False;
end;

function TCivPalette.Entry(ParaIndex: Integer): TCivPaletteEntry;
begin
    if (ParaIndex < 0) or (ParaIndex > 255) then
        FillChar(Result, SizeOf(Result), 0)
    else
        Result := mColors[ParaIndex];
end;

procedure TCivPalette.SetEntry(ParaIndex: Integer;
    const ParaEntry: TCivPaletteEntry);
begin
    if (ParaIndex >= 0) and (ParaIndex <= 255) then
        mColors[ParaIndex] := ParaEntry;
end;

{ TCivImage }

constructor TCivImage.Create;
begin
    inherited;
    Palette := TCivPalette.Create;
end;

destructor TCivImage.Destroy;
begin
    Palette.Free;
    inherited;
end;

{ TPictureReader }

constructor TPictureReader.Create(ParaStream: TStream; ParaPalette: TCivPalette);
begin
    inherited Create;
    mStream  := ParaStream;
    mPalette := ParaPalette;
    ResetLZW;
end;

procedure TPictureReader.ResetLZW;
var
    vI : Integer;
begin
    mCodeBits    := ConstMinCodeBits;
    mCodeMask    := (1 shl ConstMinCodeBits) - 1;
    mNextCode    := ConstFirstCompound;
    mPrevCode    := -1;
    mFirstByte   := 0;
    mBitBuffer   := 0;
    mBitCount    := 0;
    mRepeatByte  := 0;
    mRepeatCount := 0;
    mPendingPos  := 0;
    mPendingLen  := 0;
    mNibbleHigh  := False;
    for vI := 0 to 255 do
    begin
        mPrefix[vI] := -1;
        mSuffix[vI] := Byte(vI);
    end;
    for vI := 256 to ConstMaxCodes - 1 do
    begin
        mPrefix[vI] := -1;
        mSuffix[vI] := 0;
    end;
end;

{ Reads ParaCount bits from the LZW stream, LSB first. Uses TStream.Read
  (universally available) rather than the TStream.ReadByte convenience
  method, which is not exposed in every Delphi configuration. }
function TPictureReader.ReadBits(ParaCount: Integer; out ParaCode: Integer): Boolean;
var
    vI : Integer;
    vB : Byte;
begin
    ParaCode := 0;
    for vI := 0 to ParaCount - 1 do
    begin
        if mBitCount = 0 then
        begin
            if mStream.Read(vB, 1) <> 1 then
            begin
                ParaCode := 0;
                Exit(False);
            end;
            mBitBuffer := vB;
            mBitCount  := 8;
        end;
        ParaCode := ParaCode or ((mBitBuffer and 1) shl vI);
        mBitBuffer := mBitBuffer shr 1;
        Dec(mBitCount);
    end;
    Result := True;
end;

function TPictureReader.ReadLZWCode(out ParaCode: Integer): Boolean;
var
    vCode : Integer;
begin
    if not ReadBits(mCodeBits, vCode) then
    begin
        ParaCode := 0;
        Exit(False);
    end;
    ParaCode := vCode;
    Result := True;
end;

{ Expands the code into mPendingBytes (forward order). On the first code
  after a reset, only a literal is allowed. }
function TPictureReader.ExpandLZWCode(ParaCode: Integer): Boolean;
var
    vStack  : array[0..ConstMaxCodes - 1] of Byte;
    vDepth  : Integer;
    vWalk   : Integer;
    vKwKwK  : Boolean;
    vI      : Integer;
begin
    if mPrevCode = -1 then
    begin
        if ParaCode >= 256 then
            Exit(False);
        mPendingBytes[0] := mSuffix[ParaCode];
        mFirstByte := mSuffix[ParaCode];
        mPrevCode  := ParaCode;
        mPendingPos := 0;
        mPendingLen := 1;
        Exit(True);
    end;

    vKwKwK := ParaCode >= mNextCode;
    if vKwKwK then
    begin
        vStack[0] := mFirstByte;
        vDepth    := 1;
        vWalk     := mPrevCode;
    end else
    begin
        vDepth := 0;
        vWalk  := ParaCode;
    end;

    while (vWalk >= 0) and (vDepth < ConstMaxCodes) do
    begin
        vStack[vDepth] := mSuffix[vWalk];
        Inc(vDepth);
        vWalk := mPrefix[vWalk];
    end;

    if vDepth = 0 then
        Exit(False);

    mFirstByte := vStack[vDepth - 1];

    for vI := 0 to vDepth - 1 do
        mPendingBytes[vI] := vStack[vDepth - 1 - vI];
    mPendingPos := 0;
    mPendingLen := vDepth;

    if mNextCode < ConstMaxCodes then
    begin
        mPrefix[mNextCode] := SmallInt(mPrevCode);
        mSuffix[mNextCode] := mFirstByte;
        Inc(mNextCode);
        if mNextCode > mCodeMask then
        begin
            Inc(mCodeBits);
            mCodeMask := (mCodeMask shl 1) or 1;
            if mCodeBits > mDecodeLimit then
                ResetLZW;
        end;
    end;

    mPrevCode := ParaCode;
    Result := True;
end;

function TPictureReader.GetNextLZWByte(out ParaByte: Byte): Boolean;
var
    vCode : Integer;
begin
    while mPendingPos >= mPendingLen do
    begin
        if not ReadLZWCode(vCode) then
        begin
            ParaByte := 0;
            Exit(False);
        end;
        if vCode = ConstClearCode then
        begin
            ResetLZW;
            Continue;
        end;
        if vCode = ConstEOI then
        begin
            ParaByte := 0;
            Exit(False);
        end;
        if not ExpandLZWCode(vCode) then
        begin
            ParaByte := 0;
            Exit(False);
        end;
    end;

    ParaByte := mPendingBytes[mPendingPos];
    Inc(mPendingPos);
    Result := True;
end;

function TPictureReader.GetNextRLEByte(out ParaByte: Byte): Boolean;
var
    vValue, vCount : Integer;
begin
    if mRepeatCount > 0 then
    begin
        ParaByte := mRepeatByte;
        Dec(mRepeatCount);
        Exit(True);
    end;

    while True do
    begin
        if not GetNextLZWByte(ParaByte) then
            Exit(False);

        if ParaByte <> ConstRLEEscape then
        begin
            mRepeatByte := ParaByte;
            Exit(True);
        end;

        if not GetNextLZWByte(ParaByte) then
        begin
            mRepeatByte := ConstRLEEscape;
            ParaByte    := ConstRLEEscape;
            Exit(True);
        end;
        vValue := ParaByte;
        if vValue = 0 then
        begin
            mRepeatByte := ConstRLEEscape;
            ParaByte    := ConstRLEEscape;
            Exit(True);
        end;

        vCount := vValue - 1;
        mRepeatCount := vCount;
        ParaByte := mRepeatByte;
        Exit(True);
    end;
end;

function TPictureReader.NextOutputByte(out ParaByte: Byte): Boolean;
var
    vB : Byte;
begin
    if mNibbleMode and mNibbleHigh then
    begin
        ParaByte := (mNibbleByte shr 4) and $0F;
        mNibbleHigh := False;
        Exit(True);
    end;

    if not GetNextRLEByte(vB) then
    begin
        ParaByte := 0;
        Exit(False);
    end;

    if mNibbleMode then
    begin
        mNibbleByte  := vB;
        mNibbleHigh  := True;
        ParaByte     := vB and $0F;
        Exit(True);
    end;

    ParaByte := vB;
    Result := True;
end;

function TPictureReader.ReadPaletteChunk(ParaLength: Integer): Boolean;
var
    vData : TBytes;
    vStart, vEnd, vCount, vI : Integer;
    vEntry : TCivPaletteEntry;
begin
    if ParaLength < 2 then
        Exit(False);

    SetLength(vData, ParaLength);
    if mStream.Read(vData[0], ParaLength) <> ParaLength then
        Exit(False);

    vStart := vData[0];
    vEnd   := vData[1];
    vCount := vEnd - vStart + 1;
    if (vCount < 1) or (vCount > 256) or (ParaLength < 2 + 3 * vCount) then
        Exit(False);

    for vI := 0 to vCount - 1 do
    begin
        vEntry.R := vData[2 + vI * 3];
        vEntry.G := vData[2 + vI * 3 + 1];
        vEntry.B := vData[2 + vI * 3 + 2];
        mPalette.SetEntry(vStart + vI, vEntry);
    end;
    mPalette.StartIdx := vStart;
    mPalette.EndIdx   := vEnd;
    mPalette.Loaded   := True;
    Result := True;
end;

function TPictureReader.ReadImageChunk(ParaNibbleMode: Boolean;
    out ParaImage: TCivImage): Boolean;
var
    vSize, vWidth, vHeight : Word;
    vLimit, vB             : Byte;
    vTotalPixels           : Int64;
    vOutPos                : Int64;
    vPixel                 : Byte;
    vImage                 : TCivImage;
begin
    ParaImage := nil;
    if mStream.Read(vSize, 2) <> 2 then Exit(False);
    if mStream.Read(vWidth, 2) <> 2 then Exit(False);
    if mStream.Read(vHeight, 2) <> 2 then Exit(False);
    if mStream.Read(vLimit, 1) <> 1 then Exit(False);

    if (vWidth = 0) or (vHeight = 0) then Exit(False);
    if Int64(vWidth) * vHeight > 4 * 320 * 200 then Exit(False);

    ResetLZW;
    mNibbleMode  := ParaNibbleMode;
    mNibbleHigh  := False;
    mNibbleByte  := 0;
    mDecodeLimit := vLimit;
    if mDecodeLimit > ConstMaxCodeBits then mDecodeLimit := ConstMaxCodeBits;
    if mDecodeLimit < ConstMinCodeBits then mDecodeLimit := ConstMinCodeBits;

    { Initial bit buffer: one explicit byte read after the header. }
    vB := 0;
    if (mStream.Position < mStream.Size) and
       (mStream.Read(vB, 1) = 1) then
    begin
        mBitBuffer := vB;
        mBitCount  := 8;
    end;

    vImage := TCivImage.Create;
    try
        vImage.Width      := vWidth;
        vImage.Height     := vHeight;
        vImage.NibbleMode := ParaNibbleMode;
        vTotalPixels      := Int64(vWidth) * vHeight;
        SetLength(vImage.Pixels, vTotalPixels);
        vOutPos := 0;

        while vOutPos < vTotalPixels do
        begin
            if not NextOutputByte(vPixel) then
                Break;
            vImage.Pixels[vOutPos] := vPixel;
            Inc(vOutPos);
        end;

        for var vI := 0 to 255 do
            vImage.Palette.SetEntry(vI, mPalette.Entry(vI));
        vImage.Palette.StartIdx := mPalette.StartIdx;
        vImage.Palette.EndIdx   := mPalette.EndIdx;
        vImage.Palette.Loaded   := mPalette.Loaded;

        ParaImage := vImage;
        vImage := nil;
        Result := True;
    finally
        vImage.Free;
    end;
end;

function TPictureReader.ReadPicture: TCivImage;
var
    vTag   : Word;
    vLow   : Byte;
    vHigh  : Byte;
    vLen   : Word;
    vImage : TCivImage;
begin
    while (mStream.Size - mStream.Position) >= 2 do
    begin
        if mStream.Read(vTag, 2) <> 2 then
            Break;
        vLow  := Byte(vTag and $FF);
        vHigh := Byte(vTag shr 8);

        if vLow = ConstTagX then
        begin
            if not ReadImageChunk((vHigh and 1) <> 0, vImage) then
                Break;
            Exit(vImage);
        end
        else if (vLow = ConstTagM) and (vHigh = ConstTagZero) then
        begin
            if mStream.Read(vLen, 2) <> 2 then
                Break;
            if not ReadPaletteChunk(vLen) then
                Break;
        end
        else
            Break;
    end;
    Result := nil;
end;

function ReadCivImage(const ParaFileName: string;
    ParaPalette: TCivPalette): TCivImage;
var
    vStream : TFileStream;
    vReader : TPictureReader;
begin
    vStream := TFileStream.Create(ParaFileName, fmOpenRead or fmShareDenyNone);
    try
        vReader := TPictureReader.Create(vStream, ParaPalette);
        try
            Result := vReader.ReadPicture;
        finally
            vReader.Free;
        end;
    finally
        vStream.Free;
    end;
end;

end.