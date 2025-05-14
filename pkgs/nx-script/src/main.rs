use clap::{App, Arg, ArgMatches, SubCommand, AppSettings};
use dirs;
use serde::{Deserialize, Serialize};
use serde_json;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, exit};

// Constants for environment variables and config paths
const CONFIG_DIR_ENV: &str = "config_dir";
const HOSTNAME_ENV: &str = "hostname";
const NX_CONFIG_DIR: &str = ".config/nx";
const TARGET_HOST_FILE: &str = "target_host.json";

#[derive(Serialize, Deserialize, Debug)]
struct HostConfig {
    domain: String,
}

// Function to build the clap App definition
fn build_cli<'a, 'b>() -> App<'a, 'b> {
    App::new("nx")
        .version("0.1.0")
        .author("Nicholas Selby <selby@niko.ink>")
        .about("NixOS configuration management tool")
        // Allow both subcommands and positional arguments
        .setting(AppSettings::ArgRequiredElseHelp)
        .arg(
            Arg::with_name("force")
                .short("f")
                .long("force")
                .global(true)
                .help("Force rebuild even if git is dirty"),
        )
        // Define subcommands
        .subcommand(SubCommand::with_name("rb").about("Rebuild and switch configuration"))
        .subcommand(SubCommand::with_name("rt").about("Test configuration"))
        .subcommand(SubCommand::with_name("cr").about("Enter nix repl"))
        .subcommand(SubCommand::with_name("vm").about("Build VM"))
        .subcommand(
            SubCommand::with_name("cd")
                .about("Change directory within config")
                .arg(
                    Arg::with_name("query")
                        .multiple(true)
                        .help("Query string to filter directories"),
                ),
        )
        .subcommand(
            SubCommand::with_name("rr")
                .about("Rebuild remote")
                .arg(
                    Arg::with_name("update")
                        .short("u")
                        .long("update")
                        .help("Update the target host"),
                ),
        )
        .subcommand(
            SubCommand::with_name("nix-completions")
                .about("Generate nix command completions for flake configurations (experimental)")
        )
        // Define a positional 'query' argument for default action (file search)
        .arg(
            Arg::with_name("query")
                .index(1) // Make it a positional argument
                .multiple(true)
                .help("Query string to filter files for editing (default action)"),
        )
}

fn main() {
    let matches = build_cli().get_matches();

    // Retrieve environment variables
    let config_dir = match env::var(CONFIG_DIR_ENV) {
        Ok(val) => val,
        Err(_) => {
            eprintln!("Error: Environment variable {} not set.", CONFIG_DIR_ENV);
            eprintln!("Please set {} to the path of your NixOS configuration flake.", CONFIG_DIR_ENV);
            exit(1);
        }
    };

    let hostname = match env::var(HOSTNAME_ENV) {
        Ok(val) => val,
        Err(_) => {
            eprintln!("Warning: Environment variable {} not set.", HOSTNAME_ENV);
            eprintln!("Some commands might require it. Attempting to proceed.");
            String::new() // Empty string as default
        }
    };

    // Determine if force flag is set
    let force_flag = matches.is_present("force");

    // Handle subcommands
    match matches.subcommand() {
        ("rb", _) => {
            if hostname.is_empty() {
                eprintln!("Error: Hostname is required for 'rb' command. Set the {} environment variable.", HOSTNAME_ENV);
                exit(1);
            }
            handle_rb(&config_dir, &hostname, force_flag)
        },
        ("rt", _) => {
            if hostname.is_empty() {
                eprintln!("Error: Hostname is required for 'rt' command. Set the {} environment variable.", HOSTNAME_ENV);
                exit(1);
            }
            handle_rt(&config_dir, &hostname)
        },
        ("cr", _) => {
            if hostname.is_empty() {
                eprintln!("Error: Hostname is required for 'cr' command. Set the {} environment variable.", HOSTNAME_ENV);
                exit(1);
            }
            handle_cr(&config_dir, &hostname)
        },
        ("vm", _) => {
            if hostname.is_empty() {
                eprintln!("Error: Hostname is required for 'vm' command. Set the {} environment variable.", HOSTNAME_ENV);
                exit(1);
            }
            handle_vm(&config_dir, &hostname)
        },
        ("cd", Some(sub_matches)) => handle_cd(&config_dir, sub_matches),
        ("rr", Some(sub_matches)) => handle_rr(&config_dir, sub_matches),
        ("nix-completions", _) => handle_nix_completions(&config_dir),
        (_, _) => { // No recognized subcommand given; handle default (file search) or show help
            if let Some(query_values) = matches.values_of("query") {
                let query = query_values.collect::<Vec<&str>>().join(" ");
                handle_default(&config_dir, &query);
            } else {
                // If no subcommand and no query, print help via clap
                let _ = build_cli().print_help();
                println!();
                exit(1);
            }
        }
    }
}

