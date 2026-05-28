{*******************************************************************************
  Unit Name: Repositories.AdventureSpellsU
  Purpose: FireDAC repository for adventure_spells instance lifecycle

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the adventure_spells table. Each row is one prepared
    copy of a spell for a given adventure run. Spells are consumed oldest-first
    (lowest ord, then lowest id) inside a transaction so a concurrent consumer
    cannot pick the same row twice. RevertForStep re-availabilises every copy
    consumed at a given step and is used by the soft-undo path.

  Dependencies:
    - Models.AdventureSpellU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.AdventureSpellsU;

interface

uses
  Models.AdventureSpellU;

type
  /// <summary>
  ///   Read/write access to the adventure_spells table.
  /// </summary>
  TAdventureSpellsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts a new spell instance for the given adventure / spell_def at
    ///   the given display order. Returns the new row id.
    /// </summary>
    function Insert(AAdventureId, ASpellDefId: Int64; AOrd: Integer): Int64;

    /// <summary>Atomically picks the oldest unconsumed instance of the given
    /// spell for this adventure, marks it consumed at the given step, and
    /// returns its id. Returns 0 when no available instance exists.</summary>
    function ConsumeOldest(AAdventureId, ASpellDefId,
      AStepId: Int64): Int64;

    /// <summary>Re-availabilizes every instance previously consumed at the
    /// given step. Used by soft-undo.</summary>
    procedure RevertForStep(AStepId: Int64);

    /// <summary>Lists all spell instances for an adventure ordered by
    /// spell_def_id, ord, id.</summary>
    function ListByAdventure(AAdventureId: Int64): TArray<TAdventureSpell>;

    /// <summary>Aggregated counts per spell_def, joined with the user's
    /// language-resolved title. The repo returns a generic shape (no titles);
    /// see TAdventureStateService.GetSpellSnapshot for the titled view.</summary>
    function ListGroups(AAdventureId: Int64): TArray<TAdventureSpellGroup>;
  end;

implementation

uses
  System.SysUtils,
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

constructor TAdventureSpellsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TAdventureSpellsRepo.Insert(AAdventureId, ASpellDefId: Int64;
  AOrd: Integer): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO adventure_spells (adventure_id, spell_def_id, ord) ' +
      'VALUES (:a,:s,:o)',
      [AAdventureId, ASpellDefId, AOrd]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

function TAdventureSpellsRepo.ConsumeOldest(AAdventureId, ASpellDefId,
  AStepId: Int64): Int64;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LId: Int64;
  LConsumedAt: string;
begin
  Result := 0;
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LQ := TFDQuery.Create(nil);
      try
        LQ.Connection := LC;
        LQ.Open(
          'SELECT id FROM adventure_spells ' +
          'WHERE adventure_id=:a AND spell_def_id=:s AND consumed_at IS NULL ' +
          'ORDER BY ord ASC, id ASC LIMIT 1',
          [AAdventureId, ASpellDefId]);
        if LQ.Eof then
        begin
          LC.Commit;
          Exit(0);
        end;
        LId := LQ.FieldByName('id').AsLargeInt;
      finally
        LQ.Free;
      end;
      LConsumedAt := FormatDateTime(ISO_FMT, Now);
      LC.ExecSQL(
        'UPDATE adventure_spells SET consumed_at=:t, consumed_step_id=:k ' +
        'WHERE id=:i',
        [LConsumedAt, AStepId, LId]);
      LC.Commit;
      Result := LId;
    except
      LC.Rollback;
      raise;
    end;
  finally
    LC.Free;
  end;
end;

procedure TAdventureSpellsRepo.RevertForStep(AStepId: Int64);
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'UPDATE adventure_spells SET consumed_at=NULL, consumed_step_id=NULL ' +
      'WHERE consumed_step_id=:k',
      [AStepId]);
  finally
    LC.Free;
  end;
end;

function TAdventureSpellsRepo.ListByAdventure(
  AAdventureId: Int64): TArray<TAdventureSpell>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LRow: TAdventureSpell;
  LConsumedAtField, LConsumedStepField: TField;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, adventure_id, spell_def_id, ord, consumed_at, ' +
      'consumed_step_id FROM adventure_spells WHERE adventure_id=:a ' +
      'ORDER BY spell_def_id, ord, id',
      [AAdventureId]);
    while not LQ.Eof do
    begin
      LRow.Id          := LQ.FieldByName('id').AsLargeInt;
      LRow.AdventureId := LQ.FieldByName('adventure_id').AsLargeInt;
      LRow.SpellDefId  := LQ.FieldByName('spell_def_id').AsLargeInt;
      LRow.Ord         := LQ.FieldByName('ord').AsInteger;
      LConsumedAtField   := LQ.FieldByName('consumed_at');
      LConsumedStepField := LQ.FieldByName('consumed_step_id');
      LRow.Consumed := not LConsumedAtField.IsNull;
      if LRow.Consumed then
      begin
        LRow.ConsumedAt := ParseIsoDateTime(LConsumedAtField.AsString);
        if LConsumedStepField.IsNull then
          LRow.ConsumedStepId := 0
        else
          LRow.ConsumedStepId := LConsumedStepField.AsLargeInt;
      end
      else
      begin
        LRow.ConsumedAt := 0;
        LRow.ConsumedStepId := 0;
      end;
      Result := Result + [LRow];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TAdventureSpellsRepo.ListGroups(
  AAdventureId: Int64): TArray<TAdventureSpellGroup>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LRow: TAdventureSpellGroup;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT spell_def_id, ' +
      'SUM(CASE WHEN consumed_at IS NULL THEN 1 ELSE 0 END) AS avail, ' +
      'SUM(CASE WHEN consumed_at IS NULL THEN 0 ELSE 1 END) AS cons ' +
      'FROM adventure_spells WHERE adventure_id=:a ' +
      'GROUP BY spell_def_id ORDER BY spell_def_id',
      [AAdventureId]);
    while not LQ.Eof do
    begin
      LRow.SpellDefId  := LQ.FieldByName('spell_def_id').AsLargeInt;
      LRow.Slug        := '';
      LRow.DisplayName := '';
      LRow.Description := '';
      LRow.Available   := LQ.FieldByName('avail').AsInteger;
      LRow.Consumed    := LQ.FieldByName('cons').AsInteger;
      Result := Result + [LRow];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
