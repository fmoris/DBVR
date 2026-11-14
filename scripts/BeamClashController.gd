class_name BeamClashController
extends Node3D

## BeamClashController (Godot 4.3+ VR)
## Controlador del Choque de Poderes (Beam Struggle Clash) entre dos Super Haces de Ki.
## Ambos rayos colisionan en un punto medio dinámico de la arena, generando un minijuego
## de empuje de Ki con dilatación temporal, pulso háptico y deformación del terreno.

signal clash_resolved(winner: Node3D, loser: Node3D, winning_tech: String)

var attacker: Node3D = null
var defender: Node3D = null
var tech_atk: String = "Kamehameha"
var tech_def: String = "Galick Ho"
var color_atk: Color = Color(0.2, 0.8, 1.0)
var color_def: Color = Color(0.9, 0.2, 1.0)

# Balance dinámico del choque: 0.0 (Gana atacante), 0.5 (Centro exacto), 1.0 (Gana defensor)
var clash_ratio: float = 0.5
var clash_timer: float = 0.0
var clash_duration: float = 3.5
var is_active: bool = false

# Nodos visuales del choque
var clash_sphere: MeshInstance3D = null
var clash_light: OmniLight3D = null
var beam_mesh_atk: MeshInstance3D = null
var beam_mesh_def: MeshInstance3D = null
var beam_inner_atk: MeshInstance3D = null
var beam_inner_def: MeshInstance3D = null
var shockwave_mesh: MeshInstance3D = null
var header_label: Label3D = null

# Audio 3D del choque
var audio_loop: AudioStreamPlayer3D = null
var audio_clash_impact: AudioStreamPlayer3D = null

# Detección de bombeo y empuje físico VR con manos hacia adelante
var prev_l_trig: bool = false
var prev_r_trig: bool = false
var prev_l_grip: bool = false
var prev_r_grip: bool = false
var _prev_l_hand_pos: Vector3 = Vector3.ZERO
var _prev_r_hand_pos: Vector3 = Vector3.ZERO
var _hand_track_init: bool = false
var _physical_push_cd: float = 0.0

const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const KiBeamShader = preload("res://shaders/ki_beam.gdshader")
const ShockwaveShader = preload("res://shaders/shockwave.gdshader")


func setup(
	p_attacker: Node3D,
	p_defender: Node3D,
	p_tech_atk: String,
	p_color_atk: Color,
	p_tech_def: String,
	p_color_def: Color,
	p_duration: float = 3.5
) -> void:
	attacker = p_attacker
	defender = p_defender
	tech_atk = p_tech_atk
	tech_def = p_tech_def
	color_atk = p_color_atk
	color_def = p_color_def
	clash_duration = p_duration
	clash_timer = 0.0
	clash_ratio = 0.5
	is_active = true

	# Ralentizar levemente el tiempo para enfatizar la escala del choque
	Engine.time_scale = 0.50

	_build_visuals()
	_build_audio()
	_update_beam_transforms()

	print("[BeamClash] ¡CHOQUE DE PODERES INICIADO! %s vs %s. Duración estimada: %.1fs" % [
		tech_atk, tech_def, clash_duration
	])


func _process(delta: float) -> void:
	if not is_active:
		return

	# delta no afectado por time_scale para la duración real
	var real_delta = delta / maxf(Engine.time_scale, 0.01)
	clash_timer += real_delta

	# 1. Procesar empuje del jugador humano (VR)
	_process_player_inputs(real_delta)

	# 2. Procesar resistencia de la IA
	_process_ai_resistance(real_delta)

	# 3. Actualizar geometría y posición de los rayos y la esfera central
	_update_beam_transforms()
	_update_hud()

	# 4. Pulsos hápticos continuos a los mandos del jugador
	_apply_continuous_clash_haptics()

	# 5. Evaluar condiciones de victoria del choque
	if clash_ratio <= 0.15:
		_resolve_clash(attacker, defender, tech_atk)
	elif clash_ratio >= 0.85:
		_resolve_clash(defender, attacker, tech_def)
	elif clash_timer >= clash_duration:
		# Al expirar el tiempo, el combatiente con la ventaja de empuje gana
		if clash_ratio < 0.5:
			_resolve_clash(attacker, defender, tech_atk)
		else:
			_resolve_clash(defender, attacker, tech_def)


