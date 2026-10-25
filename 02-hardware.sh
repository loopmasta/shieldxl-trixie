#!/bin/bash
# shieldXL (norns shield 210330, CS4270) on Raspberry Pi OS trixie (arm64),
# step 2: codec driver, overlays and boot config. Boot files live in
# /boot/firmware now; the screen needs no kernel driver (matron drives the
# SSD1322 over spidev0.0 itself). Reboot afterwards.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
BOOT=/boot/firmware

# --- CS4270 codec driver via DKMS (rebuilt automatically for new kernels)
KVER=$(uname -r)
BRANCH=rpi-$(echo $KVER | cut -d. -f1-2).y
D=/usr/src/snd-soc-cs4270-1.0
sudo mkdir -p $D
sudo cp $HERE/dkms/snd-soc-cs4270/{dkms.conf,Makefile} $D/
curl -sfL https://raw.githubusercontent.com/raspberrypi/linux/$BRANCH/sound/soc/codecs/cs4270.c | sudo tee $D/cs4270.c > /dev/null
sudo dkms status snd-soc-cs4270/1.0 -k $KVER | grep -q installed || sudo dkms install snd-soc-cs4270/1.0 -k $KVER

# --- overlays
for o in monome-snd-4270 norns-buttons-encoders; do
  sudo dtc -q -@ -I dts -O dtb -o $BOOT/overlays/$o.dtbo $HERE/overlays/$o.dts
done

sudo cp -n $BOOT/config.txt $BOOT/config.txt.orig
sudo cp -n $BOOT/cmdline.txt $BOOT/cmdline.txt.orig

# a kernel screen driver would take spidev0.0 away from matron
sudo sed -i '/^dtoverlay=fates-ssd1322/d; /^dtoverlay=ssd1322-spi/d' $BOOT/config.txt
sudo rm -f /etc/modprobe.d/norns-oled.conf
# onboard audio off, the CS4270 is the only card
sudo sed -i 's/^dtparam=audio=on/dtparam=audio=off/' $BOOT/config.txt
if ! grep -q "^# norns shield" $BOOT/config.txt; then
  sudo tee -a $BOOT/config.txt > /dev/null <<EOF

# norns shield
[all]
dtparam=spi=on
dtparam=i2c_arm=on
dtoverlay=monome-snd-4270
dtoverlay=norns-buttons-encoders
EOF
fi

# a whole screen (128 x 64 x 4 bit = 8 KB) in one SPI transfer
grep -q "spidev.bufsiz" $BOOT/cmdline.txt || sudo sed -i '1 s/$/ spidev.bufsiz=8192/' $BOOT/cmdline.txt

echo "step 2 done, reboot now"
