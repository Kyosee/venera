# Venera

[![Flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![AI-Driven](https://img.shields.io/badge/AI--Driven-Claude%20Opus%204.7-6e47ff)](https://claude.ai)
[![License](https://img.shields.io/github/license/kyosee/venera)](https://github.com/kyosee/venera/blob/master/LICENSE)
[![Stars](https://img.shields.io/github/stars/kyosee/venera?style=flat)](https://github.com/kyosee/venera/stargazers)
[![Release](https://img.shields.io/github/v/release/kyosee/venera)](https://github.com/kyosee/venera/releases)

**[中文](README_CN.md) | English**

A cross-platform manga/comic reader with self-hosted Web frontend support.

> **Disclaimer:** This repository is for personal learning and use only.

## Warning

**Do NOT deploy the Web frontend on the public internet.** It is designed for personal use on a trusted LAN only. Exposing it publicly may lead to attacks, traffic abuse, and data leaks (cookies, WebDAV config, personal data). All legal and security risks are your own.

## Features

- Multi-platform: Windows, Linux, macOS, Android, iOS
- JavaScript-based comic source plugins (QuickJS on native, Node.js on server)
- Self-hosted Web frontend with Docker support
- WebDAV backup & sync
- Windows auto-updater

## Quick Start

### Native App

```bash
flutter build apk        # Android
flutter build windows    # Windows
flutter build linux      # Linux
flutter build macos      # macOS
```

### Web Frontend

The Web frontend is a Vue 3 PWA served by a Node.js + Rust (Axum) server. The Node.js server hosts the PWA static files and handles API routes; the Rust sidecar (`venera-fetch`) handles image proxying and fetching.

#### Docker (Recommended)

```bash
# Build and start the full stack (Vue frontend + server + sidecar)
cd web
docker build -t venera-web .
docker run -d -p 60098:60098 \
  -v "$(pwd)/data.venera:/app/data" \
  --name venera-web \
  venera-web
```

Default access: `http://localhost:60098`

#### Manual Deployment

**Prerequisites:** Node.js 20+, Rust 1.95+

```bash
# 1. Build the Vue PWA frontend
cd web/client
npm ci
npm run build
# Output: web/client/dist/

# 2. Build the Rust fetch sidecar
cd ../../server/rust-fetch
cargo build --release
# Output: target/release/venera-fetch

# 3. Install server dependencies
cd ../../web/server
npm install --omit=dev

# 4. Run (VENERA_STATIC_DIR must point to the built frontend)
VENERA_STATIC_DIR=../client/dist \
VENERA_WEB_BIND=127.0.0.1:3000 \
VENERA_WEB_DATA_DIR=./data.venera/webpwa \
  node server.js
```

Default access: `http://localhost:3000`

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VENERA_WEB_BIND` | `127.0.0.1:3000` | Server listen address |
| `VENERA_WEB_DATA_DIR` | `./data.venera/webpwa` | Data & database directory |
| `VENERA_WEB_STATIC_DIR` | `../client/dist` | PWA static files path |
| `VENERA_FETCH_SIDECAR` | `http://127.0.0.1:9876` | Sidecar endpoint for image fetch |
| `VENERA_COOKIE_JAR_PATH` | (optional) | Cookie persistence file path |

#### Development

```bash
# Terminal 1: Start the Rust server
cd web/server
VENERA_WEB_BIND=127.0.0.1:3000 VENERA_WEB_DATA_DIR=./data.venera/webpwa VENERA_WEB_STATIC_DIR=../client/dist node server.js

# Terminal 2: Start Vite dev server (hot-reload, proxies /api to :3000)
cd web/client
npm ci && npm run dev
# Access: http://localhost:5173
```

## Build from Source

1. Clone the repository
2. Install [Flutter](https://flutter.dev/docs/get-started/install) (for native app)
3. Install [Rust](https://rustup.rs/) (for server sidecar)
4. Node.js 20+ (for Web frontend & server runtime)

## Migration

If migrating from [venera-app/venera](https://github.com/venera-app/venera), use a separate WebDAV sync directory. Back up your old data before migrating.

## Documentation

| Document | Link |
|----------|------|
| Local Comic Import | [doc/import_comic.md](doc/import_comic.md) |
| Headless Mode | [doc/headless_doc.md](doc/headless_doc.md) |

## Acknowledgments

- [EhTagTranslation](https://github.com/EhTagTranslation/Database) — Chinese tag translations
