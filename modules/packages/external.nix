{
  pkgs,
  inputs,
  ...
}:
{
  environment.systemPackages = [
    inputs.kidex.packages.${pkgs.stdenv.hostPlatform.system}.kidex
    inputs.pfm.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}

