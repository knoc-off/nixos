//! 4-phase IPC wire protocol.
//!
//! Normal query (4 messages on one connection):
//!   1. Client → Daemon:  [cmd_len: u16 LE] [cwd_len: u16 LE] [command] [cwd]
//!   2. Daemon → Client:  [env_count: u8] [var_name\0 ...]
//!   3. Client → Daemon:  [env_count: u8] [env_val\0 ...]
//!   4. Daemon → Client:  [status: u8] [value_len: u16 LE] [value: bytes]
//!
//! Status query (2 messages):
//!   1. Client → Daemon:  [cmd_len: u16 LE = 0] [cwd_len: u16 LE = 0]
//!   2. Daemon → Client:  [status: u8] [value_len: u16 LE] [value: bytes]

use tokio::io::{AsyncReadExt, AsyncWriteExt};

// ── Phase 1: Client sends command name + CWD ───────────────────────

/// Write command name and CWD to the wire (client side).
/// Send cmd_len=0 and cwd_len=0 for a status query.
pub async fn write_command<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    command: &str,
    cwd: &str,
) -> std::io::Result<()> {
    let cmd_bytes = command.as_bytes();
    let cwd_bytes = cwd.as_bytes();
    let cmd_len = cmd_bytes.len().min(u16::MAX as usize) as u16;
    let cwd_len = cwd_bytes.len().min(u16::MAX as usize) as u16;

    writer.write_u16_le(cmd_len).await?;
    writer.write_u16_le(cwd_len).await?;
    if cmd_len > 0 {
        writer.write_all(&cmd_bytes[..cmd_len as usize]).await?;
    }
    if cwd_len > 0 {
        writer.write_all(&cwd_bytes[..cwd_len as usize]).await?;
    }
    writer.flush().await?;
    Ok(())
}

/// Read command name and CWD from the wire (daemon side).
/// Returns `(command, cwd, is_status_query)`.
pub async fn read_command<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<(String, String, bool)> {
    let cmd_len = reader.read_u16_le().await?;
    let cwd_len = reader.read_u16_le().await?;

    if cmd_len == 0 && cwd_len == 0 {
        return Ok((String::new(), String::new(), true));
    }

    let command = if cmd_len > 0 {
        let mut buf = vec![0u8; cmd_len as usize];
        reader.read_exact(&mut buf).await?;
        String::from_utf8(buf)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?
    } else {
        String::new()
    };

    let cwd = if cwd_len > 0 {
        let mut buf = vec![0u8; cwd_len as usize];
        reader.read_exact(&mut buf).await?;
        String::from_utf8(buf)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?
    } else {
        String::new()
    };

    Ok((command, cwd, false))
}

// ── Phase 2: Daemon sends required env var names ────────────────────

/// Write the list of required env var names (daemon side).
pub async fn write_env_request<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    var_names: &[String],
) -> std::io::Result<()> {
    let count = var_names.len().min(u8::MAX as usize) as u8;
    writer.write_u8(count).await?;
    for name in var_names.iter().take(count as usize) {
        writer.write_all(name.as_bytes()).await?;
        writer.write_u8(0).await?;
    }
    writer.flush().await?;
    Ok(())
}

/// Read the list of required env var names (client side).
pub async fn read_env_request<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<Vec<String>> {
    let count = reader.read_u8().await?;
    let mut names = Vec::with_capacity(count as usize);
    for _ in 0..count {
        names.push(read_null_terminated(reader).await?);
    }
    Ok(names)
}

// ── Phase 3: Client sends env var values ────────────────────────────

/// Write env var values back to the daemon (client side).
/// Values must be in the same order as the names from phase 2.
pub async fn write_env_values<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    values: &[String],
) -> std::io::Result<()> {
    let count = values.len().min(u8::MAX as usize) as u8;
    writer.write_u8(count).await?;
    for val in values.iter().take(count as usize) {
        writer.write_all(val.as_bytes()).await?;
        writer.write_u8(0).await?;
    }
    writer.flush().await?;
    Ok(())
}

/// Read env var values from the client (daemon side).
pub async fn read_env_values<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<Vec<String>> {
    let count = reader.read_u8().await?;
    let mut values = Vec::with_capacity(count as usize);
    for _ in 0..count {
        values.push(read_null_terminated(reader).await?);
    }
    Ok(values)
}

// ── Phase 4: Daemon sends response ──────────────────────────────────

/// Write a response (daemon side).
pub async fn write_response<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    status: u8,
    value: &str,
) -> std::io::Result<()> {
    let bytes = value.as_bytes();
    let len = bytes.len().min(u16::MAX as usize) as u16;
    writer.write_u8(status).await?;
    writer.write_u16_le(len).await?;
    writer.write_all(&bytes[..len as usize]).await?;
    writer.flush().await?;
    Ok(())
}

