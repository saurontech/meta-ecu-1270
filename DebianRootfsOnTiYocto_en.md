# ECU-1270: TI Kernel and Debian/Ubuntu RootFS Integration Guide

## Overview

This document describes how to integrate the official TI Yocto Kernel with a custom Debian/Ubuntu RootFS on the TI AM62x/J722S platform to achieve a more flexible system configuration. This solution preserves the integrity of TI hardware support while providing the advantages of the standard Debian ecosystem.

## System Architecture

This integration solution uses the following system components:

| Component        | Source      | Description                                         |
| ---------------- | ----------- | --------------------------------------------------- |
| **Bootloader**   | TI Yocto    | tiboot3.bin, tispl.bin, u-boot.img                  |
| **Kernel**       | TI Yocto    | Linux Kernel 6.6.x with TI BSP, DTS, driver modules |
| **RootFS**       | Debootstrap | Debian 12 (Bookworm) / Ubuntu 24.04 (Noble)         |
| **Image Format** | TI Yocto    | WIC (OpenEmbedded Image Creator)                    |

## Prerequisites

### Environment Requirements

- Host OS: Ubuntu 20.04+ / Debian 11+ (x86_64 or ARM64)
- Working Directory: `~/work`

### Preparation Materials

Obtain the following files from the Yocto build system:

1. **WIC Image**: `tisdk-base-image-j722s-ecu1270.rootfs.wic.xz`
   - Contains complete partition table, bootloader, and original Yocto rootfs
2. **FIT Image**: `fitImage`
   - Flattened Image Tree package containing TI Kernel, DTB...

---

## Operation Workflow

### Step 1: Extract WIC Image

Extract the pre-built Yocto WIC image:

```bash
cd ~/work
tar -xvf ecu1270_ubuntu_dataset_nov_17.tar.xz
cd ecu1270_ubuntu_dataset_nov_17
xz -dk tisdk-base-image-j722s-ecu1270.rootfs.wic.xz
```

Verify extraction results:

```bash
ls -lh
# Expected output:
# tisdk-base-image-j722s-ecu1270.rootfs.wic
# fitImage
```

---

### Step 2: Mount WIC Image Partitions

Mount the WIC image using loop device:

```bash
cd ~/work/ecu1270_ubuntu_dataset_nov_17
sudo losetup -Pf --show tisdk-base-image-j722s-ecu1270.rootfs.wic
```

Record the returned loop device (e.g., `/dev/loop2`) and verify partition structure:

```bash
lsblk /dev/loop2
```

**Expected Partition Configuration:**

| Partition | Type  | Mount Point | Purpose                            |
| --------- | ----- | ----------- | ---------------------------------- |
| loop2p1   | FAT32 | /boot       | U-Boot, MLO, environment variables |
| loop2p2   | ext4  | /           | Root filesystem                    |

---

### Step 3: Mount System Partitions

Create mount points and mount partitions:

```bash
sudo mkdir -p /mnt/yocto_{boot,rootfs}
sudo mount /dev/loop2p1 /mnt/yocto_boot
sudo mount /dev/loop2p2 /mnt/yocto_rootfs
```

Verify mount status:

```bash
df -h | grep yocto
mount | grep loop2
```

---

### Step 4: Build Debian/Ubuntu RootFS

#### 4.1 Install Required Tools

```bash
sudo apt-get update
sudo apt-get install -y qemu-user-static debootstrap debian-archive-keyring
```

#### 4.2 Create Base RootFS

Create rootfs directory:

```bash
sudo mkdir -p ~/work/ecu1270-rootfs
cd ~/work
```

**Option A: Debian 12 (Bookworm)**

```bash
sudo debootstrap --arch=arm64 --variant=minbase \
    bookworm ecu1270-rootfs http://deb.debian.org/debian
```

**Option B: Ubuntu 24.04 (Noble)**

```bash
sudo debootstrap --arch=arm64 --variant=minbase \
    noble ecu1270-rootfs http://ports.ubuntu.com/ubuntu-ports
```

#### 4.3 Configure QEMU Static Binary (for x86_64 Host)

