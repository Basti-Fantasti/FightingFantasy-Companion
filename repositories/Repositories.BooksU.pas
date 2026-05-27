{*******************************************************************************
  Unit Name: Repositories.BooksU
  Purpose: FireDAC repository for books, book_titles, stat_defs, stat_def_titles

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the book catalogue tables. Each public method opens
    a short-lived TFDConnection against the named FireDAC connection definition
    and uses bound parameters throughout — no SQL is built by concatenating
    user-supplied strings. Replace-all title operations are wrapped in a
    transaction so a mid-write failure leaves the previous titles untouched.

  Dependencies:
    - Models.BookU
    - Models.StatDefU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.BooksU;

interface

uses
  Models.BookU, Models.StatDefU;

type
  /// <summary>
  ///   Read/write access to the book catalogue (books, titles, stat defs).
  /// </summary>
  TBooksRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>Inserts or refreshes a seed catalogue book.</summary>
    function UpsertSeedBook(const ASlug, AAuthor: string): Int64;
    /// <summary>Inserts or refreshes a user-owned custom book.</summary>
    function UpsertCustomBook(AOwnerUserId: Int64;
      const ASlug, AAuthor: string): Int64;
    /// <summary>Replaces all localised titles for the given book.</summary>
    procedure SetBookTitles(ABookId: Int64;
      const ATitles: TArray<TBookTitle>);
    /// <summary>Inserts or refreshes a stat def keyed by (book_id, name).</summary>
    function UpsertStatDef(ABookId: Int64; AOrd: Integer;
      const AName, AKind, ADefaultValue: string): Int64;
    /// <summary>Replaces all localised display names for the stat def.</summary>
    procedure SetStatDefTitles(AStatDefId: Int64;
      const ATitles: TArray<TStatDefTitle>);
    /// <summary>Returns seed books plus the user's own custom books.</summary>
    function ListBooksForUser(AUserId: Int64): TArray<TBook>;
    /// <summary>Loads a single book row by id.</summary>
    function GetBook(ABookId: Int64): TBook;
    /// <summary>Loads stat defs for a book ordered by Ord, Id.</summary>
    function GetStatDefs(ABookId: Int64): TArray<TStatDef>;
    /// <summary>Loads localised titles for a book.</summary>
    function GetBookTitles(ABookId: Int64): TArray<TBookTitle>;
    /// <summary>Loads localised display names for a stat def.</summary>
    function GetStatDefTitles(AStatDefId: Int64): TArray<TStatDefTitle>;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  FireDAC.Comp.Client;

const
  ISO_FMT = 'yyyy-mm-dd"T"hh:nn:ss';

function ParseIsoDateTime(const AValue: string): TDateTime;
begin
  if AValue = '' then Exit(0);
  try Result := ISO8601ToDate(AValue, False); except Result := 0; end;
end;

function NewConn(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := AName;
  Result.Open;
end;

procedure ReadBookRow(AQ: TFDQuery; out ABook: TBook);
begin
  ABook.Id := AQ.FieldByName('id').AsLargeInt;
  ABook.Slug := AQ.FieldByName('slug').AsString;
  ABook.Author := AQ.FieldByName('author').AsString;
  ABook.OwnerUserId := AQ.FieldByName('owner_user_id').AsLargeInt;
  ABook.IsSeed := AQ.FieldByName('is_seed').AsInteger <> 0;
  ABook.CreatedAt := ParseIsoDateTime(AQ.FieldByName('created_at').AsString);
end;

constructor TBooksRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TBooksRepo.UpsertSeedBook(const ASlug, AAuthor: string): Int64;
var LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO books (slug, author, owner_user_id, is_seed, created_at) ' +
      'VALUES (:s, :a, NULL, 1, :c) ' +
      'ON CONFLICT(slug) DO UPDATE SET ' +
      '  author = excluded.author, is_seed = 1, owner_user_id = NULL',
      [ASlug, AAuthor, FormatDateTime(ISO_FMT, Now)]);
    Result := LC.ExecSQLScalar('SELECT id FROM books WHERE slug=:s', [ASlug]);
  finally LC.Free; end;
end;

function TBooksRepo.UpsertCustomBook(AOwnerUserId: Int64;
  const ASlug, AAuthor: string): Int64;
var LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO books (slug, author, owner_user_id, is_seed, created_at) ' +
      'VALUES (:s, :a, :o, 0, :c) ' +
      'ON CONFLICT(slug) DO UPDATE SET ' +
      '  author = excluded.author, is_seed = 0, ' +
      '  owner_user_id = excluded.owner_user_id',
      [ASlug, AAuthor, AOwnerUserId, FormatDateTime(ISO_FMT, Now)]);
    Result := LC.ExecSQLScalar('SELECT id FROM books WHERE slug=:s', [ASlug]);
  finally LC.Free; end;
end;

procedure TBooksRepo.SetBookTitles(ABookId: Int64;
  const ATitles: TArray<TBookTitle>);
var LC: TFDConnection; LT: TBookTitle;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LC.ExecSQL('DELETE FROM book_titles WHERE book_id=:b', [ABookId]);
      for LT in ATitles do
        LC.ExecSQL(
          'INSERT INTO book_titles (book_id, lang, title) VALUES (:b,:l,:t)',
          [ABookId, LT.Lang, LT.Title]);
      LC.Commit;
    except
      LC.Rollback;
      raise;
    end;
  finally LC.Free; end;
