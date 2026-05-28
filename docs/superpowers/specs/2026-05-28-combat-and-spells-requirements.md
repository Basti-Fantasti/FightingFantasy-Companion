# Combat, Spells & Starting Gear — Requirements (pre-brainstorm)

**Date:** 2026-05-28
**Status:** Requirements draft — input for a brainstorming session, not a spec
**Supersedes nothing.** Extends `2026-05-27-fightingfantasy-companion-design.md` §13 (which lists "Combat resolver" as out of scope for v1).

## Why this exists

The v1 design deliberately excluded combat automation. User feedback on *Die Zitadelle des Zauberers* (Citadel of Chaos, German edition) makes clear that without combat, spell-slot, and starting-gear support, the companion is missing the parts of solo play that benefit most from a digital helper. This document captures what those features need to cover so the next brainstorming session has a concrete starting point.

## Scope of this document

Three related but separable features:

1. **Combat resolver** — round-by-round duel between player and monster(s).
2. **Spells (`Zauberformeln`)** — finite per-adventure spell list whose entries are consumed by use.
3. **Starting gear / inventory presets** — per-book default inventory applied at adventure start.

Each can ship independently. Combat is the largest; spells touch combat (spells can affect a duel) and inventory (spell list lives alongside items); gear is the smallest.

## 1. Combat resolver

### 1.1 Rule summary (Citadel of Chaos / classic FF)

- Both sides have **Skill** (`Gewandtheit`) and **Stamina** (`Stärke`).
- Each round:
  1. Each side rolls **Attack Strength = 2d6 + Skill**.
  2. Higher Attack Strength wins the round.
  3. Loser takes **2 Stamina damage**. Tie = parry, no damage.
- Combat ends when one side's Stamina reaches 0.
- **Luck** (`Glück`) may be tested after a hit:
  - *Lucky* on damage dealt → +2 (4 total).
  - *Lucky* on damage taken → −1 (1 total).
  - *Unlucky* on damage dealt → −1 (1 total).
  - *Unlucky* on damage taken → +1 (3 total).
  - Each Luck test reduces Luck by 1 regardless of result.

These are the canonical FF rules; user-described rules in the chat align with this. The implementation must encode this exactly — no "house rule" variants in v1.

### 1.2 Functional requirements

- **Start a combat** attached to the current step (sets `steps.flag_fight = 1`).
- **Enter monster(s)** — name, Skill, Stamina. Support multiple monsters fought in sequence (FF books often list "Monster 1 then Monster 2"). Simultaneous multi-attacker combat (rare in Citadel) is a later concern, not v1 of this feature.
- **Round log** — for each round, record both Attack Strengths, the dice rolls, the winner, damage applied, and any Luck test outcome. The log is the audit trail; the user can read it back.
- **Auto-apply damage** to the active side's Stamina via the existing `stat_changes` mechanism, tagged with a reason like `"Combat round 3 — hit by Goblin"`.
- **Luck test action** inside a round — prompts for which direction (dealing/taking) and applies the modifier + Luck decrement atomically.
- **End combat** — explicit "Victory" / "Fled" / "Defeated" outcomes; ties the combat record to the step and updates the timeline chip from generic "Fight" to e.g. "Defeated Goblin (4 rounds)".
- **Spell interaction (forward-looking)** — combat must be able to consume a `Zauberformel` mid-fight (see §2). Design data shapes so this fits cleanly.

### 1.3 Data model sketch

New tables (names tentative):

```
combats        (id, step_id, outcome, started_at, ended_at NULL)
                -- outcome: 'in_progress' | 'victory' | 'fled' | 'defeated'

combat_foes    (id, combat_id, ord, name, skill, stamina_start, stamina_current)
                -- one row per monster; ord = sequence

combat_rounds  (id, combat_id, foe_id, round_no,
                player_roll, player_attack,
                foe_roll, foe_attack,
                winner,                -- 'player' | 'foe' | 'tie'
                damage_to,             -- 'player' | 'foe' | NULL
                damage_amount,
                luck_tested BOOL, luck_result NULL, -- 'lucky' | 'unlucky'
                spell_used_id NULL,    -- FK to spells consumed this round
                created_at)
```

Stamina is mirrored in `combat_foes.stamina_current` (combat-scoped) while player Stamina remains the derived stat. The `stat_changes` rows produced by each round give the audit fold; `combat_foes.stamina_current` is a cache.

### 1.4 UI sketch

A combat panel that opens from the step form when *Fight* is checked, or from a button on a step already flagged as a fight. Compact round-runner:

```
┌─ Kampf: Ork (Gewandtheit 7, Stärke 6) ───────────────┐
│ Runde 3                                              │
│ Spieler: 2W6 = [4][5] + 9 = 18                       │
│ Ork:     2W6 = [3][6] + 7 = 16                       │
│ → Spieler trifft. Ork verliert 2 Stärke.             │
│                                                      │
│ [Glück testen — verstärken] [Glück testen — mindern] │
│ [Zauber einsetzen ▼]   [Nächste Runde]   [Fliehen]   │
└──────────────────────────────────────────────────────┘
```

Driven by HTMX, same pattern as the existing stat +/− modal.

