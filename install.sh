#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

GRUB_THEME='grubermeister'
GRUB_REPO='N1njaflam1ng0/grubermeister'

# Check dependencies
INSTALLER_DEPENDENCIES=(
    'cp'
    'fc-match'
    'mkdir'
    'mktemp'
    'sed'
    'sudo'
    'tar'
    'tee'
    'wget'
)

for i in "${INSTALLER_DEPENDENCIES[@]}"; do
    command -v "$i" > /dev/null 2>&1 || {
        echo >&2 "'$i' command is required, but not available. Aborting.";
        exit 1;
    }
done

# GRUB's tools are prefixed `grub-` on most distros but `grub2-` on
# Fedora/RHEL/SUSE. Pick whichever mkfont is present.
if command -v grub-mkfont > /dev/null 2>&1; then
    GRUB_MKFONT='grub-mkfont'
elif command -v grub2-mkfont > /dev/null 2>&1; then
    GRUB_MKFONT='grub2-mkfont'
else
    echo >&2 "'grub-mkfont' (or 'grub2-mkfont') is required, but not available. Aborting."
    echo >&2 "It usually ships in the 'grub' / 'grub2-tools' package."
    exit 1
fi

# Change to temporary directory
cd "$(mktemp -d)"

# Pre-authorise sudo
sudo echo

echo 'Fetching and unpacking theme'
wget -O - "https://github.com/${GRUB_REPO}/archive/main.tar.gz" | tar -xzf - --strip-components=1

# The theme files (theme.txt, background.png, icons/) live under theme/ in the
# repo; that is what gets copied into place. Build the fonts into it too.
#
# GRUB reads only bitmap .pf2 fonts, one file per point size, and none are
# committed to the repo. grub-mkfont composes the internal font name as
# "<-n> <style> <size>", which is what theme.txt matches against -- so
# "Potsdam Regular 24" and "CaskaydiaCove Regular 18" here must stay in sync
# with theme.txt if you change fonts.
echo 'Building Potsdam font (menu entries)'
"$GRUB_MKFONT" -s 24 -n "Potsdam" -o theme/potsdam-24.pf2 fonts/Potsdam.ttf

echo 'Building CaskaydiaCove font (console and countdown)'
CASKAYDIA_TTF=$(fc-match -f '%{file}' 'CaskaydiaCove Nerd Font:style=Regular' 2>/dev/null || true)
if [[ -n "$CASKAYDIA_TTF" && -f "$CASKAYDIA_TTF" ]]; then
    "$GRUB_MKFONT" -s 18 -n "CaskaydiaCove" -o theme/caskaydia-18.pf2 "$CASKAYDIA_TTF"
else
    echo >&2 'warning: CaskaydiaCove Nerd Font not found via fontconfig;'
    echo >&2 '         console and countdown text will fall back to GRUB defaults.'
    echo >&2 '         Install CaskaydiaCove Nerd Font and re-run to fix.'
fi

# background.png is a single fixed-size asset (1619x971). theme.txt scales it
# with desktop-image-scale-method "crop", so on a screen of a different
# resolution GRUB stretches/crops that fixed image to fit -- soft or
# oddly-cropped on anything far from 1619x971. Detect the real screen
# resolution and resize the background to match before it's installed, and
# pin GRUB_GFXMODE to the same value so the video mode GRUB picks and the
# image resolution always agree instead of relying on GRUB_GFXMODE=auto
# picking whatever the firmware happens to prefer.
#
# Detection prefers xrandr's connected/preferred output (works under X and
# Xwayland); falls back to the DRM sysfs interface for a bare TTY or a
# Wayland session without an X server.
DETECTED_WIDTH=''
DETECTED_HEIGHT=''

if command -v xrandr > /dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    read -r DETECTED_WIDTH DETECTED_HEIGHT < <(
        xrandr --query | awk '
            /^[A-Za-z0-9-]+ connected/ { in_output=1; next }
            /^[A-Za-z0-9-]+ disconnected/ { in_output=0; next }
            in_output && /\+/ {
                split($1, r, "x")
                print r[1], r[2]
                exit
            }
        '
    ) || true
fi

