#!/bin/sh -e

. ../../common-script.sh

gitpath="$HOME/.local/share/mybash"

installDepend() {
    if ! command_exists bash bash-completion tar bat tree unzip fontconfig git; then
        printf "%b\n" "${YELLOW}Installing Bash...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm bash bash-completion tar bat tree unzip fontconfig git
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add bash bash-completion tar bat tree unzip fontconfig git
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy bash bash-completion tar bat tree unzip fontconfig git
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y bash bash-completion tar bat tree unzip fontconfig git
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" install -y bash bash-completion tar bat tree unzip fontconfig git
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y bash bash-completion tar bat tree unzip fontconfig git
                ;;
        esac
    fi
}

cloneMyBash() {
    # Check if the dir exists before attempting to clone into it.
    if [ -d "$gitpath" ]; then
        if [ -d "$gitpath/.git" ]; then
            printf "%b\n" "${YELLOW}Updating existing mybash repository...${RC}"
            cd "$gitpath" && git pull
        else
            printf "%b\n" "${YELLOW}Directory exists but is not a git repo. Backing up and cloning...${RC}"
            mv "$gitpath" "${gitpath}.bak.$(date +%s)"
            cd "$HOME" && git clone https://github.com/rahuljangirwork/bash-rahul.git "$gitpath"
        fi
    else
        mkdir -p "$HOME/.local/share" # Only create the dir if it doesn't exist.
        cd "$HOME" && git clone https://github.com/rahuljangirwork/bash-rahul.git "$gitpath"
    fi
}

