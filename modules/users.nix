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
  users.users.newuser = {
    isNormalUser = true;
    description = "test";
    extraGroups = [ "networkmanager" "video" "audio" "input"];
    shell = pkgs.nushell;
    packages = with pkgs; [ ];
  };
}
