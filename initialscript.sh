#!/usr/bin/env bash
# Ensures the script stops on any error, making it safer.
set -euo pipefail

# This script prepares the VM by installing all necessary packages and checking the environment.

# --- 1. Root User Check ---
# Provisioning scripts typically run as root, but this check ensures it.
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be executed as root (or with sudo)."
  exit 1
fi

echo "~> Starting VM Configuration..."

# --- 2. Package Installation ---
# Set apt to non-interactive mode to prevent it from asking for user input during provisioning.
export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "~> Installing project dependencies..."
# Install essential packages required by the project scripts.
# --no-install-recommends keeps the VM footprint smaller.
apt-get install -y --no-install-recommends \
  build-essential \
  util-linux \
  iproute2 \
  coreutils \
  procps \
  jq \
  lsof \
  lsblk \
  python3 \
  python3-venv

# Optional: Install 'stress' tool, useful for load testing and demonstrations.
apt-get install -y --no-install-recommends stress || true

echo "~> Package installation finished."

# --- 3. System Cleanup ---
# Clean up apt cache to save disk space in the final VM.
apt-get clean
rm -rf /var/lib/apt/lists/*

# --- 4. Cgroup v2 Environment Check ---
echo "~> Checking if cgroup v2 is active (unified hierarchy)..."

# A robust check: looks for 'type cgroup2' in mount output or the v2 controllers file.
if mount | grep -q 'type cgroup2' || [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "~> SUCCESS: cgroup v2 detected."
else
  echo "~> WARN: cgroup v2 was not detected or not mounted at /sys/fs/cgroup."
  echo "  - If you are using a VM image that doesn't enable cgroup v2 by default, you can"
  echo "    enable it by adding 'systemd.unified_cgroup_hierarchy=1' to your kernel"
  echo "    boot options (usually in GRUB) and then rebooting the VM."
  echo "  - Many modern Vagrant boxes (like bento/ubuntu-22.04) already have this enabled."
  # If you want the script to fail when cgroup v2 is missing, uncomment the line below:
  # exit 1
fi

# --- 5. Create Base Project Directories ---
# Create the base directories that the project scripts will use.
mkdir -p /vagrant/scripts /vagrant/outputs
# Change ownership to the 'vagrant' user so you can easily edit files after ssh'ing.
chown -R vagrant:vagrant /vagrant || true

echo "~> Initial VM Configuration Finished!"