// 像素格位于独立窄底板上、目标牌下；透明间隙透出窄底板。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;
uniform sampler2D cookie_map : filter_linear, repeat_enable;
uniform float cookie_time = 0.0;
varying vec2 light_uv;
void vertex() {
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    light_uv=vec2(dot(world,vec3(0.8,0.0,-0.6)),dot(world,vec3(0.350582,0.811534,0.467443)));
}
uniform float progress_value = 0.0;
uniform vec4 progress_color = vec4(0.956863,0.756863,0.313725,1.0);
void fragment() {
    vec2 p=UV*vec2(226.0,26.0);
    float localX=p.x-8.0;
    float column=floor(localX/10.0);
    bool slot=localX>=0.0 && column<21.0 && mod(localX,10.0)<8.0
        && p.y>=7.0 && p.y<19.0;
    float edge=8.0+208.0*clamp(progress_value,0.0,1.0);
    vec3 color=p.x<edge ? progress_color.rgb : vec3(0.207843,0.243137,0.164706);
    ALBEDO=mix(vec3(dot(color,vec3(0.2126,0.7152,0.0722))),color,0.85);
    METALLIC=0.0;ROUGHNESS=1.0;SPECULAR=0.0;
    ALPHA=slot ? 1.0 : 0.0;
    ALPHA_SCISSOR_THRESHOLD=0.5;
}
void light() {
    vec2 cookieUV=(light_uv-(vec2(4.0,2.0)+cookie_time*vec2(0.0,-3.5)*0.25))/vec2(22.0,30.0)+vec2(0.5);
    float hardShadow=mix(0.18,1.0,step(0.6,ATTENUATION));
    DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*hardShadow*max(dot(NORMAL,LIGHT),0.0)*texture(cookie_map,cookieUV).r;
}
