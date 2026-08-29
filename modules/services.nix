{
  pkgs,
  ...
}:
{
  services.xserver.videoDrivers = ["nvidia"];
  services.openssh.enable = true;
  services.printing = {
      enable = true;
      drivers = [
        pkgs.gutenprint
        pkgs.gutenprintBin
        pkgs.cnijfilter2
      ];
    };
  services.avahi = {
    enable = true;
    openFirewall = true;
  };
  services.displayManager.ly.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
  services.libinput.enable = true;
  services.dbus = {
    enable = true;
    packages = [ pkgs.dconf ];
  };
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "gtk";
  };
  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;
  # No services.xserver.enable / xfce here. niri is the only session, ly is a
  # TTY greeter, and X11 clients reach the compositor through
  # xwayland-satellite (started from configs/theming/niri.nix), so nothing
  # needs a real X server. videoDrivers above is kept: it is what pulls in the
  # nvidia kernel modules for this machine's dGPU (modules/hardware.nix).
}
