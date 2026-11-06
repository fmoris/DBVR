shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.08, 0.08, 0.10, 1.0);
uniform float outline_thickness : hint_range(0.0, 5.0) = 1.2;

void vertex() {
	// Extrusión de normales invertidas (Inverted Hull Anime Outline)
	VERTEX += NORMAL * (outline_thickness * 0.001);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
