{*******************************************************************************
  Unit Name: Services.AuthU
  Purpose: User signup and login service with bcrypt password hashing

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TAuthService wraps the users repository and exposes the password-hashing
    primitives plus higher-level Signup and Login operations. Passwords are
    hashed with bcrypt via the standalone BCrypt unit (TBCrypt.GenerateHash /
    TBCrypt.CompareHash). The plan originally referenced MVCFramework.Crypt.
    Utils.BCryptHash/BCryptCheck, but those symbols are not present in the
    DMVCFramework version installed under X:\Delphi_libs\D12; the standalone
    bcrypt library provides equivalent functionality.

  Dependencies:
    - Models.UserU
    - Repositories.UsersU
    - BCrypt (X:\Delphi_libs\D12\bcrypt\src)
*******************************************************************************}

unit Services.AuthU;

interface

uses
  Models.UserU;

type
  /// <summary>
  ///   Coordinates user creation and authentication against the users table.
  /// </summary>
  TAuthService = class
  private
    FConn: string;
  public
    /// <summary>
    ///   Constructs the service bound to a FireDAC connection definition.
    /// </summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Computes a bcrypt hash of the supplied plaintext password.
    /// </summary>
    function HashPassword(const APlain: string): string;

    /// <summary>
    ///   Compares a plaintext password against a previously stored bcrypt hash.
    /// </summary>
    function VerifyPassword(const APlain, AHash: string): Boolean;

    /// <summary>
    ///   Creates a new user after validating the inputs and ensuring the
    ///   username is unique. On success the new user id is returned via
    ///   AUserId; on failure AError carries a short machine-readable reason
    ///   ('username_too_short', 'password_too_short', 'username_taken').
    /// </summary>
    function Signup(const AUsername, APassword: string;
      out AUserId: Int64; out AError: string): Boolean;

    /// <summary>
    ///   Loads the user and verifies the supplied password.
    /// </summary>
    /// <returns>True when both the user exists and the password matches.</returns>
    function Login(const AUsername, APassword: string;
      out AUser: TUser): Boolean;
  end;

implementation

uses
  System.SysUtils,
  BCrypt,
  Repositories.UsersU;

constructor TAuthService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TAuthService.HashPassword(const APlain: string): string;
begin
  Result := TBCrypt.GenerateHash(APlain);
end;

function TAuthService.VerifyPassword(const APlain, AHash: string): Boolean;
begin
  Result := TBCrypt.CompareHash(APlain, AHash);
end;

function TAuthService.Signup(const AUsername, APassword: string;
  out AUserId: Int64; out AError: string): Boolean;
var
  LRepo: TUsersRepo;
begin
  AError := '';
  AUserId := 0;
  if Length(AUsername) < 3 then
  begin
    AError := 'username_too_short';
    Exit(False);
  end;
  if Length(APassword) < 6 then
  begin
    AError := 'password_too_short';
    Exit(False);
  end;
  LRepo := TUsersRepo.Create(FConn);
  try
    if LRepo.ExistsUsername(AUsername) then
    begin
      AError := 'username_taken';
      Exit(False);
    end;
    AUserId := LRepo.Insert(AUsername, HashPassword(APassword));
    Result := True;
  finally
    LRepo.Free;
  end;
end;

function TAuthService.Login(const AUsername, APassword: string;
  out AUser: TUser): Boolean;
var
  LRepo: TUsersRepo;
begin
  LRepo := TUsersRepo.Create(FConn);
  try
    Result := LRepo.FindByUsername(AUsername, AUser)
      and VerifyPassword(APassword, AUser.PasswordHash);
  finally
    LRepo.Free;
  end;
end;

end.