fn handle_rb(config_dir: &str, hostname: &str, force: bool) {
    if !force {
        // Check if git is dirty
        let output = Command::new("git")
            .args(&["status", "--porcelain"])
            .current_dir(config_dir)
            .output()
            .expect("Failed to execute git command");

        if !output.stdout.is_empty() {
            eprintln!("Git repository is dirty. Commit changes or use --force (-f).");
            exit(1);
        }
        println!("Git repository is clean.");
    }

    println!(
        "{} Rebuilding system '{}' from flake '{}'...",
        if force { "Forcing" } else { "Starting" },
        hostname,
        config_dir
    );

    // Execute nixos-rebuild switch
    let status = Command::new("sudo")
        .args(&[
            "nixos-rebuild",
            "switch",
            "--flake",
            &format!("{}#{}", config_dir, hostname),
        ])
        .status()
        .expect("Failed to execute nixos-rebuild command");

    if !status.success() {
        eprintln!("nixos-rebuild switch failed");
        exit(status.code().unwrap_or(1));
    }
    println!("System rebuild successful.");
}

fn handle_rt(config_dir: &str, hostname: &str) {
    println!(
        "Testing configuration '{}' from flake '{}'...",
        hostname, config_dir
    );

    // Execute nixos-rebuild test
    let status = Command::new("nixos-rebuild")
        .args(&[
            "test",
            "--flake",
            &format!("{}#{}", config_dir, hostname),
            "--use-remote-sudo",
        ])
        .status()
        .expect("Failed to execute nixos-rebuild command");

    if !status.success() {
        eprintln!("nixos-rebuild test failed");
        exit(status.code().unwrap_or(1));
    }
    println!("Configuration test successful.");
}

fn handle_cr(config_dir: &str, hostname: &str) {
    println!(
        "Entering nix repl for configuration '{}' from flake '{}'...",
        hostname, config_dir
    );

    // Execute nix repl
    let status = Command::new("nix")
        .args(&[
            "repl",
            "--extra-experimental-features",
            "repl-flake",
            &format!("{}#nixosConfigurations.{}", config_dir, hostname),
        ])
        .status()
        .expect("Failed to execute nix repl command");

    if !status.success() {
        eprintln!("nix repl exited (code: {})", status.code().unwrap_or(-1));
    }
}

fn handle_vm(config_dir: &str, hostname: &str) {
    println!(
        "Building VM for configuration '{}' from flake '{}'...",
        hostname, config_dir
    );

    // Execute nixos-rebuild build-vm
    let status = Command::new("nixos-rebuild")
        .args(&[
            "build-vm",
            "--flake",
            &format!("{}#{}", config_dir, hostname),
            "--use-remote-sudo",
        ])
        .status()
        .expect("Failed to execute nixos-rebuild command");

    if !status.success() {
        eprintln!("nixos-rebuild build-vm failed");
        exit(status.code().unwrap_or(1));
    }
    println!("VM build successful. Run result/bin/run-*-vm");
}

fn handle_cd(config_dir: &str, matches: &ArgMatches) {
    let query_vec: Vec<&str> = matches.values_of("query").unwrap_or_default().collect();
    let query = query_vec.join(" ");
    // Pass an empty string if no query provided, fzf will handle it
    search_and_change_directory(config_dir, &query);
}