func _process_player_inputs(real_delta: float) -> void:
	var player = _get_player_instance()
	if not player:
		return

	var origin: XROrigin3D = player.get_parent() as XROrigin3D if player.get("is_player") else null
	if not origin:
		return

	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	var l_trig = l_ctrl.get_float("trigger") > 0.60 or l_ctrl.is_button_pressed("trigger_click") if l_ctrl else false
	var r_trig = r_ctrl.get_float("trigger") > 0.60 or r_ctrl.is_button_pressed("trigger_click") if r_ctrl else false
	var l_grip = l_ctrl.get_float("grip") > 0.60 or l_ctrl.is_button_pressed("grip_click") if l_ctrl else false
	var r_grip = r_ctrl.get_float("grip") > 0.60 or r_ctrl.is_button_pressed("grip_click") if r_ctrl else false

	# Detección de pulsos de bombeo ("Pump / Push")
	var did_pulse = false
	if (l_trig and not prev_l_trig) or (r_trig and not prev_r_trig) or (l_grip and not prev_l_grip) or (r_grip and not prev_r_grip):
		did_pulse = true

	prev_l_trig = l_trig
	prev_r_trig = r_trig
	prev_l_grip = l_grip
	prev_r_grip = r_grip

	# Detección de empuje físico VR real de ambas manos hacia el punto de choque
	if _physical_push_cd > 0.0:
		_physical_push_cd -= real_delta
	var did_physical_push: bool = false
	if l_ctrl and r_ctrl and l_ctrl.get_is_active() and r_ctrl.get_is_active():
		var l_pos: Vector3 = l_ctrl.global_position
		var r_pos: Vector3 = r_ctrl.global_position
		if _hand_track_init and real_delta > 0.0001 and _physical_push_cd <= 0.0:
			var opp_node: Node3D = defender if player == attacker else attacker
			var push_dir: Vector3 = (opp_node.global_position - player.global_position).normalized() if (opp_node and is_instance_valid(opp_node)) else Vector3.FORWARD
			var l_fwd_speed: float = ((l_pos - _prev_l_hand_pos) / real_delta).dot(push_dir)
			var r_fwd_speed: float = ((r_pos - _prev_r_hand_pos) / real_delta).dot(push_dir)
			if l_fwd_speed > 1.35 or r_fwd_speed > 1.35:
				did_physical_push = true
				_physical_push_cd = 0.22
		_prev_l_hand_pos = l_pos
		_prev_r_hand_pos = r_pos
		_hand_track_init = true

	if did_pulse or did_physical_push:
		var push_power = 0.055 if did_physical_push else 0.045
		# Bonificación de empuje si está en modo Furia o Zenkai
		if player.get("is_in_zenkai_state"):
			push_power *= 1.45

		# Consumo de Ki por cada bombeo o empuje físico
		if player.has_method("consume_ki_or_life_force"):
			player.consume_ki_or_life_force(3.5 if did_physical_push else 4.0)

		# Si el jugador es el atacante, empuja clash_ratio hacia 0.0; si es defensor, hacia 1.0
		if player == attacker:
			clash_ratio = maxf(clash_ratio - push_power, 0.05)
		else:
			clash_ratio = minf(clash_ratio + push_power, 0.95)

		_pulse_haptic_burst(origin, 220.0, 1.0, 0.16)
		_spawn_clash_shockwave()


