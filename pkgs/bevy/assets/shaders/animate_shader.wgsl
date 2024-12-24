#import bevy_sprite::mesh2d_vertex_output::VertexOutput;

@group(2) @binding(0) var<uniform> material_color: vec4<f32>;
@group(2) @binding(1) var<uniform> mouse_position: vec2<f32>;
@group(2) @binding(2) var<uniform> time: f32;
@group(2) @binding(3) var<uniform> aspect_ratio: f32;

@fragment
fn fragment(mesh: VertexOutput) -> @location(0) vec4<f32> {
    // Adjust UV coordinates for aspect ratio
    let corrected_uv = vec2<f32>(mesh.uv.x, mesh.uv.y);
    
    // Adjust mouse position to match the corrected UV space
    let corrected_mouse = vec2<f32>(
        mouse_position.x,
        mouse_position.y
    );
    
    let dist = distance(corrected_uv, corrected_mouse);
    
    // Create a falloff effect - closer to cursor is more intense
    let intensity = 1.0 - smoothstep(0.0, 0.1, dist);
    
    return material_color * intensity;
}
