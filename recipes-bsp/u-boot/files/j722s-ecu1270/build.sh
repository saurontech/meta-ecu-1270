#!/bin/sh
if [ "$1" = "" ]; then
    echo "Usage: $0 DeviceName"
    echo "Example: $0 ECU1270"
    exit 1
fi

DeviceList="ECU1270"

RET=0
for devicename in $DeviceList
do
    if [ "$devicename" = $1 ]; then
        RET=1
		break
    fi
done

if [ $RET -eq 0 ]; then
    echo "Not $1 device!"
    exit 1
fi

BASE=`pwd`
UBOOT_DIR=$BASE
TI_LINUX_FW_DIR=$BASE/../prebuilt-images
TFA_DIR=$BASE/../trusted-firmware-a-2.10+git
OPTEE_DIR=$BASE/../optee-os-4.2.0+git

OUT_DIR=Adv_$1
devicename=`echo $1 | tr A-Z a-z`
DEF_CONFIG=am64x_${devicename}_a53_defconfig
R5_DEF_CONFIG=am64x_${devicename}_r5_defconfig

if [ "$1" = "ECU1270" ]; then
    R5_DEF_CONFIG=j722s_${devicename}_r5_defconfig
    DEF_CONFIG=j722s_${devicename}_a53_defconfig
fi

# R5 build
rm -f $OUT_DIR/r5/tiboot3.bin
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE_32" $R5_DEF_CONFIG O=$OUT_DIR/r5
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE_32" O=$OUT_DIR/r5 BINMAN_INDIRS=${TI_LINUX_FW_DIR}
rm -f $OUT_DIR/r5/tiboot3.bin && cp -a $OUT_DIR/r5/tiboot3-j722s-hs-fs-${devicename}.bin $OUT_DIR/r5/tiboot3.bin

# A53 build
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE_64" $DEF_CONFIG O=$OUT_DIR/a53
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE_64" CC="$CC_64" BL31=${TI_LINUX_FW_DIR}/bl31.bin TEE=${TI_LINUX_FW_DIR}/bl32.bin O=$OUT_DIR/a53 BINMAN_INDIRS=${TI_LINUX_FW_DIR}

# copy file to $OUT_DIR/ diretory
cp -f $OUT_DIR/r5/tiboot3.bin $OUT_DIR/a53/tispl.bin $OUT_DIR/a53/u-boot.img $OUT_DIR/

exit 0

