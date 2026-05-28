{*******************************************************************************
  Unit Name: Models.SpellDefU
  Purpose: Spell definition records matching spell_defs / spell_def_titles schema

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data records representing rows in the spell_defs and
    spell_def_titles tables. A spell definition describes a single spell
    available in a book's spell list, identified by a stable slug and an
    ordering index. Localised display names and descriptions live in the
    accompanying TSpellDefTitle records.
*******************************************************************************}

unit Models.SpellDefU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the spell_defs table.
  /// </summary>
  TSpellDef = record
    /// <summary>Primary key from spell_defs.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into books.id.</summary>
    BookId: Int64;
    /// <summary>Machine identifier (stable slug, unique within the book).</summary>
    Slug: string;
    /// <summary>Display order within the owning book (0-based).</summary>
    Ord: Integer;
  end;

  /// <summary>
  ///   Snapshot of a row in the spell_def_titles table.
  /// </summary>
  TSpellDefTitle = record
    /// <summary>Foreign key into spell_defs.id.</summary>
    SpellDefId: Int64;
    /// <summary>BCP-47 language tag (typically the primary subtag only).</summary>
    Lang: string;
    /// <summary>Display name in the given language.</summary>
    DisplayName: string;
    /// <summary>Spell description / rules text in the given language.</summary>
    Description: string;
  end;

implementation

end.
