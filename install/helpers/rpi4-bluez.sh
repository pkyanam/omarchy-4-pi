# shellcheck shell=bash
# Retire this exact-version backport when stable ARM packages contain the
# upstream fix. A newer repository package follows the normal signed plan.
omarchy_pi_install_bluez_backport() (
  local checkout=$1 artifact metadata installed
  installed=$(pacman -Q bluez-utils) || return 1
  [[ $installed == "bluez-utils 5.87-2" ]] || return 0
  source "$checkout/default/pi/build-environment.sh" || return 1
  omarchy_pi_prepare_build bluez || return 1
  trap omarchy_pi_cleanup_build EXIT
  cp -a "$checkout/default/pi/bluez-utils" "$OMARCHY_PI_BUILD_WORK/recipe" || return 1
  cd "$OMARCHY_PI_BUILD_WORK/recipe" || return 1
  makepkg --config "$OMARCHY_PI_MAKEPKG_CONF" --noconfirm || return 1
  artifact=$(makepkg --config "$OMARCHY_PI_MAKEPKG_CONF" --packagelist) || return 1
  [[ -f $artifact ]] || return 1
  metadata=$(bsdtar -xOf "$artifact" .PKGINFO) || return 1
  [[ $(awk -F ' = ' '$1 == "pkgname" {print $2}' <<<"$metadata") == "bluez-utils" &&
    $(awk -F ' = ' '$1 == "pkgver" {print $2}' <<<"$metadata") == "5.87-2.1" &&
    $(awk -F ' = ' '$1 == "arch" {print $2}' <<<"$metadata") == "aarch64" ]] || return 1
  sudo pacman -U --noconfirm "$artifact" || return 1
  [[ $(pacman -Q bluez-utils) == "bluez-utils 5.87-2.1" ]]
)
