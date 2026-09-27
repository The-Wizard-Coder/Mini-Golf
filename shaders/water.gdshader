shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Stylised-but-realistic water: multi-octave waves, fresnel sky reflection,
// deep/shallow body colour and a sharp sun specular.
uniform vec3 shallow_color : source_color = vec3(0.16, 0.55, 0.62);
uniform vec3 deep_color : source_color = vec3(0.01, 0.09, 0.20);
uniform vec3 sky_color : source_color = vec3(0.55, 0.72, 0.90);
uniform float wave_height : hint_range(0.0, 0.4) = 0.08;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float ripple_strength : hint_range(0.0, 3.0) = 1.2;
uniform float reflection_amount : hint_range(0.0, 1.0) = 0.75;
uniform float alpha : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_pos;

// Sum of directional waves (also used analytically for the normal).
float wave_sum(vec2 p, float t) {
    return sin(p.x * 1.1 + t) * 0.5
         + sin(p.y * 0.9 + t * 1.25) * 0.3
         + sin((p.x + p.y) * 0.65 + t * 0.8) * 0.2;
}

void vertex() {
    float t = TIME * wave_speed;
    vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_pos = wp;
    VERTEX.y += wave_sum(wp.xz, t) * wave_height;
}

void fragment() {
    float t = TIME * wave_speed;
    vec2 p = world_pos.xz;

    // Analytic gradient of wave_sum -> ripple normal.
    float dx = cos(p.x * 1.1 + t) * 1.1 * 0.5
             + cos((p.x + p.y) * 0.65 + t * 0.8) * 0.65 * 0.2;
    float dz = cos(p.y * 0.9 + t * 1.25) * 0.9 * 0.3
             + cos((p.x + p.y) * 0.65 + t * 0.8) * 0.65 * 0.2;
    vec3 n = normalize(vec3(-dx * ripple_strength, 1.0, -dz * ripple_strength));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

    // Fresnel: strong at grazing angles -> sky reflection; weak looking down -> body colour.
    float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    vec3 body = mix(deep_color, shallow_color, clamp(fres * 1.2 + 0.2, 0.0, 1.0));
    ALBEDO = mix(body, sky_color, clamp(fres * reflection_amount, 0.0, 1.0));

    ROUGHNESS = 0.03;
    SPECULAR = 0.8;
    ALPHA = alpha;
}
