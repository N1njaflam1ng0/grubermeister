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
#
# Potsdam is vendored in-repo so it always resolves; CaskaydiaCove comes from
# the host via fontconfig, so it may legitimately be missing here.
if ! compgen -G "$themedir/*.pf2" >/dev/null; then
  grub-mkfont -s 24 -n "Potsdam" \
    -o "$themedir/potsdam-24.pf2" "$here/fonts/Potsdam.ttf"

  ttf=$(fc-match -f '%{file}' 'CaskaydiaCove Nerd Font:style=Regular' 2>/dev/null || true)
  if [ -n "$ttf" ] && [ -f "$ttf" ]; then
    grub-mkfont -s 18 -n "CaskaydiaCove" \
      -o "$themedir/caskaydia-18.pf2" "$ttf"
  else
    echo "warning: CaskaydiaCove not found via fontconfig; console text will fall back" >&2
  fi
fi

# Fake menu mirroring what install-grub.pl emits, including the --class
# values the emblem menu keys its icons off.
cat >"$work/iso/boot/grub/grub.cfg" <<'EOF'
insmod all_video
insmod gfxterm
insmod png
insmod font
set gfxmode=1920x1080
terminal_output gfxterm
EOF

# theme.txt's `font = "..."` is matched against fonts already in memory --
# grub_font_get() searches only the loaded-font list and never touches disk,
# silently falling back to the first loaded font when the name is absent. So
# every .pf2 has to be loadfont'ed here, exactly as grub-mkconfig's 00_header
# does for a real install. Without this the theme renders in GRUB's built-in
# font and nothing says why.
for pf2 in "$themedir"/*.pf2; do
  [ -e "$pf2" ] || continue
  echo "loadfont /boot/grub/themes/grubermeister/${pf2##*/}"
done >>"$work/iso/boot/grub/grub.cfg"

cat >>"$work/iso/boot/grub/grub.cfg" <<'EOF'

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
