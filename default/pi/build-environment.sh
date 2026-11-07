# shellcheck shell=bash
# Installer/builder/updater contract (no user manager required):
#   source "$OMARCHY_PATH/default/pi/build-environment.sh"
#   omarchy_pi_prepare_build installer
#   trap 'omarchy_pi_cleanup_build' EXIT   # compose with the caller's cleanup
#   makepkg --config "$OMARCHY_PI_MAKEPKG_CONF" ...
# Call in the current shell BEFORE staging or the first makepkg. A subshell or
# sudo invocation must receive the exported variables and readable config.
# Each process owns only its own mktemp child. No trap or HOME override here.

omarchy_pi_check_build_storage() {
  local directory=$1 filesystem free_kib free_inodes total_inodes inode_report
  local min_kib=${OMARCHY_PI_BUILD_MIN_KIB:-6291456} min_inodes=${OMARCHY_PI_BUILD_MIN_INODES:-50000}
  if [[ ! $min_kib =~ ^[1-9][0-9]*$ || ! $min_inodes =~ ^[1-9][0-9]*$ ]]; then
    echo "Pi build space/inode minimums must be positive integers." >&2
    return 1
  fi
  filesystem=$(findmnt -n -o FSTYPE --target "$directory") || return 1
  case "$filesystem" in
    ext2|ext3|ext4|btrfs|xfs|f2fs|zfs|bcachefs) ;;
    *)
      echo "Pi builds require a verified disk filesystem; $directory is $filesystem. Set OMARCHY_PI_BUILD_PARENT to a disk mount (also in containers/chroots)." >&2
      return 1
      ;;
  esac
  free_kib=$(df -Pk -- "$directory" | awk 'NR == 2 {print $4}') || return 1
  inode_report=$(df -Pi -- "$directory" | awk 'NR == 2 {print $2, $4}') || return 1
  read -r total_inodes free_inodes <<<"$inode_report"
  if [[ ! $free_kib =~ ^[0-9]+$ || ! $total_inodes =~ ^[0-9]+$ || ! $free_inodes =~ ^[0-9]+$ ]] ||
    (( free_kib < min_kib )); then
    echo "Insufficient Pi build space/inodes at $directory: need ${min_kib}KiB and $min_inodes free inodes." >&2
    return 1
  fi
  if (( total_inodes == 0 )); then
    # Btrfs (and ZFS/bcachefs) allocate inodes dynamically; df can report an
    # all-zero inode table. This is not a zero-free fixed ext4 inode pool.
    case "$filesystem" in
      btrfs|zfs|bcachefs) ;;
      *) echo "Cannot determine fixed inode capacity at $directory." >&2; return 1 ;;
    esac
  elif (( free_inodes < min_inodes )); then
    echo "Insufficient Pi build inodes at $directory: need $min_inodes free inodes." >&2
    return 1
  fi
}

