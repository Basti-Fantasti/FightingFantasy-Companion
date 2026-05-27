{*******************************************************************************
  Unit Name: Tests.E2E.PlaythroughU
  Purpose: End-to-end smoke test driving the in-process DMVC server via HTTP

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Boots the full FFCompanion WebBroker stack inside the test process using
    TIdHTTPWebBrokerBridge bound to a unique temporary SQLite database, drives
    a complete playthrough (signup, create adventure, log six steps with one
    revisit, undo the revisit) via real HTTP requests, and asserts the final
    graph.json payload matches the expected shape.

    The test is the only one in the suite that exercises every layer end to
    end. It complements the per-unit fixtures by guaranteeing the controllers,
    views, middlewares, services and repositories compose correctly.

    Path handling:
      - TAppConfig.AppPath resolves to the test executable directory. Required
        runtime assets (l10n, templates, data) are copied next to the exe at
        SetUp time so the controller's L10n loader, the TemplatePro view
        engine and the seed loader all find their inputs without depending on
        the current working directory.
      - The static-files middleware tolerates a missing static dir, so we do
        not have to mirror it.

    Database lifecycle:
      - DATABASE_PATH points at a per-test unique file under TPath.GetTempPath
        so concurrent test runs (and re-runs after crashes) do not collide.
      - The FFMain FireDAC connection def is created lazily by WebModuleCreate
        on the first request; TearDown closes and deletes it, then removes
        the backing SQLite file.

  Dependencies:
    - DUnitX
    - IdHTTPWebBrokerBridge (Indy DMVC bridge)
    - Web.WebReq, Web.WebBroker, WebModuleU (boot the engine)
    - IdHTTP, IdCookieManager (drive HTTP with session cookies)
    - JsonDataObjects (parse graph.json)
*******************************************************************************}

unit Tests.E2E.PlaythroughU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   End-to-end test fixture that boots the DMVC server in-process and
  ///   drives a complete playthrough over HTTP.
  /// </summary>
  [TestFixture]
  TPlaythroughE2ETests = class
  private
    FServer: TObject;
    FBaseUrl: string;
    FDbPath: string;
    FPrevCurrentDir: string;
    FAssetsPrepared: Boolean;
    /// <summary>
    ///   Copies l10n, templates and data trees from the repository root next
    ///   to the test executable so TAppConfig.AppPath-based asset resolution
    ///   works regardless of the current working directory.
    /// </summary>
    procedure PrepareAssets;
    /// <summary>Starts the WebBroker bridge on the configured port.</summary>
    procedure StartServer(APort: Integer);
    /// <summary>Stops the bridge and frees the underlying object.</summary>
    procedure StopServer;
    /// <summary>Extracts the integer value of a named hidden input field.</summary>
    function ExtractHiddenInt(const AHtml, AFieldName: string): Int64;
  public
    [Setup] procedure SetUp;
    [TearDown] procedure TearDown;
    /// <summary>
    ///   Runs the signup + adventure + six-step + undo sequence and asserts
    ///   the resulting graph.json shape (5 nodes, 4 edges, current=200,
    ///   section 42 visits=1).
    /// </summary>
    [Test] procedure FullPlaythroughProducesExpectedGraph;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.NetEncoding,
  System.RegularExpressions,
  Winapi.Windows,
  Web.HTTPApp, Web.WebReq, Web.WebBroker,
  IdHTTPWebBrokerBridge,
  IdHTTP, IdCookieManager, IdGlobalProtocols,
  JsonDataObjects,
  FireDAC.Stan.Intf, FireDAC.Comp.Client, FireDAC.Stan.Def,
  MVCFramework.SQLGenerators.Sqlite,
  WebModuleU;

const
  CTestPort = 18900;
  CConnName = 'FFMain';

