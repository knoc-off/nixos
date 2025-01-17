//! Displays a single [`Sprite`], created from an image.

use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(ImagePlugin::default_nearest())) // prevents blurry sprites
        .add_systems(Startup, setup)
        .add_systems(Update, animate_sprite)
        .add_systems(Update, move_snake)
        .run();
}

#[derive(Component, Clone, Copy)]
struct AnimationIndices {
    first: usize,
    last: usize,
}

enum Direction {
    Up,
    Down,
    Left,
    Right,
}

// arrow facing dir:
#[derive(Component)]
struct Snake {
    dir: Direction,
    length: u32,
    body: Vec<Entity>,
}

#[derive(Component)]
struct GridPosition {
    current: Vec2,
    target: Vec2,
    move_timer: Timer,
}

#[derive(Component, Deref, DerefMut)]
struct AnimationTimer(Timer);

fn animate_sprite(
    time: Res<Time>,
    mut query: Query<(&AnimationIndices, &mut AnimationTimer, &mut Sprite)>,
) {
    for (indices, mut timer, mut sprite) in &mut query {
        timer.tick(time.delta());

        if timer.just_finished() {
            if let Some(atlas) = &mut sprite.texture_atlas {
                atlas.index = if atlas.index == indices.last {
                    indices.first
                } else {
                    atlas.index + 1
                };
            }
        }
    }
}

fn setup(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut texture_atlas_layouts: ResMut<Assets<TextureAtlasLayout>>,
) {
    let dot = asset_server.load("textures/dot-sheet-X8.png");
    let arrow = asset_server.load("textures/arrow-sheet-X8.png");
    let layout = TextureAtlasLayout::from_grid(UVec2::splat(32), 8, 1, None, None);
    let texture_atlas_layout = texture_atlas_layouts.add(layout);
    let animation_indices = AnimationIndices { first: 1, last: 6 };

    commands.spawn(Camera2d);

    let mut body_segments = Vec::new();
    for i in 1..=3 {
        let segment = commands.spawn((
            Sprite::from_atlas_image(
                dot.clone(),
                TextureAtlas {
                    layout: texture_atlas_layout.clone(),
                    index: animation_indices.first,
                },
            ),
            Transform::from_xyz(0.0, -32.0 * i as f32, 0.0).with_scale(Vec3::splat(6.0)),
            animation_indices.clone(),
            AnimationTimer(Timer::from_seconds(0.1, TimerMode::Repeating)),
        )).id();
        body_segments.push(segment);
    }

    commands.spawn((
        Snake {
            dir: Direction::Up,
            length: 3,
            body: body_segments,
        },
        GridPosition {
            current: Vec2::ZERO,
            target: Vec2::new(0.0, 32.0), // One grid unit up
            move_timer: Timer::from_seconds(1.0, TimerMode::Repeating),
        },
        Sprite::from_atlas_image(
            arrow,
            TextureAtlas {
                layout: texture_atlas_layout,
                index: animation_indices.first,
            },
        ),
        Transform::from_scale(Vec3::splat(6.0)),
        animation_indices,
        AnimationTimer(Timer::from_seconds(0.1, TimerMode::Repeating)),
    ));
}

fn move_snake(
    time: Res<Time>,
    mut query: Query<(&mut Transform, &mut GridPosition, &Snake)>,
    mut body_query: Query<&mut Transform, Without<Snake>>,
) {
    for (mut transform, mut grid_pos, snake) in &mut query {
        grid_pos.move_timer.tick(time.delta());

        // Lerp current position to target
        let t = grid_pos.move_timer.elapsed_secs() / grid_pos.move_timer.duration().as_secs_f32();
        let new_pos = grid_pos.current.lerp(grid_pos.target, t);
        transform.translation = new_pos.extend(0.0);

        // When movement complete, set new target
        if grid_pos.move_timer.just_finished() {
            grid_pos.current = grid_pos.target;
            // Set new target based on direction
            grid_pos.target = match snake.dir {
                Direction::Up => grid_pos.current + Vec2::new(0.0, 32.0),
                Direction::Down => grid_pos.current + Vec2::new(0.0, -32.0),
                Direction::Left => grid_pos.current + Vec2::new(-32.0, 0.0),
                Direction::Right => grid_pos.current + Vec2::new(32.0, 0.0),
            };

            // Update body positions
            let mut prev_pos = grid_pos.current;
            for &body_entity in &snake.body {
                if let Ok(mut body_transform) = body_query.get_mut(body_entity) {
                    let current_pos = body_transform.translation.truncate();
                    body_transform.translation = prev_pos.extend(0.0);
                    prev_pos = current_pos;
                }
            }
        }
    }
}
