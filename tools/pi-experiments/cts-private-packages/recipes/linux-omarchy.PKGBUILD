pkgbase=linux-omarchy-cts-private
pkgname=('linux-omarchy')
pkgver=7.3
pkgrel=32.11
url='https://omarchy.org'
arch=('aarch64')
license=('GPL-2.0-only')
makedepends=('libarchive' 'zstd' 'python' 'kmod' 'openssl' 'binutils')
options=('!strip' '!debug' '!purge' '!zipman' '!libtool' 'staticlibs' 'emptydirs')
source=('base.pkg.tar.zst' 'provenance.txt' 'patched.ko.zst')
noextract=('base.pkg.tar.zst' 'provenance.txt' 'patched.ko.zst')
sha256sums=('2164fb79c02442b9047166b07f1667558f1674c2ccf345d38b9f7e10e97ef8d8' 'f4683bfff5c3c5d104b8f493bccd5dc4417ca7ab1ae8b11a2becdd00e29ce5b0' 'db5cd638b0e88a6b957e50474b7de97ac9bb6f595af8c7e058539cfa8c799993')
package_linux-omarchy() {
  pkgdesc='The Omarchy Linux for aarch64 (BORE CPU scheduler, ADIOS I/O scheduler) kernel and modules (incremental full-payload private CTS candidate)'
  depends=('coreutils' 'initramfs' 'kmod')
  optdepends=('linux-omarchy-headers: headers and scripts for building modules' 'linux-firmware: firmware images needed for some devices' 'scx-scheds: to use sched-ext schedulers' 'sof-firmware: firmware for Intel SOF audio' 'wireless-regdb: to set the correct wireless channels of your country')
  provides=('ADIOS-MODULE' 'KSMBD-MODULE' 'NTSYNC-MODULE' 'VIRTUALBOX-GUEST-MODULES' 'WIREGUARD-MODULE' 'linux-omarchy-pi4=1')
  conflicts=('linux-omarchy-n1x')
  replaces=('linux-omarchy-n1x')
  bsdtar -xpf "$srcdir/base.pkg.tar.zst" -C "$pkgdir" --exclude ".PKGINFO" --exclude ".BUILDINFO" --exclude ".MTREE"
  cat "$srcdir/patched.ko.zst" > "$pkgdir/usr/lib/modules/7.3.0-32.1-omarchy/kernel/drivers/tty/serial/8250/8250_bcm2835aux.ko.zst"
  install -Dm644 "$srcdir/provenance.txt" "$pkgdir/usr/share/doc/linux-omarchy/cts-private-provenance.txt"
}
