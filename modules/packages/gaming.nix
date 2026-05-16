{
  pkgs,
  ...
}:

{

  # environment.systemPackages = with pkgs; [
  #   # bottles
  # ];

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
    package = pkgs.steam.override {
      extraEnv = {
        MANGOHUD = "1";
        MANGOHUD_CONFIG = "read_cfg,no_display";
        GAMEMODERUN = "1";
        WINE_VK_VULKAN_ONLY = "1";
        WINEDLLOVERRIDES = "dinput8,dxgi,dsound=n,b";
      };
    };
  };
  programs.gamemode.enable = true;
}
# SteamDeck=1 gamescope -f -W 1980 -H 1080 -r 144 --force-grab-cursor -- %command%
