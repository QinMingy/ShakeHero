shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled;

uniform sampler2D body_map : source_color, filter_nearest, repeat_disable;
uniform vec4 mood_tint : source_color = vec4(1.0);

void fragment() {
    vec4 ink = texture(body_map, UV);
    vec2 drift = vec2(0.10 * sin(TIME * 0.36), 0.025 * cos(TIME * 0.23));
    vec2 spot = (UV - vec2(0.24, 0.83) - drift) * vec2(1.0, 1.65);
    float lamp = exp(-dot(spot, spot) * 7.0);
    float edge_shadow = smoothstep(0.02, 0.19, UV.x) *
        (1.0 - smoothstep(0.82, 0.99, UV.x));
    ALBEDO = ink.rgb * mood_tint.rgb * (0.82 + 0.27 * lamp + 0.13 * edge_shadow) +
        vec3(0.025, 0.014, 0.003) * lamp;
    ALPHA = ink.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