function RepoRoot: string;
begin
  // tests\bin\Win64\Debug\FFCompanionTests.exe -> four levels up = repo root.
  Result := TPath.GetFullPath(
    TPath.Combine(ExtractFileDir(ParamStr(0)), '..\..\..\..'));
end;

procedure CopyTreeIfMissing(const ASrc, ADst: string);
var
  LFiles: TArray<string>;
  LFile, LRel, LDstFile, LDstDir: string;
begin
  if not TDirectory.Exists(ASrc) then
    Exit;
  if not TDirectory.Exists(ADst) then
    TDirectory.CreateDirectory(ADst);
  LFiles := TDirectory.GetFiles(ASrc, '*', TSearchOption.soAllDirectories);
  for LFile in LFiles do
  begin
    LRel := LFile.Substring(Length(ASrc));
    if LRel.StartsWith(TPath.DirectorySeparatorChar) then
      LRel := LRel.Substring(1);
    LDstFile := TPath.Combine(ADst, LRel);
    LDstDir := ExtractFilePath(LDstFile);
    if not TDirectory.Exists(LDstDir) then
      TDirectory.CreateDirectory(LDstDir);
    if not TFile.Exists(LDstFile) then
      TFile.Copy(LFile, LDstFile, False);
  end;
end;

{ TPlaythroughE2ETests }

procedure TPlaythroughE2ETests.PrepareAssets;
var
  LExeDir, LRoot: string;
begin
  if FAssetsPrepared then
    Exit;
  LExeDir := ExtractFileDir(ParamStr(0));
  LRoot := RepoRoot;
  CopyTreeIfMissing(TPath.Combine(LRoot, 'l10n'),
    TPath.Combine(LExeDir, 'l10n'));
  CopyTreeIfMissing(TPath.Combine(LRoot, 'templates'),
    TPath.Combine(LExeDir, 'templates'));
  CopyTreeIfMissing(TPath.Combine(LRoot, 'data'),
    TPath.Combine(LExeDir, 'data'));
  FAssetsPrepared := True;
end;

procedure TPlaythroughE2ETests.StartServer(APort: Integer);
var
  LBridge: TIdHTTPWebBrokerBridge;
begin
  if (WebRequestHandler.WebModuleClass = nil) or
     not WebRequestHandler.WebModuleClass.InheritsFrom(TWebModule) then
    WebRequestHandler.WebModuleClass := WebModuleClass;

  LBridge := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LBridge.DefaultPort := APort;
    LBridge.Active := True;
    FServer := LBridge;
  except
    LBridge.Free;
    raise;
  end;
end;

procedure TPlaythroughE2ETests.StopServer;
var
  LBridge: TIdHTTPWebBrokerBridge;
begin
  if FServer = nil then
    Exit;
  LBridge := TIdHTTPWebBrokerBridge(FServer);
  try
    LBridge.Active := False;
  except
    // swallow: shutdown errors must not mask the test outcome
  end;
  LBridge.Free;
  FServer := nil;
end;

procedure TPlaythroughE2ETests.SetUp;
var
  LGuid: TGUID;
begin
  FPrevCurrentDir := GetCurrentDir;
  PrepareAssets;

  CreateGUID(LGuid);
  FDbPath := TPath.Combine(TPath.GetTempPath,
    'ff-e2e-' + GUIDToString(LGuid).Replace('{', '').Replace('}', '')
    + '.db');

  SetEnvironmentVariable('DATABASE_PATH', PChar(FDbPath));
  SetEnvironmentVariable('DEFAULT_LANGUAGE', 'de');

  // Switch cwd to the exe dir so the static-files middleware (and any other
  // relative-path consumers) resolve against the asset copy we just made.
  SetCurrentDir(ExtractFileDir(ParamStr(0)));

  StartServer(CTestPort);
  FBaseUrl := Format('http://127.0.0.1:%d', [CTestPort]);
end;

procedure TPlaythroughE2ETests.TearDown;
var
  LDef: IFDStanConnectionDef;
