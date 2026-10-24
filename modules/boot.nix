{
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # /tmp is on the root ext4, so nothing clears it between boots. Every nh
  # build leaves a /tmp/nh-osXXXX/result gcroot there pinning its whole system
  # closure; 17 had accumulated since January 2026, which is why weekly nix-gc
  # freed almost nothing. `just clean` sweeps them, this stops them piling up
  # in between.
  boot.tmp.cleanOnBoot = true;
  boot.kernelModules = [
    "nf_tables"
    "nft_compat"
    "nf_nat"
    "nf_conntrack"
  ];
  # nvme0 (Kingston OM8PCP3512F, root disk) dropped off PCIe on 2026-09-13:
  # "controller is down; will reset: CSTS=0xffffffff", reset failed with -19,
  # root went read-only, systemd died, kernel panicked ("Attempted to kill
  # init"). Disable NVMe APST and PCIe ASPM/port power management so the
  # controller never enters a low-power state it cannot wake from.
  boot.kernelParams = [
    "nvme_core.default_ps_max_latency_us=0"
    "pcie_aspm=off"
    "pcie_port_pm=off"
  ];
}
