shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 outer_color : source_color = vec4(1.0, 0.55, 0.1, 0.95);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.5, 8.0) = 3.2;
uniform float noise_speed : hint_range(0.5, 15.0) = 6.0;
uniform float has_bio_lightning : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float val_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	float pulse = sin(TIME * 28.0 + VERTEX.y * 10.0) * 0.035 * (1.0 - progress);
	VERTEX += NORMAL * pulse;
}

void fragment() {
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 1.75);
	float core = pow(ndotv, 2.2);

	vec2 uv_flow = UV * 6.0 + vec2(TIME * noise_speed * 0.25, -TIME * noise_speed * 0.45);
	float n1 = val_noise(uv_flow);
	float n2 = val_noise(uv_flow * 2.3 - vec2(TIME * 1.8, 0.0));
	float plasma = n1 * 0.65 + n2 * 0.35;

	float dissolve_threshold = progress * 1.15;
	float dissolve_mask = smoothstep(dissolve_threshold - 0.25, dissolve_threshold + 0.15, plasma + core * 0.45);

	float arc = smoothstep(0.76, 0.95, 1.0 - abs(n2 * 2.0 - 1.0)) * has_bio_lightning;

	vec3 col = mix(outer_color.rgb, core_color.rgb, clamp(core * 1.15 + arc * 0.65, 0.0, 1.0));
	col += outer_color.rgb * fresnel * 1.65;
	col += vec3(0.45, 0.85, 1.0) * arc * 2.5;

	float fade = pow(1.0 - progress, 0.65);
	ALBEDO = col * intensity * fade;
	ALPHA = clamp((core * 0.85 + fresnel * 0.90 + arc) * dissolve_mask * fade * outer_color.a, 0.0, 1.0);
}
