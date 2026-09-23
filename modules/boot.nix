{
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Required for TPM2 unlock of the root LUKS container. The classic initrd
  # cannot talk to the TPM, so without this the tpm2-device option in
  # hardware-configuration.nix is ignored and every boot falls back to the
  # passphrase.
  boot.initrd.systemd.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [
    "nf_tables"
    "nft_compat"      
    "nf_nat"
    "nf_conntrack"
  ];
}
