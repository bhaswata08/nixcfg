{ config, lib, ... }:

let
  # Kept equal to the output_path values below. The @import lines in each
  # profile have to name the same files, and the activation script writes them.
  chromeCss = "${config.xdg.cacheHome}/noctalia/zen-browser/zen-userChrome.css";
  contentCss = "${config.xdg.cacheHome}/noctalia/zen-browser/zen-userContent.css";
in
{
  # zen is installed from the flake input (modules/packages/external.nix) and
  # its profile is ordinary browser state, so nothing here manages the profile
  # itself. This wires up two things: the palette, and the prefs the palette
  # needs in order to be read at all.
  #
  # The templates are ours rather than noctalia's built-in zenBrowser one, which
  # stays off in configs/theming/noctalia-config.json. Its colour choices put
  # the browser on a different rung of the tonal ramp and a different accent
  # from the rest of the desktop, and it paints every surface opaque, which
  # hides the compositor blur. configs/zen/*.css explain both changes. Taking it
  # over wholesale rather than layering an override on top is deliberate: the
  # built-in template's post-process step rewrites its own @import line to the
  # end of userChrome.css on every render, so an override file could not stay
  # after it in the cascade.
  programs.noctalia-shell.user-templates.templates = {
    zenUserChrome = {
      input_path = "${./zen/userchrome-template.css}";
      output_path = chromeCss;
    };
    zenUserContent = {
      input_path = "${./zen/usercontent-template.css}";
      output_path = contentCss;
    };
  };

  # Two prefs, both off by default in zen's greprefs.js:
  #
  # toolkit.legacyUserProfileCustomizations.stylesheets gates userChrome.css and
  # userContent.css entirely. Without it the templates above render into files
  # the browser never opens. zen does flip it itself when it finds a user
  # stylesheet, but only inside _migrateV1, a one-shot keyed on the profile's
  # migration version, so a profile created before the templates were added
  # never runs it.
  #
  # zen.widget.linux.transparency gives the window an ARGB visual. Without it
  # the toplevel is opaque, and the alpha in the chrome CSS composites against
  # zen's own backdrop rather than against the wallpaper, so niri's blur never
  # shows through no matter what the stylesheet asks for.
  #
  # user.js rather than prefs.js: the browser rewrites prefs.js on exit and
  # re-reads user.js on every start, so these survive a reset from inside the
  # browser.
  #
  # The glob matches on chrome/ rather than on any directory under
  # ~/.config/zen, which also holds firefox-mpris, native-messaging-hosts and
  # Profile Groups.
  home.activation.zenTheming = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for chrome in "$HOME"/.config/zen/*/chrome/; do
      [ -d "$chrome" ] || continue
      profile="$(dirname "$chrome")"

      appendOnce() {
        # Appending needs a shell redirect, which `run` cannot wrap without the
        # redirect firing during a dry run too, so the dry run is handled here.
        grep -Fqs "$2" "$1" && return 0
        if [[ -v DRY_RUN ]]; then
          echo "would append to $1: $2"
        else
          printf '%s\n' "$2" >> "$1"
        fi
      }

      appendOnce "$profile/user.js" \
        'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
      appendOnce "$profile/user.js" \
        'user_pref("zen.widget.linux.transparency", true);'
      appendOnce "$chrome/userChrome.css" '@import "${chromeCss}";'
      appendOnce "$chrome/userContent.css" '@import "${contentCss}";'
    done
  '';
}
