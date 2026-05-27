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
  end;

implementation

uses
  System.SysUtils, System.DateUtils, System.Generics.Collections,
  JsonDataObjects,
  AppConfigU,
  Models.AdventureU, Models.BookU,
  Repositories.AdventuresU, Repositories.BooksU,
  Services.AdventureStateU,
  Services.LocalizedTitleU;

const
  CMainConnection = 'FFMain';
  CStatusActive    = 'active';
  CStatusCompleted = 'completed';
  CStatusAbandoned = 'abandoned';
  CISODateFmt      = 'yyyy-mm-dd';

resourcestring
  SBookRequired   = 'A book must be selected.';
  STitleRequired  = 'Adventure title is required.';
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
var
  LBookRepo: TBooksRepo;
  LBooks: TArray<TBook>;
  LBook: TBook;
  LArr: TJsonArray;
  LObj: TJsonObject;
  LCurrentLang, LDefaultLang: string;
begin
  RequireLogin;
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
  ViewData['error'] := '';
  Render(RenderView('pages/adventures/new'));
end;

procedure TAdventuresController.PostCreate;
var
  LAdvRepo: TAdventuresRepo;
  LBookRepo: TBooksRepo;
  LBookIdStr, LTitle: string;
  LBookId, LNewId: Int64;
  LVisible: TArray<TBook>;
  LBook: TBook;
  LOwned: Boolean;
begin
  RequireLogin;

  LBookIdStr := Trim(Context.Request.ContentParam('book_id'));
  LTitle     := Trim(Context.Request.ContentParam('title'));
  LBookId    := StrToInt64Def(LBookIdStr, 0);

  if LBookId <= 0 then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(SBookRequired);
    Exit;
  end;
  if LTitle = '' then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(STitleRequired);
    Exit;
  end;

  // Validate the book is one the current user is allowed to start an
  // adventure with (seed or their own custom book).
  LOwned := False;
  LBookRepo := TBooksRepo.Create(CMainConnection);
  try
    LVisible := LBookRepo.ListBooksForUser(CurrentUserId);
    for LBook in LVisible do
      if LBook.Id = LBookId then
      begin
        LOwned := True;
        Break;
      end;
  finally
    LBookRepo.Free;
  end;
  if not LOwned then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(SInvalidBook);
    Exit;
  end;

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    LNewId := LAdvRepo.Create(CurrentUserId, LBookId, LTitle);
  finally
    LAdvRepo.Free;
  end;

  Redirect('/adventures/' + IntToStr(LNewId));
end;

procedure TAdventuresController.Play(Id: Int64);
var
  LAdvRepo: TAdventuresRepo;
  LBookRepo: TBooksRepo;
  LStateSvc: TAdventureStateService;
  LAdv: TAdventure;
  LAdvObj: TJsonObject;
  LStats: TJsonArray;
  LInventory: TJsonArray;
  LBookTitle: string;
  LCurrentLang, LDefaultLang: string;
  LCurrentSection: Integer;
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

  LStateSvc := TAdventureStateService.Create(CMainConnection);
  try
    LCurrentSection := LStateSvc.GetCurrentSection(LAdv.Id);
    // Stats / inventory folders are stubs in Task 5.1; Tasks 7.2 / 8.2 will
    // populate the panels via separate HTMX endpoints. We just hand the
    // template empty arrays for now so the partials can render skeletons.
  finally
    LStateSvc.Free;
  end;

  LAdvObj := TJsonObject.Create;
  LAdvObj.L['id']     := LAdv.Id;
  LAdvObj.S['title']  := LAdv.Title;
  LAdvObj.S['status'] := LAdv.Status;
  LAdvObj.L['book_id'] := LAdv.BookId;

  LStats := TJsonArray.Create;
  LInventory := TJsonArray.Create;

  ViewData['adventure']       := LAdvObj;
  ViewData['book_title']      := LBookTitle;
  ViewData['current_section'] := IntToStr(LCurrentSection);
  ViewData['stats']           := LStats;
  ViewData['inventory']       := LInventory;

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

end.