fn handle_rr(config_dir: &str, matches: &ArgMatches) {
    let update = matches.is_present("update");
    let config_path = get_config_file_path();

    // Fetch available systems
    println!("Fetching available systems from flake '{}'...", config_dir);
    let systems = get_available_systems(config_dir);
    if systems.is_empty() {
        eprintln!("No available NixOS configurations found in flake '{}'.", config_dir);
        eprintln!("Ensure your flake exposes an attribute set named 'nixosConfigurations'.");
        exit(1);
    }

    // Always prompt the user to select a system
    let selected_host = match select_with_fzf(&systems, "Select target system: ") {
        Some(host) => host,
        None => {
            eprintln!("No system selected.");
            exit(1);
        }
    };
    println!("Selected system: {}", selected_host);

    let mut saved_domain: Option<String> = None;
    if !update {
        saved_domain = get_saved_domain(&config_path, &selected_host);
    }

    let domain = match saved_domain {
         Some(d) if !update => {
             println!("Using saved target for {}: {}", selected_host, d);
             d
         }
         _ => { // Either update is true or no saved domain found
             if update {
                 println!("Updating target host for '{}'.", selected_host);
             } else {
                 println!("No saved target found for '{}'. Please provide one.", selected_host);
             }

             print!("<user>@<domain/IP> for {}: ", selected_host);
             io::stdout().flush().unwrap();
             let mut domain_input = String::new();
             io::stdin()
                 .read_line(&mut domain_input)
                 .expect("Failed to read domain/IP");
             let domain = domain_input.trim().to_string();

             if domain.is_empty() {
                 eprintln!("Error: Target host cannot be empty.");
                 exit(1);
             }
             if !domain.contains('@') || domain.split('@').nth(1).map_or(true, |s| s.is_empty()) {
                 eprintln!("Error: Invalid format. Please use user@domain/IP format.");
                 exit(1);
             }

             // Save the new domain/IP
             println!("Saving target {} for host '{}' to {:?}...", domain, selected_host, config_path);
             save_target_host(&config_path, &selected_host, &domain)
                 .expect("Failed to save target host configuration");

             domain
         }
    };

    println!(
        "Starting remote rebuild for system '{}' on target '{}'...",
        selected_host, domain
    );

    // Execute nixos-rebuild switch for the target host
    let status = Command::new("nixos-rebuild")
        .args(&[
            "switch",
            "--flake",
            &format!("{}#{}", config_dir, selected_host),
            "--target-host",
            &domain,
            "--use-remote-sudo",
        ])
        .status()
        .expect("Failed to execute nixos-rebuild command");

    if !status.success() {
        eprintln!("Remote nixos-rebuild switch failed");
        exit(status.code().unwrap_or(1));
    }
    println!("Remote rebuild successful.");
}

fn handle_default(config_dir: &str, query: &str) {
    // Default action: search for a file matching the query and open with nvim
    println!("Searching for files matching '{}' in '{}'...", query, config_dir);

    // Execute fd to find nix files
    let fd_output = Command::new("fd")
        .args(&[
            "--type",
            "file",
            "--extension",
            "nix",
            "--exclude",
            ".git",
            "--hidden",
            "--absolute-path",
            ".",
            config_dir,
        ])
        .output()
        .expect("Failed to execute fd command. Is 'fd' installed and in PATH?");

    if !fd_output.status.success() {
        eprintln!(
            "fd command failed with status: {}",
            fd_output.status
        );
        eprintln!("Stderr: {}", String::from_utf8_lossy(&fd_output.stderr));
        exit(fd_output.status.code().unwrap_or(1));
    }

    // Convert fd output to a string
    let fd_results = String::from_utf8_lossy(&fd_output.stdout).to_string();
    if fd_results.trim().is_empty() {
        println!("No '.nix' files found in '{}'.", config_dir);
        exit(0);
    }

    // Pipe results to fzf with the constructed query
    println!("Piping results to fzf with query: '{}'", query);
    let mut fzf_command = Command::new("fzf")
        .arg("--query")
        .arg(query)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to spawn fzf command. Is 'fzf' installed and in PATH?");

    // Write fd_results to fzf's stdin
    if let Some(mut stdin) = fzf_command.stdin.take() {
        stdin
            .write_all(fd_results.as_bytes())
            .expect("Failed to write to fzf stdin");
    } // stdin is dropped here, closing the pipe

    // Get the output from fzf
    let fzf_output = fzf_command
        .wait_with_output()
        .expect("Failed to wait on fzf command");

    if fzf_output.status.success() {
        let file = String::from_utf8_lossy(&fzf_output.stdout)
            .trim()
            .to_string();
        if !file.is_empty() {
            // fd already gave us an absolute path, check if it's a file just in case
            let path = PathBuf::from(&file);
            if path.is_file() {
                println!("Opening selected file: {}", file);
                // Open the selected file with nvim (or $EDITOR)
                let editor = env::var("EDITOR").unwrap_or_else(|_| "nvim".to_string());
                let status = Command::new(&editor)
                    .arg(&file)
                    .status()
                    .expect(&format!("Failed to execute editor '{}'", editor));

                if !status.success() {
                    eprintln!("Editor '{}' failed to open the file.", editor);
                    exit(status.code().unwrap_or(1));
                }
            } else {
                // This shouldn't happen if fd worked correctly with --type file
                eprintln!("Selected path is not a file (unexpected): {}", file);
                exit(1);
            }
        } else {
            println!("No file selected from fzf.");
            exit(0); // Exiting normally if user selected nothing in fzf
        }
    } else {
        // fzf returns non-zero status if user cancels (e.g., Esc)
        eprintln!("fzf selection canceled or failed (exit code: {}).", fzf_output.status);
        // Exit normally on cancellation, non-normally on other errors
        exit(if fzf_output.status.code() == Some(130) { 0 } else { fzf_output.status.code().unwrap_or(1) });
    }
}

