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
var clash_bar_root: Node3D = null
var clash_player_fill: MeshInstance3D = null
var clash_enemy_fill: MeshInstance3D = null
var clash_divider_spark: MeshInstance3D = null
var clash_player_mat: StandardMaterial3D = null
var clash_enemy_mat: StandardMaterial3D = null

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
var _prev_l_vel: Vector3 = Vector3.ZERO
var _prev_r_vel: Vector3 = Vector3.ZERO
var _hand_track_init: bool = false
var _physical_push_cd: float = 0.0
var _is_burning_bp_in_clash: bool = false
var _in_phase2_pose: bool = true
var _player_desist_timer: float = 0.0
var clash_hud_anchor: Node3D = null
var clash_action_card_anchor: Node3D = null
var _clash_card_label: Label3D = null
var _clash_card_border_mat: StandardMaterial3D = null
var _last_clash_card_key: String = ""

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
	p_duration: float = 5.5,
	p_atk_damage: float = 1800.0,
	p_def_damage: float = 1800.0,
	p_atk_charge: float = 1.0,
	p_def_charge: float = 1.0
) -> void:
	attacker = p_attacker
	defender = p_defender
	tech_atk = p_tech_atk
	tech_def = p_tech_def
	color_atk = p_color_atk
	color_def = p_color_def
	clash_duration = p_duration
	clash_timer = 0.0

	# Ventaja inicial calculada con BP + carga + potencia de cada Super Poder
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
	var power_atk: float = bp_atk * (1.0 + clampf(p_atk_charge, 0.2, 3.0) * 0.25) * clampf(p_atk_damage / 1800.0, 0.7, 2.5)
	var power_def: float = bp_def * (1.0 + clampf(p_def_charge, 0.2, 3.0) * 0.25) * clampf(p_def_damage / 1800.0, 0.7, 2.5)
	var advantage: float = clampf((power_def - power_atk) / maxf(power_atk + power_def, 1.0), -0.25, 0.25)
	clash_ratio = 0.5 + advantage
	is_active = true
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_in_beam_clash", true)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_in_beam_clash", true)

	# Ralentizar levemente el tiempo para enfatizar la escala del choque
	Engine.time_scale = 0.42

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
	var dd_clash: DramaticDirector = DramaticDirector.get_active(get_tree())
	if dd_clash:
		var c_pos: Vector3 = clash_sphere.global_position if (clash_sphere and is_instance_valid(clash_sphere)) else global_position
		dd_clash.update_beam_clash_atmosphere(clash_ratio, color_atk, color_def, c_pos, true)

	# 4. Pulsos hápticos continuos a los mandos del jugador
	_apply_continuous_clash_haptics()

	# 5. Evaluar colapso por Ki == 0, desistimiento, tiempo expirado o impacto físico (0.0 / 1.0)
	_apply_exhaustion_or_timeout_surge(real_delta)

	if clash_ratio <= 0.0:
		_resolve_clash(attacker, defender, tech_atk)
	elif clash_ratio >= 1.0:
		_resolve_clash(defender, attacker, tech_def)


