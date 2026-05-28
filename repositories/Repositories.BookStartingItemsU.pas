{*******************************************************************************
  Unit Name: Repositories.BookStartingItemsU
  Purpose: FireDAC repository for book_starting_items and
           book_starting_item_titles

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the starting-item (default loadout) tables. Each
    public method opens a short-lived TFDConnection against the named FireDAC
    connection definition and uses bound parameters throughout. Upsert is
    idempotent on (book_id, slug): re-upserting an existing slug returns the
    original id and refreshes ord and quantity. Replace-all title operations
    run inside a single transaction so a mid-write failure leaves the previous
    titles untouched. ListByBookLocalized returns one row per starting item
    with a localised display name, falling back to any other seeded language
    when the requested language has no entry.

  Dependencies:
    - Models.StartingItemU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.BookStartingItemsU;

interface

uses
  Models.StartingItemU;

type
  /// <summary>
  ///   Read/write access to a book's starting-items catalogue
  ///   (book_starting_items, book_starting_item_titles).
  /// </summary>
  TBookStartingItemsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts or refreshes a starting item keyed by (book_id, slug).
    ///   Re-upserting an existing slug returns the original id and updates
    ///   ord and quantity.
    /// </summary>
    function Upsert(ABookId: Int64; const ASlug: string;
      AOrd, AQuantity: Integer): Int64;

    /// <summary>Replaces all localised titles for the given starting item.</summary>
    procedure SetTitles(AStartingItemId: Int64;
      const ATitles: TArray<TStartingItemTitle>);

    /// <summary>
    ///   Returns one row per starting item with the title chosen for ALang.
    ///   Falls back to any other lang for that item when ALang has no entry,
    ///   so seed-time partial translations still render something.
    /// </summary>
    function ListByBookLocalized(ABookId: Int64;
      const ALang: string): TArray<TStartingItemRow>;
  end;

implementation

uses
  FireDAC.Comp.Client;

function NewConn(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := AName;
  Result.Open;
end;

constructor TBookStartingItemsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TBookStartingItemsRepo.Upsert(ABookId: Int64; const ASlug: string;
  AOrd, AQuantity: Integer): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO book_starting_items (book_id, slug, ord, quantity) ' +
      'VALUES (:b, :s, :o, :q) ' +
      'ON CONFLICT(book_id, slug) DO UPDATE SET ' +
      'ord = excluded.ord, quantity = excluded.quantity',
      [ABookId, ASlug, AOrd, AQuantity]);
    Result := LC.ExecSQLScalar(
      'SELECT id FROM book_starting_items WHERE book_id=:b AND slug=:s',
      [ABookId, ASlug]);
  finally
    LC.Free;
  end;
end;

procedure TBookStartingItemsRepo.SetTitles(AStartingItemId: Int64;
  const ATitles: TArray<TStartingItemTitle>);
var
  LC: TFDConnection;
  LT: TStartingItemTitle;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LC.ExecSQL(
        'DELETE FROM book_starting_item_titles WHERE starting_item_id=:s',
        [AStartingItemId]);
      for LT in ATitles do
        LC.ExecSQL(
          'INSERT INTO book_starting_item_titles ' +
          '(starting_item_id, lang, display_name) ' +
          'VALUES (:s, :l, :n)',
          [AStartingItemId, LT.Lang, LT.DisplayName]);
      LC.Commit;
    except
      LC.Rollback;
      raise;
    end;
  finally
    LC.Free;
  end;
end;

function TBookStartingItemsRepo.ListByBookLocalized(ABookId: Int64;
  const ALang: string): TArray<TStartingItemRow>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LR: TStartingItemRow;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT bsi.slug, ' +
      '       COALESCE(t1.display_name, t2.display_name) AS name, ' +
      '       bsi.quantity ' +
      'FROM book_starting_items bsi ' +
      'LEFT JOIN book_starting_item_titles t1 ' +
      '  ON t1.starting_item_id = bsi.id AND t1.lang = :lang ' +
      'LEFT JOIN book_starting_item_titles t2 ' +
      '  ON t2.starting_item_id = bsi.id AND t2.lang = (' +
      '       SELECT lang FROM book_starting_item_titles ' +
      '       WHERE starting_item_id = bsi.id ORDER BY lang LIMIT 1) ' +
      'WHERE bsi.book_id = :b ' +
      'ORDER BY bsi.ord ASC, bsi.id ASC',
      [ALang, ABookId]);
    while not LQ.Eof do
    begin
      LR.Slug        := LQ.FieldByName('slug').AsString;
      LR.DisplayName := LQ.FieldByName('name').AsString;
      LR.Quantity    := LQ.FieldByName('quantity').AsInteger;
      Result := Result + [LR];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
