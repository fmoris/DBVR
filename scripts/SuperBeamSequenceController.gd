class_name SuperBeamSequenceController
extends Node3D

## SuperBeamSequenceController (Godot 4.3+ VR)
## Controlador de la Secuencia Cinemática y Bullet-Time para Super Ataques de Ki.
## Ralentiza el tiempo de forma adaptativa según el diferencial de NP entre los combatientes.
## Ofrece al defensor 4 respuestas tácticas: Z-Vanish, Desvío Físico, Bloqueo de Contención y Choque de Haces.

signal sequence_completed(action_result: String, damage_dealt: float)
signal beam_clash_initiated(clash_controller: Node3D)

enum BeamState {
	ADVANCING_BULLET_TIME,
	HAND_HOLDING,
	IMPACTING,
	DEFLECTED,
	BLOCKED,
	EVADED,
	HIT_CONFIRMED,
	CLASHING,
	COMPLETED
}

var attacker: Node3D = null
var defender: Node3D = null
var power_name: String = "Kamehameha"
var energy_color: Color = Color(0.2, 0.8, 1.0)
var base_damage: float = 1800.0
var tier: int = 3
var is_orb_super: bool = false

var state: BeamState = BeamState.ADVANCING_BULLET_TIME
var is_active: bool = false
var reaction_duration: float = 2.2
var time_left: float = 2.2
var beam_progress: float = 0.0 # 0.0 en atacante, 1.0 en defensor
var impact_sustain_timer: float = 0.0
const IMPACT_SUSTAIN_DURATION: float = 1.00

# Posiciones clave
var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var beam_dir: Vector3 = Vector3.FORWARD
var current_head_pos: Vector3 = Vector3.ZERO
var prev_head_pos: Vector3 = Vector3.ZERO
var fired_aim_dir: Vector3 = Vector3.ZERO
var is_aimed_miss: bool = false
var miss_target_pos: Vector3 = Vector3.ZERO

# Nodos visuales del haz
var beam_core_mesh: MeshInstance3D = null
var beam_head_mesh: MeshInstance3D = null
var beam_light: OmniLight3D = null
var reticle_mesh: MeshInstance3D = null
var alert_label: Label3D = null
var beam_hud_anchor: Node3D = null
var super_action_card_anchor: Node3D = null
var _super_card_label: Label3D = null
var _super_card_border_mat: StandardMaterial3D = null
var hold_progress: float = 0.0
var hold_required_sec: float = 1.65
var hold_stall_timer: float = 0.0
var _reading_pause_timer: float = 0.0
var _last_card_state_key: String = ""

# Audio espacial
var audio_player: AudioStreamPlayer3D = null
var sfx_clash: AudioStream = null

# Seguimiento cinemático de manos para desvío físico
var prev_l_hand_pos: Vector3 = Vector3.ZERO
var prev_r_hand_pos: Vector3 = Vector3.ZERO
var l_hand_vel: Vector3 = Vector3.ZERO
var r_hand_vel: Vector3 = Vector3.ZERO

const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const ZenkaiAuraShader = preload("res://shaders/zenkai_aura.gdshader")
const KiBeamShader = preload("res://shaders/ki_beam.gdshader")
const ShockwaveShader = preload("res://shaders/shockwave.gdshader")
const BeamClashControllerClass = preload("res://scripts/BeamClashController.gd")


func _get_attacker_hand_position() -> Vector3:
	if not attacker or not is_instance_valid(attacker):
		return start_pos

	var p_low: String = power_name.to_lower()
	var is_genkidama: bool = "genkidama" in p_low
	var is_big_bang: bool = "big bang" in p_low

	if attacker.get("is_player"):
		var origin = attacker.get_parent() as XROrigin3D
		if origin:
			var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
			var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D
			if is_big_bang:
				var gss: Node = origin.get_parent().get_node_or_null("GesturePhaseTree") if origin.get_parent() else null
				var bb_hand: int = int(gss.get("big_bang_hand")) if (gss and gss.get("big_bang_hand") != null) else 1
				var active_ctrl: XRController3D = l_ctrl if (bb_hand == 0 and l_ctrl) else (r_ctrl if r_ctrl else l_ctrl)
				if active_ctrl:
					return active_ctrl.global_position
			if l_ctrl and r_ctrl:
				var mid: Vector3 = (l_ctrl.global_position + r_ctrl.global_position) * 0.5
				return (mid + Vector3(0.0, 0.75, 0.0)) if is_genkidama else mid
			elif r_ctrl:
				return (r_ctrl.global_position + Vector3(0.0, 0.75, 0.0)) if is_genkidama else r_ctrl.global_position
			elif l_ctrl:
				return (l_ctrl.global_position + Vector3(0.0, 0.75, 0.0)) if is_genkidama else l_ctrl.global_position
	else:
		var skel = attacker.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
		if not skel:
			skel = attacker.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			var rw_idx = skel.find_bone("RightWrist")
			var lw_idx = skel.find_bone("LeftWrist")
			if is_big_bang and rw_idx != -1:
				return skel.to_global(skel.get_bone_global_pose(rw_idx).origin)
			if rw_idx != -1 and lw_idx != -1:
				var r_global = skel.to_global(skel.get_bone_global_pose(rw_idx).origin)
				var l_global = skel.to_global(skel.get_bone_global_pose(lw_idx).origin)
				var mid_ai: Vector3 = (r_global + l_global) * 0.5
				return (mid_ai + Vector3(0.0, 0.75, 0.0)) if is_genkidama else mid_ai
		var fb_y: float = 2.05 if is_genkidama else 1.25
		return attacker.global_position + attacker.global_transform.basis * Vector3(0.0, fb_y, 0.55)
	
	return attacker.global_position + Vector3(0.0, 2.05 if is_genkidama else 1.25, 0.0)


func _get_defender_target_position() -> Vector3:
	if not defender or not is_instance_valid(defender):
		return target_pos
	if defender.get("is_player"):
		var origin = defender.get_parent() as XROrigin3D
		if origin:
			var cam = origin.get_node_or_null("XRCamera3D") as Camera3D
			if cam:
				return cam.global_position - Vector3(0.0, 0.20, 0.0)
	return defender.global_position + Vector3(0.0, 1.25, 0.0)


