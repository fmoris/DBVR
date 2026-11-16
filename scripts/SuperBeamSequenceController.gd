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

var state: BeamState = BeamState.ADVANCING_BULLET_TIME
var is_active: bool = false
var reaction_duration: float = 2.2
var time_left: float = 2.2
var beam_progress: float = 0.0 # 0.0 en atacante, 1.0 en defensor
var impact_sustain_timer: float = 0.0
const IMPACT_SUSTAIN_DURATION: float = 0.70

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

# Audio espacial
var audio_player: AudioStreamPlayer3D = null
var sfx_clash: AudioStream = null

# Seguimiento cinemático de manos para desvío físico
var prev_l_hand_pos: Vector3 = Vector3.ZERO
var prev_r_hand_pos: Vector3 = Vector3.ZERO
var l_hand_vel: Vector3 = Vector3.ZERO
var r_hand_vel: Vector3 = Vector3.ZERO

const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const KiBeamShader = preload("res://shaders/ki_beam.gdshader")
const ShockwaveShader = preload("res://shaders/shockwave.gdshader")
const BeamClashControllerClass = preload("res://scripts/BeamClashController.gd")


func _get_attacker_hand_position() -> Vector3:
	if not attacker or not is_instance_valid(attacker):
		return start_pos
	
	if attacker.get("is_player"):
		var origin = attacker.get_parent() as XROrigin3D
		if origin:
			var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
			var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D
			if l_ctrl and r_ctrl:
				return (l_ctrl.global_position + r_ctrl.global_position) * 0.5
			elif r_ctrl:
				return r_ctrl.global_position
			elif l_ctrl:
				return l_ctrl.global_position
	else:
		var skel = attacker.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
		if not skel:
			skel = attacker.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			var rw_idx = skel.find_bone("RightWrist")
			var lw_idx = skel.find_bone("LeftWrist")
			if rw_idx != -1 and lw_idx != -1:
				var r_global = skel.to_global(skel.get_bone_global_pose(rw_idx).origin)
				var l_global = skel.to_global(skel.get_bone_global_pose(lw_idx).origin)
				return (r_global + l_global) * 0.5
		return attacker.global_position + attacker.global_transform.basis * Vector3(0.0, 1.25, 0.55)
	
	return attacker.global_position + Vector3(0.0, 1.25, 0.0)


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
	tier = p_tier

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
		if dot_def > 0.25 and perp_dist <= 1.15:
			is_aimed_miss = false
			target_pos = def_pos.lerp(closest_pt, 0.35)
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

	# 3. Aplicar dilatación temporal (Bullet-Time normal en impacto o vuelo rápido en tiro fallado)
	if is_aimed_miss:
		reaction_duration = 0.65
		time_left = reaction_duration
		Engine.time_scale = 0.65
	else:
		Engine.time_scale = 0.18

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

		# El rayo crece continuamente desde las manos hacia el objetivo
		prev_head_pos = current_head_pos
		beam_progress = clampf(1.0 - (time_left / maxf(reaction_duration, 0.01)), 0.0, 1.0)
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

		# Detección de colisión: cuando la cabeza del rayo alcanza el objetivo, expira el tiempo o toca el suelo
		var dist_to_target = current_head_pos.distance_to(target_pos)
		if dist_to_target <= 0.85 or time_left <= 0.0 or beam_progress >= 0.98 or current_head_pos.y <= 0.15:
			if is_aimed_miss:
				_resolve_aimed_miss()
			else:
				_resolve_direct_hit()

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

	var diff_ratio = clampf((float(np_def) - float(np_atk)) / maxf(float(np_atk), 100.0), -0.65, 1.2)
	var base_t = 2.2
	if defender and defender.get("is_in_zenkai_state"):
		base_t = 2.8 # Ventana más amplia en Zenkai para permitir remontada épica

	return base_t * (1.0 + diff_ratio)


