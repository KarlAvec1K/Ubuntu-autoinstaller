#!/bin/bash

set -e

# Variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
ISO_MOUNT="/mnt"
WORK_DIR="ubuntu-autoinstall-work"
MODIFIED_ISO="ubuntu-20.04-autoinstall.iso"
USB_DEVICE=""
USERNAME=""
PASSWORD=""
HOSTNAME=""
SSH_KEY=""

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

# Function to create user-data
create_user_data() {
    echo "#cloud-config" > "$WORK_DIR/user-data"
    echo "autoinstall:" >> "$WORK_DIR/user-data"
    echo "  version: 1" >> "$WORK_DIR/user-data"
    echo "  ssh:" >> "$WORK_DIR/user-data"
    echo "    install-server: yes" >> "$WORK_DIR/user-data"
    echo "    authorized-keys:" >> "$WORK_DIR/user-data"
    echo "      - $SSH_KEY" >> "$WORK_DIR/user-data"
    echo "  packages:" >> "$WORK_DIR/user-data"
    echo "    - vim" >> "$WORK_DIR/user-data"
    echo "    - htop" >> "$WORK_DIR/user-data"
    echo "  user-data:" >> "$WORK_DIR/user-data"
    echo "    username: $USERNAME" >> "$WORK_DIR/user-data"
    echo "    password: $PASSWORD" >> "$WORK_DIR/user-data"
    echo "    hostname: $HOSTNAME" >> "$WORK_DIR/user-data"
}

# Function to get USB device
get_usb_device() {
    echo "[🔍] Please select the USB device to write the modified ISO to:"
    lsblk -o NAME,SIZE,MOUNTPOINT,LABEL
    echo -n "Enter USB device (e.g., /dev/sdX): "
    read -r USB_ID
    USB_DEVICE="/dev/$USB_ID"
    if [ ! -b "$USB_DEVICE" ]; then
        echo "[❌] USB device $USB_DEVICE not found."
        exit 1
    fi
}

# Start script
echo "[👶] Starting up..."

# Display ASCII logo
echo " 888    d8P                   888        d8888                             d888   888    d8P  "
echo " 888   d8P                    888       d88888                            d8888   888   d8P  "
echo " 888  d8P                     888      d88P888                              888   888  d8P   "
echo " 888d88K      8888b.  888d888 888     d88P 888 888  888  .d88b.   .d8888b   888   888d88K  "
echo " 8888888b        88b 888P\"   888    d88P  888 888  888 d8P  Y8b d88P\"      888   8888888b "
echo " 888  Y88b   .d888888 888     888   d88P   888 Y88  88P 88888888 888        888   888  Y88b"
echo " 888   Y88b  888  888 888     888  d8888888888  Y8bd8P  Y8b.     Y88b.      888   888   Y88b"
echo " 888    Y88b \"Y888888 888     888 d88P     888   Y88P    \"Y8888   \"Y8888P 8888888 888    Y88b"
echo "                                                                                              "
echo "                                 https://github.com/KarlAvec1K                                "
echo "                                                                                              "


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

# Get autoinstall configuration details
echo "[📝] Please enter the following details for autoinstall configuration:"
echo -n "Username: "
read -r USERNAME
echo -n "Password: "
read -s PASSWORD
echo
echo -n "Hostname: "
read -r HOSTNAME
echo -n "SSH Public Key: "
read -r SSH_KEY
create_user_data

# Get USB device
get_usb_device

# Modify ISO
echo "[🛠️] Modifying ISO..."
# Here you could include any specific modifications to the ISO if needed

# Create modified ISO
echo "[💾] Creating modified ISO..."
mkisofs -r -V "Custom Ubuntu ISO" -cache-inodes -J -l -o "$MODIFIED_ISO" "$WORK_DIR" &
spinner

# Write modified ISO to USB
echo "[💿] Writing ISO to USB device $USB_DEVICE..."
sudo dd if="$MODIFIED_ISO" of="$USB_DEVICE" bs=4M status=progress && sync

# Cleanup
echo "[❓] Do you want to delete the working directory '$WORK_DIR'? [y/n]: "
read -r delete_dir
if [ "$delete_dir" = "y" ]; then
    echo "[🗑️] Deleting working directory..."
    rm -rf "$WORK_DIR"
fi

echo "[✔️] Done. Modified ISO created as '$MODIFIED_ISO' and written to '$USB_DEVICE'."
