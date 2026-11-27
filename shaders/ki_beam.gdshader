shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D streak_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D flame_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float flow_speed : hint_range(1.0, 30.0) = 16.0;
uniform float beam_frequency : hint_range(1.0, 50.0) = 6.0;
uniform float core_intensity : hint_range(1.0, 10.0) = 4.2;
uniform float edge_falloff : hint_range(0.1, 5.0) = 1.5;
uniform float noise_scale : hint_range(1.0, 20.0) = 4.0;

void vertex() {
	float t = TIME * 38.0;
	float wobble = sin(VERTEX.y * 14.0 + t) * cos(VERTEX.x * 14.0 + t) * 0.035;
	VERTEX += NORMAL * wobble;
}

void fragment() {
	vec2 uv_band = vec2(UV.x * noise_scale, UV.y * beam_frequency - TIME * flow_speed * 0.35);
	vec2 uv_spiral = vec2(UV.x * 3.0 + UV.y * 2.5 - TIME * 1.4, UV.y * 3.5 - TIME * flow_speed * 0.45);
	float s1 = texture(streak_tex, uv_band).r;
	float f1 = texture(flame_tex, uv_spiral).r;
	float lightning_streaks = smoothstep(0.45, 0.86, s1 * 0.55 + f1 * 0.45);

	float normal_dot = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float core_factor = pow(normal_dot, edge_falloff);
	float rim_factor = pow(1.0 - normal_dot, 1.6);

	float flicker = 0.88 + 0.12 * sin(TIME * 62.0);
	vec3 white_core = core_color.rgb * core_intensity * core_factor;
	vec3 sheath_plasma = beam_color.rgb * (2.4 + rim_factor * 2.2) * (1.0 - core_factor * 0.40);
	vec3 electric_burst = mix(beam_color.rgb, core_color.rgb, 0.45) * lightning_streaks * 3.0;

	ALBEDO = (white_core + sheath_plasma + electric_burst) * flicker;
	ALPHA = clamp((0.88 + core_factor * 0.25 + lightning_streaks * 0.25) * flicker, 0.0, 1.0) * beam_color.a;
}