func setup(
	p_attacker: Node3D,
	p_defender: Node3D,
	p_power_name: String,
	p_color: Color,
	p_base_damage: float,
	p_tier: int = 3,
	p_aim_dir: Vector3 = Vector3.ZERO
) -> void:
	attacker = p_attacker
	defender = p_defender
	power_name = p_power_name
	energy_color = p_color
	base_damage = p_base_damage
	if attacker and is_instance_valid(attacker) and attacker.has_method("get_dramatic_modifier"):
		base_damage *= attacker.get_dramatic_modifier("damage_mult", 1.0) * attacker.get_dramatic_modifier("super_damage_mult", 1.0)
	tier = p_tier
	var p_low: String = power_name.to_lower()
	is_orb_super = ("big bang" in p_low) or ("genkidama" in p_low)

	state = BeamState.ADVANCING_BULLET_TIME
	is_active = true

	# Notificar a ambos combatientes que están en secuencia de Super Haz
	if attacker and attacker.has_method("set"):
		attacker.set("is_in_beam_sequence", true)
		attacker.set("is_firing_beam", true)
		attacker.set("beam_tech_name", power_name)
	if defender and defender.has_method("set"):
		defender.set("is_in_beam_sequence", true)

	# 1. Calcular Bullet-Time Adaptativo según la jerarquía de poder
	reaction_duration = _calculate_adaptive_reaction_time()
	time_left = reaction_duration

	# 2. Calcular trayectorias dinámicas desde las manos del atacante y evaluar puntería real
	start_pos = _get_attacker_hand_position()
	var def_pos: Vector3 = _get_defender_target_position()
	var to_def_vec: Vector3 = def_pos - start_pos
	var dist_to_def: float = maxf(to_def_vec.length(), 0.1)
	var to_def_dir: Vector3 = to_def_vec / dist_to_def

	if p_aim_dir.length_squared() > 0.01:
		fired_aim_dir = p_aim_dir.normalized()
		var dot_def: float = fired_aim_dir.dot(to_def_dir)
		var closest_pt: Vector3 = start_pos + fired_aim_dir * (dist_to_def * maxf(dot_def, 0.0))
		var perp_dist: float = closest_pt.distance_to(def_pos)
		var hit_radius: float = maxf(1.35, dist_to_def * 0.085)
		if dot_def > 0.25 and (perp_dist <= hit_radius or dot_def >= 0.985):
			is_aimed_miss = false
			target_pos = def_pos.lerp(closest_pt, 0.25)
			fired_aim_dir = (target_pos - start_pos).normalized()
		else:
			is_aimed_miss = true
			miss_target_pos = start_pos + fired_aim_dir * maxf(dist_to_def + 10.0, 24.0)
			if miss_target_pos.y < 0.15:
				miss_target_pos.y = 0.15
			target_pos = miss_target_pos
	else:
		is_aimed_miss = false
		target_pos = def_pos
		fired_aim_dir = to_def_dir

	beam_dir = (target_pos - start_pos).normalized()
	current_head_pos = start_pos
	prev_head_pos = start_pos

	# 3. Aplicar dilatación temporal (Bullet-Time profundo en impacto o vuelo rápido en tiro fallado)
	if is_aimed_miss:
		reaction_duration = 0.65
		time_left = reaction_duration
		_reading_pause_timer = 0.0
		Engine.time_scale = 0.65
	else:
		var is_player_def: bool = defender != null and is_instance_valid(defender) and bool(defender.get("is_player"))
		_reading_pause_timer = 1.0 if is_player_def else 0.0
		Engine.time_scale = 0.05 if _reading_pause_timer > 0.0 else 0.11

	_build_visual_beam()
	_build_reticle_and_hud()
	_build_audio()

	# Si el defensor es la IA y el tiro va al cuerpo, evaluar su respuesta anticipada
	if defender and not defender.get("is_player") and not is_aimed_miss:
		_plan_ai_defense_reaction()

	print("[SuperBeamSequence] ⚡ ¡SECUENCIA DE SUPER HAZ INICIADA! %s -> %s (Miss: %s | Ventana Bullet-Time: %.2fs)" % [
		power_name, defender.name if defender else "Rival", str(is_aimed_miss), reaction_duration
	])


func _process(delta: float) -> void:
	if not is_active:
		return

	if state == BeamState.ADVANCING_BULLET_TIME:
		# delta real no afectado por time_scale para la cuenta regresiva subjetiva
		var real_delta = delta / maxf(Engine.time_scale, 0.01)
		if _reading_pause_timer > 0.0:
			_reading_pause_timer = maxf(_reading_pause_timer - real_delta, 0.0)
			if _reading_pause_timer <= 0.0 and not is_aimed_miss:
				Engine.time_scale = 0.11
		else:
			time_left -= real_delta

		# Anclar el origen del rayo en tiempo real a las manos del atacante
		start_pos = _get_attacker_hand_position()
		if is_aimed_miss:
			target_pos = miss_target_pos
		else:
			var def_now: Vector3 = _get_defender_target_position()
			var d_now: float = start_pos.distance_to(def_now)
			var aimed_pt: Vector3 = start_pos + fired_aim_dir * d_now
			target_pos = def_now.lerp(aimed_pt, 0.30)
		beam_dir = (target_pos - start_pos).normalized()

		# Avance continuo desde que sale de las manos del atacante (0% -> 88% en Bullet-Time, 88% -> 100% impacto)
		prev_head_pos = current_head_pos
		var norm_t: float = clampf(1.0 - (time_left / maxf(reaction_duration, 0.01)), 0.0, 1.0)
		if is_aimed_miss:
			beam_progress = norm_t
		elif norm_t < 0.90:
			beam_progress = lerpf(0.0, 0.88, norm_t / 0.90)
		else:
			beam_progress = lerpf(0.88, 1.0, (norm_t - 0.90) / 0.10)
		current_head_pos = start_pos.lerp(target_pos, beam_progress)

		_update_beam_geometry()
		_update_hud(time_left)
		_pulse_firing_haptics()

		# Evaluar respuestas defensivas únicamente cuando el ataque va dirigido al defensor
		if not is_aimed_miss:
			_update_defender_hand_velocities(real_delta)
			if defender and defender.get("is_player"):
				_check_player_defense_options()
			else:
				_check_ai_defense_trigger()

		# Detección de colisión: en tiros desviados, comprobar impacto contra terreno/rocas (capa 1)
		var dist_to_target: float = current_head_pos.distance_to(target_pos)
		if is_aimed_miss:
			var space_env: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() and get_world_3d() else null
			if space_env and prev_head_pos.distance_squared_to(current_head_pos) > 0.0025:
				var rq := PhysicsRayQueryParameters3D.create(prev_head_pos, current_head_pos)
				rq.collision_mask = 1
				var r_hit: Dictionary = space_env.intersect_ray(rq)
				if not r_hit.is_empty():
					current_head_pos = r_hit["position"]
					target_pos = current_head_pos
					_resolve_aimed_miss()
					return
			if dist_to_target <= 0.85 or time_left <= 0.0 or beam_progress >= 0.98 or current_head_pos.y <= 0.15:
				_resolve_aimed_miss()
		else:
			if time_left <= 0.0 or beam_progress >= 0.98 or (norm_t >= 0.88 and dist_to_target <= 0.85):
				_resolve_direct_hit()

	elif state == BeamState.HAND_HOLDING:
		_process_hand_holding(delta)

	elif state == BeamState.IMPACTING:
		impact_sustain_timer -= delta
		# Mantener el haz extendido desde las manos hasta el punto de impacto
		start_pos = _get_attacker_hand_position()
		current_head_pos = target_pos
		_update_beam_geometry()
		_pulse_impact_haptics()

		# Destellos y chispas de plasma continuas en el punto de contacto
		if int(impact_sustain_timer * 20.0) % 3 == 0:
			_spawn_spark_at(current_head_pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), randf_range(-0.25, 0.25)), energy_color)

		if impact_sustain_timer <= 0.0:
			state = BeamState.HIT_CONFIRMED
			is_active = false
			_cleanup_and_finish("direct_hit", base_damage)


func _calculate_adaptive_reaction_time() -> float:
	var np_atk = attacker.get("current_np") if attacker and attacker.get("current_np") != null else 10000.0
	var np_def = defender.get("current_np") if defender and defender.get("current_np") != null else 10000.0

	var diff_ratio = clampf((float(np_def) - float(np_atk)) / maxf(float(np_atk), 100.0), -0.50, 0.80)
	var base_t: float = 4.5
	if defender and (bool(defender.get("is_in_zenkai_state")) or bool(defender.get("is_in_furia"))):
		base_t = 5.0 # Ventana más amplia en Zenkai o Furia para permitir remontada épica

	var bt_mult: float = defender.get_dramatic_modifier("bullet_time_mult", 1.0) if (defender and is_instance_valid(defender) and defender.has_method("get_dramatic_modifier")) else 1.0
	return maxf(base_t * (1.0 + diff_ratio), 2.4) * bt_mult