omarchy_pi_prepare_build() {
  local label=${1:-build} defaults parent work base_conf pkgdest variable
  [[ $label =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || return 1
  defaults=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 1
  source "$defaults/build-budget.sh" || return 1
  if [[ -n ${_omarchy_pi_owned_build:-} && ${_omarchy_pi_build_pid:-} == "$BASHPID" ]]; then
    omarchy_pi_check_build_storage "$_omarchy_pi_owned_build"
    return
  fi
  parent=${OMARCHY_PI_BUILD_PARENT:-${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/pi-build}}
  [[ $parent == /* ]] || { echo "Pi build parent must be an absolute path." >&2; return 1; }
  (umask 077; mkdir -p -- "$parent") || return 1
  parent=$(cd -- "$parent" && pwd -P) || return 1
  omarchy_pi_check_build_storage "$parent" || return 1
  base_conf=${OMARCHY_PI_MAKEPKG_BASE_CONF:-/etc/makepkg.conf}
  [[ -r $base_conf ]] || { echo "Cannot read makepkg base config: $base_conf" >&2; return 1; }
  work=$(umask 077; mktemp -d "$parent/omarchy-pi-$label.XXXXXXXX") || return 1
  _omarchy_pi_owned_build=$work
  _omarchy_pi_build_pid=$BASHPID
  _omarchy_pi_build_owner="$$:$BASHPID:$RANDOM:$RANDOM"
  if ! (umask 077; printf '%s\n' "$_omarchy_pi_build_owner" >"$work/.omarchy-pi-build-owner"); then
    # A failed write can still leave a partial marker in the new directory.
    rm -f -- "$work/.omarchy-pi-build-owner" 2>/dev/null || true
    rmdir -- "$work" 2>/dev/null || true
    unset _omarchy_pi_owned_build _omarchy_pi_build_owner _omarchy_pi_build_pid
    return 1
  fi
  _omarchy_pi_previous_tmpdir=${TMPDIR-}
  _omarchy_pi_tmpdir_was_set=${TMPDIR+x}
  pkgdest=${PKGDEST:-$work/cache/packages}
  if [[ $pkgdest != /* ]] || ! (umask 077; mkdir -p -- "$pkgdest") ||
    ! omarchy_pi_check_build_storage "$pkgdest"; then
    omarchy_pi_cleanup_build
    return 1
  fi
  if ! (
    umask 077
    mkdir -p "$work/tmp" "$work/build" "$work/cache/sources" "$work/cache/packages" && {
      printf 'source %q\n' "$base_conf"
      printf 'source %q\n' "$defaults/build-budget.sh"
      printf 'BUILDDIR=%q\nSRCDEST=%q\nSRCPKGDEST=%q\nPKGDEST=%q\n' \
        "$work/build" "$work/cache/sources" "$work/cache/packages" "$pkgdest"
    } >"$work/makepkg.conf"
  ); then
    omarchy_pi_cleanup_build
    return 1
  fi
  export OMARCHY_PI_BUILD_WORK=$work OMARCHY_PI_BUILD_CACHE="$work/cache"
  export OMARCHY_PI_MAKEPKG_CONF="$work/makepkg.conf" TMPDIR="$work/tmp"
  # makepkg restores these variables from its environment after sourcing a
  # --config file. Export checked private locations too, so inherited /tmp
  # overrides cannot silently move compiler/cache data back onto tmpfs.
  declare -gA _omarchy_pi_previous_paths=() _omarchy_pi_previous_paths_set=()
  for variable in BUILDDIR SRCDEST SRCPKGDEST; do
    _omarchy_pi_previous_paths[$variable]=${!variable-}
    if [[ -v $variable ]]; then
      _omarchy_pi_previous_paths_set[$variable]=1
    else
      _omarchy_pi_previous_paths_set[$variable]=0
    fi
  done
  export BUILDDIR="$work/build" SRCDEST="$work/cache/sources" SRCPKGDEST="$work/cache/packages"
}

omarchy_pi_cleanup_build() {
  local work=${_omarchy_pi_owned_build:-} variable
  [[ -n $work ]] || return 0
  [[ ${_omarchy_pi_build_pid:-} == "$BASHPID" ]] || return 0
  # A missing/changed marker, substituted directory, or inherited path is never
  # authority to delete caller files. Parent/cache locations are never removed.
  if [[ ! -d $work || -L $work || ! -O $work || -L $work/.omarchy-pi-build-owner ||
    ! -f $work/.omarchy-pi-build-owner || $(<"$work/.omarchy-pi-build-owner") != "${_omarchy_pi_build_owner:-}" ]]; then
    echo "Refusing cleanup of an unowned Pi build workspace: $work" >&2
    return 1
  fi
  rm -rf -- "$work" || return 1
  if [[ ${TMPDIR:-} == "$work/tmp" ]]; then
    if [[ ${_omarchy_pi_tmpdir_was_set:-} == "x" ]]; then
      export TMPDIR=$_omarchy_pi_previous_tmpdir
    else
      unset TMPDIR
    fi
  fi
  for variable in BUILDDIR SRCDEST SRCPKGDEST; do
    if [[ ${!variable:-} == "$work/"* ]]; then
      if [[ ${_omarchy_pi_previous_paths_set[$variable]:-0} == 1 ]]; then
        export "$variable=${_omarchy_pi_previous_paths[$variable]}"
      else
        unset "$variable"
      fi
    fi
  done
  unset _omarchy_pi_previous_paths _omarchy_pi_previous_paths_set
  unset _omarchy_pi_owned_build _omarchy_pi_build_owner _omarchy_pi_build_pid _omarchy_pi_previous_tmpdir _omarchy_pi_tmpdir_was_set
  unset OMARCHY_PI_BUILD_WORK OMARCHY_PI_BUILD_CACHE OMARCHY_PI_MAKEPKG_CONF
}
