#!/usr/bin/env bash
set -euo pipefail

#======== Helpers ========#
log() { echo -e "\n\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\n\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\n\033[1;31m[ERROR]\033[0m $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found"; exit 1; }
}

#======== Pre-flight ========#
require_cmd sudo
require_cmd lsblk
require_cmd df

log "Checking current disk and partition layout..."
echo ""
lsblk
echo ""
df -h
echo ""

#======== Detect Setup ========#
log "Detecting partition layout..."

# Find the root filesystem
root_mount=$(df / | tail -1 | awk '{print $1}')
log "Root filesystem is mounted on: ${root_mount}"

# Determine if using LVM or direct partition
if [[ "${root_mount}" =~ ^/dev/mapper/ ]] || [[ "${root_mount}" =~ ^/dev/.*-vg/ ]]; then
  using_lvm=true
  log "Detected LVM setup"

  # Get VG and LV names
  vg_name=$(sudo lvs --noheadings -o vg_name "${root_mount}" | tr -d ' ')
  lv_name=$(sudo lvs --noheadings -o lv_name "${root_mount}" | tr -d ' ')

  log "Volume Group: ${vg_name}"
  log "Logical Volume: ${lv_name}"

  # Find the physical disk and partition
  pv_name=$(sudo pvs --noheadings -o pv_name -S vg_name="${vg_name}" | tr -d ' ' | head -1)
  log "Physical Volume: ${pv_name}"

  # Extract disk name (e.g., /dev/sda3 -> /dev/sda)
  if [[ "${pv_name}" =~ ^/dev/(sd[a-z]|vd[a-z]|nvme[0-9]+n[0-9]+)p?[0-9]+$ ]]; then
    disk_name=$(echo "${pv_name}" | sed -E 's/p?[0-9]+$//')
    partition_num=$(echo "${pv_name}" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')
  else
    err "Could not parse disk name from PV: ${pv_name}"
    exit 1
  fi
else
  using_lvm=false
  log "Detected direct partition setup (no LVM)"

  # Extract disk and partition info
  if [[ "${root_mount}" =~ ^/dev/(sd[a-z]|vd[a-z]|nvme[0-9]+n[0-9]+)p?[0-9]+$ ]]; then
    disk_name=$(echo "${root_mount}" | sed -E 's/p?[0-9]+$//')
    partition_num=$(echo "${root_mount}" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')
    pv_name="${root_mount}"
  else
    err "Could not parse disk name from root mount: ${root_mount}"
    exit 1
  fi
fi

log "Disk: ${disk_name}"
log "Partition number: ${partition_num}"

#======== Confirmation ========#
warn "This script will resize partition ${partition_num} on ${disk_name} to use all available space."
warn "This operation is generally safe but you should have backups!"
echo ""
read -r -p "Continue? (yes/no): " confirm
if [[ "${confirm}" != "yes" ]]; then
  log "Aborted by user."
  exit 0
fi

#======== Resize Partition ========#
log "Resizing partition ${pv_name}..."

# Install required tools if missing
if ! command -v growpart >/dev/null 2>&1; then
  log "Installing cloud-guest-utils for growpart..."
  sudo apt-get update -y
  sudo apt-get install -y cloud-guest-utils
fi

if ! command -v parted >/dev/null 2>&1; then
  log "Installing parted..."
  sudo apt-get update -y
  sudo apt-get install -y parted
fi

# Use growpart to resize the partition
log "Growing partition ${partition_num} on ${disk_name}..."
if sudo growpart "${disk_name}" "${partition_num}"; then
  log "Partition resized successfully"
else
  warn "growpart reported no changes needed or failed. Checking if partition is already at maximum size..."
fi

# Inform kernel of partition table changes
sudo partprobe "${disk_name}" || true

#======== Resize Physical Volume (if LVM) ========#
if [[ "${using_lvm}" == "true" ]]; then
  log "Resizing Physical Volume ${pv_name}..."
  sudo pvresize "${pv_name}"

  log "Extending Logical Volume ${lv_name}..."
  sudo lvextend -l +100%FREE "/dev/${vg_name}/${lv_name}"

  resize_target="/dev/${vg_name}/${lv_name}"
else
  resize_target="${pv_name}"
fi

#======== Resize Filesystem ========#
log "Detecting filesystem type on ${resize_target}..."
fs_type=$(sudo blkid -o value -s TYPE "${resize_target}")
log "Filesystem type: ${fs_type}"

case "${fs_type}" in
  ext2|ext3|ext4)
    log "Resizing ext filesystem..."
    sudo resize2fs "${resize_target}"
    ;;
  xfs)
    log "Resizing XFS filesystem..."
    sudo xfs_growfs /
    ;;
  btrfs)
    log "Resizing Btrfs filesystem..."
    sudo btrfs filesystem resize max /
    ;;
  *)
    err "Unsupported filesystem type: ${fs_type}"
    exit 1
    ;;
esac

#======== Final Status ========#
log "Resize complete! New disk layout:"
echo ""
lsblk
echo ""
df -h
echo ""
log "Done! Your disk has been resized to use all available space."
