# GaiaFTCL Mac Cell — Complete Technical Guide

**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

---

## What This Is

GaiaFTCL is a sovereign fusion-plant rendering and control system that runs natively on Apple Silicon. It is not a web app. It is not a cross-platform abstraction. It is not built on a game engine. It is a purpose-built macOS application that speaks directly to the Apple Metal GPU API, lives inside Apple Silicon's unified memory architecture, and renders nine canonical fusion plant types using precompiled Metal Shading Language pipelines — one per plant kind.

The system is designed for deployment at CERN and qualified to GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11. Every data value it produces carries an epistemic classification tag. Every plant swap it executes goes through a defined five-state lifecycle. Every build it produces runs 32 automated GxP tests before it is considered operational.

This document explains how the system works — from the physics of each plant kind, through the vQbit data model, through unified memory, through the Metal render pipeline, to the frame you see on screen.

---

## The Apple Silicon Advantage — Unified Memory

Apple Silicon M-chips eliminate the boundary between CPU memory and GPU memory. On every other computing architecture, getting data from the CPU to the GPU requires an explicit copy — the application writes data to system RAM, the GPU driver copies it across the PCIe bus into VRAM, and the GPU reads from VRAM. That copy takes time, consumes bandwidth, and introduces a synchronisation point.

On Apple Silicon, there is one pool of physical DRAM. The CPU and GPU both read and write from the same physical addresses. There is no PCIe bus between them. There is no VRAM. There is no copy.

GaiaFTCL is built entirely around this property. Every Metal buffer in the renderer is allocated with `MTLResourceOptions::StorageModeShared`. This is the direct instruction to the Metal runtime to place the buffer in unified memory — accessible to both the CPU and the GPU at the same physical address.

What this means in practice:

When the USD parser reads a `.usda` file and produces a `Vec<vQbitPrimitive>`, those structs live in CPU-accessible memory. When `upload_geometry_from_primitives()` is called, the renderer creates a new `MTLBuffer` with `StorageModeShared` and writes the vertex data into it. The GPU renders from that buffer on the very next frame without any copy, without any transfer, without any DMA. The data the CPU wrote is the data the GPU reads — because they share the same silicon and the same physical memory.

The uniform buffer that carries the MVP matrix is also `StorageModeShared`. The CPU writes a new `Mat4` into it on every frame. The vertex shader on the GPU reads that matrix on the same frame. No staging buffer. No double-buffering required for correctness. No fence waiting for a DMA transfer to complete.

This is why GaiaFTCL targets Apple Silicon exclusively. The zero-copy unified memory model is not a nice-to-have — it is a foundational architectural choice that the entire render pipeline depends on.

---

## The vQbit Data Model

Every piece of geometry in GaiaFTCL flows through a single struct: `vQbitPrimitive`.

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct vQbitPrimitive {
    pub transform: [[f32; 4]; 4],  // 4×4 transform matrix — 64 bytes
    pub vqbit_entropy: f32,        // custom_vQbit:entropy_delta in USDA — offset 64
    pub vqbit_truth: f32,          // custom_vQbit:truth_threshold in USDA — offset 68
    pub prim_id: u32,              // sequential primitive ID — offset 72
}                                  // total: 76 bytes, #[repr(C)]
```

The `#[repr(C)]` attribute is not optional. It is a guarantee — the Rust compiler is instructed to lay this struct out in memory exactly as a C compiler would, with no reordering and no padding beyond alignment. This guarantee is what makes the struct safe to hand across the FFI boundary to Swift, safe to map directly into a Metal buffer, and safe to write from the USD parser and read in the renderer without any serialisation layer.

The `vQbitPrimitive` is the atomic unit of the GaiaFTCL data model. One primitive = one USD scope = one plant element. A complete plant scene is a `Vec<vQbitPrimitive>`, parsed from a `.usda` file, uploaded as a `MTLBuffer`, and rendered as indexed triangles.

### vqbit_entropy and vqbit_truth

These two `f32` fields are the primary telemetry channels that the vQbit model exposes through the renderer. They are read from `.usda` file attributes:

- `custom_vQbit:entropy_delta` → `vqbit_entropy` → **red channel** of the rendered vertex colour
- `custom_vQbit:truth_threshold` → `vqbit_truth` → **green channel** of the rendered vertex colour

The blue channel is fixed at 0.5. Alpha is always 1.0. The renderer clamps both values to [0.0, 1.0] before writing them to `GaiaVertex.color` — but the raw values in the `vQbitPrimitive` are never altered. The clamping is display-only. The ground truth is always the primitive.

This mapping is not aesthetic. It is a direct readout of the epistemic state of the plant. Higher entropy (more disorder, more uncertainty in the plasma state) pushes the red channel up. Higher truth threshold (stronger confinement, more reliable measurement) pushes the green channel up. The rendered colour is a real-time epistemic display of what the plant is doing.

