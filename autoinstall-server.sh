#!/bin/bash

set -e

# Variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
ISO_MOUNT="/mnt"
WORK_DIR="ubuntu-autoinstall-work"
MODIFIED_ISO="ubuntu-20.04-autoinstall.iso"
AUTO_INSTALL_DIR="autoinstall-server"
SERVER_DIR="$AUTO_INSTALL_DIR/server"
SCRIPT="$0"  # This script itself

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

# Create autoinstall-server and server directories
echo "[📂] Creating directories..."
mkdir -p "$AUTO_INSTALL_DIR"
mkdir -p "$SERVER_DIR"

# Create user-data and meta-data files
echo "[📝] Creating user-data and meta-data files..."
touch "$SERVER_DIR/user-data"
touch "$SERVER_DIR/meta-data"

# Ask user for username and password
echo "[👤] Enter the username for the new account:"
read -r USERNAME

echo "[🔐] Enter password for the user '$USERNAME':"
read -s PASSWORD

# Generate hashed password
PASSWORD_HASH=$(openssl passwd -6 -stdin <<< "$PASSWORD")

# Write user-data content with chosen username
cat <<EOF > "$SERVER_DIR/user-data"
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-server
    password: $PASSWORD_HASH
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
    - network-manager
EOF

# Ensure the script has execute permission
chmod +x "$SCRIPT"

# Run the script
echo "[🚀] Executing the script..."
"$SCRIPT"

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

# USB Installation
echo "[🔌] Please plug in your USB drive and press Enter..."
read -r

# List USB devices
echo "[📋] Listing USB devices..."
lsblk

# Ask user for USB device
echo "[💾] Enter the device ID of your USB drive (e.g., sdb):"
read -r DEVICE_ID

# Confirm and warn user
echo "[⚠️] WARNING: This action will erase all data on /dev/$DEVICE_ID. Do you want to proceed? [yes/no/exit]:"
read -r proceed

case "$proceed" in
    yes)
        echo "[📝] Writing ISO to /dev/$DEVICE_ID..."
        sudo dd if="$MODIFIED_ISO" of="/dev/$DEVICE_ID" bs=1024k status=progress && sync
        ;;
    no)
        echo "[🔄] Please run the script again and select the correct device."
        exit 1
        ;;
    exit)
        echo "[🚪] Exiting script."
        exit 0
        ;;
    *)
        echo "[❓] Invalid option. Exiting."
        exit 1
        ;;
esac

echo "[✔️] Done. The ISO has been written to /dev/$DEVICE_ID."
