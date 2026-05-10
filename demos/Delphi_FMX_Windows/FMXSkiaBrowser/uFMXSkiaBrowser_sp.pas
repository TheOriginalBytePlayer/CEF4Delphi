unit uFMXSkiaBrowser_sp;

interface

uses
  uCEFApplication,uCEFApplicationCore, uCEFInterfaces, uCEFTypes, uCEFConstants,uMyRenderProcess;

  type
  // Subclass to tell CEF we MUST have a RenderProcessHandler
  TMyCustomSubProcessApp = class(TCefApplication)
  protected
    function GetMustCreateRenderProcessHandler: boolean; override;
    function OnProcessMessageReceived(const browser: ICefBrowser;
      const frame: ICefFrame; sourceProcess: TCefProcessId;
      const message: ICefProcessMessage): Boolean;
  end;

  procedure CreateGlobalCEFApp;

implementation

uses uCEFv8Value;

function TMyCustomSubProcessApp.GetMustCreateRenderProcessHandler: boolean;
begin
  // Returning True here is what triggers the internal creation
  // of the RenderProcessHandler.
  Result := True;
end;

function TMyCustomSubProcessApp.OnProcessMessageReceived(const browser: ICefBrowser;
  const frame: ICefFrame; sourceProcess: TCefProcessId;
  const message: ICefProcessMessage): Boolean;
begin
  if (message.Name = 'QueryResults') then
  begin
    var context := frame.GetV8Context;
    if context.Enter then
    try
      var jsonStr := message.ArgumentList.GetString(0);
      // Instead of building a script string, we can use the JS engine
      // to call the function directly with a real V8 String object.
      var onResultFunc := context.GetGlobal.GetValueByKey('onQueryResult');
      if onResultFunc.IsFunction then
      begin
         var arg := TCefV8ValueRef.NewString(jsonStr);
         onResultFunc.ExecuteFunction(nil, [arg]);
      end;
    finally
      context.Exit;
    end;
  end;
end;
procedure CreateGlobalCEFApp;
begin
  GlobalCEFApp                            := TCefApplicationCore.Create;
  GlobalCEFApp.WindowlessRenderingEnabled := True;
  GlobalCEFApp.ExternalMessagePump        := True;
  GlobalCEFApp.MultiThreadedMessageLoop   := False;
  GlobalCEFApp.EnableGPU                  := True;
  GlobalCEFApp.EnableSpeechInput          := True;
  GlobalCEFApp.OnProcessMessageReceived   :=
  {$IFDEF DEBUG}
  //GlobalCEFApp.LogFile                    := 'debug.log';
  //GlobalCEFApp.LogSeverity                := LOGSEVERITY_INFO;
  {$ENDIF}
  GlobalCEFApp.OnContextcREATED:=GlobalOnContextCreated;


  GlobalCEFApp.StartSubProcess;
  GlobalCEFApp.Free;
end;

end.
