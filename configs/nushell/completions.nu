# Zoxide completion

def "nu-complete zoxide path" [context: string] {
    let parts = $context | split row " " | skip 1
    {
      options: {
        sort: false,
        completion_algorithm: substring,
        case_sensitive: false,
      },
      completions: (^zoxide query --list --exclude $env.PWD -- ...$parts | lines),
    }
  }

def --env --wrapped z [...rest: string@"nu-complete zoxide path"] {
  __zoxide_z ...$rest
}

# Carapace
let carapace_completer = {|spans|
    carapace $spans.0 nushell ...$spans | from json
}

$env.config = {
    completions: {
        external: {
            enable: true
            max_results: 100
            completer: $carapace_completer
        }
    }
}
