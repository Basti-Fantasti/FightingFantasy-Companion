{*******************************************************************************
  Unit Name: Controllers.BooksU
  Purpose: HTTP controller for the book catalogue list and custom-book creation

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TBooksController, the controller hosting the book catalogue UI:
      GET  /books      - lists seed books plus the user's own custom books
      GET  /books/new  - renders the custom-book creation form
      POST /books      - creates a custom book + per-stat definitions

    All endpoints require an authenticated session (RequireLogin from
    TBaseController). The list view runs every book title through
    TLocalizedTitleService.Pick to apply the four-step language fallback
    (current_lang -> default -> alpha-first non-empty -> slug literal).

    The creation form is single-language for v1 per Task 4.4 guidance: the
    only language captured is the user's current UI language, which is also
    used for the localised display names of the three default stat rows.
    Multi-language custom books remain supported by the underlying repo and
    the seed YAML pipeline; the affordance can be added to the form later.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU (TBaseController, RequireLogin, L10n)
    - Repositories.BooksU (TBooksRepo)
    - Services.LocalizedTitleU (TLocalizedTitleService)
    - Models.BookU, Models.StatDefU
*******************************************************************************}

unit Controllers.BooksU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller exposing the authenticated book-catalogue endpoints.
  ///   Mounted at /books; every action calls RequireLogin from the base.
  /// </summary>
  [MVCPath('/books')]
  TBooksController = class(TBaseController)
  public
    /// <summary>
    ///   Renders the catalogue list with localised titles for every book
    ///   the user can see (seed books plus their own custom entries).
    /// </summary>
    [MVCPath('')]
    [MVCPath('/')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Index;

    /// <summary>Renders the custom-book creation form.</summary>
    [MVCPath('/new')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetNew;

    /// <summary>
    ///   Creates a custom book from the submitted form. On success the
    ///   browser is redirected to /books with a success flash; on a validation
    ///   failure (bad slug, slug collision with a seed book, missing title)
    ///   the form is re-rendered with a localised error notification.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostCreate;
  end;

implementation

uses
  System.SysUtils, System.RegularExpressions, System.Generics.Collections,
  JsonDataObjects,
  AppConfigU,
  Models.BookU, Models.StatDefU,
  Repositories.BooksU,
  Services.LocalizedTitleU;

const
  CMainConnection = 'FFMain';
  CSlugPattern    = '^[a-z0-9-]+$';
  CStatRowCount   = 3;

resourcestring
  SInvalidSlug      = 'Slug must contain only lowercase letters, digits, and hyphens.';
  SSlugTaken        = 'A book with this slug already exists.';
  STitleRequired    = 'Title is required.';
  SStatNameRequired = 'Every stat needs a machine name.';

{ TBooksController }

/// <summary>
///   Builds the {slug, title, author, custom} JSON array consumed by
///   templates/pages/books/list.html.
/// </summary>
function BuildBookViewModel(ARepo: TBooksRepo; const ABooks: TArray<TBook>;
  const ACurrentLang, ADefaultLang: string): TJsonArray;
var
  LBook: TBook;
  LTitles: TArray<TBookTitle>;
  LT: TBookTitle;
  LDict: TDictionary<string, string>;
  LObj: TJsonObject;
begin
  Result := TJsonArray.Create;
  try
    for LBook in ABooks do
    begin
      LDict := TDictionary<string, string>.Create;
      try
        LTitles := ARepo.GetBookTitles(LBook.Id);
        for LT in LTitles do
          LDict.AddOrSetValue(LT.Lang, LT.Title);
        LObj := Result.AddObject;
        LObj.S['slug']   := LBook.Slug;
        LObj.S['author'] := LBook.Author;
        LObj.B['custom'] := not LBook.IsSeed;
        LObj.S['title']  := TLocalizedTitleService.Pick(
          LDict, ACurrentLang, ADefaultLang, LBook.Slug);
      finally
        LDict.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TBooksController.Index;
var
  LRepo: TBooksRepo;
  LBooks: TArray<TBook>;
  LArr: TJsonArray;
  LCurrentLang: string;
begin
  RequireLogin;
  LCurrentLang := ViewData['current_lang'].AsString;
  LRepo := TBooksRepo.Create(CMainConnection);
  try
    LBooks := LRepo.ListBooksForUser(CurrentUserId);
    LArr := BuildBookViewModel(LRepo, LBooks, LCurrentLang,
      TAppConfig.DefaultLanguage);
    // ViewData owns the JsonArray and frees it on request end.
    ViewData['books'] := LArr;
  finally
    LRepo.Free;
  end;
  Render(RenderView('pages/books/list'));
end;

procedure TBooksController.GetNew;
begin
  RequireLogin;
  ViewData['error'] := '';
  Render(RenderView('pages/books/form'));
end;

procedure TBooksController.PostCreate;
var
  LRepo: TBooksRepo;
  LSlug, LAuthor, LTitle, LCurrentLang, LError: string;
  LStatNames, LStatKinds, LStatDefaults, LStatTitles: TArray<string>;
  LStatKind, LStatDefault, LStatTitle: string;
  LBookId, LStatDefId: Int64;
  LBookTitles: TArray<TBookTitle>;
  LStatTitleArr: TArray<TStatDefTitle>;
  LExisting: TArray<TBook>;
  LBook: TBook;
  I: Integer;
begin
  RequireLogin;
  LCurrentLang := ViewData['current_lang'].AsString;

  LSlug   := Trim(Context.Request.ContentParam('slug')).ToLower;
  LAuthor := Trim(Context.Request.ContentParam('author'));
  LTitle  := Trim(Context.Request.ContentParam('title_text'));

  // Form posts repeated stat_name[], stat_kind[], stat_default[], stat_title[]
  // pairs (the form template renders CStatRowCount rows). DMVC exposes these
  // as ContentParamsMulti, which preserves the original submission order.
  LStatNames    := Context.Request.ContentParamsMulti['stat_name[]'];
  LStatKinds    := Context.Request.ContentParamsMulti['stat_kind[]'];
  LStatDefaults := Context.Request.ContentParamsMulti['stat_default[]'];
  LStatTitles   := Context.Request.ContentParamsMulti['stat_title[]'];

  LError := '';
  if (LSlug = '') or not TRegEx.IsMatch(LSlug, CSlugPattern) then
    LError := SInvalidSlug
  else if LTitle = '' then
    LError := STitleRequired;

  LRepo := TBooksRepo.Create(CMainConnection);
  try
    if LError = '' then
    begin
      // Slug uniqueness: reject if any existing book (seed or another user's
      // custom book) already owns this slug. ListBooksForUser only sees the
      // caller's own custom books plus seeds, which is enough to catch the
      // most common collision (a seeded slug); the DB UNIQUE(slug) constraint
      // catches cross-user collisions on insert.
      LExisting := LRepo.ListBooksForUser(CurrentUserId);
      for LBook in LExisting do
        if SameText(LBook.Slug, LSlug) then
        begin
          LError := SSlugTaken;
          Break;
        end;
    end;

    if LError <> '' then
    begin
      ViewData['error'] := LError;
      Render(RenderView('pages/books/form'));
      Exit;
    end;

    LBookId := LRepo.UpsertCustomBook(CurrentUserId, LSlug, LAuthor);

    // Single-language v1: store one title in the user's current UI language.
    SetLength(LBookTitles, 1);
    LBookTitles[0].BookId := LBookId;
    LBookTitles[0].Lang   := LCurrentLang;
    LBookTitles[0].Title  := LTitle;
    LRepo.SetBookTitles(LBookId, LBookTitles);

    // Walk the parallel stat arrays; skip rows whose machine name is empty
    // (lets the user leave any of the three fixed rows blank).
    for I := 0 to High(LStatNames) do
    begin
      if Trim(LStatNames[I]) = '' then
        Continue;
      if I <= High(LStatKinds) then LStatKind := LStatKinds[I]
        else LStatKind := 'integer';
      if I <= High(LStatDefaults) then LStatDefault := LStatDefaults[I]
        else LStatDefault := '';
      LStatDefId := LRepo.UpsertStatDef(LBookId, I,
        Trim(LStatNames[I]), LStatKind, LStatDefault);

      if (I <= High(LStatTitles)) and (Trim(LStatTitles[I]) <> '') then
        LStatTitle := Trim(LStatTitles[I])
      else
        LStatTitle := Trim(LStatNames[I]);
      SetLength(LStatTitleArr, 1);
      LStatTitleArr[0].StatDefId   := LStatDefId;
      LStatTitleArr[0].Lang        := LCurrentLang;
      LStatTitleArr[0].DisplayName := LStatTitle;
      LRepo.SetStatDefTitles(LStatDefId, LStatTitleArr);
    end;
  finally
    LRepo.Free;
  end;

  Flash('success', L10n('flash_saved'));
  Redirect('/books');
end;

end.
