# docker-bake.hcl — buildx bake definition for the REGALITECH telephony images.
#
# Each target builds one fully self-contained OSS telephony image from public
# upstreams (no private Go modules, no build-context COPY beyond multi-stage
# --from=builder, no secrets). Images publish to GHCR under
# ghcr.io/regalitech/docker/<image>.
#
# Local usage:
#   docker buildx bake                 # build all four, :latest
#   docker buildx bake rtpengine       # build one image
#   TAG=v1 docker buildx bake          # custom tag
#   REGISTRY=ghcr.io/myorg/docker docker buildx bake   # override registry path
#
# GHCR requires a lowercase repository path, so the default REGISTRY uses the
# lowercase "regalitech" even though the GitHub org is "REGALITECH".

variable "REGISTRY" {
  default = "ghcr.io/regalitech/docker"
}

variable "TAG" {
  default = "latest"
}

# linux/amd64 only: the EKS telephony nodes are amd64 and rtpengine/asterisk are
# heavy source builds. Add linux/arm64 here later if a build host needs it.
variable "PLATFORMS" {
  default = "linux/amd64"
}

group "default" {
  targets = ["rtpengine", "kamailio", "asterisk", "ari-proxy"]
}

target "rtpengine" {
  context    = "rtpengine"
  dockerfile = "Dockerfile"
  tags = [
    "${REGISTRY}/rtpengine:${TAG}",
    "${REGISTRY}/rtpengine:latest",
  ]
  platforms = split(",", PLATFORMS)
}

target "kamailio" {
  context    = "kamailio"
  dockerfile = "Dockerfile"
  tags = [
    "${REGISTRY}/kamailio:${TAG}",
    "${REGISTRY}/kamailio:latest",
  ]
  platforms = split(",", PLATFORMS)
}

target "asterisk" {
  context    = "asterisk"
  dockerfile = "Dockerfile"
  tags = [
    "${REGISTRY}/asterisk:${TAG}",
    "${REGISTRY}/asterisk:latest",
  ]
  platforms = split(",", PLATFORMS)
}

target "ari-proxy" {
  context    = "ari-proxy"
  dockerfile = "Dockerfile"
  tags = [
    "${REGISTRY}/ari-proxy:${TAG}",
    "${REGISTRY}/ari-proxy:latest",
  ]
  platforms = split(",", PLATFORMS)
}
