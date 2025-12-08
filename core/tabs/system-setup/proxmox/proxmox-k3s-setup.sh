#!/bin/bash

# ==============================================================================
# Proxmox K3s Control Plane Setup
#
# This script creates an LXC container and sets up a K3s control plane.
# It handles LXC creation, Tailscale configuration, and K3s installation.
# ==============================================================================

# --- Source common functions and set colors ---
source "$(dirname "$0")/proxmox-common.sh"

# --- Helper Functions (Local to this script) ---
get_lxc_templates() {
    local template_storage
    template_storage=$(grep -B 2 'content .*vztmpl' /etc/pve/storage.cfg | grep -E 'dir:|nfs:|cifs:' | head -n 1 | awk '{print $2}')

    if [[ -z "$template_storage" ]]; then
        return
    fi
    pveam list "$template_storage" | tail -n +2 | awk '{print $1}'
}

get_rootfs_storage() {
    # Parse pvesm status to find active storage that supports rootdir or images
    # We look for storage that is 'active' and supports 'rootdir' or 'images' content type.
    # pvesm status output format: Name Type Status Total Used Available %
    # pvesm set/list commands might be better but pvesm status ensures it's online.
    
    # Better approach: Iterate over all storage and check content type using pvesm list or just parsing config is safer IF we cross reference status.
    # However, 'pvesm status' doesn't show content type.
    # 'pvesm list <storage>' fails if not available.
    
    # Robust method:
    # 1. Get List of all enabled storage from pvesm status (to ensure they are up)
    local active_storages
    active_storages=$(pvesm status -enabled 2>/dev/null | awk 'NR>1 {print $1}')
    
    if [[ -z "$active_storages" ]]; then
        return
    fi
    
    # 2. For each active storage, check if it allows 'rootdir' or 'images'
    for storage in $active_storages; do
        # check content type from storage.cfg for this storage
        # pvesm gets ugly to parse content type directly from CLI without json.
        # simpler: grep the config for this specific storage block and check content.
        
        # We can use pvesm path to check if it supports the content type? No.
        # Let's fallback to parsing the config BUT only for storages that are in $active_storages.
        
        # Actually, 'pvesm list <storage> --content rootdir' serves as a check? No, that lists volumes.
        
        # Let's stick to parsing /etc/pve/storage.cfg but cross-referencing with active_storages.
        # This is safe because we only offer what is configured AND active.
        
        local content
        content=$(grep -A 5 "dir: $storage\|lvm: $storage\|lvmthin: $storage\|zfspool: $storage\|cifs: $storage\|nfs: $storage\|glusterfs: $storage\|pbs: $storage\|iscsi: $storage\|cephfs: $storage\|rbd: $storage\|zfs: $storage" /etc/pve/storage.cfg | grep "content" | head -n 1)
        
        # If we can't match exact line easily, let's use a simpler heuristic for content.
        # A storage block starts with "type: name".
        # We can just check if the storage name appears in the config associated with rootdir.
        
        if pvesm list "$storage" --content rootdir >/dev/null 2>&1; then
            echo "$storage"
        elif pvesm list "$storage" --content images >/dev/null 2>&1; then
             echo "$storage"
        fi
    done
}

