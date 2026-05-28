{*******************************************************************************
  Unit Name: Tests.Services.BookCatalogU
  Purpose: DUnitX tests for TBookCatalogService.LoadSeed idempotency

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Covers the idempotent-upsert contract from spec section 7.2:
      * Loading the same YAML twice produces stable row counts.
      * Removing a title from the YAML deletes it from the database on reload.
      * Removing a book from the YAML does NOT delete it from the database.

    Each test runs against a fresh in-memory SQLite database created via
    TDbHelper and writes its YAML fixtures to a temp file that is deleted in
    a finally block.
*******************************************************************************}

unit Tests.Services.BookCatalogU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   Asserts the seed-loader keeps the catalogue in sync with the YAML.
  /// </summary>
  [TestFixture]
  TBookCatalogServiceTests = class
  public
    [Test] procedure LoadingSeedTwiceIsIdempotent;
    [Test] procedure RemovingTitleFromYamlDeletesItOnReload;
    [Test] procedure BookMissingFromYamlNotDeleted;
    [Test] procedure LoadSeed_PopulatesSpellsAndStartingItems;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  FireDAC.Comp.Client,
  Services.BookCatalogU, TestHelpers.DbU,
  Repositories.BooksU, Repositories.SpellDefsU,
  Repositories.BookStartingItemsU,
  Models.SpellDefU, Models.StartingItemU;

const
  FIXTURE_CITADEL_FULL =
    '- slug: citadel-of-chaos'#10 +
    '  author: Steve Jackson'#10 +
    '  titles:'#10 +
    '    en: The Citadel of Chaos'#10 +
    '    de: Die Zitadelle des Zauberers'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill, de: Geschicklichkeit } }'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic, de: Magie } }'#10;

  FIXTURE_CITADEL_EN_ONLY =
    '- slug: citadel-of-chaos'#10 +
    '  author: Steve Jackson'#10 +
    '  titles:'#10 +
    '    en: The Citadel of Chaos'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill, de: Geschicklichkeit } }'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic, de: Magie } }'#10;

  FIXTURE_TWO_BOOKS =
    '- slug: citadel-of-chaos'#10 +
    '  author: Steve Jackson'#10 +
    '  titles:'#10 +
    '    en: The Citadel of Chaos'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill } }'#10 +
    #10 +
    '- slug: warlock-of-firetop-mountain'#10 +
    '  author: Steve Jackson & Ian Livingstone'#10 +
    '  titles:'#10 +
    '    en: The Warlock of Firetop Mountain'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill } }'#10;

  FIXTURE_ONE_BOOK =
    '- slug: warlock-of-firetop-mountain'#10 +
    '  author: Steve Jackson & Ian Livingstone'#10 +
    '  titles:'#10 +
    '    en: The Warlock of Firetop Mountain'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill } }'#10;

/// <summary>
///   Writes the YAML body to a freshly named temp file and returns its path.
///   The caller is responsible for deleting it.
/// </summary>
function WriteTempYaml(const AContent: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'ffcompanion_seed_' + FormatDateTime('yyyymmddhhnnsszzz', Now) +
    '_' + IntToStr(Random(MaxInt)) + '.yaml');
  TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function CountRows(const AConnName, ASql: string): Integer;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := AConnName;
    LC.Open;
    Result := LC.ExecSQLScalar(ASql);
  finally
    LC.Free;
  end;
end;

function CountRowsParam(const AConnName, ASql: string;
  const AParams: array of Variant): Integer;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := AConnName;
    LC.Open;
    Result := LC.ExecSQLScalar(ASql, AParams);
  finally
    LC.Free;
  end;
end;

procedure TBookCatalogServiceTests.LoadingSeedTwiceIsIdempotent;
var
  LDb, LPath: string;
  LSvc: TBookCatalogService;
begin
  LDb := TDbHelper.NewMemoryDb;
  LPath := WriteTempYaml(FIXTURE_CITADEL_FULL);
  LSvc := TBookCatalogService.Create(LDb);
  try
    LSvc.LoadSeed(LPath);
    LSvc.LoadSeed(LPath);

    Assert.AreEqual(1, CountRows(LDb, 'SELECT COUNT(*) FROM books'),
      'books table must contain exactly one row after double load');
    Assert.AreEqual(2, CountRows(LDb, 'SELECT COUNT(*) FROM book_titles'),
      'book_titles must contain 2 rows (en + de)');
    Assert.AreEqual(2, CountRows(LDb, 'SELECT COUNT(*) FROM stat_defs'),
      'stat_defs must contain 2 rows (skill + magic)');
    Assert.AreEqual(4, CountRows(LDb, 'SELECT COUNT(*) FROM stat_def_titles'),
      'stat_def_titles must contain 4 rows (2 stats x 2 langs)');
  finally
    LSvc.Free;
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
    TDbHelper.Drop(LDb);
  end;
end;

procedure TBookCatalogServiceTests.RemovingTitleFromYamlDeletesItOnReload;
var
  LDb, LPath1, LPath2: string;
  LSvc: TBookCatalogService;
  LBookId: Int64;
  LC: TFDConnection;
