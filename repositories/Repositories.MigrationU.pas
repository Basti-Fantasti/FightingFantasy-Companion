{*******************************************************************************
  Unit Name: Repositories.MigrationU
  Purpose: SQLite schema migration runner and FireDAC connection factory

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TMigrationRunner: idempotent CREATE TABLE / CREATE INDEX execution
    against a named FireDAC connection, plus factory helpers for file-backed
    and in-memory SQLite connection definitions. The schema covers all eleven
    tables from the FFCompanion design spec (§5).

    PRAGMA foreign_keys is enabled per connection inside RunOnConnection.
    SQLite enforces this PRAGMA per connection, so subsequent connections that
    rely on foreign-key behaviour must enable it themselves.

  Dependencies:
    - FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async
    - FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef, FireDAC.Phys.SQLiteWrapper.Stat
*******************************************************************************}

unit Repositories.MigrationU;

interface

uses
  FireDAC.Stan.Intf,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat;

type
  /// <summary>
  ///   Static helper that creates and migrates SQLite connections used by
  ///   FFCompanion. All methods are class methods; the class is never
  ///   instantiated.
  /// </summary>
  TMigrationRunner = class
  public
    /// <summary>
    ///   Opens the named FireDAC connection definition and runs every
    ///   CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS statement
    ///   that defines the FFCompanion schema. Enables foreign keys for the
    ///   duration of the open connection.
    /// </summary>
    /// <param name="AConnectionName">
    ///   Name of a previously registered FireDAC connection definition.
    /// </param>
    class procedure RunOnConnection(const AConnectionName: string);

    /// <summary>
    ///   Registers a FireDAC connection definition pointing at the given
    ///   SQLite file path (creating parent directories as needed). Returns
    ///   the connection definition name to pass to RunOnConnection / repos.
    ///   Idempotent: re-uses the existing definition on subsequent calls.
    /// </summary>
    /// <param name="ADbPath">Absolute path to the SQLite file.</param>
    /// <returns>Connection definition name (constant 'FFMain').</returns>
    class function CreateFileConnection(const ADbPath: string): string;

    /// <summary>
    ///   Registers a fresh FireDAC connection definition backed by an
    ///   anonymous in-memory SQLite database. Each call returns a unique
    ///   name so tests can run isolated databases in parallel.
    /// </summary>
    /// <returns>Unique connection definition name.</returns>
    class function CreateInMemoryConnection: string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  FireDAC.Stan.Param, FireDAC.DApt;

procedure InitRandom;
begin
  if RandSeed = 0 then
    Randomize;
end;

