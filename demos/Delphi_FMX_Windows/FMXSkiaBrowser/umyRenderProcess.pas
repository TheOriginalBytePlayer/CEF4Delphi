unit uMyRenderProcess;

interface

uses
  uCEFRenderProcessHandler, uCEFInterfaces, uCEFTypes, uCEFv8Handler, uCEFv8Value, uCEFProcessMessage,
  uCefSchemeRegistrar;

procedure GlobalOnContextCreated(const browser: ICefBrowser; const frame: ICefFrame; const context: ICefv8Context);
// Add this procedure to the interface
procedure GlobalOnProcessMessageReceived(const browser: ICefBrowser; const frame: ICefFrame; sourceProcess: TCefProcessId; const message: ICefProcessMessage; var aHandled : boolean);
procedure GlobalCEFApp_OnRegCustomSchemes(const registrar: TCefSchemeRegistrarRef);

type
  TMyBridgeHandler = class(TCefV8HandlerOwn)
  private
    FFrame: ICefFrame;
  protected
    function Execute(const name: ustring; const obj: ICefV8Value; const arguments: TCefV8ValueArray; var retval: ICefV8Value; var exception: ustring): Boolean; override;
  public
    constructor Create(const aFrame: ICefFrame);
  end;


implementation

uses
  uCEFConstants,uFMXApplicationService;

procedure GlobalOnProcessMessageReceived(const browser: ICefBrowser; const frame: ICefFrame; sourceProcess: TCefProcessId; const message: ICefProcessMessage; var aHandled : boolean);
begin
  if (message.Name = 'QueryResults') then
  begin
    var context := frame.GetV8Context;
    if (context <> nil) and context.Enter then
    try
      var jsonStr := message.ArgumentList.GetString(0);
      var global  := context.GetGlobal;
      var onResultFunc := global.GetValueByKey('onQueryResult');

      if (onResultFunc <> nil) and onResultFunc.IsFunction then
      begin
         var arg := TCefV8ValueRef.NewString(jsonStr);
         onResultFunc.ExecuteFunction(nil, [arg]);
         aHandled := True;
      end;
    finally
      context.Exit;
    end;
  end;
end;

procedure GlobalOnContextCreated(const browser: ICefBrowser; const frame: ICefFrame; const context: ICefv8Context);

var
  obj, func: ICefV8Value;
  handler: ICefV8Handler;
begin
  obj := TCefV8ValueRef.NewObject(nil, nil);
  handler := TMyBridgeHandler.Create(frame);
  func := TCefV8ValueRef.NewFunction('query', handler);

  obj.SetValueByKey('query', func, V8_PROPERTY_ATTRIBUTE_NONE);
  context.GetGlobal.SetValueByKey('Bridge', obj, V8_PROPERTY_ATTRIBUTE_NONE);
end;


procedure GlobalCEFApp_OnRegCustomSchemes(const registrar: TCefSchemeRegistrarRef);
  var Options:TCEFSchemeOptions;
begin
  Options := CEF_SCHEME_OPTION_STANDARD or
               CEF_SCHEME_OPTION_SECURE or
               CEF_SCHEME_OPTION_CORS_ENABLED;
  // Register 'app-img' as a standard, secure scheme
  registrar.AddCustomScheme('app-img',Options);
end;

{ TMyBridgeHandler }

constructor TMyBridgeHandler.Create(const aFrame: ICefFrame);
begin
  inherited Create;
  FFrame := aFrame;
end;

function TMyBridgeHandler.Execute(const name: ustring; const obj: ICefV8Value; const arguments: TCefV8ValueArray; var retval: ICefV8Value; var exception: ustring): Boolean;
var
  msg: ICefProcessMessage;
begin
  Result := False;
  if (name = 'query') then
  begin
    msg := TCefProcessMessageRef.New('ExecuteQuery');
    if Length(arguments) > 0 then
      msg.ArgumentList.SetString(0, arguments[0].GetStringValue);

    FFrame.SendProcessMessage(PID_BROWSER, msg);
    Result := True;
  end;
end;

{ TMyRenderProcessHandler }


end.