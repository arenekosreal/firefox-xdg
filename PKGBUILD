# Maintainer: Jan Alexander Steffens (heftig) <jan.steffens@gmail.com>
# Contributor: Ionut Biru <ibiru@archlinux.org>
# Contributor: Jakub Schmidtke <sjakub@gmail.com>

pkgname=firefox
pkgver=51.0
pkgrel=1
pkgdesc="Standalone web browser from mozilla.org"
arch=(i686 x86_64)
license=(MPL GPL LGPL)
url="https://www.mozilla.org/firefox/"
depends=(gtk3 gtk2 mozilla-common libxt startup-notification mime-types dbus-glib alsa-lib ffmpeg
         libvpx libevent nss hunspell sqlite ttf-font icu)
makedepends=(unzip zip diffutils python2 yasm mesa imake gconf libpulse inetutils xorg-server-xvfb
             autoconf2.13 cargo)
optdepends=('networkmanager: Location detection via available WiFi networks'
            'libnotify: Notification integration'
            'upower: Battery API')
options=(!emptydirs !makeflags)
source=(https://ftp.mozilla.org/pub/mozilla.org/firefox/releases/$pkgver/source/firefox-$pkgver.source.tar.xz
        mozconfig
        firefox.desktop
        firefox-install-dir.patch
        rust-i686.patch
        vendor.js
        firefox-symbolic.svg
        fix-wifi-scanner.diff)
sha256sums=('6535b7a69c28e3613a815801aa2d9416d133dd92e17e7c8eb68d9776ce9eebea'
            '3b0c6b08c0211d8c5a02aa050755276ec864c5f2c5ac1a3d3f9f8a9af6512737'
            '75c526e9669b91b4fe5dcea650a1e8419220abb2e9564184f0d984c71eae82e8'
            'd86e41d87363656ee62e12543e2f5181aadcff448e406ef3218e91865ae775cd'
            'f61ea706ce6905f568b9bdafd1b044b58f20737426f0aa5019ddb9b64031a269'
            '93c5df00f409988bbfa890ac175103476ead3af68f7501973ee70bd11dc472f8'
            'a2474b32b9b2d7e0fb53a4c89715507ad1c194bef77713d798fa39d507def9e9'
            '9765bca5d63fb5525bbd0520b7ab1d27cabaed697e2fc7791400abc3fa4f13b8')
validpgpkeys=('2B90598A745E992F315E22C58AB132963A06537A')

# Google API keys (see http://www.chromium.org/developers/how-tos/api-keys)
# Note: These are for Arch Linux use ONLY. For your own distribution, please
# get your own set of keys. Feel free to contact foutrelis@archlinux.org for
# more information.
_google_api_key=AIzaSyDwr302FpOSkGRpLlUpPThNTDPbXcIn_FM

# Mozilla API keys (see https://location.services.mozilla.com/api)
# Note: These are for Arch Linux use ONLY. For your own distribution, please
# get your own set of keys. Feel free to contact heftig@archlinux.org for
# more information.
_mozilla_api_key=16674381-f021-49de-8622-3021c5942aff


prepare() {
  cd $pkgname-$pkgver

  cp ../mozconfig .mozconfig
  patch -Np1 -i ../firefox-install-dir.patch

  # https://bugzilla.mozilla.org/show_bug.cgi?id=1314968
  patch -Np1 -i ../fix-wifi-scanner.diff

  # Build with the rust targets we actually ship
  patch -Np1 -i ../rust-i686.patch

  echo -n "$_google_api_key" >google-api-key
  echo "ac_add_options --with-google-api-keyfile=\"$PWD/google-api-key\"" >>.mozconfig

  echo -n "$_mozilla_api_key" >mozilla-api-key
  echo "ac_add_options --with-mozilla-api-keyfile=\"$PWD/mozilla-api-key\"" >>.mozconfig

  mkdir "$srcdir/path"
  ln -s /usr/bin/python2 "$srcdir/path/python"
}

build() {
  cd $pkgname-$pkgver

  # _FORTIFY_SOURCE causes configure failures
  CPPFLAGS+=" -O2"

  # Hardening
  LDFLAGS+=" -Wl,-z,now"

  # GCC 6
  CXXFLAGS+=" -fno-delete-null-pointer-checks -fno-schedule-insns2"

  export PATH="$srcdir/path:$PATH"

  # Do PGO
  #xvfb-run -a -s "-extension GLX -screen 0 1280x1024x24" \
  #  make -f client.mk build MOZ_PGO=1
  make -f client.mk build
}

package() {
  cd $pkgname-$pkgver
  make -f client.mk DESTDIR="$pkgdir" INSTALL_SDK= install

  install -Dm644 ../vendor.js "$pkgdir/usr/lib/firefox/browser/defaults/preferences/vendor.js"

  for i in 16 22 24 32 48 256; do
      install -Dm644 browser/branding/official/default$i.png \
        "$pkgdir/usr/share/icons/hicolor/${i}x${i}/apps/firefox.png"
  done
  install -Dm644 browser/branding/official/content/icon64.png \
    "$pkgdir/usr/share/icons/hicolor/64x64/apps/firefox.png"
  install -Dm644 browser/branding/official/mozicon128.png \
    "$pkgdir/usr/share/icons/hicolor/128x128/apps/firefox.png"
  install -Dm644 browser/branding/official/content/about-logo.png \
    "$pkgdir/usr/share/icons/hicolor/192x192/apps/firefox.png"
  install -Dm644 browser/branding/official/content/about-logo@2x.png \
    "$pkgdir/usr/share/icons/hicolor/384x384/apps/firefox.png"
  install -Dm644 ../firefox-symbolic.svg \
    "$pkgdir/usr/share/icons/hicolor/symbolic/apps/firefox-symbolic.svg"

  install -Dm644 ../firefox.desktop \
    "$pkgdir/usr/share/applications/firefox.desktop"

  # Use system-provided dictionaries
  rm -rf "$pkgdir"/usr/lib/firefox/{dictionaries,hyphenation}
  ln -s /usr/share/hunspell "$pkgdir/usr/lib/firefox/dictionaries"
  ln -s /usr/share/hyphen "$pkgdir/usr/lib/firefox/hyphenation"

  # Replace duplicate binary with symlink
  # https://bugzilla.mozilla.org/show_bug.cgi?id=658850
  ln -sf firefox "$pkgdir/usr/lib/firefox/firefox-bin"
}
