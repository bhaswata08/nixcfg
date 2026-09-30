{
  pkgs, config,
  ...
}:
{
  hardware.graphics.enable = true;
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };
  virtualisation.docker.enable = true;
  virtualisation.waydroid.enable = true;
  zramSwap.enable = true;
  hardware.bluetooth.enable = true;

  # On 2026-09-30 a switch that compiled C++ from source used up all RAM and
  # zram, and the machine locked up. The defaults (max-jobs = 24, cores = 0)
  # allow 24 builds with 24 compiler threads each. Cap the total at about 24.
  nix.settings = {
    max-jobs = 4;
    cores = 6;
  };

  # zram swap stops the kernel OOM killer from firing, so cap the daemon
  # instead. A runaway build is throttled, then killed inside its own cgroup,
  # and the desktop keeps running.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "20G";
    MemoryMax = "24G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "80%";
  };
  systemd.oomd = {
    enableRootSlice = true;
    enableUserSlices = true;
  };
}