func _process_player_inputs(real_delta: float) -> void:
	var player = _get_player_instance()
	if not player:
		return

	var origin: XROrigin3D = player.get_parent() as XROrigin3D if player.get("is_player") else null
	if not origin:
		return

	var cam = origin.get_node_or_null("XRCamera3D") as Camera3D
	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	var l_trig = l_ctrl.get_float("trigger") > 0.60 or l_ctrl.is_button_pressed("trigger_click") if l_ctrl else false
	var r_trig = r_ctrl.get_float("trigger") > 0.60 or r_ctrl.is_button_pressed("trigger_click") if r_ctrl else false
	var l_grip = l_ctrl.get_float("grip") > 0.50 or l_ctrl.is_button_pressed("grip_click") if l_ctrl else false
	var r_grip = r_ctrl.get_float("grip") > 0.50 or r_ctrl.is_button_pressed("grip_click") if r_ctrl else false

	# 1. Mantener postura de Fase 2 (Grips sostenidos + manos proyectadas al frente)
	var hands_extended: bool = true
	if cam and l_ctrl and r_ctrl and l_ctrl.get_is_active() and r_ctrl.get_is_active():
		var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
		var l_z: float = (l_ctrl.global_position - cam.global_position).dot(cam_fwd)
		var r_z: float = (r_ctrl.global_position - cam.global_position).dot(cam_fwd)
		hands_extended = (l_z >= 0.16 or r_z >= 0.16)
	_in_phase2_pose = (l_grip or r_grip) and hands_extended

	var did_pulse = false
	if (l_trig and not prev_l_trig) or (r_trig and not prev_r_trig):
		did_pulse = true
	prev_l_trig = l_trig
	prev_r_trig = r_trig
	prev_l_grip = l_grip
	prev_r_grip = r_grip

	# 2. Medir agitación enérgica de los controles en espacio local del XROrigin3D (inmune a vibración/movimiento de cámara)
	if _physical_push_cd > 0.0:
		_physical_push_cd -= real_delta
	var shake_mag: float = 0.0
	if l_ctrl and r_ctrl and l_ctrl.get_is_active() and r_ctrl.get_is_active() and real_delta > 0.0001:
		var orig_basis: Basis = origin.global_transform.basis.orthonormalized()
		var l_loc: Vector3 = l_ctrl.position
		var r_loc: Vector3 = r_ctrl.position
		if _hand_track_init:
			var l_vel: Vector3 = orig_basis * ((l_loc - _prev_l_hand_pos) / real_delta)
			var r_vel: Vector3 = orig_basis * ((r_loc - _prev_r_hand_pos) / real_delta)
			var l_accel: float = (l_vel - _prev_l_vel).length() / maxf(real_delta, 0.001)
			var r_accel: float = (r_vel - _prev_r_vel).length() / maxf(real_delta, 0.001)
			shake_mag = (l_vel.length() + r_vel.length()) * 0.5 + (l_accel + r_accel) * 0.035
			_prev_l_vel = l_vel
			_prev_r_vel = r_vel
		_prev_l_hand_pos = l_loc
		_prev_r_hand_pos = r_loc
		_hand_track_init = true

	_is_burning_bp_in_clash = false
	if _in_phase2_pose:
		_player_desist_timer = 0.0
	else:
		_player_desist_timer += real_delta
		return

	var p_ki_check: float = float(player.get("current_ki")) if player.get("current_ki") != null else 0.0
	if p_ki_check <= 0.0:
		return

	var push_power: float = 0.0
	var is_shaking: bool = shake_mag >= 1.50
	if is_shaking:
		push_power += clampf((shake_mag - 1.2) * 0.065 * real_delta, 0.01 * real_delta, 0.15 * real_delta)
	if did_pulse:
		push_power += 0.030

	if push_power <= 0.0:
		return

	if player.get("is_in_zenkai_state"):
		push_power *= 1.45

	# 3. Consumo de Ki; si Ki llega a 0, permite seguir compitiendo gastando BP (Último Aliento)
	var ki_cost: float = (11.0 * real_delta if is_shaking else 0.0) + (2.5 if did_pulse else 0.0)
	var p_ki: float = float(player.get("current_ki")) if player.get("current_ki") != null else 0.0
	if p_ki > 0.0:
		if player.has_method("consume_ki"):
			player.consume_ki(minf(p_ki, ki_cost))
	else:
		_is_burning_bp_in_clash = true
		var bp_burn: float = maxf(ki_cost * 38.0, 25.0 * real_delta)
		var p_np: float = float(player.get("current_np")) if player.get("current_np") != null else 0.0
		var new_np: float = maxf(p_np - bp_burn, 0.0)
		player.set("current_np", new_np)
		if player.has_method("_notify_stats"):
			player._notify_stats()
		if new_np <= 0.0:
			var opp_win: Node3D = defender if player == attacker else attacker
			var opp_tech: String = tech_def if player == attacker else tech_atk
			_resolve_clash(opp_win, player, opp_tech)
			return

	if player == attacker:
		clash_ratio = maxf(clash_ratio - push_power, 0.0)
	else:
		clash_ratio = minf(clash_ratio + push_power, 1.0)

	if _physical_push_cd <= 0.0:
		_physical_push_cd = 0.20
		_pulse_haptic_burst(origin, 220.0, 1.0, 0.14)
		_spawn_clash_shockwave()


