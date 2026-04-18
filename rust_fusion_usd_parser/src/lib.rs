#![allow(clippy::assertions_on_constants)]
#![allow(clippy::needless_range_loop)]

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

/// A single vQbit USD primitive extracted from a `.usda` file.
///
/// Field-name mapping (Rust ↔ USDA on-disk):
///   `vqbit_entropy`  ←  `custom_vQbit:entropy_delta`
///   `vqbit_truth`    ←  `custom_vQbit:truth_threshold`
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct vQbitPrimitive {
    pub transform: [[f32; 4]; 4],
    pub vqbit_entropy: f32, // maps to custom_vQbit:entropy_delta in USDA
    pub vqbit_truth: f32,   // maps to custom_vQbit:truth_threshold in USDA
    pub prim_id: u32,
}

pub struct UsdParser;

impl UsdParser {
    /// Scan `line` for the USDA attribute keywords `entropy_delta` and
    /// `truth_threshold`, parse their values, and store them into the
    /// corresponding Rust fields `vqbit_entropy` / `vqbit_truth`.
    ///
    /// Both attributes are checked independently (no `else if`) so a
    /// compact one-liner holds both values correctly.
    fn parse_attrs_from_line(line: &str, prim: &mut vQbitPrimitive) {
        let lower = line.to_lowercase();

        // USDA keyword: custom_vQbit:entropy_delta  →  prim.vqbit_entropy
        if lower.contains("entropy_delta") {
            if let Some(kw_pos) = lower.find("entropy_delta") {
                let rest = &line[kw_pos..];
                if let Some(eq_rel) = rest.find('=') {
                    let after = &rest[eq_rel + 1..];
                    let token = after
                        .split_whitespace()
                        .next()
                        .unwrap_or("0.0")
                        .trim_end_matches(';')
                        .trim();
                    if let Ok(v) = token.parse::<f32>() {
                        prim.vqbit_entropy = v;
                    }
                }
            }
        }

        // USDA keyword: custom_vQbit:truth_threshold  →  prim.vqbit_truth
        // Independent `if` (NOT else-if) — never skipped when entropy_delta
        // was already found on the same line.
        if lower.contains("truth_threshold") {
            if let Some(kw_pos) = lower.find("truth_threshold") {
                let rest = &line[kw_pos..];
                if let Some(eq_rel) = rest.find('=') {
                    let after = &rest[eq_rel + 1..];
                    let token = after
                        .split_whitespace()
                        .next()
                        .unwrap_or("0.0")
                        .trim_end_matches(';')
                        .trim();
                    if let Ok(v) = token.parse::<f32>() {
                        prim.vqbit_truth = v;
                    }
                }
            }
        }
    }