### The ABI as a Contract

The 76-byte layout of `vQbitPrimitive` is a controlled configuration item (CI-007). It is the contract between four separate systems:

1. The **USD parser** (`rust_fusion_usd_parser`) — writes the struct
2. The **Metal renderer** (`gaia-metal-renderer`) — reads the struct and maps fields to vertex colours
3. The **Swift layer** (GaiaFusion) — receives the struct through a C FFI boundary
4. The **GxP test suite** — asserts the exact byte layout on every build via five regression guard tests (RG-001 through RG-005)

If the layout changes, all four systems must be updated simultaneously, and the full PQ test suite must be re-executed. This is not a bureaucratic requirement — it is a physical necessity, because the Swift FFI reads raw memory at fixed byte offsets.

---

## How Unified Memory Carries Each Plant

When a plant is loaded, the flow through unified memory is as follows.

The USD parser opens the `.usda` file for that plant and scans it line by line, building `vQbitPrimitive` structs. Each `def Scope` block in the file becomes one primitive. The `entropy_delta` and `truth_threshold` attributes on each scope become the `vqbit_entropy` and `vqbit_truth` fields on the corresponding primitive. The parser stores these structs in a `Vec<vQbitPrimitive>` — a contiguous block of memory on the CPU heap, 76 bytes per element.

`upload_geometry_from_primitives()` then iterates over that `Vec` and constructs a `Vec<GaiaVertex>` and a `Vec<u16>` (index buffer). The translation from primitive to vertex extracts the translation component of the transform matrix as the vertex position, and maps `vqbit_entropy` and `vqbit_truth` to the RGBA colour channels.

The Metal device then allocates two new `MTLBuffer` objects with `StorageModeShared` — one for vertices, one for indices — and copies the data into them with `newBufferWithBytes_length_options`. From this point, the CPU's job is done. The data is in unified memory. The GPU can see it immediately.

On every frame, `render_frame()` writes a new MVP matrix (model-view-projection, computed from the current frame count, aspect ratio, and plant rotation angle) into the uniform buffer — also `StorageModeShared`. The vertex shader on the GPU reads this matrix in `buffer(1)`. The vertex positions from the vertex buffer come in on `buffer(0)`. The GPU multiplies each vertex position by the MVP matrix, outputs the colour directly, and the fragment shader passes the interpolated colour through to the pixel.

No copy. No transfer. No wait. The CPU writes, the GPU reads, from the same physical addresses in the same physical DRAM.

---

## The Metal Render Pipeline

The renderer is built on `objc2-metal 0.3` — direct Rust bindings to the Objective-C Metal API. There is no intermediate graphics abstraction layer. No wgpu. No Vulkan translation layer. No OpenGL compatibility path. The Rust code calls Metal directly, in the same way Swift or Objective-C would.

The window surface is a `CAMetalLayer` attached to an AppKit `NSView`. On each frame, `nextDrawable()` is called on the layer to get the current framebuffer texture. A `MTLRenderPassDescriptor` is configured with a clear colour of near-black (0.02, 0.02, 0.05, 1.0) and the drawable texture as the colour attachment. A `MTLCommandBuffer` is obtained from the command queue, a `MTLRenderCommandEncoder` is created from the pass descriptor, the pipeline state is set, the vertex and uniform buffers are bound, the indexed draw call is issued, and the encoder is ended. The command buffer presents the drawable and is committed.

From commit to pixel, the GPU handles everything. The CPU returns to the event loop immediately and requests the next frame via `window.request_redraw()`. The render loop is continuous — `ControlFlow::Poll` — which means frames are produced as fast as the GPU can consume them.

### The GaiaVertex Structure

Every vertex that goes to the GPU is a `GaiaVertex`:

```rust
#[repr(C)]
pub struct GaiaVertex {
    pub position: [f32; 3],  // xyz — 12 bytes — attribute(0) — Float3
    pub color:    [f32; 4],  // rgba — 16 bytes — attribute(1) — Float4
}                            // total: 28 bytes — stride locked by RG-001
```

The `MTLVertexDescriptor` in `MetalRenderer::new()` is configured to match this layout byte-for-byte. `attribute(0)` is `Float3` at offset 0. `attribute(1)` is `Float4` at offset 12. The stride is 28. This configuration is locked by regression test RG-001 — any change to `GaiaVertex` that alters the stride will fail the test and block the build.

### The Uniform Buffer

One uniform buffer carries the MVP matrix to the vertex shader:

```rust
#[repr(C)]
pub struct Uniforms {
    pub mvp: [[f32; 4]; 4],  // float4x4 — 64 bytes
}
```