If operating on a non-ARM64 host, configure QEMU user-mode emulation:

```bash
sudo cp /usr/bin/qemu-aarch64-static ~/work/ecu1270-rootfs/usr/bin/
```
#### 4.4 Configure RootFS Base System

Create chroot management script `~/work/ch-rootfs.sh`:

```bash
#!/bin/bash
#
function mnt() {
 echo "MOUNTING"
 sudo mount -t proc /proc ${2}proc
 sudo mount -t sysfs /sys ${2}sys
 sudo mount -o bind /dev ${2}dev
 sudo mount -o bind /dev/pts ${2}dev/pts
 sudo chroot ${2}
}
function umnt() {
 echo "UNMOUNTING"
 sudo umount ${2}proc
 sudo umount ${2}sys
 sudo umount ${2}dev/pts
 sudo umount ${2}dev
}

function pack() {
 echo "Packing rootfs to rootfs.tar.gz ...."
 sudo rm -f ../rootfs.tar.gz
 echo '=== tar rootfs start ==='
 cd $2 && sudo tar zcvf ../rootfs.tar.gz *
 echo '=== tar rootfs finish ==='
}

if [ "$1" == "-m" ] && [ -n "$2" ] ;
then
 mnt $1 $2
 umnt $1 $2
elif [ "$1" == "-u" ] && [ -n "$2" ];
then
 umnt $1 $2
elif [ "$1" == "-z" ] && [ -n "$2" ];
then
 pack $1 $2
else
 echo ""
 echo "Either 1'st, 2'nd or both parameters were missing"
 echo ""
 echo "1'st parameter can be one of these: -m(mount) OR -u(umount) or -z(pack)"
 echo "2'nd parameter is the full path of rootfs directory(with trailing '/')"
 echo ""
 echo "For example: ./ch-rootfs.sh -m /media/sdcard/"
 echo ""
 echo 1st parameter : ${1}
 echo 2nd parameter : ${2}
fi
```

Grant execute permission:

```bash
chmod +x ~/work/ch-rootfs.sh
```

Enter chroot environment and configure system:

```bash
cd ~/work
./ch-rootfs.sh -m ~/work/ecu1270-rootfs/
```

Execute inside chroot environment:

```bash
# Configure APT sources
apt update

# Install base system packages
apt install -y \
    systemd systemd-sysv \
    sudo ssh openssh-server \
    net-tools iputils-ping iproute2 ethtool \
    rsyslog bash-completion htop \
    vim nano less dialog \
    locales tzdata \
    ca-certificates \
    kmod udev \
    firmware-misc-nonfree

# Configure locales
dpkg-reconfigure locales

# Set root password
passwd

# Exit chroot
exit
```

> [!Note]
> The chroot environment requires mounting `/proc`, `/sys`, `/dev` and other virtual file systems for proper operation of package managers and systemd.

---

### Step 5: Integrate TI Kernel Modules

#### 5.1 Copy Kernel Modules

Identify kernel version in Yocto rootfs:

```bash
ls /mnt/yocto_rootfs/lib/modules/
# Example output: 6.6.44-ti-01480-geb3986191d2e
```

Create target directory and copy modules:

```bash
# Set kernel version variable (modify according to actual output)
KERNEL_VER="6.6.44-ti-01480-geb3986191d2e"

sudo mkdir -p ~/work/ecu1270-rootfs/lib/modules
sudo cp -a /mnt/yocto_rootfs/lib/modules/${KERNEL_VER} \
    ~/work/ecu1270-rootfs/lib/modules/
```

> [!Note]
> The `KERNEL_VER` variable value must match the actual output from the previous `ls` command. If the version number contains special characters, use double quotes.

#### 5.2 Rebuild Module Dependencies

Run `depmod` to generate `modules.dep` and other dependency files:

```bash
sudo depmod -a -b ~/work/ecu1270-rootfs ${KERNEL_VER}
```

Verify module dependency files:

```bash
ls -1 ~/work/ecu1270-rootfs/lib/modules/${KERNEL_VER}/ | sort
```

**Expected Output:**

