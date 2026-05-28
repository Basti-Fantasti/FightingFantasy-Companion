{*******************************************************************************
  Unit Name: Models.BookU
  Purpose: Book and book-title records matching the books / book_titles schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data records representing rows in the books and book_titles tables.
    Books carry only the language-neutral fields (slug, author, ownership,
    seed flag, created_at); their localised display titles live in the
    accompanying TBookTitle records. Repositories populate these from FireDAC
    queries and services pass them around without additional behaviour.
*******************************************************************************}

unit Models.BookU;

interface

type
  /// <summary>
  ///   Snapshot of a row in the books table.
  /// </summary>
  TBook = record
    /// <summary>Primary key from books.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Stable machine identifier (e.g. 'citadel-of-chaos').</summary>
    Slug: string;
    /// <summary>Author name as printed on the book cover.</summary>
    Author: string;
    /// <summary>
    ///   Owning user id for custom books; zero for seeded catalogue entries.
    /// </summary>
    OwnerUserId: Int64;
    /// <summary>True when the row originates from the seed catalogue.</summary>
    IsSeed: Boolean;
    /// <summary>ISO-8601 timestamp of insertion, parsed to TDateTime.</summary>
    CreatedAt: TDateTime;
  end;

  /// <summary>
  ///   Snapshot of a row in the book_titles table.
  /// </summary>
  TBookTitle = record
    /// <summary>Foreign key into books.id.</summary>
    BookId: Int64;
    /// <summary>BCP-47 language tag (typically the primary subtag only).</summary>
    Lang: string;
    /// <summary>Display title in the given language.</summary>
    Title: string;
  end;

implementation

end.
