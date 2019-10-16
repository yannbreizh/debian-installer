#!/bin/bash

function usage {
    cat <<EOF
Preseed Creator
./preseed_creator.sh [options]
    Options:
        -i <image.iso>              ISO image to preseed. MANDATORY.
        -p <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso"
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid
        -h                          Print this help and exit
EOF
    exit
}

INPUT=""
PRESEED=""
MYPWD=$(pwd)
OUTPUT=""
XORRISO=""
while getopts ":i:o:p:xgh" opt; do
    case $opt in
        i)
            INPUT=$OPTARG;;
        o)
            OUTPUT=$OPTARG;;
        p)
            PRESEED=$OPTARG;;
        x)
            XORRISO='yes';;
        h)
            usage;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage;;
    esac
done

mkdir preseed_creator -p
cd preseed_creator

if [[ ! -z $PRESEED ]]
then
    if [ ${PRESEED:0:1} != / ]
    then
        PRESEED="${MYPWD}/${PRESEED}"
    fi
    if [[ ! -e $PRESEED ]]
    then
        echo "$PRESEED does not exists. Aborting"
        exit 1
    fi
    if [[ ! -r $PRESEED ]]
    then
        echo "$PRESEED is not readable. Aborting"
        exit 1
    fi
fi

if [[ ! -z $OUTPUT ]]
then
    if [ ${OUTPUT:0:1} != / ]
    then
        OUTPUT="${MYPWD}/${OUTPUT}"
    fi
else
    OUTPUT="debian-with-preseed.iso"
fi

if [[ -z $INPUT ]]
then
    echo "No ISO image provided. Aborting"
    exit 1
else
    if [ ${INPUT:0:1} != / ]
    then
        INPUT="${MYPWD}/${INPUT}"
    fi
    if [[ ! -e $INPUT ]]
    then
        echo "$INPUT does not exists. Aborting"
        exit 1
    fi
    if [[ ! -r $INPUT ]]
    then
        echo "$INPUT is not readable. Aborting"
        exit 1
    fi
fi

echo "Mount ISO image..."
mkdir loopdir -p
mount -o loop $INPUT loopdir > /dev/null 2>&1
if [ $? -ne 0 ]
then
    echo "Error while mounting the ISO image. Aborting"
    exit 1
fi

mkdir cd
echo "Extract ISO image..."
rsync -a -H --exclude=TRANS.TBL loopdir/ cd
echo "Umount ISO image..."
umount loopdir

echo "Decompress initrd..."
mkdir irmod -p
cd irmod
gzip -d < ../cd/install.amd/initrd.gz | cpio --extract --make-directories --no-absolute-filenames 2>/dev/null
if [ $? -ne 0 ]
then
    echo "Error while getting ../cd/install.amd/initrd.gz content. Aborting"
    exit 1
fi

echo "Change linux boot menu..."
cd ../cd/isolinux
chmod +w isolinux.cfg
sed -i "s/timeout 0/timeout 5/g" ./isolinux.cfg
chmod -w isolinux.cfg

chmod +w menu.cfg
cat << EOF > ./menu.cfg
menu hshift 7
menu width 61

menu title Orange CDN cPoP
include stdmenu.cfg
include x86menu.cfg
default cpop
label cpop
	menu label ^Orange cPoP autoinstall
	menu default
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz preseed/file=/preseed.cfg grub-installer/bootdev="/dev/sda" --- quiet
EOF
chmod -w menu.cfg
cd ../../irmod

echo "Append the preseed file to the initrd and recompress the initrd..."
cp $PRESEED preseed.cfg
find . | cpio -H newc --create 2>/dev/null | gzip -9 > ../cd/install.amd/initrd.gz 2>/dev/null
if [ $? -ne 0 ]
then
    echo "Error while putting new content into ../cd/install.amd/initrd.gz. Aborting"
    exit 1
fi

cd ../
rm -rf irmod/

echo "Fix md5sums..."
cd cd
md5sum `find -follow -type f 2>/dev/null` > md5sum.txt 2>/dev/null
if [ $? -ne 0 ]
then
    echo "Error while fixing md5sums. Aborting"
    exit 1
fi

cd ..
echo "Create preseeded ISO image for LEGACY BIOS mode..."
if [[ -z $XORRISO ]]
then
	genisoimage -quiet -o $OUTPUT -r -J -no-emul-boot -boot-load-size 4 -boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat ./cd > /dev/null 2>&1
else
	xorriso -as mkisofs \
		-quiet \
		-o $OUTPUT \
		-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
		-c isolinux/boot.cat \
		-b isolinux/isolinux.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-eltorito-alt-boot \
		-e boot/grub/efi.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
		./cd /dev/null 2>$1
fi

if [ $? -ne 0 ]
then
    echo "Error while creating the preseeded ISO image. Aborting"
    exit 1
fi

cd ..
rm -rf preseed_creator/

echo "Preseeded ISO image created at $OUTPUT"
