shader_type spatial;
render_mode shading_model_unlit, cull_disabled;
uniform sampler2D sprite_map : filter_nearest;
uniform float eye_depth = 12.5;
uniform float wind_time = 0.0;
uniform vec2 wind_amount = vec2(0.0);
void vertex() {
    float phase=wind_time*0.5+(VERTEX.x+VERTEX.y+VERTEX.z)*0.3;
    float weight=mix(0.5,1.0,1.0-UV.y);
    VERTEX.xy+=wind_amount*sin(phase)*weight;
}
void fragment() {
    ALPHA=texture(sprite_map,UV).a;
    ALPHA_SCISSOR_THRESHOLD=0.12;
    ALBEDO=vec3(eye_depth/30.0);
}
