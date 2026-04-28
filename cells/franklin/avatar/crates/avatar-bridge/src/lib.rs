use std::ffi::{c_char, CStr};
use std::ptr;

#[no_mangle]
pub extern "C" fn franklin_avatar_bridge_version() -> *const c_char {
    b"avatar-bridge/0.1.0\0".as_ptr().cast()
}

#[no_mangle]
pub extern "C" fn franklin_avatar_validate_frame(frame_ms: f32, target_hz: u16) -> bool {
    avatar_render::frame_ok(frame_ms, target_hz)
}

#[no_mangle]
pub extern "C" fn franklin_avatar_first_viseme(input: *const c_char) -> *const c_char {
    if input.is_null() {
        return b"rest\0".as_ptr().cast();
    }
    let text = unsafe { CStr::from_ptr(input) };
    let viseme = avatar_tts::first_viseme_for_text(text.to_str().unwrap_or_default());
    match viseme {
        "open_vowel" => b"open_vowel\0".as_ptr().cast(),
        _ => b"rest\0".as_ptr().cast(),
    }
}

#[no_mangle]
pub extern "C" fn franklin_avatar_null() -> *const c_char {
    ptr::null()
}

mod avatar_tts {
    pub use avatar_tts::first_viseme_for_text;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn bridge_version_is_exposed() {
        let ptr = franklin_avatar_bridge_version();
        assert!(!ptr.is_null());
        let version = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .expect("valid utf8");
        assert!(version.starts_with("avatar-bridge/"));
    }

    #[test]
    fn bridge_frame_validation_refuses_budget_overrun() {
        assert!(franklin_avatar_validate_frame(8.2, 120));
        assert!(!franklin_avatar_validate_frame(8.31, 120));
    }

    #[test]
    fn bridge_returns_viseme_for_non_empty_text() {
        let ptr = franklin_avatar_first_viseme(c"franklin".as_ptr());
        let viseme = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .expect("valid utf8");
        assert_eq!(viseme, "open_vowel");
    }
}
