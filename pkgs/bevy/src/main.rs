use bevy::{
    prelude::*,
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
        .add_systems(Update, update_shader)
        .run();
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
        (cursor_position.x / window.width()) * 2.0 - 1.0,
        (cursor_position.y / window.height()) * 2.0 - 1.0,
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
    time: Res<Time>,
    window: Query<&Window>,
) {
    commands.spawn(Camera2d);

    let window = window.single();
    let width = window.width();
    let height = window.height();

    commands.spawn((
        Mesh2d(meshes.add(Rectangle::default())),
        MeshMaterial2d(materials.add(CustomMaterial {
            color: LinearRgba::BLUE,
            mouse_pos: Vec2::new(0.0, 0.0),
            time: time.elapsed_secs_f64() as f32,
            aspect_ratio: width / height,
        })),
        Transform::default()
            .with_scale(Vec3::new(width, height, 1.0))
            .with_translation(Vec3::new(0.0, 0.0, 0.0)),
    ));
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
struct CustomMaterial {
    #[uniform(0)]
    color: LinearRgba,
    #[uniform(1)]
    mouse_pos: Vec2,
    #[uniform(2)]
    time: f32,
    #[uniform(3)]
    aspect_ratio: f32,
}

impl Material2d for CustomMaterial {
    fn fragment_shader() -> ShaderRef {
        SHADER_ASSET_PATH.into()
    }
}