```
kernel/
modules.alias
modules.alias.bin
modules.builtin
modules.builtin.alias.bin
modules.builtin.bin
modules.builtin.modinfo
modules.dep
modules.dep.bin
modules.devname
modules.order
modules.softdep
modules.symbols
modules.symbols.bin
```

---

### Step 6: Integrate TI Firmware Blobs

TI SoCs require proprietary firmware for hardware operation. Copy the complete firmware directory:

```bash
sudo cp -a /mnt/yocto_rootfs/lib/firmware \
    ~/work/ecu1270-rootfs/lib/
```

---

### Step 7: Replace RootFS in WIC Image

#### 7.1 Clear Original Yocto RootFS

```bash
sudo rm -rf /mnt/yocto_rootfs/*
```

> [!Warning]
> Ensure `/mnt/yocto_rootfs` is correctly mounted to avoid deleting host system files.

#### 7.2 Deploy Debian RootFS

Use rsync to copy while preserving permissions and attributes:

```bash
sudo rsync -a ~/work/ecu1270-rootfs/ /mnt/yocto_rootfs/
```

**rsync Parameter Explanation:**

- `-a`: archive mode, preserves permissions, timestamps, and symbolic links

#### 7.3 Install FIT Image

Create boot directory and install kernel:

```bash
sudo mkdir -p /mnt/yocto_rootfs/boot
sudo cp ~/work/ecu1270_ubuntu_dataset_nov_17/fitImage \
    /mnt/yocto_rootfs/boot/fitImage
sudo chmod 644 /mnt/yocto_rootfs/boot/fitImage
```

> [!Note]
> __TI Yocto U-Boot loads the FIT Image using the following command:__  
> 
> ```
> loadfitimage=ext4load mmc ${mmcdev}:${mmcpart} ${addr_fit} boot/${name_fit};bootm ${addr_fit}#${name_fit_config}
> ```
> 
> The FIT Image is loaded from the `/boot` directory of the rootfs partition (`mmcblk0p2`), not from the FAT32 boot partition.

---

### Step 8: Unmount and Package Image

#### 8.1 Sync and Unmount Partitions

```bash
# Force write all buffers
sudo sync

# Unmount partitions
sudo umount /mnt/yocto_boot
sudo umount /mnt/yocto_rootfs
```

#### 8.2 Detach Loop Device

```bash
sudo losetup -d /dev/loop2
```

Verify loop device is released:

```bash
losetup -a | grep loop2
# Should have no output
```

---

### Step 9: Flash to SD Card

#### 9.1 Identify Target Device

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN
# Look for the corresponding SD card device, e.g., /dev/sdd
```

#### 9.2 Unmount Existing Mount Points (if any)

```bash
sudo umount /dev/sdd* 2>/dev/null
```

#### 9.3 Execute Flashing

```bash
cd ~/work/ecu1270_ubuntu_dataset_nov_17

sudo dd if=tisdk-base-image-j722s-ecu1270.rootfs.wic \
        of=/dev/sdd \
        bs=1M \
        iflag=fullblock \
        oflag=direct \
        conv=fsync \
        status=progress

sudo sync
sudo eject /dev/sdd
```

> [!Warning] 
> Please ensure the `of=` parameter points to the correct device. An incorrect path will result in irreversible data loss.

**dd Parameter Explanation:**

- `bs=1M`: Use 1MB block size to improve write performance
- `iflag=fullblock`: Ensure complete reading of input blocks
- `oflag=direct`: Bypass kernel page cache, write directly to device
- `conv=fsync`: Execute fsync after completion to ensure data is written to disk
- `status=progress`: Display real-time progress

---

## System Deployment Results

After successful deployment, the SD card contains the following components:

| Component          | Location       | Description                             |
| ------------------ | -------------- | --------------------------------------- |
| **SPL/MLO**        | Boot partition | TI first-stage bootloader (tiboot3.bin) |
| **U-Boot**         | Boot partition | tispl.bin, u-boot.img                   |
| **FIT Image**      | /boot/fitImage | Kernel + DTB + initramfs                |
| **RootFS**         | /              | Debian 12 / Ubuntu 24.04                |
| **Kernel Modules** | /lib/modules   | TI BSP modules (v6.6.x)                 |
| **Firmware**       | /lib/firmware  | TI hardware firmware blobs              |

**Boot Sequence:**

1. ROM Code → tiboot3.bin (R5F SPL)
2. tiboot3.bin → tispl.bin (A53 SPL + ATF + OPTEE)
3. tispl.bin → u-boot.img
4. U-Boot → Load `/boot/fitImage`
5. Kernel → Mount rootfs → systemd init

---

## Appendix A: Network Configuration

### A.1 Problem Background

Debian 12 does not automatically configure network interfaces by default. Manual networking setup is required.

### A.2 Using ifupdown

Edit `/etc/network/interfaces`:

```bash
sudo nano /etc/network/interfaces
```

Add the following configuration:

```
# Loopback interface
auto lo
iface lo inet loopback

