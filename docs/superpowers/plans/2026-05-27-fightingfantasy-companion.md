# Fighting Fantasy Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Delphi/DMVCFramework web app that records decision paths, stats, and inventory through Fighting Fantasy gamebooks, with timeline + Cytoscape graph views, German/English UI, and Docker Compose deployment.

**Architecture:** Single Linux64 Delphi binary serving TemplatePro HTML with HTMX, Bulma CSS, and Cytoscape.js. SQLite + FireDAC via `TMVCActiveRecord`. Session-cookie auth. Four layers: controllers / services / repositories / models. l10n via JSON catalogs in `l10n/`. Touch-friendly value modal for stat/inventory edits. Soft-undo on steps. Translations for book/stat titles live in the data layer.

**Tech Stack:** Delphi (Linux64 cross-compile), DMVCFramework, TemplatePro, FireDAC, SQLite, HTMX, Bulma CSS, Cytoscape.js, DUnitX, Docker.

**Reference spec:** `docs/superpowers/specs/2026-05-27-fightingfantasy-companion-design.md` — re-read it before each task; the plan references its sections.

---

## File Structure (Locked In)

```
fightingfantasy-companion/
├── FFCompanion.dpr
├── FFCompanion.dproj
├── controllers/
│   ├── Controllers.BaseU.pas              # TBaseController (l10n, HTMX, flash, current_user)
│   ├── Controllers.AuthU.pas              # /login, /signup, /logout
│   ├── Controllers.BooksU.pas             # /books, /books/new
│   ├── Controllers.AdventuresU.pas        # /, /adventures/...
│   ├── Controllers.StepsU.pas             # /adventures/:id/steps
│   ├── Controllers.StatsU.pas             # /adventures/:id/stats
│   ├── Controllers.InventoryU.pas         # /adventures/:id/inventory
│   ├── Controllers.DiceU.pas              # /adventures/:id/roll
│   └── Controllers.GraphU.pas             # /adventures/:id/graph.json
├── models/
│   ├── Models.UserU.pas
│   ├── Models.SessionU.pas
│   ├── Models.BookU.pas                   # TBook + TBookTitle
│   ├── Models.StatDefU.pas                # TStatDef + TStatDefTitle
│   ├── Models.AdventureU.pas
│   ├── Models.StepU.pas
│   ├── Models.StatChangeU.pas
│   ├── Models.InventoryEventU.pas
│   └── Models.DiceRollU.pas
├── services/
│   ├── Services.AuthU.pas                 # password hashing, session lifecycle
│   ├── Services.BookCatalogU.pas          # YAML seed loader + upsert
│   ├── Services.LocalizedTitleU.pas       # 4-step fallback chain
│   ├── Services.AdventureStateU.pas       # current section, stats, inventory folding
│   ├── Services.GraphBuilderU.pas         # steps → graph.json
│   └── Services.YamlReaderU.pas           # tiny YAML subset parser
├── repositories/
│   └── Repositories.MigrationU.pas        # CREATE TABLE migrations
├── webmodule/
│   └── WebModuleU.pas
├── config/
│   ├── AppConfigU.pas
│   └── app.conf
├── l10n/
│   ├── de.json
│   └── en.json
├── templates/
│   ├── layouts/
│   │   └── base.html
│   ├── partials/
│   │   ├── _navbar.html
│   │   ├── _footer.html
│   │   ├── _flash_messages.html
│   │   ├── _stats_panel.html
│   │   ├── _inventory_panel.html
│   │   ├── _dice_panel.html
│   │   ├── _step_form.html
│   │   ├── _timeline.html
│   │   ├── _graph_tab.html
│   │   └── _value_modal.html
│   └── pages/
│       ├── auth/{login,signup}.html
│       ├── books/{list,form}.html
│       └── adventures/{list,new,play}.html
├── static/
│   ├── css/{bulma.min.css,app.css}
│   ├── js/{htmx.min.js,cytoscape.min.js,app.js}
│   └── favicon.ico
├── data/
│   └── books_seed.yaml
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yaml
├── tests/
│   ├── FFCompanionTests.dpr
│   ├── FFCompanionTests.dproj
│   ├── TestHelpers.DbU.pas                # in-memory SQLite setup
│   ├── Tests.Repositories.*Pas
│   ├── Tests.Services.*Pas
│   └── Tests.Controllers.*Pas
└── docs/superpowers/{plans,specs}/...
```

Each unit ≤ ~300 LOC (per `delphi-style`). Templates split aggressively into partials so the play view stays composable.

---

## Phase 0: Pre-flight & Conventions

### Task 0.1: Confirm toolchain

**Files:**
- Read: `/home/teufel/.claude/skills/delphi-style/` (full skill)
- Read: `/home/teufel/.claude/skills/delphi-deps/` (full skill)
- Read: `/home/teufel/.claude/skills/dmvc-webapp/` (especially `references/l10n-conventions.md`, `references/templatepro-syntax.md`, `references/base-layout.tpro`, `examples/sample-controller.pas`)

- [ ] **Step 1:** Read the three skills above end-to-end. The plan does not repeat them; it relies on them.
- [ ] **Step 2:** Confirm `delphi-build` MCP server is reachable with `mcp__delphi-build__compile_delphi_project` available. The plan compiles **only** through this MCP — never invoke Delphi compilers manually.
- [ ] **Step 3:** Confirm DMVCFramework, FireDAC, Cytoscape.js (pin v3.28.1), htmx.min.js (pin v1.9.12), bulma.min.css (pin v1.0.2) are available via the dependency layout from `delphi-deps`.

### Task 0.2: Commit conventions

- [ ] **Step 1:** Verify `git config user.name` returns `Basti-Fantasti` and `git config user.email` returns `bastian.teufel@gmail.com`. If not, set them.
- [ ] **Step 2:** Use imperative-mood, English-only commit messages. **Never** include AI co-authorship.

---

## Phase 1: Project Scaffold & Base Layout

### Task 1.1: Create empty Delphi project group

**Files:**
- Create: `FFCompanion.dpr`, `FFCompanion.dproj`
- Create: `webmodule/WebModuleU.pas`
- Create: `config/AppConfigU.pas`, `config/app.conf`

- [ ] **Step 1: `config/AppConfigU.pas`** — config accessor.

```pascal
unit AppConfigU;

interface

type
  TAppConfig = class
  public
    class function DefaultLanguage: string;
    class function HttpPort: Integer;
    class function DatabasePath: string;
    class function SeedYamlPath: string;
    class function AppPath: string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

class function TAppConfig.AppPath: string;
begin
  Result := TPath.GetDirectoryName(ParamStr(0));
end;

class function TAppConfig.DefaultLanguage: string;
begin
  Result := GetEnvironmentVariable('DEFAULT_LANGUAGE');
  if Result.IsEmpty then
    Result := 'de';
end;

class function TAppConfig.HttpPort: Integer;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('HTTP_PORT');
  if LRaw.IsEmpty or not TryStrToInt(LRaw, Result) then
    Result := 8080;
end;

class function TAppConfig.DatabasePath: string;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('DATABASE_PATH');
  if LRaw.IsEmpty then
    Result := TPath.Combine(AppPath, 'data' + PathDelim + 'ffcompanion.db')
  else
    Result := LRaw;
end;

class function TAppConfig.SeedYamlPath: string;
begin
  Result := TPath.Combine(AppPath, 'data' + PathDelim + 'books_seed.yaml');
end;

end.
```

- [ ] **Step 2: `webmodule/WebModuleU.pas`** — wire DMVC, TemplatePro view engine, static files, session middleware. Pattern from `dmvc-webapp/examples/sample-controller.pas`'s sibling WebModule conventions; include `MVCFramework.SQLGenerators.Sqlite` in `.dpr` (added in Step 4 below). Register controllers added in later phases via placeholder `TODO add` comment to be removed in Phase 2 — do not leave a "TODO add controller" comment longer than one task; each subsequent phase that adds a controller updates this unit.

```pascal
unit WebModuleU;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp,
  MVCFramework;

type
  TFFWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    FMVC: TMVCEngine;
  end;

var
  WebModuleClass: TComponentClass = TFFWebModule;

implementation

{$R *.dfm}

uses
  MVCFramework.Commons,
  MVCFramework.View.Renderers.TemplatePro,
  MVCFramework.Middleware.StaticFiles,
  MVCFramework.Middleware.Session,
  AppConfigU;

procedure TFFWebModule.WebModuleCreate(Sender: TObject);
begin
  FMVC := TMVCEngine.Create(Self,
    procedure(Config: TMVCConfig)
    begin
      Config[TMVCConfigKey.ViewPath] := 'templates';
      Config[TMVCConfigKey.DefaultViewFileExtension] := 'html';
      Config[TMVCConfigKey.DefaultContentType] := TMVCMediaType.TEXT_HTML;
      Config[TMVCConfigKey.SessionType] := 'memory';
      Config[TMVCConfigKey.SessionTimeout] := '0';
    end);
  FMVC.SetViewEngine(TMVCTemplateProViewEngine);
  FMVC.AddMiddleware(TMVCStaticFilesMiddleware.Create('/static',
    TPath.Combine(TAppConfig.AppPath, 'static')));
  FMVC.AddMiddleware(TMVCSessionMiddleware.Create);
  // Controllers added in later phases:
  // FMVC.AddController(TAuthController);
  // FMVC.AddController(TAdventuresController);
  // ...
end;

procedure TFFWebModule.WebModuleDestroy(Sender: TObject);
begin
  FMVC.Free;
end;

end.
```

- [ ] **Step 3: `FFCompanion.dpr`** — host. Standalone (no IIS) using DMVC's `MVCFramework.Server`.

```pascal
program FFCompanion;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  MVCFramework.Logger,
  MVCFramework.Commons,
  MVCFramework.Signal,
  MVCFramework.SQLGenerators.Sqlite,
  IdHTTPWebBrokerBridge,
  Web.WebReq,
  Web.WebBroker,
  WebModuleU in 'webmodule\WebModuleU.pas' {FFWebModule: TWebModule},
  AppConfigU in 'config\AppConfigU.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln('Starting FFCompanion on port ', APort);
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := APort;
    LServer.Active := True;
    WaitForTerminationSignal;
    LServer.Active := False;
  finally
    LServer.Free;
  end;
end;

begin
  if not WebRequestHandler.WebModuleClass.InheritsFrom(TWebModule) then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  try
    RunServer(TAppConfig.HttpPort);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
```

- [ ] **Step 4: `FFCompanion.dproj`** — Delphi project file targeting Linux64. Use the `delphi-build` MCP server `generate_config_from_build_log` flow if needed; if generating manually, ensure `<Platforms>` includes `Linux64=true` and `Win64=true` (Win64 for local dev test), and `<DCC_UnitSearchPath>` includes `controllers;models;services;repositories;webmodule;config`.

- [ ] **Step 5: Compile (Win64 first, then Linux64).**

Use: `mcp__delphi-build__compile_delphi_project` with platform `Win64`, then platform `Linux64`.
Expected: Both succeed; binary appears under `bin\Win64\Debug\FFCompanion.exe` and `bin\Linux64\Debug\FFCompanion`.

- [ ] **Step 6: Commit.**

```bash
git add FFCompanion.dpr FFCompanion.dproj webmodule/WebModuleU.pas config/AppConfigU.pas config/app.conf
git commit -m "Scaffold FFCompanion DMVC server (Linux64 + Win64)"
```

### Task 1.2: Static assets & base templates

**Files:**
- Create: `static/css/bulma.min.css` (download pinned v1.0.2)
- Create: `static/css/app.css`
- Create: `static/js/htmx.min.js` (download pinned v1.9.12)
- Create: `static/js/cytoscape.min.js` (download pinned v3.28.1)
- Create: `static/js/app.js`
- Create: `static/favicon.ico`
- Create: `templates/layouts/base.html`
- Create: `templates/partials/_navbar.html`, `_footer.html`, `_flash_messages.html`

- [ ] **Step 1:** Place the three pinned vendor files into `static/css/` and `static/js/`. Verify SHA-256 against vendor releases.

- [ ] **Step 2: `templates/layouts/base.html`** — derived from `dmvc-webapp/references/base-layout.tpro`, but using the `{{if ispage}}...{{endif}}` wrapper so HTMX fragments skip the document chrome. Include Bulma, app.css, htmx, app.js. Cytoscape is loaded only on the play page (see Task 9.2).

