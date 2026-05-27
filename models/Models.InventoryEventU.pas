{*******************************************************************************
  Unit Name: Models.InventoryEventU
  Purpose: Inventory event record matching the inventory_events table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the inventory_events table. Each
    row captures a single mutation of inventory state triggered by a step:
    a kind ('gain', 'lose', or 'modify'), the item name, a quantity, and an
    optional human-readable note. The folder service uses this together with
    the steps.undone flag to compute the current inventory snapshot for an
    adventure.
*******************************************************************************}

unit Models.InventoryEventU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the inventory_events table.
  /// </summary>
  TInventoryEvent = record
    /// <summary>Primary key from inventory_events.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into steps.id; the step that caused the event.</summary>
    StepId: Int64;
    /// <summary>Event kind: 'gain', 'lose', or 'modify' (absolute set).</summary>
    Kind: string;
    /// <summary>Display name of the item being mutated.</summary>
    ItemName: string;
    /// <summary>Quantity delta for gain/lose, absolute value for modify.</summary>
    Quantity: Integer;
    /// <summary>Optional free-form note carried with the event.</summary>
    Note: string;
  end;

implementation

end.