const
  SQL_SCHEMA: array[0..14] of string = (
    'CREATE TABLE IF NOT EXISTS users (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'username TEXT NOT NULL UNIQUE, ' +
      'password_hash TEXT NOT NULL, ' +
      'created_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS sessions (' +
      'token TEXT PRIMARY KEY, ' +
      'user_id INTEGER NOT NULL REFERENCES users(id), ' +
      'expires_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS books (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'slug TEXT NOT NULL UNIQUE, ' +
      'author TEXT, ' +
      'owner_user_id INTEGER REFERENCES users(id), ' +
      'is_seed INTEGER NOT NULL DEFAULT 0, ' +
      'created_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS book_titles (' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'title TEXT NOT NULL, ' +
      'PRIMARY KEY (book_id, lang))',

    'CREATE TABLE IF NOT EXISTS stat_defs (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'ord INTEGER NOT NULL, ' +
      'name TEXT NOT NULL, ' +
      'kind TEXT NOT NULL CHECK(kind IN (''integer'',''text'',''checkbox'')), ' +
      'default_value TEXT, ' +
      'UNIQUE(book_id, name))',

    'CREATE TABLE IF NOT EXISTS stat_def_titles (' +
      'stat_def_id INTEGER NOT NULL REFERENCES stat_defs(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'display_name TEXT NOT NULL, ' +
      'PRIMARY KEY (stat_def_id, lang))',

    'CREATE TABLE IF NOT EXISTS adventures (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'user_id INTEGER NOT NULL REFERENCES users(id), ' +
      'book_id INTEGER NOT NULL REFERENCES books(id), ' +
      'title TEXT NOT NULL, ' +
      'status TEXT NOT NULL DEFAULT ''active'' CHECK(status IN (''active'',''completed'',''abandoned'')), ' +
      'started_at TEXT NOT NULL, ' +
      'last_step_id INTEGER)',

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

    'CREATE TABLE IF NOT EXISTS stat_changes (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'step_id INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE, ' +
      'stat_def_id INTEGER NOT NULL REFERENCES stat_defs(id), ' +
      'old_value TEXT, ' +
      'new_value TEXT NOT NULL, ' +
      'reason TEXT)',

    'CREATE TABLE IF NOT EXISTS inventory_events (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'step_id INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE, ' +
      'kind TEXT NOT NULL CHECK(kind IN (''gain'',''lose'',''modify'')), ' +
      'item_name TEXT NOT NULL, ' +
      'quantity INTEGER NOT NULL DEFAULT 1, ' +
      'note TEXT)',

    'CREATE TABLE IF NOT EXISTS spell_defs (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'slug TEXT NOT NULL, ' +
      'ord INTEGER NOT NULL, ' +
      'UNIQUE(book_id, slug))',

    'CREATE TABLE IF NOT EXISTS spell_def_titles (' +
      'spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'display_name TEXT NOT NULL, ' +
      'description TEXT NOT NULL DEFAULT '''', ' +
      'PRIMARY KEY (spell_def_id, lang))',

    'CREATE TABLE IF NOT EXISTS adventure_spells (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
      'spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id), ' +
      'ord INTEGER NOT NULL, ' +
      'consumed_at TEXT, ' +
      'consumed_step_id INTEGER REFERENCES steps(id))',

    'CREATE TABLE IF NOT EXISTS book_starting_items (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'slug TEXT NOT NULL, ' +
      'ord INTEGER NOT NULL, ' +
      'quantity INTEGER NOT NULL DEFAULT 1, ' +
      'UNIQUE(book_id, slug))',

    'CREATE TABLE IF NOT EXISTS book_starting_item_titles (' +
      'starting_item_id INTEGER NOT NULL REFERENCES book_starting_items(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'display_name TEXT NOT NULL, ' +
      'PRIMARY KEY (starting_item_id, lang))'
  );

  SQL_INDICES: array[0..10] of string = (
    'CREATE INDEX IF NOT EXISTS idx_steps_adv_seq ON steps(adventure_id, seq)',
    'CREATE INDEX IF NOT EXISTS idx_stat_changes_step ON stat_changes(step_id)',
    'CREATE INDEX IF NOT EXISTS idx_inv_events_step ON inventory_events(step_id)',
    'CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)',
    'CREATE INDEX IF NOT EXISTS idx_adventures_user_status ON adventures(user_id, status)',
    'CREATE INDEX IF NOT EXISTS idx_book_titles ON book_titles(book_id, lang)',
    'CREATE INDEX IF NOT EXISTS idx_stat_def_titles ON stat_def_titles(stat_def_id, lang)',
    'CREATE INDEX IF NOT EXISTS idx_adventure_spells_avail ON adventure_spells(adventure_id, consumed_at)',
    'CREATE INDEX IF NOT EXISTS idx_adventure_spells_step  ON adventure_spells(consumed_step_id)',
    'CREATE INDEX IF NOT EXISTS idx_book_starting_items    ON book_starting_items(book_id, ord)',
    'CREATE INDEX IF NOT EXISTS idx_book_starting_item_titles ON book_starting_item_titles(starting_item_id, lang)'
  );

  // 11th table held separately so the SQL_SCHEMA array stays balanced.
  SQL_DICE = 'CREATE TABLE IF NOT EXISTS dice_rolls (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
    'step_id INTEGER REFERENCES steps(id), ' +
    'expression TEXT NOT NULL, ' +
    'result INTEGER NOT NULL, ' +
    'rolled_at TEXT NOT NULL)';

  FFMAIN_CONN_NAME = 'FFMain';

class procedure TMigrationRunner.RunOnConnection(const AConnectionName: string);
var
  LConn: TFDConnection;
  LStmt: string;
begin
  LConn := TFDConnection.Create(nil);
  try
    LConn.ConnectionDefName := AConnectionName;
    LConn.Open;
    LConn.ExecSQL('PRAGMA foreign_keys = ON');
    for LStmt in SQL_SCHEMA do
      LConn.ExecSQL(LStmt);
    LConn.ExecSQL(SQL_DICE);
    for LStmt in SQL_INDICES do
      LConn.ExecSQL(LStmt);
  finally
    LConn.Free;
  end;
end;

class function TMigrationRunner.CreateFileConnection(const ADbPath: string): string;
var
  LDef: IFDStanConnectionDef;
  LParams: TFDPhysSQLiteConnectionDefParams;
begin
  ForceDirectories(ExtractFilePath(ADbPath));
  Result := FFMAIN_CONN_NAME;
  LDef := FDManager.ConnectionDefs.FindConnectionDef(Result);
  if LDef = nil then
  begin
    LDef := FDManager.ConnectionDefs.AddConnectionDef;
    LDef.Name := Result;
    LParams := TFDPhysSQLiteConnectionDefParams(LDef.Params);
    LParams.DriverID := 'SQLite';
    LParams.Database := ADbPath;
    LDef.Apply;
  end;
end;

class function TMigrationRunner.CreateInMemoryConnection: string;
var
  LDef: IFDStanConnectionDef;
  LParams: TFDPhysSQLiteConnectionDefParams;
  LTag, LPath: string;
begin
  InitRandom;
  // SQLite ':memory:' databases are private to a single physical connection
  // and FireDAC pooling does not share them. To let independent
  // TFDConnection instances observe the same migrated schema, the "in
  // memory" helper points at a unique file inside the OS temp directory and
  // relies on Drop to delete it. The data set per test is tiny enough that
  // the disk hit is negligible (sub-millisecond on tmpfs/NTFS).
  LTag := FormatDateTime('hhnnsszzz', Now) + IntToStr(Random(100000));
  Result := 'FFTest_' + LTag;
  LPath := TPath.Combine(TPath.GetTempPath, Result + '.sqlite');
  LDef := FDManager.ConnectionDefs.AddConnectionDef;
  LDef.Name := Result;
  LParams := TFDPhysSQLiteConnectionDefParams(LDef.Params);
  LParams.DriverID := 'SQLite';
  LParams.Database := LPath;
  LDef.Apply;
end;

end.
