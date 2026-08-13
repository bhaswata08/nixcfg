{
  pkgs,
  ...
}:

{

  users.users.bhaswata = {
    isNormalUser = true;
    description = "bhaswata";
    extraGroups = [
      "networkmanager"
      "wheel"
      "lp"
      "lpadmin"
      "scanner"
      "libvirtd"
      "docker"
    ];
    shell = pkgs.nushell;
    packages = with pkgs; [ ];
  };
}
