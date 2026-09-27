shader_type canvas_item;

// Anime-style outline post-process (colour-edge sobel). No posterize here - the
// toon materials already produce flat, banded shading.
//
// Only the outline is drawn, alpha blended over the frame. It deliberately does
// NOT re-draw the screen: writing an opaque screen sample means that if the
// backbuffer copy ever comes back stale or empty - which it can on the web
// backend - the whole view gets replaced by whatever that copy contained, and
// the level appears to be missing.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float outline_strength : hint_range(0.0, 4.0) = 1.0;
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float edge_width : hint_range(1.0, 4.0) = 1.5;
uniform vec3 outline_color : source_color = vec3(0.02, 0.02, 0.05);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * edge_width;

	vec3 cl = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
	vec3 cr = texture(screen_tex, uv - vec2(px.x, 0.0)).rgb;
	vec3 cu = texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
	vec3 cd = texture(screen_tex, uv - vec2(0.0, px.y)).rgb;

	vec3 d = abs(cl - cr) + abs(cu - cd);
	float edge = max(d.r, max(d.g, d.b));
	float outline = smoothstep(edge_threshold, edge_threshold * 2.0, edge);

	// Overlay only. A blank screen texture yields no edges and therefore nothing
	// painted, rather than a blank frame.
	COLOR = vec4(outline_color, clamp(outline * outline_strength, 0.0, 1.0));
}
