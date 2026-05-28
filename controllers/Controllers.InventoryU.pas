{*******************************************************************************
  Unit Name: Controllers.InventoryU
  Purpose: HTTP controller for the inventory panel and touch value editor

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TInventoryController, mounted under /adventures/:adv_id/inventory.
    Three actions back the panel rendered in _inventory_panel.html together
    with the touch value-modal shared with the stats panel:

      POST /adventures/:id/inventory                  - PostEvent (commit)
      GET  /adventures/:id/inventory/:item/modal      - GetModal  (open editor)
      POST /adventures/:id/inventory/preview          - PostPreview (re-render)

    PostEvent persists a new inventory_events row of kind 'gain', 'lose', or
    'modify' against the adventure's current step. The form on the panel
    submits the lose / gain variants directly; the value-modal commits a
    'modify' with the new working quantity. After the insert the step's
    flag_item marker is set so the timeline icon reflects the mutation, and
    the response is the refreshed _inventory_panel.html fragment paired with
    an HX-Trigger that closes any open modal and refreshes the graph tab.

    GetModal resolves a URL-encoded item name to its current quantity through
    TAdventureStateService.GetCurrentInventory and renders the inventory-
    flavoured value-modal partial seeded with that quantity.

    PostPreview is stateless — same +/- math as the stats preview — and never
    touches the database. The original / working / delta values round-trip as
    form fields so the user can poke at +/- buttons without DB chatter.

    Refactor decision: rather than generalising _value_modal.html into an
    extra_hidden array shape (which would also require refactoring the stats
    controller and template), we duplicated the partial as
    _value_modal_inventory.html. The two files differ only in the hidden form
    fields posted by the Confirm button and the hx-target of the surrounding
    form. Consolidation can happen later when a third caller appears.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, L10n)
    - Repositories.AdventuresU, Repositories.StepsU,
      Repositories.InventoryEventsU
    - Services.AdventureStateU
*******************************************************************************}

