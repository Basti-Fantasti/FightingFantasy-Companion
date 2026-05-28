unit Tests.Repositories.SpellDefsU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TSpellDefsRepoTests = class
  public
    [Test] procedure Upsert_InsertsRowAndReturnsId;
    [Test] procedure Upsert_IsIdempotentBySlug;
    [Test] procedure SetTitles_ReplacesAllForSpell;
    [Test] procedure ListByBook_OrdersByOrd;
  end;

implementation

uses
  System.SysUtils,
  TestHelpers.DbU,
  Repositories.BooksU, Repositories.SpellDefsU,
  Models.SpellDefU;

procedure TSpellDefsRepoTests.Upsert_InsertsRowAndReturnsId;
var
  LConn: string;
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LBookId, LId1, LId2: Int64;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LId1 := LSpells.UpsertSpellDef(LBookId, 'weakness', 0);
      LId2 := LSpells.UpsertSpellDef(LBookId, 'strength', 1);
      Assert.IsTrue(LId1 > 0);
      Assert.AreNotEqual<Int64>(LId1, LId2);
    finally
      LSpells.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellDefsRepoTests.Upsert_IsIdempotentBySlug;
var
  LConn: string;
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LBookId, LId1, LId2: Int64;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LId1 := LSpells.UpsertSpellDef(LBookId, 'weakness', 0);
      LId2 := LSpells.UpsertSpellDef(LBookId, 'weakness', 5); // re-upsert
      Assert.AreEqual<Int64>(LId1, LId2);
    finally
      LSpells.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellDefsRepoTests.SetTitles_ReplacesAllForSpell;
var
  LConn: string;
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LBookId, LSpellId: Int64;
  LTitles: TArray<TSpellDefTitle>;
  LList: TArray<TSpellDefTitle>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'weakness', 0);
      SetLength(LTitles, 2);
      LTitles[0].SpellDefId := LSpellId; LTitles[0].Lang := 'de';
        LTitles[0].DisplayName := 'Schwäche'; LTitles[0].Description := 'Senkt Skill.';
      LTitles[1].SpellDefId := LSpellId; LTitles[1].Lang := 'en';
        LTitles[1].DisplayName := 'Weakness'; LTitles[1].Description := 'Lowers Skill.';
      LSpells.SetTitles(LSpellId, LTitles);

      // Replace with only DE; EN must disappear.
      SetLength(LTitles, 1);
      LSpells.SetTitles(LSpellId, LTitles);
      LList := LSpells.ListTitles(LSpellId);
      Assert.AreEqual<Integer>(1, Length(LList));
      Assert.AreEqual('de', LList[0].Lang);
    finally
      LSpells.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellDefsRepoTests.ListByBook_OrdersByOrd;
var
  LConn: string;
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LBookId: Int64;
  LList: TArray<TSpellDef>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
      LSpells.UpsertSpellDef(LBookId, 'b', 1);
      LSpells.UpsertSpellDef(LBookId, 'a', 0);
      LSpells.UpsertSpellDef(LBookId, 'c', 2);
      LList := LSpells.ListByBook(LBookId);
      Assert.AreEqual<Integer>(3, Length(LList));
      Assert.AreEqual('a', LList[0].Slug);
      Assert.AreEqual('b', LList[1].Slug);
      Assert.AreEqual('c', LList[2].Slug);
    finally
      LSpells.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSpellDefsRepoTests);

end.
