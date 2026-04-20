//! GaiaHealth Metal Renderer — macOS CAMetalLayer driver
//!
//! Implements the molecular visualization pipeline using objc2-metal 0.3.
//! Mirrors the pattern from GaiaFTCL/gaia-metal-renderer but renders
//! BioligitPrimitive buffers with M/I/A epistemic alpha blending.
//!
//! Key differences from the Fusion renderer:
//!   1. Four shader pipelines (M=opaque, I=translucent, A=stippled, alarm=overlay)
//!      selected by epistemic_tag uniform per frame.
//!   2. MTLLoadActionClear on EVERY pass (21 CFR Part 11 — no ghost artifacts).
//!   3. CONSTITUTIONAL_FLAG state triggers alarm_pipeline (pulsing red overlay).
//!   4. Unified memory (StorageModeShared) — zero CPU↔GPU copy, same as Fusion.
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

// objc2-metal: some `unsafe { }` blocks wrap calls the bindings also mark safe; keep blocks for clarity.
#![allow(unused_unsafe)]

use std::mem;
use core::ptr::NonNull;
use core::ffi::c_void;

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
    MTLBuffer, MTLCommandEncoder, MTLBlendFactor, MTLBlendOperation,
};
use objc2_quartz_core::{CAMetalDrawable, CAMetalLayer};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use raw_window_metal::Layer;

use crate::shaders::BIOLOGIT_SHADERS;

/// GaiaHealth vertex — 32-byte stride (RG-005 lock).
/// position(12) + color(16) + padding(4) = 32 bytes.
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct GaiaHealthVertex {
    pub position: [f32; 3],   // offset 0,  12 bytes
    pub color:    [f32; 4],   // offset 12, 16 bytes
    pub _pad:     f32,        // offset 28,  4 bytes — stride = 32
}

impl GaiaHealthVertex {
    pub const fn new(pos: [f32; 3], col: [f32; 4]) -> Self {
        Self { position: pos, color: col, _pad: 0.0 }
    }
}

/// GaiaHealth uniforms — 80 bytes total.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct GaiaHealthUniforms {
    pub mvp:              [[f32; 4]; 4],  // 64 bytes
    pub epistemic_alpha:  f32,            // 1.0=M, 0.6=I, 0.3=A
    pub epistemic_tag:    u32,            // 0=M, 1=I, 2=A
    pub cell_state:       u32,            // BiologicalCellState discriminant
    pub training_mode:    u32,            // 1=training
}

/// GaiaHealth Metal renderer — four pipelines (M/I/A/alarm).
pub struct HealthMetalRenderer {
    /// Retained `MTLDevice` for layer lifetime; not read after `new`.
    #[allow(dead_code)]
    device:           Retained<ProtocolObject<dyn MTLDevice>>,
    command_queue:    Retained<ProtocolObject<dyn MTLCommandQueue>>,
    m_pipeline:       Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    i_pipeline:       Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    a_pipeline:       Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    alarm_pipeline:   Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    layer:            Retained<CAMetalLayer>,
    vertex_buffer:    Retained<ProtocolObject<dyn MTLBuffer>>,
    index_buffer:     Retained<ProtocolObject<dyn MTLBuffer>>,
    uniform_buffer:   Retained<ProtocolObject<dyn MTLBuffer>>,
    index_count:      usize,
    frame:            u64,
}

impl HealthMetalRenderer {
    /// Initialize the Metal renderer with four pipelines.
    pub fn new(window: &impl HasWindowHandle) -> Self {
        let device = unsafe { MTLCreateSystemDefaultDevice() }
            .expect("No Metal-capable GPU found");

        let command_queue = device
            .newCommandQueue()
            .expect("Failed to create command queue");

        // Extract CAMetalLayer from window
        let handle = window.window_handle().expect("No window handle");
        let raw_layer = match handle.as_raw() {
            RawWindowHandle::AppKit(h) => unsafe { Layer::from_ns_view(h.ns_view) },
            _ => panic!("Only macOS/AppKit supported"),
        };
        let layer_ptr = raw_layer.into_raw().as_ptr().cast::<CAMetalLayer>();
        let layer = unsafe { Retained::from_raw(layer_ptr).unwrap() };

        unsafe {
            layer.setDevice(Some(&device));
            layer.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
            layer.setFramebufferOnly(true);
        }

        // Compile shaders
        let source = NSString::from_str(BIOLOGIT_SHADERS);
        let library = unsafe { device.newLibraryWithSource_options_error(&source, None) }
            .expect("Shader compilation failed");

        // Create vertex descriptor (32-byte stride)
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
            layout0.setStride(32); // 32-byte stride (RG-005 lock)
            layout0.setStepFunction(MTLVertexStepFunction::PerVertex);
            layout0.setStepRate(1);
        }

        // Create M pipeline (opaque, no blending)
        let bio_vert_name = NSString::from_str("bio_vertex_main");
        let bio_frag_name = NSString::from_str("bio_fragment_main");
        let bio_vert_fn = unsafe { library.newFunctionWithName(&bio_vert_name) }
            .expect("bio_vertex_main not found");
        let bio_frag_fn = unsafe { library.newFunctionWithName(&bio_frag_name) }
            .expect("bio_fragment_main not found");

