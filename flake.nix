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
    # Both of these default to their own pinned nixpkgs. kidex additionally
    # pinned its own home-manager. Left alone they pulled a June 2025 nixpkgs
    # and home-manager into the lock, so the system evaluated two nixpkgs trees
    # and built kidex against a 14-month-old one.
    pfm = {
      url = "github:bhaswata08/pfm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kidex = {
      url = "github:Kirottu/kidex";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
