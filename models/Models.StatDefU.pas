{*******************************************************************************
  Unit Name: Models.StatDefU
  Purpose: Stat definition records matching stat_defs / stat_def_titles schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data records representing rows in the stat_defs and stat_def_titles
    tables. A stat definition describes one tracked statistic for a book
    (Skill, Stamina, Luck, ...) including its display order, machine name,
    storage kind and default value. Localised display names live in the
    accompanying TStatDefTitle records.
*******************************************************************************}

unit Models.StatDefU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the stat_defs table.
  /// </summary>
  TStatDef = record
    /// <summary>Primary key from stat_defs.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into books.id.</summary>
    BookId: Int64;
    /// <summary>Display order within the owning book (0-based).</summary>
    Ord: Integer;
    /// <summary>Machine identifier (e.g. 'skill', 'stamina').</summary>
    Name: string;
    /// <summary>One of 'integer', 'text', 'checkbox'.</summary>
    Kind: string;
    /// <summary>Default value used when a new adventure is created.</summary>
    DefaultValue: string;
  end;

  /// <summary>
  ///   Snapshot of a row in the stat_def_titles table.
  /// </summary>
  TStatDefTitle = record
    /// <summary>Foreign key into stat_defs.id.</summary>
    StatDefId: Int64;
    /// <summary>BCP-47 language tag (typically the primary subtag only).</summary>
    Lang: string;
    /// <summary>Display name in the given language.</summary>
    DisplayName: string;
  end;

implementation

end.
