#!/bin/sh
#set -x 
set -e

USAGE="`basename $0` <vmname>"

if [ $# -ne 1 ]; then
  echo "\nUsage: $USAGE"
  exit 1
fi

HOST="${1:-onevm}"
BACKUP="${HOST}_snap_disk"
EXPORT_PATH="/var/lib/bareos"

for i in `find ${EXPORT_PATH} -maxdepth 1 -name ${BACKUP}\* -print |tr "\n" " "`; do 
  find $i -delete
done
