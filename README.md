# Testurl
To run testurl.sh, you need:

`pacman -Syu arch-install-scripts`

By default, it installs chroot into /tmp for increased speed when testing so if your /tmp is a tmpfs type, so mounted in RAM, you should have enough ram to fit an install of chroot inside it. For example, I have 32GB of RAM and can do 1-2 tests in parallel. I noticed one run takes around 8-9GB of RAM.

You can set some stuff in the script itself, they are hardcoded.
