{*******************************************************************************
  Unit Name: TestHelpers.DbU
  Purpose: Database fixture helpers for FFCompanion DUnitX tests

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TDbHelper exposes class methods to spin up a fresh isolated SQLite
    database with the FFCompanion schema applied, and to drop the
    corresponding FireDAC connection definition afterwards. Tests should
    bracket their fixture work with NewMemoryDb / Drop to keep runs isolated.

    Although named NewMemoryDb for clarity at call sites, the helper is
    backed by a unique per-call temporary file: pure SQLite ':memory:'
    databases are private to a single physical FireDAC connection and cannot
    be shared with the independent TFDConnection instances that repositories
    open by name. A temp file is removed in Drop, so test isolation matches
    the in-memory semantics intended by the design.

  Dependencies:
    - FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Intf
    - Repositories.MigrationU
*******************************************************************************}

unit TestHelpers.DbU;

interface

type
  /// <summary>
  ///   Database fixture helpers for isolated per-test SQLite databases.
  /// </summary>
  TDbHelper = class
  public
    /// <summary>
    ///   Creates a fresh FireDAC connection definition backed by a unique
    ///   temp-file SQLite database, runs migrations against it, and returns
    ///   its definition name.
    /// </summary>
    /// <returns>Unique FireDAC connection definition name.</returns>
    class function NewMemoryDb: string;

    /// <summary>
    ///   Closes any pooled connections, removes the FireDAC connection
    ///   definition, and deletes the backing SQLite file. Safe to call in
    ///   a finally block paired with NewMemoryDb.
    /// </summary>
    /// <param name="AConnectionName">Name previously returned by NewMemoryDb.</param>
    class procedure Drop(const AConnectionName: string);
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  FireDAC.Stan.Intf,
  FireDAC.Comp.Client, FireDAC.Stan.Def,
  Repositories.MigrationU;

class function TDbHelper.NewMemoryDb: string;
begin
  Result := TMigrationRunner.CreateInMemoryConnection;
  TMigrationRunner.RunOnConnection(Result);
end;

class procedure TDbHelper.Drop(const AConnectionName: string);
var
  LDef: IFDStanConnectionDef;
  LPath: string;
begin
  LPath := '';
  LDef := FDManager.ConnectionDefs.FindConnectionDef(AConnectionName);
  if LDef <> nil then
    LPath := LDef.Params.Values['Database'];

  FDManager.CloseConnectionDef(AConnectionName);
  if LDef <> nil then
    LDef.Delete;

  if (LPath <> '') and TFile.Exists(LPath) then
    TFile.Delete(LPath);
end;

end.
