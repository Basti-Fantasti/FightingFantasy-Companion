{*******************************************************************************
  Unit Name: Tests.Repositories.BookStartingItemsU
  Purpose: DUnitX tests for TBookStartingItemsRepo

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Verifies the starting-items catalogue repository: idempotent upsert by
    (book_id, slug), full-replace SetTitles semantics, and the localised
    listing's fallback to a seeded language when the requested language is
    missing.
*******************************************************************************}

unit Tests.Repositories.BookStartingItemsU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TBookStartingItemsRepoTests = class
  public
    [Test] procedure Upsert_InsertsAndIsIdempotent;
    [Test] procedure SetTitles_ReplacesAll;
    [Test] procedure ListByBookLocalized_FallsBackToFirstLangWhenMissing;
  end;

implementation

uses
  System.SysUtils,
  TestHelpers.DbU,
  Repositories.BooksU, Repositories.BookStartingItemsU,
  Models.StartingItemU;

procedure TBookStartingItemsRepoTests.Upsert_InsertsAndIsIdempotent;
var
  LConn: string; LBooks: TBooksRepo; LRepo: TBookStartingItemsRepo;
  LBookId, LId1, LId2: Int64;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LRepo := TBookStartingItemsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LId1 := LRepo.Upsert(LBookId, 'sword', 0, 1);
      LId2 := LRepo.Upsert(LBookId, 'sword', 5, 3);
      Assert.AreEqual<Int64>(LId1, LId2);
    finally
      LRepo.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TBookStartingItemsRepoTests.SetTitles_ReplacesAll;
var
  LConn: string; LBooks: TBooksRepo; LRepo: TBookStartingItemsRepo;
  LBookId, LItemId: Int64;
  LTitles: TArray<TStartingItemTitle>;
  LRows: TArray<TStartingItemRow>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LRepo := TBookStartingItemsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LItemId := LRepo.Upsert(LBookId, 'sword', 0, 1);
      SetLength(LTitles, 2);
      LTitles[0].StartingItemId := LItemId; LTitles[0].Lang := 'de'; LTitles[0].DisplayName := 'Schwert';
      LTitles[1].StartingItemId := LItemId; LTitles[1].Lang := 'en'; LTitles[1].DisplayName := 'Sword';
      LRepo.SetTitles(LItemId, LTitles);
      LRows := LRepo.ListByBookLocalized(LBookId, 'de');
      Assert.AreEqual(1, Integer(Length(LRows)));
      Assert.AreEqual('Schwert', LRows[0].DisplayName);
    finally
      LRepo.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TBookStartingItemsRepoTests.ListByBookLocalized_FallsBackToFirstLangWhenMissing;
var
  LConn: string; LBooks: TBooksRepo; LRepo: TBookStartingItemsRepo;
  LBookId, LItemId: Int64;
  LTitles: TArray<TStartingItemTitle>;
  LRows: TArray<TStartingItemRow>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LRepo := TBookStartingItemsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LItemId := LRepo.Upsert(LBookId, 'sword', 0, 1);
      SetLength(LTitles, 1);
      LTitles[0].StartingItemId := LItemId; LTitles[0].Lang := 'de'; LTitles[0].DisplayName := 'Schwert';
      LRepo.SetTitles(LItemId, LTitles);
      LRows := LRepo.ListByBookLocalized(LBookId, 'en'); // EN missing
      Assert.AreEqual(1, Integer(Length(LRows)));
      Assert.AreEqual('Schwert', LRows[0].DisplayName, 'must fall back to seeded lang');
    finally
      LRepo.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBookStartingItemsRepoTests);

end.
