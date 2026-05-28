{*******************************************************************************
  Unit Name: Services.AdventureCreateU
  Purpose: Transactional creation of a new adventure with setup data

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TAdventureCreateService orchestrates the creation of a new adventure run.
    It validates the request (notably that selected spell picks do not exceed
    the budget of a designated stat), then persists the adventure row, a
    seq=1 setup step, gear inventory events, initial stat changes, and the
    chosen spell instances. The setup step is always recorded so that later
    operations have a well-known anchor to attribute initial state to.

    Each repository call manages its own connection and transaction. If a
    failure occurs partway through, the user is left with a partial
    adventure that can be removed from the adventure list; v1 does not wrap
    the whole sequence in a single transaction.

  Dependencies:
    - Repositories.AdventuresU
    - Repositories.StepsU
    - Repositories.InventoryEventsU
    - Repositories.StatChangesU
    - Repositories.AdventureSpellsU
*******************************************************************************}

unit Services.AdventureCreateU;

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when the adventure-create request fails validation,
  /// for example when the requested spell picks exceed the available
  /// budget.</summary>
  EAdventureCreateError = class(Exception);

  /// <summary>Initial value for one stat def at adventure setup time.</summary>
  TAdventureCreateStatValue = record
    StatDefId: Int64;
    Value: string;
  end;

  /// <summary>One row of the gear-selection form. When Keep is True the
  /// item becomes an initial inventory event on the setup step.</summary>
  TAdventureCreateGearRow = record
    Slug: string;
    Keep: Boolean;
    Name: string;
    Quantity: Integer;
  end;

  /// <summary>One row of the spell-selection form. Count copies of the
  /// chosen spell def are inserted as adventure_spells instances.</summary>
  TAdventureCreateSpellPick = record
    SpellDefId: Int64;
    Count: Integer;
  end;

  /// <summary>All inputs required to create an adventure run.</summary>
  TAdventureCreateRequest = record
    UserId, BookId: Int64;
    Title: string;
    Lang: string;
    StatValues: TArray<TAdventureCreateStatValue>;
    GearRows: TArray<TAdventureCreateGearRow>;
    SpellPicks: TArray<TAdventureCreateSpellPick>;
    /// <summary>StatDef id of the stat that bounds the spell budget; 0
    /// when the book has no spells.</summary>
    SpellBudgetStatDefId: Int64;
  end;

  /// <summary>Service-layer orchestrator for new adventure runs.</summary>
  TAdventureCreateService = class
  private
    FConn: string;
  public
    /// <summary>Stores the FireDAC connection definition name used for
    /// all repository operations.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>Validates the request, then persists adventure + setup
    /// step + gear inventory events + initial stat changes + spell
    /// instances. Sets adventures.last_step_id to the setup step's id.
    /// Returns the new adventure id. Raises EAdventureCreateError on
    /// validation failure. Each repository call manages its own
    /// transaction; failures partway through leave a partially-created
    /// adventure that the user can clean up by deleting from the
    /// adventure list (acceptable for v1).</summary>
    function CreateAdventure(const ARequest: TAdventureCreateRequest): Int64;
  end;

implementation

uses
  System.Math,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.InventoryEventsU,
  Repositories.StatChangesU,
  Repositories.AdventureSpellsU;

resourcestring
  RS_ERR_SPELL_BUDGET =
    'Die Zauberauswahl überschreitet das verfügbare Budget.';

constructor TAdventureCreateService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

/// <summary>Finds the request-provided value for a given stat def id.
/// Returns False when the caller did not supply one.</summary>
function FindStatValue(const AStats: TArray<TAdventureCreateStatValue>;
  AStatDefId: Int64; out AValue: string): Boolean;
var
  LS: TAdventureCreateStatValue;
begin
  for LS in AStats do
    if LS.StatDefId = AStatDefId then
    begin
      AValue := LS.Value;
      Exit(True);
    end;
  Result := False;
end;

function TAdventureCreateService.CreateAdventure(
  const ARequest: TAdventureCreateRequest): Int64;
var
  LAdvRepo: TAdventuresRepo;
  LSteps: TStepsRepo;
  LInv: TInventoryEventsRepo;
  LStat: TStatChangesRepo;
  LAS: TAdventureSpellsRepo;
  LSetupId: Int64;
  LGear: TAdventureCreateGearRow;
  LStatVal: TAdventureCreateStatValue;
  LPick: TAdventureCreateSpellPick;
  LBudgetStr: string;
  LBudget, LTotal, I: Integer;
  LInstanceOrd: Integer;
begin
  // Validate spell budget when the book defines a bounding stat.
  if ARequest.SpellBudgetStatDefId > 0 then
  begin
    if not FindStatValue(ARequest.StatValues,
      ARequest.SpellBudgetStatDefId, LBudgetStr) then
      LBudget := 0
    else
      LBudget := StrToIntDef(LBudgetStr, 0);
    LTotal := 0;
    for LPick in ARequest.SpellPicks do
      Inc(LTotal, LPick.Count);
    if LTotal > LBudget then
      raise EAdventureCreateError.Create(RS_ERR_SPELL_BUDGET);
  end;

  LAdvRepo := TAdventuresRepo.Create(FConn);
  LSteps := TStepsRepo.Create(FConn);
  LInv := TInventoryEventsRepo.Create(FConn);
  LStat := TStatChangesRepo.Create(FConn);
  LAS := TAdventureSpellsRepo.Create(FConn);
  try
    Result := LAdvRepo.Create(ARequest.UserId, ARequest.BookId,
      ARequest.Title);
    LSetupId := LSteps.InsertSetup(Result);

    // Gear -> inventory_events on the setup step
    for LGear in ARequest.GearRows do
      if LGear.Keep and (Trim(LGear.Name) <> '') then
        LInv.Insert(LSetupId, 'gain', LGear.Name,
          Max(1, LGear.Quantity), '');

    // Initial stat values -> one stat_change row each (old NULL, new=value)
    for LStatVal in ARequest.StatValues do
      if Trim(LStatVal.Value) <> '' then
        LStat.Insert(LSetupId, LStatVal.StatDefId, '',
          LStatVal.Value, '');

    // Spell instances: insert Count copies of each picked spell def.
    LInstanceOrd := 0;
    for LPick in ARequest.SpellPicks do
      for I := 1 to LPick.Count do
      begin
        LAS.Insert(Result, LPick.SpellDefId, LInstanceOrd);
        Inc(LInstanceOrd);
      end;

    LAdvRepo.SetLastStepId(Result, LSetupId);
  finally
    LAS.Free;
    LStat.Free;
    LInv.Free;
    LSteps.Free;
    LAdvRepo.Free;
  end;
end;

end.
