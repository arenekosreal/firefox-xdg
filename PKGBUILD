# Maintainer: Dan McGee <dan@archlinux.org>
# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=3.0
pkgrel=1
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
	mozilla-firstrun.patch)
md5sums=('4210ae0801df2eb498408533010d97c1'
         'b7cc507da321ccac96282e938f2fdf36'
         '68cf02788491c6e846729b2f2913bf79'
         '5e68cabfcf3c021806b326f664ac505e'
         'bd5db57c23c72a02a489592644f18995'
         '0f935d428ae3a94c00d06d92c4142498')

build() {
  cd ${startdir}/src/mozilla

  patch -Np1 -i $startdir/src/mozilla-firefox-1.0-lang.patch || return 1
  patch -Np1 -i ${startdir}/src/mozilla-firstrun.patch || return 1
  cp ${startdir}/src/mozconfig .mozconfig

  unset CFLAGS
  unset CXXFLAGS

  export LDFLAGS="-Wl,-rpath,/usr/lib/firefox-3.0"

  make -j1 -f client.mk build MOZ_MAKE_FLAGS="$MAKEFLAGS" || return 1
  make -j1 DESTDIR=${startdir}/pkg install || return 1

  rm -f ${startdir}/pkg/usr/lib/firefox-3.0/libjemalloc.so

  mkdir -p ${startdir}/pkg/usr/share/applications
  mkdir -p ${startdir}/pkg/usr/share/pixmaps
  install -m644 ${startdir}/src/mozilla/browser/app/default48.png ${startdir}/pkg/usr/share/pixmaps/firefox.png
  install -m644 ${startdir}/src/firefox.desktop ${startdir}/pkg/usr/share/applications/
  install -m644 ${startdir}/src/firefox-safe.desktop ${startdir}/pkg/usr/share/applications/
}
