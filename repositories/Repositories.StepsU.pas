{*******************************************************************************
  Unit Name: Repositories.StepsU
  Purpose: FireDAC repository for the steps table with monotonic seq + soft undo

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Thin data-access layer over the steps table. Each method opens its own
    short-lived TFDConnection against the named FireDAC connection definition.
    All SQL parameters are bound via FireDAC's [:name] macro syntax to keep
    statements injection-safe.

    Insert assigns the next per-adventure sequence number atomically inside a
    transaction by reading COALESCE(MAX(seq),0)+1 and inserting the new row
    in the same transaction. The UNIQUE(adventure_id, seq) constraint is the
    real safety net: should two concurrent writers race past the SELECT, the
    losing INSERT triggers a constraint violation and Insert retries once.

    GetById raises EStepNotFound when the row does not exist.

  Dependencies:
    - Models.StepU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.StepsU;

interface

uses
  System.SysUtils,
  Models.StepU;

type
  /// <summary>Raised by GetById when the step id is unknown.</summary>
  EStepNotFound = class(Exception);

  /// <summary>
  ///   Read/write access to the steps table.
  /// </summary>
  TStepsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts a new step. The seq column is assigned atomically as
    ///   MAX(seq)+1 for the given adventure inside a transaction. Pass 0 for
    ///   AFromSection to record a NULL first-step source.
    /// </summary>
    /// <returns>The autoincrement id of the new row.</returns>
    function Insert(AAdventureId: Int64; AFromSection, AToSection: Integer;
      const ANote: string;
      AFlagFight, AFlagItem, AFlagStat: Boolean): Int64;

    /// <summary>
    ///   Lists steps for an adventure, newest-first by seq DESC.
    /// </summary>
    /// <param name="AIncludeUndone">
    ///   When True, returns every step. When False, hides soft-undone rows.
    /// </param>
    function ListByAdventure(AAdventureId: Int64;
      AIncludeUndone: Boolean): TArray<TStep>;

    /// <summary>
    ///   Lists steps for an adventure in chronological (seq ASC) order. Used
    ///   by graph construction where the natural traversal direction is
    ///   first-step-first. Excludes soft-undone rows when AIncludeUndone is
    ///   False.
    /// </summary>
    function ListByAdventureAsc(AAdventureId: Int64;
      AIncludeUndone: Boolean): TArray<TStep>;

    /// <summary>Sets the undone flag of a single step row.</summary>
    procedure SetUndone(AStepId: Int64; AUndone: Boolean);

    /// <summary>
    ///   Sets the flag_stat marker on a single step row. Called by the stats
    ///   controller when a stat change is committed against a previously
    ///   unflagged step so the timeline icon reflects that the step now
    ///   carries a stat mutation.
    /// </summary>
    procedure SetFlagStat(AStepId: Int64; AValue: Boolean);

    /// <summary>
    ///   Sets the flag_item marker on a single step row. Called by the
    ///   inventory controller when an inventory mutation is committed against
    ///   a previously unflagged step so the timeline icon reflects that the
    ///   step now carries an item change.
    /// </summary>
    procedure SetFlagItem(AStepId: Int64; AValue: Boolean);

    /// <summary>
    ///   Loads a step by id.
    /// </summary>
    /// <exception cref="EStepNotFound">When no row matches.</exception>
    function GetById(AStepId: Int64): TStep;

    /// <summary>Inserts a synthetic kind='setup' step with NULL to_section
    /// and seq=1. Used by the adventure-create transaction to host starting
    /// inventory and initial stat snapshots.</summary>
    function InsertSetup(AAdventureId: Int64): Int64;
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

procedure ReadStepRow(AQ: TFDQuery; out AStep: TStep);
var
  LFromField: TField;
begin
  AStep.Id := AQ.FieldByName('id').AsLargeInt;
  AStep.AdventureId := AQ.FieldByName('adventure_id').AsLargeInt;
  AStep.Seq := AQ.FieldByName('seq').AsInteger;
  LFromField := AQ.FieldByName('from_section');
  if LFromField.IsNull then
    AStep.FromSection := 0
  else
    AStep.FromSection := LFromField.AsInteger;
  if AQ.FieldByName('to_section').IsNull then
    AStep.ToSection := 0
  else
    AStep.ToSection := AQ.FieldByName('to_section').AsInteger;
  AStep.Kind := AQ.FieldByName('kind').AsString;
  if AStep.Kind = '' then AStep.Kind := 'normal';
  AStep.Note := AQ.FieldByName('note').AsString;
  AStep.FlagFight := AQ.FieldByName('flag_fight').AsInteger <> 0;
  AStep.FlagItem := AQ.FieldByName('flag_item').AsInteger <> 0;
  AStep.FlagStat := AQ.FieldByName('flag_stat').AsInteger <> 0;
  AStep.Undone := AQ.FieldByName('undone').AsInteger <> 0;
  AStep.CreatedAt := ParseIsoDateTime(AQ.FieldByName('created_at').AsString);
end;

constructor TStepsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TStepsRepo.Insert(AAdventureId: Int64;
  AFromSection, AToSection: Integer; const ANote: string;
  AFlagFight, AFlagItem, AFlagStat: Boolean): Int64;

  function TryInsertOnce(out ANewId: Int64): Boolean;
  var
    LC: TFDConnection;
    LSeq: Integer;
    LCreatedAt: string;
    LFightVal, LItemVal, LStatVal: Integer;
  begin
    Result := False;
    ANewId := 0;
    LC := NewConn(FConn);
    try
      LC.StartTransaction;
      try
        LSeq := LC.ExecSQLScalar(
          'SELECT COALESCE(MAX(seq),0)+1 FROM steps WHERE adventure_id=:a',
          [AAdventureId]);
        LCreatedAt := FormatDateTime(ISO_FMT, Now);
        if AFlagFight then LFightVal := 1 else LFightVal := 0;
        if AFlagItem  then LItemVal  := 1 else LItemVal  := 0;
        if AFlagStat  then LStatVal  := 1 else LStatVal  := 0;
        if AFromSection = 0 then
          LC.ExecSQL(
            'INSERT INTO steps (adventure_id, seq, from_section, to_section, ' +
            'note, flag_fight, flag_item, flag_stat, undone, created_at) ' +
            'VALUES (:a,:s,NULL,:t,:n,:ff,:fi,:fs,0,:c)',
            [AAdventureId, LSeq, AToSection, ANote,
             LFightVal, LItemVal, LStatVal, LCreatedAt])
        else
          LC.ExecSQL(
            'INSERT INTO steps (adventure_id, seq, from_section, to_section, ' +
            'note, flag_fight, flag_item, flag_stat, undone, created_at) ' +
            'VALUES (:a,:s,:f,:t,:n,:ff,:fi,:fs,0,:c)',
            [AAdventureId, LSeq, AFromSection, AToSection, ANote,
             LFightVal, LItemVal, LStatVal, LCreatedAt]);
        ANewId := LC.ExecSQLScalar('SELECT last_insert_rowid()');
        LC.Commit;
        Result := True;
      except
        LC.Rollback;
        // Caller decides whether to retry.
      end;
    finally
      LC.Free;
    end;
  end;

begin
  // Atomic-ish: read MAX(seq)+1, INSERT, commit. The UNIQUE(adventure_id,seq)
  // index is the canonical guard. If a concurrent writer wins the race the
  // INSERT fails and we retry exactly once.
  if not TryInsertOnce(Result) then
    if not TryInsertOnce(Result) then
      raise EDatabaseError.CreateFmt(
        'Failed to insert step for adventure %d after retry', [AAdventureId]);
end;

function TStepsRepo.ListByAdventure(AAdventureId: Int64;
  AIncludeUndone: Boolean): TArray<TStep>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LStep: TStep;
  LSql: string;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LSql :=
      'SELECT id, adventure_id, seq, from_section, to_section, kind, note, ' +
      'flag_fight, flag_item, flag_stat, undone, created_at ' +
      'FROM steps WHERE adventure_id=:a';
    if not AIncludeUndone then
      LSql := LSql + ' AND undone=0';
    LSql := LSql + ' ORDER BY seq DESC';
    LQ.Open(LSql, [AAdventureId]);
    while not LQ.Eof do
    begin
      ReadStepRow(LQ, LStep);
      Result := Result + [LStep];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TStepsRepo.ListByAdventureAsc(AAdventureId: Int64;
  AIncludeUndone: Boolean): TArray<TStep>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LStep: TStep;
  LSql: string;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LSql :=
      'SELECT id, adventure_id, seq, from_section, to_section, kind, note, ' +
      'flag_fight, flag_item, flag_stat, undone, created_at ' +
      'FROM steps WHERE adventure_id=:a';
    if not AIncludeUndone then
      LSql := LSql + ' AND undone=0';
    LSql := LSql + ' ORDER BY seq ASC';
    LQ.Open(LSql, [AAdventureId]);
    while not LQ.Eof do
    begin
      ReadStepRow(LQ, LStep);
      Result := Result + [LStep];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

procedure TStepsRepo.SetUndone(AStepId: Int64; AUndone: Boolean);
var
  LC: TFDConnection;
  LValue: Integer;
begin
  if AUndone then LValue := 1 else LValue := 0;
  LC := NewConn(FConn);
  try
    LC.ExecSQL('UPDATE steps SET undone=:u WHERE id=:i', [LValue, AStepId]);
  finally
    LC.Free;
  end;
end;

procedure TStepsRepo.SetFlagStat(AStepId: Int64; AValue: Boolean);
var
  LC: TFDConnection;
  LValue: Integer;
begin
  if AValue then LValue := 1 else LValue := 0;
  LC := NewConn(FConn);
  try
    LC.ExecSQL('UPDATE steps SET flag_stat=:v WHERE id=:i',
      [LValue, AStepId]);
  finally
    LC.Free;
  end;
end;

procedure TStepsRepo.SetFlagItem(AStepId: Int64; AValue: Boolean);
var
  LC: TFDConnection;
  LValue: Integer;
begin
  if AValue then LValue := 1 else LValue := 0;
  LC := NewConn(FConn);
  try
    LC.ExecSQL('UPDATE steps SET flag_item=:v WHERE id=:i',
      [LValue, AStepId]);
  finally
    LC.Free;
  end;
end;

function TStepsRepo.GetById(AStepId: Int64): TStep;
var
  LC: TFDConnection;
  LQ: TFDQuery;
begin
  Result := Default(TStep);
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, adventure_id, seq, from_section, to_section, kind, note, ' +
      'flag_fight, flag_item, flag_stat, undone, created_at ' +
      'FROM steps WHERE id=:i', [AStepId]);
    if LQ.Eof then
      raise EStepNotFound.CreateFmt('Step not found: %d', [AStepId]);
    ReadStepRow(LQ, Result);
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TStepsRepo.InsertSetup(AAdventureId: Int64): Int64;
var
  LC: TFDConnection;
  LCreatedAt: string;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LCreatedAt := FormatDateTime(ISO_FMT, Now);
      // setup steps always live at seq=1; the create service is responsible
      // for guaranteeing this is the first step of the adventure.
      LC.ExecSQL(
        'INSERT INTO steps (adventure_id, seq, from_section, to_section, ' +
        'kind, note, flag_fight, flag_item, flag_stat, undone, created_at) ' +
        'VALUES (:a, 1, NULL, NULL, ''setup'', '''', 0, 0, 0, 0, :c)',
        [AAdventureId, LCreatedAt]);
      Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
      LC.Commit;
    except
      LC.Rollback; raise;
    end;
  finally
    LC.Free;
  end;
end;

end.