begin
  StopServer;

  // Tear down the FFMain connection def created by WebModuleCreate so the
  // next test gets a fresh database path.
  LDef := FDManager.ConnectionDefs.FindConnectionDef(CConnName);
  if LDef <> nil then
  begin
    try
      FDManager.CloseConnectionDef(CConnName);
    except
      // ignore
    end;
    try
      LDef.Delete;
    except
      // ignore
    end;
  end;

  SetEnvironmentVariable('DATABASE_PATH', nil);
  SetEnvironmentVariable('DEFAULT_LANGUAGE', nil);
  SetCurrentDir(FPrevCurrentDir);

  if (FDbPath <> '') and TFile.Exists(FDbPath) then
  begin
    try
      TFile.Delete(FDbPath);
    except
      // best-effort; OS may still hold the handle briefly after FireDAC close
    end;
  end;
end;

function TPlaythroughE2ETests.ExtractHiddenInt(const AHtml,
  AFieldName: string): Int64;
var
  LMatch: TMatch;
  LPattern: string;
begin
  // Matches: <input ... name="<field>" ... value="<digits>"> OR value before name
  LPattern := 'name="' + AFieldName + '"\s+value="(-?\d+)"';
  LMatch := TRegEx.Match(AHtml, LPattern);
  if not LMatch.Success then
  begin
    LPattern := 'value="(-?\d+)"\s+name="' + AFieldName + '"';
    LMatch := TRegEx.Match(AHtml, LPattern);
  end;
  if not LMatch.Success then
    Result := 0
  else
    Result := StrToInt64Def(LMatch.Groups[1].Value, 0);
end;

procedure TPlaythroughE2ETests.FullPlaythroughProducesExpectedGraph;
var
  LHttp: TIdHTTP;
  LCookies: TIdCookieManager;
  LBody: TStringList;

  procedure PostForm(const APath: string; AFormFields: TStringList;
    AExpectedStatus: Integer; out AResponse: string);
  var
    LStream: TStringStream;
  begin
    LHttp.HandleRedirects := False;
    LStream := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        AResponse := LHttp.Post(FBaseUrl + APath, AFormFields);
      except
        on E: Exception do
          AResponse := LStream.DataString;
      end;
    finally
      LStream.Free;
    end;
    if AExpectedStatus <> 0 then
      Assert.AreEqual(AExpectedStatus, LHttp.ResponseCode,
        Format('Unexpected status for POST %s: body=%s', [APath, AResponse]));
  end;

  function GetText(const APath: string): string;
  begin
    LHttp.HandleRedirects := False;
    Result := LHttp.Get(FBaseUrl + APath);
  end;

  procedure LogStep(AToSection: Integer; var ALastStepId: Int64);
  var
    LForm: TStringList;
    LResp: string;
    LNewId: Int64;
  begin
    LForm := TStringList.Create;
    try
      LForm.Add('last_step_id=' + IntToStr(ALastStepId));
      LForm.Add('to_section=' + IntToStr(AToSection));
      LForm.Add('note=');
      PostForm('/adventures/1/steps', LForm, 200, LResp);
      LNewId := ExtractHiddenInt(LResp, 'last_step_id');
      Assert.IsTrue(LNewId > ALastStepId,
        Format('LogStep to=%d did not advance last_step_id (was %d, got %d). Response: %s',
          [AToSection, ALastStepId, LNewId, LResp]));
      ALastStepId := LNewId;
    finally
      LForm.Free;
    end;
  end;

var
  LResp, LLocation, LGraphJson: string;
  LJson, LNode: TJsonObject;
  LNodes, LEdges: TJsonArray;
  LLastStepId: Int64;
  LFound42: Boolean;
  I: Integer;
  LRespCode: Integer;