installFont() {
    # Check to see if the MesloLGS Nerd Font is installed (Change this to whatever font you would like)
    FONT_NAME="MesloLGS Nerd Font Mono"
    if fc-list :family | grep -iq "$FONT_NAME"; then
        printf "%b\n" "${GREEN}Font '$FONT_NAME' is installed.${RC}"
    else
        printf "%b\n" "${YELLOW}Installing font '$FONT_NAME'${RC}"
        # Change this URL to correspond with the correct font
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
        FONT_DIR="$HOME/.local/share/fonts"
        TEMP_DIR=$(mktemp -d)
        curl -sSLo "$TEMP_DIR"/"${FONT_NAME}".zip "$FONT_URL"
        unzip "$TEMP_DIR"/"${FONT_NAME}".zip -d "$TEMP_DIR"
        mkdir -p "$FONT_DIR"/"$FONT_NAME"
        mv "${TEMP_DIR}"/*.ttf "$FONT_DIR"/"$FONT_NAME"
        fc-cache -fv
        rm -rf "${TEMP_DIR}"
        printf "%b\n" "${GREEN}'$FONT_NAME' installed successfully.${RC}"
    fi
}

installStarshipAndFzf() {
    if command_exists starship; then
        printf "%b\n" "${GREEN}Starship already installed${RC}"
        return
    fi

    if ! curl -sSL https://starship.rs/install.sh | sh; then
        printf "%b\n" "${RED}Something went wrong during starship install!${RC}"
        exit 1
    fi
    if command_exists fzf; then
        printf "%b\n" "${GREEN}Fzf already installed${RC}"
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        "$ESCALATION_TOOL" ~/.fzf/install
    fi
}

installZoxide() {
    if command_exists zoxide; then
        printf "%b\n" "${GREEN}Zoxide already installed${RC}"
        return
    fi

    if ! curl -sSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        printf "%b\n" "${RED}Something went wrong during zoxide install!${RC}"
        exit 1
    fi
}

installFastfetch() {
    if ! command_exists fastfetch; then
        printf "%b\n" "${YELLOW}Installing Fastfetch...${RC}"
        case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm fastfetch
            ;;
        apt-get | nala)
            case "$ARCH" in
                x86_64)
                    DEB_FILE="fastfetch-linux-amd64.deb"
                    ;;
                aarch64)
                    DEB_FILE="fastfetch-linux-aarch64.deb"
                    ;;
            esac
            curl -sSLo "/tmp/fastfetch.deb" "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$DEB_FILE"
            "$ESCALATION_TOOL" "$PACKAGER" install -y /tmp/fastfetch.deb
            rm /tmp/fastfetch.deb
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add fastfetch
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy fastfetch
            ;;
        *)
            "$ESCALATION_TOOL" "$PACKAGER" install -y fastfetch
            ;;
        esac
    else
        printf "%b\n" "${GREEN}Fastfetch is already installed.${RC}"
    fi
}

setupFastfetchConfig() {
    printf "%b\n" "${YELLOW}Copying Fastfetch config files...${RC}"
    if [ -d "${HOME}/.config/fastfetch" ] && [ ! -d "${HOME}/.config/fastfetch-bak" ]; then
        cp -r "${HOME}/.config/fastfetch" "${HOME}/.config/fastfetch-bak"
    fi
    mkdir -p "${HOME}/.config/fastfetch/"
    if [ -f "$gitpath/config.jsonc" ]; then
        ln -sf "$gitpath/config.jsonc" "${HOME}/.config/fastfetch/config.jsonc"
    else
         curl -sSLo "${HOME}/.config/fastfetch/config.jsonc" https://raw.githubusercontent.com/rahuljangirwork/bash-rahul/main/config.jsonc
    fi
}


linkConfig() {
    OLD_BASHRC="$HOME/.bashrc"
    if [ -e "$OLD_BASHRC" ] && [ ! -e "$HOME/.bashrc.bak" ]; then
        printf "%b\n" "${YELLOW}Moving old bash config file to $HOME/.bashrc.bak${RC}"
        if ! mv "$OLD_BASHRC" "$HOME/.bashrc.bak"; then
            printf "%b\n" "${RED}Can't move the old bash config file!${RC}"
            exit 1
        fi
    fi

    printf "%b\n" "${YELLOW}Linking new bash config file...${RC}"
    
    # Copy custom starship.toml if it exists locally
    if [ -f "starship.toml" ]; then
         printf "%b\n" "${YELLOW}Copying custom starship.toml theme...${RC}"
         cp "starship.toml" "$gitpath/starship.toml"
    fi

    ln -svf "$gitpath/.bashrc" "$HOME/.bashrc" || {
        printf "%b\n" "${RED}Failed to create symbolic link for .bashrc${RC}"
        exit 1
    }
    ln -svf "$gitpath/starship.toml" "$HOME/.config/starship.toml" || {
        printf "%b\n" "${RED}Failed to create symbolic link for starship.toml${RC}"
        exit 1
    }
    printf "%b\n" "${GREEN}Done! restart your shell to see the changes.${RC}"
}

uninstall() {
    printf "%b\n" "${YELLOW}Uninstalling MyBash and components...${RC}"

    # Remove fastfetch
    if command_exists fastfetch; then
        printf "%b\n" "${YELLOW}Removing fastfetch...${RC}"
        case "$PACKAGER" in
            pacman) "$ESCALATION_TOOL" "$PACKAGER" -Rns --noconfirm fastfetch ;;
            apt-get|nala) "$ESCALATION_TOOL" "$PACKAGER" remove -y fastfetch ;;
            apk) "$ESCALATION_TOOL" "$PACKAGER" del fastfetch ;;
            xbps-install) "$ESCALATION_TOOL" xbps-remove -Ry fastfetch ;;
            dnf|zypper) "$ESCALATION_TOOL" "$PACKAGER" remove -y fastfetch ;;
            *) printf "%b\n" "${RED}Unable to remove fastfetch automatically.${RC}" ;;
        esac
    fi
    rm -rf "${HOME}/.config/fastfetch"

    # Restore bashrc
    if [ -e "$HOME/.bashrc.bak" ]; then
        printf "%b\n" "${YELLOW}Restoring backup .bashrc...${RC}"
        mv "$HOME/.bashrc.bak" "$HOME/.bashrc"
    else
        printf "%b\n" "${YELLOW}No backup .bashrc found. Removing link...${RC}"
        rm "$HOME/.bashrc"
    fi

    # Remove config links/files
    rm "$HOME/.config/starship.toml"
    
    # Remove repo
    if [ -d "$gitpath" ]; then
        printf "%b\n" "${YELLOW}Removing mybash repository...${RC}"
        rm -rf "$gitpath"
    fi

    printf "%b\n" "${GREEN}Uninstallation complete.${RC}"
}

checkEnv
checkEscalationTool

if [ "$1" = "uninstall" ]; then
    uninstall
else
    installDepend
    cloneMyBash
    installFont
    installStarshipAndFzf
    installZoxide
    installFastfetch
    setupFastfetchConfig
    linkConfig
fi