unit Controllers.InventoryU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Models.AdventureU,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller backing the inventory panel and in-place value editor.
  ///   Every action verifies the adventure belongs to the current user and
  ///   returns 404 on mismatch to avoid leaking adventure ids.
  /// </summary>
  [MVCPath('/adventures/($AdvId)/inventory')]
  TInventoryController = class(TBaseController)
  strict private
    /// <summary>
    ///   Loads the adventure and verifies it belongs to the current user.
    ///   On miss writes a 404 response and returns False; the caller must
    ///   Exit without touching the response further.
    /// </summary>
    function TryLoadOwnedAdventure(AAdvId: Int64;
      out AAdv: TAdventure): Boolean;

    /// <summary>
    ///   Re-renders the inventory panel fragment for the given adventure.
    ///   Used as the success response of every PostEvent variant.
    /// </summary>
    procedure RenderInventoryPanel(const AAdv: TAdventure);
  public
    /// <summary>
    ///   Persists a single inventory event ('gain', 'lose', or 'modify')
    ///   against the current step. Sets flag_item on the step and returns
    ///   the refreshed inventory panel fragment with an HX-Trigger that
    ///   closes any open modal and refreshes the graph tab.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostEvent(AdvId: Int64;
      [MVCFromContentField('kind', 'gain')] AKind: string;
      [MVCFromContentField('item_name', '')] AItemName: string;
      [MVCFromContentField('quantity', '1')] AQuantityRaw: string;
      [MVCFromContentField('note', '')] ANote: string;
      [MVCFromContentField('last_step_id', '')] ALastStepRaw: string);

    /// <summary>
    ///   Returns the value-edit modal fragment seeded with the current
    ///   quantity of the requested item. ItemEnc is the URL-encoded item
    ///   name as embedded in the panel buttons.
    /// </summary>
    [MVCPath('/($ItemEnc)/modal')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetModal(AdvId: Int64; ItemEnc: string);

    /// <summary>
    ///   Stateless re-render of the value modal with an updated working
    ///   quantity and delta display. Computes new_working = working + delta
    ///   and delta_display from (new_working - original). Never writes.
    /// </summary>
    [MVCPath('/preview')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure PostPreview(AdvId: Int64;
      [MVCFromContentField('item_name', '')] AItemName: string;
      [MVCFromContentField('original', '')] AOriginalRaw: string;
      [MVCFromContentField('working', '')] AWorkingRaw: string;
      [MVCFromContentField('delta', '0')] ADeltaRaw: string;
      [MVCFromContentField('reason', '')] AReason: string);
  end;

implementation

uses
  System.SysUtils, System.NetEncoding, System.Generics.Collections,
  JsonDataObjects,
  Repositories.AdventuresU,
  Repositories.StepsU,
  Repositories.InventoryEventsU,
  Services.AdventureStateU;

const
  CMainConnection = 'FFMain';
  CTriggerCloseAndGraph = '{"close-modal":{},"graph-changed":{}}';
  CKindGain   = 'gain';
  CKindLose   = 'lose';
  CKindModify = 'modify';

resourcestring
  SAdventureGone = 'Adventure not found.';
  SItemGone      = 'Item not found.';
  SInvalidKind   = 'Invalid inventory event kind.';
  SInvalidQty    = 'Quantity must be a non-negative integer.';
  SItemNameReq   = 'Item name is required.';

/// <summary>
///   Formats a signed integer delta as "+N", "-N", or "±0" for display in
///   the modal's "Δ ..." hint line. Mirrors the stats controller helper.
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

{ TInventoryController }

function TInventoryController.TryLoadOwnedAdventure(AAdvId: Int64;
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

procedure TInventoryController.RenderInventoryPanel(const AAdv: TAdventure);
var
  LStateSvc: TAdventureStateService;
  LItems: TList<TInventoryItem>;
  LItem: TInventoryItem;
  LInventory: TJsonArray;
  LObj: TJsonObject;
  LAdvObj: TJsonObject;
begin
  LInventory := TJsonArray.Create;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LItems := LStateSvc.GetCurrentInventory(AAdv.Id);
    try
      for LItem in LItems do
      begin
        LObj := LInventory.AddObject;
        LObj.S['name']     := LItem.Name;
        // Pre-encode the URL slug here so the template stays trivial. The
        // matching GetModal action URL-decodes the captured segment.
        LObj.S['name_url'] := TNetEncoding.URL.Encode(LItem.Name);
        LObj.I['quantity'] := LItem.Quantity;
      end;
    finally
      LItems.Free;
    end;
  finally
    LStateSvc.Free;
  end;

  LAdvObj := TJsonObject.Create;
  LAdvObj.L['id']           := AAdv.Id;
  LAdvObj.S['title']        := AAdv.Title;
  LAdvObj.S['status']       := AAdv.Status;
  LAdvObj.L['book_id']      := AAdv.BookId;
  LAdvObj.L['last_step_id'] := AAdv.LastStepId;

  ViewData['adventure'] := LAdvObj;
  ViewData['inventory'] := LInventory;

  Render(RenderView('partials/_inventory_panel'));
end;

procedure TInventoryController.PostEvent(AdvId: Int64;
  AKind, AItemName, AQuantityRaw, ANote, ALastStepRaw: string);
var
  LAdv: TAdventure;
  LQuantity: Integer;
  LClientLastStep: Int64;
  LName: string;
  LRepo: TInventoryEventsRepo;
  LStepsRepo: TStepsRepo;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  AKind := LowerCase(Trim(AKind));
  LName := Trim(AItemName);
  LClientLastStep := StrToInt64Def(Trim(ALastStepRaw), 0);

  if (AKind <> CKindGain) and (AKind <> CKindLose) and (AKind <> CKindModify) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [SInvalidKind]));
    Exit;
  end;

  if LName = '' then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [SItemNameReq]));
    Exit;
  end;

  // Quantity must parse as a non-negative integer. We accept 0 for
  // 'modify' (clear an item) but the panel UI never submits 0 for gain/lose.
  if not TryStrToInt(Trim(AQuantityRaw), LQuantity) or (LQuantity < 0) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [SInvalidQty]));
    Exit;
  end;

  // Optimistic concurrency: another tab logged a step between render and
  // submit. Reject with the same Bulma fragment shape as the stats panel.
  if LClientLastStep <> LAdv.LastStepId then
  begin
    Context.Response.StatusCode := HTTP_STATUS.Conflict;
    Render(Format('<div class="notification is-danger">%s</div>',
      [L10n('flash_concurrency')]));
    Exit;
  end;

  // Inventory events are always attached to a step — no orphan history.
  if LAdv.LastStepId = 0 then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [L10n('flash_no_current_step')]));
    Exit;
  end;

  LRepo := TInventoryEventsRepo.Create(CMainConnection);
  try
    LRepo.Insert(LAdv.LastStepId, AKind, LName, LQuantity, ANote);
  finally
    LRepo.Free;
  end;

  // Flip flag_item so the timeline icon for this step shows an item change.
  // Idempotent: already-set rows just write 1 again.
  LStepsRepo := TStepsRepo.Create(CMainConnection);
  try
    LStepsRepo.SetFlagItem(LAdv.LastStepId, True);
  finally
    LStepsRepo.Free;
  end;

  Context.Response.SetCustomHeader('HX-Trigger', CTriggerCloseAndGraph);
  RenderInventoryPanel(LAdv);
