# Kamailio SIP edge proxy, built from the official Kamailio APT repo.
# No maintained, version-pinnable prebuilt Kamailio image exists (Docker Hub
# kamailio/kamailio is gone; kamailio-ci version tags stop at 5.5.2), so we
# build a thin image pinned to the 6.1 stable branch with the modules the
# telephony stack's kamailio.cfg loads (tls, dispatcher, rtpengine, nathelper,
# pike, permissions, ...).
FROM debian:bookworm-slim

# kamailio61 = Kamailio 6.1 stable branch (deb.kamailio.org).
ARG KAMAILIO_REPO=kamailio61

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL https://deb.kamailio.org/kamailiodebkey.gpg | gpg --dearmor -o /usr/share/keyrings/kamailio.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/kamailio.gpg] http://deb.kamailio.org/${KAMAILIO_REPO} bookworm main" \
      > /etc/apt/sources.list.d/kamailio.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      kamailio \
      kamailio-tls-modules \
      kamailio-extra-modules \
      kamailio-utils-modules \
      gawk \
 && rm -rf /var/lib/apt/lists/*

# Module->package mapping (Kamailio 6.1, deb.kamailio.org/kamailio61 bookworm):
# In 6.1 the old kamailio-nat-modules package is gone; dispatcher, rtpengine,
# nathelper, pike and permissions all ship in the core `kamailio` package.
# Only tls (crypto/tls/tlsa) lives in kamailio-tls-modules. extra/utils-modules
# back additional helper modules the rendered config may load.

# curl: IMDS lookup in the render initContainer. gawk/md5sum/getent: the
# dispatcher-resync + TLS-reload helper sidecar. kamcmd ships with kamailio.

# SIP signaling (udp/tcp) + TLS. Media is handled by RTPengine, not Kamailio.
EXPOSE 5060/udp 5060/tcp 5061/tcp

# Config is rendered from a ConfigMap into /etc/kamailio by the init
# container at runtime; the DaemonSet supplies the full command/args.
CMD ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
