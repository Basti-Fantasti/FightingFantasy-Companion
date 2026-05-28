{*******************************************************************************
  Unit Name: Controllers.AdventuresU
  Purpose: HTTP controller for the adventure dashboard, creation, and play view

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TAdventuresController, the controller hosting the authenticated
    adventure flows:
      GET  /                         - dashboard (active + archived adventures)
      GET  /adventures/new           - new-adventure form
      POST /adventures               - create + redirect to play view
      GET  /adventures/:id           - play view (panels + timeline + step form)
      POST /adventures/:id/status    - change status (completed | abandoned)

    The play view skeleton is intentionally empty in this task: the stat /
    inventory / dice / step-form / timeline / graph areas are placeholder
    partials that later phases (Tasks 6.2, 7.2, 8.2, 9.x) fill in.

    Ownership: Play and PostStatus verify the adventure's UserId matches the
    current session user; otherwise the request is rejected with 404 (unknown
    or not visible) to avoid leaking adventure ids.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, L10n)
    - Repositories.AdventuresU (TAdventuresRepo)
    - Repositories.BooksU (TBooksRepo)
    - Services.AdventureStateU (TAdventureStateService)
    - Services.LocalizedTitleU (TLocalizedTitleService)
*******************************************************************************}

unit Controllers.AdventuresU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller exposing the authenticated adventure endpoints. Mounted at
  ///   the application root because the dashboard lives at "/"; the
  ///   adventure-scoped routes use the /adventures prefix on their action
  ///   attributes.
  /// </summary>
  [MVCPath('')]
  TAdventuresController = class(TBaseController)
  strict private
    procedure RenderNewForm(const AError: string);
  public
    /// <summary>
    ///   Dashboard at /. Lists the current user's adventures split into
    ///   active and archived (completed + abandoned) sections.
    /// </summary>
    [MVCPath('')]
    [MVCPath('/')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Index;

    /// <summary>Renders the new-adventure form with a localised book dropdown.</summary>
    [MVCPath('/adventures/new')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetNew;

    /// <summary>
    ///   Creates a new adventure from the submitted form (book_id, title) and
    ///   redirects to the play view for the new id.
    /// </summary>
    [MVCPath('/adventures')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostCreate;

    /// <summary>
    ///   HTMX fragment endpoint returning the book-specific form sections
    ///   (stats, starting gear, spell picks) for the new-adventure form. The
    ///   client requests this whenever the book select changes so the form
    ///   reflects the selected book's stat defs, starting items, and spell
    ///   defs without a full page reload.
    /// </summary>
    [MVCPath('/adventures/new/sections')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetNewSections;

    /// <summary>
    ///   Play view for a single adventure. Verifies ownership before
    ///   rendering the panels + timeline / graph + step-form skeleton.
    /// </summary>
    [MVCPath('/adventures/($Id)')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Play(Id: Int64);

    /// <summary>
    ///   Changes the status of an adventure to 'completed' or 'abandoned'
    ///   and redirects back to the dashboard. Any other status value is
    ///   rejected with 400.
    /// </summary>
    [MVCPath('/adventures/($Id)/status')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostStatus(Id: Int64;
      [MVCFromContentField('status', '')] ANewStatus: string);

    /// <summary>
    ///   Returns the timeline partial fragment for the adventure. Used by the
    ///   HTMX step-logged listener in app.js to refresh #timeline-area after
    ///   a new step is logged. The fragment includes undone steps so the UI
    ///   can apply is-undone styling; ownership is verified before rendering.
    /// </summary>
    [MVCPath('/adventures/($Id)/timeline')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Timeline(Id: Int64);
  end;

implementation

uses
  System.SysUtils, System.DateUtils, System.NetEncoding,
  System.Generics.Collections,
  JsonDataObjects,
  AppConfigU,
  Models.AdventureU, Models.BookU, Models.StepU,
  Models.DiceRollU,
  Models.StatDefU, Models.StartingItemU, Models.SpellDefU,
  Models.AdventureSpellU,
  Repositories.AdventuresU, Repositories.BooksU, Repositories.StepsU,
  Repositories.DiceRollsU,
  Repositories.SpellDefsU, Repositories.BookStartingItemsU,
  Repositories.InventoryEventsU,
  Models.InventoryEventU,
  Services.AdventureStateU,
  Services.AdventureCreateU,
  Services.LocalizedTitleU,
  Controllers.StepsU;

const
  CMainConnection = 'FFMain';
  CStatusActive    = 'active';
  CStatusCompleted = 'completed';
  CStatusAbandoned = 'abandoned';
  CISODateFmt      = 'yyyy-mm-dd';

resourcestring
  SInvalidBook    = 'Invalid book selection.';
  SInvalidStatus  = 'Invalid status value.';
  SAdventureGone  = 'Adventure not found.';

{ TAdventuresController }

/// <summary>
///   Resolves a book id to its localised title using the four-step fallback
///   chain from TLocalizedTitleService.
/// </summary>
function PickBookTitle(ARepo: TBooksRepo; ABookId: Int64;
  const ACurrentLang, ADefaultLang, AFallback: string): string;
var
  LTitles: TArray<TBookTitle>;
  LT: TBookTitle;
  LDict: TDictionary<string, string>;
begin
  LDict := TDictionary<string, string>.Create;
  try
    LTitles := ARepo.GetBookTitles(ABookId);
    for LT in LTitles do
      LDict.AddOrSetValue(LT.Lang, LT.Title);
    Result := TLocalizedTitleService.Pick(LDict,
      ACurrentLang, ADefaultLang, AFallback);
  finally
    LDict.Free;
  end;
end;

/// <summary>
///   Builds a view-model JsonObject for one adventure row including the
///   localised book title and an ISO-formatted started_at date.
/// </summary>
function BuildAdventureRow(const AAdv: TAdventure;
  const ABookTitle: string): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.L['id']         := AAdv.Id;
  Result.S['title']      := AAdv.Title;
  Result.S['book_title'] := ABookTitle;
  Result.S['status']     := AAdv.Status;
  if AAdv.StartedAt = 0 then
    Result.S['started_at'] := ''
  else
    Result.S['started_at'] := FormatDateTime(CISODateFmt, AAdv.StartedAt);
end;

procedure TAdventuresController.Index;
var
  LAdvRepo: TAdventuresRepo;
  LBookRepo: TBooksRepo;
  LAll: TArray<TAdventure>;
  LAdv: TAdventure;
  LActive, LArchived: TJsonArray;
  LCurrentLang, LDefaultLang, LBookTitle: string;
begin
  RequireLogin;
  LCurrentLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  LActive   := TJsonArray.Create;
  LArchived := TJsonArray.Create;
  // ViewData takes ownership of both arrays and frees them on request end.

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    LBookRepo := TBooksRepo.Create(CMainConnection);
    try
      LAll := LAdvRepo.ListForUser(CurrentUserId, []);
      for LAdv in LAll do
      begin
        LBookTitle := PickBookTitle(LBookRepo, LAdv.BookId,
          LCurrentLang, LDefaultLang, '');
        if SameText(LAdv.Status, CStatusActive) then
          LActive.Add(BuildAdventureRow(LAdv, LBookTitle))
        else
          LArchived.Add(BuildAdventureRow(LAdv, LBookTitle));
      end;
    finally
      LBookRepo.Free;
    end;
  finally
    LAdvRepo.Free;
  end;

  ViewData['active']   := LActive;
  ViewData['archived'] := LArchived;
  Render(RenderView('pages/adventures/list'));
end;

procedure TAdventuresController.GetNew;
begin
  RequireLogin;
  RenderNewForm('');
end;

/// <summary>
///   Renders the new-adventure form with the user's available books and an
///   optional error message shown in a notification banner above the form.
///   Shared between GetNew (no error) and PostCreate validation failures so
///   the user sees a properly chromed page instead of a bare error string.
/// </summary>
procedure TAdventuresController.RenderNewForm(const AError: string);
var
  LBookRepo: TBooksRepo;
  LBooks: TArray<TBook>;
  LBook: TBook;
  LArr: TJsonArray;
  LObj: TJsonObject;
  LCurrentLang, LDefaultLang: string;
begin
  LCurrentLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  LArr := TJsonArray.Create;
  LBookRepo := TBooksRepo.Create(CMainConnection);
  try
    LBooks := LBookRepo.ListBooksForUser(CurrentUserId);
    for LBook in LBooks do
    begin
      LObj := LArr.AddObject;
      LObj.L['id']    := LBook.Id;
      LObj.S['title'] := PickBookTitle(LBookRepo, LBook.Id,
        LCurrentLang, LDefaultLang, LBook.Slug);
    end;
  finally
    LBookRepo.Free;
  end;

  ViewData['books'] := LArr;
  ViewData['error'] := AError;
  Render(RenderView('pages/adventures/new'));
end;

/// <summary>
///   Verifies the current user is allowed to start an adventure with ABookId
///   (seed book or one of their own custom books). Returns True when the
///   book id appears in TBooksRepo.ListBooksForUser for the current user.
/// </summary>
function TAdventuresController_UserOwnsBook(const AConn: string;
  AUserId, ABookId: Int64): Boolean;
var
  LBookRepo: TBooksRepo;
  LVisible: TArray<TBook>;
  LBook: TBook;
begin
  Result := False;
  LBookRepo := TBooksRepo.Create(AConn);
  try
    LVisible := LBookRepo.ListBooksForUser(AUserId);
    for LBook in LVisible do
      if LBook.Id = ABookId then
      begin
        Result := True;
        Break;
      end;
  finally
    LBookRepo.Free;
  end;
end;

procedure TAdventuresController.PostCreate;
var
  LSvc: TAdventureCreateService;
  LReq: TAdventureCreateRequest;
  LBookRepo: TBooksRepo;
  LSpellRepo: TSpellDefsRepo;
  LItemsRepo: TBookStartingItemsRepo;
  LStatDefs: TArray<TStatDef>;
  LSpells: TArray<TSpellDef>;
  LGearRows: TArray<TStartingItemRow>;
  LGear: TStartingItemRow;
  LIdx: Integer;
  LNewId: Int64;
  LLang: string;
  LMagicStatDefId: Int64;
  LBookIdStr, LTitle: string;
  LBookId: Int64;
begin
  RequireLogin;
  LLang := ViewData['current_lang'].AsString;

  LBookIdStr := Trim(Context.Request.ContentParam('book_id'));
  LTitle     := Trim(Context.Request.ContentParam('title'));
  LBookId    := StrToInt64Def(LBookIdStr, 0);

  if LBookId <= 0 then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    RenderNewForm(L10n('adv_error_book_required'));
    Exit;
  end;
  if LTitle = '' then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    RenderNewForm(L10n('adv_error_title_required'));
    Exit;
  end;

  if not TAdventuresController_UserOwnsBook(CMainConnection,
    CurrentUserId, LBookId) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    RenderNewForm(L10n('adv_error_invalid_book'));
    Exit;
  end;

  // Gather book-specific definitions so we know which form fields to read
  // and so we can default missing values back to the book defaults.
  LBookRepo  := TBooksRepo.Create(CMainConnection);
  LSpellRepo := TSpellDefsRepo.Create(CMainConnection);
  LItemsRepo := TBookStartingItemsRepo.Create(CMainConnection);
  try
    LStatDefs := LBookRepo.GetStatDefs(LBookId);
    LSpells   := LSpellRepo.ListByBook(LBookId);
    LGearRows := LItemsRepo.ListByBookLocalized(LBookId, LLang);
  finally
    LItemsRepo.Free;
    LSpellRepo.Free;
    LBookRepo.Free;
  end;

  LReq := Default(TAdventureCreateRequest);
  LReq.UserId := CurrentUserId;
  LReq.BookId := LBookId;
  LReq.Title  := LTitle;
  LReq.Lang   := LLang;

  // Stats: one form field per stat def (stat_<id>). We also note the
  // magic stat def id (case-insensitive name match) so the service can
  // enforce the spell budget against it.
  SetLength(LReq.StatValues, Length(LStatDefs));
  LMagicStatDefId := 0;
  for LIdx := 0 to High(LStatDefs) do
  begin
    LReq.StatValues[LIdx].StatDefId := LStatDefs[LIdx].Id;
    LReq.StatValues[LIdx].Value :=
      Trim(Context.Request.ContentParam(
        'stat_' + IntToStr(LStatDefs[LIdx].Id)));
    if SameText(LStatDefs[LIdx].Name, 'magic') then
      LMagicStatDefId := LStatDefs[LIdx].Id;
  end;

  // Gear: per starting-item slug, three fields (keep flag, optional rename,
  // quantity override). Missing name falls back to the localised default;
  // missing quantity falls back to the book-defined quantity.
  SetLength(LReq.GearRows, Length(LGearRows));
  for LIdx := 0 to High(LGearRows) do
  begin
    LGear := LGearRows[LIdx];
    LReq.GearRows[LIdx].Slug := LGear.Slug;
    LReq.GearRows[LIdx].Keep :=
      Context.Request.ContentParam('gear_keep_' + LGear.Slug) = '1';
    LReq.GearRows[LIdx].Name :=
      Trim(Context.Request.ContentParam('gear_name_' + LGear.Slug));
    if LReq.GearRows[LIdx].Name = '' then
      LReq.GearRows[LIdx].Name := LGear.DisplayName;
    LReq.GearRows[LIdx].Quantity := StrToIntDef(
      Context.Request.ContentParam('gear_qty_' + LGear.Slug),
      LGear.Quantity);
  end;

  // Spells: only meaningful when the book actually has spell defs. The
  // budget is anchored on the magic stat def id (0 when no magic stat).
  if Length(LSpells) > 0 then
    LReq.SpellBudgetStatDefId := LMagicStatDefId
  else
    LReq.SpellBudgetStatDefId := 0;
  SetLength(LReq.SpellPicks, Length(LSpells));
  for LIdx := 0 to High(LSpells) do
  begin
    LReq.SpellPicks[LIdx].SpellDefId := LSpells[LIdx].Id;
    LReq.SpellPicks[LIdx].Count := StrToIntDef(
      Context.Request.ContentParam(
        'spell_count_' + IntToStr(LSpells[LIdx].Id)),
      0);
  end;

  LSvc := TAdventureCreateService.Create(CMainConnection);
  try
    try
      LNewId := LSvc.CreateAdventure(LReq);
    except
      on E: EAdventureCreateError do
      begin
        Context.Response.StatusCode := HTTP_STATUS.BadRequest;
        RenderNewForm(E.Message);
        Exit;
      end;
    end;
  finally
    LSvc.Free;
  end;

  Redirect('/adventures/' + IntToStr(LNewId));
end;

procedure TAdventuresController.GetNewSections;
var
  LBookIdStr: string;
  LBookId: Int64;
  LBookRepo: TBooksRepo;
  LSpellRepo: TSpellDefsRepo;
  LItemsRepo: TBookStartingItemsRepo;
  LStatDefs: TArray<TStatDef>;
  LSpells: TArray<TSpellDef>;
  LGearRows: TArray<TStartingItemRow>;
  LStatsArr, LGearArr, LSpellsArr: TJsonArray;
  LObj: TJsonObject;
  LIdx: Integer;
  LLang, LDefaultLang: string;
  LStatTitles: TArray<TStatDefTitle>;
  LStatTitle: TStatDefTitle;
  LStatTitleDict: TDictionary<string, string>;
  LSpellTitles: TArray<TSpellDefTitle>;
  LSpellTitleNames, LSpellTitleDescs: TDictionary<string, string>;
  LSpellTitle: TSpellDefTitle;
  LSpellBudget: Integer;
begin
  RequireLogin;
  LLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  LBookIdStr := Context.Request.QueryStringParam('book_id');
  LBookId := StrToInt64Def(LBookIdStr, 0);

  // No book selected yet: render an empty fragment so the form clears.
  if LBookId <= 0 then
  begin
    Render('');
    Exit;
  end;

  if not TAdventuresController_UserOwnsBook(CMainConnection,
    CurrentUserId, LBookId) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(SInvalidBook);
    Exit;
  end;

  LBookRepo  := TBooksRepo.Create(CMainConnection);
  LSpellRepo := TSpellDefsRepo.Create(CMainConnection);
  LItemsRepo := TBookStartingItemsRepo.Create(CMainConnection);
  try
    LStatDefs := LBookRepo.GetStatDefs(LBookId);
    LSpells   := LSpellRepo.ListByBook(LBookId);
    LGearRows := LItemsRepo.ListByBookLocalized(LBookId, LLang);

    LStatsArr  := TJsonArray.Create;
    LGearArr   := TJsonArray.Create;
    LSpellsArr := TJsonArray.Create;
    // ViewData takes ownership of the arrays.

    // Stats: resolve a localised display_name for each stat def using the
    // same fallback chain as the play view (current lang -> default lang ->
    // machine name).
    LSpellBudget := 0;
    for LIdx := 0 to High(LStatDefs) do
    begin
      LStatTitleDict := TDictionary<string, string>.Create;
      try
        LStatTitles := LBookRepo.GetStatDefTitles(LStatDefs[LIdx].Id);
        for LStatTitle in LStatTitles do
          LStatTitleDict.AddOrSetValue(LStatTitle.Lang, LStatTitle.DisplayName);
        LObj := LStatsArr.AddObject;
        LObj.L['id']            := LStatDefs[LIdx].Id;
        LObj.S['display_name']  := TLocalizedTitleService.Pick(LStatTitleDict,
          LLang, LDefaultLang, LStatDefs[LIdx].Name);
        LObj.S['default_value'] := LStatDefs[LIdx].DefaultValue;
        LObj.B['is_magic']      := SameText(LStatDefs[LIdx].Name, 'magic');
      finally
        LStatTitleDict.Free;
      end;
      // Capture the default magic value so the template can render the
      // spell-picker budget. The picker reads the live input value via the
      // is_magic flag above so the budget tracks edits to the stat input.
      if SameText(LStatDefs[LIdx].Name, 'magic') then
        LSpellBudget := StrToIntDef(LStatDefs[LIdx].DefaultValue, 0);
    end;

    for LIdx := 0 to High(LGearRows) do
    begin
      LObj := LGearArr.AddObject;
      LObj.S['slug']         := LGearRows[LIdx].Slug;
      LObj.S['display_name'] := LGearRows[LIdx].DisplayName;
      LObj.I['quantity']     := LGearRows[LIdx].Quantity;
    end;

    // Spells: resolve display_name + description per spell, preferring the
    // current language and falling back to any available title row (mirrors
    // the four-step pattern used elsewhere but lighter — we just want
    // something readable in the picker).
    for LIdx := 0 to High(LSpells) do
    begin
      LSpellTitleNames := TDictionary<string, string>.Create;
      LSpellTitleDescs := TDictionary<string, string>.Create;
      try
        LSpellTitles := LSpellRepo.ListTitles(LSpells[LIdx].Id);
        for LSpellTitle in LSpellTitles do
        begin
          LSpellTitleNames.AddOrSetValue(LSpellTitle.Lang, LSpellTitle.DisplayName);
          LSpellTitleDescs.AddOrSetValue(LSpellTitle.Lang, LSpellTitle.Description);
        end;
        LObj := LSpellsArr.AddObject;
        LObj.L['id']           := LSpells[LIdx].Id;
        LObj.S['display_name'] := TLocalizedTitleService.Pick(LSpellTitleNames,
          LLang, LDefaultLang, LSpells[LIdx].Slug);
        LObj.S['description']  := TLocalizedTitleService.Pick(LSpellTitleDescs,
          LLang, LDefaultLang, '');
      finally
        LSpellTitleDescs.Free;
        LSpellTitleNames.Free;
      end;
    end;
  finally
    LItemsRepo.Free;
    LSpellRepo.Free;
    LBookRepo.Free;
  end;

  ViewData['book_id']        := LBookIdStr;
  ViewData['stats']          := LStatsArr;
  ViewData['gear']           := LGearArr;
  ViewData['spells']         := LSpellsArr;
  ViewData['spell_budget']   := IntToStr(LSpellBudget);
  ViewData['spells_present'] := Length(LSpells) > 0;
  ViewData['gear_present']   := Length(LGearRows) > 0;

  Render(RenderView('pages/adventures/_new_sections'));
end;

procedure TAdventuresController.Play(Id: Int64);
var
  LAdvRepo: TAdventuresRepo;
  LBookRepo: TBooksRepo;
  LStepsRepo: TStepsRepo;
  LStateSvc: TAdventureStateService;
  LAdv: TAdventure;
  LAdvObj: TJsonObject;
  LStats: TJsonArray;
  LStatObj: TJsonObject;
  LStatList: TList<TStatSnapshot>;
  LStat: TStatSnapshot;
  LInventory: TJsonArray;
  LInvList: TList<TInventoryItem>;
  LInvItem: TInventoryItem;
  LInvObj: TJsonObject;
  LStepsArr: TJsonArray;
  LStepList: TArray<TStep>;
  LDiceRepo: TDiceRollsRepo;
  LRecentRolls: TArray<TDiceRoll>;
  LRoll: TDiceRoll;
  LLastRoll: TJsonObject;
  LRecentArr: TJsonArray;
  LRollObj: TJsonObject;
  LBookTitle: string;
  LCurrentLang, LDefaultLang: string;
  LCurrentSection: Integer;
  LSpellSnapshot: TArray<TAdventureSpellGroup>;
  LSpellGroup: TAdventureSpellGroup;
  LSpellAvailArr, LSpellConsumedArr: TJsonArray;
  LSpellObj: TJsonObject;
  LSpellConsumedAny: Boolean;
  LInvEventsRepo: TInventoryEventsRepo;
  LInvEvents: TArray<TInventoryEvent>;
  LSpellCasts: TDictionary<Int64, TArray<string>>;
begin
  RequireLogin;
  LCurrentLang := ViewData['current_lang'].AsString;
  LDefaultLang := TAppConfig.DefaultLanguage;

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LAdvRepo.TryGetById(Id, LAdv) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
    // Ownership check: do not leak existence of other users' adventures, so
    // return 404 rather than 403 on a foreign id.
    if LAdv.UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
  finally
    LAdvRepo.Free;
  end;

  LBookRepo := TBooksRepo.Create(CMainConnection);
  try
    LBookTitle := PickBookTitle(LBookRepo, LAdv.BookId,
      LCurrentLang, LDefaultLang, '');
  finally
    LBookRepo.Free;
  end;

  LStats := TJsonArray.Create;
  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LCurrentSection := LStateSvc.GetCurrentSection(LAdv.Id);
    LStatList := LStateSvc.GetStatsHistory(LAdv.Id, LCurrentLang, LDefaultLang);
    try
      for LStat in LStatList do
      begin
        LStatObj := LStats.AddObject;
        LStatObj.L['stat_def_id']  := LStat.StatDefId;
        LStatObj.S['display_name'] := LStat.DisplayName;
        LStatObj.S['kind']         := LStat.Kind;
        LStatObj.S['value']        := LStat.Value;
        LStatObj.S['start_value']  := LStat.StartValue;
        // Used by _stats_panel.html to decide between an editable button and a
        // read-only span. Kept as a pre-resolved Boolean to keep the template
        // logic trivial (independent of the TemplatePro filter syntax).
        LStatObj.B['is_integer']   := SameText(LStat.Kind, 'integer');
      end;
    finally
      LStatList.Free;
    end;

    // Inventory: fold non-undone events into current quantities. The
    // name_url field is pre-encoded server-side so the panel template can
    // embed it directly in the modal-open hx-get URL.
    LInventory := TJsonArray.Create;
    LInvList := LStateSvc.GetCurrentInventory(LAdv.Id);
    try
      for LInvItem in LInvList do
      begin
        LInvObj := LInventory.AddObject;
        LInvObj.S['name']     := LInvItem.Name;
        LInvObj.S['name_url'] := TNetEncoding.URL.Encode(LInvItem.Name);
        LInvObj.I['quantity'] := LInvItem.Quantity;
      end;
    finally
      LInvList.Free;
    end;

    // Spells panel snapshot: one row per spell_def used in this adventure,
    // split into Available / Consumed buckets for the partial. Pre-resolved
    // boolean flags (count_gt_one, spells_available_none, spells_consumed_any)
    // keep the template free of negation and comparison operators.
    LSpellSnapshot := LStateSvc.GetSpellSnapshot(LAdv.Id, LCurrentLang);
    // Spell casts keyed by step id; consumed by BuildStepsArray to decorate
    // timeline chips with the spells cast at each step.
    LSpellCasts := LStateSvc.GetSpellCastsByStep(LAdv.Id, LCurrentLang);
  finally
    LStateSvc.Free;
  end;

  LSpellAvailArr := TJsonArray.Create;
  LSpellConsumedArr := TJsonArray.Create;
  LSpellConsumedAny := False;
  for LSpellGroup in LSpellSnapshot do
  begin
    if LSpellGroup.Available > 0 then
    begin
      LSpellObj := LSpellAvailArr.AddObject;
      LSpellObj.L['id']           := LSpellGroup.SpellDefId;
      LSpellObj.S['display_name'] := LSpellGroup.DisplayName;
      LSpellObj.I['count']        := LSpellGroup.Available;
      LSpellObj.B['count_gt_one'] := LSpellGroup.Available > 1;
    end;
    if LSpellGroup.Consumed > 0 then
    begin
      LSpellConsumedAny := True;
      LSpellObj := LSpellConsumedArr.AddObject;
      LSpellObj.S['display_name'] := LSpellGroup.DisplayName;
      LSpellObj.I['count']        := LSpellGroup.Consumed;
      LSpellObj.B['count_gt_one'] := LSpellGroup.Consumed > 1;
    end;
  end;

  // Timeline: pull the full step list (including undone rows so the partial
  // can apply is-undone styling). Newest-first as returned by the repo.
  LStepsRepo := TStepsRepo.Create(CMainConnection);
  try
    LStepList := LStepsRepo.ListByAdventure(LAdv.Id, True);
  finally
    LStepsRepo.Free;
  end;

  // Inventory events drive the setup chip's item sub-chips; pull every event
  // (including undone) so undone setup rows still display their gear with the
  // greyed-out box styling.
  LInvEventsRepo := TInventoryEventsRepo.Create(CMainConnection);
  try
    LInvEvents := LInvEventsRepo.ListByAdventure(LAdv.Id, True);
  finally
    LInvEventsRepo.Free;
  end;

  LAdvObj := TJsonObject.Create;
  LAdvObj.L['id']           := LAdv.Id;
  LAdvObj.S['title']        := LAdv.Title;
  LAdvObj.S['status']       := LAdv.Status;
  LAdvObj.L['book_id']      := LAdv.BookId;
  LAdvObj.L['last_step_id'] := LAdv.LastStepId;

  try
    LStepsArr := BuildStepsArray(LStepList, LInvEvents, LSpellCasts);
  finally
    LSpellCasts.Free;
  end;

  // Dice history: surface the most recent roll for the "Last: ..." highlight
  // and up to 3 entries for the short history list. When the player hasn't
  // rolled anything yet both ViewData keys stay unset so the panel's
  // {{if last_roll}} / {{if recent_rolls}} blocks render nothing.
  LDiceRepo := TDiceRollsRepo.Create(CMainConnection);
  try
    LRecentRolls := LDiceRepo.LastN(LAdv.Id, 3);
  finally
    LDiceRepo.Free;
  end;

  if Length(LRecentRolls) > 0 then
  begin
    LRoll := LRecentRolls[0];
    LLastRoll := TJsonObject.Create;
    LLastRoll.S['expression'] := LRoll.Expression;
    LLastRoll.I['result']     := LRoll.Rolled;
    ViewData['last_roll'] := LLastRoll;

    LRecentArr := TJsonArray.Create;
    for LRoll in LRecentRolls do
    begin
      LRollObj := LRecentArr.AddObject;
      LRollObj.S['expression'] := LRoll.Expression;
      LRollObj.I['result']     := LRoll.Rolled;
    end;
    ViewData['recent_rolls'] := LRecentArr;
  end;

  ViewData['adventure']            := LAdvObj;
  ViewData['adventure_id']         := IntToStr(LAdv.Id);
  ViewData['book_title']           := LBookTitle;
  ViewData['current_section']      := IntToStr(LCurrentSection);
  ViewData['stats']                := LStats;
  ViewData['inventory']            := LInventory;
  ViewData['steps']                := LStepsArr;
  ViewData['spells_panel_visible'] := Length(LSpellSnapshot) > 0;
  ViewData['spells_available']     := LSpellAvailArr;
  ViewData['spells_consumed']      := LSpellConsumedArr;
  ViewData['spells_available_none'] := LSpellAvailArr.Count = 0;
  ViewData['spells_consumed_any']  := LSpellConsumedAny;

  Render(RenderView('pages/adventures/play'));
end;

procedure TAdventuresController.PostStatus(Id: Int64; ANewStatus: string);
var
  LAdvRepo: TAdventuresRepo;
  LAdv: TAdventure;
begin
  RequireLogin;

  if (ANewStatus <> CStatusCompleted) and (ANewStatus <> CStatusAbandoned) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(SInvalidStatus);
    Exit;
  end;

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
    LAdvRepo.UpdateStatus(Id, ANewStatus);
  finally
    LAdvRepo.Free;
  end;

  Flash('success', L10n('flash_saved'));
  Redirect('/');
end;

procedure TAdventuresController.Timeline(Id: Int64);
var
  LAdvRepo: TAdventuresRepo;
  LStepsRepo: TStepsRepo;
  LInvEventsRepo: TInventoryEventsRepo;
  LStateSvc: TAdventureStateService;
  LAdv: TAdventure;
  LAdvObj: TJsonObject;
  LStepList: TArray<TStep>;
  LInvEvents: TArray<TInventoryEvent>;
  LSpellCasts: TDictionary<Int64, TArray<string>>;
  LCurrentLang: string;
begin
  RequireLogin;

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

  LCurrentLang := ViewData['current_lang'].AsString;

  LStepsRepo := TStepsRepo.Create(CMainConnection);
  try
    LStepList := LStepsRepo.ListByAdventure(Id, True);
  finally
    LStepsRepo.Free;
  end;

  // Match Play: pull inventory events and spell casts so chip enrichment
  // survives across HTMX refreshes after a step is logged.
  LInvEventsRepo := TInventoryEventsRepo.Create(CMainConnection);
  try
    LInvEvents := LInvEventsRepo.ListByAdventure(Id, True);
  finally
    LInvEventsRepo.Free;
  end;

  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LSpellCasts := LStateSvc.GetSpellCastsByStep(Id, LCurrentLang);
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
  try
    ViewData['steps'] := BuildStepsArray(LStepList, LInvEvents, LSpellCasts);
  finally
    LSpellCasts.Free;
  end;

  // Fragment-only response — the partial doesn't extend a layout, so we
  // skip the base wrapper entirely.
  Render(RenderView('partials/_timeline'));
end;

end.
