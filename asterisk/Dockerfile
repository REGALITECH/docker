FROM debian:bookworm-slim AS builder

ARG ASTERISK_VERSION=23.3.0

# Built from a fork rather than the release tarball to carry patches that are
# not in an upstream release: a res_audiosocket fix (the header read loop
# retries an idle poll without bound, which starves the AudioSocket channel's
# outbound audio) and the PJSIP capture lease patches in res_pjsip_logger.
# ASTERISK_REF pins the exact commit.
# Revert to the upstream tarball once these ship in a release.
ARG ASTERISK_REPO=https://github.com/daniel-sullivan/asterisk.git
ARG ASTERISK_REF=8b5f5d6a8ce713736af0e12144eeffc86d827773

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
        --disable BUILD_NATIVE \
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
    && test -r menuselect.makeopts \
    && ! grep -q '^MENUSELECT_CFLAGS=.*BUILD_NATIVE' menuselect.makeopts \
    && make -j$(nproc) \
    && make install

# Run the capture lease fixtures from the fork against this build: a unit
# fixture compiled around res_pjsip_logger.c, and a TLS fixture that drives
# the installed module in an isolated Asterisk. A failure fails the image build.
RUN PJ=/usr/src/third-party/pjproject/source \
    && gcc -o /tmp/pjsip_capture_lease tests/fixtures/pjsip_capture_lease.c \
        -pthread -I/usr/src/include -I/usr/include/libxml2 -g -O1 \
        -ffunction-sections -fdata-sections \
        -DAST_MODULE=\"res_pjsip_logger\" \
        -DAST_MODULE_SELF_SYM=__internal_res_pjsip_logger_self \
        -DPJ_AUTOCONF=1 -DPJ_HAS_LINUX_EPOLL=1 -DPJ_IS_BIG_ENDIAN=0 -DPJ_IS_LITTLE_ENDIAN=1 \
        -DPJMEDIA_HAS_SRTP=0 \
        -I$PJ/pjlib/include -I$PJ/pjlib-util/include -I$PJ/pjnath/include \
        -I$PJ/pjmedia/include -I$PJ/pjsip/include \
        -Wl,--gc-sections -Wl,--wrap=clock_gettime \
    && /tmp/pjsip_capture_lease /tmp/pjsip_capture_lease.pcap \
    && echo "capture lease unit fixture: ok" \
    && python3 tests/fixtures/pjsip_capture_lease_tls.py \
    && rm -f /tmp/pjsip_capture_lease /tmp/pjsip_capture_lease.pcap

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