# --- Main Logic ---
main() {
    clear
    print_header "Proxmox K3s Control Plane Setup"

    # --- 1. Container Configuration ---
    
    # Get Next ID
    local next_id
    next_id=$(get_next_id 'lxc' 2>/dev/null)
    
    # Log file on host (temporary)
    LOG_FILE="/tmp/k3s-setup-${next_id}.log"
    rm -f "$LOG_FILE" 2>/dev/null
    
    # Default to 201 if next_id is less than 201 (as requested by user preference, though user said "default will 201")
    # If the user explicitly wants 201 as default, we can suggest it.
    if [ "$next_id" -lt 201 ]; then
        next_id=201
    fi
    # Check if 201 is already taken, if so, just use the next available
    if pct status 201 &>/dev/null; then
        next_id=$(get_next_id 'lxc')
    fi

    echo -e "✅ Proposed Container ID: ${COLOR_GREEN}${next_id}${COLOR_NC}"
    read -p "Press Enter to accept or enter a different ID: " vmid
    vmid=${vmid:-$next_id}
    
    # Update log file name if ID changed
    LOG_FILE="/tmp/k3s-setup-${vmid}.log"

    # Select Template
    print_header "Select LXC Template"
    mapfile -t template_volids < <(get_lxc_templates)
    if [ ${#template_volids[@]} -eq 0 ]; then
        print_error "No LXC templates found. Please download some with 'pveam download <storage> <template>'."
        return 1
    fi

    local template_display_names=()
    for volid in "${template_volids[@]}"; do
        template_display_names+=("$(echo "$volid" | sed 's#.*/##')")
    done

    select template_display_name in "${template_display_names[@]}"; do
        if [[ -n "$template_display_name" ]]; then
            for volid in "${template_volids[@]}"; do
                if [[ "$volid" == *"$template_display_name" ]]; then
                    template_volid="$volid"
                    break
                fi
            done
            break
        else
            print_error "Invalid selection."
        fi
    done

    # Storage
    print_header "Storage Configuration"
    mapfile -t storages < <(get_rootfs_storage | sort -u)
    if [ ${#storages[@]} -eq 0 ]; then
        print_error "No suitable storage found."
        return 1
    fi
    echo "Choose storage for root disk:"
    select storage in "${storages[@]}"; do
        if [[ -n "$storage" ]]; then break; fi
    done
    
    read -p "Disk size in GB [Default: 8]: " disk_size
    disk_size=${disk_size:-8}
    rootfs="${storage}:${disk_size}"

    # Resources
    print_header "System Resources"
    read -p "CPU Cores [Default: 2]: " cores
    cores=${cores:-2}
    read -p "RAM in MB [Default: 2048]: " memory
    memory=${memory:-2048}
    read -p "Swap in MB [Default: 512]: " swap
    swap=${swap:-512}

    # Network
    print_header "Network Configuration"
    local bridge
    bridge=$(ip -br a | grep 'UP' | awk '{print $1}' | grep 'vmbr' | head -n 1)
    echo "Using bridge: ${bridge}"
    
    read -p "Use DHCP or Static IP? (dhcp/static) [Default: dhcp]: " ip_type
    ip_type=${ip_type:-dhcp}
    
    if [ "$ip_type" = "static" ]; then
        while true; do
            read -p "IP CIDR [Default: 192.168.0.201/24]: " static_ip
            static_ip=${static_ip:-192.168.0.201/24}
            if [[ "$static_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                break
            else
                echo "Invalid format. Please include subnet mask (e.g., /24)."
            fi
        done
        read -p "Gateway [Default: 192.168.0.1]: " gateway
        gateway=${gateway:-192.168.0.1}
        read -p "DNS Server (Optional): " dns
        net0="name=eth0,bridge=${bridge},ip=${static_ip},gw=${gateway}"
        if [ -n "$dns" ]; then nameserver="--nameserver ${dns}"; fi
    else
        net0="name=eth0,bridge=${bridge},ip=dhcp"
    fi

    # --- 2. Tailscale & K3s Config ---
    print_header "Cluster Configuration"
    read -p "Enter Tailscale Auth Key (tskey-auth-...): " ts_key
    read -p "Enter Hostname (for OS and Tailscale): " hostname
    read -p "Enter Tailscale Tag (e.g. k3s-control): " ts_tag
    
    # --- 3. Confirmation ---
    clear
    print_header "Confirm Settings"
    echo -e "ID: ${vmid}"
    echo -e "Hostname: ${hostname}"
    echo -e "Template: ${template_volid}"
    echo -e "Resources: ${cores} CPU, ${memory}MB RAM, ${disk_size}GB Disk"
    echo -e "Network: ${net0}"
    echo -e "Tailscale Tag: ${ts_tag}"
    echo -e "Cluster Role: K3s Control Plane"
    
    read -p "Proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then exit 1; fi

    # --- 4. Execution ---
    print_header "Creating LXC Container..."
    
    # Create LXC
    pct create "$vmid" "$template_volid" \
        --rootfs "$rootfs" \
        --hostname "$hostname" \
        --password "k3s-password" \
        --memory "$memory" --swap "$swap" --cores "$cores" \
        --net0 "$net0" \
        --onboot 1 \
        --features nesting=1 \
        $nameserver
        
    print_success "Container $vmid created."
    
    # Enable K3s and Tailscale Requirements
    # Enable K3s and Tailscale Requirements
    if ! grep -q "lxc.mount.entry: /dev/kmsg" "/etc/pve/lxc/${vmid}.conf"; then
        cat >> "/etc/pve/lxc/${vmid}.conf" << 'EOF'

# K3s Requirements
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.mount.auto: proc:rw sys:rw
lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file 0 0

# Tailscale TUN Device
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
    fi

    # Start Container
    print_header "Starting Container..."
    pct start "$vmid"
    sleep 5 # Wait for init

    # Install Dependencies & SSH
    print_header "Installing Dependencies..."
    pct exec "$vmid" -- apt-get update
    pct exec "$vmid" -- apt-get install -y curl openssh-server
    pct exec "$vmid" -- systemctl enable --now ssh
    
    # Install Tailscale
    print_header "Installing Tailscale..."
    pct exec "$vmid" -- bash -c "curl -fsSL https://tailscale.com/install.sh | sh" | tee -a "$LOG_FILE"
    
    # Find Tailscale Binary
    TS_BIN=$(pct exec "$vmid" -- which tailscale)
    if [ -z "$TS_BIN" ]; then
        TS_BIN=$(pct exec "$vmid" -- find / -name tailscale -type f -executable 2>/dev/null | head -n 1)
    fi
    
    if [ -n "$TS_BIN" ]; then
        # Check if we are already logged in to avoid interactive prompt issues if re-running
        if ! pct exec "$vmid" -- "$TS_BIN" status >/dev/null 2>&1; then
             pct exec "$vmid" -- "$TS_BIN" up --authkey="$ts_key" --hostname="$hostname" --advertise-tags="tag:${ts_tag}" --ssh 2>&1 | tee -a "$LOG_FILE"
        else
             echo "Tailscale already up." | tee -a "$LOG_FILE"
        fi
    else
        echo "Error: Tailscale binary not found." | tee -a "$LOG_FILE"
    fi
    
    # Install K3s
    print_header "Installing K3s Control Plane..."
    # Get Tailscale IP
    TS_IP=$(pct exec "$vmid" -- "$TS_BIN" ip -4 2>/dev/null)
    
    # K3s Install
    # We use sh -c to properly handle piping and redirection inside the container
    pct exec "$vmid" -- bash -c "curl -sfL https://get.k3s.io | sh -s - server --flannel-backend=none --disable-network-policy --tls-san $TS_IP --node-name $hostname" 2>&1 | tee -a "$LOG_FILE"

    print_success "K3s Control Plane Setup Complete on Node $vmid ($hostname)"
    
    # Move log to persistent location
    print_header "Saving Logs..."
    pct push "$vmid" "$LOG_FILE" /var/log/k3s-setup.log
    rm -f "$LOG_FILE"

    # Recommendation
    echo ""
    echo -e "${COLOR_YELLOW}Recommendation:${COLOR_NC} For HA k3s control plane, you should have at least 3 nodes."
    echo "This script can be run again to create additional control plane nodes (join command required)."
    echo ""
    echo "To view installation logs:"
    echo "pct exec $vmid -- cat /var/log/k3s-setup.log"
    
}

main "$@"
