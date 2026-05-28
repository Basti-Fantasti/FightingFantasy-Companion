# Spells & Starting Gear Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement seeded starting inventory + opt-in spell list with pick UI and cast/strike-out mechanics, both wired into the adventure-create flow and the adventure page.

**Architecture:** Schema extension (new `spell_defs`, `spell_def_titles`, `adventure_spells`, `book_starting_items`, `book_starting_item_titles` tables; `steps.kind` column; `steps.to_section` made nullable). Seed YAML grows two optional block types parsed by an extended `TYamlReader`. Adventure creation becomes transactional and seeds a synthetic `kind='setup'` step holding starting-gear `inventory_events`. A new `SpellService` handles cast/undo; the adventure page gains a third panel rendered from `TAdventureStateService`.

**Tech Stack:** Delphi (RTL + FireDAC), DMVCFramework, TemplatePro, HTMX, Bulma, SQLite, DUnitX.

**Spec source:** [`../specs/2026-05-28-spells-and-gear-design.md`](../specs/2026-05-28-spells-and-gear-design.md).

**Spec deviations the plan applies:**
1. The spec says "no new tables for gear". To make seeded starting inventory queryable at adventure-create time without re-parsing YAML, this plan adds `book_starting_items` + `book_starting_item_titles` tables seeded by `TBookCatalogService`.
2. The spec used the conceptual column name `section_no`; the live schema uses `from_section` / `to_section`. The setup step uses `to_section NULL` (existing convention: `from_section NULL` already means "first step"; nullable `to_section` is new).
3. The seed unit referenced in the spec ("webmodule/SeedU.pas") does not exist — seeding lives in `services/Services.BookCatalogU.pas`. All seed extensions land there.
4. The YAML parser (`Services.YamlReaderU`) is strict and limited. Seed format is constrained to its dialect: inline mappings, one level of nesting under `titles`. Spell entries therefore use two title-style maps (`names: { de: …, en: … }`, `descriptions: { de: …, en: … }`) instead of `titles: { de: { name: …, description: … } }`.

**Greenfield migration policy:** The user has confirmed no backwards-compatibility is required. The migration runner uses `CREATE TABLE IF NOT EXISTS`, which will NOT add the new `kind` column to a pre-existing `steps` table. Before running the upgraded binary against a previously-used DB, delete `data/ffcompanion.db`.

**Build/test commands** (run from project root in Windows where Delphi runs; tests are Win64 only per README):

- Build the test runner: `mcp__delphi-build__compile_delphi_project` against `tests/FFCompanionTests.dproj` (Win64 Debug).
- Run all tests: `tests/bin/Win64/Debug/FFCompanionTests.exe`.
- Run a single test fixture: `tests/bin/Win64/Debug/FFCompanionTests.exe --include:<TestFixtureName>`.
- Build the Linux64 server binary (after server changes pass): `mcp__delphi-build__compile_delphi_project` against `FFCompanion.dproj` (Linux64 Release).

**Commit convention:** Imperative subject line, no AI attribution. Use `feat:`, `test:`, `refactor:` prefixes consistent with the recent log (`git log --oneline -20`).

---

## File Structure

**New files:**
- `models/Models.SpellDefU.pas` — `TSpellDef`, `TSpellDefTitle` records.
- `models/Models.AdventureSpellU.pas` — `TAdventureSpell`, `TAdventureSpellSnapshot` records.
- `models/Models.StartingItemU.pas` — `TStartingItem`, `TStartingItemTitle` records.
- `repositories/Repositories.SpellDefsU.pas` — CRUD for `spell_defs`, `spell_def_titles`.
- `repositories/Repositories.AdventureSpellsU.pas` — CRUD for `adventure_spells`.
- `repositories/Repositories.BookStartingItemsU.pas` — CRUD for `book_starting_items`, `book_starting_item_titles`.
- `services/Services.AdventureCreateU.pas` — transactional adventure builder (adventure row + setup step + gear events + initial stat_changes + spell instances).
- `services/Services.SpellU.pas` — `TSpellService.Cast`, `TSpellService.UndoForStep`.
- `controllers/Controllers.SpellsU.pas` — `POST /adventures/:id/spells/cast`.
- `templates/partials/_spells_panel.html` — rendered on the adventure page.
- `templates/partials/_adventure_create_gear.html` — gear rows on the create form (re-renderable HTMX fragment).
- `templates/partials/_adventure_create_spells.html` — spell picker (re-renderable HTMX fragment).
- `tests/Tests.Repositories.SpellDefsU.pas`
- `tests/Tests.Repositories.AdventureSpellsU.pas`
- `tests/Tests.Repositories.BookStartingItemsU.pas`
- `tests/Tests.Services.SpellU.pas`
- `tests/Tests.Services.AdventureCreateU.pas`
- `tests/Tests.E2E.SpellsAndGearU.pas`

**Modified files:**
- `repositories/Repositories.MigrationU.pas` — schema additions.
- `models/Models.StepU.pas` — add `Kind` field, change `ToSection` to allow zero-as-NULL convention.
- `repositories/Repositories.StepsU.pas` — read/write `kind`, accept nullable `to_section`, new `InsertSetup` method.
- `services/Services.YamlReaderU.pas` — new top-level fields `starting_inventory`, `spells`.
- `services/Services.BookCatalogU.pas` — upsert starting items + spells.
- `services/Services.AdventureStateU.pas` — new method `GetSpellSnapshot(adventureId)`.
- `services/Services.GraphBuilderU.pas` — filter `kind='normal'` (skip setup step).
- `controllers/Controllers.AdventuresU.pas` — refactor `PostCreate` to delegate to `TAdventureCreateService`; add HTMX endpoint that re-renders the book-specific form sections after the book picker changes.
- `controllers/Controllers.StepsU.pas` — call `TSpellService.UndoForStep` from the existing undo handler.
- `templates/pages/adventures/new.html` — append gear/spell sections (conditional on book seed).
- `templates/pages/adventures/play.html` — include spell panel partial.
- `templates/partials/_timeline.html` — render setup chip and spell sub-chips.
- `data/books_seed.yaml` — add `starting_inventory` and `spells` to Citadel.
- `l10n/de.json`, `l10n/en.json` — new strings.
- `tests/Tests.Services.YamlReaderU.pas` — fixtures for new fields.
- `tests/Tests.Services.BookCatalogU.pas` — assertions for new tables.
- `tests/Tests.MigrationU.pas` — new tables exist; `steps.kind` column exists; `steps.to_section` is nullable.

---

## Task 1: Schema migration — new tables and `steps` extensions

**Files:**
- Modify: `repositories/Repositories.MigrationU.pas` (lines 86–175)
- Modify: `tests/Tests.MigrationU.pas`

- [ ] **Step 1: Write failing migration test**

Append a new test method to `Tests.MigrationU.pas` inside the existing `[TestFixture] TMigrationTests`:

```pascal
[Test]
procedure NewSpellAndGearTables_AreCreated;

procedure TMigrationTests.NewSpellAndGearTables_AreCreated;
var
  LConn: string;
  LExpected: TArray<string>;
  LName: string;
  LDb: TFDConnection;
begin
  LExpected := ['spell_defs', 'spell_def_titles', 'adventure_spells',
                'book_starting_items', 'book_starting_item_titles'];
  LConn := TDbHelper.NewMemoryDb;
  try
    LDb := TFDConnection.Create(nil);
    try
      LDb.ConnectionDefName := LConn;
      LDb.Open;
      for LName in LExpected do
        Assert.AreEqual<Int64>(1,
          LDb.ExecSQLScalar(
            'SELECT COUNT(*) FROM sqlite_master ' +
            'WHERE type=''table'' AND name=:n', [LName]),
          'Missing table: ' + LName);
    finally
      LDb.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

[Test]
procedure StepsTable_HasKindColumnAndNullableToSection;

procedure TMigrationTests.StepsTable_HasKindColumnAndNullableToSection;
var
  LConn: string;
  LDb: TFDConnection;
  LQ: TFDQuery;
  LFoundKind: Boolean;
  LToSectionNotNull: Integer;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LDb := TFDConnection.Create(nil);
    LQ := TFDQuery.Create(nil);
    try
      LDb.ConnectionDefName := LConn;
      LDb.Open;
      LQ.Connection := LDb;
      LFoundKind := False;
      LToSectionNotNull := -1;
      LQ.Open('PRAGMA table_info(steps)');
      while not LQ.Eof do
      begin
        if SameText(LQ.FieldByName('name').AsString, 'kind') then
          LFoundKind := True;
        if SameText(LQ.FieldByName('name').AsString, 'to_section') then
          LToSectionNotNull := LQ.FieldByName('notnull').AsInteger;
        LQ.Next;
      end;
      Assert.IsTrue(LFoundKind, 'steps.kind column missing');
      Assert.AreEqual(0, LToSectionNotNull,
        'steps.to_section must be nullable');
    finally
      LQ.Free;
      LDb.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;
```

Update `uses` at the top of the test unit to include `FireDAC.Comp.Client`.

