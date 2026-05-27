{*******************************************************************************
  Unit Name: Controllers.StepsU
  Purpose: HTTP controller for logging steps and soft-undo/redo on the timeline

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TStepsController, mounted under /adventures/:adv_id/steps. It owns
    three actions in the play-view flow:

      POST /adventures/:id/steps             - LogStep (HTMX form submission)
      POST /adventures/:id/steps/:sid/undo   - Undo  (soft-undone = 1)
      POST /adventures/:id/steps/:sid/redo   - Redo  (soft-undone = 0)

    All three actions perform the standard FFCompanion ownership check: load
    the adventure, verify UserId matches the session user, and return 404 on
    miss to avoid leaking adventure ids.

    LogStep additionally implements optimistic concurrency: the form posts the
    adventure's last_step_id at render time; if it no longer matches the DB
    value, the request fails with HTTP 409 and a Bulma "is-danger" notification
    fragment rendered inline (concurrency error is unusual enough that a
    dedicated template would be overkill).

    LogStep emits two HTMX events via a single HX-Trigger header carrying a
    JSON object: "step-logged" (so app.js refreshes the timeline area) and
    "graph-changed" (so the graph tab redraws). Undo/Redo emit only
    "graph-changed" because their own response already contains the refreshed
    timeline.

    The shared BuildStepsArray helper produces the view-model TJsonArray
    consumed by partials/_timeline.html (one object per step, including a
    pre-formatted created_at_display string). It is exposed for reuse by
    TAdventuresController.Play and TAdventuresController.Timeline.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, L10n)
    - Repositories.AdventuresU, Repositories.StepsU
    - Services.AdventureStateU (current section lookup)
*******************************************************************************}

unit Controllers.StepsU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  JsonDataObjects,
  Controllers.BaseU,
  Models.StepU;

/// <summary>
///   Builds the view-model JSON array consumed by partials/_timeline.html
///   from a flat TStep[] list (newest-first as returned by the repository).
///   Each object carries id, seq, from_section, to_section, note, flag_*,
///   undone and a pre-formatted created_at_display string.
///   The caller owns the returned array (assign to ViewData to transfer
///   ownership to the request lifetime).
/// </summary>
function BuildStepsArray(const ASteps: TArray<TStep>): TJsonArray;

