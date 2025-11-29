#!/bin/sh -e

# Source common functions and variables
. ../../common-script.sh

# --- Helper Functions (as a fallback if not in common-script.sh) ---
if ! command -v print_status >/dev/null; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_status() { echo -e "\n${CYAN}[INFO] $1${NC}"; }
    print_error() { echo -e "\n${RED}[ERROR] $1${NC}"; exit 1; }
    print_warning() { echo -e "\n${YELLOW}[WARNING] $1${NC}"; }
    success() { echo -e "\n${GREEN}[SUCCESS] $1${NC}"; }
fi

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
    pvesh get /cluster/resources --output-format json | jq -r ".[] | select(.type == \"lxc\" and .name == \"$LXC_HOSTNAME\") | .vmid"
}

# --- Menu Functions ---

show_menu() {
    printf "\n"
    printf "%b\n" "${YELLOW}--- Fully Automatic Proxmox Tailscale LXC Manager ---${NC}"
    printf "%b 1 %b- Setup Tailscale Subnet Router LXC\n" "${GREEN}" "${NC}"
    printf "%b 2 %b- Destroy Tailscale LXC\n" "${RED}" "${NC}"
    printf "%b 3 %b- View Tailscale Logs\n" "${GREEN}" "${NC}"
    printf "%b 4 %b- Enter Tailscale LXC Shell\n" "${GREEN}" "${NC}"
    printf "%b 5 %b- Check Tailscale Status\n" "${GREEN}" "${NC}"
    printf "%b q %b- Quit\n" "${GREEN}" "${NC}"
    printf "%b" "${YELLOW}Choose an option: ${NC} "
}

