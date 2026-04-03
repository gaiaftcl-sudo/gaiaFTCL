//! Camera Plugin for Dimensional Viewer
//!
//! Provides an orbital camera controller for navigating the 3D projection space.

use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;

/// Marker for the main camera
#[derive(Component)]
pub struct MainCamera;

/// Orbital camera state
#[derive(Component)]
pub struct OrbitalCamera {
    pub focus: Vec3,
    pub radius: f32,
    pub pitch: f32,
    pub yaw: f32,
    pub sensitivity: f32,
    pub zoom_sensitivity: f32,
}

impl Default for OrbitalCamera {
    fn default() -> Self {
        Self {
            focus: Vec3::ZERO,
            radius: 15.0,
            pitch: 0.5,
            yaw: 0.8,
            sensitivity: 0.005,
            zoom_sensitivity: 1.0,
        }
    }
}

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_camera).add_systems(
            Update,
            (orbital_camera_control, update_camera_transform).chain(),
        );
    }
}

/// Spawn the main camera
fn setup_camera(mut commands: Commands) {
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(12.0, 10.0, 12.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        MainCamera,
        OrbitalCamera::default(),
    ));
}

/// Handle mouse input for orbital camera control
fn orbital_camera_control(
    mouse_button: Res<ButtonInput<MouseButton>>,
    mut mouse_motion: EventReader<MouseMotion>,
    mut scroll: EventReader<MouseWheel>,
    mut query: Query<&mut OrbitalCamera, With<MainCamera>>,
) {
    let Ok(mut orbital) = query.get_single_mut() else {
        return;
    };

    // Rotate on left mouse drag
    if mouse_button.pressed(MouseButton::Left) {
        for motion in mouse_motion.read() {
            orbital.yaw -= motion.delta.x * orbital.sensitivity;
            orbital.pitch -= motion.delta.y * orbital.sensitivity;

            // Clamp pitch to avoid gimbal lock
            orbital.pitch = orbital.pitch.clamp(-1.5, 1.5);
        }
    } else {
        mouse_motion.clear();
    }

    // Pan on right mouse drag
    if mouse_button.pressed(MouseButton::Right) {
        for motion in mouse_motion.read() {
            let right = Vec3::new(orbital.yaw.cos(), 0.0, -orbital.yaw.sin());
            let up = Vec3::Y;

            orbital.focus -= right * motion.delta.x * orbital.sensitivity * orbital.radius * 0.1;
            orbital.focus += up * motion.delta.y * orbital.sensitivity * orbital.radius * 0.1;
        }
    }

    // Zoom on scroll
    for wheel in scroll.read() {
        orbital.radius -= wheel.y * orbital.zoom_sensitivity;
        orbital.radius = orbital.radius.clamp(2.0, 50.0);
    }
}

/// Update camera transform from orbital state
fn update_camera_transform(mut query: Query<(&OrbitalCamera, &mut Transform), With<MainCamera>>) {
    let Ok((orbital, mut transform)) = query.get_single_mut() else {
        return;
    };

    // Calculate camera position from spherical coordinates
    let x = orbital.radius * orbital.pitch.cos() * orbital.yaw.cos();
    let y = orbital.radius * orbital.pitch.sin();
    let z = orbital.radius * orbital.pitch.cos() * orbital.yaw.sin();

    let position = orbital.focus + Vec3::new(x, y, z);

    transform.translation = position;
    transform.look_at(orbital.focus, Vec3::Y);
}
