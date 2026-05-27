{*******************************************************************************
  Unit Name: Models.AdventureU
  Purpose: Adventure record matching the adventures table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the adventures table. Repositories
    populate this from FireDAC queries and services pass it around without
    additional behaviour. Kept as a record (not a class) so callers do not
    need to manage lifetime when reading or returning adventure data.

    The LastStepId field is zero when the adventures.last_step_id column is
    NULL, i.e. when the player has not yet recorded a first step.
*******************************************************************************}

unit Models.AdventureU;

interface

type
  /// <summary>
  ///   Snapshot of an adventures row.
  /// </summary>
  TAdventure = record
    /// <summary>Primary key from adventures.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Owning user id (users.id).</summary>
    UserId: Int64;
    /// <summary>Book this adventure plays through (books.id).</summary>
    BookId: Int64;
    /// <summary>Player-chosen title for this run.</summary>
    Title: string;
    /// <summary>One of 'active', 'completed', 'abandoned'.</summary>
    Status: string;
    /// <summary>ISO-8601 timestamp captured when the adventure was created.</summary>
    StartedAt: TDateTime;
    /// <summary>
    ///   steps.id of the most recently recorded step, or 0 when the
    ///   adventure has no steps yet (DB NULL).
    /// </summary>
    LastStepId: Int64;
  end;

implementation

end.
