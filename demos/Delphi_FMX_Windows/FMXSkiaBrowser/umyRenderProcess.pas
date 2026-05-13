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
  uCEFConstants,uFMXApplicationService, system.SysUtils;

procedure GlobalOnProcessMessageReceived(const browser: ICefBrowser; const frame: ICefFrame; sourceProcess: TCefProcessId; const message: ICefProcessMessage; var aHandled : boolean);
var
  apiMethod, paramJSON: string;
  jsResult: ICefV8Value;
  arg: ICefV8Value;
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
         arg := TCefV8ValueRef.NewString(jsonStr);
         onResultFunc.ExecuteFunction(nil, [arg]);
         aHandled := True;
      end;
    finally
      context.Exit;
    end;
  end
 else
  if (message.Name = 'CallFrameForgeAPI') then
  begin
    apiMethod := message.ArgumentList.GetString(0); // e.g., 'isLoggedIn'

    if message.ArgumentList.GetSize > 1 then
       paramJSON := message.ArgumentList.GetString(1)
    else
       ParamJSON:=''; // e.g., '{"userName":"ken"}'

    var context := frame.GetV8Context;
    if (context <> nil) and context.Enter then
    try
      var global := context.GetGlobal;
      var apiObj := global.GetValueByKey('FrameForgeAPI');

      if (apiObj <> nil) and apiObj.IsObject then
      begin
        var jsFunc := apiObj.GetValueByKey(apiMethod);
        if (jsFunc <> nil) and jsFunc.IsFunction then
        begin
          // Convert the JSON string from Delphi into a real V8 Object
          // We use the built-in JSON.parse within the V8 context
          var jsonParser := global.GetValueByKey('JSON').GetValueByKey('parse');
          if ParamJSon <> '' then
           begin
             arg := jsonParser.ExecuteFunction(nil, [TCefV8ValueRef.NewString(paramJSON)]);
          // Execute: window.FrameForgeAPI.isLoggedIn({'userName':'ken'})
            jsResult := jsFunc.ExecuteFunction(nil, [arg])
           end
          else //Execute the JS function: window.FrameForgeAPI.isLoggedIn()
           jsResult := jsFunc.ExecuteFunction(nil, []);

          // Reply logic remains the same
          var reply := TCefProcessMessageRef.New('FrameForgeAPIResult');
          reply.ArgumentList.SetString(0, apiMethod);

          if jsResult.IsBool then
            reply.ArgumentList.SetString(1, BoolToStr(jsResult.GetBoolValue, True))
          else
            reply.ArgumentList.SetString(1, jsResult.GetStringValue);

          frame.SendProcessMessage(PID_BROWSER, reply);
          aHandled := True;
        end;
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