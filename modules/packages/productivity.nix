{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # anki's offline uv build reads wheels from UV_FIND_LINKS. hatchling now
    # depends on tomlkit, which nixpkgs leaves out of that wheel set, so uv
    # cannot resolve hatchling. Add tomlkit until nixpkgs adds it upstream.
    # nixpkgs' cargo setup hook also now forces zstd-sys and libsqlite3-sys to
    # link system libraries through pkg-config, which anki doesn't provide.
    (anki.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ pkg-config ];
      buildInputs = old.buildInputs ++ [
        zstd
        sqlite
        openssl
      ];
      env = old.env // {
        UV_FIND_LINKS = pkgs.runCommand "uv-wheels-tomlkit" { } ''
          mkdir -p $out
          ln -s ${old.env.UV_FIND_LINKS}/*.whl $out
          ln -s ${python3.pkgs.tomlkit.dist}/*.whl $out
        '';
      };
    }))
    onlyoffice-desktopeditors
    libreoffice
    drawing
    obsidian
    thunderbird
  ];

}
