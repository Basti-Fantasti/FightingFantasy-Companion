# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-05-29

### Fixed
- Container failed to start on a fresh host with `ESQLiteNativeException ... unable to open database file`. The data directory was a bind mount (`./data`), which Docker creates as `root` on first run, so the non-root `ff` user (UID 999) could not create the SQLite file. Both compose files now use a Docker-managed named volume (`ffcompanion-data`), which is initialized with the image directory's `ff:ff` ownership and is writable by the runtime user.

### Changed
- `docker/.env`: bumped `IMAGE_TAG` to `v0.1.1`.

## [0.1.0] - 2026-05-28

### Added
- Initial release of the Fighting Fantasy Companion DMVC server.
- Books catalog with seed data (Citadel of Chaos) and custom book creation.
- Authentication (login, signup, logout) with bcrypt password hashing.
- Adventures: dashboard, create form, play view, and state-folding service.
- Step logging with monotonic sequence and soft undo/redo, HTMX timeline refresh.
- Stat changes with undo-aware folding and touch-friendly stat editor.
- Inventory panel with gain/lose/modify events and folding.
- Spells and starting gear: spell catalog, casting (oldest-first), revert on undo.
- Dice roller (2d6, 1d6) with history.
- Cytoscape graph view backed by a graph builder service and revisit highlighting.
- DE/EN localization catalogs with key-parity test.
- SQLite migration runner and in-memory test harness.
- Dockerfile (Linux64) and docker-compose for deployment, with GHCR image tag.
