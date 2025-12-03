#!/bin/bash
set -e  # Exit on any error

# Helper function for clear yes/no prompts. Defaults to 'no'.
ask_yes_no() {
    read -p "$1 (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if Tailscale is installed
check_install_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        echo "Tailscale is not installed. Installing now..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        echo "Tailscale is already installed."
    fi
}

# Function to enable and start the Tailscale service
start_tailscale_service() {
    echo "Enabling and starting the Tailscale service..."
    sudo systemctl enable --now tailscaled
}

# Function to authenticate using the API key
authenticate_with_api_key() {
    echo "--- Tailscale Authentication ---"
    
    # Loop until a non-empty auth key is provided
    AUTH_KEY=""
    while [ -z "$AUTH_KEY" ]; do
        read -p "Please enter your Tailscale API auth key: " AUTH_KEY
        if [ -z "$AUTH_KEY" ]; then
            echo "Auth key cannot be empty. Please try again."
        fi
    done

    # Add auth key to command arguments
    cmd_args+=("--authkey=$AUTH_KEY")

    # Ask to advertise routes
    if ask_yes_no "Do you want to advertise routes?"; then
        ROUTES=""
        while [ -z "$ROUTES" ]; do
            read -p "Please enter the routes to advertise (e.g., 10.0.0.0/8,192.168.0.0/24): " ROUTES
            if [ -z "$ROUTES" ]; then
                echo "Routes cannot be empty. Please try again."
            fi
        done
        cmd_args+=("--advertise-routes=$ROUTES")
    fi
}

# Function to bring Tailscale up with the provided arguments
start_tailscale() {
    echo "Running Tailscale with your configuration..."
    sudo tailscale up "${cmd_args[@]}"
    echo "Tailscale has been configured and is now running."
}

# Function to connect manually using Tailscale (no API key)
manual_connect() {
    echo "--- Manual Connection ---"
    echo "Please run the following command to connect to your Tailnet:"
    echo "  sudo tailscale up"
    
    # Wait for confirmation that the user has run the command
    while true; do
        read -p "Have you run the command and authenticated (y/N)? " confirmation
        case "$confirmation" in
            [yY][eE][sS]|[yY])
                break
                ;;
            *)
                echo "Please run the command and authenticate first."
                ;;
        esac
    done
}

# Function to check the Tailscale connection status
check_connection_status() {
    echo "--- Checking Tailscale Connection Status ---"
    STATUS=$(sudo tailscale status)
    
    if echo "$STATUS" | grep -q "Tailscale is running"; then
        echo "Tailscale is connected successfully!"
        IP_ADDRESS=$(tailscale ip -4)
        echo "Assigned IP address: $IP_ADDRESS"
    else
        echo "Tailscale is not connected."
    fi
}

# Function to advertise subnet
advertise_subnet() {
    if ask_yes_no "Do you want to advertise a subnet?"; then
        SUBNET=""
        while [ -z "$SUBNET" ]; do
            read -p "Please enter the subnet to advertise (e.g., 192.168.0.0/24): " SUBNET
            if [ -z "$SUBNET" ]; then
                echo "Subnet cannot be empty. Please try again."
            fi
        done
        # Advertise the route
        sudo tailscale up --advertise-routes=$SUBNET
        echo "Subnet $SUBNET is now being advertised."
    else
        echo "Skipping subnet advertisement."
    fi
}

# Main script logic
echo "--- Tailscale Setup ---"

# 1. Install Tailscale
check_install_tailscale

# 2. Enable and start the Tailscale service
start_tailscale_service

# 3. Ask if the user wants to authenticate using an API key or manually
declare -a cmd_args  # Array to store command arguments for Tailscale

if ask_yes_no "Do you want to authenticate automatically using an API key?"; then
    authenticate_with_api_key
    start_tailscale
else
    manual_connect
fi

# 4. Advertise subnet if the user agrees
advertise_subnet

# 5. Check connection status
check_connection_status

echo "-----------------------"