- [ ] **Step 2: Run the tests, confirm both fail**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TMigrationTests
```
Expected: the two new tests FAIL — missing tables / missing column / notnull=1.

- [ ] **Step 3: Extend `SQL_SCHEMA` in `Repositories.MigrationU.pas`**

In `Repositories.MigrationU.pas`, change the array bound from `array[0..9]` to `array[0..14]`. Replace the existing `steps` entry (index 7) with a version that adds the `kind` column and removes the NOT NULL from `to_section`. Append five new table definitions. Final array literal:

```pascal
SQL_SCHEMA: array[0..14] of string = (
  // ... users, sessions, books, book_titles, stat_defs, stat_def_titles, adventures unchanged ...

  // index 7 — steps (modified)
  'CREATE TABLE IF NOT EXISTS steps (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
    'seq INTEGER NOT NULL, ' +
    'from_section INTEGER, ' +
    'to_section INTEGER, ' +
    'kind TEXT NOT NULL DEFAULT ''normal'' CHECK(kind IN (''normal'',''setup'')), ' +
    'note TEXT, ' +
    'flag_fight INTEGER NOT NULL DEFAULT 0, ' +
    'flag_item INTEGER NOT NULL DEFAULT 0, ' +
    'flag_stat INTEGER NOT NULL DEFAULT 0, ' +
    'undone INTEGER NOT NULL DEFAULT 0, ' +
    'created_at TEXT NOT NULL, ' +
    'UNIQUE(adventure_id, seq))',

  // ... stat_changes, inventory_events unchanged ...

  // index 10 — spell_defs
  'CREATE TABLE IF NOT EXISTS spell_defs (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
    'slug TEXT NOT NULL, ' +
    'ord INTEGER NOT NULL, ' +
    'UNIQUE(book_id, slug))',

  // index 11 — spell_def_titles
  'CREATE TABLE IF NOT EXISTS spell_def_titles (' +
    'spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id) ON DELETE CASCADE, ' +
    'lang TEXT NOT NULL, ' +
    'display_name TEXT NOT NULL, ' +
    'description TEXT NOT NULL DEFAULT '''', ' +
    'PRIMARY KEY (spell_def_id, lang))',

  // index 12 — adventure_spells
  'CREATE TABLE IF NOT EXISTS adventure_spells (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
    'spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id), ' +
    'ord INTEGER NOT NULL, ' +
    'consumed_at TEXT, ' +
    'consumed_step_id INTEGER REFERENCES steps(id))',

  // index 13 — book_starting_items
  'CREATE TABLE IF NOT EXISTS book_starting_items (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
    'slug TEXT NOT NULL, ' +
    'ord INTEGER NOT NULL, ' +
    'quantity INTEGER NOT NULL DEFAULT 1, ' +
    'UNIQUE(book_id, slug))',

  // index 14 — book_starting_item_titles
  'CREATE TABLE IF NOT EXISTS book_starting_item_titles (' +
    'starting_item_id INTEGER NOT NULL REFERENCES book_starting_items(id) ON DELETE CASCADE, ' +
    'lang TEXT NOT NULL, ' +
    'display_name TEXT NOT NULL, ' +
    'PRIMARY KEY (starting_item_id, lang))'
);
```

Extend `SQL_INDICES` from `array[0..6]` to `array[0..10]` by appending:

```pascal
'CREATE INDEX IF NOT EXISTS idx_adventure_spells_avail ON adventure_spells(adventure_id, consumed_at)',
'CREATE INDEX IF NOT EXISTS idx_adventure_spells_step  ON adventure_spells(consumed_step_id)',
'CREATE INDEX IF NOT EXISTS idx_book_starting_items    ON book_starting_items(book_id, ord)',
'CREATE INDEX IF NOT EXISTS idx_book_starting_item_titles ON book_starting_item_titles(starting_item_id, lang)'
```

- [ ] **Step 4: Re-run the migration tests, confirm both pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TMigrationTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add repositories/Repositories.MigrationU.pas tests/Tests.MigrationU.pas
git commit -m "feat: extend schema with spell, gear, and setup-step support"
```

---

## Task 2: Model records for spells, starting items, and steps

**Files:**
- Create: `models/Models.SpellDefU.pas`
- Create: `models/Models.AdventureSpellU.pas`
- Create: `models/Models.StartingItemU.pas`
- Modify: `models/Models.StepU.pas`

- [ ] **Step 1: Add `Kind` to `TStep`**

In `models/Models.StepU.pas`, add a field to the `TStep` record (after `Undone`):

```pascal
/// <summary>'normal' for player-recorded steps, 'setup' for the synthetic
/// adventure-start step that carries starting inventory.</summary>
Kind: string;
```

- [ ] **Step 2: Create `Models.SpellDefU.pas`**

Use the existing model unit headers (`Models.StatDefU.pas`) as a template for the comment block and copyright. Content:

```pascal
unit Models.SpellDefU;

interface

type
  TSpellDef = record
    Id: Int64;
    BookId: Int64;
    Slug: string;
    Ord: Integer;
  end;

  TSpellDefTitle = record
    SpellDefId: Int64;
    Lang: string;
    DisplayName: string;
    Description: string;
  end;

implementation

end.
```

- [ ] **Step 3: Create `Models.AdventureSpellU.pas`**

```pascal
unit Models.AdventureSpellU;

interface

type
  TAdventureSpell = record
    Id: Int64;
    AdventureId: Int64;
    SpellDefId: Int64;
    Ord: Integer;
    Consumed: Boolean;
    ConsumedAt: TDateTime;       // 0 when not consumed
    ConsumedStepId: Int64;       // 0 when not consumed
  end;

  /// <summary>Aggregated view used by the Spells panel:
  /// one entry per spell definition with the available/consumed counts.</summary>
  TAdventureSpellGroup = record
    SpellDefId: Int64;
    Slug: string;
    DisplayName: string;
    Description: string;
    Available: Integer;
    Consumed: Integer;
  end;

implementation

end.
```

- [ ] **Step 4: Create `Models.StartingItemU.pas`**

```pascal
unit Models.StartingItemU;

interface

type
  TStartingItem = record
    Id: Int64;
    BookId: Int64;
    Slug: string;
    Ord: Integer;
    Quantity: Integer;
  end;

  TStartingItemTitle = record
    StartingItemId: Int64;
    Lang: string;
    DisplayName: string;
  end;

  /// <summary>Pre-localized view used by the create form.</summary>
  TStartingItemRow = record
    Slug: string;
    DisplayName: string;
    Quantity: Integer;
  end;

implementation

end.
```

- [ ] **Step 5: Add the three new model units to `FFCompanion.dproj`**

Open `FFCompanion.dproj` in the IDE OR run the existing project-config helper. The three new units must appear in the `<DCCReference>` list. Tests dproj (`tests/FFCompanionTests.dproj`) must also reference them. If editing the dproj XML directly is preferred, add three `<DCCReference Include="models\Models.SpellDefU.pas"/>`-style lines for each project.

- [ ] **Step 6: Verify the binaries still compile**

Use the `delphi-build` MCP server:
- `mcp__delphi-build__compile_delphi_project` against `FFCompanion.dproj` (Win64 Debug — fastest sanity check).
- `mcp__delphi-build__compile_delphi_project` against `tests/FFCompanionTests.dproj` (Win64 Debug).

Expected: both compile without errors.

- [ ] **Step 7: Commit**

```bash
git add models/ FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add spell, adventure-spell, starting-item, and setup-step models"
```

---

## Task 3: `TSpellDefsRepo` — CRUD for spell catalog

**Files:**
- Create: `repositories/Repositories.SpellDefsU.pas`
- Create: `tests/Tests.Repositories.SpellDefsU.pas`

- [ ] **Step 1: Write the failing test**

```pascal
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
      Assert.AreEqual(1, Length(LList));
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
      Assert.AreEqual(3, Length(LList));
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
```

- [ ] **Step 2: Run, confirm failure**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TSpellDefsRepoTests
```
Expected: FAIL — unit `Repositories.SpellDefsU` does not exist.

- [ ] **Step 3: Implement `Repositories.SpellDefsU.pas`**

Use `Repositories.InventoryEventsU.pas` as the structural template (header block, `NewConn` helper, short-lived connections, `[:name]` binds). Public surface:

```pascal
unit Repositories.SpellDefsU;

interface

uses Models.SpellDefU;

type
  TSpellDefsRepo = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    function UpsertSpellDef(ABookId: Int64; const ASlug: string;
      AOrd: Integer): Int64;
    procedure SetTitles(ASpellDefId: Int64;
      const ATitles: TArray<TSpellDefTitle>);
    function ListByBook(ABookId: Int64): TArray<TSpellDef>;
    function ListTitles(ASpellDefId: Int64): TArray<TSpellDefTitle>;
  end;
```

Implementation rules:
- `UpsertSpellDef`: `SELECT id FROM spell_defs WHERE book_id=:b AND slug=:s`; if found, `UPDATE … SET ord=:o`; else `INSERT` and return `last_insert_rowid()`. Same pattern as `TBooksRepo.UpsertSeedBook` (review that file for the exact pattern).
- `SetTitles`: open a transaction; `DELETE FROM spell_def_titles WHERE spell_def_id=:s`; loop-insert. Commit.
- `ListByBook`: `SELECT id, book_id, slug, ord FROM spell_defs WHERE book_id=:b ORDER BY ord ASC, id ASC`.
- `ListTitles`: `SELECT spell_def_id, lang, display_name, description FROM spell_def_titles WHERE spell_def_id=:s ORDER BY lang ASC`.

- [ ] **Step 4: Add `Repositories.SpellDefsU.pas` to both dproj files**

Same procedure as Task 2 Step 5.

- [ ] **Step 5: Compile and run, confirm tests pass**

```
mcp__delphi-build__compile_delphi_project  # tests/FFCompanionTests.dproj
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TSpellDefsRepoTests
```
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add repositories/Repositories.SpellDefsU.pas tests/Tests.Repositories.SpellDefsU.pas FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add spell_defs repository with upsert/title-replace semantics"
```

---

## Task 4: `TAdventureSpellsRepo` — instance lifecycle

**Files:**
- Create: `repositories/Repositories.AdventureSpellsU.pas`
- Create: `tests/Tests.Repositories.AdventureSpellsU.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Tests.Repositories.AdventureSpellsU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TAdventureSpellsRepoTests = class
  public
    [Test] procedure Insert_AssignsAscendingOrd;
    [Test] procedure ListGroups_ReturnsAvailableAndConsumedCounts;
    [Test] procedure ConsumeOldest_SelectsLowestOrdInstance;
    [Test] procedure ConsumeOldest_ReturnsZeroWhenNoneAvailable;
    [Test] procedure RevertForStep_ReopensAllConsumedAtThatStep;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  TestHelpers.DbU,
  Repositories.BooksU, Repositories.UsersU, Repositories.AdventuresU,
  Repositories.StepsU, Repositories.SpellDefsU,
  Repositories.AdventureSpellsU,
  Models.AdventureSpellU;

// Helper: bootstrap a book, spell, user, adventure, and one normal step.
// Returns adventure_id, spell_def_id, step_id via out params.
procedure Seed(const AConn: string; out AAdvId, ASpellId, AStepId: Int64);
var
  LBooks: TBooksRepo;
  LUsers: TUsersRepo;
  LAdv: TAdventuresRepo;
  LSteps: TStepsRepo;
  LSpells: TSpellDefsRepo;
  LBookId: Int64; LUserId: Int64;
begin
  LBooks := TBooksRepo.Create(AConn);
  LUsers := TUsersRepo.Create(AConn);
  LAdv := TAdventuresRepo.Create(AConn);
  LSteps := TStepsRepo.Create(AConn);
  LSpells := TSpellDefsRepo.Create(AConn);
  try
    LBookId := LBooks.UpsertSeedBook('citadel', 'SJ');
    LUserId := LUsers.Create('alice', 'hash');
    AAdvId := LAdv.Create(LUserId, LBookId, 'Run 1');
    ASpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
    AStepId := LSteps.Insert(AAdvId, 0, 1, '', False, False, False);
  finally
    LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
  end;
end;

procedure TAdventureSpellsRepoTests.Insert_AssignsAscendingOrd;
var
  LConn: string; LAdv, LSpell, LStep, LId1, LId2: Int64;
  LRepo: TAdventureSpellsRepo;
  LList: TArray<TAdventureSpell>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    Seed(LConn, LAdv, LSpell, LStep);
    LRepo := TAdventureSpellsRepo.Create(LConn);
    try
      LId1 := LRepo.Insert(LAdv, LSpell, 0);
      LId2 := LRepo.Insert(LAdv, LSpell, 1);
      LList := LRepo.ListByAdventure(LAdv);
      Assert.AreEqual(2, Length(LList));
      Assert.AreEqual(0, LList[0].Ord);
      Assert.AreEqual(1, LList[1].Ord);
    finally
      LRepo.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureSpellsRepoTests.ListGroups_ReturnsAvailableAndConsumedCounts;
var
  LConn: string; LAdv, LSpell, LStep: Int64;
  LRepo: TAdventureSpellsRepo;
  LGroups: TArray<TAdventureSpellGroup>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    Seed(LConn, LAdv, LSpell, LStep);
    LRepo := TAdventureSpellsRepo.Create(LConn);
    try
      LRepo.Insert(LAdv, LSpell, 0);
      LRepo.Insert(LAdv, LSpell, 1);
      LRepo.Insert(LAdv, LSpell, 2);
      LRepo.ConsumeOldest(LAdv, LSpell, LStep);
      LGroups := LRepo.ListGroups(LAdv);
      Assert.AreEqual(1, Length(LGroups));
      Assert.AreEqual(LSpell, LGroups[0].SpellDefId);
      Assert.AreEqual(2, LGroups[0].Available);
      Assert.AreEqual(1, LGroups[0].Consumed);
    finally
      LRepo.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureSpellsRepoTests.ConsumeOldest_SelectsLowestOrdInstance;
var
  LConn: string; LAdv, LSpell, LStep, LConsumedId: Int64;
  LRepo: TAdventureSpellsRepo;
  LList: TArray<TAdventureSpell>;
  LSpellInstance: TAdventureSpell;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    Seed(LConn, LAdv, LSpell, LStep);
    LRepo := TAdventureSpellsRepo.Create(LConn);
    try
      LRepo.Insert(LAdv, LSpell, 5);
      LRepo.Insert(LAdv, LSpell, 1);  // smallest ord
      LRepo.Insert(LAdv, LSpell, 3);
      LConsumedId := LRepo.ConsumeOldest(LAdv, LSpell, LStep);
      Assert.IsTrue(LConsumedId > 0);
      LList := LRepo.ListByAdventure(LAdv);
      for LSpellInstance in LList do
        if LSpellInstance.Id = LConsumedId then
        begin
          Assert.IsTrue(LSpellInstance.Consumed, 'wrong instance consumed');
          Assert.AreEqual(1, LSpellInstance.Ord, 'must consume ord=1 first');
          Exit;
        end;
      Assert.Fail('consumed id not in list');
    finally
      LRepo.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureSpellsRepoTests.ConsumeOldest_ReturnsZeroWhenNoneAvailable;
var
  LConn: string; LAdv, LSpell, LStep: Int64;
  LRepo: TAdventureSpellsRepo;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    Seed(LConn, LAdv, LSpell, LStep);
    LRepo := TAdventureSpellsRepo.Create(LConn);
    try
      Assert.AreEqual<Int64>(0, LRepo.ConsumeOldest(LAdv, LSpell, LStep));
    finally
      LRepo.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureSpellsRepoTests.RevertForStep_ReopensAllConsumedAtThatStep;
var
  LConn: string; LAdv, LSpell, LStep: Int64;
  LRepo: TAdventureSpellsRepo;
  LGroups: TArray<TAdventureSpellGroup>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    Seed(LConn, LAdv, LSpell, LStep);
    LRepo := TAdventureSpellsRepo.Create(LConn);
    try
      LRepo.Insert(LAdv, LSpell, 0);
      LRepo.Insert(LAdv, LSpell, 1);
      LRepo.ConsumeOldest(LAdv, LSpell, LStep);
      LRepo.ConsumeOldest(LAdv, LSpell, LStep);
      LRepo.RevertForStep(LStep);
      LGroups := LRepo.ListGroups(LAdv);
      Assert.AreEqual(2, LGroups[0].Available);
      Assert.AreEqual(0, LGroups[0].Consumed);
    finally
      LRepo.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventureSpellsRepoTests);

end.
```

- [ ] **Step 2: Run, confirm failure**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TAdventureSpellsRepoTests
```
Expected: FAIL — unit missing.

- [ ] **Step 3: Implement `Repositories.AdventureSpellsU.pas`**

Public surface:

```pascal
unit Repositories.AdventureSpellsU;

interface

uses Models.AdventureSpellU;

type
  TAdventureSpellsRepo = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    function Insert(AAdventureId, ASpellDefId: Int64; AOrd: Integer): Int64;
    /// <summary>Atomically picks the oldest unconsumed instance of the given
    /// spell for this adventure, marks it consumed at the given step, and
    /// returns its id. Returns 0 when no available instance exists.</summary>
    function ConsumeOldest(AAdventureId, ASpellDefId,
      AStepId: Int64): Int64;
    /// <summary>Re-availabilizes every instance previously consumed at the
    /// given step. Used by soft-undo.</summary>
    procedure RevertForStep(AStepId: Int64);
    function ListByAdventure(AAdventureId: Int64): TArray<TAdventureSpell>;
    /// <summary>Aggregated counts per spell_def, joined with the user's
    /// language-resolved title. The repo returns a generic shape (no titles);
    /// see TAdventureStateService.GetSpellSnapshot for the titled view.</summary>
    function ListGroups(AAdventureId: Int64): TArray<TAdventureSpellGroup>;
  end;
```

Key SQL:

- `Insert`:
  `INSERT INTO adventure_spells (adventure_id, spell_def_id, ord) VALUES (:a,:s,:o)` then `SELECT last_insert_rowid()`.
- `ConsumeOldest` (inside a single short-lived connection + transaction):
  - `SELECT id FROM adventure_spells WHERE adventure_id=:a AND spell_def_id=:s AND consumed_at IS NULL ORDER BY ord ASC, id ASC LIMIT 1`
  - if no row, return 0.
  - else `UPDATE adventure_spells SET consumed_at=:t, consumed_step_id=:k WHERE id=:i` with `t = FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now)`.
- `RevertForStep`:
  `UPDATE adventure_spells SET consumed_at=NULL, consumed_step_id=NULL WHERE consumed_step_id=:k`.
- `ListByAdventure`:
  `SELECT id, adventure_id, spell_def_id, ord, consumed_at, consumed_step_id FROM adventure_spells WHERE adventure_id=:a ORDER BY spell_def_id, ord, id`. Map `Consumed := not FieldByName('consumed_at').IsNull`.
- `ListGroups`:
  ```sql
  SELECT spell_def_id,
    SUM(CASE WHEN consumed_at IS NULL THEN 1 ELSE 0 END) AS avail,
    SUM(CASE WHEN consumed_at IS NULL THEN 0 ELSE 1 END) AS cons
  FROM adventure_spells
  WHERE adventure_id=:a
  GROUP BY spell_def_id
  ORDER BY spell_def_id
  ```
  Map into `TAdventureSpellGroup` leaving Slug/DisplayName/Description blank — those get filled by the service layer in Task 10.

- [ ] **Step 4: Add unit to both dproj files**

- [ ] **Step 5: Compile, run tests, confirm 5 tests pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TAdventureSpellsRepoTests
```

- [ ] **Step 6: Commit**

```bash
git add repositories/Repositories.AdventureSpellsU.pas tests/Tests.Repositories.AdventureSpellsU.pas FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add adventure_spells repository with ConsumeOldest and RevertForStep"
```

---

## Task 5: `TBookStartingItemsRepo` — gear catalog

**Files:**
- Create: `repositories/Repositories.BookStartingItemsU.pas`
- Create: `tests/Tests.Repositories.BookStartingItemsU.pas`

- [ ] **Step 1: Write the failing test**

```pascal
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
      Assert.AreEqual(1, Length(LRows));
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
      Assert.AreEqual(1, Length(LRows));
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
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement `Repositories.BookStartingItemsU.pas`**

Public surface:

```pascal
unit Repositories.BookStartingItemsU;

interface

uses Models.StartingItemU;

type
  TBookStartingItemsRepo = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    function Upsert(ABookId: Int64; const ASlug: string;
      AOrd, AQuantity: Integer): Int64;
    procedure SetTitles(AStartingItemId: Int64;
      const ATitles: TArray<TStartingItemTitle>);
    /// <summary>Returns one row per starting item with the title chosen for
    /// ALang. Falls back to any other lang for that item when ALang has no
    /// entry, so seed-time partial translations still render something.</summary>
    function ListByBookLocalized(ABookId: Int64;
      const ALang: string): TArray<TStartingItemRow>;
  end;
```

Key SQL for `ListByBookLocalized`:

```sql
SELECT bsi.slug,
       COALESCE(t1.display_name, t2.display_name) AS name,
       bsi.quantity
FROM book_starting_items bsi
LEFT JOIN book_starting_item_titles t1
  ON t1.starting_item_id = bsi.id AND t1.lang = :lang
LEFT JOIN book_starting_item_titles t2
  ON t2.starting_item_id = bsi.id AND t2.starting_item_id = (
       SELECT MIN(starting_item_id) FROM book_starting_item_titles
       WHERE starting_item_id = bsi.id)
WHERE bsi.book_id = :b
ORDER BY bsi.ord ASC
```

(The fallback subselect picks any one available title for the item.)

- [ ] **Step 4: Add unit to both dproj files, compile, run tests**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TBookStartingItemsRepoTests
```
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add repositories/Repositories.BookStartingItemsU.pas tests/Tests.Repositories.BookStartingItemsU.pas FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add book_starting_items repository with localized listing"
```

---

## Task 6: Extend YAML parser for `starting_inventory` and `spells`

**Files:**
- Modify: `services/Services.YamlReaderU.pas`
- Modify: `tests/Tests.Services.YamlReaderU.pas`

- [ ] **Step 1: Add types for the new data**

In the `interface` section of `Services.YamlReaderU.pas`, add (before `TYamlBook`):

```pascal
TYamlStartingItem = record
  Slug: string;
  Quantity: Integer;       // 0 means "absent"; caller treats as default 1
  Titles: TDictionary<string, string>;
end;

TYamlSpell = record
  Slug: string;
  Names: TDictionary<string, string>;
  Descriptions: TDictionary<string, string>;
end;
```

Extend `TYamlBook`:

```pascal
TYamlBook = record
  Slug, Author: string;
  Titles: TDictionary<string, string>;
  Stats: TArray<TYamlStat>;
  StartingInventory: TArray<TYamlStartingItem>;
  Spells: TArray<TYamlSpell>;
end;
```

Update the doc comment to note the new fields and that the new dictionaries are also caller-owned.

- [ ] **Step 2: Write the failing parser test**

In `tests/Tests.Services.YamlReaderU.pas`, append:

```pascal
[Test]
procedure ParsesStartingInventoryAndSpells;

procedure TYamlReaderTests.ParsesStartingInventoryAndSpells;
const
  CYaml =
    '- slug: citadel'#10 +
    '  author: SJ'#10 +
    '  titles:'#10 +
    '    en: Citadel'#10 +
    '  stats:'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic } }'#10 +
    '  starting_inventory:'#10 +
    '    - { slug: sword, quantity: 1, titles: { de: Schwert, en: Sword } }'#10 +
    '    - { slug: torch, titles: { de: Fackel, en: Torch } }'#10 +
    '  spells:'#10 +
    '    - { slug: strength, names: { de: Stärke, en: Strength }, descriptions: { de: "Erhöht Skill.", en: "Raises Skill." } }'#10 +
    '    - { slug: weakness, names: { de: Schwäche, en: Weakness }, descriptions: { de: "Senkt Skill.", en: "Lowers Skill." } }'#10;
var
  LBooks: TArray<TYamlBook>;
  LBook: TYamlBook;
  LItem: TYamlStartingItem;
  LSpell: TYamlSpell;
begin
  LBooks := TYamlReader.ParseSeedString(CYaml);
  try
    Assert.AreEqual(1, Length(LBooks));
    Assert.AreEqual(2, Length(LBooks[0].StartingInventory));
    Assert.AreEqual('sword', LBooks[0].StartingInventory[0].Slug);
    Assert.AreEqual(1, LBooks[0].StartingInventory[0].Quantity);
    Assert.AreEqual('Schwert', LBooks[0].StartingInventory[0].Titles['de']);
    Assert.AreEqual(0, LBooks[0].StartingInventory[1].Quantity,
      'absent quantity stays 0; caller defaults to 1');

    Assert.AreEqual(2, Length(LBooks[0].Spells));
    Assert.AreEqual('strength', LBooks[0].Spells[0].Slug);
    Assert.AreEqual('Stärke', LBooks[0].Spells[0].Names['de']);
    Assert.AreEqual('Senkt Skill.', LBooks[0].Spells[1].Descriptions['de']);
  finally
    for LBook in LBooks do
    begin
      LBook.Titles.Free;
      for LItem in LBook.StartingInventory do LItem.Titles.Free;
      for LSpell in LBook.Spells do
      begin
        LSpell.Names.Free; LSpell.Descriptions.Free;
      end;
    end;
  end;
end;
```

Audit the existing `TYamlReaderTests` cleanup code — any test that already iterates `LBooks` to free Titles/Stats now needs to also free the two new dictionary kinds when present. Add a small helper in the test unit:

```pascal
procedure FreeBookOwned(const ABooks: TArray<TYamlBook>);
var
  LBook: TYamlBook; LStat: TYamlStat; LItem: TYamlStartingItem;
  LSpell: TYamlSpell;
begin
  for LBook in ABooks do
  begin
    LBook.Titles.Free;
    for LStat in LBook.Stats do LStat.Titles.Free;
    for LItem in LBook.StartingInventory do LItem.Titles.Free;
    for LSpell in LBook.Spells do
    begin
      LSpell.Names.Free; LSpell.Descriptions.Free;
    end;
  end;
end;
```

Replace existing per-test free loops with `FreeBookOwned(LBooks)`.

- [ ] **Step 3: Run, confirm failure**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TYamlReaderTests
```
Expected: existing tests still pass (they never used these fields); the new test fails — fields not parsed.

- [ ] **Step 4: Implement parser extensions**

In `Services.YamlReaderU.pas`:

1. Inside `ParseBook` (around line 320, where `stats` is parsed), add two new branches:

```pascal
else if LKey = 'starting_inventory' then
begin
  if LValue <> '' then RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
  LInvList := TList<TYamlStartingItem>.Create;
  try
    while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
    begin
      if not StartsText('- ', ALines[AIdx].Content) then
        RaiseAt(ALines[AIdx].LineNo, RS_ERR_STARTING_ITEM_ITEM);
      LInvList.Add(ParseStartingItemInline(
        ALines[AIdx].Content, ALines[AIdx].LineNo));
      Inc(AIdx);
    end;
    Result.StartingInventory := LInvList.ToArray;
  finally
    LInvList.Free;
  end;
end
else if LKey = 'spells' then
begin
  if LValue <> '' then RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
  LSpellList := TList<TYamlSpell>.Create;
  try
    while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
    begin
      if not StartsText('- ', ALines[AIdx].Content) then
        RaiseAt(ALines[AIdx].LineNo, RS_ERR_SPELL_ITEM);
      LSpellList.Add(ParseSpellInline(
        ALines[AIdx].Content, ALines[AIdx].LineNo));
      Inc(AIdx);
    end;
    Result.Spells := LSpellList.ToArray;
  finally
    LSpellList.Free;
  end;
end
```

Declare `LInvList: TList<TYamlStartingItem>;` and `LSpellList: TList<TYamlSpell>;` at the top of `ParseBook`.

2. Add the two new resourcestrings to the existing block:

```pascal
RS_ERR_STARTING_ITEM_ITEM = 'expected starting_inventory list item starting with "- { ... }"';
RS_ERR_SPELL_ITEM         = 'expected spells list item starting with "- { ... }"';
RS_ERR_UNKNOWN_INV_FIELD  = 'unknown field "%s" in starting_inventory mapping';
RS_ERR_UNKNOWN_SPELL_FIELD = 'unknown field "%s" in spells mapping';
```

3. Add the two new inline parsers (model them on `ParseStatInline` at line 241):

```pascal
function ParseStartingItemInline(const ALine: string;
  ALineNo: Integer): TYamlStartingItem;
var
  LBody, LP, LK, LV, LInner: string;
begin
  LBody := Trim(Copy(ALine, 3, MaxInt));
  if (LBody = '') or (LBody[1] <> '{') or (LBody[Length(LBody)] <> '}') then
    RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
  LBody := Trim(Copy(LBody, 2, Length(LBody) - 2));
  Result.Slug := '';
  Result.Quantity := 0;
  Result.Titles := TDictionary<string, string>.Create;
  try
    for LP in SplitTopLevelCommas(LBody, ALineNo) do
    begin
      if LP = '' then Continue;
      SplitKV(LP, ALineNo, LK, LV);
      if LK = 'slug' then Result.Slug := LV
      else if LK = 'quantity' then Result.Quantity := StrToIntDef(LV, 0)
      else if LK = 'titles' then
      begin
        if (LV = '') or (LV[1] <> '{') or (LV[Length(LV)] <> '}') then
          RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
        LInner := Trim(Copy(LV, 2, Length(LV) - 2));
        ParseFlatInlineInto(LInner, ALineNo, Result.Titles);
      end
      else
        RaiseAt(ALineNo, Format(RS_ERR_UNKNOWN_INV_FIELD, [LK]));
    end;
  except
    Result.Titles.Free; raise;
  end;
end;

function ParseSpellInline(const ALine: string;
  ALineNo: Integer): TYamlSpell;
var
  LBody, LP, LK, LV, LInner: string;
begin
  LBody := Trim(Copy(ALine, 3, MaxInt));
  if (LBody = '') or (LBody[1] <> '{') or (LBody[Length(LBody)] <> '}') then
    RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
  LBody := Trim(Copy(LBody, 2, Length(LBody) - 2));
  Result.Slug := '';
  Result.Names := TDictionary<string, string>.Create;
  Result.Descriptions := TDictionary<string, string>.Create;
  try
    for LP in SplitTopLevelCommas(LBody, ALineNo) do
    begin
      if LP = '' then Continue;
      SplitKV(LP, ALineNo, LK, LV);
      if LK = 'slug' then Result.Slug := LV
      else if (LK = 'names') or (LK = 'descriptions') then
      begin
        if (LV = '') or (LV[1] <> '{') or (LV[Length(LV)] <> '}') then
          RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
        LInner := Trim(Copy(LV, 2, Length(LV) - 2));
        if LK = 'names' then
          ParseFlatInlineInto(LInner, ALineNo, Result.Names)
        else
          ParseFlatInlineInto(LInner, ALineNo, Result.Descriptions);
      end
      else
        RaiseAt(ALineNo, Format(RS_ERR_UNKNOWN_SPELL_FIELD, [LK]));
    end;
  except
    Result.Names.Free; Result.Descriptions.Free; raise;
  end;
end;
```

4. Initialize `Result.StartingInventory := nil; Result.Spells := nil;` at the top of `ParseBook`.

- [ ] **Step 5: Run, confirm test passes**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TYamlReaderTests
```

- [ ] **Step 6: Commit**

```bash
git add services/Services.YamlReaderU.pas tests/Tests.Services.YamlReaderU.pas
git commit -m "feat: parse starting_inventory and spells blocks in seed yaml"
```

---

## Task 7: Extend `TBookCatalogService` + seed Citadel

**Files:**
- Modify: `services/Services.BookCatalogU.pas`
- Modify: `data/books_seed.yaml`
- Modify: `tests/Tests.Services.BookCatalogU.pas`

- [ ] **Step 1: Write the failing test**

Append to `tests/Tests.Services.BookCatalogU.pas`:

```pascal
[Test]
procedure LoadSeed_PopulatesSpellsAndStartingItems;

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
      Assert.AreEqual(1, Length(LSpellList));
      Assert.AreEqual('strength', LSpellList[0].Slug);
      LSpellTitles := LSpells.ListTitles(LSpellList[0].Id);
      Assert.AreEqual(2, Length(LSpellTitles));
      LItemRows := LItems.ListByBookLocalized(LBookId, 'de');
      Assert.AreEqual(1, Length(LItemRows));
      Assert.AreEqual('Schwert', LItemRows[0].DisplayName);
    finally
      LItems.Free; LSpells.Free; LBooks.Free;
    end;
  finally
    if TFile.Exists(LPath) then TFile.Delete(LPath);
    TDbHelper.Drop(LConn);
  end;
end;
```

This test calls `TBooksRepo.FindIdBySlug`. Check whether this method exists (`grep -n "FindIdBySlug\|GetIdBySlug" repositories/Repositories.BooksU.pas`). If only `UpsertSeedBook` exists, add a small read-only `FindIdBySlug(const ASlug: string): Int64` (returns 0 when not found) to `TBooksRepo` and re-export it; mirror the existing repo patterns (header doc-comment, short-lived connection, parameterized SELECT). Include this helper change in this task's commit.

Update the test unit's `uses` clause with: `System.IOUtils, Repositories.SpellDefsU, Repositories.BookStartingItemsU, Models.SpellDefU, Models.StartingItemU`.

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Extend `TBookCatalogService.LoadSeed`**

In `services/Services.BookCatalogU.pas`:

1. Add to `uses` (implementation): `Repositories.SpellDefsU, Repositories.BookStartingItemsU, Models.SpellDefU, Models.StartingItemU`.

2. Inside the outer `for LBook in LBooks do` loop, after the stat-def upsert block, add:

```pascal
// Starting inventory
LItemRepo := TBookStartingItemsRepo.Create(FConn);
try
  LOrd := 0;
  for LInv in LBook.StartingInventory do
  begin
    LQty := LInv.Quantity;
    if LQty <= 0 then LQty := 1;
    LItemId := LItemRepo.Upsert(LBookId, LInv.Slug, LOrd, LQty);
    SetLength(LItemTitles, LInv.Titles.Count);
    I := 0;
    for LTitlesPair in LInv.Titles do
    begin
      LItemTitles[I].StartingItemId := LItemId;
      LItemTitles[I].Lang := LTitlesPair.Key;
      LItemTitles[I].DisplayName := LTitlesPair.Value;
      Inc(I);
    end;
    LItemRepo.SetTitles(LItemId, LItemTitles);
    Inc(LOrd);
  end;
finally
  LItemRepo.Free;
end;

// Spells
LSpellRepo := TSpellDefsRepo.Create(FConn);
try
  LOrd := 0;
  for LSp in LBook.Spells do
  begin
    LSpellDefId := LSpellRepo.UpsertSpellDef(LBookId, LSp.Slug, LOrd);
    // Merge names + descriptions into spell_def_titles rows by lang.
    LSpellTitles := nil;
    for LTitlesPair in LSp.Names do
    begin
      SetLength(LSpellTitles, Length(LSpellTitles) + 1);
      with LSpellTitles[High(LSpellTitles)] do
      begin
        SpellDefId := LSpellDefId;
        Lang := LTitlesPair.Key;
        DisplayName := LTitlesPair.Value;
        if LSp.Descriptions.TryGetValue(LTitlesPair.Key, LDescVal) then
          Description := LDescVal
        else
          Description := '';
      end;
    end;
    LSpellRepo.SetTitles(LSpellDefId, LSpellTitles);
    Inc(LOrd);
  end;
finally
  LSpellRepo.Free;
end;
```

Add the new local variables to the var block: `LItemRepo: TBookStartingItemsRepo; LSpellRepo: TSpellDefsRepo; LInv: TYamlStartingItem; LSp: TYamlSpell; LItemId, LSpellDefId: Int64; LItemTitles: TArray<TStartingItemTitle>; LSpellTitles: TArray<TSpellDefTitle>; LQty: Integer; LDescVal: string;`.

3. Extend the final cleanup loop (around line 129):

```pascal
for LBook in LBooks do
begin
  LBook.Titles.Free;
  for LStat in LBook.Stats do LStat.Titles.Free;
  for LInv in LBook.StartingInventory do LInv.Titles.Free;
  for LSp in LBook.Spells do
  begin
    LSp.Names.Free; LSp.Descriptions.Free;
  end;
end;
```

- [ ] **Step 4: Run BookCatalog tests, confirm pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TBookCatalogServiceTests
```

- [ ] **Step 5: Extend `data/books_seed.yaml`**

Replace the `citadel-of-chaos` block (lines 1–10) so it ends with the new fields. The full updated Citadel block:

```yaml
- slug: citadel-of-chaos
  author: Steve Jackson
  titles:
    en: The Citadel of Chaos
    de: Die Zitadelle des Zauberers
  stats:
    - { name: skill,   kind: integer, default: 0, titles: { en: Skill,   de: Gewandtheit } }
    - { name: stamina, kind: integer, default: 0, titles: { en: Stamina, de: Stärke } }
    - { name: luck,    kind: integer, default: 0, titles: { en: Luck,    de: Glück } }
    - { name: magic,   kind: integer, default: 0, titles: { en: Magic,   de: Zauberkraft } }
  starting_inventory:
    - { slug: sword,         titles: { de: Schwert,      en: Sword } }
    - { slug: leather-armor, titles: { de: Lederrüstung, en: Leather Armor } }
    - { slug: torch,         titles: { de: Fackel,       en: Torch } }
  spells:
    - { slug: weakness,     names: { de: Schwäche,     en: Weakness },     descriptions: { de: "Senkt die Gewandtheit eines Gegners.", en: "Lowers a foe's Skill." } }
    - { slug: strength,     names: { de: Stärke,       en: Strength },     descriptions: { de: "Erhöht die eigene Gewandtheit.",       en: "Raises your Skill." } }
    - { slug: luck-spell,   names: { de: Glück,        en: Luck },         descriptions: { de: "Erhöht den Glückswert.",               en: "Raises your Luck." } }
    - { slug: stamina,      names: { de: Lebenskraft,  en: Stamina },      descriptions: { de: "Stellt Stärke wieder her.",            en: "Restores Stamina." } }
    - { slug: shielding,    names: { de: Abschirmung,  en: Shielding },    descriptions: { de: "Wehrt einen Angriff ab.",              en: "Wards off an attack." } }
    - { slug: illusion,     names: { de: Illusion,     en: Illusion },     descriptions: { de: "Erzeugt eine Trugbild.",               en: "Creates an illusion." } }
    - { slug: levitation,   names: { de: Schwerelosigkeit, en: Levitation }, descriptions: { de: "Hebt dich vom Boden.",               en: "Lifts you off the ground." } }
    - { slug: friendship,   names: { de: Freundschaft, en: Friendship },   descriptions: { de: "Macht einen Gegner zum Freund.",      en: "Makes a foe friendly." } }
    - { slug: language,     names: { de: Sprache,      en: Language },     descriptions: { de: "Du verstehst eine fremde Sprache.",   en: "Understand any language." } }
    - { slug: open,         names: { de: Öffnen,       en: Open },         descriptions: { de: "Öffnet ein Schloss.",                 en: "Opens a lock." } }
    - { slug: weakness-undo, names: { de: Schwäche aufheben, en: Undo Weakness }, descriptions: { de: "Hebt eine Schwäche-Wirkung auf.", en: "Reverses a Weakness spell." } }
    - { slug: e-s-p,        names: { de: Gedankenlesen, en: ESP },         descriptions: { de: "Liest die Gedanken einer Kreatur.",   en: "Reads creature thoughts." } }
    - { slug: fire,         names: { de: Feuer,        en: Fire },         descriptions: { de: "Entfacht eine Flamme.",               en: "Conjures fire." } }
    - { slug: creature-copy, names: { de: Kreatur-Abbild, en: Creature Copy }, descriptions: { de: "Erzeugt ein Abbild einer Kreatur.", en: "Creates a creature double." } }
```

Other books (Warlock, Deathtrap) stay untouched — they have no `starting_inventory` or `spells`, so the seed loader simply does nothing for those features.

- [ ] **Step 6: Boot the server once locally to verify the seed loads**

This can only be done after Linux64 build. Skip until end of Task 19, then circle back. For now, the unit tests cover the seed loader path.

- [ ] **Step 7: Commit**

```bash
git add services/Services.BookCatalogU.pas data/books_seed.yaml tests/Tests.Services.BookCatalogU.pas repositories/Repositories.BooksU.pas
git commit -m "feat: seed starting inventory and spell catalog for Citadel"
```

(Include `Repositories.BooksU.pas` only if `FindIdBySlug` was added there in Step 1.)

---

## Task 8: Extend `TStepsRepo` for setup steps

**Files:**
- Modify: `repositories/Repositories.StepsU.pas`
- Modify: `tests/Tests.Repositories.StepsU.pas`

- [ ] **Step 1: Write the failing test**

Append to `tests/Tests.Repositories.StepsU.pas`:

```pascal
[Test]
procedure InsertSetup_CreatesKindSetupStepWithNullToSection;

procedure TStepsRepoTests.InsertSetup_CreatesKindSetupStepWithNullToSection;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo;
  LAdvId, LStepId: Int64;
  LStep: TStep;
  LDb: TFDConnection; LQ: TFDQuery;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    try
      LAdvId := LAdv.Create(
        LUsers.Create('alice', 'h'),
        LBooks.UpsertSeedBook('citadel', 'SJ'),
        'Run');
      LStepId := LSteps.InsertSetup(LAdvId);
      LStep := LSteps.GetById(LStepId);
      Assert.AreEqual('setup', LStep.Kind);
      Assert.AreEqual(1, LStep.Seq, 'setup is the first step of the adventure');

      // to_section must actually be NULL in the row.
      LDb := TFDConnection.Create(nil); LQ := TFDQuery.Create(nil);
      try
        LDb.ConnectionDefName := LConn; LDb.Open; LQ.Connection := LDb;
        LQ.Open('SELECT to_section FROM steps WHERE id=:i', [LStepId]);
        Assert.IsTrue(LQ.FieldByName('to_section').IsNull,
          'setup step must have NULL to_section');
      finally
        LQ.Free; LDb.Free;
      end;
    finally
      LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;
```

Also append:

```pascal
[Test]
procedure NormalInsert_StillProducesKindNormal;

procedure TStepsRepoTests.NormalInsert_StillProducesKindNormal;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LStepId: Int64; LStep: TStep;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    try
      LStepId := LSteps.Insert(
        LAdv.Create(LUsers.Create('a','h'),
                    LBooks.UpsertSeedBook('citadel','SJ'),
                    'Run'),
        0, 1, '', False, False, False);
      LStep := LSteps.GetById(LStepId);
      Assert.AreEqual('normal', LStep.Kind);
    finally
      LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;
```

- [ ] **Step 2: Run, confirm both fail**

- [ ] **Step 3: Implement the changes**

In `Repositories.StepsU.pas`:

1. Add to the interface section of `TStepsRepo`:

```pascal
/// <summary>Inserts a synthetic kind='setup' step with NULL to_section
/// and seq=1. Used by the adventure-create transaction to host starting
/// inventory and initial stat snapshots.</summary>
function InsertSetup(AAdventureId: Int64): Int64;
```

2. Update `ReadStepRow` to also populate `AStep.Kind`:

```pascal
AStep.Kind := AQ.FieldByName('kind').AsString;
if AStep.Kind = '' then AStep.Kind := 'normal';
```

Also handle nullable `to_section`:

```pascal
if AQ.FieldByName('to_section').IsNull then
  AStep.ToSection := 0
else
  AStep.ToSection := AQ.FieldByName('to_section').AsInteger;
```

3. Update every SELECT to include `kind` in the column list (search for `'SELECT id, adventure_id, seq, from_section, to_section, note,'` and append `kind,`):

```pascal
'SELECT id, adventure_id, seq, from_section, to_section, kind, note, ' +
'flag_fight, flag_item, flag_stat, undone, created_at '
```

Apply to all three queries: `ListByAdventure`, `ListByAdventureAsc`, `GetById`.

4. Implement `InsertSetup`:

```pascal
function TStepsRepo.InsertSetup(AAdventureId: Int64): Int64;
var
  LC: TFDConnection;
  LCreatedAt: string;
begin
  LC := NewConn(FConn);
  try
    LC.StartTransaction;
    try
      LCreatedAt := FormatDateTime(ISO_FMT, Now);
      // setup steps always live at seq=1; the create service is responsible
      // for guaranteeing this is the first step of the adventure.
      LC.ExecSQL(
        'INSERT INTO steps (adventure_id, seq, from_section, to_section, ' +
        'kind, note, flag_fight, flag_item, flag_stat, undone, created_at) ' +
        'VALUES (:a, 1, NULL, NULL, ''setup'', '''', 0, 0, 0, 0, :c)',
        [AAdventureId, LCreatedAt]);
      Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
      LC.Commit;
    except
      LC.Rollback; raise;
    end;
  finally
    LC.Free;
  end;
