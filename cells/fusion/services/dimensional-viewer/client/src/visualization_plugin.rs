//! Visualization Plugin for Dimensional Viewer
//!
//! Renders projected points with coherence and virtue indicators.
//! Points are colored by layer, sized by virtue, and alpha by coherence.

use bevy::prelude::*;

use crate::websocket_plugin::{ViewState, ViewUpdatedEvent};

/// Marker component for projected point entities
#[derive(Component)]
pub struct PointEntity {
    pub layer_index: usize,
    pub point_index: usize,
    pub coherence: f32,
    pub virtue: f32,
}

/// Marker component for layer parent entities
#[derive(Component)]
pub struct LayerEntity {
    pub layer_index: usize,
}

/// Marker for coherence indicator rings
#[derive(Component)]
pub struct CoherenceRing {
    pub point_entity: Entity,
}

/// Materials for visualization
#[derive(Resource)]
pub struct VisualizationMaterials {
    pub layer_materials: Vec<Handle<StandardMaterial>>,
    pub low_coherence_material: Handle<StandardMaterial>,
}

/// Meshes for visualization
#[derive(Resource)]
pub struct VisualizationMeshes {
    pub point_mesh: Handle<Mesh>,
    pub ring_mesh: Handle<Mesh>,
}

pub struct VisualizationPlugin;

impl Plugin for VisualizationPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_visualization).add_systems(
            Update,
            (handle_view_update, animate_points, update_coherence_rings),
        );
    }
}

/// Initialize visualization resources
fn setup_visualization(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Create point mesh (sphere)
    let point_mesh = meshes.add(Sphere::new(0.15).mesh().ico(2).unwrap());

    // Create ring mesh for coherence indicator
    let ring_mesh = meshes.add(Torus::new(0.2, 0.02).mesh());

    commands.insert_resource(VisualizationMeshes {
        point_mesh,
        ring_mesh,
    });

    // Create layer materials with distinct colors
    let layer_colors = [
        Color::srgb(0.4, 0.8, 1.0), // vQbit - cyan
        Color::srgb(0.2, 1.0, 0.4), // Agents - green
        Color::srgb(1.0, 0.6, 0.2), // Cells - orange
        Color::srgb(1.0, 0.4, 0.8), // Systems - pink
        Color::srgb(0.8, 0.8, 0.2), // Networks - yellow
    ];

    let layer_materials: Vec<Handle<StandardMaterial>> = layer_colors
        .iter()
        .map(|color| {
            materials.add(StandardMaterial {
                base_color: *color,
                emissive: (*color * 0.5).into(),
                ..default()
            })
        })
        .collect();

    let low_coherence_material = materials.add(StandardMaterial {
        base_color: Color::srgba(1.0, 0.2, 0.2, 0.5),
        alpha_mode: AlphaMode::Blend,
        ..default()
    });

    commands.insert_resource(VisualizationMaterials {
        layer_materials,
        low_coherence_material,
    });

    // Add ambient light
    commands.insert_resource(AmbientLight {
        color: Color::WHITE,
        brightness: 400.0,
    });

    // Add directional light
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 15000.0,
            shadows_enabled: false,
            ..default()
        },
        transform: Transform::from_xyz(10.0, 20.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..default()
    });

    // Add coordinate axes
    spawn_axes(&mut commands, &mut meshes, &mut materials);
}

/// Spawn coordinate axes for orientation
fn spawn_axes(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    materials: &mut ResMut<Assets<StandardMaterial>>,
) {
    let axis_length = 5.0;
    let axis_radius = 0.03;

    // X axis (red)
    commands.spawn(PbrBundle {
        mesh: meshes.add(Cylinder::new(axis_radius, axis_length).mesh()),
        material: materials.add(StandardMaterial {
            base_color: Color::srgb(1.0, 0.2, 0.2),
            ..default()
        }),
        transform: Transform::from_xyz(axis_length / 2.0, 0.0, 0.0)
            .with_rotation(Quat::from_rotation_z(-std::f32::consts::FRAC_PI_2)),
        ..default()
    });

    // Y axis (green)
    commands.spawn(PbrBundle {
        mesh: meshes.add(Cylinder::new(axis_radius, axis_length).mesh()),
        material: materials.add(StandardMaterial {
            base_color: Color::srgb(0.2, 1.0, 0.2),
            ..default()
        }),
        transform: Transform::from_xyz(0.0, axis_length / 2.0, 0.0),
        ..default()
    });

    // Z axis (blue)
    commands.spawn(PbrBundle {
        mesh: meshes.add(Cylinder::new(axis_radius, axis_length).mesh()),
        material: materials.add(StandardMaterial {
            base_color: Color::srgb(0.2, 0.2, 1.0),
            ..default()
        }),
        transform: Transform::from_xyz(0.0, 0.0, axis_length / 2.0)
            .with_rotation(Quat::from_rotation_x(std::f32::consts::FRAC_PI_2)),
        ..default()
    });
}