func _check_player_defense_options() -> void:
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return

	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D
	var cam = origin.get_node_or_null("XRCamera3D") as Camera3D

	if defender and is_instance_valid(defender) and bool(defender.get("is_defenseless_crash")):
		return

	var l_grip: bool = (l_ctrl.get_float("grip") > 0.55 or l_ctrl.is_button_pressed("grip_click")) if l_ctrl else false
	var r_grip: bool = (r_ctrl.get_float("grip") > 0.55 or r_ctrl.is_button_pressed("grip_click")) if r_ctrl else false
	var l_trig: bool = (l_ctrl.get_float("trigger") > 0.55 or l_ctrl.is_button_pressed("trigger_click")) if l_ctrl else false
	var r_trig: bool = (r_ctrl.get_float("trigger") > 0.55 or r_ctrl.is_button_pressed("trigger_click")) if r_ctrl else false

	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
	var def_ki: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 0.0

	# OPCIÓN 1: CHOQUE DE SUPER PODER (BEAM CLASH) — con Super Poder propio usable del personaje
	if defender.get("is_charging_super") or defender.get("is_firing_beam"):
		var counter_info: Dictionary = _get_signature_counter_beam(defender)
		if bool(counter_info.get("usable", true)) and def_ki >= 15.0:
			var hands_fwd_ok: bool = true
			if cam and l_ctrl and r_ctrl:
				var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
				var l_z: float = (l_ctrl.global_position - cam.global_position).dot(cam_fwd)
				var r_z: float = (r_ctrl.global_position - cam.global_position).dot(cam_fwd)
				hands_fwd_ok = (l_z >= 0.22 and r_z >= 0.22) or bool(defender.get("is_firing_beam"))
			if hands_fwd_ok:
				_trigger_beam_clash(defender, String(counter_info["name"]), counter_info["color"], float(counter_info.get("damage", 1800.0)))
				return

	# OPCIÓN 2: ESQUIVAR (Z-VANISH) — flick rápido en joystick izquierdo o derecho (15 Ki)
	var stick_l: Vector2 = l_ctrl.get_vector2("primary") if l_ctrl else Vector2.ZERO
	var stick_r: Vector2 = r_ctrl.get_vector2("primary") if r_ctrl else Vector2.ZERO
	if (stick_l.length() > 0.72 or stick_r.length() > 0.72 or defender.get("is_teleporting")) and def_ki >= 15.0:
		_resolve_evasion()
		return

	# OPCIÓN 3: AGUANTAR EL PODER CON LAS MANOS (extender manos al frente + ambos Grips sin Trigger + agitar)
	if l_grip and r_grip and not (l_trig and r_trig) and cam and l_ctrl and r_ctrl:
		var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
		var l_z: float = (l_ctrl.global_position - cam.global_position).dot(cam_fwd)
		var r_z: float = (r_ctrl.global_position - cam.global_position).dot(cam_fwd)
		if l_z >= 0.26 and r_z >= 0.26:
			_start_hand_holding(bp_atk, bp_def)
			return

	# OPCIÓN 4: DESVÍO FÍSICO CON LA MANO (Batear el rayo al cielo; exige BP competitivo >= 70% del atacante)
	var l_pos = l_ctrl.global_position if l_ctrl else Vector3.ZERO
	var r_pos = r_ctrl.global_position if r_ctrl else Vector3.ZERO
	var dist_l = current_head_pos.distance_to(l_pos)
	var dist_r = current_head_pos.distance_to(r_pos)
	if (dist_l < 1.80 and l_hand_vel.length() > 2.0) or (dist_r < 1.80 and r_hand_vel.length() > 2.0):
		if bp_def >= bp_atk * 0.70:
			_resolve_deflection()
		else:
			_resolve_containment_block(true)
		return

	# OPCIÓN 5: DEFENSA DE BRAZOS CRUZADOS (Grip + Trigger cruzados al pecho)
	if ((l_grip and l_trig) or (r_grip and r_trig) or defender.get("is_blocking")) and _is_defender_crossing_arms(origin):
		_resolve_containment_block(false)
		return


var ai_planned_action: String = "clash"
var ai_action_time: float = 0.8

func _plan_ai_defense_reaction() -> void:
	var ai_ki = defender.get("current_ki") if defender and defender.get("current_ki") != null else 50.0
	var ai_zenkai = defender.get("is_in_zenkai_state") if defender and defender.get("is_in_zenkai_state") != null else false
	var is_obscured: bool = defender != null and is_instance_valid(defender) and bool(defender.get("smoke_obscures_active")) and (float(defender.get("smoke_obscured_timer")) if defender.get("smoke_obscured_timer") != null else 0.0) > 0.0
	var in_crater_stun: bool = defender != null and is_instance_valid(defender) and (defender.get("ground_crater_stun_timer") != null and float(defender.get("ground_crater_stun_timer")) > 0.0)
	var clash_prob: float = 0.15 if in_crater_stun else (0.35 if is_obscured else 0.70)
	var vanish_prob: float = 0.0 if in_crater_stun else (0.25 if is_obscured else 0.55)
	var block_prob: float = 0.40 if in_crater_stun else 0.65
	var delay_extra: float = 0.55 if in_crater_stun else (0.35 if is_obscured else 0.0)

	if ai_ki >= 45.0 and ((ai_zenkai and not in_crater_stun) or randf() < clash_prob):
		ai_planned_action = "clash"
		ai_action_time = minf(randf_range(0.45, reaction_duration * 0.75) + delay_extra, reaction_duration * 0.92)
	elif ai_ki >= 25.0 and randf() < vanish_prob:
		ai_planned_action = "vanish"
		ai_action_time = minf(randf_range(0.5, reaction_duration * 0.85) + delay_extra, reaction_duration * 0.92)
	elif randf() < block_prob:
		ai_planned_action = "block"
		ai_action_time = minf(randf_range(0.3, reaction_duration * 0.60) + delay_extra * 0.6, reaction_duration * 0.92)
	else:
		ai_planned_action = "hit"


func _check_ai_defense_trigger() -> void:
	if reaction_duration - time_left >= ai_action_time:
		match ai_planned_action:
			"clash":
				var counter_info: Dictionary = _get_signature_counter_beam(defender)
				_trigger_beam_clash(defender, String(counter_info["name"]), counter_info["color"])
			"vanish":
				_resolve_evasion()
			"block":
				_resolve_containment_block()


func _get_signature_counter_beam(fighter: Node3D) -> Dictionary:
	var fallback_name: String = "Kamehameha"
	var fallback_col: Color = Color(0.2, 0.8, 1.0)
	if not fighter or not is_instance_valid(fighter):
		return { "name": fallback_name, "color": fallback_col }

	var cdata = fighter.get("character_data")
	if cdata:
		var cname: String = String(cdata.get("character_name")).to_upper()
		var cur_trans = fighter.get("current_transformation")
		var cur_form: String = String(cur_trans.get("form_name")) if cur_trans else ""
		if "VEGETA" in cname:
			fallback_name = "Final Flash" if ("SSJ" in cur_form.to_upper()) else "Galick Ho"
			fallback_col = Color(1.0, 0.85, 0.15) if ("SSJ" in cur_form.to_upper()) else Color(0.85, 0.25, 1.0)
		var powers = cdata.get("powers")
		if powers is Array:
			for p in powers:
				if p:
					var trig_u: String = String(p.gesture_trigger).to_upper()
					var pname_u: String = String(p.power_name).to_upper()
					var is_beam: bool = ("KAMEHAMEHA" in trig_u or "GALICK" in trig_u or "FINAL_FLASH" in trig_u or "KAMEHAMEHA" in pname_u or "GALICK" in pname_u or "FINAL FLASH" in pname_u)
					if is_beam and not p.forbidden_transformations.has(cur_form):
						if p.unlock_requirement_transformation == "" or (fighter.has_method("is_transformation_unlocked") and fighter.is_transformation_unlocked(p.unlock_requirement_transformation)):
							var p_col: Color = p.energy_color if p.energy_color.a > 0.05 else fallback_col
							var p_dmg: float = float(p.base_damage_np) if "base_damage_np" in p else 1800.0
							return { "name": p.power_name, "color": p_col, "damage": p_dmg, "usable": true }
	return { "name": fallback_name, "color": fallback_col, "damage": 1800.0, "usable": true }


func _trigger_beam_clash(clash_defender: Node3D, counter_tech: String, counter_color: Color, counter_damage: float = 1800.0) -> void:
	state = BeamState.CLASHING
	is_active = false
	Engine.time_scale = 1.0

	var atk_charge: float = clampf(float(attacker.get("last_super_charge_time")) if (attacker and attacker.get("last_super_charge_time") != null) else 1.0, 0.4, 3.0)
	var def_charge: float = clampf(float(clash_defender.get("last_super_charge_time")) if (clash_defender and clash_defender.get("last_super_charge_time") != null) else 0.8, 0.4, 3.0)

	# Instanciar el controlador del Choque de Haces con BP y carga reales
	var clash = BeamClashControllerClass.new()
	clash.name = "BeamClashController"
	var clash_parent: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if clash_parent:
		clash_parent.add_child(clash)
	else:
		add_sibling(clash)
	clash.setup(attacker, clash_defender, power_name, energy_color, counter_tech, counter_color, 5.5, base_damage, counter_damage, atk_charge, def_charge)

	emit_signal("beam_clash_initiated", clash)
	print("[SuperBeamSequence] ⚡ ¡CHOQUE DE PODERES ACTIVADO! Transfiriendo control a BeamClashController.")

	# Limpiar esta secuencia para dar paso al choque
	_cleanup_and_finish("clash", 0.0)


