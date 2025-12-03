#!/bin/sh -e

# Source common functions and variables
. ../../common-script.sh

# Function for clear yes/no prompts, defaulting to 'no'.
confirm_action() {
    printf "%b" "${CYAN}$1 (y/N): ${RC}"
    read -r confirm
    if echo "$confirm" | grep -qE '^[Yy]$'; then
        return 0
    else
        return 1
    fi
}

# --- Main Script Execution ---
printf "%b\n" "${BLUE}--- Tailscale Uninstaller ---${RC}"

# First, check environment and escalation tool to ensure script can run
checkEnv
checkEscalationTool

# Confirm the user wants to proceed
if ! confirm_action "This will stop, disable, and uninstall Tailscale. Are you sure?"; then
    printf "%b\n" "${RED}Uninstallation cancelled.${RC}"
    exit 0
fi

# 1. Stop and disable the tailscaled service
if systemctl is-active --quiet tailscaled; then
    printf "%b\n" "${YELLOW}Stopping and disabling Tailscale service...${RC}"
    "$ESCALATION_TOOL" systemctl stop tailscaled
    "$ESCALATION_TOOL" systemctl disable tailscaled
    printf "%b\n" "${GREEN}Service stopped and disabled.${RC}"
else
    printf "%b\n" "${CYAN}Tailscale service is not running.${RC}"
fi

# 2. Remove the Tailscale package using the detected package manager
printf "%b\n" "${YELLOW}Removing Tailscale package...${RC}"
if command_exists tailscale; then
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y tailscale
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y tailscale
            ;;
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -Rns --noconfirm tailscale
            ;;
        *)
            printf "%b\n" "${RED}Could not determine package manager. Please uninstall Tailscale manually.${RC}"
            ;;
    esac
    printf "%b\n" "${GREEN}Tailscale package removed.${RC}"
else
    printf "%b\n" "${CYAN}Tailscale package is not installed.${RC}"
fi

# 3. Clean up remaining state files
if [ -d /var/lib/tailscale ]; then
    if confirm_action "Do you want to remove all Tailscale state and identity files? (This cannot be undone)"; then
        printf "%b\n" "${YELLOW}Removing Tailscale state files...${RC}"
        "$ESCALATION_TOOL" rm -rf /var/lib/tailscale
        printf "%b\n" "${GREEN}State files removed.${RC}"
    fi
fi

printf "%b\n" "${GREEN}--- Tailscale uninstallation complete ---${RC}"
