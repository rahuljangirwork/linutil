#!/bin/bash

# ==============================================================================
# WSL K3s Worker Node Setup
#
# This script sets up a WSL 2 instance as a K3s worker node.
# It installs dependencies (SSH, K3s agent) and configures a user with sudo.
# ==============================================================================

# --- Colors ---
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# --- Resources ---
print_header() {
    echo -e "\n${COLOR_YELLOW}=== $1 ===${COLOR_NC}"
}

print_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_NC}"
}

print_error() {
    echo -e "${COLOR_RED}❌ $1${COLOR_NC}"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root (or with sudo)."
        exit 1
    fi
}

main() {
    check_root
    clear
    print_header "WSL K3s Worker Node Setup"

    # --- 1. User Inputs ---
    echo "First, we need to configure the user for this WSL instance."
    echo "This user will have root (sudo) privileges."
    
    read -p "Enter Username: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty."
        exit 1
    fi

    echo "Enter Password:"
    read -s password
    echo
    if [ -z "$password" ]; then
        print_error "Password cannot be empty."
        exit 1
    fi

    # --- 2. K3s Inputs ---
    print_header "K3s Cluster Information"
    echo "Enter the connection details for your existing K3s Control Plane."
    
    read -p "Control Plane URL (e.g., https://192.168.1.100:6443): " k3s_url
    read -p "Cluster Token: " k3s_token
    
    if [ -z "$k3s_url" ] || [ -z "$k3s_token" ]; then
        print_error "K3s URL and Token are required."
        exit 1
    fi

    # --- 3. System Prep & Dependencies ---
    print_header "Installing Dependencies"
    
    # Detect Package Manager (Basic support)
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y curl wget openssh-server sudo
    elif command -v pacman &>/dev/null; then
        pacman -Syu --noconfirm curl wget openssh sudo
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget openssh-server sudo
    else
        print_error "Unsupported package manager. Please install curl, wget, openssh-server manually."
        exit 1
    fi

    # --- 4. User Configuration ---
    print_header "Configuring User: $username"
    
    if id "$username" &>/dev/null; then
        echo "User $username exists. Updating password..."
        echo "$username:$password" | chpasswd
    else
        echo "Creating user $username..."
        useradd -m -s /bin/bash "$username"
        echo "$username:$password" | chpasswd
    fi

    # Add to sudoers/wheel
    if getent group sudo &>/dev/null; then
        usermod -aG sudo "$username"
    elif getent group wheel &>/dev/null; then
        usermod -aG wheel "$username"
    fi
    print_success "User configured."

    # Set Default WSL User via /etc/wsl.conf
    # This ensures that next time WSL starts, it logs in as this user.
    if ! grep -q "default=$username" /etc/wsl.conf 2>/dev/null; then
        print_header "Setting default WSL user"
        echo -e "[user]\ndefault=$username" > /etc/wsl.conf
        print_success "Updated /etc/wsl.conf"
    fi

    # --- 5. SSH Configuration ---
    print_header "Setting up SSH"
    # Ensure keys exist
    ssh-keygen -A >/dev/null 2>&1
    
    # Enable service
    if command -v systemctl &>/dev/null; then
        systemctl enable --now ssh
    else
        service ssh start
    fi
    print_success "SSH Service configured."

    # --- 6. K3s Installation ---
    print_header "Installing K3s Agent (Worker)"
    
    # Install K3s Agent
    curl -sfL https://get.k3s.io | K3S_URL="$k3s_url" K3S_TOKEN="$k3s_token" sh -
    
    if [ $? -eq 0 ]; then
        print_success "K3s Agent successfully installed!"
        echo "This node should now be visible in your cluster."
    else
        print_error "K3s installation encountered an error."
        exit 1
    fi

    # --- 7. Final Notes ---
    print_header "Setup Complete"
    echo "To verify, run 'kubectl get nodes' on your control plane."
    echo "Note: If you just changed the default user in /etc/wsl.conf, you may need to restart WSL (wsl --shutdown) for it to take effect on login."
}

main "$@"
