{*******************************************************************************
  Unit Name: Tests.Services.GraphBuilderU
  Purpose: DUnitX fixtures for TGraphBuilder folding of steps into graph.json

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exercises TGraphBuilder.Build against synthetic step histories: a linear
    walk, a revisit that should bump the visits counter, exclusion of a
    soft-undone tail step (and re-derivation of "current"), and the empty
    adventure short-circuit. Each test brackets fixture work with
    TDbHelper.NewMemoryDb / Drop so runs stay fully isolated.
*******************************************************************************}

unit Tests.Services.GraphBuilderU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising TGraphBuilder against SQLite.
  /// </summary>
  [TestFixture]
  TGraphBuilderTests = class
  public
    [Test] procedure LinearAdventureProducesNodesAndEdges;
    [Test] procedure RevisitIncrementsVisits;
    [Test] procedure UndoneStepExcluded;
    [Test] procedure EmptyAdventureReturnsEmptyShape;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  JsonDataObjects,
  FireDAC.Comp.Client,
  Models.StepU,
  Repositories.UsersU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Services.GraphBuilderU,
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

/// <summary>
///   Finds the node object in an arr that has section=ASection. Returns
///   nil when no such node exists so tests can assert absence.
/// </summary>
function FindNode(AArr: TJsonArray; ASection: Integer): TJsonObject;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to AArr.Count - 1 do
    if AArr.O[I].I['section'] = ASection then
      Exit(AArr.O[I]);
end;

procedure TGraphBuilderTests.LinearAdventureProducesNodesAndEdges;
var
  LDb: string;
  LSteps: TStepsRepo;
  LBuilder: TGraphBuilder;
  LAid: Int64;
  LPayload: TJsonObject;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  LBuilder := TGraphBuilder.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    // Linear walk: NULL->§1 (first step), §1->§42, §42->§187.
    LSteps.Insert(LAid, 0,  1,   '', False, False, False);
    LSteps.Insert(LAid, 1,  42,  '', False, False, False);
    LSteps.Insert(LAid, 42, 187, '', False, False, False);

    LPayload := LBuilder.Build(LAid);
    try
      Assert.AreEqual<Integer>(187, LPayload.I['current']);
      Assert.AreEqual<Integer>(3, LPayload.A['nodes'].Count);
      Assert.AreEqual<Integer>(2, LPayload.A['edges'].Count);
      // First node added is §1 (the from_section=NULL start), no edge for it.
      Assert.IsNotNull(FindNode(LPayload.A['nodes'], 1));
      Assert.IsNotNull(FindNode(LPayload.A['nodes'], 42));
      Assert.IsNotNull(FindNode(LPayload.A['nodes'], 187));
    finally
      LPayload.Free;
    end;
  finally
    LBuilder.Free;
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TGraphBuilderTests.RevisitIncrementsVisits;
var
  LDb: string;
  LSteps: TStepsRepo;
  LBuilder: TGraphBuilder;
  LAid: Int64;
  LPayload: TJsonObject;
  LNode42: TJsonObject;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  LBuilder := TGraphBuilder.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    // §1, §42, §187, back to §42.
    LSteps.Insert(LAid, 0,   1,   '', False, False, False);
    LSteps.Insert(LAid, 1,   42,  '', False, False, False);
    LSteps.Insert(LAid, 42,  187, '', False, False, False);
    LSteps.Insert(LAid, 187, 42,  '', False, False, False);

    LPayload := LBuilder.Build(LAid);
    try
      Assert.AreEqual<Integer>(42, LPayload.I['current']);
      Assert.AreEqual<Integer>(3, LPayload.A['nodes'].Count);
      Assert.AreEqual<Integer>(3, LPayload.A['edges'].Count);
      LNode42 := FindNode(LPayload.A['nodes'], 42);
      Assert.IsNotNull(LNode42, 'section 42 node should exist');
      // §42 is reached twice: once via 1->42, once via 187->42.
      Assert.AreEqual<Integer>(2, LNode42.I['visits'],
        'section 42 visits = arrivals (2)');
    finally
      LPayload.Free;
    end;
  finally
    LBuilder.Free;
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TGraphBuilderTests.UndoneStepExcluded;
var
  LDb: string;
  LSteps: TStepsRepo;
  LBuilder: TGraphBuilder;
  LAid, LLastId: Int64;
  LPayload: TJsonObject;
  LNode42: TJsonObject;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSteps := TStepsRepo.Create(LDb);
  LBuilder := TGraphBuilder.Create(LDb);
  try
    MakeAdventure(LDb, LAid);
    LSteps.Insert(LAid, 0,   1,   '', False, False, False);
    LSteps.Insert(LAid, 1,   42,  '', False, False, False);
    LSteps.Insert(LAid, 42,  187, '', False, False, False);
    LLastId := LSteps.Insert(LAid, 187, 42, '', False, False, False);
    // Soft-undo the 187->42 tail step. The graph builder derives "current"
    // from the last surviving step, so it should fall back to §187.
    LSteps.SetUndone(LLastId, True);

    LPayload := LBuilder.Build(LAid);
    try
      Assert.AreEqual<Integer>(187, LPayload.I['current'],
        'current re-derives from last non-undone step.to_section');
      Assert.AreEqual<Integer>(3, LPayload.A['nodes'].Count);
      Assert.AreEqual<Integer>(2, LPayload.A['edges'].Count);
      LNode42 := FindNode(LPayload.A['nodes'], 42);
      Assert.IsNotNull(LNode42, 'section 42 node should exist');
      // Without the undone 187->42 step, §42 is only reached once (1->42).
      Assert.AreEqual<Integer>(1, LNode42.I['visits'],
        'section 42 visits without the undone revisit');
    finally
      LPayload.Free;
    end;
  finally
    LBuilder.Free;
    LSteps.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TGraphBuilderTests.EmptyAdventureReturnsEmptyShape;
var
  LDb: string;
  LBuilder: TGraphBuilder;
  LAid: Int64;
  LPayload: TJsonObject;
begin
  LDb := TDbHelper.NewMemoryDb;
  LBuilder := TGraphBuilder.Create(LDb);
  try
    MakeAdventure(LDb, LAid);

    LPayload := LBuilder.Build(LAid);
    try
      Assert.AreEqual<Integer>(0, LPayload.I['current']);
      Assert.AreEqual<Integer>(0, LPayload.A['nodes'].Count);
      Assert.AreEqual<Integer>(0, LPayload.A['edges'].Count);
    finally
      LPayload.Free;
    end;
  finally
    LBuilder.Free;
    TDbHelper.Drop(LDb);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGraphBuilderTests);

end.
