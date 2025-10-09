#!/bin/sh

echo "Advantech Start RAUC boot checking..."

cmdline=$(cat /proc/cmdline)

if echo "$cmdline" | grep -q "root=/dev/mmcblk0"; then
        echo "boot from EMMC"
        cp /etc/rauc/system_emmc.conf /etc/rauc/system.conf
	PART=/dev/mmcblk0p1

elif echo "$cmdline" | grep -q "root=/dev/mmcblk1"; then
        echo "boot from SD"
        cp /etc/rauc/system_sd.conf /etc/rauc/system.conf
	PART=/dev/mmcblk1p1

else
        echo "can't find boot source"
	exit 1
fi

MNT=$(lsblk -no MOUNTPOINT $PART | head -n1)
echo "MNT is $MNT"
if [ -n "$MNT" ]; then
    echo "$MNT/uboot.env 0x0 0x40000" > /etc/fw_env.config
else
    echo "Warning: $PART not mounted, fallback to device path"
    echo "$PART/uboot.env 0x0 0x40000" > /etc/fw_env.config
fi

echo "rauc mark good after env setting and restart rauc"
rauc status mark-good
systemctl restart rauc
