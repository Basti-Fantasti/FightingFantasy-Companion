{*******************************************************************************
  Unit Name: Repositories.InventoryEventsU
  Purpose: FireDAC repository for the inventory_events table

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the inventory_events table. Insert records a single
    inventory mutation tied to a step; ListByAdventure joins to steps to
    return every event for an adventure, ordered by step seq then event id so
    the folder service can replay them in chronological order. The
    IncludeUndone flag controls whether events from soft-undone steps are
    filtered out.

  Dependencies:
    - Models.InventoryEventU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.InventoryEventsU;

interface

uses
  Models.InventoryEventU;

type
  /// <summary>
  ///   Read/write access to the inventory_events table.
  /// </summary>
  TInventoryEventsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts a single inventory event row tied to a step. Kind must be
    ///   one of 'gain', 'lose', or 'modify'; the CHECK constraint on the
    ///   table will reject any other value.
    /// </summary>
    /// <returns>The autoincrement id of the new row.</returns>
    function Insert(AStepId: Int64; const AKind, AItemName: string;
      AQuantity: Integer; const ANote: string): Int64;

    /// <summary>
    ///   Lists every inventory event for an adventure, ordered by step seq
    ///   ASC then event id ASC so the folder can replay them chronologically.
    /// </summary>
    /// <param name="AIncludeUndoneSteps">
    ///   When True, returns every event. When False, hides events whose
    ///   originating step has been soft-undone.
    /// </param>
    function ListByAdventure(AAdventureId: Int64;
      AIncludeUndoneSteps: Boolean): TArray<TInventoryEvent>;
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

constructor TInventoryEventsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TInventoryEventsRepo.Insert(AStepId: Int64;
  const AKind, AItemName: string; AQuantity: Integer;
  const ANote: string): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO inventory_events (step_id, kind, item_name, quantity, ' +
      'note) VALUES (:s, :k, :i, :q, :n)',
      [AStepId, AKind, AItemName, AQuantity, ANote]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

function TInventoryEventsRepo.ListByAdventure(AAdventureId: Int64;
  AIncludeUndoneSteps: Boolean): TArray<TInventoryEvent>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LSql: string;
  LEvent: TInventoryEvent;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LSql :=
      'SELECT ie.id, ie.step_id, ie.kind, ie.item_name, ie.quantity, ' +
      'ie.note ' +
      'FROM inventory_events ie ' +
      'JOIN steps s ON s.id = ie.step_id ' +
      'WHERE s.adventure_id = :a';
    if not AIncludeUndoneSteps then
      LSql := LSql + ' AND s.undone = 0';
    LSql := LSql + ' ORDER BY s.seq ASC, ie.id ASC';
    LQ.Open(LSql, [AAdventureId]);
    while not LQ.Eof do
    begin
      LEvent.Id       := LQ.FieldByName('id').AsLargeInt;
      LEvent.StepId   := LQ.FieldByName('step_id').AsLargeInt;
      LEvent.Kind     := LQ.FieldByName('kind').AsString;
      LEvent.ItemName := LQ.FieldByName('item_name').AsString;
      LEvent.Quantity := LQ.FieldByName('quantity').AsInteger;
      LEvent.Note     := LQ.FieldByName('note').AsString;
      Result := Result + [LEvent];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
