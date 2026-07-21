{
  description = "grubermeister — a Jägermeister-inspired GRUB theme";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: {
      default = self.packages.${pkgs.system}.grubermeister;

      grubermeister = pkgs.stdenvNoCC.mkDerivation {
        pname = "grubermeister";
        version = "0.1.0";
        src = ./theme;

        nativeBuildInputs = [pkgs.grub2];

        # GRUB only reads bitmap .pf2 fonts, and each point size is a
        # separate file. grub-mkfont composes the internal name as
        # "<-n> <style> <size>", and that full string — not the filename —
        # is what theme.txt's `font = "..."` must match. So -n "Potsdam"
        # at -s 24 is referenced as "Potsdam Regular 24".
        #
        # Two faces, deliberately: Potsdam (vendored, see fonts/README) is the
        # branded blackletter for menu entries, CaskaydiaCove the monospace for
        # the console and countdown. Only the sizes actually referenced by
        # theme.txt are built.
        installPhase = ''
          runHook preInstall

          mkdir -p $out
          cp -r ./* $out/

          grub-mkfont -s 24 -n "Potsdam" \
            -o "$out/potsdam-24.pf2" ${./fonts/Potsdam.ttf}

          ttf=$(find ${pkgs.nerd-fonts.caskaydia-cove}/share/fonts \
                  -name 'CaskaydiaCoveNerdFont-Regular.ttf' | head -1)
          if [ -z "$ttf" ]; then
            echo "could not locate CaskaydiaCove regular TTF" >&2
            exit 1
          fi

          grub-mkfont -s 18 -n "CaskaydiaCove" \
            -o "$out/caskaydia-18.pf2" "$ttf"

          runHook postInstall
        '';
      };
    });

    overlays.default = final: prev: {
      grubermeister = self.packages.${final.system}.grubermeister;
    };

    # nix run .#preview — build an ISO and boot it in QEMU, no reboot needed.
    apps = forAllSystems (pkgs: {
      preview = {
        type = "app";
        program = "${pkgs.writeShellScript "preview-grubermeister" ''
          export PATH=${pkgs.lib.makeBinPath [pkgs.grub2 pkgs.xorriso pkgs.mtools pkgs.qemu]}:$PATH
          export GRUBERMEISTER_THEME=${self.packages.${pkgs.system}.grubermeister}
          exec ${pkgs.bash}/bin/bash ${./preview.sh} "$@"
        ''}";
      };
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [pkgs.grub2 pkgs.xorriso pkgs.mtools pkgs.qemu pkgs.imagemagick];
      };
    });
  };
}
