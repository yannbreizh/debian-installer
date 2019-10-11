Debian installer script
===

This script is used to automate a Debian installation:
- change linux boot menus to automatically start in the automated installation
- append the preseed file to the initrd
- create the preseeded ISO image for LEGACY BIOS mode

## Usage

```bash
preseed_creator.sh [options]
    Options:
        -i <image.iso>              ISO image to preseed. MANDATORY.
        -p <preseed_file.cfg>       Preseed file. MANDATORY.
        -o <preseeded_image.iso>    Output preseeded ISO image. Default to "preseed_creator/debian-with-preseed.iso"
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid
        -h                          Print this help and exit
```