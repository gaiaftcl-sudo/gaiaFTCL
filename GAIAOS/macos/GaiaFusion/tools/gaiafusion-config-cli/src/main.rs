// gaiafusion-config-cli
// TOML config parser for GaiaFusion GAMP 5 validation scripts
// Emits shell-sourceable SECTION__KEY=value pairs
// FortressAI Research Institute | USPTO 19/460,960

use std::env;
use std::fs;
use std::process;
use toml::Value;

fn flatten_toml(prefix: &str, value: &Value) {
    match value {
        Value::Table(table) => {
            for (key, val) in table {
                let new_prefix = if prefix.is_empty() {
                    key.to_uppercase().replace("-", "_")
                } else {
                    format!("{}__{}", prefix, key.to_uppercase().replace("-", "_"))
                };
                flatten_toml(&new_prefix, val);
            }
        }
        Value::Array(arr) => {
            // Output array as space-separated string
            let values: Vec<String> = arr
                .iter()
                .filter_map(|v| match v {
                    Value::String(s) => Some(s.clone()),
                    Value::Integer(i) => Some(i.to_string()),
                    Value::Float(f) => Some(f.to_string()),
                    Value::Boolean(b) => Some(b.to_string()),
                    _ => None,
                })
                .collect();
            println!("{}=\"{}\"", prefix, values.join(" "));
        }
        Value::String(s) => println!("{}=\"{}\"", prefix, s),
        Value::Integer(i) => println!("{}={}", prefix, i),
        Value::Float(f) => println!("{}={}", prefix, f),
        Value::Boolean(b) => println!("{}={}", prefix, b),
        _ => {}
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    if args.len() != 2 {
        eprintln!("Usage: gaiafusion-config-cli <config.toml>");
        eprintln!("Outputs shell-sourceable SECTION__KEY=value pairs");
        process::exit(1);
    }
    
    let toml_path = &args[1];
    
    let content = fs::read_to_string(toml_path).unwrap_or_else(|e| {
        eprintln!("Error reading {}: {}", toml_path, e);
        process::exit(1);
    });
    
    let parsed: Value = toml::from_str(&content).unwrap_or_else(|e| {
        eprintln!("Error parsing TOML: {}", e);
        process::exit(1);
    });
    
    flatten_toml("", &parsed);
}
