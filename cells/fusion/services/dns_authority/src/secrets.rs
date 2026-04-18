use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Secrets {
    values: HashMap<String, String>,
}

impl Secrets {
    /// Load secrets from environment variables and optional secrets file
    /// Priority: env vars > secrets file
    pub fn load() -> Result<Self> {
        let mut values = HashMap::new();

        // Try to load from secrets file
        let secrets_file_path = std::env::var("GAIAFTCL_SECRETS_FILE")
            .unwrap_or_else(|_| "/etc/gaiaftcl/secrets.env".to_string());

        if Path::new(&secrets_file_path).exists() {
            tracing::info!("Loading secrets from: {}", secrets_file_path);
            let file_secrets = Self::load_from_file(&secrets_file_path)?;
            values.extend(file_secrets);
        } else {
            tracing::warn!("Secrets file not found: {}", secrets_file_path);
        }

        // Override with environment variables
        for (key, value) in std::env::vars() {
            if key.starts_with("GODADDY_") || key.starts_with("HEAD_") || key.starts_with("DNS_") {
                values.insert(key, value);
            }
        }

        Ok(Self { values })
    }

    fn load_from_file(path: &str) -> Result<HashMap<String, String>> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read secrets file: {}", path))?;

        // Try JSON first
        if let Ok(json_values) = serde_json::from_str::<HashMap<String, String>>(&content) {
            return Ok(json_values);
        }

        // Fall back to KEY=VALUE format
        let mut values = HashMap::new();
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            if let Some((key, value)) = line.split_once('=') {
                values.insert(key.trim().to_string(), value.trim().to_string());
            }
        }

        Ok(values)
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.values.get(key).map(|s| s.as_str())
    }

    pub fn get_required(&self, key: &str) -> Result<String> {
        self.get(key)
            .map(|s| s.to_string())
            .with_context(|| format!("Required secret not found: {}", key))
    }

    /// Check if GoDaddy credentials are available
    pub fn has_godaddy_credentials(&self) -> bool {
        self.get("GODADDY_API_KEY").is_some() && self.get("GODADDY_API_SECRET").is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_load_key_value_format() {
        let mut file = NamedTempFile::new().unwrap();
        writeln!(file, "# Comment").unwrap();
        writeln!(file, "KEY1=value1").unwrap();
        writeln!(file, "KEY2=value2").unwrap();
        writeln!(file, "").unwrap();
        file.flush().unwrap();

        let values = Secrets::load_from_file(file.path().to_str().unwrap()).unwrap();
        assert_eq!(values.get("KEY1"), Some(&"value1".to_string()));
        assert_eq!(values.get("KEY2"), Some(&"value2".to_string()));
    }

    #[test]
    fn test_load_json_format() {
        let mut file = NamedTempFile::new().unwrap();
        writeln!(file, r#"{{"KEY1": "value1", "KEY2": "value2"}}"#).unwrap();
        file.flush().unwrap();

        let values = Secrets::load_from_file(file.path().to_str().unwrap()).unwrap();
        assert_eq!(values.get("KEY1"), Some(&"value1".to_string()));
        assert_eq!(values.get("KEY2"), Some(&"value2".to_string()));
    }
}
