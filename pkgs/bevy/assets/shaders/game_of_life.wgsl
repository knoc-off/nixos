@group(0) @binding(0) var input: texture_storage_2d<r32float, read>;
@group(0) @binding(1) var output: texture_storage_2d<r32float, write>;

fn hash(value: u32) -> u32 {
    var state = value;
    state = state ^ 2747636419u;
    state = state * 2654435769u;
    state = state ^ state >> 16u;
    state = state * 2654435769u;
    state = state ^ state >> 16u;
    state = state * 2654435769u;
    return state;
}

fn randomFloat(value: u32) -> f32 {
    return f32(hash(value)) / 4294967295.0;
}

@compute @workgroup_size(8, 8, 1)
fn init(@builtin(global_invocation_id) invocation_id: vec3<u32>, @builtin(num_workgroups) num_workgroups: vec3<u32>) {
    let location = vec2<i32>(i32(invocation_id.x), i32(invocation_id.y));

    let randomNumber = randomFloat(invocation_id.y << 16u | invocation_id.x);
    let alive = randomNumber > 0.9;
    let color = vec4<f32>(f32(alive));

    textureStore(output, location, color);
}


// Fragment shader inputs must match the vertex shader outputs
// and the CustomMaterial definition.
struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

// Bindings must match CustomMaterial in main.rs
@group(1) @binding(0) var<uniform> time: f32;
@group(1) @binding(1) var<uniform> aspect_ratio: f32;
@group(1) @binding(2) var t_color: texture_2d<f32>;
@group(1) @binding(3) var s_color: sampler;
@group(1) @binding(4) var<uniform> mouse_pos: vec2<f32>;
@group(1) @binding(5) var<uniform> color: vec4<f32>; // Matches LinearRgba

@fragment
fn fragment(in: FragmentInput) -> @location(0) vec4<f32> {
    // Sample the texture provided by the material
    // Use the color uniform as a fallback or multiplier if needed
    return textureSample(t_color, s_color, in.uv) * color;
    // Or just return the texture color directly:
    // return textureSample(t_color, s_color, in.uv);
}

fn is_alive(location: vec2<i32>, offset_x: i32, offset_y: i32) -> i32 {
    let value: vec4<f32> = textureLoad(input, location + vec2<i32>(offset_x, offset_y));
    return i32(value.x);
}

fn count_alive(location: vec2<i32>) -> i32 {
    return is_alive(location, -1, -1) +
           is_alive(location, -1,  0) +
           is_alive(location, -1,  1) +
           is_alive(location,  0, -1) +
           is_alive(location,  0,  1) +
           is_alive(location,  1, -1) +
           is_alive(location,  1,  0) +
           is_alive(location,  1,  1);
}

@compute @workgroup_size(8, 8, 1)
fn update(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    let location = vec2<i32>(i32(invocation_id.x), i32(invocation_id.y));

    let n_alive = count_alive(location);

    var alive: bool;
    if (n_alive == 3) {
        alive = true;
    } else if (n_alive == 2) {
        let currently_alive = is_alive(location, 0, 0);
        alive = bool(currently_alive);
    } else {
        alive = false;
    }
    let color = vec4<f32>(f32(alive));

    textureStore(output, location, color);
}