func _apply_exhaustion_or_timeout_surge(real_delta: float) -> void:
	var atk_ki: float = float(attacker.get("current_ki")) if (attacker and is_instance_valid(attacker) and attacker.get("current_ki") != null) else 0.0
	var def_ki: float = float(defender.get("current_ki")) if (defender and is_instance_valid(defender) and defender.get("current_ki") != null) else 0.0
	var atk_is_player: bool = bool(attacker and is_instance_valid(attacker) and attacker.get("is_player"))
	var def_is_player: bool = bool(defender and is_instance_valid(defender) and defender.get("is_player"))

	var atk_collapsed: bool = (atk_ki <= 0.0) or (atk_is_player and _player_desist_timer >= 0.40)
	var def_collapsed: bool = (def_ki <= 0.0) or (def_is_player and _player_desist_timer >= 0.40)

	if atk_collapsed and not def_collapsed:
		clash_ratio = minf(clash_ratio + 1.65 * real_delta, 1.0)
	elif def_collapsed and not atk_collapsed:
		clash_ratio = maxf(clash_ratio - 1.65 * real_delta, 0.0)
	elif clash_timer >= clash_duration:
		if clash_ratio < 0.5:
			clash_ratio = maxf(clash_ratio - 1.90 * real_delta, 0.0)
		else:
			clash_ratio = minf(clash_ratio + 1.90 * real_delta, 1.0)


func _process_ai_resistance(real_delta: float) -> void:
	var ai = defender if attacker.get("is_player") else attacker
	if not ai or not is_instance_valid(ai):
		return

	var ai_ki: float = float(ai.get("current_ki")) if ai.get("current_ki") != null else 0.0
	if ai_ki <= 0.0:
		return
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
		clash_ratio = maxf(clash_ratio - ai_push, 0.0)
	else:
		clash_ratio = minf(clash_ratio + ai_push, 1.0)


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

	if header_label and is_instance_valid(header_label) and (not clash_hud_anchor or not is_instance_valid(clash_hud_anchor)):
		var player_cam: Camera3D = _get_active_camera()
		if player_cam and is_instance_valid(player_cam):
			_build_visuals_hud_attach()
		else:
			header_label.global_position = clash_pos + Vector3(0.0, 1.1, 0.0)

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


func get_player_clash_progress() -> float:
	var player: Node3D = _get_player_instance()
	if player and attacker and player == attacker:
		return clampf((0.85 - clash_ratio) / 0.70, 0.0, 1.0)
	if player and defender and player == defender:
		return clampf((clash_ratio - 0.15) / 0.70, 0.0, 1.0)
	return clampf((0.85 - clash_ratio) / 0.70, 0.0, 1.0)


func _update_hud() -> void:
	if not header_label or not is_instance_valid(header_label):
		return

	var p_prog: float = get_player_clash_progress()
	var player: Node3D = _get_player_instance()
	var is_winning: bool = p_prog >= 0.50

	if clash_player_fill and is_instance_valid(clash_player_fill):
		var p_fill: float = clampf(p_prog, 0.01, 0.99)
		clash_player_fill.scale = Vector3(p_fill, 1.0, 1.0)
		clash_player_fill.position.x = -0.23 + 0.23 * p_fill
	if clash_enemy_fill and is_instance_valid(clash_enemy_fill):
		var e_fill: float = clampf(1.0 - p_prog, 0.01, 0.99)
		clash_enemy_fill.scale = Vector3(e_fill, 1.0, 1.0)
		clash_enemy_fill.position.x = 0.23 - 0.23 * e_fill
	if clash_divider_spark and is_instance_valid(clash_divider_spark):
		clash_divider_spark.position.x = -0.23 + 0.46 * p_prog

	var status_text: String = "¡SIGUE EMPUJANDO! AGITA LOS CONTROLES" if is_winning else "¡TE ESTÁN GANANDO! AGITA RÁPIDO"
	var col: Color = Color(0.25, 1.0, 0.45) if is_winning else Color(1.0, 0.45, 0.2)
	if not _in_phase2_pose:
		status_text = "⚠️ ¡EXTIENDE MANOS CON GRIP (FASE 2)!"
		col = Color(1.0, 0.25, 0.25)
	elif _is_burning_bp_in_clash:
		status_text = "⚠️ ¡SIN KI! QUEMANDO BP PARA RESISTIR"
		col = Color(1.0, 0.55, 0.15)

	var pct_p: int = int(roundf(p_prog * 100.0))
	header_label.text = "⚡ CHOQUE DE PODER: TÚ %d%% vs %d%% RIVAL ⚡\n%s" % [pct_p, 100 - pct_p, status_text]
	header_label.modulate = col
	_refresh_clash_action_card()


