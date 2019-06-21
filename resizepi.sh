#!/usr/bin/env bash
# resizepi.sh
#
#  - Resize Pi Image by Removing Free/Empty Disk Space
#  - PreReqs: parted losetup tune2fs md5sum e2fsck resize2fs
# Usage:
#  sudo resizepi.sh [-s] imagefile.img [newimagefile.img]
#
# -s option will skip the auto expanding option of the new image.
#    This will fail if you do not have enough disk space to build
#    the new image. ie -64gb will need 128gb of free disk space on
#    your local drive.
###############################################################################

function Clean_Up() {
  if losetup $Loopback &>/dev/null; then
	losetup -d "$Loopback"
  fi
}

# Check for prequisites #######################################################
for command in parted losetup tune2fs md5sum e2fsck resize2fs; do
  which $command 2>&1 >/dev/null
  if (( $? != 0 )); then
    echo "ERROR: $command is not installed."
    exit -4
  fi
done
###############################################################################

Usage() { echo "Usage: $0 [-s] imagefile.Image [newimagefile.Image]"; exit -1; }

Skip_Autoexpand=false

while Get_Options ":s" opt; do
  case "${opt}" in
    s) Skip_Autoexpand=true ;;
    *) Usage ;;
  esac
done
shift $((OPTIND-1))

# Arguments####################################################################
Image="$1"
###############################################################################

# Usage sanity checks #########################################################
if [[ -z "$Image" ]]; then
  Usage
fi
if [[ ! -f "$Image" ]]; then
  echo "ERROR: $Image is not an disk image file..."
  exit -2
fi
if (( EUID != 0 )); then
  echo "ERROR: You need to be run this command as root."
  exit -3
fi

# Copy to new file if requested ###############################################
if [ -n "$2" ]; then
  echo "Copying $1 to $2..."
  cp --reflink=auto --sparse=always "$1" "$2"
  if (( $? != 0 )); then
    echo "ERROR: Could not copy file..."
    exit -5
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown $old_owner "$2"
  Image="$2"
fi
###############################################################################

# Clean_Up at script exit #####################################################
trap Clean_Up ERR EXIT
###############################################################################

# Gather Data #################################################################
Before_Size=$(ls -lh "$Image" | cut -d ' ' -f 5)
Parted_Output=$(parted -ms "$Image" unit B print | tail -n 1)
Partition_Number=$(echo "$Parted_Output" | cut -d ':' -f 1)
Partition_Start=$(echo "$Parted_Output" | cut -d ':' -f 2 | tr -d 'B')
Loopback=$(losetup -f --show -o $Partition_Start "$Image")
Tune2fs_Output=$(tune2fs -l "$Loopback")
Current_Size=$(echo "$Tune2fs_Output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
Block_Size=$(echo "$Tune2fs_Output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)

#Check to see if disk should allocate free space to /root #####################
if [ "$Skip_Autoexpand" = false ]; then
  # Expand rootfs on next boot
  Mount_Point=$(mktemp -d)
  mount "$Loopback" "$Mount_Point"
  if [ $(md5sum "$Mount_Point/etc/rc.local" | cut -d ' ' -f 1) != "0542054e9ff2d2e0507ea1ffe7d4fc87" ]; then
    echo "Creating New /etc/rc.local"
    mv "$Mount_Point/etc/rc.local" "$Mount_Point/etc/rc.local.bak"
###############################################################################

#### Do Not Modify the Folllowing #############################################
cat <<\EOF1 > "$Mount_Point/etc/rc.local"
#!/bin/bash
do_expand_rootfs() {
  ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')
  PART_NUM=${ROOT_PART#mmcblk0p}
  if [ "$PART_NUM" = "$ROOT_PART" ]; then
    echo "$ROOT_PART is not an SD card. Don't know how to expand"
    return 0
  fi
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
  [ "$PART_START" ] || return 1
  fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF

cat <<EOF > /etc/rc.local &&
#!/bin/sh
echo "Expanding /dev/$ROOT_PART"
resize2fs /dev/$ROOT_PART
rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local

EOF
reboot
exit
}
raspi_config_expand() {
/usr/bin/env raspi-config --expand-rootfs
if [[ $? != 0 ]]; then
  return -1
else
  rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local
  reboot
  exit
fi
}
raspi_config_expand
echo "WARNING: Using backup expand..."
sleep 5
do_expand_rootfs
echo "ERROR: Expanding failed..."
sleep 5
rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local
exit 0
EOF1
##### End No Modify Zone ######################################################
    chmod +x "$Mount_Point/etc/rc.local"
  fi
  umount "$Mount_Point"
else
  echo "Skipping Auto Filesystem Allocation"
fi

# Run Filesystems Checks ######################################################
e2fsck -p -f "$Loopback"
Minimum_Size=$(resize2fs -P "$Loopback" | cut -d ':' -f 2 | tr -d ' ')
if [[ $Current_Size -eq $Minimum_Size ]]; then
  echo "ERROR: Image already the smallest size it can be."
  exit -6
fi

# Add A Bit of Free Space to the End of Disk ##################################
Extra_Space=$(($Current_Size - $Minimum_Size))
for Space in 5000 1000 100; do
  if [[ $Extra_Space -gt $space ]]; then
    Minimum_Size=$(($Minimum_Size + $Space))
    break
  fi
done

# Shrink Disk #################################################################
resize2fs -p "$Loopback" $Minimum_Size
if [[ $? != 0 ]]; then
  echo "ERROR: resize2fs failed..."
  mount "$Loopback" "$Mount_Point"
  mv "$Mount_Point/etc/rc.local.bak" "$Mount_Point/etc/rc.local"
  umount "$Mount_Point"
  losetup -d "$Loopback"
  exit -7
fi
sleep 1
###############################################################################
#Shrink Root FS ###############################################################
Partion_New_Size=$(($Minimum_Size * $Block_Size))
New_Partition_End=$(($Partition_Start + $Partion_New_Size))
parted -s -a minimal "$Image" rm $Partition_Number >/dev/null
parted -s "$Image" unit B mkpart primary $Partition_Start $New_Partition_End >/dev/null
###############################################################################
#Truncate the file ############################################################
End_Result=$(parted -ms "$Image" unit B print free | tail -1 | cut -d ':' -f 2 | tr -d 'B')
truncate -s $End_Result "$Image"
After_Size=$(ls -lh "$Image" | cut -d ' ' -f 5)

echo "Resized $Image from $Before_Size to $After_Size"
