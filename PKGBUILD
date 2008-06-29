# Maintainer: Dan McGee <dan@archlinux.org>
# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=3.0
pkgrel=2
pkgdesc="Standalone web browser from mozilla.org"
arch=(i686 x86_64)
license=('MPL' 'GPL' 'LGPL')
depends=('xulrunner>=1.9' 'startup-notification' 'desktop-file-utils')
makedepends=('zip' 'pkgconfig' 'diffutils' 'libgnomeui>=2.22.1')
replaces=('firefox3')
install=firefox.install
url="http://www.mozilla.org/projects/firefox"
source=(http://releases.mozilla.org/pub/mozilla.org/firefox/releases/${pkgver}/source/firefox-${pkgver}-source.tar.bz2
        mozconfig
        firefox.desktop
        firefox-safe.desktop
        mozilla-firefox-1.0-lang.patch
	mozilla-firstrun.patch
	firefox.sh)
md5sums=('4210ae0801df2eb498408533010d97c1'
         'b7cc507da321ccac96282e938f2fdf36'
         '68cf02788491c6e846729b2f2913bf79'
         '5e68cabfcf3c021806b326f664ac505e'
         'bd5db57c23c72a02a489592644f18995'
         '0f935d428ae3a94c00d06d92c4142498'
	 'afc69657a5881cc264a8b2e7ded146e3')

build() {
  cd ${srcdir}/mozilla

  patch -Np1 -i ${srcdir}/mozilla-firefox-1.0-lang.patch || return 1
  patch -Np1 -i ${srcdir}/mozilla-firstrun.patch || return 1
  cp ${srcdir}/mozconfig .mozconfig

  unset CFLAGS
  unset CXXFLAGS

  export LDFLAGS="-Wl,-rpath,/usr/lib/firefox-3.0"

  make -j1 -f client.mk build MOZ_MAKE_FLAGS="${MAKEFLAGS}" || return 1
  make -j1 DESTDIR=${pkgdir} install || return 1

  rm -f ${pkgdir}/usr/bin/firefox
  install -m755 ${srcdir}/firefox.sh ${pkgdir}/usr/bin/firefox || return 1

  rm -f ${pkgdir}/usr/lib/firefox-3.0/libjemalloc.so

  install -m755 -d ${pkgdir}/usr/share/applications
  install -m755 -d ${pkgdir}/usr/share/pixmaps
  install -m644 ${srcdir}/mozilla/browser/app/default48.png ${pkgdir}/usr/share/pixmaps/firefox.png || return 1
  install -m644 ${srcdir}/firefox.desktop ${pkgdir}/usr/share/applications/ || return 1
  install -m644 ${srcdir}/firefox-safe.desktop ${pkgdir}/usr/share/applications/ || return 1
}
