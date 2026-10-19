// Semi-transparent relic source pixels, same matte light/cookie as LayeredSpriteLit.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D sprite_map : source_color, filter_nearest, repeat_disable;
uniform sampler2D cookie_map : filter_linear, repeat_enable;
uniform float cookie_time = 0.0;
varying vec2 light_uv;
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    light_uv = vec2(dot(world, vec3(0.8,0.0,-0.6)), dot(world, vec3(0.350582,0.811534,0.467443)));
}
void fragment() {
    vec4 pixel = texture(sprite_map, UV);
    ALBEDO = mix(vec3(dot(pixel.rgb,vec3(0.2126,0.7152,0.0722))),pixel.rgb,0.85);
    ALPHA = pixel.a;
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
void light() {
    vec2 cookieUV=(light_uv-(vec2(4.0,2.0)+cookie_time*vec2(0.0,-3.5)*0.25))/vec2(22.0,30.0)+vec2(0.5);
    float cookie=texture(cookie_map,cookieUV).r;
    float hardShadow=mix(0.18,1.0,step(0.6,ATTENUATION));
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * hardShadow * max(dot(NORMAL,LIGHT),0.0) * cookie;
}
