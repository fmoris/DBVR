shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D particle_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity_mult : hint_range(0.0, 1.0) = 1.0;
uniform float fp_center_clear : hint_range(0.0, 1.0) = 0.0;
uniform float fp_clear_outer : hint_range(0.0, 0.99) = 0.72;
uniform float fp_clear_inner : hint_range(0.0, 1.0) = 0.94;

void vertex() {
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0001, INV_VIEW_MATRIX[0].z));
	vec3 up_vec = vec3(0.0, 1.0, 0.0);
	vec3 fwd = normalize(cross(cam_right, up_vec));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(cam_right * sx, 0.0),
		vec4(up_vec * sy, 0.0),
		vec4(fwd * sz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec4 tex = texture(particle_tex, UV);
	float mask = tex.a * max(tex.r, max(tex.g, tex.b));
	float center_align = smoothstep(fp_clear_outer, fp_clear_inner, clamp(VIEW.z, 0.0, 1.0));
	float fp_mask = mix(1.0, 1.0 - fp_center_clear, center_align);
	ALBEDO = tex.rgb * COLOR.rgb * 1.15;
	ALPHA = clamp(mask * COLOR.a * opacity_mult * fp_mask, 0.0, 1.0);
}