fn search_and_change_directory(config_dir: &str, query: &str) {
    println!("Searching for directories matching '{}' in '{}'...", query, config_dir);
    // Execute fd to find directories
    let fd_output = Command::new("fd")
        .args(&[
            "--type",
            "directory",
            "--exclude",
            ".git",
            "--hidden",
            "--absolute-path",
            ".",
            config_dir,
        ])
        .output()
        .expect("Failed to execute fd command. Is 'fd' installed and in PATH?");

    if !fd_output.status.success() {
        eprintln!(
            "fd command failed with status: {}",
            fd_output.status
        );
        eprintln!("Stderr: {}", String::from_utf8_lossy(&fd_output.stderr));
        exit(fd_output.status.code().unwrap_or(1));
    }

    let fd_results = String::from_utf8_lossy(&fd_output.stdout).to_string();
    if fd_results.trim().is_empty() {
        println!("No directories found in '{}'.", config_dir);
        exit(0);
    }

    // Pipe results to fzf with query
    println!("Piping results to fzf with query: '{}'", query);
    let mut fzf_command = Command::new("fzf")
        .arg("--query")
        .arg(query)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to spawn fzf command. Is 'fzf' installed and in PATH?");

    // Write fd_results to fzf's stdin
    if let Some(mut stdin) = fzf_command.stdin.take() {
        stdin
            .write_all(fd_results.as_bytes())
            .expect("Failed to write to fzf stdin");
    } // stdin is dropped here

    // Get the output from fzf
    let fzf_output = fzf_command
        .wait_with_output()
        .expect("Failed to wait on fzf command");

    if fzf_output.status.success() {
        let dir = String::from_utf8_lossy(&fzf_output.stdout)
            .trim()
            .to_string();
        if !dir.is_empty() {
            let path = PathBuf::from(&dir);
            if path.is_dir() {
                // Output the directory path. The calling shell script must handle the 'cd'.
                // This Rust program cannot change the working directory of its parent shell.
                println!("{}", dir);
                // We cannot 'cd' the parent shell from here.
                // The typical pattern is for the shell function/alias calling this Rust program
                // to capture the stdout and 'cd' to it.
                exit(0); // Exit successfully after printing the path
            } else {
                // Should not happen with fd --type directory
                eprintln!("Selected path is not a directory (unexpected): {}", dir);
                exit(1);
            }
        } else {
            eprintln!("No directory selected from fzf.");
            exit(1); // Exit with error if nothing selected
        }
    } else {
        eprintln!("fzf selection canceled or failed (exit code: {}).", fzf_output.status);
        // Exit normally on cancellation (130), non-normally on other errors
        exit(if fzf_output.status.code() == Some(130) { 0 } else { fzf_output.status.code().unwrap_or(1) });
    }
}