/// Read a response (client side).
pub async fn read_response<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<(u8, String)> {
    let status = reader.read_u8().await?;
    let value_len = reader.read_u16_le().await?;
    let mut buf = vec![0u8; value_len as usize];
    reader.read_exact(&mut buf).await?;
    let value = String::from_utf8(buf)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    Ok((status, value))
}

// ── Helpers ─────────────────────────────────────────────────────────

async fn read_null_terminated<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<String> {
    let mut buf = Vec::new();
    loop {
        let byte = reader.read_u8().await?;
        if byte == 0 {
            break;
        }
        buf.push(byte);
    }
    String::from_utf8(buf)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[tokio::test]
    async fn command_round_trip() {
        let mut buf = Vec::new();
        write_command(&mut buf, "git_status", "/home/user").await.unwrap();

        let mut reader = Cursor::new(buf);
        let (cmd, cwd, is_status) = read_command(&mut reader).await.unwrap();
        assert_eq!(cmd, "git_status");
        assert_eq!(cwd, "/home/user");
        assert!(!is_status);
    }

    #[tokio::test]
    async fn status_query_round_trip() {
        let mut buf = Vec::new();
        write_command(&mut buf, "", "").await.unwrap();

        let mut reader = Cursor::new(buf);
        let (cmd, cwd, is_status) = read_command(&mut reader).await.unwrap();
        assert_eq!(cmd, "");
        assert_eq!(cwd, "");
        assert!(is_status);
    }

    #[tokio::test]
    async fn env_request_round_trip() {
        let names = vec!["GIT_BRANCH".into(), "HOSTNAME".into()];
        let mut buf = Vec::new();
        write_env_request(&mut buf, &names).await.unwrap();

        let mut reader = Cursor::new(buf);
        let result = read_env_request(&mut reader).await.unwrap();
        assert_eq!(result, vec!["GIT_BRANCH", "HOSTNAME"]);
    }

    #[tokio::test]
    async fn env_request_empty() {
        let mut buf = Vec::new();
        write_env_request(&mut buf, &[]).await.unwrap();

        let mut reader = Cursor::new(buf);
        let result = read_env_request(&mut reader).await.unwrap();
        assert!(result.is_empty());
    }

    #[tokio::test]
    async fn env_values_round_trip() {
        let values = vec!["main".into(), "myhost".into()];
        let mut buf = Vec::new();
        write_env_values(&mut buf, &values).await.unwrap();

        let mut reader = Cursor::new(buf);
        let result = read_env_values(&mut reader).await.unwrap();
        assert_eq!(result, vec!["main", "myhost"]);
    }

    #[tokio::test]
    async fn response_round_trip() {
        let mut buf = Vec::new();
        write_response(&mut buf, 0x01, "cached value").await.unwrap();

        let mut reader = Cursor::new(buf);
        let (status, value) = read_response(&mut reader).await.unwrap();
        assert_eq!(status, 0x01);
        assert_eq!(value, "cached value");
    }

    #[tokio::test]
    async fn response_empty_value() {
        let mut buf = Vec::new();
        write_response(&mut buf, 0x04, "").await.unwrap();

        let mut reader = Cursor::new(buf);
        let (status, value) = read_response(&mut reader).await.unwrap();
        assert_eq!(status, 0x04);
        assert_eq!(value, "");
    }

    #[tokio::test]
    async fn full_4_phase_exchange() {
        // Simulate a complete client<->daemon exchange in a single buffer
        let mut wire = Vec::new();

        // Phase 1: client writes command + CWD
        write_command(&mut wire, "git_branch", "/repo").await.unwrap();

        // Phase 2: daemon writes env request
        let env_names = vec!["GIT_BRANCH".into()];
        write_env_request(&mut wire, &env_names).await.unwrap();

        // Phase 3: client writes env values
        let env_vals = vec!["main".into()];
        write_env_values(&mut wire, &env_vals).await.unwrap();

        // Phase 4: daemon writes response
        write_response(&mut wire, 0x01, "main").await.unwrap();

        // Now read it all back
        let mut reader = Cursor::new(wire);

        let (cmd, cwd, is_status) = read_command(&mut reader).await.unwrap();
        assert_eq!(cmd, "git_branch");
        assert_eq!(cwd, "/repo");
        assert!(!is_status);

        let names = read_env_request(&mut reader).await.unwrap();
        assert_eq!(names, vec!["GIT_BRANCH"]);

        let vals = read_env_values(&mut reader).await.unwrap();
        assert_eq!(vals, vec!["main"]);

        let (status, value) = read_response(&mut reader).await.unwrap();
        assert_eq!(status, 0x01);
        assert_eq!(value, "main");
    }
}
