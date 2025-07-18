#!/bin/bash

check_url() {
    curl --output /dev/null --silent --head --fail "$1/lastsync"
    return $?
}

fetch_and_convert_time() {
    # Fetches lastsync from URL and converts it
    local url="$1"
    local epoch_time

    epoch_time=$(curl -s "$url/lastsync" | head -n 1)

    if [[ "$epoch_time" =~ ^[0-9]+$ ]]; then
        echo -n "last time mirror was synced:"
        date -d "@$epoch_time"
    else
        echo "Error: Retrieved data is not a valid epoch timestamp."
    fi
}

fetch_and_convert_time "$1"

CURRENT_USER=$(who am i | awk '{print $1}')

# Assumes you have mirrortest https://github.com/Torxed/mirrortest (Needs access to T0)
sudo -u "$CURRENT_USER" bash -c "cd mirrortest && python -m mirrortest --mirror '$1'"

# Start time of mirror test
start_time=$(date +%s)

# URL for the Arch Linux mirror being tested
MIRROR_URL="$1"

if [[ -z "$MIRROR_URL" ]]; then
    echo "No mirror URL provided. Please provide a mirror URL as an argument."
    exit 1
fi

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
ROOT_DIR="/tmp/mirrors"
# Unique subdirectory for this installation
SUB_DIR="${ROOT_DIR}/$(date +%Y%m%d-%H%M%S)"

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
echo "Server = $MIRROR_URL/\$repo/os/\$arch" >"$CUSTOM_MIRRORLIST"

# Update the custom pacman.conf to use the custom mirrorlist for all relevant sections
sed -i "/\[core\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
sed -i "/\[extra\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
sed -i "/\[multilib\]/,/Include/ s|Include = .*|Include = $CUSTOM_MIRRORLIST|" "$CUSTOM_PACMAN_CONF"
#cat "$CUSTOM_PACMAN_CONF"
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
echo "Finished checking $MIRROR_URL"
