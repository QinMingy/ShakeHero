// Near-camera foliage; user-requested shared lighting, no cast/receive shadows.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D sprite_map : filter_nearest;
uniform sampler2D cookie_map : filter_linear, repeat_enable;
uniform float cookie_time = 0.0;
varying vec2 light_uv;
uniform float wind_time = 0.0;
void vertex() {
    // Vegetation Sprite: slow phase + spatial offset, bottom-to-tip falloff.
    // Original speed .5, offset .3, bottom .5; portrait amplitude scaled to 60%.
    float phase=wind_time*0.5+(VERTEX.x+VERTEX.y+VERTEX.z)*0.3;
    float weight=mix(0.5,1.0,1.0-UV.y);
    VERTEX.xy+=vec2(0.03,0.042)*sin(phase)*weight;
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    light_uv=vec2(dot(world,vec3(0.8,0.0,-0.6)),dot(world,vec3(0.350582,0.811534,0.467443)));
}
void fragment() {
    vec4 p=texture(sprite_map,UV);
    vec3 color=vec3(0.012,0.022,0.016);
    ALBEDO=mix(vec3(dot(color,vec3(0.2126,0.7152,0.0722))),color,0.62);
    ALPHA=p.a*0.88;
    METALLIC=0.0;ROUGHNESS=1.0;SPECULAR=0.0;
}
void light() {
    vec2 cookieUV=(light_uv-(vec2(4.0,2.0)+cookie_time*vec2(0.0,-3.5)*0.25))/vec2(22.0,30.0)+vec2(0.5);
    DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*max(dot(NORMAL,LIGHT),0.0)*texture(cookie_map,cookieUV).r;
}
