#!/usr/bin/bash -f
# Make sure only root can run this script
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 1>&2
  echo "Usage: sudo $0" 1>&2
  exit 1
fi
# Create backup dir
mkdir -p /home/glecoz/Documents/sb-backup && cd 
for var in PK KEK db dbx; do
  # Get the key
  efi-readvar -v ${var} -o bak_${var}.esl
  # Export it as DER
  sig-list-to-certs bak_${var}.esl bak_cert_${var}
done
chown -R glecoz:glecoz /home/glecoz/Documents/sb-backup
