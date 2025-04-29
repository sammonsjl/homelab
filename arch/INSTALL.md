# Arch installation guide
* GPT partition and UEFI mode installation
* LVM on LUKS partition scheme
* Minimal system configuration

## Table of contents
1. Create bootable install medium
2. Create disk layout
3. Install base system
4. Install bootloader
5. Configure users

### Disk partition layout:
```
+----------------+-----------------+-----------------+
| Boot:          | Volume 1:       | Volume 2:       |
|                |                 |                 |
| /boot          | /               | /home           |
|                |                 |                 |
|                | /dev/vg0/root   | /dev/vg0/home   |
| /dev/vda1      +-----------------+-----------------+
| unencrypted    | /dev/vda2 encrypted LVM on LUKS   |
+----------------+-----------------------------------+
```
## 1. Create bootable install medium

Get the latest iso and checksums from a fast mirror.
```bash
wget https://mirrors.edge.kernel.org/archlinux/iso/latest/archlinux-$(date +%Y.%m.%d)-x86_64.iso archlinux.iso
wget https://mirrors.edge.kernel.org/archlinux/iso/latest/md5sums.txt
wget https://mirrors.edge.kernel.org/archlinux/iso/latest/sha1sums.txt
```

Validate the downloads.
```bash
md5sum --check md5sums.txt
sha1sum --check sha1sums.txt
```

Create a bootable usb flash drive, make sure /dev/sdX corresponds to the usb drive.
```bash
dd if=archlinux.iso of=/dev/sdX bs=1M status=progress && sync
```

Boot and check your internet connection, fix if necessary.
```bash
ping google.com
```

Ensure the clock system is synchronized.
```bash
timedatectl
```

Check if your system is running in uefi mode.
```bash
cat /sys/firmware/efi/fw_platform_size
```
The number 64 should be returned for a 64bit UEFI system.

Determine IP address of booted machine.
```bash
ip addr
```

From the host machine ssh to the arch installation:
```bash
ssh root@<ip address obtained above>
```

## 2. Create disk layout

Create partitions according to the partitioning scheme above.
Use a gpt partition table. And do not forget to set the correct partition types.
```bash
fdisk /dev/vda
```

The partition table should look like the following example.  Make sure to start with type "G" and pressing enter to change the disk label to GPT.
```
Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         1050623   1 GiB       EF00  EFI System
   2         1050624       976773133   465.3 GiB   8E00  Linux LVM
```

Create an encrypted container containing the logical volumes /root and swap. Set a safe passphrase.
The default cipher for LUKS is `aes-xts-plain64`, which means AES as cipher and XTS as mode of operation.
```bash
cryptsetup luksFormat /dev/vda2
cryptsetup open /dev/vda2 cryptlvm
```

Create a physical volume and a volume group inside the luks container.
```bash
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm
```

Create the logical volumes.
```bash
lvcreate -L 32G vg0 -n root
lvcreate -l 100%FREE vg0 -n home
```

Create the filesystems.
```bash
mkfs.fat -F32 /dev/vda1
mkfs.ext4 /dev/mapper/vg0-root
mkfs.ext4 /dev/mapper/vg0-home
```

Mount everything on the live system.
```bash
mount /dev/mapper/vg0-root /mnt
mount --mkdir /dev/mapper/vg0-home /mnt/home
mount --mkdir /dev/vda1 /mnt/boot/
```

Check all the filesystems.
```bash
lsblk
```

If the output looks like this you're good to go.
```bash
NAME           MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
vda            254:0    0   120G  0 disk  
├─vda1         254:1    0     1G  0 part  /mnt/boot
└─vda2         254:2    0   119G  0 part  
  └─cryptlvm   253:0    0   119G  0 crypt 
    ├─vg0-root 253:1    0    32G  0 lvm   /mnt
    └─vg0-home 253:2    0    87G  0 lvm   /mnt/home
```

## 3. Install base system

Install the base system and some further components using pacstrap.
```bash
pacstrap -K /mnt base linux-lts linux-firmware lvm2 openssh sudo terminus-font 
```

Generate fstab with UUID representation.
```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Chroot into your new base system.
```bash
arch-chroot /mnt
```

Set timezone and set your hwclock to use utc format.
```bash
ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
hwclock --systohc
```

Configure your locales.
```bash
echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
locale-gen
```

Set a console font.
```bash
echo FONT=ter-124b >> /etc/vconsole.conf
```

Configure systemd-based networking
```bash
echo "archlinux" > /etc/hostname

systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd
```
Create network interface:

```bash
cat <<EOF >/etc/systemd/network/20-wired.network
[Match]
Name=enp1s0

[Link]
RequiredForOnline=routable

[Network]
DHCP=yes
EOF
```

Configure systemd-based initramfs

Change `/etc/mkinitcpio.conf` to support encryption. You need to change the following line.
```bash
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)
```

Regenerate the initrd image. And check for errors.
```bash
mkinitcpio -P
```

## 4. Install systemd-based bootloader

Install the UEFI boot manager
```bash
bootctl install
```

Create a new bootloader entry:
```bash
export rootUUID=blkid /dev/vda2 -s UUID -o value

cat <<EOF | envsubst >/boot/efi/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img

options rd.luks.name=${rootUUID}=vg0 root=/dev/vg0/root rw
EOF
```

## 5. Configure users
Create a new user and set its password.
```bash
useradd -m -g users -G wheel $YOUR_USER_NAME
passwd $YOUR_USER_NAME
```

Finally uncomment the string `%wheel ALL=(ALL) ALL` in `/etc/sudoers` to allow sudo for users of the group wheel.
```bash
vim /etc/sudoers
```

Exit from chroot, unmount system, shutdown, extract flash stick. You made it! Now you have fully encrypted system.
```bash
exit
umount -R /mnt
swapoff -a
reboot
```
