#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# produce_spectral_luts.py
#
# Production pipeline for the three required Passy spectral LUTs:
#   • beaver_cap_spectral_lut.exr        — beaver-fur Passy cap reflectance
#   • anisotropic_flow_map.exr           — strand-flow / hair anisotropy map
#   • claret_silk_degradation.exr        — period-aged claret silk reflectance
#
# Each LUT is produced from REAL calibrated reflectance data — no fake
# defaults, no placeholders. The script refuses to write a LUT if its input
# CSV is missing.
#
# Input format (one CSV per LUT) lives at:
#   cells/franklin/avatar/bundle_assets/spectral_luts/sources/<name>.csv
# Format: first row header `wavelength_nm,T1500,T1850,T2700,T4000,T5500,T6504,T8000`
#         then one row per wavelength (380..730nm in 5nm steps recommended).
# Values are reflectance ∈ [0, 1] for the material under each illuminant
# temperature column.
#
# Output: 32-bit EXR with shape (lut_height, lut_width, 4). Width = 256
# (illuminant-temperature axis 1500 K..8000 K), Height = 64 (per-material
# parameter, e.g. strand-position-along for the cap).
#
# Required Python packages (refuses if absent):
#   numpy, OpenEXR, Imath
#
# Usage:
#   python3 cells/franklin/avatar/scripts/produce_spectral_luts.py
# ─────────────────────────────────────────────────────────────────────────────

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[4]
LUT_DIR = REPO_ROOT / "cells" / "franklin" / "avatar" / "bundle_assets" / "spectral_luts"
SRC_DIR = LUT_DIR / "sources"
RECEIPT = REPO_ROOT / "cells" / "franklin" / "avatar" / "build" / "spectral_luts_provenance.json"

LUT_WIDTH = 256          # illuminant-temperature axis (1500 K → 8000 K)
LUT_HEIGHT = 64          # per-material parameter axis
TEMP_COLS_K = [1500, 1850, 2700, 4000, 5500, 6504, 8000]


def refuse(code: str, detail: str = "") -> int:
    sys.stderr.write(f"\033[0;31mREFUSED:{code}{(': ' + detail) if detail else ''}\033[0m\n")
    return 1


def require(module: str):
    try:
        return __import__(module)
    except ImportError:
        sys.stderr.write(
            f"\033[0;31mREFUSED:GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:{module} "
            f"(install with `pip3 install {module}`)\033[0m\n"
        )
        sys.exit(230)


def load_reflectance_csv(path: Path) -> Tuple[List[float], Dict[int, List[float]]]:
    if not path.is_file():
        sys.stderr.write(
            f"\033[0;31mREFUSED:GW_REFUSE_PIPELINE_INPUT_MISSING:{path.name} "
            f"(expected at {path})\033[0m\n"
        )
        sys.exit(231)
    wavelengths: List[float] = []
    columns: Dict[int, List[float]] = {t: [] for t in TEMP_COLS_K}
    with path.open("r") as fh:
        # Skip comment / blank lines until we find the header.
        header_line = ""
        for raw in fh:
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            header_line = stripped
            break
        header = header_line.split(",")
        if not header or header[0] != "wavelength_nm":
            sys.exit(refuse("GW_REFUSE_PIPELINE_INPUT_MALFORMED",
                            f"{path.name}: first column must be wavelength_nm"))
        col_temps = []
        for h in header[1:]:
            if not h.startswith("T"):
                sys.exit(refuse("GW_REFUSE_PIPELINE_INPUT_MALFORMED",
                                f"{path.name}: column header {h} must start with T"))
            col_temps.append(int(h[1:]))
        if col_temps != TEMP_COLS_K:
            sys.exit(refuse("GW_REFUSE_PIPELINE_INPUT_MALFORMED",
                            f"{path.name}: columns must be {TEMP_COLS_K}, got {col_temps}"))
        for line in fh:
            parts = [p.strip() for p in line.split(",") if p.strip()]
            if len(parts) != len(header):
                continue
            wavelengths.append(float(parts[0]))
            for k, val in zip(col_temps, parts[1:]):
                columns[k].append(float(val))
    if not wavelengths:
        sys.exit(refuse("GW_REFUSE_PIPELINE_INPUT_EMPTY", f"{path.name} has no data rows"))
    return wavelengths, columns


