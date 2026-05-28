{*******************************************************************************
  Unit Name: Models.StartingItemU
  Purpose: Starting-item records matching book_starting_items /
           book_starting_item_titles schema

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data records representing rows in the book_starting_items and
    book_starting_item_titles tables. A starting item describes one entry
    in a book's default inventory loadout used when a new adventure is
    created. Localised display names live in the accompanying
    TStartingItemTitle records; TStartingItemRow is a pre-localised view
    used by the create-adventure form to render the default loadout.
*******************************************************************************}

unit Models.StartingItemU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the book_starting_items table.
  /// </summary>
  TStartingItem = record
    /// <summary>Primary key from book_starting_items.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Foreign key into books.id.</summary>
    BookId: Int64;
    /// <summary>Machine identifier (stable slug, unique within the book).</summary>
    Slug: string;
    /// <summary>Display order within the owning book (0-based).</summary>
    Ord: Integer;
    /// <summary>Default quantity granted when a new adventure is created.</summary>
    Quantity: Integer;
  end;

  /// <summary>
  ///   Snapshot of a row in the book_starting_item_titles table.
  /// </summary>
  TStartingItemTitle = record
    /// <summary>Foreign key into book_starting_items.id.</summary>
    StartingItemId: Int64;
    /// <summary>BCP-47 language tag (typically the primary subtag only).</summary>
    Lang: string;
    /// <summary>Display name in the given language.</summary>
    DisplayName: string;
  end;

  /// <summary>Pre-localized view used by the create form.</summary>
  TStartingItemRow = record
    /// <summary>Machine identifier (stable slug from book_starting_items).</summary>
    Slug: string;
    /// <summary>Localised display name resolved for the current request.</summary>
    DisplayName: string;
    /// <summary>Default quantity granted when a new adventure is created.</summary>
    Quantity: Integer;
  end;

implementation

end.
