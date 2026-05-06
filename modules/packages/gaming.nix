{
  pkgs,
  ...
}:

{

  environment.systemPackages = with pkgs; [
    bottles
  ];

  programs.steam = {
    enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
    package = pkgs.steam.override {
      extraEnv = {
        MANGOHUD = "1";
        GAMEMODERUN = "1";
      };
    };
  };
  programs.gamemode.enable = true;
}
