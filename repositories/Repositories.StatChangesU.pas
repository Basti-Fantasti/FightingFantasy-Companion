{*******************************************************************************
  Unit Name: Repositories.StatChangesU
  Purpose: FireDAC repository for the stat_changes table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the stat_changes table. Insert records a single
    stat mutation tied to a step; ListByAdventure joins to steps to return
    every change for an adventure, ordered by step seq then change id so the
    folder service can replay them in chronological order. The IncludeUndone
    flag controls whether changes from soft-undone steps are filtered out.

  Dependencies:
    - Models.StatChangeU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.StatChangesU;

interface

uses
  Models.StatChangeU;

type
  /// <summary>
  ///   Read/write access to the stat_changes table.
  /// </summary>
  TStatChangesRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts a single stat change row tied to a step.
    /// </summary>
    /// <returns>The autoincrement id of the new row.</returns>
    function Insert(AStepId, AStatDefId: Int64;
      const AOldValue, ANewValue, AReason: string): Int64;

    /// <summary>
    ///   Lists every stat change for an adventure, ordered by step seq ASC
    ///   then change id ASC so the folder can replay them chronologically.
    /// </summary>
    /// <param name="AIncludeUndoneSteps">
    ///   When True, returns every change. When False, hides changes whose
    ///   originating step has been soft-undone.
    /// </param>
    function ListByAdventure(AAdventureId: Int64;
      AIncludeUndoneSteps: Boolean): TArray<TStatChange>;
  end;

implementation

uses
  FireDAC.Comp.Client;

function NewConn(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := AName;
  Result.Open;
end;

constructor TStatChangesRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TStatChangesRepo.Insert(AStepId, AStatDefId: Int64;
  const AOldValue, ANewValue, AReason: string): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO stat_changes (step_id, stat_def_id, old_value, ' +
      'new_value, reason) VALUES (:s, :d, :o, :n, :r)',
      [AStepId, AStatDefId, AOldValue, ANewValue, AReason]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

function TStatChangesRepo.ListByAdventure(AAdventureId: Int64;
  AIncludeUndoneSteps: Boolean): TArray<TStatChange>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LSql: string;
  LChange: TStatChange;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LSql :=
      'SELECT sc.id, sc.step_id, sc.stat_def_id, sc.old_value, ' +
      'sc.new_value, sc.reason ' +
      'FROM stat_changes sc ' +
      'JOIN steps s ON s.id = sc.step_id ' +
      'WHERE s.adventure_id = :a';
    if not AIncludeUndoneSteps then
      LSql := LSql + ' AND s.undone = 0';
    LSql := LSql + ' ORDER BY s.seq ASC, sc.id ASC';
    LQ.Open(LSql, [AAdventureId]);
    while not LQ.Eof do
    begin
      LChange.Id        := LQ.FieldByName('id').AsLargeInt;
      LChange.StepId    := LQ.FieldByName('step_id').AsLargeInt;
      LChange.StatDefId := LQ.FieldByName('stat_def_id').AsLargeInt;
      LChange.OldValue  := LQ.FieldByName('old_value').AsString;
      LChange.NewValue  := LQ.FieldByName('new_value').AsString;
      LChange.Reason    := LQ.FieldByName('reason').AsString;
      Result := Result + [LChange];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
