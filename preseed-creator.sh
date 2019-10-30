#!/bin/bash

function usage {
    cat <<EOF
Preseed Creator
./preseed_creator.sh [options]
    Options:
        -i <image.iso>              ISO image to preseed. MANDATORY.
        -p <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso".
        -r <root_key.pub>           Root SSH key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/authorized_keys with a dedicated preseed late_command).
        -a <ansible_key.pub>        Ansible SSH key to add to the initrd (this key will then be retrieved and copied to /home/ansible/.ssh/authorized_keys with a dedicated preseed late_command).
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid.
        -h                          Print this help and exit.
EOF
    exit
}

INPUT=""
PRESEED=""
MYPWD=$(pwd)
OUTPUT=""
XORRISO=""
while getopts ":i:o:p:r:a:xh" opt; do
    case $opt in
        i)
            INPUT=$OPTARG;;
        o)
            OUTPUT=$OPTARG;;
        p)
            PRESEED=$OPTARG;;
        r)
            ROOTSSHKEY=$OPTARG;;
        a)
            ANSIBLESSHKEY=$OPTARG;;
        x)
            XORRISO='yes';;
        h)
            usage;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage;;
    esac
done

# test arguments consistency

if [[ ! -z $PRESEED ]] # test if the $PRESEED string's size is not zero
then
    if [ ${PRESEED:0:1} != / ]
    then
        PRESEED="${MYPWD}/${PRESEED}"
    fi
    if [[ ! -e $PRESEED ]] # test if the $PRESEED file exists
    then
        echo "$PRESEED does not exists. Aborting"
        exit 1
    fi
    if [[ ! -r $PRESEED ]] # test if the $PRESEED file is readable
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

if [[ -z $ROOTSSHKEY ]]
then
    echo "No SSH root key provided."
else
    if [ ${ROOTSSHKEY:0:1} != / ]
    then
        INPUT="${MYPWD}/${ROOTSSHKEY}"
    fi
    if [[ ! -e $ROOTSSHKEY ]]
    then
        echo "$ROOTSSHKEY does not exists. Aborting"
        exit 1
    fi
    if [[ ! -r $ROOTSSHKEY ]]
    then
        echo "$ROOTSSHKEY is not readable. Aborting"
        exit 1
    fi
fi

if [[ -z $ANSIBLESSHKEY ]]
then
    echo "No SSH ansible key provided."
else
    if [ ${ANSIBLESSHKEY:0:1} != / ]
    then
        INPUT="${MYPWD}/${ANSIBLESSHKEY}"
    fi
    if [[ ! -e $ANSIBLESSHKEY ]]
    then
        echo "$ANSIBLESSHKEY does not exists. Aborting"
        exit 1
    fi
    if [[ ! -r $ANSIBLESSHKEY ]]
    then
        echo "$ANSIBLESSHKEY is not readable. Aborting"
        exit 1
    fi
fi

mkdir preseed_creator -p
cd preseed_creator

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
sed -i "s/timeout 0/timeout 10/g" ./isolinux.cfg
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

echo "Add the preseed file to the initrd..."
cp $PRESEED preseed.cfg

mkdir ./custom

echo "Add sudoer ansible nopasswd specifics..."
cat << EOF > ./custom/ansible.sudoers
ansible ALL=(ALL) NOPASSWD: ALL
EOF

if [[ ! -z $ROOTSSHKEY ]]
then
    echo "Add the root SSH key to the initrd..."
    cp $ROOTSSHKEY ./custom/root_key.pub
fi

if [[ ! -z $ANSIBLESSHKEY ]]
then
    echo "Add the ansible SSH key to the initrd..."
    cp $ANSIBLESSHKEY ./custom/ansible_key.pub
fi

echo "Recompress the initrd..."
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
