# Venera Web Helper

`web_helper` 是 Web 端的同源后端。它负责：

- 代理 Web 端的跨域请求；
- 打开 helper browser 处理 Cloudflare 和网页登录；
- 承担 WebDAV 同步的后端流程（文件列表、下载、上传、清理）；
- 托管 Flutter Web 构建产物，让 Web 页面和 helper API 使用同一个 origin。

## 架构

容器内同时跑两个进程：

```
┌─ Container ────────────────────────────────────────────┐
│                                                        │
│   Browser → :8080  Node helper (server.js)             │
│                       │                                │
│                       │ POST /proxy                    │
│                       ↓                                │
│                    127.0.0.1:9876  venera-fetch (Rust) │
│                       │                                │
│                       ↓ reqwest + rustls               │
│                    Comic source servers                │
└────────────────────────────────────────────────────────┘
```

**为什么有 Rust sidecar**：Node 原生 `fetch()` 的 TLS 指纹（JA3/JA4）跟 app 端的 `rhttp`（用 reqwest+rustls）不一样。CopyManga 之类的源会把 cookies 绑死在签发它的 client 指纹上，从 app 同步过去的 cookies 经过 Node fetch 转发会被秒封。

`web_helper/rust-fetch/` 是一个极简 Rust 二进制，监听 `127.0.0.1:9876`，把 Node 的代理请求用 reqwest+rustls 转发到上游——TLS 握手跟 app 一致，cookies 不再被封。

`server.js` 里的 `proxyFetch` 已经改成调 sidecar，对外接口和原来完全一样。

## 一体化部署

推荐用仓库根目录的脚本生成部署包：

```powershell
.\tool\build_web_helper_bundle.ps1
```

生成目录：

```text
build/web-helper-bundle/
```

把这个目录整体拷贝到 NAS，然后在目录内启动：

```powershell
docker compose up -d --build
```

访问：

```text
http://<nas-host>:60098/
```

Web 端从这个地址打开时，会自动把同源地址作为 helper 地址，不需要再单独配置 `web_helper`。

构建第一次会编译 Rust sidecar（`rust:1.95-slim-bookworm` 阶段），约 1–2 分钟。Cargo 镜像默认用 `rsproxy.cn`，国内构建无需翻墙。如要走官方 crates.io，传 `--build-arg DISABLE_CARGO_MIRROR=1`。

## 一键登录导入（iOS）

不再依赖 iOS 快捷指令的复杂流程，新增书签栏方案：

```text
http://<helper>/login-import/<code>/bookmarklet
```

打开此页面后长按「Venera 导入」按钮，把它加到 Safari 收藏夹。在登录漫画站后点击该书签即可一键同步 cookies。

旧的快捷指令路径仍然保留：

```text
http://<helper>/login-import/<code>/shortcut
```

## Node.js 直接运行（本地开发）

需要先单独跑 Rust sidecar：

```powershell
# 终端 1
cd rust-fetch
cargo run --release

# 终端 2
$env:PORT="60098"
$env:VENERA_FETCH_SIDECAR="http://127.0.0.1:9876"
$env:VENERA_STATIC_DIR="./public"
$env:VENERA_BROWSER_DATA_DIR="./browser-data"
$env:VENERA_COOKIE_JAR_PATH="./browser-data/helper-cookies.json"
node server.js
```

`public/` 需要放 Flutter Web 构建产物。构建脚本会自动复制。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8080` | Node helper 监听端口 |
| `VENERA_FETCH_SIDECAR` | `http://127.0.0.1:9876` | Rust sidecar 端点 |
| `VENERA_FETCH_PORT` | `9876` | Sidecar 监听端口（容器内） |
| `VENERA_STATIC_DIR` | `./public` | Flutter web 静态文件目录 |
| `VENERA_BROWSER_DATA_DIR` | — | Playwright 用户数据目录 |
| `VENERA_COOKIE_JAR_PATH` | — | Cookie jar 持久化路径 |
| `VENERA_BROWSER_HEADLESS` | `true` | Playwright 是否无头 |

## WebDAV 同步接口（给 Web 前端调用）

- `POST /sync/webdav/list`
  - 入参：`{url,user,pass}`
  - 出参：`{ok,files}`
- `POST /sync/webdav/download`
  - 入参：`{url,user,pass,force,remoteFileName,lastSyncTime}`
  - 出参：`{ok,skipped,reason,remoteFileName,remoteTimestamp,dataBase64,availableFiles}`
- `POST /sync/webdav/upload`
  - 入参：`{url,user,pass,fileName,dataBase64,removeFileNames?}`
  - 出参：`{ok,fileName,files}`
- `POST /sync/webdav/cleanup`
  - 入参：`{url,user,pass,removeFileNames}`
  - 出参：`{ok,files}`

## 测试

```powershell
npm test
```

执行 helper 的 30 个集成测试。注意：测试期间 sidecar 必须跑起来（默认 `127.0.0.1:9876`），否则代理类的测试会卡住。
