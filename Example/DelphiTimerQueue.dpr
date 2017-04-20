program DelphiTimerQueue;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$IFDEF MSWINDOWS}
  Windows,
  Grijjy.TimerQueue.Win,
  {$ENDIF}
  {$IFDEF LINUX}
  Posix.Pthread,
  Grijjy.TimerQueue.Linux,
  {$ENDIF}
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils;

type
  TMyClass = class(TObject)
  private
    FTimerQueue: TgoTimerQueue;
  private
    procedure OnTimer(const ASender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  MyClass: TMyClass;

procedure Log(const AText: String);
begin
  Writeln(AText);
end;

{ TMyClass }

constructor TMyClass.Create;
var
  I: Integer;
  Handle: THandle;
begin
  FTimerQueue := TgoTimerQueue.Create;
  for I := 1 to 5 do // add 5 timers to the queue
  begin
    // set interval to 1000ms, and the event to OnTimer()
    Handle := FTimerQueue.Add(1000, OnTimer);
    Writeln(Format('Timer Added (Handle=%d)', [Handle]));
  end;
end;

destructor TMyClass.Destroy;
begin
  FTimerQueue.Free;
  inherited;
end;

procedure TMyClass.OnTimer(const ASender: TObject);
var
  Timer: TgoTimer;
begin
  Timer := ASender as TgoTimer;
  // each timer callback event with unique handle and threadid
  Log(Format('OnTimer (Handle=%d, ThreadId=%d)', [Timer.Handle, GetCurrentThreadId]));
end;

begin
  try
    MyClass := TMyClass.Create;
    try
      Readln; // wait
    finally
      MyClass.Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