if [[ -z "$DETECTED_WIDTH" || -z "$DETECTED_HEIGHT" ]]; then
    for status in /sys/class/drm/*/status; do
        [[ -e "$status" ]] || continue
        [[ "$(cat "$status")" == "connected" ]] || continue
        modes="${status%status}modes"
        [[ -e "$modes" ]] || continue
        read -r DETECTED_WIDTH DETECTED_HEIGHT < <(head -n1 "$modes" | tr 'x' ' ') || true
        [[ -n "$DETECTED_WIDTH" && -n "$DETECTED_HEIGHT" ]] && break
    done
fi

if [[ -n "$DETECTED_WIDTH" && -n "$DETECTED_HEIGHT" ]]; then
    if command -v convert > /dev/null 2>&1; then
        echo "Detected screen resolution ${DETECTED_WIDTH}x${DETECTED_HEIGHT}; resizing background to match"
        convert theme/background.png -resize "${DETECTED_WIDTH}x${DETECTED_HEIGHT}^" \
            -gravity center -extent "${DETECTED_WIDTH}x${DETECTED_HEIGHT}" theme/background.png
    else
        echo >&2 "warning: 'convert' (ImageMagick) not found; background.png will stay at its"
        echo >&2 "         bundled 1619x971 resolution and may look soft or oddly cropped."
        echo >&2 "         Install imagemagick and re-run to fix."
        DETECTED_WIDTH=''
        DETECTED_HEIGHT=''
    fi
else
    echo >&2 'warning: could not detect screen resolution; leaving GRUB_GFXMODE as-is'
    echo >&2 '         and background.png at its bundled 1619x971 resolution.'
fi

# Detect distro and set GRUB location and update method
GRUB_DIR='grub'
UPDATE_GRUB=''
BOOT_MODE='legacy'

if [[ -d /boot/efi && -d /sys/firmware/efi ]]; then
    BOOT_MODE='UEFI'
fi

echo "Boot mode: ${BOOT_MODE}"

if [[ -e /etc/os-release ]]; then

    ID=""
    ID_LIKE=""
    source /etc/os-release

    if [[ "$ID" =~ (debian|ubuntu|solus|void) || \
          "$ID_LIKE" =~ (debian|ubuntu|void) ]]; then

        UPDATE_GRUB='update-grub'

    elif [[ "$ID" =~ (arch|gentoo|artix) || \
            "$ID_LIKE" =~ (^arch|gentoo|^artix) ]]; then

        UPDATE_GRUB="grub-mkconfig -o /boot/${GRUB_DIR}/grub.cfg"

    elif [[ "$ID" =~ (centos|fedora|opensuse) || \
            "$ID_LIKE" =~ (fedora|rhel|suse) ]]; then

        GRUB_DIR='grub2'
        UPDATE_GRUB="grub2-mkconfig -o /boot/${GRUB_DIR}/grub.cfg"

        # BLS entries have 'kernel' class, copy corresponding icon
        if [[ -d /boot/loader/entries && -e theme/icons/${ID}.png ]]; then
            cp theme/icons/${ID}.png theme/icons/kernel.png
        fi
    fi
fi

echo 'Creating GRUB themes directory'
sudo mkdir -p /boot/${GRUB_DIR}/themes/${GRUB_THEME}

echo 'Copying theme to GRUB themes directory'
sudo cp -r theme/* /boot/${GRUB_DIR}/themes/${GRUB_THEME}

echo 'Removing other themes from GRUB config'
sudo sed -i '/^GRUB_THEME=/d' /etc/default/grub

echo 'Making sure GRUB uses graphical output'
sudo sed -i 's/^\(GRUB_TERMINAL\w*=.*\)/#\1/' /etc/default/grub

echo 'Removing empty lines at the end of GRUB config' # optional
sudo sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' /etc/default/grub

echo 'Adding new line to GRUB config just in case' # optional
echo | sudo tee -a /etc/default/grub

echo 'Adding theme to GRUB config'
echo "GRUB_THEME=/boot/${GRUB_DIR}/themes/${GRUB_THEME}/theme.txt" | sudo tee -a /etc/default/grub

if [[ -n "$DETECTED_WIDTH" && -n "$DETECTED_HEIGHT" ]]; then
    echo 'Pinning GRUB_GFXMODE to the detected screen resolution'
    sudo sed -i '/^GRUB_GFXMODE=/d' /etc/default/grub
    echo "GRUB_GFXMODE=${DETECTED_WIDTH}x${DETECTED_HEIGHT},auto" | sudo tee -a /etc/default/grub
fi

echo 'Removing theme installation files'
rm -rf "$PWD"
cd

echo 'Updating GRUB'
if [[ $UPDATE_GRUB ]]; then
    eval sudo "$UPDATE_GRUB"
else
    cat << '    EOF'
    --------------------------------------------------------------------------------
    Cannot detect your distro, you will need to run `grub-mkconfig` (as root) manually.

    Common ways:
    - Debian, Ubuntu, Solus and derivatives: `update-grub` or `grub-mkconfig -o /boot/grub/grub.cfg`
    - RHEL, CentOS, Fedora, SUSE and derivatives: `grub2-mkconfig -o /boot/grub2/grub.cfg`
    - Arch, Artix, Gentoo and derivatives: `grub-mkconfig -o /boot/grub/grub.cfg`
    --------------------------------------------------------------------------------
    EOF
fi
