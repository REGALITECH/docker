#!/usr/bin/env bash
# Verify that the Asterisk image was built from source carrying the
# res_audiosocket idle-poll bound, and that the AudioSocket modules were
# produced. The bound is a compile-time constant with no runtime symbol or
# string, so it is checked in the builder stage's source tree rather than in
# the compiled module.
#
# Run this after any change to ASTERISK_REF, ASTERISK_REPO or ASTERISK_VERSION.
# It fails closed: if the pinned revision no longer carries the fix, the check
# fails instead of silently shipping an unpatched Asterisk.
set -euo pipefail

service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="${ASTERISK_IMAGE:-regalitech-asterisk:audiosocket-bound-check}"
builder_image="${image}-builder"
platform="${PLATFORM:-}"

build_args=()
run_args=(--rm)
if [[ -n "$platform" ]]; then
    build_args=(--platform "$platform")
    run_args=(--platform "$platform" "${run_args[@]}")
fi

docker build "${build_args[@]}" --target builder --tag "$builder_image" "$service_dir"
docker build "${build_args[@]}" --tag "$image" "$service_dir"

# The guard must bound retries only while no header byte has been consumed;
# a bound applied at any read position would desynchronize the frame stream.
docker run "${run_args[@]}" --entrypoint sh "$builder_image" -ec '
    grep -Fq "#define IDLE_POLL_MAX" /usr/src/res/res_audiosocket.c
    grep -Fq "if (i == 0 && ++idle_polls > IDLE_POLL_MAX) {" /usr/src/res/res_audiosocket.c
'

echo -n "built from: "
docker run "${run_args[@]}" --entrypoint sh "$builder_image" -ec \
    'cd /usr/src && git --no-pager log -1 --format="%H %s"'

docker run "${run_args[@]}" --entrypoint sh "$image" -ec '
    test -f /usr/lib/asterisk/modules/res_audiosocket.so
    test -f /usr/lib/asterisk/modules/chan_audiosocket.so
'

echo "ok: idle-poll bound present in built source, AudioSocket modules produced"