end;
```

5. Update the normal `Insert` to start `seq` at MAX(seq)+1 as before (no change needed — the COALESCE handles the case where a setup step exists at seq=1 and the next normal step gets seq=2).

- [ ] **Step 4: Run repository tests, confirm all pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TStepsRepoTests
```

- [ ] **Step 5: Commit**

```bash
git add repositories/Repositories.StepsU.pas tests/Tests.Repositories.StepsU.pas
git commit -m "feat: add InsertSetup and read steps.kind in steps repository"
```

---

## Task 9: `TSpellService` — cast and undo

**Files:**
- Create: `services/Services.SpellU.pas`
- Create: `tests/Tests.Services.SpellU.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Tests.Services.SpellU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TSpellServiceTests = class
  public
    [Test] procedure Cast_ConsumesOldestAndReturnsTrue;
    [Test] procedure Cast_RejectsWhenNoInstanceAvailable;
    [Test] procedure Cast_RejectsWhenAdventureHasNoNormalStepYet;
    [Test] procedure UndoForStep_DelegatesToRepo;
  end;

implementation

uses
  System.SysUtils,
  TestHelpers.DbU,
  Repositories.BooksU, Repositories.UsersU, Repositories.AdventuresU,
  Repositories.StepsU, Repositories.SpellDefsU,
  Repositories.AdventureSpellsU,
  Services.SpellU, Models.AdventureSpellU;

procedure TSpellServiceTests.Cast_ConsumesOldestAndReturnsTrue;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo; LAS: TAdventureSpellsRepo;
  LBookId, LUserId, LAdvId, LSpellId, LStepId, LConsumedId: Int64;
  LSvc: TSpellService;
  LErr: string;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel','SJ');
      LUserId := LUsers.Create('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      LAS.Insert(LAdvId, LSpellId, 0);
      LStepId := LSteps.Insert(LAdvId, 0, 47, '', False, False, False);
      LAdv.SetLastStepId(LAdvId, LStepId);

      LSvc := TSpellService.Create(LConn);
      try
        Assert.IsTrue(LSvc.Cast(LAdvId, LSpellId, LConsumedId, LErr));
        Assert.IsTrue(LConsumedId > 0);
        Assert.AreEqual('', LErr);
      finally
        LSvc.Free;
      end;
    finally
      LAS.Free; LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellServiceTests.Cast_RejectsWhenNoInstanceAvailable;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo;
  LBookId, LUserId, LAdvId, LSpellId, LStepId, LConsumedId: Int64;
  LSvc: TSpellService; LErr: string;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel','SJ');
      LUserId := LUsers.Create('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      LStepId := LSteps.Insert(LAdvId, 0, 1, '', False, False, False);
      LAdv.SetLastStepId(LAdvId, LStepId);

      LSvc := TSpellService.Create(LConn);
      try
        Assert.IsFalse(LSvc.Cast(LAdvId, LSpellId, LConsumedId, LErr));
        Assert.AreNotEqual('', LErr);
      finally
        LSvc.Free;
      end;
    finally
      LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellServiceTests.Cast_RejectsWhenAdventureHasNoNormalStepYet;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo; LAS: TAdventureSpellsRepo;
  LBookId, LUserId, LAdvId, LSpellId, LConsumedId, LSetupId: Int64;
  LSvc: TSpellService; LErr: string;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel','SJ');
      LUserId := LUsers.Create('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      LAS.Insert(LAdvId, LSpellId, 0);
      LSetupId := LSteps.InsertSetup(LAdvId);
      LAdv.SetLastStepId(LAdvId, LSetupId); // only setup, no normal step yet

      LSvc := TSpellService.Create(LConn);
      try
        Assert.IsFalse(LSvc.Cast(LAdvId, LSpellId, LConsumedId, LErr));
        Assert.Contains(LErr, 'Sektion'); // localized error key resolves to German text containing "Sektion"
      finally
        LSvc.Free;
      end;
    finally
      LAS.Free; LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TSpellServiceTests.UndoForStep_DelegatesToRepo;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo; LAS: TAdventureSpellsRepo;
  LBookId, LUserId, LAdvId, LSpellId, LStepId, LConsumedId: Int64;
  LSvc: TSpellService;
  LGroups: TArray<TAdventureSpellGroup>;
  LErr: string;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel','SJ');
      LUserId := LUsers.Create('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      LAS.Insert(LAdvId, LSpellId, 0);
      LStepId := LSteps.Insert(LAdvId, 0, 47, '', False, False, False);
      LAdv.SetLastStepId(LAdvId, LStepId);
      LSvc := TSpellService.Create(LConn);
      try
        LSvc.Cast(LAdvId, LSpellId, LConsumedId, LErr);
        LSvc.UndoForStep(LStepId);
      finally
        LSvc.Free;
      end;
      LGroups := LAS.ListGroups(LAdvId);
      Assert.AreEqual(1, LGroups[0].Available);
      Assert.AreEqual(0, LGroups[0].Consumed);
    finally
      LAS.Free; LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSpellServiceTests);

end.
```

