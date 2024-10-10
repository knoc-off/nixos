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

fn main() {
    let matches = App::new("nx")
        .version("0.1.0")
        .author("Nicholas Selby <selby@niko.ink>")
        .about("NixOS configuration management tool")
        // Allow both subcommands and positional arguments
        .setting(AppSettings::ArgRequiredElseHelp)
        .arg(
            Arg::with_name("force")
                .short("f")
                .long("force")
                .help("Force rebuild even if git is dirty"),
        )
        // Define subcommands
        .subcommand(SubCommand::with_name("rb").about("Rebuild and switch configuration"))
        .subcommand(SubCommand::with_name("rt").about("Test configuration"))
        .subcommand(SubCommand::with_name("cr").about("Enter nix repl"))
        .subcommand(SubCommand::with_name("vm").about("Build VM"))
        .subcommand(
            SubCommand::with_name("cd")
                .about("Change directory")
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
        // Define a positional 'query' argument for default action
        .arg(
            Arg::with_name("query")
                .multiple(true)
                .help("Query string to filter files or directories"),
        )
        .get_matches();

    // Retrieve environment variables
    let config_dir = match env::var(CONFIG_DIR_ENV) {
        Ok(val) => val,
        Err(_) => {
            eprintln!("Environment variable {} not set", CONFIG_DIR_ENV);
            exit(1);
        }
    };

    let hostname = match env::var(HOSTNAME_ENV) {
        Ok(val) => val,
        Err(_) => {
            eprintln!("Environment variable {} not set", HOSTNAME_ENV);
            exit(1);
        }
    };

    // Determine if force flag is set
    let force_flag = matches.is_present("force");

    // Handle subcommands
    let (subcommand, sub_matches_opt) = matches.subcommand();

    match subcommand {
        "rb" => handle_rb(&config_dir, &hostname, force_flag),
        "rt" => handle_rt(&config_dir, &hostname),
        "cr" => handle_cr(&config_dir, &hostname),
        "vm" => handle_vm(&config_dir, &hostname),
        "cd" => {
            if let Some(sub_matches) = sub_matches_opt {
                handle_cd(&config_dir, sub_matches)
            } else {
                eprintln!("No arguments provided for 'cd' subcommand.");
                exit(1);
            }
        },
        "rr" => {
            if let Some(sub_matches) = sub_matches_opt {
                handle_rr(&config_dir, sub_matches)
            } else {
                eprintln!("No arguments provided for 'rr' subcommand.");
                exit(1);
            }
        },
        "" => { // No subcommand given; handle default
            if let Some(query_values) = matches.values_of("query") {
                let query = query_values.collect::<Vec<&str>>().join(" ");
                handle_default(&config_dir, &query);
            } else {
                print_help_and_exit();
            }
        },
        _ => {
            eprintln!("Unknown subcommand: {}", subcommand);
            print_help_and_exit();
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
            println!("git is dirty");
            exit(1);
        }
    }

    println!("{}", if force { "Force rebuild" } else { "Rebuilding..." });

    // Execute nixos-rebuild switch
    let status = Command::new("nixos-rebuild")
        .args(&[
            "switch",
            "--flake",
            &format!("{}#{}", config_dir, hostname),
            "--use-remote-sudo",
        ])
        .status()
        .expect("Failed to execute nixos-rebuild command");

    if !status.success() {
        eprintln!("nixos-rebuild switch failed");
        exit(status.code().unwrap_or(1));
    }
}

fn handle_rt(config_dir: &str, hostname: &str) {
    println!("Testing configuration...");

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
}

fn handle_cr(config_dir: &str, hostname: &str) {
    println!("Entering nix repl...");

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
        eprintln!("nix repl failed");
        exit(status.code().unwrap_or(1));
    }
}

fn handle_vm(config_dir: &str, hostname: &str) {
    println!("Building VM...");

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
}

fn handle_cd(config_dir: &str, matches: &ArgMatches) {
    if let Some(query_values) = matches.values_of("query") {
        let query = query_values.collect::<Vec<&str>>().join(" ");
        search_and_change_directory(config_dir, &query);
    } else {
        eprintln!("No query provided for 'cd' subcommand.");
        exit(1);
    }
}

