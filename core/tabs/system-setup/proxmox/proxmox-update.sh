#!/bin/sh -e

. ../../common-script.sh

updateSystem() {
    printf "%b\n" "${YELLOW}Updating Proxmox VE system packages.${RC}"
    if command_exists apt-get;
 then
        "$ESCALATION_TOOL" apt-get update
        "$ESCALATION_TOOL" apt-get dist-upgrade -y
    else
        printf "%b\n" "${RED}apt-get not found. This script is intended for Debian-based systems like Proxmox VE.${RC}"
        exit 1
    fi
}

checkEnv
checkEscalationTool
updateSystem

printf "%b\n" "${GREEN}Proxmox VE system update complete.${RC}"