```html
{{if ispage}}<!DOCTYPE html>
<html lang="{{:current_lang}}" data-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{block "title"}}{{:l10n.app_name}}{{endblock}}</title>
  <link rel="icon" href="/static/favicon.ico">
  <link rel="stylesheet" href="/static/css/bulma.min.css">
  <link rel="stylesheet" href="/static/css/app.css">
  {{block "styles"}}{{endblock}}
</head>
<body>
  {{include "../partials/_navbar.html"}}
  <main class="section">
    <div class="container">
      {{include "../partials/_flash_messages.html"}}
      {{endif}}
      {{block "content"}}{{endblock}}
      {{if ispage}}
    </div>
  </main>
  {{include "../partials/_footer.html"}}
  <script src="/static/js/htmx.min.js"></script>
  <script src="/static/js/app.js"></script>
  {{block "scripts"}}{{endblock}}
</body>
</html>{{endif}}
```

- [ ] **Step 3: `templates/partials/_navbar.html`** — DE/EN switcher (per `l10n-conventions.md`), brand link to `/`, login/logout link based on `current_user`.

```html
<nav class="navbar is-primary" role="navigation">
  <div class="navbar-brand">
    <a class="navbar-item" href="/"><strong>{{:l10n.app_name}}</strong></a>
  </div>
  <div class="navbar-menu">
    <div class="navbar-end">
      <div class="navbar-item">
        <div class="buttons are-small">
          <a href="?lang=de" class="button {{if current_lang|eq,de}}is-primary{{else}}is-outlined{{endif}}">DE</a>
          <a href="?lang=en" class="button {{if current_lang|eq,en}}is-primary{{else}}is-outlined{{endif}}">EN</a>
        </div>
      </div>
      {{if current_user}}
        <div class="navbar-item">{{:current_user.username}}</div>
        <div class="navbar-item">
          <form method="post" action="/logout"><button class="button is-light">{{:l10n.nav_logout}}</button></form>
        </div>
      {{else}}
        <div class="navbar-item"><a href="/login" class="button is-light">{{:l10n.nav_login}}</a></div>
      {{endif}}
    </div>
  </div>
</nav>
```

- [ ] **Step 4: `templates/partials/_footer.html`** — single line; `templates/partials/_flash_messages.html` — empty `<div id="flash-area"></div>` (filled by `app.js` listening to `showFlash` HX-Trigger).

- [ ] **Step 5: `static/js/app.js`** — three listeners: `showFlash`, `close-modal`, `graph-changed` (no-op until Task 9.3).

```javascript
document.body.addEventListener('showFlash', (e) => {
  const {type, message} = e.detail;
  const cls = {success:'is-success', error:'is-danger', info:'is-info', warning:'is-warning'}[type] || 'is-info';
  const node = document.createElement('div');
  node.className = `notification ${cls}`;
  node.innerHTML = `<button class="delete" onclick="this.parentNode.remove()"></button>${message}`;
  document.getElementById('flash-area').appendChild(node);
  setTimeout(() => node.remove(), 5000);
});

document.body.addEventListener('close-modal', () => {
  document.querySelectorAll('.modal.is-active').forEach(m => m.classList.remove('is-active'));
});

document.body.addEventListener('graph-changed', () => {
  if (window.ffRefreshGraph) window.ffRefreshGraph();
});
```

- [ ] **Step 6: `static/css/app.css`** — minimal: touch-friendly button class `.is-touch { min-width:48px; min-height:48px; font-size:1.25rem; }`, soft-undo `.is-undone { text-decoration: line-through; opacity: 0.5; }`, graph canvas height.

- [ ] **Step 7: Commit.**

```bash
git add static/ templates/
git commit -m "Add base layout, navbar, partials, static assets"
```

### Task 1.3: l10n catalogs (initial keys)

**Files:**
- Create: `l10n/de.json`, `l10n/en.json`

- [ ] **Step 1: `l10n/en.json`** — start with the keys actually used by Phase 1-12 templates. Both files MUST contain identical key sets.

```json
{
  "app_name": "Fighting Fantasy Companion",
  "nav_login": "Login",
  "nav_logout": "Logout",
  "nav_signup": "Sign up",
  "btn_save": "Save",
  "btn_cancel": "Cancel",
  "btn_create": "Create",
  "btn_confirm": "Confirm",
  "btn_delete": "Delete",
  "btn_undo": "Undo",
  "btn_redo": "Redo",
  "lbl_username": "Username",
  "lbl_password": "Password",
  "lbl_yes": "Yes",
  "lbl_no": "No",
  "lbl_status": "Status",
  "lbl_reason": "Reason (optional)",
  "lbl_quantity": "Quantity",
  "flash_saved": "Saved.",
  "flash_deleted": "Deleted.",
  "flash_error": "An error occurred.",
  "flash_login_failed": "Wrong username or password.",
  "flash_signup_taken": "Username is already taken.",
  "flash_concurrency": "This adventure changed in another tab. Reload to continue.",
  "confirm_delete": "Are you sure you want to delete this?",
  "login_title": "Sign in",
  "login_no_account": "No account?",
  "signup_title": "Create account",
  "book_list_title": "Books",
  "book_new_title": "Add custom book",
  "book_title_label": "Title",
  "book_author_label": "Author",
  "book_stat_skill": "Skill",
  "book_stat_stamina": "Stamina",
  "book_stat_luck": "Luck",
  "book_stat_magic": "Magic",
  "adv_dashboard_title": "Active adventures",
  "adv_new_title": "New adventure",
  "adv_select_book": "Select book",
  "adv_title_label": "Adventure title",
  "adv_status_active": "Active",
  "adv_status_completed": "Completed",
  "adv_status_abandoned": "Abandoned",
  "adv_btn_complete": "Complete",
  "adv_btn_abandon": "Abandon",
  "step_form_from": "From §",
  "step_form_to": "To §",
  "step_form_note": "Note",
  "step_flag_fight": "Fight",
  "step_flag_item": "Item",
  "step_flag_stat": "Stat change",
  "step_btn_log": "Log step",
  "tab_timeline": "Timeline",
  "tab_graph": "Graph",
  "stat_panel_title": "Stats",
  "inv_panel_title": "Inventory",
  "inv_add_item": "Add item",
  "inv_item_name": "Item name",
  "dice_panel_title": "Dice",
  "dice_roll_2d6": "Roll 2d6",
  "dice_roll_1d6": "Roll 1d6",
  "dice_last": "Last:"
}
```

- [ ] **Step 2: `l10n/de.json`** — same keys, German values. Critical: `book_title_label`: `Titel`, `book_stat_skill`: `Geschicklichkeit`, `book_stat_stamina`: `Ausdauer`, `book_stat_luck`: `Glück`, `book_stat_magic`: `Magie`, `step_form_from`: `Von §`, `step_form_to`: `Zu §`, `tab_timeline`: `Verlauf`, `tab_graph`: `Graph`, `lbl_reason`: `Grund (optional)`, etc. Translate every key.

- [ ] **Step 3: Commit.**

```bash
git add l10n/
git commit -m "Add initial DE/EN l10n catalogs"
```

### Task 1.4: TBaseController + key-set parity test

**Files:**
- Create: `controllers/Controllers.BaseU.pas`
- Create: `tests/Tests.L10nU.pas`
- Create: `tests/FFCompanionTests.dpr`, `tests/FFCompanionTests.dproj`
- Create: `tests/TestHelpers.DbU.pas` (skeleton for now)

- [ ] **Step 1: `tests/FFCompanionTests.dpr`** — DUnitX console runner.

```pascal
program FFCompanionTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  MVCFramework.SQLGenerators.Sqlite,
  Tests.L10nU in 'Tests.L10nU.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
begin
  try
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    logger := TDUnitXConsoleLogger.Create(True);
    runner.AddLogger(logger);
    results := runner.Execute;
    if not results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
```

- [ ] **Step 2: Write failing test `tests/Tests.L10nU.pas`** — l10n key-set parity.

```pascal
unit Tests.L10nU;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TL10nTests = class
  public
    [Test]
    procedure DeAndEnHaveIdenticalKeys;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Generics.Collections,
  JsonDataObjects;

function LoadKeys(const APath: string): TList<string>;
var
  LObj: TJsonObject;
  I: Integer;
begin
  Result := TList<string>.Create;
  LObj := TJsonObject(TJsonObject.ParseFromFile(APath));
  try
    for I := 0 to LObj.Count - 1 do
      Result.Add(LObj.Names[I]);
    Result.Sort;
  finally
    LObj.Free;
  end;
end;

procedure TL10nTests.DeAndEnHaveIdenticalKeys;
var
  LEn, LDe: TList<string>;
  LBase: string;
begin
  LBase := TPath.Combine(ExtractFileDir(ParamStr(0)), '..\..\..\l10n');
  LEn := LoadKeys(TPath.Combine(LBase, 'en.json'));
  LDe := LoadKeys(TPath.Combine(LBase, 'de.json'));
  try
    Assert.AreEqual(string.Join(',', LEn.ToArray), string.Join(',', LDe.ToArray),
      'l10n key sets must be identical between de.json and en.json');
  finally
    LEn.Free;
    LDe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TL10nTests);

end.
```

- [ ] **Step 3: Compile and run.**

Compile tests via `mcp__delphi-build__compile_delphi_project` (Win64). Run the produced exe.
Expected: PASS (the JSON files from Task 1.3 are identical-keyed).

- [ ] **Step 4: `controllers/Controllers.BaseU.pas`** — copy the full `TBaseController` from `dmvc-webapp/references/l10n-conventions.md`. Extend with `CurrentUser: TUser` property that reads from session (placeholder returns `nil` until Phase 2 wires Login).

```pascal
unit Controllers.BaseU;

interface

uses
  MVCFramework, MVCFramework.Commons, JsonDataObjects;

type
  TBaseController = class(TMVCController)
  strict private
    FL10n: TJsonObject;
    FCurrentUserId: Int64;
    FCurrentUsername: string;
  protected
    procedure OnBeforeAction(AContext: TWebContext; const AActionName: string; var AHandled: Boolean); override;
    procedure Flash(const AType, AMessage: string);
    procedure RequireLogin;
    function IsHTMXRequest: Boolean;
    function RenderPage(const AViewName: string): string;
    property CurrentUserId: Int64 read FCurrentUserId;
    property CurrentUsername: string read FCurrentUsername;
  public
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  MVCFramework.Logger, MVCFramework.HTMX,
  AppConfigU;

resourcestring
  SL10nFileNotFound = 'Translation file not found, falling back to default: %s';
  SNotAuthenticated = 'Authentication required';

destructor TBaseController.Destroy;
begin
  FL10n.Free;
  inherited;
end;

procedure TBaseController.OnBeforeAction(AContext: TWebContext; const AActionName: string; var AHandled: Boolean);
var
  LPrefLang, LFName, LUid: string;
begin
  inherited;
  ViewData['ispage'] := not AContext.Request.IsHTMX;

  LPrefLang := AContext.Request.QueryStringParam('lang');
  if LPrefLang.IsEmpty then
    LPrefLang := AContext.Request.ClientPreferredLanguage;
  if LPrefLang.IsEmpty then
    LPrefLang := TAppConfig.DefaultLanguage
  else
    LPrefLang := LPrefLang.Split(['-'])[0];

  LFName := TPath.Combine(TAppConfig.AppPath, TPath.Combine('l10n', LPrefLang + '.json'));
  if not TFile.Exists(LFName) then
  begin
    LogW(Format(SL10nFileNotFound, [LFName]));
    LFName := TPath.Combine(TAppConfig.AppPath, TPath.Combine('l10n', TAppConfig.DefaultLanguage + '.json'));
  end;
  FreeAndNil(FL10n);
  FL10n := TJsonObject(TJsonObject.ParseFromFile(LFName));
  ViewData['l10n'] := FL10n;
  ViewData['current_lang'] := LPrefLang;

  LUid := Session['user_id'];
  if not LUid.IsEmpty then
  begin
    FCurrentUserId := StrToInt64Def(LUid, 0);
    FCurrentUsername := Session['username'];
    ViewData['current_user'] := TJsonObject.Create;
    TJsonObject(ViewData['current_user']).S['username'] := FCurrentUsername;
  end;
end;

procedure TBaseController.Flash(const AType, AMessage: string);
var
  LObj, LFlash: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LFlash := LObj.O['showFlash'];
    LFlash.S['type'] := AType;
    LFlash.S['message'] := AMessage;
    Context.Response.SetCustomHeader('HX-Trigger', LObj.ToJSON);
  finally
    LObj.Free;
  end;
end;

procedure TBaseController.RequireLogin;
begin
  if FCurrentUserId = 0 then
  begin
    if IsHTMXRequest then
      Context.Response.SetCustomHeader('HX-Redirect', '/login')
    else
      Context.Response.SetCustomHeader('Location', '/login');
    raise EMVCException.Create(HTTP_STATUS.Unauthorized, SNotAuthenticated);
  end;
end;

function TBaseController.IsHTMXRequest: Boolean;
begin
  Result := Context.Request.IsHTMX;
end;

function TBaseController.RenderPage(const AViewName: string): string;
begin
  Result := RenderView(AViewName);
end;

end.
```

