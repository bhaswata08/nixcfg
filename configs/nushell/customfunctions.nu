def --env setup-openrouter [key: string] {
    let openrouter_key = $key

    load-env {
        OPENROUTER_API_KEY: $openrouter_key
        ANTHROPIC_BASE_URL: "https://openrouter.ai/api"
        ANTHROPIC_AUTH_TOKEN: $openrouter_key
        ANTHROPIC_API_KEY: ""
    }
    
    print "OpenRouter environment variables configured successfully!"
}


def --env setup-openrouter-custom [key: string] {
    let openrouter_key = $key

    load-env {
        OPENROUTER_API_KEY: $openrouter_key
        ANTHROPIC_BASE_URL: "https://openrouter.ai/api"
        ANTHROPIC_AUTH_TOKEN: $openrouter_key
        ANTHROPIC_API_KEY: ""
        ANTHROPIC_DEFAULT_OPUS_MODEL: "deepseek/deepseek-v4-pro"
        ANTHROPIC_DEFAULT_SONNET_MODEL: "deepseek/deepseek-v4-pro"
        ANTHROPIC_DEFAULT_HAIKU_MODEL: "deepseek/deepseek-v4-pro"
    }
    
    print "OpenRouter environment variables configured successfully!"
}


# Run Claude Code against Synthetic's Anthropic-compatible endpoint instead of
# Anthropic. The env is scoped to the one command, so `claude` in the same shell
# still talks to Anthropic and you always know which engine you are on.
#
# The API key is read from ~/.config/synthetic/key (chmod 600) or the
# SYNTHETIC_API_KEY env var. It stays out of this file because the nix store is
# world readable, and out of shell history because it is not an argument.
#
#   synclaude                    # GLM-5.2
#   synclaude -m kimi            # Kimi-K3
#   synclaude -m glm-flash -- -p "fix the lint errors"
def synclaude [
    --model (-m): string = "glm"  # glm | glm-flash | glm4-flash | kimi | qwen | nemotron | gpt-oss
    ...args                       # passed through to claude
] {
    let models = {
        glm:        "hf:zai-org/GLM-5.2"
        glm-flash:  "hf:zai-org/GLM-5.3-Flash"
        glm4-flash: "hf:zai-org/GLM-4.7-Flash"
        kimi:       "hf:moonshotai/Kimi-K3"
        qwen:       "hf:Qwen/Qwen3.8-27B"
        nemotron:   "hf:nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4"
        gpt-oss:    "hf:openai/gpt-oss-120b"
    }

    # Context window per model, from Synthetic's model list. Claude Code does not
    # recognize these hf: model ids, so without this it assumes 200k and
    # auto-compacts early.
    let context_lengths = {
        glm:        512_000
        glm-flash:  512_000
        glm4-flash: 192_000
        kimi:       512_000
        qwen:       256_000
        nemotron:   256_000
        gpt-oss:    128_000
    }

    let big = ($models | get -o $model)
    if ($big | is-empty) {
        error make {msg: $"unknown model '($model)'. pick one of: ($models | columns | str join ', ')"}
    }

    let max_context = ($context_lengths | get -o $model)

    let keyfile = ($env.HOME | path join ".config/synthetic/key")
    let key = if ($env.SYNTHETIC_API_KEY? | default "" | is-not-empty) {
        $env.SYNTHETIC_API_KEY
    } else if ($keyfile | path exists) {
        open --raw $keyfile | str trim
    } else {
        error make {msg: $"no Synthetic API key. write it to ($keyfile) or set $env.SYNTHETIC_API_KEY"}
    }

    print $"(ansi yellow)synthetic(ansi reset) ($big)"

    with-env {
        ANTHROPIC_BASE_URL: "https://api.synthetic.new/anthropic"
        ANTHROPIC_AUTH_TOKEN: $key
        ANTHROPIC_API_KEY: ""
        ANTHROPIC_DEFAULT_OPUS_MODEL: $big
        ANTHROPIC_DEFAULT_SONNET_MODEL: $big
        ANTHROPIC_DEFAULT_HAIKU_MODEL: "hf:zai-org/GLM-5.3-Flash"
        CLAUDE_CODE_SUBAGENT_MODEL: $big
        CLAUDE_CODE_ATTRIBUTION_HEADER: "0"
        CLAUDE_CODE_MAX_CONTEXT_TOKENS: ($max_context | into string)
    } { ^claude ...$args }
}