fn get_available_systems(config_dir: &str) -> Vec<String> {
    println!("Fetching available systems using NIX_GET_COMPLETIONS...");

    // Ensure config_dir is a valid path
    let flake_path = PathBuf::from(config_dir);
    if !flake_path.exists() {
        eprintln!("Error: Configuration directory '{}' does not exist.", config_dir);
        exit(1);
    }

    // Use canonical path if possible for better reliability
    let canonical_path = flake_path.canonicalize()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|e| {
            eprintln!("Warning: Could not get canonical path for '{}': {}", config_dir, e);
            config_dir.to_string() // Fallback to original path
        });

    // Format the flake URI with trailing dot to trigger completion for nixosConfigurations
    let flake_uri = format!("{}#nixosConfigurations.", canonical_path);

    // Run the command with NIX_GET_COMPLETIONS=2 environment variable
    let output = Command::new("env")
        .env("NIX_GET_COMPLETIONS", "2")
        .args(&["nix", "shell", &flake_uri])
        .output()
        .expect("Failed to execute nix completion command. Make sure nix is installed.");

    if !output.status.success() {
        eprintln!(
            "Error: nix completion command failed with status: {}",
            output.status
        );
        eprintln!("Stderr: {}", String::from_utf8_lossy(&output.stderr));
        exit(output.status.code().unwrap_or(1));
    }

    // Parse the output to extract system names
    let stdout = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = stdout.lines().collect();

    // Skip the first line ("attrs") and extract system names from full paths
    let mut systems = Vec::new();

    // Start from index 1 to skip the "attrs" line
    for i in 1..lines.len() {
        let trimmed = lines[i].trim();
        if trimmed.is_empty() {
            continue;
        }

        // Extract just the system name from the full path
        // Format is like: "/path/to/config#nixosConfigurations.system_name"
        if let Some(suffix) = trimmed.split("nixosConfigurations.").nth(1) {
            systems.push(suffix.trim().to_string());
        } else {
            // If we can't parse the name correctly, log a warning and skip
            eprintln!("Warning: Could not parse system name from '{}'", trimmed);
        }
    }

    if systems.is_empty() {
        eprintln!("Warning: No NixOS configurations found in '{}'", config_dir);
    } else {
        println!("Found {} systems: {:?}", systems.len(), systems);
    }

    systems
}

fn select_with_fzf(options: &[String], prompt: &str) -> Option<String> {
    if options.is_empty() {
        return None; // No options to select from
    }

    let mut child = Command::new("fzf")
        .arg("--prompt")
        .arg(prompt)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to execute fzf command. Is 'fzf' installed and in PATH?");

    {
        // Use a block to ensure stdin is closed after writing
        let stdin = child
            .stdin
            .as_mut()
            .expect("Failed to open fzf stdin");
        for option in options {
            // Write each option followed by a newline
            if let Err(e) = writeln!(stdin, "{}", option) {
                 // Handle potential broken pipe errors if fzf exits early
                 eprintln!("Warning: Failed to write to fzf stdin: {}", e);
                 break; // Stop writing if pipe is broken
             }
        }
    } // stdin is dropped here, closing the pipe

    let output = match child.wait_with_output() {
         Ok(out) => out,
         Err(e) => {
             eprintln!("Failed to wait on fzf child process: {}", e);
             return None;
         }
     };


    if output.status.success() {
        let selection = String::from_utf8_lossy(&output.stdout)
            .trim()
            .to_string();
        if !selection.is_empty() {
            Some(selection)
        } else {
            // fzf exited successfully but produced no output (shouldn't happen with selection)
            None
        }
    } else {
        // fzf returns non-zero status on cancellation (e.g., Esc key)
        // We consider cancellation as "no selection made" -> None
        eprintln!("fzf selection canceled or failed (exit code: {}).", output.status);
        None
    }
}

