#!/bin/sh -e

. ../../common-script.sh

# RustDesk version
RUSTDESK_VERSION="1.4.1"
GITHUB_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}"

detectArchitecture() {
    case "$(uname -m)" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l) ARCH="armv7" ;;
        i686|i386) ARCH="i386" ;;
        *) 
            printf "%b\n" "${RED}Unsupported architecture: $(uname -m)${RC}"
            exit 1
            ;;
    esac
}

installRustDeskClient() {
    if ! command_exists rustdesk; then
        printf "%b\n" "${YELLOW}Installing RustDesk Client v${RUSTDESK_VERSION}...${RC}"
        detectArchitecture
        
        case "$PACKAGER" in
            pacman)
                # RustDesk is available in AUR
                checkAURHelper
                "$AUR_HELPER" -S --needed --noconfirm rustdesk-bin
                ;;
            apt-get|nala)
                # Download and install .deb package for Debian/Ubuntu
                TEMP_DIR=$(mktemp -d)
                cd "$TEMP_DIR"
                
                if [ "$ARCH" = "x86_64" ]; then
                    DEB_FILE="rustdesk-${RUSTDESK_VERSION}-${ARCH}.deb"
                elif [ "$ARCH" = "aarch64" ]; then
                    DEB_FILE="rustdesk-${RUSTDESK_VERSION}-${ARCH}.deb"
                else
                    printf "%b\n" "${RED}Architecture ${ARCH} not supported for Debian packages${RC}"
                    exit 1
                fi
                
                printf "%b\n" "${YELLOW}Downloading RustDesk ${DEB_FILE}...${RC}"
                if curl -sSL "${GITHUB_URL}/${DEB_FILE}" -o "${DEB_FILE}"; then
                    printf "%b\n" "${YELLOW}Installing RustDesk .deb package...${RC}"
                    "$ESCALATION_TOOL" dpkg -i "${DEB_FILE}"
                    # Fix any dependency issues
                    "$ESCALATION_TOOL" "$PACKAGER" install -f -y
                else
                    printf "%b\n" "${RED}Failed to download ${DEB_FILE}${RC}"
                    exit 1
                fi
                cd - > /dev/null
                rm -rf "$TEMP_DIR"
                ;;
            dnf)
                # Download and install .rpm package for Fedora
                TEMP_DIR=$(mktemp -d)
                cd "$TEMP_DIR"
                
                if [ "$ARCH" = "x86_64" ]; then
                    RPM_FILE="rustdesk-${RUSTDESK_VERSION}-0.${ARCH}.rpm"
                elif [ "$ARCH" = "aarch64" ]; then
                    RPM_FILE="rustdesk-${RUSTDESK_VERSION}-0.${ARCH}.rpm"
                else
                    printf "%b\n" "${RED}Architecture ${ARCH} not supported for Fedora packages${RC}"
                    exit 1
                fi
                
                printf "%b\n" "${YELLOW}Downloading RustDesk ${RPM_FILE}...${RC}"
                if curl -sSL "${GITHUB_URL}/${RPM_FILE}" -o "${RPM_FILE}"; then
                    printf "%b\n" "${YELLOW}Installing RustDesk .rpm package...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" localinstall -y "${RPM_FILE}"
                else
                    printf "%b\n" "${RED}Failed to download ${RPM_FILE}${RC}"
                    exit 1
                fi
                cd - > /dev/null
                rm -rf "$TEMP_DIR"
                ;;
            zypper)
                # Download and install .rpm package for openSUSE
                TEMP_DIR=$(mktemp -d)
                cd "$TEMP_DIR"
                
                if [ "$ARCH" = "x86_64" ]; then
                    RPM_FILE="rustdesk-${RUSTDESK_VERSION}-0.${ARCH}-suse.rpm"
                elif [ "$ARCH" = "aarch64" ]; then
                    RPM_FILE="rustdesk-${RUSTDESK_VERSION}-0.${ARCH}-suse.rpm"
                else
                    printf "%b\n" "${RED}Architecture ${ARCH} not supported for openSUSE packages${RC}"
                    exit 1
                fi
                
                printf "%b\n" "${YELLOW}Downloading RustDesk ${RPM_FILE}...${RC}"
                if curl -sSL "${GITHUB_URL}/${RPM_FILE}" -o "${RPM_FILE}"; then
                    printf "%b\n" "${YELLOW}Installing RustDesk .rpm package...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" install --allow-unsigned-rpm -y "${RPM_FILE}"
                else
                    printf "%b\n" "${RED}Failed to download ${RPM_FILE}${RC}"
                    exit 1
                fi
                cd - > /dev/null
                rm -rf "$TEMP_DIR"
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: ${PACKAGER}${RC}"
                printf "%b\n" "${YELLOW}You can manually download RustDesk from: ${GITHUB_URL}${RC}"
                exit 1
                ;;
        esac
        printf "%b\n" "${GREEN}RustDesk Client v${RUSTDESK_VERSION} installed successfully.${RC}"
    else
        CURRENT_VERSION=$(rustdesk --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n1 || echo "unknown")
        printf "%b\n" "${GREEN}RustDesk Client is already installed (version: ${CURRENT_VERSION}).${RC}"
        if [ "$CURRENT_VERSION" != "$RUSTDESK_VERSION" ] && [ "$CURRENT_VERSION" != "unknown" ]; then
            printf "%b\n" "${YELLOW}Note: Latest version is ${RUSTDESK_VERSION}. Consider updating.${RC}"
        fi
    fi
}

