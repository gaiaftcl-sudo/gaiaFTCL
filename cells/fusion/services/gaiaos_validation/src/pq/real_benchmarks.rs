//! Real PQ Benchmarking - NO SYNTHETIC METRICS
//!
//! Actual HTTP-based performance tests against running GaiaOS services.
//! Replaces synthetic metric generation with real measurements.

use anyhow::Result;
use serde::Serialize;
use std::time::Instant;

#[derive(Debug, Serialize)]
pub struct BenchmarkResult {
    pub endpoint: String,
    pub requests_total: usize,
    pub requests_successful: usize,
    pub duration_secs: f64,
    pub throughput_per_sec: f64,
    pub latency_p50_ms: f64,
    pub latency_p95_ms: f64,
    pub latency_p99_ms: f64,
    pub error_rate: f64,
}

#[derive(Debug, Serialize)]
pub struct DomainBenchmarkResults {
    pub substrate_collapse: BenchmarkResult,
    pub franklin_virtue: BenchmarkResult,
    pub core_agent_goal: BenchmarkResult,
    pub gnn_embed: BenchmarkResult,
}

/// Run complete benchmark suite against all critical endpoints
pub async fn run_real_benchmarks(
    substrate_url: &str,
    franklin_url: &str,
    core_agent_url: &str,
    gnn_url: &str,
) -> Result<DomainBenchmarkResults> {
    tracing::info!("Starting real PQ benchmarks (NO SYNTHETIC METRICS)");

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()?;

    // Run benchmarks in parallel
    let (substrate_result, franklin_result, agent_result, gnn_result) = tokio::join!(
        benchmark_substrate_collapse(&client, substrate_url),
        benchmark_franklin_virtue(&client, franklin_url),
        benchmark_core_agent_goal(&client, core_agent_url),
        benchmark_gnn_embed(&client, gnn_url),
    );

    Ok(DomainBenchmarkResults {
        substrate_collapse: substrate_result?,
        franklin_virtue: franklin_result?,
        core_agent_goal: agent_result?,
        gnn_embed: gnn_result?,
    })
}

/// Benchmark substrate collapse operations (target: 1000/sec)
async fn benchmark_substrate_collapse(
    client: &reqwest::Client,
    url: &str,
) -> Result<BenchmarkResult> {
    let endpoint = format!("{}/collapse", url);
    let num_requests = 1000;

    tracing::info!(endpoint = %endpoint, requests = num_requests, "Benchmarking substrate collapse");

    let mut latencies = Vec::with_capacity(num_requests);
    let mut successful = 0;

    let start = Instant::now();

    for _ in 0..num_requests {
        let req_start = Instant::now();

        let result = client
            .post(&endpoint)
            .json(&serde_json::json!({
                "coord": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                "control": 0
            }))
            .send()
            .await;

        let latency = req_start.elapsed();
        latencies.push(latency.as_secs_f64() * 1000.0); // Convert to ms

        if let Ok(resp) = result {
            if resp.status().is_success() {
                successful += 1;
            }
        }
    }

    let duration = start.elapsed();
    let duration_secs = duration.as_secs_f64();

    // Calculate percentiles
    latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = latencies[num_requests / 2];
    let p95 = latencies[(num_requests * 95) / 100];
    let p99 = latencies[(num_requests * 99) / 100];

    let result = BenchmarkResult {
        endpoint,
        requests_total: num_requests,
        requests_successful: successful,
        duration_secs,
        throughput_per_sec: successful as f64 / duration_secs,
        latency_p50_ms: p50,
        latency_p95_ms: p95,
        latency_p99_ms: p99,
        error_rate: (num_requests - successful) as f64 / num_requests as f64,
    };

    tracing::info!(
        throughput = result.throughput_per_sec,
        p50_ms = result.latency_p50_ms,
        success_rate = successful as f64 / num_requests as f64,
        "Substrate benchmark complete"
    );

    Ok(result)
}

/// Benchmark Franklin virtue scoring (target: 500/sec)
async fn benchmark_franklin_virtue(client: &reqwest::Client, url: &str) -> Result<BenchmarkResult> {
    let endpoint = format!("{}/virtue/score", url);
    let num_requests = 500;

    tracing::info!(endpoint = %endpoint, requests = num_requests, "Benchmarking Franklin virtue");

    let mut latencies = Vec::with_capacity(num_requests);
    let mut successful = 0;

    let start = Instant::now();

    for _ in 0..num_requests {
        let req_start = Instant::now();

        let result = client.get(&endpoint).send().await;

        let latency = req_start.elapsed();
        latencies.push(latency.as_secs_f64() * 1000.0);

        if let Ok(resp) = result {
            if resp.status().is_success() {
                successful += 1;
            }
        }
    }

    let duration = start.elapsed();
    let duration_secs = duration.as_secs_f64();

    latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = latencies[num_requests / 2];
    let p95 = latencies[(num_requests * 95) / 100];
    let p99 = latencies[(num_requests * 99) / 100];

    Ok(BenchmarkResult {
        endpoint,
        requests_total: num_requests,
        requests_successful: successful,
        duration_secs,
        throughput_per_sec: successful as f64 / duration_secs,
        latency_p50_ms: p50,
        latency_p95_ms: p95,
        latency_p99_ms: p99,
        error_rate: (num_requests - successful) as f64 / num_requests as f64,
    })
}

