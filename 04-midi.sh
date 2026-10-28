#!/bin/bash
# shieldXL (norns shield 210330, CS4270) on Raspberry Pi OS trixie (arm64),
# step 4 (optional): hardware MIDI on the shieldXL's TRS jacks, after
# okyeron's install-midi.sh. The jacks are wired to UART0 (GPIO 14/15);
# ttymidi turns the serial port into an ALSA MIDI client ("shieldXL") and a
# small service connects it to matron's virtual MIDI port, which shows up as
# "virtual" in SYSTEM > DEVICES > MIDI. Reboot afterwards.
set -e
BOOT=/boot/firmware
TTYMIDI_COMMIT=06f18e0f4a8f09bb13130fba2295c2a3c534c03c

# --- UART0 on GPIO 14/15 at MIDI speed, Bluetooth moves to the mini UART
sudo cp -n $BOOT/config.txt $BOOT/config.txt.orig
sudo cp -n $BOOT/cmdline.txt $BOOT/cmdline.txt.orig
if ! grep -q "^# shieldXL MIDI" $BOOT/config.txt; then
  sudo tee -a $BOOT/config.txt > /dev/null <<EOF

# shieldXL MIDI
[all]
enable_uart=1
dtoverlay=miniuart-bt
dtoverlay=uart0
dtoverlay=midi-uart0
EOF
fi
# no serial console on the MIDI port
sudo sed -i 's/console=serial0,[0-9]* //' $BOOT/cmdline.txt

# --- ttymidi (okyeron's fork), a single C file
T=$(mktemp -d)
git clone -q https://github.com/okyeron/ttymidi $T/ttymidi
git -C $T/ttymidi checkout -q $TTYMIDI_COMMIT
gcc -O2 $T/ttymidi/src/ttymidi.c -o $T/ttymidi/ttymidi -lasound -lpthread
sudo install -m 755 $T/ttymidi/ttymidi /usr/local/bin/ttymidi
rm -rf $T

# midi-uart0 turns the requested 38400 baud into MIDI's 31250
sudo tee /etc/systemd/system/ttymidi.service > /dev/null <<EOF
[Unit]
Description=shieldXL TRS MIDI (ttymidi on ttyAMA0)
After=sound.target

[Service]
User=we
ExecStart=/usr/local/bin/ttymidi -s /dev/ttyAMA0 -b 38400 -n shieldXL -q
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

# --- keep shieldXL connected to matron's virtual port (replaces amidiminder,
# which has no arm64 package). matron opens the virtual device twice and only
# uses the second client, so connect to its highest-numbered client. The
# client numbers change when matron or ttymidi restart: reconnect then.
sudo tee /usr/local/bin/norns-midi-connect > /dev/null <<'EOF'
#!/bin/sh
last=
while sleep 2; do
  mpid=$(pidof matron) || { last=; continue; }
  list=$(aconnect -l)
  s=$(echo "$list" | sed -n "s/^client \([0-9]*\): 'shieldXL'.*pid=\([0-9]*\).*/\1 \2/p")
  v=$(echo "$list" | sed -n "s/^client \([0-9]*\): 'Client-[0-9]*' .*pid=$mpid\].*/\1/p" | tail -1)
  [ -n "$s" ] && [ -n "$v" ] || { last=; continue; }
  [ "$s $v $mpid" = "$last" ] && continue
  c=${s% *}
  aconnect $c:0 $v:0 2>/dev/null || true
  aconnect $v:0 $c:1 2>/dev/null || true
  last="$s $v $mpid"
done
EOF
sudo chmod 755 /usr/local/bin/norns-midi-connect

sudo tee /etc/systemd/system/norns-midi-connect.service > /dev/null <<EOF
[Unit]
Description=connect shieldXL TRS MIDI to norns
After=ttymidi.service

[Service]
User=we
ExecStart=/usr/local/bin/norns-midi-connect
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ttymidi norns-midi-connect

echo "step 4 done, reboot now"
