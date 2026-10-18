shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D label_map : source_color, filter_linear, repeat_disable;
uniform float flip_y = 0.0;

void fragment() {
    vec2 uv = vec2(UV.x, mix(UV.y, 1.0 - UV.y, flip_y));
    ALBEDO = texture(label_map, uv).rgb;
    ALPHA = 1.0;
}
