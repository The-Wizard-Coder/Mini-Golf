shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;

// Toon water: banded colour from crossing waves plus white foam on the crests.
// Fully procedural (no depth lookup) so the colours are always present.
uniform vec3 shallow_color : source_color = vec3(0.38, 0.82, 0.92);
uniform vec3 deep_color : source_color = vec3(0.06, 0.32, 0.58);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 4.0;
uniform float band_scale : hint_range(0.1, 4.0) = 0.8;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.4;
uniform float wave_freq : hint_range(0.1, 5.0) = 1.4;
uniform float wave_amp : hint_range(0.0, 0.5) = 0.06;
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float foam_soft : hint_range(0.01, 0.5) = 0.12;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += (sin(world_pos.x * wave_freq + t) + sin(world_pos.z * wave_freq * 0.85 + t * 1.3)) * wave_amp * 0.5;
}

void fragment() {
	float t = TIME * wave_speed;
	float w = sin(world_pos.x * band_scale + t * 0.9) * 0.5
			+ sin(world_pos.z * band_scale * 0.85 + t * 1.2) * 0.5
			+ sin((world_pos.x + world_pos.z) * band_scale * 0.5 + t * 0.7) * 0.35;
	float n = clamp(w * 0.35 + 0.5, 0.0, 1.0);

	float q = floor(n * bands) / max(bands - 1.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, q);

	float foam = smoothstep(foam_threshold - foam_soft, foam_threshold + foam_soft, n);
	col = mix(col, foam_color, foam);

	ALBEDO = col;
}