func _resolve_clash(winner: Node3D, loser: Node3D, winning_tech: String) -> void:
	if not is_active:
		return
	is_active = false
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_in_beam_clash", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_in_beam_clash", false)
	Engine.time_scale = 1.0

	print("[BeamClash] 💥 ¡CHOQUE RESUELTO! Vencedor: %s con %s" % [
		winner.name if winner else "None", winning_tech
	])

	# Daño masivo de impacto directo para el perdedor (2200 NP base) + lanzamiento único con Air Brake
	var clash_damage: float = 2200.0
	if winner and winner.get("is_in_zenkai_state"):
		clash_damage *= 1.65

	var dir_to_loser: Vector3 = (loser.global_position - winner.global_position).normalized() if (winner and loser) else Vector3.BACK
	if loser and is_instance_valid(loser) and loser.has_method("take_hit"):
		loser.take_hit(clash_damage, dir_to_loser, false)
		if loser.has_method("apply_knockback"):
			loser.apply_knockback(dir_to_loser, 16.0, 2.4)

	var dd_res: DramaticDirector = DramaticDirector.get_active(get_tree())
	if dd_res:
		var r_pos: Vector3 = clash_sphere.global_position if (clash_sphere and is_instance_valid(clash_sphere)) else global_position
		dd_res.on_beam_clash_resolved(r_pos)

	# Recompensas de Ki y BP al vencedor
	if winner and is_instance_valid(winner):
		var was_winner_zenkai: bool = bool(winner.get("is_in_zenkai_state"))
		if winner.has_method("recharge_ki"):
			winner.recharge_ki(45.0)
		if winner.has_method("increase_np"):
			winner.increase_np(600.0)
		if was_winner_zenkai and winner.has_method("trigger_zenkai_match_finish"):
			winner.trigger_zenkai_match_finish(winner, loser, winning_tech)
		elif (bool(winner.get("is_in_furia")) or clash_timer >= 2.8) and winner.has_method("trigger_comeback_zenkai"):
			winner.trigger_comeback_zenkai()

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

	# 5. HUD 3D de balance (título + barra diegética de tira y afloja)
	header_label = Label3D.new()
	header_label.name = "ClashHUD"
	header_label.text = "⚡ ¡CHOQUE DE PODERES! ⚡"
	header_label.font_size = 24
	header_label.pixel_size = 0.0014
	header_label.no_depth_test = true
	header_label.render_priority = 125
	header_label.outline_size = 10
	header_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_build_clash_diegetic_bar()
	_build_visuals_hud_attach()
	_update_hud()


func _build_clash_diegetic_bar() -> void:
	if clash_bar_root and is_instance_valid(clash_bar_root):
		return
	clash_bar_root = Node3D.new()
	clash_bar_root.name = "ClashDiegeticBar"

	var player: Node3D = _get_player_instance()
	var player_col: Color = color_atk if (player and attacker and player == attacker) else color_def
	var enemy_col: Color = color_def if (player and attacker and player == attacker) else color_atk

	var bg_mesh := MeshInstance3D.new()
	bg_mesh.name = "ClashBarBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.48, 0.044)
	bg_mesh.mesh = bg_q
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 122
	bg_mat.albedo_color = Color(0.05, 0.07, 0.12, 0.88)
	bg_mesh.material_override = bg_mat
	clash_bar_root.add_child(bg_mesh)

	clash_player_fill = MeshInstance3D.new()
	clash_player_fill.name = "ClashPlayerFill"
	var pf_q := QuadMesh.new()
	pf_q.size = Vector2(0.46, 0.030)
	clash_player_fill.mesh = pf_q
	clash_player_fill.position = Vector3(-0.115, 0.0, 0.002)
	clash_player_mat = StandardMaterial3D.new()
	clash_player_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	clash_player_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clash_player_mat.no_depth_test = true
	clash_player_mat.render_priority = 123
	clash_player_mat.albedo_color = Color(player_col.r, player_col.g, player_col.b, 0.96)
	clash_player_fill.material_override = clash_player_mat
	clash_bar_root.add_child(clash_player_fill)

	clash_enemy_fill = MeshInstance3D.new()
	clash_enemy_fill.name = "ClashEnemyFill"
	var ef_q := QuadMesh.new()
	ef_q.size = Vector2(0.46, 0.030)
	clash_enemy_fill.mesh = ef_q
	clash_enemy_fill.position = Vector3(0.115, 0.0, 0.002)
	clash_enemy_mat = StandardMaterial3D.new()
	clash_enemy_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	clash_enemy_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clash_enemy_mat.no_depth_test = true
	clash_enemy_mat.render_priority = 123
	clash_enemy_mat.albedo_color = Color(enemy_col.r, enemy_col.g, enemy_col.b, 0.96)
	clash_enemy_fill.material_override = clash_enemy_mat
	clash_bar_root.add_child(clash_enemy_fill)

	var center_tick := MeshInstance3D.new()
	center_tick.name = "ClashCenterTick"
	var ct_q := QuadMesh.new()
	ct_q.size = Vector2(0.005, 0.052)
	center_tick.mesh = ct_q
	center_tick.position = Vector3(0.0, 0.0, 0.003)
	var ct_mat := StandardMaterial3D.new()
	ct_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ct_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ct_mat.no_depth_test = true
	ct_mat.render_priority = 125
	ct_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.72)
	center_tick.material_override = ct_mat
	clash_bar_root.add_child(center_tick)

	clash_divider_spark = MeshInstance3D.new()
	clash_divider_spark.name = "ClashDividerSpark"
	var ds_q := QuadMesh.new()
	ds_q.size = Vector2(0.014, 0.058)
	clash_divider_spark.mesh = ds_q
	clash_divider_spark.position = Vector3(0.0, 0.0, 0.004)
	var ds_mat := StandardMaterial3D.new()
	ds_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ds_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ds_mat.no_depth_test = true
	ds_mat.render_priority = 126
	ds_mat.albedo_color = Color(1.0, 0.96, 0.45, 1.0)
	clash_divider_spark.material_override = ds_mat
	clash_bar_root.add_child(clash_divider_spark)


