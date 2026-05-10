unit uFMXSkiaBrowser_sp;

interface

uses
  uCEFApplication,uCEFApplicationCore, uCEFInterfaces, uCEFTypes, uCEFConstants,uMyRenderProcess;

  type
  // Subclass to tell CEF we MUST have a RenderProcessHandler
  TMyCustomSubProcessApp = class(TCefApplicationCore)
  protected
    function GetMustCreateRenderProcessHandler: boolean; override;
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

procedure CreateGlobalCEFApp;
begin
  GlobalCEFApp                            := TMyCustomSubProcessApp.Create;
  GlobalCEFApp.WindowlessRenderingEnabled := True;
  GlobalCEFApp.ExternalMessagePump        := True;
  GlobalCEFApp.MultiThreadedMessageLoop   := False;
  GlobalCEFApp.EnableGPU                  := True;
  GlobalCEFApp.EnableSpeechInput          := True;
  GlobalCEFApp.OnContextCreated          := GlobalOnContextCreated;
  GlobalCEFApp.OnProcessMessageReceived  := GlobalOnProcessMessageReceived;
  GlobalCEFApp.OnRegCustomSchemes         := GlobalCEFApp_OnRegCustomSchemes;
  {$IFDEF DEBUG}
  //GlobalCEFApp.LogFile                    := 'debug.log';
  //GlobalCEFApp.LogSeverity                := LOGSEVERITY_INFO;
  {$ENDIF}


  GlobalCEFApp.StartSubProcess;
  GlobalCEFApp.Free;
end;

end.
