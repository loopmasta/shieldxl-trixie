#!/bin/bash
# shieldXL (norns shield 210330) on Raspberry Pi OS trixie (arm64), step 1:
# packages and libraries. Everything comes from Debian except libgpiod 1.6
# (norns uses the v1 API, trixie only ships v2) and libmonome (not in Debian).
set -e
SRC=~/src
mkdir -p $SRC

# passwordless sudo for we, as on a norns (matron calls sudo for system actions)
echo "we ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/010_we-nopasswd > /dev/null
sudo chmod 440 /etc/sudoers.d/010_we-nopasswd
sudo visudo -c -q

echo "jackd2 jackd/tweak_rt_limits boolean true" | sudo debconf-set-selections
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git build-essential pkg-config python3 curl wget xz-utils \
  autoconf automake autoconf-archive libtool \
  jackd2 jack-example-tools libjack-jackd2-dev \
  supercollider-language supercollider-server supercollider-dev sc3-plugins \
  libevdev-dev liblo-dev libudev-dev libcairo2-dev liblua5.3-dev \
  libavahi-compat-libdnssd-dev libasound2-dev libncurses-dev libreadline-dev \
  libsndfile1-dev libnanomsg-dev libboost-dev libi2c-dev i2c-tools \
  alsa-utils samba dkms linux-headers-rpi-v8 golang-go
sudo usermod -aG audio,gpio,spi,i2c,input we

# libgpiod 1.6 (v1 API) into /usr/local
if [ "$(pkg-config --modversion libgpiod 2>/dev/null)" != "1.6.5" ]; then
  cd $SRC
  curl -sL https://mirrors.edge.kernel.org/pub/software/libs/libgpiod/libgpiod-1.6.5.tar.xz | tar xJ
  cd libgpiod-1.6.5
  ./configure --prefix=/usr/local
  make -j4
  sudo make install
  sudo ldconfig
fi

# libmonome, at the release this setup was tested with
LIBMONOME_TAG=v1.4.11
if [ ! -e /usr/local/lib/libmonome.so.${LIBMONOME_TAG#v} ]; then
  cd $SRC
  rm -rf libmonome
  git clone --branch $LIBMONOME_TAG --depth 1 https://github.com/monome/libmonome.git
  cd libmonome
  ./waf configure
  ./waf
  sudo ./waf install
  sudo ldconfig
fi

echo "step 1 done"
