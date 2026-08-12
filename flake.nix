{
  description = "Opinionated nix flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs"; 
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nebula, the glass theme zen's chrome is skinned with (configs/zen.nix).
    # Plain CSS, not a flake.
    #
    # Pinned to a commit, not to a tag. The tags lag the tree they are named
    # for: v3.3 holds a theme.json saying 3.2, under a differently cased
    # directory layout. This rev is 3.3.3. An upgrade wants checking against
    # whatever zen the zen-browser input is on at the time, since Nebula tracks
    # zen's own versions.
    zen-nebula = {
      url = "github:JustAdumbPrsn/Zen-Nebula/31ba4a3bde77391e173a6a3460d9fb0ab9bca8a0";
      flake = false;
    };
    # pfm defaults to its own pinned nixpkgs; left alone it pulled a second
    # nixpkgs tree into the lock.
    pfm = {
      url = "github:bhaswata08/pfm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    qml-niri = {
      url = "github:imiric/qml-niri/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/legacy-v4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    {
      nixosConfigurations.frosties = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = {
          inherit inputs;
        };

        modules = [
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          # Only the home-manager catppuccin module is used (configs/theming/
          # themes.nix). The NixOS one stayed at catppuccin.enable = false, so
          # it themed nothing and only emitted a deprecation warning.
          inputs.home-manager.nixosModules.home-manager
          ./configuration.nix
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.extraSpecialArgs = {
              inherit inputs;
            };

            home-manager.users.bhaswata = {
              imports = [
                inputs.noctalia.homeModules.default
                inputs.catppuccin.homeModules.catppuccin
                ./home.nix
              ];
            };
          }
        ];
      };

      # No standalone homeConfigurations output. home.nix is already applied
      # through the home-manager NixOS module above, which is what `just switch`
      # runs; a second entry point nothing exercised would only rot.
    };
}