func _process_ai_resistance(real_delta: float) -> void:
	var ai = defender if attacker.get("is_player") else attacker
	if not ai or not is_instance_valid(ai):
		return

	var ai_ki = ai.get("current_ki") if ai.get("current_ki") != null else 50.0
	var ai_in_zenkai = ai.get("is_in_zenkai_state") if ai.get("is_in_zenkai_state") != null else false

	var base_ai_force = 0.08
	if ai_in_zenkai:
		base_ai_force *= 1.35
	if ai_ki < 15.0:
		base_ai_force *= 0.40 # IA pierde fuerza si se le agota el Ki

	# Pequeña variación pseudo-rítmica para simular ráfagas de esfuerzo de la IA
	var burst_mod = 1.0 + sin(clash_timer * 6.0) * 0.35
	var ai_push = base_ai_force * burst_mod * real_delta

	# Consumir Ki pasivo de la IA durante el choque
	if ai.has_method("consume_ki"):
		ai.consume_ki(3.0 * real_delta)

	if ai == attacker:
		clash_ratio = maxf(clash_ratio - ai_push, 0.05)
	else:
		clash_ratio = minf(clash_ratio + ai_push, 0.95)


func _get_fighter_hand_origin(fighter: Node3D, aim_toward: Vector3) -> Vector3:
	if not fighter or not is_instance_valid(fighter):
		return Vector3.ZERO
	if fighter.get("is_player"):
		var orig: Node = fighter.get_parent()
		if orig:
			var l_ctrl: XRController3D = orig.get_node_or_null("LeftHand") as XRController3D
			var r_ctrl: XRController3D = orig.get_node_or_null("RightHand") as XRController3D
			if l_ctrl and r_ctrl and l_ctrl.get_is_active() and r_ctrl.get_is_active():
				return (l_ctrl.global_position + r_ctrl.global_position) * 0.5
			elif r_ctrl and r_ctrl.get_is_active():
				return r_ctrl.global_position
			elif l_ctrl and l_ctrl.get_is_active():
				return l_ctrl.global_position
	var skel: Skeleton3D = fighter.get("skeleton") as Skeleton3D
	if skel and is_instance_valid(skel):
		var lh_idx: Variant = fighter.get("left_hand_idx")
		var rh_idx: Variant = fighter.get("right_hand_idx")
		if lh_idx is int and rh_idx is int and int(lh_idx) != -1 and int(rh_idx) != -1:
			var l_w: Vector3 = skel.global_transform * skel.get_bone_global_pose(int(lh_idx)).origin
			var r_w: Vector3 = skel.global_transform * skel.get_bone_global_pose(int(rh_idx)).origin
			return (l_w + r_w) * 0.5
	var fwd: Vector3 = (aim_toward - fighter.global_position).normalized()
	if fwd.length_squared() < 0.001:
		fwd = -fighter.global_transform.basis.z
	return fighter.global_position + Vector3(0.0, 1.25, 0.0) + fwd * 0.45


