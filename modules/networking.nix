{
  ...
}:
{
  networking.hostName = "frosties";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
# DO NOT FUCKING CLOSE THIS PORT EVEN IF NOTHING RUNNING ON IT. IF YOU WANT TO FUCKING ASK AND THEN CONFIRM
  networking.firewall.allowedTCPPorts = [ 9999 ];
  networking.nftables.enable = true;
  # networking.firewall.allowedUDPPorts = [ ... ];
}
