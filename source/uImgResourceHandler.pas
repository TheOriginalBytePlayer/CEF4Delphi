unit uImgResourceHandler;

interface

uses
  System.SysUtils, System.Classes, System.NetEncoding, System.Generics.Collections, System.SyncObjs,
  uCEFInterfaces, uCEFTypes, uCEFResourceHandler, uCEFRequest, uCEFResponse;

type
  // Simple in-memory UUID -> image bytes store (thread-safe)
  TUuidImageStore = class
  private
    class var FMap: TDictionary<string, TBytes>;
    class var FLock: TObject;
    class constructor Create;
    class destructor Destroy;
    class function NormalizeGuid(const AGuid: TGUID): string; static;
  public
    class procedure Put(const AGuid: TGUID; const ABytes: TBytes); overload; static;
    class procedure Put(const AGuidText: string; const ABytes: TBytes); overload; static;
    class function TryGet(const AGuid: TGUID; out ABytes: TBytes): Boolean; overload; static;
    class function TryGet(const AGuidText: string; out ABytes: TBytes): Boolean; overload; static;
    class procedure Remove(const AGuid: TGUID); overload; static;
    class procedure Remove(const AGuidText: string); overload; static;
    class procedure Clear; static;
  end;

  TImgResourceHandler = class(TCefResourceHandlerOwn)
  private
    FData      : TBytes;
    FDataPos   : Integer;
    FMimeType  : ustring;
    FStatus    : Integer;
    FStatusTxt : ustring;
  protected
    function ProcessRequest(const request: ICefRequest;
                            const callback: ICefCallback): Boolean; override;
    procedure GetResponseHeaders(const response: ICefResponse;
                                 out responseLength: Int64;
                                 out redirectUrl: ustring); override;
    function ReadResponse(dataOut: Pointer; bytesToRead: Integer;
                          out bytesRead: Integer;
                          const callback: ICefCallback): Boolean; override;
    procedure Cancel; override;
  public
    constructor Create; override;
  end;

function ExtractGuidFromUuidUrl(const AUrl: string; out AGuid: TGUID): Boolean;
function GuessMimeTypeFromBytes(const ABytes: TBytes): ustring;

implementation

function UrlDecodeSafe(const S: string): string;
begin
  try
    Result := TNetEncoding.URL.Decode(S);
  except
    Result := S;
  end;
end;

function ExtractGuidFromUuidUrl(const AUrl: string; out AGuid: TGUID): Boolean;
var
  S: string;
  P, Q: Integer;
  Candidate: string;
