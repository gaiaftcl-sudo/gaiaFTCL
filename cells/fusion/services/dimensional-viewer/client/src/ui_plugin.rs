//! UI Plugin for Dimensional Viewer
//!
//! Provides overlay UI showing:
//! - Connection status
//! - Coherence metrics
//! - Virtue pass rate
//! - Dimension mapping
//! - Layer information

use bevy::prelude::*;

use crate::websocket_plugin::ViewState;

/// Marker for connection status text
#[derive(Component)]
pub struct ConnectionStatusText;

/// Marker for coherence display
#[derive(Component)]
pub struct CoherenceText;

/// Marker for virtue display
#[derive(Component)]
pub struct VirtueText;

/// Marker for dimension map display
#[derive(Component)]
pub struct DimensionText;

/// Marker for layer info display
#[derive(Component)]
pub struct LayerInfoText;

pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_ui)
            .add_systems(Update, (update_connection_status, update_metrics_display));
    }
}

/// Create the UI layout
fn setup_ui(mut commands: Commands) {
    // Root container
    commands
        .spawn(NodeBundle {
            style: Style {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                justify_content: JustifyContent::SpaceBetween,
                padding: UiRect::all(Val::Px(16.0)),
                ..default()
            },
            ..default()
        })
        .with_children(|parent| {
            // Top bar
            parent
                .spawn(NodeBundle {
                    style: Style {
                        width: Val::Percent(100.0),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        ..default()
                    },
                    ..default()
                })
                .with_children(|parent| {
                    // Title and dimension info
                    parent
                        .spawn(NodeBundle {
                            style: Style {
                                flex_direction: FlexDirection::Column,
                                ..default()
                            },
                            ..default()
                        })
                        .with_children(|parent| {
                            parent.spawn(TextBundle::from_section(
                                "GaiaOS Dimensional Viewer",
                                TextStyle {
                                    font_size: 24.0,
                                    color: Color::WHITE,
                                    ..default()
                                },
                            ));

                            parent.spawn((
                                TextBundle::from_section(
                                    "Dimensions: [0, 2, 5]",
                                    TextStyle {
                                        font_size: 14.0,
                                        color: Color::srgb(0.7, 0.7, 0.7),
                                        ..default()
                                    },
                                ),
                                DimensionText,
                            ));
                        });

                    // Connection status
                    parent.spawn((
                        TextBundle::from_section(
                            "Connecting...",
                            TextStyle {
                                font_size: 16.0,
                                color: Color::srgb(1.0, 0.8, 0.2),
                                ..default()
                            },
                        ),
                        ConnectionStatusText,
                    ));
                });

            // Right side metrics panel
            parent
                .spawn(NodeBundle {
                    style: Style {
                        position_type: PositionType::Absolute,
                        right: Val::Px(16.0),
                        top: Val::Px(60.0),
                        flex_direction: FlexDirection::Column,
                        padding: UiRect::all(Val::Px(12.0)),
                        ..default()
                    },
                    background_color: Color::srgba(0.0, 0.0, 0.0, 0.7).into(),
                    ..default()
                })
                .with_children(|parent| {
                    parent.spawn(TextBundle::from_section(
                        "METRICS",
                        TextStyle {
                            font_size: 12.0,
                            color: Color::srgb(0.5, 0.5, 0.5),
                            ..default()
                        },
                    ));

                    parent.spawn((
                        TextBundle::from_section(
                            "Coherence: --",
                            TextStyle {
                                font_size: 16.0,
                                color: Color::srgb(0.4, 0.8, 1.0),
                                ..default()
                            },
                        ),
                        CoherenceText,
                    ));

                    parent.spawn((
                        TextBundle::from_section(
                            "Virtue Pass: --",
                            TextStyle {
                                font_size: 16.0,
                                color: Color::srgb(0.2, 1.0, 0.4),
                                ..default()
                            },
                        ),
                        VirtueText,
                    ));

                    parent.spawn((
                        TextBundle::from_section(
                            "Layers: --",
                            TextStyle {
                                font_size: 14.0,
                                color: Color::srgb(0.8, 0.8, 0.8),
                                ..default()
                            },
                        ),
                        LayerInfoText,
                    ));
                });

            // Bottom info bar
            parent
                .spawn(NodeBundle {
                    style: Style {
                        width: Val::Percent(100.0),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        padding: UiRect::all(Val::Px(8.0)),
                        ..default()
                    },
                    background_color: Color::srgba(0.0, 0.0, 0.0, 0.5).into(),
                    ..default()
                })
                .with_children(|parent| {
                    parent.spawn(TextBundle::from_section(
                        "8D → 3D Quantum Projection | Virtue-Gated via Franklin Guardian",
                        TextStyle {
                            font_size: 12.0,
                            color: Color::srgb(0.6, 0.6, 0.6),
                            ..default()
                        },
                    ));

                    parent.spawn(TextBundle::from_section(
                        "LMB: Rotate | RMB: Pan | Scroll: Zoom",
                        TextStyle {
                            font_size: 12.0,
                            color: Color::srgb(0.5, 0.5, 0.5),
                            ..default()
                        },
                    ));
                });
        });
}

