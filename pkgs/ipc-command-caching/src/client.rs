use tokio::net::UnixStream;

use prompt_daemon::config::socket_path;
use prompt_daemon::ipc::protocol;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.is_empty() {
        eprintln!("usage: prompt-client <command_name>");
        eprintln!("       prompt-client status");
        std::process::exit(1);
    }

    // Starship compatibility: strips "-c" prefix
    let command = if args[0] == "-c" {
        if args.len() < 2 {
            eprintln!("error: -c requires a command");
            std::process::exit(1);
        }
        &args[1]
    } else {
        &args[0]
    };

    let result = if command == "status" {
        run_status().await
    } else {
        run_query(command).await
    };

    if let Err(e) = result {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}

async fn run_query(command: &str) -> Result<(), Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?
        .to_string_lossy()
        .into_owned();

    let stream = UnixStream::connect(socket_path()).await?;
    let (mut reader, mut writer) = stream.into_split();

    // Phase 1: send command name + CWD
    protocol::write_command(&mut writer, command, &cwd).await?;

    // Phase 2: read required env var names from daemon
    let var_names = protocol::read_env_request(&mut reader).await?;

    // Phase 3: look up each var in our environment, send values back
    let values: Vec<String> = var_names
        .iter()
        .map(|name| std::env::var(name).unwrap_or_default())
        .collect();
    protocol::write_env_values(&mut writer, &values).await?;

    // Phase 4: read response
    let (_status, value) = protocol::read_response(&mut reader).await?;

    print!("{value}");
    Ok(())
}

async fn run_status() -> Result<(), Box<dyn std::error::Error>> {
    let stream = UnixStream::connect(socket_path()).await?;
    let (mut reader, mut writer) = stream.into_split();

    // Status query: send empty command + empty CWD
    protocol::write_command(&mut writer, "", "").await?;

    // Daemon skips phases 2-3, goes straight to response
    let (_status, value) = protocol::read_response(&mut reader).await?;

    print!("{value}");
    Ok(())
}