func _resolve_deflection() -> void:
	state = BeamState.DEFLECTED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	# Recompensas de maestría marcial
	if defender and is_instance_valid(defender):
		if defender.has_method("recharge_ki"):
			defender.recharge_ki(25.0)
		if defender.has_method("increase_np"):
			defender.increase_np(300.0)
		if bool(defender.get("is_in_furia")) and not bool(defender.get("is_in_zenkai_state")) and defender.has_method("trigger_comeback_zenkai"):
			defender.trigger_comeback_zenkai()

	_spawn_spark_at(current_head_pos, Color(1.0, 0.9, 0.2))

	# Pulso háptico de desvío
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = origin.get_node_or_null(h) as XRController3D
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 240.0, 1.0, 0.20, 0.0)

	# Desviar la trayectoria visual del haz 55 grados hacia el cielo
	var sky_target = current_head_pos + (beam_dir + Vector3.UP * 1.8).normalized() * 45.0
	var tw = create_tween()
	tw.tween_method(func(p: Vector3):
		target_pos = p
		current_head_pos = p
		_update_beam_geometry()
	, target_pos, sky_target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	print("[SuperBeamSequence] 🥋 ¡DESVÍO FÍSICO EXITOSO! El haz fue bateado hacia la estratósfera (+25 Ki, +300 BP).")
	tw.tween_callback(func(): _cleanup_and_finish("deflected", 0.0))


func _start_hand_holding(bp_atk: float, bp_def: float) -> void:
	state = BeamState.HAND_HOLDING
	hold_progress = 0.0
	hold_stall_timer = 0.0
	hold_required_sec = clampf(1.85 * sqrt(bp_atk / maxf(bp_def, 100.0)), 1.30, 2.40)
	Engine.time_scale = 0.35


func _process_hand_holding(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	start_pos = _get_attacker_hand_position()
	target_pos = _get_defender_target_position()
	beam_dir = (target_pos - start_pos).normalized()
	current_head_pos = target_pos - beam_dir * 0.65
	_update_beam_geometry()
	_update_defender_hand_velocities(real_delta)

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if (defender and defender.get("is_player")) else null
	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D if origin else null
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D if origin else null
	var l_grip: bool = (l_ctrl.get_float("grip") > 0.50 or l_ctrl.is_button_pressed("grip_click")) if l_ctrl else false
	var r_grip: bool = (r_ctrl.get_float("grip") > 0.50 or r_ctrl.is_button_pressed("grip_click")) if r_ctrl else false

	if not (l_grip and r_grip):
		# Soltó los Grips antes de disipar el rayo -> impacto directo
		_resolve_direct_hit()
		return

	var shake_speed: float = l_hand_vel.length() + r_hand_vel.length()
	if shake_speed >= 1.35:
		hold_stall_timer = 0.0
		var shake_boost: float = clampf(shake_speed / 3.0, 0.75, 1.85)
		hold_progress += (real_delta * shake_boost) / maxf(hold_required_sec, 0.5)
		if defender and defender.has_method("consume_ki_or_life_force"):
			defender.consume_ki_or_life_force(9.0 * real_delta)
		if origin:
			for h in ["LeftHand", "RightHand"]:
				var ctrl = origin.get_node_or_null(h) as XRController3D
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 190.0, 0.85, 0.08, 0.0)
	else:
		hold_stall_timer += real_delta
		if hold_stall_timer >= 0.45:
			_resolve_direct_hit()
			return

	_update_hud(hold_progress)
	if hold_progress >= 1.0:
		_resolve_hand_hold_dissipated()


func _resolve_hand_hold_dissipated() -> void:
	state = BeamState.BLOCKED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	var chip_dmg: float = base_damage * 0.10
	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(chip_dmg, beam_dir, false)
		if defender.has_method("apply_knockback"):
			defender.apply_knockback(beam_dir, 4.0)
	_spawn_spark_at(current_head_pos, Color(0.45, 0.95, 1.0))
	_cleanup_and_finish("hand_held", chip_dmg)


func _resolve_containment_block(is_failed_deflect: bool = false) -> void:
	state = BeamState.BLOCKED
	is_active = false
	Engine.time_scale = 1.0

	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
	var bp_ratio: float = clampf(sqrt(bp_atk / bp_def), 0.50, 2.2)

	var def_ki: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 0.0
	var guard_broken: bool = def_ki < 12.0
	var mitigated_damage: float = base_damage * (0.55 if (guard_broken or is_failed_deflect) else 0.25)

	if defender and is_instance_valid(defender):
		if defender.has_method("consume_ki"):
			defender.consume_ki(minf(def_ki, 16.0))
		if defender.has_method("take_hit"):
			defender.take_hit(mitigated_damage, beam_dir, false)
		if defender.has_method("apply_knockback"):
			var kb_spd: float = (9.5 if guard_broken else 5.0) * bp_ratio
			defender.apply_knockback(beam_dir, kb_spd, 2.6)

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed") and not guard_broken:
		attacker.notify_attack_failed()

	_spawn_spark_at(current_head_pos, Color(1.0, 0.35, 0.2) if guard_broken else Color(0.2, 0.8, 1.0))

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if (defender and defender.get("is_player")) else null
	if origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = origin.get_node_or_null(h) as XRController3D
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 180.0, 0.90 if guard_broken else 0.75, 0.35, 0.0)

	if guard_broken and attacker and is_instance_valid(attacker) and bool(attacker.get("is_in_zenkai_state")) and attacker.has_method("trigger_zenkai_match_finish"):
		attacker.trigger_zenkai_match_finish(attacker, defender, power_name)

	_cleanup_and_finish("guard_break" if guard_broken else "blocked", mitigated_damage)


static func compute_super_explosion_splash(
	blast_pos: Vector3,
	target_pos: Vector3,
	blast_radius: float,
	base_super_dmg: float,
	atk_bp: float,
	def_bp: float
) -> Dictionary:
	var dist: float = blast_pos.distance_to(target_pos)
	if dist > blast_radius:
		return { "in_radius": false, "damage_bp": 0.0, "knockback_speed": 0.0, "no_sell": false, "proximity": 0.0, "power_ratio": 0.0 }
	var prox: float = clampf(1.0 - (dist / maxf(blast_radius, 0.1)), 0.0, 1.0)
	var attack_power_bp: float = maxf(atk_bp, 1000.0) * clampf(base_super_dmg / 1800.0, 0.75, 2.20)
	var power_ratio: float = attack_power_bp / maxf(def_bp, 1000.0)
	if power_ratio <= 0.55 or (power_ratio * prox) <= 0.22:
		return { "in_radius": true, "damage_bp": 0.0, "knockback_speed": 0.0, "no_sell": true, "proximity": prox, "power_ratio": power_ratio }
	var intensity: float = clampf((power_ratio - 0.50) * prox, 0.05, 1.60)
	var dmg_bp: float = base_super_dmg * 0.45 * intensity
	var kb_speed: float = clampf(4.5 + intensity * 14.0, 0.0, 24.0)
	if kb_speed < 3.0:
		kb_speed = 0.0
	return { "in_radius": true, "damage_bp": dmg_bp, "knockback_speed": kb_speed, "no_sell": false, "proximity": prox, "power_ratio": power_ratio }


func _get_super_explosion_radius() -> float:
	var p_low: String = power_name.to_lower()
	if "genkidama" in p_low:
		return 14.0
	if "big bang" in p_low or "final flash" in p_low or "super kamehameha" in p_low or "10x" in p_low:
		return 11.0
	return 9.0


