#!/bin/bash

set -euxo pipefail

BASE_DIR=${BASE_DIR:-"/mnt/"}
declare -a MOUNT_LIST=("/mnt/data" "/mnt/data2")
NVME_LIST=($(nvme list | grep "Amazon EC2 NVMe Instance Storage" | cut -d " " -f 1 || true))
NVME_COUNT=${#NVME_LIST[@]}
PARTED_SCRIPT=${PARTED_SCRIPT:-""}

# Checking if local disks are already provisioned
if [[ "$(ls -A $BASE_DIR)" ]]
then
  echo -e "\n$(ls -Al $BASE_DIR | tail -n +2)\n"
  echo "Local disks are already provisioned"
  sleep infinity
fi

for mntpointinlist in "${MOUNT_LIST[@]}"; do
  mkdir -p $mntpointinlist
done

case ${NVME_COUNT} in
"0")
  printf "There are no 'Amazon EC2 NVMe Instance Storage' devices.\n"
  exit 1
  ;;

*)
  printf "Following 'Amazon EC2 NVMe Instance Storage' devices are found:\n"
  printf "%s\n" ${NVME_LIST[@]}
  if [ -z "$PARTED_SCRIPT" ]
  then
    # PARTITIONING
    printf "Proceed without partitioning.\n"
    # FORMATTING
    for NVME in ${NVME_LIST[@]}
    do
      mkfs.xfs -f $NVME
      UUID=$(blkid -s UUID -o value "$NVME") 
      #mkdir $BASE_DIR/$UUID
      for mntpointinlist in "${MOUNT_LIST[@]}"; do
        if mountpoint -q "$mntpointinlist"; then
        printf "%s already mounted\n" $mntpointinlist
    else
        mount -t xfs "$NVME" "$mntpointinlist"
        echo UUID=`blkid -s UUID -o value "$NVME"` $mntpointinlist xfs defaults 0 2 | tee -a /etc/fstab
        break
    fi
      done
    done
  else
    # PARTITIONING
    printf "Partitioning script: %s\n" "${PARTED_SCRIPT}"
    for NVME in ${NVME_LIST[@]}
    do
      parted --script $NVME ${PARTED_SCRIPT}
    done
    # FORMATTING
    for NVME in ${NVME_LIST[@]}
    do
      PARTITION_COUNT=$(lsblk | grep $(cut -d'/' -f3 <<<$NVME)p | wc -l)
      for i in $(seq 1 $PARTITION_COUNT); do
        mkfs.xfs -f "$NVME"p"$i"
        UUID=$(blkid -s UUID -o value "$NVME"p"$i")
        #mkdir $BASE_DIR/$UUID
        mount -t xfs "$NVME"p"$i" $BASE_DIR
        echo UUID=`blkid -s UUID -o value "$NVME"p"$i"` $BASE_DIR xfs defaults 0 2 | tee -a /etc/fstab
      done
    done
  fi
  
  ;;
esac

echo "Local disks are provisioned succesfully"
sleep infinity
