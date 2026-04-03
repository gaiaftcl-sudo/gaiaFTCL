//! GaiaOS Dimensional Viewer - Bevy WASM Client
//!
//! Professional 3D/4D visualization of 8D quantum substrate.
//! Phase 1.1: Basic Bevy setup with projection rendering.

use bevy::prelude::*;
use dimensional_viewer_shared::{Coord8D, ProjectionMatrix, VirtueScore, VisualizationPoint};

fn main() {
    // Setup panic hook for better WASM error messages
    #[cfg(target_arch = "wasm32")]
    console_error_panic_hook::set_once();

    #[cfg(target_arch = "wasm32")]
    tracing_web::try_set_as_global_default().ok();

    info!("🚀 GaiaOS Dimensional Viewer starting...");
    info!("   Mode: WASM (WebGL2)");
    info!("   Version: 0.1.0");

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "GaiaOS Dimensional Viewer".to_string(),
                canvas: Some("#bevy".to_string()),
                ..default()
            }),
            ..default()
        }))
        .insert_resource(ClearColor(Color::srgb(0.0, 0.0, 0.05))) // Deep blue background
        .insert_resource(ViewerState::default())
        .add_systems(Startup, setup)
        .add_systems(Update, (update_info_display, rotate_camera))
        .run();
}

#[derive(Resource)]
struct ViewerState {
    projection_matrix: ProjectionMatrix,
    points_loaded: usize,
    avg_coherence_loss: f32,
}

impl Default for ViewerState {
    fn default() -> Self {
        Self {
            projection_matrix: ProjectionMatrix::default_projection(),
            points_loaded: 0,
            avg_coherence_loss: 0.0,
        }
    }
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    info!("Setting up 3D scene...");

    // Add camera
    commands.spawn(Camera3dBundle {
        transform: Transform::from_xyz(0.0, 5.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..default()
    });

    // Add directional light
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 10000.0,
            shadows_enabled: false,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(
            EulerRot::XYZ,
            -std::f32::consts::FRAC_PI_4,
            std::f32::consts::FRAC_PI_4,
            0.0,
        )),
        ..default()
    });

    // Add reference grid
    let grid_size = 10;
    let grid_spacing = 1.0;

    for x in -grid_size..=grid_size {
        for z in -grid_size..=grid_size {
            if x % 2 == 0 && z % 2 == 0 {
                let material = if (x + z) % 4 == 0 {
                    Color::srgb(0.1, 0.1, 0.15)
                } else {
                    Color::srgb(0.05, 0.05, 0.1)
                };

                commands.spawn(PbrBundle {
                    mesh: meshes.add(Cuboid::new(0.1, 0.1, 0.1)),
                    material: materials.add(StandardMaterial {
                        base_color: material,
                        unlit: true,
                        ..default()
                    }),
                    transform: Transform::from_xyz(
                        x as f32 * grid_spacing,
                        0.0,
                        z as f32 * grid_spacing,
                    ),
                    ..default()
                });
            }
        }
    }

    // Add test vQbit visualization (demonstrates projection)
    let test_coord = Coord8D::new([1.0, 2.0, 3.0, 0.5, 0.3, 0.2, 0.1, 0.05]);
    let projection_matrix = ProjectionMatrix::default_projection();
    let proj = projection_matrix.project(&test_coord);
    let virtue = VirtueScore::new(0.85);

    let (h, s, v) = virtue.to_hsv();
    let color = hsv_to_rgb(h, s, v);

    commands.spawn(PbrBundle {
        mesh: meshes.add(Sphere::new(0.2)),
        material: materials.add(StandardMaterial {
            base_color: Color::srgb(color.0, color.1, color.2),
            emissive: LinearRgba::new(color.0, color.1, color.2, 1.0) * 2.0,
            ..default()
        }),
        transform: Transform::from_xyz(proj.x, proj.y, proj.z),
        ..default()
    });

    info!("✅ Scene setup complete");
    info!("   Grid: {}×{} cells", grid_size * 2, grid_size * 2);
    info!(
        "   Test point projected: ({:.2}, {:.2}, {:.2})",
        proj.x, proj.y, proj.z
    );
    info!("   Coherence loss: {:.1}%", proj.coherence_loss * 100.0);
}

fn update_info_display() {
    // WebGL rendering info (future: update HUD)
}

fn rotate_camera(time: Res<Time>, mut query: Query<&mut Transform, With<Camera3d>>) {
    for mut transform in &mut query {
        let rotation_speed = 0.1;
        let angle = time.elapsed_seconds() * rotation_speed;
        let radius = 10.0;

        transform.translation.x = angle.sin() * radius;
        transform.translation.z = angle.cos() * radius;
        transform.look_at(Vec3::ZERO, Vec3::Y);
    }
}

/// Convert HSV to RGB
fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (f32, f32, f32) {
    let c = v * s;
    let h_prime = h / 60.0;
    let x = c * (1.0 - ((h_prime % 2.0) - 1.0).abs());
    let m = v - c;

    let (r, g, b) = if h_prime < 1.0 {
        (c, x, 0.0)
    } else if h_prime < 2.0 {
        (x, c, 0.0)
    } else if h_prime < 3.0 {
        (0.0, c, x)
    } else if h_prime < 4.0 {
        (0.0, x, c)
    } else if h_prime < 5.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };

    (r + m, g + m, b + m)
}
