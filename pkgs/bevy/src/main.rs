use bevy::{
    prelude::*,
    window::WindowResized,
    reflect::TypePath,
    render::render_resource::{AsBindGroup, ShaderRef},
    sprite::{Material2d, Material2dPlugin},
};

const SHADER_ASSET_PATH: &str = "shaders/animate_shader.wgsl";


fn main() {
    App::new()
        .add_plugins((
            DefaultPlugins,
            Material2dPlugin::<CustomMaterial>::default(),
        ))
        .add_systems(Startup, setup)
        .add_systems(Update, ( resize_rectangle_system, update_shader).chain() )
        .run();
}


fn resize_rectangle_system(
    mut resize_reader: EventReader<WindowResized>,
    mut rect_query: Query<&mut Transform, With<Mesh2d>>,
) {
    for e in resize_reader.read() {
        // Update the rectangle to fill the entire window
        for mut transform in &mut rect_query {
            // Scale a unit rectangle to window size
            transform.scale = Vec3::new(e.width, e.height, 1.0);

            // Position it at the center (0, 0)
            transform.translation = Vec3::new(0.0, 0.0, 0.0);

            println!("Resized to: {} x {}", e.width, e.height);
        }
    }
}


fn update_shader(
    mut materials: ResMut<Assets<CustomMaterial>>,
    time: Res<Time>,
    window: Query<&Window>,
    material_query: Query<&MeshMaterial2d<CustomMaterial>>,
) {
    let window = window.single();
    let cursor_position = window.cursor_position().unwrap_or_default();

    let normalized_pos = Vec2::new(
        cursor_position.x / window.width(),
        cursor_position.y / window.height(),
    );

    for mesh_material in material_query.iter() {
        if let Some(material) = materials.get_mut(&mesh_material.0) {
            material.time = time.elapsed_secs_f64() as f32;
            material.mouse_pos = normalized_pos;
            material.aspect_ratio = window.width() / window.height();
        }
    }
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<CustomMaterial>>,
    asset_server: Res<AssetServer>,
    time: Res<Time>,
    window: Query<&Window>,
) {
    commands.spawn(Camera2d);

    let window = window.single();
    // We'll size/position this rectangle in a separate system. For now just
    // spawn at unit size and default transform:
    commands.spawn((
        Mesh2d(meshes.add(Rectangle::default())),
        MeshMaterial2d(materials.add(CustomMaterial {
            color: LinearRgba::BLUE,
            mouse_pos: Vec2::ZERO,
            time: time.elapsed_secs_f64() as f32,
            aspect_ratio: window.width() / window.height(),
            color_texture: Some(asset_server.load("textures/image.png")),
        })),
        Transform::default()
            .with_scale(Vec3::new(10., 10., 1.0))
            .with_translation(Vec3::ZERO),
    ));
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
struct CustomMaterial {

    #[uniform(0)]
    time: f32,

    #[uniform(1)]
    aspect_ratio: f32,

    #[texture(2)]
    #[sampler(3)]
    color_texture: Option<Handle<Image>>,

    #[uniform(4)]
    mouse_pos: Vec2,

    #[uniform(5)]
    color: LinearRgba,

}

impl Material2d for CustomMaterial {
    fn fragment_shader() -> ShaderRef {
        SHADER_ASSET_PATH.into()
    }
}
