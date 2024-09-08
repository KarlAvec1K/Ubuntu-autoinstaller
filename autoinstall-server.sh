#!/bin/bash

# Define variables
ISO_URL="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current/focal-live-server-amd64+intel-iot.iso"
ISO_NAME="focal-live-server-amd64+intel-iot.iso"
WORK_DIR="/mnt/ubuntu-autoinstall-work"
ISO_MOUNT="/mnt/iso"
MODIFIED_ISO="modified-ubuntu.iso"
USB_DEVICE=""
DOWNLOAD_DIR="/path/to/downloads"

# Function to create user data
create_user_data() {
    cat <<EOF > "$WORK_DIR/user-data"
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
users:
  - name: $USERNAME
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    plain_text_passwd: $PASSWORD
    lock_passwd: false
    ssh_authorized_keys:
      - $SSH_KEY
EOF
}

# Function to get USB device
get_usb_device() {
    echo "[🔍] Please select the USB device to write the modified ISO to:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
    echo -n "Enter USB device (e.g., /dev/sdX): "
    read -r USB_DEVICE
    USB_DEVICE="/dev/$USB_DEVICE"
    if ! lsblk | grep -q "$USB_DEVICE"; then
        echo "[❌] USB device $USB_DEVICE not found."
        exit 1
    fi
}

# Function to show spinner while waiting
spinner() {
    local pid=$!
    local spin='-\|/'
    local i=0
    while [ -d /proc/$pid ]; do
        i=$(( (i+1) %4 ))
        printf "\r${spin:$i:1}"
        sleep .1
    done
    printf " done.\n"
}

# Function to handle error
handle_error() {
    echo "[❌] Error modifying ISO"
    exit 1
}

# Ensure aria2 is installed
if ! command -v aria2c &> /dev/null; then
    echo "aria2 is not installed. Installing aria2..."
    sudo apt update && sudo apt install -y aria2
fi

# Create download directory if it doesn't exist
mkdir -p "$DOWNLOAD_DIR"

# Configure Cloudflare DNS temporarily
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
echo "nameserver 1.0.0.1" | sudo tee -a /etc/resolv.conf > /dev/null

# Download ISO with aria2
echo "[📥] Downloading ISO from $ISO_URL..."
aria2c -x 16 -s 16 -d "$DOWNLOAD_DIR" -o "$ISO_NAME" "$ISO_URL"
echo "[✔️] Download completed: $DOWNLOAD_DIR/$ISO_NAME"

# Restore original DNS settings if needed
# Uncomment the following lines if you have a backup of the original /etc/resolv.conf
# sudo mv /etc/resolv.conf.bak /etc/resolv.conf

# Start script
echo "[👶] Starting up..."

# Create working directory
echo "[🔧] Creating working directory..."
mkdir -p "$WORK_DIR"
sudo mount -o loop "$DOWNLOAD_DIR/$ISO_NAME" "$ISO_MOUNT"
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