setup_lxc() {
    print_status "Starting Fully Automatic Tailscale LXC setup..."

    # Step 0: Check if LXC already exists
    if [ -n "$(get_lxc_vmid)" ]; then
        print_warning "A Tailscale LXC with hostname '$LXC_HOSTNAME' already exists. Aborting."
        return
    fi

    # Step 1: Get Tailscale Auth Key from user
    print_warning "A Tailscale Auth Key is required for automatic setup."
    printf "You can generate one at: https://login.tailscale.com/admin/settings/keys\n"
    printf "Make sure the key is NOT ephemeral and is reusable if you plan to run this script multiple times.\n"
    printf "Enter your Tailscale Auth Key: "
    read -r AUTH_KEY
    if [ -z "$AUTH_KEY" ]; then
        print_error "Auth Key cannot be empty. Aborting."
    fi

    # Step 2: Choose network type
    print_status "[1/9] Configuring Network..."
    printf "Choose network type:\n"
    printf "  1) DHCP (automatic, recommended)\n"
    printf "  2) Static IP\n"
    printf "Your choice: "
    read -r net_choice

    NET_OPTS=""
    case "$net_choice" in
        1)
            print_status "Using DHCP."
            NET_OPTS="ip=dhcp"
            ;;
        2)
            print_status "Using Static IP."
            printf "Enter Static IP address (e.g., 192.168.1.50/24): "
            read -r STATIC_IP
            if [ -z "$STATIC_IP" ]; then print_error "Static IP cannot be empty."; fi
            
            printf "Enter Gateway IP address (e.g., 192.168.1.1): "
            read -r GATEWAY_IP
            if [ -z "$GATEWAY_IP" ]; then print_error "Gateway IP cannot be empty."; fi

            NET_OPTS="ip=${STATIC_IP},gw=${GATEWAY_IP}"
            ;;
        *)
            print_error "Invalid choice. Aborting."
            ;;
    esac

    # Step 3: Check for Debian 12 template
    print_status "[2/9] Checking for Debian 12 template..."
    
    # Get the exact template filename
    TEMPLATE_FILENAME=$(pveam list "$TEMPLATE_STORAGE" | grep "$TEMPLATE_NAME" | grep "amd64.tar.zst" | sort -V | tail -1 | awk '{print $1}' | sed "s|${TEMPLATE_STORAGE}:vztmpl/||")
    
    if [ -z "$TEMPLATE_FILENAME" ]; then
        print_warning "Template not found locally. Checking available templates..."
        TEMPLATE_FILENAME=$(pveam available --section system | grep "$TEMPLATE_NAME" | grep "amd64.tar.zst" | sort -V | tail -1 | awk '{print $2}')
        
        if [ -z "$TEMPLATE_FILENAME" ]; then
            print_error "Could not find a Debian 12 template. Please update your template list with 'pveam update'."
        fi
        
        print_warning "Downloading template: $TEMPLATE_FILENAME"
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILENAME"
        success "Template downloaded."
    else
        success "Debian 12 template found: $TEMPLATE_FILENAME"
    fi

    # Step 4: Get Host's DNS servers
    print_status "[3/9] Detecting host's DNS servers..."
    HOST_DNS_SERVERS=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}')
    if [ -z "$HOST_DNS_SERVERS" ]; then
        print_warning "Could not detect host DNS servers. Falling back to 8.8.8.8."
        HOST_DNS_SERVERS="8.8.8.8"
    else
        success "Found DNS servers: $HOST_DNS_SERVERS"
    fi
    DNS_OPTS=""
    for ns in $HOST_DNS_SERVERS; do
        DNS_OPTS="$DNS_OPTS --nameserver $ns"
    done

    # Step 5: Create the LXC (but don't start it yet)
    VMID=$(pvesh get /cluster/nextid)
    print_status "[4/9] Creating LXC with ID $VMID..."
    pct create "$VMID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE_FILENAME" \
        --hostname "$LXC_HOSTNAME" \
        --storage "$LXC_STORAGE" \
        --cores "$LXC_CORES" \
        --memory "$LXC_MEMORY" \
        --swap 0 \
        --net0 name=eth0,bridge="$LXC_BRIDGE",${NET_OPTS} \
        $DNS_OPTS \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --onboot 1 \
        --start 0 # Don't start yet

    success "LXC created. Now configuring for Tailscale."

    # Step 6: Apply LXC Configuration for TUN device
    print_status "[5/9] Applying LXC Configuration for TUN device..."
    CONF_FILE="/etc/pve/lxc/${VMID}.conf"
    {
        echo ""
        echo "# Added for Tailscale"
        echo "lxc.cgroup2.devices.allow: c 10:200 rwm"
        echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
    } >> "$CONF_FILE"
    success "TUN device configured."

    # Step 7: Start container and wait for network (IMPROVED)
    print_status "[6/9] Starting LXC and waiting for network..."
    pct start "$VMID"
    
    # Give container time to fully boot
    print_status "Waiting 15 seconds for container to initialize..."
    sleep 15
    
    ATTEMPTS=0
    MAX_ATTEMPTS=20 # 20 attempts x 5 seconds = 100 seconds max wait
    IP=""
    
    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        # Try to get IP using hostname -I (more reliable)
        IP=$(pct exec "$VMID" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
        
        # Check if we got a valid IP (not empty and not localhost)
        if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
            print_status "Container has IP: $IP. Verifying internet connectivity..."
            
            # First test gateway (faster)
            if pct exec "$VMID" -- ping -c 1 -W 3 10.0.0.10 >/dev/null 2>&1; then
                # Gateway works, now test internet
                if pct exec "$VMID" -- ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
                    success "Network is up!"
                    break
                else
                    print_warning "Gateway reachable but internet failed. Retrying..."
                fi
            else
                print_warning "Container has IP but gateway unreachable. Waiting..."
            fi
        fi
        
        ATTEMPTS=$((ATTEMPTS + 1))
        printf "${CYAN}Waiting for network... (Attempt $ATTEMPTS/$MAX_ATTEMPTS)${NC}\n"
        sleep 5 # Wait 5 seconds between attempts
    done

    if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
        if [ "$net_choice" = "1" ]; then
            print_error "Network connectivity failed. The container did not get proper internet access via DHCP. Please check your network/firewall or try again with a static IP."
        else
            print_error "Network connectivity failed. The container has an IP but could not reach the internet. Please check your gateway and firewall settings."
        fi
    fi

    # Step 8: Install and Configure Tailscale
    print_status "[7/9] Installing Tailscale inside the LXC..."
    pct exec "$VMID" -- apt-get update -qq
    pct exec "$VMID" -- apt-get install -y curl
    pct exec "$VMID" -- sh -c "curl -fsSL https://tailscale.com/install.sh | sh"
    success "Tailscale installed."

    print_status "[8/9] Configuring Tailscale as a subnet router..."
    # Get local subnets (exclude docker networks)
    SUBNETS=$(ip -4 route show | grep 'proto kernel' | grep -v 'docker' | awk '{print $1}' | grep -v '^default' | paste -s -d, -)
    
    if [ -z "$SUBNETS" ]; then
        # Fallback to your known network
        SUBNETS="10.0.0.0/24"
        print_warning "Could not auto-detect subnets. Using default: $SUBNETS"
    fi
    print_status "Will advertise the following subnets: $SUBNETS"

    pct exec "$VMID" -- tailscale up \
        --authkey="$AUTH_KEY" \
        --advertise-routes="$SUBNETS" \
        --accept-routes \
        --hostname="$LXC_HOSTNAME"
    
    success "Tailscale is up and configured."

    # Step 9: Final Status
    print_status "[9/9] Finalizing Setup..."
    TAILSCALE_IP=$(pct exec "$VMID" -- tailscale ip -4 2>/dev/null || echo "N/A")
    
    # If DHCP was used, IP is already set. If static, parse it.
    if [ -z "$IP" ]; then
        IP=$(echo "$STATIC_IP" | cut -d/ -f1)
    fi
    
    success "Setup complete! Your Tailscale Subnet Router is running."
    echo ""
    echo "========================================"
    echo "LXC VMID: $VMID"
    echo "Hostname: $LXC_HOSTNAME"
    echo "Container IP: $IP"
    echo "Tailscale IP: $TAILSCALE_IP"
    echo "Advertised Routes: $SUBNETS"
    echo "========================================"
    echo ""
    print_warning "IMPORTANT: Remember to approve the advertised routes in the Tailscale admin console!"
    printf "\n${CYAN}Visit: https://login.tailscale.com/admin/machines${NC}\n"
    printf "${CYAN}Find your device '$LXC_HOSTNAME' and approve the subnet routes.${NC}\n\n"
}

