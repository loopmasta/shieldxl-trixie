#!/bin/bash
# shieldXL (norns shield 210330) on Raspberry Pi OS trixie (arm64), step 3:
# norns, maiden, services. Builds monome/norns at a release tag (the shield
# pins and matronrc.lua are norns' defaults), builds the maiden server for
# arm64 (its web app comes from the official update package), installs the
# norns-image systemd units. Run after the reboot that follows step 2 (the
# sound card has to be up).
set -e
NORNS_TAG=v2.9.4
UPDATE=norns260102 # the update package of $NORNS_TAG (maiden app, version)
MAIDEN_TAG=v1.1.6  # the maiden in $UPDATE
SRC=~/src
mkdir -p $SRC

# --- norns
cd ~
if [ ! -d norns ]; then
  git clone --branch $NORNS_TAG --depth 1 https://github.com/monome/norns.git
  cd norns
  git submodule update --init --recursive --depth 1
fi
cd ~/norns

# --- patches for trixie / arm64 (norns 2.9.4 targets 32-bit Raspberry Pi OS
# buster): each one only applies if it isn't there yet
# waf 2.0.14 vs Python 3.12+: no imp module, no 'rU' file mode
./waf --version > /dev/null 2>&1 || true # unpacks waflib
W=$(ls -d .waf3-2.0.14-*)
sed -i "s/^import os,re,imp,sys$/import os,re,sys,types/; s/module=imp.new_module(WSCRIPT_FILE)/module=types.ModuleType(WSCRIPT_FILE)/" $W/waflib/Context.py
sed -i "s/m='rU'/m='r'/; s/node.read('rU',encoding)/node.read('r',encoding)/" $W/waflib/ConfigSet.py $W/waflib/Context.py
rm -rf $W/waflib/__pycache__
# arm64: no -mfpu / -mfloat-abi (NEON is always on), tune for the Pi 4
sed -i "s/, '-mfpu=neon'\]/]/; /'-mfpu=neon-fp-armv8',/d; /'-mfloat-abi=hard',/d; s/cortex-a53/cortex-a72/g" \
  matron/wscript crone/wscript
# device_hid.c needs glib, which older systems pulled in through other packages
grep -q "glib-2.0" wscript || sed -i "/check_cfg(package='alsa'/ i\\    conf.check_cfg(package='glib-2.0', args=['--cflags', '--libs'], uselib_store='GLIB')" wscript
grep -q "'GLIB'" matron/wscript || sed -i "s/^        'JACK',\$/        'JACK',\n        'GLIB',/" matron/wscript
# liblo 0.32 has its own lo_message type
sed -i 's|^typedef void \*lo_message;$|#include <lo/lo.h>|' matron/src/event_types.h
# GCC 14 no longer includes <string> through other headers
grep -q "#include <string>" crone/src/BufDiskWorker.h || sed -i '0,/^#include/s//#include <string>\n#include/' crone/src/BufDiskWorker.h

./waf configure --release
./waf build -j4

mkdir -p ~/.local/share/SuperCollider/Extensions
(cd sc && ./install.sh)
# the first sclang run adds norns' class paths (Norns.initClass), they apply
# from the next run on; without this the first boot shows SUPERCOLLIDER FAIL
echo | QT_QPA_PLATFORM=offscreen timeout 120 sclang > /dev/null 2>&1 || true