    pub fn parse_usd_file<P: AsRef<Path>>(file_path: P) -> Result<Vec<vQbitPrimitive>, String> {
        let file = File::open(&file_path).map_err(|e| {
            format!(
                "Failed to open USD file {}: {}",
                file_path.as_ref().display(),
                e
            )
        })?;
        let reader = BufReader::new(file);

        let mut primitives = Vec::new();
        let mut prim_id_counter = 0u32;
        let mut in_prim_scope = false;
        let mut current_prim: Option<vQbitPrimitive> = None;

        for line_result in reader.lines() {
            let line =
                line_result.map_err(|e| format!("Failed to read line from USD file: {e}"))?;
            let trimmed = line.trim();
            let lower = trimmed.to_lowercase();

            if lower.contains("def scope") {
                // Flush any previously open prim before starting a new one.
                if let Some(prim) = current_prim.take() {
                    primitives.push(prim);
                }

                let mut new_prim = vQbitPrimitive {
                    prim_id: prim_id_counter,
                    ..Default::default()
                };
                prim_id_counter += 1;

                // Parse attributes on the SAME line as the def Scope opener
                // (compact one-liner format).
                Self::parse_attrs_from_line(trimmed, &mut new_prim);

                // If the scope closes on this same line, commit immediately.
                if trimmed.contains('}') {
                    primitives.push(new_prim);
                    in_prim_scope = false;
                    current_prim = None;
                } else {
                    current_prim = Some(new_prim);
                    in_prim_scope = true;
                }
            } else if trimmed == "}" && in_prim_scope {
                if let Some(prim) = current_prim.take() {
                    primitives.push(prim);
                }
                in_prim_scope = false;
            } else if in_prim_scope {
                if let Some(prim) = current_prim.as_mut() {
                    Self::parse_attrs_from_line(trimmed, prim);
                }
            }
        }

        // Commit any prim still open at EOF (no closing brace).
        if let Some(prim) = current_prim.take() {
            primitives.push(prim);
        }

        Ok(primitives)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn create_temp_usd_file(content: &str) -> tempfile::NamedTempFile {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        Write::write_all(&mut file, content.as_bytes()).unwrap();
        file
    }

    // ── IQ ───────────────────────────────────────────────────────────────────

    #[test]
    fn iq_001_parser_compiles() {
        assert!(true);
    }

    #[test]
    fn iq_003_vqbit_primitive_repr_c() {
        assert_eq!(std::mem::size_of::<vQbitPrimitive>(), 76);
    }

    #[test]
    fn iq_004_field_offsets() {
        assert_eq!(std::mem::offset_of!(vQbitPrimitive, transform), 0);
        assert_eq!(std::mem::offset_of!(vQbitPrimitive, vqbit_entropy), 64);
        assert_eq!(std::mem::offset_of!(vQbitPrimitive, vqbit_truth), 68);
        assert_eq!(std::mem::offset_of!(vQbitPrimitive, prim_id), 72);
    }

    // ── TP ───────────────────────────────────────────────────────────────────

    #[test]
    fn tp_001_parse_two_prims() {
        let usd_content = r#"
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
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();

        assert_eq!(prims.len(), 2);
        assert_eq!(prims[0].prim_id, 0);
        assert_eq!(prims[0].vqbit_entropy, 0.5);
        assert_eq!(prims[0].vqbit_truth, 0.9);
        assert_eq!(prims[1].prim_id, 1);
        assert_eq!(prims[1].vqbit_entropy, 0.7);
        assert_eq!(prims[1].vqbit_truth, 0.8);
    }

    #[test]
    fn tp_002_parse_empty_world() {
        let usd_content = "#usda 1.0\ndef \"World\" {\n}\n";
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 0);
    }

