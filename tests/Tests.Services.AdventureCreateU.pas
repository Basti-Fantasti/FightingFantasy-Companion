{*******************************************************************************
  Unit Name: Tests.Services.AdventureCreateU
  Purpose: DUnitX tests for TAdventureCreateService

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Verifies the transactional adventure-create orchestrator: that it
    persists adventure + setup step + gear + initial stats + spells in
    the happy path, rejects requests whose spell picks exceed the budget,
    and tolerates books that lack any gear or spell seed data.
*******************************************************************************}

unit Tests.Services.AdventureCreateU;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAdventureCreateServiceTests = class
  public
    [Test] procedure Create_PersistsAdventureSetupStepGearStatsAndSpells;
    [Test] procedure Create_RejectsWhenSpellPicksExceedBudget;
    [Test] procedure Create_SkipsGearAndSpellsForBooksWithoutSeed;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  TestHelpers.DbU,
  Repositories.BooksU,
  Repositories.UsersU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.SpellDefsU,
  Repositories.AdventureSpellsU,
  Repositories.BookStartingItemsU,
  Repositories.InventoryEventsU,
  Repositories.StatChangesU,
  Services.AdventureCreateU,
  Models.AdventureSpellU,
  Models.InventoryEventU,
  Models.StartingItemU,
  Models.SpellDefU;

/// <summary>Seeds a Citadel-style book with a magic=3 stat, a sword gear
/// row, and two spell defs (strength, weakness). Returns the freshly
/// created identifiers via out parameters.</summary>
procedure SeedCitadel(const AConn: string;
  out ABookId, AStrengthId, AWeaknessId, AStatMagicId: Int64);
var
  LBooks: TBooksRepo;
  LSpells: TSpellDefsRepo;
  LItems: TBookStartingItemsRepo;
  LItemId: Int64;
  LSwordTitles: TArray<TStartingItemTitle>;
  LTitles: TArray<TSpellDefTitle>;
begin
  LBooks := TBooksRepo.Create(AConn);
  LSpells := TSpellDefsRepo.Create(AConn);
  LItems := TBookStartingItemsRepo.Create(AConn);
  try
    ABookId := LBooks.UpsertSeedBook('citadel', 'SJ');
    AStatMagicId := LBooks.UpsertStatDef(ABookId, 0, 'magic',
      'integer', '3');
    LItemId := LItems.Upsert(ABookId, 'sword', 0, 1);
    SetLength(LSwordTitles, 1);
    LSwordTitles[0].StartingItemId := LItemId;
    LSwordTitles[0].Lang := 'de';
    LSwordTitles[0].DisplayName := 'Schwert';
    LItems.SetTitles(LItemId, LSwordTitles);
    AStrengthId := LSpells.UpsertSpellDef(ABookId, 'strength', 0);
    AWeaknessId := LSpells.UpsertSpellDef(ABookId, 'weakness', 1);
    SetLength(LTitles, 1);
    LTitles[0].SpellDefId := AStrengthId;
    LTitles[0].Lang := 'de';
    LTitles[0].DisplayName := 'Stärke';
    LTitles[0].Description := '';
    LSpells.SetTitles(AStrengthId, LTitles);
    LTitles[0].SpellDefId := AWeaknessId;
    LTitles[0].DisplayName := 'Schwäche';
    LSpells.SetTitles(AWeaknessId, LTitles);
  finally
    LItems.Free;
    LSpells.Free;
    LBooks.Free;
  end;
end;

procedure TAdventureCreateServiceTests.
  Create_PersistsAdventureSetupStepGearStatsAndSpells;
