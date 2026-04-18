use anyhow::Result;
use ndarray::Array2;

/// Orthonormal basis projector: compresses hidden states via an orthonormal basis `B`.
///
/// - `basis` shape: [k, d]
/// - compress: alpha = H · Bᵀ => [N, k]
/// - reconstruct: Ĥ = alpha · B => [N, d]
///
/// This is deterministic and auditable; basis is orthonormalized via Gram-Schmidt.
#[derive(Debug, Clone)]
pub struct QuantumBasisCompressor {
    pub hidden_dim: usize,
    pub compressed_dim: usize,
    pub basis: Array2<f32>, // [k, d]
}

impl QuantumBasisCompressor {
    pub fn new(hidden_dim: usize, compressed_dim: usize) -> Result<Self> {
        anyhow::ensure!(compressed_dim > 0, "compressed_dim must be > 0");
        anyhow::ensure!(hidden_dim > 0, "hidden_dim must be > 0");
        anyhow::ensure!(
            compressed_dim <= hidden_dim,
            "compressed_dim must be <= hidden_dim"
        );

        // Deterministic seed basis: first k rows of identity (orthonormal).
        let mut basis = Array2::<f32>::zeros((compressed_dim, hidden_dim));
        for i in 0..compressed_dim {
            basis[(i, i)] = 1.0;
        }

        Ok(Self {
            hidden_dim,
            compressed_dim,
            basis,
        })
    }

    pub fn compress(&self, hidden: &Array2<f32>) -> Result<Array2<f32>> {
        anyhow::ensure!(
            hidden.ncols() == self.hidden_dim,
            "hidden dim mismatch: got {}, expected {}",
            hidden.ncols(),
            self.hidden_dim
        );
        let n = hidden.nrows();
        let mut out = Array2::<f32>::zeros((n, self.compressed_dim));

        // out[n,k] = sum_d hidden[n,d] * basis[k,d]
        for i in 0..n {
            for k in 0..self.compressed_dim {
                let mut s = 0.0f32;
                for d in 0..self.hidden_dim {
                    s += hidden[(i, d)] * self.basis[(k, d)];
                }
                out[(i, k)] = s;
            }
        }
        Ok(out)
    }

    pub fn reconstruct(&self, compressed: &Array2<f32>) -> Result<Array2<f32>> {
        anyhow::ensure!(
            compressed.ncols() == self.compressed_dim,
            "compressed dim mismatch: got {}, expected {}",
            compressed.ncols(),
            self.compressed_dim
        );
        let n = compressed.nrows();
        let mut out = Array2::<f32>::zeros((n, self.hidden_dim));

        // out[n,d] = sum_k compressed[n,k] * basis[k,d]
        for i in 0..n {
            for d in 0..self.hidden_dim {
                let mut s = 0.0f32;
                for k in 0..self.compressed_dim {
                    s += compressed[(i, k)] * self.basis[(k, d)];
                }
                out[(i, d)] = s;
            }
        }
        Ok(out)
    }

    pub fn reconstruction_mse(&self, hidden: &Array2<f32>) -> Result<f32> {
        let c = self.compress(hidden)?;
        let r = self.reconstruct(&c)?;
        let mut s = 0.0f64;
        let mut n = 0u64;
        for i in 0..hidden.nrows() {
            for d in 0..hidden.ncols() {
                let diff = (hidden[(i, d)] - r[(i, d)]) as f64;
                s += diff * diff;
                n += 1;
            }
        }
        if n == 0 {
            return Ok(0.0);
        }
        Ok((s / (n as f64)).sqrt() as f32)
    }

    pub fn orthonormalize(&mut self) {
        // Gram-Schmidt over basis rows.
        for i in 0..self.compressed_dim {
            // Subtract projections onto previous rows
            for j in 0..i {
                let dot = dot_row(&self.basis, i, j, self.hidden_dim);
                for d in 0..self.hidden_dim {
                    self.basis[(i, d)] -= dot * self.basis[(j, d)];
                }
            }
            // Normalize
            let norm = row_norm(&self.basis, i, self.hidden_dim).max(1e-12);
            for d in 0..self.hidden_dim {
                self.basis[(i, d)] /= norm;
            }
        }
    }
}

fn dot_row(basis: &Array2<f32>, i: usize, j: usize, d: usize) -> f32 {
    let mut s = 0.0f32;
    for k in 0..d {
        s += basis[(i, k)] * basis[(j, k)];
    }
    s
}

fn row_norm(basis: &Array2<f32>, i: usize, d: usize) -> f32 {
    let mut s = 0.0f32;
    for k in 0..d {
        let v = basis[(i, k)];
        s += v * v;
    }
    s.sqrt()
}


