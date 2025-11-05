# ECU-1270 Yocto Layer introduction

The goal of this project is to open source the Advantech ECU-1270 Linux project.
We intend to release our changes as a yocto meta-layer on top of the standard TI Yocto project, so customizations would be more obvious.

## Download standard TI Yocto project and setup environment

```sh
> git clone https://git.ti.com/git/arago-project/oe-layersetup.git ti-yocto
> cd ./ti-yocto/ && ./oe-layertool-setup.sh -f configs/processor-sdk-linux/processor-sdk-linux-10_01_08_01.txt
> cd ./build/ && source ./conf/setenv
> export MACHINE=j722s-ecu1270  
```

> [!NOTE]
> reference: https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-am67/09_02_00_04/exports/docs/linux/Overview_Building_the_SDK.html

## Add the ECU-1270 customized meta layer

Download the yocto meta layer from this git repostory and place it under the "source" directory

```sh
> ls ../sources/meta-ecu-1270/conf/machine/
j722s-ecu1270.conf  j722s-ecu1270-k3r5.conf  j722s.inc

> bitbake-layers add-layer ../sources/meta-ecu-1270/
```

## Build Yocto

> [!NOTE]
> On Ubuntu 24.04 hosts, AppAromor settings needs to be adjusted before building Yocto.
> 
> ```console
> foo@bar:~/$ sudo sh -c 'echo 0 > /proc/sys/kernel/apparmor_restrict_unprivileged_userns'
> ```

> [!TIP]
> Edit __local.conf__ based on your host resource.  
> Building Yocto, with the default configure, is very memory consuming. At least 32 GBytes of RAM will be needed.  
> With insufficient RAM, the building process will fail.
> Therefore, limiting the maximum parallel processes allowed, migth be a good idea.
> One may do so by adding the following parameters to **"build/config/local.conf"**
> 
> ```sh
> PARALLEL_MAKE = "-j 2"
> BB_NUMBER_THREADS = "2"
> ```

```sh
> bitbake -k tisdk-base-image
```

The image will be located in the "build/tmp/eploy-ti/images/j722s-ecu1270/" folder.  
The wic image is named: tisdk-base-image-j722s-ecu1270.rootfs.wic.xz  

## Build Kernel only (linux-imx or virtual/kernel)

```sh
> bitbake linux-ti-staging
```

## Deploy Yocto image to SD

```sh
> xzcat tisdk-base-image-j722s-ecu1270.rootfs.wic.xz | sudo dd of=/dev/sdb bs=1M iflag=fullblock oflag=direct conv=fsync
```

# Setup SecureBoot

## Setup environment

