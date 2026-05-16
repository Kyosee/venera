# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Venera is a manga/comic reader with three components:

- **Flutter/Dart** (`lib/`) — Desktop (Windows/Linux/macOS) and mobile (Android/iOS) app. Uses QuickJS (`flutter_qjs`) to execute user-provided JavaScript comic source scripts. SQLite for local data storage.
- **Rust server** (`server/`) — Axum web server that serves the PWA frontend and proxies requests to a Node.js-based comic source runtime. Uses SQLite (rusqlite) for the PWA's independent database.
- **React PWA** (`web/`) — Vite + React 19 + TypeScript single-user PWA frontend. Runs in Docker or alongside the Rust server.

The Flutter app and the Rust server are independent. They do not share code or databases. Each has its own SQLite schema and its own way of executing comic source JS scripts (QuickJS in Flutter, Node.js child process in Rust).

## Common Commands

### Flutter App
```bash
# Lint
flutter analyze

# Run tests
flutter test

# Build APK
flutter build apk

# Build Windows
flutter build windows
```

### Rust Server
```bash
# Build
cd server && cargo build

# Run (serves PWA at localhost:3000)
VENERA_WEB_BIND=127.0.0.1:3000 VENERA_WEB_DATA_DIR=./data.venera/webpwa VENERA_WEB_STATIC_DIR=./web/dist cargo run

# Lint
cd server && cargo clippy
```

### Web PWA (development)
```bash
# Dev server with API proxy to Rust server (runs on port 5173)
cd web && npm ci && npm run dev

# Build for production
cd web && npm run build
```

### Docker PWA (full stack)
```bash
docker compose -f docker-compose.webpwa.yml up -d --build
```

## Architecture

### Flutter App (`lib/`)

**Entry**: `lib/main.dart` — supports `--headless` mode and normal UI mode.

**Foundation layer** (`lib/foundation/`):
- `comic_source/` — `ComicSourceManager` manages JS comic source scripts. Sources define `key`, `name`, `version` and implement search/info/pages. Sources are executed via QuickJS (`js_engine.dart`, `js_pool.dart`).
- `app.dart` — global app state and platform detection
- `history.dart`, `follow_updates.dart` — reading history and update tracking
- `comic_type.dart`, `source_platform.dart` — comic type and source platform enums

**Pages** (`lib/pages/`): `main_page.dart` (tab shell), `reader/` (comic reader with gallery modes), `favorites/`, `search_page.dart`, `history_page.dart`, `local_comics_page.dart`, `settings/`

**Network** (`lib/network/`): HTTP client via Dio, image caching, proxy support

**Utils** (`lib/utils/`): CBZ/EPUB/PDF parsing, WebDAV data sync, comic import

### Rust Server (`server/src/`)

**Stack**: Axum + Tokio + Rusqlite. Single-user LAN mode, no auth.

**Entry**: `main.rs` — loads config from env vars, connects SQLite, mounts `/api` routes and serves static PWA files.

**Key modules**:
- `routes.rs` — all API handlers (library, favorites, sources, search, comic info/pages, WebDAV, backup import, follow-updates, image proxy, settings)
- `source_runtime.rs` — invokes `source-runtime.mjs` via `node` as a child process. Each call is a subcommand (search, info, pages, manifest, settings, etc.) with a 20-second timeout. Responses parsed from JSON envelopes.
- `webdav_runtime.rs` — WebDAV client for backup upload/download
- `db.rs` — database connection + schema migration (WAL mode, incremental column adds)
- `models.rs` — request/response types
- `config.rs` — env-based config (`VENERA_WEB_*` vars)
- `import_preview.rs` / `backup_export.rs` — zip-based data import/export
- `image_proxy.rs` — image caching proxy with 7-day immutable cache headers

**Database (`0001_init.sql`)**: settings, comic_sources, reading_history, favorites, favorite_folders, favorite_folder_items, webdav_config, tasks. Schema uses soft upgrades via `ALTER TABLE ADD COLUMN` in `db.rs`.

### React PWA (`web/src/`)

- `App.tsx` — single-page app with tabs (Home, Library, Search, Explore, Settings). Uses URL hash-based navigation. All state managed via `useState`/`useEffect`; no router library.
- `api.ts` — typed fetch client for all `/api` endpoints. Also exports all TypeScript response types.
- `ReloadPrompt.tsx` — PWA update prompt using vite-plugin-pwa's `registerType: 'prompt'`
- `styles.css` — all styles in one file

**Dev flow**: Vite dev server proxies `/api` to the Rust server at `127.0.0.1:3000`. Start the Rust server first, then run `npm run dev`.

### Comic Source Scripts

Comic sources are JavaScript files implementing a `ComicSource` class. In the Flutter app, they live in the app's data directory and run via QuickJS. In the Rust server, they live in `$DATA_DIR/sources/` and run via `node source-runtime.mjs search|info|pages|manifest|...`. The source runtime uses a JSON envelope `{ ok: bool, data: T, error: string }`.

## WebDAV Sync

The Flutter app and Rust server both support WebDAV backup/restore independently. The Rust server's WebDAV flow exports a zip backup, then uploads it. Import goes the other direction — download zip from WebDAV, preview contents, apply to database.

## Tool

`tool/windows_updater.dart` — Windows self-update utility that downloads and replaces the current binary from GitHub Releases.

## Development Rules

- Commit when a task or requirement is completed. Use concise Chinese commit messages. Commit scope should match the completed task — don't batch unrelated changes.
- Use `git add <specific files>` not `git add -A` for own changes. Leave user's unrelated modifications uncommitted unless user explicitly asks.
