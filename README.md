# ResizePi #

Raspbian disk images can be quite large when they are backed up because on boot they are set to use the entire size of the SD card for the root partition. ResizePi is a script to remove the extra space and set Raspbian to resize to the filesystem to the disk.

## Prerequisites ##
`parted losetup tune2fs md5sum e2fsck`
This will not work on a  [NOOBS](https://github.com/raspberrypi/noobs) image due to the fact that the [NOOBS partitioning](https://github.com/raspberrypi/noobs/wiki/NOOBS-partitioning-explained) is different than the Raspbian Stretch and Stretch Lite images.

## Usage ##
`sudo resizepi.sh [-s] imagefile.img [newimagefile.img]`

If the `-s` option is given the script will skip the autoexpanding part of the process. If you specify the `newimagefile.img` a new file will be made and resized. You will need local disk space.


## Installation ##
```bash
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin
```

## Example ##
```bash
[user@localhost PiShrink]$ sudo pishrink.sh pi.img
e2fsck 1.42.9 (28-Dec-2013)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
/dev/loop1: 88262/1929536 files (0.2% non-contiguous), 842728/7717632 blocks
resize2fs 1.42.9 (28-Dec-2013)
resize2fs 1.42.9 (28-Dec-2013)
Resizing the filesystem on /dev/loop1 to 773603 (4k) blocks.
Begin pass 2 (max = 100387)
Relocating blocks             XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Begin pass 3 (max = 236)
Scanning inode table          XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Begin pass 4 (max = 7348)
Updating inode references     XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
The filesystem on /dev/loop1 is now 773603 blocks long.

Shrunk pi.img from 30G to 3.1G
```
