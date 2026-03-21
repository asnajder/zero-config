# Mainline Sovol Zero (Klipper, Armbian Trixie)

Special thanks to: Leoboi420, Teapot-Apple, matt73210, Atomique13, J&B ,jedi 2^10, wildBill, Rappetor, vvuk and others of the discord coming together to share information!

## Overview

- This guide installs and configures Sovol Zero on Armbian Trixie with Klipper, Moonraker, Mainsail, and Crowsnest.
- Covers CAN bus setup, flashing mainboard/toolhead/chamber, eddy probe calibration, and post-install tuning.
- Assumes you are comfortable with Linux shell commands, systemd services, and basic electrical safety.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Safety & Warnings](#safety--warnings)
- [Initial Setup](#initial-setup)
- [Installing Stuff](#installing-stuff)
- [Set up CAN](#set-up-can)
- [Multiple Ways to Flash Mainboard](#multiple-ways-to-flash-mainboard)
- [Make Klipper Configs for Toolhead and Chamber Heater](#make-klipper-configs-for-toolhead-and-chamber-heater)
- [If something goes wrong](#if-something-goes-wrong)
- [Finishing Up](#finishing-up)

---

## Prerequisites

- 32GB eMMC (stock Sovol 8GB will NOT work).
- eMMC reader
- Armbian Imager on PC.
- USB keyboard + HDMI monitor (or SSH over Ethernet).
- ST-LINK and basic knowledge of flashing STM32.
- Backup of any existing Klipper configs, Moonraker database, G-code files, and timelapses.

## Safety & Warnings

- Power off and unplug the printer before touching electronics or swapping the eMMCs
- Most things in here can and will brick your printer if you don’t follow this thoroughly, so having an ST-LINK is mandatory (or took the risks, lmao).

---

## Initial Setup

1. Backup your  and old stock emmc  
2. Download Armbian Imager, insert your 32GB eMMC into the eMMC reader (note that Sovol stock 8GB eMMC will NOT work), Select BTT (BIQU) Manufacturer, Select BigTreeTech CB1 Board, Select Minimal tab, then Armbian <release date> Trixie cli, then Erase and Flash  
3. On the newly flashed eMMC, boot partition,  edit /boot/armbianEnv.txt, COPY your `rootdev=UUID=` (for example, save this line: `rootdev=UUID=938afde5-6689-4a1a-a044-680f6247d523` NOTE that your UUID will be unique to you, and you are copying the NEW UUID, not the old eMMc UUID!) then replace everything else with:  
```
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

You can fix the partition size now if you have access to another linux host:  
`sudo fdisk /dev/<device> then e, 2, <enter>, w`  

If not, I it will do it on first boot.  

**Note:** On Mac you’ll need a VM and to share the EMMC drive to it after flashing- you just need this VM to access the file system on your EMMC, so you can use UTM and pick an easy to setup / use Linux VM (Matt suggested: Debian 11 xfce or something easy)

4. You can either use an Ethernet cable and then SSH in (if it asks, default user is `root` / password `1234`), or connect a keyboard to the printer, and an HDMI from printer to a monitor, then follow the first login steps. Note that if you're going to be using wifi, DO NOT configure it here when it asks. Select `N` and just configure it later with `armbian-config`. My installs (on here and my SV08) just froze at this step.  
You can run `sudo armbian-config` and under network you can add your wifi.  

5. Mask networkd to avoid boot delays (https://github.com/Rappetor/Sovol-SV08-Mainline/issues/229#issuecomment-3765616568):  
```
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service  
```  

6. Install Git:  
`sudo apt install git python3-pip -y`  

7. Clone and run KIAUH  
```
git clone https://github.com/dw-0/kiauh.git
./kiauh/kiauh.sh
```  

CREDIT FOR THIS SECTION:  
ljg-dev (https://github.com/ljg-dev/sovol-sv08-mainline/tree/main)  

---

## Installing Stuff 

1. Via KIAUH, install Klipper, Moonraker, Mainsail, and Crowsnest  

- Reboot after Crowsnest
- Optionally install `KIAUH main menu -> Advanced -> Extra Dependencies -> [Input Shaper]`
- Install dependencies:
  - `sudo apt install python3-serial -y`
  - `~/klippy-env/bin/pip install scipy` (needed for eddy probe)

2. Install moonraker-timelapse:
  
```
cd ~/
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
cd ~/moonraker-timelapse
make install
```  

Add what it outputs at the end to your `moonraker.conf`  

In Orca (or your preferred slicer) add `TIMELAPSE_TAKE_FRAME` to:  
```
-> Printer settings
-> Machine G-Code
-> 'Before layer change G-code'
```  
(I had some other stuff there, I removed it and just kept the above)  

3. Install Katapult:  
`cd ~ && git clone https://github.com/Arksine/katapult`  

4. If you haven't already, maybe a good idea to reboot here:  
`sudo reboot now`  

---

## Set up CAN

1. It should be, but check that this service is "loaded active running"
`systemctl | grep systemd-networkd`

If not, `sudo systemctl enable systemd-networkd`, then `sudo systemctl start systemd-networkd`, then `sudo systemctl disable systemd-networkd-wait-online.service` then check again that it is running  

2. Configure the txqueuelen for can0:
```
echo -e 'SUBSYSTEM=="net", ACTION=="change|add", KERNEL=="can*"  ATTR{tx_queue_len}="128"' | sudo tee /etc/udev/rules.d/10-can.rules > /dev/null
```  

Check it with:  
`cat /etc/udev/rules.d/10-can.rules`, should see:  
```
SUBSYSTEM=="net", ACTION=="change|add", KERNEL=="can*"  ATTR{tx_queue_len}="128"
```  

3. Enable the can0 interface and set the speed:  
```
echo -e "[Match]\nName=can*\n\n[CAN]\nBitRate=1M\n\n[Link]\nRequiredForOnline=no" | sudo tee /etc/systemd/network/25-can.network > /dev/null
```  

Check it with:  
`cat /etc/systemd/network/25-can.network`  
Should see:  
```
[Match]
Name=can*

[CAN]
BitRate=1M

[Link]
RequiredForOnline=no
```  

4. Reboot:  
`sudo reboot now`  

5. Next, upload your printer.cfg. You need to COMMENT out all mcu/extruder_mcu/mcu hot_mcu sections, then reboot (I recommend a hard power off, then power back on. Sometimes a soft reboot I was still not able to see the canbus IDs) 

This is so we can see the canbus IDs to note and to flash.  
Thanks to Teapot-Apple on the discord for this note.  

Note the following:  
- sovol hardcodes the UUIDs for mainboard/toolhead/chamber heater  
- after flashing, the UUIDs WILL change  

6. `sudo service klipper stop`, then run `~/katapult/scripts/flashtool.py -q` and SAVE THE OUTPUT.  

This was my output (I have a chamber heater, so we see 3, if you don't have it, you'll see 2):  
```
biqu@Zero:~$ python3 ~/katapult/scripts/flashtool.py -i can0 -q
Resetting all bootloader node IDs...
Checking for Katapult nodes...
Detected UUID: 0d1445047cdd, Application: Klipper
Detected UUID: 58a72bb93aa4, Application: Klipper
Detected UUID: 61755fe321ac, Application: Klipper
CANBus UUID Query Complete
biqu@Zero:~$
```  

You should see your CANBUS devices here, if you don't, something above was done wrong, OR, you were like me, and had a hard time seeing them, take my info on how to see them above.  

---

[Katapult and Klipper firmwares](./menuconfig/bins)

Katapult

Deployer bins like "Deployer_Zero_Host_H743_128kb" are intended to be flashed over the stock Sovol bootloader via flashtool.py . Do not use this as a standalone or with ST-LINK. Those expect you to flash Klipper firmware immediately after the deployer is flashed.This is optional but highly recommended.

Katapult bins like "Katapult_Zero_Host_H743_128kb" are intended to be flashed with ST-LINK.

Klipper

Both Host and Toolhead Klipper bins are intended to be flashed via flashtool.py .

If you want to generate those yourself you have the settings down.

## Flash Mainboard

Sovol's bootloader uses 128KiB offset (which technically we are not sure how it works, since the chip only has ~~128KiB~~ of flash)

We found out via brute force and unorthodox methods that the MCU actually appears to have 2MB flash and is likely an STM32H743 variant, not H750.

Flash Katapult_Zero_Host_H743_128kb.bin with st-link or use the flashtool.py and Deployer_Zero_Host_H743_128kb.

~/katapult/scripts/flashtool.py -f Deployer_Zero_Host_H743_128kb.bin  -u 4bc297a772bc [Replace with your UUID for Host]

~/katapult/scripts/flashtool.py -f Klipper_Zero_Host_H743_128kb.bin  -d /dev/ttyACM0 

**Mainboard**

make menuconfig reference:
```
STM32H743
128KiB deployment offset [Katapult optional]
25 MHz crystal clock
USB to CAN bus bridge (USB on PA11/PA12) [Klipper]
<OR>
USB on PA11/PA12 [Katapult]
CAN bus on PB8/PB9 [Klipper]
GPIO pins to set at micro-controller startup: !PE11,!PB0

(These are the aux and exhaust fans. If this isn't set, both of these will come on full blast at boot until Klipper takes control the board)
```
Credit for this info:  
Vlad (vvuk)  
https://github.com/vvuk/printer-configs/wiki/Kalico-on-the-Sovol-Zero  

2. For the mainboard, reference the menuconfig settings above. Then,   
`cd ~/klipper`, `make menuconfig`, `make clean`, `make`  
It will save the firmware to `~/klipper/out/klipper.bin`  

3. Flash your mainboard:  
`sudo service klipper stop`, then `~/katapult/scripts/flashtool.py -q`, this lists all CANBUS IDs, in my case mainboard was `0d1445047cdd`  

Flash it:  
`~/katapult/scripts/flashtool.py -f ~/klipper/out/klipper.bin -u 0d1445047cdd`  

Note the 1 CANBUS ID that changed here, that's your new mainboard ID:  
`~/katapult/scripts/flashtool.py -q`  

> [!IMPORTANT]  
> Now, skip to section **Make Klipper Configs for Toolhead and Chamber Heater**

> Carry on to **Make Klipper Configs for Toolhead and Chamber Heater**

## Make Klipper Configs for Toolhead and Chamber Heater

This is the info to reference when you do `make menuconfig` below.

**Toolhead / Chamber Heater** 

make menuconfig reference:
```
STM32F103
8KiB deployment offset [optional]
8 MHz clock
8KiB application offset
CAN bus on PB8/PB9
Balanced Speed/Size (-O2)
```  

Credit for this info:  
Vlad (vvuk)  
https://github.com/vvuk/printer-configs/wiki/Kalico-on-the-Sovol-Zero  

Now, remake the firmware, but for your toolhead/chamber heater (they both use the same config, but it is DIFFERENT than the mainboard)  
Repeat steps to flash for toolhead and then for chamber (REMEMBER TO CHANGE UUID IN THE COMMAND!), check which UUID changes each time using the query command above.

1. Reference the menuconfig settings above for toolhead and chamber heater.  
`cd ~/klipper`, `make menuconfig`, `make clean`, `make`  
It will save the firmware to `~/klipper/out/klipper.bin`  

2. Flash your mainboard:  
`sudo service klipper stop`, then `~/katapult/scripts/flashtool.py -q`, this lists all CANBUS IDs, in my case toolhead was `61755fe321ac`  

Flash it:  
`~/katapult/scripts/flashtool.py -f ~/klipper/out/klipper.bin -u 61755fe321ac`  

Note the 1 CANBUS ID that changed here, that's the ID of the device you just flashed:  
`katapult/scripts/flashtool.py -q`  

If you mess up and forget to check, you can turn the printer off, unplug the toolhead CAN connection, boot it back up, run the query, and the new ID is your chamber heater.  
Power down, plug toolhead CAN connection back in, query again, and that new ID is your toolhead.  

3. Once you have everything flashed, start klipper back up: `sudo service klipper start`

Credit for this section:  
Esoterical  
https://canbus.esoterical.online/Getting_Started.html  
https://canbus.esoterical.online/toolhead_flashing.html  

---

## If something goes wrong

I have the files uploaded [recovery](./recovery), each file can be flashed using st-link, which gets you back to Sovol firmware.
Reference Rappetor's guide Step 6/Step 7 to get you through it.

---

## Finishing Up

0. You can use my config (uploaded here), or go through and edit yours. Note that when you start, IF using the original Sovol config, you'll need to play "remove config whack-a-mole" to remove things we cannot use anymore. That consists of removing a section klipper errors out about, then going back and removing the next thing. Do this til no errors. 

IMO, just start with your printer.cfg, an eddy config, and very basic macros. You don't want to use the old Sovol stuff, especially **not** `klippy/extras/probe_eddy_current.py` and `klippy/extras/probe.py` as we will be setting up the probe with normal Klipper  

1. Change all `canbus_uuid` in your configs to your new ones. Save and restart. Everything should connect.  

2. Add your webcam back, I had to edit `crowsnest.conf` and change `device` to `/dev/video1`, save, then add the webcam in mainsail.  

3. You can remove `[virtual_sdcard]` location, since there is one in mainsail.cfg  

4. If you use my macros.cfg, the START_PRINT and END_PRINT (credit https://github.com/jontek2/A-better-print_start-macro/blob/main/README.md) requires you to update Orca's START_PRINT and END_PRINT in your:  
```
-> Printer settings
-> Machine G-Code
-> 'Machine Start G-code'
M104 S0 ; Stops OrcaSlicer from sending temp waits separately
M140 S0
START_PRINT EXTRUDER=[first_layer_temperature] BED=[first_layer_bed_temperature] CHAMBER=[chamber_temperature] MATERIAL=[filament_type]
```  

Just remove everything else there  

-> 'Machine End G-code'  
`END_PRINT`  

5. Calibrate eddy:

It is recommended to calibrate your eddy at bed temp that you most commonly use, i.e. I print ASA mainly on this printer so I calibrated at bed 90C  
Reference my SV08 guide here for general instructions, but **NOTE** that there are some significant changes:  
https://github.com/asnajder/sv08-config/blob/main/README.md

And my zero specific eddy config I suggest you use is found in this repo under `sovol_eddy.cfg`, note, ensure you use software I2C, hardware will not work (if you use my config, it's set up for software I2C)  

Additional short form steps:
```
# home the printer, it will fail on Z, that's ok
SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
# baby step it (manually move it to around z=2 if you can)
LDC_CALIBRATE_DRIVE_CURRENT CHIP=my_eddy_probe
# save_config after it finds the current, mine was set to 16
# after reboot:
SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
PROBE_EDDY_CURRENT_CALIBRATE CHIP=my_eddy_probe
# do paper test, etc
```

Just note that setting the kinematic position you will want to do within bounds of the Zero bed size, and of course in "How to use it", we don't QGL, etc  

NOTE: I had an error when calibrating my eddy:  
`I2C request to addr 42 reports error START_NACK`  

I did this change:  
`sudo nano /etc/systemd/system/klipper.service`  
and then add `Nice=-10` to the bottom of what is already there  
and restarted, and it fixed it  

> [!IMPORTANT]
> Note regarding Eddy calibration

If you get a `reg_drive_current` of `15`, it might help to bump it up to `16`, that seems to be the common working value  
If you leave it at `15`, you may end up with error `Error during homing probe: Trigger analog error: RAW_RANGE`  
If that's the case, change it manually to `16`, `SAVE_CONFIG`, then run:
```
SET_KINEMATIC_POSITION X=96 Y=76.2 Z=2
PROBE_EDDY_CURRENT_CALIBRATE CHIP=my_eddy_probe
```
do paper test, and re-set your `tap_threshold` again  

If you just change that value and try to home WITHOUT recalibration with `PROBE_EDDY_CURRENT_CALIBRATE CHIP=my_eddy_probe` , **your toolhead will crash into the bed, you have been warned!**  

6. PID tune, SHAPER_CALIBRATE, etc  

7. Print!