func _spawn_super_aoe_explosion(blast_pos: Vector3, apply_splash_to_defender: bool) -> Dictionary:
	var blast_radius: float = _get_super_explosion_radius()
	var exp_parent: Node = (get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent())

	if exp_parent and exp_parent.is_inside_tree():
		if is_inside_tree() and get_tree():
			ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), blast_pos, 4, energy_color, true)
			KiSmokeFX.spawn_smoke(get_tree(), blast_pos, 2.2)

	var result: Dictionary = { "in_radius": false, "damage_bp": 0.0, "knockback_speed": 0.0, "no_sell": false }
	if apply_splash_to_defender and defender and is_instance_valid(defender) and not bool(defender.get("is_match_over")):
		var atk_bp: float = float(attacker.get("current_np")) if (attacker and is_instance_valid(attacker) and attacker.get("current_np") != null) else 10000.0
		var def_bp: float = float(defender.get("current_np")) if (defender.get("current_np") != null) else 10000.0
		var def_center: Vector3 = defender.global_position + Vector3(0.0, 1.0, 0.0)
		result = compute_super_explosion_splash(blast_pos, def_center, blast_radius, base_damage, atk_bp, def_bp)

		if bool(result.get("in_radius", false)):
			var def_name: String = defender.character_data.character_name if (defender.get("character_data") and "character_name" in defender.character_data) else defender.name
			if bool(result.get("no_sell", false)):
				if defender.has_method("_spawn_bp_delta_popup"):
					defender._spawn_bp_delta_popup(0.0, "0 BP · INMUNE")
				if defender.has_method("_log_combat_event"):
					defender._log_combat_event("🛡️ ¡%s RESISTIÓ LA ONDA EXPANSIVA SIN MOVERSE! (0 BP)" % def_name, "success")
				if attacker and is_instance_valid(attacker) and attacker.has_method("_log_combat_event"):
					attacker._log_combat_event("🛡️ ¡%s aguantó la onda explosiva de %s sin daño ni retroceso! (0 BP)" % [def_name, power_name], "warning")
			else:
				var dmg_bp: float = float(result.get("damage_bp", 0.0))
				var kb_speed: float = float(result.get("knockback_speed", 0.0))
				var radial_dir: Vector3 = defender.global_position - blast_pos
				radial_dir.y = 0.0
				if radial_dir.length_squared() < 0.01:
					radial_dir = beam_dir
				else:
					radial_dir = (radial_dir.normalized() + Vector3(0.0, 0.25, 0.0)).normalized()

				defender.set("_last_hit_attacker_bp", maxf(atk_bp, 1000.0))
				defender.set("_last_hit_damage_np", dmg_bp)
				if defender.has_method("take_hit"):
					defender.take_hit(dmg_bp, radial_dir, false)
				if kb_speed >= 3.0 and defender.has_method("apply_knockback"):
					defender.apply_knockback(radial_dir, kb_speed, 2.4)
				if defender.has_method("_log_combat_event"):
					defender._log_combat_event("💥 ¡ONDA EXPANSIVA DE %s! (-%d BP | Empuje %.1f m/s)" % [power_name.to_upper(), int(dmg_bp), kb_speed], "warning")
	return result


func _resolve_evasion() -> void:
	state = BeamState.EVADED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	if defender and is_instance_valid(defender) and defender.has_method("consume_ki"):
		defender.consume_ki(15.0)

	# Determinar punto real de explosión al continuar su trayectoria recta (colisión con suelo/montaña o fin de rango cercano)
	var mountain_target: Vector3 = start_pos + beam_dir * 48.0
	var space_env: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() and get_world_3d() else null
	if space_env:
		var rq := PhysicsRayQueryParameters3D.create(current_head_pos, mountain_target)
		rq.collision_mask = 1
		var hit: Dictionary = space_env.intersect_ray(rq)
		if not hit.is_empty():
			mountain_target = hit["position"]

	var tw = create_tween()
	tw.tween_method(func(p: Vector3):
		current_head_pos = p
		_update_beam_geometry()
	, current_head_pos, mountain_target, 0.40).set_trans(Tween.TRANS_LINEAR)

	print("[SuperBeamSequence] 💨 ¡Z-VANISH EVASIVO! El haz pasó de largo y detonó al impacto.")
	tw.tween_callback(func():
		if is_instance_valid(self):
			_spawn_super_aoe_explosion(mountain_target, true)
			_cleanup_and_finish("evaded", 0.0)
	)


func _resolve_aimed_miss() -> void:
	if state == BeamState.IMPACTING or state == BeamState.HIT_CONFIRMED or state == BeamState.EVADED:
		return
	state = BeamState.EVADED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	_spawn_spark_at(current_head_pos, energy_color)
	if current_head_pos.y <= 3.0:
		_spawn_plasma_crater(Vector3(current_head_pos.x, 0.12, current_head_pos.z), 2.4, energy_color)

	# Explosión AoE con onda expansiva (daño BP + empuje según BP ataque vs BP defensor)
	_spawn_super_aoe_explosion(current_head_pos, true)
	var adm_miss: ArenaDestructionManager = ArenaDestructionManager.get_active(get_tree())
	if adm_miss:
		var bp_atk_m: float = float(attacker.get("current_np")) if (attacker and is_instance_valid(attacker) and attacker.get("current_np") != null) else 10000.0
		adm_miss.apply_power_aoe_destruction(current_head_pos, 16.0, base_damage, bp_atk_m)

	if attacker and is_instance_valid(attacker) and attacker.has_method("_log_combat_event"):
		attacker._log_combat_event("💥 ¡%s detonó cerca del objetivo! (Onda expansiva)" % power_name, "info")

	print("[SuperBeamSequence] 💥 ¡DETONACIÓN DE EXPLOSIÓN %s en %s!" % [power_name, str(current_head_pos)])
	_cleanup_and_finish("missed", 0.0)


func _resolve_direct_hit() -> void:
	if state == BeamState.IMPACTING or state == BeamState.HIT_CONFIRMED:
		return
	state = BeamState.IMPACTING
	impact_sustain_timer = IMPACT_SUSTAIN_DURATION
	Engine.time_scale = 1.0

	var final_damage = base_damage
	if attacker and attacker.get("is_in_zenkai_state"):
		final_damage *= 1.5

	# 1. Aplicar daño y empuje proporcional a la diferencia de BP (sale volando si el atacante es superior)
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
	var bp_ratio: float = clampf(sqrt(bp_atk / bp_def), 0.45, 2.8)
	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(final_damage, beam_dir, false)
		if defender.has_method("apply_knockback"):
			defender.apply_knockback(beam_dir, clampf(28.0 * bp_ratio, 22.0, 40.0), 1.6)
		if defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(2.5, beam_dir)

	# 2. Notificar al atacante para sostener la pose de empuje de energía
	if attacker and is_instance_valid(attacker):
		if attacker.has_method("increase_np"):
			attacker.increase_np(final_damage * 0.35)
		attacker.set("is_firing_beam", true)
		attacker.set("beam_tech_name", power_name)

	# 3. Onda de choque doble, esfera de explosión volumétrica, humo denso DBZ y destrucción de entorno
	_spawn_spark_at(current_head_pos, energy_color)
	_spawn_spark_at(current_head_pos + Vector3.UP * 0.5, Color(1.0, 0.95, 0.75))
	_spawn_super_impact_explosion_vfx(current_head_pos, energy_color, bp_ratio)
	if current_head_pos.y <= 3.0:
		_spawn_plasma_crater(Vector3(current_head_pos.x, 0.12, current_head_pos.z), 2.8 * clampf(bp_ratio, 0.8, 1.5), energy_color)
	var adm_hit: ArenaDestructionManager = ArenaDestructionManager.get_active(get_tree())
	if adm_hit:
		adm_hit.apply_power_aoe_destruction(current_head_pos, 18.0 * clampf(bp_ratio, 0.8, 1.6), final_damage, bp_atk)
		adm_hit.spawn_dense_dbz_smoke(current_head_pos, defender, 3.0 * clampf(bp_ratio, 0.85, 1.5), 2.2)
	_pulse_impact_haptics()

	print("[SuperBeamSequence] 💥 ¡IMPACTO DIRECTO DE SUPER HAZ! %s colisionó con el defensor (Daño: %.0f NP)." % [power_name, final_damage])

	var atk_in_zenkai: bool = bool(attacker and is_instance_valid(attacker) and (attacker.get("is_in_zenkai_state") or attacker.get("is_comeback_zenkai")))
	if atk_in_zenkai and defender and is_instance_valid(defender):
		if attacker.has_method("trigger_zenkai_match_finish"):
			attacker.trigger_zenkai_match_finish(attacker, defender, power_name)


