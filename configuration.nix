# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nix.settings.trusted-users = [
    "root"
    "bhaswata"
  ];
  imports = [ 
      ./hardware-configuration.nix
      ./modules/packages/development.nix
      ./modules/packages/external.nix
      ./modules/packages/fonts.nix
      ./modules/packages/gaming.nix
      ./modules/packages/languages.nix
      ./modules/packages/multimedia.nix
      ./modules/packages/productivity.nix
      ./modules/packages/utilities.nix
      ./modules/packages/web.nix
      ./modules/packages/wm.nix
      ./modules/boot.nix
      ./modules/daemons.nix
      ./modules/environment.nix
      ./modules/garbagecollector.nix
      ./modules/hardware.nix
      ./modules/locale.nix
      ./modules/networking.nix
      ./modules/nix-ld.nix
      ./modules/security.nix
      ./modules/services.nix
      ./modules/users.nix
  ];
  # swapDevices = lib.mkForce [
  #   { device = "/dev/mapper/luks-7282faec-2147-4fdf-b6d8-6529460f9fe1";
  #     randomEncryption.enable = true;
  #   }
  # ];
  swapDevices = lib.mkForce [ ];
  # system.copySystemConfiguration = true;
  system.stateVersion = "26.05"; # DO NOT CHANGE
}
