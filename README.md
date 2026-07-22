# grubermeister
<img width="1904" height="972" alt="image" src="https://github.com/user-attachments/assets/d8280fc0-a605-448e-80af-185c00f9d259" />

A Jägermeister-inspired GRUB theme.

## Install

### Any Linux distro

```console
$ wget -O - https://raw.githubusercontent.com/N1njaflam1ng0/grubermeister/main/install.sh | bash
```

The script fetches the theme, builds the fonts, copies everything into your
GRUB themes directory, points `/etc/default/grub` at it, and regenerates the
GRUB config. It detects your distro to pick the right paths and update command
(Debian/Ubuntu, Arch, Fedora/RHEL, SUSE, and derivatives).

**Potsdam** (the blackletter menu font) is vendored in the repo, but
**CaskaydiaCove Nerd Font** used for the console and countdown — needs to be
installed on your system beforehand. Without it those fall back to GRUB's
default font; the rest of the theme still works. You also need `grub-mkfont`,
usually shipped in the `grub` / `grub2-tools` package.

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
