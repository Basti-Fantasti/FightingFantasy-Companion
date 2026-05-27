{*******************************************************************************
  Unit Name: Controllers.BaseU
  Purpose: Base controller providing l10n, HTMX, flash, and current-user plumbing

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TBaseController, the shared ancestor for every FFCompanion DMVC
    controller. OnBeforeAction loads the localised JSON catalogue, detects the
    preferred language, marks HTMX fragment vs. full-page rendering, and pulls
    the current user from the session. Helpers wrap flash messages, HTMX
    redirects, and a thin RenderPage shim.

    The current_user wiring is a placeholder: Phase 3 will populate
    Session['user_id'] / Session['username'] via the auth controller.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons, MVCFramework.HTMX)
    - JsonDataObjects
    - AppConfigU
*******************************************************************************}

unit Controllers.BaseU;

interface

uses
  MVCFramework, MVCFramework.Commons, JsonDataObjects;

type
  /// <summary>
  ///   Abstract base for all FFCompanion controllers. Adds l10n loading,
  ///   HTMX detection, flash messaging via HX-Trigger, and session-backed
  ///   current-user resolution. Inherit from this instead of TMVCController.
  /// </summary>
  TBaseController = class(TMVCController)
  strict private
    FL10n: TJsonObject;
    FCurrentUserId: Int64;
    FCurrentUsername: string;
  protected
    /// <summary>
    ///   Loads the per-request localisation catalogue, populates ViewData
    ///   (l10n, current_lang, ispage, current_user) and reads the current
    ///   user from the session. Invoked by DMVC before every action.
    /// </summary>
    procedure OnBeforeAction(AContext: TWebContext;
      const AActionName: string; var AHandled: Boolean); override;

    /// <summary>
    ///   Emits an HX-Trigger event named "showFlash" carrying type and message
    ///   for the client-side flash notification handler in static/js/app.js.
    /// </summary>
    /// <param name="AType">One of success, error, info, warning.</param>
    /// <param name="AMessage">Already-localised message to display.</param>
    procedure Flash(const AType, AMessage: string);

    /// <summary>
    ///   Aborts the request with HTTP 401 when no user is bound to the
    ///   session. Issues an HX-Redirect for HTMX requests, otherwise a
    ///   plain Location header pointing at /login.
    /// </summary>
    procedure RequireLogin;

    /// <summary>True when the current request carries the HX-Request header.</summary>
    function IsHTMXRequest: Boolean;

    /// <summary>Thin wrapper around RenderView for symmetry with the layout chrome.</summary>
    function RenderPage(const AViewName: string): string;

    /// <summary>
    ///   Looks up a localised string in the catalogue loaded for the current
    ///   request. Use this when a controller needs the translated text of an
    ///   l10n key (e.g. for ViewData passed to a template).
    /// </summary>
    /// <param name="AKey">l10n key (must exist in both de.json and en.json).</param>
    /// <returns>Translated text, or empty string when the key is absent.</returns>
    function L10n(const AKey: string): string;

    /// <summary>Numeric id of the logged-in user; 0 when anonymous.</summary>
    property CurrentUserId: Int64 read FCurrentUserId;

    /// <summary>Username of the logged-in user; empty when anonymous.</summary>
    property CurrentUsername: string read FCurrentUsername;
  public
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  MVCFramework.Logger, MVCFramework.HTMX,
  AppConfigU;

resourcestring
  SL10nFileNotFound = 'Translation file not found, falling back to default: %s';
  SNotAuthenticated = 'Authentication required';

destructor TBaseController.Destroy;
begin
  FL10n.Free;
  inherited;
end;

procedure TBaseController.OnBeforeAction(AContext: TWebContext;
  const AActionName: string; var AHandled: Boolean);
var
  LPrefLang, LFName, LUid: string;
  LCurrentUser: TJsonObject;
begin
  inherited;

  // HTMX detection: templates use {{if ispage}} to skip layout chrome on
  // partial fragment responses.
  ViewData['ispage'] := not AContext.Request.IsHTMX;

  // Language detection chain: ?lang query, Accept-Language, configured default.
  LPrefLang := AContext.Request.QueryStringParam('lang');
  if LPrefLang.IsEmpty then
    LPrefLang := AContext.Request.ClientPreferredLanguage;
  if LPrefLang.IsEmpty then
    LPrefLang := TAppConfig.DefaultLanguage
  else
    LPrefLang := LPrefLang.Split(['-'])[0]; // de-DE -> de

  LFName := TPath.Combine(TAppConfig.AppPath,
    TPath.Combine('l10n', LPrefLang + '.json'));
  if not TFile.Exists(LFName) then
  begin
    LogW(Format(SL10nFileNotFound, [LFName]));
    LFName := TPath.Combine(TAppConfig.AppPath,
      TPath.Combine('l10n', TAppConfig.DefaultLanguage + '.json'));
  end;

  FreeAndNil(FL10n);
  FL10n := TJsonObject(TJsonObject.ParseFromFile(LFName));
  ViewData['l10n'] := FL10n;
  ViewData['current_lang'] := LPrefLang;

  // Current user from session (populated by AuthController in Phase 3).
  FCurrentUserId := 0;
  FCurrentUsername := '';
  if AContext.SessionStarted then
  begin
    LUid := Session['user_id'];
    if not LUid.IsEmpty then
    begin
      FCurrentUserId := StrToInt64Def(LUid, 0);
      FCurrentUsername := Session['username'];
      LCurrentUser := TJsonObject.Create;
      LCurrentUser.S['username'] := FCurrentUsername;
      ViewData['current_user'] := LCurrentUser;
    end;
  end;
end;

procedure TBaseController.Flash(const AType, AMessage: string);
var
  LObj, LFlash: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LFlash := LObj.O['showFlash'];
    LFlash.S['type'] := AType;
    LFlash.S['message'] := AMessage;
    Context.Response.SetCustomHeader('HX-Trigger', LObj.ToJSON);
  finally
    LObj.Free;
  end;
end;

procedure TBaseController.RequireLogin;
begin
  if FCurrentUserId = 0 then
  begin
    if IsHTMXRequest then
      Context.Response.HXSetRedirect('/login')
    else
      Context.Response.SetCustomHeader('Location', '/login');
    raise EMVCException.Create(HTTP_STATUS.Unauthorized, SNotAuthenticated);
  end;
end;

function TBaseController.IsHTMXRequest: Boolean;
begin
  Result := Context.Request.IsHTMX;
end;

function TBaseController.RenderPage(const AViewName: string): string;
begin
  Result := RenderView(AViewName);
end;

function TBaseController.L10n(const AKey: string): string;
begin
  if Assigned(FL10n) and FL10n.Contains(AKey) then
    Result := FL10n.S[AKey]
  else
    Result := '';
end;

end.
