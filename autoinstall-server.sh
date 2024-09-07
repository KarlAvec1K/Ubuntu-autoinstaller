#!/bin/bash

set -e

# Variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
ISO_MOUNT="/mnt"
WORK_DIR="ubuntu-autoinstall-work"
MODIFIED_ISO="ubuntu-20.04-autoinstall.iso"

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

# Create working directory
echo "[🔧] Creating working directory..."
mkdir -p "$WORK_DIR"
sudo mount -o loop "$ISO_NAME" "$ISO_MOUNT"
rsync -a "$ISO_MOUNT/" "$WORK_DIR/"
sudo umount "$ISO_MOUNT"

# Modify ISO
echo "[🛠️] Modifying ISO..."
# Here you should add your sed or other modification commands. For demonstration:
# sed -i 's/old/new/g' "$WORK_DIR/path/to/file"
# The example sed command might need adjustments based on the actual modification required.
sed -i 's/old/new/g' "$WORK_DIR/path/to/file" || { echo "Error modifying ISO"; exit 1; }

# Create modified ISO
echo "[💾] Creating modified ISO..."
mkisofs -r -V "Custom Ubuntu ISO" -cache-inodes -J -l -o "$MODIFIED_ISO" "$WORK_DIR" &
spinner

# Cleanup
echo "[❓] Do you want to delete the working directory '$WORK_DIR'? [y/n]: "
read -r delete_dir
if [ "$delete_dir" = "y" ]; then
    echo "[🗑️] Deleting working directory..."
    rm -rf "$WORK_DIR"
fi

echo "[✔️] Done. Modified ISO created as '$MODIFIED_ISO'."