/// Update connection status display
fn update_connection_status(
    view_state: Res<ViewState>,
    mut query: Query<&mut Text, With<ConnectionStatusText>>,
) {
    let Ok(mut text) = query.get_single_mut() else {
        return;
    };

    if view_state.connected {
        text.sections[0].value = "● Connected".to_string();
        text.sections[0].style.color = Color::srgb(0.2, 1.0, 0.4);
    } else {
        text.sections[0].value = "○ Disconnected".to_string();
        text.sections[0].style.color = Color::srgb(1.0, 0.4, 0.2);
    }
}

/// Update metrics display
fn update_metrics_display(
    view_state: Res<ViewState>,
    mut coherence_query: Query<
        &mut Text,
        (
            With<CoherenceText>,
            Without<VirtueText>,
            Without<DimensionText>,
            Without<LayerInfoText>,
        ),
    >,
    mut virtue_query: Query<
        &mut Text,
        (
            With<VirtueText>,
            Without<CoherenceText>,
            Without<DimensionText>,
            Without<LayerInfoText>,
        ),
    >,
    mut dimension_query: Query<
        &mut Text,
        (
            With<DimensionText>,
            Without<CoherenceText>,
            Without<VirtueText>,
            Without<LayerInfoText>,
        ),
    >,
    mut layer_query: Query<
        &mut Text,
        (
            With<LayerInfoText>,
            Without<CoherenceText>,
            Without<VirtueText>,
            Without<DimensionText>,
        ),
    >,
) {
    let meta = &view_state.response.metadata;

    // Update coherence
    if let Ok(mut text) = coherence_query.get_single_mut() {
        text.sections[0].value = format!(
            "Coherence: {:.0}% (min {:.0}%, max {:.0}%)",
            meta.avg_coherence * 100.0,
            meta.min_coherence * 100.0,
            meta.max_coherence * 100.0
        );

        // Color based on coherence level
        text.sections[0].style.color = if meta.avg_coherence >= 0.85 {
            Color::srgb(0.2, 1.0, 0.4) // Green - good
        } else if meta.avg_coherence >= 0.70 {
            Color::srgb(1.0, 0.8, 0.2) // Yellow - warning
        } else {
            Color::srgb(1.0, 0.4, 0.2) // Red - low
        };
    }

    // Update virtue
    if let Ok(mut text) = virtue_query.get_single_mut() {
        text.sections[0].value = format!(
            "Virtue Pass: {:.1}% ({}/{})",
            meta.virtue_pass_rate * 100.0,
            meta.points_displayed,
            meta.total_points_8d
        );
    }

    // Update dimension map
    if let Ok(mut text) = dimension_query.get_single_mut() {
        text.sections[0].value = format!(
            "Dimensions: [{}, {}, {}] | Threshold: {:.0}%",
            meta.dimension_map[0],
            meta.dimension_map[1],
            meta.dimension_map[2],
            meta.virtue_threshold * 100.0
        );
    }

    // Update layer info
    if let Ok(mut text) = layer_query.get_single_mut() {
        let layer_names: Vec<&str> = view_state
            .response
            .layers
            .iter()
            .map(|l| l.name.as_str())
            .collect();

        text.sections[0].value = format!(
            "Layers: {} ({})",
            view_state.response.layers.len(),
            layer_names.join(", ")
        );
    }
}
