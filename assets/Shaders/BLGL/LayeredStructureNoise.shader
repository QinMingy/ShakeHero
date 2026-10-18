// Shader Graphs/Scan Lines (sharedassets0:218), active ALPHAMODULATE variant.
// Algebra recovered from DXBC. The texture is an original project asset.
shader_type spatial;
render_mode shading_model_unlit, blend_mul, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D noise_map : filter_nearest, repeat_enable;
void fragment() {
    // 与整帧后效保持同一128设计单位平铺周期。
    vec2 cell=floor(UV*vec2(201.0,437.0));
    vec2 sample_uv=(mod(cell,vec2(64.0))+vec2(0.5))/64.0;
    vec4 texel=texture(noise_map,sample_uv);
    texel.rgb=clamp(vec3(0.74)+(texel.rgb-vec3(0.795))*2.0,vec3(0.40),vec3(0.98));
    vec4 base=vec4(1.498039,1.498039,1.498039,0.5490196);
    vec4 shaded=base.a*(base*texel-base)+base;
    ALBEDO=mix(vec3(1.0),shaded.rgb,shaded.a)/1.19390381;
    ALPHA=shaded.a;
}
