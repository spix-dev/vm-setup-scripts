
#!/usr/bin/env bash
set -euo pipefail

#======== Helpers ========#
log() { echo -e "\n\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\n\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\n\033[1;31m[ERROR]\033[0m $*"; }
inp() { echo -e "\n\033[1;34m[INPUT]\033[0m $*: "; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found"; exit 1; }
}

#======== Pre-flight ========#
require_cmd sudo
require_cmd sed
require_cmd tee
require_cmd curl

log "Updating APT and upgrading system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

#======== Hostname ========#
inp "Hostname"
read -r -p "" varhostname
if [[ -z "${varhostname}" ]]; then
  err "Hostname cannot be empty."
  exit 1
fi
if ! [[ "${varhostname}" =~ ^[a-zA-Z0-9-]+$ ]]; then
  warn "Hostname contains non-RFC characters. Continuing anyway."
fi
log "Setting hostname to '${varhostname}'..."
sudo hostnamectl set-hostname "${varhostname}"

#======== SSH Port ========#
inp "SSH Port (1024–65535 recommended)"
read -r -p "" varsshport
if ! [[ "${varsshport}" =~ ^[0-9]+$ ]] || (( varsshport < 1 || varsshport > 65535 )); then
  err "Invalid SSH port: ${varsshport}"
  exit 1
fi

log "Updating /etc/ssh/sshd_config to use Port ${varsshport}..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)

# Replace first occurrence of Port; else append
if grep -Eq '^[#\s]*Port\s+[0-9]+' /etc/ssh/sshd_config; then
  sudo sed -i -E "0,/^[#\s]*Port\s+[0-9]+/ s//Port ${varsshport}/" /etc/ssh/sshd_config
else
  echo "Port ${varsshport}" | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi

# Basic hardening, keep password auth enabled for now
if grep -Eq '^[#\s]*PermitRootLogin\s+' /etc/ssh/sshd_config; then
  sudo sed -i -E "s/^[#\s]*PermitRootLogin\s+.*/PermitRootLogin no/" /etc/ssh/sshd_config
else
  echo "PermitRootLogin no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi
# Ensure PubkeyAuthentication is enabled
if grep -Eq '^[#\s]*PubkeyAuthentication\s+' /etc/ssh/sshd_config; then
  sudo sed -i -E "s/^[#\s]*PubkeyAuthentication\s+.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config
else
  echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi
# Disable PasswordAuthentication for security
if grep -Eq '^[#\s]*PasswordAuthentication\s+' /etc/ssh/sshd_config; then
  sudo sed -i -E "s/^[#\s]*PasswordAuthentication\s+.*/PasswordAuthentication no/" /etc/ssh/sshd_config
else
  echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi

log "Testing sshd configuration..."
sudo sshd -t || { err "sshd configuration test failed. Restoring backup..."; sudo mv /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config; exit 1; }
log "Reloading ssh service..."
sudo systemctl reload ssh || sudo systemctl restart ssh

#======== Firewall (UFW) ========#
log "Configuring UFW..."
sudo apt-get install -y ufw
sudo ufw allow "${varsshport}/tcp"
if ufw app list | grep -q '^OpenSSH$'; then
  sudo ufw allow OpenSSH
fi
if ! sudo ufw status | grep -q "Status: active"; then
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  echo "y" | sudo ufw enable
else
  sudo ufw reload
fi

#======== Sudo password for user ========#
inp "System username"
read -r -p "" system_user_name
if [[ -z "${system_user_name}" ]]; then
  err "System username cannot be empty."
  exit 1
fi

log "Changing sudo password for ${system_user_name}..."
inp "System user password"
if id -u "${system_user_name}" >/dev/null 2>&1; then
  while true; do
    if sudo passwd "${system_user_name}"; then
      break
    else
      warn "Password change failed. Trying again..."
    fi
  done
