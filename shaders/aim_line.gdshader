shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Procedural dotted aim line, flat on the ground and stretching along +dir from
// start_pos. Dots are placed in WORLD space so they stay evenly spaced as the
// line stretches, and they gently fade in/out over time.
uniform vec3 start_pos = vec3(0.0);
uniform vec2 dir = vec2(0.0, 1.0);
uniform float spacing = 0.09;          // world units between dot centres
uniform float dot_radius = 0.022;      // world radius of each dot
uniform float pulse_speed = 3.0;
uniform float alpha_min = 0.25;
uniform vec3 line_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz - start_pos.xz;
	float along = dot(p, dir);
	float across = dot(p, vec2(-dir.y, dir.x));

	float near_along = abs(fract(along / spacing + 0.5) - 0.5) * spacing;
	float d = sqrt(near_along * near_along + across * across);
	float dot_mask = 1.0 - smoothstep(dot_radius * 0.45, dot_radius, d);
	if (dot_mask <= 0.001) {
		discard;
	}

	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	ALBEDO = line_color;
	ALPHA = dot_mask * (alpha_min + (1.0 - alpha_min) * pulse);
}
