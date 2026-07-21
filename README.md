# grubermeister

A Jägermeister-inspired GRUB theme: boot entries down the left, stag emblem on
the right — where the emblem **is the icon of whichever entry is highlighted**.

Works on any distro's GRUB 2. The theme format is fully declarative, so there
is nothing distro-specific in `theme.txt` itself; the only thing that differs
between distros is how entries get their `--class`, which is what selects the
emblem.

## Install

### Any Linux distro

**1. Build the fonts.** GRUB reads only bitmap `.pf2` fonts, one file per point
size, and they are *not* committed to this repo. Skipping this step is the most
common way to get a broken-looking theme: `theme.txt` asks for a font name that
does not exist, GRUB silently falls back to its default, and the layout comes
out wrong for reasons that look unrelated.

You need CaskaydiaCove Nerd Font installed, plus `grub-mkfont` (usually in the
`grub` package):

```console
$ ttf=$(fc-match -f '%{file}' 'CaskaydiaCove Nerd Font:style=Regular')
$ for size in 18 24; do
      grub-mkfont -s "$size" -n "CaskaydiaCove" -o "theme/caskaydia-$size.pf2" "$ttf"
  done
```

The `-n` name is what `theme.txt` matches against, and it is *not* derived from
the filename — `grub-mkfont` composes the internal name as
`"<-n> <style> <size>"`, so `-n "CaskaydiaCove" -s 24` is referenced as
`"CaskaydiaCove Regular 24"`. Keep the two in sync if you change fonts.

**2. Copy the theme into place.**

```console
# cp -r theme /boot/grub/themes/grubermeister
```

On Fedora/RHEL that path is `/boot/grub2/themes/` instead.

**3. Point GRUB at it** in `/etc/default/grub`:

```sh
GRUB_THEME=/boot/grub/themes/grubermeister/theme.txt
GRUB_GFXMODE=1920x1080
```

`theme.txt` mixes percentages with fixed pixel sizes, and the emblem is 256px
square, so it is laid out for a reasonably large framebuffer. If your firmware
cannot deliver the mode you ask for, GRUB drops to something like 1024x768 or
640x480 and the emblem can run off the right edge. To see what a given machine
actually offers, press `c` at the boot menu and run `videoinfo`.

**4. Regenerate the config.**

```console
# grub-mkconfig -o /boot/grub/grub.cfg
```

Debian/Ubuntu wrap this as `update-grub`; Fedora/RHEL write to
`/boot/grub2/grub.cfg`.

#### Getting the right emblem

Icons resolve to `theme/icons/<class>.png`, where `<class>` comes from the
menuentry's `--class`. An entry can carry several, and GRUB tries them **in
order, first match wins** (`grub-core/gfxmenu/icon_manager.c`).

`grub-mkconfig` emits `--class $distributor --class gnu-linux --class gnu
--class os`, so on Arch your entries are `--class arch --class gnu-linux ...`.
That is why this repo ships a generic `icons/gnu-linux.png` — every distro's
entries reach it, so you get an emblem out of the box. To give your distro its
own, drop in `icons/arch.png` (or `icons/debian.png`, …) and it wins
automatically, being earlier in the list.

Windows and other os-prober entries already get `--class windows` and friends
for free.

Icons must be **truecolour** PNG — GRUB's PNG loader ignores paletted files and
renders nothing, silently. ImageMagick will happily emit a paletted PNG for
simple flat art, so force it:

```console
$ magick ... PNG32:icons/arch.png
```

They want to read at 256px against a busy background, so flat single-colour
silhouettes beat full-colour logos.

### NixOS

The flake builds the fonts for you, so there is no manual `grub-mkfont` step.

```nix
# flake.nix
inputs.grubermeister.url = "github:N1njaflam1ng0/grubermeister";
```

```nix
# configuration
boot.loader.grub.theme = "${inputs.grubermeister.packages.${pkgs.system}.default}";

boot.loader.grub.entryOptions    = "--unrestricted --class nixos";
boot.loader.grub.subEntryOptions = "--unrestricted --class nixos-generation";
```

The `entryOptions` lines are required, and are the one part that does not work
out of the box. NixOS emits `menuentry "$name" $options {` with `$options`
taken straight from `entryOptions`, and the default carries no class at all —
so without these, NixOS entries render no emblem. (os-prober entries still get
`--class windows` etc. for free.)

Check the current default of `entryOptions` before overriding so you don't
silently drop `--unrestricted`.

## Preview without rebooting

```console
$ nix run .#preview
```

Builds a throwaway ISO with a fake menu — one entry per icon class — and boots
it in QEMU. Edit `theme/theme.txt`, re-run, look. ~10s per iteration. Extra
arguments are passed through to QEMU, e.g. `nix run .#preview -- -display none`.

Nix only sees git-tracked files, so a new `theme/icons/foo.png` you haven't
`git add`ed will not be in the ISO — it renders nothing, which looks exactly
like the paletted-PNG failure above.

To iterate against the working tree instead, including untracked files:

```console
$ nix develop
$ ./preview.sh
```

This reads `theme/` live and builds the fonts via fontconfig rather than the
derivation, so it needs CaskaydiaCove installed on the host.

Without Nix, `preview.sh` is portable bash — it needs `grub-mkrescue`,
`xorriso`, `mtools`, `qemu`, and `fc-match` on `PATH`. Note that it boots via
BIOS rather than UEFI, so it is not exercising the firmware path most modern
machines use; rendering is identical in practice, but it is not proof.

## Placeholder art

`theme/background.png` and `theme/icons/*.png` are generated placeholders —
flat geometry to prove the layout works. Replace them with real art. The
background deliberately has **no cross**: that is the emblem overlay.

If you publish this, an original Jägermeister-*inspired* stag will save you
trademark grief versus tracing the real mark.