func _update_beam_transforms() -> void:
	if not attacker or not defender or not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var p_atk: Vector3 = _get_fighter_hand_origin(attacker, defender.global_position)
	var p_def: Vector3 = _get_fighter_hand_origin(defender, attacker.global_position)

	# Punto central del choque interpolado por clash_ratio
	# clash_ratio = 0.0 -> cerca del defensor
	# clash_ratio = 1.0 -> cerca del atacante
	var clash_pos = p_atk.lerp(p_def, 1.0 - clash_ratio)

	# Actualizar posición de la esfera de choque
	if clash_sphere and is_instance_valid(clash_sphere):
		clash_sphere.global_position = clash_pos
		var osc = 1.0 + sin(clash_timer * 25.0) * 0.12
		clash_sphere.scale = Vector3.ONE * (0.85 * osc)

	if clash_light and is_instance_valid(clash_light):
		clash_light.global_position = clash_pos

	if header_label and is_instance_valid(header_label):
		var target_pos: Vector3 = clash_pos + Vector3(0.0, 1.1, 0.0)
		var player_cam = _get_active_camera()
		if player_cam and is_instance_valid(player_cam):
			if target_pos.distance_to(player_cam.global_position) < 1.75:
				var cam_fwd: Vector3 = -player_cam.global_transform.basis.z.normalized()
				target_pos = player_cam.global_position + cam_fwd * 1.75 + Vector3(0.0, 0.22, 0.0)
			header_label.global_position = target_pos
			header_label.look_at(player_cam.global_position, Vector3.UP)
			header_label.rotate_y(PI)
		else:
			header_label.global_position = target_pos

	# 1. Haz exterior y núcleo blanco del Atacante (desde manos del atacante hasta clash_pos)
	if beam_mesh_atk and is_instance_valid(beam_mesh_atk):
		_position_beam(beam_mesh_atk, p_atk, clash_pos, 0.38)
	if beam_inner_atk and is_instance_valid(beam_inner_atk):
		_position_beam(beam_inner_atk, p_atk, clash_pos, 0.17)

	# 2. Haz exterior y núcleo blanco del Defensor (desde manos del defensor hasta clash_pos)
	if beam_mesh_def and is_instance_valid(beam_mesh_def):
		_position_beam(beam_mesh_def, p_def, clash_pos, 0.38)
	if beam_inner_def and is_instance_valid(beam_inner_def):
		_position_beam(beam_inner_def, p_def, clash_pos, 0.17)


func _position_beam(mesh_inst: MeshInstance3D, p_from: Vector3, p_to: Vector3, radius: float) -> void:
	var dist = p_from.distance_to(p_to)
	if dist < 0.05:
		mesh_inst.visible = false
		return
	mesh_inst.visible = true

	var cyl = mesh_inst.mesh as CylinderMesh
	if cyl:
		cyl.height = dist
		cyl.top_radius = radius
		cyl.bottom_radius = radius

	mesh_inst.global_position = (p_from + p_to) * 0.5
	var dir = (p_to - p_from).normalized()
	if dir.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(dir.y) < 0.95 else Vector3.FORWARD
		mesh_inst.look_at(mesh_inst.global_position + dir, up_vec)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _update_hud() -> void:
	if not header_label or not is_instance_valid(header_label):
		return

	var pct = clampf(clash_ratio, 0.0, 1.0)
	var bar_width = 16
	var marker_idx = int(pct * float(bar_width))
	var bar_str = ""
	for i in range(bar_width):
		if i == marker_idx:
			bar_str += "⚡"
		elif i < marker_idx:
			bar_str += "◀"
		else:
			bar_str += "▶"

	var player = _get_player_instance()
	var is_winning = (player == attacker and clash_ratio < 0.5) or (player == defender and clash_ratio > 0.5)
	var status_text = "¡MANTÉN LA PRESIÓN!" if is_winning else "¡BOMBEA KI PARA RESISTIR!"
	var col = Color(0.2, 1.0, 0.4) if is_winning else Color(1.0, 0.4, 0.2)

	header_label.text = "⚡ ¡CHOQUE DE PODERES! ⚡\n[ %s ]\n%s" % [bar_str, status_text]
	header_label.modulate = col


