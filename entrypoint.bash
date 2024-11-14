#!/bin/bash

# Copyright (c) 2024 Alex Speranza.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Safeguard for incomplete downloads (the entrypoint function is run only when all of its body is already downloaded)
entrypoint()
{
set -euo pipefail

if [ "${USER}" != "root" ] ; then
    >&2 echo "This script must be run as root."
    exit 1
fi

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
    "hyperfine" "hyperfine-bash-completion"
    "stow"
)

TMP_CONFIG_FILE="/tmp/configuration_output"
TMP_CONFIG_RECAP_FILE="/tmp/config_recap"
TMP_STOW_LIST="/tmp/stow-list"

SUDO_USER_GROUP="$(su - "${SUDO_USER}" -c groups)"
SUDO_USER_HOME="/home/${SUDO_USER}"
SUDO_USER_XDG_DATA_HOME="$(su - "${SUDO_USER}" -c env | grep 'XDG_DATA_HOME' || true)"
USER_FONTS_DIR="${SUDO_USER_XDG_DATA_HOME:-"${SUDO_USER_HOME}/.local/share"}/fonts"

FONT_VARIANT="IosevkaTermSS04"
FONT_TARGET_DIR="${USER_FONTS_DIR}/Unknown Vendor/TrueType/${FONT_VARIANT}"

# TODO: calc dialog_height and dialog_width
dialog_height="30"
dialog_width="100"
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

#### START
install_packages "dialog"

#### Configuration form
echo "Starting configuration phase..."
if [ ! -f "${TMP_CONFIG_FILE}" ]; then
    echo "Previous configuration not found. Opening configuration form..."
    exec 3<> "${TMP_CONFIG_FILE}"
    dialog --erase-on-exit \
        --separate-widget "," \
        --output-fd 3 \
        --ok-label "Next" \
        --inputbox "Insert the git name you want to use" "${dialog_height}" "${dialog_width}" "${USER}" \
        --and-widget \
        --inputbox "Insert the git email you want to use" "${dialog_height}" "${dialog_width}" \
        --and-widget \
        --inputbox "Insert your dotfiles repository" "${dialog_height}" "${dialog_width}" "https://github.com/" \
        --and-widget \
        --inputbox "Insert the dotfiles repository ref to clone" "${dialog_height}" "${dialog_width}" "main" \
        --and-widget \
        --inputbox "Insert the path where to clone the dotfile repository" "${dialog_height}" "${dialog_width}"
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
IFS="," read -r git_name git_email dotfiles_repo dotfiles_ref dotfiles_dest rest < <(cat "${TMP_CONFIG_FILE}")
cat <<EOF > "${TMP_CONFIG_RECAP_FILE}"
Git name: ${git_name}
Git email: ${git_email}
Dotfiles repository: ${dotfiles_repo}
Dotfiles repository ref: ${dotfiles_ref}
Dotfiles repository destination: ${dotfiles_dest}
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

echo "Updating system..."
update_system

## Packages
install_packages "${PACKAGES[@]}"

## Sway
install_packages "sway" "swaybg" "swaylock" "swayidle"

## Wezterm
install_packages "wezterm"

## NVIM
install_packages "neovim"

## Git user config
git config --global user.name "${git_name}"
git config --global user.email "${git_email}"

# Font
mkdir -p "${FONT_TARGET_DIR}"
if [ "$(ls "${FONT_TARGET_DIR}")" == "" ] ; then
    git clone --depth 1 "https://github.com/Iosevka-NerdFont/${FONT_VARIANT}.git" "${FONT_TARGET_DIR}"
    chown -R "${SUDO_USER}:${SUDO_USER_GROUP}" "${FONT_TARGET_DIR}"
else
    ( cd "${FONT_TARGET_DIR}" && git pull )
fi
fc-cache "${FONT_TARGET_DIR}/${FONT_VARIANT}"

if [ "$(ls "${dotfiles_dest}")" == "" ] ; then
    git clone --depth 1 --branch "${dotfiles_ref}" "${dotfiles_repo}" "${dotfiles_dest}"
    chown -R "${SUDO_USER}:${SUDO_USER_GROUP}" "${dotfiles_dest}"
else
    ( cd "${dotfiles_dest}" && git pull )
fi

exec 3<> "${TMP_STOW_LIST}"
dialog --erase-on-exit \
    --output-fd 3 \
    --title "Select Stow packages" \
    --checklist "Select the packages to stow from your dotfiles into your home directory:" "${dialog_height}" "${dialog_width}" "20" \
    $(for package in "${dotfiles_dest}"/*; do echo "${package##*/} ${package##*/} off"; done )
dialog_exit_status="$?"
exec 3>&-
echo ""
if [ "$dialog_exit_status" -eq "1" ]; then
    >&2 echo "Dialog cancelled. Exiting script"
    exit 1
fi

stow -d "${dotfiles_dest}" -t "${SUDO_USER_HOME}" --adopt --dotfiles -v $(cat "${TMP_STOW_LIST}")
( cd "${dotfiles_dest}" && git restore . )

# TODO: add Grub theme (BSOL)
} && entrypoint
