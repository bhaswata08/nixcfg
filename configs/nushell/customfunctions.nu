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
