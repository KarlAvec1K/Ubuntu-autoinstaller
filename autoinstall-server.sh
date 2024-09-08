#!/bin/bash

# ASCII logo
echo "                                                                                             
 888    d8P                   888        d8888                             d888   888    d8P 
 888   d8P                    888       d88888                            d8888   888   d8P  
 888  d8P                     888      d88P888                              888   888  d8P   
 888d88K      8888b.  888d888 888     d88P 888 888  888  .d88b.   .d8888b   888   888d88K    
 8888888b        88b 888P   888    d88P  888 888  888 d8P  Y8b d88P 888 8888888b  
 888  Y88b   .d888888 888     888   d88P   888 Y88  88P 88888888 888        888   888  Y88b  
 888   Y88b  888  888 888     888  d8888888888  Y8bd8P  Y8b.     Y88b.      888   888   Y88b  
 888    Y88b Y888888 888 888 d88P 888 Y88P Y8888   Y8888P 8888888 888 Y88b
                                                                                             
                                                                                             
https://github.com/KarlAvec1K"

# Start script
echo "[👶] Starting up..."

# Function to generate SSH key
generate_ssh_key() {
    SSH_DIR="$HOME/.ssh"
    SSH_KEY="$SSH_DIR/id_rsa"

    if [ ! -f "$SSH_KEY" ]; then
        echo "[🔑] SSH key not found. Generating a new SSH key pair..."
        mkdir -p "$SSH_DIR"
        ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$SSH_KEY" -N ""
        echo "[🔑] SSH key generated."
        echo "[🔑] Public key:"
        cat "${SSH_KEY}.pub"
    else
        echo "[🔑] SSH key already exists."
        echo "[🔑] Public key:"
        cat "${SSH_KEY}.pub"
    fi
}

# Generate SSH key
generate_ssh_key

# Download ISO using aria2 with Cloudflare
echo "[📥] Downloading ISO from $ISO_URL..."
aria2c --continue=true --max-connection-per-server=4 --split=4 --header='User-Agent: Mozilla/5.0' "$ISO_URL" -o "$ISO_NAME" &
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
