shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D label_map : source_color, filter_linear, repeat_disable;
uniform float flip_y = 0.0;
uniform vec4 face_color : source_color = vec4(0.66, 0.55, 0.32, 1.0);
uniform vec4 recess_color : source_color = vec4(0.08, 0.07, 0.04, 1.0);

void fragment() {
    vec2 uv = vec2(UV.x, mix(UV.y, 1.0 - UV.y, flip_y));
    vec3 mark = texture(label_map, uv).rgb;
    float coverage = max(mark.r, mark.g);
    float face = mark.g / max(mark.r + mark.g, 0.001);

    ALBEDO = mix(recess_color.rgb, face_color.rgb, face);
    ALPHA = coverage;
}
