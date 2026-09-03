#!/bin/bash

# Assemble a flashable Omarchy 4 Pi disk image from the signed Arch Linux ARM
# Raspberry Pi aarch64 root filesystem. Run on an aarch64 Linux host as root.

set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd)"
readonly rootfs_name=ArchLinuxARM-rpi-aarch64-latest.tar.gz
readonly rootfs_url="${OMARCHY_ROOTFS_URL:-http://os.archlinuxarm.org/os/$rootfs_name}"
readonly keyring_url="${OMARCHY_ALARM_KEYRING_URL:-https://raw.githubusercontent.com/archlinuxarm/archlinuxarm-keyring/master/archlinuxarm.gpg}"
readonly build_key=68B3537F39A313B3E574D06777193F152BDBE6A6
readonly image_size_gib="${OMARCHY_IMAGE_SIZE_GIB:-12}"
readonly output_dir="${OMARCHY_IMAGE_OUTPUT:-$repo_root/build/image}"

install_mode=minimal
work_dir=""
loop_device=""
root_mount=""
image_path=""
keep_work=0

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: sudo image/build-rpi4-image.sh [--minimal|--full] [--keep-work]

Builds a Raspberry Pi Imager-compatible .img.xz plus checksums and manifests.
The default minimal image contains the full Quattro desktop but omits optional
locally compiled applications. --full adds those applications and takes much
longer to build.

Environment:
  OMARCHY_IMAGE_SIZE_GIB  Uncompressed image size (default: 12)
  OMARCHY_IMAGE_OUTPUT    Artifact directory (default: build/image)
  OMARCHY_IMAGE_WORK      Reusable work directory (default: a temporary dir)
  OMARCHY_ROOTFS_URL      Override the Arch Linux ARM root filesystem URL
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --minimal)
        install_mode=minimal
        shift
        ;;
      --full)
        install_mode=full
        shift
        ;;
      --keep-work)
        keep_work=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

require_host() {
  (( EUID == 0 )) || fail "Run the image builder as root (it mounts loop devices)."
  [[ $(uname -s) == Linux ]] || fail "The image builder requires Linux with loop-device support."
  [[ $(uname -m) == aarch64 ]] || fail "Use an aarch64 Linux host; GitHub Actions provides ubuntu-24.04-arm."
  [[ $image_size_gib =~ ^[0-9]+$ ]] && (( image_size_gib >= 10 )) ||
    fail "OMARCHY_IMAGE_SIZE_GIB must be an integer of at least 10."

  local command
  for command in blockdev bsdtar chroot curl gpg losetup mount mountpoint mkfs.ext4 mkfs.vfat parted rsync sha256sum udevadm umount xz; do
    command -v "$command" >/dev/null || fail "Missing host command: $command"
  done
}

cleanup() {
  set +e
  if [[ -n $root_mount && -d $root_mount ]]; then
    mountpoint -q "$root_mount/dev" && umount -R -l "$root_mount/dev"
    mountpoint -q "$root_mount/proc" && umount -R -l "$root_mount/proc"
    mountpoint -q "$root_mount/sys" && umount -R -l "$root_mount/sys"
    mountpoint -q "$root_mount/mnt/omarchy-build" && umount -l "$root_mount/mnt/omarchy-build"
    mountpoint -q "$root_mount/boot" && umount -l "$root_mount/boot"
    mountpoint -q "$root_mount" && umount -R -l "$root_mount"
  fi
  [[ -z $loop_device ]] || losetup -d "$loop_device"
  if (( keep_work == 0 )) && [[ -n $work_dir && -d $work_dir ]]; then
    rm -rf -- "$work_dir"
  elif [[ -n $work_dir ]]; then
    log "Kept build workspace at $work_dir"
  fi
}

download_and_verify_rootfs() {
  local downloads="$work_dir/downloads"
  local status
  mkdir -p "$downloads" "$work_dir/gnupg"
  chmod 700 "$work_dir/gnupg"

  log "Downloading the Arch Linux ARM Raspberry Pi root filesystem"
  curl --fail --location --retry 5 --retry-all-errors \
    --output "$downloads/$rootfs_name" "$rootfs_url"
  curl --fail --location --retry 5 --retry-all-errors \
    --output "$downloads/$rootfs_name.sig" "$rootfs_url.sig"
  curl --fail --location --retry 5 --retry-all-errors \
    --output "$downloads/archlinuxarm.gpg" "$keyring_url"

  GNUPGHOME="$work_dir/gnupg" gpg --quiet --import "$downloads/archlinuxarm.gpg"
  status=$(GNUPGHOME="$work_dir/gnupg" gpg --status-fd 1 \
    --verify "$downloads/$rootfs_name.sig" "$downloads/$rootfs_name" 2>/dev/null)
  grep -F "[GNUPG:] VALIDSIG $build_key " <<<"$status" >/dev/null ||
    fail "The Arch Linux ARM root filesystem was not signed by the published build key."
  log "Verified Arch Linux ARM signature $build_key"
}