var
  LConn: string;
  LUsers: TUsersRepo;
  LSteps: TStepsRepo;
  LAS: TAdventureSpellsRepo;
  LInv: TInventoryEventsRepo;
  LBookId, LStrengthId, LWeaknessId, LStatMagicId: Int64;
  LUserId, LNewAdvId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
  LSetupId: Int64;
  LInvList: TArray<TInventoryEvent>;
  LGroups: TArray<TAdventureSpellGroup>;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    SeedCitadel(LConn, LBookId, LStrengthId, LWeaknessId, LStatMagicId);
    LUsers := TUsersRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    LAS := TAdventureSpellsRepo.Create(LConn);
    LInv := TInventoryEventsRepo.Create(LConn);
    try
      LUserId := LUsers.Insert('alice', 'h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId;
        LReq.BookId := LBookId;
        LReq.Title := 'Run 1';
        LReq.Lang := 'de';
        SetLength(LReq.StatValues, 1);
        LReq.StatValues[0].StatDefId := LStatMagicId;
        LReq.StatValues[0].Value := '3';
        SetLength(LReq.GearRows, 1);
        LReq.GearRows[0].Slug := 'sword';
        LReq.GearRows[0].Keep := True;
        LReq.GearRows[0].Name := 'Schwert';
        LReq.GearRows[0].Quantity := 1;
        // pick 2x strength + 1x weakness (sum = 3 = magic)
        SetLength(LReq.SpellPicks, 2);
        LReq.SpellPicks[0].SpellDefId := LStrengthId;
        LReq.SpellPicks[0].Count := 2;
        LReq.SpellPicks[1].SpellDefId := LWeaknessId;
        LReq.SpellPicks[1].Count := 1;
        LReq.SpellBudgetStatDefId := LStatMagicId;

        LNewAdvId := LSvc.CreateAdventure(LReq);
      finally
        LSvc.Free;
      end;

      Assert.IsTrue(LNewAdvId > 0);
      LSetupId := LSteps.ListByAdventureAsc(LNewAdvId, False)[0].Id;
      Assert.AreEqual('setup', LSteps.GetById(LSetupId).Kind);
      LInvList := LInv.ListByAdventure(LNewAdvId, True);
      Assert.AreEqual(NativeInt(1), Length(LInvList));
      Assert.AreEqual('Schwert', LInvList[0].ItemName);
      Assert.AreEqual(LSetupId, LInvList[0].StepId);
      LGroups := LAS.ListGroups(LNewAdvId);
      Assert.AreEqual(NativeInt(2), Length(LGroups));
    finally
      LInv.Free;
      LAS.Free;
      LSteps.Free;
      LUsers.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureCreateServiceTests.
  Create_RejectsWhenSpellPicksExceedBudget;
var
  LConn: string;
  LUsers: TUsersRepo;
  LBookId, LStrengthId, LWeaknessId, LStatMagicId, LUserId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    SeedCitadel(LConn, LBookId, LStrengthId, LWeaknessId, LStatMagicId);
    LUsers := TUsersRepo.Create(LConn);
    try
      LUserId := LUsers.Insert('alice', 'h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId;
        LReq.BookId := LBookId;
        LReq.Title := 'Run';
        LReq.Lang := 'de';
        SetLength(LReq.StatValues, 1);
        LReq.StatValues[0].StatDefId := LStatMagicId;
        LReq.StatValues[0].Value := '3';
        SetLength(LReq.SpellPicks, 1);
        LReq.SpellPicks[0].SpellDefId := LStrengthId;
        LReq.SpellPicks[0].Count := 99; // exceeds budget 3
        LReq.SpellBudgetStatDefId := LStatMagicId;
        Assert.WillRaise(
          procedure
          begin
            LSvc.CreateAdventure(LReq);
          end,
          EAdventureCreateError);
      finally
        LSvc.Free;
      end;
    finally
      LUsers.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

procedure TAdventureCreateServiceTests.
  Create_SkipsGearAndSpellsForBooksWithoutSeed;
var
  LConn: string;
  LBooks: TBooksRepo;
  LUsers: TUsersRepo;
  LSteps: TStepsRepo;
  LBookId, LUserId, LNewAdvId, LSetupId: Int64;
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
begin
  LConn := TDbHelper.NewMemoryDb;
  try
    LBooks := TBooksRepo.Create(LConn);
    LUsers := TUsersRepo.Create(LConn);
    LSteps := TStepsRepo.Create(LConn);
    try
      LBookId := LBooks.UpsertSeedBook('warlock', 'IL');
      LUserId := LUsers.Insert('alice', 'h');
      LSvc := TAdventureCreateService.Create(LConn);
      try
        LReq := Default(TAdventureCreateRequest);
        LReq.UserId := LUserId;
        LReq.BookId := LBookId;
        LReq.Title := 'Run';
        LReq.Lang := 'de';
        LNewAdvId := LSvc.CreateAdventure(LReq);
      finally
        LSvc.Free;
      end;
      LSetupId := LSteps.ListByAdventureAsc(LNewAdvId, False)[0].Id;
      Assert.AreEqual('setup', LSteps.GetById(LSetupId).Kind);
    finally
      LSteps.Free;
      LUsers.Free;
      LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventureCreateServiceTests);

end.
