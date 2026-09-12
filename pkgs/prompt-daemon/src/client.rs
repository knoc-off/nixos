use std::collections::HashMap;

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
    let cwd = std::env::current_dir()?.to_string_lossy().into_owned();
    let env: HashMap<String, String> = std::env::vars().collect();

    let stream = UnixStream::connect(socket_path()).await?;
    let (mut reader, mut writer) = stream.into_split();

    protocol::write_request(&mut writer, command, &cwd, &env).await?;
    let (_status, value) = protocol::read_response(&mut reader).await?;

    print!("{value}");
    Ok(())
}

async fn run_status() -> Result<(), Box<dyn std::error::Error>> {
    let stream = UnixStream::connect(socket_path()).await?;
    let (mut reader, mut writer) = stream.into_split();

    protocol::write_request(&mut writer, "", "", &HashMap::new()).await?;
    let (_status, value) = protocol::read_response(&mut reader).await?;

    print!("{value}");
    Ok(())
}