    #[test]
    fn tp_003_parse_no_custom_attrs() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert_eq!(prims[0].vqbit_entropy, 0.0);
        assert_eq!(prims[0].vqbit_truth, 0.0);
    }

    #[test]
    fn tp_004_file_not_found() {
        let result = UsdParser::parse_usd_file("/tmp/this_file_does_not_exist_gaiaftcl.usda");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Failed to open USD file"));
    }

    #[test]
    fn tp_005_header_only() {
        let temp_file = create_temp_usd_file("#usda 1.0\n");
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 0);
    }

    #[test]
    fn tp_006_nine_canonical_prims() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Tokamak"         { float custom_vQbit:entropy_delta = 0.1; float custom_vQbit:truth_threshold = 0.91; }
    def Scope "Stellarator"     { float custom_vQbit:entropy_delta = 0.2; float custom_vQbit:truth_threshold = 0.92; }
    def Scope "FRC"             { float custom_vQbit:entropy_delta = 0.3; float custom_vQbit:truth_threshold = 0.93; }
    def Scope "Spheromak"       { float custom_vQbit:entropy_delta = 0.4; float custom_vQbit:truth_threshold = 0.94; }
    def Scope "Mirror"          { float custom_vQbit:entropy_delta = 0.5; float custom_vQbit:truth_threshold = 0.95; }
    def Scope "Inertial"        { float custom_vQbit:entropy_delta = 0.6; float custom_vQbit:truth_threshold = 0.96; }
    def Scope "SphericalTokamak"{ float custom_vQbit:entropy_delta = 0.7; float custom_vQbit:truth_threshold = 0.97; }
    def Scope "ZPinch"          { float custom_vQbit:entropy_delta = 0.8; float custom_vQbit:truth_threshold = 0.98; }
    def Scope "MIF"             { float custom_vQbit:entropy_delta = 0.9; float custom_vQbit:truth_threshold = 0.99; }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();

        assert_eq!(prims.len(), 9);
        for i in 0..9 {
            assert_eq!(prims[i].prim_id, i as u32);

            // Approximate comparison — f32 arithmetic (e.g. 9.0 * 0.1) can
            // differ by 1 ULP from the same literal parsed as a string.
            let expected_entropy = (i as f32 + 1.0) * 0.1;
            assert!(
                (prims[i].vqbit_entropy - expected_entropy).abs() < 1e-5,
                "prim[{i}] vqbit_entropy: got {}, expected {expected_entropy}",
                prims[i].vqbit_entropy
            );

            let expected_truth = 0.91 + i as f32 * 0.01;
            assert!(
                (prims[i].vqbit_truth - expected_truth).abs() < 1e-5,
                "prim[{i}] vqbit_truth: got {}, expected {expected_truth}",
                prims[i].vqbit_truth
            );
        }
    }

    #[test]
    fn tp_007_mixed_format() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "OneLiner" { float custom_vQbit:entropy_delta = 0.3; float custom_vQbit:truth_threshold = 0.7; }
    def Scope "MultiLine" {
        float custom_vQbit:entropy_delta = 0.6
        float custom_vQbit:truth_threshold = 0.4
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 2);
        assert!((prims[0].vqbit_entropy - 0.3).abs() < 1e-5);
        assert!((prims[0].vqbit_truth - 0.7).abs() < 1e-5);
        assert!((prims[1].vqbit_entropy - 0.6).abs() < 1e-5);
        assert!((prims[1].vqbit_truth - 0.4).abs() < 1e-5);
    }

    #[test]
    fn tp_008_extra_whitespace() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
        float custom_vQbit:entropy_delta   =   0.55
        float custom_vQbit:truth_threshold =   0.88
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert!((prims[0].vqbit_entropy - 0.55).abs() < 1e-5);
        assert!((prims[0].vqbit_truth - 0.88).abs() < 1e-5);
    }

    #[test]
    fn tp_009_reversed_attr_order() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
        float custom_vQbit:truth_threshold = 0.75
        float custom_vQbit:entropy_delta = 0.25
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert!((prims[0].vqbit_entropy - 0.25).abs() < 1e-5);
        assert!((prims[0].vqbit_truth - 0.75).abs() < 1e-5);
    }

    #[test]
    fn tp_010_prim_id_sequence() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "A" { float custom_vQbit:entropy_delta = 0.1; float custom_vQbit:truth_threshold = 0.9; }
    def Scope "B" { float custom_vQbit:entropy_delta = 0.2; float custom_vQbit:truth_threshold = 0.8; }
    def Scope "C" { float custom_vQbit:entropy_delta = 0.3; float custom_vQbit:truth_threshold = 0.7; }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 3);
        assert_eq!(prims[0].prim_id, 0);
        assert_eq!(prims[1].prim_id, 1);
        assert_eq!(prims[2].prim_id, 2);
    }

    // ── TN ───────────────────────────────────────────────────────────────────

    #[test]
    fn tn_001_malformed_float_no_panic() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
        float custom_vQbit:entropy_delta = NOT_A_FLOAT
        float custom_vQbit:truth_threshold = 0.5
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert_eq!(prims[0].vqbit_entropy, 0.0); // malformed → default
        assert!((prims[0].vqbit_truth - 0.5).abs() < 1e-5);
    }

    #[test]
    fn tn_002_no_equals_sign_no_panic() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {
        # entropy_delta mentioned in comment with no equals sign
        float custom_vQbit:truth_threshold = 0.5
    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert_eq!(prims[0].vqbit_entropy, 0.0);
        assert!((prims[0].vqbit_truth - 0.5).abs() < 1e-5);
    }

    #[test]
    fn tn_003_empty_file_no_panic() {
        let temp_file = create_temp_usd_file("");
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 0);
    }

    #[test]
    fn tn_004_scope_whitespace_only() {
        let usd_content = r#"
#usda 1.0
def "World" {
    def Scope "Cell1" {

    }
}
"#;
        let temp_file = create_temp_usd_file(usd_content);
        let prims = UsdParser::parse_usd_file(temp_file.path()).unwrap();
        assert_eq!(prims.len(), 1);
        assert_eq!(prims[0].vqbit_entropy, 0.0);
        assert_eq!(prims[0].vqbit_truth, 0.0);
    }
}

#[cfg(test)]
mod iq_tests {
    #[test]
    fn iq_001_parser_compiles() {
        assert!(true, "Parser crate compiles");
    }
}