setupRustDeskService() {
    printf "%b\n" "${YELLOW}Setting up RustDesk service...${RC}"
    
    # Enable RustDesk service to start automatically (if available)
    if command_exists systemctl; then
        if systemctl list-unit-files | grep -q "rustdesk.service"; then
            "$ESCALATION_TOOL" systemctl enable rustdesk.service
            printf "%b\n" "${GREEN}RustDesk service enabled.${RC}"
        else
            printf "%b\n" "${YELLOW}RustDesk service file not found. You can start RustDesk manually.${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}systemctl not available. Service setup skipped.${RC}"
    fi
}

configureFirewall() {
    printf "%b\n" "${YELLOW}Configuring firewall for RustDesk...${RC}"
    
    # RustDesk uses port 21116 for direct connections
    if command_exists ufw; then
        printf "%b\n" "${YELLOW}Configuring UFW firewall...${RC}"
        
        # Check if UFW is working properly first
        if ! sudo ufw status >/dev/null 2>&1; then
            printf "%b\n" "${YELLOW}UFW has issues. Attempting to fix...${RC}"
            
            # Try common fixes
            sudo ufw logging off >/dev/null 2>&1
            
            # For Arch Linux, install iptables-nft if missing
            if [ "$PACKAGER" = "pacman" ]; then
                if ! pacman -Qi iptables-nft >/dev/null 2>&1; then
                    printf "%b\n" "${YELLOW}Installing iptables-nft...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm iptables-nft
                fi
            fi
            
            # Test again
            if ! sudo ufw status >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}UFW still has issues. Skipping firewall configuration.${RC}"
                printf "%b\n" "${YELLOW}You may need to manually configure port 21116.${RC}"
                return
            fi
        fi
        
        # Configure UFW rules
        if sudo ufw allow 21116/tcp >/dev/null 2>&1 && sudo ufw allow 21116/udp >/dev/null 2>&1; then
            printf "%b\n" "${GREEN}UFW firewall configured for RustDesk.${RC}"
        else
            printf "%b\n" "${YELLOW}Failed to configure UFW. You may need to manually allow port 21116.${RC}"
        fi
        
    elif command_exists firewall-cmd; then
        printf "%b\n" "${YELLOW}Configuring firewalld...${RC}"
        "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=21116/tcp
        "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=21116/udp
        "$ESCALATION_TOOL" firewall-cmd --reload
        printf "%b\n" "${GREEN}Firewalld configured for RustDesk.${RC}"
    else
        printf "%b\n" "${YELLOW}No supported firewall found. You may need to manually configure port 21116.${RC}"
    fi
}

postInstallMessage() {
    printf "%b\n" "${GREEN}============================================${RC}"
    printf "%b\n" "${GREEN}RustDesk Client v${RUSTDESK_VERSION} Installation Complete!${RC}"
    printf "%b\n" "${GREEN}============================================${RC}"
    printf "%b\n" "${CYAN}You can now start RustDesk by:${RC}"
    printf "%b\n" "${YELLOW}1. Running 'rustdesk' from terminal${RC}"
    printf "%b\n" "${YELLOW}2. Finding it in your applications menu${RC}"
    printf "%b\n" "${CYAN}New features in v${RUSTDESK_VERSION}:${RC}"
    printf "%b\n" "${YELLOW}- Terminal support${RC}"
    printf "%b\n" "${YELLOW}- UDP and IPv6 Punch${RC}"
    printf "%b\n" "${YELLOW}- Stylus support${RC}"
    printf "%b\n" "${YELLOW}- Numeric one-time password option${RC}"
    printf "%b\n" "${YELLOW}- Force-always-relay option${RC}"
    printf "%b\n" "${CYAN}Important notes:${RC}"
    printf "%b\n" "${YELLOW}- Allow permissions for screen sharing on first run${RC}"
    printf "%b\n" "${YELLOW}- Port 21116 has been configured in firewall (if supported)${RC}"
    printf "%b\n" "${YELLOW}- Visit https://rustdesk.com for more information${RC}"
    printf "%b\n" "${GREEN}============================================${RC}"
}

checkEnv
checkEscalationTool
installRustDeskClient
setupRustDeskService
configureFirewall
postInstallMessage
