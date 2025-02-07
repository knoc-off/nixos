pub fn encode_base62(mut num: i64) -> String {
    let base = 62;
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut result = String::new();

    if num == 0 {
        return "a".to_string(); // Special case for 0
    }

    while num > 0 {
        let index = (num % base) as usize;
        result.push(characters.chars().nth(index).unwrap());
        num /= base;
    }

    result.chars().rev().collect()
}