        let m_desc = unsafe { MTLRenderPipelineDescriptor::new() };
        unsafe {
            m_desc.setVertexFunction(Some(&bio_vert_fn));
            m_desc.setFragmentFunction(Some(&bio_frag_fn));
            m_desc.setVertexDescriptor(Some(&vertex_desc));

            let color_attachments = m_desc.colorAttachments();
            let ca0: Retained<MTLRenderPipelineColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
            ca0.setBlendingEnabled(false);
        }

        let m_pipeline = unsafe { device.newRenderPipelineStateWithDescriptor_error(&m_desc) }
            .expect("Failed to create M pipeline");

        // Create I pipeline (alpha blending)
        let i_desc = unsafe { MTLRenderPipelineDescriptor::new() };
        unsafe {
            i_desc.setVertexFunction(Some(&bio_vert_fn));
            i_desc.setFragmentFunction(Some(&bio_frag_fn));
            i_desc.setVertexDescriptor(Some(&vertex_desc));

            let color_attachments = i_desc.colorAttachments();
            let ca0: Retained<MTLRenderPipelineColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
            ca0.setBlendingEnabled(true);
            ca0.setSourceRGBBlendFactor(MTLBlendFactor::SourceAlpha);
            ca0.setDestinationRGBBlendFactor(MTLBlendFactor::OneMinusSourceAlpha);
            ca0.setRgbBlendOperation(MTLBlendOperation::Add);
            ca0.setSourceAlphaBlendFactor(MTLBlendFactor::One);
            ca0.setDestinationAlphaBlendFactor(MTLBlendFactor::Zero);
            ca0.setAlphaBlendOperation(MTLBlendOperation::Add);
        }

        let i_pipeline = unsafe { device.newRenderPipelineStateWithDescriptor_error(&i_desc) }
            .expect("Failed to create I pipeline");

        // Create A pipeline (same as I — stipple discard in shader)
        let a_pipeline = unsafe { device.newRenderPipelineStateWithDescriptor_error(&i_desc) }
            .expect("Failed to create A pipeline");

        // Create alarm pipeline (additive blend, pulsing red overlay)
        let alarm_vert_name = NSString::from_str("alarm_vertex_main");
        let alarm_frag_name = NSString::from_str("alarm_fragment_main");
        let alarm_vert_fn = unsafe { library.newFunctionWithName(&alarm_vert_name) }
            .expect("alarm_vertex_main not found");
        let alarm_frag_fn = unsafe { library.newFunctionWithName(&alarm_frag_name) }
            .expect("alarm_fragment_main not found");

        let alarm_desc = unsafe { MTLRenderPipelineDescriptor::new() };
        unsafe {
            alarm_desc.setVertexFunction(Some(&alarm_vert_fn));
            alarm_desc.setFragmentFunction(Some(&alarm_frag_fn));
            alarm_desc.setVertexDescriptor(Some(&vertex_desc));

            let color_attachments = alarm_desc.colorAttachments();
            let ca0: Retained<MTLRenderPipelineColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
            ca0.setBlendingEnabled(true);
            ca0.setSourceRGBBlendFactor(MTLBlendFactor::SourceAlpha);
            ca0.setDestinationRGBBlendFactor(MTLBlendFactor::One);
            ca0.setRgbBlendOperation(MTLBlendOperation::Add);
        }

        let alarm_pipeline = unsafe { device.newRenderPipelineStateWithDescriptor_error(&alarm_desc) }
            .expect("Failed to create alarm pipeline");

        // Create buffers
        let (vertices, indices) = Self::default_geometry();

        let vertex_buffer = unsafe {
            device
                .newBufferWithBytes_length_options(
                    NonNull::new(vertices.as_ptr() as *mut c_void).unwrap(),
                    (vertices.len() * mem::size_of::<GaiaHealthVertex>()) as usize,
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
                    mem::size_of::<GaiaHealthUniforms>(),
                    MTLResourceOptions::StorageModeShared,
                )
                .expect("Failed to create uniform buffer")
        };

