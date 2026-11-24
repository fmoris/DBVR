shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 outer_color : source_color = vec4(1.0, 0.55, 0.1, 0.95);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform sampler2D plasma_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D streak_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.5, 8.0) = 3.6;
uniform float noise_speed : hint_range(0.5, 15.0) = 6.5;
uniform float has_bio_lightning : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float pulse = sin(TIME * 32.0 + VERTEX.y * 9.0 + VERTEX.x * 7.0) * 0.045 * (1.0 - progress);
	VERTEX += NORMAL * pulse;
}

void fragment() {
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 1.55);
	float core = pow(ndotv, 1.9);

	vec2 uv_flow = vec2(UV.x * 3.0 + TIME * noise_speed * 0.18, UV.y * 2.5 - TIME * noise_speed * 0.35);
	float tex_p = texture(plasma_tex, uv_flow).r;
	float tex_s = texture(streak_tex, vec2(UV.x * 4.0, UV.y * 2.0 + TIME * noise_speed * 0.45)).r;
	float plasma = tex_p * 0.65 + tex_s * 0.35;

	float dissolve_threshold = progress * 1.18;
	float dissolve_mask = smoothstep(dissolve_threshold - 0.22, dissolve_threshold + 0.12, plasma + core * 0.50);

	float arc = smoothstep(0.72, 0.92, tex_p) * has_bio_lightning;

	// Crisp anime inner-core + cel-banded plasma edge
	float cel_rim = smoothstep(0.35, 0.65, fresnel + tex_s * 0.35);
	vec3 col = mix(outer_color.rgb * 1.6, core_color.rgb * 2.2, clamp(core * 1.2 + arc * 0.6, 0.0, 1.0));
	col += outer_color.rgb * cel_rim * 2.1;
	col += vec3(0.45, 0.88, 1.0) * arc * 3.2;

	float fade = pow(1.0 - progress, 0.58);
	ALBEDO = col * intensity * fade;
	ALPHA = clamp((core * 0.90 + cel_rim * 0.95 + arc) * dissolve_mask * fade * outer_color.a, 0.0, 1.0);
}
