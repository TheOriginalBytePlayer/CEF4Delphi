unit uMyRenderProcess;

interface

uses
  uCEFRenderProcessHandler, uCEFInterfaces, uCEFTypes, uCEFv8Handler, uCEFv8Value;

procedure GlobalOnContextCreated(const browser: ICefBrowser; const frame: ICefFrame; const context: ICefv8Context);


implementation

uses
  uCEFConstants,uFMXApplicationService, uCEFProcessMessage;

type
  TMyBridgeHandler = class(TCefV8HandlerOwn)
  private
    FFrame: ICefFrame;
  protected
    function Execute(const name: ustring; const obj: ICefV8Value; const arguments: TCefV8ValueArray; var retval: ICefV8Value; var exception: ustring): Boolean; override;
  public
    constructor Create(const aFrame: ICefFrame);
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

end.