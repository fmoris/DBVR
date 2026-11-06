shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Paleta auténtica de rocas y cañones de Akira Toriyama (DBZ Wasteland)
uniform vec3 color_base_rock   : source_color = vec3(0.58, 0.42, 0.28); // Marrón arcilla / arenisca DBZ
uniform vec3 color_stratum     : source_color = vec3(0.72, 0.54, 0.36); // Estrato ocre iluminado
uniform vec3 color_dark_crevice: source_color = vec3(0.38, 0.27, 0.18); // Grietas y sombras de roca
uniform vec3 color_top_haze    : source_color = vec3(0.68, 0.62, 0.52); // Desgaste solar en crestas

uniform float stratum_scale = 0.12; // Frecuencia de bandas horizontales
uniform float roughness_val = 0.92;

varying vec3 v_world_pos;
varying vec3 v_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 1. Bandas de sedimentación horizontal (estratos característicos del manga/anime)
	float stratum_wave = sin(v_world_pos.y * stratum_scale * 6.28318 + sin(v_world_pos.x * 0.03 + v_world_pos.z * 0.03) * 2.2);
	float stratum_factor = smoothstep(-0.2, 0.5, stratum_wave);
	
	// Mezcla entre roca base y estrato ocre
	vec3 rock_color = mix(color_base_rock, color_stratum, stratum_factor * 0.55);
	
	// 2. Micro-ruido de grano de piedra
	float grain = sin(v_world_pos.x * 0.5) * cos(v_world_pos.z * 0.5) * 0.03;
	rock_color += vec3(grain);
	
	// 3. Gradiente de altura: base más en sombra y profunda, cumbre con desgaste solar
	float height_factor = clamp(v_world_pos.y / 110.0, 0.0, 1.0);
	rock_color = mix(mix(color_dark_crevice, rock_color, 0.7 + height_factor * 0.3), color_top_haze, height_factor * 0.25);
	
	// 4. Caras horizontales superiores de las mesetas
	if (v_normal.y > 0.6) {
		rock_color = mix(rock_color, color_stratum * 1.08, 0.35);
	}
	
	ALBEDO = rock_color;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.05;
}
