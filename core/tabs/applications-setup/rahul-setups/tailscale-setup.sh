#!/bin/bash
set -e

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

echo "--- Tailscale Setup ---"

# 1. Installation
echo "Installing Tailscale using the official script..."
# The official script handles distro detection and is the most robust method.
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Enable and start the Tailscale service
echo "Enabling and starting the Tailscale service..."
sudo systemctl enable --now tailscaled

# 3. Configuration
echo "--- Configuration ---"

# Use an array for command arguments for robustness
declare -a cmd_args

if ask_yes_no "Do you want to authenticate automatically using an API key?"; then
    # Loop until a non-empty auth key is provided
    AUTH_KEY=""
    while [ -z "$AUTH_KEY" ]; do
        read -p "Please enter your Tailscale API auth key: " AUTH_KEY
        if [ -z "$AUTH_KEY" ]; then
            echo "Auth key cannot be empty. Please try again."
        fi
    done
    cmd_args+=("--authkey=$AUTH_KEY")

    # Only ask to advertise routes if using an auth key
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

    echo "Running Tailscale with your configuration..."
    sudo tailscale up "${cmd_args[@]}"
    echo "Tailscale has been configured and is now running."

else
    echo
    echo "Okay. To connect this machine to your Tailnet, run the following command from your terminal:"
    echo "  sudo tailscale up"
    echo
fi

echo "-----------------------"
