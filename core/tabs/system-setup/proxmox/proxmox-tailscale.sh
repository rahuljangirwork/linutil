#!/bin/sh -e

. ../../common-script.sh

# --- Configuration ---
LXC_HOSTNAME="tailscale-router"
TEMPLATE_STORAGE="local"
TEMPLATE_NAME="debian-12-standard"
LXC_STORAGE="local-lvm"
LXC_BRIDGE="vmbr0"
LXC_CORES=1
LXC_MEMORY=512
LXC_DISK_SIZE=4

# --- Helper Functions ---

# Find the VMID of the Tailscale LXC
get_lxc_vmid() {
    # Query PVE API for containers, filter by hostname, and get the vmid
    pvesh get /cluster/resources --output-format json | jq -r ".[] | select(.type == \"lxc\" and .name == \"$LXC_HOSTNAME\") | .vmid"
}

# --- Menu Functions ---

show_menu() {
    printf "\n"
    printf "%b%s%b\n" "${YELLOW}--- Proxmox Tailscale LXC Manager ---${RC}"
    printf "%b 1 %b- Setup Tailscale Subnet Router LXC\n" "${GREEN}" "${RC}"
    printf "%b 2 %b- Destroy Tailscale LXC\n" "${GREEN}" "${RC}"
    printf "%b 3 %b- View Tailscale Logs\n" "${GREEN}" "${RC}"
    printf "%b 4 %b- Enter Tailscale LXC Shell\n" "${GREEN}" "${RC}"
    printf "%b 5 %b- Check Tailscale Status\n" "${GREEN}" "${RC}"
    printf "%b q %b- Quit\n" "${GREEN}" "${RC}"
    printf "%b%s%b" "${YELLOW}Choose an option: ${RC}"
}

setup_lxc() {
    printf "%b\n" "${YELLOW}Starting Tailscale LXC setup...${RC}"

    # Check if LXC already exists
    if [ -n "$(get_lxc_vmid)" ]; then
        printf "%b\n" "${RED}A Tailscale LXC with hostname '$LXC_HOSTNAME' already exists. Aborting.${RC}"
        return
    fi

    # 1. Check for Debian 12 template
    printf "%b\n" "${CYAN}Checking for Debian 12 template...${RC}"
    TEMPLATE_FILENAME=$(pveam available --section system | grep "$TEMPLATE_NAME" | awk '{print $2}')
    if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE_FILENAME"; then
        printf "%b\n" "${YELLOW}Template not found. Downloading...${RC}"
        if [ -z "$TEMPLATE_FILENAME" ]; then
            printf "%b\n" "${RED}Could not find a Debian 12 template. Please update your template list with 'pveam update'.${RC}"
            return
        fi
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILENAME"
        printf "%b\n" "${GREEN}Template downloaded successfully.${RC}"
    else
        printf "%b\n" "${GREEN}Debian 12 template found.${RC}"
    fi

    # 2. Get next available VMID
    VMID=$(pvesh get /cluster/nextid)
    printf "%b\n" "${CYAN}Creating LXC with ID $VMID...${RC}"

    # 3. Create the LXC
    pct create "$VMID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE_FILENAME" \
        --hostname "$LXC_HOSTNAME" \
        --storage "$LXC_STORAGE" \
        --cores "$LXC_CORES" \
        --memory "$LXC_MEMORY" \
        --swap 0 \
        --net0 name=eth0,bridge="$LXC_BRIDGE",ip=dhcp \
        --nameserver 8.8.8.8 \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --onboot 1 \
        --start 1

    printf "%b\n" "${GREEN}LXC created and started. Waiting for network...${RC}"
    sleep 15 # Give LXC time to get an IP

    # 4. Install Tailscale
    printf "%b\n" "${CYAN}Installing Tailscale inside the LXC...${RC}"
    pct exec "$VMID" -- apt update
    pct exec "$VMID" -- apt install -y curl
    pct exec "$VMID" -- sh -c "curl -fsSL https://tailscale.com/install.sh | sh"
    printf "%b\n" "${GREEN}Tailscale installed.${RC}"

    # 5. Configure Tailscale to advertise routes
    printf "%b\n" "${CYAN}Configuring Tailscale subnet router...${RC}"
    # Get all local, non-virtual subnets
    SUBNETS=$(ip -4 route show | awk '/src/ {print $1}' | paste -s -d, -)
    if [ -z "$SUBNETS" ]; then
        printf "%b\n" "${RED}Could not automatically determine local subnets.${RC}"
        return
    fi
    printf "%b\n" "${YELLOW}Will advertise the following subnets: $SUBNETS${RC}"

    # Instruct user to run tailscale up
    printf "%b\n" "${YELLOW}--- IMPORTANT ---${RC}"
    printf "%b\n" "Run the following command inside the LXC to bring Tailscale up."
    printf "%b\n" "You will be given a URL to authenticate in your browser."
    printf "%b\n" "After authenticating, remember to disable key expiry and approve the advertised routes in the Tailscale admin console."
    printf "\n"
    printf "%b tailscale up --advertise-routes=$SUBNETS --accept-routes %b\n" "${CYAN}" "${RC}"
    printf "\n"
    printf "%b\n" "You can enter the LXC shell now to run the command, or use option 4 from the main menu later."
}

destroy_lxc() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        printf "%b\n" "${RED}No Tailscale LXC found to destroy.${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}This will permanently destroy the Tailscale LXC (ID: $VMID).${RC}"
    printf "Are you sure you want to continue? (y/N): "
    read -r confirmation
    if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
        printf "%b\n" "${CYAN}Destruction aborted.${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Stopping and destroying LXC $VMID...${RC}"
    pct stop "$VMID" || true # Ignore error if already stopped
    pct destroy "$VMID"
    printf "%b\n" "${GREEN}Tailscale LXC destroyed.${RC}"
}

view_logs() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        printf "%b\n" "${RED}No Tailscale LXC found.${RC}"
        return
    fi
    printf "%b\n" "${CYAN}Showing logs for LXC $VMID. Press Ctrl+C to exit.${RC}"
    pct exec "$VMID" -- journalctl -u tailscaled -f
}

enter_lxc() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        printf "%b\n" "${RED}No Tailscale LXC found.${RC}"
        return
    fi
    printf "%b\n" "${CYAN}Entering shell for LXC $VMID. Type 'exit' or press Ctrl+D to leave.${RC}"
    pct enter "$VMID"
}

check_status() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        printf "%b\n" "${RED}No Tailscale LXC found.${RC}"
        return
    fi
    printf "%b\n" "${CYAN}Getting Tailscale status for LXC $VMID...${RC}"
    pct exec "$VMID" -- tailscale status
}


# --- Main Loop ---

checkEnv
checkEscalationTool

# Check for dependencies
if ! command_exists jq || ! command_exists pvesh || ! command_exists pveam || ! command_exists pct; then
    printf "%b\n" "${RED}This script requires jq, pvesh, pveam, and pct to be installed and in your PATH.${RC}"
    printf "%b\n" "${RED}Please ensure you are running this on a Proxmox host.${RC}"
    exit 1
fi

while true; do
    show_menu
    read -r choice

    case "$choice" in
        1)
            setup_lxc
            ;; 
        2)
            destroy_lxc
            ;; 
        3)
            view_logs
            ;; 
        4)
            enter_lxc
            ;; 
        5)
            check_status
            ;; 
        q|Q)
            printf "%b\n" "${GREEN}Exiting.${RC}"
            exit 0
            ;; 
        *)
            printf "%b\n" "${RED}Invalid option, please try again.${RC}"
            ;; 
    esac
done
