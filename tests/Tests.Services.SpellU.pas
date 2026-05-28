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
      LUserId := LUsers.Insert('alice','h');
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
      LUserId := LUsers.Insert('alice','h');
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
      LUserId := LUsers.Insert('alice','h');
      LAdvId := LAdv.Create(LUserId, LBookId, 'Run');
      LSpellId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      LAS.Insert(LAdvId, LSpellId, 0);
      LSetupId := LSteps.InsertSetup(LAdvId);
      LAdv.SetLastStepId(LAdvId, LSetupId); // only setup, no normal step yet

      LSvc := TSpellService.Create(LConn);
      try
        Assert.IsFalse(LSvc.Cast(LAdvId, LSpellId, LConsumedId, LErr));
        Assert.Contains(LErr, 'Sektion'); // German message containing "Sektion"
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
      LUserId := LUsers.Insert('alice','h');
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
