#!/bin/sh
#set -x
set -e

usage() {
  echo "Usage: $0 [-a one_auth] [-c ceph_conf] [-d export_dir] [-f] [-i rbd_id] [-p rbd_pool] [-u rpc_url] [-v] [vmname]"
  echo "Defaults:"
  echo "    one_auth:   /var/lib/bareos/.one_auth"
  echo "   ceph_conf:   /etc/ceph/ceph.conf"
  echo "  export_dir:   /var/lib/bareos/"
  echo "          -f:   file extraction from snapshot (experimental, requires libguestfs)"
  echo "      rbd_id:   libvirt"
  echo "    rbd_pool:   one-pool"
  echo "     rpc_url:   127.0.0.1"
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
LIMIT="1080"
WAIT="5"
DOW=$(date +"%u")
DATE=$(date +"%F-%T")

while getopts a:c:d:fi:p:u:v o; do
  case "$o" in
    a) ONE_AUTH="$OPTARG"
    ;;
    c) CEPH_CONF="$OPTARG"
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
    v) LOG="/tmp/exportvm.${DATE}.log"
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
LOG="${LOG:-/dev/null}"
CEPH_CONF="${CEPH_CONF:-/etc/ceph/ceph.conf}"

export ONE_AUTH ONE_XMLRPC

GEN_DISK_IDS=$(onevm show ${HOST} | sed -n -e '/VM DISKS/,/VM NICS/ p' |grep ${HOST} | awk '{print $1}' | tr "\n" " ")


# If the vm does not exist do not continue
if [ $(${ONEVM} list -f NAME=${HOST} -lNAME |grep -v "NAME"|wc -l) -eq 0 ]; then
  echo "VM ${HOST} not found" >> ${LOG} 2>&1
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
      echo "Backup image ${HOST} already exists" >> ${LOG} 2>&1
      exit 1
    fi 

    # Take snapshot for backup
    ${ONEVM} disk-saveas ${HOST} ${DISK_ID} ${SAVEIMG} >> ${LOG} 2>&1
    # Legacy command <= V4.12
    #${ONEVM} disk-snapshot --live ${HOST} ${DISK_ID} ${SAVEIMG} >> ${LOG} 2>&1

    # Wait LIMIT * WAIT seconds max for the image to be ready
    until [ $(${ONEIMAGE} show ${SAVEIMG} | grep STATE | cut -d ":" -f 2) = "rdy" ]; do
      if [ ${ABORT} -eq 0 ]; then
        C=$(($C+1))
        sleep $WAIT
          if [ ${C} -eq ${LIMIT} ]; then
            ABORT=1
          fi
      else
        echo "Snapshot of ${HOST} exceeded time limit of $((${LIMIT}*${WAIT})) seconds" >> ${LOG} 2>&1
        exit 1
      fi
    done

    # Output the path for export
    RBD_IMAGE=$(${ONEIMAGE} show ${SAVEIMG} | grep SOURCE | cut -d ":" -f 2) 

    # Export rdb device to disk for backup
    if [ -f ${EI} ]; then
      echo "File ${EI} already exists" >> ${LOG} 2>&1
      exit 1
    else
      ${RBD} -c $CEPH_CONF --no-progress --id $RBD_ID -p $RBD_POOL export ${RBD_IMAGE} ${EI}
    fi

    # Delete snapshot once exported to disk
    if [ $? -eq 0 ]; then
      ${ONEIMAGE} delete ${SAVEIMG}
    else
      echo "Export error for ${EI}" >> ${LOG} 2>&1
      exit 1
    fi

    # Output fileset for backup (for file extraction also output the image once a week)
    if [ ${EXTRACT} = "NO" ]; then
      echo ${EI}
    elif [ ${EXTRACT} = "YES" ]; then
      # output the image on a friday
      if [ "${DOW}" -eq 5 ]; then
      # output snapshot on sat or sun to gives the full fs more backup time
      #if [ "${DOW}" -eq 6 -o "${DOW}" -eq 7 ]; then
        echo ${EI}
      fi
      mkdir -p ${EF}
      if [ "${DISK_ID}" -eq 0 ]; then
        guestfish --ro -i copy-out -a ${EI} / ${EF} >> ${LOG} 2>&1 | head
      else
        FS=$(virt-list-filesystems ${EI} | head -1)
        guestfish --ro -a ${EI} -m ${FS} tar-out / - | tar -xf - -C ${EF}
      fi
      echo ${EF}
    else
      echo "Extract error for ${EF}" >> ${LOG} 2>&1
      exit 1
    fi
  done

else
  # Bork
  echo "${HOST} not found or not running" >> ${LOG} 2>&1
  exit 1
fi

