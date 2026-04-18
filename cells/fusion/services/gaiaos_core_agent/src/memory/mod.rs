//! Episode Memory Layer
//!
//! Stores and retrieves episodes, trajectories, outcomes, and learned policies.
//! This forms the long-term memory of the AGI system.

use crate::types::*;
use crate::substrate_reader::SubstrateReader;
use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Episode Memory - stores all experiences
pub struct EpisodeMemory {
    substrate: SubstrateReader,
    /// In-memory cache of recent episodes
    cache: Arc<RwLock<EpisodeCache>>,
}

struct EpisodeCache {
    episodes: HashMap<String, Episode>,
    /// Indexed by outcome type for fast lookup
    by_success: Vec<String>,
    by_failure: Vec<String>,
    /// Indexed by domain
    by_domain: HashMap<String, Vec<String>>,
}

impl Default for EpisodeMemory {
    fn default() -> Self {
        Self::new()
    }
}

impl EpisodeMemory {
    pub fn new() -> Self {
        Self {
            substrate: SubstrateReader::new(),
            cache: Arc::new(RwLock::new(EpisodeCache {
                episodes: HashMap::new(),
                by_success: Vec::new(),
                by_failure: Vec::new(),
                by_domain: HashMap::new(),
            })),
        }
    }
    
    /// Store a new episode
    pub async fn store_episode(&self, episode: Episode) -> Result<String> {
        let id = episode.id.clone();
        let success = episode.success;
        let domains: Vec<String> = episode.plans.iter()
            .flat_map(|p| p.domains_involved.iter())
            .map(|d| d.as_str().to_string())
            .collect();
        
        // Persist to AKG
        self.substrate.persist_episode(&episode).await?;
        
        // Update cache
        {
            let mut cache = self.cache.write().await;
            
            if success {
                cache.by_success.push(id.clone());
            } else {
                cache.by_failure.push(id.clone());
            }
            
            for domain in domains {
                cache.by_domain
                    .entry(domain)
                    .or_insert_with(Vec::new)
                    .push(id.clone());
            }
            
            cache.episodes.insert(id.clone(), episode);
        }
        
        Ok(id)
    }
    
    /// Get an episode by ID
    pub async fn get_episode(&self, id: &str) -> Option<Episode> {
        let cache = self.cache.read().await;
        cache.episodes.get(id).cloned()
    }
    
    /// Get recent successful episodes
    pub async fn get_successful_episodes(&self, limit: usize) -> Vec<Episode> {
        let cache = self.cache.read().await;
        cache.by_success.iter()
            .rev()
            .take(limit)
            .filter_map(|id| cache.episodes.get(id).cloned())
            .collect()
    }
    
    /// Get recent failed episodes
    pub async fn get_failed_episodes(&self, limit: usize) -> Vec<Episode> {
        let cache = self.cache.read().await;
        cache.by_failure.iter()
            .rev()
            .take(limit)
            .filter_map(|id| cache.episodes.get(id).cloned())
            .collect()
    }
    
    /// Get episodes by domain
    pub async fn get_episodes_by_domain(&self, domain: &str, limit: usize) -> Vec<Episode> {
        let cache = self.cache.read().await;
        cache.by_domain.get(domain)
            .map(|ids| {
                ids.iter()
                    .rev()
                    .take(limit)
                    .filter_map(|id| cache.episodes.get(id).cloned())
                    .collect()
            })
            .unwrap_or_default()
    }
    
    /// Find similar past episodes
    pub async fn find_similar(&self, goal: &Goal, limit: usize) -> Vec<Episode> {
        let cache = self.cache.read().await;
        
        // Simple similarity: keyword matching in goal description
        let keywords: Vec<&str> = goal.description.split_whitespace().collect();
        
        let mut scored: Vec<(f64, &Episode)> = cache.episodes.values()
            .map(|ep| {
                let score = keywords.iter()
                    .filter(|kw| ep.goal.description.to_lowercase().contains(&kw.to_lowercase()))
                    .count() as f64;
                (score, ep)
            })
            .filter(|(score, _)| *score > 0.0)
            .collect();
        
        scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
        
        scored.into_iter()
            .take(limit)
            .map(|(_, ep)| ep.clone())
            .collect()
    }
    
    /// Extract lessons from episodes
    pub async fn extract_lessons(&self, episodes: &[Episode]) -> Vec<String> {
        let mut lessons = Vec::new();
        
        for ep in episodes {
            lessons.extend(ep.lessons_learned.clone());
            
            // Extract implicit lessons from failures
            if !ep.success {
                if let Some(traj) = &ep.trajectory {
                    for step in &traj.steps {
                        if !step.success {
                            if let Some(err) = &step.error {
                                lessons.push(format!("Avoid: {} (error: {})", 
                                    ep.goal.description, err));
                            }
                        }
                    }
                }
            }
        }
        
        lessons
    }
    
    /// Load recent episodes from AKG into cache
    pub async fn load_recent(&self, limit: usize) -> Result<()> {
        let episodes = self.substrate.get_recent_episodes(limit).await?;
        
        let mut cache = self.cache.write().await;
        
        for episode in episodes {
            let id = episode.id.clone();
            let success = episode.success;
            let domains: Vec<String> = episode.plans.iter()
                .flat_map(|p| p.domains_involved.iter())
                .map(|d| d.as_str().to_string())
                .collect();
            
            if success {
                cache.by_success.push(id.clone());
            } else {
                cache.by_failure.push(id.clone());
            }
            
            for domain in domains {
                cache.by_domain
                    .entry(domain)
                    .or_insert_with(Vec::new)
                    .push(id.clone());
            }
            
            cache.episodes.insert(id, episode);
        }
        
        Ok(())
    }
}

