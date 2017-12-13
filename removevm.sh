#!/bin/sh
#set -x 
set -e

USAGE="`basename $0` <vmname>"

if [ $# -lt 1 ]; then
  echo "\nUsage: $USAGE"
  exit 1
fi

HOST="${1:-onevm}"
EXPORT_PATH="${2:-/var/lib/bareos/}"
BACKUP="${HOST}_snap_disk"

for i in `find ${EXPORT_PATH} -maxdepth 1 -name ${BACKUP}\* -print |tr "\n" " "`; do 
  find $i -delete
done
