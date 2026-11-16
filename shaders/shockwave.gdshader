shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 ring_color : source_color = vec4(0.45, 0.85, 1.0, 0.9);
uniform float force : hint_range(-0.5, 0.5) = 0.08;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 0.5) = 0.14;
uniform float use_uv_ring : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float fresnel = clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float uv_dist = length(UV - vec2(0.5)) * 2.0;
	float radial = mix(fresnel, uv_dist, use_uv_ring);

	float ring_pos = mix(0.70, progress, step(0.001, progress));
	float band = smoothstep(ring_pos - thickness, ring_pos, radial) *
				 (1.0 - smoothstep(ring_pos, ring_pos + thickness, radial));
	float fade = (1.0 - progress) * ring_color.a;
	float quad_mask = 1.0 - smoothstep(0.86, 1.0, uv_dist);
	float mask = mix(1.0, quad_mask, use_uv_ring);

	float intensity = band * fade * mask;
	ALBEDO = ring_color.rgb * (1.25 + force * 2.0) * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
