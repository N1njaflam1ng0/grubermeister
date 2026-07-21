#!/usr/bin/env bash
# Build a throwaway ISO carrying the theme and boot it in QEMU.
# Iteration loop is ~10s, so you never have to reboot to see a change.
#
#   nix run .#preview     previews the built derivation (fonts included)
#   ./preview.sh          previews the source tree, inside `nix develop`
#
# Extra args are passed through to QEMU, e.g. `./preview.sh -display none`.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
theme_src="${GRUBERMEISTER_THEME:-$here/theme}"

if [ ! -f "$theme_src/theme.txt" ]; then
  echo "no theme.txt under $theme_src" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

themedir="$work/iso/boot/grub/themes/grubermeister"
mkdir -p "$themedir"
cp -r "$theme_src"/* "$themedir/"
chmod -R u+w "$themedir"

# When previewing the source tree there are no .pf2 files yet, so build them
# the same way the derivation does. grub-mkfont composes the internal name as
# "<-n> <style> <size>", which is what theme.txt matches against.
if ! compgen -G "$themedir/*.pf2" >/dev/null; then
  ttf=$(fc-match -f '%{file}' 'CaskaydiaCove Nerd Font:style=Regular' 2>/dev/null || true)
  if [ -n "$ttf" ] && [ -f "$ttf" ]; then
    for size in 18 24; do
      grub-mkfont -s "$size" -n "CaskaydiaCove" \
        -o "$themedir/caskaydia-$size.pf2" "$ttf"
    done
  else
    echo "warning: CaskaydiaCove not found via fontconfig; text will fall back" >&2
  fi
fi

# Fake menu mirroring what install-grub.pl emits, including the --class
# values the emblem menu keys its icons off.
cat >"$work/iso/boot/grub/grub.cfg" <<'EOF'
insmod all_video
insmod gfxterm
insmod png
set gfxmode=1920x1080
terminal_output gfxterm

set theme=/boot/grub/themes/grubermeister/theme.txt
export theme
set timeout=300

menuentry "NixOS" --class nixos {
  echo "boot nixos"
}

menuentry "Windows 11" --class windows {
  echo "boot windows"
}

submenu "NixOS - All configurations" --class submenu {
  menuentry "NixOS - Configuration 42" --class nixos-generation {
    echo "boot gen 42"
  }
}
EOF

grub-mkrescue -o "$work/preview.iso" "$work/iso" >/dev/null 2>&1

exec qemu-system-x86_64 \
  -m 512 \
  -vga std \
  -cdrom "$work/preview.iso" \
  "$@"
