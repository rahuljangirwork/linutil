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
    printf "%b\n" "${GREEN}Fail2ban installed.${RC}"
}

create_non_root_user() {
    printf "%b\n" "${YELLOW}Creating a non-root user...${RC}"
    printf "Enter a username for the new user (default: rahul): "
    read -r username
    username=${username:-rahul} # Set default value if input is empty

    if id "$username" >/dev/null 2>&1; then
        printf "%b\n" "${CYAN}User '$username' already exists. Skipping creation.${RC}"
    else
        printf "Creating user '$username'...\n"
        "$ESCALATION_TOOL" adduser --disabled-password --gecos "" "$username"
        printf "%b\n" "${YELLOW}User '$username' created without a password.${RC}"
        printf "%b\n" "${YELLOW}Please set a password for this user by running 'passwd $username' in the terminal.${RC}"
    fi

    printf "Adding user '$username' to the sudo group...\n"
    "$ESCALATION_TOOL" usermod -aG sudo "$username"
    printf "%b\n" "${GREEN}User '$username' is configured with sudo privileges.${RC}"
}

enable_firewall() {
    printf "%b\n" "${YELLOW}Enabling Proxmox firewall...${RC}"
    if command_exists pveum; then
        "$ESCALATION_TOOL" pveum datacenter modify --firewall 1
        printf "%b\n" "${GREEN}Proxmox firewall enabled at the Datacenter level.${RC}"
        printf "%b\n" "${YELLOW}WARNING: Ensure you have configured firewall rules before enabling it on VMs or hosts to avoid losing access.${RC}"
    else
        printf "%b\n" "${RED}pveum command not found. Cannot enable firewall.${RC}"
    fi
}

remove_subscription_popup() {
    printf "%b\n" "${YELLOW}Removing 'No valid subscription' popup...${RC}"
    if [ -f "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js" ]; then
        "$ESCALATION_TOOL" sed -Ezi.bak "s/(Ext.Msg.show(\{\s+title: gettext('No valid sub)/void(\{\s\/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
        "$ESCALATION_TOOL" systemctl restart pveproxy.service
        printf "%b\n" "${GREEN}Subscription popup removed.${RC}"
    else
        printf "%b\n" "${RED}Could not find proxmoxlib.js, skipping.${RC}"
    fi
}

install_useful_tools() {
    printf "%b\n" "${YELLOW}Installing useful tools (htop, ncdu, vim, git)...${RC}"
    "$ESCALATION_TOOL" apt install -y htop ncdu vim git
    printf "%b\n" "${GREEN}Useful tools installed.${RC}"
}


# --- Main script execution ---

checkEnv
checkEscalationTool

disable_enterprise_repo
add_no_subscription_repo
update_system
install_fail2ban
create_non_root_user
enable_firewall
remove_subscription_popup
install_useful_tools

printf "%b\n" "${GREEN}Proxmox post-installation script finished!${RC}"
