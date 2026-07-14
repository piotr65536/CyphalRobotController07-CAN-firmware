#!/usr/bin/env bash
#
# flash.sh - build this firmware and flash the Raspberry Pi Pico over the UF2 bootloader.
#
#   1. arduino-cli compile -e     (stops here if the build fails)
#   2. find the RPI-RP2 bootloader drive (tells you how to enter BOOTSEL if it's missing)
#   3. mount it at /mnt/rp2
#   4. copy the .uf2 -> the Pico flashes and reboots itself
#
# Usage:  ./flash.sh
#
set -euo pipefail

FQBN="rp2040:rp2040:rpipico"
MNT="/mnt/rp2"
SKETCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SKETCH_DIR"

echo "==> [1/4] Building ($FQBN) ..."
if ! arduino-cli compile -b "$FQBN" -e .; then
    echo "!! Build FAILED - fix the errors above. Nothing was flashed." >&2
    exit 1
fi

UF2="$(ls build/*/*.uf2 2>/dev/null | head -n1 || true)"
if [ -z "$UF2" ]; then
    echo "!! Build ok but no .uf2 found under build/ - aborting." >&2
    exit 1
fi
echo "    built: $UF2"

echo "==> [2/4] Looking for the RPI-RP2 bootloader drive ..."
RP2_DEV="$(lsblk -rno NAME,LABEL | awk '$2=="RPI-RP2"{print "/dev/"$1; exit}' || true)"
if [ -z "$RP2_DEV" ]; then
    cat >&2 <<'EOF'
!! No RPI-RP2 drive - the Pico is not in BOOTSEL mode.

   Enter BOOTSEL, then re-run this script:
     1. Unplug the Pico USB.
     2. Press and HOLD the BOOTSEL button.
     3. Plug the USB back in, then release BOOTSEL.
   It should then show up as RPI-RP2 in  lsblk .
EOF
    exit 1
fi
echo "    found: $RP2_DEV"

echo "==> [3/4] Mounting $RP2_DEV -> $MNT ..."
MOUNTED="$(findmnt -nro TARGET -S "$RP2_DEV" 2>/dev/null || true)"
if [ -z "$MOUNTED" ]; then
    sudo mkdir -p "$MNT"
    sudo mount "$RP2_DEV" "$MNT"
    MOUNTED="$MNT"
fi
echo "    mounted at: $MOUNTED"

echo "==> [4/4] Flashing $(basename "$UF2") ..."
# The Pico reboots the instant the image is written, so the drive disappears mid-copy:
# a 'cannot close / No space left' error here is NORMAL - it means the image was taken.
sudo cp "$UF2" "$MOUNTED"/ 2>/dev/null || true
sync 2>/dev/null || true
sudo umount "$MNT" 2>/dev/null || true   # clear the now-stale mount

echo
echo "==> Done. The Pico is rebooting into the new firmware."
echo "    Serial:  arduino-cli monitor -p /dev/ttyACM0 -c baudrate=115200"
