shader_type spatial;
render_mode shading_model_unlit, cull_disabled;

uniform sampler2D content_map : source_color, filter_linear, repeat_disable;
uniform float curvature = 0.04;
uniform float scanline_strength = 0.18;
uniform float bloom_strength = 0.38;
uniform float flip_y = 0.0;
uniform vec4 mood_glow : source_color = vec4(0.0);

vec3 sample_screen(vec2 uv) {
    vec2 tex_uv = vec2(uv.x, mix(uv.y, 1.0 - uv.y, flip_y));
    return texture(content_map, clamp(tex_uv, vec2(0.001), vec2(0.999))).rgb;
}

vec3 bright(vec2 uv) {
    vec3 color = sample_screen(uv);
    float peak = max(color.r, max(color.g, color.b));
    return color * smoothstep(0.35, 0.85, peak);
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    vec2 uv = (p * (1.0 + curvature * dot(p, p)) + 1.0) * 0.5;
    vec2 pixel = vec2(1.0 / 336.0, 1.0 / 448.0);
    vec3 color = sample_screen(uv);

    // Thresholded, two-radius blur: a restrained bloom confined to the glass.
    vec3 glow = bright(uv) * 0.16;
    glow += (bright(uv + vec2(pixel.x * 2.0, 0.0)) + bright(uv - vec2(pixel.x * 2.0, 0.0))
        + bright(uv + vec2(0.0, pixel.y * 2.0)) + bright(uv - vec2(0.0, pixel.y * 2.0))) * 0.12;
    glow += (bright(uv + pixel * 4.0) + bright(uv - pixel * 4.0)
        + bright(uv + vec2(pixel.x, -pixel.y) * 4.0)
        + bright(uv + vec2(-pixel.x, pixel.y) * 4.0)) * 0.09;
    float scan = 1.0 - scanline_strength * (0.5 + 0.5 * cos(uv.y * 448.0 * 3.14159265));
    float vignette = 1.0 - 0.19 * dot(p * 0.7071, p * 0.7071);
    float mask = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    color = (color * scan + glow * bloom_strength) * vignette;
    // A reflection at the glass rim changes with the room lighting;
    // the center of the gameplay image keeps its original palette.
    float rim = smoothstep(0.56, 1.25, length(p));
    color += mood_glow.rgb * mood_glow.a * rim * 0.12;
    ALBEDO = mix(vec3(0.008, 0.016, 0.009), color, mask);
}