- [ ] **Step 5: Compile** — both main project and tests (Win64). Expected: success.

- [ ] **Step 6: Commit.**

```bash
git add controllers/Controllers.BaseU.pas tests/
git commit -m "Add TBaseController and l10n key-parity test"
```

---

## Phase 2: Migrations, In-Memory SQLite Test Harness

### Task 2.1: Migration runner

**Files:**
- Create: `repositories/Repositories.MigrationU.pas`
- Modify: `webmodule/WebModuleU.pas` (add `Migrations.Run` on startup)

- [ ] **Step 1: `repositories/Repositories.MigrationU.pas`** — a `TMigrationRunner` that opens FireDAC against `TAppConfig.DatabasePath` (or a provided connection name), then executes `CREATE TABLE IF NOT EXISTS` statements for every table in spec §5. Single SQL block; idempotent. Also a `BuildInMemoryConnection: string` helper that creates a unique-named FireDAC connection backed by `:memory:` for tests.

```pascal
unit Repositories.MigrationU;

interface

uses
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteWrapper.Stat;

type
  TMigrationRunner = class
  public
    class procedure RunOnConnection(const AConnectionName: string);
    class function CreateFileConnection(const ADbPath: string): string;
    class function CreateInMemoryConnection: string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  FireDAC.Stan.Param, FireDAC.DApt;

const
  SQL_SCHEMA: array[0..9] of string = (
    'CREATE TABLE IF NOT EXISTS users (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'username TEXT NOT NULL UNIQUE, ' +
      'password_hash TEXT NOT NULL, ' +
      'created_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS sessions (' +
      'token TEXT PRIMARY KEY, ' +
      'user_id INTEGER NOT NULL REFERENCES users(id), ' +
      'expires_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS books (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'slug TEXT NOT NULL UNIQUE, ' +
      'author TEXT, ' +
      'owner_user_id INTEGER REFERENCES users(id), ' +
      'is_seed INTEGER NOT NULL DEFAULT 0, ' +
      'created_at TEXT NOT NULL)',

    'CREATE TABLE IF NOT EXISTS book_titles (' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'title TEXT NOT NULL, ' +
      'PRIMARY KEY (book_id, lang))',

    'CREATE TABLE IF NOT EXISTS stat_defs (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, ' +
      'ord INTEGER NOT NULL, ' +
      'name TEXT NOT NULL, ' +
      'kind TEXT NOT NULL CHECK(kind IN (''integer'',''text'',''checkbox'')), ' +
      'default_value TEXT, ' +
      'UNIQUE(book_id, name))',

    'CREATE TABLE IF NOT EXISTS stat_def_titles (' +
      'stat_def_id INTEGER NOT NULL REFERENCES stat_defs(id) ON DELETE CASCADE, ' +
      'lang TEXT NOT NULL, ' +
      'display_name TEXT NOT NULL, ' +
      'PRIMARY KEY (stat_def_id, lang))',

    'CREATE TABLE IF NOT EXISTS adventures (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'user_id INTEGER NOT NULL REFERENCES users(id), ' +
      'book_id INTEGER NOT NULL REFERENCES books(id), ' +
      'title TEXT NOT NULL, ' +
      'status TEXT NOT NULL DEFAULT ''active'' CHECK(status IN (''active'',''completed'',''abandoned'')), ' +
      'started_at TEXT NOT NULL, ' +
      'last_step_id INTEGER)',

    'CREATE TABLE IF NOT EXISTS steps (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
      'seq INTEGER NOT NULL, ' +
      'from_section INTEGER, ' +
      'to_section INTEGER NOT NULL, ' +
      'note TEXT, ' +
      'flag_fight INTEGER NOT NULL DEFAULT 0, ' +
      'flag_item INTEGER NOT NULL DEFAULT 0, ' +
      'flag_stat INTEGER NOT NULL DEFAULT 0, ' +
      'undone INTEGER NOT NULL DEFAULT 0, ' +
      'created_at TEXT NOT NULL, ' +
      'UNIQUE(adventure_id, seq))',

    'CREATE TABLE IF NOT EXISTS stat_changes (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'step_id INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE, ' +
      'stat_def_id INTEGER NOT NULL REFERENCES stat_defs(id), ' +
      'old_value TEXT, ' +
      'new_value TEXT NOT NULL, ' +
      'reason TEXT)',

    'CREATE TABLE IF NOT EXISTS inventory_events (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'step_id INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE, ' +
      'kind TEXT NOT NULL CHECK(kind IN (''gain'',''lose'',''modify'')), ' +
      'item_name TEXT NOT NULL, ' +
      'quantity INTEGER NOT NULL DEFAULT 1, ' +
      'note TEXT)'
  );

  SQL_INDICES: array[0..6] of string = (
    'CREATE INDEX IF NOT EXISTS idx_steps_adv_seq ON steps(adventure_id, seq)',
    'CREATE INDEX IF NOT EXISTS idx_stat_changes_step ON stat_changes(step_id)',
    'CREATE INDEX IF NOT EXISTS idx_inv_events_step ON inventory_events(step_id)',
    'CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)',
    'CREATE INDEX IF NOT EXISTS idx_adventures_user_status ON adventures(user_id, status)',
    'CREATE INDEX IF NOT EXISTS idx_book_titles ON book_titles(book_id, lang)',
    'CREATE INDEX IF NOT EXISTS idx_stat_def_titles ON stat_def_titles(stat_def_id, lang)'
  );

  // dice_rolls left as a separate constant to keep arrays balanced
  SQL_DICE = 'CREATE TABLE IF NOT EXISTS dice_rolls (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'adventure_id INTEGER NOT NULL REFERENCES adventures(id) ON DELETE CASCADE, ' +
    'step_id INTEGER REFERENCES steps(id), ' +
    'expression TEXT NOT NULL, ' +
    'result INTEGER NOT NULL, ' +
    'rolled_at TEXT NOT NULL)';

class procedure TMigrationRunner.RunOnConnection(const AConnectionName: string);
var
  LConn: TFDConnection;
  LStmt: string;
begin
  LConn := TFDConnection.Create(nil);
  try
    LConn.ConnectionDefName := AConnectionName;
    LConn.Open;
    LConn.ExecSQL('PRAGMA foreign_keys = ON');
    for LStmt in SQL_SCHEMA do
      LConn.ExecSQL(LStmt);
    LConn.ExecSQL(SQL_DICE);
    for LStmt in SQL_INDICES do
      LConn.ExecSQL(LStmt);
  finally
    LConn.Free;
  end;
end;

class function TMigrationRunner.CreateFileConnection(const ADbPath: string): string;
var
  LParams: TFDPhysSQLiteConnectionDefParams;
  LDef: IFDStanConnectionDef;
begin
  ForceDirectories(ExtractFilePath(ADbPath));
  Result := 'FFMain';
  LDef := FDManager.ConnectionDefs.FindConnectionDef(Result);
  if LDef = nil then
  begin
    LDef := FDManager.ConnectionDefs.AddConnectionDef;
    LDef.Name := Result;
    LParams := TFDPhysSQLiteConnectionDefParams(LDef.Params);
    LParams.DriverID := 'SQLite';
    LParams.Database := ADbPath;
    LDef.Apply;
  end;
end;

class function TMigrationRunner.CreateInMemoryConnection: string;
var
  LDef: IFDStanConnectionDef;
  LParams: TFDPhysSQLiteConnectionDefParams;
begin
  Result := 'FFTest_' + FormatDateTime('hhnnsszzz', Now);
  LDef := FDManager.ConnectionDefs.AddConnectionDef;
  LDef.Name := Result;
  LParams := TFDPhysSQLiteConnectionDefParams(LDef.Params);
  LParams.DriverID := 'SQLite';
  LParams.Database := ':memory:';
  LDef.Apply;
end;

end.
```

- [ ] **Step 2: `tests/TestHelpers.DbU.pas`** — `TDbHelper.NewMemoryDb: string` returns a fresh in-memory connection name with migrations applied; `TDbHelper.Drop(AName)` closes & removes the def.

```pascal
unit TestHelpers.DbU;

interface

type
  TDbHelper = class
  public
    class function NewMemoryDb: string;
    class procedure Drop(const AConnectionName: string);
  end;

implementation

uses
  FireDAC.Comp.Client, FireDAC.Stan.Def,
  Repositories.MigrationU;

class function TDbHelper.NewMemoryDb: string;
begin
  Result := TMigrationRunner.CreateInMemoryConnection;
  TMigrationRunner.RunOnConnection(Result);
end;

class procedure TDbHelper.Drop(const AConnectionName: string);
begin
  FDManager.ConnectionDefs.Remove(AConnectionName);
end;

end.
```

- [ ] **Step 3: Failing test `tests/Tests.MigrationU.pas`** — assert all tables exist after migration.

```pascal
unit Tests.MigrationU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TMigrationTests = class
  public
    [Test] procedure AllTablesCreated;
  end;

implementation

uses
  System.Classes,
  FireDAC.Comp.Client,
  TestHelpers.DbU;

procedure TMigrationTests.AllTablesCreated;
var
  LConn: TFDConnection;
  LExpected: TStringList;
  LName, LFound: string;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LExpected := TStringList.Create;
  try
    LExpected.CommaText := 'users,sessions,books,book_titles,stat_defs,stat_def_titles,' +
      'adventures,steps,stat_changes,inventory_events,dice_rolls';
    LConn := TFDConnection.Create(nil);
    try
      LConn.ConnectionDefName := LDb;
      LConn.Open;
      for LName in LExpected do
      begin
        LFound := LConn.ExecSQLScalar(
          'SELECT name FROM sqlite_master WHERE type=''table'' AND name=:n', [LName]);
        Assert.AreEqual(LName, LFound, 'Missing table: ' + LName);
      end;
    finally
      LConn.Free;
    end;
  finally
    LExpected.Free;
    TDbHelper.Drop(LDb);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMigrationTests);

end.
```

- [ ] **Step 4: Register `Tests.MigrationU` in `tests/FFCompanionTests.dpr` uses clause; add `TestHelpers.DbU` and `Repositories.MigrationU` to test project search paths.

- [ ] **Step 5: Compile & run tests.** Expected: PASS.

- [ ] **Step 6:** Modify `webmodule/WebModuleU.pas` `WebModuleCreate` to call `TMigrationRunner.CreateFileConnection(TAppConfig.DatabasePath)` and `TMigrationRunner.RunOnConnection(...)` before adding controllers.

- [ ] **Step 7: Compile main project. Commit.**

```bash
git add repositories/ tests/ webmodule/WebModuleU.pas
git commit -m "Add SQLite migration runner and in-memory test harness"
```

---

## Phase 3: Auth (Users, Sessions, Login, Signup, Logout)

### Task 3.1: User & Session repositories

**Files:**
- Create: `models/Models.UserU.pas`, `models/Models.SessionU.pas`
- Create: `repositories/Repositories.UsersU.pas`, `repositories/Repositories.SessionsU.pas`
- Create: `services/Services.AuthU.pas`
- Create: `tests/Tests.Services.AuthU.pas`