else
  err "User '${system_user_name}' does not exist. Create it first: sudo adduser ${system_user_name} && sudo usermod -aG sudo ${system_user_name}"
fi

#======== SSH Keys from GitHub ========#
inp "GitHub username to fetch SSH keys"
read -r -p "" github_user
if [[ -z "${github_user}" ]]; then
  err "GitHub username cannot be empty."
  exit 1
fi

log "Fetching SSH public keys from https://github.com/${github_user}.keys ..."
tmp_keys="$(mktemp)"
if ! curl -fsSL "https://github.com/${github_user}.keys" -o "${tmp_keys}"; then
  err "Failed to download keys from GitHub for user '${github_user}'."
  rm -f "${tmp_keys}"
  exit 1
fi

# Basic validation: file not empty and contains typical key types
if ! [[ -s "${tmp_keys}" ]]; then
  err "No keys returned from GitHub for '${github_user}'."
  rm -f "${tmp_keys}"
  exit 1
fi
if ! grep -Eiq 'ssh-(rsa|ed25519|ecdsa)' "${tmp_keys}"; then
  warn "Downloaded file contains no recognized SSH key types. Continuing anyway."
fi

user_home="$(getent passwd "${system_user_name}" | cut -d: -f6)"
ssh_dir="${user_home}/.ssh"
auth_keys="${ssh_dir}/authorized_keys"

log "Installing keys into ${auth_keys} ..."
sudo mkdir -p "${ssh_dir}"
sudo touch "${auth_keys}"
# Backup existing authorized_keys
sudo cp "${auth_keys}" "${auth_keys}.bak.$(date +%s)" || true

# Deduplicate: merge existing + new keys, unique lines
sudo sh -c "cat '${tmp_keys}' >> '${auth_keys}'"
sudo sh -c "sort -u '${auth_keys}' -o '${auth_keys}'"

# Permissions and ownership
sudo chown -R "${system_user_name}:${system_user_name}" "${ssh_dir}"
sudo chmod 700 "${ssh_dir}"
sudo chmod 600 "${auth_keys}"
rm -f "${tmp_keys}"

log "Reloading ssh to ensure key auth is recognized..."
sudo systemctl reload ssh || sudo systemctl restart ssh

#======== Docker Installation (Optional) ========#
echo ""
read -r -p "Do you want to install Docker now? (y/N): " install_docker
if [[ "${install_docker,,}" =~ ^(y|yes)$ ]]; then
  log "Starting Docker installation..."

  log "Removing conflicting container packages (if present)..."
  sudo apt-get purge -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
  sudo apt-get autoremove -y || true

  log "Installing prerequisites for Docker repo..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl

  log "Adding Docker's official GPG key..."
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release
  log "Adding Docker APT repository (stable) for '${UBUNTU_CODENAME:-$VERSION_CODENAME}'..."
  sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  log "Updating APT indexes..."
  sudo apt-get update -y

  log "Installing Docker Engine and plugins..."
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Enabling and starting Docker service..."
  sudo systemctl enable --now docker

  log "Adding '${system_user_name}' to 'docker' group..."
  sudo usermod -aG docker "${system_user_name}"

  log "Docker installation complete!"
else
  log "Skipping Docker installation."
fi

#======== Final Notes ========#
log "Setup complete!"

echo -e "\nNext steps:"
echo "  1) IMPORTANT: Open a NEW terminal and verify you can SSH on port ${varsshport} using your GitHub key (user: ${system_user_name})."
echo "     DO NOT close this session until you've confirmed SSH key login works!"
if [[ "${install_docker,,}" =~ ^(y|yes)$ ]]; then
  echo "  2) Log out/in or run 'newgrp docker' to apply docker group membership; then test: 'docker run hello-world'."
  echo "  3) Optional reboot: 'sudo reboot'."
else
  echo "  2) Run setup-docker.sh if you want to install Docker later."
  echo "  3) Optional reboot: 'sudo reboot'."
fi