On every frame, `render_frame()` computes a new MVP matrix from the current `frame` counter (for rotation), the viewport aspect ratio, and fixed camera parameters (eye at (0, 1.5, 4), looking at origin, up = Y). The matrix is written directly into the uniform buffer's `StorageModeShared` memory via `std::ptr::write`. The GPU reads it in the same frame from `buffer(1)`.

---

## MSL Shaders — One Pipeline Per Plant Kind

The Metal Shading Language shaders are embedded in `shaders.rs` as a `&'static str`. They are compiled by the Metal driver at application startup, via `newLibraryWithSource_options_error`, into a `MTLLibrary`. Two functions — `vertex_main` and `fragment_main` — are extracted from the library and assembled into a `MTLRenderPipelineState`.

This compilation happens **once** — in `MetalRenderer::new()` — before the first frame is drawn. The compiled pipeline state is stored for the lifetime of the renderer. There is no runtime shader compilation, no shader permutation system, no on-demand compilation. The pipeline is ready.

The current shader is the foundation for per-plant-kind pipelines. Each plant kind has distinct physical behaviour, distinct wireframe topology, and distinct telemetry operating windows. The architecture provides one `MTLRenderPipelineState` per plant kind, compiled at startup from its dedicated MSL source. When a plant is loaded, the renderer switches to that plant's pipeline state. The vertex and fragment functions for each plant can express the specific colour logic, geometry transformation, or visual encoding that is physically meaningful for that confinement approach.

The vertex shader:

```metal
vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.color    = in.color;
    return out;
}
```

The fragment shader:

```metal
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
```

The vertex shader multiplies each position by the MVP matrix and passes the colour through unchanged. The fragment shader outputs the interpolated colour directly. The colour that the USD parser encoded from `vqbit_entropy` and `vqbit_truth` is what the user sees — a real-time visual readout of the plant's epistemic state.

---

## The Nine Plant Kinds — Full Technical Detail

Each of the nine plant kinds is a complete physical system with its own confinement approach, wireframe topology, telemetry operating window, and epistemic classification. The following sections document each kind as a first-class system — not as a list item, but as a plant that has real physics, real geometry, and real requirements.

---

### 1. Tokamak

The tokamak is the most mature and most studied magnetic confinement concept. It confines plasma in a donut-shaped (toroidal) volume using two sets of magnetic fields: a toroidal field produced by external D-shaped coils that wrap around the vessel (TF coils), and a poloidal field produced by a large transformer in the centre (the central solenoid) that drives a current through the plasma itself. The combination of these two fields creates helical field lines that hold the plasma in stable orbits inside the toroidal vessel.

The key physical quantity that distinguishes a tokamak from other confinement approaches is the plasma current, I_p. The plasma current is both a confinement mechanism and a diagnostic — if I_p falls below the operational minimum, confinement degrades and the plasma cools. If I_p rises above the maximum, the plasma can disrupt violently, dumping all its energy into the vessel wall in milliseconds.

**Wireframe topology:** Nested torus for the plasma vessel, a stack of circular PF coil rings positioned above and below the midplane for vertical field control, and D-shaped TF coil loops surrounding the torus. The minimum geometry for a physically meaningful representation is 48 vertices and 96 indices.

**USDA scope name:** `Tokamak`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.50 | 0.85 | 2.00 | MA | M | NSTX-U shot database |
| B_T | 0.40 | 0.52 | 1.00 | T | M | NSTX-U shot database |
| n_e | 1×10¹⁹ | 3.5×10¹⁹ | 1×10²⁰ | m⁻³ | M | Thomson scattering |

**How unified memory carries the tokamak:** The tokamak plant is the largest geometry of the nine kinds. Its nested torus and PF coil stack produce the highest vertex count. The `StorageModeShared` vertex buffer holds all 48+ vertices in unified memory, accessible to the GPU without a copy. When the plant swaps from tokamak to another kind, the old vertex buffer is released and a new one allocated — this is a two-pointer swap in unified memory, not a DMA transfer.

**How vQbit encodes the tokamak:** `vqbit_entropy` represents the uncertainty in the plasma current measurement — higher entropy means the current profile is less well-determined, which pushes the red channel up and signals that the confinement geometry is less certain. `vqbit_truth` represents the confidence in the confinement threshold — when B_T and I_p are both well inside their operating windows, truth is high and the green channel is bright. A fully confined, well-measured tokamak plasma renders with high green and moderate red — a warm greenish glow that immediately communicates stable confinement to the operator.

---

### 2. Stellarator

The stellarator is the tokamak's older and more geometrically complex cousin. Where the tokamak drives a current through the plasma to create part of its confinement field, the stellarator produces all of its confinement field from external coils alone — no plasma current required. This makes it inherently steady-state: there is no pulsed transformer cycle, no disruption risk from plasma current quench, and no need to continuously re-ignite the plasma.

