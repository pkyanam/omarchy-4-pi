# shellcheck shell=bash
# Shared Pi package provenance and artifact checks. Sourcing has no side effects.
omarchy_pi_core_version=4.5.0.pi4.1
omarchy_pi_core_packages=(omarchy-keyring ttf-jetbrains-mono-nerd-basic omarchy-settings omarchy)

omarchy_pi_verify_recipes() {
  local repository=$1 expected=$2
  [[ -d $repository/.git && $expected =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $(git -C "$repository" rev-parse HEAD) == "$expected" &&
    -z $(git -C "$repository" status --porcelain) ]] || {
    echo "Pi package recipes must be clean at reviewed commit $expected." >&2
    return 1
  }
  [[ $(git -C "$repository" remote get-url origin) == "https://github.com/omacom/omarchy-pkgs.git" ]] || {
    echo "Unexpected Pi package recipe origin." >&2
    return 1
  }
}

# Populates omarchy_pi_artifacts only after a complete, non-duplicated set has
# passed metadata checks. Globbing alone used to install stale/missing packages.
omarchy_pi_verify_artifacts() {
  local directory=$1 artifact metadata name version arch expected filename
  shift
  local -a candidates=("$@")
  local -A found=()
  if (( ${#candidates[@]} == 0 )); then
    if [[ -f $directory/omarchy-pi-artifacts.list ]]; then
      while IFS= read -r filename; do
        [[ -n $filename && $filename != */* && $filename == *.pkg.tar.* && $filename != *.sig ]] || return 1
        candidates+=("$directory/$filename")
      done <"$directory/omarchy-pi-artifacts.list"
    else
      candidates=("$directory"/*.pkg.tar.*)
    fi
  fi
  omarchy_pi_artifacts=()
  for artifact in "${candidates[@]}"; do
    [[ -f $artifact && $artifact != *.sig ]] || continue
    metadata=$(bsdtar -xOf "$artifact" .PKGINFO) || return 1
    name=$(awk -F ' = ' '$1 == "pkgname" { print $2 }' <<<"$metadata")
    version=$(awk -F ' = ' '$1 == "pkgver" { print $2 }' <<<"$metadata")
    arch=$(awk -F ' = ' '$1 == "arch" { print $2 }' <<<"$metadata")
    case $name in
      omarchy|omarchy-settings)
        [[ $version == "$omarchy_pi_core_version-1" && $arch == "aarch64" ]] || return 1
        ;;
      omarchy-keyring)
        [[ $version == "20251027-1" && $arch == "any" ]] || return 1
        ;;
      ttf-jetbrains-mono-nerd-basic)
        [[ $version == "3.5.1-2" && $arch == "any" ]] || return 1
        ;;
      *) echo "Unexpected Pi core artifact: $artifact" >&2; return 1 ;;
    esac
    [[ -z ${found[$name]:-} ]] || return 1
    found[$name]=1
    omarchy_pi_artifacts+=("$artifact")
  done
  for expected in "${omarchy_pi_core_packages[@]}"; do
    [[ ${found[$expected]:-} == "1" ]] || {
      echo "Pi core artifact set is missing $expected." >&2
      return 1
    }
  done
}

omarchy_pi_verify_installed_artifacts() {
  local artifact metadata name version
  for artifact in "${omarchy_pi_artifacts[@]}"; do
    metadata=$(bsdtar -xOf "$artifact" .PKGINFO) || return 1
    name=$(awk -F ' = ' '$1 == "pkgname" { print $2 }' <<<"$metadata")
    version=$(awk -F ' = ' '$1 == "pkgver" { print $2 }' <<<"$metadata")
    [[ $(pacman -Q "$name") == "$name $version" ]] || {
      echo "Pi artifact did not install at its expected version: $name $version" >&2
      return 1
    }
  done
}
