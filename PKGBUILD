# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=4.0rc1
pkgrel=2
_xulver=2.0rc1
pkgdesc="Standalone web browser from mozilla.org"
arch=('i686' 'x86_64')
license=('MPL' 'GPL' 'LGPL')
depends=("xulrunner=${_xulver}" 'desktop-file-utils')
makedepends=('zip' 'pkg-config' 'diffutils' 'python2' 'wireless_tools' 'yasm' 'mesa')
install=firefox.install
url="http://www.mozilla.org/projects/firefox"
source=(http://releases.mozilla.org/pub/mozilla.org/firefox/releases/${pkgver}/source/firefox-${pkgver}.source.tar.bz2
        mozconfig
        firefox.desktop
        firefox-safe.desktop
        mozilla-firefox-1.0-lang.patch
        firefox-version.patch)
md5sums=('511828dcc226f38602c6c67bd192ef40'
         '8f8b86cd0cc36a3f60c0d287a2c0b9fb'
         'bdeb0380c7fae30dd0ead6d2d3bc5873'
         '6f38a5899034b7786cb1f75ad42032b8'
         'bd5db57c23c72a02a489592644f18995'
         'cea73894617d0e12362db294864fb87f')

build() {
  cd "${srcdir}/mozilla-2.0"
  patch -Np1 -i "${srcdir}/mozilla-firefox-1.0-lang.patch"
  patch -Np1 -i "${srcdir}/firefox-version.patch"

  cp "${srcdir}/mozconfig" .mozconfig
  unset CFLAGS
  unset CXXFLAGS

  export LDFLAGS="-Wl,-rpath,/usr/lib/firefox-4.0"

  make -j1 -f client.mk build MOZ_MAKE_FLAGS="${MAKEFLAGS}"
}

package() {
  cd "${srcdir}/mozilla-2.0"
  make -j1 -f client.mk DESTDIR="${pkgdir}" install

  install -m755 -d ${pkgdir}/usr/share/{applications,pixmaps}
  install -m644 browser/branding/unofficial/default48.png ${pkgdir}/usr/share/pixmaps/firefox.png
  install -m644 ${srcdir}/firefox.desktop ${pkgdir}/usr/share/applications/
  install -m644 ${srcdir}/firefox-safe.desktop ${pkgdir}/usr/share/applications/
}
