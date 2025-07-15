/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Configuration header file for K3 J722S SoC family
 *
 * Copyright (C) 2024 Texas Instruments Incorporated - https://www.ti.com/
 */

#ifndef __CONFIG_J722S_EVM_H
#define __CONFIG_J722S_EVM_H

/* Now for the remaining common defines */
#include <configs/ti_armv7_common.h>

#define FDTFILE_DEFAULT		"k3-j722s-ecu1270.dtb"

/* Initial environment variables */
#define CFG_EXTRA_ENV_SETTINGS          \
	"boot=mmc\0" 						\
	"mmcdev=0\0"						\
	"bootpart=0:1\0"					\
	"bootdir=\0"						\
	"fdt_file="FDTFILE_DEFAULT"\0" 		\
	"get_overlay_adv=fdt address ${fdt_addr_r}; fdt resize 0x100000; for overlay in $name_overlays; do; load mmc ${bootpart} ${dtboaddr} ${bootdir}/${overlay} && fdt apply ${dtboaddr}; done;\0" \
	"get_fdt_adv=load mmc ${bootpart} ${fdt_addr_r} ${fdt_file}\0" \
	"get_kern_adv=load mmc ${bootpart} ${loadaddr} ${name_kern}\0" \
	"get_fit_adv=load mmc ${bootpart} ${addr_fit} ${name_fit}\0" \
	"mmc_args=setenv bootargs console=${console} ${optargs} root=${mmcroot} rw rootfstype=${mmcrootfstype};\0" \
	"mmc_loados=" \
		"if test ${boot_fit} -eq 1; then " \
			"run get_fit_adv; run get_fit_overlaystring; run run_fit; " \
		"else " \
			"run get_kern_adv; run get_fdt_adv; run get_overlay_adv; run run_kern; " \
		"fi\0" \
	"mmc_boot=echo Booting from mmc ...; setenv mmcdev 1; setenv bootpart 1:1; setenv mmcroot /dev/mmcblk1p2; " \
		"setenv fdtfile ${fdt_file}; " \
		"run mmc_args; " \
		"mmc dev ${mmcdev}; " \
		"setenv devnum ${mmcdev}; " \
		"setenv devtype mmc; " \
		"run mmc_loados\0" \
    "emmc_boot=echo Booting from emmc ...; setenv mmcdev 0; setenv bootpart 0:1; setenv mmcroot /dev/mmcblk0p2; " \
		"setenv fdtfile ${fdt_file}; " \
		"run mmc_args; " \
		"mmc dev ${mmcdev}; " \
		"setenv devnum ${mmcdev}; " \
		"setenv devtype mmc; " \
		"run mmc_loados;\0" \
	"advufile=advupdate.txt\0" \
	"ramrootfstype=ext2 rootwait\0" \
	"loadramdisk=load mmc ${mmcdev} ${ramdisk_addr_r} ramdisk.gz\0" \
	"loadusbimage=load usb ${usbdev}:${usbpart} ${loadaddr} ${name_kern}\0" \
	"loadusbfdt=load usb ${usbdev}:${usbpart} ${fdt_addr_r} ${fdt_file}\0" \
	"loadusbramdisk=load usb ${usbdev}:${usbpart} ${ramdisk_addr_r} ramdisk.gz\0" \
	"advrargs=setenv bootargs console=${console} " \
		"${optargs} " \
		"root=/dev/ram0 rw ramdisk_size=65536 "\
		"initrd=${ramdisk_addr_r},64M " \
		"rootfstype=${ramrootfstype}\0" \
	"advrfs=echo Advantech recovery file system ramdisk ...; " \
		"setenv devnum ${mmcdev}; " \
		"setenv devtype mmc; " \
		"setenv bootpart ${mmcdev}:${mmcpart}; " \
		"setenv fdtfile ${fdt_file}; " \
		"run get_kern_adv; " \
		"run loadramdisk; " \
		"run advrargs; " \
		"if run get_fdt_adv; then " \
			"booti ${loadaddr} - ${fdt_addr_r}; " \
		"else " \
			"booti ${loadaddr};" \
		"fi;\0" \
	"advusbrfs=echo Advantech Recovery System ...; " \
		"usb start; " \
		"setenv usbdev 0; " \
		"setenv usbpart 1; " \
		"setenv devtype usb; " \
		"run advrargs; " \
		"run loadusbimage; " \
		"run loadusbramdisk; " \
		"if run loadusbfdt; then " \
			"booti ${kernel_addr_r} - ${fdt_addr_r}; " \
		"else " \
			"echo advusbrfs load image/fdt file failed!; " \
		"fi\0" \
	"get_fdt_file=" \
	    "if gpio input gpio@600000_51; then " \
	        "if gpio input gpio@600000_50; then " \
                "setenv board_id_3_2 00; " \
            "else " \
                "setenv board_id_3_2 01; " \
            "fi; " \
        "else " \
            "if gpio input gpio@600000_50; then " \
                "setenv board_id_3_2 10; " \
                "setenv fdt_file k3-j722s-ecu1270-dio.dtb; " \
            "else " \
                "setenv board_id_3_2 11; " \
            "fi; " \
		"fi;\0" \
	"bsp_bootcmd=echo Running BSP bootcmd ...; " \
		"mmc dev ${mmcdev}; " \
		"if mmc rescan; then " \
			"run get_fdt_file; " \
			"if run get_kern_adv; then " \
				"run emmc_boot; " \
			"else " \
				"run mmc_boot; " \
			"fi; " \
		"fi;\0"

#define CONFIG_SYS_USB_FAT_BOOT_PARTITION 1

#endif /* __CONFIG_J722S_EVM_H */
