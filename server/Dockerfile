# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build the Linux AOT relay binary. The Windows relay (server/build/*.exe) is
# built separately with `dart compile exe` and is not used in this image.
# ---------------------------------------------------------------------------
FROM dart:3.5.4 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY bin ./bin
RUN mkdir -p /out && dart compile exe bin/server.dart -o /out/orbitlink-relay

# ---------------------------------------------------------------------------
# Minimal runtime image. The relay is stateless and writes no files.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

LABEL org.opencontainers.image.title="OrbitLink Relay" \
      org.opencontainers.image.description="Signaling and relay server for OrbitLink remote control" \
      org.opencontainers.image.version="1.0.0"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home-dir /app --shell /usr/sbin/nologin relay \
    && mkdir -p /app \
    && chown relay:relay /app

WORKDIR /app
COPY --from=build --chown=relay:relay /out/orbitlink-relay /usr/local/bin/orbitlink-relay

USER relay
ENV PORT=7080 \
    BIND=0.0.0.0
EXPOSE 7080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/orbitlink-relay"]
