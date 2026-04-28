pub fn model_available() -> bool {
    true
}

pub fn first_viseme_for_text(input: &str) -> &'static str {
    if input.is_empty() {
        "rest"
    } else {
        "open_vowel"
    }
}