func _resolve_clash(winner: Node3D, loser: Node3D, winning_tech: String) -> void:
	if not is_active:
		return
	is_active = false
	Engine.time_scale = 1.0

	print("[BeamClash] 💥 ¡CHOQUE RESUELTO! Vencedor: %s con %s" % [
		winner.name if winner else "None", winning_tech
	])

	# Daño masivo de impacto directo para el perdedor (2200 NP base)
	var clash_damage = 2200.0
	if winner.get("is_in_zenkai_state"):
		clash_damage *= 1.65

	var dir_to_loser = (loser.global_position - winner.global_position).normalized()
	if loser and is_instance_valid(loser) and loser.has_method("take_hit"):
		loser.take_hit(clash_damage, dir_to_loser)
		if loser.has_method("apply_knockback"):
			loser.apply_knockback(dir_to_loser, 9.5)

	# Recompensas de Ki y BP al vencedor
	if winner and is_instance_valid(winner):
		if winner.has_method("recharge_ki"):
			winner.recharge_ki(45.0)
		if winner.has_method("increase_np"):
			winner.increase_np(600.0)
		if bool(winner.get("is_in_zenkai_state")) and winner.has_method("trigger_zenkai_match_finish"):
			winner.trigger_zenkai_match_finish(winner, loser, winning_tech)

	_spawn_colossal_explosion()

	# Emitir señal
	emit_signal("clash_resolved", winner, loser, winning_tech)

	# Desvanecer y limpiar
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _build_visuals() -> void:
	# 1. Esfera de colisión central
	clash_sphere = MeshInstance3D.new()
	clash_sphere.name = "ClashSphere"
	var sph = SphereMesh.new()
	sph.radius = 0.50
	sph.height = 1.0
	clash_sphere.mesh = sph

	var mat_sph = ShaderMaterial.new()
	mat_sph.shader = KiCoronaShader
	mat_sph.set_shader_parameter("base_color", color_atk.lerp(color_def, 0.5))
	mat_sph.set_shader_parameter("speed", 8.0)
	mat_sph.set_shader_parameter("vertex_displacement", 0.12)
	clash_sphere.material_override = mat_sph
	add_child(clash_sphere)

	# 2. Luz omnidireccional brillante
	clash_light = OmniLight3D.new()
	clash_light.name = "ClashLight"
	clash_light.light_color = color_atk.lerp(color_def, 0.5)
	clash_light.light_energy = 5.0
	clash_light.omni_range = 8.0
	add_child(clash_light)

	# 3. Haz del Atacante + Núcleo blanco incandescente interno
	beam_mesh_atk = MeshInstance3D.new()
	beam_mesh_atk.name = "BeamAtk"
	var cyl_atk = CylinderMesh.new()
	cyl_atk.radial_segments = 16
	beam_mesh_atk.mesh = cyl_atk

	var mat_atk = ShaderMaterial.new()
	mat_atk.shader = KiBeamShader
	mat_atk.set_shader_parameter("beam_color", color_atk)
	mat_atk.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	mat_atk.set_shader_parameter("flow_speed", 14.0)
	mat_atk.set_shader_parameter("core_intensity", 3.8)
	beam_mesh_atk.material_override = mat_atk
	add_child(beam_mesh_atk)

	var mat_inner_white := StandardMaterial3D.new()
	mat_inner_white.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_inner_white.albedo_color = Color(1.0, 1.0, 1.0, 0.96)

	beam_inner_atk = MeshInstance3D.new()
	beam_inner_atk.name = "BeamInnerAtk"
	var cyl_inner_atk = CylinderMesh.new()
	cyl_inner_atk.radial_segments = 12
	beam_inner_atk.mesh = cyl_inner_atk
	beam_inner_atk.material_override = mat_inner_white
	add_child(beam_inner_atk)

	# 4. Haz del Defensor + Núcleo blanco incandescente interno
	beam_mesh_def = MeshInstance3D.new()
	beam_mesh_def.name = "BeamDef"
	var cyl_def = CylinderMesh.new()
	cyl_def.radial_segments = 16
	beam_mesh_def.mesh = cyl_def

	var mat_def = ShaderMaterial.new()
	mat_def.shader = KiBeamShader
	mat_def.set_shader_parameter("beam_color", color_def)
	mat_def.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	mat_def.set_shader_parameter("flow_speed", 14.0)
	mat_def.set_shader_parameter("core_intensity", 3.8)
	beam_mesh_def.material_override = mat_def
	add_child(beam_mesh_def)

	beam_inner_def = MeshInstance3D.new()
	beam_inner_def.name = "BeamInnerDef"
	var cyl_inner_def = CylinderMesh.new()
	cyl_inner_def.radial_segments = 12
	beam_inner_def.mesh = cyl_inner_def
	beam_inner_def.material_override = mat_inner_white
	add_child(beam_inner_def)

	# 5. HUD 3D de balance
	header_label = Label3D.new()
	header_label.name = "ClashHUD"
	header_label.text = "⚡ ¡CHOQUE DE PODERES! ⚡"
	header_label.font_size = 28
	header_label.pixel_size = 0.0022
	header_label.no_depth_test = true
	header_label.render_priority = 115
	header_label.outline_size = 10
	header_label.outline_color = Color(0.0, 0.0, 0.0, 0.95)
	add_child(header_label)


