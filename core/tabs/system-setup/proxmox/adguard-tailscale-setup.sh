#!/bin/bash

# Phase 1: Create LXC Container on Proxmox Host
echo "Creating LXC container..."
pct create 103 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --hostname adguard-tailscale \
  --memory 768 \
  --cores 1 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=10.0.0.52/24,gw=10.0.0.10 \
  --nameserver 8.8.8.8 \
  --nameserver 8.8.4.4 \
  --unprivileged 1 \
  --features nesting=1

# Phase 2: Configure TUN Device Access for Tailscale
echo "Configuring TUN device..."
cat <<EOT >> /etc/pve/lxc/103.conf
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOT

# Phase 3: Start Container and Update System
echo "Starting container and updating system..."
pct start 103
pct exec 103 -- apt update
pct exec 103 -- apt upgrade -y
pct exec 103 -- apt install -y curl sudo wget iptables ca-certificates

# Phase 4: Install Tailscale
echo "Installing Tailscale..."
pct exec 103 -- bash -c "curl -fsSL https://tailscale.com/install.sh | sh"
pct exec 103 -- tailscale up --accept-routes --hostname="adguard-tailscale"

# Phase 6: Install AdGuard Home
echo "Installing AdGuard Home..."
pct exec 103 -- bash -c "curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh"

# Phase 9: Configure Container Auto-Start
echo "Configuring container to start on boot..."
pct set 103 --onboot 1

echo "Script finished."
echo "Please complete the AdGuard Home setup via the web interface at http://10.0.0.52:3000"
echo "Then, authorize the new Tailscale device in your Tailscale admin console."
