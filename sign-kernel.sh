#!/bin/bash

############################################################################################
#
# !!!!! IMPORTANT NOTE !!!!!
#   THIS SCRIPT HAS ONLY BEEN TESTED ON A BARE METAL DEBIAN 12 SYSTEM
#   WITH GRUB AND THE zabbly/linux kernel
#
# Also:
#   I am not responsible if this script destroys your system's ability to boot.
#   Always carefully read through the scripts you randomly find on the internet
#   and decide for yourself if you want to accept any risks you may find.
#
#
# This script automates signing custom kernel builds using MOK, DKMS, and sbsigntool.
# Thus, the chance of successfully booting the kernel with Secure Boot enabled is increased,
# but not guaranteed.
#
# Some kernel modules might need additional signing, which is NOT what this script
# is designed for.
#
#
# How to install:
#   1. Copy and paste or download this source code to some location that's in your PATH,
#      e.g., /usr/local/bin/sign-kernel.sh
#   2. Make it executable: `chmod +x /usr/local/bin/sign-kernel.sh`
#
#
# How to use:
#    sign-kernel.sh [<kernel image path>]
#
#     where <kernel image path> is optional and, if provided, must point to a valid `vmlinuz` kernel image.
#
#    Examples:
#      sign-kernel.sh
#         to sign the currently running kernel image (`uname -r`)
#
#      sign-kernel.sh /boot/vmlinuz-<kernel version>
#         to sign a specific kernel image
#
#   I have no idea what `sbsign` does to non-kernel images. So be aware...
#   Also: this script must be executed with root privileges, e.g., using `sudo sign-kernel.sh`.
#
#
# Quick and dirty overview of what it does:
#   - Ensure that the kernel image to sign exists in /boot
#   - Ensure the MOK key files exist
#   - Check if the kernel image to sign has already been signed using `sbverify` and the MOK certificate
#     and abort if that's the case
#   - Sign the kernel image with `sbsign` and the MOK key and store it as `/boot/vmlinuz-<kernel_version>.tmp`
#   - Verify the signed image using `sbverify` and the MOK certificate
#     - On failure: Remove `/boot/vmlinuz-<kernel_version>.tmp` and abort any further operations
#     - On success: Replace the unsigned `/boot/vmlinuz-<kernel_version>` file with `/boot/vmlinuz-<kernel_version>.tmp`
#
#   Note: You will LOSE the original unsigned image after the signature has been applied.
#         If you don't like this behavior, fork the repo or download the script and modify it yourself.
#
#
#
# Required packages:
#   mokutil (should already be installed when the OS was installed onto an UEFI-enabled system)
#   dkms
#   sbsigntool
#
#
# Other prerequisites:
#  /sbin/dkms generate_mok
#     has been run once to populate /var/lib/dkms with mok.key and mok.pub
#
#  mokutil --import /var/lib/dkms/mok.pub
#     has been run once to prepare MOK key enrollment into the system's UEFI firmware
#
#  The MOK key has manually been enrolled into the system's UEFI firmware
#  (system reboot after successful `mokutil --import` execution).
#
#
# Author: thetredev <thetredev@gmail.com>
# License: MIT
#
############################################################################################



assert_file_exists() {
  local file_path=${1}
  local file_type=${2}

  if [[ ! -f ${file_path} ]]; then
    echo "${file_type} file '${file_path}' does not exist. Aborting verify/sign!"
    exit 1
  fi
}


set -e


source_image=${1:-"/boot/vmlinuz-$(uanme -r)"}
assert_file_exists ${source_image} "Source image"

sign_key=/var/lib/dkms/mok.key
assert_file_exists ${sign_key} "Signing key"

sign_cert_binary=/var/lib/dkms/mok.pub
assert_file_exists ${sign_key} "Public certificate of the signing key"


# sbverify and sbsign want the MOK cert in PEM format
# so create it if it doesn't exist yet
sign_cert_pem=/var/lib/dkms/mok.pem
test -f ${sign_cert} || openssl x509 -in ${sign_cert_binary} -outform PEM -out ${sign_cert_pem}

# do nothing if the source image was already signed
sbverify --cert ${sign_cert_pem} ${source_image} && exit 0

# otherwise sign the image and save it to a temporary file
temp_image="${source_image}.tmp"
sbsign --key ${sign_key} --cert ${sign_cert_pem} ${source_image} --output ${temp_image}

# verify the recently signed file
#   on failure: remove the temporary file + abort any further operations
if [[ ! $(sbverify --cert ${sign_cert_pem} ${temp_image}) ]]; then
  rm ${temp_image}
  exit 1
fi

# install the signed image by replacing the unsigned one with the former
mv ${temp_image} ${source_image}
