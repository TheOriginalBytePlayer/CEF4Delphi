unit uUuidSchemeHandlerFactory;

interface

uses
  uCEFInterfaces, uCEFSchemeHandlerFactory, uCEFBrowser, uCEFRequest,
  uImgResourceHandler;

type
  TUuidSchemeHandlerFactory = class(TCefSchemeHandlerFactoryOwn)
  protected
    function New(const browser: ICefBrowser; const frame: ICefFrame;
      const schemeName: ustring; const request: ICefRequest): ICefResourceHandler; override;
  end;

implementation

function TUuidSchemeHandlerFactory.New(const browser: ICefBrowser;
  const frame: ICefFrame; const schemeName: ustring;
  const request: ICefRequest): ICefResourceHandler;
begin
  Result := TImgResourceHandler.Create;
end;

end.
