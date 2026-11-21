shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec4 vignette_color : source_color = vec4(1.0, 0.15, 0.15, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.15, 0.70) = 0.28;
uniform float outer_radius : hint_range(0.45, 0.95) = 0.62;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float mask = smoothstep(inner_radius, outer_radius, dist);
	ALBEDO = vignette_color.rgb;
	ALPHA = clamp(mask * intensity * vignette_color.a, 0.0, 0.94);
}
