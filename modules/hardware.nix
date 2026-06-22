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
}
