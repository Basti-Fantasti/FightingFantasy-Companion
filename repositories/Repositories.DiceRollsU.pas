{*******************************************************************************
  Unit Name: Repositories.DiceRollsU
  Purpose: FireDAC repository for the dice_rolls table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the dice_rolls table. Insert records a single dice
    expression evaluation tied (optionally) to a step; pass zero for the step
    id to write a SQL NULL (rolls made before any step is logged). LastN
    returns the most recent N rolls for an adventure ordered by rolled_at
    descending so the panel can show a short history alongside the latest
    result.

  Dependencies:
    - Models.DiceRollU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.DiceRollsU;

interface

uses
  Models.DiceRollU;

type
  /// <summary>
  ///   Read/write access to the dice_rolls table.
  /// </summary>
  TDiceRollsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts a single dice roll row. Pass 0 for AStepId to store NULL in
    ///   the step_id column (rolls made before any step exists).
    /// </summary>
    /// <returns>The autoincrement id of the new row.</returns>
    function Insert(AAdventureId, AStepId: Int64;
      const AExpression: string; AResult: Integer): Int64;

    /// <summary>
    ///   Returns the N most recent dice rolls for an adventure, ordered by
    ///   rolled_at DESC. Used to populate the recent-history list in the dice
    ///   panel.
    /// </summary>
    function LastN(AAdventureId: Int64; ACount: Integer): TArray<TDiceRoll>;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
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

constructor TDiceRollsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TDiceRollsRepo.Insert(AAdventureId, AStepId: Int64;
  const AExpression: string; AResult: Integer): Int64;
var
  LC: TFDConnection;
  LNow: string;
begin
  LC := NewConn(FConn);
  try
    LNow := FormatDateTime(ISO_FMT, Now);
    if AStepId = 0 then
      // step_id NULL: roll happened before any step was logged.
      LC.ExecSQL(
        'INSERT INTO dice_rolls (adventure_id, step_id, expression, ' +
        'result, rolled_at) VALUES (:a, NULL, :e, :r, :t)',
        [AAdventureId, AExpression, AResult, LNow])
    else
      LC.ExecSQL(
        'INSERT INTO dice_rolls (adventure_id, step_id, expression, ' +
        'result, rolled_at) VALUES (:a, :s, :e, :r, :t)',
        [AAdventureId, AStepId, AExpression, AResult, LNow]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

function TDiceRollsRepo.LastN(AAdventureId: Int64;
  ACount: Integer): TArray<TDiceRoll>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LRoll: TDiceRoll;
  LField: TField;
begin
  Result := nil;
  if ACount <= 0 then
    Exit;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, adventure_id, step_id, expression, result, rolled_at ' +
      'FROM dice_rolls WHERE adventure_id=:a ' +
      'ORDER BY rolled_at DESC, id DESC LIMIT :n',
      [AAdventureId, ACount]);
    while not LQ.Eof do
    begin
      LRoll.Id          := LQ.FieldByName('id').AsLargeInt;
      LRoll.AdventureId := LQ.FieldByName('adventure_id').AsLargeInt;
      LField := LQ.FieldByName('step_id');
      if LField.IsNull then
        LRoll.StepId := 0
      else
        LRoll.StepId := LField.AsLargeInt;
      LRoll.Expression := LQ.FieldByName('expression').AsString;
      LRoll.Rolled     := LQ.FieldByName('result').AsInteger;
      LRoll.RolledAt   := ParseIsoDateTime(LQ.FieldByName('rolled_at').AsString);
      Result := Result + [LRoll];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
