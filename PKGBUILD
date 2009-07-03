# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=3.5
pkgrel=1
_xulver=1.9.1
pkgdesc="Standalone web browser from mozilla.org"
arch=(i686 x86_64)
license=('MPL' 'GPL' 'LGPL')
depends=("xulrunner>=${_xulver}" 'desktop-file-utils')
makedepends=('zip' 'pkgconfig' 'diffutils' 'libgnomeui>=2.24.1' 'python')
replaces=('firefox3')
install=firefox.install
url="http://www.mozilla.org/projects/firefox"
source=(http://releases.mozilla.org/pub/mozilla.org/firefox/releases/${pkgver}/source/firefox-${pkgver}-source.tar.bz2
        mozconfig
        firefox.desktop
        firefox-safe.desktop
        mozilla-firefox-1.0-lang.patch
        browser-defaulturls.patch)
md5sums=('6dd59399db08963ef022a1d0e5010053'
         'd672df11a6e16a5dec68428b00bfb810'
         '68cf02788491c6e846729b2f2913bf79'
         '5e68cabfcf3c021806b326f664ac505e'
         'bd5db57c23c72a02a489592644f18995'
         '346d74ec560e7bbf453c02ff21f4b868')

build() {
  cd "${srcdir}/mozilla-${_xulver}"
  patch -Np1 -i "${srcdir}/mozilla-firefox-1.0-lang.patch" || return 1
  patch -Np0 -i "${srcdir}/browser-defaulturls.patch" || return 1

  cp "${srcdir}/mozconfig" .mozconfig
  unset CFLAGS
  unset CXXFLAGS

  export LDFLAGS="-Wl,-rpath,/usr/lib/firefox-3.5"

  make -j1 -f client.mk build MOZ_MAKE_FLAGS="${MAKEFLAGS}" || return 1
  make -j1 DESTDIR="${pkgdir}" install || return 1

  rm -f ${pkgdir}/usr/lib/firefox-3.5/libjemalloc.so

  install -m755 -d ${pkgdir}/usr/share/applications
  install -m755 -d ${pkgdir}/usr/share/pixmaps
  install -m644 ${srcdir}/mozilla-${_xulver}/browser/branding/unofficial/default48.png ${pkgdir}/usr/share/pixmaps/firefox.png || return 1
  install -m644 ${srcdir}/firefox.desktop ${pkgdir}/usr/share/applications/ || return 1
  install -m644 ${srcdir}/firefox-safe.desktop ${pkgdir}/usr/share/applications/ || return 1
}
