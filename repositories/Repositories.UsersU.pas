{*******************************************************************************
  Unit Name: Repositories.UsersU
  Purpose: FireDAC repository for the users table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Thin data-access layer over the users table. Each method opens its own
    short-lived TFDConnection against the named FireDAC connection definition
    so that callers do not need to manage connections explicitly. All SQL
    parameters are bound via FireDAC's [:name] macro syntax to keep the
    statements injection-safe.

  Dependencies:
    - Models.UserU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.UsersU;

interface

uses
  Models.UserU;

type
  /// <summary>
  ///   Read/write access to the users table.
  /// </summary>
  TUsersRepo = class
  private
    FConn: string;
  public
    /// <summary>
    ///   Constructs the repo bound to a named FireDAC connection definition.
    /// </summary>
    /// <param name="AConnectionName">
    ///   Name registered with FDManager (e.g. 'FFMain' or a per-test name).
    /// </param>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Loads a user by their unique username.
    /// </summary>
    /// <param name="AUsername">Exact username to look up.</param>
    /// <param name="AUser">Output user record (unchanged on miss).</param>
    /// <returns>True when a row was found, False otherwise.</returns>
    function FindByUsername(const AUsername: string; out AUser: TUser): Boolean;

    /// <summary>
    ///   Reports whether the username is already taken.
    /// </summary>
    function ExistsUsername(const AUsername: string): Boolean;

    /// <summary>
    ///   Inserts a new user with the given pre-hashed password.
    /// </summary>
    /// <returns>The autoincrement id of the newly inserted row.</returns>
    function Insert(const AUsername, APasswordHash: string): Int64;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  FireDAC.Comp.Client;

function ParseIsoDateTime(const AValue: string): TDateTime;
begin
  if AValue = '' then
    Exit(0);
  try
    Result := ISO8601ToDate(AValue, False);
  except
    Result := 0;
  end;
end;

constructor TUsersRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TUsersRepo.FindByUsername(const AUsername: string; out AUser: TUser): Boolean;
var
  LC: TFDConnection;
  LQ: TFDQuery;
begin
  Result := False;
  LC := TFDConnection.Create(nil);
  LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LQ.Connection := LC;
    LQ.Open('SELECT id, username, password_hash, created_at FROM users WHERE username=:u',
      [AUsername]);
    if not LQ.Eof then
    begin
      AUser.Id := LQ.FieldByName('id').AsLargeInt;
      AUser.Username := LQ.FieldByName('username').AsString;
      AUser.PasswordHash := LQ.FieldByName('password_hash').AsString;
      AUser.CreatedAt := ParseIsoDateTime(LQ.FieldByName('created_at').AsString);
      Result := True;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TUsersRepo.ExistsUsername(const AUsername: string): Boolean;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    Result := LC.ExecSQLScalar('SELECT 1 FROM users WHERE username=:u', [AUsername]) = 1;
  finally
    LC.Free;
  end;
end;

function TUsersRepo.Insert(const AUsername, APasswordHash: string): Int64;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LC.ExecSQL('INSERT INTO users (username, password_hash, created_at) VALUES (:u,:p,:c)',
      [AUsername, APasswordHash, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now)]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

end.
