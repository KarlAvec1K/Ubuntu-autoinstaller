#!/bin/bash

set -e

# Variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
ISO_MOUNT="/mnt"
WORK_DIR="ubuntu-autoinstall-work"
MODIFIED_ISO="ubuntu-20.04-autoinstall.iso"
AUTOINSTALL_CONFIG="$WORK_DIR/auto-install/user-data"

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

# Display ASCII Logo
echo "
888    d8P                   888        d8888                             d888   888    d8P  
888   d8P                    888       d88888                            d8888   888   d8P   
888  d8P                     888      d88P888                              888   888  d8P    
888d88K      8888b.  888d888 888     d88P 888 888  888  .d88b.   .d8888b   888   888d88K     
8888888b        \"88b 888P\"   888    d88P  888 888  888 d8P  Y8b d88P\"      888   8888888b    
888  Y88b   .d888888 888     888   d88P   888 Y88  88P 88888888 888        888   888  Y88b   
888   Y88b  888  888 888     888  d8888888888  Y8bd8P  Y8b.     Y88b.      888   888   Y88b  
888    Y88b \"Y888888 888     888 d88P     888   Y88P    \"Y8888   \"Y8888P 8888888 888    Y88b 
                                                                                             
                                                                                             
                                                                                             
"

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

# Prompt for user input
echo "[📝] Please enter the following details for autoinstall configuration:"

read -p "Username: " USERNAME
read -sp "Password: " PASSWORD
echo
read -p "Hostname: " HOSTNAME
read -p "Autoinstall Config File Path (relative to $WORK_DIR): " CONFIG_PATH

# Prompt for USB device
echo "[🔍] Please select the USB device to write the modified ISO to:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -w "disk"
read -p "Enter USB device (e.g., /dev/sdX): " USB_DEVICE

# Validate USB device
if [ ! -b "$USB_DEVICE" ]; then
    echo "[❌] USB device $USB_DEVICE not found."
    exit 1
fi

# Create autoinstall configuration
echo "[🛠️] Creating autoinstall configuration..."

# Ensure the file exists
CONFIG_FILE="$WORK_DIR/$CONFIG_PATH"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[❌] Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Modify autoinstall configuration
echo "[🔄] Modifying autoinstall configuration..."
mkdir -p "$(dirname "$AUTOINSTALL_CONFIG")"
cat > "$AUTOINSTALL_CONFIG" << EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: $HOSTNAME
    username: $USERNAME
    password: $PASSWORD
EOF

# Modify ISO
echo "[🛠️] Modifying ISO..."
# Replace old/new with appropriate modifications if needed
sed -i 's/old/new/g' "$CONFIG_FILE" || { echo "Error modifying ISO"; exit 1; }

# Create modified ISO
echo "[💾] Creating modified ISO..."
mkisofs -r -V "Custom Ubuntu ISO" -cache-inodes -J -l -o "$MODIFIED_ISO" "$WORK_DIR" &
spinner

# Write modified ISO to USB
echo "[💾] Writing modified ISO to USB device $USB_DEVICE..."
sudo dd if="$MODIFIED_ISO" of="$USB_DEVICE" bs=4M status=progress
sync

# Cleanup
echo "[❓] Do you want to delete the working directory '$WORK_DIR'? [y/n]: "
read -r delete_dir
if [ "$delete_dir" = "y" ]; then
    echo "[🗑️] Deleting working directory..."
    rm -rf "$WORK_DIR"
fi

echo "[✔️] Done. Modified ISO created and written to '$USB_DEVICE'."
