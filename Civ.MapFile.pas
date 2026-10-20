unit Civ.MapFile;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils,
    System.Classes,
    Civ.ImageFormat;

type
    ECivMapError = class(Exception);

const
    { The game's graphics page 2 is always 320×200. Exposing these as unit
      constants makes them usable from anywhere without a TMapPage instance. }
    ConstMapPageWidth  = 320;
    ConstMapPageHeight = 200;

type
    { A decoded 320x200 map page. Pixel indices are what the game's page 2
      stores; extractors like TerrainByte and SiteScore read the well-known
      regions of that page. }
    TMapPage = class
    private
        mPixels  : TBytes;
        mPalette : TCivPalette;
        function  GetBytes: PByte;
        function  GetWidth: Integer;
        function  GetHeight: Integer;
    public
        constructor Create;
        destructor Destroy; override;

        procedure Clear;
        procedure LoadFromFile(const ParaFileName: string);
        procedure SaveToFile(const ParaFileName: string);

        function  Pixel(ParaX, ParaY: Integer): Byte;
        procedure SetPixel(ParaX, ParaY: Integer; ParaValue: Byte);

        function  SiteScore(ParaX, ParaY: Integer): Byte;
        function  TerrainByte(ParaX, ParaY: Integer): Byte;
        function  Occupancy(ParaX, ParaY: Integer): Byte;
        function  Region(ParaX, ParaY: Integer): Byte;

        property Bytes:   PByte       read GetBytes;
        property Width:   Integer     read GetWidth;
        property Height:  Integer     read GetHeight;
        property Palette: TCivPalette read mPalette;
    end;

implementation

constructor TMapPage.Create;
begin
    inherited;
    mPalette := TCivPalette.Create;
    Clear;
end;

destructor TMapPage.Destroy;
begin
    mPalette.Free;
    inherited;
end;

function TMapPage.GetBytes: PByte;
begin
    if Length(mPixels) = 0 then
        Result := nil
    else
        Result := @mPixels[0];
end;

function TMapPage.GetWidth: Integer;
begin
    Result := ConstMapPageWidth;
end;

function TMapPage.GetHeight: Integer;
begin
    Result := ConstMapPageHeight;
end;

procedure TMapPage.Clear;
begin
    SetLength(mPixels, ConstMapPageWidth * ConstMapPageHeight);
    FillChar(mPixels[0], Length(mPixels), 0);
end;

procedure TMapPage.LoadFromFile(const ParaFileName: string);
var
    vImage : TCivImage;
    vI     : Integer;
begin
    vImage := ReadCivImage(ParaFileName, mPalette);
    try
        if vImage = nil then
            raise ECivMapError.CreateFmt('%s: not a valid picture file',
                [ParaFileName]);
        if (vImage.Width <> ConstMapPageWidth) or
           (vImage.Height <> ConstMapPageHeight) then
            raise ECivMapError.CreateFmt('%s: unexpected size %dx%d '
                + '(expected %dx%d)',
                [ParaFileName, vImage.Width, vImage.Height,
                 ConstMapPageWidth, ConstMapPageHeight]);
        mPixels := vImage.Pixels;
        SetLength(mPixels, ConstMapPageWidth * ConstMapPageHeight);
        for vI := 0 to 255 do
            mPalette.SetEntry(vI, vImage.Palette.Entry(vI));
        mPalette.StartIdx := vImage.Palette.StartIdx;
        mPalette.EndIdx   := vImage.Palette.EndIdx;
        mPalette.Loaded   := vImage.Palette.Loaded;
    finally
        vImage.Free;
    end;
end;

procedure TMapPage.SaveToFile(const ParaFileName: string);
begin
    { Writing the game's picture format requires the LZW encoder, which is
      not part of this port yet. The reader path covers loading and inspecting
      saves; writing .MAP back to disk is deferred until the encoder is
      ported from IMAGE.C. }
    raise ECivMapError.Create('saving .MAP files is not implemented yet');
end;

function TMapPage.Pixel(ParaX, ParaY: Integer): Byte;
begin
    if (ParaX < 0) or (ParaX >= ConstMapPageWidth) or
       (ParaY < 0) or (ParaY >= ConstMapPageHeight) or
       (Length(mPixels) < ConstMapPageWidth * ConstMapPageHeight) then
        Exit(0);
    Result := mPixels[ParaY * ConstMapPageWidth + ParaX];
end;

procedure TMapPage.SetPixel(ParaX, ParaY: Integer; ParaValue: Byte);
begin
    if (ParaX < 0) or (ParaX >= ConstMapPageWidth) or
       (ParaY < 0) or (ParaY >= ConstMapPageHeight) or
       (Length(mPixels) < ConstMapPageWidth * ConstMapPageHeight) then
        Exit;
    mPixels[ParaY * ConstMapPageWidth + ParaX] := ParaValue;
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