The price of this advantage is geometric complexity. The external coils of a stellarator must be shaped into precise three-dimensional curves that produce the correct rotational transform of field lines as they wind around the torus. The Wendelstein 7-X device in Greifswald, Germany — the world's largest operational stellarator — has 70 superconducting coils arranged in five-fold symmetry, each one a unique three-dimensional shape machined to millimetre precision.

**Wireframe topology:** A twisted toroidal vessel following the five-fold helical symmetry of the magnetic field, with modular coil windings that follow the prescribed 3D curves. Minimum 48 vertices, 96 indices — comparable to the tokamak in complexity, but with fundamentally different geometry.

**USDA scope name:** `Stellarator`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.00 | 0.00 | 0.05 | MA | T | W7-X design studies |
| B_T | 1.50 | 2.50 | 3.50 | T | M | W7-X operational data |
| n_e | 5×10¹⁸ | 2.0×10¹⁹ | 5×10¹⁹ | m⁻³ | T | W7-X Thomson scattering |

**Critical constraint:** I_p > 0.05 MA is a configuration fault indicator for a stellarator. If plasma current exceeds this threshold, the device is no longer operating as a stellarator — the plasma current is doing confinement work that should be done by the coils. The system detects this as an invariant violation and enters CURE state.

**How unified memory carries the stellarator:** The stellarator's helical coil geometry requires higher vertex count per coil than the tokamak's circular TF coils, but the overall topology is similar in memory footprint. The `StorageModeShared` buffer holds the complete twisted vessel and coil geometry, ready for the GPU on each frame.

