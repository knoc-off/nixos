use std::collections::HashMap;

/// Derive a deterministic cache key from command name + env vars.
///
/// Format: `command_name\0KEY1=val1\0KEY2=val2` (sorted by key name).
/// If no env vars, just `command_name`.
pub fn derive_cache_key(command: &str, env: &HashMap<String, String>) -> String {
    if env.is_empty() {
        return command.to_string();
    }
    let mut key = command.to_string();
    let mut pairs: Vec<_> = env.iter().collect();
    pairs.sort_by_key(|(k, _)| *k);
    for (k, v) in pairs {
        key.push('\0');
        key.push_str(k);
        key.push('=');
        key.push_str(v);
    }
    key
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_env_is_just_command_name() {
        let env = HashMap::new();
        assert_eq!(derive_cache_key("git_status", &env), "git_status");
    }

    #[test]
    fn single_env_var() {
        let mut env = HashMap::new();
        env.insert("CWD".into(), "/home/user".into());
        assert_eq!(
            derive_cache_key("git_status", &env),
            "git_status\0CWD=/home/user"
        );
    }

    #[test]
    fn multiple_env_vars_sorted() {
        let mut env = HashMap::new();
        env.insert("ZZZ".into(), "last".into());
        env.insert("AAA".into(), "first".into());
        env.insert("MMM".into(), "middle".into());
        assert_eq!(
            derive_cache_key("cmd", &env),
            "cmd\0AAA=first\0MMM=middle\0ZZZ=last"
        );
    }

    #[test]
    fn deterministic_across_insertion_order() {
        let mut env1 = HashMap::new();
        env1.insert("B".into(), "2".into());
        env1.insert("A".into(), "1".into());

        let mut env2 = HashMap::new();
        env2.insert("A".into(), "1".into());
        env2.insert("B".into(), "2".into());

        assert_eq!(
            derive_cache_key("cmd", &env1),
            derive_cache_key("cmd", &env2)
        );
    }
}
