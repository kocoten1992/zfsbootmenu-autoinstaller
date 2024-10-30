#!/bin/bash

# Automatically set other variables
BOOT_DISK="/dev/nvme0n1"
BOOT_PART="1"
POOL_DISK="/dev/nvme0n1"
POOL_PART="2"
POOL_NAME="zroot"
KERNEL_VERSION=$(uname -r)  # Automatically get current kernel version
MOUNT_POINT="/mnt"
ID=$(source /etc/os-release && echo "$ID")  # Get OS ID from /etc/os-release

get_username_and_password(){
  # Prompt user for variables
  read -p "Enter username for the new user: " USERNAME
  read -sp "Enter password for the new user: " USER_PASSWORD
  echo
  read -sp "Enter root password: " ROOT_PASSWORD
  echo
  read -p "Enter hostname for this system: " HOSTNAME
}

select_disk() {
  echo "Available disks:"
  # List available disks with lsblk and store them in an array
  mapfile -t disks < <(lsblk -dn -o NAME,SIZE,TYPE | grep 'disk')

  # Display disks with numbering
  for i in "${!disks[@]}"; do
    echo "$((i + 1)). ${disks[i]}"
  done

  # Prompt user to select a disk by number
  while true; do
    read -p "Enter the number of the disk you want to use for boot and pool (e.g., 1, 2): " choice
    if [[ $choice -gt 0 && $choice -le ${#disks[@]} ]]; then
      # Get the selected disk name (e.g., 'sda' from 'sda 500G disk')
      selected_disk=$(echo "${disks[$((choice - 1))]}" | awk '{print $1}')
      BOOT_DISK="/dev/$selected_disk"
      POOL_DISK="/dev/$selected_disk"
      echo "Selected disk: $BOOT_DISK"
      break
    else
      echo "Invalid choice. Please select a number from the list."
    fi
  done
  echo "Boot Disk is set to $BOOT_DISK"
  echo "Pool Disk is set to $POOL_DISK"
}




# Functions
generate_hostid() {
  echo "Generating host ID..."
  zgenhostid -f 0x00bab10c
}

configure_apt_sources() {
  echo "Configuring APT sources..."
  cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free-firmware

deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security main contrib non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware

deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
EOF
}

install_host_packages() {
  echo "Installing necessary packages"
  apt update
  apt install -y dosfstools efibootmgr curl debootstrap gdisk dkms zfsutils-linux # Install efibootmgr 
}

partition_disk() {
  echo "Partitioning disk $POOL_DISK..."
  sgdisk --zap-all $POOL_DISK
  sgdisk -n1:1M:+512M -t1:EF00 $BOOT_DISK
  sgdisk -n2:0:-10M -t2:BF00 $POOL_DISK
}

create_zpool() {
  echo "Creating ZFS pool and datasets..."
  zpool create -f -o ashift=12 -O compression=lz4 -O acltype=posixacl -O xattr=sa -O relatime=on -o autotrim=on -o compatibility=openzfs-2.1-linux -m none $POOL_NAME ${POOL_DISK}p${POOL_PART}
  zfs create -o mountpoint=none $POOL_NAME/ROOT
  zfs create -o mountpoint=/ -o canmount=noauto $POOL_NAME/ROOT/$ID
  zfs create -o mountpoint=/home $POOL_NAME/home
  zpool set bootfs=$POOL_NAME/ROOT/$ID $POOL_NAME
}

export_import_zpool() {
  echo "Exporting and re-importing ZFS pool for mounting..."
  zpool export $POOL_NAME
  zpool import -N -R $MOUNT_POINT $POOL_NAME
  zfs mount $POOL_NAME/ROOT/$ID
  zfs mount $POOL_NAME/home
}

setup_base_system() {
  echo "Installing base system with debootstrap..."
  debootstrap bookworm $MOUNT_POINT
  cp /etc/hostid $MOUNT_POINT/etc/hostid
  cp /etc/resolv.conf $MOUNT_POINT/etc/resolv.conf
}

prepare_chroot() {
  echo "Mounting filesystems for chroot environment..."
  mount --bind /dev $MOUNT_POINT/dev
  mount --bind /proc $MOUNT_POINT/proc
  mount --bind /sys $MOUNT_POINT/sys
  mount --bind /dev/pts $MOUNT_POINT/dev/pts
}

enter_chroot() {
  echo "Entering chroot environment to configure system..."
  chroot $MOUNT_POINT /bin/bash <<EOF
# Set hostname
echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1    $HOSTNAME" >> /etc/hosts

# Configure apt sources
$(configure_apt_sources)

# Update and install necessary packages
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y locales linux-headers-$KERNEL_VERSION linux-image-amd64 zfs-initramfs

# Install efibootmgr and dosfstools
echo "Installing additional important software"
apt install -y dosfstools efibootmgr curl

# Install system utilities
echo "Installing system utilities..."
apt install -y systemd-timesyncd net-tools iproute2 isc-dhcp-client iputils-ping traceroute curl wget dnsutils ethtool ifupdown tcpdump nmap nano vim htop openssh-server git tmux

# Perform system upgrade
echo "Upgrading system packages..."
apt upgrade -y

# Set locale and timezone
echo "Configuring locale and timezone..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
dpkg-reconfigure -f noninteractive tzdata

# Set root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
echo "Creating user and setting permissions..."
useradd -m -s /bin/bash -G sudo,audio,cdrom,dip,floppy,netdev,plugdev,video $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure ZFSBootMenu
echo "Setting up ZFSBootMenu EFI configuration..."
mkdir -p /boot/efi/EFI/ZBM
curl -Lo /boot/efi/EFI/ZBM/VMLINUZ.EFI https://get.zfsbootmenu.org/efi

# Create EFI filesystem on boot partition and mount
mkfs.vfat ${BOOT_DISK}p${BOOT_PART}
mkdir -p /boot/efi
mount ${BOOT_DISK}p${BOOT_PART} /boot/efi

# Set up EFI boot entries
echo "Adding EFI boot entries..."
efibootmgr -c -d ${BOOT_DISK} -p $BOOT_PART -L "ZFSBootMenu" -l '\\EFI\\ZBM\\VMLINUZ.EFI'
efibootmgr -c -d ${BOOT_DISK} -p $BOOT_PART -L "ZFSBootMenu (Backup)" -l '\\EFI\\ZBM\\VMLINUZ-BACKUP.EFI'
efibootmgr -c -d ${BOOT_DISK} -p $BOOT_PART -L "ZFSBootMenu" -l '\\EFI\\BOOT\\bootx64.efi'

# Perform a distribution upgrade
echo "Running dist-upgrade to upgrade all packages to the latest version..."
apt full-upgrade -y
EOF
}

cleanup_chroot() {
  echo "Cleaning up chroot environment..."
  umount -l $MOUNT_POINT/dev/pts
  umount -l $MOUNT_POINT/dev
  umount -l $MOUNT_POINT/sys
  umount -l $MOUNT_POINT/proc
}

final_cleanup() {
  echo "Exporting ZFS pool and completing installation..."
  zpool export -a
}

# Execution sequence
echo "Starting ZFS Boot Menu installation..."
select_disk
get_username_and_password
generate_hostid
configure_apt_sources
install_host_packages
partition_disk
create_zpool
export_import_zpool
setup_base_system
prepare_chroot
enter_chroot
cleanup_chroot
final_cleanup

echo "ZFS Boot Menu installation complete. You may reboot."
