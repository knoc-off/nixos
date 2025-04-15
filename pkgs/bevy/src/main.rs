use bevy::{
    prelude::*,
    input::mouse::MouseWheel,
};

const GRID_SIZE: f32 = 20.0;
const GRID_SPACING: f32 = 1.0;
const CAMERA_MOVE_SPEED: f32 = 10.0;
const CAMERA_ZOOM_SPEED: f32 = 1.0;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Startup, setup)
        .add_systems(Update, (draw_grid, camera_controls))
        .run();
}

fn setup(mut commands: Commands) {
    // Spawn the camera
    commands.spawn((
        Camera3d::default(), // Use Camera3d component directly
        Transform::from_xyz(0.0, 10.0, 0.0).looking_at(Vec3::ZERO, Vec3::Z),
        Projection::Orthographic(OrthographicProjection {
            scale: 10.0,
            far: 1000.0,
            near: -1000.0,
            area: Rect::new(-1.0, -1.0, 1.0, 1.0),
        }),
    ));

    // Add lighting
    commands.spawn((
        PointLight { // Use PointLight component directly
            intensity: 1500.0,
            shadows_enabled: true,
            ..default() // PointLight itself implements Default
        },
        Transform::from_xyz(4.0, 8.0, 4.0),
    ));
}

fn draw_grid(mut gizmos: Gizmos) {
    let half_size = GRID_SIZE / 2.0;
    let color = Color::rgb(0.3, 0.3, 0.3); // Use a valid color constant

    for i in 0..=(GRID_SIZE / GRID_SPACING) as i32 {
        let pos = -half_size + i as f32 * GRID_SPACING;

        // Draw lines along X axis
        gizmos.line(
            Vec3::new(-half_size, 0.0, pos),
            Vec3::new(half_size, 0.0, pos),
            color,
        );

        // Draw lines along Z axis
        gizmos.line(
            Vec3::new(pos, 0.0, -half_size),
            Vec3::new(pos, 0.0, half_size),
            color,
        );
    }
}

fn camera_controls(
    time: Res<Time>,
    keyboard_input: Res<ButtonInput<KeyCode>>,
    mut mouse_wheel_events: EventReader<MouseWheel>,
    mut query: Query<(&mut Transform, &mut Projection), With<Camera>>,
) {
    let (mut transform, mut projection) = query.single_mut();
    let mut direction = Vec3::ZERO;

    if keyboard_input.pressed(KeyCode::KeyW) {
        direction -= Vec3::Z; // Move forward (along -Z in camera space, which is world -Z)
    }
    if keyboard_input.pressed(KeyCode::KeyS) {
        direction += Vec3::Z; // Move backward
    }
    if keyboard_input.pressed(KeyCode::KeyA) {
        direction -= Vec3::X; // Move left
    }
    if keyboard_input.pressed(KeyCode::KeyD) {
        direction += Vec3::X; // Move right
    }

    if direction.length_squared() > 0.0 {
        direction = direction.normalize();
        transform.translation += direction * CAMERA_MOVE_SPEED * time.delta_secs(); // Use delta_secs()
    }

    // Handle zoom with mouse wheel
    if let Projection::Orthographic(ref mut ortho) = *projection {
        for event in mouse_wheel_events.read() {
            let scroll_amount = event.y;
            ortho.scale -= scroll_amount * CAMERA_ZOOM_SPEED * time.delta_secs(); // Use delta_secs()
            ortho.scale = ortho.scale.max(0.1); // Prevent scale from becoming zero or negative
        }
    }
}
