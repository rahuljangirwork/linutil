#!/bin/sh -e

# Source common functions and variables
. ../../common-script.sh

# Function for clear yes/no prompts, defaulting to 'no'.
confirm_action() {
    printf "%b" "${CYAN}$1 (y/N): ${RC}"
    read -r confirm
    if echo "$confirm" | grep -qE '^[Yy]
; then
        return 0
    else
        return 1
    fi
}

# 1. Install Tailscale if it's not already present
install_tailscale() {
    printf "%b\n" "${YELLOW}Checking Tailscale installation...${RC}"
    if ! command_exists tailscale; then
        printf "%b\n" "${YELLOW}Installing Tailscale using the official script...${RC}"
        # The official script handles distro detection and is the most robust method.
        "$ESCALATION_TOOL" sh -c "curl -fsSL https://tailscale.com/install.sh | sh"
        printf "%b\n" "${GREEN}Tailscale installed successfully.${RC}"
    else
        printf "%b\n" "${GREEN}Tailscale is already installed.${RC}"
    fi
}

# 2. Ensure the Tailscale service is enabled and running
ensure_service_running() {
    printf "%b\n" "${YELLOW}Ensuring Tailscale service is running...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now tailscaled
    printf "%b\n" "${GREEN}Service is active.${RC}"
}

# --- Main Script Execution ---
printf "%b\n" "${BLUE}--- Tailscale Setup ---${RC}"
checkEnv
checkEscalationTool
install_tailscale
ensure_service_running

# 3. Authentication and Connection
printf "%b\n" "${BLUE}--- Connection ---${RC}"
UP_ARGS=""

if confirm_action "Do you want to authenticate automatically using an API key?"; then
    # --- API Key Flow ---
    AUTH_KEY=""
    while [ -z "$AUTH_KEY" ]; do
        printf "%b" "${CYAN}Please enter your Tailscale API auth key: ${RC}"
        read -r AUTH_KEY
        if [ -z "$AUTH_KEY" ]; then
            printf "%b\n" "${RED}Auth key cannot be empty. Please try again.${RC}"
        fi
    done
    UP_ARGS="--authkey=$AUTH_KEY"
    printf "%b\n" "${YELLOW}Authenticating with API key...${RC}"
    "$ESCALATION_TOOL" tailscale up $UP_ARGS
else
    # --- Manual Authentication Flow ---
    printf "%b\n" "${YELLOW}Starting manual authentication...${RC}"
    "$ESCALATION_TOOL" tailscale up
    printf "%b\n" "${CYAN}Please complete the authentication process in your web browser.${RC}"
    printf "%b" "${CYAN}Press [Enter] to continue once you have authenticated...${RC}"
    read -r
fi

# 4. Verify Connection
printf "%b\n" "${YELLOW}Waiting for successful connection...${RC}"
max_retries=15
count=0
while ! "$ESCALATION_TOOL" tailscale status | grep -q "Logged in."; do
    if [ "$count" -ge "$max_retries" ]; then
        printf "%b\n" "${RED}Connection timed out. Please check your Tailscale dashboard.${RC}"
        exit 1
    fi
    sleep 2
    count=$((count + 1))
done
printf "%b\n" "${GREEN}Successfully connected to Tailscale.${RC}"

# 5. Advertise Routes (post-authentication)
if confirm_action "Do you want to advertise routes?"; then
    ROUTES=""
    while [ -z "$ROUTES" ]; do
        printf "%b" "${CYAN}Please enter the routes to advertise (e.g., 10.0.0.0/8): ${RC}"
        read -r ROUTES
        if [ -z "$ROUTES" ]; then
            printf "%b\n" "${RED}Routes cannot be empty. Please try again.${RC}"
        fi
    done
    printf "%b\n" "${YELLOW}Advertising routes: $ROUTES...${RC}"
    "$ESCALATION_TOOL" tailscale up --advertise-routes="$ROUTES"
    printf "%b\n" "${GREEN}Route advertisement configured.${RC}"
fi

# 6. Final Status Check
printf "%b\n" "${BLUE}--- Final Status ---${RC}"
"$ESCALATION_TOOL" tailscale status
TS_IP=$("$ESCALATION_TOOL" tailscale ip -4)
printf "%b\n" "${GREEN}Tailscale IP: $TS_IP${RC}"
printf "%b\n" "${BLUE}--------------------${RC}"
