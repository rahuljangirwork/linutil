#!/bin/bash

# ==============================================================================
# WSL K3s Worker Cleanup
#
# This script removes the K3s agent and cleans up configurations applied by
# the wsl-k3s-worker-setup.sh script.
# ==============================================================================

# --- Colors ---
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# --- Helpers ---
print_header() { echo -e "\n${COLOR_YELLOW}=== $1 ===${COLOR_NC}"; }
print_success() { echo -e "${COLOR_GREEN}✅ $1${COLOR_NC}"; }
print_error() { echo -e "${COLOR_RED}❌ $1${COLOR_NC}"; }

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
    print_header "WSL K3s Cleanup/Uninstall"

    echo "This script will:"
    echo "1. Uninstall K3s Agent"
    echo "2. Remove the WSL mount propagation fix service"
    echo "3. (Optional) Logout of Tailscale"
    echo ""
    read -p "Are you sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    # --- 1. Uninstall K3s ---
    print_header "Uninstalling K3s Agent"
    if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
        /usr/local/bin/k3s-agent-uninstall.sh
        print_success "K3s Agent uninstalled."
    else
        echo "K3s Agent uninstall script not found. Is K3s installed?"
    fi

    # --- 1a. Force Cleanup of Stubborn Mounts ---
    # WSL often holds onto mounts in /var/lib/kubelet (e.g. pods), causing "Device or resource busy"
    
    cleanup_mounts() {
        local target_dir=$1
        if [ -d "$target_dir" ]; then
             echo "Checking for leftovers in $target_dir..."
             # Find all mounts under this dir and lazy unmount them
             mount | grep "$target_dir" | awk '{print $3}' | sort -r | while read -r mountpoint; do
                 echo "Force unmounting $mountpoint..."
                 umount -l "$mountpoint" 2>/dev/null || true
             done
             
             # Try removing again
             rm -rf "$target_dir" 2>/dev/null || echo "Warning: Could not fully remove $target_dir"
        fi
    }

    cleanup_mounts "/var/lib/kubelet"
    cleanup_mounts "/var/lib/rancher/k3s"
    cleanup_mounts "/run/k3s"

    # --- 2. Remove Mount Fix Service ---
    print_header "Removing WSL Mount Fix Service"
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet wsl-mount-fix.service; then
            systemctl stop wsl-mount-fix.service
        fi
        if systemctl is-enabled --quiet wsl-mount-fix.service; then
            systemctl disable wsl-mount-fix.service
        fi
    fi
    
    if [ -f /etc/systemd/system/wsl-mount-fix.service ]; then
        rm /etc/systemd/system/wsl-mount-fix.service
        if command -v systemctl &>/dev/null; then
            systemctl daemon-reload
        fi
        print_success "Removed wsl-mount-fix.service"
    else
        echo "wsl-mount-fix.service not found."
    fi

    # --- 3. Tailscale Cleanup ---
    print_header "Tailscale Cleanup"
    read -p "Do you want to logout of Tailscale? (y/n): " ts_logout
    if [[ "$ts_logout" == "y" ]]; then
        if command -v tailscale &>/dev/null; then
            tailscale logout
            print_success "Tailscale logged out."
        else
            print_error "Tailscale command not found."
        fi
    fi

    print_header "Cleanup Complete"
    echo "Note: Dependencies installed (curl, openssh-server, etc.) were NOT removed."
    echo "User accounts created were NOT removed."
}

main "$@"
