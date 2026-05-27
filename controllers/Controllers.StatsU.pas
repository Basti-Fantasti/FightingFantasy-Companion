{*******************************************************************************
  Unit Name: Controllers.StatsU
  Purpose: HTTP controller for the touch-friendly stat editor modal

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TStatsController, mounted under /adventures/:adv_id/stats. Three
    actions back the value-edit interaction surfaced by the stats panel on
    the play view:

      GET  /adventures/:id/stats/:sd/modal   - GetModal     (open editor)
      POST /adventures/:id/stats/preview     - PostPreview  (re-render delta)
      POST /adventures/:id/stats             - PostCommit   (persist change)

    GetModal resolves the current value of the requested stat via
    TAdventureStateService.GetStatsHistory and renders _value_modal.html with
    the working value seeded to the current value and the delta display at
    "±0".

    PostPreview is stateless and intentionally avoids any database access:
    the client posts the previous working value, the original value, and the
    delta to apply. We compute the new working value, recompute the delta
    display from (new_working - original), and re-render the same partial.
    The original value rides through every round-trip as a hidden form field
    so the page never needs to re-query the database while the user pokes at
    +/- buttons.

    PostCommit verifies ownership and optimistic concurrency (the form posts
    the adventure's last_step_id at render time). If no step has been logged
    yet (last_step_id = 0) the request is rejected with an inline Bulma
    is-danger fragment carrying the flash_no_current_step l10n string — stat
    changes are always attached to a step. Otherwise a stat_changes row is
    inserted against the current step, the step's flag_stat marker is set
    so the timeline icon reflects the mutation, and the response is the
    refreshed _stats_panel.html fragment together with an HX-Trigger that
    closes the modal and refreshes the graph tab.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, L10n)
    - Repositories.AdventuresU, Repositories.StepsU, Repositories.StatChangesU
    - Services.AdventureStateU
*******************************************************************************}

