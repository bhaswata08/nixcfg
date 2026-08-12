{ lib, ... }:
{
  # zen is installed from the flake input (modules/packages/external.nix) and
  # its profile is ordinary browser state, so nothing here manages the profile
  # itself. This sets one prerequisite pref.
  #
  # noctalia's zenBrowser template renders the palette into
  # ~/.cache/noctalia/zen-browser/ and appends an @import for each file to the
  # profile's userChrome.css and userContent.css. zen ships
  # `toolkit.legacyUserProfileCustomizations.stylesheets` as false
  # (greprefs.js), so without this the template writes files the browser reads
  # nothing from. zen does flip the pref itself when it finds a user stylesheet,
  # but only inside _migrateV1, a one-shot keyed on the profile's migration
  # version, so a profile created before the template was enabled never sees it.
  #
  # user.js rather than prefs.js: the browser rewrites prefs.js on exit and
  # re-reads user.js on every start, so this survives a pref reset. The profile
  # directory name is generated per machine, hence the glob.
  #
  # The glob matches on `chrome/` rather than on any directory under
  # ~/.config/zen, which also holds firefox-mpris, native-messaging-hosts and
  # Profile Groups. Beyond skipping those, it selects the same set noctalia's
  # own hook writes into, since that hook only visits profiles whose chrome
  # directory already exists: exactly the profiles the pref matters for.
  home.activation.zenUserChrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for chrome in "$HOME"/.config/zen/*/chrome/; do
      [ -d "$chrome" ] || continue
      userjs="$(dirname "$chrome")/user.js"
      line='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
      if ! grep -Fqs "$line" "$userjs"; then
        # Appending needs a shell redirect, which `run` cannot wrap without the
        # redirect firing during a dry run too, so the dry run is handled here.
        if [[ -v DRY_RUN ]]; then
          echo "would append the legacy stylesheet pref to $userjs"
        else
          printf '%s\n' "$line" >> "$userjs"
        fi
      fi
    done
  '';
}
