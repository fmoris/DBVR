shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

// --- Uniforms del Haz de Super Ki ---
uniform vec4 beam_color : source_color = vec4(0.2, 0.6, 1.0, 1.0); // Color característico de la técnica
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Núcleo blanco incandescente
uniform float flow_speed : hint_range(1.0, 30.0) = 14.0;           // Velocidad longitudinal de avance del plasma
uniform float beam_frequency : hint_range(1.0, 50.0) = 8.0;         // Frecuencia de ondas a lo largo del rayo
uniform float core_intensity : hint_range(1.0, 10.0) = 3.5;         // Brillo del núcleo central
uniform float edge_falloff : hint_range(0.1, 5.0) = 1.6;           // Gradiente de concentración central
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;

// Ruido pseudo-aleatorio para filamentos eléctricos del rayo
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float stream_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// Micro-vibración de alta energía anime en el volumen del haz
	float t = TIME * 35.0;
	float wobble = sin(VERTEX.y * 14.0 + t) * cos(VERTEX.x * 14.0 + t) * 0.03;
	VERTEX += NORMAL * wobble;
}

void fragment() {
	// Coordenadas UV proyectadas con flujo ultra rápido hacia el objetivo
	vec2 stream_uv = vec2(UV.x * noise_scale, UV.y * beam_frequency - TIME * flow_speed);
	float n1 = stream_noise(stream_uv);
	float n2 = stream_noise(stream_uv * 2.0 + vec2(TIME * 2.0, 0.0));
	float lightning_streaks = smoothstep(0.40, 0.90, n1 * 0.65 + n2 * 0.35);
	
	// Ángulo normal respecto a la vista: normal_dot = 1 en el centro del rayo, 0 en los bordes
	float normal_dot = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core_factor = pow(normal_dot, edge_falloff);
	
	// Parpadeo eléctrico de alta tensión
	float flicker = 0.90 + 0.10 * sin(TIME * 60.0);
	
	// Composición del plasma: Centro blanco puro hiper-incandescente + Envoltura de energía coloreada
	vec3 white_core = core_color.rgb * core_intensity * core_factor;
	vec3 sheath_plasma = beam_color.rgb * 2.6 * (1.0 - core_factor * 0.45);
	vec3 electric_burst = beam_color.rgb * lightning_streaks * 2.2;
	
	vec3 final_color = (white_core + sheath_plasma + electric_burst) * flicker;
	
	ALBEDO = final_color;
	// Opacidad densa y continua: 90% mínimo en el cuerpo del haz, aumentando en el núcleo
	ALPHA = clamp((0.88 + core_factor * 0.20 + lightning_streaks * 0.15) * flicker, 0.0, 1.0) * beam_color.a;
}