fn handle_rr(config_dir: &str, matches: &ArgMatches) {
    let update = matches.is_present("update");
    let config_path = get_config_file_path();

    // Fetch available systems
    let systems = get_available_systems(config_dir);
    if systems.is_empty() {
        eprintln!("No available systems found.");
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

    let domain = if update {
        print!("<user>@<domain/IP> for {}: ", selected_host);
        io::stdout().flush().unwrap();
        let mut domain_input = String::new();
        io::stdin()
            .read_line(&mut domain_input)
            .expect("Failed to read domain/IP");
        let domain = domain_input.trim().to_string();


        if !domain.contains('@') || domain.split('@').nth(1).map_or(true, |s| s.is_empty()) {
            eprintln!("Invalid format. Please use user@domain/IP format.");
            std::process::exit(1);
        }


        if domain.is_empty() {
            eprintln!("Domain/IP cannot be empty.");
            exit(1);
        }

        // Save the new domain/IP
        save_target_host(&config_path, &selected_host, &domain)
            .expect("Failed to save target host");

        domain
    } else {
        // Check if the selected host has a saved domain/IP
        match get_saved_domain(&config_path, &selected_host) {
            Some(domain) => {
                println!(
                    "Using saved domain/IP for {}: {}",
                    selected_host, domain
                );
                domain
            }
            None => {
                print!("<user>@<domain/IP> for {}: ", selected_host);
                io::stdout().flush().unwrap();
                let mut domain_input = String::new();
                io::stdin()
                    .read_line(&mut domain_input)
                    .expect("Failed to read domain/IP");
                let domain = domain_input.trim().to_string();


                if !domain.contains('@') || domain.split('@').nth(1).map_or(true, |s| s.is_empty()) {
                    eprintln!("Invalid format. Please use user@domain/IP format.");
                    std::process::exit(1);
                }


                if domain.is_empty() {
                    eprintln!("Domain/IP cannot be empty.");
                    exit(1);
                }

                // Save the new domain/IP
                save_target_host(&config_path, &selected_host, &domain)
                    .expect("Failed to save target host");

                domain
            }
        }
    };

    println!("Target host: {} ({})", selected_host, domain);

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
        eprintln!("nixos-rebuild switch failed");
        exit(status.code().unwrap_or(1));
    }
}

fn handle_default(config_dir: &str, query: &str) {
    // Default action: search for a file matching the query and open with nvim

    // Execute fd to find nix files
    let fd_output = Command::new("fd")
        .args(&[
            "-e",
            "nix",
            "-E",
            ".git",
            "-H",
            "--hidden",
            ".",
            &config_dir,
        ])
        .output()
        .expect("Failed to execute fd command");

    if !fd_output.status.success() {
        eprintln!("fd command failed");
        exit(fd_output.status.code().unwrap_or(1));
    }

    // Convert fd output to a string
    let fd_results = String::from_utf8_lossy(&fd_output.stdout).to_string();

    // Pipe results to fzf with the constructed query
    let mut fzf_command = Command::new("fzf")
        .arg("--query")
        .arg(&query)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to spawn fzf command");

    // Write fd_results to fzf's stdin
    if let Some(mut stdin) = fzf_command.stdin.take() {
        stdin.write_all(fd_results.as_bytes()).expect("Failed to write to fzf stdin");
    }

    // Get the output from fzf
    let fzf_output = fzf_command.wait_with_output().expect("Failed to wait on fzf command");

    if fzf_output.status.success() {
        let file = String::from_utf8_lossy(&fzf_output.stdout).trim().to_string();
        if !file.is_empty() {
            // Check if the selected path is a file
            let path = PathBuf::from(&file);
            if path.is_file() {
                println!("Selected file: {}", file);
                // Open the selected file with nvim
                let status = Command::new("nvim")
                    .arg(&file)
                    .status()
                    .expect("Failed to execute nvim");

                if !status.success() {
                    eprintln!("nvim failed to open the file");
                    std::process::exit(status.code().unwrap_or(1));
                }
            } else {
                println!("Selected path is not a file: {}", file);
            }
        } else {
            println!("No file selected.");
        }
    } else {
        eprintln!("fzf was canceled or failed");
        std::process::exit(fzf_output.status.code().unwrap_or(1));
    }
}

