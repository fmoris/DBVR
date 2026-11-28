shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0, 0.85, 0.1, 0.9);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.88, 1.0);
uniform sampler2D flame_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D band_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float speed : hint_range(0.5, 14.0) = 4.5;
uniform float scale : hint_range(1.0, 12.0) = 3.0;
uniform float vertex_displacement : hint_range(0.0, 0.25) = 0.08;
uniform float has_bio_lightning : hint_range(0.0, 1.0) = 0.0;
uniform float is_divine : hint_range(0.0, 1.0) = 0.0;
uniform float opacity_mult : hint_range(0.0, 1.0) = 1.0;
uniform float fp_center_clear : hint_range(0.0, 1.0) = 0.0;
uniform float fp_clear_outer : hint_range(0.0, 0.99) = 0.72;
uniform float fp_clear_inner : hint_range(0.0, 1.0) = 0.94;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float t = TIME * speed * 2.2;
	float wave = sin(UV.x * 18.8495 + t) * cos(UV.y * 12.0 - t * 1.4);
	float ridge = sin(UV.x * 31.4159 - t * 1.35) * 0.06 * h;
	float bell = mix(1.05, 0.62, pow(h, 0.85)) + sin(h * 3.14159) * 0.14;
	VERTEX.xz *= (bell + ridge);
	VERTEX += NORMAL * (wave * vertex_displacement * (0.35 + h * 0.95));
}

void fragment() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 1.35);

	vec2 uv1 = vec2(UV.x * scale, UV.y * 1.35 + TIME * speed * 0.42);
	vec2 uv2 = vec2(UV.x * scale * 1.65 - TIME * 0.35, UV.y * 2.1 + TIME * speed * 0.68);
	vec4 t1 = texture(flame_tex, uv1);
	vec4 t2 = texture(flame_tex, uv2);
	vec4 tb = texture(band_tex, vec2(UV.x * 2.0, UV.y + TIME * speed * 0.55));
	float f1 = t1.r * t1.a;
	float f2 = t2.r * t2.a;
	float band = tb.r * tb.a;

	float flame_val = f1 * 0.60 + f2 * 0.40 + band * 0.25;
	float top_fade = smoothstep(1.0, 0.18, h);
	float bot_fade = smoothstep(0.0, 0.24, h);
	float v_mask = top_fade * bot_fade;

	float flame_edge = smoothstep(0.20, 0.62, flame_val);
	float rim_flame = fresnel * flame_edge * v_mask;
	float outer_shell = smoothstep(0.36, 0.64, flame_val * v_mask + rim_flame * 0.45);
	float inner_core = smoothstep(0.66, 0.88, flame_val * v_mask + rim_flame * 0.28);

	// Bio-lightning arcs (SSJ2 / SSJ3 / Super Vegeta / UI / UE / Furia)
	vec2 bolt_uv = vec2(UV.x * 4.0 + floor(TIME * 14.0) * 0.37, UV.y * 1.8 + TIME * 2.6);
	vec4 tb_bolt = texture(flame_tex, bolt_uv);
	float bolt_sample = tb_bolt.r * tb_bolt.a;
	float bolt_flash = step(0.45, hash21(vec2(floor(TIME * 18.0), floor(UV.x * 5.0))));
	float lightning = smoothstep(0.76, 0.93, bolt_sample) * bolt_flash * has_bio_lightning * v_mask;

	// Divine rising stardust motes (SSB / UI / UE)
	vec2 spark_cell = floor(vec2(UV.x * 24.0, UV.y * 18.0 + TIME * speed * 1.1));
	vec2 spark_f = fract(vec2(UV.x * 24.0, UV.y * 18.0 + TIME * speed * 1.1)) - 0.5;
	float spark_rnd = hash21(spark_cell);
	float spark_dot = step(0.84, spark_rnd) * smoothstep(0.26, 0.04, length(spark_f)) * is_divine * v_mask;

	float flicker = 0.90 + 0.10 * sin(TIME * 42.0);
	vec3 col = mix(base_color.rgb * 1.10, core_color.rgb * 1.35, inner_core);
	col += base_color.rgb * rim_flame * 0.55;
	col += vec3(0.55, 0.92, 1.0) * lightning * 2.2;
	col += core_color.rgb * spark_dot * 2.0;

	float center_align = smoothstep(fp_clear_outer, fp_clear_inner, clamp(VIEW.z, 0.0, 1.0));
	float fp_mask = mix(1.0, 1.0 - fp_center_clear, center_align);
	float raw_alpha = clamp((outer_shell * 0.68 + rim_flame * 0.30 + lightning + spark_dot) * base_color.a, 0.0, 1.0);
	float vis = clamp(opacity_mult * fp_mask, 0.0, 1.0);

	ALBEDO = col * flicker;
	ALPHA = clamp(raw_alpha * vis, 0.0, 1.0);
}
