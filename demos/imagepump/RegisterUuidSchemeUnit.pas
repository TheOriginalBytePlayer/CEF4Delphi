unit RegisterUuidSchemeUnit;

interface

procedure RegisterUuidSchemeFactory;

implementation

uses
  uCEFApplication, uUuidSchemeHandlerFactory;

procedure RegisterUuidSchemeFactory;
begin
  CefRegisterSchemeHandlerFactory('uuid', '', TUuidSchemeHandlerFactory.Create);
end;

end;
