unit uUuidImageApi;

interface

uses
  System.SysUtils, System.Classes;

procedure RegisterUuidImage(const AGuid: TGUID; const ABytes: TBytes); overload;
procedure RegisterUuidImage(const AGuidText: string; const ABytes: TBytes); overload;
function RegisterUuidImageFromFile(const AGuid: TGUID; const AFileName: string): Boolean; overload;
function RegisterUuidImageFromFile(const AGuidText: string; const AFileName: string): Boolean; overload;
procedure UnregisterUuidImage(const AGuid: TGUID); overload;
procedure UnregisterUuidImage(const AGuidText: string); overload;
procedure ClearUuidImages;

implementation

uses
  uCEFApplication, uCEFInterfaces, uCEFSchemeHandlerFactory, uCEFBrowser, uCEFRequest,
  uImgResourceHandler;

var 
  RegisteredFactory;

type
  TUuidSchemeHandlerFactory = class(TCefSchemeHandlerFactoryOwn)
  protected
    function New(const browser: ICefBrowser; const frame: ICefFrame;
      const schemeName: ustring; const request: ICefRequest): ICefResourceHandler; override;
  end;

procedure RegisterUuidSchemeFactory;
begin
  RegisteredFactory:=CefRegisterSchemeHandlerFactory('uuid', '', TUuidSchemeHandlerFactory.Create);
end;

function TUuidSchemeHandlerFactory.New(const browser: ICefBrowser;
  const frame: ICefFrame; const schemeName: ustring;
  const request: ICefRequest): ICefResourceHandler;
begin
  Result := TImgResourceHandler.Create;
end;

procedure RegisterUuidImage(const AGuid: TGUID; const ABytes: TBytes);
begin
  if not RegisteredFactory then 
    RegisterUuidSchemeFactory;
  TUuidImageStore.Put(AGuid, ABytes);
end;

procedure RegisterUuidImage(const AGuidText: string; const ABytes: TBytes);
begin
  if not RegisteredFactory then 
    RegisterUuidSchemeFactory;
  TUuidImageStore.Put(AGuidText, ABytes);
end;

function RegisterUuidImageFromFile(const AGuid: TGUID; const AFileName: string): Boolean;
var
  FS: TFileStream;
  B: TBytes;
begin
  if not RegisteredFactory then 
    RegisterUuidSchemeFactory;
  Result := False;
  if not FileExists(AFileName) then Exit;

  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(B[0], FS.Size);
  finally
    FS.Free;
  end;

  TUuidImageStore.Put(AGuid, B);
  Result := True;
end;

function RegisterUuidImageFromFile(const AGuidText: string; const AFileName: string): Boolean;
var
  G: TGUID;
begin
  if not RegisteredFactory then 
    RegisterUuidSchemeFactory;
  Result := TryStrToGUID(Trim(AGuidText), G) and RegisterUuidImageFromFile(G, AFileName);
end;

procedure UnregisterUuidImage(const AGuid: TGUID);
begin
  if not RegisteredFactory then 
    exit;
  TUuidImageStore.Remove(AGuid);
end;

procedure UnregisterUuidImage(const AGuidText: string);
begin
  if not RegisteredFactory then 
    exit;
  TUuidImageStore.Remove(AGuidText);
end;

procedure ClearUuidImages;
begin
  if not RegisteredFactory then 
    exit;
  
  TUuidImageStore.Clear;
end;

initialization
  RegisteredFactory:=False;

finalization

 if RegisteredFactory then 
   CefClearSchemeHandlerFactories();

end.
