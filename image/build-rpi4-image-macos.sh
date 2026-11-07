#!/bin/bash

# Run the native aarch64 image factory inside a bounded Docker/OrbStack container.
# Source is copied through Docker's archive API to avoid slow macOS bind mounts.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
repo_root="$(cd -- "$script_dir/.." && pwd)"
readonly repo_root
readonly builder_image=omarchy-4-pi-builder:local

container=""
transfer_dir=""
workspace_volume=""
keep_work=0

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: image/build-rpi4-image-macos.sh [--minimal|--full] [--keep-work]

Build a Raspberry Pi Imager-compatible image on an Apple-silicon Mac using
Docker/OrbStack's native ARM64 engine. Defaults leave VM memory headroom,
use at most two workers, and keep all staging on disk. The helper does not
change global VM resource settings.

Environment:
  OMARCHY_LOCAL_CPUS      Build cores (default: min(2, VM cores))
  OMARCHY_LOCAL_MEMORY_MIB  Container RAM (default: VM RAM minus 512MiB, max 4096)
  OMARCHY_XZ_THREADS      Compression workers (default: 1)
  OMARCHY_XZ_MEMORY_MIB   Compression RAM in MiB (default: 512)
  OMARCHY_IMAGE_OUTPUT    Artifact directory (default: build/image)
  OMARCHY_IMAGE_SIZE_GIB  Uncompressed image size (default: 12)
  OMARCHY_XZ_PRESET       xz preset (default: -1)
EOF
}

cleanup() {
  [[ -z $container ]] || docker rm --force "$container" >/dev/null 2>&1 || true
  if [[ -n $workspace_volume ]]; then
    if (( keep_work )); then
      log "Kept private disk workspace volume $workspace_volume"
    else
      docker volume rm "$workspace_volume" >/dev/null 2>&1 || true
    fi
  fi
  [[ -z $transfer_dir ]] || rm -rf -- "$transfer_dir"
}

prepare_source_transfer() {
  local source_repository=$1 source_commit=$2 tracking_commit=$3
  # Transfer the exact local commit even when this branch is unpublished.
  # Advertise private local refs: FETCH_HEAD alone is not a fetchable branch.
  transfer_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/omarchy-source.XXXXXXXX")
  git init --quiet --bare "$transfer_dir/source-git"
  git -C "$transfer_dir/source-git" fetch --quiet --depth 1 "$source_repository" "$source_commit"
  git -C "$transfer_dir/source-git" update-ref refs/heads/image-source "$source_commit"
  if [[ -n $tracking_commit && $tracking_commit != "$source_commit" ]]; then
    git -C "$transfer_dir/source-git" fetch --quiet --depth 1 "$source_repository" "$tracking_commit"
    git -C "$transfer_dir/source-git" update-ref refs/heads/image-tracking "$tracking_commit"
  fi
}

