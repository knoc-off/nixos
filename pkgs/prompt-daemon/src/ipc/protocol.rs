//! 2-message IPC wire protocol.
//!
//! Normal query:
//!   1. Client → Daemon:  [payload_len: u32 LE] [command\0 cwd\0 (KEY=VALUE\0)*]
//!   2. Daemon → Client:  [status: u8] [value_len: u16 LE] [value: bytes]
//!
//! Status query:
//!   1. Client → Daemon:  [payload_len: u32 LE = 0]
//!   2. Daemon → Client:  [status: u8] [value_len: u16 LE] [value: bytes]
//!
//! The client sends its full environment; the daemon picks out whatever
//! variables the requested command declared in its `env` list.

use std::collections::HashMap;

use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// A parsed request, or `None` for a status query.
pub struct Request {
    pub command: String,
    pub cwd: String,
    pub env: HashMap<String, String>,
}

// ── Message 1: Client sends command + CWD + full environment ───────

/// Write a request (client side). Pass `env` as an empty map for a status query.
pub async fn write_request<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    command: &str,
    cwd: &str,
    env: &HashMap<String, String>,
) -> std::io::Result<()> {
    if command.is_empty() && cwd.is_empty() && env.is_empty() {
        writer.write_u32_le(0).await?;
        writer.flush().await?;
        return Ok(());
    }

    let mut payload = Vec::new();
    payload.extend_from_slice(command.as_bytes());
    payload.push(0);
    payload.extend_from_slice(cwd.as_bytes());
    payload.push(0);
    for (k, v) in env {
        payload.extend_from_slice(k.as_bytes());
        payload.push(b'=');
        payload.extend_from_slice(v.as_bytes());
        payload.push(0);
    }

    writer.write_u32_le(payload.len() as u32).await?;
    writer.write_all(&payload).await?;
    writer.flush().await?;
    Ok(())
}

/// Read a request (daemon side). Returns `None` for a status query.
pub async fn read_request<R: AsyncReadExt + Unpin>(
    reader: &mut R,
) -> std::io::Result<Option<Request>> {
    let len = reader.read_u32_le().await?;
    if len == 0 {
        return Ok(None);
    }

    let mut buf = vec![0u8; len as usize];
    reader.read_exact(&mut buf).await?;

    let mut parts = buf.split(|&b| b == 0).map(|s| {
        String::from_utf8(s.to_vec())
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    });

    let command = parts
        .next()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "missing command"))??;
    let cwd = parts
        .next()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "missing cwd"))??;

    let mut env = HashMap::new();
    for entry in parts {
        let entry = entry?;
        if entry.is_empty() {
            continue;
        }
        if let Some((k, v)) = entry.split_once('=') {
            env.insert(k.to_string(), v.to_string());
        }
    }

    Ok(Some(Request { command, cwd, env }))
}

// ── Message 2: Daemon sends response ────────────────────────────────

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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[tokio::test]
    async fn request_round_trip() {
        let mut env = HashMap::new();
        env.insert("GIT_BRANCH".to_string(), "main".to_string());

        let mut buf = Vec::new();
        write_request(&mut buf, "git_branch", "/repo", &env).await.unwrap();

        let mut reader = Cursor::new(buf);
        let req = read_request(&mut reader).await.unwrap().unwrap();
        assert_eq!(req.command, "git_branch");
        assert_eq!(req.cwd, "/repo");
        assert_eq!(req.env.get("GIT_BRANCH"), Some(&"main".to_string()));
    }

    #[tokio::test]
    async fn request_with_no_env() {
        let mut buf = Vec::new();
        write_request(&mut buf, "uptime", "", &HashMap::new()).await.unwrap();

        let mut reader = Cursor::new(buf);
        let req = read_request(&mut reader).await.unwrap().unwrap();
        assert_eq!(req.command, "uptime");
        assert_eq!(req.cwd, "");
        assert!(req.env.is_empty());
    }

    #[tokio::test]
    async fn status_query_round_trip() {
        let mut buf = Vec::new();
        write_request(&mut buf, "", "", &HashMap::new()).await.unwrap();

        let mut reader = Cursor::new(buf);
        let req = read_request(&mut reader).await.unwrap();
        assert!(req.is_none());
    }

    #[tokio::test]
    async fn env_value_containing_equals() {
        let mut env = HashMap::new();
        env.insert("FOO".to_string(), "a=b=c".to_string());

        let mut buf = Vec::new();
        write_request(&mut buf, "cmd", "/x", &env).await.unwrap();

        let mut reader = Cursor::new(buf);
        let req = read_request(&mut reader).await.unwrap().unwrap();
        assert_eq!(req.env.get("FOO"), Some(&"a=b=c".to_string()));
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
    async fn full_exchange() {
        let mut wire = Vec::new();

        let mut env = HashMap::new();
        env.insert("GIT_BRANCH".to_string(), "main".to_string());
        write_request(&mut wire, "git_branch", "/repo", &env).await.unwrap();
        write_response(&mut wire, 0x01, "main").await.unwrap();

        let mut reader = Cursor::new(wire);

        let req = read_request(&mut reader).await.unwrap().unwrap();
        assert_eq!(req.command, "git_branch");
        assert_eq!(req.cwd, "/repo");
        assert_eq!(req.env.get("GIT_BRANCH"), Some(&"main".to_string()));

        let (status, value) = read_response(&mut reader).await.unwrap();
        assert_eq!(status, 0x01);
        assert_eq!(value, "main");
    }
}
