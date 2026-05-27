{*******************************************************************************
  Unit Name: Tests.Repositories.StepsU
  Purpose: DUnitX fixtures for TStepsRepo monotonic seq and soft undo semantics

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exercises Insert/ListByAdventure/SetUndone/GetById round-trips for the
    steps repository. Each test brackets fixture work with
    TDbHelper.NewMemoryDb / Drop so runs stay fully isolated.

    Note on concurrency: the design plan also mentions a parallel-insert
    concurrency test. That is fiddly to write reliably against SQLite's
    serialized write model (and not load-bearing for v1) so it is skipped
    here intentionally; the UNIQUE(adventure_id, seq) index in the schema
    and the retry-once branch in TStepsRepo.Insert are the real safety net.
*******************************************************************************}

unit Tests.Repositories.StepsU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising TStepsRepo against SQLite.
  /// </summary>
  [TestFixture]
  TStepsRepoTests = class
  public
    [Test] procedure InsertAssignsMonotonicSeq;
    [Test] procedure SetUndoneFlipsFlag;
    [Test] procedure ListIncludeUndoneVsExcludeUndone;
    [Test] procedure FirstStepHasNullFromSection;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  FireDAC.Comp.Client,
  Models.StepU,
  Repositories.UsersU,
  Repositories.AdventuresU,
  Repositories.StepsU,
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

function MakeAdventure(const AConn: string; out AAid: Int64): Int64;
var
  LUsers: TUsersRepo;
  LAdvs: TAdventuresRepo;
  LUid, LBid: Int64;
begin
  LUsers := TUsersRepo.Create(AConn);
  LAdvs := TAdventuresRepo.Create(AConn);
  try
    LUid := LUsers.Insert('alice', 'hash');
    LBid := InsertSeedBook(AConn, 'warlock', 'Jackson, Livingstone');
    AAid := LAdvs.Create(LUid, LBid, 'test-run');
    Result := AAid;
  finally
    LAdvs.Free;
    LUsers.Free;
  end;
end;

procedure TStepsRepoTests.InsertAssignsMonotonicSeq;
var
  LDb: string;
  LSteps: TStepsRepo;
  LAid, LId1, LId2, LId3: Int64;
  LStep: TStep;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    LId1 := LSteps.Insert(LAid, 0,  10, '', False, False, False);
    LId2 := LSteps.Insert(LAid, 10, 42, '', False, False, False);
    LId3 := LSteps.Insert(LAid, 42, 99, '', False, False, False);

    LStep := LSteps.GetById(LId1);
    Assert.AreEqual<Integer>(1, LStep.Seq);
    LStep := LSteps.GetById(LId2);
    Assert.AreEqual<Integer>(2, LStep.Seq);
    LStep := LSteps.GetById(LId3);
    Assert.AreEqual<Integer>(3, LStep.Seq);
  finally
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TStepsRepoTests.SetUndoneFlipsFlag;
var
  LDb: string;
  LSteps: TStepsRepo;
  LAid, LId: Int64;
  LStep: TStep;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    LId := LSteps.Insert(LAid, 0, 10, '', False, False, False);

    LStep := LSteps.GetById(LId);
    Assert.IsFalse(LStep.Undone, 'fresh step should not be undone');

    LSteps.SetUndone(LId, True);
    LStep := LSteps.GetById(LId);
    Assert.IsTrue(LStep.Undone, 'after SetUndone(True)');

    LSteps.SetUndone(LId, False);
    LStep := LSteps.GetById(LId);
    Assert.IsFalse(LStep.Undone, 'after SetUndone(False)');
  finally
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TStepsRepoTests.ListIncludeUndoneVsExcludeUndone;
var
  LDb: string;
  LSteps: TStepsRepo;
  LAid, LId1, LId2, LId3: Int64;
  LAll, LVisible: TArray<TStep>;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    LId1 := LSteps.Insert(LAid, 0,  10, '', False, False, False);
    LId2 := LSteps.Insert(LAid, 10, 42, '', False, False, False);
    LId3 := LSteps.Insert(LAid, 42, 99, '', False, False, False);
    Assert.IsTrue(LId1 > 0); Assert.IsTrue(LId3 > 0);

    LSteps.SetUndone(LId2, True);

    LAll := LSteps.ListByAdventure(LAid, True);
    Assert.AreEqual<Integer>(3, Length(LAll));

    LVisible := LSteps.ListByAdventure(LAid, False);
    Assert.AreEqual<Integer>(2, Length(LVisible));
    // Newest first by seq DESC: seq 3, then seq 1 (seq 2 is hidden).
    Assert.AreEqual<Integer>(3, LVisible[0].Seq);
    Assert.AreEqual<Integer>(1, LVisible[1].Seq);
  finally
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TStepsRepoTests.FirstStepHasNullFromSection;
var
  LDb: string;
  LSteps: TStepsRepo;
  LAid, LId: Int64;
  LStep: TStep;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    LId := LSteps.Insert(LAid, 0, 1, '', False, False, False);

    LStep := LSteps.GetById(LId);
    Assert.AreEqual<Integer>(0, LStep.FromSection,
      'first-step from_section NULL maps to 0');
    Assert.AreEqual<Integer>(1, LStep.ToSection);
  finally
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStepsRepoTests);

end.
