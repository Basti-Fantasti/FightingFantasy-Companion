{*******************************************************************************
  Unit Name: Tests.Services.AdventureStateU.Inventory
  Purpose: DUnitX fixtures for TAdventureStateService.GetCurrentInventory folding

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exercises the real folding implementation of GetCurrentInventory: 'gain'
    adds, 'lose' subtracts, 'modify' sets an absolute value, events on
    soft-undone steps are excluded, and items with a final quantity of zero
    or less are dropped from the snapshot. Each test brackets fixture work
    with TDbHelper.NewMemoryDb / Drop so runs stay fully isolated.
*******************************************************************************}

unit Tests.Services.AdventureStateU.Inventory;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising inventory folding against SQLite.
  /// </summary>
  [TestFixture]
  TAdventureStateInventoryTests = class
  public
    [Test] procedure GainPlusGainSums;
    [Test] procedure GainMinusLoseSubtracts;
    [Test] procedure ModifyOverrides;
    [Test] procedure UndoneStepEventsExcluded;
    [Test] procedure ItemsWithZeroOrNegativeQtyExcluded;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Repositories.UsersU,
  Repositories.BooksU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.InventoryEventsU,
  Services.AdventureStateU,
  TestHelpers.DbU;

type
  TFixture = record
    Db: string;
    UserId: Int64;
    BookId: Int64;
    AdventureId: Int64;
  end;

/// <summary>
///   Creates user + custom book + adventure and returns the ids needed by the
///   inventory tests. The book is a custom book owned by the user so the
///   repository APIs available for tests can be used directly.
/// </summary>
function MakeFixture: TFixture;
var
  LUsers: TUsersRepo;
  LBooks: TBooksRepo;
  LAdvs: TAdventuresRepo;
begin
  Result.Db := TDbHelper.NewMemoryDb;
  LUsers := TUsersRepo.Create(Result.Db);
  LBooks := TBooksRepo.Create(Result.Db);
  LAdvs := TAdventuresRepo.Create(Result.Db);
  try
    Result.UserId      := LUsers.Insert('alice', 'hash');
    Result.BookId      := LBooks.UpsertCustomBook(Result.UserId,
      'test-book', 'Tester');
    Result.AdventureId := LAdvs.Create(Result.UserId, Result.BookId, 'run');
  finally
    LAdvs.Free;
    LBooks.Free;
    LUsers.Free;
  end;
end;

/// <summary>
///   Looks up an item by name in the snapshot list and returns its
///   quantity, or -1 when the item is absent.
/// </summary>
function FindQty(const AList: TList<TInventoryItem>;
  const AName: string): Integer;
var
  LItem: TInventoryItem;
begin
  for LItem in AList do
    if LItem.Name = AName then
      Exit(LItem.Quantity);
  Result := -1;
end;

procedure TAdventureStateInventoryTests.GainPlusGainSums;
var
  LFx: TFixture;
  LSteps: TStepsRepo;
  LEvents: TInventoryEventsRepo;
  LSvc: TAdventureStateService;
  LStep1Id, LStep2Id: Int64;
  LResult: TList<TInventoryItem>;
begin
  LFx := MakeFixture;
  LSteps := TStepsRepo.Create(LFx.Db);
  LEvents := TInventoryEventsRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStep1Id := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, True, False);
    LEvents.Insert(LStep1Id, 'gain', 'Sword', 1, '');
    LStep2Id := LSteps.Insert(LFx.AdventureId, 1, 2, '',
      False, True, False);
    LEvents.Insert(LStep2Id, 'gain', 'Sword', 1, '');

    LResult := LSvc.GetCurrentInventory(LFx.AdventureId);
    try
      Assert.AreEqual<Integer>(1, LResult.Count);
      Assert.AreEqual<Integer>(2, FindQty(LResult, 'Sword'));
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LEvents.Free;
    LSteps.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateInventoryTests.GainMinusLoseSubtracts;
