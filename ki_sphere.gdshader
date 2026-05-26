shader_type spatial;
render_mode blend_add, unshaded;

uniform vec4 base_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.1, 5.0) = 2.0;
uniform float fresnel_power : hint_range(0.1, 5.0) = 2.0;

void fragment() {
	// Efecto Fresnel (brillo en los bordes)
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), fresnel_power);
	
	// Pulsación simple
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);
	
	vec3 final_color = base_color.rgb * fresnel * pulse;
	
	ALBEDO = final_color;
	ALPHA = fresnel * pulse * base_color.a;
}