begin
  LHttp := TIdHTTP.Create(nil);
  LCookies := TIdCookieManager.Create(LHttp);
  try
    LHttp.CookieManager := LCookies;
    LHttp.AllowCookies := True;
    LHttp.HandleRedirects := False;
    LHttp.HTTPOptions := LHttp.HTTPOptions + [hoNoProtocolErrorException, hoWantProtocolErrorContent];

    // ---- 1. Signup
    LBody := TStringList.Create;
    try
      LBody.Add('username=alice');
      LBody.Add('password=secret123');
      LResp := LHttp.Post(FBaseUrl + '/signup', LBody);
      LRespCode := LHttp.ResponseCode;
      Assert.IsTrue((LRespCode = 302) or (LRespCode = 303) or (LRespCode = 200),
        Format('Unexpected /signup status %d, body=%s', [LRespCode, LResp]));
    finally
      LBody.Free;
    end;

    // ---- 2. Create adventure
    LBody := TStringList.Create;
    try
      LBody.Add('book_id=1');
      LBody.Add('title=Test Adventure');
      LResp := LHttp.Post(FBaseUrl + '/adventures', LBody);
      LRespCode := LHttp.ResponseCode;
      Assert.IsTrue((LRespCode = 302) or (LRespCode = 303),
        Format('Expected redirect from /adventures, got %d, body=%s',
          [LRespCode, LResp]));
      LLocation := LHttp.Response.Location;
      Assert.AreEqual('/adventures/1', LLocation,
        'Expected redirect to /adventures/1');
    finally
      LBody.Free;
    end;

    // ---- 3. Log six steps; first step starts with last_step_id=0
    LLastStepId := 0;
    LogStep(1,   LLastStepId);  // step 1, from=NULL to=1
    LogStep(42,  LLastStepId);  // step 2, 1 -> 42
    LogStep(187, LLastStepId);  // step 3, 42 -> 187
    LogStep(42,  LLastStepId);  // step 4, 187 -> 42 (will be undone)
    LogStep(87,  LLastStepId);  // step 5, 42 -> 87
    LogStep(200, LLastStepId);  // step 6, 87 -> 200

    // ---- 4. Undo step 4 (the revisit to §42)
    LBody := TStringList.Create;
    try
      // Empty form body — undo takes no form fields, but Indy requires a body.
      LBody.Add('');
      LResp := LHttp.Post(FBaseUrl + '/adventures/1/steps/4/undo', LBody);
      LRespCode := LHttp.ResponseCode;
      Assert.AreEqual(200, LRespCode,
        Format('Undo failed: status=%d, body=%s', [LRespCode, LResp]));
    finally
      LBody.Free;
    end;

    // ---- 5. Fetch graph.json and assert structure
    LGraphJson := GetText('/adventures/1/graph.json');
    Assert.AreEqual(200, LHttp.ResponseCode,
      'graph.json fetch failed: ' + LGraphJson);

    LJson := TJsonObject(TJsonObject.Parse(LGraphJson));
    try
      Assert.AreEqual(200, LJson.I['current'],
        'Expected current=200 (last to_section)');

      LNodes := LJson.A['nodes'];
      LEdges := LJson.A['edges'];
      Assert.AreEqual(5, LNodes.Count,
        Format('Expected 5 nodes (sections 1, 42, 187, 87, 200), got %d. JSON=%s',
          [LNodes.Count, LGraphJson]));
      Assert.AreEqual(4, LEdges.Count,
        Format('Expected 4 edges (1->42, 42->187, 42->87, 87->200), got %d. JSON=%s',
          [LEdges.Count, LGraphJson]));

      LFound42 := False;
      for I := 0 to LNodes.Count - 1 do
      begin
        LNode := LNodes.O[I];
        if LNode.I['section'] = 42 then
        begin
          LFound42 := True;
          Assert.AreEqual(1, LNode.I['visits'],
            'Section 42 visits expected 1 (revisit was undone)');
        end;
      end;
      Assert.IsTrue(LFound42, 'Node for section 42 missing from graph');
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPlaythroughE2ETests);

end.
