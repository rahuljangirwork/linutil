#!/bin/bash

# Function to detect the Linux distribution and install Tailscale
install_tailscale() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "Unsupported OS. Cannot determine distribution."
        exit 1
    fi

    echo "Detected distribution: $DISTRO"

    case "$DISTRO" in
        ubuntu|debian|pop)
            echo "Using apt for installation..."
            sudo apt-get update
            sudo apt-get install -y curl
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        fedora|centos|rhel)
            echo "Using dnf/yum for installation..."
            sudo dnf install -y 'dnf-command(config-manager)'
            sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
            sudo dnf install -y tailscale
            ;;
        arch)
            echo "Using pacman for installation..."
            # Check for AUR helper (yay/paru) or use makepkg
            if command -v yay &> /dev/null; then
                yay -S tailscale
            elif command -v paru &> /dev/null; then
                paru -S tailscale
            else
                echo "No AUR helper found. Please install Tailscale manually from the AUR."
                exit 1
            fi
            ;;
        *)
            echo "Unsupported distribution: $DISTRO. Trying generic script."
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
    esac
    
    # Enable the Tailscale service
    sudo systemctl enable --now tailscaled
}

# Main script execution
echo "--- Tailscale Setup ---"
install_tailscale

# Build the tailscale up command
TS_UP_CMD="sudo tailscale up"

# Ask for authentication method
read -p "How do you want to authenticate? (api/manual): " AUTH_METHOD
if [[ "$AUTH_METHOD" == "api" ]]; then
    read -p "Please enter your Tailscale API auth key: " AUTH_KEY
    if [ -n "$AUTH_KEY" ]; then
        TS_UP_CMD="$TS_UP_CMD --authkey=$AUTH_KEY"
    else
        echo "No API key provided. You will need to run 'sudo tailscale up' manually."
    fi
elif [[ "$AUTH_METHOD" == "manual" ]]; then
    echo "Please run 'sudo tailscale up' manually to authenticate this machine."
else
    echo "Invalid option. You will need to run 'sudo tailscale up' manually."
fi

# Ask about advertising a subnet
read -p "Do you want to advertise a subnet? (yes/no): " ADVERTISE_SUBNET
if [[ "$ADVERTISE_SUBNET" == "yes" ]]; then
    read -p "Please enter the subnet to advertise (e.g., 192.168.1.0/24): " SUBNET
    if [ -n "$SUBNET" ]; then
        TS_UP_CMD="$TS_UP_CMD --advertise-routes=$SUBNET"
    else
        echo "No subnet provided. Skipping advertisement."
    fi
fi

# Execute the command if not manual
if [[ "$AUTH_METHOD" == "api" ]]; then
    echo "Running the following command: $TS_UP_CMD"
    eval $TS_UP_CMD
    echo "Tailscale setup is complete."
else
    echo "Manual setup chosen. Please complete the authentication when ready."
fi

echo "-----------------------"