func _check_player_defense_options() -> void:
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return

	# OPCIÓN 1: CHOQUE DE PODERES (BEAM CLASH)
	# Si el jugador está concentrando o liberando un Super Haz con Ki >= 40
	if defender.get("is_charging_super"):
		var counter_info: Dictionary = _get_signature_counter_beam(defender)
		_trigger_beam_clash(defender, String(counter_info["name"]), counter_info["color"])
		return

	# OPCIÓN 2: DESVÍO FÍSICO CON LA MANO (KI DEFLECTION / BATTING)
	# Cuando el haz está a menos de 1.4m de las manos y el jugador da un manotazo lateral veloz (> 2.8 m/s)
	var l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var r_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	var l_pos = l_ctrl.global_position if l_ctrl else Vector3.ZERO
	var r_pos = r_ctrl.global_position if r_ctrl else Vector3.ZERO

	var dist_l = current_head_pos.distance_to(l_pos)
	var dist_r = current_head_pos.distance_to(r_pos)

	if (dist_l < 1.35 and l_hand_vel.length() > 2.6) or (dist_r < 1.35 and r_hand_vel.length() > 2.6):
		_resolve_deflection()
		return

	# OPCIÓN 3: BLOQUEO DE CONTENCIÓN (GUARDIA PESADA / MANOS CRUZADAS)
	if _is_defender_crossing_arms(origin):
		_resolve_containment_block()
		return

	# OPCIÓN 4: Z-VANISH (TELETRANSPORTE EVASIVO)
	if defender.get("is_teleporting") or (defender.get("is_blocking") and defender.get("velocity").length_squared() > 1.0):
		_resolve_evasion()
		return


var ai_planned_action: String = "clash"
var ai_action_time: float = 0.8

func _plan_ai_defense_reaction() -> void:
	var ai_ki = defender.get("current_ki") if defender and defender.get("current_ki") != null else 50.0
	var ai_zenkai = defender.get("is_in_zenkai_state") if defender and defender.get("is_in_zenkai_state") != null else false

	if ai_ki >= 45.0 and (ai_zenkai or randf() < 0.70):
		ai_planned_action = "clash"
		ai_action_time = randf_range(0.45, reaction_duration * 0.75)
	elif ai_ki >= 25.0 and randf() < 0.55:
		ai_planned_action = "vanish"
		ai_action_time = randf_range(0.5, reaction_duration * 0.85)
	elif randf() < 0.65:
		ai_planned_action = "block"
		ai_action_time = randf_range(0.3, reaction_duration * 0.60)
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
							return { "name": p.power_name, "color": p_col }
	return { "name": fallback_name, "color": fallback_col }


func _trigger_beam_clash(clash_defender: Node3D, counter_tech: String, counter_color: Color) -> void:
	state = BeamState.CLASHING
	is_active = false
	Engine.time_scale = 1.0

	# Instanciar el controlador del Choque de Haces
	var clash = BeamClashControllerClass.new()
	clash.name = "BeamClashController"
	get_tree().current_scene.add_child(clash)
	clash.setup(attacker, clash_defender, power_name, energy_color, counter_tech, counter_color, 3.5)

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


func _resolve_containment_block() -> void:
	state = BeamState.BLOCKED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	# Mitiga el 80% del daño a cambio de Ki de resistencia
	var mitigated_damage = base_damage * 0.20
	if defender and is_instance_valid(defender):
		if defender.has_method("consume_ki"):
			defender.consume_ki(15.0)
		if defender.has_method("take_hit"):
			defender.take_hit(mitigated_damage, beam_dir)
		if defender.has_method("apply_knockback"):
			# Empuje hacia atrás creando trinchera
			defender.apply_knockback(beam_dir, 4.2)

	_spawn_spark_at(current_head_pos, Color(0.2, 0.8, 1.0))

	# Pulso háptico sostenido
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = origin.get_node_or_null(h) as XRController3D
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 180.0, 0.85, 0.35, 0.0)

	print("[SuperBeamSequence] 🛡️ ¡BLOQUEO DE CONTENCIÓN! 80%% de daño absorbido con retroceso.")
	_cleanup_and_finish("blocked", mitigated_damage)


