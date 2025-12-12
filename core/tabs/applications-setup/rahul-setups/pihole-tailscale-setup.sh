#!/bin/bash
set -e

# Load common linutil functions
. ../../common-script.sh

# Initialize LinUtil Environment
checkEnv

install_docker() {
    if ! command_exists docker; then
        printf "%b\n" "${YELLOW}Installing Docker...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm docker docker-compose
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" update
                "$ESCALATION_TOOL" "$PACKAGER" install -y docker.io docker-compose-plugin
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y docker docker-compose-plugin
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" install -y docker docker-compose
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add docker docker-compose
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy docker docker-compose
                ;;
            eopkg)
                "$ESCALATION_TOOL" "$PACKAGER" install -y docker docker-compose
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager for automatic Docker installation.${RC}"
                exit 1
                ;;
        esac
        
        # Start and enable Docker service
        if command_exists systemctl; then
            "$ESCALATION_TOOL" systemctl enable --now docker
        elif command_exists service; then
            "$ESCALATION_TOOL" service docker start
        fi
        
        # Add user to docker group if not already
        if ! groups | grep -q docker; then
            "$ESCALATION_TOOL" usermod -aG docker "$USER"
            printf "%b\n" "${YELLOW}Added $USER to docker group. You may need to logout and login again.${RC}"
        fi
    else
        printf "%b\n" "${GREEN}Docker is already installed.${RC}"
    fi
}

check_port_53() {
    printf "%b\n" "${CYAN}Checking Port 53 (DNS) availability...${RC}"
    if "$ESCALATION_TOOL" ss -lptn 'sport = :53' | grep -q "LISTEN"; then
        printf "%b\n" "${YELLOW}Port 53 is in use. Checking owner...${RC}"
        
        # Check if it is systemd-resolved
        if "$ESCALATION_TOOL" systemctl is-active systemd-resolved >/dev/null 2>&1; then
             # Double check if systemd-resolved is actually the one listening
             if "$ESCALATION_TOOL" ss -lptn 'sport = :53' | grep -q "systemd-resolve"; then
                printf "%b\n" "${YELLOW}systemd-resolved is binding Port 53. Disabling it to allow Pi-hole to work...${RC}"
                "$ESCALATION_TOOL" systemctl stop systemd-resolved
                "$ESCALATION_TOOL" systemctl disable systemd-resolved
                
                # Fix /etc/resolv.conf so the host still has DNS
                printf "%b\n" "${CYAN}Updating /etc/resolv.conf to use default DNS (8.8.8.8) temporarily...${RC}"
                "$ESCALATION_TOOL" rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" | "$ESCALATION_TOOL" tee /etc/resolv.conf > /dev/null
                return
             fi
        fi

        # Check if it is Docker (likely our own Pi-hole)
        if "$ESCALATION_TOOL" ss -lptn 'sport = :53' | grep -q "docker-proxy"; then
             printf "%b\n" "${GREEN}Port 53 is being used by Docker. Assuming this is our specific Pi-hole container and proceeding...${RC}"
             return
        fi

        # If we got here, it's something unrelated blocking the port
        printf "%b\n" "${RED}Something other than systemd-resolved or Docker is using Port 53.${RC}"
        printf "%b\n" "${RED}Process details:${RC}"
        "$ESCALATION_TOOL" ss -lptn 'sport = :53'
        exit 1
    else
        printf "%b\n" "${GREEN}Port 53 is free.${RC}"
    fi
}

get_tailscale_ip() {
    if command_exists tailscale; then
        TS_IP=$(tailscale ip -4 2>/dev/null)
        if [ -n "$TS_IP" ]; then
            echo "$TS_IP"
            return
        fi
    fi
    echo "127.0.0.1" # Fallback, though user should have Tailscale
}

deploy_pihole() {
    PIHOLE_DIR="$HOME/pihole-tailscale"
    mkdir -p "$PIHOLE_DIR"
    
    CONTAINER_NAME="pihole-tailscale"
    WEB_PORT="8053"
    DEFAULT_PASS="admin123"
    
    # Check if container is already running
    if "$ESCALATION_TOOL" docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        printf "%b\n" "${GREEN}Pi-hole container is already running.${RC}"
        
        # Try to grab the password from the environment variables of the running container
        CURRENT_PASS=$("$ESCALATION_TOOL" docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{if match "WEBPASSWORD=" .}}{{.}}{{end}}{{end}}' | cut -d= -f2)
        
        if [ -z "$CURRENT_PASS" ]; then
            CURRENT_PASS="<Unknown (Custom Set)>"
        fi
    else
        printf "%b\n" "${CYAN}Stopping any existing stopped Pi-hole container...${RC}"
        "$ESCALATION_TOOL" docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

        printf "%b\n" "${CYAN}Deploying Pi-hole Docker container...${RC}"
        
        "$ESCALATION_TOOL" docker run -d \
            --name "$CONTAINER_NAME" \
            -p 53:53/tcp \
            -p 53:53/udp \
            -p "${WEB_PORT}:80" \
            -e WEBPASSWORD="$DEFAULT_PASS" \
            -e TZ='Asia/Kolkata' \
            -v "${PIHOLE_DIR}/etc-pihole:/etc/pihole" \
            -v "${PIHOLE_DIR}/etc-dnsmasq.d:/etc/dnsmasq.d" \
            --restart=unless-stopped \
            pihole/pihole:latest
            
        if [ $? -eq 0 ]; then
            printf "%b\n" "${GREEN}Pi-hole deployed successfully!${RC}"
            CURRENT_PASS="$DEFAULT_PASS"
        else
            printf "%b\n" "${RED}Failed to deploy Pi-hole.${RC}"
            exit 1
        fi
    fi

    TS_IP=$(get_tailscale_ip)
    
    printf "%b\n" "${BOLD}========================================${RC}"
    printf "%b\n" "${BOLD}   Pi-hole Setup Complete (Tailscale)${RC}"
    printf "%b\n" "${BOLD}========================================${RC}"
    printf "%b\n" "Web Interface: http://${TS_IP}:${WEB_PORT}/admin"
    printf "%b\n" "Password:      ${MAGENTA}${CURRENT_PASS}${RC}"
    printf "%b\n" "DNS IP:        ${TS_IP}"
    printf "%b\n" "${BOLD}----------------------------------------${RC}"
    printf "%b\n" "${CYAN}To change proper password:${RC}"
    printf "%b\n" "  sudo docker exec -it pihole-tailscale pihole setpassword"
    printf "%b\n" "${BOLD}----------------------------------------${RC}"
    printf "%b\n" "${YELLOW}NEXT STEPS (On your other devices):${RC}"
    printf "%b\n" "1. Open Tailscale Admin Console (https://login.tailscale.com/admin/dns)"
    printf "%b\n" "2. Go to DNS -> Global Nameservers"
    printf "%b\n" "3. Add Nameserver -> Custom"
    printf "%b\n" "4. Enter IPv4: ${TS_IP}"
    printf "%b\n" "5. Turn on 'Override local DNS'"
    printf "%b\n" "${BOLD}========================================${RC}"
}

install_docker
check_port_53
deploy_pihole
