use std::fs;
use std::path::Path;
use regex::Regex;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct vQbitPrimitive {
    pub transform: [[f32; 4]; 4],
    pub vqbit_entropy: f32,
    pub vqbit_truth: f32,
    pub prim_id: u32,
}

pub fn parse_usd_file<P: AsRef<Path>>(path: P) -> Result<Vec<vQbitPrimitive>, String> {
    let content = fs::read_to_string(path.as_ref())
        .map_err(|e| format!("Failed to open USD file {}: {}", path.as_ref().display(), e))?;
    Ok(parse_usd_string(&content))
}

pub fn parse_usd_string(content: &str) -> Vec<vQbitPrimitive> {
    let mut prims = Vec::new();
    let mut prim_id = 0u32;

    let entropy_re = Regex::new(r"custom_vQbit:entropy_delta\s*=\s*([-\d.]+)").unwrap();
    let truth_re = Regex::new(r"custom_vQbit:truth_threshold\s*=\s*([-\d.]+)").unwrap();

    for cap in Regex::new(r"def\s+Scope").unwrap().find_iter(content) {
        let start = cap.start();
        let slice = &content[start..];

        let entropy = entropy_re.captures(slice)
            .and_then(|c| c.get(1))
            .and_then(|m| m.as_str().parse::<f32>().ok())
            .unwrap_or(0.0);

        let truth = truth_re.captures(slice)
            .and_then(|c| c.get(1))
            .and_then(|m| m.as_str().parse::<f32>().ok())
            .unwrap_or(0.0);

        prims.push(vQbitPrimitive {
            vqbit_entropy: entropy,
            vqbit_truth: truth,
            prim_id,
            ..Default::default()
        });
        prim_id += 1;
    }

    prims
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn temp_usd(content: &str) -> NamedTempFile {
        let mut f = NamedTempFile::new().unwrap();
        f.write_all(content.as_bytes()).unwrap();
        f.flush().unwrap();
        f
    }

    #[test]
    fn iq_003_vqbit_primitive_repr_c() {
        assert_eq!(std::mem::size_of::<vQbitPrimitive>(), 76);
    }

    #[test]
    fn tp_001_parse_two_prims() {
        let f = temp_usd(r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
        float custom_vQbit:entropy_delta = 0.5
        float custom_vQbit:truth_threshold = 0.9
    }
    def Scope "Cell2" {
        float custom_vQbit:entropy_delta = 0.7
        float custom_vQbit:truth_threshold = 0.8
    }
}
"#);
        let prims = parse_usd_file(f.path()).unwrap();
        assert_eq!(prims.len(), 2);
        assert_eq!(prims[0].prim_id, 0);
        assert_eq!(prims[0].vqbit_entropy, 0.5);
        assert_eq!(prims[0].vqbit_truth, 0.9);
        assert_eq!(prims[1].prim_id, 1);
        assert_eq!(prims[1].vqbit_entropy, 0.7);
        assert_eq!(prims[1].vqbit_truth, 0.8);
    }

    #[test]
    fn tp_006_nine_canonical_prims() {
        let f = temp_usd(r#"
#usda 1.0
def "World" {
    def Scope "Tokamak" { float custom_vQbit:entropy_delta = 0.1; float custom_vQbit:truth_threshold = 0.91; }
    def Scope "Stellarator" { float custom_vQbit:entropy_delta = 0.2; float custom_vQbit:truth_threshold = 0.92; }
    def Scope "FRC" { float custom_vQbit:entropy_delta = 0.3; float custom_vQbit:truth_threshold = 0.93; }
    def Scope "Spheromak" { float custom_vQbit:entropy_delta = 0.4; float custom_vQbit:truth_threshold = 0.94; }
    def Scope "Mirror" { float custom_vQbit:entropy_delta = 0.5; float custom_vQbit:truth_threshold = 0.95; }
    def Scope "Inertial" { float custom_vQbit:entropy_delta = 0.6; float custom_vQbit:truth_threshold = 0.96; }
    def Scope "SphericalTokamak" { float custom_vQbit:entropy_delta = 0.7; float custom_vQbit:truth_threshold = 0.97; }
    def Scope "ZPinch" { float custom_vQbit:entropy_delta = 0.8; float custom_vQbit:truth_threshold = 0.98; }
    def Scope "MIF" { float custom_vQbit:entropy_delta = 0.9; float custom_vQbit:truth_threshold = 0.99; }
}
"#);
        let prims = parse_usd_file(f.path()).unwrap();
        assert_eq!(prims.len(), 9);
        for i in 0..9 {
            assert_eq!(prims[i].prim_id, i as u32);
            let expected = (i as f32 + 1.0) * 0.1;
            assert!((prims[i].vqbit_entropy - expected).abs() < 1e-5);
        }
    }
}
