// Original marbled green display. Only the screen substrate moves; UI stays sharp.
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;
uniform sampler2D sprite_map : source_color, filter_nearest, repeat_enable;
uniform sampler2D cookie_map : filter_linear, repeat_enable;
uniform float cookie_time = 0.0;
uniform float flow_time = 0.0;
uniform float vortex_strength = 0.0;
uniform float flow_rotation = 0.0;
uniform float gesture_spin = 0.0;
uniform vec4 gesture_motion = vec4(0.0);
// UV position, followed by direction multiplied by the point's fading weight.
uniform vec4 stir_1 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 stir_2 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 stir_3 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 stir_4 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 stir_5 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 stir_6 = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec2 panel_pixels = vec2(370.0, 458.0);
varying vec2 light_uv;

vec2 stirWarp(vec2 samplePos, vec4 stir) {
    vec2 center = (stir.xy - vec2(0.5)) * vec2(panel_pixels.x / panel_pixels.y, 1.0) * 2.4;
    vec2 delta = samplePos - center;
    // A bounded local push and paired curl. No extra texture pass or allocation.
    float falloff = 1.0 / (1.0 + dot(delta, delta) * 7.0);
    float curl = delta.x * stir.w - delta.y * stir.z;
    return stir.zw * falloff * 0.20
        + vec2(-delta.y, delta.x) * curl * falloff * falloff * 0.55;
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    light_uv = vec2(dot(world, vec3(0.8,0.0,-0.6)), dot(world, vec3(0.350582,0.811534,0.467443)));
}

void fragment() {
    // One field across both screen-5 planes, sampled at two design pixels.
    // These are panel UVs, not the sprite's repeated tile coordinates.
    vec2 grid = panel_pixels * 0.5;
    vec2 uv = (floor(UV * grid) + vec2(0.5)) / grid;
    vec2 p = (uv - vec2(0.5)) * vec2(panel_pixels.x / panel_pixels.y, 1.0) * 2.4;
    // Physics uses +Y up; display UVs use +Y down. Steering affects only this field.
    vec2 direction = vec2(gesture_motion.x, -gesture_motion.y);
    vec2 impulse = vec2(gesture_motion.z, -gesture_motion.w);
    float strength = length(direction);
    vec2 axis = direction / max(strength, 0.0001);
    vec2 pushed = p - direction * 0.14 - impulse * 0.10;
    pushed -= axis * dot(p, axis) * strength * 0.18;
    pushed -= stirWarp(p, stir_1) + stirWarp(p, stir_2) + stirWarp(p, stir_3)
        + stirWarp(p, stir_4) + stirWarp(p, stir_5) + stirWarp(p, stir_6);
    float radius = length(p);
    // Radial differential rotation forms a vortex without an atan seam/core singularity.
    // Keep accumulated rotation independent of strength, so changing strength
    // after a long idle cannot cause a phase jump.
    // Signed turning changes the curl's handedness. Rotation is integrated on CPU,
    // so reversing direction never multiplies the whole accumulated animation time.
    float handedness = gesture_spin + 0.35 * (1.0 - abs(gesture_spin));
    float turn = vortex_strength * handedness * 5.0 / (0.35 + radius) + flow_rotation;
    float c = cos(turn);
    float s = sin(turn);
    vec2 q = vec2(c * pushed.x - s * pushed.y, s * pushed.x + c * pushed.y);
    // Broad, warped ink ribbons, rather than high-frequency random noise.
    q += vec2(sin(q.y * 2.7 + flow_time * 0.7),
        cos(q.x * 2.3 - flow_time * 0.6)) * 0.28;
    float fold = sin(q.y * 3.1 + sin(q.x * 2.4 - flow_time * 0.5) * 1.3);
    float ribbon = 0.5 + 0.5 * sin(q.x * 3.5 + q.y * 1.6 + fold * 1.8 + flow_time * 0.8);
    float detail = 0.5 + 0.5 * sin(q.y * 4.3 - q.x * 1.4 + fold + flow_time * 0.45);
    float field = ribbon * 0.82 + detail * 0.18;
    vec3 deep = vec3(0.004, 0.023, 0.014);
    vec3 green = vec3(0.007, 0.050, 0.029);
    vec3 light = vec3(0.017, 0.088, 0.047);
    vec3 color = mix(deep, green, smoothstep(0.12, 0.62, field));
    color = mix(color, light, smoothstep(0.60, 0.96, field) * 0.72);
    // Keep a trace of the original display texture, beneath the shared CRT post pass.
    vec3 substrate = texture(sprite_map, UV * panel_pixels / vec2(92.0, 90.0)).rgb;
    color = mix(color, substrate, 0.06);
    ALBEDO = mix(vec3(dot(color, vec3(0.2126,0.7152,0.0722))), color, 0.85);
    ALPHA = 1.0;
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}

// Same light/cookie/shadow contract as the existing layered sprites.
void light() {
    vec2 cookieUV = (light_uv - (vec2(4.0,2.0) + cookie_time * vec2(0.0,-3.5) * 0.25)) / vec2(22.0,30.0) + vec2(0.5);
    float cookie = texture(cookie_map, cookieUV).r;
    float hardShadow = mix(0.18, 1.0, step(0.6, ATTENUATION));
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * hardShadow * max(dot(NORMAL,LIGHT), 0.0) * cookie;
}