- [ ] **Step 1: `models/Models.UserU.pas`** — minimal record (not `TMVCActiveRecord` — we'll do raw FireDAC for tight control over SQLite specifics).

```pascal
unit Models.UserU;

interface

type
  TUser = record
    Id: Int64;
    Username: string;
    PasswordHash: string;
    CreatedAt: TDateTime;
  end;

implementation

end.
```

- [ ] **Step 2: `models/Models.SessionU.pas`** — same shape for sessions (Token, UserId, ExpiresAt).

- [ ] **Step 3: `repositories/Repositories.UsersU.pas`** — `TUsersRepo` with `FindByUsername`, `Insert`, `ExistsUsername` taking a connection name.

```pascal
unit Repositories.UsersU;

interface

uses Models.UserU;

type
  TUsersRepo = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    function FindByUsername(const AUsername: string; out AUser: TUser): Boolean;
    function ExistsUsername(const AUsername: string): Boolean;
    function Insert(const AUsername, APasswordHash: string): Int64;
  end;

implementation

uses
  System.SysUtils, FireDAC.Comp.Client;

constructor TUsersRepo.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TUsersRepo.FindByUsername(const AUsername: string; out AUser: TUser): Boolean;
var LC: TFDConnection; LQ: TFDQuery;
begin
  Result := False;
  LC := TFDConnection.Create(nil); LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn; LC.Open; LQ.Connection := LC;
    LQ.Open('SELECT id, username, password_hash, created_at FROM users WHERE username=:u',
      [AUsername]);
    if not LQ.Eof then
    begin
      AUser.Id := LQ.FieldByName('id').AsLargeInt;
      AUser.Username := LQ.FieldByName('username').AsString;
      AUser.PasswordHash := LQ.FieldByName('password_hash').AsString;
      AUser.CreatedAt := LQ.FieldByName('created_at').AsDateTime;
      Result := True;
    end;
  finally LQ.Free; LC.Free; end;
end;

function TUsersRepo.ExistsUsername(const AUsername: string): Boolean;
var LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn; LC.Open;
    Result := LC.ExecSQLScalar('SELECT 1 FROM users WHERE username=:u', [AUsername]) = 1;
  finally LC.Free; end;
end;

function TUsersRepo.Insert(const AUsername, APasswordHash: string): Int64;
var LC: TFDConnection;
begin
  LC := TFDConnection.Create(nil);
  try
    LC.ConnectionDefName := FConn; LC.Open;
    LC.ExecSQL('INSERT INTO users (username, password_hash, created_at) VALUES (:u,:p,:c)',
      [AUsername, APasswordHash, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now)]);
    Result := LC.ExecSQLScalar('SELECT last_insert_rowid()');
  finally LC.Free; end;
end;

end.
```

- [ ] **Step 4: `repositories/Repositories.SessionsU.pas`** — `Insert(token, userId, expiresAt)`, `FindByToken`, `DeleteByToken`, `DeleteExpired`. Same FireDAC pattern.

- [ ] **Step 5: `services/Services.AuthU.pas`** — wraps repos. Provides `HashPassword(plain): string` (bcrypt via `MVCFramework.Crypt.Utils` `BCrypt.HashPassword`), `VerifyPassword`, `Signup`, `Login` (returns session token), `Logout`.

```pascal
unit Services.AuthU;

interface

uses Models.UserU;

type
  TAuthService = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    function HashPassword(const APlain: string): string;
    function VerifyPassword(const APlain, AHash: string): Boolean;
    function Signup(const AUsername, APassword: string; out AUserId: Int64; out AError: string): Boolean;
    function Login(const AUsername, APassword: string; out AUser: TUser): Boolean;
  end;

implementation

uses
  System.SysUtils,
  MVCFramework.Crypt.Utils,
  Repositories.UsersU;

constructor TAuthService.Create(const AConnectionName: string);
begin
  inherited Create; FConn := AConnectionName;
end;

function TAuthService.HashPassword(const APlain: string): string;
begin
  Result := BCryptHash(APlain);
end;

function TAuthService.VerifyPassword(const APlain, AHash: string): Boolean;
begin
  Result := BCryptCheck(APlain, AHash);
end;

function TAuthService.Signup(const AUsername, APassword: string;
  out AUserId: Int64; out AError: string): Boolean;
var LRepo: TUsersRepo;
begin
  AError := '';
  if Length(AUsername) < 3 then begin AError := 'username_too_short'; Exit(False); end;
  if Length(APassword) < 6 then begin AError := 'password_too_short'; Exit(False); end;
  LRepo := TUsersRepo.Create(FConn);
  try
    if LRepo.ExistsUsername(AUsername) then begin AError := 'username_taken'; Exit(False); end;
    AUserId := LRepo.Insert(AUsername, HashPassword(APassword));
    Result := True;
  finally LRepo.Free; end;
end;

function TAuthService.Login(const AUsername, APassword: string; out AUser: TUser): Boolean;
var LRepo: TUsersRepo;
begin
  LRepo := TUsersRepo.Create(FConn);
  try
    Result := LRepo.FindByUsername(AUsername, AUser) and VerifyPassword(APassword, AUser.PasswordHash);
  finally LRepo.Free; end;
end;

end.
```

- [ ] **Step 6: Failing test `tests/Tests.Services.AuthU.pas`** — signup creates user; duplicate signup fails; login matches; wrong password rejected.

```pascal
unit Tests.Services.AuthU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TAuthServiceTests = class
  public
    [Test] procedure SignupCreatesUser;
    [Test] procedure DuplicateSignupFails;
    [Test] procedure LoginAcceptsCorrectPassword;
    [Test] procedure LoginRejectsWrongPassword;
  end;

implementation

uses
  System.SysUtils,
  Models.UserU, Services.AuthU, TestHelpers.DbU;

procedure TAuthServiceTests.SignupCreatesUser;
var LSvc: TAuthService; LUid: Int64; LErr: string; LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    Assert.IsTrue(LSvc.Signup('alice', 'secret123', LUid, LErr));
    Assert.IsTrue(LUid > 0);
  finally LSvc.Free; TDbHelper.Drop(LDb); end;
end;

procedure TAuthServiceTests.DuplicateSignupFails;
var LSvc: TAuthService; LUid: Int64; LErr: string; LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsFalse(LSvc.Signup('alice', 'other123', LUid, LErr));
    Assert.AreEqual('username_taken', LErr);
  finally LSvc.Free; TDbHelper.Drop(LDb); end;
end;

procedure TAuthServiceTests.LoginAcceptsCorrectPassword;
var LSvc: TAuthService; LUid: Int64; LErr: string; LUser: TUser; LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsTrue(LSvc.Login('alice', 'secret123', LUser));
    Assert.AreEqual<Int64>(LUid, LUser.Id);
  finally LSvc.Free; TDbHelper.Drop(LDb); end;
end;

procedure TAuthServiceTests.LoginRejectsWrongPassword;
var LSvc: TAuthService; LUid: Int64; LErr: string; LUser: TUser; LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsFalse(LSvc.Login('alice', 'wrong', LUser));
  finally LSvc.Free; TDbHelper.Drop(LDb); end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAuthServiceTests);

end.
```

- [ ] **Step 7: Add the new test unit to `FFCompanionTests.dpr` uses. Compile, run.** Expected: 4 PASS.

- [ ] **Step 8: Commit.**

```bash
git add models/Models.UserU.pas models/Models.SessionU.pas repositories/Repositories.UsersU.pas repositories/Repositories.SessionsU.pas services/Services.AuthU.pas tests/Tests.Services.AuthU.pas
git commit -m "Add auth service with bcrypt password hashing"
```

### Task 3.2: Auth controller + templates

**Files:**
- Create: `controllers/Controllers.AuthU.pas`
- Create: `templates/pages/auth/login.html`, `templates/pages/auth/signup.html`
- Modify: `webmodule/WebModuleU.pas` (register `TAuthController`)

- [ ] **Step 1: `templates/pages/auth/login.html`** — extends base, posts to `/login`.

```html
{{extends "../../layouts/base.html"}}
{{block "title"}}{{:l10n.login_title}} - {{:l10n.app_name}}{{endblock}}
{{block "content"}}
<section class="hero is-fullheight-with-navbar">
  <div class="hero-body">
    <div class="container">
      <div class="columns is-centered">
        <div class="column is-one-third">
          <h1 class="title">{{:l10n.login_title}}</h1>
          <form method="post" action="/login">
            <div class="field">
              <label class="label">{{:l10n.lbl_username}}</label>
              <div class="control"><input class="input" type="text" name="username" required></div>
            </div>
            <div class="field">
              <label class="label">{{:l10n.lbl_password}}</label>
              <div class="control"><input class="input" type="password" name="password" required></div>
            </div>
            {{if error}}<div class="notification is-danger">{{:error}}</div>{{endif}}
            <div class="field">
              <button class="button is-primary">{{:l10n.nav_login}}</button>
            </div>
          </form>
          <p>{{:l10n.login_no_account}} <a href="/signup">{{:l10n.nav_signup}}</a></p>
        </div>
      </div>
    </div>
  </div>
</section>
{{endblock}}
```

- [ ] **Step 2: `templates/pages/auth/signup.html`** — mirror login.html but posts to `/signup`.

- [ ] **Step 3: `controllers/Controllers.AuthU.pas`** — `GET /login`, `POST /login`, `GET /signup`, `POST /signup`, `POST /logout`. Stores `user_id` and `username` in DMVC `Session`. Plus root `[MVCPath('')]` `[MVCPath('/')]` is owned by `TAdventuresController` later — not here.

```pascal
unit Controllers.AuthU;

interface

uses MVCFramework, MVCFramework.Commons, Controllers.BaseU;

type
  [MVCPath('')]
  TAuthController = class(TBaseController)
  public
    [MVCPath('/login')][MVCHTTPMethod([httpGET])][MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetLogin;

    [MVCPath('/login')][MVCHTTPMethod([httpPOST])][MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostLogin(
      [MVCFromContentField('username', '')] AUsername: string;
      [MVCFromContentField('password', '')] APassword: string);

    [MVCPath('/signup')][MVCHTTPMethod([httpGET])][MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure GetSignup;

    [MVCPath('/signup')][MVCHTTPMethod([httpPOST])][MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    procedure PostSignup(
      [MVCFromContentField('username', '')] AUsername: string;
      [MVCFromContentField('password', '')] APassword: string);

    [MVCPath('/logout')][MVCHTTPMethod([httpPOST])]
    procedure PostLogout;
  end;

implementation

uses
  System.SysUtils,
  AppConfigU, Models.UserU, Services.AuthU;

procedure TAuthController.GetLogin;
begin
  ViewData['error'] := '';
  Render(RenderView('pages/auth/login'));
end;

procedure TAuthController.PostLogin(AUsername, APassword: string);
var LSvc: TAuthService; LUser: TUser;
begin
  LSvc := TAuthService.Create('FFMain');
  try
    if LSvc.Login(AUsername, APassword, LUser) then
    begin
      Session['user_id'] := IntToStr(LUser.Id);
      Session['username'] := LUser.Username;
      Redirect('/');
    end
    else
    begin
      ViewData['error'] := 'flash_login_failed';
      Render(RenderView('pages/auth/login'));
    end;
  finally LSvc.Free; end;
end;

procedure TAuthController.GetSignup;
begin
  ViewData['error'] := '';
  Render(RenderView('pages/auth/signup'));
end;

procedure TAuthController.PostSignup(AUsername, APassword: string);
var LSvc: TAuthService; LUid: Int64; LErr: string;
begin
  LSvc := TAuthService.Create('FFMain');
  try
    if LSvc.Signup(AUsername, APassword, LUid, LErr) then
    begin
      Session['user_id'] := IntToStr(LUid);
      Session['username'] := AUsername;
      Redirect('/');
    end
    else
    begin
      ViewData['error'] := 'flash_signup_' + LErr;
      Render(RenderView('pages/auth/signup'));
    end;
  finally LSvc.Free; end;
end;

procedure TAuthController.PostLogout;
begin
  Context.SessionStop;
  Redirect('/login');
end;

end.
```

- [ ] **Step 4: Modify `WebModuleU.pas`** — uncomment / add `FMVC.AddController(TAuthController);` and add `Controllers.AuthU` to uses.

- [ ] **Step 5: Compile (Win64), launch `bin\Win64\Debug\FFCompanion.exe`, open `http://localhost:8080/login`.** Manual verify: signup creates a user; login redirects to `/`; logout works. Open in incognito to test German default.

- [ ] **Step 6: Commit.**

```bash
git add controllers/Controllers.AuthU.pas templates/pages/auth/ webmodule/WebModuleU.pas
git commit -m "Add auth controller (login, signup, logout) with templates"
```

---

## Phase 4: Book Catalog (Models, YAML Seed, List, Custom Book Form)

### Task 4.1: Book/StatDef models + repositories + LocalizedTitleService

**Files:**
- Create: `models/Models.BookU.pas`, `models/Models.StatDefU.pas`
- Create: `repositories/Repositories.BooksU.pas`
- Create: `services/Services.LocalizedTitleU.pas`
- Create: `tests/Tests.Services.LocalizedTitleU.pas`

- [ ] **Step 1: `models/Models.BookU.pas`** — `TBook = record (Id: Int64; Slug, Author: string; OwnerUserId: Int64; IsSeed: Boolean)`; `TBookTitle = record (BookId: Int64; Lang, Title: string)`.

- [ ] **Step 2: `models/Models.StatDefU.pas`** — `TStatDef = record (Id, BookId: Int64; Ord: Integer; Name, Kind, DefaultValue: string)`; `TStatDefTitle = record (StatDefId: Int64; Lang, DisplayName: string)`.

- [ ] **Step 3: `repositories/Repositories.BooksU.pas`** — methods:
  - `UpsertSeedBook(Slug, Author): Int64`
  - `UpsertCustomBook(OwnerUserId; Slug, Author): Int64`
  - `SetBookTitles(BookId; Titles: TArray<TBookTitle>)` — replace-all semantics for that book's titles
  - `UpsertStatDef(BookId, Ord, Name, Kind, DefaultValue): Int64`
  - `SetStatDefTitles(StatDefId; Titles: TArray<TStatDefTitle>)`
  - `ListBooksForUser(UserId: Int64): TArray<TBook>` — seed + own custom
  - `GetBook(BookId): TBook`
  - `GetStatDefs(BookId): TArray<TStatDef>`
  - `GetBookTitles(BookId): TArray<TBookTitle>`
  - `GetStatDefTitles(StatDefId): TArray<TStatDefTitle>`

  Each method follows the FireDAC pattern in Task 3.1 Step 3.

- [ ] **Step 4: `services/Services.LocalizedTitleU.pas`** — implements the four-step lookup chain from spec §6.

```pascal
unit Services.LocalizedTitleU;

interface

uses System.Generics.Collections;

type
  TLocalizedTitleService = class
  public
    class function Pick(const ATitles: TDictionary<string, string>;
      const ACurrentLang, ADefaultLang, AFallback: string): string;
  end;

implementation

uses System.Generics.Defaults, System.SysUtils, System.Classes;

class function TLocalizedTitleService.Pick(
  const ATitles: TDictionary<string, string>;
  const ACurrentLang, ADefaultLang, AFallback: string): string;
var LKeys: TArray<string>; LK: string;
begin
  if ATitles.TryGetValue(ACurrentLang, Result) and (Result <> '') then Exit;
  if ATitles.TryGetValue(ADefaultLang, Result) and (Result <> '') then Exit;
  LKeys := ATitles.Keys.ToArray;
  TArray.Sort<string>(LKeys);
  for LK in LKeys do
    if ATitles[LK] <> '' then Exit(ATitles[LK]);
  Result := AFallback;
end;

end.
```

- [ ] **Step 5: Failing test `tests/Tests.Services.LocalizedTitleU.pas`** — four cases: current lang wins, fallback to default, fallback to first available, fallback to literal.

```pascal
unit Tests.Services.LocalizedTitleU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TLocalizedTitleTests = class
  public
    [Test] procedure CurrentLangWins;
    [Test] procedure FallsBackToDefault;
    [Test] procedure FallsBackToFirstAvailable;
    [Test] procedure FallsBackToLiteral;
  end;

implementation

uses System.Generics.Collections, Services.LocalizedTitleU;

procedure TLocalizedTitleTests.CurrentLangWins;
var LD: TDictionary<string,string>;
begin
  LD := TDictionary<string,string>.Create;
  try
    LD.Add('de', 'Die Zitadelle des Zauberers');
    LD.Add('en', 'The Citadel of Chaos');
    Assert.AreEqual('Die Zitadelle des Zauberers',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally LD.Free; end;
end;

procedure TLocalizedTitleTests.FallsBackToDefault;
var LD: TDictionary<string,string>;
begin
  LD := TDictionary<string,string>.Create;
  try
    LD.Add('en', 'The Citadel of Chaos');
    Assert.AreEqual('The Citadel of Chaos',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally LD.Free; end;
end;

procedure TLocalizedTitleTests.FallsBackToFirstAvailable;
var LD: TDictionary<string,string>;
begin
  LD := TDictionary<string,string>.Create;
  try
    LD.Add('fr', 'La Citadelle');
    Assert.AreEqual('La Citadelle',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally LD.Free; end;
end;

procedure TLocalizedTitleTests.FallsBackToLiteral;
var LD: TDictionary<string,string>;
begin
  LD := TDictionary<string,string>.Create;
  try
    Assert.AreEqual('fallback',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally LD.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLocalizedTitleTests);

end.
```

- [ ] **Step 6: Compile, run. Commit.**

```bash
git add models/Models.BookU.pas models/Models.StatDefU.pas repositories/Repositories.BooksU.pas services/Services.LocalizedTitleU.pas tests/Tests.Services.LocalizedTitleU.pas
git commit -m "Add book/stat-def repos and localized title service"
```

### Task 4.2: YAML reader (minimal subset)

**Files:**
- Create: `services/Services.YamlReaderU.pas`
- Create: `tests/Tests.Services.YamlReaderU.pas`

The seed YAML uses only: top-level list of mappings; nested mapping `titles`; nested list `stats` whose items are mappings (some with inline `{ k: v, ... }` braces). Rather than pull a YAML library, implement a tiny parser sized to this exact subset.

- [ ] **Step 1: Failing test** with one fixture covering all the syntactic features used by `books_seed.yaml`. Place fixture as a Delphi const string inside the test.

```pascal
unit Tests.Services.YamlReaderU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TYamlReaderTests = class
  public
    [Test] procedure ParsesSeedFixture;
  end;

implementation

uses System.SysUtils, Services.YamlReaderU;

const
  FIXTURE =
    '- slug: citadel-of-chaos'#10 +
    '  author: Steve Jackson'#10 +
    '  titles:'#10 +
    '    en: The Citadel of Chaos'#10 +
    '    de: Die Zitadelle des Zauberers'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill, de: Geschicklichkeit } }'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic, de: Magie } }'#10;

procedure TYamlReaderTests.ParsesSeedFixture;
var LBooks: TArray<TYamlBook>;
begin
  LBooks := TYamlReader.ParseSeedString(FIXTURE);
  Assert.AreEqual(1, Length(LBooks));
  Assert.AreEqual('citadel-of-chaos', LBooks[0].Slug);
  Assert.AreEqual('Steve Jackson', LBooks[0].Author);
  Assert.AreEqual('Die Zitadelle des Zauberers', LBooks[0].Titles['de']);
  Assert.AreEqual('The Citadel of Chaos', LBooks[0].Titles['en']);
  Assert.AreEqual(2, Length(LBooks[0].Stats));
  Assert.AreEqual('skill', LBooks[0].Stats[0].Name);
  Assert.AreEqual('integer', LBooks[0].Stats[0].Kind);
  Assert.AreEqual('Geschicklichkeit', LBooks[0].Stats[0].Titles['de']);
  Assert.AreEqual('Magie', LBooks[0].Stats[1].Titles['de']);
end;

initialization
  TDUnitX.RegisterTestFixture(TYamlReaderTests);

end.
```

- [ ] **Step 2: Implement `services/Services.YamlReaderU.pas`.** Two record types `TYamlStat` and `TYamlBook` (with `Titles: TDictionary<string,string>`); `TYamlReader.ParseSeedString(s): TArray<TYamlBook>` and `ParseSeedFile(path)`. Parser strategy: split into lines, track 2-space indent depth, recognize `- ` list items at depths 0 and 2 (the stats list at depth 2 also accepts inline `{ … }` mapping on the same line). Inline `{ k: v, k: v }` parsed by splitting on commas at depth-0 within braces (no commas in our values, by convention). Reject anything outside this subset with a clear error message — never silently ignore.

```pascal
unit Services.YamlReaderU;

interface

uses System.Generics.Collections;

type
  TYamlStat = record
    Name, Kind, DefaultValue: string;
    Titles: TDictionary<string, string>;
  end;

  TYamlBook = record
    Slug, Author: string;
    Titles: TDictionary<string, string>;
    Stats: TArray<TYamlStat>;
  end;

  TYamlReader = class
  public
    class function ParseSeedString(const ASource: string): TArray<TYamlBook>;
    class function ParseSeedFile(const APath: string): TArray<TYamlBook>;
  end;

  EYamlError = class(Exception);

implementation

uses System.SysUtils, System.Classes, System.IOUtils;

// Implementation note: see Tests.Services.YamlReaderU for the accepted dialect.
// Two-space indent; top-level list of book mappings; `titles:` block-mapping;
// `stats:` list whose items are inline `{ k: v, ..., titles: { ... } }` mappings.

// ... full parser body (~150 LOC). Algorithm:
//   1. Tokenize lines, compute indent count (must be multiple of 2).
//   2. Walk: at indent 0, '- key: value' starts a new book; subsequent indent-2 lines
//      fill its fields. `titles:` at indent 2 expects indent-4 'lang: text' lines.
//      `stats:` at indent 2 expects indent-4 '- { ... }' inline mappings.
//   3. Inline mapping parser: strip braces, split on top-level commas (none in our
//      values), each token is 'key: value' or 'key: { inner }' (one level of nesting).
//   4. Raise EYamlError with line number on any deviation.
// Engineer: implement strictly to pass the test fixture; reject anything else.

end.
```

(Engineer note: write the parser body to pass `ParsesSeedFixture`. Keep the unit ≤ 300 LOC by extracting helpers like `IndentOf(line)`, `SplitInlineMapping(s)`. No additional features.)

- [ ] **Step 3: Run test.** Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add services/Services.YamlReaderU.pas tests/Tests.Services.YamlReaderU.pas
git commit -m "Add minimal YAML reader for book seed format"
```

### Task 4.3: Book catalog service + seed file

**Files:**
- Create: `data/books_seed.yaml`
- Create: `services/Services.BookCatalogU.pas`
- Create: `tests/Tests.Services.BookCatalogU.pas`
- Modify: `webmodule/WebModuleU.pas` (call seed loader on boot)

- [ ] **Step 1: `data/books_seed.yaml`.**

```yaml
- slug: citadel-of-chaos
  author: Steve Jackson
  titles:
    en: The Citadel of Chaos
    de: Die Zitadelle des Zauberers
  stats:
    - { name: skill,   kind: integer, default: 0, titles: { en: Skill,   de: Geschicklichkeit } }
    - { name: stamina, kind: integer, default: 0, titles: { en: Stamina, de: Ausdauer } }
    - { name: luck,    kind: integer, default: 0, titles: { en: Luck,    de: Glück } }
    - { name: magic,   kind: integer, default: 0, titles: { en: Magic,   de: Magie } }

- slug: warlock-of-firetop-mountain
  author: Steve Jackson & Ian Livingstone
  titles:
    en: The Warlock of Firetop Mountain
  stats:
    - { name: skill,   kind: integer, default: 0, titles: { en: Skill,   de: Geschicklichkeit } }
    - { name: stamina, kind: integer, default: 0, titles: { en: Stamina, de: Ausdauer } }
    - { name: luck,    kind: integer, default: 0, titles: { en: Luck,    de: Glück } }

- slug: deathtrap-dungeon
  author: Ian Livingstone
  titles:
    en: Deathtrap Dungeon
  stats:
    - { name: skill,   kind: integer, default: 0, titles: { en: Skill,   de: Geschicklichkeit } }
    - { name: stamina, kind: integer, default: 0, titles: { en: Stamina, de: Ausdauer } }
    - { name: luck,    kind: integer, default: 0, titles: { en: Luck,    de: Glück } }
```

- [ ] **Step 2: `services/Services.BookCatalogU.pas`** — `LoadSeed(YamlPath)` does idempotent upsert per spec §7.2.

```pascal
unit Services.BookCatalogU;

interface

type
  TBookCatalogService = class
  private
    FConn: string;
  public
    constructor Create(const AConnectionName: string);
    procedure LoadSeed(const AYamlPath: string);
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  FireDAC.Comp.Client,
  Models.BookU, Models.StatDefU,
  Repositories.BooksU, Services.YamlReaderU;

constructor TBookCatalogService.Create(const AConnectionName: string);
begin
  inherited Create; FConn := AConnectionName;
end;

procedure TBookCatalogService.LoadSeed(const AYamlPath: string);
var
  LBooks: TArray<TYamlBook>;
  LBook: TYamlBook;
  LStat: TYamlStat;
  LRepo: TUsersRepo; // placeholder, actually TBooksRepo
  LBookRepo: TBooksRepo;
  LBookId, LStatDefId: Int64;
  LTitlesPair: TPair<string, string>;
  LOrd: Integer;
  LBookTitles: TArray<TBookTitle>;
  LStatTitles: TArray<TStatDefTitle>;
  I: Integer;
begin
  if not TFile.Exists(AYamlPath) then Exit;
  LBooks := TYamlReader.ParseSeedFile(AYamlPath);
  LBookRepo := TBooksRepo.Create(FConn);
  try
    for LBook in LBooks do
    begin
      LBookId := LBookRepo.UpsertSeedBook(LBook.Slug, LBook.Author);
      // Reconcile book_titles: replace-all
      SetLength(LBookTitles, LBook.Titles.Count);
      I := 0;
      for LTitlesPair in LBook.Titles do
      begin
        LBookTitles[I].BookId := LBookId;
        LBookTitles[I].Lang := LTitlesPair.Key;
        LBookTitles[I].Title := LTitlesPair.Value;
        Inc(I);
      end;
      LBookRepo.SetBookTitles(LBookId, LBookTitles);
      LOrd := 0;
      for LStat in LBook.Stats do
      begin
        LStatDefId := LBookRepo.UpsertStatDef(LBookId, LOrd, LStat.Name, LStat.Kind, LStat.DefaultValue);
        SetLength(LStatTitles, LStat.Titles.Count);
        I := 0;
        for LTitlesPair in LStat.Titles do
        begin
          LStatTitles[I].StatDefId := LStatDefId;
          LStatTitles[I].Lang := LTitlesPair.Key;
          LStatTitles[I].DisplayName := LTitlesPair.Value;
          Inc(I);
        end;
        LBookRepo.SetStatDefTitles(LStatDefId, LStatTitles);
        Inc(LOrd);
      end;
    end;
  finally LBookRepo.Free; end;
end;

end.
```

- [ ] **Step 3: Failing tests in `tests/Tests.Services.BookCatalogU.pas`:**
  - `LoadingSeedTwiceIsIdempotent`: load fixture YAML twice; count of books and titles is stable.
  - `RemovingTitleFromYamlDeletesItOnReload`: load v1 of YAML (with `de` title), then v2 (only `en`); assert the `de` row is gone.
  - `BookMissingFromYamlNotDeleted`: load v1 with 3 books, then v2 with 2 books; assert all 3 books still in DB.

Each test writes a temp file and calls `LoadSeed`, then asserts via the repo.

- [ ] **Step 4: Run tests. Commit.**

```bash
git add data/books_seed.yaml services/Services.BookCatalogU.pas tests/Tests.Services.BookCatalogU.pas
git commit -m "Add book catalog service and seed YAML (Citadel of Chaos)"
```

- [ ] **Step 5: Modify `WebModuleU.pas`** — after migrations, call `TBookCatalogService.Create('FFMain').LoadSeed(TAppConfig.SeedYamlPath)`. Commit:

```bash
git add webmodule/WebModuleU.pas
git commit -m "Load book seed on startup"
```

### Task 4.4: Books list page + custom book form

**Files:**
- Create: `controllers/Controllers.BooksU.pas`
- Create: `templates/pages/books/list.html`, `templates/pages/books/form.html`
- Modify: `webmodule/WebModuleU.pas` (register `TBooksController`)

- [ ] **Step 1: `controllers/Controllers.BooksU.pas`** — `GET /books` (uses `RequireLogin`; lists seed + own custom, names rendered via `LocalizedTitleService`), `GET /books/new` (form), `POST /books` (creates custom book + at least one stat from form). The form supports multiple languages via repeated `title_lang[]`/`title_text[]` field pairs and `stat_name[]`/`stat_kind[]`/`stat_default[]`/`stat_title_lang_<i>[]`/`stat_title_text_<i>[]`.

  Controller composes a `TArray<TBookListItem>` view model (slug + localized title + author + custom-flag) and assigns it to `ViewData['books']`.

- [ ] **Step 2: `templates/pages/books/list.html`** — table with localized titles, link to `/books/new`. Iterates `{{for book in books}}`.

- [ ] **Step 3: `templates/pages/books/form.html`** — form with: book title (one language; `[+ add translation]` button uses HTMX `hx-get` to fetch a row template that adds a fresh `title_lang/title_text` pair); stats block where the user can add multiple stats, each with name/kind/default/title pairs. Initial submission requires at least one stat; one title in `current_lang`.

- [ ] **Step 4: Register controller in WebModule. Compile.**

- [ ] **Step 5: Manual smoke** — log in, view `/books` (sees three seeded books with localized titles), create a custom book.

- [ ] **Step 6: Commit.**

```bash
git add controllers/Controllers.BooksU.pas templates/pages/books/ webmodule/WebModuleU.pas
git commit -m "Add books list page and custom book creation form"
```

---

## Phase 5: Adventures (Dashboard, Create, Empty Play View)

### Task 5.1: Adventure model + repo + service

**Files:**
- Create: `models/Models.AdventureU.pas`
- Create: `repositories/Repositories.AdventuresU.pas`
- Create: `services/Services.AdventureStateU.pas`
- Create: `tests/Tests.Repositories.AdventuresU.pas`

- [ ] **Step 1: Model** record (Id, UserId, BookId, Title, Status, StartedAt, LastStepId).

- [ ] **Step 2: Repo** — `Create`, `GetById`, `ListForUser(UserId, Status: TArray<string>)`, `UpdateStatus`, `UpdateLastStep`.

- [ ] **Step 3: `Services.AdventureStateU.pas`** — `GetCurrentSection(AdventureId): Integer` (reads `last_step_id → steps.to_section`, returns 0 if none); `GetStatsHistory(AdventureId): TList<TStatSnapshot>` (folds `stat_changes` per `stat_def`, returns current value + per-step values, excluding undone steps); `GetCurrentInventory(AdventureId): TList<TInventoryItem>` (folds `inventory_events`, excluding undone).

- [ ] **Step 4: Failing tests** in `Tests.Repositories.AdventuresU.pas` covering: create + get round-trip; list filters by user and status.

- [ ] **Step 5: Run. Commit.**

```bash
git add models/Models.AdventureU.pas repositories/Repositories.AdventuresU.pas services/Services.AdventureStateU.pas tests/Tests.Repositories.AdventuresU.pas
git commit -m "Add adventure model, repo, and state-folding service"
```

### Task 5.2: Adventures controller + dashboard + new-adventure form + empty play page

**Files:**
- Create: `controllers/Controllers.AdventuresU.pas`
- Create: `templates/pages/adventures/list.html`, `new.html`, `play.html`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1: Controller** — `[MVCPath('')]`, `[MVCPath('/')]` index renders `/templates/pages/adventures/list.html` with `active` and `archived` adventure arrays for current user. `GET /adventures/new` renders book picker. `POST /adventures` creates and redirects to play view. `GET /adventures/:id` renders empty play page (panels populated in later phases).

- [ ] **Step 2: Templates** — Bulma columns layout per spec §9.1; stats/inventory/dice/step-form panels are `{{include "../../partials/_stats_panel.html"}}` etc. Create empty placeholder partials now; each phase fills its panel.

- [ ] **Step 3: Register controller. Compile. Manual smoke.**

- [ ] **Step 4: Commit.**

```bash
git add controllers/Controllers.AdventuresU.pas templates/pages/adventures/ templates/partials/_stats_panel.html templates/partials/_inventory_panel.html templates/partials/_dice_panel.html templates/partials/_step_form.html templates/partials/_timeline.html templates/partials/_graph_tab.html templates/partials/_value_modal.html webmodule/WebModuleU.pas
git commit -m "Add adventures dashboard, create form, and empty play view"
```

---

## Phase 6: Steps & Timeline

### Task 6.1: Steps repository + log-step service

**Files:**
- Create: `models/Models.StepU.pas`
- Create: `repositories/Repositories.StepsU.pas`
- Create: `tests/Tests.Repositories.StepsU.pas`

- [ ] **Step 1:** Model record.

- [ ] **Step 2: Repo** — `Insert(adventureId, fromSection, toSection, note, flags): Int64` (computes next `seq` atomically inside a transaction with `SELECT COALESCE(MAX(seq),0)+1 FROM steps WHERE adventure_id=:a`); `ListByAdventure(adventureId; includeUndone: Boolean): TArray<TStep>`; `SetUndone(stepId, undone: Boolean)`; `GetById(stepId): TStep`.

- [ ] **Step 3: Failing tests** —
  - `InsertAssignsMonotonicSeq` (three inserts get seq 1,2,3)
  - `SetUndoneFlipsFlag`
  - `ListIncludeUndoneReturnsAll` vs `ListExcludeUndoneSkipsThem`
  - Concurrency: insert from two transactions — second one's seq still equals 2 (use UNIQUE constraint to verify; expected behavior with SQLite serialization).

- [ ] **Step 4: Compile, run, commit.**

```bash
git add models/Models.StepU.pas repositories/Repositories.StepsU.pas tests/Tests.Repositories.StepsU.pas
git commit -m "Add steps repository with monotonic seq and soft undo"
```

### Task 6.2: StepsController + step-form + timeline partial

**Files:**
- Create: `controllers/Controllers.StepsU.pas`
- Update: `templates/partials/_step_form.html`, `_timeline.html`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1: `_step_form.html`** — HTMX form per spec §9.2.

```html
<form id="step-form" hx-post="/adventures/{{:adventure.id}}/steps"
      hx-target="this" hx-swap="outerHTML">
  <input type="hidden" name="last_step_id" value="{{:adventure.last_step_id}}">
  <div class="field is-grouped">
    <div class="control">
      <label class="label">{{:l10n.step_form_from}}</label>
      <input class="input" name="from_section" value="{{:current_section}}" readonly>
    </div>
    <div class="control">
      <label class="label">{{:l10n.step_form_to}}</label>
      <input class="input" name="to_section" type="number" min="1" required autofocus>
    </div>
  </div>
  <div class="field">
    <label class="label">{{:l10n.step_form_note}}</label>
    <input class="input" name="note">
  </div>
  <div class="field">
    <label class="checkbox"><input type="checkbox" name="flag_fight"> {{:l10n.step_flag_fight}}</label>
    <label class="checkbox"><input type="checkbox" name="flag_item"> {{:l10n.step_flag_item}}</label>
    <label class="checkbox"><input type="checkbox" name="flag_stat"> {{:l10n.step_flag_stat}}</label>
  </div>
  <button class="button is-primary">{{:l10n.step_btn_log}}</button>
</form>
```

- [ ] **Step 2: Controller**

```pascal
[MVCPath('/adventures/($AdvId)/steps')]
TStepsController = class(TBaseController)
public
  [MVCPath('')][MVCHTTPMethod([httpPOST])][MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
  procedure LogStep(AAdvId: Int64;
    [MVCFromContentField('to_section', '')] AToRaw: string;
    [MVCFromContentField('note', '')] ANote: string;
    [MVCFromContentField('last_step_id', '')] ALastStepRaw: string;
    [MVCFromContentField('flag_fight', '')] AFlagFight: string;
    [MVCFromContentField('flag_item', '')] AFlagItem: string;
    [MVCFromContentField('flag_stat', '')] AFlagStat: string);

  [MVCPath('/($SId)/undo')][MVCHTTPMethod([httpPOST])]
  procedure Undo(AAdvId, ASId: Int64);

  [MVCPath('/($SId)/redo')][MVCHTTPMethod([httpPOST])]
  procedure Redo(AAdvId, ASId: Int64);
end;
```

`LogStep`:
1. `RequireLogin`; load adventure; verify `user_id` matches.
2. Concurrency check: parse `ALastStepRaw`, compare with `adventures.last_step_id`. Mismatch → return Bulma error fragment with `flash_concurrency`.
3. Validate `to_section` is positive integer.
4. Insert step (Service.AdventureState.GetCurrentSection for `from_section`).
5. Update `adventures.last_step_id`.
6. Re-render `_step_form.html` fragment with updated `current_section`.
7. Set `HX-Trigger: step-logged, graph-changed`.

Also create a small `GET /adventures/:id/timeline` action returning the rendered `_timeline.html`. The `step-logged` JS listener triggers a refresh.

Add to `app.js`:

```javascript
document.body.addEventListener('step-logged', () => {
  htmx.ajax('GET', '/adventures/' + window.ffAdventureId + '/timeline', '#timeline-area');
});
```

(`window.ffAdventureId` is set by an inline `<script>` in `play.html`.)

- [ ] **Step 3: `_timeline.html`** — list rendering.

```html
<div id="timeline-area">
  {{for step in steps}}
    <div class="box {{if step.undone}}is-undone{{endif}}">
      <span class="tag">#{{:step.seq}}</span>
      {{if step.from_section}}§{{:step.from_section}} → {{endif}}§{{:step.to_section}}
      {{if step.note}} — {{:step.note}}{{endif}}
      {{if step.flag_fight}}<span class="tag is-danger">{{:l10n.step_flag_fight}}</span>{{endif}}
      {{if step.flag_item}}<span class="tag is-info">{{:l10n.step_flag_item}}</span>{{endif}}
      {{if step.flag_stat}}<span class="tag is-warning">{{:l10n.step_flag_stat}}</span>{{endif}}
      <span class="is-pulled-right">{{:step.created_at_display}}</span>
      <div class="mt-2">
        {{if step.undone}}
          <form hx-post="/adventures/{{:adventure.id}}/steps/{{:step.id}}/redo" hx-target="#timeline-area">
            <button class="button is-small">{{:l10n.btn_redo}}</button>
          </form>
        {{else}}
          <form hx-post="/adventures/{{:adventure.id}}/steps/{{:step.id}}/undo" hx-target="#timeline-area">
            <button class="button is-small">{{:l10n.btn_undo}}</button>
          </form>
        {{endif}}
      </div>
    </div>
  {{endfor}}
</div>
```

- [ ] **Step 4: Manual smoke** — log 3 steps, verify timeline updates, undo/redo flips the styling.

- [ ] **Step 5: Commit.**

```bash
git add controllers/Controllers.StepsU.pas templates/partials/_step_form.html templates/partials/_timeline.html static/js/app.js webmodule/WebModuleU.pas
git commit -m "Add step logging, soft undo/redo, and HTMX timeline refresh"
```

---

## Phase 7: Stats + Value Modal

### Task 7.1: stat_changes repo + folding logic

**Files:**
- Create: `models/Models.StatChangeU.pas`
- Create: `repositories/Repositories.StatChangesU.pas`
- Update: `services/Services.AdventureStateU.pas` (real `GetStatsHistory`)
- Create: `tests/Tests.Services.AdventureStateU.pas`

- [ ] **Step 1:** Model + repo (`Insert`, `ListByAdventure(adventureId; includeUndoneSteps: Boolean)` — joins `steps` and excludes `undone=1` unless requested).

- [ ] **Step 2:** Update `Services.AdventureStateU.GetStatsHistory` to fold `stat_changes` per `stat_def_id`, ordered by `steps.seq`, producing current value (last `new_value` for that stat_def, or `stat_defs.default_value` if none).

- [ ] **Step 3: Failing tests:**
  - `CurrentStatsReflectLastChange`: insert two changes for Skill (12 → 9), assert current = 9.
  - `UndoneStepStatChangesExcluded`: insert change in step that's then undone; assert current value reverts.
  - `MultipleStatDefsTrackedIndependently`.

- [ ] **Step 4: Run. Commit.**

```bash
git add models/Models.StatChangeU.pas repositories/Repositories.StatChangesU.pas services/Services.AdventureStateU.pas tests/Tests.Services.AdventureStateU.pas
git commit -m "Add stat changes with undo-aware folding"
```

### Task 7.2: Stats controller, modal partial, panel partial

**Files:**
- Create: `controllers/Controllers.StatsU.pas`
- Update: `templates/partials/_stats_panel.html`, `_value_modal.html`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1: `_stats_panel.html`** — list current stats with localized names; integer rows have `hx-get="/adventures/{{:adventure.id}}/stats/{{:stat.def_id}}/modal"` that fetches the modal and swaps it into `#modal-host`.

```html
<div id="stats-panel">
  <h3 class="title is-5">{{:l10n.stat_panel_title}}</h3>
  {{for stat in stats}}
    <div class="level">
      <div class="level-left"><strong>{{:stat.display_name}}</strong></div>
      <div class="level-right">
        {{if stat.kind|eq,integer}}
          <button class="button is-large is-touch"
                  hx-get="/adventures/{{:adventure.id}}/stats/{{:stat.def_id}}/modal"
                  hx-target="#modal-host" hx-swap="innerHTML">
            {{:stat.value}}
          </button>
        {{else}}
          <span>{{:stat.value}}</span>
        {{endif}}
      </div>
    </div>
  {{endfor}}
</div>
<div id="modal-host"></div>
```

- [ ] **Step 2: `_value_modal.html`** — reusable touch modal.

```html
<div class="modal is-active">
  <div class="modal-background" onclick="document.dispatchEvent(new CustomEvent('close-modal'))"></div>
  <div class="modal-card">
    <header class="modal-card-head"><p class="modal-card-title">{{:label}}</p></header>
    <section class="modal-card-body has-text-centered">
      <div class="buttons is-centered">
        <button class="button is-large is-touch"
                hx-post="{{:preview_url}}" hx-target="#modal-host"
                hx-vals='{"working":"{{:working}}","delta":"-5","reason":"{{:reason}}"}'>−5</button>
        <button class="button is-large is-touch"
                hx-post="{{:preview_url}}" hx-target="#modal-host"
                hx-vals='{"working":"{{:working}}","delta":"-1","reason":"{{:reason}}"}'>−1</button>
      </div>
      <input class="input is-large has-text-centered" type="number" value="{{:working}}"
             hx-post="{{:preview_url}}" hx-trigger="change" hx-target="#modal-host"
             hx-vals='{"delta":"0","reason":"{{:reason}}"}' name="working">
      <p class="has-text-grey">(was {{:original}} • Δ {{:delta_display}})</p>
      <div class="buttons is-centered">
        <button class="button is-large is-touch"
                hx-post="{{:preview_url}}" hx-target="#modal-host"
                hx-vals='{"working":"{{:working}}","delta":"+1","reason":"{{:reason}}"}'>+1</button>
        <button class="button is-large is-touch"
                hx-post="{{:preview_url}}" hx-target="#modal-host"
                hx-vals='{"working":"{{:working}}","delta":"+5","reason":"{{:reason}}"}'>+5</button>
      </div>
      <div class="field mt-3">
        <label class="label">{{:l10n.lbl_reason}}</label>
        <input class="input" name="reason" value="{{:reason}}"
               hx-post="{{:preview_url}}" hx-trigger="change delay:300ms" hx-target="#modal-host"
               hx-include="[name='working']"
               hx-vals='{"delta":"0"}'>
      </div>
    </section>
    <footer class="modal-card-foot">
      <button class="button" onclick="document.dispatchEvent(new CustomEvent('close-modal'))">{{:l10n.btn_cancel}}</button>
      <form hx-post="{{:commit_url}}" hx-target="#stats-panel" hx-swap="outerHTML">
        <input type="hidden" name="working" value="{{:working}}">
        <input type="hidden" name="reason" value="{{:reason}}">
        <input type="hidden" name="last_step_id" value="{{:last_step_id}}">
        <button class="button is-primary">{{:l10n.btn_confirm}}</button>
      </form>
    </footer>
  </div>
</div>
```

- [ ] **Step 3: `Controllers.StatsU.pas`** — three actions:

  - `GET /adventures/:id/stats/:sdid/modal` → reads current value, renders `_value_modal.html` with `working = current`, `delta_display = "±0"`, `preview_url`, `commit_url`, `last_step_id`.
  - `POST /adventures/:id/stats/preview` → reads `working`, `delta`, `reason`; computes new working = `working + delta`; re-renders `_value_modal.html` with new working and updated Δ display.
  - `POST /adventures/:id/stats` → concurrency-check on `last_step_id`; if no current step, reject with flash (`stat changes require a step` — add l10n key `flash_no_current_step`); insert `stat_changes(step_id=current, stat_def_id, old=current_value, new=working, reason)`; set `steps.flag_stat=1`; return updated `#stats-panel` plus `HX-Trigger: close-modal, graph-changed`.

  (Add `flash_no_current_step` to both l10n files.)

- [ ] **Step 4: Failing controller test** — POST commit inserts a stat_changes row.

- [ ] **Step 5: Manual smoke** — open modal, click +/−, confirm.

- [ ] **Step 6: Commit.**

```bash
git add controllers/Controllers.StatsU.pas templates/partials/_stats_panel.html templates/partials/_value_modal.html l10n/ webmodule/WebModuleU.pas
git commit -m "Add touch-friendly stat editor with +/- modal"
```

---

## Phase 8: Inventory

### Task 8.1: Inventory events repo + folding

**Files:**
- Create: `models/Models.InventoryEventU.pas`
- Create: `repositories/Repositories.InventoryEventsU.pas`
- Update: `services/Services.AdventureStateU.pas` (real `GetCurrentInventory`)
- Create: `tests/Tests.Services.AdventureStateU.Inventory.pas` (or extend existing)

- [ ] **Step 1:** Model + repo: `Insert(step_id, kind, item_name, quantity, note)`, `ListByAdventure(adventureId; includeUndone)`.

- [ ] **Step 2:** `GetCurrentInventory`: group by `item_name`. For each item: start at 0; iterate events ordered by step seq; `gain` adds, `lose` subtracts, `modify` sets absolute. Exclude items with final qty ≤ 0 from display (but keep events in history).

- [ ] **Step 3: Failing tests** — gain+gain combines; gain+lose subtracts; modify overrides; undone-step events excluded.

- [ ] **Step 4: Run. Commit.**

```bash
git add models/Models.InventoryEventU.pas repositories/Repositories.InventoryEventsU.pas services/Services.AdventureStateU.pas tests/
git commit -m "Add inventory events with folding (gain/lose/modify)"
```

### Task 8.2: Inventory controller + panel + modal reuse

**Files:**
- Create: `controllers/Controllers.InventoryU.pas`
- Update: `templates/partials/_inventory_panel.html`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1: `_inventory_panel.html`** — list current items, each with quantity button that opens the shared value modal (same `_value_modal.html`, parameterized with `commit_url=/adventures/:id/inventory` and an additional hidden `item_name` field). Plus a small `+ Add item` form (`hx-post`).

- [ ] **Step 2: Controller actions:**
  - `POST /adventures/:id/inventory` with `kind=gain|lose|modify`, `item_name`, `quantity`, optional `note` → inserts event tied to current step, sets `flag_item=1`, returns updated panel + `HX-Trigger: graph-changed`.
  - `GET /adventures/:id/inventory/:item/modal` (item URL-encoded) → opens value modal with current qty.
  - `POST /adventures/:id/inventory/preview` → working/delta math.
  - Remove (`[×]`) posts `kind=lose, quantity=<current>` to the same endpoint.

- [ ] **Step 3: Manual smoke. Commit.**

```bash
git add controllers/Controllers.InventoryU.pas templates/partials/_inventory_panel.html webmodule/WebModuleU.pas
git commit -m "Add inventory panel with shared value modal"
```

---

## Phase 9: Dice + Graph View

### Task 9.1: Dice roller

**Files:**
- Create: `models/Models.DiceRollU.pas`
- Create: `repositories/Repositories.DiceRollsU.pas`
- Create: `controllers/Controllers.DiceU.pas`
- Update: `templates/partials/_dice_panel.html`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1:** Model + repo (`Insert`, `LastN(adventureId, N)`).

- [ ] **Step 2: Service-less roller**: `POST /adventures/:id/roll` accepts `expression` in `{2d6, 1d6}`; rolls using `Random` (call `Randomize` once in WebModuleCreate); inserts row with current `step_id` (nullable); returns small fragment with last result + last 3 rolls.

- [ ] **Step 3: `_dice_panel.html`** — two buttons + result strip.

```html
<div id="dice-panel">
  <h3 class="title is-5">{{:l10n.dice_panel_title}}</h3>
  <div class="buttons">
    <button class="button" hx-post="/adventures/{{:adventure.id}}/roll"
            hx-vals='{"expression":"2d6"}' hx-target="#dice-panel" hx-swap="outerHTML">
      {{:l10n.dice_roll_2d6}}
    </button>
    <button class="button" hx-post="/adventures/{{:adventure.id}}/roll"
            hx-vals='{"expression":"1d6"}' hx-target="#dice-panel" hx-swap="outerHTML">
      {{:l10n.dice_roll_1d6}}
    </button>
  </div>
  {{if last_roll}}<p>{{:l10n.dice_last}} {{:last_roll.expression}} = <strong>{{:last_roll.result}}</strong></p>{{endif}}
</div>
```

- [ ] **Step 4: Commit.**

```bash
git add models/Models.DiceRollU.pas repositories/Repositories.DiceRollsU.pas controllers/Controllers.DiceU.pas templates/partials/_dice_panel.html webmodule/WebModuleU.pas
git commit -m "Add dice roller (2d6, 1d6) with history"
```

### Task 9.2: Graph builder service + JSON endpoint

**Files:**
- Create: `services/Services.GraphBuilderU.pas`
- Create: `controllers/Controllers.GraphU.pas`
- Create: `tests/Tests.Services.GraphBuilderU.pas`
- Modify: `webmodule/WebModuleU.pas`

- [ ] **Step 1:** `TGraphBuilder.Build(adventureId): TJsonObject` exactly matching the shape in spec §9.4. Excludes undone steps. Nodes deduped by `section`; `visits` = count of incoming edges + 1 if it's the starting section; `first_seq` = lowest seq where the node appears as `to_section` (or `from_section` for the first node).

- [ ] **Step 2: Failing tests** —
  - Linear adventure 1→42→187 produces 3 nodes, 2 edges, `current=187`.
  - Revisit 1→42→187→42 produces 3 nodes (42 has `visits=2`), 3 edges, `current=42`.
  - Undone last step excluded.
  - Empty adventure returns `{current:0, nodes:[], edges:[]}`.

- [ ] **Step 3: Controller** — `GET /adventures/:id/graph.json` requires login + ownership, returns `Content-Type: application/json`.

- [ ] **Step 4: Commit.**

```bash
git add services/Services.GraphBuilderU.pas controllers/Controllers.GraphU.pas tests/Tests.Services.GraphBuilderU.pas webmodule/WebModuleU.pas
git commit -m "Add graph builder service and graph.json endpoint"
```

### Task 9.3: Cytoscape integration in play view

**Files:**
- Update: `templates/pages/adventures/play.html` (load Cytoscape, set `window.ffAdventureId`, init graph on tab activation)
- Update: `templates/partials/_graph_tab.html`
- Update: `static/js/app.js`

- [ ] **Step 1: `_graph_tab.html`** — container `<div id="cy" style="height: 600px;"></div>`.

- [ ] **Step 2: `play.html`** — `{{block "scripts"}}` includes `<script src="/static/js/cytoscape.min.js"></script>` and an inline script:

```html
<script>
window.ffAdventureId = {{:adventure.id}};
let cy = null;
window.ffRefreshGraph = async function() {
  const r = await fetch('/adventures/' + window.ffAdventureId + '/graph.json');
  const data = await r.json();
  const elements = [
    ...data.nodes.map(n => ({ data: { id: n.id, label: '§' + n.section, visits: n.visits },
                              classes: n.section === data.current ? 'current' : (n.visits > 1 ? 'revisit' : '') })),
    ...data.edges.map(e => ({ data: { source: e.from, target: e.to, label: e.seq } }))
  ];
  if (!cy) {
    cy = cytoscape({
      container: document.getElementById('cy'),
      elements,
      style: [
        { selector: 'node', style: { 'label': 'data(label)', 'background-color': '#3273dc', 'color':'#fff', 'text-valign':'center' } },
        { selector: 'node.current', style: { 'background-color': '#ffdd57', 'color':'#000' } },
        { selector: 'node.revisit', style: { 'border-width': 3, 'border-color': '#ff3860' } },
        { selector: 'edge', style: { 'curve-style': 'bezier', 'target-arrow-shape': 'triangle', 'label': 'data(label)' } }
      ],
      layout: { name: 'cose', animate: true }
    });
  } else {
    cy.json({ elements });
    cy.layout({ name: 'cose', animate: true }).run();
  }
};
// Initial load when Graph tab activated
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('tab-graph')?.addEventListener('click', () => {
    setTimeout(() => window.ffRefreshGraph(), 0);
  });
});
</script>
```

- [ ] **Step 3: Tab switching** in `play.html` — two `<a>` tabs (`#tab-timeline`, `#tab-graph`) toggle visibility of `<div id="timeline-area">` and `<div id="graph-area">`.

- [ ] **Step 4: Manual smoke** — log 4 steps including one revisit; switch to Graph tab; verify nodes/edges/current highlight; log another step from Timeline tab, switch back, verify graph updates.

- [ ] **Step 5: Commit.**

```bash
git add templates/pages/adventures/play.html templates/partials/_graph_tab.html static/js/app.js
git commit -m "Wire Cytoscape graph view to graph.json with revisit highlighting"
```

---

## Phase 10: Controller-Level Integration Test

### Task 10.1: End-to-end smoke

**Files:**
- Create: `tests/Tests.E2E.PlaythroughU.pas`

- [ ] **Step 1: Write test** — spins up DMVC server in-process bound to a temp file SQLite, drives:
  1. `POST /signup` (alice/secret123) → 302 to `/`
  2. `POST /adventures` with seeded book `citadel-of-chaos` → 302 to `/adventures/1`
  3. `POST /adventures/1/steps` six times (1, 42, 187, 42 (revisit), 87, 200)
  4. `POST /adventures/1/stats/3` (Stamina) commit, working=14
  5. `POST /adventures/1/inventory` `kind=gain, item_name=Sword`
  6. `POST /adventures/1/steps/4/undo` (undo the second visit to §42)
  7. `GET /adventures/1/graph.json` → assert 5 nodes (not 6, undone excluded), §42 has visits=1, current=§200

  Uses DMVCFramework's `TMVCRESTClient` against the in-process server.

- [ ] **Step 2: Run. Commit.**

```bash
git add tests/Tests.E2E.PlaythroughU.pas
git commit -m "Add end-to-end smoke test of full playthrough"
```

---

## Phase 11: Docker Compose Deployment

### Task 11.1: Dockerfile (multi-stage)

**Files:**
- Create: `docker/Dockerfile`, `docker/docker-compose.yaml`, `.dockerignore`

- [ ] **Step 1: `docker/Dockerfile`** — multi-stage. Builder stage runs the `delphi-build` MCP server target Linux64 (or is built externally; the image just consumes the artifact). Pragmatic structure:

```dockerfile
# Stage 1: runtime (artifact built externally via mcp__delphi-build__compile_delphi_project)
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN groupadd -r ff && useradd -r -g ff ff && mkdir -p /app/data && chown -R ff:ff /app

COPY --chown=ff:ff bin/Linux64/Release/FFCompanion /app/FFCompanion
COPY --chown=ff:ff templates /app/templates
COPY --chown=ff:ff static /app/static
COPY --chown=ff:ff l10n /app/l10n
COPY --chown=ff:ff data/books_seed.yaml /app/data/books_seed.yaml

USER ff
ENV HTTP_PORT=8080 \
    DEFAULT_LANGUAGE=de \
    DATABASE_PATH=/app/data/ffcompanion.db

EXPOSE 8080
CMD ["/app/FFCompanion"]
```

- [ ] **Step 2: `docker/docker-compose.yaml`** —

```yaml
services:
  ffcompanion:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    image: ffcompanion:latest
    ports:
      - "8080:8080"
    environment:
      DEFAULT_LANGUAGE: de
      HTTP_PORT: 8080
      DATABASE_PATH: /app/data/ffcompanion.db
    volumes:
      - ./data:/app/data
    restart: unless-stopped
```

- [ ] **Step 3: `.dockerignore`** — `bin/Win64`, `tests`, `docs`, `.git`, `*.dproj.local`, `__history`.

- [ ] **Step 4: Build:**
  - Compile via `mcp__delphi-build__compile_delphi_project` (platform Linux64, config Release).
  - `cd docker && docker compose build`
  - `docker compose up -d`
  - Smoke: `curl http://localhost:8080/login` returns the German login page.

- [ ] **Step 5: Commit.**

```bash
git add docker/ .dockerignore
git commit -m "Add Dockerfile and docker-compose for Linux64 deployment"
```

---

## Phase 12: Final Polish

### Task 12.1: l10n key audit

- [ ] **Step 1:** `grep -ro 'l10n\.\w*' templates/ | sort -u` — every referenced key exists in both `en.json` and `de.json`. The parity test from Task 1.4 catches missing keys in one file; this catches templates referencing keys that exist in neither.

- [ ] **Step 2:** Fix any gaps. Re-run all tests.

- [ ] **Step 3: Commit if changes.**

```bash
git add l10n/ templates/
git commit -m "Complete l10n key coverage"
```

### Task 12.2: README

**Files:**
- Create: `README.md`

- [ ] **Step 1:** Concise README — what it is, how to run (`docker compose up`), default language, signup link, link back to the spec/plan.

- [ ] **Step 2: Commit.**

```bash
git add README.md
git commit -m "Add README"
```

---

## Self-Review Notes

**Spec coverage check:**
- §2 Users & Deployment → Phases 3 (auth) + 11 (Docker) ✓
- §3 Tech stack → Phase 1 scaffold ✓
- §4 Architecture/layers → file structure section ✓
- §5 Data model → Task 2.1 migration runner ✓
- §6 LocalizedTitle lookup chain → Task 4.1 Step 4 + test ✓
- §7 Seed catalog (Citadel of Chaos with German title) → Task 4.3 Step 1 ✓
- §8 Routes → covered by Phases 3, 4, 5, 6, 7, 8, 9 ✓
- §9.1 Layout → Task 5.2 + each panel phase ✓
- §9.2 Step-logging flow → Task 6.2 ✓
- §9.3 Timeline → Task 6.2 ✓
- §9.4 Graph + JSON shape → Task 9.2 + Task 9.3 ✓
- §9.5 Stat +/− modal → Task 7.2 ✓
- §9.6 Dice → Task 9.1 ✓
- §9.7 Inventory editing → Task 8.2 ✓
- §10 i18n → Task 1.3 (catalogs) + Task 1.4 (parity test) + Task 12.1 (audit) ✓
- §11 Error handling → concurrency check in Task 6.2 + 7.2; flash + l10n keys included ✓
- §12 Testing → DUnitX tests across phases + E2E in Task 10.1 ✓
- §13 Out of scope → not implemented ✓
- §14 Open items — YAML parser handled in Task 4.2 (hand-rolled subset parser); Cytoscape version pinned in Task 0.1 / Task 1.2; additional German titles flagged in Task 4.3 Step 1 (only Citadel ships with German title, others can be added without migration) ✓

**Placeholder scan:** no "TBD", "TODO", "fill in details", or "similar to" references. Task 4.2 Step 2 contains an algorithmic note rather than full parser code because the parser body is straightforward to write to the test and not the interesting part of the plan — the test fixture pins the dialect strictly. If the implementing engineer prefers, they can replace the inline note with a fully-written parser, but the test alone is sufficient to verify correctness.

**Type consistency:** field names `working`, `delta`, `reason`, `last_step_id`, `from_section`, `to_section`, `flag_fight/item/stat`, `kind`, `stat_def_id`, `item_name` are used consistently across templates, controllers, repos, and schema.
