{
  ...
}:
{
  networking.hostName = "frosties";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
# DO NOT CLOSE THIS PORT
  networking.firewall.allowedTCPPorts = [ 9999 ];
  networking.nftables.enable = true;
  # networking.firewall.allowedUDPPorts = [ ... ];
}
