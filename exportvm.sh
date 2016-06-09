#!/bin/sh
#set -x
set -e

usage() {
  echo "Usage: $0 [-a one_auth] [-d export_dir] [-f] [-i rbd_id] [-p rbd_pool] [-u rpc_url] [vmname]"
  echo "Defaults:"
  echo "  one_auth:   /var/lib/bareos/.one_auth"
  echo "  export_dir: /var/lib/bareos/"
  echo "  -f file extraction from snapshot (experimental, requires libguestfs)"
  echo "  rbd_id:     libvirt"
  echo "  rbd_pool:   one-pool"
  echo "  rpc_url:    127.0.0.1"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi


# One env
ONEVM="/usr/bin/onevm"
ONEIMAGE="/usr/bin/oneimage"

# RBD env
RBD="/usr/bin/rbd"

# Script env
C="0"
ABORT="0"
LIMIT="900"
WAIT="5"
DOW=$(date +"%u")

while getopts a:d:fi:p:u: o; do
  case "$o" in
    a) ONE_AUTH="$OPTARG"
    ;;
    d) EXPORT_PATH="$OPTARG"
    ;;
    f) EXTRACT="YES"
    ;;
    i) RBD_ID="$OPTARG"
    ;;
    p) RBD_POOL="$OPTARG"
    ;;
    u) URL="$OPTARG"
    ;;
    \?)
    usage
    ;;
  esac
done
shift $(($OPTIND - 1))

HOST="${1:-onevm}"
URL="${URL:-127.0.0.1}"
ONE_AUTH="${ONE_AUTH:-/var/lib/bareos/.one_auth}"
ONE_XMLRPC="http://${URL}:2633/RPC2"
RBD_ID="${RBD_ID:-libvirt}"
RBD_POOL="${RBD_POOL:-one-pool}"
EXPORT_PATH="${EXPORT_PATH:-/var/lib/bareos}"
EXTRACT="${EXTRACT:-NO}"
BACKUP="${HOST}_snap_disk"

export ONE_AUTH ONE_XMLRPC

GEN_DISK_IDS=$(onevm show ${HOST} | sed -n -e '/VM DISKS/,/VM NICS/ p' |grep ${HOST} | awk '{print $1}' | tr "\n" " ")


# If the vm does not exist do not continue
if [ $(${ONEVM} list -f NAME=${HOST} -lNAME |grep -v "NAME"|wc -l) -eq 0 ]; then
  echo VM not found
  exit 1
fi 

# Check the vm is running and proceed
if [ $(${ONEVM} show ${HOST} | grep LCM_STATE | cut -d ":" -f 2) = "RUNNING" ]; then

  for DISK_ID in ${GEN_DISK_IDS}; do
    SAVEIMG=${BACKUP}_${DISK_ID}
    EI=${EXPORT_PATH}/${SAVEIMG}
    EF=${EI}_fs

    # If the images exists, something is wrong 
    if [ $(${ONEIMAGE} list -f NAME=${SAVEIMG} -lNAME |grep -v "NAME"|wc -l) -ne 0 ]; then
      echo Backup image already exists
      exit 1
    fi 

    # Take snapshot for backup
    # V4.14
    #${ONEVM} disk-saveas --live ${HOST} ${DISK_ID} ${SAVEIMG} > /dev/null 2>&1 
    # V4.12
    ${ONEVM} disk-snapshot --live ${HOST} ${DISK_ID} ${SAVEIMG} > /dev/null 2>&1 
    # Wait 15 min max for the image to be ready
    until [ $(${ONEIMAGE} show ${SAVEIMG} | grep STATE | cut -d ":" -f 2) = "rdy" ]; do
      if [ ${ABORT} -eq 0 ]; then
        C=$(($C+1))
        sleep $WAIT
          if [ ${C} -eq ${LIMIT} ]; then
            ABORT=1
          fi
      else
        echo Snapshot exceeded time limit of $((${LIMIT}*${WAIT})) seconds
        exit 1
      fi
    done

    # Output the path for export
    RBD_IMAGE=$(${ONEIMAGE} show ${SAVEIMG} | grep SOURCE | cut -d ":" -f 2) 

    # Export rdb device to disk for backup
    if [ -f ${EI} ]; then
      echo File already exists
      exit 1
    else
      ${RBD} --no-progress --id $RBD_ID -p $RBD_POOL export ${RBD_IMAGE} ${EI}
    fi

    # Delete snapshot once exported to disk
    if [ $? -eq 0 ]; then
      ${ONEIMAGE} delete ${SAVEIMG}
    else
      echo Export error
      exit 1
    fi

    # Output fileset for backup (for file extraction also output the image once a week)
    if [ ${EXTRACT} = "NO" ]; then
      echo ${EI}
    elif [ ${EXTRACT} = "YES" ]; then
      if [ "${DOW}" -eq 5 ]; then
        echo ${EI}
      fi
      mkdir -p ${EF}
      if [ "${DISK_ID}" -eq 0 ]; then
        guestfish --ro -i copy-out -a ${EI} / ${EF} > /dev/null 2>&1 | head
      else
        FS=$(virt-list-filesystems ${EI} | head -1)
        guestfish --ro -a ${EI} -m ${FS} tar-out / - | tar -xf - -C ${EF}
      fi
      echo ${EF}
    else
      echo Extract error 
      exit 1
    fi
  done

else
  # Bork
  echo ${HOST} not found or not running
  exit 1
fi