func _resolve_evasion() -> void:
	state = BeamState.EVADED
	is_active = false
	Engine.time_scale = 1.0

	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_comeback_zenkai")) and attacker.has_method("notify_attack_failed"):
		attacker.notify_attack_failed()

	if defender and is_instance_valid(defender) and defender.has_method("consume_ki"):
		defender.consume_ki(25.0)

	# El haz continúa su trayectoria recta y colisiona contra las montañas lejanas
	var mountain_target = start_pos + beam_dir * 80.0
	var tw = create_tween()
	tw.tween_method(func(p: Vector3):
		current_head_pos = p
		_update_beam_geometry()
	, current_head_pos, mountain_target, 0.40).set_trans(Tween.TRANS_LINEAR)

	print("[SuperBeamSequence] 💨 ¡Z-VANISH EVASIVO! El haz pasó de largo hacia las cordilleras.")
	tw.tween_callback(func(): _cleanup_and_finish("evaded", 0.0))


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
		_spawn_plasma_crater(Vector3(current_head_pos.x, 0.12, current_head_pos.z), 2.0, energy_color)

	if attacker and is_instance_valid(attacker) and attacker.has_method("_log_combat_event"):
		attacker._log_combat_event("💨 ¡%s pasó de largo! Apunta tus manos hacia el rival al lanzar en Fase 2." % power_name, "warning")

	print("[SuperBeamSequence] 💨 ¡TIRO FALLADO POR PUNTERÍA! %s viajó desviado sin impactar al rival." % power_name)
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

	# 1. Aplicar daño y cambio de pose (flinch/stagger) al defensor
	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(final_damage, beam_dir)
		if defender.has_method("apply_knockback"):
			defender.apply_knockback(beam_dir, 9.5)
		if defender.get("procedural_animator"):
			# Cambio de pose drástico del defensor al recibir el impacto
			defender.procedural_animator.trigger_hit_flinch(2.2, beam_dir)

	# 2. Notificar al atacante para sostener la pose de empuje de energía
	if attacker and is_instance_valid(attacker):
		if attacker.has_method("increase_np"):
			attacker.increase_np(final_damage * 0.35)
		attacker.set("is_firing_beam", true)
		attacker.set("beam_tech_name", power_name)

	# 3. Onda de choque, cráter de plasma y chispas masivas en el punto de impacto
	_spawn_spark_at(current_head_pos, energy_color)
	if current_head_pos.y <= 3.0:
		_spawn_plasma_crater(Vector3(current_head_pos.x, 0.12, current_head_pos.z), 2.4, energy_color)
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

	emit_signal("sequence_completed", result, dmg)

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


func _update_hud(rem_time: float) -> void:
	if not alert_label or not is_instance_valid(alert_label):
		return

	var cam = _get_active_camera()
	if cam and is_instance_valid(cam):
		var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
		alert_label.global_position = cam.global_position + cam_fwd * 1.80 + Vector3(0.0, 0.18, 0.0)
		alert_label.look_at(cam.global_position, Vector3.UP)
		alert_label.rotate_y(PI)
	else:
		var target_head = defender.global_position + Vector3(0.0, 1.6, 0.0) if defender else global_position
		alert_label.global_position = target_head + Vector3(0.0, 0.45, 0.0)

	if is_aimed_miss:
		alert_label.modulate = Color(1.0, 0.72, 0.25)
		alert_label.text = "💨 ¡%s DESVIADO!\nApunta las manos al rival al lanzar" % power_name.to_upper()
		return

	var pct = clampf(rem_time / maxf(reaction_duration, 0.01), 0.0, 1.0)
	var bar_len = int(pct * 10.0)
	var bar = "█".repeat(bar_len) + "░".repeat(10 - bar_len)

	var zenkai_prefix: String = ""
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_in_zenkai_state")):
		if bool(attacker.get("is_player")):
			zenkai_prefix = "🔥 ¡ATAQUE ZENKAI DE VICTORIA EN CURSO! 🔥\n"
			alert_label.modulate = Color(1.0, 0.88, 0.15)
		else:
			zenkai_prefix = "💀 ¡ATAQUE ZENKAI K.O. ENTRANTE! 💀\n"
			alert_label.modulate = Color(1.0, 0.22, 0.22)
	else:
		alert_label.modulate = Color(1.0, 0.8, 0.2)

	alert_label.text = "%s⚡ ¡%s ENTRANTE! ⚡\n[ %s ] %.1fs\n[Z-VANISH | DESVÍO CON MANO | BLOQUEO | CHOQUE]" % [
		zenkai_prefix, power_name.to_upper(), bar, maxf(rem_time, 0.0)
	]