func _exit_tree() -> void:
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_in_beam_clash", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_in_beam_clash", false)
	if is_active:
		var dd_ex: DramaticDirector = DramaticDirector.get_active(get_tree())
		if dd_ex:
			dd_ex.update_beam_clash_atmosphere(0.5, color_atk, color_def, global_position, false)
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	if clash_hud_anchor and is_instance_valid(clash_hud_anchor):
		clash_hud_anchor.queue_free()
		clash_hud_anchor = null
	if clash_action_card_anchor and is_instance_valid(clash_action_card_anchor):
		clash_action_card_anchor.queue_free()
		clash_action_card_anchor = null


func _ensure_clash_action_card() -> void:
	var cam: Camera3D = _get_active_camera()
	if not cam or not is_instance_valid(cam):
		return
	if clash_action_card_anchor and is_instance_valid(clash_action_card_anchor):
		return

	clash_action_card_anchor = Node3D.new()
	clash_action_card_anchor.name = "ClashActionGuideCardAnchor"
	clash_action_card_anchor.position = Vector3(0.0, -0.34, -1.10)
	clash_action_card_anchor.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	cam.add_child(clash_action_card_anchor)

	var border := MeshInstance3D.new()
	border.name = "CardBorder"
	var b_q := QuadMesh.new()
	b_q.size = Vector2(0.58, 0.22)
	border.mesh = b_q
	_clash_card_border_mat = StandardMaterial3D.new()
	_clash_card_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_clash_card_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_clash_card_border_mat.no_depth_test = true
	_clash_card_border_mat.render_priority = 122
	_clash_card_border_mat.albedo_color = Color(1.0, 0.80, 0.20, 0.92)
	border.material_override = _clash_card_border_mat
	clash_action_card_anchor.add_child(border)

	var bg := MeshInstance3D.new()
	bg.name = "CardBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.565, 0.205)
	bg.mesh = bg_q
	bg.position = Vector3(0.0, 0.0, 0.001)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 123
	bg_mat.albedo_color = Color(0.03, 0.05, 0.10, 0.88)
	bg.material_override = bg_mat
	clash_action_card_anchor.add_child(bg)

	_clash_card_label = Label3D.new()
	_clash_card_label.name = "ClashCardText"
	_clash_card_label.font_size = 22
	_clash_card_label.pixel_size = 0.00130
	_clash_card_label.no_depth_test = true
	_clash_card_label.render_priority = 124
	_clash_card_label.outline_size = 6
	_clash_card_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_clash_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_clash_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clash_card_label.position = Vector3(-0.26, 0.0, 0.002)
	clash_action_card_anchor.add_child(_clash_card_label)
	_last_clash_card_key = ""
	_refresh_clash_action_card()