func _cleanup_and_finish(result: String, dmg: float) -> void:
	if attacker and is_instance_valid(attacker):
		attacker.set("is_firing_beam", false)
		if attacker.has_method("set"):
			attacker.set("is_in_beam_sequence", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_in_beam_sequence", false)

	if audio_player and is_instance_valid(audio_player):
		audio_player.stop()

	emit_signal("sequence_completed", result, dmg)

	if (result == "direct_hit" or result == "hit") and attacker and is_instance_valid(attacker) and not bool(attacker.get("is_match_over")):
		if defender and is_instance_valid(defender) and attacker.has_method("start_post_super_followup"):
			attacker.start_post_super_followup(defender)

	var tw = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _pulse_firing_haptics() -> void:
	if attacker and attacker.get("is_player"):
		var orig = attacker.get_parent() as XROrigin3D
		if orig:
			for h in ["LeftHand", "RightHand"]:
				var ctrl = orig.get_node_or_null(h) as XRController3D
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 120.0, 0.45, 0.08, 0.0)


func _pulse_impact_haptics() -> void:
	if attacker and attacker.get("is_player"):
		var orig = attacker.get_parent() as XROrigin3D
		if orig:
			for h in ["LeftHand", "RightHand"]:
				var ctrl = orig.get_node_or_null(h) as XRController3D
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 190.0, 0.85, 0.12, 0.0)
	if defender and defender.get("is_player"):
		var orig = defender.get_parent() as XROrigin3D
		if orig:
			for h in ["LeftHand", "RightHand"]:
				var ctrl = orig.get_node_or_null(h) as XRController3D
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 260.0, 1.0, 0.15, 0.0)


func _update_defender_hand_velocities(delta: float) -> void:
	if not defender or not defender.get("is_player"):
		return
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return

	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	if l_ctrl:
		var cur_l = l_ctrl.global_position
		if prev_l_hand_pos != Vector3.ZERO and delta > 0.001:
			l_hand_vel = (cur_l - prev_l_hand_pos) / delta
		prev_l_hand_pos = cur_l

	if r_ctrl:
		var cur_r = r_ctrl.global_position
		if prev_r_hand_pos != Vector3.ZERO and delta > 0.001:
			r_hand_vel = (cur_r - prev_r_hand_pos) / delta
		prev_r_hand_pos = cur_r


func _is_defender_crossing_arms(origin: XROrigin3D) -> bool:
	if not origin:
		return false
	var cam = origin.get_node_or_null("XRCamera3D") as Camera3D
	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	if cam and l_ctrl and r_ctrl:
		var hands_dist = l_ctrl.global_position.distance_to(r_ctrl.global_position)
		var avg_pos = (l_ctrl.global_position + r_ctrl.global_position) * 0.5
		var rel_y = avg_pos.y - cam.global_position.y
		if hands_dist < 0.32 and rel_y > -0.35 and rel_y < 0.25:
			return true
	return false


func _update_beam_geometry() -> void:
	if is_orb_super:
		if beam_core_mesh and is_instance_valid(beam_core_mesh):
			beam_core_mesh.visible = false
		if beam_head_mesh and is_instance_valid(beam_head_mesh):
			beam_head_mesh.visible = true
			beam_head_mesh.global_position = current_head_pos
			beam_head_mesh.rotate_y(0.04)
		if beam_light and is_instance_valid(beam_light):
			beam_light.global_position = current_head_pos
		return

	if not beam_core_mesh or not is_instance_valid(beam_core_mesh):
		return

	var dist = start_pos.distance_to(current_head_pos)
	if dist < 0.05:
		beam_core_mesh.visible = false
		return
	beam_core_mesh.visible = true

	var cyl = beam_core_mesh.mesh as CylinderMesh
	if cyl:
		cyl.height = dist

	var inner = beam_core_mesh.get_node_or_null("InnerWhiteCore") as MeshInstance3D
	if inner and inner.mesh is CylinderMesh:
		(inner.mesh as CylinderMesh).height = dist

	var sheath = beam_core_mesh.get_node_or_null("ZenkaiBeamOuterSheath") as MeshInstance3D
	if sheath and sheath.mesh is CylinderMesh:
		(sheath.mesh as CylinderMesh).height = dist

	beam_core_mesh.global_position = (start_pos + current_head_pos) * 0.5
	var dir = (current_head_pos - start_pos).normalized()
	if dir.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(dir.y) < 0.95 else Vector3.FORWARD
		beam_core_mesh.look_at(beam_core_mesh.global_position + dir, up_vec)
		beam_core_mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	if beam_head_mesh and is_instance_valid(beam_head_mesh):
		beam_head_mesh.global_position = current_head_pos

	if beam_light and is_instance_valid(beam_light):
		beam_light.global_position = current_head_pos


func _exit_tree() -> void:
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	if beam_hud_anchor and is_instance_valid(beam_hud_anchor):
		beam_hud_anchor.queue_free()
		beam_hud_anchor = null
	if super_action_card_anchor and is_instance_valid(super_action_card_anchor):
		super_action_card_anchor.queue_free()
		super_action_card_anchor = null


func _ensure_super_action_card() -> void:
	var cam: Camera3D = _get_active_camera()
	if not cam or not is_instance_valid(cam):
		return
	if super_action_card_anchor and is_instance_valid(super_action_card_anchor):
		return

	super_action_card_anchor = Node3D.new()
	super_action_card_anchor.name = "SuperActionGuideCardAnchor"
	super_action_card_anchor.position = Vector3(0.0, -0.34, -1.10)
	super_action_card_anchor.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	cam.add_child(super_action_card_anchor)

	var border := MeshInstance3D.new()
	border.name = "CardBorder"
	var b_q := QuadMesh.new()
	b_q.size = Vector2(0.60, 0.27)
	border.mesh = b_q
	_super_card_border_mat = StandardMaterial3D.new()
	_super_card_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_super_card_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_super_card_border_mat.no_depth_test = true
	_super_card_border_mat.render_priority = 122
	_super_card_border_mat.albedo_color = Color(0.15, 0.85, 1.0, 0.88)
	border.material_override = _super_card_border_mat
	super_action_card_anchor.add_child(border)

	var bg := MeshInstance3D.new()
	bg.name = "CardBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.585, 0.255)
	bg.mesh = bg_q
	bg.position = Vector3(0.0, 0.0, 0.001)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 123
	bg_mat.albedo_color = Color(0.03, 0.06, 0.11, 0.88)
	bg.material_override = bg_mat
	super_action_card_anchor.add_child(bg)

	_super_card_label = Label3D.new()
	_super_card_label.name = "SuperCardText"
	_super_card_label.font_size = 22
	_super_card_label.pixel_size = 0.00130
	_super_card_label.no_depth_test = true
	_super_card_label.render_priority = 124
	_super_card_label.outline_size = 6
	_super_card_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_super_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_super_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_super_card_label.position = Vector3(-0.27, 0.0, 0.002)
	super_action_card_anchor.add_child(_super_card_label)
	_last_card_state_key = ""
	_refresh_super_action_card_text()