begin
  Result := False;

  // Decode and normalize
  S := Trim(UrlDecodeSafe(AUrl));
  S := StringReplace(S, '/', '\', [rfReplaceAll]); // allow uuid:/ and uuid:\
  P := Pos('uuid:', LowerCase(S));
  if P <= 0 then Exit(False);

  S := Trim(Copy(S, P + Length('uuid:'), MaxInt));

  // Strip leading slashes/backslashes: uuid:\{...} or uuid://{...}
  while (Length(S) > 0) and ((S[1] = '\') or (S[1] = '/')) do
    Delete(S, 1, 1);

  // Preferred: {GUID}
  P := Pos('{', S);
  Q := Pos('}', S);
  if (P > 0) and (Q > P) then
  begin
    Candidate := Copy(S, P, Q - P + 1);
    Exit(TryStrToGUID(Candidate, AGuid));
  end;

  // Fallback: raw GUID maybe with suffix/query/fragment
  Candidate := S;
  for P := 1 to Length(Candidate) do
    if CharInSet(Candidate[P], ['?', '#', '&']) then
    begin
      Candidate := Copy(Candidate, 1, P - 1);
      Break;
    end;
  Candidate := Trim(Candidate);

  if TryStrToGUID(Candidate, AGuid) then Exit(True);
  if (Length(Candidate) = 36) and TryStrToGUID('{' + Candidate + '}', AGuid) then Exit(True);
end;

function GuessMimeTypeFromBytes(const ABytes: TBytes): ustring;
begin
  if (Length(ABytes) >= 8) and
     (ABytes[0] = $89) and (ABytes[1] = $50) and (ABytes[2] = $4E) and (ABytes[3] = $47) then
    Exit('image/png');

  if (Length(ABytes) >= 3) and
     (ABytes[0] = $FF) and (ABytes[1] = $D8) and (ABytes[2] = $FF) then
    Exit('image/jpeg');

  if (Length(ABytes) >= 6) and
     (ABytes[0] = Ord('G')) and (ABytes[1] = Ord('I')) and (ABytes[2] = Ord('F')) then
    Exit('image/gif');

  if (Length(ABytes) >= 12) and
     (ABytes[0] = Ord('R')) and (ABytes[1] = Ord('I')) and (ABytes[2] = Ord('F')) and
     (ABytes[8] = Ord('W')) and (ABytes[9] = Ord('E')) and (ABytes[10] = Ord('B')) and (ABytes[11] = Ord('P')) then
    Exit('image/webp');

  if (Length(ABytes) >= 2) and
     (ABytes[0] = Ord('B')) and (ABytes[1] = Ord('M')) then
    Exit('image/bmp');

  Result := 'application/octet-stream';
end;

{ TUuidImageStore }

class constructor TUuidImageStore.Create;
begin
  FMap  := TDictionary<string, TBytes>.Create;
  FLock := TObject.Create;
end;

class destructor TUuidImageStore.Destroy;
begin
  FMap.Free;
  FLock.Free;
end;

class function TUuidImageStore.NormalizeGuid(const AGuid: TGUID): string;
begin
  Result := LowerCase(GuidToString(AGuid)); // "{xxxxxxxx-...}"
end;

class procedure TUuidImageStore.Put(const AGuid: TGUID; const ABytes: TBytes);
begin
  Put(NormalizeGuid(AGuid), ABytes);
end;

class procedure TUuidImageStore.Put(const AGuidText: string; const ABytes: TBytes);
var
  G: TGUID;
  K: string;
begin
  if not TryStrToGUID(Trim(AGuidText), G) then
    Exit;
  K := NormalizeGuid(G);

  TMonitor.Enter(FLock);
  try
    FMap.AddOrSetValue(K, Copy(ABytes));
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TUuidImageStore.TryGet(const AGuid: TGUID; out ABytes: TBytes): Boolean;
begin
  Result := TryGet(NormalizeGuid(AGuid), ABytes);
end;

class function TUuidImageStore.TryGet(const AGuidText: string; out ABytes: TBytes): Boolean;
var
  G: TGUID;
  K: string;
  Temp: TBytes;
begin
  Result := False;
  SetLength(ABytes, 0);

  if not TryStrToGUID(Trim(AGuidText), G) then
    Exit;

  K := NormalizeGuid(G);

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(K, Temp) then
    begin
      ABytes := Copy(Temp);
      Result := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TUuidImageStore.Remove(const AGuid: TGUID);
begin
  Remove(NormalizeGuid(AGuid));
end;

class procedure TUuidImageStore.Remove(const AGuidText: string);
var
  G: TGUID;
  K: string;
begin
  if not TryStrToGUID(Trim(AGuidText), G) then
    Exit;
  K := NormalizeGuid(G);

  TMonitor.Enter(FLock);
  try
    FMap.Remove(K);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TUuidImageStore.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FMap.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TImgResourceHandler }

constructor TImgResourceHandler.Create;
begin
  inherited Create;
  FDataPos   := 0;
  FMimeType  := 'application/octet-stream';
  FStatus    := 404;
  FStatusTxt := 'Not Found';
end;

function TImgResourceHandler.ProcessRequest(const request: ICefRequest;
                                            const callback: ICefCallback): Boolean;
var
  G: TGUID;
begin
  Result := True; // handled by us

  if ExtractGuidFromUuidUrl(request.Url, G) and TUuidImageStore.TryGet(G, FData) then
  begin
    FStatus    := 200;
    FStatusTxt := 'OK';
    FMimeType  := GuessMimeTypeFromBytes(FData);
  end
  else
  begin
    FStatus    := 404;
    FStatusTxt := 'Not Found';
    FMimeType  := 'text/plain; charset=utf-8';
    FData      := TEncoding.UTF8.GetBytes('UUID image not found');
  end;

  FDataPos := 0;
  callback.Cont;
end;

procedure TImgResourceHandler.GetResponseHeaders(const response: ICefResponse;
                                                 out responseLength: Int64;
                                                 out redirectUrl: ustring);
begin
  redirectUrl := '';
  response.Status := FStatus;
  response.StatusText := FStatusTxt;
  response.MimeType := FMimeType;
  responseLength := Length(FData);
end;

function TImgResourceHandler.ReadResponse(dataOut: Pointer; bytesToRead: Integer;
                                          out bytesRead: Integer;
                                          const callback: ICefCallback): Boolean;
var
  Remaining, ToCopy: Integer;
begin
  bytesRead := 0;
  Remaining := Length(FData) - FDataPos;
  if Remaining <= 0 then
    Exit(False);

  ToCopy := bytesToRead;
  if ToCopy > Remaining then
    ToCopy := Remaining;

  Move(FData[FDataPos], dataOut^, ToCopy);
  Inc(FDataPos, ToCopy);
  bytesRead := ToCopy;
  Result := True;
end;

procedure TImgResourceHandler.Cancel;
begin
  // no-op
end;

end.
