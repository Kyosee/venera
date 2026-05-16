# --- Stage 1: Build the Rust fetch sidecar ---
# We compile the sidecar against glibc inside Debian (matches the Playwright
# runtime's libc) so the resulting binary runs without extra runtime deps.
FROM rust:1.95-slim-bookworm AS sidecar-builder
WORKDIR /build

ARG DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV CARGO_HTTP_TIMEOUT=120
ENV RUSTUP_TOOLCHAIN=1.95.0
ENV RUSTUP_NO_UPDATE_CHECK=1
ENV RUSTUP_DIST_SERVER=https://rsproxy.cn
ENV RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup

RUN set -eux; \
    sed -i "s|http://deb.debian.org/debian|${DEBIAN_MIRROR}|g; s|http://security.debian.org/debian-security|${DEBIAN_MIRROR}-security|g" /etc/apt/sources.list.d/debian.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Pre-cache dependencies with a stub main.rs so changes to the source don't
# bust the deps cache layer.
COPY rust-fetch/Cargo.toml rust-fetch/Cargo.lock* ./
COPY rust-fetch/.cargo /root/.cargo
RUN mkdir -p src && echo "fn main(){}" > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/venera_fetch* target/release/venera-fetch

COPY rust-fetch/src ./src
RUN cargo build --release

# --- Stage 2: Runtime ---
FROM mcr.microsoft.com/playwright:v1.59.1-noble

WORKDIR /app

ARG NPM_REGISTRY=https://registry.npmmirror.com
ENV NODE_ENV=production
ENV PORT=8080
ENV VENERA_STATIC_DIR=/app/public
ENV VENERA_BROWSER_DATA_DIR=/app/browser-data
ENV VENERA_COOKIE_JAR_PATH=/app/browser-data/helper-cookies.json
ENV VENERA_BROWSER_HEADLESS=true
ENV VENERA_FETCH_SIDECAR=http://127.0.0.1:9876

COPY package.json server.js ./
RUN npm config set registry "${NPM_REGISTRY}" && npm install --omit=dev

# Bring in the compiled sidecar binary
COPY --from=sidecar-builder /build/target/release/venera-fetch /usr/local/bin/venera-fetch
RUN chmod +x /usr/local/bin/venera-fetch

# Entrypoint runs both processes. The Node helper is the foreground process;
# if it exits, the container exits (and the sidecar dies with it).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
