# Illuminants

Spec §5.2 / §7.3. Four scene illuminants:

| Name                     | Temperature | Use                                  |
|--------------------------|-------------|--------------------------------------|
| `candle_1850k.json`      | 1850 K      | Beeswax candle                       |
| `oil_lamp_2200k.json`    | 2200 K      | Argand oil lamp (Franklin's study)   |
| `window_north_7000k.json`| 7000 K      | North-facing daylight                |
| `afternoon_5500k.json`   | 5500 K      | Direct afternoon sun                 |

## Format

Each file is a JSON object:

```json
{
  "name":          "candle_1850k",
  "temperature_k": 1850.0,
  "spd":           [f32, f32, ...]
}
```

`spd` length matches the bundle's `spectral_tier_target` (16, 32, or 64).
Bins are linearly spaced across 380–780nm. Values are normalised so the peak
sample is 1.0.

## Reproducing

The bundle build invokes:

```sh
cargo run --bin gen_illuminants -- \
    --bins 64 \
    --output cells/franklin/avatar/assets/illuminants/
```

The generator is in `tools/gen_pose_templates` (despite the name, it also
produces illuminants on `--include-illuminants`). Reproducible because it's a
Planckian blackbody computed from a hardcoded constant; producer and verifier
land at the same bytes given the same temperature + bin count.

The four files committed here are reference values at 64 bins so the tests in
`avatar-render` can validate the runtime resampler.
