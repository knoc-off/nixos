use bevy::{
    prelude::*,
    window::WindowResized,
    reflect::TypePath,
    render::render_resource::{AsBindGroup, ShaderRef},
    sprite::{Material2d, Material2dPlugin},
};

use bevy_render::render_resource::Extent3d;
use bevy_render::render_resource::TextureDimension;
use bevy_render::render_resource::TextureFormat;
use bevy_render::render_asset::RenderAssetUsages;
use bevy_render::render_resource::TextureUsages;


const SHADER_ASSET_PATH: &str = "shaders/animate_shader.wgsl";

#[derive(Resource)]
struct AnimateTextures {
    texture_a: Handle<Image>,
    texture_b: Handle<Image>,
    initial_texture: Handle<Image>,
}

// Modify main to include initialization
fn main() {
    App::new()
        .add_plugins((
            DefaultPlugins,
            Material2dPlugin::<CustomMaterial>::default(),
        ))
        .add_systems(Startup, setup)
        .add_systems(Update, (
            initialize_render_textures,
            resize_rectangle_system,
            update_shader,
            switch_textures,
        ).chain())
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

fn initialize_render_textures(
    mut images: ResMut<Assets<Image>>,
    textures: Res<AnimateTextures>,
    mut initialized: Local<bool>,
) {
    if *initialized {
        return;
    }

    // First clone the initial image data
    let initial_image = if let Some(img) = images.get(&textures.initial_texture) {
        if img.texture_descriptor.size.width == 0 {
            return; // Image not loaded yet
        }
        img.clone()
    } else {
        return; // Image not available yet
    };

    // Then update both render textures
    images.insert(&textures.texture_a.clone(), initial_image.clone());
    images.insert(&textures.texture_b.clone(), initial_image);

    *initialized = true;
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<CustomMaterial>>,
    mut images: ResMut<Assets<Image>>,
    asset_server: Res<AssetServer>,
    time: Res<Time>,
    window: Query<&Window>,
) {
    commands.spawn(Camera2d);
    let window = window.single();

    // Load initial image
    let initial_texture = asset_server.load("textures/image.png");

    // Create render textures for ping-pong
    let mut render_texture = Image::new_fill(
        Extent3d {
            width: window.width() as u32,
            height: window.height() as u32,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[0, 0, 0, 255],
        TextureFormat::Rgba8Unorm,
        RenderAssetUsages::RENDER_WORLD,
    );

    // Set up texture usage flags
    render_texture.texture_descriptor.usage =
        TextureUsages::COPY_DST
        | TextureUsages::STORAGE_BINDING
        | TextureUsages::TEXTURE_BINDING
        | TextureUsages::RENDER_ATTACHMENT;

    let texture_a = images.add(render_texture.clone());
    let texture_b = images.add(render_texture);

    commands.insert_resource(AnimateTextures {
        texture_a: texture_a.clone(),
        texture_b: texture_b.clone(),
        initial_texture: initial_texture.clone(),
    });

    // Spawn the main sprite with initial texture
    commands.spawn((
        Mesh2d(meshes.add(Rectangle::default())),
        MeshMaterial2d(materials.add(CustomMaterial {
            color: LinearRgba::BLUE,
            mouse_pos: Vec2::ZERO,
            time: time.elapsed_secs_f64() as f32,
            aspect_ratio: window.width() / window.height(),
            color_texture: Some(initial_texture),
        })),
        Transform::default()
            .with_scale(Vec3::new(10., 10., 1.0))
            .with_translation(Vec3::ZERO),
    ));
}


fn switch_textures(
    textures: Res<AnimateTextures>,
    mut images: ResMut<Assets<Image>>,
    mut materials: ResMut<Assets<CustomMaterial>>,
    material_query: Query<&MeshMaterial2d<CustomMaterial>>,
) {
    for mesh_material in material_query.iter() {
        if let Some(material) = materials.get_mut(&mesh_material.0) {
            // Get the current texture
            let current_texture = if material.color_texture == Some(textures.texture_a.clone()) {
                &textures.texture_a
            } else {
                &textures.texture_b
            };

            // Clone the current frame first
            let current_image = if let Some(img) = images.get(current_texture) {
                img.clone()
            } else {
                continue;
            };

            // Determine next texture
            let next_texture = if current_texture == &textures.texture_a {
                &textures.texture_b
            } else {
                &textures.texture_a
            };

            // Update the next texture with current frame
            images.insert(&next_texture.clone(), current_image);

            // Switch the material to use the next texture
            material.color_texture = Some(next_texture.clone());
        }
    }
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
