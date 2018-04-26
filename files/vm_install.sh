#!/bin/bash

IMG=/var/lib/libvirt/images/ubuntu-cloud-16.04.img
VMNAME=wpserver
RAM=2048
VCPU=2
USER_D=~/bootstrap/user-data
META_D=~/bootstrap/meta-data
NET_D=~/bootstrap/network-config.yml
KEY_DIR=~/bootstrap
IMG_DIR=/var/lib/libvirt/images
INV_FILE=~/WP-cluster/wp-hosts
VAR_FILE=~/WP-cluster/group_vars/all

### check if VMs are present. Continue if not

if [ $(virsh list --all | grep $VMNAME | awk '{print$2}' | wc -l) -eq 2 ]; then
  exit 0
fi

### generate ssh-rsa keypair
mkdir -p $KEY_DIR
rm -rf $KEY_DIR/* && ssh-keygen -q -N "" -f $KEY_DIR/key
KEY_PUB=$(cat $KEY_DIR/key.pub)

### downoload Ubuntu cloud image
#wget -O $IMG https://cloud-images.ubuntu.com/xenial/20180413/xenial-server-cloudimg-i386-disk1.img

### create ISO with user-data and meta-data for cloud-init, run VMs in KVM using this ISO and downloaded Ubuntu image
for i in 1 2
do

  cp $IMG $IMG_DIR/wp$i.img
  cat > $USER_D << _EOF_
#cloud-config

preserve_hostname: False
hostname: $VMNAME$i
ssh_svcname: ssh
ssh_deletekeys: True
ssh_genkeytypes: ['rsa', 'ecdsa']
ssh_pwauth: True
ssh_authorized_keys:
  - $KEY_PUB
packages: python
write_files:
  - content: |
       auto lo
       iface lo inet loopback
       auto ens3
       iface ens3 inet static
       address 192.168.122.2$i/24
       gateway 192.168.122.1
       dns-nameservers 192.168.122.1
    path: /etc/network/interfaces
runcmd:
  - [ sudo, touch, /etc/cloud/cloud-init.disabled, ]

_EOF_

  cat > $META_D << _EOF_
instance-id: $i
local-hostname: $VMNAME$i
_EOF_

genisoimage -o $KEY_DIR/WP$i.iso -volid cidata -joliet -r $USER_D $META_D &>> $KEY_DIR/bootstrap.log

/usr/bin/virt-install --name $VMNAME$i \
--ram $RAM \
--vcpus $VCPU \
--disk $IMG_DIR/wp$i.img,format=qcow2,bus=virtio \
--cdrom $KEY_DIR/WP$i.iso \
--os-type linux \
--network bridge=virbr0,model=virtio \
--noautoconsole
###time for VM initialization needed
sleep 120
virsh destroy $VMNAME$i
virsh start $VMNAME$i
sleep 60
done



exit 0
