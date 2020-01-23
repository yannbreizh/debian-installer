#!/usr/bin/env bash

function usage {
    cat <<EOF
Preseed Creator
./preseed_creator.sh [options]
    Options:
        -i <image.iso>              ISO image to preseed. MANDATORY.
        -f <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso".
        -r <pub_root_key.pub>       Root SSH public key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/authorized_keys with a dedicated preseed late_command).
        -p <pri_root_key.pub>       Root SSH private key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/id_rsa with a dedicated preseed late_command).
        -a <ansible_key.pub>        Ansible SSH key to add to the initrd (this key will then be retrieved and copied to /home/ansible/.ssh/authorized_keys with a dedicated preseed late_command).
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid.
        -n                          Do not unmount and cleanup temporary files (for debugging)
        -d                          Debug mode
        -h                          Print this help and exit.

EOF
    exit
}

function add_trap_cmd()
{
    # [ -n "$NO_CLEANUP" ] && return
    for cmd in "$@"
    do
        if [ -n "$NO_CLEANUP" ]
        then
            cmd="echo ${cmd}"
        fi
        if [ -z "$TRAP_COMMANDS" ]; then
            TRAP_COMMANDS="$cmd"
        else
            TRAP_COMMANDS+="; $cmd"
        fi
        # shellcheck disable=SC2064
        trap "$TRAP_COMMANDS" EXIT
    done
}

function err()
{
    echo "$@" >&2
}

function die()
{
    err "$@"
    exit 1
}

function check_requirements()
{
    for req in "$@"
    do
        command -v $req >/dev/null 2>&1 || die "Cannot find ${req} command"

    done
}

function validate_input_file()
{
    if [[ ! -e $1 ]]
    then
        die "$1 does not exists. Aborting"
    fi
    if [[ ! -r $1 ]]
    then
        die "$1 is not readable. Aborting"
    fi
}

# requirements pre-check
check_requirements genisoimage rsync md5sum gzip cpio readlink

# parse input arguments
while getopts ":i:o:f:r:p:a:xndh" opt; do
    case $opt in
        i)
            INPUT=$(readlink -f $OPTARG);;
        o)
            OUTPUT=$(readlink -f $OPTARG);;
        f)
            PRESEED=$(readlink -f $OPTARG);;
        r)
            ROOTPUBSSHKEY=$(readlink -f $OPTARG);;
        p)
            ROOTPRISSHKEY=$(readlink -f $OPTARG);;
        a)
            ANSIBLESSHKEY=$(readlink -f $OPTARG);;
        x)
            check_requirements xorriso
            XORRISO='yes';;
        n)
            NO_CLEANUP='yes';;
        d)
            DEBUG_MODE='yes';;
        h)
            usage;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage;;
    esac
done

# validate arguments
if [[ ! -z $PRESEED && ! -r $PRESEED ]]
then
    echo "$PRESEED is not readable. Aborting"
    exit 1
fi

if [ -z $OUTPUT ]
then
    OUTPUT=$PWD/debian-with-preseed.iso
