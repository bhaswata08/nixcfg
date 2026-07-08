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
