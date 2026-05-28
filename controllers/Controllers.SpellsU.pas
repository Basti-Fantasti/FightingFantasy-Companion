{*******************************************************************************
  Unit Name: Controllers.SpellsU
  Purpose: HTTP controller for the spells panel and cast endpoint

  Author: Bastian Teufel
  Created: 2026-05-28

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TSpellsController, mounted under /adventures/:id/spells. Hosts the
    POST /cast endpoint that consumes the oldest available copy of the chosen
    spell against the adventure's current step, then re-renders the spells
    panel partial as an HTMX outerHTML swap. Ownership of the adventure is
    verified before any state change; foreign ids respond 404.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, CurrentUserId)
    - Services.SpellU (TSpellService)
    - Services.AdventureStateU (TAdventureStateService)
    - Repositories.AdventuresU (TAdventuresRepo)
    - Models.AdventureU, Models.AdventureSpellU
*******************************************************************************}

unit Controllers.SpellsU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller backing the spells panel. POST /adventures/:id/spells/cast
  ///   consumes one copy of the named spell_def and returns the refreshed
  ///   _spells_panel.html fragment.
  /// </summary>
  [MVCPath('')]
  TSpellsController = class(TBaseController)
  public
    /// <summary>
    ///   Consumes the oldest unconsumed instance of the spell definition
    ///   identified by spell_def_id for the given adventure. On success
    ///   responds with the refreshed spells panel; on validation failure
    ///   responds with a Bulma error notification fragment.
    /// </summary>
    [MVCPath('/adventures/($Id)/spells/cast')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostCast(Id: Int64;
      [MVCFromContentField('spell_def_id', '0')] ASpellDefId: Int64);
  end;

implementation

uses
  System.SysUtils,
  JsonDataObjects,
  Services.SpellU, Services.AdventureStateU,
  Repositories.AdventuresU,
  Models.AdventureU, Models.AdventureSpellU;

const
  CMainConnection = 'FFMain';

resourcestring
  SAdventureGone = 'Adventure not found.';

{ TSpellsController }

procedure TSpellsController.PostCast(Id: Int64; ASpellDefId: Int64);
var
  LSvc: TSpellService;
  LStateSvc: TAdventureStateService;
  LAdvRepo: TAdventuresRepo;
  LAdv: TAdventure;
  LConsumedId: Int64;
  LErr: string;
  LSnapshot: TArray<TAdventureSpellGroup>;
  LAvailArr, LConsumedArr: TJsonArray;
  LObj: TJsonObject;
  LGroup: TAdventureSpellGroup;
  LLang: string;
  LConsumedAny: Boolean;
begin
  RequireLogin;

  // Ownership guard: a 404 (rather than 403) avoids leaking that the
  // adventure exists for some other user.
  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LAdvRepo.TryGetById(Id, LAdv) then
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
  finally
    LAdvRepo.Free;
  end;

  // Service-layer cast: verifies the adventure has advanced past setup and
  // consumes the oldest available instance of the spell_def.
  LSvc := TSpellService.Create(CMainConnection);
  try
    if not LSvc.Cast(Id, ASpellDefId, LConsumedId, LErr) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.BadRequest;
      Render('<div class="notification is-danger">' + LErr + '</div>');
      Exit;
    end;
  finally
    LSvc.Free;
  end;

  // Re-render the panel from the fresh snapshot. The template reads two
  // separate arrays (available / consumed) plus pre-resolved boolean flags
  // because TemplatePro conditionals do not support !negation or >comparisons.
  LLang := ViewData['current_lang'].AsString;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LSnapshot := LStateSvc.GetSpellSnapshot(Id, LLang);
  finally
    LStateSvc.Free;
  end;

  LAvailArr := TJsonArray.Create;
  LConsumedArr := TJsonArray.Create;
  LConsumedAny := False;
  for LGroup in LSnapshot do
  begin
    if LGroup.Available > 0 then
    begin
      LObj := LAvailArr.AddObject;
      LObj.L['id']           := LGroup.SpellDefId;
      LObj.S['display_name'] := LGroup.DisplayName;
      LObj.I['count']        := LGroup.Available;
      LObj.B['count_gt_one'] := LGroup.Available > 1;
    end;
    if LGroup.Consumed > 0 then
    begin
      LConsumedAny := True;
      LObj := LConsumedArr.AddObject;
      LObj.S['display_name'] := LGroup.DisplayName;
      LObj.I['count']        := LGroup.Consumed;
      LObj.B['count_gt_one'] := LGroup.Consumed > 1;
    end;
  end;

  ViewData['adventure_id']         := IntToStr(Id);
  ViewData['spells_available']     := LAvailArr;
  ViewData['spells_consumed']      := LConsumedArr;
  ViewData['spells_available_none'] := LAvailArr.Count = 0;
  ViewData['spells_consumed_any']  := LConsumedAny;
  Render(RenderView('partials/_spells_panel'));
end;

end.
