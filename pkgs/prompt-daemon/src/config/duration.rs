use serde::de;

/// A wrapper around `std::time::Duration` that deserializes from strings like
/// "500ms", "2s", "30s", "5m", "1h", "1d".
#[derive(Debug, Clone, PartialEq)]
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
    match suffix {
        "ms" => Ok(std::time::Duration::from_millis(value)),
        "s" => Ok(std::time::Duration::from_secs(value)),
        "m" => Ok(std::time::Duration::from_secs(value * 60)),
        "h" => Ok(std::time::Duration::from_secs(value * 3600)),
        "d" => Ok(std::time::Duration::from_secs(value * 86400)),
        "" => Err(format!("missing duration suffix in '{s}' (use ms, s, m, h, or d)")),
        _ => Err(format!("unknown duration suffix '{suffix}' (use ms, s, m, h, or d)")),
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
    fn test_parse_millis() {
        assert_eq!(parse_duration("500ms").unwrap().as_millis(), 500);
        assert_eq!(parse_duration("100ms").unwrap().as_millis(), 100);
    }

    #[test]
    fn test_parse_invalid() {
        assert!(parse_duration("").is_err());
        assert!(parse_duration("abc").is_err());
        assert!(parse_duration("5x").is_err());
        assert!(parse_duration("5").is_err());
    }
}
