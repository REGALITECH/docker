# RTPengine media proxy, built from sipwise/rtpengine source.
#
# No maintained, version-pinnable prebuilt rtpengine image with the
# CVE-2025-53399 fix exists: jambonz/rtpengine is stuck at 12.5.1.48 (pre-fix)
# and sipwise ships NO official Docker images. So we build the C `daemon`
# (the rtpengine binary) from a pinned upstream tag, mirroring the
# build-from-source pattern of services/asterisk/Dockerfile.
#
# CVE-2025-53399 (RTP Inject / RTP Bleed, CVSS v4.0 9.3): an origin-validation
# flaw in the endpoint-learning core lets a remote attacker inject/intercept
# RTP/SRTP. Fixed in mr13.4.1.1+ (adds the heuristic learning cap + the
# `recrypt` SRTP flag). We build mr26.0.1.13 — the latest STABLE sipwise
# release (2026-05-27), far past the fix threshold and shipping recrypt.
# Sources:
#   https://github.com/advisories/GHSA-9m93-62q8-9jmx (fix = before 13.4.1.1)
#   https://www.enablesecurity.com/blog/rtpengine-critical-security-advisory-cve-2025-53399/
#   https://github.com/sipwise/rtpengine/releases (mr26.0.1.13, 2026-05-27)
FROM debian:bookworm-slim AS builder

# mr26.0.1.13 = latest stable sipwise/rtpengine release (2026-05-27);
# CVE-2025-53399 fixed (>= mr13.4.1.1, recrypt present).
ARG RTPENGINE_VERSION=mr26.0.1.13

# Build-deps for the daemon. Derived from upstream debian/control Build-Depends,
# trimmed to what the `daemon/` build actually links (no Perl test/DKMS/doc
# tooling, no kernel-module path — we run userspace-only, see the --interface
# flags in telephony_rtpengine.tf). ffmpeg (libav*/libswresample), glib +
# json-glib, libcrypto/ssl, pcre2, hiredis, curl, websockets, mosquitto (MQTT),
# opus, spandsp, libevent, ncurses, iptc/xtables (netfilter ng), io_uring,
# zlib, systemd, cjson, libjwt.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    pkg-config \
    gperf \
    pandoc \
    default-libmysqlclient-dev \
    libavcodec-dev \
    libavfilter-dev \
    libavformat-dev \
    libavutil-dev \
    libswresample-dev \
    libbcg729-dev \
    libcjson-dev \
    libcurl4-openssl-dev \
    libevent-dev \
    libglib2.0-dev \
    libhiredis-dev \
    libiptc-dev \
    libjson-glib-dev \
    libjwt-dev \
    libmosquitto-dev \
    libncurses-dev \
    libopus-dev \
    libpcap0.8-dev \
    libpcre2-dev \
    libspandsp-dev \
    libssl-dev \
    libsystemd-dev \
    liburing-dev \
    libwebsockets-dev \
    libxtables-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# Shallow-clone just the pinned tag (the repo is large; no history needed).
RUN git clone --depth 1 --branch "${RTPENGINE_VERSION}" \
        https://github.com/sipwise/rtpengine.git . \
    && make -C daemon -j"$(nproc)"

# --- runtime ---
FROM debian:bookworm-slim

# Only the shared libs the daemon links at runtime (the -dev counterparts of
# the build-deps above). No build toolchain, no kernel-module bits.
#
# curl + ca-certificates are also required at runtime by the telephony
# DaemonSet's `discover-addr` initContainer, which reuses THIS image to query
# EC2 IMDSv2 (http://169.254.169.254) over HTTPS-capable curl for the node's
# EIP/private IP (see telephony_rtpengine.tf). Without curl that init exits 127.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libavcodec59 \
    libavfilter8 \
    libavformat59 \
    libavutil57 \
    libswresample4 \
    libbcg729-0 \
    libcjson1 \
    libcurl4 \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libglib2.0-0 \
    libhiredis0.14 \
    libip4tc2 \
    libip6tc2 \
    libmariadb3 \
    libjson-glib-1.0-0 \
    libjwt0 \
    libmosquitto1 \
    libncurses6 \
    libopus0 \
    libpcap0.8 \
    libpcre2-8-0 \
    libspandsp2 \
    libssl3 \
    liburing2 \
    libwebsockets17 \
    libxtables12 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/daemon/rtpengine /usr/local/bin/rtpengine

# Media (RTP/SRTP) UDP range + the ng control protocol (Kamailio drives
# rtpengine over 127.0.0.1:22222 in the telephony DaemonSet). The full
# command/args (interfaces, port range, --endpoint-learning) are supplied at
# runtime by etla_infra_tf's telephony_rtpengine.tf DaemonSet.
EXPOSE 10000-20000/udp
EXPOSE 22222/udp

ENTRYPOINT ["/usr/local/bin/rtpengine"]
CMD ["--help"]
