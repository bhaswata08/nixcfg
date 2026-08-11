{
  pkgs,
  lib,
  ...
}:

let
  # Obsidian's vim mode is CodeMirror 6 vim, and the only way to configure it is
  # the obsidian-vimrc-support community plugin, which reads .obsidian.vimrc
  # from the vault root. relative-line-numbers covers Neovim's `relativenumber`,
  # which vim mode itself cannot set.
  #
  # There is no nixpkgs packaging for Obsidian community plugins, so the release
  # files are fetched directly. Bump: check the releases page, change the
  # version, run `just switch` and take the hash nix prints.
  ghRelease =
    {
      owner,
      repo,
      version,
      files,
    }:
    lib.mapAttrs (
      file: hash:
      pkgs.fetchurl {
        url = "https://github.com/${owner}/${repo}/releases/download/${version}/${file}";
        inherit hash;
      }
    ) files;

  # https://github.com/esm7/obsidian-vimrc-support/releases
  vimrcSupport = ghRelease {
    owner = "esm7";
    repo = "obsidian-vimrc-support";
    version = "0.10.2";
    files = {
      "main.js" = "sha256-aGNzThnu8lBeBUJQyoIbxTL21iceb1AXKx6KBHNObOI=";
      "manifest.json" = "sha256-st5aS+ORuI69konjgVYtFJGlh5ef0Iu9pqf/Ub4n0FY=";
    };
  };

  # https://github.com/nadavspi/obsidian-relative-line-numbers/releases
  relativeLineNumbers = ghRelease {
    owner = "nadavspi";
    repo = "obsidian-relative-line-numbers";
    version = "3.1.0";
    files = {
      "main.js" = "sha256-JpufX+6TrczDl9MZmRgYrZThsC/tUT2pusVP9e7ln6U=";
      "manifest.json" = "sha256-6ZhpsAukiZT17B+oYosLs/10+euPerkmz1pIEMvKHGs=";
      "styles.css" = "sha256-cFvcj1jC6GluwtmcQ2k42hVPQvVXkIquVLXM4PDjXAI=";
    };
  };

  plugins = {
    obsidian-vimrc-support = vimrcSupport;
    obsidian-relative-line-numbers = relativeLineNumbers;
  };

  # Vault roots, relative to $HOME. Add a vault here and it gets the same vim
  # setup as the others.
  vaults = [
    "self_projects/learning/CS336"
    "self_projects/learning/ACR-Prep"
    "self_projects/projects/bhaswata08.github.io"
  ];

  # Obsidian owns .obsidian/plugins/<id>/data.json, so each plugin is linked
  # file by file rather than as a whole directory; the directory itself stays
  # writable. .obsidian/community-plugins.json is left alone for the same
  # reason - Obsidian rewrites it whenever a plugin is toggled in the UI.
  pluginFiles =
    vault: id: files:
    lib.mapAttrs' (
      file: drv: lib.nameValuePair "${vault}/.obsidian/plugins/${id}/${file}" { source = drv; }
    ) files;

  vaultFiles =
    vault:
    lib.mkMerge (
      [ { "${vault}/.obsidian.vimrc".source = ./obsidian/obsidian.vimrc; } ]
      ++ lib.mapAttrsToList (pluginFiles vault) plugins
    );
in
{
  home.file = lib.mkMerge (map vaultFiles vaults);
}
