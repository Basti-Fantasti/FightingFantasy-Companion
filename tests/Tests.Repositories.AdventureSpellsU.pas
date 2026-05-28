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
    LUserId := LUsers.Insert('alice', 'hash');
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
      Assert.IsTrue(LId1 > 0);
      Assert.IsTrue(LId2 > LId1);
      LList := LRepo.ListByAdventure(LAdv);
      Assert.AreEqual<Integer>(2, Length(LList));
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
      Assert.AreEqual<Integer>(1, Length(LGroups));
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
