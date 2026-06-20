shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.0, 0.7, 1.0, 1.0);
uniform float plasma_speed : hint_range(0.1, 10.0) = 3.0;
uniform float fresnel_power : hint_range(0.1, 8.0) = 3.5;
uniform float core_glow : hint_range(1.0, 10.0) = 4.0;

// Generador pseudo-aleatorio para el ruido
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Ruido bilineal estándar
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// 1. Efecto Fresnel (borde luminoso)
	float raw_ndotv = dot(NORMAL, VIEW);
	float fresnel = pow(1.0 - raw_ndotv, fresnel_power);
	
	// 2. Ruido procedimental animado para simular plasma denso
	vec2 p = UV * 5.0;
	float n1 = noise(p + vec2(TIME * plasma_speed * 0.3, TIME * plasma_speed * 0.2));
	float n2 = noise(p * 1.5 - vec2(-TIME * plasma_speed * 0.2, TIME * plasma_speed * 0.4));
	float plasma = mix(n1, n2, 0.5);
	
	// 3. Crear el núcleo denso hiper-brillante (cerca del centro)
	// Cuando el rayo de la vista incide directamente en el centro (raw_ndotv alto), creamos un núcleo blanco
	float core = pow(raw_ndotv, 2.8) * 1.2;
	
	// Combinación de color:
	// - El núcleo aporta un tono blanco intenso al centro.
	// - El plasma y Fresnel aportan el color del elemento fluyendo hacia los bordes.
	vec3 core_color = vec3(1.0, 1.0, 1.0) * core;
	vec3 border_color = base_color.rgb * (fresnel + plasma * 0.3) * core_glow;
	vec3 final_color = core_color + border_color;
	
	// Opacidad controlada
	float final_alpha = clamp((core + fresnel * 0.6 + plasma * 0.2) * base_color.a, 0.0, 1.0);
	
	ALBEDO = final_color;
	ALPHA = final_alpha;
}