fn get_config_file_path() -> PathBuf {
    let home_dir = dirs::home_dir().expect("Failed to get home directory");
    let config_dir = home_dir.join(NX_CONFIG_DIR);
    // Create the directory if it doesn't exist before returning the file path
    if let Err(e) = fs::create_dir_all(&config_dir) {
        eprintln!("Warning: Could not create config directory {:?}: {}", config_dir, e);
    }
    config_dir.join(TARGET_HOST_FILE)
}

fn save_target_host(path: &PathBuf, host: &str, domain: &str) -> io::Result<()> {
    let mut hosts: HashMap<String, HostConfig> = if path.exists() {
        match fs::read_to_string(path) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_else(|e| {
                eprintln!("Warning: Could not parse existing config file {:?}: {}. Starting fresh.", path, e);
                HashMap::new()
            }),
            Err(e) => {
                eprintln!("Warning: Could not read existing config file {:?}: {}. Starting fresh.", path, e);
                HashMap::new()
            }
        }
    } else {
        HashMap::new()
    };

    hosts.insert(
        host.to_string(),
        HostConfig {
            domain: domain.to_string(),
        },
    );

    // Ensure parent directory exists (get_config_file_path attempts this, but double-check)
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?; // Propagate IO error if creation fails here
    }
    let content = serde_json::to_string_pretty(&hosts)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("JSON serialization failed: {}", e)))?;
    fs::write(path, content)
}

fn get_saved_domain(path: &PathBuf, host: &str) -> Option<String> {
    if path.exists() {
        let content = fs::read_to_string(path).ok()?;
        let hosts: HashMap<String, HostConfig> = serde_json::from_str(&content).ok()?;
        hosts.get(host).map(|config| config.domain.clone())
    } else {
        None
    }
}

fn handle_nix_completions(config_dir: &str) {
    println!(
        "# Generating nix command completions for flake configurations in '{}'",
        config_dir
    );
    println!("# To use, source the output in your shell: source <(nx nix-completions)");
    println!("# Note: This provides completions for 'nix' commands interacting with the flake,");
    println!("# not completions for the 'nx' tool itself.");

    // Ensure config_dir is a valid path before passing to nix
    let flake_path = PathBuf::from(config_dir);
    if !flake_path.exists() {
        eprintln!("Error: Configuration directory '{}' does not exist.", config_dir);
        exit(1);
    }
    // Use canonical path if possible
    let canonical_path = flake_path.canonicalize()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|e| {
            eprintln!("Warning: Could not get canonical path for '{}': {}", config_dir, e);
            config_dir.to_string() // Fallback to original path
        });

    let flake_uri = format!("{}#nixosConfigurations", canonical_path);

    let output = Command::new("env")
        .env("NIX_GET_COMPLETIONS", "2")
        .arg("nix")
        .args(&[
            "shell", // Use the 'shell' subcommand as requested
            &flake_uri,
            "--extra-experimental-features",
            "nix-command flakes",
        ])
        .output()
        .expect("Failed to execute nix shell command for completions. Is 'nix' installed and in PATH?");

    if !output.status.success() {
        eprintln!(
            "nix shell command for completions failed with status: {}",
            output.status
        );
        eprintln!("Stderr: {}", String::from_utf8_lossy(&output.stderr));
        // Provide hints based on common errors
        if String::from_utf8_lossy(&output.stderr).contains("experimental Nix feature") {
             eprintln!("Hint: Ensure flakes and nix-command are enabled in your nix configuration or use --extra-experimental-features 'nix-command flakes'.");
        }
        if String::from_utf8_lossy(&output.stderr).contains("cannot find flake") {
             eprintln!("Hint: Ensure '{}' is a valid flake path.", canonical_path);
        }
         if String::from_utf8_lossy(&output.stderr).contains("does not provide attribute 'nixosConfigurations'") {
             eprintln!("Hint: Ensure your flake.nix file defines the output 'nixosConfigurations'.");
         }
        exit(output.status.code().unwrap_or(1));
    }

    // Print the completion script directly to stdout
    if let Err(e) = io::stdout().write_all(&output.stdout) {
         eprintln!("Error writing completion script to stdout: {}", e);
         exit(1);
     }
     // No newline needed usually, as the script should be complete
     io::stdout().flush().unwrap(); // Ensure output is flushed

     // Exit successfully
     exit(0);
}

