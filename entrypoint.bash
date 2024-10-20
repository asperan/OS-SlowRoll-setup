#!/bin/bash

# Copyright (c) 2024 Alex Speranza.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Safeguard for incomplete downloads (the entrypoint function is run only when all of its body is already downloaded)
entrypoint()
{
set -euo pipefail

#### VARIABLES

PACKAGES=(
    ## CLI utilities (Git, bat, delta, btop, eza, fzf, ripgrep, nnn, yq, dialog)
    "git"
    "btop"
    "bat" "bat-bash-completion"
    "git-delta"
    "eza" "eza-bash-completion"
    "fzf" "fzf-bash-completion"
    "ripgrep" "ripgrep-bash-completion"
    "nnn" "nnn-bash-completion"
    "yq" "yq-bash-completion"
    "dialog"
    "stow"
)

USER_FONTS_DIR="${XDG_DATA_HOME:-"${HOME}/.local/share"}/fonts"
FONT_VARIANT="IosevkaTermSS04"
FONT_TARGET_DIR="${USER_FONTS_DIR}/Unknown Vendor/TrueType/${FONT_VARIANT}"
TMP_CONFIG_FILE="/tmp/inputbox_output"
TMP_CONFIG_RECAP_FILE="/tmp/config_recap"

#### HELPERS

update_system()
{
    zypper dist-upgrade -y
}

# $@: the packages to install
install_packages()
{
    zypper install --no-confirm --no-recommends "$@"
}

# $1: URL
# $2: target folder
clone_git_repository() {
    mkdir -p "$2"
    git clone "$1" "$2"
}

#### Configuration form
echo "Starting configuration phase..."
if [ ! -f "${TMP_CONFIG_FILE}" ]; then
    echo "Previous configuration not found. Opening configuration form..."
    # TODO: calc dialog_height and dialog_width
    dialog_height="30"
    dialog_width="100"
    exec 3<> "${TMP_CONFIG_FILE}"
    dialog --erase-on-exit \
        --separate-widget "," \
        --output-fd 3 \
        --ok-label "Next" \
        --inputbox "Insert the git name you want to use" "${dialog_height}" "${dialog_width}" \
        --and-widget \
        --inputbox "Insert the git email you want to use" "${dialog_height}" "${dialog_width}"
    dialog_exit_status="$?"
    exec 3>&-
    echo "" >> "${TMP_CONFIG_FILE}"
    echo ""
    if [ "$dialog_exit_status" -eq "1" ]; then
        >&2 echo "Dialog cancelled. Exiting script"
        exit 1
    fi
else
    echo "Previous configuration found. Configuration form skipped."
fi

#### Confirmation form
echo "Parsing configuration..."
IFS="," read -r git_name git_email rest < <(cat "${TMP_CONFIG_FILE}")
cat <<EOF > "${TMP_CONFIG_RECAP_FILE}"
Git name: ${git_name}
Git email: ${git_email}
EOF
confirmation_dialog_height="100"
confirmation_dialog_width="100"
dialog --title "Confirm configuration?" --yesno "$(cat "${TMP_CONFIG_RECAP_FILE}")" "${confirmation_dialog_height}" "${confirmation_dialog_width}"
confirmation_exit_code="$?"
echo ""
case "${confirmation_exit_code}" in
    1) echo "Refused configuration, removing temp config file and aborting installation."
       rm "${TMP_CONFIG_FILE}"
       exit 1
    ;;
    -1) echo "Exited from dialog, keeping temp config file and aborting installation."
        exit 1
    ;;
    *)
    ;;
esac
echo "Configuration confirmed."
rm "${TMP_CONFIG_RECAP_FILE}"
#### START SETUP
echo "Starting setup phase..."
update_system

## Packages
install_packages "${PACKAGES[@]}"

## Sway
install_packages "sway" "swaybg" "swaylock" "swayidle"

## Wezterm
install_packages "wezterm"

## NVIM
install_packages "neovim"

# Font
mkdir -p "${FONT_TARGET_DIR}"
eval $(curl -fsSL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/asperan/nerdfont-iosevka/contents/${FONT_VARIANT} | jq -r 'map({"name": .name, "download_url": .download_url })[] | "curl -fsSL -o \"${FONT_TARGET_DIR}/" + .name + "\" \"" + .download_url + "\" ;"')

## Git user config
git config --global user.name "${CONFIG_GIT_USER_NAME}"
git config --global user.email "${CONFIG_GIT_USER_EMAIL}"

# TODO: ask for stow repository, clone it somewhere (ask for it?) and stow all packages
# Stow target is always "${HOME}"

# TODO: add Grub theme (BSOL)
} && entrypoint
