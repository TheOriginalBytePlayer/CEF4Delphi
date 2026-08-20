unit DemoUsage;

interface


implementation

uses
  System.SysUtils, uUuidImageApi;

var
  G: TGUID;
begin
  CreateGUID(G);
  RegisterUuidImageFromFile(G, 'C:\temp\served.png');

  // then in HTML you send to browser:
  // <img src="uuid:{GUID-HERE}">
  // e.g. Format('<img src="uuid:%s">', [GuidToString(G)]);
end;

.