# Pairs with `cc = claude` in aliases.nu: cc is Anthropic, sc is Synthetic.
# This lives here rather than in aliases.nu because nushell resolves aliases at
# parse time and config.nu sources aliases.nu first, so the alias would bind to a
# missing external command instead of the def above.
alias sc = synclaude


# heal-claude-session: fix Claude Code session transcripts corrupted by a
# non-Anthropic backend (Synthetic, OpenRouter, ...) emitting tool_use /
# tool_result ids that don't match Anthropic's required pattern
# ^[a-zA-Z0-9_-]+$. Symptom when you resume such a session against real
# Anthropic:
#
#   API Error: 400 messages.N.content.M.tool_use.id: String should match
#   pattern '^[a-zA-Z0-9_-]+$'
#
# Every offending id has its invalid characters replaced with "_"
# (e.g. "Bash:0-<uuid>" -> "Bash_0-<uuid>"), consistently everywhere it
# appears, so tool_use/tool_result pairs still match each other. The file
# is backed up before any write, and the fix is verified afterward.
#
# Requires: jq, perl, and (for the default picker) fzf.

def "heal-claude-session bad-ids" [
    path: path  # session .jsonl to scan
] {
    let result = (
        ^jq -r '.message.content?[]? | select(.type=="tool_use" or .type=="tool_result") | (.id // .tool_use_id) | select(. != null)' $path
        | ^grep -Ev '^[a-zA-Z0-9_-]+$'
        | complete
    )
    $result.stdout | lines | uniq | sort
}

def "heal-claude-session sanitize" [
    id: string  # id to sanitize
] {
    $id | str replace --all --regex '[^a-zA-Z0-9_-]' '_'
}

def "heal-claude-session scan" [
    projects_dir: path  # root containing per-project session dirs
] {
    glob ($projects_dir | path join "*" "*.jsonl")
    | par-each {|p|
        let bad = (heal-claude-session bad-ids $p)
        # stat, not `ls`, because a user `ls` alias (e.g. `alias ls = eza ...`)
        # would shadow the builtin here and return unstructured text instead
        # of a record with a `.modified` field.
        let modified = ((^stat -c '%y' $p | complete).stdout | str trim)
        {
            path: $p
            project: ($p | path dirname | path basename)
            session: ($p | path basename | str replace '.jsonl' '')
            bad: ($bad | length)
            modified: $modified
        }
    }
    | where bad > 0
    | sort-by modified --reverse
}

def "heal-claude-session pick" [
    rows: table  # rows from `heal-claude-session scan`
] {
    let text = (
        $rows
        | each {|r| $"($r.session)\t($r.project)\t($r.bad) bad ids\t($r.modified)" }
        | str join "\n"
    )
    let selected = (
        $text
        | ^fzf --prompt "corrupted session> " --delimiter "\t" --height 60% --reverse
        | complete
    )
    if ($selected.stdout | str trim | is-empty) {
        null
    } else {
        let session = ($selected.stdout | str trim | split row "\t" | first)
        $rows | where session == $session | first
    }
}