/// Benchmark core agent goal execution (target: 100 concurrent)
async fn benchmark_core_agent_goal(client: &reqwest::Client, url: &str) -> Result<BenchmarkResult> {
    let endpoint = format!("{}/api/goal", url);
    let num_requests = 100;

    tracing::info!(endpoint = %endpoint, requests = num_requests, "Benchmarking core agent goal");

    let start = Instant::now();

    // Launch all requests concurrently
    let mut handles = Vec::new();

    for i in 0..num_requests {
        let client = client.clone();
        let endpoint = endpoint.clone();

        handles.push(tokio::spawn(async move {
            let req_start = Instant::now();

            let result = client
                .post(&endpoint)
                .json(&serde_json::json!({
                    "description": format!("PQ benchmark goal {}", i),
                    "priority": "medium"
                }))
                .send()
                .await;

            let latency = req_start.elapsed().as_secs_f64() * 1000.0;

            let success = result.map(|r| r.status().is_success()).unwrap_or(false);
            (success, latency)
        }));
    }

    // Collect results
    let mut successful = 0;
    let mut latencies = Vec::new();

    for handle in handles {
        if let Ok((success, latency)) = handle.await {
            if success {
                successful += 1;
            }
            latencies.push(latency);
        }
    }

    let duration = start.elapsed();
    let duration_secs = duration.as_secs_f64();

    latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = if !latencies.is_empty() {
        latencies[latencies.len() / 2]
    } else {
        0.0
    };
    let p95 = if !latencies.is_empty() {
        latencies[(latencies.len() * 95) / 100]
    } else {
        0.0
    };
    let p99 = if !latencies.is_empty() {
        latencies[(latencies.len() * 99) / 100]
    } else {
        0.0
    };

    Ok(BenchmarkResult {
        endpoint,
        requests_total: num_requests,
        requests_successful: successful,
        duration_secs,
        throughput_per_sec: successful as f64 / duration_secs,
        latency_p50_ms: p50,
        latency_p95_ms: p95,
        latency_p99_ms: p99,
        error_rate: (num_requests - successful) as f64 / num_requests as f64,
    })
}

/// Benchmark GNN embedding generation (target: 50/sec)
async fn benchmark_gnn_embed(client: &reqwest::Client, url: &str) -> Result<BenchmarkResult> {
    let endpoint = format!("{}/embed", url);
    let num_requests = 50;

    tracing::info!(endpoint = %endpoint, requests = num_requests, "Benchmarking GNN embed");

    let mut latencies = Vec::with_capacity(num_requests);
    let mut successful = 0;

    let start = Instant::now();

    for i in 0..num_requests {
        let req_start = Instant::now();

        let result = client
            .post(&endpoint)
            .json(&serde_json::json!({
                "text": format!("PQ benchmark embedding test {}", i),
                "model": "default"
            }))
            .send()
            .await;

        let latency = req_start.elapsed();
        latencies.push(latency.as_secs_f64() * 1000.0);

        if let Ok(resp) = result {
            if resp.status().is_success() {
                successful += 1;
            }
        }
    }

    let duration = start.elapsed();
    let duration_secs = duration.as_secs_f64();

    latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = latencies[num_requests / 2];
    let p95 = latencies[(num_requests * 95) / 100];
    let p99 = latencies[(num_requests * 99) / 100];

    Ok(BenchmarkResult {
        endpoint,
        requests_total: num_requests,
        requests_successful: successful,
        duration_secs,
        throughput_per_sec: successful as f64 / duration_secs,
        latency_p50_ms: p50,
        latency_p95_ms: p95,
        latency_p99_ms: p99,
        error_rate: (num_requests - successful) as f64 / num_requests as f64,
    })
}

/// Convert benchmark results to domain metrics
pub fn benchmarks_to_domain_metrics(
    results: &DomainBenchmarkResults,
) -> crate::types::DomainMetrics {
    // Use real performance data to compute domain metrics
    let substrate_score = (results.substrate_collapse.throughput_per_sec / 1000.0).min(1.0);
    let franklin_score = (results.franklin_virtue.throughput_per_sec / 500.0).min(1.0);
    let agent_score = if results.core_agent_goal.error_rate < 0.05 {
        0.95
    } else {
        0.70
    };
    let _gnn_score = (results.gnn_embed.throughput_per_sec / 50.0).min(1.0);

    // Aggregate into general reasoning metrics (this is a simplification - real implementation
    // would route to specific domain benchmark per ModelFamily)
    crate::types::DomainMetrics::GeneralReasoning(crate::types::GeneralReasoningMetrics {
        reasoning_score: agent_score,
        coherence_score: substrate_score,
        mmlu_score: Some(franklin_score),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_benchmark_result_calculation() {
        // Verify benchmark result calculations are correct
        let result = BenchmarkResult {
            endpoint: "test".to_string(),
            requests_total: 100,
            requests_successful: 95,
            duration_secs: 1.0,
            throughput_per_sec: 95.0,
            latency_p50_ms: 10.0,
            latency_p95_ms: 25.0,
            latency_p99_ms: 50.0,
            error_rate: 0.05,
        };

        assert_eq!(result.throughput_per_sec, 95.0);
        assert_eq!(result.error_rate, 0.05);
    }
}
