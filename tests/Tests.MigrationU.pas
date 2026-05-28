{*******************************************************************************
  Unit Name: Tests.MigrationU
  Purpose: DUnitX tests for the FFCompanion SQLite migration runner

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Asserts that running the migrations against a fresh in-memory SQLite
    database produces all eleven tables declared in the design spec.
    Each test owns its connection definition and removes it in a finally
    block so parallel runs stay isolated.

  Dependencies:
    - DUnitX.TestFramework
    - FireDAC.Comp.Client
    - TestHelpers.DbU
*******************************************************************************}

unit Tests.MigrationU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Tests that verify SQLite schema migrations produce the expected tables.</summary>
  [TestFixture]
  TMigrationTests = class
  public
    /// <summary>Every table from the design spec exists after running migrations.</summary>
    [Test]
    procedure AllTablesCreated;

    /// <summary>New spell and gear tables are created by the migration.</summary>
    [Test]
    procedure NewSpellAndGearTables_AreCreated;

    /// <summary>steps table has the kind column and to_section is nullable.</summary>
    [Test]
    procedure StepsTable_HasKindColumnAndNullableToSection;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  FireDAC.Comp.Client,
  TestHelpers.DbU;

procedure TMigrationTests.AllTablesCreated;
var
  LConn: TFDConnection;
  LExpected: TStringList;
  LName, LFound: string;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LExpected := TStringList.Create;
  try
    LExpected.CommaText :=
      'users,sessions,books,book_titles,stat_defs,stat_def_titles,' +
      'adventures,steps,stat_changes,inventory_events,dice_rolls';
    LConn := TFDConnection.Create(nil);
    try
      LConn.ConnectionDefName := LDb;
      LConn.Open;
      for LName in LExpected do
      begin
        LFound := LConn.ExecSQLScalar(
          'SELECT name FROM sqlite_master WHERE type=''table'' AND name=:n',
          [LName]);
        Assert.AreEqual(LName, LFound, 'Missing table: ' + LName);
      end;
    finally
      LConn.Free;
    end;
  finally
    LExpected.Free;
    TDbHelper.Drop(LDb);
  end;
end;

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

initialization
  TDUnitX.RegisterTestFixture(TMigrationTests);

end.
