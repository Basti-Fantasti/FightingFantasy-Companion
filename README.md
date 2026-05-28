# Fighting Fantasy Companion

A record-keeping companion for solo play of *Fighting Fantasy* gamebooks. The
app does **not** contain gamebook text and does **not** automate combat - it
keeps an honest log of your playthrough so you can focus on the book and still
have a complete record of where you went, what you carried, and how your stats
evolved.

UI is available in **German** (default) and **English**.

![License](https://img.shields.io/badge/license-see%20LICENSE-blue)
![Backend](https://img.shields.io/badge/backend-Delphi%20%2B%20DMVCFramework-red)
![Frontend](https://img.shields.io/badge/frontend-HTMX%20%2B%20Bulma-teal)
![Storage](https://img.shields.io/badge/storage-SQLite-lightgrey)

## Features

- **Decision-path tracking** - every section visited, every jump made, every
  revisit. The full chronological trail of your adventure, never just the
  current page.
- **Per-book configurable stats** - Skill, Stamina and Luck are standard, but
  each book defines its own set. *Sorcery!*-style titles get an extra *Magic*
  stat; you can also define **custom books** with arbitrary stat fields from
  the UI.
- **Inventory management** - pick up, drop, consume and use items as you go;
  starting inventory is seeded from the book definition.
- **Spells / abilities** - for spell-using books, casting a spell is recorded
  and consumption is reverted on undo.
- **Soft-undo** - step back a move; stat changes, inventory pickups and spell
  uses are rolled back together.
- **Timeline view** - chronological list of every section, jump and event.
- **Interactive graph view** - a Cytoscape.js graph of the sections you
  visited and the jumps between them. Revisits, branches and dead ends are
  visible at a glance.
- **Dice roller** - built-in d6 / 2d6 roller for stat checks and combat.
- **Multi-adventure** - keep several runs in parallel; switch between them
  freely.
- **Multi-user** - sign up with just username + password (no email). Each
  user's adventures are isolated.
- **Parchment / ink theme** - touch-friendly UI tuned for tablets next to an
  open book.
- **Localized** - full German and English interfaces, including localized
  stat names, item names and spell descriptions per book.
- **Seeded catalog** - *The Citadel of Chaos*, *The Warlock of Firetop
  Mountain* and *Deathtrap Dungeon* ship out of the box.

## Quick start (deployment)

You don't need to clone the repo. The image is published to the GitHub
Container Registry; only the deploy compose file is needed.

```bash
# 1. Fetch the deploy compose file and store it as docker-compose.yaml
curl -fsSLo docker-compose.yaml \
  https://raw.githubusercontent.com/Basti-Fantasti/FightingFantasy-Companion/main/docker/docker-compose.deploy.yaml

# 2. Bring it up
docker compose up -d

# 3. Open the app
xdg-open http://localhost:8099/signup
```

The SQLite database is persisted at `./data/ffcompanion.db` next to the
compose file. Sign up (username + password, no email), and you're in.

### Environment variables

| Variable           | Default                       | Purpose                                     |
|--------------------|-------------------------------|---------------------------------------------|
| `HTTP_PORT`        | `8080`                        | Port the server listens on (inside the container) |
| `DEFAULT_LANGUAGE` | `de`                          | Fallback when no language header / query param given |
| `DATABASE_PATH`    | `/app/data/ffcompanion.db`    | SQLite file path                            |
| `SEED_YAML_PATH`   | `/app/seed/books_seed.yaml`   | Book catalog seed file                      |
| `TZ`               | `Europe/Berlin`               | Container timezone                          |

To use a different host port, change the left-hand side of the `ports:`
mapping in `docker-compose.yaml` (e.g. `"9000:8080"`).

## Contributing

### Adding more books

The seeded catalog covers three titles. **PRs to add further Fighting
Fantasy books are very welcome** - they'll ship in the next release. Add an
entry to [`data/books_seed.yaml`](data/books_seed.yaml) following the
existing pattern (slug, English/German titles, per-book stats, starting
inventory, and - for spell-using titles - the spell list with localized
names and descriptions), then open a pull request.

### Translations

UI strings live in [`l10n/de.json`](l10n/de.json) and
[`l10n/en.json`](l10n/en.json). If you'd like to see another UI language,
or you spot a wording that could be improved, please **open a pull request**
with the new catalog, or **open a GitHub issue** describing what's missing
and we'll coordinate from there.

## Project layout

```
controllers/   DMVC HTTP controllers (one per resource)
models/        Plain record types
services/      Business logic (auth, catalog, graph builder, state folding)
repositories/  FireDAC SQLite access
webmodule/     DMVC engine wiring + migrations + seed-on-boot
templates/     TemplatePro views (pages, layouts, partials)
static/        Bulma, HTMX, Cytoscape, app.css, app.js
l10n/          Flat-JSON message catalogs (de.json, en.json)
data/          books_seed.yaml + SQLite at runtime
docker/        Dockerfile + docker-compose.yaml + docker-compose.deploy.yaml
tests/         DUnitX test suite
```

## Tests

```bash
# Build the test runner ./tests/FFCompanionTests.dproj using the Delphi IDE (Win64 only)

# Run:
tests/bin/Win64/Debug/FFCompanionTests.exe
```

34 tests cover migrations, repositories, services (auth / localized title /
YAML reader / book catalog / state folding / graph builder), and one
end-to-end HTTP playthrough that drives a 6-step adventure (with an undo)
and asserts the resulting `graph.json` shape.
