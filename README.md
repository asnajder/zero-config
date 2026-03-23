# Mainline Sovol Zero (Klipper, Armbian Trixie)

Special thanks to Leoboi420, Teapot-Apple, matt73210, Atomique13, J&B, jedi 2^10, wildBill, Rappetor, vvuk, and everyone else who shared information and testing results.

## Overview

- This guide walks through installing and configuring a Sovol Zero on Armbian Trixie with Klipper, Moonraker, Mainsail, and Crowsnest.
- It covers CAN bus setup, flashing mainboard/toolhead/chamber boards, Eddy probe calibration, and post-install tuning.
- It assumes you are comfortable with Linux commands, systemd services, and basic electrical safety.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Safety and Warnings](#safety-and-warnings)
- [Initial Setup](#initial-setup)
- [Install Core Software](#install-core-software)
- [Set Up CAN](#set-up-can)
- [Firmware Binaries](#firmware-binaries)
- [Build and Flash Mainboard](#build-and-flash-mainboard)
- [Build and Flash Toolhead and Chamber](#build-and-flash-toolhead-and-chamber)
- [If Something Goes Wrong](#if-something-goes-wrong)
- [Finishing Up](#finishing-up)
- [Updater Script](#updater-script)

---

## Prerequisites

- 32GB eMMC (the stock Sovol 8GB eMMC will NOT work)
- eMMC reader
- Armbian Imager on a PC
- USB keyboard + HDMI monitor (or SSH over Ethernet)
- ST-LINK and basic STM32 flashing knowledge
- Backup of your existing Klipper configs, Moonraker database, G-code files, and timelapses

## Safety and Warnings

- Power off and unplug the printer before touching electronics or swapping eMMC modules.
- A mistake during this processes can brick your printer. Keep an ST-LINK available before you begin.

---

## Initial Setup

1. Back up your stock eMMC and any current configs/data.

2. Flash Armbian to the 32GB eMMC using Armbian Imager:
   - Manufacturer: `BTT (BIQU)`
   - Board: `BigTreeTech CB1`
   - Image: `Minimal -> Armbian <release date> Trixie CLI`
   - Then run erase + flash.

3. On the newly flashed eMMC boot partition, edit `/boot/armbianEnv.txt`.
   - First copy your new `rootdev=UUID=...` line (example: `rootdev=UUID=938afde5-6689-4a1a-a044-680f6247d523`).
   - Replace the rest with:

```ini
verbosity=1
bootlogo=false
console=both
disp_mode=1920x1080p60
overlay_prefix=sun50i-h616
fdtfile=sun50i-h616-bigtreetech-cb1-emmc.dtb
rootdev=UUID=YOUR_COPIED_UUID_HERE
rootfstype=ext4
overlays=sun50i-h6-uart3 sun50i-h616-ws2812 sun50i-h616-spidev1_1
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
```

You can also expand the partition now if you have another Linux host:

```bash
sudo fdisk /dev/<device>
# then: e, 2, <enter>, w
```

If you skip this, first boot should expand it.

Note for macOS users: you will need a VM and pass the eMMC through to access its filesystem after flashing. UTM + a simple Linux VM (for example Debian XFCE) works well.

4. Boot the printer and complete first login.
   - Option A: Ethernet + SSH (`root` / `1234` on first login).
   - Option B: Keyboard + HDMI monitor directly on the printer.

If you plan to use Wi-Fi, do not configure it during first-login prompts. Choose `N`, then set it later with:

```bash
sudo armbian-config
```

5. Mask network wait-online to avoid boot delays (reference: [Rappetor issue comment](https://github.com/Rappetor/Sovol-SV08-Mainline/issues/229#issuecomment-3765616568)):

```bash
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service
```

6. Install base tools:

```bash
sudo apt install git python3-pip -y
```

7. Clone and run KIAUH:

```bash
git clone https://github.com/dw-0/kiauh.git
./kiauh/kiauh.sh
```

Credit for parts of this setup flow:
- [ljg-dev](https://github.com/ljg-dev/sovol-sv08-mainline/tree/main)

---

## Install Core Software

1. In KIAUH, install:
   - Klipper
   - Moonraker
   - Mainsail
   - Crowsnest

Then reboot.

Optional in KIAUH: `Advanced -> Extra Dependencies -> Input Shaper`

Install additional dependencies:

```bash
sudo apt install python3-serial -y
~/klippy-env/bin/pip install scipy
```

(`scipy` is needed for Eddy probe workflows.)

2. Install `moonraker-timelapse`:

```bash
cd ~/
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
cd ~/moonraker-timelapse
make install
```

Add the output snippet from the installer to `moonraker.conf`.

In Orca (or your slicer), add `TIMELAPSE_TAKE_FRAME` to:

```text
Printer settings -> Machine G-Code -> Before layer change G-code
```

3. Install Katapult:

```bash
cd ~ && git clone https://github.com/Arksine/katapult
```

4. Reboot once more:

```bash
sudo reboot now
```

---

## Set Up CAN

1. Confirm `systemd-networkd` is active:

```bash
systemctl | grep systemd-networkd
```

If not active:

```bash
sudo systemctl enable systemd-networkd
sudo systemctl start systemd-networkd
sudo systemctl disable systemd-networkd-wait-online.service
```

2. Set `tx_queue_len` for CAN interfaces:

```bash
echo -e 'SUBSYSTEM=="net", ACTION=="change|add", KERNEL=="can*" ATTR{tx_queue_len}="128"' | sudo tee /etc/udev/rules.d/10-can.rules > /dev/null
```

Verify:

```bash
cat /etc/udev/rules.d/10-can.rules
```

Expected:

```text
SUBSYSTEM=="net", ACTION=="change|add", KERNEL=="can*" ATTR{tx_queue_len}="128"
```

3. Configure CAN bitrate:

```bash
echo -e "[Match]\nName=can*\n\n[CAN]\nBitRate=1M\n\n[Link]\nRequiredForOnline=no" | sudo tee /etc/systemd/network/25-can.network > /dev/null
```

Verify:

```bash
cat /etc/systemd/network/25-can.network
```

Expected:

```ini
[Match]
Name=can*

[CAN]
BitRate=1M

[Link]
RequiredForOnline=no
```

4. Reboot:

```bash
sudo reboot now
```

5. Upload your `printer.cfg`, then comment out all MCU sections (`mcu`, `extruder_mcu`, `hot_mcu`) and reboot.

This ensures clean CAN UUID detection before flashing.

Notes:
- Sovol uses fixed UUID mappings for mainboard/toolhead/chamber in stock firmware.
- UUIDs change after flashing.

6. Query devices and save the output:

```bash
sudo service klipper stop
python3 ~/katapult/scripts/flashtool.py -i can0 -q
```

Example output with chamber heater installed:

```text
Resetting all bootloader node IDs...
Checking for Katapult nodes...
Detected UUID: 0d1445047cdd, Application: Klipper
Detected UUID: 58a72bb93aa4, Application: Klipper
Detected UUID: 61755fe321ac, Application: Klipper
CANBus UUID Query Complete
```

If you do not see your devices, revisit the CAN setup and power-cycle sequence.

---

## Firmware Binaries

Prebuilt binaries are in [bins](./bins) if you do not want to build your own.

Katapult:
- `Deployer_Zero_Host_<H743>_128kb.bin` is for flashing over the stock Sovol bootloader via `flashtool.py`.
- Do not use the deployer as standalone firmware or with ST-LINK.
- After deployer flash, immediately flash Klipper firmware.
- `Katapult_Zero_Host_H743_128kb.bin` is intended for ST-LINK flashing.

Klipper:
- Host, toolhead and chamber Klipper binaries can be flashed via `flashtool.py`.
- You can also build your own using the menuconfig values below.

## Build and Flash Mainboard

Sovol's bootloader uses a 128 KiB offset. Through testing, the MCU appears to behave like an STM32H743-class part (2 MB flash behavior), not a strict H750 configuration.

Method A: Prebuilt bins

You can either:
- Flash `Katapult_Zero_Host_H743_128kb.bin` with ST-LINK, or
- Flash `Deployer_Zero_Host_H743_128kb.bin` via `flashtool.py`.

Example deployer flash command (replace UUID):

```bash
~/katapult/scripts/flashtool.py -f Deployer_Zero_Host_H743_128kb.bin -u <HOST_UUID>
```

Then flash Klipper to host:

```bash
~/katapult/scripts/flashtool.py -f Klipper_Zero_Host_H743_128kb.bin -d /dev/ttyACM0
```

Method B: Build from source

Credit for board-level details:
- [Vlad (vvuk)](https://github.com/vvuk/printer-configs/wiki/Kalico-on-the-Sovol-Zero)

Mainboard Katapult `make menuconfig` reference:

```text
STM32H743
25 MHz clock
8KiB Application offset
USB on PA11/PA12 [Katapult]
Balanced Speed/Size (-O2) [Katapult]
GPIO pins to set at micro-controller startup: !PE11,!PB0
```

`!PE11,!PB0` keeps aux/exhaust fans from blasting at full speed before Klipper takes control.

Build and flash steps:

1. Build firmware:

```bash
cd ~/katapult
make menuconfig
make clean
make -j4
```

Output: `~/katapult/out/katapult.bin`

2. Find current UUIDs:

```bash
sudo service klipper stop
~/katapult/scripts/flashtool.py -q
```

3. Flash mainboard (replace UUID):

```bash
~/katapult/scripts/flashtool.py -f ~/katapult/out/katapult.bin -u <MAINBOARD_UUID>
```

4. Query again and record the changed UUID (this is your new mainboard UUID):

```bash
~/katapult/scripts/flashtool.py -q
```

Mainboard Klipper `make menuconfig` reference:

```text
STM32H743
25 MHz crystal clock
8KiB Application offset
USB to CAN bus bridge (USB on PA11/PA12) [Klipper]
CAN bus on PB8/PB9 [Klipper]
GPIO pins to set at micro-controller startup: !PE11,!PB0
```

`!PE11,!PB0` keeps aux/exhaust fans from blasting at full speed before Klipper takes control.

Build and flash steps:

1. Build firmware:

```bash
cd ~/klipper
make menuconfig
make clean
make -j4
```

Output: `~/klipper/out/klipper.bin`

2. Find current UUIDs:

```bash
sudo service klipper stop
~/katapult/scripts/flashtool.py -q
```

3. Flash mainboard (replace UUID):

```bash
~/katapult/scripts/flashtool.py -f ~/klipper/out/klipper.bin -u <MAINBOARD_UUID>
```

4. Query again and record the changed UUID (this is your new mainboard UUID):

```bash
~/katapult/scripts/flashtool.py -q
```

> [!IMPORTANT]
> Continue to **Build and Flash Toolhead and Chamber** next.

## Build and Flash Toolhead and Chamber

Toolhead and chamber heater use the same firmware settings, and those settings are different from the mainboard.

Credit:
- [Vlad (vvuk)](https://github.com/vvuk/printer-configs/wiki/Kalico-on-the-Sovol-Zero)

Toolhead/chamber Katapult `make menuconfig` reference:

```text
STM32F103
8 MHz clock
8KiB Application offset
CAN bus on PB8/PB9
Balanced Speed/Size (-O2) [Katapult]
```

Build and flash steps:

1. Build firmware:

```bash
cd ~/katapult
make menuconfig
make clean
make -j4
```

Output: `~/katapult/out/katapult.bin`

2. Query UUIDs, then flash one board at a time (replace UUID each time):

```bash
sudo service klipper stop
~/katapult/scripts/flashtool.py -q
~/katapult/scripts/flashtool.py -f ~/katapult/out/katapult.bin -u <TOOLHEAD_OR_CHAMBER_UUID>
~/katapult/scripts/flashtool.py -q
```

After each flash, the UUID that changes is the one you just flashed.

If you lose track:
- Power off.
- Unplug toolhead CAN.
- Boot and query (remaining new UUID is chamber).
- Power off, reconnect toolhead CAN, boot and query again (newly appearing UUID is toolhead).

3. Start Klipper:

```bash
sudo service klipper start
```

Toolhead/chamber Klipper `make menuconfig` reference:

```text
STM32F103
8 MHz clock
8KiB Application offset
CAN bus on PB8/PB9
```

Build and flash steps:

1. Build firmware:

```bash
cd ~/klipper
make menuconfig
make clean
make -j4
```

Output: `~/klipper/out/klipper.bin`

2. Query UUIDs, then flash one board at a time (replace UUID each time):

```bash
sudo service klipper stop
~/katapult/scripts/flashtool.py -q
~/katapult/scripts/flashtool.py -f ~/klipper/out/klipper.bin -u <TOOLHEAD_OR_CHAMBER_UUID>
~/katapult/scripts/flashtool.py -q
```

After each flash, the UUID that changes is the one you just flashed.

If you lose track:
- Power off.
- Unplug toolhead CAN.
- Boot and query (remaining new UUID is chamber).
- Power off, reconnect toolhead CAN, boot and query again (newly appearing UUID is toolhead).

3. Start Klipper:

```bash
sudo service klipper start
```

Credit for CAN flashing workflow:
- [Esoterical - Getting Started](https://canbus.esoterical.online/Getting_Started.html)
- [Esoterical - Toolhead Flashing](https://canbus.esoterical.online/toolhead_flashing.html)

---

## If Something Goes Wrong

Recovery files are available in [recovery](./recovery). These can be flashed with ST-LINK to return to Sovol firmware.



### Mainboard pinout ↓

<img src="./Mainboard_pinout.png" alt="Mainboard pinout" width="500" style="border: 2px solid #999; border-radius: 6px;" />



### Toolhead pinout ↓

<img src="./Toolhead_pinout.png" alt="Toolhead pinout" width="500" style="border: 2px solid #999; border-radius: 6px;" />



### Chamber pinout ↓

<img src="./Chamber_pinout.png" alt="Chamber pinout" width="500" style="border: 2px solid #999; border-radius: 6px;" />

Also reference [Rappetor's guide (Step 6/Step 7)](https://github.com/Rappetor/Sovol-SV08-Mainline?tab=readme-ov-file#step-6---stock-firmware-backup) 

---

## Finishing Up

0. Use the configs in this repo as a baseline, or edit your own.

If you start from stock Sovol configs, expect to remove unsupported sections one by one until Klipper starts cleanly.

Recommended minimum starting point:
- `printer.cfg`
- Eddy config
- Basic macros

Avoid old Sovol probe files like:
- `klippy/extras/probe_eddy_current.py`
- `klippy/extras/probe.py`

Use standard Klipper Eddy setup instead.

1. Update every `canbus_uuid` in your configs with your new UUIDs, then save/restart.

2. Re-add webcam settings if needed. Example: in `crowsnest.conf`, set device to `/dev/video1`, then add webcam in Mainsail.

3. Remove duplicate `[virtual_sdcard]` location entries if one is already defined in `mainsail.cfg`.

4. If using this repo's `macros.cfg` START_PRINT/END_PRINT approach (credit: https://github.com/jontek2/A-better-print_start-macro/blob/main/README.md), update slicer machine G-code.

In Orca:

```text
Printer settings -> Machine G-Code -> Machine Start G-code
```

Use:

```gcode
M104 S0 ; prevent Orca from sending separate temperature waits
M140 S0
START_PRINT EXTRUDER=[first_layer_temperature] BED=[first_layer_bed_temperature] CHAMBER=[chamber_temperature] MATERIAL=[filament_type]
```

Keep machine end G-code as:

```gcode
END_PRINT
```

5. Calibrate Eddy.

Calibrate at the bed temperature you normally print at. The bed must be heated, never calibrate on a cold bed. (For example, if you print ASA, calibrate at around 90 °C or more)

General reference (only use as a guide, do not edit `ldc1612.py`, but general steps are similar):
[asnajder/sv08-config README](https://github.com/asnajder/sv08-config/blob/main/README.md)

Use this repo's `sovol_eddy.cfg` as a baseline and keep software I2C enabled (hardware I2C does not work reliably in this setup).

Short-form calibration flow:

```gcode
# Home printer (Z may fail initially, this is expected)
SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
# Move to a safe manual height if needed
LDC_CALIBRATE_DRIVE_CURRENT CHIP=my_eddy_probe
# SAVE_CONFIG after current is found (mine was 16)
# Reboot, then:
SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
PROBE_EDDY_CURRENT_CALIBRATE CHIP=my_eddy_probe
# Then do paper test and finalize
```

Keep coordinates within Sovol Zero bed bounds.

If you hit:

```text
I2C request to addr 42 reports error START_NACK
```

Try adding `Nice=-10` to Klipper service and restart:

```bash
sudo nano /etc/systemd/system/klipper.service
```

Then restart Klipper and/or the system.

> [!IMPORTANT]
> Eddy calibration note
>
> If `reg_drive_current` is `15`, you may need `16`.
> At `15`, you may see: `Error during homing probe: Trigger analog error: RAW_RANGE`.
>
> If you change to `16`, run:
>
> ```gcode
> SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
> PROBE_EDDY_CURRENT_CALIBRATE CHIP=my_eddy_probe
> ```
>
> Then redo paper test and set `tap_threshold` again.
>
> Do not home after only changing `reg_drive_current` without recalibrating first, or the toolhead can crash into the bed.

6. Run final tuning (`PID`, `SHAPER_CALIBRATE`, etc.).

7. Add the fan back to your display (add this in printer.cfg):
```
[display_data _default_16x4 fan_generic]
position: 0, 10
text: { render("_fan_speed") }

[display_template _fan_speed]
text:
  {% if 'fan_generic fan0' in printer %}
    {% set speed = printer["fan_generic fan0"].speed %}
    {% if speed %}
      {% set frame = (printer.toolhead.estimated_print_time|int % 2) + 1 %}
      ~fan{frame}~
    {% else %}
      ~fan1~
    {% endif %}
    { "{:>4.0%}".format(speed) }
  {% endif %}
  ```

8. Fix knob direction on display: 
Under `[display]`, change `encoder_pins: ^EXP2_5, ^EXP2_3` to `encoder_pins: ^EXP2_3, ^EXP2_5`  
9. Print.

## Updater Script

This can be used to update the MCUs automatically in the future.

1. Download the updater [script](./update_klipper_mcus_svzero.sh).

2. Upload `update_klipper_mcus_svzero.sh` to your printer home directory (`cd ~/`).

3. Make it executable:

```bash
chmod +x ~/update_klipper_mcus_svzero.sh
```

4. Edit the script and set the UUID values for HOST, TOOLHEAD, and CHAMBER (if installed).

5. Run the script:

```bash
~/update_klipper_mcus_svzero.sh
```

Use the same `make menuconfig` values referenced in this guide when prompted.