partition_path() {
  local number="$1"
  if [[ $loop_device == *[0-9] ]]; then
    printf '%sp%s' "$loop_device" "$number"
  else
    printf '%s%s' "$loop_device" "$number"
  fi
}

create_filesystems() {
  image_path="$work_dir/omarchy-4-pi.img"
  root_mount="$work_dir/root"
  mkdir -p "$root_mount"

  log "Creating a sparse ${image_size_gib} GiB MBR image"
  truncate -s "${image_size_gib}G" "$image_path"
  parted --script "$image_path" \
    mklabel msdos \
    mkpart primary fat32 4MiB 1028MiB \
    mkpart primary ext4 1028MiB 100% \
    set 1 boot on

  loop_device=$(losetup --find --show --partscan "$image_path")
  udevadm settle
  mkfs.vfat -F 32 -n OMARCHYBOOT "$(partition_path 1)"
  mkfs.ext4 -F -L omarchyroot -m 0 "$(partition_path 2)"
  mount "$(partition_path 2)" "$root_mount"
}

extract_rootfs() {
  local boot_staging="$work_dir/boot"
  mkdir -p "$boot_staging"

  log "Extracting the signed aarch64 root filesystem"
  bsdtar -xpf "$work_dir/downloads/$rootfs_name" -C "$root_mount"
  cp -a "$root_mount/boot/." "$boot_staging/"
  rm -rf "$root_mount/boot"
  mkdir -p "$root_mount/boot"
  mount "$(partition_path 1)" "$root_mount/boot"
  cp -R "$boot_staging/." "$root_mount/boot/"

  cat >"$root_mount/etc/fstab" <<'EOF'
LABEL=omarchyroot /     ext4 defaults,noatime 0 1
LABEL=OMARCHYBOOT /boot vfat defaults,noatime 0 2
EOF
}

mount_chroot_filesystems() {
  local directory
  for directory in dev proc sys; do
    mount --rbind "/$directory" "$root_mount/$directory"
    mount --make-rslave "$root_mount/$directory"
  done

  mkdir -p "$work_dir/package-work/tmp" "$work_dir/package-work/cache" \
    "$root_mount/mnt/omarchy-build"
  chmod 1777 "$work_dir/package-work/tmp" "$work_dir/package-work/cache"
  mount --bind "$work_dir/package-work" "$root_mount/mnt/omarchy-build"

  rm -f "$root_mount/etc/resolv.conf"
  cp /etc/resolv.conf "$root_mount/etc/resolv.conf"
}

copy_source_checkout() {
  mkdir -p "$root_mount/opt/omarchy-4-pi"
  rsync -a --delete \
    --exclude '/build/' \
    --exclude '/build-output-rpi4/' \
    "$repo_root/" "$root_mount/opt/omarchy-4-pi/"
}

prepare_build_user() {
  log "Preparing the Arch Linux ARM build environment"
  cp "$repo_root/default/pacman/pacman-rpi4.conf" "$root_mount/etc/pacman.conf"
  cp "$repo_root/default/pacman/mirrorlist-rpi4" "$root_mount/etc/pacman.d/mirrorlist"
  chroot "$root_mount" pacman-key --init
  chroot "$root_mount" pacman-key --populate archlinuxarm
  chroot "$root_mount" pacman -Syyu --needed --noconfirm base-devel git sudo

  chroot "$root_mount" useradd -m -s /bin/bash omarchy-builder
  printf 'omarchy-builder ALL=(ALL:ALL) NOPASSWD: ALL\n' \
    >"$root_mount/etc/sudoers.d/99-omarchy-image-builder"
  chmod 0440 "$root_mount/etc/sudoers.d/99-omarchy-image-builder"
  chroot "$root_mount" chown -R omarchy-builder:omarchy-builder \
    /home/omarchy-builder /opt/omarchy-4-pi
  printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$root_mount/tmp/omarchy-rpi-model"
}

install_omarchy() {
  local -a installer_args=(--image)
  [[ $install_mode == minimal ]] && installer_args+=(--minimal)

  log "Installing the Omarchy Quattro $install_mode image payload"
  chroot "$root_mount" runuser -u omarchy-builder -- env \
    HOME=/home/omarchy-builder \
    USER=omarchy-builder \
    LOGNAME=omarchy-builder \
    TMPDIR=/mnt/omarchy-build/tmp \
    XDG_CACHE_HOME=/mnt/omarchy-build/cache \
    OMARCHY_RPI_MODEL_PATH=/tmp/omarchy-rpi-model \
    OMARCHY_RPI_CONFIG_PATH=/boot/config.txt \
    OMARCHY_RPI4_ALLOW_UNSUPPORTED=1 \
    /opt/omarchy-4-pi/install-rpi4.sh "${installer_args[@]}"
}