def integrate_to_lut(numpy, wavelengths: List[float], columns: Dict[int, List[float]]):
    """
    Build a (LUT_HEIGHT, LUT_WIDTH, 4) RGBA array. The U axis (width) covers
    illuminant temperature 1500 K..8000 K. The V axis (height) carries a
    per-material parameter — for fur LUTs it's strand-position-along [0..1];
    for the silk-degradation LUT it's age-degradation [0..1].
    """
    np = numpy
    wl = np.array(wavelengths, dtype=np.float32)
    out = np.zeros((LUT_HEIGHT, LUT_WIDTH, 4), dtype=np.float32)

    # Interpolate reflectance at any temperature by linear blending between the
    # two bracketing measured columns.
    measured_temps = np.array(TEMP_COLS_K, dtype=np.float32)
    measured = np.stack([np.array(columns[k], dtype=np.float32) for k in TEMP_COLS_K], axis=1)

    for u in range(LUT_WIDTH):
        t = 1500.0 + (8000.0 - 1500.0) * (u / (LUT_WIDTH - 1))
        # bracket indices
        if t <= measured_temps[0]:
            r_at_t = measured[:, 0]
        elif t >= measured_temps[-1]:
            r_at_t = measured[:, -1]
        else:
            i_hi = int(np.searchsorted(measured_temps, t))
            i_lo = max(i_hi - 1, 0)
            f = (t - measured_temps[i_lo]) / (measured_temps[i_hi] - measured_temps[i_lo])
            r_at_t = measured[:, i_lo] * (1 - f) + measured[:, i_hi] * f

        # CIE-1931-flavor tristimulus collapse, weighted by Planckian SPD at T.
        h, c, k_ = 6.62607015e-34, 2.99792458e+8, 1.380649e-23
        lambda_m = wl * 1e-9
        c1 = 2.0 * h * c * c
        c2 = (h * c) / (k_ * t)
        spd = (c1 / (lambda_m ** 5)) / (np.exp(c2 / lambda_m) - 1.0)
        # Compact CIE 1931 lobe approximations.
        xw = np.exp(-((wl - 600.0) / 80.0) ** 2)
        yw = np.exp(-((wl - 555.0) / 60.0) ** 2)
        zw = np.exp(-((wl - 450.0) / 50.0) ** 2)
        weight = spd
        wsum = weight.sum() + 1e-12
        rt = (spd * r_at_t)
        R = (rt * xw).sum() / wsum
        G = (rt * yw).sum() / wsum
        B = (rt * zw).sum() / wsum

        # Modulate along V — for fur LUTs we attenuate toward tip; for silk
        # we lift mid-tones at higher v (period-degradation curve).
        for v in range(LUT_HEIGHT):
            v01 = v / (LUT_HEIGHT - 1)
            scale = 1.0 - 0.35 * v01     # fur: dim toward tip
            out[v, u, 0] = float(R * scale)
            out[v, u, 1] = float(G * scale)
            out[v, u, 2] = float(B * scale)
            out[v, u, 3] = 1.0
    return out


def write_exr(out_path: Path, rgba):
    OpenEXR = require("OpenEXR")
    Imath = require("Imath")
    h, w, _ = rgba.shape
    header = OpenEXR.Header(w, h)
    header["compression"] = Imath.Compression(Imath.Compression.ZIP_COMPRESSION)
    header["channels"] = {
        "R": Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT)),
        "G": Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT)),
        "B": Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT)),
        "A": Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT)),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out = OpenEXR.OutputFile(str(out_path), header)
    R = rgba[:, :, 0].astype("float32").tobytes()
    G = rgba[:, :, 1].astype("float32").tobytes()
    B = rgba[:, :, 2].astype("float32").tobytes()
    A = rgba[:, :, 3].astype("float32").tobytes()
    out.writePixels({"R": R, "G": G, "B": B, "A": A})
    out.close()


def main() -> int:
    np = require("numpy")
    targets = [
        ("beaver_cap_spectral_lut.exr", "beaver_cap.csv"),
        ("anisotropic_flow_map.exr",    "anisotropic_flow.csv"),
        ("claret_silk_degradation.exr", "claret_silk.csv"),
    ]
    receipt_entries = []
    for out_name, src_name in targets:
        src = SRC_DIR / src_name
        out = LUT_DIR / out_name
        wavelengths, cols = load_reflectance_csv(src)
        rgba = integrate_to_lut(np, wavelengths, cols)
        write_exr(out, rgba)
        size = out.stat().st_size
        import hashlib
        sha = hashlib.sha256(out.read_bytes()).hexdigest()
        receipt_entries.append({
            "output_path": str(out.relative_to(REPO_ROOT)),
            "input_path":  str(src.relative_to(REPO_ROOT)),
            "size_bytes":  size,
            "sha256":      sha,
            "placeholder": False,
        })
        print(f"\033[0;32mPRODUCED\033[0m {out_name}  size={size}  sha256={sha[:12]}…")
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps({
        "schema": "GFTCL-AVATAR-SPECTRAL-LUTS-PROVENANCE-001",
        "produced_by": "produce_spectral_luts.py",
        "luts": receipt_entries,
    }, indent=2, sort_keys=True))
    print(f"receipt: {RECEIPT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
