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

function RegisterUuidSchemeFactory: Boolean;
function WriteRegisteredImagesToDir(const TargetDirectory: string;
  OverwriteExisting: Boolean = True;
  ClearUUIDsOnSuccess: Boolean = False): Integer;

function TryStrToGUID(const AStr: string; out AValue: TGUID): Boolean;
function TryGuidFromFileName(const AFileName: string; out AGuid: TGUID; out AExt: string): Boolean;

implementation

uses
  uCEFApplication, uCEFInterfaces, uCEFSchemeHandlerFactory, uCEFBrowser, uCEFRequest,
  uImgResourceHandler, uCEFTypes, System.IOUtils, System.StrUtils,
  uCEFMiscFunctions;

var
  RegisteredFactory: Boolean;


function IsImageExtension(const Ext: string): Boolean;
var
  E: string;
begin
  E := LowerCase(Trim(Ext));
  Result := (E = '.webp') or (E = '.png') or (E = '.jpg') or (E = '.jpeg') or
            (E = '.gif') or (E = '.bmp') or (E = '.svg') or (E = '.ico') or
            (E = '.tif') or (E = '.tiff') or (E = '.avif') or (E = '.glb') or
            (E = '.gltf');
end;

function GuessExtensionFromBytes(const ABytes: TBytes): string;
begin
  if (Length(ABytes) >= 8) and
     (ABytes[0] = $89) and (ABytes[1] = $50) and (ABytes[2] = $4E) and (ABytes[3] = $47) then
    Exit('.png');

  if (Length(ABytes) >= 3) and
     (ABytes[0] = $FF) and (ABytes[1] = $D8) and (ABytes[2] = $FF) then
    Exit('.jpg');

  if (Length(ABytes) >= 6) and
     (ABytes[0] = Ord('G')) and (ABytes[1] = Ord('I')) and (ABytes[2] = Ord('F')) then
    Exit('.gif');

  if (Length(ABytes) >= 12) and
     (ABytes[0] = Ord('R')) and (ABytes[1] = Ord('I')) and (ABytes[2] = Ord('F')) and
     (ABytes[8] = Ord('W')) and (ABytes[9] = Ord('E')) and (ABytes[10] = Ord('B')) and (ABytes[11] = Ord('P')) then
    Exit('.webp');

  if (Length(ABytes) >= 2) and
     (ABytes[0] = Ord('B')) and (ABytes[1] = Ord('M')) then
    Exit('.bmp');

  if (Length(ABytes) >= 4) and
     (ABytes[0] = Ord('g')) and (ABytes[1] = Ord('l')) and
     (ABytes[2] = Ord('T')) and (ABytes[3] = Ord('F')) then
    Exit('.glb');

  Result := '.bin';
end;

function TryStrToGUID(const AStr: string; out AValue: TGUID): Boolean;
begin
  Result := True;
  try
    if (Length(AStr) = 38) and (AStr[1] = '{') and (AStr[Length(AStr)] = '}') then
      AValue := StringToGUID(AStr)
    else if (Length(AStr) = 36) and (AStr[1] <> '{') and (AStr[Length(AStr)] <> '}') then
      AValue := StringToGUID('{' + AStr + '}')
    else
      Result := False;
  except
    Result := False;
  end;
  if not Result then
    AValue := TGUID.Empty;
end;

function TryGuidFromFileName(const AFileName: string; out AGuid: TGUID; out AExt: string): Boolean;
var
  BaseName: string;
  Ext: string;
begin
  Result := False;
  AExt := '';
  Ext := LowerCase(ExtractFileExt(AFileName));
  if not IsImageExtension(Ext) then
    Exit;

  BaseName := Trim(ChangeFileExt(ExtractFileName(AFileName), ''));
  if TryStrToGUID(BaseName, AGuid) then
  begin
    AExt := Ext;
    Exit(True);
  end;
  if (Length(BaseName) = 36) and TryStrToGUID('{' + BaseName + '}', AGuid) then
  begin
    AExt := Ext;
    Exit(True);
  end;
end;

function RegisterUuidSchemeFactory: Boolean;
begin
  if not RegisteredFactory then
    RegisteredFactory := CefRegisterSchemeHandlerFactory('uuid', '', TImgResourceHandler);
  Result := RegisteredFactory;
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
  Ext: string;
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

  Ext := LowerCase(ExtractFileExt(AFileName));
  TUuidImageStore.Put(AGuid, B, Ext);
  Result := True;
end;

function RegisterUuidImageFromFile(const AGuidText: string; const AFileName: string): Boolean;
var
  G: TGUID;
  Ext: string;
  S: string;
begin
  if not RegisteredFactory then
    RegisterUuidSchemeFactory;

  S := Trim(AGuidText);
  if TryStrToGUID(S, G) then
    Exit(RegisterUuidImageFromFile(G, AFileName));

  if (Length(S) = 36) and TryStrToGUID('{' + S + '}', G) then
    Exit(RegisterUuidImageFromFile(G, AFileName));

  if ExtractGuidFromUuidUrl(S, G) then
    Exit(RegisterUuidImageFromFile(G, AFileName));

  // Intercept: filename is "{guid}.<imageExt>" (GUID part without extension)
  if TryGuidFromFileName(AFileName, G, Ext) then
  begin
    Result := RegisterUuidImageFromFile(G, AFileName);
    Exit;
  end;

  Result := False;
end;

procedure UnregisterUuidImage(const AGuid: TGUID);
begin
  if not RegisteredFactory then
    Exit;
  TUuidImageStore.Remove(AGuid);
end;

procedure UnregisterUuidImage(const AGuidText: string);
begin
  if not RegisteredFactory then
    Exit;
  TUuidImageStore.Remove(AGuidText);
end;

procedure ClearUuidImages;
begin
  if not RegisteredFactory then
    Exit;

  TUuidImageStore.Clear;
end;

function WriteRegisteredImagesToDir(const TargetDirectory: string;
  OverwriteExisting: Boolean = True;
  ClearUUIDsOnSuccess: Boolean = False): Integer;
var
  Written: Integer;
  Failed: Boolean;
begin
  if not RegisteredFactory then
    Exit(0);

  if Trim(TargetDirectory) = '' then
    raise EArgumentException.Create('TargetDirectory cannot be empty.');

  ForceDirectories(TargetDirectory);

  Written := 0;
  Failed := False;

  TUuidImageStore.ForEach(
    procedure(const AGuidText: string; const AItem: TUuidImageItem)
    var
      OutExt: string;
      OutFile: string;
      FS: TFileStream;
    begin
      if Length(AItem.Bytes) = 0 then
        Exit;

      OutExt := LowerCase(Trim(AItem.Extension));
      if OutExt = '' then
        OutExt := GuessExtensionFromBytes(AItem.Bytes);
      if (OutExt <> '') and (OutExt[1] <> '.') then
        OutExt := '.' + OutExt;

      OutFile := TPath.Combine(TargetDirectory, AGuidText + OutExt);

      if (not OverwriteExisting) and TFile.Exists(OutFile) then
        Exit;

      try
        FS := TFileStream.Create(OutFile, fmCreate);
        try
          FS.WriteBuffer(AItem.Bytes[0], Length(AItem.Bytes));
        finally
          FS.Free;
        end;
        Inc(Written);
      except
        Failed := True;
      end;
    end
  );

  if ClearUUIDsOnSuccess and (not Failed) then
    TUuidImageStore.Clear;

  Result := Written;
end;

initialization
  RegisteredFactory := False;

finalization

 if RegisteredFactory then
   CefClearSchemeHandlerFactories();

end.
