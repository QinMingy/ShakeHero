// Cross-engine post pipeline. Reference values/provenance in CINEMATIC.md.
// Separate lit scene and transparent UI: light UI once, then compose and bloom.
shader_type spatial;
render_mode shading_model_unlit, cull_disabled;
uniform sampler2D source_map : filter_linear;
uniform sampler2D scene_map : filter_linear;
uniform sampler2D dust_map : filter_linear;
uniform sampler2D cookie_map : filter_linear, repeat_enable;
uniform float cookie_time = 0.0;
uniform vec2 ui_camera_offset = vec2(0.0);
uniform sampler2D noise_map : filter_nearest, repeat_enable;
uniform float noise_enabled = 1.0;
uniform vec2 pixel_size = vec2(0.002,0.001);
uniform vec4 game_rect = vec4(0.0,0.0,1.0,1.0);
uniform vec4 effects = vec4(1.0);
uniform sampler2D lamp_mask : filter_linear;
uniform float lamp_bloom_active = 0.0;
// game_rect使用UI左上原点；NanoVG RTT的采样原点由同帧mask的G标记识别。
// 只转换几何坐标，不翻source／scene／dust纹理或最终输出。
vec2 gameUV(vec2 uv,float flipY) {
    vec2 uiUV=vec2(uv.x,mix(uv.y,1.0-uv.y,flipY));
    return (uiUV-game_rect.xy)/game_rect.zw;
}
vec3 composed(vec2 uv,float flipY) {
    vec4 ui=texture(source_map,uv);
    vec2 guv=gameUV(uv,flipY);
    // UI lies on the camera-facing z=0 reference plane; same world projection,
    // texture, phase and slow speed as the scene's actual directional light.
    vec2 world=(guv-vec2(0.5))*vec2(4.02,-8.74)+ui_camera_offset;
    vec2 lightUV=vec2(world.x*0.8,dot(world,vec2(0.350582,0.811534)));
    vec2 cookieUV=(lightUV-(vec2(4.0,2.0)+cookie_time*vec2(0.0,-3.5)*0.25))/vec2(22.0,30.0)+vec2(0.5);
    float cookie=texture(cookie_map,cookieUV).r;
    vec3 ambient=vec3(0.22,0.24,0.21);
    float direct=2.76*0.649227;
    // UI colors are display-authored, premultiplied. Normalize against full
    // illumination; approximate linear irradiance -> display-space gain.
    vec3 gain=pow((ambient+vec3(direct*cookie))/(ambient+vec3(direct)),vec3(1.0/2.2));
    return ui.rgb*gain+texture(scene_map,uv).rgb*(1.0-ui.a)+texture(dust_map,uv).rgb;
}
vec3 bright(vec2 uv,float flipY) {
    vec3 c=composed(clamp(uv,vec2(0.001),vec2(0.999)),flipY);
    float b=max(c.r,max(c.g,c.b));
    float knee=0.10;
    float soft=clamp(b-0.82+knee,0.0,2.0*knee);
    soft=soft*soft/(4.0*knee+0.00001);
    return c*max(b-0.82,soft)/max(b,0.0001);
}
vec3 bloomLevel(vec2 uv,float radius,float flipY) {
    vec2 d=pixel_size*radius;
    return bright(uv,flipY)*0.20+(bright(uv+vec2(d.x,0.0),flipY)+bright(uv-vec2(d.x,0.0),flipY)+
      bright(uv+vec2(0.0,d.y),flipY)+bright(uv-vec2(0.0,d.y),flipY))*0.12+
      (bright(uv+d,flipY)+bright(uv-d,flipY)+bright(uv+vec2(d.x,-d.y),flipY)+bright(uv+vec2(-d.x,d.y),flipY))*0.08;
}
// 遮罩与 source_map 同 UV，提取本帧真实亮灯；不依赖后端 RTT 的绝对 Y 方向。
vec3 lampBright(vec2 uv) {
    vec2 q=clamp(uv,vec2(0.001),vec2(0.999));
    // Lamp emitters are already lit in scene_map; no need to resample UI here.
    vec3 c=texture(scene_map,q).rgb;
    float b=max(c.r,max(c.g,c.b));
    // 灯面专用较低阈值：源像素经过真实受光后未必超过普通UI高光阈值。
    return c*smoothstep(0.35,0.85,b)*texture(lamp_mask,q).r;
}
vec3 lampBloom(vec2 uv,float flipY) {
    vec2 p=gameUV(uv,flipY)*vec2(402.0,874.0);
    // 两种 RTT 纵向约定都覆盖；仅在屏幕灯带邻域执行卷积，正文不增加采样成本。
    float edgeY=min(p.y,874.0-p.y);
    bool sides=(p.x<54.0 || p.x>348.0) && p.y>138.0 && p.y<736.0;
    if(!sides && abs(edgeY-196.0)>58.0) return vec3(0.0);
    vec2 unit=game_rect.zw/vec2(402.0,874.0);
    vec3 sum=vec3(0.0);
    // 连续覆盖灯面宽度的双尺度高斯，外圈权重更高，避免稀疏星芒。
    for(int y=-4;y<=4;y++) {
        for(int x=-4;x<=4;x++) {
            vec2 offset=vec2(float(x),float(y));
            float weight=exp(-dot(offset,offset)/8.0);
            sum+=lampBright(uv+offset*unit*2.0)*weight*0.035;
            sum+=lampBright(uv+offset*unit*4.0)*weight*0.065;
        }
    }
    // 光能主要扩散到灯外；灯芯保留原图细节，不靠继续叠白提高可见度。
    float core=texture(lamp_mask,clamp(uv,vec2(0.001),vec2(0.999))).r;
    return sum*vec3(1.0,0.90,0.72)*4.5*(1.0-core*0.65);
}
void fragment() {
    vec2 uv=UV;
    // 左上4×4物理像素G标记：采样端原点相反时，它出现在UV底边。
    float topMarker=texture(lamp_mask,pixel_size*2.0).g;
    float bottomMarker=texture(lamp_mask,vec2(pixel_size.x*2.0,1.0-pixel_size.y*2.0)).g;
    float flipY=step(topMarker+0.5,bottomMarker);
    vec2 guv=gameUV(uv,flipY);
    vec3 original=composed(uv,flipY);
    vec3 c=original;
    bool inGame=guv.x>=0.0 && guv.x<=1.0 && guv.y>=0.0 && guv.y<=1.0;
    // Process the whole game uniformly. A rectangular toolbar exclusion also
    // excludes its background and creates a visible exposure/tint boundary.
    if (inGame && effects.w>0.5) {
        // Static Scan Lines multiply algebra recovered from original DXBC.
        // Normalize its mean gain so enabling texture doesn't change exposure.
        // 每格两个机台设计单位，64格平铺：粗虚线保留硬像素边。
        vec2 cell=floor(guv*vec2(201.0,437.0));
        vec2 noise_uv=(mod(cell,vec2(64.0))+vec2(0.5))/64.0;
        float texel=clamp(0.74+(texture(noise_map,noise_uv).r-0.795)*2.0,0.40,0.98);
        float shaded=1.498039*(1.0+0.5490196*(texel-1.0));
        float modulation=mix(1.0,shaded,0.5490196)/1.19390381;
        c*=mix(1.0,modulation,noise_enabled);
        if(effects.x>0.5) {
            vec3 bloom=(bloomLevel(uv,2.0,flipY)*0.25+bloomLevel(uv,5.0,flipY)*0.35+bloomLevel(uv,11.0,flipY)*0.40);
            // 通用高光只留少量柔化；主要可见扩散来自灯面，避免把整片UI提亮。
            // Skip the 162-tap lamp convolution when the mask is entirely black.
            // No lamp halo exists in prepare/draft/modal states.
            c+=bloom*vec3(1.0,0.89,0.67)*0.35;
            if(lamp_bloom_active>0.5) c+=lampBloom(uv,flipY);
        }
        vec2 distanceToCenter=abs(guv-vec2(0.5))*1.05;
        float v=pow(clamp(1.0-dot(distanceToCenter,distanceToCenter),0.0,1.0),1.0);
        c*=mix(vec3(0.180392,0.039216,0.048157),vec3(1.0),mix(1.0,v,effects.z));
    }
    // UI与场景已分别调色；此处保留物品原色，不再整帧去饱和。
    ALBEDO=c;ALPHA=1.0;
}
