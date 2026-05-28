# Spells & Starting Gear — Design

**Date:** 2026-05-28
**Status:** Design (approved scope; ready for implementation plan)
**Inputs:** [`2026-05-28-combat-and-spells-requirements.md`](2026-05-28-combat-and-spells-requirements.md), [`2026-05-27-fightingfantasy-companion-design.md`](2026-05-27-fightingfantasy-companion-design.md)
**Out of scope:** Combat resolver (deferred to a dedicated brainstorm). Spell-effect automation (informational only in this iteration).

## 1. Goal

Add two opt-in-per-book features to the adventure-create flow and the
adventure page:

1. **Starting gear** — each book can declare a default inventory in the seed;
   the adventure-create form lets the user accept/edit it before submitting.
2. **Spells (`Zauberformeln`)** — books with a spell catalog (Citadel of
   Chaos initially) get a pick UI driven by the starting Magic value; the
   adventure page gains a Spells panel where instances are cast and
   struck off.

Both features land in the same release and share the adventure-create form.

## 2. Architecture

Two capabilities, one shared seam.

- **Seed-driven, opt-in.** Books without `starting_inventory` skip the gear
  UI; books without `spells` skip the spell UI. Existing books (Warlock,
  Deathtrap) keep working unchanged.
- **Setup step.** Starting gear is anchored to a synthetic *setup step*
  (`steps.kind='setup'`, `section_no=NULL`, `ord=0`) created in the same
  transaction as the adventure. Inventory_events for starting items attach
  there. Timeline shows it as the opening chip; graph view filters it out.
- **List-with-strikeout for spells.** At adventure start, the player picks
  Magic instances from the book's spell catalog (repeats allowed). Each
  cast strikes one instance off; the Magic stat itself never changes after
  setup. Matches the canonical FF rule; supersedes the
  "stat decrement per cast" sketch in the requirements doc.
- **No combat coupling.** Spell casts in this iteration are informational
  — they record what was cast and when, but do not auto-apply effects.
  Combat-spell automation is part of the deferred combat brainstorm.

## 3. Data model

### 3.1 New tables (spells)

```
spell_defs        (id INTEGER PK,
                   book_id INTEGER NOT NULL REFERENCES books(id),
                   slug TEXT NOT NULL,
                   ord INTEGER NOT NULL,
                   UNIQUE (book_id, slug))

spell_def_titles  (spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id),
                   lang TEXT NOT NULL,                -- 'de' | 'en'
                   display_name TEXT NOT NULL,
                   description TEXT NOT NULL,
                   PRIMARY KEY (spell_def_id, lang))

adventure_spells  (id INTEGER PK,
                   adventure_id INTEGER NOT NULL REFERENCES adventures(id),
                   spell_def_id INTEGER NOT NULL REFERENCES spell_defs(id),
                   ord INTEGER NOT NULL,              -- pick order
                   consumed_at TEXT NULL,             -- ISO-8601 UTC
                   consumed_step_id INTEGER NULL REFERENCES steps(id))
                  -- one row per *instance* picked at start
                  -- consumed_at NULL = still available
```

Indexes:

- `idx_adventure_spells_avail (adventure_id, consumed_at)` — drives the
  Spells panel query.
- `idx_adventure_spells_step (consumed_step_id)` — drives soft-undo
  (re-availability when a step is undone).

### 3.2 Schema changes to `steps`

- Add column `kind TEXT NOT NULL DEFAULT 'normal'` with values
  `'normal' | 'setup'`.
- Relax `section_no` to `NULL`-able (setup steps have no section number).
- Existing controllers/templates that read `section_no` get a defensive
  branch for `NULL`, but in practice setup steps are filtered out of all
  user-facing lists except the timeline chip.

### 3.3 Gear (no new tables)

Reuses `inventory_events` (already keyed by step). The seed loader gains a
`starting_inventory` parser; the adventure-create service emits one
`inventory_events` row (`kind=gain`) per kept item, attached to the setup
step. Item names are free text, the same as user-added inventory today —
the seed's localized title for the user's current language is used at
create time.

### 3.4 Seed format

