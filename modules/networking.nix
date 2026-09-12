{
  ...
}:
{
  networking.hostName = "frosties";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  # Open ports in the firewall. 9999 was open with nothing listening on it;
  # re-add a port here only while something actually serves on it.
  networking.firewall.allowedTCPPorts = [ ];
  networking.nftables.enable = true;
  # networking.firewall.allowedUDPPorts = [ ... ];
}
