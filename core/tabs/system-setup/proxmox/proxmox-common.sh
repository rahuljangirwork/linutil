#!/bin/bash

# ==============================================================================
# Proxmox Common Functions (Legacy Compatible)
#
# This script contains a library of shared functions for other Proxmox
# management scripts to use. It is intended to be sourced, not executed directly.
# This version avoids '--output-format json' for compatibility with older
# Proxmox versions.
# ==============================================================================

# --- Color Codes for Output ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m' # No Color

# --- Dependency Check ---
check_dependencies() {
    local missing_deps=()
    for dep in awk numfmt; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${COLOR_RED}❌ Error: This script requires the following missing commands: ${missing_deps[*]}${COLOR_NC}"
        echo -e "${COLOR_YELLOW}⚠️ On Debian/Ubuntu, install them with: sudo apt install gawk coreutils${COLOR_NC}"
        exit 1
    fi
}

# --- Helper Functions ---
print_header() { echo -e "\n${COLOR_BLUE}--- $1 ---${COLOR_NC}"; }
print_success() { echo -e "${COLOR_GREEN}✅ $1${COLOR_NC}"; }
print_error() { echo -e "${COLOR_RED}❌ $1${COLOR_NC}"; }
print_warning() { echo -e "${COLOR_YELLOW}⚠️ $1${COLOR_NC}"; }

# --- Check Functions ---

# Checks for available storage pools and their status.
check_storage() {
    print_header "Storage Pool Status"
    local active_pools
    active_pools=$(pvesm status | tail -n +2 | grep 'active' || true)

    if [[ -z "$active_pools" ]]; then
        print_error "No active storage pools found."
        return 1
    fi

    echo "$active_pools" | while read -r name type status total avail percent; do
        # Proxmox CLI returns bytes, so we format them
        total_fmt=$(numfmt --to=iec-i --suffix=B --format="%.1f" "$total")
        avail_fmt=$(numfmt --to=iec-i --suffix=B --format="%.1f" "$avail")
        print_success "Storage '${name}' (${type}) is active. Space: ${avail_fmt} / ${total_fmt}"
    done
    return 0
}

# Finds a storage path by parsing /etc/pve/storage.cfg
get_storage_path() {
    local storage_name=$1
    local path
    # Awk script to find the storage block and print its path
    path=$(awk -v storage="$storage_name" '
        $1 ~ /:$/ && $2 == storage { in_block=1; next }
        in_block && /^\s*path\s+/ { print $2; exit }
        in_block && /:$/ { exit }
    ' /etc/pve/storage.cfg)
    echo "$path"
}


# Checks for available LXC container templates.
check_lxc_templates() {
    print_header "LXC Template Status"
    local template_storage
    # Find storage allowing 'vztmpl' content from storage config
    template_storage=$(grep -B 2 'content .*vztmpl' /etc/pve/storage.cfg | grep -E 'dir:|nfs:|cifs:' | head -n 1 | awk '{print $2}')

    if [[ -z "$template_storage" ]]; then
        print_error "No storage pool found for LXC templates."
        print_warning "Use 'pveam update' and 'pveam download' to get templates."
        return 1
    fi

    # pveam list output is a table, skip header and get the 'Volid' column
    local templates
    templates=$(pveam list "$template_storage" | tail -n +2 | awk '{print $1}' | sed 's#.*/##')
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
    # Find storage allowing 'iso' content from storage config
    iso_storage=$(grep -B 2 'content .*iso' /etc/pve/storage.cfg | grep -E 'dir:|nfs:|cifs:' | head -n 1 | awk '{print $2}')

    if [[ -z "$iso_storage" ]]; then
        print_error "No storage pool found for ISO images."
        return 1
    fi

    local iso_path
    iso_path=$(get_storage_path "$iso_storage")/template/iso

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
get_next_id() {
    local type=$1
    local last_id=99
    local ids

    if [[ "$type" == "vm" ]]; then
        # Skip header (NR>1), print first column ($1)
        ids=$(qm list | awk 'NR>1 {print $1}')
    elif [[ "$type" == "lxc" ]]; then
        ids=$(pct list | awk 'NR>1 {print $1}')
    else
        print_error "Invalid type for get_next_id. Use 'vm' or 'lxc'."
        return 1
    fi

    if [[ -n "$ids" ]]; then
        # Sort numerically and get the last one
        last_id=$(echo "$ids" | sort -n | tail -n 1)
    fi
    
    # Check if last_id is a number, default to 99 if not
    if ! [[ "$last_id" =~ ^[0-9]+$ ]]; then
        last_id=99
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