main() {
  if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    usage
    exit 0
  fi
  local argument
  for argument in "$@"; do
    case $argument in
      --minimal|--full) ;;
      --keep-work) keep_work=1 ;;
      *) fail "Unknown option: $argument" ;;
    esac
  done

  [[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] ||
    fail "This helper requires an Apple-silicon Mac."
  command -v docker >/dev/null || fail "Install Docker Desktop or OrbStack first."
  command -v python3 >/dev/null || fail "python3 is required to verify the copied image catalogs."
  docker info >/dev/null 2>&1 || fail "Start the selected Docker engine, then run this command again."
  [[ $(docker info --format '{{.Architecture}}') == aarch64 ]] ||
    fail "The selected Docker engine must be native aarch64."

  local total_cpus vm_cpus vm_memory_mib build_cpus build_memory_mib last_cpu image_size_gib
  local output_dir source_branch source_commit source_dirty source_origin tracking_commit status free_kib minimum_gib
  total_cpus=$(sysctl -n hw.logicalcpu)
  vm_cpus=$(docker info --format '{{.NCPU}}')
  vm_memory_mib=$(( $(docker info --format '{{.MemTotal}}') / 1048576 ))
  build_cpus=${OMARCHY_LOCAL_CPUS:-$((vm_cpus < 2 ? vm_cpus : 2))}
  [[ $build_cpus =~ ^[1-9][0-9]*$ ]] && (( build_cpus <= vm_cpus && build_cpus <= total_cpus )) ||
    fail "OMARCHY_LOCAL_CPUS must fit the VM's $vm_cpus CPUs and host's $total_cpus CPUs."
  build_memory_mib=${OMARCHY_LOCAL_MEMORY_MIB:-$((vm_memory_mib > 4608 ? 4096 : vm_memory_mib - 512))}
  [[ $build_memory_mib =~ ^[1-9][0-9]*$ ]] && (( build_memory_mib >= 1024 && build_memory_mib <= vm_memory_mib - 512 )) ||
    fail "Container RAM must be at least 1024MiB and leave at least 512MiB of VM headroom."
  last_cpu=$((build_cpus - 1))
  image_size_gib=${OMARCHY_IMAGE_SIZE_GIB:-12}
  [[ $image_size_gib =~ ^[0-9]+$ ]] && (( image_size_gib >= 12 )) || fail "Image size must be at least 12 GiB."
  minimum_gib=$((2 * image_size_gib + 12))
  output_dir=${OMARCHY_IMAGE_OUTPUT:-$repo_root/build/image}
  mkdir -p "$output_dir"
  free_kib=$(df -Pk "$output_dir" | awk 'END {print $4}')
  (( free_kib >= minimum_gib * 1024 * 1024 )) || fail "Host output/storage needs at least $minimum_gib GiB free."
  [[ -z $(git -C "$repo_root" ls-files --unmerged) ]] || fail "Resolve source merge conflicts before assembly."
  source_branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || printf detached)
  source_commit=$(git -C "$repo_root" rev-parse HEAD)
  git -C "$repo_root" merge-base --is-ancestor ac2690cd7be4f47e4a255f5e2e78d904d436b068 "$source_commit" ||
    fail "Source must contain the exact released Omarchy 4.5.0 commit."
  source_origin=$(git -C "$repo_root" remote get-url origin)
  if [[ $source_origin == git@github.com:* ]]; then
    source_origin="https://github.com/${source_origin#git@github.com:}"
  fi
  tracking_commit=$(git -C "$repo_root" rev-parse --verify "refs/remotes/origin/$source_branch" 2>/dev/null || true)
  source_dirty=false
  [[ -z $(git -C "$repo_root" status --porcelain) ]] || source_dirty=true
  container="omarchy-4-pi-local-${source_commit:0:8}-$$"
  workspace_volume="$container-work"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  prepare_source_transfer "$repo_root" "$source_commit" "$tracking_commit"

  log "Preparing the cached native ARM64 build host"
  docker build --platform linux/arm64 --tag "$builder_image" \
    --file "$script_dir/Dockerfile.builder" "$script_dir"

  log "Scheduling $build_cpus of $vm_cpus VM CPUs and ${build_memory_mib}MiB RAM; artifacts: $output_dir"
  docker create --name "$container" --privileged --platform linux/arm64 \
    --mount "type=volume,source=$workspace_volume,target=/var/tmp/omarchy-images" \
    --cpus "$build_cpus" --cpuset-cpus "0-$last_cpu" \
    --memory "${build_memory_mib}m" --memory-swap "${build_memory_mib}m" \
    --env "MAKEFLAGS=-j$build_cpus" \
    --env "CMAKE_BUILD_PARALLEL_LEVEL=$build_cpus" \
    --env "GOMAXPROCS=$build_cpus" \
    --env "CARGO_BUILD_JOBS=$build_cpus" \
    --env "OMARCHY_IMAGE_JOBS=$build_cpus" \
    --env "OMARCHY_XZ_THREADS=${OMARCHY_XZ_THREADS:-1}" \
    --env "OMARCHY_XZ_MEMORY_MIB=${OMARCHY_XZ_MEMORY_MIB:-512}" \
    --env "OMARCHY_IMAGE_OUTPUT=/output" \
    --env "OMARCHY_IMAGE_SIZE_GIB=${OMARCHY_IMAGE_SIZE_GIB:-12}" \
    --env "OMARCHY_SOURCE_REPOSITORY=/source-git" \
    --env "OMARCHY_SOURCE_UPSTREAM_COMMIT=ac2690cd7be4f47e4a255f5e2e78d904d436b068" \
    --env "OMARCHY_SOURCE_TRACKING_COMMIT=$tracking_commit" \
    --env "OMARCHY_SOURCE_BRANCH=$source_branch" \
    --env "OMARCHY_SOURCE_COMMIT=$source_commit" \
    --env "OMARCHY_SOURCE_DIRTY=$source_dirty" \
    --env "OMARCHY_SOURCE_ORIGIN=$source_origin" \
    --env "OMARCHY_XZ_PRESET=${OMARCHY_XZ_PRESET:--1}" \
    "$builder_image" /bin/bash -euc '
      # Archive transfer can preserve the Mac UID on the private Git store.
      # Make this container-owned copy safe for root Git without trust bypasses.
      chown -R root:root /source-git
      exec "$@"
    ' bash /workspace/image/build-rpi4-image.sh "$@" >/dev/null

  docker cp "$transfer_dir/source-git/." "$container:/source-git"
  git -C "$repo_root" ls-files --cached --others --exclude-standard -z |
    COPYFILE_DISABLE=1 tar -C "$repo_root" --no-xattrs --null -T - -cf - |
    docker cp - "$container:/workspace"

  docker start "$container" >/dev/null
  docker logs --follow "$container" &
  local logs_pid=$!
  status=$(docker wait "$container")
  wait "$logs_pid" || true
  [[ $status == 0 ]] || fail "Local image build failed with status $status."

  mkdir -p "$output_dir"
  docker cp "$container:/output/." "$output_dir"
  python3 "$script_dir/relocate-imager-catalogs.py" "$output_dir"
  log "Local image build complete"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
