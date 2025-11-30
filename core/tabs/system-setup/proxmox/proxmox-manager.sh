#!/bin/bash

# ==============================================================================
# Proxmox Manager
#
# A menu-driven script to manage Proxmox tasks like creation, deletion,
# and maintenance of VMs and LXC containers.
# ==============================================================================

# --- Source common functions and set colors ---
# All other scripts will be called from this one, so we only need to source here.
source "$(dirname "$0")/proxmox-common.sh"

# --- Menu Functions ---

show_menu() {
    clear
    echo "===================================="
    echo "        Proxmox Manager Menu"
    echo "===================================="
    echo "1. Run Proxmox Pre-flight Check"
    echo "2. Create a new LXC Container"
    echo "3. Create a new VM"
    echo "4. Exit"
    echo "===================================="
    echo -n "Please choose an option: "
}

# --- Main Loop ---

main() {
    while true; do
        show_menu
        read -r choice
        echo "" # Add a newline for cleaner output

        case $choice in
            1)
                # Run the pre-flight check script
                "$(dirname "$0")/proxmox-preflight-check.sh"
                ;;
            2)
                print_warning "LXC creation script is not yet implemented."
                # Will later call: "$(dirname "$0")/create-lxc.sh"
                ;;
            3)
                print_warning "VM creation script is not yet implemented."
                # Will later call: "$(dirname "$0")/create-vm.sh"
                ;;
            4)
                echo "Exiting Proxmox Manager."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                ;;
        esac
        echo -e "\nPress Enter to return to the menu..."
        read -r
    done
}

# --- Execute Main ---
main