### 1.5 Open questions for brainstorm

- How does combat behave under soft-undo? Undoing a step that owns a combat should undo all its stat changes (consistent with current step undo), but the `combat_rounds` rows should remain visible-but-greyed, matching the timeline convention.
- Multi-foe sequence vs. melee — is "one combat row, multiple foes fought one after another" or "one combat per foe" the right grain?
- Should the dice roller (`/adventures/:id/roll`) be reused for combat rolls, or does combat have its own roll endpoint that writes both `dice_rolls` and `combat_rounds`?
- Concurrency: combat is multi-step state. The existing `adventures.last_step_id` optimistic check (design §11) may not be sufficient — likely need a `combats.version` or similar.

## 2. Spells (`Zauberformeln`)

### 2.1 Rules (Citadel of Chaos)

- At adventure start, the player picks **N spells** from a fixed book list, where N = starting `Zauberkraft` (Magic).
- Each spell may be chosen multiple times (e.g. take *Stärke* twice).
- Casting a spell **removes one instance** from the list ("cross out"). It does not decrement the `Zauberkraft` stat — the stat is just the budget that determined the starting list.
- Some spells are combat-relevant (e.g. *Schwäche* lowers a foe's Skill); others are exploration/puzzle.

The user's chat description said "each casted spell decreases this stat by 1" — that's a reasonable simplification but does not match the book's *list with strikeout* mechanic. Need to confirm with the user during brainstorm which behavior they want; this doc assumes the canonical list-with-strikeout.

### 2.2 Functional requirements

- **Book-level spell catalog** — seed each book that has spells with its full spell list (name, optional description). Citadel of Chaos has ~14 spells.
- **Adventure setup** — when starting a Citadel adventure, prompt the user to pick `Zauberkraft` spell instances from the catalog (with repeats allowed). Persist as the adventure's *spellbook*.
- **Cast / consume** — a "Cast" action on a spell instance removes it from the available list and records a step-attached event (`flag_spell` or reuse `flag_stat` with reason).
- **Combat integration** — within a combat panel, "Zauber einsetzen" lists currently-available spells; selecting one consumes it and records the round's `spell_used_id`. Mechanical effect on the round (Skill modifier, auto-win, etc.) is per-spell metadata; for v1, keep it informational only — the user manually adjusts stats if the spell modifies them. Spell effect automation is a v2 concern.

### 2.3 Data model sketch

```
spell_defs            (id, book_id, name_slug)
spell_def_titles      (spell_def_id, lang, display_name, description)

adventure_spells      (id, adventure_id, spell_def_id, ord, consumed_at NULL,
                       consumed_step_id NULL)
                      -- one row per *instance* picked at start;
                      -- consumed_at NULL = still available
```

### 2.4 Open questions

- Should the spell list be a first-class panel on the adventure page (alongside Stats / Inventory), or live under Inventory?
- Do we want spell descriptions in the seed, or only names (since the user has the book)?
- How should the spell-pick UI work — drag-to-budget, +/− counters per spell, or a free pick with a running "X of N selected" counter? Touch-friendly is a hard requirement.

## 3. Starting gear

### 3.1 Citadel of Chaos starting inventory

- Schwert (Sword)
- Lederrüstung (Leather Armor)
- Fackel (Torch)

Other books will have different defaults (e.g. *Warlock of Firetop Mountain* gives a Sword + Leather Armor + 10 Provisions + Lantern).

### 3.2 Functional requirements

- **Seed format extension** — each book entry in `books_seed.yaml` may declare a `starting_inventory` list with `name`, optional `quantity`, optional localized `titles`.
- **Adventure start hook** — when an adventure is created, the seeder emits a synthetic first step (or attaches to step 1) with `inventory_events` rows of `kind=gain` for each starting item. These appear in the timeline as the opening state.
- **Per-user override** — the adventure-creation form lets the user uncheck/edit defaults before confirming, since some readers may have already lost their torch in §1.

### 3.3 Data model

No new tables. Reuses `inventory_events`. The seed loader gains a `starting_inventory` parser; the adventure-create service emits the events.

### 3.4 Open questions

- Quantity defaults — Citadel's torch is binary, but provisions in other books are integer. Confirm seed schema supports both.
- Should starting inventory be localized in the seed (`titles: { de: Schwert, en: Sword }`), or store the German name and let the i18n layer translate? Inventory item names today are free-text user input — adding seeded localization is a small but real schema change.

## 4. What this document is *not*

- Not a spec. The brainstorming session decides scope, sequencing, and which open questions get answered which way.
- Not a plan. No file list, no test list, no migration order yet.
- Not a commitment to ship all three. The session may decide to do only starting gear in the next iteration and defer combat by another cycle.

## 5. Suggested brainstorm agenda

1. Confirm rule fidelity — are we encoding canonical FF rules verbatim, or supporting variants?
2. Resolve the spell-consumption model (list-with-strikeout vs. stat decrement).
3. Decide combat grain (one combat row per foe vs. per encounter).
4. Pick sequencing: gear → spells → combat, or combat first because it's the highest-value pain point?
5. Identify the smallest shippable slice that proves the data model works end-to-end.
