# Maintainer : Ionut Biru <ibiru@archlinux.org>
# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=20.0.1
pkgrel=1
pkgdesc="Standalone web browser from mozilla.org"
arch=(i686 x86_64)
license=(MPL GPL LGPL)
depends=(gtk2 mozilla-common libxt startup-notification mime-types dbus-glib alsa-lib
         libnotify desktop-file-utils hicolor-icon-theme
         libvpx libevent nss hunspell sqlite)
makedepends=(unzip zip diffutils python2 yasm mesa
             autoconf2.13 libidl2 xorg-server-xvfb imake)
optdepends=('networkmanager: Location detection via available WiFi networks')
url="http://www.mozilla.org/projects/firefox"
install=firefox.install
options=(!emptydirs)
source=(https://ftp.mozilla.org/pub/mozilla.org/firefox/releases/$pkgver/source/firefox-$pkgver.source.tar.bz2
        mozconfig firefox.desktop firefox-install-dir.patch vendor.js shared-libs.patch)
md5sums=('b822ff4b2348410587dec563235d9320'
         'efdd58626b2f56dea31e26879eb2db3b'
         '6174396b4788deffa399db3f6f010a94'
         '150ac0fb3ac7b2114c8e8851a9e0516c'
         '0d053487907de4376d67d8f499c5502b'
         '52e52f840a49eb1d14be1c0065b03a93')

prepare() {
  cd mozilla-release

  cp ../mozconfig .mozconfig
  patch -Np1 -i ../firefox-install-dir.patch
  patch -Np1 -i ../shared-libs.patch

  # Fix PRE_RELEASE_SUFFIX
  sed -i '/^PRE_RELEASE_SUFFIX := ""/s/ ""//' \
    browser/base/Makefile.in

  mkdir "$srcdir/path"

  # WebRTC build tries to execute "python" and expects Python 2
  ln -s /usr/bin/python2 "$srcdir/path/python"

  # Use gold, as Mozilla can use some of its features, such as safe ICF
  ln -s /usr/bin/ld.gold "$srcdir/path/ld"

  # configure script misdetects the preprocessor without an optimization level
  # https://bugs.archlinux.org/task/34644
  sed -i '/ac_cpp=/s/$CPPFLAGS/& -O2/' configure
}

build() {
  cd mozilla-release

  export PATH="$srcdir/path:$PATH"
  export LDFLAGS="$LDFLAGS -Wl,-rpath,/usr/lib/firefox"
  export PYTHON="/usr/bin/python2"
  export MOZ_MAKE_FLAGS="$MAKEFLAGS"
  unset MAKEFLAGS

  # Enable PGO for x86_64 only. i686 currently has problems:
  # Either segfaults since gcc 4.8, or the linker runs out of memory
  # If you discover that PGO again works on i686, please file a bug
  if [[ $CARCH = x86_64 ]]; then
    export DISPLAY=:99
    Xvfb -nolisten tcp -extension GLX -screen 0 1280x1024x24 $DISPLAY &
    _fail=0

    make -f client.mk build MOZ_PGO=1 || _fail=1

    kill $! || true
    return $_fail
  else
    make -f client.mk build
  fi
}

package() {
  cd mozilla-release
  make -j1 -f client.mk DESTDIR="$pkgdir" install

  install -Dm644 ../vendor.js "$pkgdir/usr/lib/firefox/defaults/preferences/vendor.js"

  for i in 16 22 24 32 48 256; do
      install -Dm644 browser/branding/official/default$i.png \
        "$pkgdir/usr/share/icons/hicolor/${i}x${i}/apps/firefox.png"
  done

  install -Dm644 ../firefox.desktop \
    "$pkgdir/usr/share/applications/firefox.desktop"

  # Use system-provided dictionaries
  rm -rf "$pkgdir"/usr/lib/firefox/{dictionaries,hyphenation}
  ln -s /usr/share/hunspell "$pkgdir/usr/lib/firefox/dictionaries"
  ln -s /usr/share/hyphen "$pkgdir/usr/lib/firefox/hyphenation"

  # We don't want the development stuff
  rm -r "$pkgdir"/usr/{include,lib/firefox-devel,share/idl}

  #workaround for now
  #https://bugzilla.mozilla.org/show_bug.cgi?id=658850
  ln -sf firefox "$pkgdir/usr/lib/firefox/firefox-bin"
}
