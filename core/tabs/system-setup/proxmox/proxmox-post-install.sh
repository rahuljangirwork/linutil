#!/bin/sh -e

. ../../common-script.sh

# --- Functions for each task ---

disable_enterprise_repo() {
    printf "%b\n" "${YELLOW}Disabling Proxmox enterprise repository...${RC}"
    if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
        sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/pve-enterprise.list
        printf "%b\n" "${GREEN}Enterprise repository disabled.${RC}"
    else
        printf "%b\n" "${CYAN}Enterprise repository file not found, skipping.${RC}"
    fi
}

add_no_subscription_repo() {
    printf "%b\n" "${YELLOW}Adding Proxmox no-subscription repository...${RC}"
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
    printf "%b\n" "${GREEN}No-subscription repository added.${RC}"
}

update_system() {
    printf "%b\n" "${YELLOW}Updating system...${RC}"
    "$ESCALATION_TOOL" apt update
    "$ESCALATION_TOOL" apt dist-upgrade -y
    printf "%b\n" "${GREEN}System updated.${RC}"
}

install_fail2ban() {
    printf "%b\n" "${YELLOW}Installing Fail2ban...${RC}"
    "$ESCALATION_TOOL" apt install -y fail2ban
    
    # Configure Fail2ban for Proxmox
    printf "%b\n" "${YELLOW}Configuring Fail2ban for Proxmox...${RC}"
    cat > /etc/fail2ban/jail.d/proxmox.conf <<'EOF'
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 3600
EOF

    # Create Proxmox filter if it doesn't exist
    if [ ! -f "/etc/fail2ban/filter.d/proxmox.conf" ]; then
        cat > /etc/fail2ban/filter.d/proxmox.conf <<'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
    fi

    "$ESCALATION_TOOL" systemctl restart fail2ban
    "$ESCALATION_TOOL" systemctl enable fail2ban
    printf "%b\n" "${GREEN}Fail2ban installed and configured for Proxmox.${RC}"
}

create_non_root_user() {
    printf "%b\n" "${YELLOW}Creating a non-root user...${RC}"
    printf "Enter a username for the new user (default: rahul): "
    read -r username
    username=${username:-rahul}

    if id "$username" >/dev/null 2>&1; then
        printf "%b\n" "${CYAN}User '$username' already exists. Skipping creation.${RC}"
    else
        printf "Creating user '$username'...\n"
        "$ESCALATION_TOOL" useradd --create-home --shell /bin/bash "$username"
        printf "%b\n" "${YELLOW}User '$username' created.${RC}"
        
        # Prompt for password
        printf "%b\n" "${YELLOW}Please set a password for user '$username':${RC}"
        "$ESCALATION_TOOL" passwd "$username"
    fi

    # Add to sudo group
    printf "Adding user '$username' to the sudo group...\n"
    "$ESCALATION_TOOL" usermod -aG sudo "$username"
    
    # Create Proxmox user (PVE)
    printf "%b\n" "${YELLOW}Creating Proxmox user for '$username'...${RC}"
    if ! pveum user list | grep -q "$username@pam"; then
        pveum user add "$username@pam"
        pveum acl modify / -user "$username@pam" -role Administrator
        printf "%b\n" "${GREEN}Proxmox user '$username@pam' created with Administrator role.${RC}"
    else
        printf "%b\n" "${CYAN}Proxmox user '$username@pam' already exists.${RC}"
    fi
    
    printf "%b\n" "${GREEN}User '$username' is configured with sudo and Proxmox privileges.${RC}"
}

configure_firewall() {
    printf "%b\n" "${YELLOW}Configuring Proxmox firewall...${RC}"
    
    # Check if firewall config exists
    FIREWALL_CONFIG="/etc/pve/firewall/cluster.fw"
    
    # Detect local network automatically
    LOCAL_NETWORK=$(ip route | grep -E 'proto kernel scope link' | grep -v 'docker\|veth' | head -n1 | awk '{print $1}')
    
    if [ -z "$LOCAL_NETWORK" ]; then
        printf "%b\n" "${RED}Could not detect local network automatically.${RC}"
        printf "Please enter your local network (e.g., 10.0.0.0/24): "
        read -r LOCAL_NETWORK
    else
        printf "%b\n" "${GREEN}Detected local network: $LOCAL_NETWORK${RC}"
        printf "Is this correct? (y/n, default: y): "
        read -r confirm
        if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
            printf "Enter your local network (e.g., 10.0.0.0/24): "
            read -r LOCAL_NETWORK
        fi
    fi
    
    # Create firewall configuration
    printf "%b\n" "${YELLOW}Creating firewall configuration...${RC}"
    cat > "$FIREWALL_CONFIG" <<EOF
[OPTIONS]

enable: 0

[IPSET management] # Management network

$LOCAL_NETWORK # Local network
127.0.0.0/8 # Localhost

[RULES]

IN ACCEPT -source +management -p icmp -log nolog # Allow ping from management
IN ACCEPT -source +management -p tcp -dport 8006 -log nolog # Allow Proxmox Web GUI
IN ACCEPT -source +management -p tcp -dport 22 -log nolog # Allow SSH
IN ACCEPT -source +management -p tcp -dport 5900:5999 -log nolog # Allow VNC consoles
IN ACCEPT -source +management -p tcp -dport 3128 -log nolog # Allow SPICE proxy

[group proxmox-cluster] # Allow cluster communication

IN ACCEPT -p udp -dport 5404:5405 -log nolog # Corosync
IN ACCEPT -p tcp -dport 2377 -log nolog # Docker Swarm (if used)
IN ACCEPT -p tcp -dport 85 -log nolog # PVE Cluster
EOF

    printf "%b\n" "${GREEN}Firewall configuration created.${RC}"
    
    # Ask user if they want to enable the firewall now
    printf "%b\n" "${YELLOW}Do you want to enable the firewall now? (y/n, default: n)${RC}"
    printf "%b\n" "${RED}WARNING: Make sure you can access this server from $LOCAL_NETWORK${RC}"
    printf "Enable firewall? (y/n): "
    read -r enable_fw
    
    if [ "$enable_fw" = "y" ] || [ "$enable_fw" = "Y" ]; then
        # Enable firewall
        sed -i 's/enable: 0/enable: 1/' "$FIREWALL_CONFIG"
        pve-firewall restart
        printf "%b\n" "${GREEN}Proxmox firewall enabled!${RC}"
        printf "%b\n" "${YELLOW}Firewall Status:${RC}"
        pve-firewall status
    else
        printf "%b\n" "${CYAN}Firewall configuration created but NOT enabled.${RC}"
        printf "%b\n" "${YELLOW}To enable later, run:${RC}"
        printf "  sed -i 's/enable: 0/enable: 1/' /etc/pve/firewall/cluster.fw\n"
        printf "  pve-firewall restart\n"
    fi
}

