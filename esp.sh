#!/bin/bash

set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")/esp"

# get sudo access early on
echo "Creating $(dirname "$PWD")/ESP.qcow2 ..." | sudo cat

loopback_cleanup() {
    set +e

    if [[ -n "$loop_device" ]]; then
        sudo umount build/{EFI,clover} 2>/dev/null
        sudo losetup -d "$loop_device"
    fi
}

if [[ -d build/ ]]; then
    rm -rf build/
fi

mkdir -p build/{EFI,clover}

# create the empty image
truncate -s 268435456 build/ESP.img

# detect the first free loopback device
loop_device=$(losetup -f)

# register loopback cleanup
trap loopback_cleanup EXIT

# mount the empty image
sudo losetup "$loop_device" build/ESP.img

# add the partition table
sed -e "s|/dev/nbd0|$loop_device|g" nbd0_sfdisk.txt | sudo sfdisk "$loop_device"

# reread the loopback partition table
sudo partprobe "$loop_device"

# create the EFI filesystem
sudo mkfs.fat -F16 -n"EFI" -h2048 -i"4679a914" -I "${loop_device}p1"
sudo mount "${loop_device}p1" build/EFI
sudo rsync -rltD --exclude=.gitignore nbd0p1/ build/EFI/
sudo umount build/EFI

# create the clover filesystem
sudo mkfs.fat -F16 -n"clover" -h202048 -i"4682bae0" -I "${loop_device}p2" # the source image had 202048 hidden sectors
sudo mount "${loop_device}p2" build/clover
sudo rsync -rltD --exclude=.gitignore nbd0p2/ build/clover/
sudo umount build/clover

# removing existing ESP.qcow2
if [[ -f ../ESP.qcow2 ]]; then
    rm -f ../ESP.qcow2
fi

# convert the image to qcow2
qemu-img convert -f raw -O qcow2 build/ESP.img ../ESP.qcow2

# clean up the build directory
rm -f build/ESP.img
rmdir build/{EFI,clover}
rmdir build/
