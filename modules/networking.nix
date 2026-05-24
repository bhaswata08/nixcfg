{
  ...
}:
{
  networking.hostName = "frosties";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 9999 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
}