type
  /// <summary>
  ///   Controller for step lifecycle actions tied to a single adventure:
  ///   logging a new step, soft-undoing a previous step, and redoing one.
  /// </summary>
  [MVCPath('/adventures/($AdvId)/steps')]
  TStepsController = class(TBaseController)
  strict private
    /// <summary>
    ///   Shared body for Undo and Redo. Verifies ownership of the step and
    ///   the adventure, flips steps.undone to AUndone, re-fetches the full
    ///   timeline (including undone rows so the UI can grey them), and
    ///   renders the timeline partial. Emits graph-changed so the graph
    ///   view stays in sync.
    /// </summary>
    procedure SetStepUndoneAndRespond(AAdvId, ASId: Int64; AUndone: Boolean);
  public
    /// <summary>
    ///   Logs a new step for the adventure. Performs ownership + optimistic
    ///   concurrency checks, computes the from_section via the adventure
    ///   state service, inserts the row, updates adventures.last_step_id,
    ///   re-renders the step form fragment, and triggers the step-logged +
    ///   graph-changed HTMX events.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure LogStep(AdvId: Int64;
      [MVCFromContentField('to_section', '')] AToRaw: string;
      [MVCFromContentField('note', '')] ANote: string;
      [MVCFromContentField('last_step_id', '')] ALastStepRaw: string;
      [MVCFromContentField('flag_fight', '')] AFlagFight: string;
      [MVCFromContentField('flag_item', '')] AFlagItem: string;
      [MVCFromContentField('flag_stat', '')] AFlagStat: string);

    /// <summary>
    ///   Soft-undoes a step (sets undone=1) without removing the row. The
    ///   refreshed timeline fragment is returned so HTMX can swap the
    ///   #timeline-area in place; graph-changed is fired so the graph view
    ///   refreshes too.
    /// </summary>
    [MVCPath('/($SId)/undo')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Undo(AdvId, SId: Int64);

    /// <summary>
    ///   Reverses a previous Undo (sets undone=0). Same response shape as
    ///   Undo: refreshed timeline fragment + graph-changed trigger.
    /// </summary>
    [MVCPath('/($SId)/redo')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Redo(AdvId, SId: Int64);
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  Models.AdventureU,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Services.AdventureStateU;

const
  CMainConnection = 'FFMain';
  CDisplayDateFmt = 'yyyy-mm-dd hh:nn';
  CTriggerStepAndGraph = '{"step-logged":{},"graph-changed":{}}';
  CTriggerGraphOnly    = '{"graph-changed":{}}';

resourcestring
  SAdventureGone = 'Adventure not found.';
  SStepGone      = 'Step not found.';

function BuildStepsArray(const ASteps: TArray<TStep>): TJsonArray;
var
  LStep: TStep;
  LObj: TJsonObject;
  LDisplay: string;
begin
  Result := TJsonArray.Create;
  for LStep in ASteps do
  begin
    LObj := Result.AddObject;
    LObj.L['id']           := LStep.Id;
    LObj.I['seq']          := LStep.Seq;
    LObj.I['from_section'] := LStep.FromSection;
    LObj.I['to_section']   := LStep.ToSection;
    LObj.S['note']         := LStep.Note;
    LObj.B['flag_fight']   := LStep.FlagFight;
    LObj.B['flag_item']    := LStep.FlagItem;
    LObj.B['flag_stat']    := LStep.FlagStat;
    LObj.B['undone']       := LStep.Undone;
    if LStep.CreatedAt = 0 then
      LDisplay := ''
    else
      LDisplay := FormatDateTime(CDisplayDateFmt, LStep.CreatedAt);
    LObj.S['created_at_display'] := LDisplay;
  end;
end;

{ TStepsController }

/// <summary>
///   Returns True when a checkbox form field was submitted with any non-empty
///   value. HTML checkboxes only include the field in the form submission
///   when checked, so any non-empty value indicates "on".
/// </summary>
function CheckboxOn(const ARaw: string): Boolean;
begin
  Result := ARaw <> '';
end;

/// <summary>
///   Builds an adventure view-model JsonObject for the step-form partial.
///   Mirrors the shape used by TAdventuresController.Play.
/// </summary>
function BuildAdventureObj(const AAdv: TAdventure): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.L['id']           := AAdv.Id;
  Result.S['title']        := AAdv.Title;
  Result.S['status']       := AAdv.Status;
  Result.L['book_id']      := AAdv.BookId;
  Result.L['last_step_id'] := AAdv.LastStepId;
end;

procedure TStepsController.LogStep(AdvId: Int64;
  AToRaw, ANote, ALastStepRaw, AFlagFight, AFlagItem, AFlagStat: string);
var
  LAdvRepo: TAdventuresRepo;
  LStepsRepo: TStepsRepo;
  LStateSvc: TAdventureStateService;
  LAdv: TAdventure;
  LClientLastStep, LNewStepId: Int64;
  LToSection, LFromSection: Integer;
  LFight, LItem, LStat: Boolean;
begin
  RequireLogin;

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LAdvRepo.TryGetById(AdvId, LAdv) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
    if LAdv.UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;

    // Optimistic concurrency: client posts the adventure's last_step_id seen
    // at render time. If it no longer matches the DB value, another tab won
    // the race; return an inline Bulma error fragment with HTTP 409.
    LClientLastStep := StrToInt64Def(Trim(ALastStepRaw), 0);
    if LClientLastStep <> LAdv.LastStepId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.Conflict;
      Render(Format(
        '<div class="notification is-danger">%s</div>',
        [L10n('flash_concurrency')]));
      Exit;
    end;

    LToSection := StrToIntDef(Trim(AToRaw), 0);
    if LToSection <= 0 then
    begin
      // Re-render the form with current data so the user can correct input.
      Context.Response.StatusCode := HTTP_STATUS.BadRequest;
      LStateSvc := TAdventureStateService.Create(CMainConnection);
      try
        ViewData['current_section'] := IntToStr(
          LStateSvc.GetCurrentSection(LAdv.Id));
      finally
        LStateSvc.Free;
      end;
      ViewData['adventure'] := BuildAdventureObj(LAdv);
      Render(RenderView('partials/_step_form'));
      Exit;
    end;

    LFight := CheckboxOn(AFlagFight);
    LItem  := CheckboxOn(AFlagItem);
    LStat  := CheckboxOn(AFlagStat);

    LStateSvc := TAdventureStateService.Create(CMainConnection);
    try
      LFromSection := LStateSvc.GetCurrentSection(LAdv.Id);
    finally
      LStateSvc.Free;
    end;

    LStepsRepo := TStepsRepo.Create(CMainConnection);
    try
      LNewStepId := LStepsRepo.Insert(LAdv.Id, LFromSection, LToSection,
        ANote, LFight, LItem, LStat);
    finally
      LStepsRepo.Free;
    end;

    LAdvRepo.UpdateLastStep(LAdv.Id, LNewStepId);

    // Reload to reflect the fresh last_step_id in the rendered hidden field.
    LAdv := LAdvRepo.GetById(LAdv.Id);
  finally
    LAdvRepo.Free;
  end;

  ViewData['adventure']       := BuildAdventureObj(LAdv);
  ViewData['current_section'] := IntToStr(LToSection);

  // Fire BOTH step-logged (timeline refresh) and graph-changed (graph tab
  // refresh) via the JSON-object HX-Trigger form. Bypasses Flash() because
  // we want events with no payload, not a showFlash notification.
  Context.Response.SetCustomHeader('HX-Trigger', CTriggerStepAndGraph);

  Render(RenderView('partials/_step_form'));
end;

procedure TStepsController.Undo(AdvId, SId: Int64);
begin
  SetStepUndoneAndRespond(AdvId, SId, True);
end;

procedure TStepsController.Redo(AdvId, SId: Int64);
begin
  SetStepUndoneAndRespond(AdvId, SId, False);
end;

procedure TStepsController.SetStepUndoneAndRespond(AAdvId, ASId: Int64;
  AUndone: Boolean);
var
  LAdvRepo: TAdventuresRepo;
  LStepsRepo: TStepsRepo;
  LAdv: TAdventure;
  LStep: TStep;
  LList: TArray<TStep>;
  LRespondedNotFound: Boolean;
begin
  RequireLogin;
  LRespondedNotFound := False;

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LAdvRepo.TryGetById(AAdvId, LAdv) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      LRespondedNotFound := True;
    end
    else if LAdv.UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      LRespondedNotFound := True;
    end;
  finally
    LAdvRepo.Free;
  end;
  if LRespondedNotFound then
    Exit;

  LStepsRepo := TStepsRepo.Create(CMainConnection);
  try
    try
      LStep := LStepsRepo.GetById(ASId);
    except
      on EStepNotFound do
      begin
        Context.Response.StatusCode := HTTP_STATUS.NotFound;
        Render(SStepGone);
        Exit;
      end;
    end;
    if LStep.AdventureId <> AAdvId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SStepGone);
      Exit;
    end;

    LStepsRepo.SetUndone(ASId, AUndone);

    LList := LStepsRepo.ListByAdventure(AAdvId, True);
  finally
    LStepsRepo.Free;
  end;

  ViewData['adventure'] := BuildAdventureObj(LAdv);
  ViewData['steps']     := BuildStepsArray(LList);

  Context.Response.SetCustomHeader('HX-Trigger', CTriggerGraphOnly);

  Render(RenderView('partials/_timeline'));
end;

end.