Note: if `TAdventuresRepo.SetLastStepId` does not yet exist, add it (mirror existing setters in the repo; SQL `UPDATE adventures SET last_step_id=:l WHERE id=:i`).

- [ ] **Step 2: Run, confirm all four fail**

- [ ] **Step 3: Implement `Services.SpellU.pas`**

```pascal
unit Services.SpellU;

interface

type
  TSpellService = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    /// <summary>Casts the oldest unconsumed instance of ASpellDefId for the
    /// adventure. Sets AConsumedId to the consumed adventure_spells.id (0 on
    /// failure) and AErrorMsg to a localized message on failure. Returns
    /// True on success.</summary>
    function Cast(AAdventureId, ASpellDefId: Int64;
      out AConsumedId: Int64; out AErrorMsg: string): Boolean;
    /// <summary>Reverts every spell instance consumed at AStepId.</summary>
    procedure UndoForStep(AStepId: Int64);
  end;

implementation

uses
  System.SysUtils,
  Repositories.AdventuresU, Repositories.StepsU,
  Repositories.AdventureSpellsU,
  Models.AdventureU;

resourcestring
  RS_SPELL_NEED_SECTION =
    'Erst eine Sektion betreten, dann zaubern.';
  RS_SPELL_NONE_AVAILABLE =
    'Kein Exemplar dieses Zaubers mehr verfügbar.';

constructor TSpellService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TSpellService.Cast(AAdventureId, ASpellDefId: Int64;
  out AConsumedId: Int64; out AErrorMsg: string): Boolean;
var
  LAdvRepo: TAdventuresRepo;
  LStepsRepo: TStepsRepo;
  LASRepo: TAdventureSpellsRepo;
  LAdv: TAdventure;
  LStep: TStep;
begin
  Result := False;
  AConsumedId := 0;
  AErrorMsg := '';
  LAdvRepo := TAdventuresRepo.Create(FConn);
  LStepsRepo := TStepsRepo.Create(FConn);
  LASRepo := TAdventureSpellsRepo.Create(FConn);
  try
    LAdv := LAdvRepo.GetById(AAdventureId);
    if LAdv.LastStepId <= 0 then
    begin
      AErrorMsg := RS_SPELL_NEED_SECTION;
      Exit;
    end;
    // Confirm last_step_id points at a normal step, not setup.
    LStep := LStepsRepo.GetById(LAdv.LastStepId);
    if LStep.Kind <> 'normal' then
    begin
      AErrorMsg := RS_SPELL_NEED_SECTION;
      Exit;
    end;
    AConsumedId := LASRepo.ConsumeOldest(
      AAdventureId, ASpellDefId, LAdv.LastStepId);
    if AConsumedId = 0 then
    begin
      AErrorMsg := RS_SPELL_NONE_AVAILABLE;
      Exit;
    end;
    Result := True;
  finally
    LASRepo.Free; LStepsRepo.Free; LAdvRepo.Free;
  end;
end;

procedure TSpellService.UndoForStep(AStepId: Int64);
var
  LASRepo: TAdventureSpellsRepo;
begin
  LASRepo := TAdventureSpellsRepo.Create(FConn);
  try
    LASRepo.RevertForStep(AStepId);
  finally
    LASRepo.Free;
  end;
end;

end.
```

