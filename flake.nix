{
  description = "Opinionated nix flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    catppuccin.url = "github:catppuccin/nix";
    uwu-colors.url = "github:q60/uwu_colors";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pfm.url = "github:bhaswata08/pfm";
    kidex.url = "github:Kirottu/kidex";

    qml-niri = {
      url = "github:imiric/qml-niri/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = 
    inputs:
    let
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    in
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
          inputs.stylix.nixosModules.stylix
          inputs.catppuccin.nixosModules.catppuccin
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

      homeConfigurations."bhaswata" = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          inputs.noctalia.homeModules.default
          inputs.catppuccin.homeModules.catppuccin
          ./home.nix
        ];
      };
    };
}
