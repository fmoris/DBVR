shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 color_grass_inner  : source_color = vec3(0.34, 0.72, 0.22); // Verde pradera inmediato
uniform vec3 color_grass_distant: source_color = vec3(0.48, 0.67, 0.31); // Verde seco estepa DBZ
uniform vec3 color_dirt_hills   : source_color = vec3(0.68, 0.52, 0.34); // Ocre colinas lejanas

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 3000.0;
	float dist = length(p);
	
	// Ondulaciones orgánicas de vegetación y tierra
	float hill_noise = sin(p.x * 0.008) * cos(p.y * 0.008) * 0.5 + 0.5;
	vec3 ground_color = mix(color_grass_distant, color_dirt_hills, hill_noise * 0.45);
	
	// Transición suave desde el verde cercano hacia la estepa lejana
	float inner_blend = smoothstep(70.0, 140.0, dist);
	ground_color = mix(color_grass_inner, ground_color, inner_blend);
	
	ALBEDO = ground_color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.04;
}
