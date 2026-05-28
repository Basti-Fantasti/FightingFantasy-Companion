{*******************************************************************************
  Unit Name: Tests.Repositories.AdventuresU
  Purpose: DUnitX fixtures for TAdventuresRepo round-trips and filters

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exercises Create/GetById round-trip semantics for adventures and verifies
    that ListForUser filters correctly by user id and by status set. Each
    test brackets fixture work with TDbHelper.NewMemoryDb/Drop so runs stay
    fully isolated.
*******************************************************************************}

unit Tests.Repositories.AdventuresU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising TAdventuresRepo against SQLite.
  /// </summary>
  [TestFixture]
  TAdventuresRepoTests = class
  public
    [Test] procedure CreateAndGetByIdRoundTrip;
    [Test] procedure ListForUserFiltersByUser;
    [Test] procedure ListForUserFiltersByStatus;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  FireDAC.Comp.Client,
  Models.AdventureU,
  Repositories.UsersU,
  Repositories.AdventuresU,
  TestHelpers.DbU;

const
  ISO_FMT = 'yyyy-mm-dd"T"hh:nn:ss';

function InsertSeedBook(const AConn, ASlug, AAuthor: string): Int64;
var
  LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := AConn;
    LC.Open;
    LC.ExecSQL(
      'INSERT INTO books (slug, author, is_seed, created_at) ' +
      'VALUES (:s,:a,1,:c)',
      [ASlug, AAuthor, FormatDateTime(ISO_FMT, Now)]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally
    LC.Free;
  end;
end;

procedure TAdventuresRepoTests.CreateAndGetByIdRoundTrip;
var
  LDb: string;
  LUsers: TUsersRepo;
  LAdvs: TAdventuresRepo;
  LUid, LBid, LAid: Int64;
  LAdv: TAdventure;
begin
  LDb := TDbHelper.NewMemoryDb;
  LUsers := TUsersRepo.Create(LDb);
  LAdvs := TAdventuresRepo.Create(LDb);
  try
    LUid := LUsers.Insert('alice', 'hash');
    LBid := InsertSeedBook(LDb, 'warlock', 'Jackson, Livingstone');
    LAid := LAdvs.Create(LUid, LBid, 'test');
    Assert.IsTrue(LAid > 0);

    LAdv := LAdvs.GetById(LAid);
    Assert.AreEqual<Int64>(LAid, LAdv.Id);
    Assert.AreEqual<Int64>(LUid, LAdv.UserId);
    Assert.AreEqual<Int64>(LBid, LAdv.BookId);
    Assert.AreEqual('test', LAdv.Title);
    Assert.AreEqual('active', LAdv.Status);
    Assert.AreEqual<Int64>(0, LAdv.LastStepId);
  finally
    LAdvs.Free;
    LUsers.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TAdventuresRepoTests.ListForUserFiltersByUser;
var
  LDb: string;
  LUsers: TUsersRepo;
  LAdvs: TAdventuresRepo;
  LUid1, LUid2, LBid: Int64;
  LList: TArray<TAdventure>;
begin
  LDb := TDbHelper.NewMemoryDb;
  LUsers := TUsersRepo.Create(LDb);
  LAdvs := TAdventuresRepo.Create(LDb);
  try
    LUid1 := LUsers.Insert('alice', 'h1');
    LUid2 := LUsers.Insert('bob', 'h2');
    LBid := InsertSeedBook(LDb, 'warlock', 'Jackson, Livingstone');
    LAdvs.Create(LUid1, LBid, 'alice-run');
    LAdvs.Create(LUid2, LBid, 'bob-run');

    LList := LAdvs.ListForUser(LUid1, []);
    Assert.AreEqual<Integer>(1, Length(LList));
    Assert.AreEqual('alice-run', LList[0].Title);
    Assert.AreEqual<Int64>(LUid1, LList[0].UserId);
  finally
    LAdvs.Free;
    LUsers.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TAdventuresRepoTests.ListForUserFiltersByStatus;
var
  LDb: string;
  LUsers: TUsersRepo;
  LAdvs: TAdventuresRepo;
  LUid, LBid, LActive, LCompleted: Int64;
  LList: TArray<TAdventure>;
begin
  LDb := TDbHelper.NewMemoryDb;
  LUsers := TUsersRepo.Create(LDb);
  LAdvs := TAdventuresRepo.Create(LDb);
  try
    LUid := LUsers.Insert('alice', 'h1');
    LBid := InsertSeedBook(LDb, 'warlock', 'Jackson, Livingstone');
    LActive := LAdvs.Create(LUid, LBid, 'active-run');
    LCompleted := LAdvs.Create(LUid, LBid, 'completed-run');
    LAdvs.UpdateStatus(LCompleted, 'completed');

    LList := LAdvs.ListForUser(LUid, ['active']);
    Assert.AreEqual<Integer>(1, Length(LList));
    Assert.AreEqual<Int64>(LActive, LList[0].Id);
    Assert.AreEqual('active', LList[0].Status);
  finally
    LAdvs.Free;
    LUsers.Free;
    TDbHelper.Drop(LDb);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventuresRepoTests);

end.
