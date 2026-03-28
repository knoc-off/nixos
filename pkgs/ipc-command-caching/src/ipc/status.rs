use crate::cache::store::CacheStore;

/// Format a human-readable status dump of all active cache entries.
pub fn format_status_dump(store: &CacheStore) -> String {
    let mut out = String::new();

    out.push_str(&format!(
        "{:<20} {:<40} {:<10} {:<10} {:<8} {}\n",
        "COMMAND", "KEY", "STATE", "AGE", "HITS", "ACTIVITY"
    ));

    for (key, entry) in store.iter() {
        let state = entry.cache.state_name();
        let age = format_age(entry.activity.last_requested_at.elapsed());
        let hits = entry.activity.request_count;
        let hot_cold = if entry.activity.last_requested_at.elapsed().as_secs() < 60 {
            "Hot"
        } else {
            "Cold"
        };

        // Extract command name from key (part before the first '\0' separator)
        let cmd_name = key.split('\0').next().unwrap_or(key);

        out.push_str(&format!(
            "{:<20} {:<40} {:<10} {:<10} {:<8} {}\n",
            cmd_name, key, state, age, hits, hot_cold
        ));
    }

    out
}

fn format_age(duration: std::time::Duration) -> String {
    let secs = duration.as_secs();
    if secs < 60 {
        format!("{secs}s ago")
    } else if secs < 3600 {
        format!("{}m ago", secs / 60)
    } else if secs < 86400 {
        format!("{}h ago", secs / 3600)
    } else {
        format!("{}d ago", secs / 86400)
    }
}
