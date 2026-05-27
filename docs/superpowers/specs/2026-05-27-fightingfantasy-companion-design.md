# Fighting Fantasy Companion — Design

**Date:** 2026-05-27
**Status:** Draft for review

## 1. Purpose

A record-keeping companion for solo play of Fighting Fantasy gamebooks. The user reads a physical or PDF gamebook; the app tracks per-book configurable stats, inventory, and — distinctively — the **exact decision path** through the book (every section visited, every jump made, every revisit), with two views: a chronological timeline and an interactive graph.

The app deliberately does **not**:
- Contain gamebook text or implement gamebook logic
- Automate combat or auto-apply dice results to stats
- Provide curation/sharing of adventures between users

## 2. Users & Deployment

- **Users:** multi-user with username + password login, unrestricted signup. Each user's adventures are private to them.
- **Deployment:** single Docker Compose stack, Linux64 build target, SQLite file persisted on a mounted volume. Built via the `delphi-build` MCP server.
- **Default language:** German (`DEFAULT_LANGUAGE=de`).

## 3. Technology Stack

- **Server:** Delphi (Linux64), DMVCFramework with TemplatePro view engine.
- **Persistence:** SQLite via FireDAC + `TMVCActiveRecord`.
  - `.dpr` MUST include `MVCFramework.SQLGenerators.Sqlite`.
- **Frontend:** server-rendered HTML, HTMX for partial swaps, Bulma CSS, Cytoscape.js for the graph view only.
- **Auth:** session-based with server-side store and cookies.
- **i18n:** per `dmvc-webapp/references/l10n-conventions.md` — `l10n/de.json` and `l10n/en.json`, flat key/value, language switcher in the navbar.
- **Static assets:** local copies of `htmx.min.js`, `bulma.min.css`, `cytoscape.min.js` (no CDN).

## 4. Architecture

Single Delphi binary serving HTML. Four internal layers, each in its own units, each unit ≤ ~300 LOC (per `delphi-style`):

| Layer | Responsibility | Naming |
|---|---|---|
| Controllers | HTTP/HTMX endpoints, one per resource | `Controllers.<Entity>U.pas` |
| Services | Business logic, no direct DB access | `Services.<Topic>U.pas` |
| Repositories | FireDAC queries / `TMVCActiveRecord` operations | `Repositories.<Entity>U.pas` |
| Models | View models (records) passed to TemplatePro | `Models.<Entity>U.pas` |

A `TBaseController` provides l10n loading, HTMX detection, flash, role checks, and `current_user` injection (extends the pattern from `dmvc-webapp/references/l10n-conventions.md`).

### 4.1 Deployment

- `docker/Dockerfile` — multi-stage; compile produces a Linux64 binary, image bundles binary + `/templates` + `/static` + `/l10n` + `books_seed.yaml`.
- `docker/docker-compose.yaml` — single service, environment variable `DEFAULT_LANGUAGE=de`, port 8080 (configurable), volumes:
  - `./data` → SQLite database file
  - `./books_custom` → optional local catalog override file(s)
