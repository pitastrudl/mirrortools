#!/bin/bash

# Store the current user's username
CURRENT_USER=$(who am i | awk '{print $1}')

# # Change to the specified directory and run the Python script as the current user
# sudo -u "$CURRENT_USER" bash -c "cd /home/arun/projects/mirrortest && python -m mirrortest --mirror '$1'"
# sleep 5

# # Start timer
# start_time=$(date +%s)

# # Check for root privileges 
# if [[ $(id -u) -ne 0 ]]; then
#     echo "This script must be run as root."
#     exit 1
# fi

# URL for the Arch Linux mirror (must be passed as an argument)
MIRROR_URL="$1"

# Check if a mirror URL was provided
if [[ -z "$MIRROR_URL" ]]; then
    echo "No mirror URL provided. Please provide a mirror URL as an argument."
    exit 1
fi

# Function to check URL validity
check_url() {
    curl --output /dev/null --silent --head --fail "$1"
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
# ROOT_DIR="/mnt/arch-chroot-root"
ROOT_DIR="/tmp/mirrors"
# Unique subdirectory for this installation
SUB_DIR="${ROOT_DIR}/$(date +%Y%m%d-%H%M%S)"

# Create the unique subdirectory for the chroot environment
mkdir -p "$SUB_DIR"
mount -t tmpfs none "$SUB_DIR"

# Create a custom pacman configuration and mirrorlist
CUSTOM_PACMAN_CONF="/tmp/custom-pacman.conf"
CUSTOM_MIRRORLIST="/tmp/custom-mirrorlist"

# Copy the existing pacman.conf to the custom configuration file
cp /etc/pacman.conf "$CUSTOM_PACMAN_CONF"

# Enable parallel downloads with 5 parallel connections
sed -i '/^#ParallelDownloads = /c\ParallelDownloads = 5' "$CUSTOM_PACMAN_CONF"

# Create the custom mirrorlist with the provided mirror URL
echo "Server = $MIRROR_URL/\$repo/os/\$arch" > "$CUSTOM_MIRRORLIST"

# Update the custom pacman.conf to use the custom mirrorlist for all relevant sections
sed -i "/\[core\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
sed -i "/\[extra\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
sed -i "/\[multilib\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
cat "$CUSTOM_PACMAN_CONF"
# Bootstrap the Arch Linux system using the custom pacman configuration
yes '' | pacstrap -C "$CUSTOM_PACMAN_CONF" -i "$SUB_DIR" $PACKAGES

# Basic configuration inside the chroot
arch-chroot -N "$SUB_DIR" /bin/bash -c "
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
rm "$CUSTOM_PACMAN_CONF" "$CUSTOM_MIRRORLIST"

# End timer and display installation time
end_time=$(date +%s)
install_time=$((end_time - start_time))
echo "Arch Linux chroot has been set up at $SUB_DIR"
echo "Total installation time: $install_time seconds"

# End of the script
