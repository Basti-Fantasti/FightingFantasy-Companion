{*******************************************************************************
  Unit Name: Tests.Services.AdventureStateU
  Purpose: DUnitX fixtures for TAdventureStateService.GetStatsHistory folding

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exercises the real folding implementation of GetStatsHistory: it must
    seed from stat_defs.default_value, replay non-undone stat_changes in
    chronological order so the last write wins, exclude changes from
    soft-undone steps (the default reasserts), and track multiple stat defs
    independently. Each test brackets fixture work with
    TDbHelper.NewMemoryDb / Drop so runs stay fully isolated.
*******************************************************************************}

unit Tests.Services.AdventureStateU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising TAdventureStateService against SQLite.
  /// </summary>
  [TestFixture]
  TAdventureStateServiceTests = class
  public
    [Test] procedure CurrentStatsReflectLastChange;
    [Test] procedure UndoneStepStatChangesExcluded;
    [Test] procedure MultipleStatDefsTrackedIndependently;
    [Test] procedure GetSpellSnapshot_GroupsAndLocalizesAvailableAndConsumed;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Repositories.UsersU,
  Repositories.BooksU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.StatChangesU,
  Repositories.SpellDefsU,
  Repositories.AdventureSpellsU,
  Models.SpellDefU,
  Models.AdventureSpellU,
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
///   GetStatsHistory tests. The book is created as a custom book owned by the
///   user so the repository APIs available for tests can be used directly.
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

procedure TAdventureStateServiceTests.CurrentStatsReflectLastChange;
var
  LFx: TFixture;
  LBooks: TBooksRepo;
  LSteps: TStepsRepo;
  LChanges: TStatChangesRepo;
  LSvc: TAdventureStateService;
  LStatDefId, LStepId: Int64;
  LResult: TList<TStatSnapshot>;
begin
  LFx := MakeFixture;
  LBooks := TBooksRepo.Create(LFx.Db);
  LSteps := TStepsRepo.Create(LFx.Db);
  LChanges := TStatChangesRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStatDefId := LBooks.UpsertStatDef(LFx.BookId, 0,
      'skill', 'integer', '12');
    LStepId := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, False, True);
    LChanges.Insert(LStepId, LStatDefId, '12', '9', 'combat');

    LResult := LSvc.GetStatsHistory(LFx.AdventureId, 'en', 'en');
    try
      Assert.AreEqual<Integer>(1, LResult.Count);
      Assert.AreEqual<Int64>(LStatDefId, LResult[0].StatDefId);
      Assert.AreEqual('9', LResult[0].Value);
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LChanges.Free;
    LSteps.Free;
    LBooks.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateServiceTests.UndoneStepStatChangesExcluded;
var
  LFx: TFixture;
  LBooks: TBooksRepo;
  LSteps: TStepsRepo;
  LChanges: TStatChangesRepo;
  LSvc: TAdventureStateService;
  LStatDefId, LStepId: Int64;
  LResult: TList<TStatSnapshot>;
begin
  LFx := MakeFixture;
  LBooks := TBooksRepo.Create(LFx.Db);
  LSteps := TStepsRepo.Create(LFx.Db);
  LChanges := TStatChangesRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LStatDefId := LBooks.UpsertStatDef(LFx.BookId, 0,
      'skill', 'integer', '12');
    LStepId := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, False, True);
    LChanges.Insert(LStepId, LStatDefId, '12', '9', 'combat');
    LSteps.SetUndone(LStepId, True);

    LResult := LSvc.GetStatsHistory(LFx.AdventureId, 'en', 'en');
    try
      Assert.AreEqual<Integer>(1, LResult.Count);
      Assert.AreEqual('12', LResult[0].Value,
        'undone step change is excluded so the default reasserts');
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LChanges.Free;
    LSteps.Free;
    LBooks.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateServiceTests.MultipleStatDefsTrackedIndependently;
var
  LFx: TFixture;
  LBooks: TBooksRepo;
  LSteps: TStepsRepo;
  LChanges: TStatChangesRepo;
  LSvc: TAdventureStateService;
  LSkillId, LStaminaId, LStep1Id, LStep2Id: Int64;
  LResult: TList<TStatSnapshot>;
  LSnap: TStatSnapshot;
  LSkillValue, LStaminaValue: string;
  LFoundSkill, LFoundStamina: Boolean;
