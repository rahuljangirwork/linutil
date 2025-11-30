#!/bin/bash

# ==============================================================================
# Proxmox Common Functions
#
# This script contains a library of shared functions for other Proxmox
# management scripts to use. It is intended to be sourced, not executed directly.
#
# Usage in another script:
#   source "$(dirname "$0")/proxmox-common.sh"
# ==============================================================================

# --- Color Codes for Output ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m' # No Color

# --- Dependency Check ---
# Ensures required commands (like jq) are available.
check_dependencies() {
    local missing_deps=()
    for dep in jq numfmt; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${COLOR_RED}❌ Error: This script requires the following missing commands: ${missing_deps[*]}${COLOR_NC}"
        echo -e "${COLOR_YELLOW}⚠️ On Debian/Ubuntu, install them with: sudo apt install jq coreutils${COLOR_NC}"
        exit 1
    fi
}

# --- Helper Functions ---

# Prints a formatted header.
# Usage: print_header "My Header"
print_header() {
    echo -e "\n${COLOR_BLUE}--- $1 ---${COLOR_NC}"
}

# Prints a success message.
# Usage: print_success "Task completed"
print_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_NC}"
}

# Prints an error message.
# Usage: print_error "Task failed"
print_error() {
    echo -e "${COLOR_RED}❌ $1${COLOR_NC}"
}

# Prints a warning message.
# Usage: print_warning "This is a warning"
print_warning() {
    echo -e "${COLOR_YELLOW}⚠️ $1${COLOR_NC}"
}


# --- Check Functions ---

# Checks for available storage pools and their status.
check_storage() {
    print_header "Storage Pool Status"
    pvesm status --output-format json | jq -r '.[] | select(.active == 1) | [.storage, .type, .total, .avail] | @tsv' | while IFS=$'\t' read -r storage type total avail; do
        total_gb=$(numfmt --to=iec-i --suffix=B --format="%.1f" "$total")
        avail_gb=$(numfmt --to=iec-i --suffix=B --format="%.1f" "$avail")
        print_success "Storage '${storage}' (${type}) is active. Space: ${avail_gb} / ${total_gb}"
    done

    if ! pvesm status | grep -q 'active 1'; then
        print_error "No active storage pools found."
        return 1
    fi
    return 0
}

# Checks for available LXC container templates.
check_lxc_templates() {
    print_header "LXC Template Status"
    local template_storage
    template_storage=$(pvesm status --output-format json | jq -r '.[] | select(.content | contains("vztmpl")) | .storage' | head -n 1)

    if [[ -z "$template_storage" ]]; then
        print_error "No storage pool found for LXC templates."
        print_warning "Use 'pveam update' and 'pveam download' to get templates."
        return 1
    fi

    local templates
    templates=$(pveam list "$template_storage" --output-format json | jq -r '.[].volid')
    if [[ -z "$templates" ]]; then
        print_warning "No LXC templates found in storage '$template_storage'."
        print_warning "Use 'pveam download $template_storage <template-name>' to add some."
        return 1
    fi

    print_success "Found LXC templates in storage '$template_storage':"
    echo "$templates" | sed 's/^/  - /'
    return 0
}

# Checks for available VM ISO images.
check_iso_images() {
    print_header "ISO Image Status"
    local iso_storage
    iso_storage=$(pvesm status --output-format json | jq -r '.[] | select(.content | contains("iso")) | .storage' | head -n 1)

    if [[ -z "$iso_storage" ]]; then
        print_error "No storage pool found for ISO images."
        return 1
    fi

    local iso_path
    iso_path=$(pvesm status --storage "$iso_storage" --output-format json | jq -r '.[0].path')/template/iso

    if [[ ! -d "$iso_path" ]] || ! ls -1qA "$iso_path" | grep -q .; then
        print_warning "No ISO images found in storage '$iso_storage' ($iso_path)."
        return 1
    fi

    print_success "Found ISO images in storage '$iso_storage':"
    ls -1 "$iso_path" | sed 's/^/  - /'
    return 0
}

# Checks for network bridges.
check_networking() {
    print_header "Network Status"
    local bridges
    bridges=$(ip -br a | grep 'UP' | awk '{print $1}' | grep 'vmbr')

    if [[ -z "$bridges" ]]; then
        print_error "No active network bridge (vmbr) found."
        return 1
    fi

    print_success "Active network bridges found:"
    echo "$bridges" | sed 's/^/  - /'
    return 0
}

# Finds the next available VM or LXC ID.
# Usage: get_next_id "vm" or get_next_id "lxc"
get_next_id() {
    local type=$1
    local last_id=99
    local ids

    if [[ "$type" == "vm" ]]; then
        ids=$(qm list --output-format json | jq -r '.[].vmid')
    elif [[ "$type" == "lxc" ]]; then
        ids=$(pct list --output-format json | jq -r '.[].vmid')
    else
        print_error "Invalid type for get_next_id. Use 'vm' or 'lxc'."
        return 1
    fi

    if [[ -n "$ids" ]]; then
        last_id=$(echo "$ids" | sort -n | tail -n 1)
    fi

    echo "$((last_id + 1))"
}


# Checks if hardware virtualization is enabled.
check_hw_virtualization() {
    print_header "Hardware Virtualization (for VMs)"
    if grep -E -q 'svm|vmx' /proc/cpuinfo; then
        print_success "Hardware virtualization (VT-x/AMD-V) is enabled."
        return 0
    else
        print_error "Hardware virtualization is NOT enabled in the BIOS/UEFI."
        return 1
    fi
}

# --- Run dependency check immediately when sourced ---
check_dependencies
