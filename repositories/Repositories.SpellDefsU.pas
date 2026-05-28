{*******************************************************************************
  Unit Name: Repositories.SpellDefsU
  Purpose: FireDAC repository for spell_defs and spell_def_titles

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Data-access layer over the spell catalogue tables. Each public method opens
    a short-lived TFDConnection against the named FireDAC connection definition
    and uses bound parameters throughout. UpsertSpellDef is idempotent on the
    (book_id, slug) pair: re-upserting an existing slug returns the original id
    and refreshes the ord. Replace-all title operations run inside a single
    transaction so a mid-write failure leaves the previous titles untouched.

  Dependencies:
    - Models.SpellDefU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Repositories.SpellDefsU;

interface

uses
  Models.SpellDefU;

type
  /// <summary>
  ///   Read/write access to the spell catalogue (spell_defs, spell_def_titles).
  /// </summary>
  TSpellDefsRepo = class
  private
    FConn: string;
  public
    /// <summary>Constructs the repo bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Inserts or refreshes a spell definition keyed by (book_id, slug).
    ///   Re-upserting an existing slug returns the original id and updates ord.
    /// </summary>
    function UpsertSpellDef(ABookId: Int64; const ASlug: string;
      AOrd: Integer): Int64;

    /// <summary>Replaces all localised titles for the given spell def.</summary>
    procedure SetTitles(ASpellDefId: Int64;
      const ATitles: TArray<TSpellDefTitle>);

    /// <summary>Loads spell defs for a book ordered by Ord, Id.</summary>
    function ListByBook(ABookId: Int64): TArray<TSpellDef>;

    /// <summary>Loads localised titles for a spell def ordered by lang.</summary>
    function ListTitles(ASpellDefId: Int64): TArray<TSpellDefTitle>;
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

constructor TSpellDefsRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TSpellDefsRepo.UpsertSpellDef(ABookId: Int64; const ASlug: string;
  AOrd: Integer): Int64;
var
  LC: TFDConnection;
begin
  LC := NewConn(FConn);
  try
    LC.ExecSQL(
      'INSERT INTO spell_defs (book_id, slug, ord) VALUES (:b, :s, :o) ' +
      'ON CONFLICT(book_id, slug) DO UPDATE SET ord = excluded.ord',
      [ABookId, ASlug, AOrd]);
    Result := LC.ExecSQLScalar(
      'SELECT id FROM spell_defs WHERE book_id=:b AND slug=:s',
      [ABookId, ASlug]);
  finally
    LC.Free;
  end;
end;

procedure TSpellDefsRepo.SetTitles(ASpellDefId: Int64;
  const ATitles: TArray<TSpellDefTitle>);
var
  LC: TFDConnection;
  LT: TSpellDefTitle;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LC.ExecSQL('DELETE FROM spell_def_titles WHERE spell_def_id=:s',
        [ASpellDefId]);
      for LT in ATitles do
        LC.ExecSQL(
          'INSERT INTO spell_def_titles ' +
          '(spell_def_id, lang, display_name, description) ' +
          'VALUES (:s, :l, :n, :d)',
          [ASpellDefId, LT.Lang, LT.DisplayName, LT.Description]);
      LC.Commit;
    except
      LC.Rollback;
      raise;
    end;
  finally
    LC.Free;
  end;
end;

function TSpellDefsRepo.ListByBook(ABookId: Int64): TArray<TSpellDef>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LSD: TSpellDef;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT id, book_id, slug, ord FROM spell_defs ' +
      'WHERE book_id=:b ORDER BY ord ASC, id ASC',
      [ABookId]);
    while not LQ.Eof do
    begin
      LSD.Id     := LQ.FieldByName('id').AsLargeInt;
      LSD.BookId := LQ.FieldByName('book_id').AsLargeInt;
      LSD.Slug   := LQ.FieldByName('slug').AsString;
      LSD.Ord    := LQ.FieldByName('ord').AsInteger;
      Result := Result + [LSD];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TSpellDefsRepo.ListTitles(ASpellDefId: Int64): TArray<TSpellDefTitle>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LT: TSpellDefTitle;
begin
  Result := nil;
  LC := NewConn(FConn);
  LQ := TFDQuery.Create(nil);
  try
    LQ.Connection := LC;
    LQ.Open(
      'SELECT spell_def_id, lang, display_name, description ' +
      'FROM spell_def_titles WHERE spell_def_id=:s ORDER BY lang ASC',
      [ASpellDefId]);
    while not LQ.Eof do
    begin
      LT.SpellDefId  := LQ.FieldByName('spell_def_id').AsLargeInt;
      LT.Lang        := LQ.FieldByName('lang').AsString;
      LT.DisplayName := LQ.FieldByName('display_name').AsString;
      LT.Description := LQ.FieldByName('description').AsString;
      Result := Result + [LT];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