begin
  LFx := MakeFixture;
  LBooks := TBooksRepo.Create(LFx.Db);
  LSteps := TStepsRepo.Create(LFx.Db);
  LChanges := TStatChangesRepo.Create(LFx.Db);
  LSvc := TAdventureStateService.Create(LFx.Db);
  try
    LSkillId := LBooks.UpsertStatDef(LFx.BookId, 0,
      'skill', 'integer', '12');
    LStaminaId := LBooks.UpsertStatDef(LFx.BookId, 1,
      'stamina', 'integer', '20');

    LStep1Id := LSteps.Insert(LFx.AdventureId, 0, 1, '',
      False, False, True);
    LChanges.Insert(LStep1Id, LSkillId, '12', '10', '');

    LStep2Id := LSteps.Insert(LFx.AdventureId, 1, 2, '',
      False, False, True);
    LChanges.Insert(LStep2Id, LStaminaId, '20', '18', '');

    LResult := LSvc.GetStatsHistory(LFx.AdventureId, 'en', 'en');
    try
      Assert.AreEqual<Integer>(2, LResult.Count);
      LFoundSkill := False;
      LFoundStamina := False;
      LSkillValue := '';
      LStaminaValue := '';
      for LSnap in LResult do
      begin
        if LSnap.StatDefId = LSkillId then
        begin
          LFoundSkill := True;
          LSkillValue := LSnap.Value;
        end
        else if LSnap.StatDefId = LStaminaId then
        begin
          LFoundStamina := True;
          LStaminaValue := LSnap.Value;
        end;
      end;
      Assert.IsTrue(LFoundSkill, 'skill snapshot missing');
      Assert.IsTrue(LFoundStamina, 'stamina snapshot missing');
      Assert.AreEqual('10', LSkillValue);
      Assert.AreEqual('18', LStaminaValue);
    finally
      LResult.Free;
    end;
  finally
    LSvc.Free;
    LChanges.Free;
    LSteps.Free;
    LBooks.Free;
    TDbHelper.Drop(LFx.Db);
  end;
end;

procedure TAdventureStateServiceTests.GetSpellSnapshot_GroupsAndLocalizesAvailableAndConsumed;
var
  LConn: string;
  LBooks: TBooksRepo; LUsers: TUsersRepo; LAdv: TAdventuresRepo;
  LSteps: TStepsRepo; LSpells: TSpellDefsRepo; LAS: TAdventureSpellsRepo;
  LBookId, LUserId, LAdvId, LStrengthId, LWeaknessId, LStepId: Int64;
  LTitles: TArray<TSpellDefTitle>;
  LSvc: TAdventureStateService;
  LSnapshot: TArray<TAdventureSpellGroup>;
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

      LStrengthId := LSpells.UpsertSpellDef(LBookId, 'strength', 0);
      SetLength(LTitles, 1);
      LTitles[0].SpellDefId := LStrengthId;
      LTitles[0].Lang := 'de';
      LTitles[0].DisplayName := 'Stärke';
      LTitles[0].Description := 'desc';
      LSpells.SetTitles(LStrengthId, LTitles);

      LWeaknessId := LSpells.UpsertSpellDef(LBookId, 'weakness', 1);
      LTitles[0].SpellDefId := LWeaknessId;
      LTitles[0].DisplayName := 'Schwäche';
      LSpells.SetTitles(LWeaknessId, LTitles);

      LAS.Insert(LAdvId, LStrengthId, 0);
      LAS.Insert(LAdvId, LStrengthId, 1);
      LAS.Insert(LAdvId, LWeaknessId, 2);
      LStepId := LSteps.Insert(LAdvId, 0, 47, '', False, False, False);
      LAS.ConsumeOldest(LAdvId, LStrengthId, LStepId);

      LSvc := TAdventureStateService.Create(LConn);
      try
        LSnapshot := LSvc.GetSpellSnapshot(LAdvId, 'de');
      finally
        LSvc.Free;
      end;

      Assert.AreEqual<Integer>(2, Length(LSnapshot));
      // Ordered by spell_defs.ord ASC
      Assert.AreEqual('Stärke', LSnapshot[0].DisplayName);
      Assert.AreEqual(1, LSnapshot[0].Available);
      Assert.AreEqual(1, LSnapshot[0].Consumed);
      Assert.AreEqual('Schwäche', LSnapshot[1].DisplayName);
      Assert.AreEqual(1, LSnapshot[1].Available);
      Assert.AreEqual(0, LSnapshot[1].Consumed);
    finally
      LAS.Free; LSpells.Free; LSteps.Free; LAdv.Free; LUsers.Free; LBooks.Free;
    end;
  finally
    TDbHelper.Drop(LConn);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAdventureStateServiceTests);

end.
