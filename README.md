# ECU-1270 Yocto Layer introduction

The goal of this project is to open source the Advantech ECU-1270 Linux project.
We intend to release our changes as a yocto meta-layer on top of the standard TI Yocto project, so customizations would be more obvious.

## Download standard TI Yocto project and setup environment

```sh
> git clone https://git.ti.com/git/arago-project/oe-layersetup.git ti-yocto
> cd ./ti-yocto/ && ./oe-layertool-setup.sh -f configs/processor-sdk-linux/processor-sdk-linux-11_01_02_01.txt
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

# Setup HDMI Display

If you need desktop software and graphical services, use `tisdk-default-image` as the build target:

```sh
> bitbake tisdk-default-image
```

After the build completes, deploy the image to an SD card and boot the system. Once booted, connect an HDMI cable to a display and the system will automatically show the Weston graphical interface.

> [!Note]
> Due to Weston's pointer and keyboard operation mechanism, you must connect both a mouse and a keyboard simultaneously to properly focus on the terminal and input text normally.

In the Weston desktop environment, you can open a terminal and run Qt example applications. 

### Quick Testing Method

```bash
# List common test examples
ls /usr/share/examples/widgets/widgets/

# Run calculator example
QT_QPA_PLATFORM=wayland /usr/share/examples/widgets/widgets/calculator/bin/calculator
```
## Create SDK for Yocto
```console
foo@bar:~/yocto/build$ bitbake -c populate_sdk tisdk-base-image
foo@bar:~/yocto/build$ sh ./deploy-ti/sdk/arago-2025.01-toolchain-2025.01.sh
Arago SDK installer version 2025.01
===================================
Enter target directory for SDK (default: /opt/arago-2025.01): ~/my_sdk
You are about to install the SDK to "/home/foo/test/my_sdk". Proceed [Y/n]? y
Extracting SDK...................................................................................................................................................................................................................done
Setting it up...done
SDK has been successfully set up and is ready to be used.
Each time you wish to use the SDK in a new shell session, you need to source the environment setup script e.g.
 $ . /home/foo/my_sdk/environment-setup-aarch64-oe-linux
foo@bar:~/yocto/build$ . environment-setup-aarch64-oe-linux
foo@bar:~/yocto/build$ make modules_prepare -C $SDKTARGETSYSROOT/usr/src/kernel

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

# RAUC OTA (A/B update)

`meta-ecu-1270` includes built-in RAUC A/B OTA support. All RAUC-related variables are centralized in `conf/include/j722s-ecu1270-rauc.inc`. A single toggle in `local.conf`, combined with a one-time key generation, is all that is needed to build and deploy OTA bundles — there is no manual partitioning, `manifest.raucm`, or `rauc bundle` step anymore.

> [!NOTE]
> RAUC lives in the separate `meta-rauc` layer. If you have not added it yet:
> ```sh
> > cd <YOCTO_PATH>/sources
> > git clone https://github.com/rauc/meta-rauc -b scarthgap
> > cd <YOCTO_PATH>/build
> > bitbake-layers add-layer ../sources/meta-rauc/
> ```

## 1. Enable / Disable RAUC

Edit `build/conf/local.conf`:

```sh
# Enable RAUC OTA (default: disabled)
RAUC_ENABLED = "1"
```

When disabled, U-Boot boots via `normal_bootcmd` (a fixed single rootfs on `p2`); when enabled, U-Boot boots via `rauc_bootcmd` (A/B slot selection with a try-counter).

## 2. One-time: Generate signing keys (**never store inside the layer**)

Keys are kept outside the layer at `${HOME}/.config/rauc-keys-ecu1270/` to prevent accidental commits or leaks. Only the public CA certificate (`ca.cert.pem`) is copied into the layer; the private signing key never enters version control.

```console
foo@bar:~$ export KEYS=${HOME}/.config/rauc-keys-ecu1270
foo@bar:~$ mkdir -p ${KEYS} && chmod 700 ${KEYS}
foo@bar:~$ cd ${KEYS} && bash <YOCTO_PATH>/sources/meta-rauc/scripts/openssl-ca.sh
foo@bar:~/.config/rauc-keys-ecu1270$ cp openssl-ca/dev/ca.cert.pem                    ca.cert.pem
foo@bar:~/.config/rauc-keys-ecu1270$ cp openssl-ca/dev/development-1.cert.pem         dev.cert.pem
foo@bar:~/.config/rauc-keys-ecu1270$ cp openssl-ca/dev/private/development-1.key.pem  dev.key.pem
foo@bar:~/.config/rauc-keys-ecu1270$ chmod 600 *.key.pem
foo@bar:~/.config/rauc-keys-ecu1270$ cp ca.cert.pem <YOCTO_PATH>/sources/meta-ecu-1270/recipes-core/rauc/files/ca.cert.pem
```

