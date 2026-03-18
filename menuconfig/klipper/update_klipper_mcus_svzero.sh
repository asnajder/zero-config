#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# UUIDs
HOSTUUID='4bc297a772bc' #Bootloader is requested over canbus, but that drops can0 interface so gotta finish by flashing over usb, that is the next line, should work for all zeros.
HOSTSERIAL='/dev/ttyACM0'
TOOLHEADUUID='2455eaeda160'
CHAMBERUUID='2d17deb0ba01'

#python3 ~/katapult/scripts/flash_can.py -f ~/klipper/host_mcu_klipper.bin -d /dev/ttyACM0

#python3 ~/katapult/scripts/flash_can.py -i can0 -u 4bc297a772bc -r


# Paths
KLIPPER_DIR="$HOME/klipper"
KATAPULT_FLASHTOOL="$HOME/katapult/scripts/flashtool.py"

# Colors
MAGENTA=$'\e[35m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
CYAN=$'\e[36m'
NC=$'\e[0m'

info(){ echo -e "${YELLOW}[INFO]${NC} $*"; }
warn(){ echo -e "${RED}[WARN]${NC} $*"; }
success(){ echo -e "${MAGENTA}[OK]${NC} $*"; }

cleanup() {
    info "Ensuring Klipper is running..."
    sudo service klipper start || true
}
trap cleanup EXIT

check_prereqs(){
    command -v make >/dev/null || { warn "make is required"; exit 1; }
    command -v python3 >/dev/null || { warn "python3 is required"; exit 1; }
    [ -d "$KLIPPER_DIR" ] || { warn "$KLIPPER_DIR does not exist"; exit 1; }
    [ -f "$KATAPULT_FLASHTOOL" ] || { warn "$KATAPULT_FLASHTOOL not found"; exit 1; }

    if ! ip link show can0 >/dev/null 2>&1; then
        warn "can0 interface not found; TOOLHEAD/CHAMBER flash will not work. HOST USB flash can still work."
        CAN0_AVAILABLE=0
    else
        CAN0_AVAILABLE=1
    fi

    if [ -z "${HOSTSERIAL:-}" ]; then
        detect_host_serial
    else
        info "HOSTSERIAL is already set: $HOSTSERIAL"
    fi
}

validate_uuid(){
    local name="$1"
    local uuid="$2"
    [[ "$uuid" =~ ^[0-9a-f]{12}$ ]] || {
        warn "Invalid UUID for ${name}: $uuid"
        return 1
    }
}

detect_host_serial(){
    # Host serial is mandatory for HOST flash; use explicit HOSTSERIAL or /dev/serial/by-id usb-katapult path.
    local candidate

    if [ -n "${HOSTSERIAL:-}" ]; then
        info "Using externally set HOSTSERIAL: $HOSTSERIAL"
        return
    fi

    if [ -d /dev/serial/by-id ]; then
        candidate=$(ls /dev/serial/by-id 2>/dev/null | grep -i -E 'usb-katapult|stm32h7' | head -n 1 || true)
        if [ -n "$candidate" ]; then
            candidate="/dev/serial/by-id/$candidate"
        fi
    fi

    if [ -n "$candidate" ]; then
        HOSTSERIAL="$candidate"
        success "Detected HOST serial device: $HOSTSERIAL"
    else
        warn "No host serial device found automatically. Please set HOSTSERIAL manually"
    fi
}

query_can_nodes(){
    if [ "${CAN0_AVAILABLE:-0}" -ne 1 ]; then
        warn "Skipping CAN query: can0 not available."
        return
    fi

    info "Querying CAN nodes..."
    python3 "$KATAPULT_FLASHTOOL" -i can0 -q
}

stop_klipper(){
    info "Stopping Klipper service"
    sudo service klipper stop
}

start_klipper(){
    info "Starting Klipper service"
    sudo service klipper start
}

