{
  pkgs, ...
}:
{
  programs.anyrun = {
    enable = true;
    config = {
      plugins = [
        "${pkgs.anyrun}/lib/libapplications.so"
          "${pkgs.anyrun}/lib/libsymbols.so"
          "${pkgs.anyrun}/lib/librink.so"
          "${pkgs.anyrun}/lib/librandr.so"
          "${pkgs.anyrun}/lib/libwebsearch.so"
          "${pkgs.anyrun}/lib/libkidex.so"
      ];
    };

    extraConfigFiles."websearch.ron".text = ''
      Config(
          prefix: "?",
          engines: [DuckDuckGo],
          )
      '';

    extraConfigFiles."kidex.ron".text = ''
      Config(
          ignored: [], 
          directories: [
          WatchDir(
            path: "/home/bhaswata/", 
            recurse: true, 
            ignored: [], 
            ),
          ],
          )
      '';
    extraConfigFiles."randr.ron".text = ''
      Config(
        prefix: ":dp",
        max_entries: 5,
      )
    '';
  };
}
