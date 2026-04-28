use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AvatarFrameMetrics {
    pub frame_time_ms: f32,
    pub target_hz: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AvatarRefusal {
    pub code: String,
    pub detail: String,
}

pub fn enforce_frame_budget(metrics: &AvatarFrameMetrics) -> Option<AvatarRefusal> {
    let budget = if metrics.target_hz >= 120 { 8.3 } else { 16.6 };
    if metrics.frame_time_ms > budget {
        return Some(AvatarRefusal {
            code: "GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN".to_string(),
            detail: format!(
                "frame_time_ms={} exceeded budget_ms={}",
                metrics.frame_time_ms, budget
            ),
        });
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_frame_at_60hz_budget() {
        let refusal = enforce_frame_budget(&AvatarFrameMetrics {
            frame_time_ms: 16.6,
            target_hz: 60,
        });
        assert!(refusal.is_none());
    }

    #[test]
    fn refuses_frame_over_60hz_budget() {
        let refusal = enforce_frame_budget(&AvatarFrameMetrics {
            frame_time_ms: 16.7,
            target_hz: 60,
        })
        .expect("expected refusal");
        assert_eq!(refusal.code, "GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN");
    }

    #[test]
    fn refuses_frame_over_120hz_budget() {
        let refusal = enforce_frame_budget(&AvatarFrameMetrics {
            frame_time_ms: 8.31,
            target_hz: 120,
        })
        .expect("expected refusal");
        assert!(refusal.detail.contains("budget_ms=8.3"));
    }
}
