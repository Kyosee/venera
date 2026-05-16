# --- Stage 1: Build the Vue frontend ---
FROM node:22-slim AS client-builder
WORKDIR /build

ARG USE_CHINA_MIRROR=true
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      npm config set registry https://registry.npmmirror.com; \
    fi

COPY client/package.json client/package-lock.json ./
RUN npm ci

COPY client/ ./
RUN npm run build

# --- Stage 2: Build the Rust fetch sidecar ---
FROM rust:1.95-slim-bookworm AS sidecar-builder
WORKDIR /build

ARG USE_CHINA_MIRROR=true
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      sed -i 's|http://deb.debian.org/debian|https://mirrors.tuna.tsinghua.edu.cn/debian|g; s|http://security.debian.org/debian-security|https://mirrors.tuna.tsinghua.edu.cn/debian-security|g' /etc/apt/sources.list.d/debian.sources; \
    fi

ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV CARGO_HTTP_TIMEOUT=120
ENV RUSTUP_TOOLCHAIN=1.95.0
ENV RUSTUP_NO_UPDATE_CHECK=1

RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      export RUSTUP_DIST_SERVER=https://rsproxy.cn; \
      export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup; \
      mkdir -p /root/.cargo && printf '[source.crates-io]\nreplace-with = "rsproxy"\n[source.rsproxy]\nregistry = "https://rsproxy.cn/crates.io-index"\n[registries.rsproxy]\nindex = "https://rsproxy.cn/crates.io-index"\n' > /root/.cargo/config.toml; \
    fi

RUN apt-get update && \
    apt-get install -y --no-install-recommends pkg-config libssl-dev git && \
    rm -rf /var/lib/apt/lists/*

# Pre-cache dependencies with a stub main.rs so changes to the source don't
# bust the deps cache layer.
COPY server/rust-fetch/Cargo.toml server/rust-fetch/Cargo.lock* ./
RUN mkdir -p src && echo "fn main(){}" > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/venera_fetch* target/release/venera-fetch

COPY server/rust-fetch/src ./src
RUN cargo build --release

# --- Stage 3: Runtime ---
FROM mcr.microsoft.com/playwright:v1.59.1-noble

WORKDIR /app

ARG USE_CHINA_MIRROR=true
ENV NODE_ENV=production
ENV PORT=60098
ENV VENERA_STATIC_DIR=/app/public
ENV VENERA_BROWSER_DATA_DIR=/app/browser-data
ENV VENERA_COOKIE_JAR_PATH=/app/browser-data/helper-cookies.json
ENV VENERA_BROWSER_HEADLESS=true
ENV VENERA_FETCH_SIDECAR=http://127.0.0.1:9876

COPY server/package.json server/server.js ./
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      npm config set registry https://registry.npmmirror.com; \
    fi && npm install --omit=dev

# Copy pre-built frontend
COPY --from=client-builder /build/web-vue ./public/

# Bring in the compiled sidecar binary
COPY --from=sidecar-builder /build/target/release/venera-fetch /usr/local/bin/venera-fetch
RUN chmod +x /usr/local/bin/venera-fetch

# Entrypoint runs both processes. The Node helper is the foreground process;
# if it exits, the container exits (and the sidecar dies with it).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 60098
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