```yaml
- slug: citadel-of-chaos
  ...
  starting_inventory:
    - { slug: sword,         titles: { de: Schwert,      en: Sword } }
    - { slug: leather-armor, titles: { de: Lederrüstung, en: Leather Armor } }
    - { slug: torch,         titles: { de: Fackel,       en: Torch } }
  spells:
    - slug: weakness
      titles:
        de: { name: Schwäche, description: "Senkt die Gewandtheit eines Gegners." }
        en: { name: Weakness, description: "Lowers a foe's Skill." }
    - slug: strength
      titles:
        de: { name: Stärke,   description: "Erhöht die eigene Gewandtheit." }
        en: { name: Strength, description: "Raises your Skill." }
    # ... remaining Citadel spells
```

Notes:

- `slug` is the stable identifier; titles are the user-facing string.
- `starting_inventory` items support an optional `quantity` (default 1).
- Seed-on-boot is idempotent: spells are upserted by `(book_id, slug)`;
  titles are upserted by `(spell_def_id, lang)`. Removing a spell from
  the seed does **not** delete it from the DB (would orphan instances in
  existing adventures); a `deprecated` flag can be added later if needed.

## 4. Flows

### 4.1 Adventure create

```
1. GET  /adventures/new                       (book picker)
2. POST /adventures/new   { book_id }         → HTMX swap returns
                                                book-specific form sections:
                                                Stats / Starting gear / Spells
3. POST /adventures        (full form)        → transaction:
                                                a. INSERT adventures
                                                b. INSERT steps (kind=setup,
                                                   section_no=NULL, ord=0)
                                                c. INSERT inventory_events
                                                   for each kept gear row
                                                d. INSERT adventure_spells
                                                   (one row per +click)
                                                e. INSERT stat_changes for
                                                   initial stat values
                                              → 303 to /adventures/:id
```

Form sections are conditional on seed content:

- **Starting gear** section: rendered if book has `starting_inventory`.
  Each item is a row: `[✓] <name>  [qty: <n>]` (qty editable, name
  editable). Unchecked rows are skipped on submit.
- **Spells** section: rendered if book has `spells` AND its Magic stat
  default > 0. Layout:
  - Sticky header: `<picked> von <budget> Zaubern gewählt`.
  - Per-spell row: `<name>` — `<description>` — `[−] <count> [+]`.
  - `[+]` disables when `picked == budget`; `[−]` disables at 0.
  - Each click is an HTMX `POST` to an in-memory form-state endpoint that
    re-renders the picker partial with updated counts and disabled states.
    The picks live in the form (hidden field array) until final submit; no
    DB writes until the adventure is created.
- Server-side validation on final submit re-checks
  `sum(picks) == budget`. Mismatch returns the form with an error.

### 4.2 Spells panel (adventure page)

Rendered if the adventure has any `adventure_spells` rows.

```
┌─ Zauberformeln ─────────────────────────────────┐
│ Verfügbar                                       │
│   Stärke    ×2     [Wirken]                     │
│   Schwäche  ×1     [Wirken]                     │
│   Glück     ×1     [Wirken]                     │
│                                                 │
│ Verbraucht                                      │
│   Stärke     — §47                              │
└─────────────────────────────────────────────────┘
```

- Available spells are grouped by `spell_def_id` with a count badge.
- A single **Wirken** button per group casts the oldest unconsumed instance
  of that spell (deterministic; matches the "strike off the next one"
  feel).
- Consumed list is greyed; each line links to the step where it was cast.

### 4.3 Cast flow

```
POST /adventures/:id/spells/cast   { spell_def_id }
```

- Validates: the adventure has an unconsumed instance of `spell_def_id`,
  and `adventures.last_step_id IS NOT NULL` (player has entered at least
  one section past setup). If `last_step_id` is NULL, return a flash:
  *"Erst eine Sektion betreten, dann zaubern."*
- Selects the oldest unconsumed instance:
  `WHERE adventure_id=? AND spell_def_id=? AND consumed_at IS NULL
   ORDER BY ord ASC LIMIT 1`.
