//! An advanced example demonstrating a multi-model chain via OpenRouter
//! to generate a CLI command and copy it to the clipboard.
//!
//! To run this:
//! 1. Set your OpenRouter API key: export OPENROUTER_API_KEY="your-key-here"
//! 2. Run: cargo run -- "your task here"

use arboard::Clipboard;
use llm::{
    builder::{LLMBackend, LLMBuilder},
    chain::{LLMRegistryBuilder, MultiChainStepBuilder, MultiChainStepMode, MultiPromptChain},
    chat::StructuredOutputFormat,
};
use serde::Deserialize;
use std::env;
use std::thread;
use std::time::Duration;

// Simplified struct - only keeping what we need
#[derive(Deserialize, Debug)]
struct CliCommand {
    command: String,
}

/// Properly clean JSON output from LLM that might be wrapped in Markdown fences
fn clean_json_output(raw_output: &str) -> String {
    let trimmed = raw_output.trim();

    // Check if it starts with ```json or ```
    if trimmed.starts_with("```json") {
        // Remove ```json at the start and ``` at the end
        let without_start = trimmed.strip_prefix("```json").unwrap_or(trimmed);
        let without_end = without_start.strip_suffix("```").unwrap_or(without_start);
        without_end.trim().to_string()
    } else if trimmed.starts_with("```") {
        // Remove ``` at the start and ``` at the end
        let without_start = trimmed.strip_prefix("```").unwrap_or(trimmed);
        let without_end = without_start.strip_suffix("```").unwrap_or(without_start);
        without_end.trim().to_string()
    } else {
        // No fences, return as-is
        trimmed.to_string()
    }
}

/// Fallback function to extract command from malformed JSON
fn extract_command_fallback(json_str: &str) -> Option<String> {
    // Try to find "command": "..." pattern
    if let Some(start) = json_str.find("\"command\"") {
        let after_command = &json_str[start..];
        if let Some(colon_pos) = after_command.find(':') {
            let after_colon = &after_command[colon_pos + 1..].trim();
            if after_colon.starts_with('"') {
                let after_quote = &after_colon[1..];
                if let Some(end_quote) = after_quote.find('"') {
                    return Some(after_quote[..end_quote].to_string());
                }
            }
        }
    }
    None
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Get the task from command-line arguments
    let args: Vec<String> = env::args().collect();
    let user_task = if args.len() > 1 {
        args[1].clone()
    } else {
        println!("Usage: {} \"your task description\"", args[0]);
        println!("Example: {} \"find all .txt files modified in the last 7 days\"", args[0]);
        return Ok(());
    };

    // Get OpenRouter API key from environment variables
    let api_key = env::var("OPENROUTER_API_KEY")
        .expect("OPENROUTER_API_KEY must be set");

    // Define the LLM for the "Creative" brainstorming step
    let creative_llm = LLMBuilder::new()
        .backend(LLMBackend::OpenAI)
        .base_url("https://openrouter.ai/api/v1/")
        .api_key(api_key.clone())
        .model("anthropic/claude-opus-4")
        .temperature(0.8) // Higher creativity for strategy
        .build()?;

    // Define the LLM for the "Coder" command generation step
    let schema = r#"
        {
            "name": "CliCommand",
            "schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The exact shell command to execute"
                    }
                },
                "required": ["command"],
                "additionalProperties": false
            }
        }
    "#;
    let schema: StructuredOutputFormat = serde_json::from_str(schema)?;

    let coder_llm = LLMBuilder::new()
        .backend(LLMBackend::OpenAI)
        .base_url("https://openrouter.ai/api/v1/")
        .api_key(api_key.clone())
        .model("google/gemini-2.0-flash-001") // A solid model for code/command generation
        .schema(schema)
        .temperature(0.2) // Lower temperature for precise code generation
        .build()?;

    // Create a registry to manage our two different LLM configurations
    let registry = LLMRegistryBuilder::new()
        .register("creative_strategist", creative_llm)
        .register("command_generator", coder_llm)
        .build();

    println!("🤔 Task: {}", user_task);

    let first_step_template = format!(
        "Brainstorm a clever, one-line shell command strategy for this task: '{}'. Focus on the tools to pipe together (e.g., 'use find with exec, then sort, then head'). Just the strategy, not the full command.",
        user_task
    );

    // Build and run the multi-step chain
    //println!("🧠 Step 1: Brainstorming a strategy with Claude 3 Opus...");
    let chain_results = MultiPromptChain::new(&registry)
        .step(
            MultiChainStepBuilder::new(MultiChainStepMode::Chat)
                .provider_id("creative_strategist")
                .id("strategy")
                .template(&first_step_template)
                .build()?
        )
        .step(
            MultiChainStepBuilder::new(MultiChainStepMode::Chat)
                .provider_id("command_generator")
                .id("final_command")
                .template("Based on this strategy: '{{strategy}}', generate the shell command. Return ONLY valid JSON following the exact schema provided. Do not include any markdown formatting, explanations, or additional fields.")
                .build()?
        )
        .run()
        .await?;

    // Process the result
    if let Some(json_output) = chain_results.get("final_command") {
        // println!("\n🤖 Step 2: Generating command with Gemini Pro...");
        // println!("Raw output from model:");
        // println!("{}", json_output);

        // Clean the raw output to remove any Markdown fences
        let cleaned_json_str = clean_json_output(json_output);
        println!("\nCleaned JSON:");
        println!("{}", cleaned_json_str);

        // Try to deserialize the cleaned JSON string
        match serde_json::from_str::<CliCommand>(&cleaned_json_str) {
            Ok(cli_command) => {
                let final_command = cli_command.command;
                println!("\n✅ Generated Command:");
                println!("{}", final_command);

                // Copy the final command to the clipboard - keep it alive longer
                let mut clipboard = Clipboard::new()?;
                clipboard.set_text(final_command.clone())?;

                println!("\n✨ Copied to clipboard! You can now paste it in your terminal.");
                println!("💡 Tip: The command has been copied to your clipboard. Use Ctrl+V (or Cmd+V on Mac) to paste it.");

                // Keep the clipboard alive for a bit longer to ensure clipboard managers pick it up
                thread::sleep(Duration::from_millis(500));
            }
            Err(e) => {
                eprintln!("Failed to parse JSON: {}", e);
                eprintln!("Cleaned JSON was: {}", cleaned_json_str);

                // Fallback: try to extract the command using regex if JSON parsing fails
                if let Some(command) = extract_command_fallback(&cleaned_json_str) {
                    println!("\n⚠️  JSON parsing failed, but extracted command using fallback:");
                    println!("{}", command);

                    let mut clipboard = Clipboard::new()?;
                    clipboard.set_text(command.clone())?;
                    println!("\n✨ Copied to clipboard! You can now paste it in your terminal.");
                    thread::sleep(Duration::from_millis(500));
                } else {
                    return Err(e.into());
                }
            }
        }
    } else {
        eprintln!("Could not retrieve the final command from the chain results.");
    }

    Ok(())
}
