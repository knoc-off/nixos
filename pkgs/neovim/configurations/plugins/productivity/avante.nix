{ pkgs, ... }: {
  plugins.avante = {
    enable = true;
    settings = {
      # --- Set your default provider ---
      # You can set this to "openai", "claude", or "openrouter_custom" (our new vendor)
      # For example, to use the overridden 'openai' block by default:
      provider = "openai";
      # Or, to use your new custom OpenRouter vendor by default:
      # provider = "openrouter_custom";

      # --- Method 1: Overriding existing providers to use OpenRouter ---
      # This allows you to select "openai" or "claude" as the provider
      # and have them point to OpenRouter.
      openai = {
        endpoint = "https://openrouter.ai/api/v1";
        # Model for the 'openai' provider when it's using OpenRouter
        model = "anthropic/claude-3.5-sonnet-20240620";
        api_key_name = "OPENROUTER_API_KEY"; # Env var for API key
        # temperature = 0.6;
        # max_tokens = 8000;
      };

      claude = { # Optional: if you also want 'claude' to point to OpenRouter
        endpoint = "https://openrouter.ai/api/v1";
        # Model for the 'claude' provider when it's using OpenRouter
        model = "anthropic/claude-3.5-sonnet:beta";
        api_key_name = "OPENROUTER_API_KEY"; # Env var for API key
        # temperature = 0.6;
        # max_tokens = 8000;
      };

      # --- Method 2: Defining OpenRouter as a new custom vendor ---
      # This allows you to select "openrouter_custom" (or whatever you name it)
      # as the provider.
      vendors = {
        # You can name this key whatever you like, e.g., "openrouter" or "my_openrouter"
        # Using "openrouter_custom" to be clear it's your definition.
        openrouter_custom = {
          __inherited_from = "openai"; # Crucial for OpenAI-compatible APIs
          endpoint = "https://openrouter.ai/api/v1";
          api_key_name =
            "OPENROUTER_API_KEY"; # Using the same env var for simplicity
          # Default model when "openrouter_custom" is selected
          model =
            "mistralai/mistral-7b-instruct"; # Example, choose any OpenRouter model
          # You can add other OpenAI-compatible parameters here if needed, e.g.:
          # temperature = 0.7;
          # max_tokens = 4000;
        };
        # You could add other custom vendors here, for example, a second OpenRouter
        # config with a different default model or API key:
        # openrouter_another_model = {
        #   __inherited_from = "openai";
        #   endpoint = "https://openrouter.ai/api/v1";
        #   api_key_name = "OPENROUTER_API_KEY_AVANTE";
        #   model = "google/gemini-pro";
        # };
      };

      # All other settings (mappings, windows, behaviour, hints, etc.)
      # will use the defaults provided by avante.nvim or your base Nixvim setup,
      # unless you explicitly configure them here.
    };
  };
}
