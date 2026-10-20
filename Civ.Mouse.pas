unit Civ.Mouse;

// Style: semantic-prefixes v2.0

interface

uses
    System.SysUtils;

type
    TMouseEventHandler = procedure(ParaButtons, ParaX, ParaY: Integer) of object;

{ Mirrors _init_mouse. Returns -1 if a mouse driver was found, 0 otherwise. }
function  InitMouse: Integer;

{ Mirrors _mouse_close. }
procedure MouseClose;

{ Mirrors _set_mousecur(x, y, picture). No-op headless. }
procedure SetMouseCur(ParaX, ParaY, ParaPicture: Integer);

{ Mirrors _mouse_show / _mouse_hide. Keep the show/hide nesting semantics
  for the future graphics layer. }
procedure MouseShow;
procedure MouseHide;

{ Mirrors _mouse_poll. Returns the event mask accumulated since the last
  poll. Headless returns 0. }
function  MousePoll: Integer;

{ Mirrors _set_text_pos(x, y). Also stores the last pointer position. }
procedure SetTextPos(ParaX, ParaY: Integer);

{ Latest pointer position as tracked by the DOS-era state machine. Headless
  callers use this to read a saved position; graphical code will overwrite
  it via SetTextPos. }
function  MouseX: Integer;
function  MouseY: Integer;

{ Install a callback invoked on every mouse interrupt. Mirrors the
  f0_mouse_callback chain. }
procedure SetMouseCallback(ParaHandler: TMouseEventHandler);

implementation

var
    mMouseX        : Integer = 0;
    mMouseY        : Integer = 0;
    mMouseActive   : Boolean = False;
    mShowDepth     : Integer = 0;
    mCallback      : TMouseEventHandler = nil;

function  InitMouse: Integer;
begin
    { No DOS mouse driver in a Windows console app. Report "not present". }
    mMouseActive := False;
    Result := 0;
end;

procedure MouseClose;
begin
    mMouseActive := False;
end;

procedure SetMouseCur(ParaX, ParaY, ParaPicture: Integer);
begin
    { No cursor sprite in headless mode. }
end;

procedure MouseShow;
begin
    Inc(mShowDepth);
end;

procedure MouseHide;
begin
    if mShowDepth > 0 then
        Dec(mShowDepth);
end;

function  MousePoll: Integer;
begin
    Result := 0;
end;

procedure SetTextPos(ParaX, ParaY: Integer);
begin
    mMouseX := ParaX;
    mMouseY := ParaY;
end;

function  MouseX: Integer;
begin
    Result := mMouseX;
end;

function  MouseY: Integer;
begin
    Result := mMouseY;
end;

procedure SetMouseCallback(ParaHandler: TMouseEventHandler);
begin
    mCallback := ParaHandler;
end;

end.