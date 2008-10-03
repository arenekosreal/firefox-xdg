# Maintainer: Dan McGee <dan@archlinux.org>
# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=3.0.3
pkgrel=1
pkgdesc="Standalone web browser from mozilla.org"
arch=(i686 x86_64)
license=('MPL' 'GPL' 'LGPL')
depends=('xulrunner>=1.9.0.3-1' 'desktop-file-utils' 'mime-types' 'shared-mime-info')
makedepends=('zip' 'pkgconfig' 'diffutils' 'libgnomeui>=2.22.1' 'python' 'xorg-server')
replaces=('firefox3')
install=firefox.install
url="http://www.mozilla.org/projects/firefox"
source=(http://releases.mozilla.org/pub/mozilla.org/firefox/releases/${pkgver}/source/firefox-${pkgver}-source.tar.bz2
        mozconfig
        firefox.desktop
        firefox-safe.desktop
        mozilla-firefox-1.0-lang.patch
	mozilla-firstrun.patch
	mozbug421977.patch)
md5sums=('e076a4a889fce0c4ca237ac30bfadb43'
         '8b6e5f7d0a9e3f64747a024cf8f12069'
         '68cf02788491c6e846729b2f2913bf79'
         '5e68cabfcf3c021806b326f664ac505e'
         'bd5db57c23c72a02a489592644f18995'
         '42af09c0200b752ac7f7d639b3a2947b'
         '7976e3ff52e01af3388dfc3a479c4955')

build() {
  cd ${srcdir}/mozilla

  patch -Np1 -i ${srcdir}/mozilla-firefox-1.0-lang.patch || return 1
  patch -Np1 -i ${srcdir}/mozilla-firstrun.patch || return 1

  # FS#10836: fixes backgroundcolor parsing with gnome
  patch -Np0 -i ${srcdir}/mozbug421977.patch || return 1

  cp ${srcdir}/mozconfig .mozconfig

  unset CFLAGS
  unset CXXFLAGS

  export LDFLAGS="-Wl,-rpath,/usr/lib/firefox-${pkgver}"

  LD_PRELOAD="" /usr/bin/Xvfb -nolisten tcp -extension GLX :99 &
  XPID=$!
  export DISPLAY=:99

  LD_PRELOAD="" make -j1 -f client.mk profiledbuild MOZ_MAKE_FLAGS="${MAKEFLAGS}" || return 1
  kill $XPID

  make -j1 DESTDIR=${pkgdir} -C ff-opt-obj install || return 1

  rm -f ${pkgdir}/usr/lib/firefox-${pkgver}/libjemalloc.so

  install -m755 -d ${pkgdir}/usr/share/applications
  install -m755 -d ${pkgdir}/usr/share/pixmaps
  install -m644 ${srcdir}/mozilla/browser/branding/unofficial/default48.png ${pkgdir}/usr/share/pixmaps/firefox.png || return 1
  install -m644 ${srcdir}/firefox.desktop ${pkgdir}/usr/share/applications/ || return 1
  install -m644 ${srcdir}/firefox-safe.desktop ${pkgdir}/usr/share/applications/ || return 1
}
