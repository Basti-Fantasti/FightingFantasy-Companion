{*******************************************************************************
  Unit Name: Models.StatChangeU
  Purpose: Stat change record matching the stat_changes table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the stat_changes table. Each row
    captures a single mutation of a stat value triggered by a step: old value,
    new value, and an optional human-readable reason. The folder service uses
    this together with the steps.undone flag to compute the current stat
    snapshot for an adventure.
*******************************************************************************}

unit Models.StatChangeU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the stat_changes table.
  /// </summary>
  TStatChange = record
    /// <summary>Primary key from stat_changes.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into steps.id; the step that caused the change.</summary>
    StepId: Int64;
    /// <summary>Foreign key into stat_defs.id; the stat that changed.</summary>
    StatDefId: Int64;
    /// <summary>Value before the change (may be empty for the first write).</summary>
    OldValue: string;
    /// <summary>Value after the change.</summary>
    NewValue: string;
    /// <summary>Optional human-readable reason annotation.</summary>
    Reason: string;
  end;

implementation

end.
