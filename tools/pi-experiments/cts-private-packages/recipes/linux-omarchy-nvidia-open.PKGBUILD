pkgbase=linux-omarchy-nvidia-open-cts-private
pkgname=('linux-omarchy-nvidia-open')
pkgver=7.3
pkgrel=32.11
url='https://omarchy.org'
arch=('aarch64')
license=('MIT AND GPL-2.0-only')
makedepends=('libarchive' 'zstd' 'python' 'kmod' 'openssl' 'binutils')
options=('!strip' '!debug' '!purge' '!zipman' '!libtool' 'staticlibs' 'emptydirs')
source=('base.pkg.tar.zst' 'provenance.txt')
noextract=('base.pkg.tar.zst' 'provenance.txt')
sha256sums=('4d76415647b2a9c1cbf91293bdebf51da47193ed6ab49320ed8ead7baa69386f' 'f4683bfff5c3c5d104b8f493bccd5dc4417ca7ab1ae8b11a2becdd00e29ce5b0')
package_linux-omarchy-nvidia-open() {
  pkgdesc='NVIDIA open kernel modules for the Omarchy Linux for aarch64 (BORE CPU scheduler, ADIOS I/O scheduler) kernel (incremental full-payload private CTS candidate)'
  depends=('linux-omarchy=7.3-32.11' 'nvidia-utils=615.78.08')
  provides=('NVIDIA-MODULE' 'nvidia-open')
  conflicts=('nvidia-open-dkms')
  bsdtar -xpf "$srcdir/base.pkg.tar.zst" -C "$pkgdir" --exclude ".PKGINFO" --exclude ".BUILDINFO" --exclude ".MTREE"
  install -Dm644 "$srcdir/provenance.txt" "$pkgdir/usr/share/doc/linux-omarchy-nvidia-open/cts-private-provenance.txt"
}