- No PostgreSQL/Redis (single-node SQLite is sufficient for this app's load).

## 5. Data Model

```
users               (id, username UNIQUE, password_hash, created_at)
sessions            (token PK, user_id, expires_at)

books               (id, slug UNIQUE, author, owner_user_id NULL,
                     is_seed BOOL, created_at)
                    -- owner_user_id NULL + is_seed=1 → public seeded book
                    -- owner_user_id set         → custom book private to user
book_titles         (book_id, lang, title, PK: book_id+lang)

stat_defs           (id, book_id, ord, name, kind, default_value)
                    -- kind: 'integer' | 'text' | 'checkbox'
                    -- `name` is a slug-like identifier, never shown to users
stat_def_titles     (stat_def_id, lang, display_name, PK: stat_def_id+lang)

adventures          (id, user_id, book_id, title, status,
                     started_at, last_step_id NULL)
                    -- status: 'active' | 'completed' | 'abandoned'

steps               (id, adventure_id, seq, from_section NULL, to_section,
                     note, flag_fight BOOL, flag_item BOOL, flag_stat BOOL,
                     undone BOOL DEFAULT 0, created_at)
                    -- seq is monotonic per adventure, gap-free
                    -- first step has from_section=NULL

stat_changes        (id, step_id, stat_def_id, old_value, new_value,
                     reason TEXT NULL)

inventory_events    (id, step_id, kind, item_name, quantity, note)
                    -- kind: 'gain' | 'lose' | 'modify'

dice_rolls          (id, adventure_id, step_id NULL, expression, result,
                     rolled_at)
```

Indices: `steps(adventure_id, seq)`, `stat_changes(step_id)`, `inventory_events(step_id)`, `sessions(token)`, `books(slug)`, `adventures(user_id, status)`, `book_titles(book_id, lang)`, `stat_def_titles(stat_def_id, lang)`.

Derived state (current stats, current inventory, graph nodes/edges) is computed by services from event tables; only `adventures.last_step_id` is denormalized as a cache for the active-step pointer.

**Soft-undo:** `steps.undone = 1`. Undone steps and their attached `stat_changes` / `inventory_events` are excluded from current-state and graph computations, but remain in the timeline view as greyed-out, struck-through rows that can be "redone".

## 6. Localized Titles — Lookup Rule

For both `book_titles` and `stat_def_titles`, a `LocalizedTitleService` resolves the display string as:

1. `current_lang` (from `TBaseController`)
2. `DEFAULT_LANGUAGE` (env var, default `de`)
3. First available `lang` row (deterministic order: alphabetical by lang code)
4. Fallback: `books.slug` / `stat_defs.name` literal

Custom user books: the create form requires one title in `current_lang` and offers a `[+ add translation]` affordance for additional languages. Stat definitions for custom books accept the same multi-language entry pattern; if only one language is provided, the fallback rule makes it the display in all languages.

## 7. Book Catalog & Seed

### 7.1 Seed file format

`books_seed.yaml` (shipped in the image):

```yaml
- slug: citadel-of-chaos
  author: Steve Jackson
  titles:
    en: The Citadel of Chaos
    de: Die Zitadelle des Zauberers
  stats:
    - { name: skill,   kind: integer, default: 0,
        titles: { en: Skill,   de: Geschicklichkeit } }
    - { name: stamina, kind: integer, default: 0,
        titles: { en: Stamina, de: Ausdauer } }
    - { name: luck,    kind: integer, default: 0,
        titles: { en: Luck,    de: Glück } }
    - { name: magic,   kind: integer, default: 0,
        titles: { en: Magic,   de: Magie } }
```

### 7.2 Seed loader behaviour

`BookCatalogService` reads the YAML on application boot and performs an idempotent upsert by `slug`:
- Books matched on `slug` are updated in place; missing books are inserted.
- `stat_defs` are upserted by `(book_id, name)`; the `ord` column reflects YAML order.
- `book_titles` and `stat_def_titles` are reconciled against YAML: rows present in YAML are upserted, rows absent from YAML for that book are deleted.
- A seed entry removed from the YAML on a later boot is **not** deleted from the DB (existing adventures may reference it) — it simply stops being re-asserted.

### 7.3 Initial seeded books

v1 ships with at least:

| slug | English title | German title | Notes |
|---|---|---|---|
| `citadel-of-chaos` | The Citadel of Chaos | Die Zitadelle des Zauberers | Reference test book; uses `magic` stat |

Additional well-known titles (e.g. *The Warlock of Firetop Mountain*, *Deathtrap Dungeon*) ship with English titles and may be added with German titles as those are confirmed; the catalog format supports adding translations later without migration.

## 8. Routes & Controllers

```
AuthController        GET  /login, /signup
                      POST /login, /signup, /logout

BooksController       GET  /books                    list seed + own custom
                      GET  /books/new                custom-book form
                      POST /books                    create custom book + stats

AdventuresController  GET  /                         dashboard: active adventures
                      GET  /adventures/new           form
                      POST /adventures               create adventure
                      GET  /adventures/:id           main play view
                      POST /adventures/:id/status    mark completed/abandoned

StepsController       POST /adventures/:id/steps                 log next step
                      POST /adventures/:id/steps/:sid/undo       soft-undo
                      POST /adventures/:id/steps/:sid/redo       un-undo
                      GET  /adventures/:id/timeline              timeline fragment

StatsController       GET  /adventures/:id/stats/:sdid/modal     open value modal
                      POST /adventures/:id/stats/preview         mutate working value
                                                                 (returns modal fragment)
                      POST /adventures/:id/stats                 commit change

InventoryController   GET  /adventures/:id/inventory/modal       open value modal
                                                                 (for qty edits)
                      POST /adventures/:id/inventory/preview     working value
                      POST /adventures/:id/inventory             commit event

DiceController        POST /adventures/:id/roll                  returns rolled fragment

GraphController       GET  /adventures/:id/graph.json            JSON for Cytoscape
```

All mutating endpoints that change graph topology or step count emit `HX-Trigger: graph-changed`. A page-level JS listener re-fetches `graph.json` and calls `cy.json(...)` to update the graph view (only when the Graph tab is active).

All controllers MUST include a `[MVCPath('')]` + `[MVCPath('/')]` root handler (per `dmvc-webapp`).

## 9. Play View — UI & Step-logging Flow

### 9.1 Layout

`GET /adventures/:id` renders a Bulma two-column layout:

```
┌──────────────────────────────────────────────────────────────────────┐
│  Adventure title    Book: <localised title>                          │
│  Status: active                              [Complete] [Abandon]    │
├──────────────────────────┬───────────────────────────────────────────┤
│  Stats (current)         │  [ Timeline | Graph ]   ← tabs           │
│  ┌────────────────────┐  │  ┌─────────────────────────────────────┐ │
│  │ Geschicklichkeit 9 │  │  │ (active tab content)                │ │
│  │ Ausdauer  18       │  │  │                                     │ │
│  │ Glück     11       │  │  │                                     │ │
│  │ Magie      6       │  │  │                                     │ │
│  └────────────────────┘  │  │                                     │ │
│  Inventory               │  │                                     │ │
│  ┌────────────────────┐  │  │                                     │ │
│  │ Schwert            │  │  │                                     │ │
│  │ Laterne (Öl: 3)    │  │  │                                     │ │
│  │ Gold: 12           │  │  │                                     │ │
│  └────────────────────┘  │  └─────────────────────────────────────┘ │
│  Dice                    │  Log next step                           │
│  [Roll 2d6] [Roll 1d6]   │  From §[42] → To §[___]                 │
│  Last: 2d6 = 7           │  Note: [______________]                  │
│                          │  □ Fight  □ Item  □ Stat change          │
│                          │  [ Log step ]                            │
└──────────────────────────┴───────────────────────────────────────────┘
```

All visible labels above are illustrative and come from `l10n/<lang>.json` via `{{:l10n.key}}`. Stat/inventory item names come from the data layer (`stat_def_titles` / user-entered text), not l10n.

### 9.2 Step-logging flow

1. User types target section in *To §* and submits (`hx-post="/adventures/:id/steps"`, `hx-target="#step-form"`, `hx-swap="outerHTML"`).
2. `StepsController.LogStep` inserts a `steps` row (`seq = last+1`, `from_section = adventure's current section`, `to_section` from form, flags from checkboxes), updates `adventures.last_step_id`, returns the reset form fragment (now showing the new section in *From §*), and adds `HX-Trigger: step-logged, graph-changed`.
3. The page listener on `step-logged` issues an `hx-get` for `/adventures/:id/timeline` to refresh the timeline panel; the `graph-changed` listener re-fetches `graph.json` and refreshes Cytoscape.
4. Flag checkboxes (Fight/Item/Stat) set the step's flag columns but do not auto-open further dialogs. The user opens the relevant panel to record specifics, which attach to the current step.

### 9.3 Timeline tab

Vertical list of step rows, newest first:
`seq · §from → §to · note · flag-chips · timestamp`

Each row has an *Undo* link (becomes *Redo* when `undone=1`). Undone rows are visible but greyed and struck through.

### 9.4 Graph tab

Full-panel Cytoscape canvas. Nodes are section numbers (size scales with visit count, current section highlighted, revisited nodes outlined). Edges show step order via small numeric labels. Pan / zoom. Clicking a node scrolls the timeline to its first visit.

`graph.json` shape:

```json
{
  "current": 42,
  "nodes": [
    { "id": "s1",   "section": 1,   "visits": 1, "first_seq": 1 },
    { "id": "s42",  "section": 42,  "visits": 2, "first_seq": 2 },
    { "id": "s187", "section": 187, "visits": 1, "first_seq": 3 }
  ],
  "edges": [
    { "from": "s1",   "to": "s42",  "seq": 1 },
    { "from": "s42",  "to": "s187", "seq": 2 },
    { "from": "s187", "to": "s42",  "seq": 3 }
  ]
}
```

Undone steps are excluded.

### 9.5 Stat +/− modal (touch-friendly)

Clicking a stat row opens a Bulma modal (HTMX-fetched fragment):

```
┌─────────────────────────────────────┐
│  Ausdauer                           │
│       [ −5 ]  [ −1 ]                │
│            ┌────────┐               │
│            │   14   │               │
│            └────────┘               │
│        (was 18  •  Δ −4)            │
│       [ +1 ]  [ +5 ]                │
│  Grund (optional): [____________]   │
│        [ Cancel ]  [ Confirm ]      │
└─────────────────────────────────────┘
```

- `−5`, `−1`, `+1`, `+5` are HTMX `hx-post` to `/adventures/:id/stats/preview` carrying the current working value and the delta; the endpoint is **stateless** and returns the updated modal fragment with new working value and recomputed Δ. Pure server-side math, zero client JS for the arithmetic.
- A direct numeric input is also available.
- *Cancel* closes the modal — nothing persisted.
- *Confirm* posts to `/adventures/:id/stats`, which writes one `stat_changes` row (`old_value`, `new_value`, `reason`) bound to the current step, sets `steps.flag_stat = 1`, and returns the new stats-panel fragment plus `HX-Trigger: close-modal`.
- All clickable buttons are minimum 48×48 px (Bulma `is-large`) for touch.
- The same `_value_modal.html` partial is reused for inventory quantity edits (Gold +/−, oil +/−), parameterised by label, current value, step sizes, and submit endpoint.
- The +/− modal applies only to stats of kind `integer`. Stats of kind `text` use a simple inline text edit (Bulma input + save), and kind `checkbox` toggles in place. Both still write a `stat_changes` row bound to the current step.

### 9.7 Inventory editing

- **Add new item**: a small "+ Add item" form at the bottom of the Inventory panel (item name, optional quantity, optional note). Posts to `/adventures/:id/inventory` with `kind=gain`.
- **Adjust quantity of existing item**: clicking the quantity opens the shared value modal (Section 9.5).
- **Remove item**: a `[×]` button on the row posts `kind=lose` with the full current quantity (and the item disappears from the derived current-inventory view).

Current inventory is derived by folding `inventory_events` per `item_name`: sum of gains minus losses (and `modify` events set an absolute quantity). Items with net quantity ≤ 0 are excluded from display but events remain in history.

### 9.6 Dice

Two convenience buttons: *Roll 2d6*, *Roll 1d6*. Each posts to `/adventures/:id/roll`, which writes a `dice_rolls` row (with `step_id` = current step if any) and returns a small fragment with the result and the last few rolls. Results are **not** applied to stats automatically.

## 10. Localization

Per `dmvc-webapp/references/l10n-conventions.md`:

- `l10n/de.json` and `l10n/en.json` — flat key/value, identical key sets, German is the default.
- Keys grouped by prefix: `app_`, `nav_`, `btn_`, `lbl_`, `flash_`, `confirm_`, `login_`, plus app-specific `adv_`, `step_`, `stat_`, `inv_`, `dice_`, `book_`.
- Templates use `{{:l10n.key}}` only — no hardcoded user-visible strings.
- `<html lang="{{:current_lang}}">` set in `base.html`.
- Language switcher (DE / EN) in `partials/_navbar.html`.
- `TBaseController.OnBeforeAction` handles the lookup chain: `?lang=xx` → `Accept-Language` → `DEFAULT_LANGUAGE`.
- Pascal `resourcestring` is used **only** for log and exception messages, never for user-facing text — that lives in JSON.
- Data-layer strings (book titles, stat display names, user-entered item names) are **not** in JSON; they come from `book_titles`, `stat_def_titles`, or user input, via `LocalizedTitleService` (Section 6).

## 11. Error Handling

- **Validation errors** (bad section number, blank required field, duplicate username): controller re-renders the same fragment with a Bulma `is-danger` notification slot populated; no exceptions cross the controller boundary.
- **Auth failures**: redirect to `/login` with a flash; HTMX requests receive `HX-Redirect`.
- **Concurrency** (same adventure edited in two browser tabs): each mutating endpoint validates a hidden form field carrying `adventures.last_step_id`; a mismatch returns a 409 fragment instructing the user to refresh.
- **Unexpected exceptions**: a DMVC global exception handler logs the exception and returns a generic Bulma error fragment; stack traces are never exposed to the client.
- **All user-facing messages** use l10n keys; log/exception strings use `resourcestring`.

## 12. Testing (DUnitX)

- **Repository tests** against an in-memory SQLite — CRUD on each table, soft-undo exclusion queries, derived-state folds (current stats from `stat_changes`, current inventory from `inventory_events`).
- **Service tests** — adventure progression, step undo/redo flips, stat-change attribution to the current step, graph-builder output for cyclic / revisit-heavy paths, `LocalizedTitleService` fallback chain.
- **Controller tests** via DMVC's testing harness — auth gating, HTMX fragment rendering, `HX-Trigger` headers (`step-logged`, `graph-changed`, `close-modal`, `showFlash`), validation error rendering.
- **Seed loader tests** — idempotent upsert across boots, malformed YAML rejected with a clear error, removed-from-YAML rows not deleted from DB, removed-translation rows are deleted.
- **End-to-end smoke** — one DUnitX test spins the server against a temp SQLite, drives a ~6-step adventure via HTTP, asserts the timeline and `graph.json` shape.

Browser-level end-to-end is out of scope for v1.

## 13. Out of Scope (v1)

- Export / import of adventures as JSON
- Public read-only share links for adventures
- Admin role and shared promotion of custom books
- In-app gamebook text or section content
- Automatic application of dice rolls to stats
- Combat resolver
- Browser-driven end-to-end tests

## 14. Open Items for Implementation Plan

- Choose a YAML parser available for Delphi Linux64 (e.g. `Neon`, `Net.Yaml`, or a small hand-rolled subset parser sufficient for the seed file structure).
- Confirm Cytoscape.js bundle size / asset hosting; pin a version.
- Decide whether to include additional German titles in the seed for *The Warlock of Firetop Mountain* and *Deathtrap Dungeon* once confirmed; the catalog format supports adding them without migration.
