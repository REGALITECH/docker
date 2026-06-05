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

## Automated upstream tracking & CVE rebuilds

Two scheduled, AI-assisted workflows keep the images current. Both pin every
third-party Action to an immutable commit SHA (with the version tag in a trailing
comment so Dependabot can still bump them) and scope the AI's tools tightly —
supply-chain hardening for the June 2026 `trivy-action` tag-hijack and
`claude-code-action` flaw.

### `track-upstream.yml` — version tracking (daily)

Runs daily (and on `workflow_dispatch`) over a matrix of `[rtpengine, asterisk]`.
Per image:

1. A **deterministic** resolver (`.github/scripts/resolve-upstream.sh`, pure
   bash/curl/jq — **no AI**) reads the committed `ARG` pin and resolves the
   newest upstream release *within the tracked major*:
   - rtpengine: GitHub tags `sipwise/rtpengine`, strict `^mr[0-9]+(\.[0-9]+)+$`
     (excludes RC/pre).
   - asterisk: GitHub releases `asterisk/asterisk`, `^23\.[0-9]+\.[0-9]+$` **and
     `prerelease == false`** (so `23.x-rc1` prereleases are excluded), then
     verifies the tarball exists at `downloads.asterisk.org`.
   The AI never invents a version number — resolution is exact and deterministic.
2. If a newer version exists, the **Claude step**
   (`anthropics/claude-code-action`, headless, `--model claude-opus-4-8`) edits
   the Dockerfile `ARG` and **adapts the recipe** (rtpengine builder/runtime apt
   lists; asterisk `menuselect`/`configure` flags + apt lists), then
   **classifies** the bump (`auto` vs `pr`).
3. Gate:
   - **`auto`** (patch / minor / CVE-fix within the major) → commits a
     `claude/bump-…` branch and triggers `publish.yml` to build + tag
     (`:<version>` + `:latest`) + push.
   - **`pr`** (major / breaking / low-confidence) → opens a PR with the diff and
     the AI risk summary. **No auto-merge, no build.**

`kamailio` (rolling `kamailio61` apt branch) and `ari-proxy` (pinned fork commit)
are **not** version-tracked here — see the rebuild workflow and the caveats below.

### `rebuild-from-pins.yml` — CVE / base-image refresh (weekly)

Runs weekly (and on `workflow_dispatch`). This is the **only** path that refreshes
`kamailio`'s rolling apt packages and base-image CVEs for **all four** images,
**without changing any pin**:

1. `docker buildx bake` builds all four locally (loaded, not pushed).
2. **Trivy** (`aquasecurity/trivy-action`, `HIGH,CRITICAL`) scans each built
   image; the SARIF is uploaded to the GitHub **code-scanning** tab.
3. A **Claude triage step** reads the Trivy JSON and decides:
   - **`push`** (clean, or all findings are fixable-by-a-future-rebuild /
     upstream-unfixed) → publishes `:latest` + a dated `:YYYYMMDD` tag.
   - **`pr`** (a finding needs a Dockerfile change) → applies the minimal edit
     and opens a triage PR. **No publish** until merged.

### What's auto-published vs PR-gated

| Change | Path |
|--------|------|
| rtpengine / asterisk patch / minor / CVE (same major) | **auto** build + tag + push |
| rtpengine / asterisk **major** (e.g. `mr26→mr27`, `23→24`) | **PR only** (review + merge) |
| Weekly rebuild, clean or rebuild-fixable CVEs | **auto** push (`:latest` + dated) |
| Weekly rebuild needing a Dockerfile fix | **PR only** |
| kamailio rolling apt updates | weekly **rebuild-only** (no version PR) |
| ari-proxy fork HEAD moved | **flag-only** issue (never auto-bump) |
| base-image `FROM` + Action-ref bumps | **Dependabot PRs** (`.github/dependabot.yml`, weekly) |

### `ANTHROPIC_API_KEY` requirement

Both AI steps need an `ANTHROPIC_API_KEY` repo (or org) **Actions secret**, passed
as `anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}`. No secret is hardcoded;
`GITHUB_TOKEN` is the auto-provided token (no PAT needed) — the workflows request
only the minimum `contents` / `packages` / `pull-requests` / `actions` /
`security-events` scopes they use.

### Caveats — `kamailio` and `ari-proxy` are rebuild-only

- **kamailio** tracks the rolling `kamailio61` (6.1 stable) apt branch — there is
  no upstream version number to bump, so there is **no version-track job**. New
  6.1 packages are picked up automatically by the weekly rebuild. The AI only
  gets involved if the build/Trivy step flags a package rename/split (as happened
  with `kamailio-nat-modules` in 6.x).
- **ari-proxy** is pinned to a specific **fork commit** of
  `daniel-sullivan/ari-proxy` that carries the load-bearing `ExternalMedia.Data`
  `replace`. It is **never auto-bumped**. The weekly rebuild refreshes its
  `golang:1.26-bookworm` / `debian:bookworm-slim` bases for CVEs; a separate
  flag-only job opens an **issue** (not a PR/bump) if the fork's default-branch
  HEAD moves, so a human can review before changing `ARI_PROXY_REF`.

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

The version pins are tracked **automatically** (see *Automated upstream tracking &
CVE rebuilds* above): `track-upstream.yml` resolves and bumps rtpengine /
asterisk, the weekly rebuild refreshes kamailio's rolling apt + all base-image
CVEs, and Dependabot bumps the `FROM` base images + the Action refs.

If you bump a pin by hand, web-search for the current upstream release first:
rtpengine (`mr26.0.1.13`), asterisk (`23.3.0`), kamailio APT branch
(`kamailio61`), `golang:1.26-bookworm`, and the GitHub Actions
(`actions/checkout`, `docker/setup-buildx-action`, `docker/login-action`,
`docker/bake-action`, `anthropics/claude-code-action`,
`aquasecurity/trivy-action`). All Action refs are pinned to immutable commit SHAs
with the tag in a trailing comment.
