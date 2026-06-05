# REGALITECH/docker

Public OSS telephony infrastructure images for the **etla** platform (telephony +
AI-voice), published to GitHub Container Registry (GHCR).

Each top-level directory builds exactly one **fully self-contained** image from
public upstreams. None of these images do any `COPY`/`ADD` from the build context
(beyond multi-stage `--from=builder`), none use private Go modules / `GOPRIVATE`,
and none reference repo-local files or secrets — so every image is publicly
buildable with no authentication.

## Images

| Image | Upstream source | Pin | Notes |
|-------|-----------------|-----|-------|
| `rtpengine` | [sipwise/rtpengine](https://github.com/sipwise/rtpengine) (built from source) | `mr26.0.1.13` | Latest stable; CVE-2025-53399 fixed (recrypt present). Builds the userspace `daemon/` only. |
| `kamailio`  | [deb.kamailio.org](https://deb.kamailio.org) APT repo | `kamailio61` (6.1 stable) | Installs `kamailio` + `tls`/`extra`/`utils` modules + `gawk`. |
| `asterisk`  | [downloads.asterisk.org](https://downloads.asterisk.org) tarball | `23.3.0` | menuselect enables `res_ari*`, `res_stasis*`, `res_config_pgsql`, `cdr_pgsql`, `app/chan_audiosocket`. |
| `ari-proxy` | [daniel-sullivan/ari-proxy](https://github.com/daniel-sullivan/ari-proxy) fork (built from source) | `ccc0bb66` | Public fork of CyCoreSystems ari-proxy + a go.mod `replace` carrying `ExternalMedia.Data` (the AudioSocket UUID). |

The `ari-proxy` fork resolves entirely from public repos: its `go.mod` `replace`
points `github.com/CyCoreSystems/ari/v5` at the public `daniel-sullivan/ari/v5`,
and its `go.sum` already holds the checksum, so `CGO_ENABLED=0 go build` resolves
with no `GOPRIVATE` / token.

## Build locally

Requires Docker with Buildx.

```bash
docker buildx bake                      # build all four images, tagged :latest
docker buildx bake rtpengine            # build a single image
TAG=v1 docker buildx bake               # build all with a custom tag
REGISTRY=ghcr.io/myorg/docker docker buildx bake   # override the registry path
```

Defaults (see `docker-bake.hcl`):

- `REGISTRY` = `ghcr.io/regalitech/docker` (lowercase — GHCR requires a lowercase
  repository path even though the GitHub org is `REGALITECH`)
- `TAG` = `latest`
- `PLATFORMS` = `linux/amd64` (the EKS telephony nodes are amd64; add
  `linux/arm64` via `PLATFORMS=linux/amd64,linux/arm64` if a build host needs it)

## Publishing (CI)

`.github/workflows/publish.yml` runs on pushes to `main`, on pushed tags, and via
manual `workflow_dispatch`. It logs in to GHCR with the workflow's
`GITHUB_TOKEN` and runs `docker buildx bake` with `push: true`, tagging each image
both `:<git-sha>` (or the dispatch tag) and `:latest`:

```
ghcr.io/regalitech/docker/rtpengine:<sha>   + :latest
ghcr.io/regalitech/docker/kamailio:<sha>    + :latest
ghcr.io/regalitech/docker/asterisk:<sha>    + :latest
ghcr.io/regalitech/docker/ari-proxy:<sha>   + :latest
```

> **One-time admin step — make the packages public.** GHCR packages are created
> *private* by default. After the first successful publish, an org/repo admin must
> flip each package's visibility to **Public** (package -> Package settings ->
> Change visibility), or set the org default package visibility to Public.
> The workflow itself cannot change package visibility.

## Consuming the images

The etla infra (`etla_infra_tf` telephony module: `telephony_rtpengine.tf`,
`telephony_kamailio.tf`, `telephony_asterisk.tf`) references these images by their
GHCR refs once the packages are public:

```
ghcr.io/regalitech/docker/rtpengine:latest
ghcr.io/regalitech/docker/kamailio:latest
ghcr.io/regalitech/docker/asterisk:latest
ghcr.io/regalitech/docker/ari-proxy:latest
```

Pin to an immutable `:<git-sha>` tag in production rather than `:latest`.

## Version pins

Before bumping any pin, web-search for the current upstream release: rtpengine
(`mr26.0.1.13`), asterisk (`23.3.0`), kamailio APT branch (`kamailio61`),
`golang:1.26-bookworm`, and the GitHub Actions (`actions/checkout`,
`docker/setup-buildx-action`, `docker/login-action`, `docker/bake-action`).
