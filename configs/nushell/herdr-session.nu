# Minimal Herdr layout + Claude session restore.
#
# Written for this config instead of using nickmaglowsch/herdr-session-restore,
# which installs zsh wrappers into ~/.zshrc and needs python3 -- neither of which
# exists here. This version is pure nushell over the `herdr` CLI, and reads
# Claude session ids straight off disk rather than wrapping the `claude` binary
# to inject `--session-id`.
#
#   herdr-snapshot   capture workspaces, tabs, cwds and Claude sessions
#   herdr-restore    replay a snapshot into a running Herdr server
#
# Snapshot is explicit, not automatic: run it before a reboot, or wire it to a
# timer. Nothing here hooks `herdr server stop`.

const HERDR_RESTORE_FILE = ("~/.local/state/herdr/restore/last-layout.json" | path expand)

# Claude stores one .jsonl per session under ~/.claude/projects/<encoded-cwd>/,
# where the encoding replaces every "/" and "." in the absolute path with "-"
# and the file stem is the session id.
def claude-project-dir [cwd: string]: nothing -> string {
    let encoded = ($cwd | str replace --all --regex '[/.]' '-')
    $"~/.claude/projects/($encoded)" | path expand
}

# Session ids for a cwd, most recently modified first.
def claude-sessions [cwd: string]: nothing -> list<string> {
    let dir = (claude-project-dir $cwd)
    if not ($dir | path exists) { return [] }
    # `ls` on a glob with no matches is an error, not an empty list.
    let files = (try { ls $"($dir)/*.jsonl" } catch { [] })
    if ($files | is-empty) { return [] }
    $files
    | sort-by modified --reverse
    | get name
    | each { |f| $f | path parse | get stem }
}

# Capture the current layout to disk.
#
# Claude session ids are resolved per cwd by recency: the panes sharing a cwd are
# handed the N most recently touched sessions for that project, one each. Herdr
# does not expose a pane's agent session id over the CLI, so when two agents in
# one directory are restored the pairing between them can swap. The sessions
# themselves are never wrong, only which pane gets which.
export def herdr-snapshot []: nothing -> nothing {
    let panes = (herdr pane list | from json | get result.panes)
    let workspaces = (herdr workspace list | from json | get result.workspaces)
    let tabs = (herdr tab list | from json | get result.tabs)

    let ws_labels = ($workspaces | reduce --fold {} { |w, acc|
        $acc | insert $w.workspace_id ($w.label? | default "")
    })
    let tab_labels = ($tabs | reduce --fold {} { |t, acc|
        $acc | insert $t.tab_id ($t.label? | default "")
    })

    # Assign each Claude pane a distinct session id, most recent first.
    mut used = {}
    mut entries = []
    for p in $panes {
        let cwd = ($p.cwd? | default $p.foreground_cwd? | default $env.HOME)
        let agent = ($p.agent? | default null)

        let taken = ($used | get -o $cwd | default 0)
        let available = (if $agent == "claude" { claude-sessions $cwd } else { [] })
        let session = (if $taken < ($available | length) {
            $available | get $taken
        } else {
            null
        })
        if $session != null {
            $used = ($used | upsert $cwd ($taken + 1))
        }

        $entries = ($entries | append {
            workspace_id: $p.workspace_id
            workspace_label: ($ws_labels | get -o $p.workspace_id | default "")
            tab_id: $p.tab_id
            tab_label: ($tab_labels | get -o $p.tab_id | default "")
            cwd: $cwd
            agent: $agent
            session_id: $session
        })
    }

    mkdir ($HERDR_RESTORE_FILE | path dirname)
    {
        captured_at: (date now | format date "%+")
        panes: $entries
    } | to json | save --force $HERDR_RESTORE_FILE

    let n_agents = ($entries | where agent == "claude" | length)
    print $"Snapshot: ($entries | length) panes \(($n_agents) Claude\) -> ($HERDR_RESTORE_FILE)"
}

# Replay the snapshot. Creates one workspace per recorded workspace and one tab
# per recorded pane, then resumes Claude where a session id was captured.
#
# This is additive -- it never closes or reuses what is already open, so running
# it against a populated server duplicates workspaces. Intended for a cold start.
export def herdr-restore [
    --dry-run  # print what would be created without touching the server
]: nothing -> nothing {
    if not ($HERDR_RESTORE_FILE | path exists) {
        print $"No snapshot at ($HERDR_RESTORE_FILE). Run herdr-snapshot first."
        return
    }

    # `open` parses .json by extension; no `from json` needed.
    let snapshot = (open $HERDR_RESTORE_FILE)
    print $"Restoring snapshot from ($snapshot.captured_at)"

    for group in ($snapshot.panes | group-by workspace_id --to-table) {
        let entries = $group.items
        let label = ($entries | first | get workspace_label)
        let root = ($entries | first | get cwd)

        if $dry_run {
            print $"workspace ($label) @ ($root)"
            for e in $entries {
                let resume = (if $e.session_id != null { $" resume ($e.session_id)" } else { "" })
                print $"  tab ($e.tab_label) @ ($e.cwd)($resume)"
            }
            continue
        }

        # `workspace create` already yields a root tab and pane, so the first
        # entry reuses those; only the remaining entries need `tab create`.
        # Both commands return the new pane directly under result.root_pane.
        let ws = (herdr workspace create --cwd $root --label $label --no-focus
            | from json | get result)
        let ws_id = $ws.workspace.workspace_id

        for e in ($entries | enumerate) {
            # Tab labels are not restored: Herdr derives them itself from the
            # pane's cwd and occupying agent, and overrides anything set here.
            let pane_id = (if $e.index == 0 {
                $ws.root_pane.pane_id
            } else {
                herdr tab create --workspace $ws_id --cwd $e.item.cwd --label $e.item.tab_label --no-focus
                | from json | get result.root_pane.pane_id
            })

            if $e.item.session_id != null {
                herdr pane run $pane_id $"claude --resume ($e.item.session_id)"
            }
        }
        print $"  restored ($label) with ($entries | length) tabs"
    }
}