        Self {
            device,
            command_queue,
            m_pipeline,
            i_pipeline,
            a_pipeline,
            alarm_pipeline,
            layer,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            index_count: indices.len(),
            frame: 0,
        }
    }

    /// Resize the drawable.
    pub fn resize(&self, width: u32, height: u32) {
        unsafe {
            self.layer.setDrawableSize(NSSize {
                width: width as f64,
                height: height as f64,
            });
        }
    }

    /// Render one MD frame with epistemic tag selection and optional alarm overlay.
    ///
    /// epistemic_tag: 0=M (opaque), 1=I (translucent), 2=A (stippled)
    /// cell_state: 7=CONSTITUTIONAL_FLAG triggers alarm overlay
    pub fn render_frame(&mut self, epistemic_tag: u32, cell_state: u32) {
        self.frame += 1;

        // Select pipeline based on epistemic tag
        let epistemic_alpha = match epistemic_tag {
            0 => 1.0, // M — fully opaque
            1 => 0.6, // I — translucent
            2 => 0.3, // A — faint
            _ => 1.0,
        };

        let pipeline = match epistemic_tag {
            0 => &self.m_pipeline,
            1 => &self.i_pipeline,
            2 => &self.a_pipeline,
            _ => &self.m_pipeline,
        };

        // Update uniforms
        let uniforms = GaiaHealthUniforms {
            mvp: [[1.0, 0.0, 0.0, 0.0],
                  [0.0, 1.0, 0.0, 0.0],
                  [0.0, 0.0, 1.0, 0.0],
                  [0.0, 0.0, 0.0, 1.0]], // Identity MVP for now
            epistemic_alpha,
            epistemic_tag,
            cell_state,
            training_mode: 0,
        };
        unsafe {
            let contents = self.uniform_buffer.contents();
            let ptr = contents.as_ptr() as *mut GaiaHealthUniforms;
            std::ptr::write(ptr, uniforms);
        }

        // Get drawable
        let drawable = unsafe { self.layer.nextDrawable() };
        let drawable = match drawable {
            Some(d) => d,
            None => return,
        };

        // Create render pass with MTLLoadActionClear (21 CFR Part 11 — no ghost artifacts)
        let pass_desc = unsafe { MTLRenderPassDescriptor::new() };
        unsafe {
            let color_attachments = pass_desc.colorAttachments();
            let ca0: Retained<MTLRenderPassColorAttachmentDescriptor> =
                color_attachments.objectAtIndexedSubscript(0);
            ca0.setTexture(Some(&drawable.texture()));
            ca0.setLoadAction(MTLLoadAction::Clear);
            ca0.setStoreAction(MTLStoreAction::Store);
            ca0.setClearColor(MTLClearColor {
                red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0,
            });
        }

        let cmd_buffer = self.command_queue
            .commandBuffer()
            .expect("Failed to create command buffer");

        // Main render pass
        let encoder = unsafe {
            cmd_buffer
                .renderCommandEncoderWithDescriptor(&pass_desc)
                .expect("Failed to create render encoder")
        };

        unsafe {
            encoder.setRenderPipelineState(pipeline);
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

        // If CONSTITUTIONAL_FLAG (7), render alarm overlay
        if cell_state == 7 {
            let alarm_encoder = unsafe {
                cmd_buffer
                    .renderCommandEncoderWithDescriptor(&pass_desc)
                    .expect("Failed to create alarm encoder")
            };

            unsafe {
                alarm_encoder.setRenderPipelineState(&self.alarm_pipeline);
                alarm_encoder.setVertexBuffer_offset_atIndex(Some(&self.vertex_buffer), 0, 0);
                alarm_encoder.setVertexBuffer_offset_atIndex(Some(&self.uniform_buffer), 0, 1);
                alarm_encoder.drawIndexedPrimitives_indexCount_indexType_indexBuffer_indexBufferOffset(
                    MTLPrimitiveType::Triangle,
                    self.index_count,
                    MTLIndexType::UInt16,
                    &self.index_buffer,
                    0,
                );
                alarm_encoder.endEncoding();
            }
        }

        unsafe {
            cmd_buffer.presentDrawable(drawable.as_ref() as &ProtocolObject<dyn MTLDrawable>);
        }
        cmd_buffer.commit();
    }

    /// Default cube geometry for testing.
    fn default_geometry() -> (Vec<GaiaHealthVertex>, Vec<u16>) {
        let vertices = vec![
            GaiaHealthVertex::new([-0.5, -0.5,  0.5], [0.0, 0.6, 1.0, 1.0]),
            GaiaHealthVertex::new([ 0.5, -0.5,  0.5], [1.0, 0.7, 0.0, 1.0]),
            GaiaHealthVertex::new([ 0.5,  0.5,  0.5], [1.0, 1.0, 1.0, 1.0]),
            GaiaHealthVertex::new([-0.5,  0.5,  0.5], [0.0, 0.3, 0.8, 1.0]),
            GaiaHealthVertex::new([-0.5, -0.5, -0.5], [0.0, 0.3, 0.8, 1.0]),
            GaiaHealthVertex::new([ 0.5, -0.5, -0.5], [0.0, 0.6, 1.0, 1.0]),
            GaiaHealthVertex::new([ 0.5,  0.5, -0.5], [1.0, 0.7, 0.0, 1.0]),
            GaiaHealthVertex::new([-0.5,  0.5, -0.5], [1.0, 1.0, 1.0, 1.0]),
        ];
        #[rustfmt::skip]
        let indices: Vec<u16> = vec![
            0,1,2, 2,3,0,  1,5,6, 6,2,1,
            5,4,7, 7,6,5,  4,0,3, 3,7,4,
            3,2,6, 6,7,3,  4,5,1, 1,0,4,
        ];
        (vertices, indices)
    }
}

impl Default for HealthMetalRenderer {
    fn default() -> Self { 
        // Note: default() requires a window, so this creates a minimal renderer
        // This will panic if called outside of a window context
        panic!("HealthMetalRenderer::default() not supported - use new(window) instead");
    }
}
