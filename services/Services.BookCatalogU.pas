{*******************************************************************************
  Unit Name: Services.BookCatalogU
  Purpose: Idempotent seed loader that upserts books, titles and stat defs

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TBookCatalogService.LoadSeed reads the seed YAML at the given path, parses
    it via TYamlReader, and upserts every book together with its localised
    titles and stat definitions into the SQLite database identified by the
    supplied FireDAC connection name. The operation is idempotent per spec
    section 7.2:

      * Books are matched by slug; existing rows are refreshed in place.
      * Book and stat-def title sets are reconciled by replace-all (delete +
        re-insert inside a transaction) so titles removed from the YAML
        disappear from the database on the next reload.
      * Books that are no longer present in the YAML are intentionally NOT
        deleted: existing adventures referencing them must keep working.

    Memory ownership:
      TYamlReader returns records whose Titles dictionaries are owned by the
      caller. LoadSeed frees every dictionary (the book Titles plus every
      stat Titles) inside try/finally blocks so seed loading is leak-free
      even when an exception propagates from the repository.

  Dependencies:
    - Models.BookU, Models.StatDefU
    - Repositories.BooksU
    - Services.YamlReaderU
*******************************************************************************}

unit Services.BookCatalogU;

interface

type
  /// <summary>
  ///   Loads the catalogue seed YAML and upserts its contents idempotently.
  /// </summary>
  TBookCatalogService = class
  private
    FConn: string;
  public
    /// <summary>Constructs the service bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);
    /// <summary>
    ///   Reads <paramref name="AYamlPath"/> and upserts every book, title and
    ///   stat definition. Silently returns when the file does not exist so
    ///   callers can invoke it unconditionally on startup.
    /// </summary>
    procedure LoadSeed(const AYamlPath: string);
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  Models.BookU, Models.StatDefU,
  Repositories.BooksU, Services.YamlReaderU;

constructor TBookCatalogService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

procedure TBookCatalogService.LoadSeed(const AYamlPath: string);
var
  LBooks: TArray<TYamlBook>;
  LBook: TYamlBook;
  LStat: TYamlStat;
  LBookRepo: TBooksRepo;
  LBookId, LStatDefId: Int64;
  LTitlesPair: TPair<string, string>;
  LOrd, I: Integer;
  LBookTitles: TArray<TBookTitle>;
  LStatTitles: TArray<TStatDefTitle>;
begin
  if not TFile.Exists(AYamlPath) then
    Exit;
  LBooks := TYamlReader.ParseSeedFile(AYamlPath);
  try
    LBookRepo := TBooksRepo.Create(FConn);
    try
      for LBook in LBooks do
      begin
        LBookId := LBookRepo.UpsertSeedBook(LBook.Slug, LBook.Author);
        // Reconcile book_titles: replace-all
        SetLength(LBookTitles, LBook.Titles.Count);
        I := 0;
        for LTitlesPair in LBook.Titles do
        begin
          LBookTitles[I].BookId := LBookId;
          LBookTitles[I].Lang := LTitlesPair.Key;
          LBookTitles[I].Title := LTitlesPair.Value;
          Inc(I);
        end;
        LBookRepo.SetBookTitles(LBookId, LBookTitles);

        LOrd := 0;
        for LStat in LBook.Stats do
        begin
          LStatDefId := LBookRepo.UpsertStatDef(LBookId, LOrd, LStat.Name,
            LStat.Kind, LStat.DefaultValue);
          SetLength(LStatTitles, LStat.Titles.Count);
          I := 0;
          for LTitlesPair in LStat.Titles do
          begin
            LStatTitles[I].StatDefId := LStatDefId;
            LStatTitles[I].Lang := LTitlesPair.Key;
            LStatTitles[I].DisplayName := LTitlesPair.Value;
            Inc(I);
          end;
          LBookRepo.SetStatDefTitles(LStatDefId, LStatTitles);
          Inc(LOrd);
        end;
      end;
    finally
      LBookRepo.Free;
    end;
  finally
    // Free every dictionary owned by the parser output. TYamlReader allocates
    // one per book (Titles) and one per stat (Stats[i].Titles); records have
    // no destructors, so cleanup is the caller's job.
    for LBook in LBooks do
    begin
      LBook.Titles.Free;
      for LStat in LBook.Stats do
        LStat.Titles.Free;
    end;
  end;
end;

end.
