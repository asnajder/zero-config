# Mainline Sovol Zero (Klipper, Armbian Trixie)

Special thanks to: Teapot-Apple, matt73210, Atomique13, jedi 2^10, Rappetor, and others of the discord coming together to share information!

---

## Initial Setup

1. Backup your config  
2. Download Armbian Imager, insert your 32GB EMMC (note that 8GB will NOT work), Select BTT (BIQU) Manufacturer, Select BigTreeTech CB1 Board, Select Minimal tab, then Armbian <release date> Trixie cli, then Erase and Flash  
3. On the eMMC, edit /boot/armbianEnv.txt, COPY your `rootdev=UUID=`, then replace everything else with:  
```
verbosity=1
bootlogo=false
console=both
disp_mode=1920x1080p60
overlay_prefix=sun50i-h616
fdtfile=sun50i-h616-bigtreetech-cb1-emmc.dtb
rootdev=UUID=YOUR_COPIED_UUID_HERE
rootfstype=ext4
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
```  

You can fix the partition size now if you have access to another linux host:  
`sudo fdisk /dev/<device> then e, 2, <enter>, w`  

If not, I believe it will do it on first boot.  

4. Connect a keyboard to the printer, and an HDMI from printer to a monitor, then follow the first login steps. Note that if you're going to be using wifi, DO NOT configure it here when it asks. Select `N` and just configure it later with `armbian-config`. My installs (on here and my SV08) just froze at this step.  
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
Note you will also need `python3-serial` (`sudo apt install python3-serial`) and to do `~/klippy-env/bin/pip install scipy` (scipy is used for eddy we set up later)  

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
echo -e "[Match]nName=can*nn[CAN]nBitRate=1Mnn[Link]nRequiredForOnline=no" | sudo tee /etc/systemd/network/25-can.network > /dev/null
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

5. Next, upload your printer.cfg. You need to COMMENT out all mcu/extruder_mcu/mcu hot_mcu sections, then reboot! This is so we can see the canbus IDs to note and to flash.  
Thanks to Teapot-Apple on the discord for this note.  

Note the following:  
- sovol hardcodes the UUIDs for mainboard/toolhead/chamber heater  
- after flashing, the UUIDs WILL change  

6. `sudo service klipper stop`, then run `python3 ~/katapult/scripts/flashtool.py -i can0 -q` and SAVE THE OUTPUT.  

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

You should see your CANBUS devices here, if you don't, something above was done wrong, OR, you were like me, and had a hard time seeing them, take my info on how to see them.  

7. Edit "~/klipper/src/stm32/Kconfig"  
You will then scroll down until you see bootloader and then scroll down til you see "config STM32_FLASH_START_20000"  
you will then need to add `MACH_STM32H750` to the end of the line under that as such:  
From:  
`bool "128KiB bootloader" if MACH_STM32H743 || MACH_STM32H723 || MACH_STM32F7`  

To:  
`bool "128KiB bootloader" if MACH_STM32H743 || MACH_STM32H723 || MACH_STM32F7 || MACH_STM32H750`  

Note, this will make Kalico or Klipper repo Dirty.  
Thanks to Teapot-Apple on the discord for this info.  


## Make Klipper Configs

**Mainboard**
```
config:
STM32H750
128KiB bootloader offset
Clock Reference: 25 MHz crystal
USB to CAN bus bridge (USB on PA11/PA12)
CAN bus on PB8/PB9
GPIO pins to set at micro-controller startup: !PE11,!PB0
These are the aux and exhaust fans. If this isn't set, both of these will come on full blast at boot until Kalico takes control of the board
```  

**Toolhead** 
```
config:
STM32F103
8KiB bootloader offset
Clock Reference: 8 MHz crystal
CAN bus on PB8/PB9
```  

**Chamber Heater**
```
config:
STM32F103
8KiB bootloader offset
Clock Reference: 8 MHz crystal
CAN bus on PB8/PB9
```  

Credit for this info:  
Vlad (vvuk)  
https://github.com/vvuk/printer-configs/wiki/Kalico-on-the-Sovol-Zero  

1. Start with the mainboard, and reference the menuconfig settings above.  
`cd ~/klipper`, `make menuconfig`, `make clean`, `make`  
It will save the firmware to `~/klipper/out/klipper.bin`  

2. Flash your mainboard:  
`sudo service klipper stop`, then `python3 ~/katapult/scripts/flashtool.py -i can0 -q`, this lists all CANBUS IDs, in my case mainboard was `0d1445047cdd`  

Flash it:  
`python3 ~/katapult/scripts/flashtool.py -i can0 -f ~/klipper/out/klipper.bin -u 61755fe321ac`  

Note the 1 CANBUS ID that changed here, that's your new mainboard ID:  
`python3 ~/katapult/scripts/flashtool.py -i can0 -q`  

Now, remake the firmware, but for your toolhead/chamber heater (it uses same config)  
Repeat steps to flash for toolhead and then for chamber (REMEMBER TO CHANGE UUID IN THE COMMAND!), noting what UUID changes each time using the query command above.  

If you mess up and forget to check, you can turn the printer off, unplug the toolhead CAN connection, boot it back up, run the query, and the new ID is your chamber heater.  
Power down, plug toolhead CAN connection back in, query again, and that new ID is your toolhead.  

Credit for this section:  
Esoterical  
https://canbus.esoterical.online/Getting_Started.html  
https://canbus.esoterical.online/toolhead_flashing.html  

---

## Finishing Up

0. You can use my config (uploaded here), or go through and edit yours. Note that when you start, IF using the original Sovol config, you'll need to play "remove config whack-a-mole" to remove things we cannot use anymore. That consists of removing a section klipper errors out about, then going back and removing the next thing. Do this til no errors.  

1. Change all `canbus_uuid` in your configs to your new ones. Save and restart. Everything should connect.  

2. Add your webcam back, I had to edit `crowsnest.conf` and change `device` to `/dev/v4l/by-id/usb-HHW_microelectronics_Co.__Ltd._MGS1-video-index0`, save, then add the webcam in mainsail.  

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
You can follow my guide for the SV08 here, it's pretty much the same:  
https://github.com/asnajder/sv08-config/blob/main/README.md  

Just note that setting the kinematic position you will want to do within bounds of the Zero bed size, and of course in "How to use it", we don't QGL, etc  

NOTE: I had an error when calibrating my eddy:  
`I2C request to addr 42 reports error START_NACK`  

I did this change:  
`sudo nano /etc/systemd/system/klipper.service`  
and then add `Nice=-10` to the bottom of what is already there  
and restarted, and it fixed it  

6. PID tune, SHAPER_CALIBRATE, etc  

7. Print!
