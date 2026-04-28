use avatar_core::{enforce_frame_budget, AvatarFrameMetrics};

pub fn pass_chain() -> [&'static str; 7] {
    [
        "geometry",
        "shadow",
        "pbd_cloth",
        "strand_fur",
        "lit",
        "refusal_banner",
        "tonemap",
    ]
}

pub fn frame_ok(frame_ms: f32, target_hz: u16) -> bool {
    enforce_frame_budget(&AvatarFrameMetrics {
        frame_time_ms: frame_ms,
        target_hz,
    })
    .is_none()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_full_seven_pass_chain_in_order() {
        assert_eq!(
            pass_chain(),
            [
                "geometry",
                "shadow",
                "pbd_cloth",
                "strand_fur",
                "lit",
                "refusal_banner",
                "tonemap",
            ]
        );
    }

    #[test]
    fn frame_ok_follows_core_budget_gate() {
        assert!(frame_ok(8.2, 120));
        assert!(!frame_ok(8.31, 120));
        assert!(frame_ok(16.6, 60));
        assert!(!frame_ok(16.7, 60));
    }
}