end;

procedure TInventoryController.GetModal(AdvId: Int64; ItemEnc: string);
var
  LAdv: TAdventure;
  LDecodedName: string;
  LStateSvc: TAdventureStateService;
  LItems: TList<TInventoryItem>;
  LItem: TInventoryItem;
  LQty: Integer;
  LFound: Boolean;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  LDecodedName := TNetEncoding.URL.Decode(ItemEnc);

  LFound := False;
  LQty   := 0;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LItems := LStateSvc.GetCurrentInventory(LAdv.Id);
    try
      for LItem in LItems do
        if LItem.Name = LDecodedName then
        begin
          LQty := LItem.Quantity;
          LFound := True;
          Break;
        end;
    finally
      LItems.Free;
    end;
  finally
    LStateSvc.Free;
  end;

  if not LFound then
  begin
    Context.Response.StatusCode := HTTP_STATUS.NotFound;
    Render(SItemGone);
    Exit;
  end;

  ViewData['label']         := LDecodedName;
  ViewData['item_name']     := LDecodedName;
  ViewData['working']       := IntToStr(LQty);
  ViewData['original']      := IntToStr(LQty);
  ViewData['delta_display'] := #$00B1 + '0';
  ViewData['reason']        := '';
  ViewData['preview_url']   := '/adventures/' + IntToStr(LAdv.Id) + '/inventory/preview';
  ViewData['commit_url']    := '/adventures/' + IntToStr(LAdv.Id) + '/inventory';
  ViewData['last_step_id']  := IntToStr(LAdv.LastStepId);

  Render(RenderView('partials/_value_modal_inventory'));
end;

procedure TInventoryController.PostPreview(AdvId: Int64;
  AItemName, AOriginalRaw, AWorkingRaw, ADeltaRaw, AReason: string);
var
  LAdv: TAdventure;
  LWorking, LDelta, LOriginal, LNewWorking: Integer;
begin
  RequireLogin;
  if not TryLoadOwnedAdventure(AdvId, LAdv) then
    Exit;

  LWorking    := StrToIntDef(Trim(AWorkingRaw), 0);
  LDelta      := StrToIntDef(Trim(ADeltaRaw), 0);
  LOriginal   := StrToIntDef(Trim(AOriginalRaw), 0);
  LNewWorking := LWorking + LDelta;
  // Quantity floor: never preview a negative running quantity. The modal can
  // still commit at zero (treated as 'modify' = clear via the folder).
  if LNewWorking < 0 then
    LNewWorking := 0;

  ViewData['label']         := AItemName;
  ViewData['item_name']     := AItemName;
  ViewData['working']       := IntToStr(LNewWorking);
  ViewData['original']      := IntToStr(LOriginal);
  ViewData['delta_display'] := FormatDelta(LNewWorking - LOriginal);
  ViewData['reason']        := AReason;
  ViewData['preview_url']   := '/adventures/' + IntToStr(LAdv.Id) + '/inventory/preview';
  ViewData['commit_url']    := '/adventures/' + IntToStr(LAdv.Id) + '/inventory';
  ViewData['last_step_id']  := IntToStr(LAdv.LastStepId);

  Render(RenderView('partials/_value_modal_inventory'));
end;

end.