func _build_visual_beam() -> void:
	var radius = 0.45 if tier >= 4 else 0.35

	# 1. Cuerpo cilíndrico del haz (Manto de plasma exterior)
	beam_core_mesh = MeshInstance3D.new()
	beam_core_mesh.name = "BeamCore"
	var cyl = CylinderMesh.new()
	cyl.radial_segments = 16
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	beam_core_mesh.mesh = cyl

	var mat_beam = ShaderMaterial.new()
	mat_beam.shader = KiBeamShader
	mat_beam.set_shader_parameter("beam_color", energy_color)
	mat_beam.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	mat_beam.set_shader_parameter("flow_speed", 14.0)
	mat_beam.set_shader_parameter("core_intensity", 3.8)
	beam_core_mesh.material_override = mat_beam
	add_child(beam_core_mesh)

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

	# 2. Cabeza del haz (esfera de impacto)
	beam_head_mesh = MeshInstance3D.new()
	beam_head_mesh.name = "BeamHead"
	var sph = SphereMesh.new()
	sph.radius = radius * 1.3
	sph.height = radius * 2.6
	beam_head_mesh.mesh = sph
	beam_head_mesh.material_override = mat_beam
	add_child(beam_head_mesh)

	var inner_head = MeshInstance3D.new()
	inner_head.name = "InnerHeadCore"
	var sph_inner = SphereMesh.new()
	sph_inner.radius = radius * 0.8
	sph_inner.height = radius * 1.6
	inner_head.mesh = sph_inner
	inner_head.material_override = mat_inner
	beam_head_mesh.add_child(inner_head)

	# 3. Luz dinámica
	beam_light = OmniLight3D.new()
	beam_light.name = "BeamLight"
	beam_light.light_color = energy_color
	beam_light.light_energy = 4.5
	beam_light.omni_range = 7.0
	add_child(beam_light)


func _build_reticle_and_hud() -> void:
	alert_label = Label3D.new()
	alert_label.name = "BeamAlertHUD"
	alert_label.font_size = 26
	alert_label.pixel_size = 0.0022
	alert_label.no_depth_test = true
	alert_label.render_priority = 115
	alert_label.outline_size = 8
	alert_label.outline_color = Color(0.0, 0.0, 0.0, 0.95)
	alert_label.modulate = Color(1.0, 0.8, 0.2)
	add_child(alert_label)


func _build_audio() -> void:
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BeamSequenceAudio"
	audio_player.unit_size = 8.0
	audio_player.max_distance = 45.0
	if ResourceLoader.exists("res://assets/sfx/Kamehameha Regular.mp3"):
		audio_player.stream = load("res://assets/sfx/Kamehameha Regular.mp3")
		audio_player.pitch_scale = randf_range(0.92, 1.08)
		audio_player.play()
	add_child(audio_player)


func _spawn_spark_at(pos: Vector3, col: Color) -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
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
	get_tree().current_scene.add_child(sw)
	sw.global_position = pos

	var tw = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * 3.5, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, 0.40)
	tw.tween_callback(sw.queue_free)
	KiSmokeFX.spawn_smoke(get_tree(), pos, 1.6)


func _spawn_plasma_crater(pos: Vector3, radius: float, col: Color) -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
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

	get_tree().current_scene.add_child(disc)
	disc.global_position = pos

	var fade_tw := get_tree().create_tween()
	if fade_tw:
		fade_tw.tween_property(mat, "albedo_color", Color(col.r, col.g, col.b, 0.0), 4.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fade_tw.tween_callback(disc.queue_free)


func _get_active_camera() -> Camera3D:
	if defender and defender.get("is_player"):
		var orig = defender.get_parent()
		if orig:
			return orig.get_node_or_null("XRCamera3D") as Camera3D
	var vp = get_viewport()
	return vp.get_camera_3d() if vp else null
