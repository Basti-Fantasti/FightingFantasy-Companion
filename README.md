# Fighting Fantasy Companion

A record-keeping companion for solo play of *Fighting Fantasy* gamebooks. The
app does not contain gamebook text and does not automate combat; it tracks the
**exact decision path** you take through a book (every section visited, every
jump made, every revisit), the **per-book configurable stats** (Skill, Stamina,
Luck, plus book-specific stats like *Magic* for Sorcery!-style titles), and the
**inventory** changes along the way. Two views of the journey are provided: a
chronological **timeline** and an interactive **graph**.

Server-side rendered in Delphi (DMVCFramework + TemplatePro) with HTMX +
Bulma CSS on the client; Cytoscape.js powers the graph view. Storage is
SQLite. The app is deployed as a single Linux64 binary in a Docker container.

UI is available in **German** (default) and **English**.

## Running with Docker

The Linux64 binary is built externally (Windows-hosted Delphi cross-compiler);
the Docker image just packages the binary plus the runtime assets.

```bash
# 1. Build the Linux64 binary (requires Delphi + the delphi-build MCP server)
#    Output: bin/Linux64/Release/FFCompanion

# 2. Build and start the container
docker compose -f docker/docker-compose.yaml up -d --build

# 3. Open the app
xdg-open http://localhost:8080/signup
```

The SQLite database is persisted on a host volume at `./data/ffcompanion.db`.
Sign up (no email, just username + password); first login redirects to the
dashboard. The book catalog (Citadel of Chaos, The Warlock of Firetop
Mountain, Deathtrap Dungeon) is seeded on first boot from
`data/books_seed.yaml`; you can also define **custom books** with arbitrary
stat fields from the UI.

### Environment variables

| Variable           | Default                       | Purpose                       |
|--------------------|-------------------------------|-------------------------------|
| `HTTP_PORT`        | `8080`                        | Port the server listens on    |
| `DEFAULT_LANGUAGE` | `de`                          | Fallback when no language     |
|                    |                               | header / query param given    |
| `DATABASE_PATH`    | `/app/data/ffcompanion.db`    | SQLite file path              |

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
docker/        Dockerfile + docker-compose.yaml
tests/         DUnitX test suite
docs/          superpowers/specs + plans
```

## Tests

```bash
# Build the test runner (Win64 only):
mcp__delphi-build__compile_delphi_project  # tests/FFCompanionTests.dproj

# Run:
tests/bin/Win64/Debug/FFCompanionTests.exe
```

34 tests cover migrations, repositories, services (auth / localized title /
YAML reader / book catalog / state folding / graph builder), and one
end-to-end HTTP playthrough that drives a 6-step adventure (with an undo) and
asserts the resulting `graph.json` shape.

## Design & implementation history

- Spec: [`docs/superpowers/specs/2026-05-27-fightingfantasy-companion-design.md`](docs/superpowers/specs/2026-05-27-fightingfantasy-companion-design.md)
- Plan: [`docs/superpowers/plans/2026-05-27-fightingfantasy-companion.md`](docs/superpowers/plans/2026-05-27-fightingfantasy-companion.md)
