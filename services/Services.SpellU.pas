{*******************************************************************************
  Unit Name: Services.SpellU
  Purpose: Cast and undo spells for an adventure

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TSpellService coordinates spell casting against the adventure_spells
    repository. Casting consumes the oldest available instance of a spell
    definition for the adventure, attributing the consumption to the
    adventure's current step. The adventure must have advanced past its
    initial setup step before any spell can be cast. UndoForStep reverts
    every spell instance consumed at a given step, used when a step is
    rolled back.

  Dependencies:
    - Repositories.AdventuresU
    - Repositories.StepsU
    - Repositories.AdventureSpellsU
    - Models.AdventureU
    - Models.StepU
*******************************************************************************}

unit Services.SpellU;

interface

type
  /// <summary>
  ///   Service-layer wrapper for spell casting and undo operations.
  /// </summary>
  TSpellService = class
  private
    FConn: string;
  public
    /// <summary>
    ///   Stores the FireDAC connection definition name to use for repository
    ///   access.
    /// </summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Casts the oldest unconsumed instance of ASpellDefId for the
    ///   adventure. Sets AConsumedId to the consumed adventure_spells.id
    ///   (0 on failure) and AErrorMsg to a localized message on failure.
    ///   Returns True on success.
    /// </summary>
    function Cast(AAdventureId, ASpellDefId: Int64;
      out AConsumedId: Int64; out AErrorMsg: string): Boolean;

    /// <summary>Reverts every spell instance consumed at AStepId.</summary>
    procedure UndoForStep(AStepId: Int64);
  end;

implementation

uses
  System.SysUtils,
  Repositories.AdventuresU, Repositories.StepsU,
  Repositories.AdventureSpellsU,
  Models.AdventureU, Models.StepU;

resourcestring
  RS_SPELL_NEED_SECTION =
    'Erst eine Sektion betreten, dann zaubern.';
  RS_SPELL_NONE_AVAILABLE =
    'Kein Exemplar dieses Zaubers mehr verfügbar.';

constructor TSpellService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TSpellService.Cast(AAdventureId, ASpellDefId: Int64;
  out AConsumedId: Int64; out AErrorMsg: string): Boolean;
var
  LAdvRepo: TAdventuresRepo;
  LStepsRepo: TStepsRepo;
  LASRepo: TAdventureSpellsRepo;
  LAdv: TAdventure;
  LStep: TStep;
begin
  Result := False;
  AConsumedId := 0;
  AErrorMsg := '';
  LAdvRepo := TAdventuresRepo.Create(FConn);
  LStepsRepo := TStepsRepo.Create(FConn);
  LASRepo := TAdventureSpellsRepo.Create(FConn);
  try
    LAdv := LAdvRepo.GetById(AAdventureId);
    if LAdv.LastStepId <= 0 then
    begin
      AErrorMsg := RS_SPELL_NEED_SECTION;
      Exit;
    end;
    // Confirm last_step_id points at a normal step, not setup.
    LStep := LStepsRepo.GetById(LAdv.LastStepId);
    if LStep.Kind <> 'normal' then
    begin
      AErrorMsg := RS_SPELL_NEED_SECTION;
      Exit;
    end;
    AConsumedId := LASRepo.ConsumeOldest(
      AAdventureId, ASpellDefId, LAdv.LastStepId);
    if AConsumedId = 0 then
    begin
      AErrorMsg := RS_SPELL_NONE_AVAILABLE;
      Exit;
    end;
    Result := True;
  finally
    LASRepo.Free;
    LStepsRepo.Free;
    LAdvRepo.Free;
  end;
end;

procedure TSpellService.UndoForStep(AStepId: Int64);
var
  LASRepo: TAdventureSpellsRepo;
begin
  LASRepo := TAdventureSpellsRepo.Create(FConn);
  try
    LASRepo.RevertForStep(AStepId);
  finally
    LASRepo.Free;
  end;
end;

end.
