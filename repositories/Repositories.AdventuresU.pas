{*******************************************************************************
  Unit Name: Repositories.AdventuresU
  Purpose: FireDAC repository for the adventures table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Thin data-access layer over the adventures table. Each method opens its
    own short-lived TFDConnection against the named FireDAC connection
    definition. All SQL parameters are bound via FireDAC's [:name] macro
    syntax to keep statements injection-safe.

    GetById raises EAdventureNotFound when the row does not exist; callers
    that need a soft miss should use TryGetById instead, which returns False
    and leaves the out parameter zero-initialised.

  Dependencies:
    - Models.AdventureU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.AdventuresU;

interface

uses
  System.SysUtils,
  Models.AdventureU;

type
  /// <summary>Raised by GetById when the adventure id is unknown.</summary>
  EAdventureNotFound = class(Exception);

  /// <summary>
  ///   Read/write access to the adventures table.
  /// </summary>
  TAdventuresRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string); overload;

    /// <summary>
    ///   Inserts a new adventure with status='active', started_at=NOW, and
    ///   last_step_id=NULL.
    /// </summary>
    /// <returns>The autoincrement id of the new row.</returns>
    function Create(AUserId, ABookId: Int64;
      const ATitle: string): Int64; reintroduce; overload;

    /// <summary>
    ///   Loads an adventure by id.
    /// </summary>
    /// <exception cref="EAdventureNotFound">When no row matches.</exception>
    function GetById(AId: Int64): TAdventure;

    /// <summary>
    ///   Soft variant of GetById.
    /// </summary>
    /// <returns>True when a row was found, False otherwise.</returns>
    function TryGetById(AId: Int64; out AAdventure: TAdventure): Boolean;

    /// <summary>
    ///   Lists the user's adventures filtered by status, newest first.
    /// </summary>
    /// <param name="AUserId">Owning user id.</param>
    /// <param name="AStatus">
    ///   Allowed status values; pass an empty array to disable the filter.
    /// </param>
    function ListForUser(AUserId: Int64;
      const AStatus: TArray<string>): TArray<TAdventure>;

    /// <summary>Sets the status column of a single adventure row.</summary>
    procedure UpdateStatus(AId: Int64; const ANewStatus: string);

    /// <summary>Sets the last_step_id column of a single adventure row.</summary>
    procedure UpdateLastStep(AId, ALastStepId: Int64);

    /// <summary>Alias for UpdateLastStep; matches the service-layer naming
    /// convention used by callers that prefer SetXxx for property-like
    /// setters.</summary>
    procedure SetLastStepId(AId, ALastStepId: Int64);
  end;

implementation

uses
  System.DateUtils,
  Data.DB,
  FireDAC.Comp.Client;

const
  ISO_FMT = 'yyyy-mm-dd"T"hh:nn:ss';

function ParseIsoDateTime(const AValue: string): TDateTime;
begin
  if AValue = '' then Exit(0);
  try Result := ISO8601ToDate(AValue, False); except Result := 0; end;
end;

function NewConn(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := AName;
  Result.Open;
end;

procedure ReadAdventureRow(AQ: TFDQuery; out AAdv: TAdventure);
var
  LField: TField;
begin
  AAdv.Id := AQ.FieldByName('id').AsLargeInt;
  AAdv.UserId := AQ.FieldByName('user_id').AsLargeInt;
  AAdv.BookId := AQ.FieldByName('book_id').AsLargeInt;
  AAdv.Title := AQ.FieldByName('title').AsString;
  AAdv.Status := AQ.FieldByName('status').AsString;
  AAdv.StartedAt := ParseIsoDateTime(AQ.FieldByName('started_at').AsString);
  LField := AQ.FieldByName('last_step_id');
  if LField.IsNull then
    AAdv.LastStepId := 0
  else
    AAdv.LastStepId := LField.AsLargeInt;
end;

constructor TAdventuresRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TAdventuresRepo.Create(AUserId, ABookId: Int64;
  const ATitle: string): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO adventures (user_id, book_id, title, status, ' +
      'started_at, last_step_id) VALUES (:u,:b,:t,''active'',:s,NULL)',
      [AUserId, ABookId, ATitle, FormatDateTime(ISO_FMT, Now)]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

function TAdventuresRepo.GetById(AId: Int64): TAdventure;
begin
  if not TryGetById(AId, Result) then
    raise EAdventureNotFound.CreateFmt('Adventure not found: %d', [AId]);
end;

function TAdventuresRepo.TryGetById(AId: Int64;
  out AAdventure: TAdventure): Boolean;
var
  LC: TFDConnection;
  LQ: TFDQuery;
begin
  Result := False;
  AAdventure := Default(TAdventure);
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, user_id, book_id, title, status, started_at, last_step_id ' +
      'FROM adventures WHERE id=:i', [AId]);
    if not LQ.Eof then
    begin
      ReadAdventureRow(LQ, AAdventure);
      Result := True;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TAdventuresRepo.ListForUser(AUserId: Int64;
  const AStatus: TArray<string>): TArray<TAdventure>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LAdv: TAdventure;
  LSql, LPlaceholders: string;
  LParams: TArray<Variant>;
  I: Integer;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    if Length(AStatus) = 0 then
    begin
      LQ.Open(
        'SELECT id, user_id, book_id, title, status, started_at, ' +
        'last_step_id FROM adventures WHERE user_id=:u ' +
        'ORDER BY started_at DESC', [AUserId]);
    end
    else
    begin
      LPlaceholders := '';
      SetLength(LParams, Length(AStatus) + 1);
      LParams[0] := AUserId;
      for I := 0 to High(AStatus) do
      begin
        if I > 0 then
          LPlaceholders := LPlaceholders + ',';
        LPlaceholders := LPlaceholders + '?';
        LParams[I + 1] := AStatus[I];
      end;
      LSql :=
        'SELECT id, user_id, book_id, title, status, started_at, ' +
        'last_step_id FROM adventures WHERE user_id=? AND status IN (' +
        LPlaceholders + ') ORDER BY started_at DESC';
      LQ.Open(LSql, LParams);
    end;
    while not LQ.Eof do
    begin
      ReadAdventureRow(LQ, LAdv);
      Result := Result + [LAdv];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

procedure TAdventuresRepo.UpdateStatus(AId: Int64; const ANewStatus: string);
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL('UPDATE adventures SET status=:s WHERE id=:i',
      [ANewStatus, AId]);
  finally
    LC.Free;
  end;
end;

procedure TAdventuresRepo.UpdateLastStep(AId, ALastStepId: Int64);
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL('UPDATE adventures SET last_step_id=:l WHERE id=:i',
      [ALastStepId, AId]);
  finally
    LC.Free;
  end;
end;

procedure TAdventuresRepo.SetLastStepId(AId, ALastStepId: Int64);
begin
  UpdateLastStep(AId, ALastStepId);
end;

end.
