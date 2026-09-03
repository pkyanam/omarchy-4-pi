# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore. ARM
# board ports can select a hardware profile rather than an x86 Omarchy mirror.
pacman_profile="${OMARCHY_PACMAN_PROFILE:-${OMARCHY_MIRROR:-stable}}"
cp -f "$OMARCHY_PATH/default/pacman/pacman-$pacman_profile.conf" /etc/pacman.conf
cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-$pacman_profile" /etc/pacman.d/mirrorlist

# Wait for CUPS to own the file, the way omarchy-settings does, so pacman does
# not turn the override into a .pacnew during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
