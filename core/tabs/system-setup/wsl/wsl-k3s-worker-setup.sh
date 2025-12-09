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
        if command -v sudo >/dev/null 2>&1; then
            print_header "Elevating Permissions"
            echo "This script requires root privileges. Prompting for sudo..."
            exec sudo bash "$0" "$@"
        else
            print_error "This script requires root privileges and sudo was not found."
            exit 1
        fi
    fi
}

main() {
    check_root
    clear
    print_header "WSL K3s Worker Node Setup"

    # --- 0. Systemd Pre-flight Check ---
    print_header "Checking System Requirements"
    if ! command -v systemctl &>/dev/null || ! systemctl list-units --type=target &>/dev/null; then
        print_error "Systemd is NOT enabled or running."
        echo "K3s and Tailscale require systemd to function correctly."
        echo ""
        echo "To enable systemd in WSL2:"
        echo "1. Run the following command in this terminal:"
        echo "   echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf"
        echo "2. Exit this terminal."
        echo "3. Run 'wsl --shutdown' from PowerShell."
        echo "4. Restart this WSL instance and re-run this script."
        echo ""
        exit 1
    else
        print_success "Systemd is running."
    fi

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

    # --- 2. Tailscale Configuration ---
    print_header "Tailscale Configuration"
    read -p "Enter Tailscale Auth Key (tskey-auth-...): " ts_key
    read -p "Enter Hostname (for OS and Tailscale): " hostname
    read -p "Enter Tailscale Tag (optional, e.g. k3s-worker): " ts_tag

    # --- 3. K3s Inputs ---
    print_header "K3s Cluster Information"
    echo "Enter the connection details for your existing K3s Control Plane."
    
    read -p "Control Plane URL (e.g., https://192.168.1.100:6443): " k3s_url
    read -p "Cluster Token: " k3s_token
    
    if [ -z "$k3s_url" ] || [ -z "$k3s_token" ]; then
        print_error "K3s URL and Token are required."
        exit 1
    fi

    # --- 4. System Prep & Dependencies ---
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
    
    # Set hostname if provided
    if [ -n "$hostname" ]; then
        if ! grep -q "hostname=$hostname" /etc/wsl.conf 2>/dev/null; then
             echo -e "[network]\nhostname=$hostname" >> /etc/wsl.conf
             hostnamectl set-hostname "$hostname" 2>/dev/null || echo "Could not set hostname immediately, requires restart."
        fi
    fi

    # --- 5. Tailscale Installation & Setup ---
    print_header "Installing Tailscale"
    curl -fsSL https://tailscale.com/install.sh | sh
    
    print_header "Authenticating Tailscale"
    if tailscale status >/dev/null 2>&1; then
        echo "Tailscale is already up and running."
    elif [ -n "$ts_key" ]; then
        extra_args=""
        if [ -n "$ts_tag" ]; then
            extra_args="--advertise-tags=tag:${ts_tag}"
        fi
        if [ -n "$hostname" ]; then
            extra_args="$extra_args --hostname=${hostname}"
        fi
        
        tailscale up --authkey="$ts_key" --ssh $extra_args
    else
        echo "No auth key provided and Tailscale is not running. Please run 'tailscale up' manually."
    fi

    # Get Tailscale IP
    TS_IP=$(tailscale ip -4 2>/dev/null)
    if [ -n "$TS_IP" ]; then
        print_success "Tailscale IP: $TS_IP"
    else
        print_error "Could not retrieve Tailscale IP. Is Tailscale running?"
    fi

    # --- 6. SSH Configuration ---
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

    # --- 7. Fix Mount Propagation (WSL2 Issue) ---
    print_header "Applying WSL2 Mount Fix"
    # K3s/Node Exporter needs shared mount propagation for / to access host filesystem
    # We create a systemd service to ensure this persists across restarts.
    
    cat <<EOF > /etc/systemd/system/wsl-mount-fix.service
[Unit]
Description=Make root mount shared for K3s (WSL2 Fix)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --make-rshared /

[Install]
WantedBy=multi-user.target
EOF

    if command -v systemctl &>/dev/null; then
        systemctl daemon-reload
        systemctl enable --now wsl-mount-fix.service
        print_success "Mount propagation fix applied."
    else
        mount --make-rshared /
        print_success "Mount propagation fix applied (Manual). Note: Persistence requires systemd."
    fi

    # --- 8. K3s Installation ---
    print_header "Installing K3s Agent (Worker)"
    
    # Install K3s Agent
    # We use FLANNEL_IFACE=tailscale0 to ensure K3s uses the Tailscale interface
    # We add labels to identify this as a WSL node
    # Install K3s Agent
    # We use FLANNEL_IFACE=tailscale0 to ensure K3s uses the Tailscale interface
    # We add labels to identify this as a WSL node
    
    if systemctl is-active --quiet k3s-agent; then
        print_success "K3s Agent is already running."
        echo "Restarting service to apply any new configurations..."
        systemctl restart k3s-agent
    else
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --flannel-iface=tailscale0 --node-label kubernetes.io/os=linux-wsl --node-label env=wsl2" K3S_URL="$k3s_url" K3S_TOKEN="$k3s_token" sh -
    fi
    
    if [ $? -eq 0 ]; then
        print_success "K3s Agent successfully installed!"
        echo "This node should now be visible in your cluster."
    else
        print_error "K3s installation encountered an error."
        exit 1
    fi

    # --- 9. Final Notes ---
    print_header "Setup Complete"
    echo "To verify, run 'kubectl get nodes' on your control plane."
    echo "Note: If you just changed the default user in /etc/wsl.conf, you may need to restart WSL (wsl --shutdown) for it to take effect on login."
}

main "$@"
