#!/usr/bin/env bash
set -Eeuo pipefail

declare -A PLATFORM_MAP=(
  [x86]="linux/386"
  [x86_64]="linux/amd64"
  [arm32]="linux/arm/v7"
  [aarch64]="linux/arm64"
  [rv64]="linux/riscv64"
)

declare -A BASE_IMAGE_MAP=(
  [x86]="debian:bookworm"
  [x86_64]="ubuntu:24.04"
  [arm32]="ubuntu:24.04"
  [aarch64]="ubuntu:24.04"
  [rv64]="ubuntu:24.04"
)

ALL_ARCHES=(x86 x86_64 arm32 aarch64 rv64)

usage() {
    cat <<EOF
Usage:
  ./src/docker/docker-build-sage.sh --all
  ./src/docker/docker-build-sage.sh --arch x86_64
  ./src/docker/docker-build-sage.sh --arch x86_64,aarch64,rv64

Supported arches:
  x86 x86_64 arm32 aarch64 rv64

Notes:
  - Builds one arch at a time
  - Exports only the built binaries to output/<arch>/
  - Removes the temporary buildx builder after each arch
  - Prunes build cache after each arch
  - rv32 is not supported in this Buildx flow
EOF
}

die() {
    echo "[!] $*" >&2
    exit 1
}

info() {
    echo "[*] $*"
}

ensure_binfmt() {
    info "Installing QEMU binfmt handlers if needed"
    docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
}

build_one() {
    local arch="$1"
    local platform="${PLATFORM_MAP[$arch]}"
    local base_image="${BASE_IMAGE_MAP[$arch]}"
    local out_dir="output/$arch"
    local builder_name="sage-${arch}-builder"

    [[ -n "${platform:-}" ]] || die "Unsupported arch: $arch"
    [[ -n "${base_image:-}" ]] || die "No base image configured for: $arch"

    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    info "Creating temporary builder for $arch"
    docker buildx create \
        --name "$builder_name" \
        --driver docker-container \
        --use >/dev/null

    docker buildx inspect "$builder_name" --bootstrap >/dev/null

    info "Building SageLang for $arch ($platform) using $base_image"
    docker buildx build \
        --builder "$builder_name" \
        --platform "$platform" \
        --build-arg BASE_IMAGE="$base_image" \
        --file Dockerfile.sage \
        --output "type=local,dest=$out_dir" \
        .

    info "Output -> $out_dir"
    ls -l "$out_dir" || true

    info "Removing temporary builder for $arch"
    docker buildx rm -f "$builder_name" >/dev/null || true

    info "Pruning dangling Docker build cache"
    docker builder prune -af >/dev/null || true

    echo
}

main() {
    local -a selected=()
    local -a arches=()
    local seen=""
    local arg

    [[ $# -gt 0 ]] || { usage; exit 1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                selected=("${ALL_ARCHES[@]}")
                shift
                ;;
            --arch)
                [[ $# -ge 2 ]] || die "--arch requires a value"
                IFS=',' read -r -a tmp <<< "$2"
                selected+=("${tmp[@]}")
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            rv32)
                die "rv32 is not supported in this Buildx flow"
                ;;
            *)
                selected+=("$1")
                shift
                ;;
        esac
    done

    [[ ${#selected[@]} -gt 0 ]] || die "No architectures selected"

    for arg in "${selected[@]}"; do
        [[ -n "${PLATFORM_MAP[$arg]:-}" ]] || die "Unsupported arch: $arg"
        if [[ " $seen " != *" $arg "* ]]; then
            arches+=("$arg")
            seen="$seen $arg"
        fi
    done

    mkdir -p output
    ensure_binfmt

    for arg in "${arches[@]}"; do
        build_one "$arg"
    done

    info "Done."
}

main "$@"