func _build_audio() -> void:
	audio_loop = AudioStreamPlayer3D.new()
	audio_loop.name = "ClashLoopAudio"
	audio_loop.unit_size = 8.0
	audio_loop.max_distance = 40.0
	if ResourceLoader.exists("res://assets/sfx/AURA.mp3"):
		audio_loop.stream = load("res://assets/sfx/AURA.mp3")
		audio_loop.pitch_scale = 0.85
		audio_loop.play()
	add_child(audio_loop)


func _spawn_clash_shockwave() -> void:
	if not clash_sphere or not is_instance_valid(clash_sphere):
		return
	var sw = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(2.5, 2.5)
	sw.mesh = quad
	sw.rotation.x = -PI * 0.5
	sw.global_position = clash_sphere.global_position

	var mat = ShaderMaterial.new()
	mat.shader = ShockwaveShader
	mat.set_shader_parameter("ring_color", Color(1.0, 0.95, 0.4, 0.85))
	sw.material_override = mat
	get_parent().add_child(sw)

	var tw = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * 3.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, 0.35)
	tw.tween_callback(sw.queue_free)


func _spawn_colossal_explosion() -> void:
	var sw = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(8.0, 8.0)
	sw.mesh = quad
	sw.rotation.x = -PI * 0.5
	sw.global_position = clash_sphere.global_position if clash_sphere else global_position

	var mat = ShaderMaterial.new()
	mat.shader = ShockwaveShader
	mat.set_shader_parameter("ring_color", Color(1.0, 0.85, 0.2, 0.95))
	sw.material_override = mat
	get_tree().current_scene.add_child(sw)

	var tw = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * 5.0, 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, 0.65)
	tw.tween_callback(sw.queue_free)


func _apply_continuous_clash_haptics() -> void:
	var player = _get_player_instance()
	if not player:
		return
	var origin: XROrigin3D = player.get_parent() as XROrigin3D if player.get("is_player") else null
	if not origin:
		return

	# Vibración sostenida oscilante
	var freq = 160.0 + sin(clash_timer * 15.0) * 40.0
	for h in ["LeftHand", "RightHand"]:
		var ctrl = origin.get_node_or_null(h) as XRController3D
		if ctrl and ctrl.has_method("trigger_haptic_pulse"):
			ctrl.trigger_haptic_pulse("haptic", freq, 0.65, 0.05, 0.0)


func _pulse_haptic_burst(origin: XROrigin3D, freq: float, amp: float, dur: float) -> void:
	if not origin:
		return
	for h in ["LeftHand", "RightHand"]:
		var ctrl = origin.get_node_or_null(h) as XRController3D
		if ctrl and ctrl.has_method("trigger_haptic_pulse"):
			ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _get_player_instance() -> Node3D:
	if attacker and attacker.get("is_player"):
		return attacker
	if defender and defender.get("is_player"):
		return defender
	return null


func _get_active_camera() -> Camera3D:
	var p = _get_player_instance()
	if p:
		var orig = p.get_parent()
		if orig:
			return orig.get_node_or_null("XRCamera3D") as Camera3D
	var vp = get_viewport()
	return vp.get_camera_3d() if vp else null
