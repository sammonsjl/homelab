#!/usr/bin/env bash

NoColor='\033[0m'
Red='\033[0;31m'
Yellow='\033[0;33m'

createDiskLayout() {
	echo -e "${Yellow}Creating Disk Layout${NoColor}"

	lsblk

	if [[ -e /dev/nvme0n1 ]]; then
		echo -e "${Red}Drive /dev/nvme0n1 detected.${NoColor}"

		export EFI=nvme0n1p1
		export LVM=nvme0n1p6

		echo -e "${Yellow}Enter password for encrypted volume${NoColor}"
		cryptsetup open /dev/"${LVM}" cryptlvm

		sleep 5
	fi

	if [[ -e /dev/vda ]]; then
		echo -e "${Yellow}Drive /dev/vda detected.${NoColor}"

		export EFI=vda1
		export LVM=vda2

		wipefs -a /dev/vda >/dev/null 2>&1
		parted -s /dev/vda mklabel gpt >/dev/null 2>&1
		parted -s /dev/vda mkpart fat32 1MiB 1025MiB >/dev/null 2>&1
		parted -s /dev/vda set 1 esp on >/dev/null 2>&1
		parted -s /dev/vda mkpart ext4 1025MiB 100% >/dev/null 2>&1
		parted -s /dev/vda set 3 lvm on >/dev/null 2>&1

		cryptsetup luksFormat /dev/${LVM}
		echo -e "${Yellow}Enter password again as we need to mount the volume${NoColor}"
		cryptsetup open /dev/${LVM} cryptlvm

		pvcreate -ff /dev/mapper/cryptlvm >/dev/null 2>&1
		vgcreate vg0 /dev/mapper/cryptlvm >/dev/null 2>&1
		lvcreate -L 32G vg0 -n root >/dev/null 2>&1
		lvcreate -l 100%FREE vg0 -n home >/dev/null 2>&1

		mkfs.ext4 /dev/mapper/vg0-home >/dev/null 2>&1
	fi

	mkfs.ext4 -F /dev/mapper/vg0-root >/dev/null 2>&1
	mkfs.fat -F 32 /dev/"${EFI}"

	mount --mkdir /dev/vg0/root /mnt >/dev/null 2>&1
	mount --mkdir /dev/vg0/home /mnt/home >/dev/null 2>&1
	mount --mkdir /dev/"${EFI}" /mnt/boot >/dev/null 2>&1

	lsblk
}

createUser() {
	echo -e "${Yellow}Create User${NoColor}"
	groupadd me
	useradd -m -g me -G wheel me

	echo "test" | sudo passwd --stdin me

	sudo sed -i '/%wheel/s/^#//' /etc/sudoers
}

pacmanConf() {
	sed -i s/#Color/Color/g /etc/pacman.conf
	sed -i s/#ParallelDownloads/ParallelDownloads/g /etc/pacman.conf
	sed -i s/#VerbosePkgLists/VerbosePkgLists\\nILoveCandy/g /etc/pacman.conf
}

installBaseSystem() {
	echo -e "${Yellow}Installing Base System${NoColor}"

	pacmanConf

	echo -e "${Yellow}Ranking mirrors for faster download speeds...${NoColor}"

	if ! command -v reflector >/dev/null; then
		if ! pacman -Sy reflector --noconfirm --needed; then
			pacman -Syu reflector --noconfirm --needed
		elif ! reflector -h >/dev/null; then
			pacman -Syu reflector --noconfirm --needed
		fi
	fi

	reflector --latest 15 --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1

	echo -e "${Yellow}Installing Base Packages${NoColor}"
	pacstrap -K /mnt ansible base git intel-ucode linux-lts linux-firmware lvm2 openssh rsync sudo terminus-font >/dev/null 2>&1

	genfstab -U /mnt >>/mnt/etc/fstab

	ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
}

installBaseSystemChroot() {
	echo -e "${Yellow}Installing Base System (chroot)${NoColor}"

	ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime >/dev/null 2>&1

	hwclock --systohc >/dev/null 2>&1

	echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
	echo 'LANG=en_US.UTF-8' >/etc/locale.conf
	locale-gen >/dev/null 2>&1

	cat <<EOF >/etc/vconsole.conf
KEYMAP=us
XKBLAYOUT=us
XKBMODEL=pc105+inet
XKBOPTIONS=terminate:ctrl_alt_bksp
EOF

	#echo FONT=ter-124b >>/etc/vconsole.conf

	echo "archlinux" >/etc/hostname

	systemctl enable systemd-networkd >/dev/null 2>&1
	systemctl enable systemd-resolved >/dev/null 2>&1
	systemctl enable systemd-timesyncd >/dev/null 2>&1
	systemctl enable sshd >/dev/null 2>&1

	cat <<EOF >/etc/systemd/network/20-wired.network
[Match]
Name=en*

[Link]
RequiredForOnline=routable

[Network]
DHCP=yes
EOF

	cd /var/lib || exit
	mkdir -p flatpak/repo/objects flatpak/repo/tmp

	cat <<EOF >flatpak/repo/config
[core]
repo_version=1
mode=bare-user-only
min-free-space-size=500MB
EOF

	sed -i '/^HOOKS=/ c\
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)' /etc/mkinitcpio.conf

	mkinitcpio -P >/dev/null 2>&1
}

installBootLoader() {
	echo -e "${Yellow}Installing BootLoader${NoColor}"
	bootctl install >/dev/null 2>&1

	rootUUID=$(blkid /dev/"${LVM}" -s UUID -o value)

	cat <<EOF | envsubst >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img

options rd.luks.name=${rootUUID}=vg0 root=/dev/vg0/root rw
EOF
}

fetchAnsible() {
	git clone --depth 1 https://github.com/sammonsjl/homelab.git /home/me/homelab  > /dev/null 2>&1
	chown -R me:users /home/me/homelab
}

if [[ -z ${1-} ]]; then
	clear
	echo -e "${Yellow}Installing Arch Linux.  Press ENTER to continue.${NoColor}"
	read -r
	clear

	timedatectl >/dev/null 2>&1

	createDiskLayout
	installBaseSystem

	cp "${BASH_SOURCE[0]}" /mnt/root
	arch-chroot /mnt /bin/bash -c "/root/$(basename "${BASH_SOURCE[0]}") chroot"
else
	installBaseSystemChroot
	installBootLoader
	createUser
	fetchAnsible
fi
