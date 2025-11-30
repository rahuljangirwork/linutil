#!/bin/bash

# ==============================================================================
# Create LXC Container
#
# An interactive script to guide the user through creating a new LXC container.
# ==============================================================================

# --- Source common functions and set colors ---
source "$(dirname "$0")/proxmox-common.sh"

# --- Helper Functions ---
get_lxc_templates() {
    # This logic mirrors the working function in proxmox-common.sh
    # It's fragile but should work for this environment. It only finds the first storage.
    local template_storage
    template_storage=$(grep -B 2 'content .*vztmpl' /etc/pve/storage.cfg | grep -E 'dir:|nfs:|cifs:' | head -n 1 | awk '{print $2}')

    if [[ -z "$template_storage" ]]; then
        return
    fi

    # Return the full VolID for each template on that storage
    pveam list "$template_storage" | tail -n +2 | awk '{print $1}'
}

get_rootfs_storage() {
    # This logic mirrors the working function in proxmox-common.sh
    # It's fragile but should work for this environment.
    grep -B 2 'content .*rootdir' /etc/pve/storage.cfg | grep 'dir:\|lvmthin:\|zfspool:' | awk '{print $2}'
    grep -B 2 'content .*images' /etc/pve/storage.cfg | grep 'dir:\|lvmthin:\|zfspool:' | awk '{print $2}'
}

# --- Main Logic ---
main() {
    clear
    echo "===================================="
    echo "      Create New LXC Container"
    echo "===================================="

    # --- Get Next Available ID ---
    local next_id
    next_id=$(get_next_id 'lxc')
    echo -e "✅ Proposed Container ID: ${COLOR_GREEN}${next_id}${COLOR_NC}"
    read -p "Press Enter to accept or enter a different ID: " vmid
    vmid=${vmid:-$next_id}

    # --- Select Template ---
    print_header "Select a Template"
    mapfile -t template_volids < <(get_lxc_templates)
    if [ ${#template_volids[@]} -eq 0 ]; then
        print_error "No LXC templates found. Please download some first."
        return 1
    fi
    
    # Create a clean list for the user to see
    local template_display_names=()
    for volid in "${template_volids[@]}"; do
        template_display_names+=("$(echo "$volid" | sed 's#.*/##')")
    done

    select template_display_name in "${template_display_names[@]}"; do
        if [[ -n "$template_display_name" ]]; then
            # Find the original volid corresponding to the selected display name
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

    # --- Select Storage for Root Filesystem ---
    print_header "Select Storage for Root Disk"
    mapfile -t storages < <(get_rootfs_storage | sort -u)
    if [ ${#storages[@]} -eq 0 ]; then
        print_error "No suitable storage for LXC root disks found."
        return 1
    fi
    echo "Choose where to store the container's disk:"
    select storage in "${storages[@]}"; do
        if [[ -n "$storage" ]]; then
            break
        else
            print_error "Invalid selection."
        fi
done

    # --- Gather Container Details ---
    print_header "Container Configuration"
    read -p "Enter Hostname: " hostname
    while true; do
        read -s -p "Enter root password: " password
        echo
        read -s -p "Confirm root password: " password2
        echo
        [ "$password" = "$password2" ] && break
        print_error "Passwords do not match. Please try again."
    done
    read -p "Tags (optional, comma-separated): " tags
    read -p "Description (optional): " description
    read -p "CPU Cores [Default: 1]: " cores
    cores=${cores:-1}
    read -p "RAM in MB [Default: 512]: " memory
    memory=${memory:-512}
    read -p "Swap in MB [Default: 512]: " swap
    swap=${swap:-512}
    read -p "Disk size in GB [Default: 8]: " disk_size
    disk_size=${disk_size:-8}
    rootfs="${storage}:${disk_size}"

    # --- Network Configuration ---
    print_header "Network Configuration"
    local bridge
    bridge=$(ip -br a | grep 'UP' | awk '{print $1}' | grep 'vmbr' | head -n 1)
    echo "Using network bridge: ${COLOR_GREEN}${bridge}${COLOR_NC}"
    read -p "Use DHCP or Static IP? (dhcp/static) [Default: dhcp]: " ip_type
    ip_type=${ip_type:-dhcp}
    if [ "$ip_type" = "static" ]; then
        read -p "Enter static IP with CIDR (e.g., 192.168.1.100/24): " static_ip
        read -p "Enter Gateway (e.g., 192.168.1.1): " gateway
        net0="name=eth0,bridge=${bridge},ip=${static_ip},gw=${gateway}"
    else
        net0="name=eth0,bridge=${bridge},ip=dhcp"
    fi

    # --- Final Options ---
    print_header "Final Options"
    read -p "Start container on boot? (yes/no) [Default: no]: " onboot_choice
    onboot=${onboot_choice:-no}
    onboot_val=$([ "$onboot_choice" = "yes" ] && echo "1" || echo "0")

    # --- Confirmation ---
    clear
    echo "===================================="
    echo "      Confirm Container Details"
    echo "===================================="
    echo -e "  ID:          ${COLOR_GREEN}${vmid}${COLOR_NC}"
    echo -e "  Hostname:    ${COLOR_GREEN}${hostname}${COLOR_NC}"
    echo -e "  Template:    ${COLOR_GREEN}${template_volid}${COLOR_NC}"
    echo -e "  Root Disk:   ${COLOR_GREEN}${rootfs}${COLOR_NC}"
    echo -e "  Cores:       ${COLOR_GREEN}${cores}${COLOR_NC}"
    echo -e "  Memory:      ${COLOR_GREEN}${memory}MB${COLOR_NC}"
    echo -e "  Swap:        ${COLOR_GREEN}${swap}MB${COLOR_NC}"
    echo -e "  Network:     ${COLOR_GREEN}${net0}${COLOR_NC}"
    echo -e "  Start on Boot: ${COLOR_GREEN}${onboot}${COLOR_NC}"
    [ -n "$tags" ] && echo -e "  Tags:        ${COLOR_GREEN}${tags}${COLOR_NC}"
    [ -n "$description" ] && echo -e "  Description: ${COLOR_GREEN}${description}${COLOR_NC}"
    echo "===================================="
    read -p "Proceed with creation? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Container creation aborted."
        exit 1
    fi

    # --- Create Container ---
    print_header "Creating LXC Container..."

    # Build the command in an array for robust argument handling
    local cmd_array=()
    cmd_array+=("$ESCALATION_TOOL" "pct" "create" "$vmid" "$template_volid")
    cmd_array+=("--rootfs" "$rootfs")
    cmd_array+=("--hostname" "$hostname")
    cmd_array+=("--password" "$password")
    cmd_array+=("--memory" "$memory")
    cmd_array+=("--swap" "$swap")
    cmd_array+=("--cores" "$cores")
    cmd_array+=("--net0" "$net0")
    cmd_array+=("--onboot" "$onboot_val")
    
    if [[ -n "$tags" ]]; then
        cmd_array+=("--tags" "$tags")
    fi
    if [[ -n "$description" ]]; then
        cmd_array+=("--description" "$description")
    fi

    echo "Running command:"
    # Print the command in a readable format
    echo -e "${COLOR_BLUE}${cmd_array[*]}${COLOR_NC}"
    
    # Execute the command
    if "${cmd_array[@]}"; then
        print_success "Container $vmid created successfully!"
    else
        print_error "Failed to create container $vmid."
    fi
}

main "$@"