write_build_manifest() {
  local commit dirty rootfs_sha built_at
  commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)
  dirty=false
  [[ -z $(git -C "$repo_root" status --porcelain 2>/dev/null) ]] || dirty=true
  rootfs_sha=$(sha256sum "$work_dir/downloads/$rootfs_name" | awk '{print $1}')
  built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  install -d "$root_mount/usr/share/omarchy-rpi4"
  cat >"$root_mount/usr/share/omarchy-rpi4/build-manifest.json" <<EOF
{
  "project": "omarchy-4-pi",
  "built_at": "$built_at",
  "source_commit": "$commit",
  "source_dirty": $dirty,
  "install_mode": "$install_mode",
  "base_url": "$rootfs_url",
  "base_sha256": "$rootfs_sha",
  "base_signing_key": "$build_key"
}
EOF
}

finalize_image() {
  log "Removing factory credentials, build caches, and machine identity"
  # pacman-key and makepkg can leave gpg-agent processes rooted inside the
  # chroot. Stop them before deleting the build user or unmounting the image.
  chroot "$root_mount" runuser -u omarchy-builder -- gpgconf --kill all 2>/dev/null || true
  chroot "$root_mount" env GNUPGHOME=/etc/pacman.d/gnupg gpgconf --kill all 2>/dev/null || true
  chroot "$root_mount" gpgconf --kill all 2>/dev/null || true
  chroot "$root_mount" chown -R root:root /opt/omarchy-4-pi
  chroot "$root_mount" userdel -r omarchy-builder
  if chroot "$root_mount" getent passwd alarm >/dev/null; then
    chroot "$root_mount" userdel -r alarm
  fi
  chroot "$root_mount" getent passwd alarm >/dev/null &&
    fail "The factory alarm account could not be removed."
  chroot "$root_mount" passwd -l root
  rm -f "$root_mount/etc/sudoers.d/99-omarchy-image-builder" \
    "$root_mount/tmp/omarchy-rpi-model"
  rm -rf "$root_mount/var/cache/pacman/pkg/"* \
    "$root_mount/var/tmp/"* \
    "$root_mount/tmp/"* \
    "$root_mount/opt/omarchy-4-pi/build-output-rpi4"
  find "$root_mount/var/log" -type f -exec truncate -s 0 {} +
  rm -f "$root_mount/etc/ssh/ssh_host_"* \
    "$root_mount/var/lib/systemd/random-seed"
  : >"$root_mount/etc/machine-id"
  printf 'omarchy\n' >"$root_mount/etc/hostname"
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$root_mount/etc/locale.gen"
  chroot "$root_mount" locale-gen
  printf 'LANG=en_US.UTF-8\n' >"$root_mount/etc/locale.conf"
  ln -sfn /usr/share/zoneinfo/UTC "$root_mount/etc/localtime"
  cp "$root_mount/usr/share/omarchy-rpi4/build-manifest.json" \
    "$work_dir/build-manifest.json"

  sync
  # Recursive bind mounts include pseudo-filesystems such as /dev/pts and
  # /dev/shm that can remain kernel-busy after the final chroot command. They
  # contain no image data, so detach those virtual mounts lazily; the real boot
  # and root filesystems below still receive strict, synchronous unmounts.
  umount -R -l "$root_mount/dev"
  umount -R -l "$root_mount/proc"
  umount -R -l "$root_mount/sys"
  umount "$root_mount/mnt/omarchy-build"
  umount "$root_mount/boot"
  if ! umount "$root_mount"; then
    echo "Warning: a stopped chroot helper still holds the root mount; detaching after sync." >&2
    command -v fuser >/dev/null 2>&1 && fuser -vm "$root_mount" >&2 || true
    umount -R -l "$root_mount"
  fi
  blockdev --flushbufs "$loop_device"
  losetup -d "$loop_device"
  loop_device=""

  mkdir -p "$output_dir"
  local commit_short stamp artifact_base compressed
  commit_short=$(git -C "$repo_root" rev-parse --short=8 HEAD 2>/dev/null || printf snapshot)
  stamp=$(date -u +%Y%m%d)
  artifact_base="omarchy-4-pi-${stamp}-${commit_short}-${install_mode}"
  compressed="$output_dir/$artifact_base.img.xz"

  log "Compressing $artifact_base.img.xz"
  XZ_OPT='-T0 -9e' xz --stdout "$image_path" >"$compressed"
  sha256sum "$compressed" >"$compressed.sha256"
  cp "$work_dir/build-manifest.json" "$output_dir/$artifact_base.manifest.json"

  "$script_dir/generate-imager-catalog.sh" "$compressed" \
    "https://github.com/pkyanam/omarchy-4-pi/releases/latest/download/$artifact_base.img.xz" \
    "$output_dir/$artifact_base.os-list.json"
  cp "$output_dir/$artifact_base.os-list.json" "$output_dir/os-list.json"
  log "Built artifacts in $output_dir"
}

main() {
  parse_args "$@"
  require_host
  if [[ -n ${OMARCHY_IMAGE_WORK:-} ]]; then
    work_dir=$OMARCHY_IMAGE_WORK
    mkdir -p "$work_dir"
  else
    work_dir=$(mktemp -d)
  fi
  trap cleanup EXIT

  download_and_verify_rootfs
  create_filesystems
  extract_rootfs
  mount_chroot_filesystems
  copy_source_checkout
  prepare_build_user
  install_omarchy
  write_build_manifest
  finalize_image
}

main "$@"