func _refresh_clash_action_card() -> void:
	if not _clash_card_label or not is_instance_valid(_clash_card_label):
		return
	var state_key: String = "C:%d:%d" % [1 if _in_phase2_pose else 0, 1 if _is_burning_bp_in_clash else 0]
	if state_key == _last_clash_card_key:
		return
	_last_clash_card_key = state_key
	if _clash_card_border_mat:
		_clash_card_border_mat.albedo_color = Color(0.25, 0.95, 0.55, 0.92) if _in_phase2_pose else Color(1.0, 0.25, 0.25, 0.95)
	_clash_card_label.modulate = Color(0.95, 0.98, 1.0) if _in_phase2_pose else Color(1.0, 0.85, 0.85)
	var line1: String = "[✅] 1. Manos al frente + 2 GRIPS" if _in_phase2_pose else "[⚠️] 1. ¡EXTIENDE MANOS + 2 GRIPS!"
	var line3: String = "[🔥] 3. Pulsa GATILLOS sin parar"
	if _is_burning_bp_in_clash:
		line3 = "[⚠️] 3. ¡SIN KI! Quemando BP"
	_clash_card_label.text = "⚡ CONTROLES DEL CHOQUE ⚡\n%s\n[⚡] 2. Agita ambos mandos rápido\n%s" % [line1, line3]


func _build_visuals_hud_attach() -> void:
	var cam: Camera3D = _get_active_camera()
	if cam and is_instance_valid(cam):
		_ensure_clash_action_card()
		clash_hud_anchor = Node3D.new()
		clash_hud_anchor.name = "ClashHUDAnchor"
		clash_hud_anchor.position = Vector3(0.0, 0.24, -1.20)
		cam.add_child(clash_hud_anchor)
		if header_label.get_parent() and header_label.get_parent() != clash_hud_anchor:
			header_label.get_parent().remove_child(header_label)
		if not header_label.get_parent():
			clash_hud_anchor.add_child(header_label)
		header_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		header_label.position = Vector3(0.0, 0.045, 0.0)
		if clash_bar_root and is_instance_valid(clash_bar_root):
			if clash_bar_root.get_parent() and clash_bar_root.get_parent() != clash_hud_anchor:
				clash_bar_root.get_parent().remove_child(clash_bar_root)
			if not clash_bar_root.get_parent():
				clash_hud_anchor.add_child(clash_bar_root)
			clash_bar_root.position = Vector3(0.0, -0.025, 0.0)
	else:
		if not header_label.get_parent():
			add_child(header_label)
		if clash_bar_root and is_instance_valid(clash_bar_root) and not clash_bar_root.get_parent():
			add_child(clash_bar_root)
			clash_bar_root.position = Vector3(0.0, 1.0, 0.0)


func _build_audio() -> void:
	audio_loop = AudioStreamPlayer3D.new()
	audio_loop.name = "ClashLoopAudio"
	audio_loop.unit_size = 8.0
	audio_loop.max_distance = 40.0
	add_child(audio_loop)
	var fallback_clash: AudioStream = load("res://assets/sfx/AURA.mp3") if ResourceLoader.exists("res://assets/sfx/AURA.mp3") else null
	audio_loop.pitch_scale = 0.85
	AudioActionManager.play_action("common.beam_clash", audio_loop, fallback_clash, true)


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
	KiSmokeFX.spawn_smoke(get_tree(), clash_sphere.global_position, 1.35)


func _spawn_colossal_explosion() -> void:
	var sw = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(8.0, 8.0)
	sw.mesh = quad
	sw.rotation.x = -PI * 0.5
	var exp_pos: Vector3 = clash_sphere.global_position if (clash_sphere and is_instance_valid(clash_sphere) and clash_sphere.is_inside_tree()) else global_position

	var mat = ShaderMaterial.new()
	mat.shader = ShockwaveShader
	mat.set_shader_parameter("ring_color", Color(1.0, 0.85, 0.2, 0.95))
	sw.material_override = mat
	var exp_parent: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if exp_parent:
		exp_parent.add_child(sw)
		sw.global_position = exp_pos

	var tw = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * 5.0, 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, 0.65)
	tw.tween_callback(sw.queue_free)
	KiSmokeFX.spawn_smoke(get_tree(), exp_pos, 2.4)


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
