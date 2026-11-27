shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0, 0.85, 0.1, 0.9);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.88, 1.0);
uniform sampler2D flame_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D band_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float speed : hint_range(0.5, 14.0) = 4.5;
uniform float scale : hint_range(1.0, 12.0) = 3.0;
uniform float vertex_displacement : hint_range(0.0, 0.25) = 0.08;
uniform float has_bio_lightning : hint_range(0.0, 1.0) = 0.0;
uniform float is_divine : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float t = TIME * speed * 2.2;
	float wave = sin(UV.x * 18.8495 + t) * cos(UV.y * 12.0 - t * 1.4);
	float flare = mix(1.18, 0.72, h);
	VERTEX.xz *= flare;
	VERTEX += NORMAL * (wave * vertex_displacement * (0.4 + h * 0.9));
}

void fragment() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 1.35);

	vec2 uv1 = vec2(UV.x * scale, UV.y * 1.35 + TIME * speed * 0.42);
	vec2 uv2 = vec2(UV.x * scale * 1.65 - TIME * 0.35, UV.y * 2.1 + TIME * speed * 0.68);
	float f1 = texture(flame_tex, uv1).r;
	float f2 = texture(flame_tex, uv2).r;
	float band = texture(band_tex, vec2(UV.x * 2.0, UV.y + TIME * speed * 0.55)).r;

	float flame_val = f1 * 0.60 + f2 * 0.40 + band * 0.25;
	float top_fade = smoothstep(1.0, 0.22, h);
	float bot_fade = smoothstep(0.0, 0.14, h);
	float v_mask = top_fade * bot_fade;

	// Crisp anime cel-stepped flame silhouette
	float outer_shell = smoothstep(0.32, 0.58, flame_val * v_mask + fresnel * 0.55);
	float inner_core = smoothstep(0.62, 0.86, flame_val * v_mask + fresnel * 0.35);

	// Bio-lightning arcs (SSJ2 / SSJ3 / Super Vegeta / UI / UE / Furia)
	vec2 bolt_uv = vec2(UV.x * 4.0 + floor(TIME * 14.0) * 0.37, UV.y * 1.8 + TIME * 2.6);
	float bolt_sample = texture(flame_tex, bolt_uv).r;
	float bolt_flash = step(0.45, hash21(vec2(floor(TIME * 18.0), floor(UV.x * 5.0))));
	float lightning = smoothstep(0.76, 0.93, bolt_sample) * bolt_flash * has_bio_lightning * v_mask;

	// Divine rising stardust motes (SSB / UI / UE)
	vec2 spark_cell = floor(vec2(UV.x * 24.0, UV.y * 18.0 + TIME * speed * 1.1));
	vec2 spark_f = fract(vec2(UV.x * 24.0, UV.y * 18.0 + TIME * speed * 1.1)) - 0.5;
	float spark_rnd = hash21(spark_cell);
	float spark_dot = step(0.84, spark_rnd) * smoothstep(0.26, 0.04, length(spark_f)) * is_divine * v_mask;

	float flicker = 0.85 + 0.15 * sin(TIME * 42.0);
	vec3 col = mix(base_color.rgb * 1.65, core_color.rgb * 2.4, inner_core);
	col += base_color.rgb * fresnel * 1.5;
	col += vec3(0.55, 0.92, 1.0) * lightning * 4.5;
	col += core_color.rgb * spark_dot * 4.0;

	ALBEDO = col * flicker;
	ALPHA = clamp((outer_shell * 0.82 + fresnel * 0.45 * v_mask + lightning + spark_dot) * base_color.a, 0.0, 1.0);
}