destroy_lxc() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        print_warning "No Tailscale LXC found to destroy."
        return
    fi

    print_warning "This will permanently destroy the Tailscale LXC (ID: $VMID)."
    printf "Are you sure you want to continue? (y/N): "
    read -r confirmation
    if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
        print_status "Destruction aborted."
        return
    fi

    print_status "Stopping and destroying LXC $VMID..."
    pct stop "$VMID" >/dev/null 2>&1 || true # Ignore error if already stopped
    pct destroy "$VMID"
    success "Tailscale LXC destroyed."
}

view_logs() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        print_warning "No Tailscale LXC found."
        return
    fi
    print_status "Showing logs for LXC $VMID. Press Ctrl+C to exit."
    pct exec "$VMID" -- journalctl -u tailscaled -f
}

enter_lxc() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        print_warning "No Tailscale LXC found."
        return
    fi
    print_status "Entering shell for LXC $VMID. Type 'exit' or press Ctrl+D to leave."
    pct enter "$VMID"
}

check_status() {
    VMID=$(get_lxc_vmid)
    if [ -z "$VMID" ]; then
        print_warning "No Tailscale LXC found."
        return
    fi
    print_status "Getting Tailscale status for LXC $VMID..."
    pct exec "$VMID" -- tailscale status
}

# --- Main Loop ---

# Check for dependencies
if ! command -v jq >/dev/null || ! command -v pvesh >/dev/null || ! command -v pveam >/dev/null || ! command -v pct >/dev/null; then
    print_error "This script requires jq, pvesh, pveam, and pct to be installed and in your PATH.\nPlease ensure you are running this on a Proxmox host."
fi

# A simple root check is more portable than sourced functions.
if [ "$(id -u)" -ne 0 ]; then
  print_error "This script must be run as root."
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
            printf "%b\n" "${GREEN}Exiting.${NC}"
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}Invalid option, please try again.${NC}"
            ;;
    esac
done
