# grubermeister

A Jägermeister-inspired GRUB theme: boot entries down the left, stag emblem on
the right — where the emblem **is the icon of whichever entry is highlighted**.

## How the swapping emblem works

GRUB's theme format is fully declarative: no conditionals, no scripting, no
"on selection change" hook. There is no component that renders "the selected
entry's image".

The trick is `make_selected_item_visible()` in GRUB's `gfxmenu/gui_list.c`,
which clamps a `boot_menu`'s `first_shown_index` so the selection is always
on screen. Get a `boot_menu` down to **exactly one visible item** and that
clamp becomes an identity: `first_shown_index == selected_index`, always.

So `theme.txt` declares two `boot_menu` components over the same menu:

1. the real list on the left, with icons disabled;
2. a one-item menu on the right that renders nothing but the icon.

Getting (2) to one item is where it gets ugly, and neither half is obvious.

**Sizing it down to one item does not work.** `list_get_minimal_size()`
hardcodes `num_items = 3`, and `gui_canvas.c` silently raises any smaller
component to that floor — so `height = 256` becomes ~768 and you get three
stacked emblems. The way through is the early return at the top of
`get_num_shown_items()`:

```c
if (item_height + item_vspace <= 0)
  return 1;
```

Setting `item_spacing = -item_height` makes that sum zero and pins the menu
to one item regardless of its bounds.

**Hiding the entry's text does not work by shrinking `width` either** —
minimum width always reserves room for the label (GRUB literally measures the
string `"Typical OS"`). Instead `item_icon_space` pushes the text past the
right screen edge, where the canvas clips it.

Icons resolve to `<theme>/icons/<class>.png`, where `<class>` comes from the
menuentry's `--class` (see `gfxmenu/icon_manager.c`). Hence `icons/nixos.png`,
`icons/windows.png`, and so on.

The background image deliberately has **no cross** — only the halo. The cross
is the overlay.

## NixOS: entries need a `--class`

This is the one part that does not work out of the box. NixOS emits
`menuentry "$name" $options {` with `$options` taken straight from
`boot.loader.grub.entryOptions`, and the default carries no class — so
without this, NixOS entries render no emblem. (os-prober entries already get
`--class windows` etc. for free.)

```nix
boot.loader.grub.entryOptions    = "--unrestricted --class nixos";
boot.loader.grub.subEntryOptions = "--unrestricted --class nixos-generation";
```

Check the current default of `entryOptions` before overriding so you don't
silently drop `--unrestricted`.

## Preview without rebooting

```console
$ nix run .#preview
```

Builds a throwaway ISO with a fake menu (one entry per icon class) and boots
it in QEMU. Edit `theme/theme.txt`, re-run, look. ~10s per iteration.

## Use it

```nix
# flake.nix
inputs.grubermeister.url = "github:<you>/grubermeister";
```

```nix
# configuration
boot.loader.grub.theme = "${inputs.grubermeister.packages.${pkgs.system}.default}";
boot.loader.grub.entryOptions    = "--unrestricted --class nixos";
boot.loader.grub.subEntryOptions = "--unrestricted --class nixos-generation";
```

## Fonts

GRUB reads only bitmap `.pf2` fonts, one file per point size. The build runs
`grub-mkfont` over CaskaydiaCove Nerd Font at 18pt and 24pt. The `-n` name is
what `theme.txt`'s `font = "..."` matches against — it is *not* derived from
the filename, so the two must be kept in sync.

## Gotchas worth knowing before you edit

- **Icons must be truecolour PNG.** GRUB's PNG loader ignores paletted files —
  they render as nothing, silently. ImageMagick will happily emit a paletted
  PNG for simple flat art, so force it: `magick ... PNG32:icon.png`.
- **Font names are not filenames.** `grub-mkfont` composes the internal name as
  `"<-n> <style> <size>"`, and that full string is what `theme.txt` matches.
  `-n "CaskaydiaCove" -s 24` must be referenced as `"CaskaydiaCove Regular 24"`.
  A mismatch silently falls back to the default font.
- **Icon size is `icon_width`/`icon_height`**, independent of `item_height`.

## Placeholder art

`theme/background.png` and `theme/icons/*.png` are generated placeholders —
flat geometry to prove the layout works. Replace them with real art. Icons
want to read at 256px against a busy background, so flat single-colour
silhouettes beat full-colour logos.

If you publish this, an original Jägermeister-*inspired* stag will save you
trademark grief versus tracing the real mark.
