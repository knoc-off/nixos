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

    // Spiral control parameters
    let swirl_strength = mouse_position.y * 15;
    let swirl_speed = 1.0;      // Rotation speed

    // Convert to polar coordinates for spiral calculation
    let diff = uv_corr - center_corr;
    let r = length(diff);
    var theta = atan2(diff.y, diff.x);

    // Apply spiral transformation
    theta = theta + swirl_strength * r + swirl_speed * time;

    // Convert back to Cartesian coordinates
    let swirl_corr_x = r * cos(theta) + center_corr.x;
    let swirl_corr_y = r * sin(theta) + center_corr.y;
    let swirl_uv = vec2<f32>(swirl_corr_x / aspect_ratio, swirl_corr_y);

    // Store warped coordinates for effects
    let uv_corr_warped = vec2<f32>(swirl_uv.x * aspect_ratio, swirl_uv.y);
    let diff_warped = uv_corr_warped - center_corr;
    let dist_warped = length(diff_warped);
    let angle_warped = atan2(diff_warped.y, diff_warped.x);

    // Debug visualization zones
    if (uv_corr.x < 0.1 && uv_corr.y < 0.1) {
        return vec4<f32>(uv_corr.x * 10.0, uv_corr.y * 10.0, 0.0, 1.0);
    }
    if (uv_corr.x >= 0.1 && uv_corr.x < 0.2 && uv_corr.y < 0.1) {
        return vec4<f32>(uv_corr_warped.x * 10.0, uv_corr_warped.y * 10.0, 0.0, 1.0);
    }
    if (uv_corr.x >= 0.2 && uv_corr.x < 0.3 && uv_corr.y < 0.1) {
        let scaled_dist = clamp(dist_warped * 3.0, 0.0, 1.0);
        return vec4<f32>(scaled_dist, scaled_dist, scaled_dist, 1.0);
    }

    // Center crosshair
    let crosshair_size = 0.002;
    if (abs(diff_warped.x) < crosshair_size || abs(diff_warped.y) < crosshair_size) {
        if (dist_warped < 0.05) {
            return vec4<f32>(0.0, 1.0, 0.0, 1.0);
        }
    }

    // Color generation using warped coordinates
    let r_chan = 0.5 + 0.5 * sin(dist_warped * 15.0 + angle_warped * 3.0 - time * 2.0);
    let g_chan = 0.5 + 0.5 * sin(dist_warped * 15.0 - angle_warped * 3.0 - time * 2.0);
    let b_chan = 0.5 + 0.5 * cos(dist_warped * 20.0 - angle_warped * 5.0 - time * 3.0);
    var swirl_color = vec4<f32>(r_chan, g_chan, b_chan, 1.0);

    // Apply material color and return
    return swirl_color * material_color;
}
