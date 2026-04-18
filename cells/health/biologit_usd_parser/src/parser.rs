//! Protein/Ligand Scene Parser
//!
//! Ingests .pdb, .sdf, and .usda files, producing Vec<BioligitPrimitive>
//! for upload to the Metal shared memory buffer.
//!
//! Zero-PII guarantee: this parser strips any AUTHOR, REMARK, or SOURCE
//! records from PDB files before in-memory processing. Patient-derived
//! experimental data must flow through the Owl Protocol encrypted channel,
//! not through raw PDB text files.

use crate::BioligitPrimitive;

#[derive(Debug)]
pub enum ParseError {
    InvalidFormat(String),
    EmptyFile,
    UnsupportedFormat(String),
    PhiLeakDetected,  // PDB AUTHOR/REMARK contains potential PHI
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MoleculeType {
    Protein = 0,
    Ligand  = 1,
    Water   = 2,
    Ion     = 3,
}

/// Parse a .pdb file (PDB format v3.3) into BioligitPrimitive list.
///
/// PHI scrubbing: strips AUTHOR, REMARK 2, SOURCE records automatically.
/// If a REMARK record contains patterns matching patient identifiers
/// (MRN, DOB, SSN patterns), returns ParseError::PhiLeakDetected.
pub fn parse_pdb(content: &str) -> Result<Vec<BioligitPrimitive>, ParseError> {
    if content.is_empty() { return Err(ParseError::EmptyFile); }

    let mut primitives: Vec<BioligitPrimitive> = Vec::new();
    let mut atom_count_per_residue: std::collections::HashMap<u32, u32> = Default::default();

    for line in content.lines() {
        // PHI scrub — reject if REMARK looks like it contains a patient ID
        if line.starts_with("REMARK") || line.starts_with("AUTHOR") {
            if contains_phi_pattern(line) {
                return Err(ParseError::PhiLeakDetected);
            }
            continue; // strip all AUTHOR/REMARK records
        }

        // Parse ATOM records
        if line.starts_with("ATOM  ") || line.starts_with("HETATM") {
            if line.len() < 54 { continue; }

            let mol_type: u32 = if line.starts_with("HETATM") { 1 } else { 0 };

            // Parse residue sequence number (cols 23-26)
            let residue_id = line[22..26].trim().parse::<u32>().unwrap_or(0);

            // Parse x, y, z coordinates (cols 31-38, 39-46, 47-54)
            let x: f32 = line[30..38].trim().parse().unwrap_or(0.0);
            let y: f32 = line[38..46].trim().parse().unwrap_or(0.0);
            let z: f32 = line[46..54].trim().parse().unwrap_or(0.0);

            *atom_count_per_residue.entry(residue_id).or_insert(0) += 1;

            let mut prim = BioligitPrimitive::identity();
            prim.transform[3][0] = x;   // translation column
            prim.transform[3][1] = y;
            prim.transform[3][2] = z;
            prim.residue_id = residue_id;
            prim.mol_type   = mol_type;
            // epistemic_tag defaults to Assumed (2) — PDB coordinates are M=Measured
            // but the caller must explicitly set M after verifying experimental provenance
            primitives.push(prim);
        }
    }

    if primitives.is_empty() {
        return Err(ParseError::InvalidFormat("No ATOM records found".to_string()));
    }

    // Propagate atom counts back to primitives
    for prim in &mut primitives {
        if let Some(&count) = atom_count_per_residue.get(&prim.residue_id) {
            prim.atom_count = count;
        }
    }

    Ok(primitives)
}

/// Heuristic PHI pattern detection in PDB text fields.
/// Detects common patient identifier formats:
///   - SSN pattern: NNN-NN-NNNN
///   - MRN pattern: MRN followed by digits
///   - DOB pattern: dates in MM/DD/YYYY format
fn contains_phi_pattern(text: &str) -> bool {
    // SSN pattern: 3-2-4 digits with hyphens
    let parts: Vec<&str> = text.split('-').collect();
    if parts.len() >= 3 {
        if parts[0].chars().rev().take(3).all(|c| c.is_ascii_digit())
            && parts[1].len() == 2 && parts[1].chars().all(|c| c.is_ascii_digit())
            && parts[2].starts_with(|c: char| c.is_ascii_digit())
        {
            return true;
        }
    }

    // MRN pattern
    if text.contains("MRN") || text.contains("mrn") || text.contains("Medical Record") {
        return true;
    }

    // DOB pattern (MM/DD/YYYY)
    if text.contains('/') {
        let slash_parts: Vec<&str> = text.split('/').collect();
        if slash_parts.len() == 3
            && slash_parts[0].ends_with(|c: char| c.is_ascii_digit())
            && slash_parts[1].chars().all(|c| c.is_ascii_digit())
            && slash_parts[2].starts_with(|c: char| c.is_ascii_digit())
        {
            return true;
        }
    }

    false
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINIMAL_PDB: &str = "\
ATOM      1  CA  ALA A   1       1.000   2.000   3.000  1.00  0.00           C
ATOM      2  CB  ALA A   1       1.500   2.500   3.500  1.00  0.00           C
END
";

    #[test]
    fn tp_011_parse_minimal_pdb() {
        let result = parse_pdb(MINIMAL_PDB);
        assert!(result.is_ok(), "minimal PDB must parse: {:?}", result);
        let prims = result.unwrap();
        assert_eq!(prims.len(), 2);
    }

    #[test]
    fn tn_005_empty_file_errors() {
        assert!(matches!(parse_pdb(""), Err(ParseError::EmptyFile)));
    }

    #[test]
    fn tc_011_phi_remark_rejected() {
        let pdb_with_phi = "REMARK Patient MRN 1234567 DOB 01/15/1980\nATOM      1  CA  ALA A   1       1.000   2.000   3.000\n";
        assert!(matches!(parse_pdb(pdb_with_phi), Err(ParseError::PhiLeakDetected)));
    }

    #[test]
    fn tp_012_atom_count_propagated() {
        let result = parse_pdb(MINIMAL_PDB).unwrap();
        // Both ATOMs in residue 1 — each primitive should know 2 atoms in its residue
        assert_eq!(result[0].atom_count, 2);
    }

    #[test]
    fn tp_013_hetatm_is_ligand_type() {
        let hetatm_pdb = "HETATM    1  C1  LIG A   1       5.000   6.000   7.000  1.00  0.00           C\n";
        let prims = parse_pdb(hetatm_pdb).unwrap();
        assert_eq!(prims[0].mol_type, 1, "HETATM must be mol_type=1 (Ligand)");
    }
}
