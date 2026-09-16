{
  pkgs, ...
}:
{
  # anyrun-daemon and kidex lived here. Both went with anyrun: rofi covers the
  # launcher and runner (configs/rofi.nix), and kidex had been crash-looping
  # out of its restart limit, so its index was never there to search.

  # Local text-to-speech for tts.nvim (configs/nvim/lua/plugins/tts.lua). It
  # speaks the OpenAI /v1/audio/speech API, so the plugin's openai backend
  # reaches it with no API key. Loopback only.
  virtualisation.oci-containers = {
    backend = "docker";
    containers.kokoro-tts = {
      image = "ghcr.io/remsky/kokoro-fastapi-cpu:v0.9.0";
      ports = [ "127.0.0.1:8880:8880" ];
      autoStart = true;
    };
  };

  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
}
