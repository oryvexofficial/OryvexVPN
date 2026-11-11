# The latest stable Rust, on Debian 12 (bookworm) like the image the binary runs in.
FROM rust:bookworm AS builder

ARG GO_VERSION=1.22.12

RUN apt-get update && \
    apt-get install -y \
    clang \
    cmake \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /usr/src/app

# The core and everything it builds from (vendor/quiche, scripts/) live in oryvexcore/.
COPY oryvexcore ./oryvexcore

WORKDIR /usr/src/app/oryvexcore

RUN bash scripts/pt-build.sh linux "$(dpkg --print-architecture)" /usr/src/app/oryvexcore/pt
RUN bash scripts/psiphon-build.sh linux "$(dpkg --print-architecture)" /usr/src/app/oryvexcore/pt

# Tor with exit-country selection, falling back on plain Tor if that feature does not build.
RUN bash scripts/build-core.sh cargo build --release

FROM gcr.io/distroless/cc-debian12

WORKDIR /app

COPY --from=builder /usr/src/app/oryvexcore/target/release/oryvexcore /usr/local/bin/oryvexcore
COPY --from=builder /usr/src/app/oryvexcore/pt /usr/local/bin/pt

ENV ORYVEXCORE_SOCKS=0.0.0.0:1819
ENV ORYVEXCORE_CONFIG=/data/oryvexcore.toml

VOLUME ["/data"]

EXPOSE 1819

ENTRYPOINT ["oryvexcore"]