/// Handle view updates by rebuilding the scene
fn handle_view_update(
    mut commands: Commands,
    mut events: EventReader<ViewUpdatedEvent>,
    view_state: Res<ViewState>,
    vis_meshes: Res<VisualizationMeshes>,
    vis_materials: Res<VisualizationMaterials>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    existing_points: Query<Entity, With<PointEntity>>,
    existing_layers: Query<Entity, With<LayerEntity>>,
    existing_rings: Query<Entity, With<CoherenceRing>>,
) {
    // Only process if we have events
    if events.read().next().is_none() {
        return;
    }

    // Clear existing entities
    for entity in existing_points.iter() {
        commands.entity(entity).despawn_recursive();
    }
    for entity in existing_layers.iter() {
        commands.entity(entity).despawn_recursive();
    }
    for entity in existing_rings.iter() {
        commands.entity(entity).despawn_recursive();
    }

    let response = &view_state.response;

    // Spawn entities for each layer
    for (layer_idx, layer) in response.layers.iter().enumerate() {
        // Spawn layer parent
        let layer_entity = commands
            .spawn((
                SpatialBundle::default(),
                LayerEntity {
                    layer_index: layer_idx,
                },
                Name::new(format!("Layer-{}", layer.name)),
            ))
            .id();

        // Spawn points
        for (point_idx, (point, virtue)) in layer
            .points
            .iter()
            .zip(layer.virtue_scores.iter())
            .enumerate()
        {
            let pos = Vec3::new(point.position[0], point.position[1], point.position[2]);

            // Scale by virtue (higher virtue = larger)
            let base_scale = 0.1 + virtue * 0.15;

            // Alpha by coherence (lower coherence = more transparent)
            let alpha = 0.3 + point.coherence * 0.7;

            // Create point-specific material with coherence-based alpha
            let point_material = materials.add(StandardMaterial {
                base_color: Color::srgba(
                    layer.color_hint[0],
                    layer.color_hint[1],
                    layer.color_hint[2],
                    alpha,
                ),
                emissive: LinearRgba::new(
                    layer.color_hint[0] * virtue * 0.5,
                    layer.color_hint[1] * virtue * 0.5,
                    layer.color_hint[2] * virtue * 0.5,
                    1.0,
                ),
                alpha_mode: if alpha < 1.0 {
                    AlphaMode::Blend
                } else {
                    AlphaMode::Opaque
                },
                ..default()
            });

            let point_entity = commands
                .spawn((
                    PbrBundle {
                        mesh: vis_meshes.point_mesh.clone(),
                        material: point_material,
                        transform: Transform::from_translation(pos)
                            .with_scale(Vec3::splat(base_scale)),
                        ..default()
                    },
                    PointEntity {
                        layer_index: layer_idx,
                        point_index: point_idx,
                        coherence: point.coherence,
                        virtue: *virtue,
                    },
                    Name::new(format!("Point-{}-{}", layer_idx, point_idx)),
                ))
                .id();

            // Parent to layer
            commands.entity(layer_entity).add_child(point_entity);

            // Add coherence ring for low-coherence points
            if point.coherence < 0.7 {
                commands.spawn((
                    PbrBundle {
                        mesh: vis_meshes.ring_mesh.clone(),
                        material: vis_materials.low_coherence_material.clone(),
                        transform: Transform::from_translation(pos)
                            .with_scale(Vec3::splat(base_scale * 2.0)),
                        ..default()
                    },
                    CoherenceRing { point_entity },
                ));
            }
        }
    }

    tracing::info!(
        "Rebuilt visualization: {} layers, {} points",
        response.layers.len(),
        response.metadata.points_displayed
    );
}

/// Animate points with subtle pulsing based on virtue
fn animate_points(time: Res<Time>, mut query: Query<(&PointEntity, &mut Transform)>) {
    let t = time.elapsed_seconds();

    for (point, mut transform) in query.iter_mut() {
        // Pulse scale based on virtue
        let pulse = 1.0 + (t * 2.0 + point.point_index as f32 * 0.1).sin() * 0.05 * point.virtue;
        let base_scale = 0.1 + point.virtue * 0.15;
        transform.scale = Vec3::splat(base_scale * pulse);
    }
}

/// Update coherence ring rotation
fn update_coherence_rings(time: Res<Time>, mut query: Query<&mut Transform, With<CoherenceRing>>) {
    let t = time.elapsed_seconds();

    for mut transform in query.iter_mut() {
        transform.rotation = Quat::from_rotation_y(t * 0.5) * Quat::from_rotation_x(t * 0.3);
    }
}
