shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float force : hint_range(-0.5, 0.5) = 0.08;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 0.3) = 0.08;

void fragment() {
	// dist va de 0.0 en el centro de la esfera visible al jugador, a 1.0 en los bordes
	float dist = 1.0 - dot(NORMAL, VIEW);
	
	// Máscara de anillo que se expande hacia afuera en función de progress
	float wave = smoothstep(progress - thickness, progress, dist) * 
				 smoothstep(progress + thickness, progress, dist);
				 
	// Dirección de desplazamiento radial en el espacio de la pantalla
	// Transformamos la normal a espacio de vista y usamos su proyección XY
	// Esto genera refracción radial perfecta desde el centro de la esfera en pantalla
	vec3 view_normal = (VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec2 disp_dir = normalize(view_normal.xy);
	vec2 displacement = disp_dir * wave * force * (1.0 - progress);
	
	// Muestrear el fondo con el desplazamiento en el espacio de pantalla
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV + displacement).rgb;
	
	// Destello luminoso en el frente de la onda expansiva térmica
	vec3 wave_glow = vec3(0.5, 0.85, 1.0) * wave * 0.25 * (1.0 - progress);
	
	ALBEDO = color + wave_glow;
	ALPHA = 1.0;
}
