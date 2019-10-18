Debian installer script
===

This script is used to automate a Debian installation:
- change linux boot menus to automatically start in the automated installation
- add the preseed file to the initrd
- add SSH keys to the initrd (optional)
- create the preseeded ISO image for LEGACY BIOS mode

## Usage

```bash
./preseed_creator.sh [options]
    Options:
        -i <image.iso>              ISO image to preseed. MANDATORY.
        -p <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso".
        -r <root_key.pub>           Root SSH key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/authorized_keys with a dedicated preseed late_command).
        -a <ansible_key.pub>        Ansible SSH key to add to the initrd (this key will then be retrieved and copied to /hoem/ansible/.ssh/authorized_keys with a dedicated preseed late_command).
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid.
        -h                          Print this help and exit.

$ sudo ./preseed-creator.sh -i debian-10.1.0-amd64-netinst.iso -o yann10.iso -p preseed-deb10-pubrepo-pvelvm-ansible.cfg -r /root/.ssh/id_rsa.pub -a /home/yann/.ssh/id_rsa.pub
Mount ISO image...
Extract ISO image...
Umount ISO image...
Decompress initrd...
Change linux boot menu...
Add the preseed file to the initrd...
Add the root SSH key to the initrd...
Add the ansible SSH key to the initrd...
Recompress the initrd...
Fix md5sums...
Create preseeded ISO image for LEGACY BIOS mode...
Preseeded ISO image created at /home/yann/dev/debian-installer/yann10.iso

```

## Note

If '-r' or '-a' options are used, the corresponding ssh public keys will be inserted in a specific folder in the initrd.
As a consequence these options assume that the preseed file ('-p' argument) will then retrieve these keys.
To do so, the preseed file should include specific late_command to copy the inserted key in the relevant folders.
The 'preseed-deb10-pubrepo-pvelvm-ansible.cfg' file in this repo implements such late commands.
