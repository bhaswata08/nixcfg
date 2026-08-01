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