**How vQbit encodes the stellarator:** Because the stellarator has no plasma current, `vqbit_entropy` for a stellarator encodes the uncertainty in the field-line rotational transform — a measure of how well the coil geometry is maintaining the designed helical field structure. `vqbit_truth` encodes the confidence in the density measurement. A well-operating stellarator has near-zero red (low entropy, because there's no volatile plasma current to be uncertain about) and high green — a clean, cold-looking blue-green that communicates the inherent stability of external-coil-only confinement.

---

### 3. Spherical Tokamak

The spherical tokamak takes the tokamak concept and compresses the aspect ratio to its physical limit. A conventional tokamak has a large hole in the middle of the torus — the plasma is a wide ring around a wide bore. A spherical tokamak makes that hole as small as physically possible, constrained only by the space required for the central solenoid. The result is a plasma that looks like a sphere with a thin rod through its centre rather than a ring doughnut.

This low aspect ratio unlocks a significant advantage: the spherical tokamak can achieve the same plasma pressure for a much lower toroidal field than a conventional tokamak. Lower B_T means less superconducting coil material, less cost, and a more compact machine. The National Spherical Torus Experiment Upgrade (NSTX-U) at Princeton and the Mega Ampere Spherical Tokamak (MAST-U) at Culham are the leading experimental devices in this class.

**Wireframe topology:** A cored sphere representing the tightly compressed plasma, a dense central solenoid stack along the axis, and asymmetric TF coils wrapping the sphere at high coverage angle. Minimum 32 vertices, 64 indices.

**USDA scope name:** `SphericalTokamak`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.80 | 1.20 | 2.50 | MA | M | NSTX-U / MAST-U |
| B_T | 0.20 | 0.30 | 0.60 | T | M | NSTX-U design |
| n_e | 2×10¹⁹ | 5.0×10¹⁹ | 2×10²⁰ | m⁻³ | M | Thomson scattering |

**How unified memory carries the spherical tokamak:** The spherical tokamak has fewer vertices than the conventional tokamak (the geometry is simpler — a sphere rather than a torus) but higher I_p density per vertex. The `StorageModeShared` buffer allocation is smaller, which means the plant swap from conventional tokamak to spherical tokamak deallocates a larger buffer and allocates a smaller one. Metal handles this instantly — buffer allocation in unified memory is a heap operation, not a DMA setup.

**How vQbit encodes the spherical tokamak:** `vqbit_entropy` encodes the uncertainty in the plasma current profile — spherical tokamaks run at higher I_p than conventional tokamaks for their size, so current profile uncertainty is a more significant epistemic concern. `vqbit_truth` encodes confidence in the low-field confinement — because B_T is lower than in a conventional tokamak, the truth threshold tests whether the reduced field is still providing adequate confinement.

---

### 4. Field-Reversed Configuration (FRC)

The Field-Reversed Configuration is the most topologically unusual of the nine plant kinds. Every other magnetic confinement concept in this catalogue uses a toroidal magnetic field component — coils that wrap around the plasma to create field lines that circulate in the toroidal direction. The FRC has no toroidal field at all.

Instead, the FRC confines plasma in a cylinder using only poloidal fields — fields that loop the short way around the plasma cross-section rather than the long way around the torus. The plasma is a compact, self-contained bubble inside a linear cylindrical vessel. Formation coils at each end of the cylinder create and compress the plasma, and confinement rings along the cylinder maintain the field structure.

The absence of a toroidal field is what makes the FRC so interesting: it allows a very compact, high-density plasma that can in principle be moved and translated along the cylinder axis, making it a candidate for magnetized target fusion approaches where the plasma is compressed by an impacting liner.

**Wireframe topology:** A straight cylinder for the confinement vessel, circular formation coil sets at each end, and a series of field-shaping confinement rings along the barrel. Minimum 24 vertices, 48 indices.

**USDA scope name:** `FRC`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.01 | 0.10 | 0.50 | MA | T | FRC experimental literature |
| B_T | 0.00 | 0.00 | 0.10 | T | T | FRC design constraint |
| n_e | 1×10²⁰ | 1.0×10²¹ | 1×10²² | m⁻³ | I | Liner compression models |

**How unified memory carries the FRC:** The FRC has the simplest geometry of the toroidal-adjacent concepts — a cylinder with end coils. Its 24-vertex minimum means the smallest `StorageModeShared` vertex buffer of the five magnetically confined plant kinds. When the FRC plant is active, the GPU is rendering fewer triangles per frame than almost any other plant kind, which means the render loop can potentially accommodate additional per-frame CPU computation.

**How vQbit encodes the FRC:** Because B_T ≈ 0 by definition, the toroidal field channel contributes essentially nothing to the colour. `vqbit_entropy` encodes the uncertainty in the plasma current profile — which drives the self-reversal of the field that defines the FRC configuration. `vqbit_truth` encodes whether the field-reversed state is being maintained — when the plasma is in the correct FRC topology, truth is high. If the plasma loses its reversed-field configuration and collapses back to a simple mirror, truth drops, the green channel dims, and the operator is alerted.

---

### 5. Mirror

The magnetic mirror is the simplest open magnetic confinement concept. Two coils separated along an axis produce a region of low magnetic field between them and high magnetic field at each end. A charged particle travelling along the axis slows down as it enters the high-field region — the magnetic mirror force — and is reflected back toward the centre. Particles with sufficient transverse velocity are trapped; particles moving too directly along the axis escape through the ends.

The mirror is historically one of the earliest fusion confinement concepts studied, and it suffered from a fundamental loss mechanism — particles that scattered into the loss cone near the axis would escape. Modern mirror concepts like the gas-dynamic trap and the tandem mirror use additional physics to plug the ends and reduce losses.

**Wireframe topology:** A sparse set of circular rings in the central confinement region where the field is low, and dense coil groups at each end where the field is high and the mirror effect occurs. Minimum 24 vertices, 48 indices.

**USDA scope name:** `Mirror`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.00 | 0.05 | 0.20 | MA | T | Gas-dynamic trap data |
| B_T | 0.50 | 1.00 | 3.00 | T | M | Mirror coil design |
| n_e | 1×10¹⁸ | 5.0×10¹⁸ | 1×10¹⁹ | m⁻³ | I | Extrapolated from GDT |

**How unified memory carries the mirror:** The mirror's geometry — sparse central rings and dense end coils — means the vertex data is asymmetrically distributed along the axis. The `StorageModeShared` vertex buffer holds a geometry that is physically meaningful: fewer vertices in the middle (low field, simple ring structure) and more at the ends (complex coil windings producing the mirror ratio). When the GPU renders this geometry, the visual asymmetry between the two ends is physically accurate.

**How vQbit encodes the mirror:** `vqbit_entropy` encodes the uncertainty in the particle confinement time — the mirror's primary physical challenge is that high-entropy (scattered, loss-cone-adjacent) particles escape. High `vqbit_entropy` means more particles are near the loss cone, which is physically bad and renders as a red warning. `vqbit_truth` encodes confidence in the mirror ratio — the ratio of the peak field at the end to the minimum field at the centre. When the mirror ratio is well inside its design window, truth is high.

---

### 6. Spheromak

The spheromak is the most self-reliant of the nine plant kinds. It contains both a toroidal and a poloidal magnetic field, just like a tokamak, but it generates these fields entirely from currents flowing in the plasma itself — no external coils thread through the plasma volume. The plasma organises itself into a stable configuration called a Taylor state: a minimum-energy state consistent with the global helicity constraints of the system.

Formation is typically achieved via a coaxial gun: a pair of coaxial electrodes injects a plasma jet with helicity (a measure of how twisted the field lines are), and this helicity is absorbed by the growing spheromak until it reaches its equilibrium Taylor state and settles into the spherical flux conserver. Once formed, the spheromak is maintained by the helicity injection from the gun.

**Wireframe topology:** A spherical flux conserver vessel that defines the boundary of the Taylor state, and a coaxial injector entering from one pole. Minimum 32 vertices, 64 indices.

**USDA scope name:** `Spheromak`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.10 | 0.30 | 0.80 | MA | T | HIT-SI / SSX data |
| B_T | 0.05 | 0.10 | 0.30 | T | I | Taylor state scaling |
| n_e | 1×10¹⁹ | 1.0×10²⁰ | 1×10²¹ | m⁻³ | I | Compact torus measurements |

**How unified memory carries the spheromak:** The spheromak geometry is simpler than the tokamak but more symmetric than the FRC. The `StorageModeShared` vertex buffer holds the spherical flux conserver shell as a triangulated sphere and the coaxial injector as a cylinder aligned with the polar axis. The plasma's Taylor state self-organisation means the field geometry is fully determined by the boundary conditions — the wireframe is a faithful representation of those boundaries.

**How vQbit encodes the spheromak:** `vqbit_entropy` encodes the helicity dissipation rate — how quickly the plasma is losing its self-organised magnetic structure to resistive decay. A high entropy spheromak is losing its Taylor state and approaching an unconfined condition. `vqbit_truth` encodes confidence in the self-organisation — when the plasma has settled into a stable Taylor state with the correct helicity, truth is high. The colour gradient for a healthy spheromak is a moderate green with controlled red — the system is always fighting entropy, but winning.

---

### 7. Z-Pinch

The Z-pinch is the most direct application of the force between parallel currents. Pass a very large current axially through a column of plasma — in the Z direction — and the current produces an azimuthal magnetic field around itself. That azimuthal field acts on the current, producing an inward J×B force that compresses the plasma column radially. This is the pinch. No external magnets required. No superconducting coils. Just current.

The Z-pinch requires extreme current — measured in megaamperes rather than the hundreds of kiloamperes typical of other confinement approaches. The Shiva Star and Z-Machine at Sandia National Laboratories are the principal experimental platforms for pulsed Z-pinch research. Modern variants include sheared-flow-stabilised Z-pinches (like the device being developed by Zap Energy) that use velocity shear to suppress the kink instabilities that historically destroyed classical Z-pinches.

**Wireframe topology:** A cylinder representing the plasma column between two electrode plates at each end, with spoke structures connecting the electrodes to the outer return current conductors. Minimum 16 vertices, 32 indices — the smallest geometry of all nine plant kinds, befitting the machine's geometric simplicity.

**USDA scope name:** `ZPinch`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.50 | 2.00 | 20.0 | MA | M | Z-machine shot data |
| B_T | 0.00 | 0.00 | 0.05 | T | T | Z-pinch definition |
| n_e | 1×10²¹ | 1.0×10²² | 1×10²³ | m⁻³ | I | Pinch compression scaling |

**How unified memory carries the Z-pinch:** The Z-pinch's 16-vertex minimum means it has the smallest memory footprint of all nine plant kinds. Its `StorageModeShared` buffer allocation and deallocation on plant swap is essentially instantaneous. Despite the geometric simplicity, the physics are extreme — the Z-pinch operates at I_p values an order of magnitude above the tokamak. The GPU renders this simple geometry at full frame rate with almost no vertex processing overhead.

**How vQbit encodes the Z-pinch:** `vqbit_entropy` encodes the instability amplitude — the Z-pinch is fundamentally susceptible to kink (m=1) and sausage (m=0) instabilities that grow from thermal fluctuations. High entropy means the instabilities are growing, which is physically dangerous. `vqbit_truth` encodes confidence in the current uniformity — a Z-pinch only produces the correct inward force when the current density is uniform across the plasma cross-section. When the current is well-distributed and I_p is high and stable, truth is maximum.

---

### 8. Magneto-Inertial Fusion (MIF)

Magneto-Inertial Fusion sits at the intersection of magnetic and inertial confinement. Rather than sustaining a confined plasma indefinitely like a tokamak, and rather than igniting a target purely by shock compression like ICF, MIF creates a magnetised plasma and then compresses it with an impacting liner, driver, or converging plasma jets. The magnetic field trapped inside the plasma slows the thermal conduction losses during compression, allowing ignition at intermediate densities between classical magnetic and inertial confinement.

The approach implemented in GaiaFTCL uses radial plasma guns arranged at Fibonacci-lattice sites on an icosphere — a geodesically uniform spherical arrangement that produces isotropic convergence of the plasma jets onto the magnetised target at the centre. The Fibonacci placement is a controlled configuration item: the gun positions are mathematically determined by the golden ratio spiral on a sphere, and any deviation from this placement breaks the convergence symmetry.

**Wireframe topology:** An icosphere representing the target chamber, with radial plasma gun structures emanating inward from Fibonacci lattice sites on the icosphere surface. Minimum 40 vertices, 80 indices.

**USDA scope name:** `MIF`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.10 | 0.50 | 5.00 | MA | T | MIF experimental literature |
| B_T | 0.10 | 0.50 | 2.00 | T | I | Liner compression scaling |
| n_e | 1×10²² | 1.0×10²³ | 1×10²⁵ | m⁻³ | A | Target design parameters |

**How unified memory carries MIF:** The MIF icosphere geometry is moderately complex — the Fibonacci-distributed gun positions add vertices at non-uniform angular spacing across the sphere, which means the index buffer is non-trivially structured. The `StorageModeShared` allocation holds this complete Fibonacci-indexed icosphere. Because the gun positions are fixed by the Fibonacci construction, the geometry is static between shots — the same vertex and index buffer can be reused across many frames.

**How vQbit encodes MIF:** `vqbit_entropy` encodes the convergence symmetry uncertainty — if the plasma jets are not arriving at the target simultaneously from all Fibonacci sites, the compression is asymmetric and the target is not heated uniformly. High entropy in MIF means the jets are out of sync. `vqbit_truth` encodes the magnetic field compression efficiency — whether the magnetic field seeded in the target is being compressed as designed by the converging plasma. When all jets converge simultaneously and the field compresses correctly, truth is high.

---

### 9. Inertial Confinement Fusion (ICF)

Inertial Confinement Fusion uses laser energy, not magnetic fields, to compress and ignite a fusion target. In the most common indirect-drive approach, laser beams enter a cylindrical gold hohlraum from each end, are absorbed by the hohlraum wall, and re-emitted as X-rays. These X-rays ablate the outer surface of a spherical fuel capsule, launching a spherically symmetric inward shock that compresses the fusion fuel to the extreme densities required for ignition.

The National Ignition Facility at LLNL achieved fusion ignition in December 2022 — the first time a fusion reaction produced more energy than the laser energy delivered to the target. This was a landmark achievement for ICF and for fusion science overall.

GaiaFTCL represents ICF as the limiting case of the telemetry space: I_p ≈ 0 (no plasma current), B_T ≈ 0 (no magnetic field), and n_e at ignition is 10³¹ m⁻³ — twelve orders of magnitude above the tokamak operating density. This extreme density requires special handling in the renderer to avoid float overflow when normalising to the [0.0, 1.0] colour space.

**Wireframe topology:** A geodesic sphere representing the hohlraum and ablator shell, a cylinder at the centre representing the cryogenic fuel layer and hot spot, and inward-pointing beam lines entering from apertures distributed across the sphere surface. Minimum 40 vertices, 80 indices.

**USDA scope name:** `Inertial`

**Telemetry operating window:**

| Channel | Min | Baseline | Max | Unit | Epistemic | Source |
| --- | --- | --- | --- | --- | --- | --- |
| I_p | 0.00 | 0.00 | 0.01 | MA | A | ICF physics — no plasma current |
| B_T | 0.00 | 0.00 | 0.01 | T | A | ICF physics — no magnetic field |
| n_e | 1×10³⁰ | 1.0×10³¹ | 1×10³² | m⁻³ | A | NIF hohlraum models |

**How unified memory carries ICF:** The ICF geodesic shell geometry is similar in vertex count to MIF, but the physics are entirely different. The `StorageModeShared` vertex buffer holds the spherical ablator shell, hohlraum, and beam line wireframe. The critical renderer requirement for ICF is float normalisation: n_e at 10³¹ m⁻³ cannot be divided by a naive normalisation factor without producing Inf in f32 arithmetic. The renderer must use a logarithmic normalisation for ICF's n_e channel — the colour value is `log10(n_e) / 32.0` rather than a linear map. This is verified by PQ-PHY-006.

**How vQbit encodes ICF:** Because I_p ≈ 0 and B_T ≈ 0, the red and green channels of an ICF rendering carry almost no information from those channels. The meaningful signal is entirely in the n_e channel — the electron density tracks the implosion trajectory. `vqbit_entropy` encodes the implosion symmetry uncertainty: how far from perfectly spherical the implosion is. Any asymmetry grows during compression and degrades target performance. `vqbit_truth` encodes confidence in the ignition threshold — whether the hot-spot temperature and density are on track to achieve self-sustaining burn. An ICF target approaching ignition renders with near-zero red (low field, low symmetry entropy), near-zero green (no plasma current), and a deep blue baseline from the dense plasma.

---

## The USD Scene Format

Every plant kind is authored as a `.usda` (Universal Scene Description ASCII) file. GaiaFTCL does not use the full OpenUSD library — it has zero dependency on OpenUSD. The parser is a purpose-built Rust implementation in `rust_fusion_usd_parser` that reads exactly the subset of USDA syntax required by GaiaFTCL.

The parser recognises two constructs:

**`def Scope` blocks** — each one becomes one `vQbitPrimitive`. The scope name (e.g. `Tokamak`, `Stellarator`) identifies the plant kind.

**`custom_vQbit:` attributes** — `entropy_delta` and `truth_threshold` inside a scope are read and stored in the corresponding `vQbitPrimitive` fields.

Both multi-line and compact one-liner formats are supported:

```
# Multi-line
def Scope "Tokamak" {
    float custom_vQbit:entropy_delta   = 0.85
    float custom_vQbit:truth_threshold = 0.92
}

# Compact
def Scope "Tokamak" { float custom_vQbit:entropy_delta = 0.85; float custom_vQbit:truth_threshold = 0.92; }
```

The parser handles attribute order independence, arbitrary whitespace, malformed float values (defaults to 0.0, never panics), missing attributes (defaults to 0.0), and EOF without a closing brace. All of this is verified by the TP and TN test series in the OQ test suite.

---

## Sovereign Time — τ

GaiaFTCL uses Bitcoin block height as its canonical time axis. This is called τ (tau). Every cell in the GaiaFTCL mesh uses the same τ — the same Bitcoin block height — as its time reference. This makes cross-cell synchronisation a function of global Bitcoin consensus, not of NTP or local clocks.

τ is delivered to the renderer through a NATS message on the subject `gaiaftcl.bitcoin.heartbeat`, published approximately every 10 minutes as Bitcoin blocks are mined. GaiaFusion Swift subscribes to this subject and calls `gaia_metal_renderer_set_tau()` on the renderer via the C FFI bridge on each new block.

τ = 0 means genesis — the renderer has not yet received a heartbeat. τ > 0 means the renderer is synchronised to the Bitcoin consensus chain. Two cells are considered synchronised if their τ values differ by no more than 2 blocks (approximately 20 minutes).

The renderer stores τ in the `MetalRenderer` struct alongside the frame counter. The frame counter drives smooth animation interpolation (updated every frame). τ drives physics-dependent calculations (updated every ~10 minutes). These are separate concerns with separate update rates — the frame counter is never used as a substitute for τ.

---

## The Qualification Stack

GaiaFTCL is qualified to GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11. The qualification has three levels:

**IQ (Installation Qualification)** verifies that the hardware, operating system, toolchain, and sovereign identity are correctly installed. See [[IQ-Installation-Qualification]] for the full test requirement specification.

**OQ (Operational Qualification)** verifies that the software does what it is designed to do. 32 automated GxP tests run on every build. See [[OQ-Operational-Qualification]] for the complete test suite specification with per-plant coverage.

**PQ (Performance Qualification)** verifies that the system performs within its specified physical parameters under real operational conditions at CERN. It covers physics bounds for all nine plant kinds, the 81-swap permutation matrix, safety interlocks, and continuous render performance. See [[PQ-Performance-Qualification]] for the full protocol.

The three levels are sequential and dependent: OQ cannot begin until IQ is signed. PQ cannot begin until OQ is passing with 32/32 tests. No force-push to the repository is permitted after PQ evidence collection begins.

---

## Configuration Management

The following items are controlled — any change requires a Change Control Record (CCR) and triggers re-execution of the associated qualification phase:

| CI ID | Controlled item | Triggers |
| --- | --- | --- |
| CI-001 | Per-plant telemetry bounds | Full PQ-PHY re-execution |
| CI-002 | M/T/I/A tag assignments per plant | PQ-PHY-004 and PQ-PHY-005 re-execution |
| CI-003 | Plant swap state machine transitions and timeouts | Full PQ-CSE re-execution |
| CI-004 | Terminal state definitions (CALORIE/CURE/REFUSED) | PQ-CSE + PQ-SAF re-execution |
| CI-005 | Nine canonical plant IDs and wireframe geometry | PQ-CSE-001, PQ-CSE-002 re-execution |
| CI-006 | Telemetry channel → colour mapping | PQ-CSE-008 re-execution |
| CI-007 | vQbitPrimitive ABI (size 76 bytes, field offsets) | Full PQ re-execution |
| CI-008 | Rust toolchain version | PQ-QA-001, PQ-QA-004 re-execution |
| CI-009 | timeline_v2.json format and field names | PQ-PHY-003 + PQ-QA-009 re-execution |
| CI-010 | Target hardware platform | PQ-CSE full re-execution |
| CI-011 | Fibonacci gun placement in MIF | PQ-CSE full re-execution |
| CI-012 | ICF n_e normalisation method | PQ-PHY-006 re-execution |

---

## See Also

- [[Plant-Catalogue]] — Telemetry bounds, epistemic tags, and geometry specifications for all nine plant kinds
- [[vQbitPrimitive-ABI]] — Complete ABI specification for the 76-byte struct
- [[IQ-Installation-Qualification]] — Installation test requirements
- [[OQ-Operational-Qualification]] — Operational test suite (32 GxP tests)
- [[PQ-Performance-Qualification]] — Performance qualification protocols

---

*GaiaFTCL Mac Cell — © 2026 Richard Gillespie*
*Patents: USPTO 19/460,960 | USPTO 19/096,071*
*GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11 | CERN Research Facility*
