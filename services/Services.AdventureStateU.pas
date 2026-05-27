{*******************************************************************************
  Unit Name: Services.AdventureStateU
  Purpose: Folds adventure event history into a current-state snapshot

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TAdventureStateService projects the append-only event tables (steps,
    stat_changes, inventory_events) into the live state a player needs:
    the current section, the current stat values, and the current inventory.

    This task (5.1) only implements GetCurrentSection. The stat-history and
    inventory folders are stubs that return empty lists; Tasks 7.1 and 8.1
    will replace those implementations once the event-recording flows land.
    Callers must Free the returned lists.

  Dependencies:
    - System.Generics.Collections
    - FireDAC.Comp.Client
*******************************************************************************}

unit Services.AdventureStateU;

interface

uses
  System.Generics.Collections;

type
  /// <summary>
  ///   Current value of a single tracked stat for an adventure.
  /// </summary>
  TStatSnapshot = record
    /// <summary>stat_defs.id this snapshot is for.</summary>
    StatDefId: Int64;
    /// <summary>Localised display name for the active language.</summary>
    DisplayName: string;
    /// <summary>Stat kind ('integer', 'string', 'boolean', ...).</summary>
    Kind: string;
    /// <summary>Current value as a string, ready for rendering.</summary>
    Value: string;
  end;

  /// <summary>
  ///   Current quantity of a single inventory item for an adventure.
  /// </summary>
  TInventoryItem = record
    /// <summary>Item display name as recorded by the player.</summary>
    Name: string;
    /// <summary>Net quantity after folding gain/lose/modify events.</summary>
    Quantity: Integer;
    /// <summary>Optional free-form note carried with the item.</summary>
    Note: string;
  end;

  /// <summary>
  ///   Read-side service that folds adventure events into current state.
  /// </summary>
  TAdventureStateService = class
  private
    FConn: string;
  public
    /// <summary>Constructs the service bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Returns the section number the player is currently on. Reads the
    ///   adventure's last_step_id and resolves it to steps.to_section.
    ///   Returns 0 when last_step_id is NULL (no steps recorded yet).
    /// </summary>
    function GetCurrentSection(AAdventureId: Int64): Integer;

    /// <summary>
    ///   Returns the current value of every tracked stat for the adventure.
    ///   STUB: this 5.1 implementation returns an empty list. Task 7.1
    ///   replaces it with the real fold over the stat_changes table.
    ///   Callers must Free the returned list.
    /// </summary>
    function GetStatsHistory(AAdventureId: Int64): TList<TStatSnapshot>;

    /// <summary>
    ///   Returns the current inventory for the adventure with quantities
    ///   summed across gain/lose/modify events.
    ///   STUB: this 5.1 implementation returns an empty list. Task 8.1
    ///   replaces it with the real fold over the inventory_events table.
    ///   Callers must Free the returned list.
    /// </summary>
    function GetCurrentInventory(AAdventureId: Int64): TList<TInventoryItem>;
  end;

implementation

uses
  Data.DB,
  FireDAC.Comp.Client;

constructor TAdventureStateService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TAdventureStateService.GetCurrentSection(AAdventureId: Int64): Integer;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LLastStepField: TField;
  LLastStepId: Int64;
begin
  Result := 0;
  LC := TFDConnection.Create(nil);
  LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LQ.Connection := LC;
    LQ.Open('SELECT last_step_id FROM adventures WHERE id=:i',
      [AAdventureId]);
    if LQ.Eof then
      Exit;
    LLastStepField := LQ.FieldByName('last_step_id');
    if LLastStepField.IsNull then
      Exit;
    LLastStepId := LLastStepField.AsLargeInt;
    LQ.Close;
    LQ.Open('SELECT to_section FROM steps WHERE id=:i', [LLastStepId]);
    if not LQ.Eof then
      Result := LQ.FieldByName('to_section').AsInteger;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TAdventureStateService.GetStatsHistory(
  AAdventureId: Int64): TList<TStatSnapshot>;
begin
  // STUB: Task 7.1 will fold stat_changes for AAdventureId into snapshots.
  Result := TList<TStatSnapshot>.Create;
end;

function TAdventureStateService.GetCurrentInventory(
  AAdventureId: Int64): TList<TInventoryItem>;
begin
  // STUB: Task 8.1 will fold inventory_events for AAdventureId into items.
  Result := TList<TInventoryItem>.Create;
end;

end.