var
  LFx: TFixture;
  LSteps: TStepsRepo;
  LEvents: TInventoryEventsRepo;
  LSvc: TAdventureStateService;
  LStep1Id, LStep2Id: Int64;
  LResult: TList<TInventoryItem>;
begin
  LFx := MakeFixture;
  LSteps := TStepsRepo.Create(LFx.Db);
  LEvents := TInventoryEventsRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStep1Id := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, True, False);
    LEvents.Insert(LStep1Id, 'gain', 'Gold', 5, '');
    LStep2Id := LSteps.Insert(LFx.AdventureId, 1, 2, '',
      False, True, False);
    LEvents.Insert(LStep2Id, 'lose', 'Gold', 2, '');

    LResult := LSvc.GetCurrentInventory(LFx.AdventureId);
    try
      Assert.AreEqual<Integer>(1, LResult.Count);
      Assert.AreEqual<Integer>(3, FindQty(LResult, 'Gold'));
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LEvents.Free;
    LSteps.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateInventoryTests.ModifyOverrides;
var
  LFx: TFixture;
  LSteps: TStepsRepo;
  LEvents: TInventoryEventsRepo;
  LSvc: TAdventureStateService;
  LStep1Id, LStep2Id: Int64;
  LResult: TList<TInventoryItem>;
begin
  LFx := MakeFixture;
  LSteps := TStepsRepo.Create(LFx.Db);
  LEvents := TInventoryEventsRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStep1Id := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, True, False);
    LEvents.Insert(LStep1Id, 'gain', 'Lantern Oil', 3, '');
    LStep2Id := LSteps.Insert(LFx.AdventureId, 1, 2, '',
      False, True, False);
    LEvents.Insert(LStep2Id, 'modify', 'Lantern Oil', 7, 'refilled');

    LResult := LSvc.GetCurrentInventory(LFx.AdventureId);
    try
      Assert.AreEqual<Integer>(1, LResult.Count);
      Assert.AreEqual<Integer>(7, FindQty(LResult, 'Lantern Oil'));
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LEvents.Free;
    LSteps.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateInventoryTests.UndoneStepEventsExcluded;
var
  LFx: TFixture;
  LSteps: TStepsRepo;
  LEvents: TInventoryEventsRepo;
  LSvc: TAdventureStateService;
  LStepId: Int64;
  LResult: TList<TInventoryItem>;
begin
  LFx := MakeFixture;
  LSteps := TStepsRepo.Create(LFx.Db);
  LEvents := TInventoryEventsRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStepId := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, True, False);
    LEvents.Insert(LStepId, 'gain', 'Sword', 1, '');
    LSteps.SetUndone(LStepId, True);

    LResult := LSvc.GetCurrentInventory(LFx.AdventureId);
    try
      Assert.AreEqual<Integer>(0, LResult.Count,
        'undone-step inventory events must not appear in the snapshot');
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LEvents.Free;
    LSteps.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateInventoryTests.ItemsWithZeroOrNegativeQtyExcluded;
var
  LFx: TFixture;
  LSteps: TStepsRepo;
  LEvents: TInventoryEventsRepo;
  LSvc: TAdventureStateService;
  LStep1Id, LStep2Id: Int64;
  LResult: TList<TInventoryItem>;
begin
  LFx := MakeFixture;
  LSteps := TStepsRepo.Create(LFx.Db);
  LEvents := TInventoryEventsRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStep1Id := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, True, False);
    LEvents.Insert(LStep1Id, 'gain', 'Sword', 1, '');
    LStep2Id := LSteps.Insert(LFx.AdventureId, 1, 2, '',
      False, True, False);
    LEvents.Insert(LStep2Id, 'lose', 'Sword', 1, '');

    LResult := LSvc.GetCurrentInventory(LFx.AdventureId);
    try
      Assert.AreEqual<Integer>(0, LResult.Count,
        'items at zero quantity are dropped from the snapshot');
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LEvents.Free;
    LSteps.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventureStateInventoryTests);

end.
