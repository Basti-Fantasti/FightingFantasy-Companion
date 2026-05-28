{*******************************************************************************
  Unit Name: Repositories.SessionsU
  Purpose: FireDAC repository for the sessions table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Persists and retrieves session tokens. The DMVC framework manages its own
    in-process session container; this repository exists so tokens can be
    persisted to SQLite when a longer-lived "remember me" or cross-process
    session story is needed. Follows the same FireDAC pattern as the users
    repository: open a short-lived TFDConnection per call, parameterised SQL.

  Dependencies:
    - Models.SessionU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.SessionsU;

interface

uses
  Models.SessionU;

type
  /// <summary>
  ///   Read/write access to the sessions table.
  /// </summary>
  TSessionsRepo = class
  private
    FConn: string;
  public
    /// <summary>
    ///   Constructs the repo bound to a named FireDAC connection definition.
    /// </summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Persists a new session row.
    /// </summary>
    procedure Insert(const AToken: string; AUserId: Int64; AExpiresAt: TDateTime);

    /// <summary>
    ///   Loads a session by its token.
    /// </summary>
    /// <returns>True when the token exists, False otherwise.</returns>
    function FindByToken(const AToken: string; out ASession: TSession): Boolean;

    /// <summary>
    ///   Deletes the session with the given token. No-op when not present.
    /// </summary>
    procedure DeleteByToken(const AToken: string);

    /// <summary>
    ///   Deletes every session whose ExpiresAt is at or before the supplied
    ///   cut-off (typically Now). Returns the number of rows removed.
    /// </summary>
    function DeleteExpired(ANow: TDateTime): Integer;
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

const
  ISO_FMT = 'yyyy-mm-dd"T"hh:nn:ss';

constructor TSessionsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

procedure TSessionsRepo.Insert(const AToken: string; AUserId: Int64;
  AExpiresAt: TDateTime);
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LC.ExecSQL('INSERT INTO sessions (token, user_id, expires_at) VALUES (:t,:u,:e)',
      [AToken, AUserId, FormatDateTime(ISO_FMT, AExpiresAt)]);
  finally
    LC.Free;
  end;
end;

function TSessionsRepo.FindByToken(const AToken: string;
  out ASession: TSession): Boolean;
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
    LQ.Open('SELECT token, user_id, expires_at FROM sessions WHERE token=:t',
      [AToken]);
    if not LQ.Eof then
    begin
      ASession.Token := LQ.FieldByName('token').AsString;
      ASession.UserId := LQ.FieldByName('user_id').AsLargeInt;
      ASession.ExpiresAt := ParseIsoDateTime(LQ.FieldByName('expires_at').AsString);
      Result := True;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

procedure TSessionsRepo.DeleteByToken(const AToken: string);
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LC.ExecSQL('DELETE FROM sessions WHERE token=:t', [AToken]);
  finally
    LC.Free;
  end;
end;

function TSessionsRepo.DeleteExpired(ANow: TDateTime): Integer;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    Result := LC.ExecSQL('DELETE FROM sessions WHERE expires_at <= :n',
      [FormatDateTime(ISO_FMT, ANow)]);
  finally
    LC.Free;
  end;
end;

end.
