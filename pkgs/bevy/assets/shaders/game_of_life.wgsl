#import bevy_sprite::mesh2d_vertex_output::VertexOutput

@group(2) @binding(0) var<uniform> time: f32;
@group(2) @binding(1) var previous_state: texture_2d<f32>;
@group(2) @binding(2) var state_sampler: sampler;

fn get_cell(uv: vec2<f32>) -> f32 {
    return textureSample(previous_state, state_sampler, uv).r;
}

fn count_neighbors(uv: vec2<f32>) -> i32 {
    let pixel_size = vec2<f32>(1.0 / 512.0);
    var count = 0;
    
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            if (i == 0 && j == 0) { continue; }
            
            let neighbor = uv + vec2<f32>(
                f32(i) * pixel_size.x,
                f32(j) * pixel_size.y
            );
            
            count += i32(get_cell(neighbor) > 0.5);
        }
    }
    
    return count;
}

@fragment
fn fragment(mesh: VertexOutput) -> @location(0) vec4<f32> {
    let current = get_cell(mesh.uv);
    let neighbors = count_neighbors(mesh.uv);
    
    var next = 0.0;
    if (current > 0.5) {
        // Cell is alive
        if (neighbors == 2 || neighbors == 3) {
            next = 1.0;
        }
    } else {
        // Cell is dead
        if (neighbors == 3) {
            next = 1.0;
        }
    }
    
    return vec4<f32>(next, next, next, 1.0);
}
