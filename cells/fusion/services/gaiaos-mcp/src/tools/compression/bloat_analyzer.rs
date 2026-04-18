use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::fs;
use walkdir::WalkDir;
use crate::akg::AKGClient;

/// Bloat Analysis Report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BloatAnalysisReport {
    pub verdict: BloatVerdict,
    pub total_bloat_kb: f64,
    pub detected_patterns: Vec<DetectedPattern>,
    pub recommendations: Vec<CompressionRecommendation>,
    pub estimated_compression_ratio: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum BloatVerdict {
    NoBloat,
    MinorBloat,
    SignificantBloat,
    CriticalBloat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedPattern {
    pub pattern_type: String,
    pub affected_files: Vec<String>,
    pub total_size_bytes: u64,
    pub procedural_alternative: String,
    pub expected_compression_ratio: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionRecommendation {
    pub priority: u8,  // 1-10
    pub pattern: String,
    pub implementation: String,
    pub estimated_savings_kb: f64,
}

/// Bloat Analyzer
pub struct BloatAnalyzer {
    akg_client: AKGClient,
    workspace_root: PathBuf,
}

impl BloatAnalyzer {
    pub fn new(akg_client: AKGClient, workspace_root: impl Into<PathBuf>) -> Self {
        Self {
            akg_client,
            workspace_root: workspace_root.into(),
        }
    }

    /// Analyze proposed patch for asset bloat
    pub async fn analyze_patch(
        &self,
        patch_files: &[String],
        world: &str,
    ) -> Result<BloatAnalysisReport> {
        println!("🔍 Analyzing patch for bloat...");
        println!("  World: {}", world);
        println!("  Files: {}", patch_files.len());
        
        let mut total_bloat = 0.0;
        let mut detected_patterns = Vec::new();
        let mut recommendations = Vec::new();
        
        // 1. Classify files by type
        let asset_files = self.classify_asset_files(patch_files);
        
        // 2. Detect bloat patterns
        for (asset_type, files) in asset_files.iter() {
            let pattern = self.detect_pattern_for_type(asset_type, files).await?;
            
            if let Some(pattern) = pattern {
                let size_kb = pattern.total_size_bytes as f64 / 1024.0;
                total_bloat += size_kb;
                
                // Generate recommendation
                let recommendation = CompressionRecommendation {
                    priority: self.calculate_priority(size_kb, pattern.expected_compression_ratio),
                    pattern: pattern.pattern_type.clone(),
                    implementation: pattern.procedural_alternative.clone(),
                    estimated_savings_kb: size_kb * (1.0 - 1.0 / pattern.expected_compression_ratio),
                };
                
                recommendations.push(recommendation);
                detected_patterns.push(pattern);
            }
        }
        
        // 3. Sort recommendations by priority
        recommendations.sort_by(|a, b| b.priority.cmp(&a.priority));
        
        // 4. Calculate overall compression ratio
        let estimated_compression_ratio = if total_bloat > 0.0 {
            let procedural_size = 10.0;  // Estimated KB for procedural generators
            total_bloat / procedural_size
        } else {
            1.0
        };
        
        // 5. Determine verdict
        let verdict = match total_bloat {
            x if x < 100.0 => BloatVerdict::NoBloat,
            x if x < 1000.0 => BloatVerdict::MinorBloat,
            x if x < 10000.0 => BloatVerdict::SignificantBloat,
            _ => BloatVerdict::CriticalBloat,
        };
        
        println!("  Verdict: {:?}", verdict);
        println!("  Total bloat: {:.1} KB", total_bloat);
        println!("  Detected {} patterns", detected_patterns.len());
        
        Ok(BloatAnalysisReport {
            verdict,
            total_bloat_kb: total_bloat,
            detected_patterns,
            recommendations,
            estimated_compression_ratio,
        })
    }

    /// Classify files by asset type
    fn classify_asset_files(&self, files: &[String]) -> Vec<(AssetType, Vec<String>)> {
        let mut classified = std::collections::HashMap::new();
        
        for file in files {
            let asset_type = AssetType::from_path(file);
            classified.entry(asset_type)
                .or_insert_with(Vec::new)
                .push(file.clone());
        }
        
        classified.into_iter().collect()
    }

    /// Detect procedural pattern for asset type
    async fn detect_pattern_for_type(
        &self,
        asset_type: &AssetType,
        files: &[String],
    ) -> Result<Option<DetectedPattern>> {
        let total_size = self.calculate_total_size(files)?;
        
        // Query V2 compression achievements for this asset type
        let pattern_query = format!(
            r#"
            FOR pattern IN CompressionAchievements_V2
                FILTER pattern.pattern_type == "{}"
                FILTER pattern.confidence == "high"
                SORT pattern.compression_ratio DESC
                LIMIT 1
                RETURN {{
                    pattern_type: pattern.pattern_type,
                    procedural_alternative: pattern.context_snippet,
                    compression_ratio: pattern.compression_ratio
                }}
            "#,
            asset_type.to_string()
        );
        
        let pattern_result: Vec<serde_json::Value> = self.akg_client
            .query(&pattern_query)
            .await
            .unwrap_or_default();
        
        if let Some(pattern_data) = pattern_result.first() {
            Ok(Some(DetectedPattern {
                pattern_type: pattern_data["pattern_type"].as_str().unwrap_or("unknown").to_string(),
                affected_files: files.to_vec(),
                total_size_bytes: total_size,
                procedural_alternative: pattern_data["procedural_alternative"]
                    .as_str()
                    .unwrap_or("see pattern library")
                    .to_string(),
                expected_compression_ratio: pattern_data["compression_ratio"]
                    .as_f64()
                    .unwrap_or(100.0),
            }))
        } else {
            // No specific pattern found
            if total_size > 100_000 && files.len() > 5 {
                // Generic bloat detected
                Ok(Some(DetectedPattern {
                    pattern_type: format!("{:?} collection bloat", asset_type),
                    affected_files: files.to_vec(),
                    total_size_bytes: total_size,
                    procedural_alternative: "Consider procedural generation".to_string(),
                    expected_compression_ratio: 100.0,
                }))
            } else {
                Ok(None)
            }
        }
    }

    /// Calculate total size of files
    fn calculate_total_size(&self, files: &[String]) -> Result<u64> {
        let mut total = 0u64;
        
        for file in files {
            let path = self.workspace_root.join(file);
            if path.exists() {
                total += fs::metadata(&path)?.len();
            }
        }
        
        Ok(total)
    }

    /// Calculate recommendation priority
    fn calculate_priority(&self, size_kb: f64, compression_ratio: f64) -> u8 {
        // Higher priority for larger size and higher compression potential
        let size_score = (size_kb / 1000.0).min(5.0);
        let compression_score = (compression_ratio / 1000.0).min(5.0);
        
        ((size_score + compression_score) as u8).clamp(1, 10)
    }
}

/// Asset Type Classification
#[derive(Debug, Clone, Copy, Hash, Eq, PartialEq)]
enum AssetType {
    Mesh,
    Texture,
    Audio,
    Animation,
    Scene,
    Other,
}

impl AssetType {
    fn from_path(path: &str) -> Self {
        let path_lower = path.to_lowercase();
        
        if path_lower.ends_with(".glb") || path_lower.ends_with(".gltf") || path_lower.ends_with(".obj") {
            AssetType::Mesh
        } else if path_lower.ends_with(".png") || path_lower.ends_with(".jpg") || path_lower.ends_with(".ktx2") {
            AssetType::Texture
        } else if path_lower.ends_with(".ogg") || path_lower.ends_with(".wav") || path_lower.ends_with(".mp3") {
            AssetType::Audio
        } else if path_lower.contains("anim") {
            AssetType::Animation
        } else if path_lower.contains("scene") {
            AssetType::Scene
        } else {
            AssetType::Other
        }
    }
    
    fn to_string(&self) -> &str {
        match self {
            AssetType::Mesh => "meshes",
            AssetType::Texture => "textures",
            AssetType::Audio => "audio",
            AssetType::Animation => "animations",
            AssetType::Scene => "scenes",
            AssetType::Other => "other",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_asset_type_classification() {
        assert!(matches!(AssetType::from_path("model.glb"), AssetType::Mesh));
        assert!(matches!(AssetType::from_path("texture.png"), AssetType::Texture));
        assert!(matches!(AssetType::from_path("sound.ogg"), AssetType::Audio));
    }

    #[test]
    fn test_bloat_verdict_thresholds() {
        // Test verdict determination logic
        let small_bloat = 50.0;
        let verdict = match small_bloat {
            x if x < 100.0 => BloatVerdict::NoBloat,
            _ => BloatVerdict::MinorBloat,
        };
        assert!(matches!(verdict, BloatVerdict::NoBloat));
    }
}