begin
  LDb := TDbHelper.NewMemoryDb;
  LPath1 := WriteTempYaml(FIXTURE_CITADEL_FULL);
  LPath2 := WriteTempYaml(FIXTURE_CITADEL_EN_ONLY);
  LSvc := TBookCatalogService.Create(LDb);
  try
    LSvc.LoadSeed(LPath1);
    LSvc.LoadSeed(LPath2);

    LC := TFDConnection.Create(nil);
    try
      LC.ConnectionDefName := LDb;
      LC.Open;
      LBookId := LC.ExecSQLScalar(
        'SELECT id FROM books WHERE slug=:s', ['citadel-of-chaos']);
    finally
      LC.Free;
    end;

    Assert.AreEqual(1,
      CountRowsParam(LDb,
        'SELECT COUNT(*) FROM book_titles WHERE book_id=:b', [LBookId]),
      'only one book_title row should survive (en)');
    Assert.AreEqual(0,
      CountRowsParam(LDb,
        'SELECT COUNT(*) FROM book_titles WHERE book_id=:b AND lang=:l',
        [LBookId, 'de']),
      'de title row must be deleted after reload');
    Assert.AreEqual(1,
      CountRowsParam(LDb,
        'SELECT COUNT(*) FROM book_titles WHERE book_id=:b AND lang=:l',
        [LBookId, 'en']),
      'en title row must remain after reload');
  finally
    LSvc.Free;
    if TFile.Exists(LPath1) then
      TFile.Delete(LPath1);
    if TFile.Exists(LPath2) then
      TFile.Delete(LPath2);
    TDbHelper.Drop(LDb);
  end;
end;

procedure TBookCatalogServiceTests.BookMissingFromYamlNotDeleted;
var
  LDb, LPath1, LPath2: string;
  LSvc: TBookCatalogService;
begin
  LDb := TDbHelper.NewMemoryDb;
  LPath1 := WriteTempYaml(FIXTURE_TWO_BOOKS);
  LPath2 := WriteTempYaml(FIXTURE_ONE_BOOK);
  LSvc := TBookCatalogService.Create(LDb);
  try
    LSvc.LoadSeed(LPath1);
    Assert.AreEqual(2, CountRows(LDb, 'SELECT COUNT(*) FROM books'),
      'precondition: both books loaded');

    LSvc.LoadSeed(LPath2);
    Assert.AreEqual(2, CountRows(LDb, 'SELECT COUNT(*) FROM books'),
      'books absent from YAML on reload must NOT be deleted (spec 7.2)');
    Assert.AreEqual(1,
      CountRowsParam(LDb,
        'SELECT COUNT(*) FROM books WHERE slug=:s', ['citadel-of-chaos']),
      'previously-seeded book must remain');
    Assert.AreEqual(1,
      CountRowsParam(LDb,
        'SELECT COUNT(*) FROM books WHERE slug=:s',
        ['warlock-of-firetop-mountain']),
      'currently-seeded book must remain');
  finally
    LSvc.Free;
    if TFile.Exists(LPath1) then
      TFile.Delete(LPath1);
    if TFile.Exists(LPath2) then
      TFile.Delete(LPath2);
    TDbHelper.Drop(LDb);
  end;
end;

procedure TBookCatalogServiceTests.LoadSeed_PopulatesSpellsAndStartingItems;
const
  CYaml =
    '- slug: citadel'#10 +
    '  author: SJ'#10 +
    '  titles:'#10 +
    '    en: Citadel'#10 +
    '  stats:'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic } }'#10 +
    '  starting_inventory:'#10 +
    '    - { slug: sword, titles: { de: Schwert, en: Sword } }'#10 +
    '  spells:'#10 +
    '    - { slug: strength, names: { de: Stärke, en: Strength }, descriptions: { de: "Erhöht Skill.", en: "Raises Skill." } }'#10;
var
  LConn, LPath: string;
  LSvc: TBookCatalogService;
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LItems: TBookStartingItemsRepo;
  LBookId: Int64;
  LSpellList: TArray<TSpellDef>;
  LSpellTitles: TArray<TSpellDefTitle>;
  LItemRows: TArray<TStartingItemRow>;
begin
  LConn := TDbHelper.NewMemoryDb;
  LPath := TPath.Combine(TPath.GetTempPath, 'seed_'+IntToStr(Random(1000000))+'.yaml');
  try
    TFile.WriteAllText(LPath, CYaml, TEncoding.UTF8);
    LSvc := TBookCatalogService.Create(LConn);
    try
      LSvc.LoadSeed(LPath);
      LSvc.LoadSeed(LPath); // idempotent
    finally
      LSvc.Free;
    end;

    LBooks := TBooksRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    LItems := TBookStartingItemsRepo.Create(LConn);
    try
      LBookId := LBooks.FindIdBySlug('citadel');
      Assert.IsTrue(LBookId > 0);
      LSpellList := LSpells.ListByBook(LBookId);
      Assert.AreEqual<Integer>(1, Length(LSpellList));
      Assert.AreEqual('strength', LSpellList[0].Slug);
      LSpellTitles := LSpells.ListTitles(LSpellList[0].Id);
      Assert.AreEqual<Integer>(2, Length(LSpellTitles));
      LItemRows := LItems.ListByBookLocalized(LBookId, 'de');
      Assert.AreEqual<Integer>(1, Length(LItemRows));
      Assert.AreEqual('Schwert', LItemRows[0].DisplayName);
    finally
      LItems.Free; LSpells.Free; LBooks.Free;
    end;
  finally
    if TFile.Exists(LPath) then TFile.Delete(LPath);
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBookCatalogServiceTests);

end.