unit Controllers.StatsU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Models.AdventureU,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller backing the in-place stat editor on the play view. All
  ///   three actions verify the adventure belongs to the current user and
  ///   return 404 on mismatch to avoid leaking adventure ids.
  /// </summary>
  [MVCPath('/adventures/($AdvId)/stats')]
  TStatsController = class(TBaseController)
  strict private
    /// <summary>
    ///   Loads the adventure and verifies it belongs to the current user.
    ///   On miss writes a 404 response and returns False; the caller must
    ///   Exit without touching the response further.
    /// </summary>
    function TryLoadOwnedAdventure(AAdvId: Int64;
      out AAdv: TAdventure): Boolean;
  public
    /// <summary>
    ///   Returns the value-edit modal fragment seeded with the current
    ///   value of the requested stat. Renders _value_modal.html.
    /// </summary>
    [MVCPath('/($StatDefId)/modal')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetModal(AdvId, StatDefId: Int64);

    /// <summary>
    ///   Stateless re-render of the modal with an updated working value
    ///   and delta display. Computes new_working = working + delta and
    ///   delta_display from (new_working - original).
    /// </summary>
    [MVCPath('/preview')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostPreview(AdvId: Int64;
      [MVCFromContentField('stat_def_id', '')] AStatDefIdRaw: string;
      [MVCFromContentField('original', '')] AOriginalRaw: string;
      [MVCFromContentField('working', '')] AWorkingRaw: string;
      [MVCFromContentField('delta', '0')] ADeltaRaw: string;
      [MVCFromContentField('reason', '')] AReason: string);

    /// <summary>
    ///   Persists a stat change against the current step, sets the step's
    ///   flag_stat marker, and returns the refreshed stats panel fragment
    ///   together with an HX-Trigger that closes the modal and refreshes
    ///   the graph tab.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostCommit(AdvId: Int64;
      [MVCFromContentField('stat_def_id', '')] AStatDefIdRaw: string;
      [MVCFromContentField('working', '')] AWorkingRaw: string;
      [MVCFromContentField('reason', '')] AReason: string;
      [MVCFromContentField('last_step_id', '')] ALastStepRaw: string);
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  JsonDataObjects,
  AppConfigU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.StatChangesU,
  Services.AdventureStateU;

const
  CMainConnection = 'FFMain';
  CTriggerCloseAndGraph = '{"close-modal":{},"graph-changed":{}}';

resourcestring
  SAdventureGone = 'Adventure not found.';
  SStatGone      = 'Stat not found.';

/// <summary>
///   Formats a signed integer delta as "+N", "-N", or "±0" for display in
///   the modal's "Δ ..." hint line. The plus sign uses ASCII '+' but the
///   zero case uses the proper plus-minus sign for visual symmetry.
/// </summary>
function FormatDelta(ADelta: Integer): string;
begin
  if ADelta = 0 then
    Result := #$00B1 + '0'   // ±0
  else if ADelta > 0 then
    Result := '+' + IntToStr(ADelta)
  else
    Result := IntToStr(ADelta);
end;

{ TStatsController }

function TStatsController.TryLoadOwnedAdventure(AAdvId: Int64;
  out AAdv: TAdventure): Boolean;
var
  LRepo: TAdventuresRepo;
begin
  Result := False;
  LRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LRepo.TryGetById(AAdvId, AAdv) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
    if AAdv.UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
  finally
    LRepo.Free;
  end;
  Result := True;
end;

procedure TStatsController.GetModal(AdvId, StatDefId: Int64);
var
  LAdv: TAdventure;
  LStateSvc: TAdventureStateService;
  LStatList: TList<TStatSnapshot>;
  LStat: TStatSnapshot;
  LFound: Boolean;
  LCurrentValue, LDisplayName: string;
  LCurrentLang, LDefaultLang: string;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  LCurrentLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  LFound := False;
  LCurrentValue := '';
  LDisplayName := '';
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LStatList := LStateSvc.GetStatsHistory(LAdv.Id, LCurrentLang, LDefaultLang);
    try
      for LStat in LStatList do
        if LStat.StatDefId = StatDefId then
        begin
          LCurrentValue := LStat.Value;
          LDisplayName  := LStat.DisplayName;
          LFound := True;
          Break;
        end;
    finally
      LStatList.Free;
    end;
  finally
    LStateSvc.Free;
  end;

  if not LFound then
  begin
    Context.Response.StatusCode := HTTP_STATUS.NotFound;
    Render(SStatGone);
    Exit;
  end;

  ViewData['label']         := LDisplayName;
  ViewData['working']       := LCurrentValue;
  ViewData['original']      := LCurrentValue;
  ViewData['delta_display'] := #$00B1 + '0';
  ViewData['reason']        := '';
  ViewData['preview_url']   := '/adventures/' + IntToStr(LAdv.Id) + '/stats/preview';
  ViewData['commit_url']    := '/adventures/' + IntToStr(LAdv.Id) + '/stats';
  ViewData['stat_def_id']   := IntToStr(StatDefId);
  ViewData['last_step_id']  := IntToStr(LAdv.LastStepId);

  Render(RenderView('partials/_value_modal'));
end;

procedure TStatsController.PostPreview(AdvId: Int64;
  AStatDefIdRaw, AOriginalRaw, AWorkingRaw, ADeltaRaw, AReason: string);
var
  LAdv: TAdventure;
  LWorking, LDelta, LOriginal, LNewWorking: Integer;
  LStatDefId: Int64;
  LSvc: TAdventureStateService;
  LList: TList<TStatSnapshot>;
  LSnap: TStatSnapshot;
  LLabel: string;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  LWorking    := StrToIntDef(Trim(AWorkingRaw), 0);
  LDelta      := StrToIntDef(Trim(ADeltaRaw), 0);
  LOriginal   := StrToIntDef(Trim(AOriginalRaw), 0);
  LNewWorking := LWorking + LDelta;
  LStatDefId  := StrToInt64Def(Trim(AStatDefIdRaw), 0);

  // Refresh the display name so the modal title survives round-trips. The
  // stateless preview deliberately avoids any DB write but does pay one
  // read so the title isn't blank — TAdventureStateService is the only
  // place that already handles the localisation fallback chain.
  LLabel := '';
  LSvc := TAdventureStateService.Create(CMainConnection);
  try
    LList := LSvc.GetStatsHistory(LAdv.Id,
      ViewData['current_lang'].AsString, TAppConfig.DefaultLanguage);
    try
      for LSnap in LList do
        if LSnap.StatDefId = LStatDefId then
        begin
          LLabel := LSnap.DisplayName;
          Break;
        end;
    finally
      LList.Free;
    end;
  finally
    LSvc.Free;
  end;

  ViewData['label']         := LLabel;
  ViewData['working']       := IntToStr(LNewWorking);
  ViewData['original']      := IntToStr(LOriginal);
  ViewData['delta_display'] := FormatDelta(LNewWorking - LOriginal);
  ViewData['reason']        := AReason;
  ViewData['preview_url']   := '/adventures/' + IntToStr(LAdv.Id) + '/stats/preview';
  ViewData['commit_url']    := '/adventures/' + IntToStr(LAdv.Id) + '/stats';
  ViewData['stat_def_id']   := Trim(AStatDefIdRaw);
  ViewData['last_step_id']  := IntToStr(LAdv.LastStepId);

  Render(RenderView('partials/_value_modal'));
end;

procedure TStatsController.PostCommit(AdvId: Int64;
  AStatDefIdRaw, AWorkingRaw, AReason, ALastStepRaw: string);
var
  LAdv: TAdventure;
  LStatDefId, LClientLastStep: Int64;
  LStateSvc: TAdventureStateService;
  LStatList: TList<TStatSnapshot>;
  LStat: TStatSnapshot;
  LOldValue, LNewValue: string;
  LChangesRepo: TStatChangesRepo;
  LStepsRepo: TStepsRepo;
  LStats: TJsonArray;
  LStatObj: TJsonObject;
  LAdvObj: TJsonObject;
  LCurrentLang, LDefaultLang: string;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  LStatDefId      := StrToInt64Def(Trim(AStatDefIdRaw), 0);
  LClientLastStep := StrToInt64Def(Trim(ALastStepRaw), 0);
  LNewValue       := Trim(AWorkingRaw);

  // Optimistic concurrency: another tab logged a step between render and
  // submit. Reject with the same Bulma fragment shape as LogStep.
  if LClientLastStep <> LAdv.LastStepId then
  begin
    Context.Response.StatusCode := HTTP_STATUS.Conflict;
    Render(Format('<div class="notification is-danger">%s</div>',
      [L10n('flash_concurrency')]));
    Exit;
  end;

  // No step → no anchor for the change. Fighting Fantasy plays one section
  // at a time; refuse to record orphan stat history.
  if LAdv.LastStepId = 0 then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [L10n('flash_no_current_step')]));
    Exit;
  end;

  LCurrentLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  // Capture the pre-commit value of the stat for the audit trail.
  LOldValue := '';
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LStatList := LStateSvc.GetStatsHistory(LAdv.Id, LCurrentLang, LDefaultLang);
    try
      for LStat in LStatList do
        if LStat.StatDefId = LStatDefId then
        begin
          LOldValue := LStat.Value;
          Break;
        end;
    finally
      LStatList.Free;
    end;
  finally
    LStateSvc.Free;
  end;

  LChangesRepo := TStatChangesRepo.Create(CMainConnection);
  try
    LChangesRepo.Insert(LAdv.LastStepId, LStatDefId,
      LOldValue, LNewValue, AReason);
  finally
    LChangesRepo.Free;
  end;

  // Flip flag_stat so the timeline icon for this step shows a stat change.
  // Idempotent: already-set rows just write 1 again.
  LStepsRepo := TStepsRepo.Create(CMainConnection);
  try
    LStepsRepo.SetFlagStat(LAdv.LastStepId, True);
  finally
    LStepsRepo.Free;
  end;

  // Re-render the stats panel fragment with the refreshed values.
  LStats := TJsonArray.Create;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LStatList := LStateSvc.GetStatsHistory(LAdv.Id, LCurrentLang, LDefaultLang);
    try
      for LStat in LStatList do
      begin
        LStatObj := LStats.AddObject;
        LStatObj.L['stat_def_id']  := LStat.StatDefId;
        LStatObj.S['display_name'] := LStat.DisplayName;
        LStatObj.S['kind']         := LStat.Kind;
        LStatObj.S['value']        := LStat.Value;
        LStatObj.B['is_integer']   := SameText(LStat.Kind, 'integer');
      end;
    finally
      LStatList.Free;
    end;
  finally
    LStateSvc.Free;
  end;

  LAdvObj := TJsonObject.Create;
  LAdvObj.L['id']           := LAdv.Id;
  LAdvObj.S['title']        := LAdv.Title;
  LAdvObj.S['status']       := LAdv.Status;
  LAdvObj.L['book_id']      := LAdv.BookId;
  LAdvObj.L['last_step_id'] := LAdv.LastStepId;

  ViewData['adventure'] := LAdvObj;
  ViewData['stats']     := LStats;

  Context.Response.SetCustomHeader('HX-Trigger', CTriggerCloseAndGraph);

  Render(RenderView('partials/_stats_panel'));
end;

end.
