#!/usr/bin/bash -f
function yes_no {
  while true; do
    read -p "$* [y/n]: " yn
    case $yn in
      [Yy]*) return 0 ;;
      [Nn]*) echo "Cancelled"; return 1 ;;
    esac
  done
}
# Make sure only root can run this script
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 1>&2
  echo "Usage: sudo $0" 1>&2
  exit 1
fi
# Confirm
yes_no "This will write to the secureboot, are you sure?" && yes_no "Really sure" || exit 1 
# Restore backup
cd /home/glecoz/Documents/sb-backup
for var in PK KEK db dbx; do
  sbctl enroll-keys --custom-bytes ./bak_${var}.esl --partial ${var} --append
done
