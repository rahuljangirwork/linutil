#!/bin/bash

# ==============================================================================
# Create Tailscale Subnet Router
#
# A fully automatic script to create an LXC container configured as a
# Tailscale subnet router to advertise the local network.
# ==============================================================================

# --- Source common functions and set colors ---
source "$(dirname "$0")/proxmox-common.sh"

# --- Script Configuration ---
# Using the Debian 12 template the user previously selected.
# This can be changed if a different base template is desired.
TEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
STORAGE="VMS" # Using the storage the user previously selected.

VMID=100
HOSTNAME="tailscale-router"
DESCRIPTION="Tailscale subnet router advertising 10.0.0.0/24"
TAGS="tailscale,router,automatic"
CORES=1
MEMORY=512 # 512MB is a safe minimum for a router.
SWAP=256
DISK_SIZE=4 # 4GB is plenty for this purpose.
ROOTFS="${STORAGE}:${DISK_SIZE}"
ONBOOT=1 # Start at boot.

# Network Configuration
BRIDGE="vmbr0"
IP_ADDRESS="10.0.0.53/24"
GATEWAY="10.0.0.10"
SUBNET_TO_ADVERTISE="10.0.0.0/24"
NET0="name=eth0,bridge=${BRIDGE},ip=${IP_ADDRESS},gw=${GATEWAY}"

# --- Main Logic ---
main() {
    clear
    echo "===================================="
    echo "  Automatic Tailscale Subnet Router"
    echo "===================================="
    echo -e "This script will create a dedicated LXC container to act as a"
    echo -e "Tailscale subnet router for the ${COLOR_GREEN}${SUBNET_TO_ADVERTISE}${COLOR_NC} network."
    echo ""

    # --- Get Tailscale Auth Key (the only interactive step) ---
    print_header "Tailscale Authentication"
    echo -e "${COLOR_YELLOW}Please provide a Tailscale auth key. It should be an ephemeral, reusable key."
    echo -e "You can generate one at: https://login.tailscale.com/admin/settings/keys${COLOR_NC}"
    read -p "Enter Tailscale auth key: " TS_AUTHKEY
    if [[ -z "$TS_AUTHKEY" ]]; then
        print_error "A Tailscale auth key is required. Aborting."
        exit 1
    fi

    # --- Generate Random Password ---
    local PASSWORD
    PASSWORD=$(openssl rand -base64 12)
    if [[ -z "$PASSWORD" ]]; then
        print_error "Failed to generate a random password. Please ensure 'openssl' is installed."
        exit 1
    fi

    # --- Confirmation ---
    clear
    echo "===================================="
    echo "      Confirm Router Details"
    echo "===================================="
    echo -e "  ID:          ${COLOR_GREEN}${VMID}${COLOR_NC}"
    echo -e "  Hostname:    ${COLOR_GREEN}${HOSTNAME}${COLOR_NC}"
    echo -e "  Template:    ${COLOR_GREEN}${TEMPLATE}${COLOR_NC}"
    echo -e "  Root Disk:   ${COLOR_GREEN}${ROOTFS}${COLOR_NC}"
    echo -e "  Network:     ${COLOR_GREEN}${NET0}${COLOR_NC}"
    echo -e "  Subnet:      ${COLOR_GREEN}${SUBNET_TO_ADVERTISE}${COLOR_NC} (to be advertised)"
    echo -e "  Tags:        ${COLOR_GREEN}${TAGS}${COLOR_NC}"
    echo -e "  Password:    ${COLOR_YELLOW}(A random password will be generated and displayed on success)${COLOR_NC}"
    echo "===================================="
    read -p "Proceed with creation? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Router creation aborted."
        exit 1
    fi

    # --- Create Container ---
    print_header "1. Creating LXC Container (ID: ${VMID})..."
    local cmd_array=()
    cmd_array+=("pct" "create" "$VMID" "$TEMPLATE")
    cmd_array+=("--rootfs" "$ROOTFS")
    cmd_array+=("--hostname" "$HOSTNAME")
    cmd_array+=("--password" "$PASSWORD")
    cmd_array+=("--memory" "$MEMORY")
    cmd_array+=("--swap" "$SWAP")
    cmd_array+=("--cores" "$CORES")
    cmd_array+=("--net0" "$NET0")
    cmd_array+=("--onboot" "$ONBOOT")
    cmd_array+=("--tags" "$TAGS")
    cmd_array+=("--description" "$DESCRIPTION")

    if [[ "$ESCALATION_TOOL" != "eval" ]]; then
        cmd_array=("$ESCALATION_TOOL" "${cmd_array[@]}")
    fi

    if ! "${cmd_array[@]}"; then
        print_error "Failed to create container ${VMID}. Aborting."
        exit 1
    fi
    print_success "Container created."

    # --- Start Container ---
    print_header "2. Starting Container..."
    if ! "$ESCALATION_TOOL" pct start "$VMID"; then
        print_error "Failed to start container ${VMID}. Aborting."
        exit 1
    fi
    
    echo "Waiting 20 seconds for container to boot and get network..."
    sleep 20
    print_success "Container started."

    # --- Install Tailscale ---
    print_header "3. Installing Dependencies and Tailscale..."
    echo -e "${COLOR_YELLOW}Note: This will run 'apt update' and install 'curl' before running the Tailscale installer.${COLOR_NC}"
    local install_cmd="bash -c 'set -e; apt-get update && apt-get install -y curl && curl -fsSL https://tailscale.com/install.sh | sh'"
    if ! "$ESCALATION_TOOL" pct exec "$VMID" -- $install_cmd; then
        print_error "Failed to install Tailscale inside the container. Aborting."
        exit 1
    fi
    print_success "Tailscale installed."

    # --- Wait for Tailscaled to be ready ---
    print_header "4. Waiting for Tailscale daemon..."
    local wait_time=0
    local max_wait=30
    while [ $wait_time -lt $max_wait ]; do
        if "$ESCALATION_TOOL" pct exec "$VMID" -- test -S /var/run/tailscale/tailscaled.sock; then
            print_success "Tailscale daemon is ready."
            break
        fi
        sleep 2
        echo "Still waiting for tailscaled.sock... (${wait_time}s / ${max_wait}s)"
        wait_time=$((wait_time + 2))
    done

    if [ $wait_time -ge $max_wait ]; then
        print_error "Tailscale daemon did not start in time. Aborting."
        exit 1
    fi

    # --- Configure Tailscale ---
    print_header "5. Configuring Tailscale..."
    local tailscale_up_cmd="tailscale up --authkey=\"${TS_AUTHKEY}\" --advertise-routes=\"${SUBNET_TO_ADVERTISE}\" --accept-routes"
    if ! "$ESCALATION_TOOL" pct exec "$VMID" -- $tailscale_up_cmd; then
        print_error "Failed to run 'tailscale up'. You may need to log in manually."
        exit 1
    fi
    print_success "Tailscale is up and advertising routes."

    # --- Final Success Message ---
    clear
    echo "===================================="
    echo "      ✅ Success! ✅"
    echo "===================================="
    echo "Tailscale subnet router '${HOSTNAME}' (ID: ${VMID}) is created and configured."
    echo ""
    echo -e "The randomly generated root password for this container is:"
    echo -e "  ${COLOR_YELLOW}${PASSWORD}${COLOR_NC}"
    echo ""
    echo -e "${COLOR_RED}IMPORTANT:${COLOR_NC}"
    echo "1. Remember to disable key expiry on the auth key in your Tailscale admin panel."
    echo "2. Enable the advertised route in the 'Machines' section of the admin panel."
    echo "===================================="
}

main "$@"
