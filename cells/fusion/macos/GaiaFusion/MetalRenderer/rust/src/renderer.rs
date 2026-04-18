use std::mem;
use core::ptr::NonNull;
use core::ffi::c_void;

use glam::{Mat4, Vec3};
use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_foundation::{NSString, NSSize, NSURL};
use objc2_metal::{
    MTLClearColor, MTLCommandBuffer, MTLCommandQueue,
    MTLCreateSystemDefaultDevice, MTLDevice, MTLDrawable, MTLIndexType, MTLLibrary,
    MTLLoadAction, MTLPixelFormat, MTLPrimitiveType, MTLRenderCommandEncoder,
    MTLRenderPassColorAttachmentDescriptor, MTLRenderPassDescriptor,
    MTLRenderPipelineColorAttachmentDescriptor, MTLRenderPipelineDescriptor,
    MTLRenderPipelineState, MTLResourceOptions, MTLStoreAction, MTLVertexAttributeDescriptor,
    MTLVertexBufferLayoutDescriptor, MTLVertexDescriptor, MTLVertexFormat, MTLVertexStepFunction,
    MTLBuffer, MTLCommandEncoder,
};
use objc2_quartz_core::{CAMetalDrawable, CAMetalLayer};

use vqbit_usd_parser::vQbitPrimitive;
use crate::shaders::SHADER_SOURCE;

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct GaiaVertex {
    pub position: [f32; 3],
    pub color: [f32; 4],
}

impl GaiaVertex {
    pub const fn new(pos: [f32; 3], col: [f32; 4]) -> Self {
        Self { position: pos, color: col }
    }
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    pub mvp: [[f32; 4]; 4],
}

/// Plasma state for volume rendering
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct PlasmaState {
    pub density: f32,       // particles/m³
    pub temperature: f32,   // keV
    pub magnetic_field: f32, // Tesla
    pub opacity: f32,       // 0.0-1.0
}

impl Default for PlasmaState {
    fn default() -> Self {
        Self {
            density: 1.0e20,
            temperature: 15.0,
            magnetic_field: 5.5,
            opacity: 0.6,
        }
    }
}

/// Plasma particle for flow visualization
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct PlasmaParticle {
    pub position: [f32; 3],
    pub velocity: [f32; 3],
    pub color: [f32; 4],
    pub age: f32,
    pub lifetime: f32,
}

pub struct MetalRenderer {
    device: Retained<ProtocolObject<dyn MTLDevice>>,
    command_queue: Retained<ProtocolObject<dyn MTLCommandQueue>>,
    pipeline_state: Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    layer: Retained<CAMetalLayer>,
    vertex_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    index_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    uniform_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    plasma_vertex_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    index_count: usize,
    tau: u64,  // Bitcoin block height (emergent time)
    /// Last frame render time in microseconds (patent requirement: <3000 μs)
    last_frame_time_us: u64,
    /// Base wireframe color (RGBA, 0-1) - controlled by constitutional WASM checks or plasma state
    base_color: [f32; 4],
    /// Plasma state for color-mapped visualization
    plasma_state: PlasmaState,
    /// Enable plasma color visualization
    plasma_enabled: bool,
    /// Plasma particles for flow visualization
    plasma_particles: Vec<PlasmaParticle>,
    /// Plasma flow animation time
    plasma_time: f32,
}

