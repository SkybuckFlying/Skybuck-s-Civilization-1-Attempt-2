unit Civ.MapFile;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes,
    Civ.ImageFormat;

type
    ECivMapError = class(Exception);

    { A decoded 320x200 pixel page (graphics page 2 = the map database). }
    TMapPage = class
    private
        mPixels : array[0..63999] of Byte;
    public
        procedure Clear;
        procedure LoadFromFile(const ParaFileName: string);
        procedure SaveToFile(const ParaFileName: string);
        function Pixel(ParaX, ParaY: Integer): Byte;
        procedure SetPixel(ParaX, ParaY: Integer; ParaValue: Byte);
        { Byte at (X + 80, Y) - the "site score / territory" layer. }
        function SiteScore(ParaX, ParaY: Integer): Byte;
        { Byte at (X, Y) - the encoded terrain. }
        function TerrainByte(ParaX, ParaY: Integer): Byte;
        { Byte at (X + 160, Y) - low 3 bits = owner, bit 3 = units. }
        function Occupancy(ParaX, ParaY: Integer): Byte;
        { Byte at (X, Y + 50) - ranked land region. }
        function Region(ParaX, ParaY: Integer): Byte;
    end;

implementation

procedure TMapPage.Clear;
begin
    FillChar(mPixels, SizeOf(mPixels), 0);
end;

procedure TMapPage.LoadFromFile(const ParaFileName: string);
var
    vStream : TFileStream;
    vWidth  : Word;
    vHeight : Word;
begin
    vStream := TFileStream.Create(ParaFileName, fmOpenRead or fmShareDenyNone);
    try
        if not ReadImageHeader(vStream, vWidth, vHeight) then
        begin
            raise ECivMapError.CreateFmt(
                '%s: not a valid image/map file', [ParaFileName]);
        end;
        if (vWidth <> 320) or (vHeight <> 200) then
        begin
            raise ECivMapError.CreateFmt(
                '%s: unexpected map size %dx%d (expected 320x200)',
                [ParaFileName, vWidth, vHeight]);
        end;
        DecodeRLE(vStream, @mPixels[0], SizeOf(mPixels));
    finally
        vStream.Free;
    end;
end;

procedure TMapPage.SaveToFile(const ParaFileName: string);
var
    vStream : TFileStream;
begin
    vStream := TFileStream.Create(ParaFileName, fmCreate);
    try
        WriteImageHeader(vStream, 320, 200);
        EncodeRLE(@mPixels[0], SizeOf(mPixels), vStream);
    finally
        vStream.Free;
    end;
end;

function TMapPage.Pixel(ParaX, ParaY: Integer): Byte;
begin
    if (ParaX < 0) or (ParaX >= 320) or (ParaY < 0) or (ParaY >= 200) then
    begin
        Result := 0;
        Exit;
    end;
    Result := mPixels[ParaY * 320 + ParaX];
end;

procedure TMapPage.SetPixel(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    if (ParaX < 0) or (ParaX >= 320) or (ParaY < 0) or (ParaY >= 200) then
    begin
        Exit;
    end;
    mPixels[ParaY * 320 + ParaX] := ParaValue;
end;

function TMapPage.SiteScore(ParaX, ParaY: Integer): Byte;
begin
    Result := Pixel(ParaX + 80, ParaY);
end;

function TMapPage.TerrainByte(ParaX, ParaY: Integer): Byte;
begin
    Result := Pixel(ParaX, ParaY);
end;

function TMapPage.Occupancy(ParaX, ParaY: Integer): Byte;
begin
    Result := Pixel(ParaX + 160, ParaY);
end;

function TMapPage.Region(ParaX, ParaY: Integer): Byte;
begin
    Result := Pixel(ParaX, ParaY + 50);
end;

end.