use std::fmt;

use serde::de;

/// A wrapper around `std::time::Duration` that deserializes from strings like
/// "2s", "30s", "5m", "1h", "1d".
#[derive(Debug, Clone)]
pub struct Duration(pub std::time::Duration);

impl<'de> de::Deserialize<'de> for Duration {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: de::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        parse_duration(&s)
            .map(Duration)
            .map_err(de::Error::custom)
    }
}

fn parse_duration(s: &str) -> Result<std::time::Duration, String> {
    let s = s.trim();
    if s.is_empty() {
        return Err("empty duration string".to_string());
    }

    // Find the split point between digits and suffix
    let num_end = s
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(s.len());

    if num_end == 0 {
        return Err(format!("invalid duration: no numeric value in '{s}'"));
    }

    let value: u64 = s[..num_end]
        .parse()
        .map_err(|e| format!("invalid duration number: {e}"))?;

    let suffix = &s[num_end..];
    let secs = match suffix {
        "s" => value,
        "m" => value * 60,
        "h" => value * 3600,
        "d" => value * 86400,
        "" => return Err(format!("missing duration suffix in '{s}' (use s, m, h, or d)")),
        _ => return Err(format!("unknown duration suffix '{suffix}' (use s, m, h, or d)")),
    };

    Ok(std::time::Duration::from_secs(secs))
}

impl fmt::Display for Duration {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let secs = self.0.as_secs();
        if secs % 86400 == 0 && secs > 0 {
            write!(f, "{}d", secs / 86400)
        } else if secs % 3600 == 0 && secs > 0 {
            write!(f, "{}h", secs / 3600)
        } else if secs % 60 == 0 && secs > 0 {
            write!(f, "{}m", secs / 60)
        } else {
            write!(f, "{secs}s")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_seconds() {
        assert_eq!(parse_duration("2s").unwrap().as_secs(), 2);
        assert_eq!(parse_duration("30s").unwrap().as_secs(), 30);
    }

    #[test]
    fn test_parse_minutes() {
        assert_eq!(parse_duration("5m").unwrap().as_secs(), 300);
    }

    #[test]
    fn test_parse_hours() {
        assert_eq!(parse_duration("1h").unwrap().as_secs(), 3600);
    }

    #[test]
    fn test_parse_days() {
        assert_eq!(parse_duration("1d").unwrap().as_secs(), 86400);
    }

    #[test]
    fn test_parse_invalid() {
        assert!(parse_duration("").is_err());
        assert!(parse_duration("abc").is_err());
        assert!(parse_duration("5x").is_err());
        assert!(parse_duration("5").is_err());
    }
}