impl MetalRenderer {
    /// Create renderer from raw CAMetalLayer pointer (from Swift FFI).
    /// Swift owns the layer and must keep it alive for the lifetime of this renderer.
    pub fn new_from_layer(layer_ptr: *mut c_void) -> Result<Self, String> {
        if layer_ptr.is_null() {
            return Err("Null layer pointer".to_string());
        }

        let device = MTLCreateSystemDefaultDevice()
            .ok_or("No Metal-capable GPU found")?;

        let command_queue = device
            .newCommandQueue()
            .ok_or("Failed to create command queue")?;

        // Borrow the CAMetalLayer from the raw pointer (Swift owns it)
        let layer = unsafe {
            let layer_ptr = layer_ptr.cast::<CAMetalLayer>();
            Retained::retain(layer_ptr).ok_or("Failed to retain CAMetalLayer")?
        };

        layer.setDevice(Some(&device));
        layer.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
        layer.setFramebufferOnly(true);

        // Load precompiled Metal shader library (required for Apple Silicon)
        // default.metallib is built by build_shaders.sh and bundled in Resources/
        let metallib_path = NSString::from_str(
            concat!(env!("CARGO_MANIFEST_DIR"), "/target/aarch64-apple-darwin/release/default.metallib")
        );
        let library = unsafe {
            let url = NSURL::fileURLWithPath(&metallib_path);
            device.newLibraryWithURL_error(&url)
        }.expect("Failed to load precompiled Metal library (default.metallib)");

        let vert_name = NSString::from_str("vertex_main");
        let frag_name = NSString::from_str("fragment_main");
        let vert_fn = unsafe { library.newFunctionWithName(&vert_name) }
            .expect("vertex_main not found");
        let frag_fn = unsafe { library.newFunctionWithName(&frag_name) }
            .expect("fragment_main not found");

        let vertex_desc = unsafe { MTLVertexDescriptor::new() };
        unsafe {
            let attrs = vertex_desc.attributes();
            let attr0: Retained<MTLVertexAttributeDescriptor> = attrs.objectAtIndexedSubscript(0);
            attr0.setFormat(MTLVertexFormat::Float3);
            attr0.setOffset(0);
            attr0.setBufferIndex(0);

            let attr1: Retained<MTLVertexAttributeDescriptor> = attrs.objectAtIndexedSubscript(1);
            attr1.setFormat(MTLVertexFormat::Float4);
            attr1.setOffset(mem::size_of::<[f32; 3]>() as usize);
            attr1.setBufferIndex(0);

            let layouts = vertex_desc.layouts();
            let layout0: Retained<MTLVertexBufferLayoutDescriptor> =
                layouts.objectAtIndexedSubscript(0);
            layout0.setStride(mem::size_of::<GaiaVertex>() as usize);
            layout0.setStepFunction(MTLVertexStepFunction::PerVertex);
            layout0.setStepRate(1);
        }

        let pipeline_desc = unsafe { MTLRenderPipelineDescriptor::new() };
        unsafe {
            pipeline_desc.setVertexFunction(Some(&vert_fn));
            pipeline_desc.setFragmentFunction(Some(&frag_fn));
            pipeline_desc.setVertexDescriptor(Some(&vertex_desc));

            let color_attachments = pipeline_desc.colorAttachments();
            let ca0: Retained<MTLRenderPipelineColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
        }

        let pipeline_state =
            unsafe { device.newRenderPipelineStateWithDescriptor_error(&pipeline_desc) }
                .expect("Failed to create render pipeline state");

        // Initialize with Tokamak geometry (default plant)
        let geom = crate::plant_geometries::build_geometry(crate::plant_geometries::PlantKind::Tokamak);
        let vertices = geom.vertices;
        let indices = geom.indices;

        let vertex_buffer = unsafe {
            device
                .newBufferWithBytes_length_options(
                    NonNull::new(vertices.as_ptr() as *mut c_void).unwrap(),
                    (vertices.len() * mem::size_of::<GaiaVertex>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create vertex buffer")
        };

        let index_buffer = unsafe {
            device
                .newBufferWithBytes_length_options(
                    NonNull::new(indices.as_ptr() as *mut c_void).unwrap(),
                    (indices.len() * mem::size_of::<u16>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create index buffer")
        };

        let uniform_buffer = unsafe {
            device
                .newBufferWithLength_options(
                    mem::size_of::<Uniforms>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create uniform buffer")
        };

        // Create plasma particle buffer (initial capacity for 5000 particles)
        let plasma_vertex_buffer = unsafe {
            device
                .newBufferWithLength_options(
                    5000 * mem::size_of::<GaiaVertex>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create plasma vertex buffer")
        };

        // Initialize plasma particles
        let plasma_particles = Self::init_plasma_particles(500);

        Ok(Self {
            device,
            command_queue,
            pipeline_state,
            layer,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            plasma_vertex_buffer,
            index_count: indices.len(),
            tau: 0,
            last_frame_time_us: 0,
            base_color: [0.0, 0.6, 1.0, 1.0], // Default: blue (PASS state)
            plasma_state: PlasmaState::default(),
            plasma_enabled: false,
            plasma_particles,
            plasma_time: 0.0,
        })
    }

    pub fn resize(&self, width: u32, height: u32) {
        unsafe {
            self.layer.setDrawableSize(NSSize {
                width: width as f64,
                height: height as f64,
            });
        }
    }

    pub fn set_tau(&mut self, block_height: u64) {
        self.tau = block_height;
    }

    pub fn get_tau(&self) -> u64 {
        self.tau
    }

    pub fn render_frame(&mut self, width: u32, height: u32) {
        let frame_start = std::time::Instant::now();
        
        // Update plasma flow animation
        self.plasma_time += 0.016; // ~60 FPS timestep
        if self.plasma_enabled {
            self.update_plasma_particles(0.016);
        }
        
        // Note: tau is updated via set_tau() from Swift NATS subscription
        // We use tau as a slower animation driver (Bitcoin blocks ~10 min)
        let aspect = width as f32 / height.max(1) as f32;
        let angle = (self.tau as f32) * 0.02;

        let projection = Mat4::perspective_rh(45.0_f32.to_radians(), aspect, 0.1, 100.0);
        // Camera positioned for optimal tokamak viewing - centered and slightly elevated
        let view = Mat4::look_at_rh(Vec3::new(0.0, 1.2, 3.8), Vec3::new(0.0, 0.0, 0.0), Vec3::Y);
        let model = Mat4::from_rotation_y(angle) * Mat4::from_rotation_x(angle * 0.7);
        let mvp = projection * view * model;

        let uniforms = Uniforms { mvp: mvp.to_cols_array_2d() };
        unsafe {
            let contents = self.uniform_buffer.contents();
            let ptr = contents.as_ptr() as *mut Uniforms;
            std::ptr::write(ptr, uniforms);
        }

        let drawable = unsafe { self.layer.nextDrawable() };
        let drawable = match drawable {
            Some(d) => d,
            None => return,
        };

        let pass_desc = unsafe { MTLRenderPassDescriptor::new() };
        unsafe {
            let color_attachments = pass_desc.colorAttachments();
            let ca0: Retained<MTLRenderPassColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setTexture(Some(&drawable.texture()));
            ca0.setLoadAction(MTLLoadAction::Clear);
            ca0.setStoreAction(MTLStoreAction::Store);
            ca0.setClearColor(MTLClearColor {
                red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0,
            });
        }

        let cmd_buffer = self.command_queue
            .commandBuffer()
            .expect("Failed to create command buffer");

        let encoder = unsafe {
            cmd_buffer
                .renderCommandEncoderWithDescriptor(&pass_desc)
                .expect("Failed to create render encoder")
        };

        unsafe {
            encoder.setRenderPipelineState(&self.pipeline_state);
            encoder.setVertexBuffer_offset_atIndex(Some(&self.vertex_buffer), 0, 0);
            encoder.setVertexBuffer_offset_atIndex(Some(&self.uniform_buffer), 0, 1);
            
            // Draw wireframe
            encoder.drawIndexedPrimitives_indexCount_indexType_indexBuffer_indexBufferOffset(
                MTLPrimitiveType::Line,
                self.index_count,
                MTLIndexType::UInt16,
                &self.index_buffer,
                0,
            );
            
            // Draw plasma flow particles if enabled
            if self.plasma_enabled && !self.plasma_particles.is_empty() {
                self.render_plasma_particles(&encoder, &mvp);
            }
            
            encoder.endEncoding();
        }

        unsafe {
            cmd_buffer.presentDrawable(drawable.as_ref() as &ProtocolObject<dyn MTLDrawable>);
        }
        cmd_buffer.commit();
        
        // Patent requirement: frame time must be <3ms (3000 μs)
        let frame_time = frame_start.elapsed();
        self.last_frame_time_us = frame_time.as_micros() as u64;
    }
    
    /// Get last frame render time in microseconds
    /// Patent requirement: must be <3000 μs with precompiled Metal shaders
    pub fn get_frame_time_us(&self) -> u64 {
        self.last_frame_time_us
    }

    /// Switch to a different plant kind geometry
    /// plant_kind_id: 0=Tokamak, 1=Stellarator, 2=FRC, 3=Spheromak, 4=Mirror,
    ///                5=Inertial, 6=SphericalTokamak, 7=ZPinch, 8=MIF
    /// Returns: true on success, false on invalid plant_kind_id
    pub fn switch_plant(&mut self, plant_kind_id: u32) -> bool {
        use crate::plant_geometries::{PlantKind, build_geometry};
        
        let plant_kind = match PlantKind::from_u32(plant_kind_id) {
            Some(kind) => kind,
            None => return false, // Invalid plant_kind_id
        };
        
        let geom = build_geometry(plant_kind);
        self.upload_geometry(&geom.vertices, &geom.indices);
        true
    }
    
    /// Set base wireframe color (driven by WASM constitutional checks)
    /// color: [r, g, b, a] where each component is 0.0-1.0
    /// - [0.0, 0.6, 1.0, 1.0] = Blue (PASS / normal state)
    /// - [1.0, 0.7, 0.0, 1.0] = Yellow (WARNING / bounds violation)
    /// - [1.0, 0.1, 0.1, 1.0] = Red (CRITICAL / constitutional violation)
    pub fn set_base_color(&mut self, color: [f32; 4]) {
        self.base_color = color;
        // Rebuild current geometry with new color
        self.apply_base_color_to_vertices();
    }
    
    /// Enable plasma visualization (RUNNING/CONSTITUTIONAL_ALARM states only per Phase 7)
    pub fn enable_plasma(&mut self) {
        self.plasma_enabled = true;
    }
    
    /// Disable plasma visualization and clear particle buffer (Phase 7 requirement)
    pub fn disable_plasma(&mut self) {
        self.plasma_enabled = false;
        // Clear particle buffer by resetting all particles
        for particle in &mut self.plasma_particles {
            particle.age = particle.lifetime; // Mark as expired
        }
    }
    
    /// Set plasma state for visualization
    /// Maps temperature to color (cooler = blue, hotter = white/yellow)
    /// density and magnetic_field affect intensity
    pub fn set_plasma_state(&mut self, density: f32, temperature: f32, magnetic_field: f32, opacity: f32) {
        self.plasma_state = PlasmaState {
            density,
            temperature,
            magnetic_field,
            opacity: opacity.clamp(0.6, 0.8),  // Phase 7: 60-80% opacity
        };
        self.plasma_enabled = true;
        
        // Map temperature (keV) to color
        // 1-10 keV: blue-cyan (cool plasma)
        // 10-20 keV: cyan-green-yellow (medium)
        // 20-50 keV: yellow-white (hot plasma)
        let temp_normalized = (temperature.clamp(1.0, 50.0) - 1.0) / 49.0;
        
        let r = temp_normalized.powf(0.5);
        let g = (temp_normalized * 2.0).clamp(0.0, 1.0);
        let b = 1.0 - temp_normalized * 0.7;
        
        // Intensity based on density and magnetic field
        let intensity = ((density / 1e20) * (magnetic_field / 5.0)).clamp(0.5, 1.0);
        
        self.base_color = [
            r * intensity,
            g * intensity,
            b * intensity,
            opacity,
        ];
        
        // Apply new color to vertices
        self.apply_base_color_to_vertices();
    }
    
    /// Initialize plasma particles in toroidal flow pattern
    fn init_plasma_particles(count: usize) -> Vec<PlasmaParticle> {
        let mut particles = Vec::with_capacity(count);
        use std::f32::consts::PI;
        
        for i in 0..count {
            let t = i as f32 / count as f32;
            
            // Toroidal coordinates
            let major_angle = t * 2.0 * PI;
            let minor_angle = (t * 17.0) * 2.0 * PI;
            
            let major_r = 1.0;
            let minor_r = 0.35;
            
            let x = (major_r + minor_r * minor_angle.cos()) * major_angle.cos();
            let y = minor_r * minor_angle.sin();
            let z = (major_r + minor_r * minor_angle.cos()) * major_angle.sin();
            
            particles.push(PlasmaParticle {
                position: [x, y, z],
                velocity: [
                    -major_angle.sin() * 0.3,
                    minor_angle.cos() * 0.15,
                    major_angle.cos() * 0.3,
                ],
                color: [0.5, 0.8, 1.0, 0.8],
                age: 0.0,
                lifetime: 10.0 + (t * 5.0),
            });
        }
        
        particles
    }
    
    /// Update plasma particle positions
    fn update_plasma_particles(&mut self, dt: f32) {
        let temp_factor = (self.plasma_state.temperature / 50.0).min(1.0);
        let field_factor = (self.plasma_state.magnetic_field / 10.0).min(1.0);
        let particle_count = self.plasma_particles.len();
        
        for (i, particle) in self.plasma_particles.iter_mut().enumerate() {
            particle.age += dt;
            
            if particle.age > particle.lifetime {
                particle.age = 0.0;
                let t = (i as f32) / (particle_count as f32);
                use std::f32::consts::PI;
                let major_angle = t * 2.0 * PI;
                let minor_angle = (t * 17.0) * 2.0 * PI;
                particle.position = [
                    (1.0 + 0.35 * minor_angle.cos()) * major_angle.cos(),
                    0.35 * minor_angle.sin(),
                    (1.0 + 0.35 * minor_angle.cos()) * major_angle.sin(),
                ];
            }
            
            let speed = 0.5 * temp_factor * field_factor;
            particle.position[0] += particle.velocity[0] * speed * dt;
            particle.position[1] += particle.velocity[1] * speed * dt;
            particle.position[2] += particle.velocity[2] * speed * dt;
            
            // Temperature-driven color gradient: blue (cool) → cyan → yellow → white (hot)
            // Normalized temperature: 0.0 (1 keV) → 1.0 (50 keV)
            let temp_normalized = (self.plasma_state.temperature.clamp(1.0, 50.0) - 1.0) / 49.0;
            
            // Enhanced color gradient for better visibility
            let (r, g, b) = if temp_normalized < 0.33 {
                // Cool plasma: blue → cyan (1-16 keV)
                let t = temp_normalized / 0.33;
                (0.0, t * 0.9, 1.0)  // Blue to cyan
            } else if temp_normalized < 0.66 {
                // Medium plasma: cyan → yellow (16-33 keV)
                let t = (temp_normalized - 0.33) / 0.33;
                (t * 1.0, 0.9 + t * 0.1, 1.0 - t * 0.5)  // Cyan to yellow
            } else {
                // Hot plasma: yellow → white (33-50 keV)
                let t = (temp_normalized - 0.66) / 0.34;
                (1.0, 1.0, 0.5 + t * 0.5)  // Yellow to white
            };
            
            let fade = 1.0 - (particle.age / particle.lifetime).clamp(0.0, 1.0);
            particle.color = [r * fade, g * fade, b * fade, self.plasma_state.opacity * fade * 0.7];
        }
    }
    
    /// Render plasma particles
    fn render_plasma_particles(&self, encoder: &Retained<ProtocolObject<dyn MTLRenderCommandEncoder>>, _mvp: &Mat4) {
        let vertices: Vec<GaiaVertex> = self.plasma_particles.iter()
            .filter(|p| p.age < p.lifetime)
            .map(|p| GaiaVertex::new(p.position, p.color))
            .collect();
        
        if vertices.is_empty() {
            return;
        }
        
        unsafe {
            let contents = self.plasma_vertex_buffer.contents();
            let byte_count = vertices.len() * std::mem::size_of::<GaiaVertex>();
            std::ptr::copy_nonoverlapping(
                vertices.as_ptr() as *const u8,
                contents.as_ptr() as *mut u8,
                byte_count
            );
            
            encoder.setVertexBuffer_offset_atIndex(Some(&self.plasma_vertex_buffer), 0, 0);
            encoder.setVertexBuffer_offset_atIndex(Some(&self.uniform_buffer), 0, 1);
            encoder.drawPrimitives_vertexStart_vertexCount(MTLPrimitiveType::Point, 0, vertices.len());
        }
    }
    
    /// Apply current base_color to all vertices in the vertex buffer
    fn apply_base_color_to_vertices(&mut self) {
        unsafe {
            let contents = self.vertex_buffer.contents();
            let vertex_count = self.vertex_buffer.length() / std::mem::size_of::<GaiaVertex>();
            let vertices = std::slice::from_raw_parts_mut(
                contents.as_ptr() as *mut GaiaVertex,
                vertex_count
            );
            for vertex in vertices.iter_mut() {
                vertex.color = self.base_color;
            }
        }
    }

    fn default_geometry() -> (Vec<GaiaVertex>, Vec<u16>) {
        let vertices = vec![
            GaiaVertex::new([-0.5, -0.5,  0.5], [0.0, 0.6, 1.0, 1.0]),
            GaiaVertex::new([ 0.5, -0.5,  0.5], [1.0, 0.7, 0.0, 1.0]),
            GaiaVertex::new([ 0.5,  0.5,  0.5], [1.0, 1.0, 1.0, 1.0]),
            GaiaVertex::new([-0.5,  0.5,  0.5], [0.0, 0.3, 0.8, 1.0]),
            GaiaVertex::new([-0.5, -0.5, -0.5], [0.0, 0.3, 0.8, 1.0]),
            GaiaVertex::new([ 0.5, -0.5, -0.5], [0.0, 0.6, 1.0, 1.0]),
            GaiaVertex::new([ 0.5,  0.5, -0.5], [1.0, 0.7, 0.0, 1.0]),
            GaiaVertex::new([-0.5,  0.5, -0.5], [1.0, 1.0, 1.0, 1.0]),
        ];
        #[rustfmt::skip]
        let indices: Vec<u16> = vec![
            0,1,2, 2,3,0,  1,5,6, 6,2,1,
            5,4,7, 7,6,5,  4,0,3, 3,7,4,
            3,2,6, 6,7,3,  4,5,1, 1,0,4,
        ];
        (vertices, indices)
    }

    pub fn upload_geometry_from_primitives(&mut self, primitives: &[vQbitPrimitive]) {
        if primitives.is_empty() {
            return;
        }
        let mut vertices = Vec::new();
        let mut indices = Vec::new();
        let mut index_offset = 0u16;

        for prim in primitives {
            let pos = [
                prim.transform[3][0],
                prim.transform[3][1],
                prim.transform[3][2],
            ];
            let color = [
                prim.vqbit_entropy.clamp(0.0, 1.0),
                prim.vqbit_truth.clamp(0.0, 1.0),
                0.5,
                1.0,
            ];
            vertices.push(GaiaVertex::new(pos, color));

            if index_offset > 0 {
                indices.push(index_offset - 1);
                indices.push(index_offset);
            }
            index_offset += 1;
        }

        unsafe {
            self.vertex_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(vertices.as_ptr() as *mut c_void).unwrap(),
                    (vertices.len() * mem::size_of::<GaiaVertex>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create vertex buffer");

            self.index_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(indices.as_ptr() as *mut c_void).unwrap(),
                    (indices.len() * mem::size_of::<u16>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create index buffer");
        }
        self.index_count = indices.len();
    }

    pub fn upload_geometry(&mut self, vertices: &[GaiaVertex], indices: &[u16]) {
        if vertices.is_empty() || indices.is_empty() {
            return;
        }
        unsafe {
            self.vertex_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(vertices.as_ptr() as *mut c_void).unwrap(),
                    (vertices.len() * mem::size_of::<GaiaVertex>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create vertex buffer");
            self.index_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(indices.as_ptr() as *mut c_void).unwrap(),
                    (indices.len() * mem::size_of::<u16>()) as usize,
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create index buffer");
        }
        self.index_count = indices.len();
    }

    pub fn frame_count(&self) -> u64 {
        self.tau
    }

    pub fn get_shell_world_matrix(&self) -> [f32; 16] {
        // Identity matrix for now - can be extended to read from USD
        [
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ]
    }
}
