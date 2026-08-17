FROM debian:bookworm-slim AS builder

ARG ASTERISK_VERSION=23.3.0

# Built from a fork rather than the release tarball to carry a fix to
# res_audiosocket that is not yet in an upstream release: the header read
# loop retries an idle poll without bound, which starves the AudioSocket
# channel's outbound audio. ASTERISK_REF pins the exact commit.
# Revert to the upstream tarball once the fix ships in a release.
ARG ASTERISK_REPO=https://github.com/daniel-sullivan/asterisk.git
ARG ASTERISK_REF=f801c5fa11e6d26fb92c499885fcce09e17bf80a

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libedit-dev \
    libjansson-dev \
    libsqlite3-dev \
    libxml2-dev \
    libxslt1-dev \
    libncurses5-dev \
    libssl-dev \
    libsrtp2-dev \
    uuid-dev \
    libpq-dev \
    pkg-config \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

RUN git init -q . \
    && git remote add origin "${ASTERISK_REPO}" \
    && git fetch -q --depth 1 origin "${ASTERISK_REF}" \
    && git checkout -q FETCH_HEAD \
    && git --no-pager log -1 --format='building asterisk from %H%n%s'

RUN ./configure --with-jansson-bundled=no \
    && make menuselect.makeopts \
    && menuselect/menuselect \
        --enable res_ari \
        --enable res_ari_applications \
        --enable res_ari_asterisk \
        --enable res_ari_bridges \
        --enable res_ari_channels \
        --enable res_ari_device_states \
        --enable res_ari_endpoints \
        --enable res_ari_events \
        --enable res_ari_mailboxes \
        --enable res_ari_model \
        --enable res_ari_playbacks \
        --enable res_ari_recordings \
        --enable res_ari_sounds \
        --enable res_http_websocket \
        --enable res_stasis \
        --enable res_stasis_answer \
        --enable res_stasis_device_state \
        --enable res_stasis_playback \
        --enable res_stasis_recording \
        --enable res_stasis_snoop \
        --enable res_config_pgsql \
        --enable cdr_pgsql \
        --enable app_audiosocket \
        --enable chan_audiosocket \
        menuselect.makeopts \
    && make -j$(nproc) \
    && make install

# --- runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libedit2 \
    libjansson4 \
    libsqlite3-0 \
    libxml2 \
    libxslt1.1 \
    libncurses6 \
    libssl3 \
    libsrtp2-1 \
    libuuid1 \
    libpq5 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/libasterisk* /usr/lib/
COPY --from=builder /usr/lib/asterisk/    /usr/lib/asterisk/
COPY --from=builder /usr/sbin/asterisk    /usr/sbin/asterisk
COPY --from=builder /var/lib/asterisk/    /var/lib/asterisk/
COPY --from=builder /var/spool/asterisk/  /var/spool/asterisk/

RUN mkdir -p /var/log/asterisk /var/run/asterisk /etc/asterisk

# Config is mounted at runtime: -v ./config:/etc/asterisk
VOLUME /etc/asterisk

# SIP/PJSIP, RTP range, HTTP/ARI
EXPOSE 5060/udp 5060/tcp 5061/tcp
EXPOSE 10000-20000/udp
EXPOSE 8088/tcp

CMD ["asterisk", "-vvvf"]
