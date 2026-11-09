shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.0, 0.7, 1.0, 1.0);
uniform float speed : hint_range(0.1, 10.0) = 5.0;
uniform float scale : hint_range(1.0, 20.0) = 6.0;
uniform float vertex_displacement : hint_range(0.0, 0.2) = 0.05;

// Generador pseudo-aleatorio para el ruido
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Ruido bilineal estándar de 2D
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Ruido con crestas (Ridged Noise) para filamentos eléctricos
float ridged_noise(vec2 p) {
	return 1.0 - abs(noise(p) * 2.0 - 1.0);
}

// Movimiento browniano fractal (fBm) para simular descargas eléctricas inestables
float fbm_lightning(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(0.877, 0.479), vec2(-0.479, 0.877)); // Rotación fija para desacoplar octavas
	for (int i = 0; i < 3; i++) {
		v += a * ridged_noise(p);
		p = rot * p * 2.0 + shift + vec2(0.0, TIME * speed);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Deformar la geometría dinámicamente usando funciones senoidales e inestabilidad de ruido
	float t = TIME * speed * 2.5;
	float offset = sin(VERTEX.x * 25.0 + t) * cos(VERTEX.y * 25.0 + t) * sin(VERTEX.z * 25.0 + t);
	VERTEX += NORMAL * offset * vertex_displacement;
}

void fragment() {
	// Mapear coordenadas UV y animar el desplazamiento de los filamentos radiales
	vec2 p = UV * scale;
	float l_val = fbm_lightning(p + vec2(TIME * 0.8, -TIME * 0.5));
	
	// Aislamos los filamentos estrechando los bordes con un smoothstep contrastado
	float glow = smoothstep(0.45, 0.90, l_val);
	
	// Añadir parpadeo de alta frecuencia (Flicker) tipo aura de Dragon Ball
	float flicker = 0.85 + 0.15 * sin(TIME * 45.0) * cos(TIME * 30.0);
	
	// Núcleo blanco incandescente hiper-denso y manto de energía exterior
	vec3 core_white = vec3(1.0, 1.0, 1.0);
	vec3 plasma_body = mix(base_color.rgb * 2.2, core_white, 0.45);
	vec3 lightning_burst = base_color.rgb * glow * flicker * 3.0;
	vec3 final_color = plasma_body + lightning_burst;
	
	ALBEDO = final_color;
	// Opacidad sólida y densa: 95% base + pulsaciones eléctricas, nunca transparente
	ALPHA = clamp((0.92 + glow * 0.15) * flicker, 0.0, 1.0);
}