end;

function TBooksRepo.UpsertStatDef(ABookId: Int64; AOrd: Integer;
  const AName, AKind, ADefaultValue: string): Int64;
var LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO stat_defs (book_id, ord, name, kind, default_value) ' +
      'VALUES (:b, :o, :n, :k, :d) ' +
      'ON CONFLICT(book_id, name) DO UPDATE SET ' +
      '  ord = excluded.ord, kind = excluded.kind, ' +
      '  default_value = excluded.default_value',
      [ABookId, AOrd, AName, AKind, ADefaultValue]);
    Result := LC.ExecSQLScalar(
      'SELECT id FROM stat_defs WHERE book_id=:b AND name=:n',
      [ABookId, AName]);
  finally LC.Free; end;
end;

procedure TBooksRepo.SetStatDefTitles(AStatDefId: Int64;
  const ATitles: TArray<TStatDefTitle>);
var LC: TFDConnection; LT: TStatDefTitle;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LC.ExecSQL('DELETE FROM stat_def_titles WHERE stat_def_id=:s',
        [AStatDefId]);
      for LT in ATitles do
        LC.ExecSQL(
          'INSERT INTO stat_def_titles (stat_def_id, lang, display_name) ' +
          'VALUES (:s, :l, :d)',
          [AStatDefId, LT.Lang, LT.DisplayName]);
      LC.Commit;
    except
      LC.Rollback;
      raise;
    end;
  finally LC.Free; end;
end;

function TBooksRepo.ListBooksForUser(AUserId: Int64): TArray<TBook>;
var LC: TFDConnection; LQ: TFDQuery; LBook: TBook;
begin
  Result := nil;
  LC := NewConn(FConn); LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, slug, author, owner_user_id, is_seed, created_at ' +
      'FROM books WHERE is_seed=1 OR owner_user_id=:u ' +
      'ORDER BY is_seed DESC, slug', [AUserId]);
    while not LQ.Eof do
    begin
      ReadBookRow(LQ, LBook);
      Result := Result + [LBook];
      LQ.Next;
    end;
  finally LQ.Free; LC.Free; end;
end;

function TBooksRepo.GetBook(ABookId: Int64): TBook;
var LC: TFDConnection; LQ: TFDQuery;
begin
  LC := NewConn(FConn); LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, slug, author, owner_user_id, is_seed, created_at ' +
      'FROM books WHERE id=:i', [ABookId]);
    if not LQ.Eof then
      ReadBookRow(LQ, Result);
  finally LQ.Free; LC.Free; end;
end;

function TBooksRepo.GetStatDefs(ABookId: Int64): TArray<TStatDef>;
var LC: TFDConnection; LQ: TFDQuery; LSD: TStatDef;
begin
  Result := nil;
  LC := NewConn(FConn); LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, book_id, ord, name, kind, default_value ' +
      'FROM stat_defs WHERE book_id=:b ORDER BY ord, id', [ABookId]);
    while not LQ.Eof do
    begin
      LSD.Id := LQ.FieldByName('id').AsLargeInt;
      LSD.BookId := LQ.FieldByName('book_id').AsLargeInt;
      LSD.Ord := LQ.FieldByName('ord').AsInteger;
      LSD.Name := LQ.FieldByName('name').AsString;
      LSD.Kind := LQ.FieldByName('kind').AsString;
      LSD.DefaultValue := LQ.FieldByName('default_value').AsString;
      Result := Result + [LSD];
      LQ.Next;
    end;
  finally LQ.Free; LC.Free; end;
end;

function TBooksRepo.GetBookTitles(ABookId: Int64): TArray<TBookTitle>;
var LC: TFDConnection; LQ: TFDQuery; LT: TBookTitle;
begin
  Result := nil;
  LC := NewConn(FConn); LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open('SELECT book_id, lang, title FROM book_titles ' +
      'WHERE book_id=:b ORDER BY lang', [ABookId]);
    while not LQ.Eof do
    begin
      LT.BookId := LQ.FieldByName('book_id').AsLargeInt;
      LT.Lang := LQ.FieldByName('lang').AsString;
      LT.Title := LQ.FieldByName('title').AsString;
      Result := Result + [LT];
      LQ.Next;
    end;
  finally LQ.Free; LC.Free; end;
end;

function TBooksRepo.GetStatDefTitles(AStatDefId: Int64): TArray<TStatDefTitle>;
var LC: TFDConnection; LQ: TFDQuery; LT: TStatDefTitle;
begin
  Result := nil;
  LC := NewConn(FConn); LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open('SELECT stat_def_id, lang, display_name FROM stat_def_titles ' +
      'WHERE stat_def_id=:s ORDER BY lang', [AStatDefId]);
    while not LQ.Eof do
    begin
      LT.StatDefId := LQ.FieldByName('stat_def_id').AsLargeInt;
      LT.Lang := LQ.FieldByName('lang').AsString;
      LT.DisplayName := LQ.FieldByName('display_name').AsString;
      Result := Result + [LT];
      LQ.Next;
    end;
  finally LQ.Free; LC.Free; end;
end;

end.
