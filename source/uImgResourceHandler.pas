unit uImgResourceHandler;

interface

uses
  System.SysUtils, System.Classes, System.NetEncoding, System.Generics.Collections, System.SyncObjs,
  uCEFInterfaces, uCEFTypes, uCEFResourceHandler, uCEFRequest, uCEFResponse;

type
  TUuidImageItem = record
    Bytes: TBytes;
    Extension: string; // normalized: '' or '.ext'
  end;

  TUuidImageStoreEnumProc = reference to procedure(const AGuidText: string; const AItem: TUuidImageItem);

  // Simple in-memory UUID -> image bytes store (thread-safe)
  TUuidImageStore = class
  private
    class var FMap: TDictionary<string, TUuidImageItem>;
    class var FLock: TObject;
    class constructor Create;
    class destructor Destroy;
    class function NormalizeGuid(const AGuid: TGUID): string; static;
    class function NormalizeExt(const AExtension: string): string; static;
  public
    class procedure Put(const AGuid: TGUID; const ABytes: TBytes; const AExtension: string = ''); overload; static;
    class procedure Put(const AGuidText: string; const ABytes: TBytes; const AExtension: string = ''); overload; static;

    class function TryGet(const AGuid: TGUID; out ABytes: TBytes): Boolean; overload; static;
    class function TryGet(const AGuidText: string; out ABytes: TBytes): Boolean; overload; static;

    class function TryGetItem(const AGuid: TGUID; out AItem: TUuidImageItem): Boolean; overload; static;
    class function TryGetItem(const AGuidText: string; out AItem: TUuidImageItem): Boolean; overload; static;

    class procedure Remove(const AGuid: TGUID); overload; static;
    class procedure Remove(const AGuidText: string); overload; static;
    class procedure Clear; static;

    // Enumerates a snapshot, so callback does not run under lock.
    class procedure ForEach(const AProc: TUuidImageStoreEnumProc); static;
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
    function  ReadResponse(const dataOut: Pointer; bytesToRead: Integer;
       var bytesRead: Integer; const callback: ICefCallback): Boolean; override;

    procedure Cancel; override;
  public
     constructor Create(const browser: ICefBrowser; const frame: ICefFrame; const schemeName: ustring; const request: ICefRequest); override;
  end;

function ExtractGuidFromUuidUrl(const AUrl: string; out AGuid: TGUID): Boolean;
function GuessMimeTypeFromBytes(const ABytes: TBytes): ustring;

implementation

uses
  uUuidImageApi;

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
  S, Candidate, NoExtCandidate: string;
  P, Q: Integer;
