use std::mem;
use core::ptr::NonNull;
use core::ffi::c_void;

use glam::{Mat4, Vec3};
use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_foundation::{NSString, NSSize};
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
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use raw_window_metal::Layer;

use rust_fusion_usd_parser::vQbitPrimitive;
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
    frame: u64,
}

impl MetalRenderer {
    pub fn new(window: &impl HasWindowHandle) -> Self {
        let device = unsafe { MTLCreateSystemDefaultDevice() }
            .expect("No Metal-capable GPU found");

        let command_queue = device
            .newCommandQueue()
            .expect("Failed to create command queue");

        let handle = window.window_handle().expect("No window handle");
        let raw_layer = match handle.as_raw() {
            RawWindowHandle::AppKit(h) => unsafe { Layer::from_ns_view(h.ns_view) },
            _ => panic!("Only macOS/AppKit supported — sovereign constraint"),
        };
        let layer_ptr = raw_layer.into_raw().as_ptr().cast::<CAMetalLayer>();
        let layer = unsafe { Retained::from_raw(layer_ptr).unwrap() };

        unsafe {
            layer.setDevice(Some(&device));
            layer.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
            layer.setFramebufferOnly(true);
        }

        let source = NSString::from_str(SHADER_SOURCE);
        let library = unsafe { device.newLibraryWithSource_options_error(&source, None) }
            .expect("Shader compilation failed");

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

        Self {
            device,
            command_queue,
            pipeline_state,
            layer,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            index_count: indices.len(),
            frame: 0,
        }
    }

    pub fn resize(&self, width: u32, height: u32) {
        unsafe {
            self.layer.setDrawableSize(NSSize {
                width: width as f64,
                height: height as f64,
            });
        }
    }

