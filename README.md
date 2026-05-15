# Venera - 漫画阅读器 / Manga & Comic Reader

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/kyosee/venera)](https://github.com/kyosee/venera/blob/master/LICENSE)
[![stars](https://img.shields.io/github/stars/kyosee/venera?style=flat)](https://github.com/kyosee/venera/stargazers)
[![Download](https://img.shields.io/github/v/release/kyosee/venera)](https://github.com/kyosee/venera/releases)

Venera 是一款基于 Flutter 的漫画阅读器，支持本地阅读、网络阅读、收藏、下载、历史记录、追更、WebDAV 同步和 Headless 模式。

这是一个个人维护版本。下面只列出当前分支相对原版 `v1.6.3` 更容易感知的功能变化，不代表基础阅读能力都是最近加入的。

## 新增功能

| 功能 | 说明 |
|------|------|
| Web/PWA 自托管 | 可以在 NAS、服务器或本机 Docker 中运行网页版本 |
| 一体化 Web 后端 | `web_helper` 同源处理代理、登录辅助、Cookie、WebDAV 和图片请求 |
| Rust 网络 sidecar | `venera-fetch` 负责更稳定的后端请求转发 |
| Web 数据持久化 | Web 端历史、收藏、WebDAV 配置和备份数据可持久保存 |
| Windows 自更新 | Windows 打包产物包含 `venera_updater.exe` |

## 功能改进

| 方向 | 改进 |
|------|------|
| WebDAV 同步 | Web 端备份导入、上传、远端清理更稳，并支持更大的备份上传 |
| 阅读体验 | 支持无缝连续章节阅读，卡片显示章节进度，修复多处手势和设置布局问题 |
| 收藏、历史、追更 | 增强本地书库历史/收藏、收藏夹管理、追更任务、历史排序和任务时间显示 |
| 登录与网络兼容 | 增强 Cookie 同步、网页登录辅助和 Cloudflare 验证回退 |
| Web 界面 | 首页、搜索、详情、设置、导航和基础控件更接近桌面/移动端体验 |
| 构建维护 | 完善 Windows x64/arm64 打包流程，拆分 Native/Web 实现，补充 Web 数据和 helper 相关测试 |

## Web/PWA 快速启动

```bash
flutter build web --target lib/main_web.dart --release --base-href / --no-wasm-dry-run --no-tree-shake-icons
docker compose -f docker-compose.webpwa.yml up -d --build
```

| 项目 | 默认值 |
|------|--------|
| 访问地址 | `http://localhost:60098` |
| 浏览器数据 | IndexedDB/localStorage |
| Docker 浏览器数据卷 | `webpwa-browser-data` |
| Docker 服务端数据卷 | `webpwa-server-data` |

## 迁移提示

如果你是从 [venera-app/venera](https://github.com/venera-app/venera) 迁移过来的，请给 WebDAV 同步重新指定一个独立目录，不要继续和原项目共用同一目录。迁移前建议先备份旧同步目录和本地数据。

## Build from source

1. Clone the repository
2. Install Flutter: [flutter.dev](https://flutter.dev/docs/get-started/install)
3. Install Rust: [rustup.rs](https://rustup.rs/)
4. For Web/PWA, install Node.js 20+ and Docker Desktop
5. Build for your platform, for example:

```bash
flutter build apk
```

## 文档

| 文档 | 链接 |
|------|------|
| 本地漫画导入 | [doc/import_comic.md](doc/import_comic.md) |
| Headless Mode | [doc/headless_doc.md](doc/headless_doc.md) |

## Thanks

### Tags Translation

[EhTagTranslation](https://github.com/EhTagTranslation/Database)

The Chinese translation of the manga tags is from this project.
