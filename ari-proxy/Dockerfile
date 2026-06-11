# ari-proxy ARI<->NATS bridge, built from the daniel-sullivan/ari-proxy FORK.
#
# WHY a source build (mirroring services/rtpengine/Dockerfile's source-build
# pattern): the deployed sidecar mirror/ari-proxy:v5.3.1 is built against
# upstream github.com/CyCoreSystems/ari/v5 v5.3.1, whose `ExternalMedia`
# struct has NO `Data` field — so the proxy silently DROPS the ExternalMedia
# `data` parameter (the AudioSocket UUID) the manager sends. The fork
# daniel-sullivan/ari carries that `Data` field; daniel-sullivan/ari-proxy is
# upstream ari-proxy v5.3.1 + a single go.mod `replace` pointing ari/v5 at the
# fork. NO ari-proxy code change — just recompiling against the fork's struct
# fixes the dropped field. See the fork go.mod replace:
#   replace github.com/CyCoreSystems/ari/v5 =>
#     github.com/daniel-sullivan/ari/v5 v5.3.2-0.20260312051653-3faec98e5b75
#
# Published to the shared ECR as streaming/ari-proxy (account 312831649310) by
# etla_streaming's build-docker.yml, exactly like streaming/rtpengine.
FROM golang:1.26-bookworm AS builder

# Pin the fork ref for a reproducible build: daniel-sullivan/ari-proxy at the
# event-plane-selfheal commit, which sits on top of the externalmedia-data
# commit (so it keeps the go.mod replace ari/v5 -> daniel-sullivan/ari carrying
# ExternalMedia.Data). Adds an event-socket watchdog that self-restarts the
# sidecar when Asterisk's event websocket half-dies (was a manual bounce), plus
# the dialog cleaner.
ARG ARI_PROXY_REF=f8d0df8413bcaaadf40ce3a49e1ec322c18e0c64

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# Shallow-clone the fork at the pinned ref. The fork's go.mod carries the
# `replace` directive (ari/v5 -> daniel-sullivan/ari/v5) AND go.sum already
# holds the fork's checksum (the user runs `go mod tidy` before committing),
# so the build resolves the fork's ExternalMedia struct with no extra flags.
# The fork is a PUBLIC repo, so no GOPRIVATE / GitHub-App token is needed.
RUN git clone https://github.com/daniel-sullivan/ari-proxy.git . \
    && git checkout "${ARI_PROXY_REF}"

# The ari-proxy main package is the MODULE ROOT (package main: main.go +
# cmd.go, NOT a cmd/ari-proxy subdir). Build a static-ish linux binary; the
# proxy is a pure NATS<->ARI(HTTP/WS over 127.0.0.1:8088) bridge with no cgo.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /usr/local/bin/ari-proxy .

# --- runtime ---
FROM debian:bookworm-slim

# Only ca-certificates: ari-proxy dials NATS over DNS and the pod-local ARI
# HTTP/WS endpoint on 127.0.0.1:8088 — no IMDS/curl path (unlike rtpengine,
# whose image is reused by an IMDS-querying initContainer). The upstream
# ari-proxy Dockerfile likewise installs only ca-certificates.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/ari-proxy /usr/local/bin/ari-proxy

# The sidecar is invoked with `--config /etc/ari-proxy/ari-proxy.yaml` by the
# Asterisk StatefulSet (etla_infra_tf telephony_asterisk.tf). v5.3.1's RootCmd
# runs the server directly (no "server" subcommand); the ENTRYPOINT is the
# binary so the manifest's args are its flags.
ENTRYPOINT ["/usr/local/bin/ari-proxy"]
CMD ["--help"]
