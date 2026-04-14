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

pub struct MetalRenderer {
    device: Retained<ProtocolObject<dyn MTLDevice>>,
    command_queue: Retained<ProtocolObject<dyn MTLCommandQueue>>,
    pipeline_state: Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    layer: Retained<CAMetalLayer>,
    vertex_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    index_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    uniform_buffer: Retained<ProtocolObject<dyn MTLBuffer>>,
    index_count: usize,
    tau: u64,  // Bitcoin block height (emergent time)
    /// Last frame render time in microseconds (patent requirement: <3000 μs)
    last_frame_time_us: u64,
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

        let (vertices, indices) = Self::default_geometry();

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

        Ok(Self {
            device,
            command_queue,
            pipeline_state,
            layer,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            index_count: indices.len(),
            tau: 0,
            last_frame_time_us: 0,
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
        
        // Note: tau is updated via set_tau() from Swift NATS subscription
        // We use tau as a slower animation driver (Bitcoin blocks ~10 min)
        let aspect = width as f32 / height.max(1) as f32;
        let angle = (self.tau as f32) * 0.02;

        let projection = Mat4::perspective_rh(45.0_f32.to_radians(), aspect, 0.1, 100.0);
        let view = Mat4::look_at_rh(Vec3::new(0.0, 1.5, 4.0), Vec3::ZERO, Vec3::Y);
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
            encoder.drawIndexedPrimitives_indexCount_indexType_indexBuffer_indexBufferOffset(
                MTLPrimitiveType::Triangle,
                self.index_count,
                MTLIndexType::UInt16,
                &self.index_buffer,
                0,
            );
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
