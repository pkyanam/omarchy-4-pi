pkgbase=linux-omarchy-headers-cts-private
pkgname=('linux-omarchy-headers')
pkgver=7.3
pkgrel=32.11
url='https://omarchy.org'
arch=('aarch64')
license=('GPL-2.0-only')
makedepends=('libarchive' 'zstd' 'python' 'kmod' 'openssl' 'binutils')
options=('!strip' '!debug' '!purge' '!zipman' '!libtool' 'staticlibs' 'emptydirs')
source=('base.pkg.tar.zst' 'provenance.txt')
noextract=('base.pkg.tar.zst' 'provenance.txt')
sha256sums=('1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1' 'f4683bfff5c3c5d104b8f493bccd5dc4417ca7ab1ae8b11a2becdd00e29ce5b0')
package_linux-omarchy-headers() {
  pkgdesc='Headers and scripts for building modules for the Omarchy Linux for aarch64 (BORE CPU scheduler, ADIOS I/O scheduler) kernel (incremental full-payload private CTS candidate)'
  depends=('linux-omarchy=7.3-32.11' 'binutils' 'glibc' 'libelf' 'libgcc' 'openssl' 'pahole' 'xxhash' 'zlib' 'zstd')
  provides=('LINUX-HEADERS')
  conflicts=('linux-omarchy-n1x-headers')
  replaces=('linux-omarchy-n1x-headers')
  bsdtar -xpf "$srcdir/base.pkg.tar.zst" -C "$pkgdir" --exclude ".PKGINFO" --exclude ".BUILDINFO" --exclude ".MTREE"
  install -Dm644 "$srcdir/provenance.txt" "$pkgdir/usr/share/doc/linux-omarchy-headers/cts-private-provenance.txt"
}
