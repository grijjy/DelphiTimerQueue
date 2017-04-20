# Cross-platform timer queues for Windows and Linux
In this article we will show how to use timer queues to create fast, lightweight, multi-threaded OnTimer() events that work on Windows and Linux in a uniform method using our helper class TgoTimerQueue.  We also discuss how they operate on Windows and Linux and show an example application using timer queues. 

For more information about us, our support and services visit the [Grijjy homepage](http://www.grijjy.com) or the [Grijjy developers blog](http://blog.grijjy.com).

The example contained here depends upon part of our [Grijjy Foundation library](https://github.com/grijjy/GrijjyFoundation).

The source code and related example repository is hosted on GitHub at [https://github.com/grijjy/DelphiTimerQueue](https://github.com/grijjy/DelphiTimerQueue).

## What is a timer queue?
You are probably already familiar with Delphi timer objects.  You set an interval and your OnTimer() event is called at the given interval.  Timer queues are a bit different. They provide a lightweight object to handle numerous timers that fire at different intervals.  These lightweight objects are handled from a thread pool that is managed by the operating system so that multiple timers can be handled by a single thread.

If your callback event executes fast enough so that it take less time than the internal rate of the timer, then it is possible for the operating system to use only a single thread to call your OnTimer() events.  However the operating system handles the issues related to making sure that more threads are used if other OnTimer events must be called.

Timer queues tend to be much more precise in their interval rate and scale up more efficiently than traditional timers.  Since they are operating from a thread, you have to make sure anything you do within the event itself is thread-safe.  With traditional Delphi timers your OnTimer() events are happening in the main application thread so this is not an issue.  However, this may be a problem for existing code that is not thread-safe or a may be a benefit if you need your timer events to happen in the background.

## Windows CreateTimerQueueTimer
On Windows we have a few APIs related to timer queues including `CreateTimerQueue`, `CreateTimerQueueTimer`, `ChangeTimerQueueTimer` and `DeleteTimerQueueTimer`.  These APIs allow you to define a queue to manage the timers and create individual handles to timer objects.    With each given handle you specify an interval rate and a callback procedure.

To create a Windows timer queue:
```Delphi
TimerQueueHandle := CreateTimerQueue;
```

To destroy a Windows timer queue:
```Delphi
DeleteTimerQueueEx(TimerQueueHandle, INVALID_HANDLE_VALUE);
```

To create a timer and add it to the queue:
```Delphi
if CreateTimerQueueTimer(Handle, TimerQueueHandle, @WaitOrTimerCallback, MyObject, 0, Interval, 0) then
begin
  // success
end
```
In the above example, `Handle` is an `out` parameter that contains the resulting handle of the timer object once it is created.  `TimerQueueHandle` is the primary handle for the timer queue.  `WaitOrTimerCallback` is your callback procedure that is called for every timer event.

The API allows you to specify your own user data, so in this case we provide our own MyObject that we will retrieve in the callback event.  You can simply pass a Delphi TObject to `CreateTimerQueueTimer()` and use it directly by defining it as a parameter in the callback to `WaitOrTimerCallback`.

```Delphi
procedure WaitOrTimerCallback(MyObject: TMyObject; TimerOrWaitFired: ByteBool); stdcall;
begin
  if TimerOrWaitFired then
  begin
    // do something
  end;
end;
```
The `stdcall` procedure will be called for each interval for each and every timer in the queue.  In other words, you can expect this event to be called by multiple threads and it needs to be completely thread safe.  

In our example code we use MyObject to actually call an OnTimer() event that is part of MyObject.  

To delete a timer from the queue:
```Delphi
if DeleteTimerQueueTimer(TimerQueueHandle, Handle, INVALID_HANDLE_VALUE) then
  ATimer.Free;
```
> The DeleteTimerQueueTimer method will block until all the pending callbacks for this specific timer object are completed.

## Linux timerfd_create

Linux offers a special set of APIs including `timerfd_creat`e and `timerfd_settime` that allow you to define descriptors for timer objects.  These are used in conjunction with the EPoll APIs to manage a queue of lightweight timer objects from a thread pool.

Just like Windows timer queues, multiple timer objects can be handled by the same thread or different threads allowing your application using timer objects to scale up more efficiently. 

To create a Linux timer queue:
```Delphi
TimerQueueHandle := epoll_create(IGNORED);
```
Since EPoll manages the queue for us, we create an EPoll handle.

To destroy a Linux timer queue:
```Delphi
__close(TimerQueueHandle);
```

To create a timer and add it to the queue:
```Delphi
Handle := timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
Event.data.ptr := MyObject;
Event.events := EPOLLIN or EPOLLET;
if epoll_ctl(TimerQueueHandle, EPOLL_CTL_ADD, Handle, @Event) <> -1 then
begin
	// success
end;
```
In the above example we create a timer object by calling timerfd_create requesting a MONOTONIC timer, a timer that isn't impacted by system clock changes, and TFD_NONBLOCK for a non-blocking event timer.  Then we add the timer to the queue managed by EPoll by calling `epoll_ctl`.  Our `MyObject` is assigned to the `Event` data.ptr parameter so we can access it during the callback just like we do on Windows.

To delete a timer from the queue:
```Delphi
epoll_ctl(TimerQueueHandle.Handle, EPOLL_CTL_DEL, Handle, @Event);
```
We simply call epoll_ctl again with the handle to delete.

To access the timerfd related APIs we added a new import header unit called Linuxapi.Timerfd that is part of the [Grijjy Foundation library](https://github.com/grijjy/GrijjyFoundation). 

## Linux epoll_wait event loop
Unlike Windows that directly calls back into your procedure when an internal is reached, on Linux you need to create an event loop that waits for the timer interval to be reached using `epoll_wait`.  You perform this inside one or more worker threads.  

Each of the threads will wait for a timer interval, but only one of the threads will handle the event.  This allows Epoll to load balance multiple timer events across a thread pool.

```Delphi
procedure TTimerQueueWorker.Execute;
var
  NumberOfEvents: Integer;
  I: Integer;
  Event: epoll_event;
  TotalTimeouts: Int64;
  Timer: TgoTimer;
  Error: Integer;
begin
  while not Terminated do
  begin
    NumberOfEvents := epoll_wait(FOwner.Handle, @FEvents, MAX_EVENTS, 100);
    if NumberOfEvents = 0 then { timeout }
      Continue
    else
    if NumberOfEvents = -1 then { error }
    begin
      Error := errno;
      if Error = EINTR then
        Continue
      else
        Break;
    end;
    for I := 0 to NumberOfEvents - 1 do
    begin
      Timer := FEvents[I].data.ptr;
      if (FEvents[I].events AND EPOLLIN) = EPOLLIN then
      begin
        if __read(Timer.Handle, @TotalTimeouts, SizeOf(TotalTimeouts)) >= 0 then
        begin
        end;
      end;
    end;
  end;
end;
```
In the above we still call the `__read()` against the timer event.  This clears the timer event from the queue.

## Putting it all together
To make it easy to use, we created the TgoTimerQueue class that operates on both Windows and Linux in a uniform manner.

You simple create a timer queue:
```Delphi
TimerQueue := TgoTimerQueue.Create;
```

Add add one or more timers to the queue:
```Delphi
MyHandle := TimerQueue.Add(1000, OnTimer);
```
Here we add a timer than fires every 1000ms and calls your OnTimer() procedure.

Your OnTimer() event is similar to a standard OnTimer() event in Delphi:
```Delphi
procedure TMyClass.OnTimer(const ASender: TObject);
var
  Timer: TgoTimer;
begin
  Timer := ASender as TgoTimer;
  // each timer callback event with unique handle and threadid
  Log(Format('OnTimer (Handle=%d, ThreadId=%d)', [Timer.Handle, GetCurrentThreadId]));
end;
```
Each timer has a different handle.  We also show the ThreadId so it is clear that that your OnTimer() event needs to be thread-safe.
> Please note that in our example code we call Writeln() to the console.  This is not reliable as the Writeln() console routine in Delphi is not thread-safe.  Making the console thread-safe is beyond the scope of this article.

## Example Application

The example program for Linux and Windows is hosted on GitHub at [https://github.com/grijjy/DelphiTimerQueue](https://github.com/grijjy/DelphiTimerQueue).

## Conclusion
We hope you find timer queues a useful addition to your application.  They are certainly nice at solving some real world issues when you need precisely timed threaded callbacks.

For more information about us, our support and services visit the [Grijjy homepage](http://www.grijjy.com) or the [Grijjy developers blog](http://blog.grijjy.com).

The base classes described herein are part of our [Grijjy Foundation library](https://github.com/grijjy/GrijjyFoundation).  