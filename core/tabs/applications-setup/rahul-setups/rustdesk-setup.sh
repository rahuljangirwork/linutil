#!/bin/bash
set -e

# Load common linutil functions
# Adjust path as necessary based on where this script ends up relative to common-script.sh
# In the previous structure, it was ../../../common-script.sh if inside core/tabs/applications-setup/rahul-setups/
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

get_ip() {
    # Try Tailscale first
    if command_exists tailscale; then
        TAILSCALE_STATUS=$(tailscale status --json 2>/dev/null || echo "{}")
        # Use python or grep to parse json if jq not guaranteed, but checkEnv ensures basic tools
        # For simplicity, let's just use tailscale ip -4 if status is running
        if tailscale status 2>/dev/null | grep -q "Log in"; then
             : # Not logged in
        elif tailscale ip -4 >/dev/null 2>&1; then
             DETECTED_IP=$(tailscale ip -4)
             if [ -n "$DETECTED_IP" ]; then
                printf "%b\n" "${GREEN}Tailscale IP detected: ${DETECTED_IP}${RC}" >&2
                echo "$DETECTED_IP"
                return
             fi
        fi
    fi

    # Fallback to local IP
    DEFAULT_IP=$(hostname -I | awk '{print $1}')
    if [ -n "$DEFAULT_IP" ]; then
        printf "%b\n" "${YELLOW}Using local IP: ${DEFAULT_IP}${RC}" >&2
        echo "$DEFAULT_IP"
        return
    fi
    
    printf "%b\n" "${RED}Could not detect valid IP.${RC}" >&2
    exit 1
}

deploy_rustdesk() {
    SERVER_IP=$(get_ip)
    CONTAINER_NAME="rustdesk-all-in-one"
    
    # Check if container is already running
    if "$ESCALATION_TOOL" docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        printf "%b\n" "${GREEN}RustDesk container is already running.${RC}"
        retrieve_and_display_info "$SERVER_IP" "$CONTAINER_NAME"
        return
    fi
    
    printf "%b\n" "${CYAN}Stopping any existing stopped RustDesk container...${RC}"
    "$ESCALATION_TOOL" docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    
    DATA_DIR="/data/rustdesk"
    "$ESCALATION_TOOL" mkdir -p "$DATA_DIR"
    
    printf "%b\n" "${CYAN}Starting RustDesk All-in-One container...${RC}"
    
    "$ESCALATION_TOOL" docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --net host \
        -e TZ=UTC \
        -e RUSTDESK_ID_SERVER="${SERVER_IP}" \
        -e RUSTDESK_RELAY_SERVER="${SERVER_IP}" \
        -e RUSTDESK_API_SERVER="http://${SERVER_IP}:21114" \
        -e RUSTDESK_API_RUSTDESK_ID_SERVER="${SERVER_IP}:21116" \
        -e RUSTDESK_API_RUSTDESK_RELAY_SERVER="${SERVER_IP}:21117" \
        -e RUSTDESK_API_RUSTDESK_API_SERVER="http://${SERVER_IP}:21114" \
        -v "${DATA_DIR}/data:/data" \
        -v "${DATA_DIR}/public:/public" \
        "lejianwen/rustdesk-server-s6:latest"
        
    if [ $? -eq 0 ]; then
        printf "%b\n" "${GREEN}RustDesk container started successfully!${RC}"
        
        if [ -n "$("$ESCALATION_TOOL" ls -A "${DATA_DIR}/data" 2>/dev/null)" ]; then
             printf "%b\n" "${YELLOW}Existing data detected. Password may not be regenerated.${RC}"
        fi
        
        printf "%b\n" "${YELLOW}Waiting for services to initialize (10s)...${RC}"
        sleep 10
        
        retrieve_and_display_info "$SERVER_IP" "$CONTAINER_NAME"
    else
        printf "%b\n" "${RED}Failed to start RustDesk container.${RC}"
        exit 1
    fi
}

retrieve_and_display_info() {
    local IP=$1
    local NAME=$2
    local PASSWORD=""
    local PUBLIC_KEY=""
    
    # Try to find password in logs (search whole history)
    # Log format: [INFO] Admin Password Is: <password> (...)
    PASSWORD=$("$ESCALATION_TOOL" docker logs "$NAME" 2>&1 | grep -i "Admin Password Is" | tail -n1 | sed -n 's/.*Admin Password Is: \([^ ]*\).*/\1/p')
    
    # Fallback for different log variants
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$("$ESCALATION_TOOL" docker logs "$NAME" 2>&1 | grep -i "Admin password" | tail -n1 | awk -F': ' '{print $2}' | tr -d '\r\n')
    fi
    
    if [ -z "$PASSWORD" ]; then
         PASSWORD="<Not found in logs. If this is an existing install, use your old password>"
    fi
    
    # Extract Public Key
    if "$ESCALATION_TOOL" ls "/data/rustdesk/data/id_ed25519.pub" >/dev/null 2>&1; then
         PUBLIC_KEY=$("$ESCALATION_TOOL" cat /data/rustdesk/data/id_ed25519.pub)
    else
         PUBLIC_KEY="<Key file not found at /data/rustdesk/data/id_ed25519.pub>"
    fi
    
    printf "%b\n" "${BOLD}========================================${RC}"
    printf "%b\n" "${BOLD}   RustDesk Server Info${RC}"
    printf "%b\n" "${BOLD}========================================${RC}"
    printf "%b\n" "ID Server:    ${IP}:21116"
    printf "%b\n" "Relay Server: ${IP}:21117"
    printf "%b\n" "API Server:   http://${IP}:21114"
    printf "%b\n" "Key:          ${PUBLIC_KEY}"
    printf "%b\n" "${BOLD}----------------------------------------${RC}"
    printf "%b\n" "Web Admin:    http://${IP}:21114/_admin/"
    printf "%b\n" "Local Admin:  http://127.0.0.1:21114/_admin/ (Try this if above fails)"
    printf "%b\n" "Web Client:   http://${IP}:21114/webclient/"
    printf "%b\n" "${BOLD}----------------------------------------${RC}"
    printf "%b\n" "Admin User:   admin"
    printf "%b\n" "Admin Pass:   ${MAGENTA}${PASSWORD}${RC}"
    printf "%b\n" "${BOLD}========================================${RC}"
    printf "%b\n" ""
    printf "%b\n" "${CYAN}To view full logs:${RC}"
    printf "%b\n" "  sudo docker logs $NAME"
    printf "%b\n" "${CYAN}To reset admin password (if lost):${RC}"
    printf "%b\n" "  sudo docker exec $NAME /app/apimain reset-admin-pwd <new_password>"
    printf "%b\n" "${BOLD}========================================${RC}"
}

install_docker
deploy_rustdesk
