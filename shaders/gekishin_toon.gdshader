shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// Shader Toon Cel-Shading fiel al estilo Dragon Ball (Toriyama & Gekishin Squadra)
// Permite iluminacion anime en 2 tonos con transicion nitida y Rim Light perimetral.

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);

uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float shadow_softness : hint_range(0.001, 0.2) = 0.02;

uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float rim_power : hint_range(0.0, 5.0) = 1.8;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.05;
}

void light() {
	// 1. Calculo de incidencia luminica Toon
	float n_dot_l = dot(NORMAL, LIGHT);
	float light_intensity = smoothstep(shadow_threshold - shadow_softness, shadow_threshold + shadow_softness, n_dot_l);
	light_intensity *= ATTENUATION;

	// 2. Mezcla de color base y sombra
	vec3 toon_diffuse = mix(shadow_color.rgb, ALBEDO.rgb, light_intensity);

	// 3. Rim Light anime (resplandor periferico frente a la camara)
	float n_dot_v = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = smoothstep(rim_threshold - 0.04, rim_threshold + 0.04, n_dot_v) * max(n_dot_l, 0.0);
	vec3 rim_effect = rim_color.rgb * rim * rim_power;

	DIFFUSE_LIGHT += (toon_diffuse + rim_effect) * LIGHT_COLOR;
}
