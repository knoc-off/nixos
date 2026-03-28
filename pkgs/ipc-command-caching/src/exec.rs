use std::collections::HashMap;
use std::process::Stdio;

/// Execute a command, optionally via a shell, with a timeout.
/// If `cwd` is Some, the command runs in that directory.
/// All entries in `env` are passed as environment variables to the command.
pub async fn run_command(
    run: &str,
    shell: bool,
    env: &HashMap<String, String>,
    timeout: std::time::Duration,
    cwd: Option<&str>,
) -> Result<String, String> {
    let mut cmd = if shell {
        let mut c = tokio::process::Command::new("/bin/sh");
        c.arg("-c").arg(run);
        c
    } else {
        let mut parts = run.split_whitespace();
        let program = parts.next().unwrap_or("");
        let args: Vec<&str> = parts.collect();
        let mut c = tokio::process::Command::new(program);
        c.args(&args);
        c
    };

    cmd.envs(env)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }

    let child = cmd.spawn().map_err(|e| format!("spawn: {e}"))?;

    let output = tokio::time::timeout(timeout, child.wait_with_output())
        .await
        .map_err(|_| "timeout".to_string())?
        .map_err(|e| format!("wait: {e}"))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(format!(
            "exit {}: {}",
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}
