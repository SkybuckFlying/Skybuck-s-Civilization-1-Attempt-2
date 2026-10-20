unit Civ.Raster;

// Style: semantic-prefixes v2.0

interface

uses
    System.Types;

type
    { Opaque handle to a screen page. In the DOS port this was a segment
      number; here it is an arbitrary Pointer that the graphics driver
      interprets. The headless demo passes nil and the routines are no-ops. }
    TPaintPage = Pointer;

{ Fill a rectangle on a page with a palette-index colour. Mirrors
  _rect_fill in RASTER.INC.}
procedure RectFill(ParaPage: TPaintPage;
    ParaX, ParaY, ParaWidth, ParaHeight, ParaColour: Integer);

{ Draw a single line with clipping. Mirrors _page_line. }
procedure PageLine(ParaPage: TPaintPage;
    ParaX1, ParaY1, ParaX2, ParaY2, ParaColour: Integer);

{ Plot a single pixel, bounds-checked against the page. Mirrors _world_draw.}
procedure WorldDraw(ParaPage: TPaintPage;
    ParaX, ParaY, ParaColour: Integer);

implementation

procedure RectFill(ParaPage: TPaintPage;
    ParaX, ParaY, ParaWidth, ParaHeight, ParaColour: Integer);
begin
    { Headless: intentionally does nothing. A graphical port would call
      FillRect on the page's canvas. }
end;

procedure PageLine(ParaPage: TPaintPage;
    ParaX1, ParaY1, ParaX2, ParaY2, ParaColour: Integer);
begin
    { Headless: no-op. }
end;

procedure WorldDraw(ParaPage: TPaintPage;
    ParaX, ParaY, ParaColour: Integer);
begin
    { Headless: no-op. }
end;

end.