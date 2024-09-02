
Make sure everything is unmounted

```bash
export ROOTFS="/tmp/installing-rootfs"
sudo umount ${ROOTFS}/{dev/pts,boot/efi,boot,dev,run,proc,sys,tmp,}
sudo losetup -D 
```

Mount for debug
```bash
export DEVICE=/dev/loop0
export ROOTFS="/tmp/installing-rootfs"
export INPUT_IMG=usb.raw
sudo losetup -fP $INPUT_IMG
sudo mkdir -p ${ROOTFS}
sudo mount ${DEVICE}p1 ${ROOTFS}
sudo mount ${DEVICE}p15 ${ROOTFS}/boot/efi

```

Build image


```bash
rm debian-12-nocloud-amd64.raw
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.raw

sudo ./build.sh debian-12-nocloud-amd64.raw d12-full.raw apham $PASS authorized_keys 1 1 1 5G
sudo ./build.sh debian-12-nocloud-amd64.raw d12-min.raw apham $PASS authorized_keys 0 0 1 4G
sudo ./build.sh debian-12-nocloud-amd64.raw d12-kube.raw apham $PASS authorized_keys 0 1 1 4G

./build.sh x x apham password authorized_keys 1 1 1 5G 1 0

scp d12-full.raw awon:/home/apham/apps/static/data
scp d12-min.raw awon:/home/apham/apps/static/data
scp d12-kube.raw awon:/home/apham/apps/static/data
```

create qcow and vhd images

```bash
sudo ./make-vm-disk.sh d12-full.raw sb 30G 192.168.199.10/24
sudo ./make-vm-disk.sh d12-full.raw dt 60G 192.168.199.20/24

```

create usb livedisk

```bash
sudo ./make-usb.sh d12-min.raw usb
qemu-img convert -f raw -O vpc usb.raw usb.vhd

```

