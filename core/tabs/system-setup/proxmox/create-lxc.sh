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
    local storages_with_vztmpl=()
    local all_storages
    # Get all active storage names from pvesm
    mapfile -t all_storages < <(pvesm status | tail -n +2 | awk '{print $1}')

    # For each storage, robustly check its content type from the config file
    for storage in "${all_storages[@]}"; do
        # Use awk to extract the entire block for the given storage
        local storage_block
        storage_block=$(awk -v s="$storage" '/^[a-z]+: *s$/{p=1} p&&/^[a-z]+:/{p=0} p' /etc/pve/storage.cfg)

        # Check if the extracted block has the 'vztmpl' content type
        if echo "$storage_block" | grep -q 'content .*vztmpl'; then
            storages_with_vztmpl+=("$storage")
        fi
    done

    if [ ${#storages_with_vztmpl[@]} -eq 0 ]; then return; fi

    for storage in "${storages_with_vztmpl[@]}"; do
        # For each valid storage, list templates and return the full VolID
        pveam list "$storage" | tail -n +2 | awk '{print $1}'
    done
}

get_rootfs_storage() {
    local storages_with_rootfs=()
    local all_storages
    # Get all active storage names from pvesm
    mapfile -t all_storages < <(pvesm status | tail -n +2 | awk '{print $1}')

    # For each storage, robustly check its content type from the config file
    for storage in "${all_storages[@]}"; do
        # Use awk to extract the entire block for the given storage
        local storage_block
        storage_block=$(awk -v s="$storage" '/^[a-z]+: *s$/{p=1} p&&/^[a-z]+:/{p=0} p' /etc/pve/storage.cfg)

        # Check if the extracted block has 'rootdir' or 'images'
        if echo "$storage_block" | grep -q -E 'content .*(rootdir|images)'; then
            storages_with_rootfs+=("$storage")
        fi
    done
    
    # Print the unique list of found storages
    printf "%s\n" "${storages_with_rootfs[@]}"
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
    local cmd="sudo pct create $vmid \"$template_volid\" --rootfs \"$rootfs\" --hostname \"$hostname\" --password \"$password\" --memory $memory --swap $swap --cores $cores --net0 \"$net0\" --onboot $onboot_val"
    [ -n "$tags" ] && cmd+=" --tags \"$tags\""
    [ -n "$description" ] && cmd+=" --description \"$description\""

    echo "Running command:"
    echo -e "${COLOR_BLUE}$cmd${COLOR_NC}"
    
    # Execute the command
    if eval "$cmd"; then
        print_success "Container $vmid created successfully!"
    else
        print_error "Failed to create container $vmid."
    fi
}

main "$@"
