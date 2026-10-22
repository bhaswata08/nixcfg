# ctrl+h/j/k/l dispatcher bound in config.toml, wrapped around herdr-navigator.
#
# herdr-navigator only forwards the key into a pane whose Neovim registered a
# marker file locally. Neovim on the far end of ssh can't do that (no Herdr
# socket or HERDR_* env over there), so the key used to move the Herdr pane and
# never reached the remote Neovim. When the pane's foreground process is a
# remote session, send the raw control character through instead and let the
# remote side handle it. prefix+h/j/k/l still moves Herdr panes from there.

direction="${1:?usage: herdr-nav-dispatch left|down|up|right}"
herdr="${HERDR_BIN_PATH:-herdr}"

case "$direction" in
  left) key=$'\x08' ;;
  down) key=$'\x0a' ;;
  up) key=$'\x0b' ;;
  right) key=$'\x0c' ;;
  *)
    echo "unsupported direction: $direction" >&2
    exit 2
    ;;
esac

pane="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
if [ -n "$pane" ]; then
  info=$("$herdr" pane process-info --pane "$pane" 2>/dev/null || true)
else
  info=$("$herdr" pane process-info --current 2>/dev/null || true)
fi

remote=$(jq -r '
  .result.process_info as $p
  | if any($p.foreground_processes[]?;
        (.name | test("^\\.?(ssh|mosh-client|mosh)(-wrapped)?$")))
    then $p.pane_id else empty end
' <<<"$info" 2>/dev/null || true)

if [ -n "$remote" ]; then
  exec "$herdr" pane send-text "$remote" "$key"
fi

exec herdr-navigator dispatch "$direction"