> The bundle recipe (`recipes-core/bundles/update-bundle.bb`) defaults to
> `${HOME}/.config/rauc-keys-ecu1270/` via `?=`. To use a different path (CI / HSM),
> override `RAUC_KEYS_DIR = "..."` in `local.conf`.

## 3. Build the A/B image and bundle

```console
foo@bar:~/yocto/build$ bitbake tisdk-base-image   # includes rauc, rauc-conf, libubootenv-bin, A/B config
foo@bar:~/yocto/build$ bitbake update-bundle      # produces the signed .raucb bundle
```

Build artifacts (in `build/deploy-ti/images/j722s-ecu1270/`):
- rootfs tarball: `tisdk-base-image-j722s-ecu1270.rootfs.tar.xz`
- bootloader:     `tiboot3.bin`, `tispl.bin`, `u-boot.img`  (TI K3 boot chain — not a single `imx-boot` blob)
- kernel FIT:     `fitImage`
- OTA bundle:     `update-bundle-j722s-ecu1270.raucb`

> [!IMPORTANT]
> The default `*.wic.xz` produced by `tisdk-base-image` is a **single-rootfs** layout and is
> **not** compatible with RAUC A/B. To produce the required **4-partition** layout —
> `p1 = FAT boot` / `p2 = rootfs A` / `p3 = rootfs B` / `p4 = /data` — on SD or eMMC, use
> `tools/flash/j722s-ecu1270_flash.sh --rauc` instead of `dd`/`bmaptool`/wic (see step 4).
> (Note: ECU-1270 has a **separate FAT boot partition** on TI K3, so it is 4 partitions
> vs. ECU-150v2's 3.)

Verify the bundle signature on the build host:

```console
foo@bar:~$ rauc info --keyring=${KEYS}/ca.cert.pem \
    <YOCTO_PATH>/build/deploy-ti/images/j722s-ecu1270/update-bundle-j722s-ecu1270.raucb
```

## 4. Flash the A/B layout to SD / eMMC

> [!NOTE]
> On ECU-1270 (TI J722S), the on-board eMMC is `mmcblk0` and the SD card slot is `mmcblk1`
> — this is the **opposite** of the NXP-based ECU-150v2. The correct device is detected at
> runtime from `/proc/cmdline` by `rauc-setup-env.service`, so nothing here is hard-coded.

`tools/flash/j722s-ecu1270_flash.sh --rauc` creates `p1 boot (FAT)` / `p2 rootfs A` / `p3 rootfs B` / `p4 /data` (rootfs/data all ext4), copies the TI boot chain (`tiboot3.bin` / `tispl.bin` / `u-boot.img`) onto the FAT boot partition, and extracts the rootfs tarball into slot A. Slot B is left **empty** for the first OTA install, and any `.raucb` passed via `--bundle` is pre-staged onto `/data`.

```console
foo@bar:~/yocto$ sudo ./scripts/flash-sd/j722s-ecu1270_flash.sh \
    --rauc \
    --disk   /dev/sdX \
    --images build/deploy-ti/images/j722s-ecu1270 \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz \
    --bundle update-bundle-j722s-ecu1270.raucb
```

> [!CAUTION]
> Replace `/dev/sdX` with the actual target device (`/dev/sdb` for a USB SD reader, or
> `/dev/mmcblk0` when writing to the on-board eMMC from a device already booted off SD).
> Double-check the device — the script wipes the entire disk.

> [!NOTE]
> If the target CPU is fused to **HS (High Security)**, pass `--hs-se` so the script uses the
> `tiboot3-j722s-hs-evm.bin` boot binary instead of the default HS-FS one. Run the script with
> `--help` to see all options (partition sizes, overlay data partition, Ubuntu base rootfs, etc.).

## 5. OTA install on target

Copy the bundle to the target (or serve it over HTTP — see the Adaptive Update section),
then install it:

```console
foo@bar:~$ scp update-bundle-j722s-ecu1270.raucb root@<target>:/tmp/
```

```console
root@j722s-ecu1270:~$ rauc status                       # confirm current slot (e.g. booted from system0 / A)
root@j722s-ecu1270:~$ rauc install /tmp/update-bundle-j722s-ecu1270.raucb
root@j722s-ecu1270:~$ fw_printenv BOOT_ORDER            # inactive slot moved to the front
root@j722s-ecu1270:~$ reboot
```

After reboot, the U-Boot console prints `Running RAUC bootcmd ...` followed by the selected
slot. Once Linux is up, confirm the new slot is active:

```console
root@j722s-ecu1270:~$ rauc status                       # booted from the newly installed slot
```

If the new slot fails to boot, the U-Boot try-counter (`BOOT_system0_LEFT` / `BOOT_system1_LEFT`, default 3 attempts each) automatically rolls back to the previously good slot. Use `rauc status mark-good` after a successful boot to reset the counter.

## 6. Identifying bundle versions

The bundle recipe defaults to `RAUC_BUNDLE_VERSION = "${DATETIME}"`. After installation, `rauc status` displays the `bundle-version` per slot. To embed additional metadata (e.g. git hash, build ID), edit `recipes-core/bundles/update-bundle.bb`.

---

# RAUC Adaptive Update (delta OTA via HTTP streaming)

Adaptive update is an optional extension on top of the standard A/B OTA. When enabled, RAUC compares the incoming bundle against the **currently installed slot** and only transfers the changed 4 KiB blocks over the network — significantly reducing bandwidth and install time for incremental updates.

## Prerequisites

- `RAUC_ENABLED = "1"` must already be set (adaptive is an extension of the base RAUC feature).
- The target SD/eMMC must already be flashed with the RAUC A/B layout — same as
  [step 4 of the RAUC OTA section](#4-flash-the-ab-layout-to-sd--emmc), using
  `tools/flash/j722s-ecu1270_flash.sh --rauc`. Adaptive update only changes how the bundle is
  *transferred*, not how the SD card is initially prepared, so there is no separate flashing
  procedure here.
- The HTTP server serving the bundle **must support Range Requests** (responds with HTTP `206`).
  Use nginx — it supports Range Requests out of the box and is the recommended server for this
  workflow.
- The kernel needs `dm-verity`, `loop`, `squashfs`, and `NBD` support. These are already
  provided by the resident `recipes-kernel/linux/files/rauc.cfg` fragment.

## 1. Enable adaptive update

Edit `build/conf/local.conf`:

```sh
# Enable RAUC OTA (required base)
RAUC_ENABLED = "1"

# Enable adaptive delta update (default: disabled)
RAUC_ADAPTIVE_ENABLED = "1"
```

Enabling adaptive automatically switches the bundle format to `verity` and sets `IMAGE_ROOTFS_ALIGNMENT = "4"`. (A guard in the SSOT fails the build if `RAUC_ADAPTIVE_ENABLED=1` is set without `RAUC_ENABLED=1`.)

## 2. Build the adaptive bundle

No changes to the build commands — the toggle is fully transparent:

```console
foo@bar:~/yocto/build$ bitbake tisdk-base-image
foo@bar:~/yocto/build$ bitbake update-bundle
```

Verify the bundle contains the adaptive metadata (`${KEYS}` — see RAUC OTA step 2):

```console
foo@bar:~$ rauc info --keyring=${KEYS}/ca.cert.pem \
    build/deploy-ti/images/j722s-ecu1270/update-bundle-j722s-ecu1270.raucb
```

## 3. Serve the bundle over HTTP

The bundle must be served by an HTTP server that supports Range Requests. The recommended
approach is nginx:

```console
foo@bar:~$ sudo apt-get install -y nginx
foo@bar:~$ sudo tee /etc/nginx/sites-available/rauc-bundle <<'EOF'
server {
    listen 8080;
    root /path/to/build/deploy-ti/images/j722s-ecu1270;
    location / { sendfile off; autoindex on; }
}
EOF
foo@bar:~$ sudo ln -sf /etc/nginx/sites-available/rauc-bundle \
               /etc/nginx/sites-enabled/rauc-bundle
foo@bar:~$ sudo rm -f /etc/nginx/sites-enabled/default
foo@bar:~$ sudo nginx -t && sudo systemctl restart nginx
```

## 4. Install via streaming on target

Replace `<server-ip>` with the build host's IP address. The `:8080` port must match the `listen` directive in the nginx config above.

```console
root@j722s-ecu1270:~$ rauc status                       # confirm current slot before install
root@j722s-ecu1270:~$ rauc install http://<server-ip>:8080/update-bundle-j722s-ecu1270.raucb
...
99% Copying image to rootfs.1 done.
99% Updating slots done.
100% Installing done.
idle
Installing `http://<server-ip>:8080/update-bundle-j722s-ecu1270.raucb` succeeded
root@j722s-ecu1270:~$ fw_printenv BOOT_ORDER            # inactive slot moved to the front
root@j722s-ecu1270:~$ reboot
```

After reboot, confirm the new slot is active:

```console
root@j722s-ecu1270:~$ rauc status                       # booted from the newly installed slot
```

## 5. Verify delta transfer (optional)

On the build host, inspect the nginx access log while the install is in progress. A successful adaptive install produces many `206` lines — one per fetched block range — rather than a single large `200` transfer:

```console
foo@bar:~$ tail -f /var/log/nginx/access.log
# expect lines like:  "GET /update-bundle-j722s-ecu1270.raucb HTTP/1.1" 206 4096
```

On the target, run with `--debug` to see the reused / fetched block counts reported by RAUC:

```console
root@j722s-ecu1270:~$ rauc --debug install http://<server-ip>:8080/update-bundle-j722s-ecu1270.raucb \
    2>&1 | tee /tmp/rauc-adaptive.log
```

---

# Appendex

1. [Building Ubuntu/Debian root file systems.](./DebianRootfsOnTiYocto_en.md)