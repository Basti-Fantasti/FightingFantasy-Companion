{*******************************************************************************
  Unit Name: Models.StepU
  Purpose: Step record matching the steps table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the steps table. Steps capture a
    single move recorded by the player along an adventure: source section,
    destination section, an optional note, and side-effect flags that hint
    whether the move also recorded a fight, an inventory change, or a stat
    change.

    The FromSection field is zero when the steps.from_section column is NULL,
    i.e. for the very first step of an adventure where the player jumped in
    without a prior section.
*******************************************************************************}

unit Models.StepU;

interface

type
  /// <summary>
  ///   Snapshot of a steps row.
  /// </summary>
  TStep = record
    /// <summary>Primary key from steps.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Owning adventure id (adventures.id).</summary>
    AdventureId: Int64;
    /// <summary>Monotonic per-adventure sequence number (starts at 1).</summary>
    Seq: Integer;
    /// <summary>
    ///   Source section number, or 0 when the column is NULL (first step).
    /// </summary>
    FromSection: Integer;
    /// <summary>Destination section number.</summary>
    ToSection: Integer;
    /// <summary>Optional free-form player note.</summary>
    Note: string;
    /// <summary>True when this step recorded a fight.</summary>
    FlagFight: Boolean;
    /// <summary>True when this step recorded an inventory change.</summary>
    FlagItem: Boolean;
    /// <summary>True when this step recorded a stat change.</summary>
    FlagStat: Boolean;
    /// <summary>Soft-delete flag for undo; True hides the step from the timeline.</summary>
    Undone: Boolean;
    /// <summary>Timestamp captured when the step was inserted.</summary>
    CreatedAt: TDateTime;
  end;

implementation

end.
