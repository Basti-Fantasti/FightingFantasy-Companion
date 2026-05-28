{*******************************************************************************
  Unit Name: Models.AdventureSpellU
  Purpose: Adventure-spell records matching the adventure_spells table schema

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the adventure_spells table.
    Each row is one copy of a spell prepared for a given adventure; when the
    player casts a spell the row is flagged consumed and tied to the step
    that consumed it. The TAdventureSpellGroup aggregate is a view used by
    the Spells panel: one entry per spell definition with the available /
    consumed counts pre-computed for rendering.
*******************************************************************************}

unit Models.AdventureSpellU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the adventure_spells table.
  /// </summary>
  TAdventureSpell = record
    /// <summary>Primary key from adventure_spells.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into adventures.id.</summary>
    AdventureId: Int64;
    /// <summary>Foreign key into spell_defs.id.</summary>
    SpellDefId: Int64;
    /// <summary>Display order within the adventure's spell list (0-based).</summary>
    Ord: Integer;
    /// <summary>True when this copy of the spell has been cast.</summary>
    Consumed: Boolean;
    /// <summary>Timestamp the spell was consumed; 0 when not consumed.</summary>
    ConsumedAt: TDateTime;
    /// <summary>Step that consumed this spell; 0 when not consumed.</summary>
    ConsumedStepId: Int64;
  end;

  /// <summary>Aggregated view used by the Spells panel:
  /// one entry per spell definition with the available/consumed counts.</summary>
  TAdventureSpellGroup = record
    /// <summary>Foreign key into spell_defs.id.</summary>
    SpellDefId: Int64;
    /// <summary>Machine identifier (stable slug from spell_defs).</summary>
    Slug: string;
    /// <summary>Localised display name resolved for the current request.</summary>
    DisplayName: string;
    /// <summary>Localised description resolved for the current request.</summary>
    Description: string;
    /// <summary>Number of copies of this spell still available to cast.</summary>
    Available: Integer;
    /// <summary>Number of copies of this spell already consumed.</summary>
    Consumed: Integer;
  end;

implementation

end.
