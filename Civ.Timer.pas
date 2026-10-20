unit Civ.Timer;

// Style: semantic-prefixes v2.0

interface

{ Timer API used by the rest of the port. On DOS these were FAR calls into
  TIMER.INC's timer_read / timer_reset / _resident_init / _restore_timer.
  On Windows, the resident timer ISR is not available, so the port uses a
  monotonic counter that advances by one per "tick" (nominally 1/60 s). The
  headless demo advances it via Sleep-based waiting; graphical applications
  would advance it from an animation loop or a TTimer. }

function  TimerRead: Integer;
procedure TimerReset;
procedure ResidentInit;
procedure RestoreTimer;

{ Advance the tick counter by ParaCount (1 = one nominal frame). }
procedure TimerAdvance(ParaCount: Integer = 1);

implementation

uses
    System.SysUtils,
    System.Diagnostics;

var
    mTicks      : Integer = 0;
    mInstalled  : Boolean = False;
    mBaseTime   : TDateTime;
    mBaseTicks  : Integer;

function  TimerRead: Integer;
begin
    Result := mTicks;
end;

procedure TimerReset;
begin
    mTicks := 0;
end;

procedure TimerAdvance(ParaCount: Integer);
begin
    Inc(mTicks, ParaCount);
end;

procedure ResidentInit;
begin
    if mInstalled then
        Exit;
    mInstalled := True;
    mBaseTime := Now;
    mBaseTicks := mTicks;
end;

procedure RestoreTimer;
begin
    mInstalled := False;
end;

end.