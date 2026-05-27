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
  end;

implementation

uses
  System.Classes,
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

initialization
  TDUnitX.RegisterTestFixture(TMigrationTests);

end.
