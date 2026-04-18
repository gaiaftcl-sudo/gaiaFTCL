use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::time::sleep;

/// Token bucket rate limiter
pub struct TokenBucket {
    tokens: Arc<Mutex<TokenBucketState>>,
    capacity: u32,
    refill_rate: Duration,
}

struct TokenBucketState {
    available: u32,
    last_refill: Instant,
}

impl TokenBucket {
    pub fn new(capacity: u32, refill_period: Duration) -> Self {
        Self {
            tokens: Arc::new(Mutex::new(TokenBucketState {
                available: capacity,
                last_refill: Instant::now(),
            })),
            capacity,
            refill_rate: refill_period,
        }
    }

    /// Acquire a token, waiting if necessary
    pub async fn acquire(&self) {
        loop {
            let mut state = self.tokens.lock().await;
            
            // Refill tokens based on elapsed time
            let elapsed = state.last_refill.elapsed();
            if elapsed >= self.refill_rate {
                state.available = self.capacity;
                state.last_refill = Instant::now();
            }

            if state.available > 0 {
                state.available -= 1;
                return;
            }

            // No tokens available, wait and retry
            drop(state);
            sleep(Duration::from_millis(100)).await;
        }
    }

    /// Try to acquire a token without waiting
    pub async fn try_acquire(&self) -> bool {
        let mut state = self.tokens.lock().await;
        
        // Refill tokens based on elapsed time
        let elapsed = state.last_refill.elapsed();
        if elapsed >= self.refill_rate {
            state.available = self.capacity;
            state.last_refill = Instant::now();
        }

        if state.available > 0 {
            state.available -= 1;
            true
        } else {
            false
        }
    }
}

/// Rate limiter for multiple providers
pub struct RateLimiter {
    massive: TokenBucket,
    fmp: TokenBucket,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            // Massive: 5 calls per minute
            massive: TokenBucket::new(5, Duration::from_secs(60)),
            // FMP: 250 calls per day (conservative: 10 per minute)
            fmp: TokenBucket::new(10, Duration::from_secs(60)),
        }
    }

    pub async fn acquire_massive(&self) {
        self.massive.acquire().await;
    }

    pub async fn try_acquire_massive(&self) -> bool {
        self.massive.try_acquire().await
    }

    pub async fn acquire_fmp(&self) {
        self.fmp.acquire().await;
    }

    pub async fn try_acquire_fmp(&self) -> bool {
        self.fmp.try_acquire().await
    }
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_token_bucket_acquire() {
        let bucket = TokenBucket::new(2, Duration::from_secs(1));
        
        // Should be able to acquire 2 tokens immediately
        bucket.acquire().await;
        bucket.acquire().await;
        
        // Third acquire should wait
        let start = Instant::now();
        bucket.acquire().await;
        let elapsed = start.elapsed();
        
        // Should have waited at least 1 second for refill
        assert!(elapsed >= Duration::from_millis(900));
    }

    #[tokio::test]
    async fn test_token_bucket_try_acquire() {
        let bucket = TokenBucket::new(1, Duration::from_secs(1));
        
        // Should succeed
        assert!(bucket.try_acquire().await);
        
        // Should fail (no tokens left)
        assert!(!bucket.try_acquire().await);
    }
}