A tool called "OTP_KEYWRITER" will be needed to setup SecureBoot.  
This tool is actually an addon app to the "MCU+ SDK for J722S"; therefore, 
Start by downloading the [PROCESSOR-SDK-RTOS-J722S](https://www.ti.com/tool/PROCESSOR-SDK-J722S) tar file, and the "MCU_PLUS_SDK" folder can be found inside.  
It also depends on [CCS](https://www.ti.com/tool/CCSTUDIO) and [SYSCONFIG](https://www.ti.com/tool/SYSCONFIG).  
Download and install them to the default loacation at "~/ti/", which we will refer as "MCU_PLUS_SDK_INSTALL_DIR" in the future.  

## Install keywriter

The OPT_KEYWRITER will be built spacific for each CPU arch, access the correct version via this portal: [https://www.ti.com/drr/opn/J7X-RESTRICTED-SECURITY](https://www.ti.com/drr/opn/J7X-RESTRICTED-SECURITY)   
This is a restricted software resource that requires a TI portal account & approval to access.  
After the correct OTP_KEYWRITER is aquired, at location <MCU_PLUS_SDK_INSTALL_DIR>/source , create an empty folder called "security" . Install the addon package at this location.  

## Build Keywriter Certificates

Go to the directory: <MCU_PLUS_SDK_INSTALL_DIR>/source/security/sbl_keywriter/scripts/cert_gen/j722s/
Create the Certificates with the following command:  

```sh
> ./gen_keywr_cert.sh -g
> cp -rf keys/* keys_devel/
```

These files are also required by the Yocto project to sign the certified binaries, copy them to the "keys" folder under this "meta-ecu-1270" layer.

### Make a copy to the meta-ecu-1270/u-boot recipe

```sh
> cp -rf keys_devel <YOCTO_PATH>/sources/meta-ecu-1270/recipes-bsp/u-boot/files/keys/
```

## Build the tiboot3 binary running OTP_KEYWRITER

> [!NOTE]
> __tiboot3.bin__ is the first executed code, running on the R5 core, acting as the first executed code during the boot process.  
> TI uses this as the platform the run the OTP_KEYWRITER app to access the OTP registers.  
> The tiboot3.bin created during this proccess is used to lockdown the CPU, making it switch to HS(High Security) mode. it cannot be used to boot into linux.  
> After locking down the CPU remember to swap the tiboot3.bin in the "boot/" partition back to the one created by the yocto project.

Create a tiboot3.bin by following the commands listed below, and copy it to a bootable SD created by the previous WIC image.

```sh
> cd <MCU_PLUS_SDK_INSTALL_DIR>/ti_mcu_sdk/ti-processor-sdk-rtos-j722s-evm-11_00_00_06/mcu_plus_sdk_j722s_11_00_00_12/source/security/sbl_keywriter/scripts/cert_gen/j722s
> ./gen_keywr_cert.sh -t tifek/SR_10/ti_fek_public.pem --msv 0xC0FFE -b keys_devel/v15/bmpk.pem --bmek keys_devel/bmek.key -s keys_devel/v15/smpk.pem --smek keys_devel/smek.key --keycnt 2 --keyrev 1
> cd <MCU_PLUS_SDK_INSTALL_DIR>/ti_mcu_sdk/ti-processor-sdk-rtos-j722s-evm-11_00_00_06/mcu_plus_sdk_j722s_11_00_00_12/source/security/sbl_keywriter/j722s-evm/wkup-r5fss0-0_nortos/ti-arm-clang
> make -sj clean PROFILE=debug
> make -sj PROFILE=debug
```

Before powering up the ECU unit, put a Jumper on __CN78__, and boot with the new tiboot3.bin and the following console output indicates the OTP has been programmed successfully.

```sh
Starting Keywriting
Enable VPP
DMSC Version 10.1.11-v10.01.11_j722s_keywriter
DMSC Firmware revision 0xa
DMSC API revision 4.0

keys Certificate found: 0x43c56280
Keywriter Debug Response: 0x0
Success Programming Keys
```

Afterwards, unplug the power and remove the jumper on __CN78__.

## Setup key files for Yocto

Create files by using OpenSSL utils to process the files, which we've copied from a [previous step](###Make a copy to the meta-ecu-1270/u-boot recipe)  

```sh
> cd <YOCTO_PATH>/sources/meta-ecu-1270/recipes-bsp/u-boot/files/keys/
> cp keys_devel/v15/smpk.pem ./custMpk.pem 
> cp custMpk.pem  custMpk.key
> openssl req -batch -new -x509 -key custMpk.key -out custMpk.crt
```

## Rebuild Yocto with Secure Boot

Use the following commands to clean build Yocto for creating a signed image.  

```sh
> bitbake -c cleansstate ti-k3-secdev-native u-boot-ti-staging ti-dm-fw trusted-firmware-a optee-os linux-ti-staging
> bitbake u-boot-ti-staging
> bitbake -c deploy mc:k3r5:u-boot-ti-staging   
```

## Preparing the SD image

> [!NOTE]
> For secure boot please notice that we need to copy the tiboot3 with the **hs**(High Security) tag, created by the Yocto project.

Uboot with Secure boot enabled will require to kernel and device tree to be encapsulated as a FIT file.  
Copy the newly generated images to the SD boot partition.  

```sh
> cd <YOCTO_PATH>/build/deploy-ti/images/j722s-ecu1270
> cp fitImage--*.bin <SD_MNT_PATH>/boot/fitImage
> cp tiboot3-j722s-hs-evm.bin <SD_MNT_PATH>/boot/tiboot3.bin
> cp tispl.bin-j722s-ecu1270-* <SD_MNT_PATH>/boot/tispl.bin
> cp u-boot-j722s-ecu1270-*.img <SD_MNT_PATH>/boot/u-boot.img
> cp uEnv.txt <SD_MNT_PATH>/boot/uEnv.txt
```

## U-Boot Boot Command

The U-Boot can boot into the fit image and reference the device tree with the following commands:  

```sh
> setenv bootargs console=ttyS2,115200 root=/dev/mmcblk1p2 rw rootwait rootfstype=ext4
> load mmc 1:1 0x90000000 fitImage
> bootm 0x90000000#conf-ti_k3-j722s-ecu1270.dtb
```

# Setup RAUC for firmware update service

## Environment setup & Build

Setup the RAUC layer, create a new CA, and build the image with the following commands.   

```sh
> cd <YOCTO_PATH>/source
> git clone https://github.com/rauc/meta-rauc -b scarthgap
> cd ../build
> bitbake-layers add-layer ./meta-rauc/
> cd ../source/meta-ecu-1270/recipes-core/rauc/files
> openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -keyout key.pem -out ca.cert.pem
> cd <YOCTO_PATH>/build
> bitbake -k tisdk-base-image
```

## Prepare Bootable SD card

> [!Caution]
> the following demo assumes that __sdb__ is the SD card,  
> change according to your system setup.

> [!NOTE]
> The same procedure can be modifed to prepare the eMMC.  
> boot the device with a bootble SD card, and switch "/dev/sdb" to "/dev/mmcblk0", and "/dev/sdb*" to "/dev/mmcblk0p*".  

1. __Partition and Formate SD__
   
   ```sh
   > umount /dev/sdb*
   > parted -s /dev/sdb mklabel msdos
   > parted -s /dev/sdb mkpart primary fat16 1049kB 135MB
   > parted -s /dev/sdb mkpart primary ext4 135MB 3135MB
   > parted -s /dev/sdb mkpart primary ext4 3135MB 6135MB
   > mkfs.vfat /dev/sdb1 -n boot
   > mkfs.ext4 /dev/sdb2 -L rootfs0
   > mkfs.ext4 /dev/sdb3 -L rootfs1
   > parted -s /dev/sdb set 1 lba on
   > parted -s /dev/sdb set 1 boot on
   ```

2. __Copy Files to SD__  
   mount the newly partitioned SD and copy files to the corresponding locations with the following commands:   
   
> [!NOTE]
>  If the target CPU has HS(high security, wich is required for running secure boot) enabled.
> Copy the tiboot3 marked with the **hs** tag(tiboot3-j722s-hs-evm.bin) instead.
   
   ```sh
   > cd <YOCTO_PATH>/build/deploy-ti/images/j722s-ecu1270
   > cp ./tiboot3.bin <SD_MNT_PATH>/boot
   > cp ./tispl.bin <SD_MNT_PATH>/boot
   > cp ./u-boot.img <SD_MNT_PATH>/boot
   > tar Jxf tisdk-base-image-j722s-ecu1270.rootfs.tar.xz -C <SD_MNT_PATH>/rootfs0
   > tar Jxf tisdk-base-image-j722s-ecu1270.rootfs.tar.xz -C <SD_MNT_PATH>/rootfs1
   ```
   
   unmout the SD card and it should be ready to boot.  
   
   ## Create RAUC bundle

3. Installing RAUC on the host PC, referencing: https://github.com/rauc/rauc/tree/v1.14?tab=readme-ov-file#building-from-sources  

4. Generate rootfs.ext4  
   Create a EXT4 image with the following commands:  
   
   ```sh
   > cd <YOCTO_PATH>/build/deploy-ti/images/j722s-ecu1270
   > mkdir mountpoint
   > mkdir content-dir
   > mkdir rootfs
   > tar Jxf tisdk-base-image-j722s-ecu1270.rootfs.tar.xz -C rootfs
   > sudo dd if=/dev/zero of=./rootfs.ext4 bs=1M count=1024
   > sudo mkfs.ext4 ./rootfs.ext4
   > sudo mount -t ext4 rootfs.ext4 mountpoint
   > sudo cp -r rootfs/* mountpoint
   > sudo umount mountpoint
   > sudo mv ./rootfs.ext4 ./content-dir
   ```

5. Generate manifest.raucm & bundle  
   
   ```sh
   > cat >> content-dir/manifest.raucm << EOF
   [update]
   compatible=Advantech
   version=$version
   [bundle]
   format=verity
   [image.rootfs]
   filename=rootfs.ext4
   EOF
   > rauc --cert ca.cert.pem --key key.pem bundle content-dir/ update.raucb -d
   ```

## Firmware Upate with RAUC(on the embedded device)

 The following commands demonstrate a remote firmware update via http on a SD booting from system0, ready to update to system1 

```sh
> rauc status 
=== System Info ===
Compatible: Advantech
Variant:
Booted from: rootfs.0 (system0)

=== Bootloader ===
Activated: rootfs.0 (system0)
 ... 

> umount /dev/mmcblk1p3
> rauc install -d http://IP_ADDR/update.raucb 
> e2fsck -f /dev/mmcblk1p3
> resize2fs /dev/mmcblk1p3
> rauc status
=== System Info ===
Compatible: Advantech
Variant:
Booted from: rootfs.0 (system0)

=== Bootloader ===
Activated: rootfs.1 (system1)

=== Slot Status ===
...
```
