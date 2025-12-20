# Ubuntu Server Setup Script

## Quick Install

```bash
wget https://raw.githubusercontent.com/spix-dev/vm-setup-scripts/master/setup-init.sh
chmod +x setup-init.sh
./setup-init.sh
```

---

## What This Does

Automated Ubuntu server initial setup script that configures:

- **System Updates** - Updates APT packages and upgrades the system
- **Hostname Configuration** - Sets a custom hostname for your server
- **SSH Hardening** - Configures custom SSH port, disables root login, enables public key authentication
- **Firewall (UFW)** - Configures and enables UFW with your SSH port allowed
- **User Management** - Sets sudo password for your system user
- **SSH Key Import** - Automatically imports SSH public keys from your GitHub account
- **Docker Installation** (optional) - Installs Docker Engine, Docker Compose, and adds user to docker group

## Requirements

- Fresh Ubuntu installation (20.04 LTS or newer recommended)
- Root or sudo access
- Internet connection
- GitHub account with uploaded SSH public keys

## Interactive Prompts

The script will ask you for:

1. **Hostname** - Your desired server hostname
2. **SSH Port** - Custom SSH port (recommended: 1024-65535)
3. **System Username** - The user account to configure
4. **System User Password** - New sudo password for the user
5. **GitHub Username** - To fetch your SSH public keys
6. **Docker Installation** - Whether to install Docker (y/N)

## Post-Setup Steps

1. **CRITICAL**: Open a new terminal and verify SSH access on your custom port with key authentication **BEFORE** closing your current session
2. If Docker was installed, log out/in or run `newgrp docker`, then test with `docker run hello-world`
3. Optional: Reboot the server with `sudo reboot`

## Security Notes

- **Password authentication is DISABLED by default** - only SSH key authentication is allowed
- Ensure your GitHub SSH keys are correctly uploaded before running this script
- Root login is disabled automatically
- UFW firewall is enabled with default deny incoming policy
- **CRITICAL**: Always test SSH access in a new terminal before closing your current session to avoid being locked out

---

# Update Scripts

Script designed to be pre-installed on VM templates. When you deploy a new VM from the template, run this script to download all the latest scripts from the repository.

## Quick Install

```bash
wget https://raw.githubusercontent.com/spix-dev/vm-setup-scripts/master/update-scripts.sh
chmod +x update-scripts.sh
./update-scripts.sh
```

## What This Does

- Automatically installs git if not already present
- Clones the entire repository and moves all scripts to the current directory
- Overwrites existing scripts with the latest versions
- Makes all scripts executable
- Future-proof: automatically includes any new scripts added to the repository

---

# Disk Resize Script

## Quick Install

```bash
wget https://raw.githubusercontent.com/spix-dev/vm-setup-scripts/master/resize-disk.sh
chmod +x resize-disk.sh
sudo ./resize-disk.sh
```

## What This Does

Automatically resizes your VM's disk partition and filesystem after you've increased the disk size in Proxmox (or other hypervisor). This script safely:

- **Detects Partition Layout** - Automatically identifies LVM or direct partition setups
- **Grows Partition** - Expands the partition to use all available disk space
- **Resizes Physical Volume** - Extends PV if using LVM
- **Extends Logical Volume** - Grows LV to use all free space in VG (LVM only)
- **Resizes Filesystem** - Expands the filesystem (ext4, XFS, or Btrfs)

## Use Case

After increasing disk size in your Proxmox GUI:

1. The hypervisor sees the new disk size
2. The VM's partition table still shows the old size
3. This script bridges the gap by resizing everything inside the VM

## Requirements

- Ubuntu 20.04 LTS or newer (tested on 24.04.3)
- Root or sudo access
- Disk must already be increased at the hypervisor level
- Internet connection (to install required packages if missing)

## Supported Configurations

- **Partition Types**: LVM and direct partitions
- **Filesystems**: ext2, ext3, ext4, XFS, Btrfs
- **Disk Types**: VirtIO (`/dev/vda`), SCSI (`/dev/sda`), NVMe (`/dev/nvme*`)

## How to Use

1. **In Proxmox GUI**: Increase the disk size for your VM
2. **In the VM**: Run this script
3. The script will show current layout and ask for confirmation
4. Type `yes` to proceed
5. Verification shows new disk space available

## Safety Notes

- The script requires explicit `yes` confirmation before making changes
- Generally safe on modern Linux systems with growpart
- **RECOMMENDED**: Take a snapshot/backup before resizing
- The script will not shrink partitions, only grow them
- No reboot required for the changes to take effect

## License

MIT