- Sets `consumed_at = now`, `consumed_step_id = last_step_id`.
- Returns an HTMX partial that swaps the Spells panel AND appends a
  spell sub-chip to the current step on the timeline.
- Does **not** modify any stat. Players who want stat effects use the
  existing Stats +/− modal.

### 4.4 Soft-undo

- Undoing a step (existing mechanism): all `adventure_spells` rows with
  `consumed_step_id = <step>` revert to `consumed_at=NULL,
  consumed_step_id=NULL`. The instances reappear in **Verfügbar**.
- Setup step (`kind='setup'`) is non-deletable from the UI and not exposed
  to the undo control. Its inventory_events are immutable for the
  adventure's lifetime.

### 4.5 Timeline & graph

- **Timeline.** Setup step renders as a chip at position 0:
  `Setup — Schwert, Lederrüstung, Fackel`. Cast events render as
  sub-chips on the owning step in the existing inventory-chip family.
- **Graph.** The graph builder filters `WHERE kind='normal'` so setup
  steps produce no node. Section numbering and edges are unaffected.

## 5. Affected code

This is a guide, not an exhaustive list — the plan will firm it up.

- `data/books_seed.yaml` — add `starting_inventory` + `spells` for Citadel.
- `webmodule/MigrationsU.pas` — new migration: spells tables, `steps.kind`,
  `steps.section_no` nullable.
- `webmodule/SeedU.pas` (or equivalent) — parse and upsert spells from
  the seed; idempotent.
- `models/` — new records for `TSpellDef`, `TAdventureSpell`, plus
  `steps.kind` field on the existing `TStep` record.
- `repositories/` — `SpellDefRepoU`, `AdventureSpellRepoU`; extend
  `StepRepoU` to read/write `kind` and tolerate NULL `section_no`.
- `services/`
  - extend `AdventureServiceU` (create flow) to write setup step + gear
    events + spell picks atomically;
  - new `SpellServiceU` with `Cast(adventureId, spellDefId)` and
    soft-undo hook;
  - extend `GraphBuilderU` to filter setup steps.
- `controllers/`
  - extend `AdventureControllerU` (POST `/adventures/new` HTMX section,
    POST `/adventures`);
  - new `SpellControllerU` for the cast endpoint.
- `templates/`
  - extend the adventure-create form (gear section, spell picker partial);
  - new spells panel partial on the adventure page;
  - extend timeline partial for the setup chip and spell sub-chips.
- `l10n/de.json`, `l10n/en.json` — new strings (panel titles, errors,
  empty states).

## 6. Testing (DUnitX)

- **Migration**: applies cleanly; `steps.kind` defaults to `'normal'`
  for existing rows (greenfield migration, so this is just sanity).
- **Seed loader**: parses `starting_inventory` and `spells` blocks;
  upserts are idempotent across two boots; `spell_def_titles` populated
  for both langs.
- **Adventure create service**:
  - setup step created with `kind='setup', section_no=NULL, ord=0`;
  - gear `inventory_events` attached to the setup step;
  - `adventure_spells` rows match the submitted picks (count + ord);
  - oversum picks rejected.
- **Cast service**:
  - oldest unconsumed instance is selected;
  - rejection when `last_step_id IS NULL`;
  - soft-undo of the casting step re-availabilizes the instance.
- **End-to-end HTTP**: create a Citadel adventure with `2× Stärke +
  1× Schwäche`, enter Section 1, cast Stärke, assert panel counts
  (Verfügbar Stärke ×1, Verbraucht Stärke ×1), undo the step, assert
  panel returns to ×2 / ×0.
- **Graph builder**: setup step produces no node; edges from Section 1
  onward are unaffected.

## 7. Open items consciously deferred

- **Combat resolver** — separate brainstorm.
- **Spell effect automation** (Stärke auto-boosts player Skill, etc.) —
  deferred with combat; spell-defs schema is already shaped to grow
  optional effect metadata later.
- **Custom-book spell catalogs** — UI for custom books to declare their
  own spell list. Out of scope; seeded books only for now.
- **Deprecating seeded spells** — if a future seed change removes a
  spell already in use, we'll add a `deprecated` flag to `spell_defs`.
  Not built now.