build_and_flash(){
    local name="$1"
    local kconfig="$2"
    local uuid="$3"
    local serial="${4:-}"

    [ -z "$uuid" ] && { warn "No UUID for ${name}, skipping"; return; }
    validate_uuid "$name" "$uuid" || return

    cd "$KLIPPER_DIR"

    info "Building Klipper firmware for ${name}"

    make clean

    info "Please configure or verify menuconfig for ${name}."
    read -r -p "${CYAN}Press Enter to open menuconfig (or type 'q' to cancel): ${NC}" choice

    if [[ "$choice" =~ ^([qQ]|quit)$ ]]; then
        warn "User cancelled ${name} build"
        return
    fi

make menuconfig KCONFIG_CONFIG="${kconfig}"

    JOBS=$(nproc)
    [ "$JOBS" -gt 4 ] && JOBS=4

    make KCONFIG_CONFIG="${kconfig}" -j"$JOBS"

    [ -f "$KLIPPER_DIR/out/klipper.bin" ] || {
        warn "Build failed: klipper.bin missing"
        return
    }

    local out_bin="${name,,}_mcu_klipper.bin"
    cp "$KLIPPER_DIR/out/klipper.bin" "$KLIPPER_DIR/$out_bin"

    info "Firmware ready: $KLIPPER_DIR/$out_bin"

    query_can_nodes
    sleep 1

    # For HOST/mainboard, request Katapult bootloader first (required for -d mode; can optionally bypass if can0 not present)
    if [[ "$name" == "HOST" ]]; then
        detect_host_serial

        if [ -z "$serial" ] && [ -n "${HOSTSERIAL:-}" ]; then
            serial="$HOSTSERIAL"
        fi

        if [ -z "$serial" ] || [ -z "$uuid" ]; then
            warn "Skipping HOST flash because HOSTSERIAL or HOSTUUID is missing"
            return
        fi

        info "Using HOST serial: $serial"

        if [ "${CAN0_AVAILABLE:-0}" -eq 1 ]; then
            info "Requesting Katapult bootloader for HOST (UUID=$uuid)"
            python3 "$KATAPULT_FLASHTOOL" -i can0 -u "$uuid" -r
            sleep 2
        else
            warn "can0 unavailable; skipping bootloader request and continuing with USB flash"
        fi

        read -r -p "${CYAN}Type YES to flash HOST via serial ($serial) (or q to cancel): ${NC}" confirm
        if [[ "$confirm" =~ ^([qQ]|quit)$ ]]; then
            warn "User cancelled host flash"
            return
        fi
        [[ "$confirm" == "YES" ]] || { warn "Aborted"; return; }

        python3 "$KATAPULT_FLASHTOOL" -f "$KLIPPER_DIR/$out_bin" -d "$serial"
    else
        if [ "${CAN0_AVAILABLE:-0}" -ne 1 ]; then
            warn "Skipping ${name} flash because can0 is not available"
            return
        fi

        read -r -p "${CYAN}Type YES to flash ${name} (UUID=$uuid) (or q to cancel): ${NC}" confirm
        if [[ "$confirm" =~ ^([qQ]|quit)$ ]]; then
            warn "User cancelled ${name} flash"
            return
        fi
        [[ "$confirm" == "YES" ]] || { warn "Aborted"; return; }

        python3 "$KATAPULT_FLASHTOOL" -i can0 -f "$KLIPPER_DIR/$out_bin" -u "$uuid"
    fi

    success "${name} flashed successfully"
    sleep 1

    query_can_nodes
    sleep 1
}

main_menu(){
    PS3='Select device to update: '

    while true; do
        clear
        echo -e "${MAGENTA}SV_ZERO AUTOMATIC MCU UPDATER${NC}"
        if [ "${CAN0_AVAILABLE:-0}" -ne 1 ]; then
            echo -e "${RED}[WARN] can0 not available: TOOLHEAD/CHAMBER/Query nodes disabled. HOST USB-only mode.${NC}"
            options=("HOST MCU" "Quit")
        else
            options=("HOST MCU" "TOOLHEAD MCU" "CHAMBER MCU" "Query CAN nodes" "Quit")
        fi

        select opt in "${options[@]}"; do
            case $opt in
                "HOST MCU")
                    build_and_flash "HOST" "host.mcu" "$HOSTUUID" "$HOSTSERIAL"
                    break
                    ;;
                "TOOLHEAD MCU")
                    build_and_flash "TOOLHEAD" "toolhead.mcu" "$TOOLHEADUUID"
                    break
                    ;;
                "CHAMBER MCU")
                    build_and_flash "CHAMBER" "chamber.mcu" "$CHAMBERUUID"
                    break
                    ;;
                "Query CAN nodes")
                    query_can_nodes
                    read -r -p "Press Enter to continue..." dummy
                    break
                    ;;
                "Quit")
                    info "Done"
                    return
                    ;;
                *)
                    warn "Invalid option '$REPLY'"
                    break
                    ;;
            esac
        done
    done
}

# run
check_prereqs
stop_klipper
main_menu
start_klipper
cd "$KLIPPER_DIR"
success "Script complete"