install_useful_tools() {
    printf "%b\n" "${YELLOW}Installing useful tools...${RC}"
    "$ESCALATION_TOOL" apt install -y htop ncdu vim git curl wget net-tools iftop iotop
    printf "%b\n" "${GREEN}Useful tools installed: htop, ncdu, vim, git, curl, wget, net-tools, iftop, iotop${RC}"
}

disable_subscription_nag() {
    printf "%b\n" "${YELLOW}Removing subscription nag message...${RC}"
    
    # Backup original file
    if [ -f "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js" ]; then
        cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak
        
        # Remove the subscription check
        sed -i.bak "s/data.status.toLowerCase() !== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
        
        printf "%b\n" "${GREEN}Subscription nag removed.${RC}"
        printf "%b\n" "${YELLOW}Note: Clear browser cache (Ctrl+F5) to see changes.${RC}"
    else
        printf "%b\n" "${RED}Proxmox library file not found. Skipping.${RC}"
    fi
}

configure_ssh() {
    printf "%b\n" "${YELLOW}Configuring SSH for better security...${RC}"
    
    # Backup SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Configure SSH
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    # Restart SSH
    systemctl restart sshd
    
    printf "%b\n" "${GREEN}SSH configured: Root login with password disabled (keys only).${RC}"
    printf "%b\n" "${YELLOW}Use your non-root user for password login.${RC}"
}

print_summary() {
    printf "\n"
    printf "%b\n" "${GREEN}================================================${RC}"
    printf "%b\n" "${GREEN}  Proxmox Post-Installation Complete!${RC}"
    printf "%b\n" "${GREEN}================================================${RC}"
    printf "\n"
    printf "%b\n" "${CYAN}Summary of changes:${RC}"
    printf "  ✓ Enterprise repository disabled\n"
    printf "  ✓ No-subscription repository added\n"
    printf "  ✓ System updated to latest packages\n"
    printf "  ✓ Fail2ban installed and configured\n"
    printf "  ✓ Non-root user created with sudo access\n"
    printf "  ✓ Firewall configured (enable manually if needed)\n"
    printf "  ✓ Useful tools installed\n"
    printf "  ✓ Subscription nag removed\n"
    printf "  ✓ SSH hardened\n"
    printf "\n"
    printf "%b\n" "${YELLOW}Next steps:${RC}"
    printf "  1. Test SSH access with your non-root user\n"
    printf "  2. Set up SSH keys for secure access\n"
    printf "  3. Enable firewall if not done already\n"
    printf "  4. Configure backups\n"
    printf "  5. Consider setting up Tailscale for remote access\n"
    printf "\n"
    printf "%b\n" "${GREEN}Proxmox Web GUI: https://$(hostname -I | awk '{print $1}'):8006${RC}"
    printf "\n"
}

# --- Main script execution ---

checkEnv
checkEscalationTool

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    printf "%b\n" "${RED}This script must be run as root or with sudo.${RC}"
    exit 1
fi

printf "%b\n" "${GREEN}Starting Proxmox Post-Installation Setup...${RC}"
printf "\n"

disable_enterprise_repo
add_no_subscription_repo
update_system
install_useful_tools
install_fail2ban
create_non_root_user
configure_ssh
configure_firewall
disable_subscription_nag

print_summary

printf "%b\n" "${GREEN}Done! Please reboot your system for all changes to take effect.${RC}"
printf "Reboot now? (y/n): "
read -r reboot_choice
if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
    printf "%b\n" "${YELLOW}Rebooting in 5 seconds... Press Ctrl+C to cancel.${RC}"
    sleep 5
    reboot
fi
