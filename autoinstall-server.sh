#!/bin/bash

set -e
set -x  # Enable debugging output

# Variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
ISO_MOUNT="/mnt"
WORK_DIR="ubuntu-autoinstall-work"
MODIFIED_ISO="ubuntu-20.04-autoinstall.iso"
AUTOINSTALL_DIR="autoinstall-server"
SERVER_DIR="$AUTOINSTALL_DIR/server"
USER_DATA="$SERVER_DIR/user-data"
META_DATA="$SERVER_DIR/meta-data"

# Function to display spinner
spinner() {
    local pid=$!
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=${temp}${spinstr%"${temp}"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Start script
echo "[👶] Starting up..."

# Download ISO
echo "[📥] Downloading ISO from $ISO_URL..."
curl -L -o "$ISO_NAME" "$ISO_URL" &
spinner
echo "[📥] ISO download complete."

# Create working directory
echo "[🔧] Creating working directory..."
mkdir -p "$WORK_DIR"
sudo mount -o loop "$ISO_NAME" "$ISO_MOUNT"
rsync -a "$ISO_MOUNT/" "$WORK_DIR/"
sudo umount "$ISO_MOUNT"
echo "[🔧] Working directory setup complete."

# Create autoinstall-server directory and files
echo "[🗂️] Creating autoinstall-server directory and files..."
mkdir -p "$SERVER_DIR"
touch "$USER_DATA" "$META_DATA"

# Prompt for user input
read -p "Enter the desired username: " USERNAME
echo "Enter password for user $USERNAME:"
read -s PASSWORD
HASHED_PASSWORD=$(openssl passwd -6 -stdin <<< "$PASSWORD")

# Write user-data and meta-data files
echo "#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-server
    password: $HASHED_PASSWORD
    username: $USERNAME
  keyboard:
    layout: en
    toggle: null
    variant: ''
  locale: en_EN.UTF-8
  ssh:
    allow-pw: true
    install-server: true
  packages:
    - build-essential
    - network-manager" > "$USER_DATA"

echo "meta-data: {}" > "$META_DATA"
echo "[🗂️] User data and meta data files created."

# Modify ISO
echo "[🛠️] Modifying ISO..."
# Example modification, replace with actual commands
sed -i 's/old/new/g' "$WORK_DIR/path/to/file" || { echo "Error modifying ISO"; exit 1; }
echo "[🛠️] ISO modification complete."

# Create modified ISO
echo "[💾] Creating modified ISO..."
mkisofs -r -V "Custom Ubuntu ISO" -cache-inodes -J -l -o "$MODIFIED_ISO" "$WORK_DIR" &
spinner
echo "[💾] Modified ISO creation complete."

# Cleanup
echo "[❓] Do you want to delete the working directory '$WORK_DIR'? [y/n]: "
read -r delete_dir
if [ "$delete_dir" = "y" ]; then
    echo "[🗑️] Deleting working directory..."
    rm -rf "$WORK_DIR"
fi

echo "[✔️] Done. Modified ISO created as '$MODIFIED_ISO'."

# Prompt user to insert USB and select device
echo "[💾] Please plug in your USB key and press Enter to continue."
read -r
echo "[💾] Listing available USB devices..."
lsblk
echo "[💾] Enter the device ID of your USB key (e.g., sdb):"
read -r usb_device
echo "You selected /dev/$usb_device. This action will erase all data on the USB device. Are you sure you want to proceed? Type 'yes' to confirm or 'no' to select a different device or exit."
read -r confirmation

if [ "$confirmation" = "yes" ]; then
    echo "[💾] Writing ISO to USB device..."
    sudo dd if="$MODIFIED_ISO" of="/dev/$usb_device" bs=1024k status=progress && sync
    echo "[💾] USB device write complete."
elif [ "$confirmation" = "no" ]; then
    echo "[❓] Please re-select your USB device."
    # You might want to add code here to allow the user to re-enter the device ID or exit.
else
    echo "[❌] Exiting."
    exit 1
fi

echo "[✔️] Script execution complete."
