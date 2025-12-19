# Ubuntu Server Setup Script

## Quick Install

```bash
wget -qO- https://raw.githubusercontent.com/spix-dev/vm-setup-scripts/master/setup.sh | bash
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

## Manual Installation

If you prefer to review the script before running:

```bash
wget https://raw.githubusercontent.com/spix-dev/vm-setup-scripts/master/setup.sh
chmod +x setup.sh
./setup.sh
```

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

## License

MIT
