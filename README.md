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
        -f <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso".
        -r <pub_root_key.pub>       Root SSH public key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/authorized_keys with a dedicated preseed late_command).
        -p <pri_root_key.pub>       Root SSH private key to add to the initrd (this key will then be retrieved and copied to /root/.ssh/id_rsa with a dedicated preseed late_command).
        -a <ansible_key.pub>        Ansible SSH key to add to the initrd (this key will then be retrieved and copied to /home/ansible/.ssh/authorized_keys with a dedicated preseed late_command).
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid.
        -h                          Print this help and exit.


$ sudo ./preseed-creator.sh -i debian-10.1.0-amd64-netinst.iso -o 192.168.10.35.iso -f preseed-192.168.10.35.cfg -r /root/.ssh/id_rsa.pub -p /root/.ssh/id_rsa -a /home/yann/.ssh/id_rsa.pub
Mount ISO image...
Extract ISO image...
Umount ISO image...
Decompress initrd...
Change linux boot menu...
Add the preseed file to the initrd...
Add sudoer ansible nopasswd specifics...
Add the root SSH public key to the initrd...
Add the root SSH private key to the initrd...
Add the ansible SSH key to the initrd...
Recompress the initrd...
Fix md5sums...
Create preseeded ISO image for LEGACY BIOS mode...
Preseeded ISO image created at /home/yann/dev/debian-installer/192.168.10.35.iso
$
```

## Note

If '-r', 'p' or '-a' options are used, the corresponding ssh public keys will be inserted in a specific folder in the initrd.
As a consequence these options assume that the preseed file ('-f' argument) will then retrieve these keys.
To do so, the preseed file should include specific late_command to copy the inserted key in the relevant folders.
The 'preseed-192.168.10.35.cfg' file in this repo implements such late commands.

With these setttings (keys included), the following login schemes are available:
* **console**:
  - root    -> with password
  - ansible -> with NO password
* **ssh**:
  - root    -> no password required if ssh issued with the expected root key
  - ansible -> no password required if ssh issued with the expected ansible key
* **sudo**:
  - ansible -> no password required for sudo