fn search_and_change_directory(config_dir: &str, query: &str) {
    // Execute fd to find directories
    let fd_output = Command::new("fd")
        .args(&[
            "-t",
            "d",
            "-E",
            ".git",
            "-H",
            "--hidden",
            ".",
            &config_dir,
        ])
        .output()
        .expect("Failed to execute fd command");

    if !fd_output.status.success() {
        eprintln!("fd command failed");
        exit(fd_output.status.code().unwrap_or(1));
    }

    let fd_results = String::from_utf8_lossy(&fd_output.stdout).to_string();

    // Pipe results to fzf with query
    let mut fzf_command = Command::new("fzf")
        .arg("--query")
        .arg(&query)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to spawn fzf command");

    // Write fd_results to fzf's stdin
    if let Some(mut stdin) = fzf_command.stdin.take() {
        stdin.write_all(fd_results.as_bytes()).expect("Failed to write to fzf stdin");
    }

    // Get the output from fzf
    let fzf_output = fzf_command.wait_with_output().expect("Failed to wait on fzf command");

    if fzf_output.status.success() {
        let dir = String::from_utf8_lossy(&fzf_output.stdout).trim().to_string();
        if !dir.is_empty() {
            let path = PathBuf::from(&dir);
            if path.is_dir() {
                println!("{}", dir);
                env::set_current_dir(&path);
                // Spawn a new shell in the selected directory
                let status = Command::new("/usr/bin/env")
                    .arg("bash")
                    .arg("-c")
                    .arg(format!("cd '{}' && exec bash", dir.replace("'", "'\\''")))
                    .status()
                    .expect("Failed to spawn shell");

                if !status.success() {
                    eprintln!("Failed to start shell in the selected directory");
                    std::process::exit(status.code().unwrap_or(1));
                }

            } else {
                println!("Selected path is not a directory: {}", dir);
            }
        } else {
            println!("No directory selected.");
        }
    } else {
        eprintln!("fzf was canceled or failed");
        std::process::exit(fzf_output.status.code().unwrap_or(1));
    }
}

fn get_available_systems(config_dir: &str) -> Vec<String> {
    let expr = format!(r#"
    let
        flake = builtins.getFlake "{}";
    in
    builtins.attrNames flake.nixosConfigurations
    "#, config_dir);


    let output = Command::new("nix")
        .args(&["eval", "--impure", "--expr", &expr, "--json"])
        .output()
        .expect("Failed to execute nix eval command");

    if !output.status.success() {
        eprintln!("nix eval command failed");
        exit(output.status.code().unwrap_or(1));
    }

    let systems: Vec<String> = serde_json::from_slice(&output.stdout)
        .expect("Failed to parse JSON output from nix eval");

    systems
}

fn select_with_fzf(options: &[String], prompt: &str) -> Option<String> {
    let mut child = Command::new("fzf")
        .arg("--prompt")
        .arg(prompt)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to execute fzf command");

    {
        let stdin = child
            .stdin
            .as_mut()
            .expect("Failed to open fzf stdin");
        for option in options {
            writeln!(stdin, "{}", option).expect("Failed to write to fzf stdin");
        }
    }

    let output = child.wait_with_output().expect("Failed to wait on fzf child");

    if output.status.success() {
        let selection = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !selection.is_empty() {
            Some(selection)
        } else {
            None
        }
    } else {
        None
    }
}

fn get_config_file_path() -> PathBuf {
    let home_dir = dirs::home_dir().expect("Failed to get home directory");
    home_dir.join(NX_CONFIG_DIR).join(TARGET_HOST_FILE)
}

fn save_target_host(path: &PathBuf, host: &str, domain: &str) -> io::Result<()> {
    let mut hosts: HashMap<String, HostConfig> = if path.exists() {
        let content = fs::read_to_string(path)?;
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        HashMap::new()
    };

    hosts.insert(host.to_string(), HostConfig { domain: domain.to_string() });

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let content = serde_json::to_string_pretty(&hosts)?;
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

fn read_target_host(path: &PathBuf) -> io::Result<(String, HostConfig)> {
    let content = fs::read_to_string(path)?;
    let hosts: HashMap<String, HostConfig> = serde_json::from_str(&content)?;
    hosts.into_iter()
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "No target host found"))
}

fn print_help_and_exit() -> ! {
    let mut app = App::new("nx")
        .version("0.1.0")
        .author("Your Name <you@example.com>")
        .about("NixOS configuration management tool");
    app.print_help().unwrap();
    println!();
    exit(1);
}