# --- dust, maiden, version
mkdir -p ~/dust/code ~/dust/data ~/dust/audio/tape ~/bin
cp build/maiden-repl/maiden-repl ~/bin/
cd $SRC
if [ ! -d norns-update/${UPDATE#norns} ]; then
  mkdir -p norns-update && cd norns-update
  curl -sL https://github.com/monome/norns/releases/download/$NORNS_TAG/$UPDATE.tgz | tar xz
fi
U=$SRC/norns-update/${UPDATE#norns}
rm -rf ~/maiden
cp -a $U/maiden ~/maiden
# the package's maiden server is a 32-bit binary: build it for arm64
cd $SRC
[ -d maiden ] || git clone --branch $MAIDEN_TAG --depth 1 https://github.com/monome/maiden.git
(cd maiden && go build -o ~/maiden/maiden \
  -ldflags "-X github.com/monome/maiden/cmd.version=$MAIDEN_TAG -X github.com/monome/maiden/cmd.compileTime=$(date -u +%Y-%m-%dT%H:%M)")
(cd ~/maiden && ./project-setup.sh)
cp $U/version.txt $U/changelog.txt ~/
if [ ! -d ~/dust/audio/common ]; then
  curl -sL https://github.com/monome/norns/releases/download/v2.7.1/dust-audio-common.tgz | tar xz -C ~/dust/audio
fi

# --- sound card for jack: the CS4270 (monome-snd-4270 overlay)
CARD=sndrpimonome
if ! grep -q "\[$CARD" /proc/asound/cards; then
  echo "sound card $CARD not found (did you reboot after step 2?):"
  cat /proc/asound/cards
  exit 1
fi
# the CS4270 output starts muted; unmute it as the norns update does, and keep
# it (alsa-restore loads the stored state at boot)
amixer -c $CARD set Master 100% on > /dev/null
sudo alsactl store

# --- systemd (units from monome/norns-image)
U=/etc/systemd/system
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/10-default-env-vars.conf > /dev/null <<EOF
[Manager]
DefaultEnvironment="JACK_NO_START_SERVER=1"
EOF
sudo tee $U/norns-jack.service > /dev/null <<EOF
[Unit]
After=sound.target

[Service]
Type=simple
User=we
Group=we
Environment="JACK_NO_AUDIO_RESERVATION=1"
LimitRTPRIO=95
LimitMEMLOCK=infinity
ExecStart=/usr/bin/jackd -R -P 95 -d alsa -d hw:$CARD -r 48000 -n 3 -p 128 -S -s
ExecStartPost=/usr/bin/jack_wait -w -t 10
TimeoutStopSec=1

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns-crone.service > /dev/null <<EOF
[Unit]
After=norns-jack.service
Requires=norns-jack.service

[Service]
Type=simple
User=we
Group=we
LimitRTPRIO=95
LimitMEMLOCK=infinity
ExecStart=/home/we/norns/build/crone/crone

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns-sclang.service > /dev/null <<EOF
[Unit]
After=norns-jack.service
Requires=norns-jack.service

[Service]
Type=simple
User=we
Group=we
Environment="QT_QPA_PLATFORM=offscreen"
LimitRTPRIO=95
LimitMEMLOCK=infinity
ExecStart=/home/we/norns/build/ws-wrapper/ws-wrapper ws://*:5556 /usr/bin/sclang -i maiden

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns-matron.service > /dev/null <<EOF
[Unit]
After=norns-jack.service

[Service]
Type=simple
User=we
Group=we
ExecStart=/home/we/norns/build/ws-wrapper/ws-wrapper ws://*:5555 /home/we/norns/build/matron/matron

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns-maiden.socket > /dev/null <<EOF
[Unit]
Description=maiden socket

[Socket]
ListenStream=80
NoDelay=true
EOF
sudo tee $U/norns-maiden.service > /dev/null <<EOF
[Unit]
Requires=norns-maiden.socket

[Service]
Type=simple
User=we
Group=we
WorkingDirectory=/home/we/maiden
ExecStart=/home/we/maiden/maiden server --fd 3 --app ./app/build --data /home/we/dust --doc /home/we/norns/doc

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns-init.service > /dev/null <<EOF
[Unit]
Description=norns-init

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

[Install]
WantedBy=norns.target
EOF
sudo tee $U/norns.target > /dev/null <<EOF
[Unit]
Description=norns

Requires=sockets.target
Requires=sound.target

Requires=norns-jack.service
Requires=norns-crone.service
Requires=norns-sclang.service
Requires=norns-matron.service
Requires=norns-maiden.service
Wants=norns-init.service

AllowIsolate=yes

[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/security/limits.d/99-realtime.conf > /dev/null <<EOF
@audio - rtprio 95
@audio - memlock unlimited
EOF
sudo systemctl daemon-reload
sudo systemctl enable norns.target norns-jack norns-crone norns-sclang norns-matron norns-maiden.socket norns-maiden norns-init

# --- samba: dust as a network share (user we, password sleep)
if ! grep -q "^\[dust\]" /etc/samba/smb.conf; then
  sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF

[dust]
comment = dust
path = /home/we/dust
browseable = yes
read only = no
create mask = 0777
directory mask = 0777
guest ok = no
veto files = /._*/.DS_Store/
delete veto files = yes
EOF
fi
(echo sleep; echo sleep) | sudo smbpasswd -s -a we
sudo systemctl restart smbd
# nmbd (NetBIOS names) times out at boot and isn't needed: the share is found
# through mDNS (avahi) as norns.local
sudo systemctl disable --now nmbd

echo "step 3 done, reboot now"