func _refresh_super_action_card_text() -> void:
	if not _super_card_label or not is_instance_valid(_super_card_label):
		return
	if state == BeamState.HAND_HOLDING:
		var pct_hold: int = int(clampf(hold_progress, 0.0, 1.0) * 100.0)
		var hold_key: String = "HOLD:" + str(pct_hold)
		if hold_key == _last_card_state_key:
			return
		_last_card_state_key = hold_key
		if _super_card_border_mat:
			_super_card_border_mat.albedo_color = Color(0.25, 0.95, 1.0, 0.95)
		_super_card_label.modulate = Color(0.90, 0.99, 1.0)
		_super_card_label.text = "👐 ¡AGUANTANDO EL PODER! (%d%%)\n1. Mantén AMBOS GRIPS (sin Gatillo)\n2. ¡AGITA AMBOS MANDOS RÁPIDO!" % pct_hold
		return

	var is_defending_player: bool = (defender != null and is_instance_valid(defender) and bool(defender.get("is_player")) and not is_aimed_miss)
	if is_defending_player:
		var def_ki: float = float(defender.get("current_ki")) if (defender.get("current_ki") != null) else 0.0
		var has_ki: bool = def_ki >= 15.0
		var in_crater: bool = defender.get("ground_crater_stun_timer") != null and float(defender.get("ground_crater_stun_timer")) > 0.0
		var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var bp_def: float = maxf(float(defender.get("current_np")) if (defender.get("current_np") != null) else 10000.0, 100.0)
		var bp_deflect_ok: bool = bp_def >= bp_atk * 0.70
		var state_key: String = "DEF:%d:%d:%d" % [1 if has_ki else 0, 1 if in_crater else 0, 1 if bp_deflect_ok else 0]
		if state_key == _last_card_state_key:
			return
		_last_card_state_key = state_key
		if _super_card_border_mat:
			_super_card_border_mat.albedo_color = Color(0.20, 0.88, 1.0, 0.90)
		_super_card_label.modulate = Color(0.90, 0.97, 1.0)
		var vanish_line: String = "• [Aturdido Cráter] Z-Vanish bloqueado" if in_crater else ("• Stick Izq/Der: Esquive Z-Vanish (-15 Ki)" if has_ki else "• [Sin Ki <15] Z-Vanish no disponible")
		var deflect_line: String = "• Manotazo veloz: Desviar haz" if bp_deflect_ok else "• Manotazo (BP<70%: Guardia parcial)"
		var clash_line: String = "• Lanza tu Super (Grips cadera→frente): ¡CHOQUE!" if has_ki else "• [Sin Ki <15] ¡CHOQUE! no disponible"
		_super_card_label.text = "⚠️ SUPER ENTRANTE — ACCIONES\n%s\n%s\n• 2 Grips al frente + Agitar: Aguantar\n• 2 Puños en X (pecho): Bloqueo\n%s" % [vanish_line, deflect_line, clash_line]
	else:
		if _last_card_state_key == "ATK":
			return
		_last_card_state_key = "ATK"
		if _super_card_border_mat:
			_super_card_border_mat.albedo_color = Color(1.0, 0.65, 0.18, 0.90)
		_super_card_label.modulate = Color(1.0, 0.93, 0.72)
		_super_card_label.text = "🔥 SUPER ATAQUE EN CURSO\n• Mantén puntería al objetivo\n• Si el rival contrataca:\n  ¡Agita los controles para Choque!"


func _update_hud(rem_time: float) -> void:
	if not alert_label or not is_instance_valid(alert_label):
		return

	if not beam_hud_anchor or not is_instance_valid(beam_hud_anchor):
		var cam: Camera3D = _get_active_camera()
		if cam and is_instance_valid(cam):
			beam_hud_anchor = Node3D.new()
			beam_hud_anchor.name = "BeamBulletTimeHUDAnchor"
			beam_hud_anchor.position = Vector3(0.0, 0.24, -1.18)
			cam.add_child(beam_hud_anchor)
			if alert_label.get_parent() and alert_label.get_parent() != beam_hud_anchor:
				alert_label.get_parent().remove_child(alert_label)
			if not alert_label.get_parent():
				beam_hud_anchor.add_child(alert_label)
			alert_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			alert_label.position = Vector3.ZERO
	_ensure_super_action_card()
	_refresh_super_action_card_text()

	if is_aimed_miss:
		alert_label.modulate = Color(1.0, 0.72, 0.25)
		alert_label.text = "💨 ¡%s DESVIADO!\nApunta las manos al rival al lanzar" % power_name.to_upper()
		return

	if state == BeamState.HAND_HOLDING:
		var h_pct: int = int(clampf(hold_progress, 0.0, 1.0) * 10.0)
		var h_bar: String = "█".repeat(h_pct) + "░".repeat(10 - h_pct)
		alert_label.modulate = Color(0.30, 0.95, 1.0)
		alert_label.text = "👐 ¡AGUANTANDO %s!\n[%s] %d%% — ¡AGITA LOS CONTROLES!" % [
			power_name.to_upper(), h_bar, int(clampf(hold_progress, 0.0, 1.0) * 100.0)
		]
		return

	var pct = clampf(rem_time / maxf(reaction_duration, 0.01), 0.0, 1.0)
	var bar_len = int(pct * 10.0)
	var bar = "█".repeat(bar_len) + "░".repeat(10 - bar_len)

	var zenkai_prefix: String = ""
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_in_zenkai_state")):
		if bool(attacker.get("is_player")):
			zenkai_prefix = "🔥 ¡ATAQUE ZENKAI EN CURSO! 🔥\n"
			alert_label.modulate = Color(1.0, 0.88, 0.15)
		else:
			zenkai_prefix = "💀 ¡ATAQUE ZENKAI ENTRANTE! 💀\n"
			alert_label.modulate = Color(1.0, 0.22, 0.22)
	else:
		alert_label.modulate = Color(1.0, 0.85, 0.25)

	if defender and is_instance_valid(defender) and bool(defender.get("is_player")):
		if _reading_pause_timer > 0.0:
			alert_label.text = "%s👁️ ¡ELIGE TU DEFENSA! (%.1fs lectura)\n[%s] %.1fs (Ver panel inferior)" % [
				zenkai_prefix, _reading_pause_timer, bar, maxf(rem_time, 0.0)
			]
		else:
			alert_label.text = "%s⚠️ ¡%s ENTRANTE! ⚠️\n[%s] %.1fs (Ver panel inferior)" % [
				zenkai_prefix, power_name.to_upper(), bar, maxf(rem_time, 0.0)
			]
	else:
		alert_label.text = "%s⚡ ¡%s ENTRANTE! [%s] %.1fs" % [
			zenkai_prefix, power_name.to_upper(), bar, maxf(rem_time, 0.0)
		]


