{*******************************************************************************
  Unit Name: Controllers.AuthU
  Purpose: HTTP controller for login, signup and logout flows

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TAuthController, the controller hosting all anonymous authentication
    endpoints (GET/POST /login, GET/POST /signup, POST /logout). On successful
    login or signup the user_id and username are written to the DMVC session
    and the browser is redirected to the application root. On failure the form
    is re-rendered with an already-localised error message obtained from the
    base controller's L10n helper.

    All visible strings are sourced from the l10n catalogue (no hardcoded
    English / German text in the controller or templates).

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController + L10n helper)
    - Services.AuthU (TAuthService for password verification / user creation)
    - Models.UserU (TUser record)
*******************************************************************************}

unit Controllers.AuthU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller exposing the anonymous authentication endpoints. Routes
  ///   are mounted at the application root (no path prefix) because the
  ///   login / signup / logout URLs are top-level.
  /// </summary>
  [MVCPath('')]
  TAuthController = class(TBaseController)
  public
    /// <summary>Renders the login form.</summary>
    [MVCPath('/login')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetLogin;

    /// <summary>
    ///   Authenticates a user with the supplied credentials. On success the
    ///   session is populated and the user is redirected to /. On failure
    ///   the login form is re-rendered with a localised error.
    /// </summary>
    /// <param name="AUsername">Form field "username".</param>
    /// <param name="APassword">Form field "password".</param>
    [MVCPath('/login')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostLogin(
      [MVCFromContentField('username', '')] AUsername: string;
      [MVCFromContentField('password', '')] APassword: string);

    /// <summary>Renders the signup form.</summary>
    [MVCPath('/signup')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetSignup;

    /// <summary>
    ///   Creates a new user, signs them in and redirects to /. On failure
    ///   (e.g. taken username, weak password) the form is re-rendered with
    ///   a localised error message.
    /// </summary>
    /// <param name="AUsername">Form field "username".</param>
    /// <param name="APassword">Form field "password".</param>
    [MVCPath('/signup')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostSignup(
      [MVCFromContentField('username', '')] AUsername: string;
      [MVCFromContentField('password', '')] APassword: string);

    /// <summary>
    ///   Clears the current session and redirects the browser to /login.
    /// </summary>
    [MVCPath('/logout')]
    [MVCHTTPMethod([httpPOST])]
    procedure PostLogout;
  end;

implementation

uses
  System.SysUtils,
  Models.UserU,
  Services.AuthU;

const
  CMainConnection = 'FFMain';

{ TAuthController }

procedure TAuthController.GetLogin;
begin
  ViewData['error'] := '';
  Render(RenderView('pages/auth/login'));
end;

procedure TAuthController.PostLogin(AUsername, APassword: string);
var
  LSvc: TAuthService;
  LUser: TUser;
begin
  LSvc := TAuthService.Create(CMainConnection);
  try
    if LSvc.Login(AUsername, APassword, LUser) then
    begin
      Session['user_id'] := IntToStr(LUser.Id);
      Session['username'] := LUser.Username;
      Redirect('/');
    end
    else
    begin
      ViewData['error'] := L10n('flash_login_failed');
      Render(RenderView('pages/auth/login'));
    end;
  finally
    LSvc.Free;
  end;
end;

procedure TAuthController.GetSignup;
begin
  ViewData['error'] := '';
  Render(RenderView('pages/auth/signup'));
end;

procedure TAuthController.PostSignup(AUsername, APassword: string);
var
  LSvc: TAuthService;
  LUid: Int64;
  LErr: string;
begin
  LSvc := TAuthService.Create(CMainConnection);
  try
    if LSvc.Signup(AUsername, APassword, LUid, LErr) then
    begin
      Session['user_id'] := IntToStr(LUid);
      Session['username'] := AUsername;
      Redirect('/');
    end
    else
    begin
      // The auth service returns short discriminators (username_taken,
      // username_too_short, password_too_short); map them to the existing
      // l10n keys. flash_signup_taken is the only one currently catalogued;
      // fall back to a generic error for the length validations.
      if LErr = 'username_taken' then
        ViewData['error'] := L10n('flash_signup_taken')
      else
        ViewData['error'] := L10n('flash_error');
      Render(RenderView('pages/auth/signup'));
    end;
  finally
    LSvc.Free;
  end;
end;

procedure TAuthController.PostLogout;
begin
  Context.SessionStop(False);
  Redirect('/login');
end;

end.
