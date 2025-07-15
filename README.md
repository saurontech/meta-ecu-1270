
## Download standard TI Yocto project and setup environment

```sh
> git clone https://git.ti.com/git/arago-project/oe-layersetup.git ti-yocto
> cd ./ti-yocto/ && ./oe-layertool-setup.sh -f configs/processor-sdk-linux/processor-sdk-linux-10_01_08_01.txt
> cd ./build/ && source ./conf/setenv

> export MACHINE=j722s-evm
> bitbake -k tisdk-base-image

#https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-am67/09_02_00_04/exports/docs/linux/Overview_Building_the_SDK.html
```

## Add the ECU-1270 customized metal layer
Download the yocto meta layer from this git repostory and place it under the "source" directory
```sh
> ls ../sources/meta-ecu-1270/conf/machine/
j722s-ecu1270.conf  j722s-ecu1270-k3r5.conf  j722s.inc

> bitbake-layers add-layer ../sources/meta-ecu-1270/
```
## Build Yocto
```sh
> bitbake -k tisdk-base-image
```
The image will be located in the "build/tmp/eploy-ti/images/j722s-ecu1270/" folder.  
The wic image is named: tisdk-base-image-j722s-ecu1270.rootfs.wic.xz  

## Build Kernel only (linux-imx or virtual/kernel)

```sh
> bitbake linux-ti-staging
or
> bitbake virtual/kernel

```
## Deploy Yocto image to SD
```sh
> xzcat tisdk-base-image-j722s-ecu1270.rootfs.wic.xz | sudo dd of=/dev/sdc bs=1M iflag=fullblock oflag=direct conv=fsync
```

