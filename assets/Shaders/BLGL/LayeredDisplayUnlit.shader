// Display substrate remains emissive/unlit, independent of physical panel light.
shader_type spatial;
render_mode shading_model_unlit, cull_disabled;
uniform sampler2D sprite_map : source_color, filter_nearest, repeat_enable;
void fragment() {
    vec4 pixel = texture(sprite_map, UV);
    ALBEDO = mix(vec3(dot(pixel.rgb,vec3(0.2126,0.7152,0.0722))),pixel.rgb,0.62);
    ALPHA = pixel.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
