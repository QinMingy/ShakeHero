shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D patina_map : source_color, filter_nearest, repeat_enable;
uniform sampler2D light_cookie : source_color, filter_linear, repeat_disable;
uniform vec4 metal_tint : source_color = vec4(1.0);

void fragment() {
    // Discrete painted values read closer to the reference's depth sprites
    // than a smooth reflective PBR coat on every cabinet face.
    vec3 patina = floor(texture(patina_map, UV).rgb * 7.0 + 0.5) / 7.0;
    float value = dot(patina, vec3(0.30, 0.55, 0.15));
    float front = smoothstep(0.15, 0.75, -NORMAL.z);
    float painted_depth = mix(0.58, 1.0, front);

    // World-space light pattern follows the desk spotlight without changing
    // the printed patina. The radial envelope keeps the readable centre quiet.
    vec2 focus = vec2(-0.75 + 1.15 * sin(TIME * 0.42),
                      2.45 + 0.37 * sin(TIME * 0.33 + 1.0));
    vec2 delta = (VERTEX.xy - focus) / vec2(2.25, 2.0);
    float falloff = max(0.0, 1.0 - dot(delta, delta));
    vec2 cookie_uv = clamp(delta * 0.5 + vec2(0.5), vec2(0.0), vec2(1.0));
    float shaped = smoothstep(0.27, 0.75, texture(light_cookie, cookie_uv).r);
    float passing_light = falloff * shaped;

    ALBEDO = metal_tint.rgb * patina * painted_depth * (1.0 + passing_light * 0.62);
    ROUGHNESS = 0.95;
    METALLIC = 0.035;
    SPECULAR = 0.10;
    AO = mix(0.72, 1.0, smoothstep(0.38, 0.84, value));
    EMISSION = metal_tint.rgb * passing_light * 0.045;
}
