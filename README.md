
## yocto 安裝 for ti

```sh
> git clone https://git.ti.com/git/arago-project/oe-layersetup.git ti-yocto
> cd ./ti-yocto/ && ./oe-layertool-setup.sh -f configs/processor-sdk-linux/processor-sdk-linux-10_01_08_01.txt
> cd ./build/ && source ./conf/setenv

> export MACHINE=j722s-evm
> bitbake -k tisdk-base-image

> devtool modify linux-ti-staging
 
#https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-am67/09_02_00_04/exports/docs/linux/Overview_Building_the_SDK.html
```

## Add meta-adv-tsu-ti

```sh
## 確認 meta 底下machine
> ls ../sources/meta-adv-tsu-ti/conf/machine/
j722s-ecu1270.conf  j722s-ecu1270-k3r5.conf  j722s.inc

> bitbake-layers add-layer ../sources/meta-adv-tsu-ti/
```

## Build Kernel (linux-imx or virtual/kernel)

```sh
> bitbake linux-ti-staging
or
> bitbake virtual/kernel

```

## copy to sd_card

```sh
> cd tmp/deploy-ti/images/j722s-ecu1270/
> cp ./Image ./fsl-j722s-ecu1270.dtb /media/yuyan/SD_CARD/
```

## 製作 rootfs

> 有兩種可以自己選擇

### yocto

```sh
> bitbake tisdk-base-image

> ls tmp/deploy-ti/images/j722s-ecu1270/

```

---

