{
  pkgs,
  lib,
  ...
}:

let
  # Obsidian's vim mode is CodeMirror 6 vim, and the only way to configure it is
  # the obsidian-vimrc-support community plugin, which reads .obsidian.vimrc
  # from the vault root. There is no nixpkgs package for Obsidian community
  # plugins, so the two release files are fetched directly.
  #
  # Bump: check https://github.com/esm7/obsidian-vimrc-support/releases, change
  # the version, then run `just switch` and take the hash nix prints.
  vimrcSupportVersion = "0.10.2";
  vimrcSupportUrl =
    file:
    "https://github.com/esm7/obsidian-vimrc-support/releases/download/${vimrcSupportVersion}/${file}";

  vimrcSupportMain = pkgs.fetchurl {
    url = vimrcSupportUrl "main.js";
    hash = "sha256-aGNzThnu8lBeBUJQyoIbxTL21iceb1AXKx6KBHNObOI=";
  };
  vimrcSupportManifest = pkgs.fetchurl {
    url = vimrcSupportUrl "manifest.json";
    hash = "sha256-st5aS+ORuI69konjgVYtFJGlh5ef0Iu9pqf/Ub4n0FY=";
  };

  # Vault roots, relative to $HOME. Add a vault here and it gets the same vim
  # setup as the others.
  vaults = [
    "self_projects/learning/CS336"
    "self_projects/learning/ACR-Prep"
    "self_projects/projects/bhaswata08.github.io"
  ];

  # Obsidian owns .obsidian/plugins/<id>/data.json, so the plugin is linked file
  # by file rather than as a whole directory; the directory itself stays
  # writable. .obsidian/community-plugins.json is left alone for the same
  # reason - Obsidian rewrites it whenever a plugin is toggled in the UI, so
  # enabling "Vimrc Support" is a one-time click per vault.
  vaultFiles =
    vault:
    let
      plugin = "${vault}/.obsidian/plugins/obsidian-vimrc-support";
    in
    {
      "${vault}/.obsidian.vimrc".source = ./obsidian/obsidian.vimrc;
      "${plugin}/main.js".source = vimrcSupportMain;
      "${plugin}/manifest.json".source = vimrcSupportManifest;
    };
in
{
  home.file = lib.mkMerge (map vaultFiles vaults);
}
