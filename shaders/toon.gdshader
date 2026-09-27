shader_type spatial;
render_mode specular_disabled;

// Toon shading: soft-edged lighting bands (quantised but rounded) plus a rim
// light, for a stylised anime / toon look.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec3 base_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float softness : hint_range(0.0, 1.0) = 0.4;
uniform float shadows : hint_range(0.0, 1.0) = 0.55;
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.2;
uniform float rim_power : hint_range(1.0, 6.0) = 3.0;

// Quantise x into `bands` steps, with a soft transition at each step edge.
float toon_ramp(float x) {
	float t = clamp(x, 0.0, 1.0) * bands;
	float i = floor(t);
	float f = t - i;
	f = smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, f);
	return (i + f) / bands;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * base_tint;
}

void light() {
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float lit = mix(shadows, 1.0, toon_ramp(ndl));
	DIFFUSE_LIGHT += ALBEDO * lit * ATTENUATION * LIGHT_COLOR;

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += ALBEDO * rim * rim_strength * rim_color * ATTENUATION * LIGHT_COLOR;
}
