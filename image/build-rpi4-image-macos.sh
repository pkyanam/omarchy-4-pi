#!/bin/bash

# Run the native aarch64 image factory inside Docker Desktop on Apple silicon.
# Source is copied through Docker's archive API to avoid slow macOS bind mounts.

set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd)"
readonly builder_image=omarchy-4-pi-builder:local

container=""

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  [[ -z $container ]] || docker rm --force "$container" >/dev/null 2>&1 || true
}

main() {
  [[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] ||
    fail "This helper requires an Apple-silicon Mac."
  command -v docker >/dev/null || fail "Install Docker Desktop first."
  docker info >/dev/null 2>&1 || fail "Start Docker Desktop, then run this command again."
  [[ $(docker info --format '{{.Architecture}}') == aarch64 ]] ||
    fail "Docker Desktop must use its native aarch64 Linux engine."

  local total_cpus build_cpus last_cpu output_dir source_branch source_commit source_dirty source_origin status
  total_cpus=$(sysctl -n hw.logicalcpu)
  build_cpus=${OMARCHY_LOCAL_CPUS:-}
  if [[ -z $build_cpus ]]; then
    if (( total_cpus > 2 )); then
      build_cpus=$((total_cpus - 2))
    else
      build_cpus=1
    fi
  fi
  [[ $build_cpus =~ ^[0-9]+$ ]] && (( build_cpus >= 1 && build_cpus <= total_cpus )) ||
    fail "OMARCHY_LOCAL_CPUS must be between 1 and $total_cpus."
  last_cpu=$((build_cpus - 1))

  output_dir=${OMARCHY_IMAGE_OUTPUT:-$repo_root/build/image}
  source_branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || printf main)
  source_commit=$(git -C "$repo_root" rev-parse HEAD)
  source_origin=$(git -C "$repo_root" remote get-url origin)
  if [[ $source_origin == git@github.com:* ]]; then
    source_origin="https://github.com/${source_origin#git@github.com:}"
  fi
  source_dirty=false
  [[ -z $(git -C "$repo_root" status --porcelain) ]] || source_dirty=true
  container="omarchy-4-pi-local-${source_commit:0:8}-$$"
  trap cleanup EXIT INT TERM

  log "Preparing the cached native ARM64 build host"
  docker build --platform linux/arm64 --tag "$builder_image" \
    --file "$script_dir/Dockerfile.builder" "$script_dir"

  log "Scheduling $build_cpus of $total_cpus cores; artifacts will land in $output_dir"
  docker create --name "$container" --privileged --platform linux/arm64 \
    --env "MAKEFLAGS=-j$build_cpus" \
    --env "CMAKE_BUILD_PARALLEL_LEVEL=$build_cpus" \
    --env "GOMAXPROCS=$build_cpus" \
    --env "RUST_BUILD_JOBS=$build_cpus" \
    --env "OMARCHY_IMAGE_OUTPUT=/output" \
    --env "OMARCHY_IMAGE_SIZE_GIB=${OMARCHY_IMAGE_SIZE_GIB:-12}" \
    --env "OMARCHY_SOURCE_BRANCH=$source_branch" \
    --env "OMARCHY_SOURCE_COMMIT=$source_commit" \
    --env "OMARCHY_SOURCE_DIRTY=$source_dirty" \
    --env "OMARCHY_SOURCE_ORIGIN=$source_origin" \
    --env "OMARCHY_XZ_PRESET=${OMARCHY_XZ_PRESET:--1}" \
    "$builder_image" taskset -c "0-$last_cpu" \
    /workspace/image/build-rpi4-image.sh "$@" >/dev/null

  git -C "$repo_root" ls-files --cached --others --exclude-standard -z |
    tar -C "$repo_root" --no-xattrs --null -T - -cf - |
    docker cp - "$container:/workspace"

  docker start "$container" >/dev/null
  docker logs --follow "$container" &
  local logs_pid=$!
  status=$(docker wait "$container")
  wait "$logs_pid" || true
  [[ $status == 0 ]] || fail "Local image build failed with status $status."

  mkdir -p "$output_dir"
  docker cp "$container:/output/." "$output_dir"
  log "Local image build complete"
}

main "$@"