begin
  Result := False;
  AGuid := TGUID.Empty;

  // Decode and normalize
  S := Trim(UrlDecodeSafe(AUrl));
  if S = '' then Exit(False);

  // Strip known prefix schemes or path roots
  P := Pos('uuid:', LowerCase(S));
  if P > 0 then
    S := Trim(Copy(S, P + Length('uuid:'), MaxInt))
  else
  begin
    P := Pos('/api/storage/', LowerCase(S));
    if P > 0 then
      S := Trim(Copy(S, P + Length('/api/storage/'), MaxInt))
    else
    begin
      P := Pos('\api\storage\', LowerCase(S));
      if P > 0 then
        S := Trim(Copy(S, P + Length('\api\storage\'), MaxInt))
      else
      begin
        P := Pos('app-img://', LowerCase(S));
        if P > 0 then
        begin
          S := Trim(Copy(S, P + Length('app-img://'), MaxInt));
          if Pos('/', S) > 0 then
            S := Copy(S, LastDelimiter('/', S) + 1, MaxInt);
        end;
      end;
    end;
  end;

  // Normalize slashes
  S := StringReplace(S, '/', '\', [rfReplaceAll]);

  // Strip leading and trailing slashes/backslashes: uuid:\{...} or uuid://{...}/
  while (Length(S) > 0) and ((S[1] = '\') or (S[1] = '/')) do
    Delete(S, 1, 1);
  while (Length(S) > 0) and ((S[Length(S)] = '\') or (S[Length(S)] = '/')) do
    Delete(S, Length(S), 1);

  // Preferred: {GUID}
  P := Pos('{', S);
  Q := Pos('}', S);
  if (P > 0) and (Q > P) then
  begin
    Candidate := Copy(S, P, Q - P + 1);
    if TryStrToGUID(Candidate, AGuid) then
      Exit(True);
  end;

  // Fallback: raw GUID maybe with suffix/query/fragment/extension
  Candidate := S;
  for P := 1 to Length(Candidate) do
    if CharInSet(Candidate[P], ['?', '#', '&']) then
    begin
      Candidate := Copy(Candidate, 1, P - 1);
      Break;
    end;
  Candidate := Trim(Candidate);

  // Check raw candidate first
  if TryStrToGUID(Candidate, AGuid) then Exit(True);
  if (Length(Candidate) = 36) and TryStrToGUID('{' + Candidate + '}', AGuid) then Exit(True);

  // If candidate contains an extension (e.g. .webp, .png, .jpg), try stripping extension
  if Pos('.', Candidate) > 0 then
  begin
    NoExtCandidate := Trim(ChangeFileExt(Candidate, ''));
    if TryStrToGUID(NoExtCandidate, AGuid) then Exit(True);
    if (Length(NoExtCandidate) = 36) and TryStrToGUID('{' + NoExtCandidate + '}', AGuid) then Exit(True);
  end;
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

  if (Length(ABytes) >= 4) and
     (ABytes[0] = Ord('g')) and (ABytes[1] = Ord('l')) and
     (ABytes[2] = Ord('T')) and (ABytes[3] = Ord('F')) then
    Exit('model/gltf-binary');

  Result := 'application/octet-stream';
end;

{ TUuidImageStore }

class constructor TUuidImageStore.Create;
begin
  FMap  := TDictionary<string, TUuidImageItem>.Create;
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

class function TUuidImageStore.NormalizeExt(const AExtension: string): string;
begin
  Result := LowerCase(Trim(AExtension));
  if (Result <> '') and (Result[1] <> '.') then
    Result := '.' + Result;
end;

class procedure TUuidImageStore.Put(const AGuid: TGUID; const ABytes: TBytes; const AExtension: string = '');
begin
  Put(NormalizeGuid(AGuid), ABytes, AExtension);
end;

class procedure TUuidImageStore.Put(const AGuidText: string; const ABytes: TBytes; const AExtension: string = '');
var
  G: TGUID;
  K: string;
  Item: TUuidImageItem;
begin
  if not TryStrToGUID(Trim(AGuidText), G) then
  begin
    if not ExtractGuidFromUuidUrl(AGuidText, G) then
    begin
      if (Length(Trim(AGuidText)) = 36) and TryStrToGUID('{' + Trim(AGuidText) + '}', G) then
        // success
      else
        Exit;
    end;
  end;
  K := NormalizeGuid(G);

  Item.Bytes := Copy(ABytes);
  Item.Extension := NormalizeExt(AExtension);

  TMonitor.Enter(FLock);
  try
    FMap.AddOrSetValue(K, Item);
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
  Item: TUuidImageItem;
begin
  Result := TryGetItem(AGuidText, Item);
  if Result then
    ABytes := Copy(Item.Bytes)
  else
    SetLength(ABytes, 0);
end;

class function TUuidImageStore.TryGetItem(const AGuid: TGUID; out AItem: TUuidImageItem): Boolean;
begin
  Result := TryGetItem(NormalizeGuid(AGuid), AItem);
end;

class function TUuidImageStore.TryGetItem(const AGuidText: string; out AItem: TUuidImageItem): Boolean;
var
  G: TGUID;
  K: string;
  Temp: TUuidImageItem;
begin
  Result := False;
  SetLength(AItem.Bytes, 0);
  AItem.Extension := '';

  if not TryStrToGUID(Trim(AGuidText), G) then
  begin
    if not ExtractGuidFromUuidUrl(AGuidText, G) then
    begin
      if (Length(Trim(AGuidText)) = 36) and TryStrToGUID('{' + Trim(AGuidText) + '}', G) then
        // success
      else
        Exit;
    end;
  end;

  K := NormalizeGuid(G);

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(K, Temp) then
    begin
      AItem.Bytes := Copy(Temp.Bytes);
      AItem.Extension := Temp.Extension;
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
  begin
    if not ExtractGuidFromUuidUrl(AGuidText, G) then
    begin
      if (Length(Trim(AGuidText)) = 36) and TryStrToGUID('{' + Trim(AGuidText) + '}', G) then
        // success
      else
        Exit;
    end;
  end;
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

class procedure TUuidImageStore.ForEach(const AProc: TUuidImageStoreEnumProc);
var
  Snapshot: TArray<TPair<string, TUuidImageItem>>;
  Pair: TPair<string, TUuidImageItem>;
begin
  if not Assigned(AProc) then
    Exit;

  TMonitor.Enter(FLock);
  try
    Snapshot := FMap.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;

  for Pair in Snapshot do
    AProc(Pair.Key, Pair.Value);
end;

{ TImgResourceHandler }

constructor TImgResourceHandler.Create(const browser: ICefBrowser; const frame: ICefFrame;
  const schemeName: ustring; const request: ICefRequest);

begin
  inherited Create(browser,frame,schemeName,request);
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

function TImgResourceHandler.ReadResponse(const dataOut: Pointer; bytesToRead: Integer;
       var bytesRead: Integer; const callback: ICefCallback): Boolean;
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