# Primary Ethernet interface (DHCP)
auto eth0
iface eth0 inet dhcp

# Or use static IP:
# auto eth0
# iface eth0 inet static
#     address 192.168.1.100
#     netmask 255.255.255.0
#     gateway 192.168.1.1
#     dns-nameservers 8.8.8.8 8.8.4.4
```

Restart network service:

```bash
sudo systemctl restart networking
sudo systemctl status networking
```

### A.3 Configure DNS Resolution

**Usage:**

```bash
sudo rm -f /etc/resolv.conf
sudo tee /etc/resolv.conf > /dev/null << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
```

### A.5 Verify Network Connectivity

```bash
# Check network interface
ip addr show eth0

# Test connectivity
ping -c 4 8.8.8.8
ping -c 4 google.com
```

---

## Appendix B: Expand RootFS to Full SD Card Capacity

### B.1 Problem Description

The default WIC image rootfs partition is typically small (approximately 2-4GB) and cannot utilize the full SD card capacity. This section describes how to expand the image file before flashing.

### B.2 Expansion Workflow

#### Step 1: Unmount and Detach Existing Loop Device

```bash
cd ~/work/ecu1270_ubuntu_dataset_nov_17

# Unmount partitions (if mounted)
sudo umount /mnt/yocto_boot /mnt/yocto_rootfs 2>/dev/null

# Detach loop device
sudo losetup -d /dev/loop2 2>/dev/null
```

Verify loop device is released:

```bash
lsblk | grep loop2
# Should have no output
```

#### Step 2: Expand WIC Image File

Expand the image file to target size (e.g., 25GB):

```bash
sudo truncate -s 25G tisdk-base-image-j722s-ecu1270.rootfs.wic
```

> [!Note]
>  The `truncate` command expands the file size but doesn't actually allocate disk space (sparse file) until data is written.

#### Step 3: Recreate Loop Device

```bash
LOOP_DEV=$(sudo losetup -Pf --show tisdk-base-image-j722s-ecu1270.rootfs.wic)
echo "Using loop device: ${LOOP_DEV}"
```

#### Step 4: Expand Partition Table

Use `parted` to adjust rootfs partition size:

```bash
sudo parted ${LOOP_DEV}
```

Execute in parted interactive interface:

```
(parted) print                           # View current partition table
(parted) resizepart 2 100%               # Expand partition 2 to file end
(parted) print                           # Verify new partition size
(parted) quit
```

> [!Note]
> 
> - `resizepart` does not move the partition start point, only adjusts the end position
> - This operation only modifies the partition table and does not affect the file system

#### Step 5: Check and Expand File System

Check file system integrity:

```bash
sudo e2fsck -f ${LOOP_DEV}p2
```

Expand ext4 file system:

```bash
sudo resize2fs ${LOOP_DEV}p2
```

**Expected Output:**

```
resize2fs 1.47.0 (5-Feb-2023)
Resizing the filesystem on /dev/loop2p2 to 6553600 (4k) blocks.
The filesystem on /dev/loop2p2 is now 6553600 (4k) blocks long.
```

#### Step 6: Cleanup

```bash
sudo losetup -d ${LOOP_DEV}
```
