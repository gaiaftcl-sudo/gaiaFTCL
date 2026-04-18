//! macOS Metal demo binary — objc2-heavy; clippy `-D warnings` is relaxed here.
#![allow(unused_unsafe)]
#![allow(dead_code)]
#![allow(clippy::derivable_impls)]
#![allow(clippy::unnecessary_cast)]
#![allow(clippy::explicit_counter_loop)]
#![allow(clippy::manual_slice_size_calculation)]
#![allow(clippy::field_reassign_with_default)]

mod renderer;
mod shaders;

use std::sync::Arc;

use renderer::MetalRenderer;
use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

// ── Application state ──

struct GaiaApp {
    window: Option<Arc<Window>>,
    renderer: Option<MetalRenderer>,
}

impl Default for GaiaApp {
    fn default() -> Self {
        Self {
            window: None,
            renderer: None,
        }
    }
}

impl ApplicationHandler for GaiaApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return; // Already initialized
        }

        let attrs = WindowAttributes::default()
            .with_title("GaiaFTCL — Sovereign Metal Renderer")
            .with_inner_size(LogicalSize::new(1280.0, 720.0));

        let window = Arc::new(
            event_loop
                .create_window(attrs)
                .expect("Failed to create window"),
        );

        let renderer = MetalRenderer::new(window.as_ref());

        // Initial resize
        let size = window.inner_size();
        renderer.resize(size.width, size.height);

        self.window = Some(window);
        self.renderer = Some(renderer);
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        event: WindowEvent,
    ) {
        match event {
            WindowEvent::CloseRequested => {
                event_loop.exit();
            }

            WindowEvent::Resized(size) => {
                if let Some(renderer) = &self.renderer {
                    renderer.resize(size.width, size.height);
                }
            }

            WindowEvent::RedrawRequested => {
                if let (Some(window), Some(renderer)) = (&self.window, &mut self.renderer) {
                    let size = window.inner_size();
                    if size.width > 0 && size.height > 0 {
                        renderer.render_frame(size.width, size.height);
                    }
                    window.request_redraw();
                }
            }

            _ => {}
        }
    }

    fn about_to_wait(&mut self, _event_loop: &ActiveEventLoop) {
        if let Some(window) = &self.window {
            window.request_redraw();
        }
    }
}

fn main() {
    let event_loop = EventLoop::new().expect("Failed to create event loop");
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = GaiaApp::default();
    event_loop
        .run_app(&mut app)
        .expect("Event loop terminated with error");
}
