#!/bin/sh
# Build VMs for Linux and RaspberryPi OS under their respective Qemu images

# Remove virtual disk if it exists
rm -f qemu/host.img

# Create an empty virtual disk image
qemu-img create qemu/host.img 500M
mkfs.ext2 qemu/host.img

# Mount it
mkdir -p /tmp/host
fuseext2 -o rw+ qemu/host.img /tmp/host

# Copy necessary files
mkdir -p /tmp/host/linux+pi
mkdir -p /tmp/host/linux+pi/libs
cp * /tmp/host/linux+pi
cp libs/* /tmp/host/linux+pi/libs
cp -r ../vm /tmp/host

# Create build scripts
echo "cd /host/linux+pi; sudo ./buildVMRaspberryPi.sh; sudo shutdown -h now" > /tmp/host/raspi-script.sh
echo "cd /host/linux+pi; ./buildVMLinux.sh; shutdown -h now" > /tmp/host/linux-script.sh
chmod +x /tmp/host/raspi-script.sh
chmod +x /tmp/host/linux-script.sh

# Unmount the virtual disk image
fusermount -u /tmp/host

# Launch Qemu virtual machines.
# They will automatically mount the host image, log in and run their respective build scripts.

# remove -nographic from both when not in deploy server

### Launch RaspberryPi Qemu VM ###
qemu-system-arm -kernel qemu/kernel-qemu-4.4.34-jessie -cpu arm1176 -m 256 -M versatilepb -k es -append "panic=-1 root=/dev/sda2 rootfstype=ext4 rw" -hda qemu/raspbian-jessie-lite.img -hdb qemu/host.img -no-reboot -nographic

### Launch Linux Qemu VM ###
qemu-system-x86_64 -m 512 -hda qemu/ubuntu16.04.img -k es -hdb qemu/host.img -nographic

# Mount the virtual disk image again
fuseext2 -o rw+ qemu/host.img /tmp/host
# Copy the compiled MicroBlocks VMs out of the virtual disk image
cp /tmp/host/linux+pi/vm.linux.* .
# Unmount the virtual disk again
fusermount -u /tmp/host