def "heal-claude-session fix" [
    path: path   # session .jsonl to fix
    dry_run: bool  # show what would change, write nothing
] {
    let bad = (heal-claude-session bad-ids $path)
    if ($bad | is-empty) {
        print $"no corruption found in ($path)"
        return
    }

    print $"found ($bad | length) bad id\(s\) in ($path):"
    for id in $bad { print $"  ($id)" }

    let mapping = ($bad | each {|id| {old: $id, new: (heal-claude-session sanitize $id)} })

    let collisions = (
        $mapping
        | group-by new
        | transpose new olds
        | where {|r| ($r.olds | length) > 1 }
    )
    if not ($collisions | is-empty) {
        for c in $collisions {
            let ids = ($c.olds | get old | str join ', ')
            print --stderr $"collision: ($ids) all sanitize to '($c.new)'"
        }
        error make {msg: "refusing to fix: id collision would merge distinct tool calls"}
    }

    if $dry_run {
        print "dry run, nothing written:"
        for m in $mapping { print $"  ($m.old) -> ($m.new)" }
        return
    }

    let backup = $"($path).bak-(date now | format date '%Y%m%d%H%M%S')"
    # ^cp: bypass the `alias cp = cp -v` from aliases.nu (parse-time alias
    # expansion would otherwise add unwanted -v output).
    ^cp $path $backup
    print $"backed up to ($backup)"

    for m in $mapping {
        with-env {OLDID: $m.old, NEWID: $m.new} {
            ^perl -pi -e 's/\Q$ENV{OLDID}\E/$ENV{NEWID}/g' $path
        }
    }

    let remaining = (heal-claude-session bad-ids $path)
    if not ($remaining | is-empty) {
        ^cp $backup $path
        error make {msg: $"fix did not fully apply \(($remaining | length) id\(s\) still bad\); restored from backup, nothing changed"}
    }

    let before = ((^wc -l $backup | complete).stdout | str trim | split row " " | first)
    let after = ((^wc -l $path | complete).stdout | str trim | split row " " | first)
    if $before != $after {
        print --stderr $"warning: line count changed \(($before) -> ($after)\)"
    }

    print $"fixed ($mapping | length) id\(s\) in ($path)"
    print $"resume with: claude --resume ($path | path basename | str replace '.jsonl' '')"
}

#   heal-claude-session                    # fzf-pick a corrupted session and fix it
#   heal-claude-session mysession-id       # fix one session directly (id substring or path)
#   heal-claude-session --list             # list corrupted sessions, fix nothing
#   heal-claude-session --all              # fix every corrupted session found, no picker
#   heal-claude-session --dry-run <id>     # show what would change, write nothing
def --env heal-claude-session [
    session?: string          # session id (substring match) or path to a .jsonl, fixed directly
    --list (-l)                 # list corrupted sessions and exit; fixes nothing
    --all (-a)                   # fix every corrupted session found, skipping the picker
    --dry-run (-n)                 # show what would change without writing anything
    --projects-dir: path = "~/.claude/projects"  # root to scan
] {
    let projects_dir = ($projects_dir | path expand)
    let rows = (heal-claude-session scan $projects_dir)

    if $list {
        if ($rows | is-empty) {
            print $"no corrupted sessions found under ($projects_dir)"
        } else {
            print ($rows | select session project bad modified)
        }
        return
    }

    if $all {
        if ($rows | is-empty) {
            print $"no corrupted sessions found under ($projects_dir)"
            return
        }
        for r in $rows {
            heal-claude-session fix $r.path $dry_run
        }
        return
    }

    if not ($session | is-empty) {
        let target = if ($session | path exists) {
            $session
        } else {
            let matches = (
                $rows
                | where {|r| ($r.session | str contains $session) or ($r.path | str contains $session) }
            )
            if ($matches | is-empty) {
                print $"no corrupted session matching '($session)' found under ($projects_dir) \(already healthy, or no such session\)"
                return
            }
            if ($matches | length) > 1 {
                let names = ($matches | get session | str join ', ')
                error make {msg: $"'($session)' matches multiple corrupted sessions: ($names)"}
            }
            ($matches | first).path
        }
        heal-claude-session fix $target $dry_run
        return
    }

    if ($rows | is-empty) {
        print $"no corrupted sessions found under ($projects_dir)"
        return
    }

    if (which fzf | is-empty) {
        error make {msg: "fzf not found; pass a session id/path directly, or use --list/--all"}
    }

    let picked = (heal-claude-session pick $rows)
    if ($picked | is-empty) {
        print "no session selected"
        return
    }
    heal-claude-session fix $picked.path $dry_run
}