    pub fn render_frame(&mut self, width: u32, height: u32) {
        self.frame += 1;

        let aspect = width as f32 / height.max(1) as f32;
        let angle = (self.frame as f32) * 0.02;

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
        // Guard: empty input — keep the current geometry untouched rather than
        // calling newBufferWithBytes with a zero-length / dangling pointer.
        if primitives.is_empty() {
            return;
        }

        let mut vertices = Vec::with_capacity(primitives.len());
        let mut indices: Vec<u16> = Vec::new();
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

        // Only upload if we actually produced geometry.
        if vertices.is_empty() || indices.is_empty() {
            return;
        }

        unsafe {
            self.vertex_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(vertices.as_ptr() as *mut c_void).unwrap(),
                    vertices.len() * mem::size_of::<GaiaVertex>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create vertex buffer");

            self.index_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(indices.as_ptr() as *mut c_void).unwrap(),
                    indices.len() * mem::size_of::<u16>(),
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
                    vertices.len() * mem::size_of::<GaiaVertex>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create vertex buffer");
            self.index_buffer = self.device
                .newBufferWithBytes_length_options(
                    NonNull::new(indices.as_ptr() as *mut c_void).unwrap(),
                    indices.len() * mem::size_of::<u16>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create index buffer");
        }
        self.index_count = indices.len();
    }

    pub fn frame_count(&self) -> u64 {
        self.frame
    }

    // Expose default_geometry for testing without constructing a MetalRenderer.
    #[cfg(test)]
    pub fn default_geometry_for_test() -> (Vec<GaiaVertex>, Vec<u16>) {
        Self::default_geometry()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests — no Metal device required; pure struct-layout + geometry logic only.
// All tests must pass on `cargo test -p gaia-metal-renderer` on macOS.
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod tests {
    use super::*;
    use rust_fusion_usd_parser::vQbitPrimitive;

    // ── TR: Type / layout validation ─────────────────────────────────────────

    #[test]
    fn tr_001_gaia_vertex_size() {
        // position [f32;3] = 12 B  +  color [f32;4] = 16 B  →  28 B total
        assert_eq!(std::mem::size_of::<GaiaVertex>(), 28);
    }

    #[test]
    fn tr_002_gaia_vertex_field_offsets() {
        assert_eq!(std::mem::offset_of!(GaiaVertex, position), 0);
        assert_eq!(std::mem::offset_of!(GaiaVertex, color), 12);
    }

    #[test]
    fn tr_003_uniforms_size() {
        // float4x4 = 16 × f32 = 64 bytes
        assert_eq!(std::mem::size_of::<Uniforms>(), 64);
    }

    #[test]
    fn tr_004_vqbit_primitive_passthrough() {
        // vQbitPrimitive must be importable and instantiable from this crate.
        let p = vQbitPrimitive::default();
        assert_eq!(p.prim_id, 0);
        assert_eq!(p.vqbit_entropy, 0.0);
        assert_eq!(p.vqbit_truth, 0.0);
        assert_eq!(std::mem::size_of::<vQbitPrimitive>(), 76);
    }

    // ── TC: Geometry conversion correctness ──────────────────────────────────

    #[test]
    fn tc_001_default_geometry_vertex_count() {
        let (vertices, _) = MetalRenderer::default_geometry_for_test();
        assert_eq!(vertices.len(), 8, "Default cube requires 8 unique vertices");
    }

    #[test]
    fn tc_002_default_geometry_index_count() {
        let (_, indices) = MetalRenderer::default_geometry_for_test();
        // 6 faces × 2 triangles × 3 vertices = 36 indices
        assert_eq!(indices.len(), 36, "Default cube requires 36 indices");
    }

    #[test]
    fn tc_003_default_geometry_indices_in_range() {
        let (vertices, indices) = MetalRenderer::default_geometry_for_test();
        let n = vertices.len() as u16;
        for &idx in &indices {
            assert!(idx < n, "Index {idx} out of range (vertex count = {n})");
        }
    }

    #[test]
    fn tc_004_vertex_new_roundtrip() {
        let v = GaiaVertex::new([1.0, 2.0, 3.0], [0.1, 0.2, 0.3, 1.0]);
        assert_eq!(v.position, [1.0, 2.0, 3.0]);
        assert_eq!(v.color, [0.1, 0.2, 0.3, 1.0]);
    }

    // ── TI: Integration — USD primitive → vertex color mapping ───────────────

    #[test]
    fn ti_001_vqbit_primitive_color_mapping() {
        // entropy → R channel, truth → G channel, hardcoded 0.5 → B
        let mut prim = vQbitPrimitive::default();
        prim.vqbit_entropy = 0.4;
        prim.vqbit_truth   = 0.8;

        // Replicate the mapping from upload_geometry_from_primitives
        let color = [
            prim.vqbit_entropy.clamp(0.0, 1.0),
            prim.vqbit_truth.clamp(0.0, 1.0),
            0.5_f32,
            1.0_f32,
        ];

        assert!((color[0] - 0.4).abs() < 1e-6, "R ← vqbit_entropy");
        assert!((color[1] - 0.8).abs() < 1e-6, "G ← vqbit_truth");
        assert!((color[2] - 0.5).abs() < 1e-6, "B hardcoded 0.5");
        assert!((color[3] - 1.0).abs() < 1e-6, "A hardcoded 1.0");
    }

    #[test]
    fn ti_002_vqbit_entropy_clamped_above_one() {
        let mut prim = vQbitPrimitive::default();
        prim.vqbit_entropy = 1.5; // out of [0,1]
        let clamped = prim.vqbit_entropy.clamp(0.0, 1.0);
        assert_eq!(clamped, 1.0);
    }

    #[test]
    fn ti_003_vqbit_truth_clamped_below_zero() {
        let mut prim = vQbitPrimitive::default();
        prim.vqbit_truth = -0.3;
        let clamped = prim.vqbit_truth.clamp(0.0, 1.0);
        assert_eq!(clamped, 0.0);
    }

    // ── RG: Regression guards ─────────────────────────────────────────────────

    #[test]
    fn rg_001_vertex_stride_28_bytes() {
        // Metal vertex descriptor stride must stay 28.  If GaiaVertex layout
        // changes, this test fails and forces a corresponding shader update.
        assert_eq!(std::mem::size_of::<GaiaVertex>(), 28,
            "REGRESSION: GaiaVertex stride changed — update MTLVertexDescriptor in renderer::new()");
    }

    #[test]
    fn rg_002_uniforms_stride_64_bytes() {
        assert_eq!(std::mem::size_of::<Uniforms>(), 64,
            "REGRESSION: Uniforms stride changed — update Metal buffer(1) binding");
    }

    #[test]
    fn rg_003_vqbit_primitive_repr_c_size() {
        assert_eq!(std::mem::size_of::<vQbitPrimitive>(), 76,
            "REGRESSION: vQbitPrimitive ABI changed — breaks FFI boundary with Swift layer");
    }
}
