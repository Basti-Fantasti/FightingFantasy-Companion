{*******************************************************************************
  Unit Name: Models.DiceRollU
  Purpose: Dice roll record matching the dice_rolls table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the dice_rolls table. Each row
    captures a single dice expression evaluation (currently '2d6' or '1d6')
    rolled by the player. The StepId field is zero when the dice_rolls.step_id
    column is NULL, i.e. when the roll happened before any step was logged.

  Dependencies:
    - (none beyond System types)
*******************************************************************************}

unit Models.DiceRollU;

interface

type
  /// <summary>
  ///   Snapshot of a dice_rolls row.
  /// </summary>
  TDiceRoll = record
    /// <summary>Primary key from dice_rolls.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Owning adventure id (adventures.id).</summary>
    AdventureId: Int64;
    /// <summary>steps.id this roll is attached to, or 0 when DB column is NULL.</summary>
    StepId: Int64;
    /// <summary>Dice expression, e.g. '2d6' or '1d6'.</summary>
    Expression: string;
    /// <summary>Numeric result of the roll.</summary>
    Rolled: Integer;
    /// <summary>ISO-8601 timestamp captured when the roll was persisted.</summary>
    RolledAt: TDateTime;
  end;

implementation

end.
