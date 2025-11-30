#!/bin/bash

# ==============================================================================
# Proxmox Pre-flight Checker
#
# This script runs a series of checks to ensure the Proxmox environment is
# ready for creating new LXC containers and VMs.
# ==============================================================================

# Source the common functions library
# The script expects proxmox-common.sh to be in the same directory.
source "$(dirname "$0")/proxmox-common.sh"

# --- Main Execution ---

main() {
    echo "===================================="
    echo "  Proxmox Pre-flight Check Report"
    echo "===================================="

    # Run all checks from the common library
    check_storage
    check_networking
    check_hw_virtualization
    check_lxc_templates
    check_iso_images

    # Report next available IDs
    print_header "Next Available IDs"
    local next_lxc_id
    next_lxc_id=$(get_next_id "lxc")
    print_success "Next available LXC ID is: $next_lxc_id"
    
    local next_vm_id
    next_vm_id=$(get_next_id "vm")
    print_success "Next available VM ID is:  $next_vm_id"

    echo -e "\n${COLOR_GREEN}====================================${COLOR_NC}"
    echo -e "${COLOR_GREEN}      Check complete.                ${COLOR_NC}"
    echo -e "${COLOR_GREEN}====================================${COLOR_NC}"
}

# Execute the main function
main