func _build_visual_beam() -> void:
	var p_low: String = power_name.to_lower()
	var is_genki: bool = "genkidama" in p_low
	var radius: float = (1.45 if is_genki else 0.72) if is_orb_super else (0.45 if tier >= 4 else 0.35)

	# 1. Cuerpo cilíndrico del haz (oculto si es Esfera Super como Big Bang / Genkidama)
	beam_core_mesh = MeshInstance3D.new()
	beam_core_mesh.name = "BeamCore"
	var cyl = CylinderMesh.new()
	cyl.radial_segments = 16
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	beam_core_mesh.mesh = cyl

	var mat_beam := ShaderMaterial.new()
	mat_beam.shader = KiBeamShader
	if ZenkaiVFXManager.get_band_tex():
		mat_beam.set_shader_parameter("streak_tex", ZenkaiVFXManager.get_band_tex())
	if ZenkaiVFXManager.get_flame_tex():
		mat_beam.set_shader_parameter("flame_tex", ZenkaiVFXManager.get_flame_tex())
	mat_beam.set_shader_parameter("beam_color", energy_color)
	mat_beam.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	mat_beam.set_shader_parameter("flow_speed", 16.0)
	mat_beam.set_shader_parameter("core_intensity", 4.2)
	beam_core_mesh.material_override = mat_beam
	beam_core_mesh.visible = not is_orb_super
	add_child(beam_core_mesh)

	var outer_sheath := MeshInstance3D.new()
	outer_sheath.name = "ZenkaiBeamOuterSheath"
	var cyl_sheath := CylinderMesh.new()
	cyl_sheath.radial_segments = 16
	cyl_sheath.top_radius = radius * 1.45
	cyl_sheath.bottom_radius = radius * 1.45
	cyl_sheath.cap_top = false
	cyl_sheath.cap_bottom = false
	outer_sheath.mesh = cyl_sheath
	var mat_sheath := ShaderMaterial.new()
	mat_sheath.shader = ZenkaiAuraShader
	if ZenkaiVFXManager.get_flame_tex():
		mat_sheath.set_shader_parameter("flame_tex", ZenkaiVFXManager.get_flame_tex())
	if ZenkaiVFXManager.get_band_tex():
		mat_sheath.set_shader_parameter("band_tex", ZenkaiVFXManager.get_band_tex())
	mat_sheath.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.72))
	mat_sheath.set_shader_parameter("speed", 11.0)
	mat_sheath.set_shader_parameter("has_bio_lightning", 1.0 if tier >= 4 else 0.0)
	outer_sheath.material_override = mat_sheath
	beam_core_mesh.add_child(outer_sheath)

	# 1.1 Núcleo interior blanco incandescente (White-Hot Inner Core)
	var mat_inner = StandardMaterial3D.new()
	mat_inner.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_inner.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var inner_core = MeshInstance3D.new()
	inner_core.name = "InnerWhiteCore"
	var cyl_inner = CylinderMesh.new()
	cyl_inner.radial_segments = 12
	cyl_inner.top_radius = radius * 0.60
	cyl_inner.bottom_radius = radius * 0.60
	inner_core.mesh = cyl_inner
	inner_core.material_override = mat_inner
	beam_core_mesh.add_child(inner_core)

	# 2. Cabeza del haz o Esfera Masiva (Big Bang / Genkidama)
	beam_head_mesh = MeshInstance3D.new()
	beam_head_mesh.name = "BeamHead"
	var sph = SphereMesh.new()
	var head_r: float = radius if is_orb_super else radius * 1.3
	sph.radius = head_r
	sph.height = head_r * 2.0
	sph.radial_segments = 24
	sph.rings = 12
	beam_head_mesh.mesh = sph
	if is_orb_super:
		var mat_orb := ShaderMaterial.new()
		mat_orb.shader = ZenkaiAuraShader
		if ZenkaiVFXManager.get_flame_tex():
			mat_orb.set_shader_parameter("flame_tex", ZenkaiVFXManager.get_flame_tex())
		if ZenkaiVFXManager.get_band_tex():
			mat_orb.set_shader_parameter("band_tex", ZenkaiVFXManager.get_band_tex())
		mat_orb.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.94))
		mat_orb.set_shader_parameter("speed", 6.5)
		mat_orb.set_shader_parameter("vertex_displacement", 0.09)
		mat_orb.set_shader_parameter("has_bio_lightning", 1.0)
		beam_head_mesh.material_override = mat_orb
	else:
		beam_head_mesh.material_override = mat_beam
	add_child(beam_head_mesh)

	var inner_head = MeshInstance3D.new()
	inner_head.name = "InnerHeadCore"
	var sph_inner = SphereMesh.new()
	var inner_r: float = head_r * (0.62 if is_orb_super else 0.62)
	sph_inner.radius = inner_r
	sph_inner.height = inner_r * 2.0
	inner_head.mesh = sph_inner
	inner_head.material_override = mat_inner
	beam_head_mesh.add_child(inner_head)

	# 3. Luz dinámica
	beam_light = OmniLight3D.new()
	beam_light.name = "BeamLight"
	beam_light.light_color = energy_color
	beam_light.light_energy = 6.0 if is_orb_super else 4.5
	beam_light.omni_range = 10.0 if is_orb_super else 7.0
	add_child(beam_light)


func _build_reticle_and_hud() -> void:
	alert_label = Label3D.new()
	alert_label.name = "BeamAlertHUD"
	alert_label.font_size = 22
	alert_label.pixel_size = 0.0014
	alert_label.no_depth_test = true
	alert_label.render_priority = 125
	alert_label.outline_size = 8
	alert_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	alert_label.modulate = Color(1.0, 0.8, 0.2)
	var cam: Camera3D = _get_active_camera()
	if cam and is_instance_valid(cam):
		beam_hud_anchor = Node3D.new()
		beam_hud_anchor.name = "BeamBulletTimeHUDAnchor"
		beam_hud_anchor.position = Vector3(0.0, 0.24, -1.18)
		cam.add_child(beam_hud_anchor)
		alert_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		alert_label.position = Vector3.ZERO
		beam_hud_anchor.add_child(alert_label)
		_ensure_super_action_card()
	else:
		add_child(alert_label)


func _build_audio() -> void:
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BeamSequenceAudio"
	audio_player.unit_size = 8.0
	audio_player.max_distance = 45.0
	add_child(audio_player)
	var fallback_beam: AudioStream = load("res://assets/audio/Sound Effects - Battle (Common)/Battle SE - Common/se_battle_16.ogg") if ResourceLoader.exists("res://assets/audio/Sound Effects - Battle (Common)/Battle SE - Common/se_battle_16.ogg") else null
	audio_player.pitch_scale = randf_range(0.92, 1.08)
	var p_lower: String = power_name.to_lower()
	var atk_name: String = ""
	if attacker and is_instance_valid(attacker) and attacker.get("character_data"):
		var cd: Resource = attacker.get("character_data")
		if cd and "character_name" in cd:
			atk_name = String(cd.character_name).to_lower()
	var is_vegeta_atk: bool = ("vegeta" in atk_name) or ("galick" in p_lower) or ("final flash" in p_lower) or ("big bang" in p_lower)
	var fire_act: String = ""
	if is_vegeta_atk:
		if "final flash" in p_lower:
			fire_act = "vegeta.final_flash_fire" if AudioActionManager.has_action_sounds("vegeta.final_flash_fire") else "vegeta.galick_gun_fire"
		elif "big bang" in p_lower:
			fire_act = "vegeta.big_bang_fire" if AudioActionManager.has_action_sounds("vegeta.big_bang_fire") else "vegeta.galick_gun_fire"
		else:
			fire_act = "vegeta.galick_gun_fire"
	else:
		if "genkidama" in p_lower:
			fire_act = "goku.genkidama_fire" if AudioActionManager.has_action_sounds("goku.genkidama_fire") else "goku.kamehameha_fire"
		else:
			fire_act = "goku.kamehameha_fire"
	AudioActionManager.play_action(fire_act, audio_player, fallback_beam)


func _spawn_spark_at(pos: Vector3, col: Color) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var target_parent: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not target_parent:
		return
	var sw = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(3.5, 3.5)
	sw.mesh = quad
	sw.rotation.x = -PI * 0.5

	var mat = ShaderMaterial.new()
	mat.shader = ShockwaveShader
	mat.set_shader_parameter("ring_color", col)
	sw.material_override = mat
	target_parent.add_child(sw)
	sw.global_position = pos

	var tw = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * 3.5, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, 0.40)
	tw.tween_callback(sw.queue_free)


func _spawn_super_impact_explosion_vfx(pos: Vector3, col: Color, _bp_ratio: float) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var atk_in_zenkai: bool = bool(attacker and is_instance_valid(attacker) and (attacker.get("is_in_zenkai_state") or attacker.get("is_comeback_zenkai")))
	var z_tier: int = 5 if (atk_in_zenkai or tier >= 4) else 4
	var has_bio: bool = atk_in_zenkai
	if attacker and is_instance_valid(attacker):
		var cur_tr: Variant = attacker.get("current_transformation")
		if cur_tr != null and cur_tr is Resource and "has_bio_lightning" in cur_tr:
			has_bio = has_bio or bool(cur_tr.get("has_bio_lightning"))
	ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), pos, z_tier, col, has_bio)
	KiSmokeFX.spawn_smoke(get_tree(), pos, 1.6)


func _spawn_plasma_crater(pos: Vector3, radius: float, col: Color) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var target_parent: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not target_parent:
		return
	var disc := MeshInstance3D.new()
	disc.name = "BeamPlasmaCrater"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.15
	cyl.height = 0.02
	cyl.radial_segments = 16
	disc.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.78)
	disc.material_override = mat

	target_parent.add_child(disc)
	disc.global_position = pos

	var fade_tw := get_tree().create_tween()
	if fade_tw:
		fade_tw.tween_property(mat, "albedo_color", Color(col.r, col.g, col.b, 0.0), 4.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fade_tw.tween_callback(disc.queue_free)


func _get_active_camera() -> Camera3D:
	for f in [defender, attacker]:
		if f and is_instance_valid(f) and bool(f.get("is_player")):
			var orig: Node = f.get_parent()
			if orig:
				var c: Camera3D = orig.get_node_or_null("XRCamera3D") as Camera3D
				if c and is_instance_valid(c):
					return c
	var vp: Viewport = get_viewport()
	return vp.get_camera_3d() if vp else null
