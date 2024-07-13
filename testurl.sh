#!/bin/bash

# Store the current user's username
CURRENT_USER=$(who am i | awk '{print $1}')

# Change to the specified directory and run the Python script as the current user
sudo -u "$CURRENT_USER" bash -c "cd /home/arun/projects/mirrortest && python -m mirrortest --mirror '$1'"
sleep 5

# Start timer
start_time=$(date +%s)

# Check for root privileges 
if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# URL for the Arch Linux mirror (can be passed as an argument)
MIRROR_URL=${1:-"https://mirror.example.com/archlinux"}

# Function to check URL validity
check_url() {
    wget --spider -q "$1/core/os/x86_64/core.db" 
    return $?
}

# Verify the mirror URL
if ! check_url "$MIRROR_URL"; then
    echo "Mirror URL is invalid or down. Please provide a valid URL."
    exit 1
fi

echo "Mirror URL is valid. Proceeding with installation..."

# List of packages to be installed
PACKAGES="base linux linux-firmware vim zsh git networkmanager gnome gnome-extra firefox \
          python python-pip gcc make docker virtualbox jre-openjdk"

# Root directory for all chroot installations
ROOT_DIR="/mnt/arch-chroot-root"

# Unique subdirectory for this installation
# Using a timestamp for uniqueness
SUB_DIR="${ROOT_DIR}/$(date +%Y%m%d-%H%M%S)"

# Create the unique subdirectory for the chroot environment
mkdir -p "$SUB_DIR"
mount -t tmpfs none "$SUB_DIR"

# Backup current mirrorlist
MIRRORLIST_BACKUP="/etc/pacman.d/mirrorlist.bak"
cp /etc/pacman.d/mirrorlist "$MIRRORLIST_BACKUP"

# Modify mirrorlist
echo "Server = $MIRROR_URL/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist

# Bootstrap the Arch Linux system, auto-accept defaults
yes '' | pacstrap -i "$SUB_DIR" $PACKAGES

# Basic configuration
arch-chroot "$SUB_DIR" /bin/bash -c "
    ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
    hwclock --systohc
    echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
    locale-gen
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf
    echo 'arch-chroot' > /etc/hostname
    echo '127.0.1.1 arch-chroot.localdomain arch-chroot' >> /etc/hosts
    systemctl enable NetworkManager
    systemctl enable gdm
"

# Cleanup
umount "$SUB_DIR"
rm -rf "$SUB_DIR"

# Restore original mirrorlist
mv "$MIRRORLIST_BACKUP" /etc/pacman.d/mirrorlist

# End timer and display installation time
end_time=$(date +%s)
install_time=$((end_time - start_time))
echo "Arch Linux chroot has been set up at $SUB_DIR"
echo "Total installation time: $install_time seconds"

# End of the script