If `TAdventuresRepo.GetById` does not exist or `TAdventure.LastStepId` is missing, audit the existing AdventuresU.pas and add what is needed (these are 5-line additions following the file's existing patterns).

- [ ] **Step 4: Add unit to dproj files, compile, run tests**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TSpellServiceTests
```
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add services/Services.SpellU.pas tests/Tests.Services.SpellU.pas FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add SpellService.Cast (oldest-first) and UndoForStep"
```

---

## Task 10: Extend `TAdventureStateService` with spell snapshot

**Files:**
- Modify: `services/Services.AdventureStateU.pas`
- Modify: `tests/Tests.Services.AdventureStateU.pas` (or create a sibling fixture)

- [ ] **Step 1: Write the failing test**

In `tests/Tests.Services.AdventureStateU.pas`, add a new fixture method:

```pascal
[Test]
procedure GetSpellSnapshot_GroupsAndLocalizesAvailableAndConsumed;

procedure TAdventureStateServiceTests.GetSpellSnapshot_GroupsAndLocalizesAvailableAndConsumed;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo; LAS: TAdventureSpellsRepo;
  LBookId, LUserId, LAdvId, LStrengthId, LWeaknessId, LStepId: Int64;
  LTitles: TArray<TSpellDefTitle>;
  LSvc: TAdventureStateService;
  LSnapshot: TArray<TAdventureSpellGroup>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LAdv := TAdventuresRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LSpells := TSpellDefsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('citadel','SJ');
      LUserId := LUsers.Create('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');

      LStrengthId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      SetLength(LTitles, 1);
      LTitles[0].SpellDefId := LStrengthId;
      LTitles[0].Lang := 'de';
      LTitles[0].DisplayName := 'Stärke';
      LTitles[0].Description := 'desc';
      LSpells.SetTitles(LStrengthId, LTitles);

      LWeaknessId := LSpells.UpsertSpellDef(LBookId, 'weakness', 1);
      LTitles[0].SpellDefId := LWeaknessId;
      LTitles[0].DisplayName := 'Schwäche';
      LSpells.SetTitles(LWeaknessId, LTitles);

      LAS.Insert(LAdvId, LStrengthId, 0);
      LAS.Insert(LAdvId, LStrengthId, 1);
      LAS.Insert(LAdvId, LWeaknessId, 2);
      LStepId := LSteps.Insert(LAdvId, 0, 47, '', False, False, False);
      LAS.ConsumeOldest(LAdvId, LStrengthId, LStepId);

      LSvc := TAdventureStateService.Create(LConn);
      try
        LSnapshot := LSvc.GetSpellSnapshot(LAdvId, 'de');
      finally
        LSvc.Free;
      end;

      Assert.AreEqual(2, Length(LSnapshot));
      // Ordered by spell_defs.ord ASC
      Assert.AreEqual('Stärke', LSnapshot[0].DisplayName);
      Assert.AreEqual(1, LSnapshot[0].Available);
      Assert.AreEqual(1, LSnapshot[0].Consumed);
      Assert.AreEqual('Schwäche', LSnapshot[1].DisplayName);
      Assert.AreEqual(1, LSnapshot[1].Available);
      Assert.AreEqual(0, LSnapshot[1].Consumed);
    finally
      LAS.Free; LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Implement `GetSpellSnapshot`**

In `Services.AdventureStateU.pas`:

1. Add to interface:

```pascal
function GetSpellSnapshot(AAdventureId: Int64;
  const ALang: string): TArray<TAdventureSpellGroup>;
```

2. Implementation: query `adventure_spells` grouped by `spell_def_id`, join `spell_defs` and `spell_def_titles` filtered by `lang=:lang`, with a fallback for missing translations (`LEFT JOIN` + `COALESCE` over any title row).

Reference SQL:

```sql
SELECT sd.id, sd.slug, sd.ord,
       COALESCE(t1.display_name, t2.display_name, sd.slug) AS name,
       COALESCE(t1.description,  t2.description,  '')      AS descr,
       SUM(CASE WHEN a.consumed_at IS NULL THEN 1 ELSE 0 END) AS avail,
       SUM(CASE WHEN a.consumed_at IS NULL THEN 0 ELSE 1 END) AS cons
FROM adventure_spells a
JOIN spell_defs sd ON sd.id = a.spell_def_id
LEFT JOIN spell_def_titles t1
  ON t1.spell_def_id = sd.id AND t1.lang = :lang
LEFT JOIN spell_def_titles t2
  ON t2.spell_def_id = sd.id AND t2.spell_def_id = (
    SELECT MIN(spell_def_id) FROM spell_def_titles WHERE spell_def_id = sd.id)
WHERE a.adventure_id = :a
GROUP BY sd.id, sd.slug, sd.ord, name, descr
ORDER BY sd.ord ASC
```

(Add `Models.AdventureSpellU` to the implementation uses clause.)

- [ ] **Step 4: Run, confirm pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TAdventureStateServiceTests
```

- [ ] **Step 5: Commit**

```bash
git add services/Services.AdventureStateU.pas tests/Tests.Services.AdventureStateU.pas
git commit -m "feat: add AdventureStateService.GetSpellSnapshot with localized grouping"
```

---

## Task 11: `TAdventureCreateService` — transactional adventure creation

**Files:**
- Create: `services/Services.AdventureCreateU.pas`
- Create: `tests/Tests.Services.AdventureCreateU.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Tests.Services.AdventureCreateU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TAdventureCreateServiceTests = class
  public
    [Test] procedure Create_PersistsAdventureSetupStepGearStatsAndSpells;
    [Test] procedure Create_RejectsWhenSpellPicksExceedBudget;
    [Test] procedure Create_SkipsGearAndSpellsForBooksWithoutSeed;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  TestHelpers.DbU,
  Repositories.BooksU, Repositories.UsersU, Repositories.AdventuresU,
  Repositories.StepsU, Repositories.SpellDefsU,
  Repositories.AdventureSpellsU, Repositories.BookStartingItemsU,
  Repositories.InventoryEventsU, Repositories.StatChangesU,
  Services.AdventureCreateU,
  Models.AdventureSpellU, Models.InventoryEventU;

// helper: seed a Citadel book with magic=3 stat, sword gear, two spells
procedure SeedCitadel(const AConn: string;
  out ABookId, AStrengthId, AWeaknessId, AStatMagicId: Int64);
var
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LItems: TBookStartingItemsRepo;
  LItemId: Int64;
  LSwordTitles: TArray<TStartingItemTitle>;
  LTitles: TArray<TSpellDefTitle>;
begin
  LBooks := TBooksRepo.Create(AConn);
  LSpells := TSpellDefsRepo.Create(AConn);
  LItems := TBookStartingItemsRepo.Create(AConn);
  try
    ABookId := LBooks.UpsertSeedBook('citadel','SJ');
    AStatMagicId := LBooks.UpsertStatDef(ABookId, 0, 'magic', 'integer', '3');
    LItemId := LItems.Upsert(ABookId, 'sword', 0, 1);
    SetLength(LSwordTitles, 1);
    LSwordTitles[0].StartingItemId := LItemId;
    LSwordTitles[0].Lang := 'de';
    LSwordTitles[0].DisplayName := 'Schwert';
    LItems.SetTitles(LItemId, LSwordTitles);
    AStrengthId := LSpells.UpsertSpellDef(ABookId, 'strength', 0);
    AWeaknessId := LSpells.UpsertSpellDef(ABookId, 'weakness', 1);
    SetLength(LTitles, 1);
    LTitles[0].SpellDefId := AStrengthId; LTitles[0].Lang := 'de';
    LTitles[0].DisplayName := 'Stärke'; LTitles[0].Description := '';
    LSpells.SetTitles(AStrengthId, LTitles);
    LTitles[0].SpellDefId := AWeaknessId;
    LTitles[0].DisplayName := 'Schwäche';
    LSpells.SetTitles(AWeaknessId, LTitles);
  finally
    LItems.Free; LSpells.Free; LBooks.Free;
  end;
end;

procedure TAdventureCreateServiceTests.Create_PersistsAdventureSetupStepGearStatsAndSpells;
var
  LConn: string;
  LUsers: TUsersRepo; LSteps: TStepsRepo; LAS: TAdventureSpellsRepo;
  LInv: TInventoryEventsRepo;
  LBookId, LStrengthId, LWeaknessId, LStatMagicId, LUserId, LNewAdvId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
  LSetupId: Int64;
  LInvList: TArray<TInventoryEvent>;
  LGroups: TArray<TAdventureSpellGroup>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    SeedCitadel(LConn, LBookId, LStrengthId, LWeaknessId, LStatMagicId);
    LUsers := TUsersRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    LInv := TInventoryEventsRepo.Create(LConn);
    try
      LUserId := LUsers.Create('alice','h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId;
        LReq.BookId := LBookId;
        LReq.Title := 'Run 1';
        LReq.Lang := 'de';
        SetLength(LReq.StatValues, 1);
        LReq.StatValues[0].StatDefId := LStatMagicId;
        LReq.StatValues[0].Value := '3';
        // keep sword default
        SetLength(LReq.GearRows, 1);
        LReq.GearRows[0].Slug := 'sword';
        LReq.GearRows[0].Keep := True;
        LReq.GearRows[0].Name := 'Schwert';
        LReq.GearRows[0].Quantity := 1;
        // pick 2x strength + 1x weakness (sum = 3 = magic)
        SetLength(LReq.SpellPicks, 2);
        LReq.SpellPicks[0].SpellDefId := LStrengthId;
        LReq.SpellPicks[0].Count := 2;
        LReq.SpellPicks[1].SpellDefId := LWeaknessId;
        LReq.SpellPicks[1].Count := 1;
        LReq.SpellBudgetStatDefId := LStatMagicId;

        LNewAdvId := LSvc.Create(LReq);
      finally
        LSvc.Free;
      end;

      Assert.IsTrue(LNewAdvId > 0);
      // setup step exists at seq=1
      LSetupId := LSteps.ListByAdventureAsc(LNewAdvId, False)[0].Id;
      Assert.AreEqual('setup',
        LSteps.GetById(LSetupId).Kind);
      // inventory event on the setup step
      LInvList := LInv.ListByAdventure(LNewAdvId, True);
      Assert.AreEqual(1, Length(LInvList));
      Assert.AreEqual('Schwert', LInvList[0].ItemName);
      Assert.AreEqual(LSetupId, LInvList[0].StepId);
      // 3 spell instances
      LGroups := LAS.ListGroups(LNewAdvId);
      Assert.AreEqual(2, Length(LGroups));
    finally
      LInv.Free; LAS.Free; LSteps.Free; LUsers.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureCreateServiceTests.Create_RejectsWhenSpellPicksExceedBudget;
var
  LConn: string;
  LUsers: TUsersRepo;
  LBookId, LStrengthId, LWeaknessId, LStatMagicId, LUserId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    SeedCitadel(LConn, LBookId, LStrengthId, LWeaknessId, LStatMagicId);
    LUsers := TUsersRepo.Create(LConn);
    try
      LUserId := LUsers.Create('alice','h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId; LReq.BookId := LBookId;
        LReq.Title := 'Run'; LReq.Lang := 'de';
        SetLength(LReq.StatValues, 1);
        LReq.StatValues[0].StatDefId := LStatMagicId;
        LReq.StatValues[0].Value := '3';
        SetLength(LReq.SpellPicks, 1);
        LReq.SpellPicks[0].SpellDefId := LStrengthId;
        LReq.SpellPicks[0].Count := 99;  // exceeds budget 3
        LReq.SpellBudgetStatDefId := LStatMagicId;
        Assert.WillRaise(
          procedure begin LSvc.Create(LReq); end,
          EAdventureCreateError);
      finally
        LSvc.Free;
      end;
    finally
      LUsers.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureCreateServiceTests.Create_SkipsGearAndSpellsForBooksWithoutSeed;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LSteps: TStepsRepo;
  LBookId, LUserId, LNewAdvId, LSetupId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('warlock','IL'); // no gear, no spells
      LUserId := LUsers.Create('alice','h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId; LReq.BookId := LBookId; LReq.Title := 'Run';
        LReq.Lang := 'de';
        LNewAdvId := LSvc.Create(LReq);
      finally
        LSvc.Free;
      end;
      // Setup step is created unconditionally — it's the foundation.
      LSetupId := LSteps.ListByAdventureAsc(LNewAdvId, False)[0].Id;
      Assert.AreEqual('setup', LSteps.GetById(LSetupId).Kind);
    finally
      LSteps.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventureCreateServiceTests);

end.
```

- [ ] **Step 2: Run, confirm all three fail**

- [ ] **Step 3: Implement `Services.AdventureCreateU.pas`**

```pascal
unit Services.AdventureCreateU;

interface

uses System.SysUtils;

type
  EAdventureCreateError = class(Exception);

  TAdventureCreateStatValue = record
    StatDefId: Int64;
    Value: string;
  end;

  TAdventureCreateGearRow = record
    Slug: string;
    Keep: Boolean;
    Name: string;
    Quantity: Integer;
  end;

  TAdventureCreateSpellPick = record
    SpellDefId: Int64;
    Count: Integer;
  end;

  TAdventureCreateRequest = record
    UserId, BookId: Int64;
    Title: string;
    Lang: string;
    StatValues: TArray<TAdventureCreateStatValue>;
    GearRows: TArray<TAdventureCreateGearRow>;
    SpellPicks: TArray<TAdventureCreateSpellPick>;
    /// <summary>StatDef id of the stat that bounds the spell budget; 0 when
    /// the book has no spells.</summary>
    SpellBudgetStatDefId: Int64;
  end;

  TAdventureCreateService = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    /// <summary>Validates the request, then persists adventure + setup step +
    /// gear inventory events + initial stat_changes + spell instances. Sets
    /// adventures.last_step_id to the setup step's id. Returns the new
    /// adventure id. Raises EAdventureCreateError on validation failure.
    /// Each repository call manages its own transaction; failures partway
    /// through leave a partially-created adventure that the user can clean
    /// up by deleting from the adventure list (acceptable for v1).</summary>
    function Create(const ARequest: TAdventureCreateRequest): Int64;
  end;

implementation

uses
  Repositories.AdventuresU, Repositories.StepsU,
  Repositories.InventoryEventsU, Repositories.StatChangesU,
  Repositories.AdventureSpellsU;

resourcestring
  RS_ERR_SPELL_BUDGET =
    'Die Zauberauswahl überschreitet das verfügbare Budget.';

constructor TAdventureCreateService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function FindStatValue(const AStats: TArray<TAdventureCreateStatValue>;
  AStatDefId: Int64; out AValue: string): Boolean;
var
  LS: TAdventureCreateStatValue;
begin
  for LS in AStats do
    if LS.StatDefId = AStatDefId then
    begin
      AValue := LS.Value;
      Exit(True);
    end;
  Result := False;
end;

function TAdventureCreateService.Create(
  const ARequest: TAdventureCreateRequest): Int64;
var
  LAdvRepo: TAdventuresRepo;
  LSteps: TStepsRepo;
  LInv: TInventoryEventsRepo;
  LStat: TStatChangesRepo;
  LAS: TAdventureSpellsRepo;
  LSetupId: Int64;
  LGear: TAdventureCreateGearRow;
  LStatVal: TAdventureCreateStatValue;
  LPick: TAdventureCreateSpellPick;
  LBudgetStr: string; LBudget, LTotal, I: Integer;
  LInstanceOrd: Integer;
begin
  // Validate spell budget if present
  if ARequest.SpellBudgetStatDefId > 0 then
  begin
    if not FindStatValue(ARequest.StatValues,
      ARequest.SpellBudgetStatDefId, LBudgetStr) then
      LBudget := 0
    else
      LBudget := StrToIntDef(LBudgetStr, 0);
    LTotal := 0;
    for LPick in ARequest.SpellPicks do
      Inc(LTotal, LPick.Count);
    if LTotal > LBudget then
      raise EAdventureCreateError.Create(RS_ERR_SPELL_BUDGET);
  end;

  LAdvRepo := TAdventuresRepo.Create(FConn);
  LSteps := TStepsRepo.Create(FConn);
  LInv := TInventoryEventsRepo.Create(FConn);
  LStat := TStatChangesRepo.Create(FConn);
  LAS := TAdventureSpellsRepo.Create(FConn);
  try
    Result := LAdvRepo.Create(ARequest.UserId, ARequest.BookId, ARequest.Title);
    LSetupId := LSteps.InsertSetup(Result);

    // Gear
    for LGear in ARequest.GearRows do
      if LGear.Keep and (Trim(LGear.Name) <> '') then
        LInv.Insert(LSetupId, 'gain', LGear.Name,
          Max(1, LGear.Quantity), '');

    // Initial stats: write a stat_change per provided value with old=NULL.
    for LStatVal in ARequest.StatValues do
      if Trim(LStatVal.Value) <> '' then
        LStat.Insert(LSetupId, LStatVal.StatDefId, '', LStatVal.Value, '');

    // Spell instances
    LInstanceOrd := 0;
    for LPick in ARequest.SpellPicks do
      for I := 1 to LPick.Count do
      begin
        LAS.Insert(Result, LPick.SpellDefId, LInstanceOrd);
        Inc(LInstanceOrd);
      end;

    LAdvRepo.SetLastStepId(Result, LSetupId);
  finally
    LAS.Free; LStat.Free; LInv.Free; LSteps.Free; LAdvRepo.Free;
  end;
end;

function Max(A, B: Integer): Integer;
begin
  if A >= B then Result := A else Result := B;
end;

end.
```

The `Max` helper is duplicated here as a tiny private function rather than pulling in `System.Math`; both are acceptable — use Math.Max if the team prefers (`uses System.Math` in the implementation section, drop the local function).

The `TStatChangesRepo.Insert` signature is assumed `(AStepId, AStatDefId; AOldValue, ANewValue, AReason: string)`. Verify and adjust by reading `repositories/Repositories.StatChangesU.pas`.

- [ ] **Step 4: Add unit to both dproj files; compile; run tests**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TAdventureCreateServiceTests
```
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add services/Services.AdventureCreateU.pas tests/Tests.Services.AdventureCreateU.pas FFCompanion.dproj tests/FFCompanionTests.dproj
git commit -m "feat: add AdventureCreateService with budget validation"
```

---

## Task 12: Wire `TAdventuresController.PostCreate` to the new service

**Files:**
- Modify: `controllers/Controllers.AdventuresU.pas` (lines 65–67 GET form action; lines 259–318 PostCreate)

- [ ] **Step 1: Read the current handler to refresh context**

Run: `sed -n '50,90p;259,320p' controllers/Controllers.AdventuresU.pas`

- [ ] **Step 2: Replace `PostCreate` body**

Parse the new form fields. The form posts:

- `book_id`, `title` (existing)
- `stat_<statDefId>` per stat (e.g., `stat_42=10`)
- `gear_keep_<slug>=1`, `gear_name_<slug>=Schwert`, `gear_qty_<slug>=1` per row
- `spell_count_<spellDefId>=2` per spell

The controller reads them into a `TAdventureCreateRequest` and calls the service.

Use `Context.Request.ContentParam(ParamName)` and `Context.Request.ContentParamNames` (or equivalent — verify via DMVC docs) to iterate keys with the `gear_keep_`, `gear_name_`, `gear_qty_`, `spell_count_`, `stat_` prefixes.

Skeleton (replace existing PostCreate body, keeping the existing login/validation guards):

```pascal
procedure TAdventuresController.PostCreate;
var
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
  LBookRepo: TBooksRepo;
  LSpellRepo: TSpellDefsRepo;
  LItemsRepo: TBookStartingItemsRepo;
  LStatDefs: TArray<TStatDef>;
  LSpells: TArray<TSpellDef>;
  LGearRows: TArray<TStartingItemRow>;
  LStatDef: TStatDef;
  LSpell: TSpellDef;
  LGear: TStartingItemRow;
  LIdx: Integer;
  LNewId: Int64;
  LLang: string;
  LMagicStatDefId: Int64;
  // ... (book validation locals as before)
begin
  RequireLogin;
  LLang := CurrentLanguage;  // existing helper, mirror BookCatalogService usage

  // Validate book ownership EXACTLY as in the existing handler (lines 271–309).
  // (Copy the existing book validation block verbatim.)

  // Pull definitions for the chosen book to translate form keys into ids.
  LBookRepo := TBooksRepo.Create(CMainConnection);
  LSpellRepo := TSpellDefsRepo.Create(CMainConnection);
  LItemsRepo := TBookStartingItemsRepo.Create(CMainConnection);
  try
    LStatDefs := LBookRepo.ListStatDefs(LReq.BookId);
    LSpells := LSpellRepo.ListByBook(LReq.BookId);
    LGearRows := LItemsRepo.ListByBookLocalized(LReq.BookId, LLang);
  finally
    LItemsRepo.Free; LSpellRepo.Free; LBookRepo.Free;
  end;

  LReq.UserId := CurrentUserId;
  LReq.BookId := /* from validated form */;
  LReq.Title  := /* from validated form */;
  LReq.Lang   := LLang;

  // Stats
  SetLength(LReq.StatValues, Length(LStatDefs));
  LMagicStatDefId := 0;
  for LIdx := 0 to High(LStatDefs) do
  begin
    LReq.StatValues[LIdx].StatDefId := LStatDefs[LIdx].Id;
    LReq.StatValues[LIdx].Value :=
      Trim(Context.Request.ContentParam(
        'stat_' + IntToStr(LStatDefs[LIdx].Id)));
    if SameText(LStatDefs[LIdx].Name, 'magic') then
      LMagicStatDefId := LStatDefs[LIdx].Id;
  end;

  // Gear
  SetLength(LReq.GearRows, Length(LGearRows));
  for LIdx := 0 to High(LGearRows) do
  begin
    LGear := LGearRows[LIdx];
    LReq.GearRows[LIdx].Slug := LGear.Slug;
    LReq.GearRows[LIdx].Keep :=
      Context.Request.ContentParam('gear_keep_' + LGear.Slug) = '1';
    LReq.GearRows[LIdx].Name :=
      Trim(Context.Request.ContentParam('gear_name_' + LGear.Slug));
    if LReq.GearRows[LIdx].Name = '' then
      LReq.GearRows[LIdx].Name := LGear.DisplayName;
    LReq.GearRows[LIdx].Quantity := StrToIntDef(
      Context.Request.ContentParam('gear_qty_' + LGear.Slug),
      LGear.Quantity);
  end;

  // Spells
  if Length(LSpells) > 0 then
    LReq.SpellBudgetStatDefId := LMagicStatDefId
  else
    LReq.SpellBudgetStatDefId := 0;
  SetLength(LReq.SpellPicks, Length(LSpells));
  for LIdx := 0 to High(LSpells) do
  begin
    LReq.SpellPicks[LIdx].SpellDefId := LSpells[LIdx].Id;
    LReq.SpellPicks[LIdx].Count := StrToIntDef(
      Context.Request.ContentParam('spell_count_' + IntToStr(LSpells[LIdx].Id)),
      0);
  end;

  LSvc := TAdventureCreateService.Create(CMainConnection);
  try
    try
      LNewId := LSvc.Create(LReq);
    except
      on E: EAdventureCreateError do
      begin
        Context.Response.StatusCode := HTTP_STATUS.BadRequest;
        Render(E.Message);
        Exit;
      end;
    end;
  finally
    LSvc.Free;
  end;

  Redirect('/adventures/' + IntToStr(LNewId));
end;
```

Add to `uses` (implementation): `Services.AdventureCreateU, Repositories.SpellDefsU, Repositories.BookStartingItemsU, Models.SpellDefU, Models.StartingItemU`.

If `TBooksRepo.ListStatDefs` does not exist by that name, find the equivalent (it might be on a different repo); read `repositories/Repositories.BooksU.pas` to find it.

- [ ] **Step 3: Add a partial-refresh endpoint for the create form**

Add a new MVC route that returns the book-specific form sections as an HTMX fragment:

```pascal
[MVCPath('/adventures/new/sections')]
[MVCHTTPMethod([httpGET])]
[MVCProduces(TMVCMediaType.TEXT_HTML)]
procedure GetNewSections([MVCFromQueryString('book_id', '0')] ABookId: Int64);
```

Implementation: validate the user can use ABookId; gather stat defs, gear rows, spell rows; render `pages/adventures/_new_sections.html` (a small template that includes the gear + spells partials). The book picker `<select>` in `pages/adventures/new.html` uses `hx-get="/adventures/new/sections"` `hx-target="#book-sections"` `hx-trigger="change"`.

- [ ] **Step 4: Compile, smoke test by checking existing tests still pass**

```
mcp__delphi-build__compile_delphi_project   # tests dproj
tests/bin/Win64/Debug/FFCompanionTests.exe  # full run
```
Expected: all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add controllers/Controllers.AdventuresU.pas
git commit -m "feat: wire adventure-create to AdventureCreateService and add HTMX sections endpoint"
```

---

## Task 13: Adventure-create form templates

**Files:**
- Modify: `templates/pages/adventures/new.html`
- Create: `templates/pages/adventures/_new_sections.html`
- Create: `templates/partials/_adventure_create_gear.html`
- Create: `templates/partials/_adventure_create_spells.html`

- [ ] **Step 1: Read the current form and confirm field names match the controller**

```bash
cat templates/pages/adventures/new.html
```

The book `<select>` element must:
- be named `book_id`
- post the form to `/adventures` on submit
- on `change`, fire HTMX: `hx-get="/adventures/new/sections" hx-include="[name='book_id']" hx-target="#book-sections" hx-swap="innerHTML"`

Add a placeholder div: `<div id="book-sections"></div>` directly below the book select. The form's submit button stays at the bottom; HTMX only swaps the inner sections.

- [ ] **Step 2: Create `_new_sections.html`**

```html
{{# Renders the book-dependent portion of the create form. Included via }}
{{# hx-get when the book selection changes. }}

<div class="field">
  <label class="label">{{loc.adventures_title_label}}</label>
  <div class="control">
    <input class="input" type="text" name="title" required>
  </div>
</div>

{{# Stats block }}
<div class="box mt-4">
  <h2 class="title is-5">{{loc.adventures_stats_heading}}</h2>
  {{for stat in stats}}
    <div class="field is-horizontal">
      <div class="field-label is-normal"><label class="label">{{stat.display_name}}</label></div>
      <div class="field-body">
        <div class="field">
          <div class="control">
            <input class="input" type="number" name="stat_{{stat.id}}" value="{{stat.default_value}}">
          </div>
        </div>
      </div>
    </div>
  {{endfor}}
</div>

{{if gear_present}}
  {{:include "partials/_adventure_create_gear.html"}}
{{endif}}

{{if spells_present}}
  {{:include "partials/_adventure_create_spells.html"}}
{{endif}}
```

Verify TemplatePro include / conditional / loop syntax against the existing partials (search `templates/partials/_inventory_panel.html` for the exact tag style used in this project — adjust syntax above to match).

- [ ] **Step 3: Create `_adventure_create_gear.html`**

```html
<div class="box mt-4">
  <h2 class="title is-5">{{loc.adventures_gear_heading}}</h2>
  <table class="table is-fullwidth">
    <thead>
      <tr>
        <th></th>
        <th>{{loc.adventures_gear_item}}</th>
        <th style="width:6rem">{{loc.adventures_gear_qty}}</th>
      </tr>
    </thead>
    <tbody>
      {{for item in gear_rows}}
        <tr>
          <td>
            <input type="checkbox" name="gear_keep_{{item.slug}}" value="1" checked>
          </td>
          <td>
            <input class="input is-small" type="text" name="gear_name_{{item.slug}}" value="{{item.display_name}}">
          </td>
          <td>
            <input class="input is-small" type="number" min="1" name="gear_qty_{{item.slug}}" value="{{item.quantity}}">
          </td>
        </tr>
      {{endfor}}
    </tbody>
  </table>
</div>
```

- [ ] **Step 4: Create `_adventure_create_spells.html`**

```html
<div class="box mt-4" id="spell-picker">
  <h2 class="title is-5">{{loc.adventures_spells_heading}}</h2>
  <p class="subtitle is-6">
    <span id="spell-picked">0</span> / <span id="spell-budget">{{spell_budget}}</span>
    {{loc.adventures_spells_chosen}}
  </p>
  <table class="table is-fullwidth">
    <tbody>
      {{for spell in spells}}
        <tr>
          <td>
            <strong>{{spell.display_name}}</strong><br>
            <small>{{spell.description}}</small>
          </td>
          <td style="width:10rem; text-align:right">
            <button type="button" class="button is-small spell-dec" data-id="{{spell.id}}">−</button>
            <span class="spell-count" data-id="{{spell.id}}">0</span>
            <input type="hidden" name="spell_count_{{spell.id}}" value="0" id="spell_count_{{spell.id}}">
            <button type="button" class="button is-small spell-inc" data-id="{{spell.id}}">+</button>
          </td>
        </tr>
      {{endfor}}
    </tbody>
  </table>
</div>

<script>
(function () {
  const budgetEl = document.getElementById('spell-budget');
  const pickedEl = document.getElementById('spell-picked');
  const budget = parseInt(budgetEl.textContent, 10) || 0;
  function total() {
    let s = 0;
    document.querySelectorAll('.spell-count').forEach(el => s += parseInt(el.textContent,10));
    return s;
  }
  function refresh() {
    pickedEl.textContent = total();
    const atMax = total() >= budget;
    document.querySelectorAll('.spell-inc').forEach(b => b.disabled = atMax);
    document.querySelectorAll('.spell-dec').forEach(b => {
      const id = b.getAttribute('data-id');
      const c = parseInt(document.querySelector('.spell-count[data-id="'+id+'"]').textContent,10);
      b.disabled = c <= 0;
    });
  }
  function bump(id, delta) {
    const cEl = document.querySelector('.spell-count[data-id="'+id+'"]');
    const hEl = document.getElementById('spell_count_'+id);
    let v = parseInt(cEl.textContent,10) + delta;
    if (v < 0) v = 0;
    if (total() - parseInt(cEl.textContent,10) + v > budget) return;
    cEl.textContent = v;
    hEl.value = v;
    refresh();
  }
  document.querySelectorAll('.spell-inc').forEach(b =>
    b.addEventListener('click', () => bump(b.getAttribute('data-id'), +1)));
  document.querySelectorAll('.spell-dec').forEach(b =>
    b.addEventListener('click', () => bump(b.getAttribute('data-id'), -1)));
  refresh();
})();
</script>
```

Note: the script lives inline because the partial is HTMX-swapped — global event delegation wouldn't survive re-renders. The IIFE re-binds every time. Tested manually in Task 19.

- [ ] **Step 4 (continued): Update the controller `GetNewSections` to render `_new_sections.html`**

Pass into the view model:
- `stats`: `TJsonArray` of `{id, default_value, display_name}` (use the existing localized-title helper, mirroring how `Play` populates stats).
- `gear_present`: True iff `Length(gear_rows) > 0`.
- `gear_rows`: `[{slug, display_name, quantity}]`.
- `spells_present`: True iff `Length(spells) > 0`.
- `spell_budget`: the integer default value of the `magic` stat (parsed via `StrToIntDef(stat.default_value, 0)`).
- `spells`: `[{id, display_name, description}]`.

Use `Services.LocalizedTitleU` for picking the right `display_name` per language; cross-reference how `BookListController` does this.

- [ ] **Step 5: Manual smoke test (deferred to Task 19's run-through)**

- [ ] **Step 6: Commit**

```bash
git add templates/
git commit -m "feat: render gear/spells sections on adventure-create form"
```

---

## Task 14: Spells panel + cast endpoint

**Files:**
- Create: `controllers/Controllers.SpellsU.pas`
- Create: `templates/partials/_spells_panel.html`
- Modify: `templates/pages/adventures/play.html`
- Modify: `webmodule/WebModuleU.pas` (register the new controller)

- [ ] **Step 1: Create `Controllers.SpellsU.pas`**

```pascal
unit Controllers.SpellsU;

interface

uses MVCFramework, MVCFramework.Commons, Controllers.BaseU;

type
  [MVCPath('')]
  TSpellsController = class(TBaseController)
  public
    [MVCPath('/adventures/($Id)/spells/cast')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostCast(Id: Int64;
      [MVCFromContentField('spell_def_id', '0')] ASpellDefId: Int64);
  end;

implementation

uses
  System.SysUtils,
  Services.SpellU, Services.AdventureStateU,
  Repositories.AdventuresU,
  Models.AdventureSpellU;

procedure TSpellsController.PostCast(Id: Int64; ASpellDefId: Int64);
var
  LSvc: TSpellService;
  LStateSvc: TAdventureStateService;
  LAdvRepo: TAdventuresRepo;
  LConsumedId: Int64; LErr: string;
  LSnapshot: TArray<TAdventureSpellGroup>;
  LLang: string;
begin
  RequireLogin;
  // Ownership guard: verify the adventure belongs to CurrentUserId.
  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if LAdvRepo.GetById(Id).UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.Forbidden;
      Render('');
      Exit;
    end;
  finally
    LAdvRepo.Free;
  end;

  LSvc := TSpellService.Create(CMainConnection);
  try
    if not LSvc.Cast(Id, ASpellDefId, LConsumedId, LErr) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.BadRequest;
      Render(LErr);
      Exit;
    end;
  finally
    LSvc.Free;
  end;

  // Re-render the spells panel
  LLang := CurrentLanguage;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LSnapshot := LStateSvc.GetSpellSnapshot(Id, LLang);
  finally
    LStateSvc.Free;
  end;
  // Hand the snapshot off to the view via the standard ViewData mechanism
  // (mirror existing Render calls in TAdventuresController.Play).
  ViewData['adventure_id'] := Id;
  ViewData['spells_available'] := AvailableJson(LSnapshot);
  ViewData['spells_consumed']  := ConsumedJson(LSnapshot);
  Render(RenderView('partials/_spells_panel'));
end;
```

`AvailableJson` / `ConsumedJson` are tiny helpers that filter the snapshot into JSON arrays. Implement inline in the unit (private functions) following the JSON-building patterns in `Controllers.AdventuresU.pas` (`TJsonObject`, `TJsonArray`).

- [ ] **Step 2: Create `_spells_panel.html`**

```html
<div id="spells-panel" class="box">
  <h2 class="title is-5">{{loc.adventures_spells_panel_heading}}</h2>
  <h3 class="subtitle is-6">{{loc.adventures_spells_available}}</h3>
  {{if !spells_available}}
    <p><em>{{loc.adventures_spells_none}}</em></p>
  {{endif}}
  {{for s in spells_available}}
    <div class="level">
      <div class="level-left">
        <strong>{{s.display_name}}</strong>
        {{if s.count > 1}}<span class="tag ml-2">×{{s.count}}</span>{{endif}}
      </div>
      <div class="level-right">
        <form hx-post="/adventures/{{adventure_id}}/spells/cast"
              hx-target="#spells-panel"
              hx-swap="outerHTML">
          <input type="hidden" name="spell_def_id" value="{{s.id}}">
          <button class="button is-small is-primary" type="submit">
            {{loc.adventures_spells_cast}}
          </button>
        </form>
      </div>
    </div>
  {{endfor}}

  {{if spells_consumed_any}}
    <h3 class="subtitle is-6 mt-4">{{loc.adventures_spells_consumed}}</h3>
    {{for c in spells_consumed}}
      <div>
        <span class="has-text-grey">{{c.display_name}}</span>
        {{if c.count > 1}}<span class="tag is-light ml-2">×{{c.count}}</span>{{endif}}
      </div>
    {{endfor}}
  {{endif}}
</div>
```

- [ ] **Step 3: Include the panel in `play.html`**

In `templates/pages/adventures/play.html`, find the existing inventory/stats panel area and add `{{:include "partials/_spells_panel.html"}}` next to them, wrapped in a conditional `{{if spells_panel_visible}}…{{endif}}`. The controller's `Play` method must populate `spells_available`, `spells_consumed`, `spells_panel_visible` from `TAdventureStateService.GetSpellSnapshot`. Cross-reference the existing inventory/stats wiring in `Play` (lines ~320–490) and follow the same JSON-building pattern.

- [ ] **Step 4: Register the new controller**

In `webmodule/WebModuleU.pas`, find where other controllers are added to the DMVC engine (`AddController` calls) and append:

```pascal
.AddController(TSpellsController)
```

Add `Controllers.SpellsU` to the `uses` clause.

- [ ] **Step 5: Add unit to dproj, compile, smoke**

```
mcp__delphi-build__compile_delphi_project   # FFCompanion.dproj Win64 Debug
mcp__delphi-build__compile_delphi_project   # tests Win64 Debug
tests/bin/Win64/Debug/FFCompanionTests.exe
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add controllers/Controllers.SpellsU.pas templates/partials/_spells_panel.html templates/pages/adventures/play.html webmodule/WebModuleU.pas FFCompanion.dproj
git commit -m "feat: render spells panel and POST cast endpoint"
```

---

## Task 15: Timeline setup chip + spell sub-chip

**Files:**
- Modify: `templates/partials/_timeline.html`
- Modify: `controllers/Controllers.AdventuresU.pas` (timeline data population)

- [ ] **Step 1: Read the current timeline partial and data shape**

```bash
cat templates/partials/_timeline.html
grep -n "timeline\|TJsonArray\|JsonStepObj" controllers/Controllers.AdventuresU.pas | head -30
```

The timeline likely receives an array of step objects with section number, flags, etc. The new requirements:

- A step with `kind='setup'` should render as `Setup — <item1>, <item2>, …`. The list of items comes from joining setup-step `inventory_events`.
- A normal step with one or more consumed spells should show a sub-chip per spell name.

- [ ] **Step 2: Extend the timeline data builder**

In the timeline-building code path of the controller, for each step:
- If `kind = 'setup'`: collect the step's inventory_events (already loaded via the inventory list) and emit a `setup_items` JSON array of item names.
- For all steps: query `adventure_spells` joined with `spell_def_titles` to collect spells consumed at that step (`WHERE consumed_step_id = step.id`). Emit `spells_cast`: array of `{display_name}`.

A small helper in `TAdventureStateService` is cleanest:

```pascal
function GetCastsByStep(AAdventureId: Int64; const ALang: string):
  TDictionary<Int64, TArray<string>>;  // stepId -> spell display names
```

Implement it and use it from the controller. (Memory: the controller owns the dictionary and frees it after rendering.)

- [ ] **Step 3: Extend `_timeline.html`**

Wherever a step row is rendered, add:

```html
{{if step.kind == "setup"}}
  <span class="tag is-light">{{loc.timeline_setup_chip}}</span>
  {{for it in step.setup_items}}<span class="tag is-info is-light ml-1">{{it}}</span>{{endfor}}
{{endif}}

{{for sp in step.spells_cast}}
  <span class="tag is-warning is-light ml-1">⚡ {{sp.display_name}}</span>
{{endfor}}
```

- [ ] **Step 4: Compile and run, confirm nothing regressed**

```
tests/bin/Win64/Debug/FFCompanionTests.exe
```

- [ ] **Step 5: Commit**

```bash
git add templates/partials/_timeline.html controllers/Controllers.AdventuresU.pas services/Services.AdventureStateU.pas
git commit -m "feat: render setup chip and spell sub-chips in timeline"
```

---

## Task 16: Graph builder filters setup steps

**Files:**
- Modify: `services/Services.GraphBuilderU.pas`
- Modify: `tests/Tests.Services.GraphBuilderU.pas`

- [ ] **Step 1: Write failing test**

Read the existing fixture to find the helper that seeds steps. Append:

```pascal
[Test]
procedure SetupStep_DoesNotProduceNode;

procedure TGraphBuilderTests.SetupStep_DoesNotProduceNode;
var
  LConn: string;
  LSteps: TStepsRepo;
  // ... bootstrap adventure + book + user as in surrounding tests
  LSetupId, LNormalId: Int64;
  LBuilder: TGraphBuilder;
  LJson: TJsonObject; LNodes: TJsonArray;
begin
  // ... LAdvId set up as in other tests
  LSetupId := LSteps.InsertSetup(LAdvId);
  LNormalId := LSteps.Insert(LAdvId, 0, 1, '', False, False, False);
  LBuilder := TGraphBuilder.Create(LConn);
  try
    LJson := LBuilder.Build(LAdvId);
    try
      LNodes := LJson.A['nodes'];
      // No node should reference the setup step
      // and the section-1 normal step should produce exactly one node.
      Assert.AreEqual(1, LNodes.Count);
    finally
      LJson.Free;
    end;
  finally
    LBuilder.Free;
  end;
end;
```

- [ ] **Step 2: Implement filter in `GraphBuilderU`**

Find where steps are iterated; add a guard `if LStep.Kind = 'setup' then Continue;` at the top of the loop body. (The repo now returns Kind for every step thanks to Task 8.)

- [ ] **Step 3: Run, confirm pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TGraphBuilderTests
```

- [ ] **Step 4: Commit**

```bash
git add services/Services.GraphBuilderU.pas tests/Tests.Services.GraphBuilderU.pas
git commit -m "feat: skip setup steps in graph builder"
```

---

## Task 17: Soft-undo wires through `TSpellService.UndoForStep`

**Files:**
- Modify: `controllers/Controllers.StepsU.pas`

- [ ] **Step 1: Find the existing undo endpoint**

```bash
grep -n "Undo\|undone\|SetUndone" controllers/Controllers.StepsU.pas
```

- [ ] **Step 2: Add the spell-revert call**

In the existing undo handler, right after the step's `flag_*` reversion / `SetUndone(StepId, True)` call (whichever signals "undo"), insert:

```pascal
LSpellSvc := TSpellService.Create(CMainConnection);
try
  LSpellSvc.UndoForStep(LStepId);
finally
  LSpellSvc.Free;
end;
```

Add `Services.SpellU` to the implementation uses clause. Mirror the redo handler if one exists: redoing a step does NOT auto-re-consume spells (the user can re-cast manually). Leave redo untouched.

- [ ] **Step 3: Add a focused test**

Append to `tests/Tests.E2E.PlaythroughU.pas` (or create `Tests.E2E.SpellUndoU.pas`):

```pascal
[Test]
procedure UndoStep_ReavailabilizesCastsOnThatStep;
// E2E HTTP equivalent: POST a step, POST a cast, POST the undo, GET the
// spells panel, assert availability restored. (Use the test helper pattern
// from Tests.E2E.PlaythroughU.pas for the HTTP harness.)
```

Implementation mirrors `Tests.E2E.PlaythroughU` — read that file for the in-process MVC harness setup.

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
git add controllers/Controllers.StepsU.pas tests/Tests.E2E.PlaythroughU.pas
git commit -m "feat: revert spell consumption on soft-undo"
```

---

## Task 18: Localization strings

**Files:**
- Modify: `l10n/de.json`
- Modify: `l10n/en.json`
- Modify: `tests/Tests.L10nU.pas`

- [ ] **Step 1: Add new keys to both files**

Add to `l10n/de.json` (preserve existing JSON structure):

```json
"adventures_gear_heading": "Startausrüstung",
"adventures_gear_item": "Gegenstand",
"adventures_gear_qty": "Anzahl",
"adventures_spells_heading": "Zauberformeln wählen",
"adventures_spells_chosen": "Zauber gewählt",
"adventures_spells_panel_heading": "Zauberformeln",
"adventures_spells_available": "Verfügbar",
"adventures_spells_consumed": "Verbraucht",
"adventures_spells_cast": "Wirken",
"adventures_spells_none": "Keine Zauber verfügbar.",
"adventures_spells_need_section": "Erst eine Sektion betreten, dann zaubern.",
"adventures_spells_none_available": "Kein Exemplar dieses Zaubers mehr verfügbar.",
"timeline_setup_chip": "Setup",
"adventures_stats_heading": "Werte",
"adventures_title_label": "Titel des Abenteuers"
```

Add equivalents to `l10n/en.json`:

```json
"adventures_gear_heading": "Starting Gear",
"adventures_gear_item": "Item",
"adventures_gear_qty": "Qty",
"adventures_spells_heading": "Choose Spells",
"adventures_spells_chosen": "spells chosen",
"adventures_spells_panel_heading": "Spells",
"adventures_spells_available": "Available",
"adventures_spells_consumed": "Used",
"adventures_spells_cast": "Cast",
"adventures_spells_none": "No spells available.",
"adventures_spells_need_section": "Enter a section before casting a spell.",
"adventures_spells_none_available": "No instance of this spell remains.",
"timeline_setup_chip": "Setup",
"adventures_stats_heading": "Stats",
"adventures_title_label": "Adventure title"
```

- [ ] **Step 2: Extend l10n tests**

`tests/Tests.L10nU.pas` likely asserts every key in `de.json` exists in `en.json` (and vice versa). Re-run it:

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TL10nTests
```

If the test fails because a specific key is missing, fix the JSON; do not relax the test.

- [ ] **Step 3: Replace the hard-coded German resourcestring in `TSpellService` with a key lookup**

The service currently returns hard-coded German via `resourcestring`. Adjust to return a STRING KEY (e.g. `'adventures_spells_need_section'`) instead, and let the controller resolve it via the l10n helper for the user's language. Update `TSpellServiceTests.Cast_RejectsWhenAdventureHasNoNormalStepYet` to assert on the key, not the German text:

```pascal
Assert.AreEqual('adventures_spells_need_section', LErr);
```

(Or keep the German text and add a German assertion — pick whichever is more consistent with existing services. Audit `Services.AuthU` for the current convention.)

- [ ] **Step 4: Commit**

```bash
git add l10n/de.json l10n/en.json services/Services.SpellU.pas tests/Tests.Services.SpellU.pas
git commit -m "feat: localize spells/gear UI strings"
```

---

## Task 19: End-to-end HTTP test + manual smoke

**Files:**
- Create: `tests/Tests.E2E.SpellsAndGearU.pas`

- [ ] **Step 1: Write the E2E test**

Use `tests/Tests.E2E.PlaythroughU.pas` as the model — it shows how to spin the MVC engine against an in-memory DB and issue HTTP requests via `MVCFramework.RESTAdapter` or `THttpClient`.

```pascal
unit Tests.E2E.SpellsAndGearU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TSpellsAndGearE2ETests = class
  public
    [Test] procedure CitadelRun_CreateCastUndoReavailabilizes;
  end;

implementation

uses
  // ... bring in the same harness uses as Tests.E2E.PlaythroughU
  ;

procedure TSpellsAndGearE2ETests.CitadelRun_CreateCastUndoReavailabilizes;
begin
  // 1. Boot in-memory DB + seed catalog (mirror PlaythroughU's setup).
  // 2. Sign up + log in via /signup, /login.
  // 3. POST /adventures with:
  //      book_id=<citadel>, title=Test, stat_<magicId>=3,
  //      gear_keep_sword=1, gear_name_sword=Schwert, gear_qty_sword=1,
  //      gear_keep_leather-armor=1, …,
  //      spell_count_<strength>=2, spell_count_<weakness>=1
  // 4. Assert: 1 setup step, 3 gear inventory_events on setup, 3 spell instances.
  // 5. POST /steps to enter section 1 (use Tests.E2E.PlaythroughU helper).
  // 6. POST /adventures/{id}/spells/cast with spell_def_id=<strength>.
  // 7. GET the adventure page; assert response body contains
  //    'Stärke ×1' in available, 'Stärke' in consumed.
  // 8. POST /adventures/{id}/steps/{id}/undo  (the section-1 step).
  // 9. GET adventure page; assert 'Stärke ×2' in available, 'Verbraucht' absent.
end;

initialization
  TDUnitX.RegisterTestFixture(TSpellsAndGearE2ETests);

end.
```

Flesh out the test using the same idioms as `Tests.E2E.PlaythroughU.pas` (the `// ...` lines above are placeholders for harness boilerplate that the existing E2E test already demonstrates — copy that pattern, don't re-invent it).

- [ ] **Step 2: Run, debug, and pass**

```
tests/bin/Win64/Debug/FFCompanionTests.exe --include:TSpellsAndGearE2ETests
```

- [ ] **Step 3: Build Linux64 release binary**

```
mcp__delphi-build__compile_delphi_project   # FFCompanion.dproj Linux64 Release
```

- [ ] **Step 4: Manual smoke test**

```bash
# From WSL:
rm -f data/ffcompanion.db   # clean slate
docker compose -f docker/docker-compose.yaml up -d --build
xdg-open http://localhost:8080/signup
```

Walk through:
1. Sign up.
2. Click "Neues Abenteuer", pick *Die Zitadelle des Zauberers*.
3. Confirm the form renders: stats (with Zauberkraft), Startausrüstung (Schwert/Lederrüstung/Fackel, all checked), Zauberformeln wählen (14 spells with +/− and budget counter).
4. Pick 2× Stärke + 1× Schwäche; the budget must show "3 / 3".
5. Submit.
6. Adventure page renders with Stats / Inventory (Schwert/Lederrüstung/Fackel) / Spells (Stärke ×2, Schwäche ×1) panels.
7. Try to cast Stärke before entering a section — must show the "Erst eine Sektion betreten" message.
8. Enter section 1 via the step form.
9. Cast Stärke; the panel re-renders to Stärke ×1 / Verbraucht: Stärke.
10. Undo the section-1 step. Spells panel returns to Stärke ×2; consumed list empty.

If any of the manual steps fails, log the failure mode and iterate on the relevant earlier task.

- [ ] **Step 5: Commit**

```bash
git add tests/Tests.E2E.SpellsAndGearU.pas tests/FFCompanionTests.dproj
git commit -m "test: e2e coverage of citadel create + cast + undo round-trip"
```

---

## After All Tasks

Run the full test suite one final time:

```
mcp__delphi-build__compile_delphi_project   # tests dproj
tests/bin/Win64/Debug/FFCompanionTests.exe
```

Expected: all green. Then build the Linux64 binary and confirm the docker image starts.
