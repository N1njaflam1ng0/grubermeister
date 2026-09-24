#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

GRUB_THEME='grubermeister'
GRUB_REPO='N1njaflam1ng0/grubermeister'

# Check dependencies
INSTALLER_DEPENDENCIES=(
    'awk'
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

# background.png is a single fixed-size asset (1619x971), and theme.txt's
# other pixel-based values (icon box size, item height/spacing, font point
# sizes, absolute offsets like "top = 50%-400") were tuned against a
# 1904x972 reference canvas -- the size baked into the README screenshot.
# On any screen far from that, GRUB stretches/crops the fixed background to
# fit and the fixed-pixel layout stays reference-sized, reading too small
# and (for the icon "cross" emblem block, which relies on a large
# item_icon_space to shove its label text off-screen) visibly mispositioned.
#
# Detect the real screen resolution up front -- it drives the background
# resize, the font point sizes (built below), and the theme.txt layout
# scaling (applied further down), so all three stay in sync.
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

# Reference canvas theme.txt's pixel values were tuned against, and the
# scale factor to go from it to the detected resolution. Geometric mean of
# the two axis ratios: adapts to the screen's aspect ratio without
# distorting the (square) icon boxes by favouring one axis over the other.
REF_WIDTH=1904
REF_HEIGHT=972
POTSDAM_SIZE=24
CASKAYDIA_SIZE=18
SCALE=1

if [[ -n "$DETECTED_WIDTH" && -n "$DETECTED_HEIGHT" ]]; then
    SCALE=$(awk -v w="$DETECTED_WIDTH" -v h="$DETECTED_HEIGHT" -v rw="$REF_WIDTH" -v rh="$REF_HEIGHT" \
        'BEGIN { printf "%.6f", sqrt((w / rw) * (h / rh)) }')
    POTSDAM_SIZE=$(awk -v s="$SCALE" 'BEGIN { printf "%d", (24 * s) + 0.5 }')
    CASKAYDIA_SIZE=$(awk -v s="$SCALE" 'BEGIN { printf "%d", (18 * s) + 0.5 }')
fi

# Rounds n*SCALE to the nearest integer, rounding negatives away from zero.
scale_int() {
    awk -v s="$SCALE" -v n="$1" 'BEGIN { v = n * s; printf "%d", (v < 0 ? v - 0.5 : v + 0.5) }'
}

# The theme files (theme.txt, background.png, icons/) live under theme/ in the
# repo; that is what gets copied into place. Build the fonts into it too.
#
# GRUB reads only bitmap .pf2 fonts, one file per point size, and none are
# committed to the repo. grub-mkfont composes the internal font name as
# "<-n> <style> <size>", which is what theme.txt matches against -- so
# whatever size is built here must stay in sync with theme.txt's font
# references (handled below, alongside the rest of the layout scaling).
echo "Building Potsdam font (menu entries) at ${POTSDAM_SIZE}pt"
"$GRUB_MKFONT" -s "$POTSDAM_SIZE" -n "Potsdam" -o "theme/potsdam-${POTSDAM_SIZE}.pf2" fonts/Potsdam.ttf

echo "Building CaskaydiaCove font (console and countdown) at ${CASKAYDIA_SIZE}pt"
CASKAYDIA_TTF=$(fc-match -f '%{file}' 'CaskaydiaCove Nerd Font:style=Regular' 2>/dev/null || true)
if [[ -n "$CASKAYDIA_TTF" && -f "$CASKAYDIA_TTF" ]]; then
    "$GRUB_MKFONT" -s "$CASKAYDIA_SIZE" -n "CaskaydiaCove" -o "theme/caskaydia-${CASKAYDIA_SIZE}.pf2" "$CASKAYDIA_TTF"
else
    echo >&2 'warning: CaskaydiaCove Nerd Font not found via fontconfig;'
    echo >&2 '         console and countdown text will fall back to GRUB defaults.'
    echo >&2 '         Install CaskaydiaCove Nerd Font and re-run to fix.'
fi

if [[ -n "$DETECTED_WIDTH" && -n "$DETECTED_HEIGHT" ]]; then
    if command -v convert > /dev/null 2>&1; then
        echo "Detected screen resolution ${DETECTED_WIDTH}x${DETECTED_HEIGHT}; resizing background and scaling theme layout to match"
        convert theme/background.png -resize "${DETECTED_WIDTH}x${DETECTED_HEIGHT}^" \
            -gravity center -extent "${DETECTED_WIDTH}x${DETECTED_HEIGHT}" theme/background.png

        # Each old value below is unique to its field in the shipped
        # theme.txt (verified against the current layout), so a literal
        # substitution is unambiguous without needing to track which
        # boot_menu block a line belongs to.
        sed -i \
            -e "s/Potsdam Regular 24/Potsdam Regular ${POTSDAM_SIZE}/g" \
            -e "s/CaskaydiaCove Regular 18/CaskaydiaCove Regular ${CASKAYDIA_SIZE}/g" \
            -e "s/top = 50%-400/top = 50%-$(scale_int 400)/" \
            -e "s/height = 360/height = $(scale_int 360)/" \
            -e "s/item_height = 44/item_height = $(scale_int 44)/" \
            -e "s/item_spacing = 12/item_spacing = $(scale_int 12)/" \
            -e "s/icon_width = 24/icon_width = $(scale_int 24)/" \
            -e "s/icon_height = 24/icon_height = $(scale_int 24)/" \
            -e "s/item_icon_space = 30/item_icon_space = $(scale_int 30)/" \
            -e "s/width = 86/width = $(scale_int 86)/" \
            -e "s/height = 86/height = $(scale_int 86)/" \
            -e "s/icon_width = 86/icon_width = $(scale_int 86)/" \
            -e "s/icon_height = 86/icon_height = $(scale_int 86)/" \
            -e "s/item_height = 86/item_height = $(scale_int 86)/" \
            -e "s/item_spacing = -86/item_spacing = $(scale_int -86)/" \
            -e "s/item_icon_space = 1028/item_icon_space = $(scale_int 1028)/" \
            -e "s/top = 100%-64/top = 100%-$(scale_int 64)/" \
            -e "s/height = 28/height = $(scale_int 28)/" \
            theme/theme.txt
    else
        echo >&2 "warning: 'convert' (ImageMagick) not found; background.png and the theme"
        echo >&2 "         layout will stay at their bundled 1619x971 / 1904x972 sizing and"
        echo >&2 "         may look soft, oddly cropped, or too small on this screen."
        echo >&2 "         Install imagemagick and re-run to fix."
        DETECTED_WIDTH=''
        DETECTED_HEIGHT=''
    fi
else
    echo >&2 'warning: could not detect screen resolution; leaving GRUB_GFXMODE as-is,'
    echo >&2 '         and background.png/theme.txt at their bundled reference sizing.'
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
