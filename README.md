# norns on a Raspberry Pi 4 with Raspberry Pi OS trixie (64-bit)

This guide installs [norns](https://monome.org/docs/norns/) **v2.9.4** on a **Raspberry Pi 4** running the current **Raspberry Pi OS Lite trixie (Debian 13, arm64, kernel 6.18)**. The hardware is a **norns shield 210330 type board**: here an [okyeron shieldXL](https://github.com/okyeron/shieldXL) with a CS4270 codec, an NHD-2.7-12864WDW3 OLED, 3 keys and 3 encoders.

The official shield disk images are based on old 32-bit Raspberry Pi OS releases. Guides from that era (e.g. the fates install instructions) no longer work on trixie, for these reasons:

- `fbtft_device` was removed from Linux in 5.4, so the old `modprobe fbtft_device …` display test fails.
- Boot files moved from `/boot` to `/boot/firmware`. `/boot/config.txt` is now just a note saying "DO NOT EDIT".
- `apt-key`, monome's stretch apt repo and the bionic PPA are gone. SuperCollider 3.9 packages don't exist for arm64.
- The Raspberry Pi kernel no longer builds the CS4270 codec driver.
- norns 2.9.4 doesn't build out of the box with Python 3.13, GCC 14, liblo 0.32 or on arm64.

The four scripts in this repository handle all of this. Everything is built from source or comes from Debian; no 32-bit packages are used.

> Status: tested on one shieldXL + Pi 4 (October 2026). Screen, keys, encoders, audio in and out, SuperCollider engines, softcut and maiden all work; checked with awake and smplr, and after a cold start. The scripts were refined while installing that one device, so a completely fresh run may still hit something. Please report back if it does.

---

## What you end up with

| Part | How |
|---|---|
| OS | Raspberry Pi OS Lite trixie, 64-bit, kernel 6.18 |
| norns | monome/norns **v2.9.4**, built from source with small compatibility patches |
| screen | matron drives the SSD1322 itself over `/dev/spidev0.0` (D/C GPIO 5, reset GPIO 6), so no kernel display driver is needed |
| keys / encoders | rewritten `norns-buttons-encoders` overlay (gpio-keys + rotary-encoder) |
| audio | rewritten `monome-snd-4270` overlay + CS4270 codec driver built as a DKMS module, card `sndrpimonome` |
| SuperCollider | 3.13 + sc3-plugins from Debian |
| JACK | jackd2 from Debian |
| libgpiod | 1.6.5 built into `/usr/local` (norns uses the v1 API; trixie only ships v2) |
| libmonome | v1.4.11, built from source |
| maiden | server v1.1.6 built from source for arm64 (Go from Debian); web app from the official norns 2.9.4 update package |
| file sharing | Samba share `dust` (user `we`, password `sleep`) |

### Pinout used (shieldXL / norns shield 210330)

| Function | GPIO |
|---|---|
| OLED D/C, reset | 5, 6 (SPI0 CE0) |
| CS4270 reset | 17 (I²C address 0x48) |
| E1 | 4, 27 |
| E2 | 12, 25 |
| E3 | 24, 23 |
| K1, K2, K3 | 22, 26, 13 |

If your shield uses other encoder or key pins, set them in `config.txt` with the overlay parameters (`dtparam=e1_pin_a=…`, `b1_pin=…`, see [`overlays/norns-buttons-encoders.dts`](overlays/norns-buttons-encoders.dts)).

---

## 1. Prepare the SD card

Use **Raspberry Pi Imager**:

1. Device: Raspberry Pi 4. OS: **Raspberry Pi OS Lite (64-bit)**, the trixie release.
2. In the OS customisation settings:
   - Hostname: `norns`
   - Username: `we`, password: `sleep` (as on a real norns)
   - Your Wi-Fi and Wi-Fi country
   - Enable SSH
3. Write the card, put it in the Pi and boot it.

Then log in and update:

```
ssh we@norns.local
sudo apt update && sudo apt full-upgrade -y
sudo raspi-config nonint do_spi 0
sudo raspi-config nonint do_i2c 0
sudo reboot
```

> You don't need to expand the filesystem: Raspberry Pi OS does that on its first boot (check with `df -h /`). The "expand filesystem" step in the shield docs is for the old fixed-size norns disk images.

> Don't follow the old fates / norns-linux-bits steps: no kernel build, no `fates_prepare_rpi4.sh`, no `fbtft`. They don't work on kernel 6.x, and the kernel build overwrites stock modules with mismatched ones.

## 2. Get the install files

```
sudo apt install -y git
git clone https://github.com/loopmasta/shieldxl-trixie.git ~/shieldxl-trixie
```

## 3. Run the scripts

```
cd ~/shieldxl-trixie
./01-packages.sh          # packages, libgpiod 1.6, libmonome   (~5 min)
./02-hardware.sh          # codec driver, overlays, boot config
sudo reboot
```

After the reboot, check the hardware before going on:

```
cat /proc/asound/cards           # 0 [sndrpimonome ]: simple-card - snd-rpi-monome
ls /dev/input/by-path/           # platform-keys-event, platform-soc:knob1/2/3-event
ls /dev/spidev0.0                # must exist (matron uses it for the screen)
```

Then:

```
cd ~/shieldxl-trixie
./03-norns.sh             # builds norns, installs maiden + services   (~5 min)
sudo reboot
```

After this reboot the norns menu should appear on the screen, and maiden is available at `http://norns.local`.

## 4. Check that everything runs, add the default scripts

```
systemctl is-active norns-jack norns-crone norns-sclang norns-matron norns-maiden
journalctl -u norns-sclang -n 30 --no-pager     # "SuperCollider 3 server ready", "/crone/ready"
jack_lsp | grep SuperCollider
```

Then install the default scripts (awake, firstlight):

```
~/shieldxl-trixie/04-scripts.sh
```

They show up under SELECT right away, no reboot needed. Install more scripts with `git clone` into `~/dust/code/`, through maiden, or copy them to the `dust` Samba share (`smb://norns.local/dust`, user `we`, password `sleep`).

---

## What each step does, and why

### Step 1: packages (`01-packages.sh`)

- **Passwordless sudo for `we`**, as on a norns. matron calls `sudo` for system actions such as restart, shutdown and Wi-Fi.
- **Debian packages:** jackd2 (with realtime limits enabled through debconf), `jack-example-tools` (provides `jack_wait`, which the JACK service needs), SuperCollider 3.13 + sc3-plugins, and the libraries norns builds against. Also `dkms` and the kernel headers for the codec driver, and Go for maiden.
- **libgpiod 1.6.5** from source into `/usr/local`: matron's screen and GPIO code uses the libgpiod v1 API (`gpiod_chip_open_by_name`, `gpiod_line_request_output`), and trixie only ships libgpiod 2.x, which removed it. Don't install `libgpiod-dev` from apt alongside.
- **libmonome v1.4.11** from source, because it isn't in Debian. The version is pinned (`LIBMONOME_TAG`) to the one this setup was tested with.

### Step 2: hardware (`02-hardware.sh`)

- **CS4270 codec driver.** The Raspberry Pi kernel has `CONFIG_SND_SOC_CS4270` disabled. The script fetches `sound/soc/codecs/cs4270.c` from the matching `raspberrypi/linux` branch and builds it as a DKMS module, so it is rebuilt automatically after every kernel update.
- **`monome-snd-4270` overlay** (from monome's 5.10 kernel fork), adapted:
  - The I²S controller is referenced as `&i2s_clk_consumer`, because the codec provides the clocks.
  - The codec reset (GPIO 17) is only claimed by the codec driver, as `reset-gpios`, active high. The old overlay also hogged the same pin, which 6.x refuses.
  - The card is still called `snd-rpi-monome`, so ALSA names it `sndrpimonome`, like on a norns.
- **`norns-buttons-encoders` overlay**, adapted: the pin groups target `&gpio` instead of `"/soc/gpio"` (that path doesn't exist on 6.x; the node is `gpio@7e200000`). The shieldXL pins are the defaults, and the old `dtparam` overrides still work.
- **`config.txt`** (in `/boot/firmware`):
  - Onboard audio is turned off.
  - SPI and I²C are enabled and both overlays are added.
  - Any old kernel screen overlay (`ssd1322-spi`, `fates-ssd1322`) is removed. It would take `spidev0.0` away from matron.
- **`cmdline.txt`:** adds `spidev.bufsiz=8192`, so a whole screen (128 × 64 × 4 bit = 8 KB) fits in one SPI transfer, as the official norns update does.
- Backups of both files are kept as `config.txt.orig` / `cmdline.txt.orig`.

### Step 3: norns (`03-norns.sh`)

Clones **monome/norns v2.9.4** with its submodules and applies these patches. Each one only applies once, so the script can be run again.

| Problem on trixie / arm64 | Fix |
|---|---|
| waf 2.0.14 imports `imp` (removed in Python 3.12) | `imp.new_module` → `types.ModuleType` in `waflib/Context.py` |
| waf opens files with mode `'rU'` (removed in Python 3.11) | `'rU'` → `'r'` in `Context.py`, `ConfigSet.py` |
| `-mfpu=neon`, `-mfloat-abi=hard` don't exist on arm64 | removed (NEON is always on); `-mcpu`/`-mtune` set to `cortex-a72` (Pi 4) |
| `device_hid.c` needs `glib.h`, which older systems pulled in through other packages | added `glib-2.0` as a pkg-config dependency for matron |
| liblo 0.32 defines `lo_message` as a struct pointer, which conflicts with norns' `typedef void *lo_message` | replaced the typedef with `#include <lo/lo.h>` |
| GCC 14 no longer includes `<string>` through other headers | added `#include <string>` to `crone/src/BufDiskWorker.h` |

Then the script:

- Builds norns (`./waf configure --release && ./waf build`) and installs norns' SuperCollider class config.
- Runs `sclang` once. The first run only registers norns' class paths, and they apply from the next run on. Without this, the first boot shows **SUPERCOLLIDER FAIL**.
- Creates `~/dust`, downloads the official 2.9.4 update package and takes **maiden's web app** and `version.txt` from it. Downloads the common audio files.
- Builds the **maiden server** (monome/maiden v1.1.6, the version in that package) for arm64 with `go build`. The package's server is a 32-bit ARM binary; it would run, but this way everything is native.
- **Sets the CS4270 output to full volume** (`amixer -c sndrpimonome set Master 100% on`, then `alsactl store`), as the official norns update does.
- **Unmutes the CS4270 output each time JACK starts** (`ExecStartPost=… amixer … set Master on` in `norns-jack.service`). The codec's `Master Playback Switch` is off whenever no audio stream is open, because the driver mutes the DAC then. At shutdown JACK is already stopped, so ALSA saves "off" and restores it at the next boot: the level meters move, but nothing is audible. Storing "on" once isn't enough.
- Installs the systemd units from monome/norns-image, adapted:
  - JACK uses `hw:sndrpimonome`.
  - sclang runs with `QT_QPA_PLATFORM=offscreen` (Debian's sclang is built with Qt).
  - `norns-init` sets the CPU governor to performance.
  - `@audio` realtime limits are set.
- Sets `RemoveIPC=no` for systemd-logind. By default logind deletes a user's files in `/dev/shm` when their last login session ends, so after an SSH logout JACK's socket is gone. Audio keeps running, but restarting crone, sclang or matron (e.g. SYSTEM > RESTART) then fails with "jack server is not running".
- Sets up the Samba `dust` share and turns off `nmbd` (Samba's NetBIOS name service). It times out at boot and isn't needed, because the share is reached as `smb://norns.local` through mDNS.

No `matronrc.lua` is needed: norns' default already matches the shield (keys + 3 encoders, screen built in).

### Step 4: default scripts (`04-scripts.sh`)

Installs **awake** (`tehn/awake`, the script a new norns starts with) and **firstlight** (from monome's base collection in maiden). Each script is cloned with git into `~/dust/code`, as maiden does, so maiden can update it later. Scripts that are already there are skipped.

---

## Important notes

- **Never use SYSTEM > UPDATE in the norns menu.** It installs the official 32-bit build and replaces your patched arm64 binaries. To update norns, change `NORNS_TAG` (and `UPDATE`, the matching update package name from the release page, and `MAIDEN_TAG`, the maiden version it contains) in `03-norns.sh`, delete `~/norns` and `~/src/maiden` and run `03-norns.sh` again.
- **Kernel updates** (`apt full-upgrade`) are fine: DKMS rebuilds the codec driver automatically. If sound is missing after an update, check `sudo dkms status`.
- **Four encoders** (as on some fates boards) aren't supported by stock norns. The Lua code only knows E1–E3.
- **Hardware MIDI on the shieldXL** (`install-midi.sh` from the shieldXL repo) isn't covered here. That script installs a 32-bit `amidiminder` package and needs adapting for arm64.
- **Other shields:** the norns shield 211028+ uses a different codec, the CS4271 (overlay `monome-snd-4271` in monome's kernel fork). The Pi kernel does include a CS4271 driver, but that overlay isn't covered here.
- **fates boards** use different pins (OLED D/C 17, reset 4, encoder 1 on 5/6) and a WM8731 codec (overlay `proto-codec` on current kernels). The same approach works, but with a pin patch in `ssd1322.h` and different overlays.

## Troubleshooting

| Symptom | Check |
|---|---|
| no `sndrpimonome` card | `sudo dmesg \| grep -i cs4270` (should say "found device at i2c address 48"); `sudo dkms status`; `i2cdetect -y 1` should show `48` (or `UU`) |
| meters move, but no sound | output muted: `amixer -c sndrpimonome contents` shows `Master Playback Switch` off → `amixer -c sndrpimonome set Master 100% on`. If it is off again after every reboot, `norns-jack.service` is missing the `ExecStartPost=… amixer … set Master on` line: run `03-norns.sh` again |
| norns-jack fails | `journalctl -u norns-jack` — `jack_wait` missing → `sudo apt install jack-example-tools` |
| SUPERCOLLIDER FAIL | `journalctl -u norns-sclang`; restart the services once: `sudo systemctl restart norns-jack norns-crone norns-sclang norns-matron` (restarting `norns.target` alone doesn't restart them) |
| crone / sclang / matron fail to restart with "jack server is not running", but `norns-jack` is active | JACK's socket in `/dev/shm` was deleted by logind after an SSH logout. Check `/etc/systemd/logind.conf.d/10-norns.conf` contains `RemoveIPC=no`, then `sudo systemctl restart norns-jack norns-crone norns-sclang norns-matron` |
| black screen | `ls /dev/spidev0.0`; no screen overlay in `config.txt`; `spidev.bufsiz=8192` in `cmdline.txt`; `pinctrl get 5,6` should show outputs while matron runs |
| `setlocale: LC_ALL: cannot change locale (en_US.UTF-8)` on every SSH login | harmless: your computer's SSH client sends its locale and the Pi doesn't have it. Generate it: `sudo sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && sudo locale-gen` |
| keys / encoders dead | `ls /dev/input/by-path/` must list `platform-keys-event` and `platform-soc:knob1-event` … `knob3-event`; `sudo evtest` to see events |

---

*Based on monome's [norns](https://github.com/monome/norns) and [norns-image](https://github.com/monome/norns-image), the overlays from monome's [linux fork](https://github.com/monome/linux), and okyeron's [shieldXL](https://github.com/okyeron/shieldXL). Not supported by monome; please don't ask them for help with this setup.*

## License

GPL-2.0, see [LICENSE](LICENSE). The overlays are derived from monome's Linux kernel fork, which is GPL-2.0.
