#import bevy_sprite::mesh2d_vertex_output::VertexOutput

@group(2) @binding(0) var<uniform> time: f32;
@group(2) @binding(1) var<uniform> aspect_ratio: f32;
@group(2) @binding(2) var base_color_texture: texture_2d<f32>;
@group(2) @binding(3) var base_color_sampler: sampler;
@group(2) @binding(4) var<uniform> mouse_position: vec2<f32>;
@group(2) @binding(5) var<uniform> material_color: vec4<f32>;

@fragment
fn fragment(mesh: VertexOutput) -> @location(0) vec4<f32> {
    // Standard UV coordinates with aspect ratio correction
    let uv = mesh.uv;
    let center = mouse_position;
    let uv_corr = vec2<f32>(uv.x * aspect_ratio, uv.y);
    let center_corr = vec2<f32>(center.x * aspect_ratio, center.y);

    // Calculate distance for falloff
    let diff = uv_corr - center_corr;
    let r = length(diff);

    // Create a smooth falloff effect
    let max_radius = 0.5; // Maximum radius of effect
    let falloff = smoothstep(max_radius, 0.0, r);

    // Spiral control parameters with falloff
    let oscillation = sin(time * 2.0) * 0.5; // Oscillates between 0 and 1
    let swirl_strength = 25.0 * falloff * oscillation; // Apply time-based oscillation
    let swirl_speed = 0.0;

    var theta = atan2(diff.y, diff.x);

    // Apply spiral transformation
    theta = theta + swirl_strength * r;

    // Convert back to Cartesian coordinates
    let swirl_corr_x = r * cos(theta) + center_corr.x;
    let swirl_corr_y = r * sin(theta) + center_corr.y;
    let swirl_uv = vec2<f32>(swirl_corr_x / aspect_ratio, swirl_corr_y);

    // Sample texture with warped coordinates
    let texture_color = textureSample(base_color_texture, base_color_sampler, swirl_uv);


    // crosshair in the center,
    let crosshair = 0.001;
    let crosshair_x = abs(center_corr.x - uv_corr.x) < crosshair;
    let crosshair_y = abs(center_corr.y - uv_corr.y) < crosshair;
    if crosshair_x || crosshair_y {
        //return vec4<f32>(1.0, 0.0, 0.0, 1.0);
    }

    return texture_color; // * material_color;
}