else
    OUTPUT_DIR=${OUTPUT%/*}
    if [[ ! -d $OUTPUT_DIR || ! -w $OUTPUT_DIR ]]
    then
        die "$OUTPUT is not writable"
    fi
fi

if [ -z $INPUT ]
then
    echo "No ISO image provided. Aborting"
    exit 1
else
    validate_input_file $INPUT
fi

if [ -z $ROOTPUBSSHKEY ]
then
    echo "No SSH root public key provided."
else
    validate_input_file $ROOTPUBSSHKEY
fi

if [ -z $ROOTPRISSHKEY ]
then
    echo "No SSH root private key provided."
else
    validate_input_file $ROOTPRISSHKEY
fi

if [ -z $ANSIBLESSHKEY ]
then
    echo "No SSH ansible key provided."
else
    validate_input_file $ANSIBLESSHKEY
fi

if [ -n "$DEBUG_MODE" ]; then
    set -x
fi

echo "Mount ISO image..."
LOOP_DIR=$(mktemp -d)
LOOP_DEV=$(losetup -f)
mount -o loop=$LOOP_DEV $INPUT $LOOP_DIR |& grep -v "WARNING: device write-protected, mounted read-only"

if [ ${PIPESTATUS[0]} -ne 0 ]
then
    echo "Error while mounting the ISO image. Aborting" >&2
    rmdir $LOOP_DIR
    losetup -d $LOOP_DIR
    exit 1
else
    add_trap_cmd "echo 'Umount ISO image...'" "losetup -d \$LOOP_DEV" "umount -f \$LOOP_DIR" "echo 'Cleaning up...'" "rm -rf \$LOOP_DIR 2>/dev/null"
fi

echo "Extract ISO image..."
CD=$(mktemp -d)
add_trap_cmd "rm -rf \$CD"
rsync -a -H --exclude=TRANS.TBL $LOOP_DIR/ $CD
if [ $? -ne 0 ]
then
    die "Error: rsync returned non-zero value"
fi

echo "Decompress initrd..."
IRMOD=$(mktemp -d)
add_trap_cmd "rm -rf \$IRMOD"
cd $IRMOD
gzip -d < $CD/install.amd/initrd.gz | cpio --extract --make-directories --no-absolute-filenames
if [[ ${PIPESTATUS[0]} -ne 0 || ${PIPESTATUS[0]} -ne 0 ]]
then
    echo "Error while getting ${CD}/install.amd/initrd.gz content. Aborting"
    exit 1
fi
cd -

echo "Change linux boot menu..."
chmod +w $CD/isolinux/isolinux.cfg
sed -i "s/timeout 0/timeout 10/g" $CD/isolinux/isolinux.cfg
chmod -w $CD/isolinux/isolinux.cfg

chmod +w $CD/isolinux/menu.cfg
cat << EOF > $CD/isolinux/menu.cfg
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
chmod -w $CD/isolinux/menu.cfg

echo "Add the preseed file to the initrd..."
cp $PRESEED $IRMOD/preseed.cfg

mkdir $IRMOD/custom

echo "Add sudoer ansible nopasswd specifics..."
cat << EOF > $IRMOD/custom/ansible.sudoers
ansible ALL=(ALL) NOPASSWD: ALL
EOF

if [[ ! -z $ROOTPUBSSHKEY ]]
then
    echo "Add the root SSH public key to the initrd..."
    cp $ROOTPUBSSHKEY $IRMOD/custom/root_pub_key.pub
fi

if [[ ! -z $ROOTPRISSHKEY ]]
then
    echo "Add the root SSH private key to the initrd..."
    cp $ROOTPRISSHKEY $IRMOD/custom/root_pri_key.pub
fi

if [[ ! -z $ANSIBLESSHKEY ]]
then
    echo "Add the ansible SSH key to the initrd..."
    cp $ANSIBLESSHKEY $IRMOD/custom/ansible_key.pub
fi

echo "Recompress the initrd..."
cd $IRMOD
find . | cpio -H newc --create | gzip -9 > $CD/install.amd/initrd.gz
if [ $? -ne 0 ]
then
    echo "Error while putting new content into ../cd/install.amd/initrd.gz. Aborting"
    exit 1
fi
cd -

echo "Fix md5sums..."
cd $CD
md5sum `find -follow -type f 2>/dev/null` > md5sum.txt
if [ $? -ne 0 ]
then
    echo "Error while fixing md5sums. Aborting"
    exit 1
fi
cd -

echo "Create preseeded ISO image for LEGACY BIOS mode..."
if [[ -z $XORRISO ]]
then
	genisoimage -quiet -o $OUTPUT -r -J -no-emul-boot -boot-load-size 4 -boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat $CD
else
	xorriso -as mkisofs \
		-quiet \
		-o $OUTPUT \
		-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
		-c $CD/isolinux/boot.cat \
		-b $CD/isolinux/isolinux.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-eltorito-alt-boot \
		-e boot/grub/efi.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
		$CD /dev/null 2>$1
fi

if [ $? -ne 0 ]
then
    echo "Error while creating the preseeded ISO image. Aborting"
    exit 1
fi

echo "Preseeded ISO image created at $OUTPUT"
