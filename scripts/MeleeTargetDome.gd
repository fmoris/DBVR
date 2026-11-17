class_name MeleeTargetDome
extends Node3D

## MeleeTargetDome (Godot 4.3+ VR)
## Cúpula holográfica anime para combate Melee secuencial con economía de Ki y dominio de ronda:
## - Ataques (100% con puño cerrado Grip+Trigger):
##   * Nv.1 Golpe Rápido (< 0.50s), Nv.2 Golpe Cargado (0.50s..1.09s)
##   * Nv.3 Ataque Cargado v3 (>= 1.10s): interrumpe y lanza atrás o arriba (sí se frena con 1 mano)
##   * Martillazo DBZ (2 manos arriba 0.85s -> abajo): rompe 1 mano y estrella contra el suelo
##   * Cancelación de Ataque: Joystick derecho hacia atrás (separa a 5.5m)
## - Defensas:
##   * Palma abierta en caja = Desvío (+1.00 pto, +12 Ki)
##   * Puñetazo contra caja = Choque de Puños (0 daño y ++Ki ambos si BP parejo, -1 ataque al rival)
##   * Grip+Trigger al impacto (90ms) = Bloqueo Perfecto (Parry + inversión inmediata)
##   * Ambos puños al pecho en 'X' = Guardia Cruzada (-85% daño, +0.25 ptos, consume Ki)
## - Iniciativa por Dominio: Si S_def > N/2 -> invierte roles; si S_def <= N/2 -> continúa ofensiva.
## - Ruptura por Ki == 0: Golpe Fuerte Imbloqueable que expulsa al luchador sin Ki.

enum DomePhase {
	PHASE_TRANSITION,
	ATTACK_RECORDING,
	DEFENSE_RHYTHM,
	UNBLOCKABLE_KI_BREAK,
	COMPLETED
}

signal target_hit(hit_count: int, zone_name: String, hit_pos: Vector3, is_charged: bool, power: float)
signal bullet_time_completed(recorded_hits: Array, launch_vector: Vector3)
signal finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3)
signal perfect_parry_triggered(new_attacker: Node3D, new_defender: Node3D)
signal defense_action_resolved(action_type: String, zone_id: int, was_successful: bool, reward_ki: float, reward_bp: float)

var phase: DomePhase = DomePhase.ATTACK_RECORDING

var attacker: Node3D = null
var defender: Node3D = null
var locked_atk_to_def_dir: Vector3 = Vector3.FORWARD
var duration: float = 5.5
var time_left: float = 5.5
var is_active: bool = false
var hits: Array = []

# Transición legible entre turnos y estado de ronda
var transition_timer: float = 0.0
var transition_next_phase: DomePhase = DomePhase.ATTACK_RECORDING
var transition_message: String = ""
var transition_color: Color = Color(1.0, 0.95, 0.3)
var transition_on_complete_mode: String = "" # "start_defense" | "restart_attacker" | "continue_offense"

# Economía de dominio de ronda e intercambios
var clash_penalty_hits: int = 0
var pending_attack_penalty: int = 0
var defense_score_sum: float = 0.0
var defense_round_total_hits: int = 0
var last_action_feedback: String = ""
# Punto 2: Tracker visual de pips por golpe + tutorial de controles solo en el primer intercambio
static var _tutorial_controls_shown: bool = false
var pip_results: Array[String] = []

# Remate imbloqueable por agotamiento de Ki (Ki == 0)
var ki_break_attacker: Node3D = null
var ki_break_victim: Node3D = null
var ki_break_timer: float = 0.0
var last_finisher_attacker: Node3D = null
var last_finisher_victim: Node3D = null

# Secuencia ordenada 1-por-1 (Ataque)
var max_allowed_hits: int = 3
var planned_attack_zones: Array[int] = []
var current_attack_step: int = 0
var attack_step_cooldown: float = 0.0

# Velocidades de atacante y defensor
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO
var def_prev_left_pos: Vector3 = Vector3.ZERO
var def_prev_right_pos: Vector3 = Vector3.ZERO
var def_left_velocity: Vector3 = Vector3.ZERO
var def_right_velocity: Vector3 = Vector3.ZERO

# Puño cerrado obligatorio (Grip+Trigger) y carga en 3 niveles (0: Izquierda, 1: Derecha)
var is_fist_closed: Array[bool] = [false, false]
var fist_charge_times: Array[float] = [0.0, 0.0]
var fist_locked_haptic: Array[bool] = [false, false]
var fist_v3_locked_haptic: Array[bool] = [false, false]
var fist_buffer_timers: Array[float] = [0.0, 0.0]
var hand_must_retract: Array[bool] = [false, false]

# Carga de Martillazo bimanual (0.85s con ambos puños arriba)
const HAMMER_CHARGE_REQ: float = 0.85
var hammer_charge_time: float = 0.0
var hammer_locked_haptic: bool = false
var hammer_primed: bool = false
var hammer_primed_window: float = 0.0
var hammer_interruption_timer: float = 0.0

# Vector del último impacto
var last_impact_vector: Vector3 = Vector3.ZERO
var was_last_hit_charged: bool = false

# Cajas holográficas y HUD
var target_zones: Array = []
var dome_mesh: MeshInstance3D = null
var header_label: Label3D = null
var melee_hud_anchor: Node3D = null
var charge_spheres: Array[MeshInstance3D] = [null, null]

# Parámetros de Defensa Rítmica (1.25s por nota)
const NOTE_CADENCE_SEC: float = 1.25
const RING_PREWARN_SEC: float = 1.10
var defense_timer: float = 0.0
var defense_total_duration: float = 0.0
var consecutive_guard_hits: int = 0
var last_animated_note_idx: int = -1
var buffer_grip_timer_l: float = 0.0
var buffer_grip_timer_r: float = 0.0
var buffer_trig_timer_l: float = 0.0
var buffer_trig_timer_r: float = 0.0
var prev_grip_l: bool = false
var prev_grip_r: bool = false
var prev_trig_l: bool = false
var prev_trig_r: bool = false
var def_grip_l: bool = false
var def_grip_r: bool = false
var def_trig_l: bool = false
var def_trig_r: bool = false

# Audio espacial
var audio_player: AudioStreamPlayer3D = null
var sfx_hit_light: AudioStream = null
var sfx_hit_heavy: AudioStream = null
var sfx_parry: AudioStream = null

const ZONE_DEFINITIONS = [
	{ "id": 0, "name": "Rostro / Cabeza", "offset": Vector3(0.0, 0.28, 0.0), "color": Color(1.0, 0.3, 0.2, 0.85) },
	{ "id": 1, "name": "Plexo Solar", "offset": Vector3(0.0, -0.02, 0.0), "color": Color(0.2, 0.85, 1.0, 0.85) },
	{ "id": 2, "name": "Hombro Izquierdo", "offset": Vector3(-0.30, 0.22, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 3, "name": "Hombro Derecho", "offset": Vector3(0.30, 0.22, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 4, "name": "Flanco Izquierdo", "offset": Vector3(-0.28, -0.22, 0.0), "color": Color(1.0, 0.8, 0.2, 0.85) },
	{ "id": 5, "name": "Flanco Derecho", "offset": Vector3(0.28, -0.22, 0.0), "color": Color(1.0, 0.8, 0.2, 0.85) }
]


## Evalúa de forma pura la fórmula matemática de dominio de ronda (1.0/0.75/0.5/0.65/0.25/0.0)
static func compute_round_outcome_decision(scores: Array, clashes: int, base_hits: int) -> Dictionary:
	var n: int = scores.size()
	var s_def: float = 0.0
	for sc in scores:
		s_def += float(sc)
	var threshold: float = float(n) * 0.5
	var turnover: bool = (n > 0 and s_def > threshold)
	var next_hits: int = maxi(1, base_hits - clashes) if not turnover else maxi(1, base_hits)
	return {
		"defense_score_sum": s_def,
		"threshold": threshold,
		"turnover": turnover,
		"next_attack_hits": next_hits
	}


func setup(p_attacker: Node3D, p_defender: Node3D, p_duration: float = -1.0, p_max_hits: int = -1) -> void:
	attacker = p_attacker
	defender = p_defender
	is_active = true
	clash_penalty_hits = 0
	pending_attack_penalty = 0
	last_action_feedback = ""

	sfx_hit_light = load("res://assets/audio/gekishin_test/003073_s1.wav")
	sfx_hit_heavy = load("res://assets/audio/gekishin_test/003073_s3.wav")
	if ResourceLoader.exists("res://assets/audio/gekishin_test/003074_s4.wav"):
		sfx_parry = load("res://assets/audio/gekishin_test/003074_s4.wav")
	else:
		sfx_parry = sfx_hit_light

	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BulletTimeAudio"
	audio_player.unit_size = 5.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

	_update_dome_transform()
	_build_visual_dome()
	_build_target_boxes()
	_build_header_hud()

	start_attack_phase(p_attacker, p_defender, p_duration, p_max_hits)


func start_attack_phase(p_attacker: Node3D, p_defender: Node3D, p_duration: float = -1.0, p_max_hits: int = -1) -> void:
	attacker = p_attacker
	defender = p_defender
	hits.clear()
	current_attack_step = 0
	attack_step_cooldown = 0.25
	clash_penalty_hits = 0
	defense_score_sum = 0.0
	defense_round_total_hits = 0
	fist_charge_times = [0.0, 0.0]
	fist_locked_haptic = [false, false]
	fist_v3_locked_haptic = [false, false]
	hand_must_retract = [false, false]
	hammer_charge_time = 0.0
	hammer_primed = false
	hammer_locked_haptic = false
	_hide_all_charge_spheres()

	var base_hits: int = 3
	if p_max_hits > 0:
		base_hits = p_max_hits
	elif attacker and is_instance_valid(attacker) and attacker.has_method("calculate_melee_attack_count"):
		base_hits = attacker.calculate_melee_attack_count(attacker, defender)

	max_allowed_hits = maxi(1, base_hits - pending_attack_penalty)
	pending_attack_penalty = 0

	duration = p_duration if p_duration > 0.0 else (float(max_allowed_hits) * 1.65 + 1.40)
	time_left = duration
	phase = DomePhase.ATTACK_RECORDING
	is_active = true
	_reset_all_timing_rings()
	_update_dome_transform()

	if dome_mesh and is_instance_valid(dome_mesh):
		var mat := dome_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.85, 0.2, 0.08)

	if attacker and not attacker.get("is_player"):
		_generate_planned_attack_sequence(max_allowed_hits)
		generate_ai_attack_sequence()
		_begin_phase_transition("start_defense", 0.55, "🛡️ ¡TURNO DE DEFENSA! (%d GOLPES)\nPalma=Desvío | Puño=Choque | X=Cruzada" % hits.size(), Color(0.25, 0.88, 1.0))
	else:
		planned_attack_zones.clear()
		_update_sequential_target_highlights()
		_refresh_header_hud()

	print("[BulletTimeDome] Ataque listo: %d golpes permitidos en %.2fs." % [max_allowed_hits, duration])


func _apply_role_dome_tint(player_attacks: bool) -> void:
	if not dome_mesh or not is_instance_valid(dome_mesh):
		return
	var mat: StandardMaterial3D = dome_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0, 0.28, 0.12, 0.11) if player_attacks else Color(0.15, 0.72, 1.0, 0.11)


func _get_pips_string(total: int) -> String:
	var n: int = maxi(total, pip_results.size())
	if n <= 0:
		return ""
	var out: String = ""
	for i in range(n):
		if i < pip_results.size():
			match pip_results[i]:
				"hit": out += "💥"
				"blocked": out += "🛡"
				"clash": out += "⚡"
				_: out += "·"
		else:
			out += "○"
		if i < n - 1:
			out += " "
	return "[%s]" % out


func _spawn_impact_popup(world_pos: Vector3, txt: String, col: Color) -> void:
	var tree: SceneTree = get_tree()
	if not tree or not tree.current_scene:
		return
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 32
	lbl.pixel_size = 0.0020
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 118
	tree.current_scene.add_child(lbl)
	lbl.global_position = world_pos + Vector3(0.0, 0.08, 0.0)
	var tw: Tween = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position", lbl.global_position + Vector3(0.0, 0.26, 0.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45).set_delay(0.12)
	tw.chain().tween_callback(lbl.queue_free)


func _begin_phase_transition(mode: String, wait_sec: float, msg: String, col: Color) -> void:
	phase = DomePhase.PHASE_TRANSITION
	transition_on_complete_mode = mode
	# Punto 2: Pausa mínima de 0.8s entre roles para que el jugador entienda quién ataca y quién defiende
	transition_timer = maxf(wait_sec, 0.80) if mode in ["start_defense", "restart_attacker", "continue_offense"] else wait_sec
	transition_message = msg
	transition_color = col
	_reset_all_timing_rings()
	_hide_all_charge_spheres()
	var player_will_attack: bool = false
	if mode == "start_defense":
		player_will_attack = attacker != null and bool(attacker.get("is_player"))
	elif mode == "restart_attacker":
		player_will_attack = defender != null and bool(defender.get("is_player"))
	elif mode == "continue_offense":
		player_will_attack = attacker != null and bool(attacker.get("is_player"))
	_apply_role_dome_tint(player_will_attack)
	if audio_player and sfx_parry:
		audio_player.stream = sfx_parry
		audio_player.pitch_scale = 1.15 if player_will_attack else 0.85
		audio_player.play()
	if player_will_attack:
		_pulse_defender_hand(0, 150.0, 0.75, 0.14)
		_pulse_defender_hand(1, 150.0, 0.75, 0.14)
	else:
		_pulse_defender_both_hands(110.0, 0.50, 0.07)
	if header_label and is_instance_valid(header_label):
		header_label.text = msg
		header_label.modulate = col


func _process_phase_transition(delta: float) -> void:
	_update_dome_transform_for_defender()
	transition_timer -= delta
	if transition_timer > 0.0:
		return

	var mode: String = transition_on_complete_mode
	transition_on_complete_mode = ""
	if mode == "start_defense":
		start_defense_phase()
	elif mode == "restart_attacker":
		restart_as_attacker()
	elif mode == "continue_offense":
		continue_attacker_offense()


func _generate_planned_attack_sequence(n_hits: int) -> void:
	planned_attack_zones.clear()
	var last_z: int = -1
	for i in range(n_hits):
		var z: int = randi() % ZONE_DEFINITIONS.size()
		if z == last_z:
			z = (z + 1) % ZONE_DEFINITIONS.size()
		last_z = z
		planned_attack_zones.append(z)


func _reset_all_timing_rings() -> void:
	for zone in target_zones:
		var r: Variant = zone.get("timing_ring")
		if r is MeshInstance3D and is_instance_valid(r):
			(r as MeshInstance3D).visible = false


func _update_sequential_target_highlights() -> void:
	var player_free_choice: bool = attacker != null and is_instance_valid(attacker) and bool(attacker.get("is_player"))
	if player_free_choice:
		for zone in target_zones:
			var z_id: int = int(zone["id"])
			var z_node: Node3D = zone["node"] as Node3D
			var box_mat: StandardMaterial3D = zone.get("box_mat") as StandardMaterial3D
			var inner_mat: StandardMaterial3D = zone.get("inner_mat") as StandardMaterial3D
			var step_lbl: Label3D = zone.get("step_label") as Label3D
			var orig_col: Color = zone["color"] as Color

			if z_node and is_instance_valid(z_node):
				z_node.visible = true
				z_node.scale = Vector3.ONE
			if box_mat:
				box_mat.albedo_color = Color(orig_col.r, orig_col.g, orig_col.b, 0.58)
				box_mat.emission = Color(orig_col.r, orig_col.g, orig_col.b)
				box_mat.emission_energy_multiplier = 1.25
			if inner_mat:
				inner_mat.albedo_color = Color(orig_col.r, orig_col.g, orig_col.b, 0.90)

			if step_lbl and is_instance_valid(step_lbl):
				var last_step_on_zone: int = -1
				for idx in range(hits.size()):
					if int(hits[idx].get("zone_id", -1)) == z_id:
						last_step_on_zone = idx + 1
				if last_step_on_zone > 0:
					step_lbl.text = "✓%d" % last_step_on_zone
					step_lbl.modulate = Color(1.0, 0.95, 0.25, 1.0)
					step_lbl.visible = true
				else:
					step_lbl.text = ""
					step_lbl.visible = false
		return

	var active_zone_id: int = -1
	if current_attack_step >= 0 and current_attack_step < planned_attack_zones.size() and current_attack_step < max_allowed_hits:
		active_zone_id = planned_attack_zones[current_attack_step]

	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var box_mat: StandardMaterial3D = zone.get("box_mat") as StandardMaterial3D
		var inner_mat: StandardMaterial3D = zone.get("inner_mat") as StandardMaterial3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color
		if z_node and is_instance_valid(z_node):
			z_node.visible = true

		if z_id == active_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 1.15
			if box_mat:
				box_mat.albedo_color = Color(orig_col.r, orig_col.g, orig_col.b, 0.92)
				box_mat.emission = Color(orig_col.r, orig_col.g, orig_col.b)
				box_mat.emission_energy_multiplier = 2.0
			if inner_mat:
				inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = str(current_attack_step + 1)
				step_lbl.modulate = Color(1.0, 0.95, 0.25, 1.0)
				step_lbl.visible = true
		else:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.72
			if box_mat:
				box_mat.albedo_color = Color(orig_col.r, orig_col.g, orig_col.b, 0.12)
				box_mat.emission_energy_multiplier = 0.15
			if inner_mat:
				inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.12)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.visible = false


func _update_defense_zone_highlights(active_zone_id: int, step_num: int, next_zone_id: int = -1, is_heavy_note: bool = false, is_hammer_note: bool = false) -> void:
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var box_mat: StandardMaterial3D = zone.get("box_mat") as StandardMaterial3D
		var inner_mat: StandardMaterial3D = zone.get("inner_mat") as StandardMaterial3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color
		if z_node and is_instance_valid(z_node):
			z_node.visible = true

		if z_id == active_zone_id:
			var hi_col: Color = Color(0.95, 0.2, 1.0, 0.95) if is_hammer_note else (Color(1.0, 0.4, 0.15, 0.95) if is_heavy_note else Color(0.2, 0.92, 1.0, 0.95))
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * (1.28 if is_hammer_note else 1.15)
			if box_mat:
				box_mat.albedo_color = hi_col
				box_mat.emission = Color(hi_col.r, hi_col.g, hi_col.b)
				box_mat.emission_energy_multiplier = 2.2
			if inner_mat:
				inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "🔨" if is_hammer_note else str(step_num)
				step_lbl.modulate = Color(1.0, 0.95, 0.3, 1.0) if is_hammer_note else Color(0.3, 0.95, 1.0, 1.0)
				step_lbl.visible = true
		elif z_id == next_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.86
			if box_mat:
				box_mat.albedo_color = Color(0.55, 0.45, 0.95, 0.36)
				box_mat.emission_energy_multiplier = 0.45
			if inner_mat:
				inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.28)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "SIG"
				step_lbl.modulate = Color(0.75, 0.85, 1.0, 0.85)
				step_lbl.visible = true
		else:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.70
			if box_mat:
				box_mat.albedo_color = Color(orig_col.r, orig_col.g, orig_col.b, 0.10)
				box_mat.emission_energy_multiplier = 0.12
			if inner_mat:
				inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.08)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.visible = false


func _process(delta: float) -> void:
	if not is_active:
		return

	if attacker and defender and is_instance_valid(attacker) and is_instance_valid(defender):
		if attacker.get("velocity") != null:
			attacker.set("velocity", Vector3.ZERO)
		if defender.get("velocity") != null:
			defender.set("velocity", Vector3.ZERO)
		_keep_ai_face_to_face(delta)

	match phase:
		DomePhase.PHASE_TRANSITION:
			_process_phase_transition(delta)
		DomePhase.ATTACK_RECORDING:
			_process_attack_recording(delta)
		DomePhase.DEFENSE_RHYTHM:
			_process_defense_rhythm(delta)
		DomePhase.UNBLOCKABLE_KI_BREAK:
			_process_unblockable_ki_break(delta)


# ==============================================================================
# FASE 1: ATAQUE (PUÑO CERRADO GRIP+TRIGGER + CARGA NV.1/NV.2/V3 + MARTILLAZO)
# ==============================================================================

func _process_attack_recording(delta: float) -> void:
	if attack_step_cooldown > 0.0:
		attack_step_cooldown -= delta

	_update_dome_transform()

	# Cancelación explícita de ataque: Joystick derecho hacia atrás
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_player")):
		var r_ctrl: XRController3D = _get_controller("RightHand")
		if r_ctrl and r_ctrl.get_vector2("primary").y <= -0.55:
			hits.clear()
			if attacker.has_method("_log_combat_event"):
				attacker._log_combat_event("↩️ ¡Ataque cancelado! Te alejas del oponente.", "info")
			finish_without_hits()
			return

	_update_controller_velocities(delta)
	var is_charging_hammer: bool = _process_hammer_charge(delta)
	_update_fist_states(delta, is_charging_hammer)

	var effective_delta: float = delta * 0.20 if is_charging_hammer else delta
	time_left -= effective_delta

	for zone in target_zones:
		if zone.get("cooldown", 0.0) > 0.0:
			zone["cooldown"] -= delta

	if _check_hammer_finisher():
		return

	_refresh_header_hud(is_charging_hammer)

	_check_controller_punches()
	if phase != DomePhase.ATTACK_RECORDING:
		return

	if time_left <= 0.0:
		if hits.is_empty():
			finish_without_hits()
		else:
			start_defense_phase()


func _refresh_header_hud(is_charging_hammer: bool = false, active_zone_name: String = "", step_num: int = 0, remaining: float = 0.0) -> void:
	if not header_label or not is_instance_valid(header_label):
		return

	var fb_line: String = ("\n%s" % last_action_feedback) if not last_action_feedback.is_empty() else ""

	if phase == DomePhase.ATTACK_RECORDING:
		_apply_role_dome_tint(true)
		header_label.modulate = Color(1.0, 0.45, 0.18)
		var pct: float = clampf(time_left / maxf(duration, 0.1), 0.0, 1.0)
		var bar_len: int = int(pct * 8.0)
		var bar_str: String = "█".repeat(bar_len) + "░".repeat(8 - bar_len)
		var step_shown: int = mini(current_attack_step + 1, max_allowed_hits)

		if hammer_charge_time >= HAMMER_CHARGE_REQ or hammer_primed:
			header_label.text = "⚔️ ATACAS — 🔨 ¡BAJA AMBOS PUÑOS!"
			return
		if is_charging_hammer:
			header_label.text = "⚔️ ATACAS — 🔨 MARTILLAZO [%s]" % bar_str
			return

		var max_fist_charge: float = maxf(fist_charge_times[0], fist_charge_times[1])
		var charge_tag: String = ""
		if max_fist_charge >= 1.10:
			charge_tag = " 🔥V3"
			header_label.modulate = Color(1.0, 0.30, 0.12)
		elif max_fist_charge >= 0.50:
			charge_tag = " ⚡CARGADO"
			header_label.modulate = Color(1.0, 0.65, 0.2)

		var tut: String = "\nGrip+Trigger=Golpe | Stick↓=Cancelar" if not _tutorial_controls_shown else ""
		header_label.text = "⚔️ ATACAS (%d/%d)%s  [%s]%s%s" % [step_shown, max_allowed_hits, charge_tag, bar_str, fb_line, tut]
	elif phase == DomePhase.DEFENSE_RHYTHM:
		var pips: String = _get_pips_string(hits.size())
		if defender and defender.get("is_player"):
			_apply_role_dome_tint(false)
			header_label.modulate = Color(0.25, 0.90, 1.0)
			var tut_def: String = "\nPalma=Desvío | Puño=Choque | X=Cruzada" if not _tutorial_controls_shown else ""
			header_label.text = "🛡️ DEFIENDES (%d/%d) %s  %s%s%s" % [step_num, hits.size(), active_zone_name, pips, fb_line, tut_def]
		else:
			_apply_role_dome_tint(true)
			header_label.modulate = Color(1.0, 0.55, 0.20)
			header_label.text = "⚔️ ATACAS (%d/%d) %s  %s%s" % [step_num, hits.size(), active_zone_name, pips, fb_line]


# ==============================================================================
# FASE 2: DEFENSA RÍTMICA SECUENCIAL (1.25s POR GOLPE)
# ==============================================================================

func start_defense_phase() -> void:
	_hide_all_charge_spheres()
	if hits.is_empty():
		finish_without_hits()
		return

	phase = DomePhase.DEFENSE_RHYTHM
	pip_results.clear()
	defense_timer = 0.0
	consecutive_guard_hits = 0
	last_animated_note_idx = -1
	defense_score_sum = 0.0
	defense_round_total_hits = hits.size()
	def_prev_left_pos = Vector3.ZERO
	def_prev_right_pos = Vector3.ZERO
	def_left_velocity = Vector3.ZERO
	def_right_velocity = Vector3.ZERO
	_reset_all_timing_rings()

	var max_offset: float = 0.0
	for h in hits:
		var off: float = float(h.get("time_offset", 0.0))
		if off > max_offset:
			max_offset = off
	defense_total_duration = max_offset + 0.90

	if dome_mesh and is_instance_valid(dome_mesh):
		var mat := dome_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.5, 0.9, 0.08)

	_update_dome_transform_for_defender()

	var first_z: int = int(hits[0].get("zone_id", 0))
	var next_z: int = int(hits[1].get("zone_id", -1)) if hits.size() > 1 else -1
	_update_defense_zone_highlights(first_z, 1, next_z, bool(hits[0].get("is_charged", false)), bool(hits[0].get("is_hammer", false)))
	_refresh_header_hud(false, String(hits[0].get("name", "Centro")), 1, defense_total_duration)


func _process_defense_rhythm(delta: float) -> void:
	defense_timer += delta
	_update_dome_transform_for_defender()
	_update_defender_velocities(delta)
	_update_defender_input_buffers(delta)

	var first_unresolved_idx: int = -1
	for i in range(hits.size()):
		if not hits[i].get("resolved", false):
			first_unresolved_idx = i
			break

	var all_resolved: bool = (first_unresolved_idx == -1)
	var defender_is_player: bool = bool(defender.get("is_player")) if (defender and is_instance_valid(defender)) else false

	if not all_resolved:
		var active_note: Dictionary = hits[first_unresolved_idx]
		var active_z_id: int = int(active_note.get("zone_id", 0))
		var next_z_id: int = int(hits[first_unresolved_idx + 1].get("zone_id", -1)) if (first_unresolved_idx + 1 < hits.size()) else -1
		var is_heavy: bool = bool(active_note.get("is_charged", false)) or bool(active_note.get("is_charged_v3", false))
		var is_hammer: bool = bool(active_note.get("is_hammer", false))
		_update_defense_zone_highlights(active_z_id, first_unresolved_idx + 1, next_z_id, is_heavy, is_hammer)

		var remaining: float = maxf(defense_total_duration - defense_timer, 0.0)
		var active_name: String = String(ZONE_DEFINITIONS[active_z_id]["name"]) if active_z_id < ZONE_DEFINITIONS.size() else "Centro"
		_refresh_header_hud(false, active_name, first_unresolved_idx + 1, remaining)

		var active_zone: Dictionary = target_zones[active_z_id] if active_z_id < target_zones.size() else target_zones[0]
		var active_ring: MeshInstance3D = active_zone.get("timing_ring") as MeshInstance3D
		for z in target_zones:
			var r_other: MeshInstance3D = z.get("timing_ring") as MeshInstance3D
			if r_other and is_instance_valid(r_other) and int(z["id"]) != active_z_id:
				r_other.visible = false

		var time_offset: float = float(active_note.get("time_offset", 0.0))
		var t_diff: float = time_offset - defense_timer

		# Sincronizar animación 3D del atacante justo al lanzar cada golpe
		if first_unresolved_idx != last_animated_note_idx and t_diff <= 0.25:
			last_animated_note_idx = first_unresolved_idx
			if attacker and is_instance_valid(attacker) and attacker.get("procedural_animator"):
				var strike_type: int = 4 if is_hammer else (first_unresolved_idx % 4)
				attacker.procedural_animator.trigger_melee_strike(strike_type)

		if t_diff > 0.0 and t_diff <= RING_PREWARN_SEC:
			if active_ring and is_instance_valid(active_ring):
				active_ring.visible = true
				var t_factor: float = clampf(t_diff / RING_PREWARN_SEC, 0.0, 1.0)
				active_ring.scale = Vector3.ONE * (1.0 + t_factor * 1.65)
				var r_mat: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
				if r_mat:
					if is_hammer:
						r_mat.albedo_color = Color(0.95, 0.2, 1.0, 0.95)
					elif bool(active_note.get("is_charged_v3", false)):
						r_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.95)
					elif bool(active_note.get("is_charged", false)):
						r_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.95)
					else:
						r_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.95)
		elif t_diff > RING_PREWARN_SEC and active_ring and is_instance_valid(active_ring):
			active_ring.visible = false

		# Ventana de resolución defensiva (hasta ±0.28s para Choque de Puños)
		if absf(t_diff) <= 0.28:
			var zone_pos: Vector3 = active_zone["node"].global_position
			if defender_is_player:
				var crossing: bool = _is_defender_crossing_arms()
				var hand_parry_idx: int = _get_defender_hand_near_zone(zone_pos, 0.25) if not crossing else -1
				var hand_clash_idx: int = _get_defender_hand_near_zone(zone_pos, 0.28) if not crossing else -1

				# 1. Bloqueo Perfecto (Parry 90ms sin ser golpe veloz lanzado previamente)
				if hand_parry_idx != -1 and absf(t_diff) <= 0.18:
					var parry_vel: float = (def_left_velocity if hand_parry_idx == 0 else def_right_velocity).length()
					if parry_vel < 0.85 and _is_defender_just_guard_active(hand_parry_idx):
						_resolve_perfect_parry(active_note, active_zone)
						return

				# 2. Choque de Puños (Grip+Trigger cerrado + puñetazo veloz >= 0.85 m/s, no aplica a Martillazo)
				if hand_clash_idx != -1 and not is_hammer:
					var clash_closed: bool = _is_defender_fist_closed(hand_clash_idx)
					var clash_vel: float = (def_left_velocity if hand_clash_idx == 0 else def_right_velocity).length()
					if clash_closed and clash_vel >= 0.85:
						_resolve_fist_clash(active_note, active_zone, hand_clash_idx)
						if phase != DomePhase.DEFENSE_RHYTHM:
							return
						return

				# 3. Desvío con Palma Abierta (sin Grip+Trigger) o 4. Guardia Cruzada en X (ambos puños al pecho)
				if absf(t_diff) <= 0.22:
					if hand_parry_idx != -1 and not _is_defender_fist_closed(hand_parry_idx):
						_resolve_hand_block(active_note, active_zone, hand_parry_idx)
						if phase != DomePhase.DEFENSE_RHYTHM:
							return
					elif crossing:
						_resolve_cross_arm_guard(active_note, active_zone)
						if phase != DomePhase.DEFENSE_RHYTHM:
							return
			elif t_diff <= 0.05:
				_resolve_ai_defense(active_note, active_zone)
				if phase != DomePhase.DEFENSE_RHYTHM:
					return
		elif t_diff < -0.22:
			_resolve_unblocked_hit(active_note, active_zone)
			if phase != DomePhase.DEFENSE_RHYTHM:
				return
	else:
		_reset_all_timing_rings()

	all_resolved = true
	for h in hits:
		if not h.get("resolved", false):
			all_resolved = false
			break

	if all_resolved or defense_timer >= defense_total_duration:
		evaluate_round_outcome()


func _resolve_perfect_parry(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	_modify_fighter_ki(defender, 25.0)
	_modify_fighter_ki(attacker, -12.0)
	if defender and is_instance_valid(defender) and defender.has_method("increase_np"):
		defender.increase_np(400.0)

	if audio_player:
		audio_player.global_position = zone["node"].global_position
		audio_player.stream = sfx_parry
		audio_player.pitch_scale = 1.30
		audio_player.play()

	_spawn_parry_shockwave(zone["node"].global_position)
	_pulse_defender_both_hands(250.0, 1.0, 0.25)

	last_action_feedback = "⚡ ¡PARRY PERFECTO! (+25 Ki)"
	pip_results.append("blocked")
	_spawn_impact_popup(zone["node"].global_position, "✨ ¡PARRY!", Color(1.0, 0.92, 0.25))
	emit_signal("defense_action_resolved", "perfect_parry", zone["id"], true, 25.0, 400.0)
	_trigger_hit_stop(0.08)

	for h in hits:
		h["resolved"] = true

	if _check_ki_break_after_note():
		return
	pending_attack_penalty = 0
	restart_as_attacker()


func _resolve_fist_clash(note: Dictionary, zone: Dictionary, hand_idx: int) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var zone_pos: Vector3 = zone["node"].global_position
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 9000.0, 100.0)
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 9000.0, 100.0)
	var r_bp: float = bp_def / bp_atk

	var score: float = 0.25
	if r_bp >= 0.70:
		# Choque de Puños Parejo o Superior: 0 daño, gran recarga de Ki y BP para ambos, -1 golpe al atacante
		clash_penalty_hits += 1
		var def_ki_gain: float = 25.0 if r_bp > 1.40 else 22.0
		var atk_ki_gain: float = 8.0 if r_bp > 1.40 else 15.0
		var def_bp_gain: float = 350.0 if r_bp > 1.40 else 300.0
		var atk_bp_gain: float = 100.0 if r_bp > 1.40 else 250.0
		score = 1.00 if r_bp > 1.40 else 0.65

		_modify_fighter_ki(defender, def_ki_gain)
		_modify_fighter_ki(attacker, atk_ki_gain)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(def_bp_gain)
		if attacker and attacker.has_method("increase_np"):
			attacker.increase_np(atk_bp_gain)

		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.stream = sfx_parry
			audio_player.pitch_scale = 1.15
			audio_player.play()
		_spawn_parry_shockwave(zone_pos)
		_pulse_defender_hand(hand_idx, 210.0, 1.0, 0.16)
		_trigger_hit_stop(0.08)

		last_action_feedback = "⚡ ¡CHOQUE DE PUÑOS! +%d Ki (-1 golpe)" % int(def_ki_gain)
		pip_results.append("clash")
		_spawn_impact_popup(zone_pos, "⚡ ¡CHOQUE!", Color(1.0, 1.0, 0.85))
		emit_signal("defense_action_resolved", "fist_clash", zone["id"], true, def_ki_gain, def_bp_gain)
	else:
		# Defensor muy inferior en BP (< 70%): puño cede, entra 50% daño
		var raw_dmg: float = 360.0 if bool(note.get("is_charged_v3", false)) else (240.0 if bool(note.get("is_charged", false)) else 140.0)
		var partial_dmg: float = raw_dmg * 0.50
		_modify_fighter_ki(defender, 5.0)
		_modify_fighter_ki(attacker, 12.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(partial_dmg, Vector3.ZERO)
		if attacker and attacker.has_method("increase_np"):
			attacker.increase_np(200.0)
		_spawn_hit_spark(zone_pos)
		_pulse_defender_hand(hand_idx, 160.0, 0.75, 0.14)

		last_action_feedback = "💥 ¡SUPERADO EN CHOQUE! (-%d BP)" % int(partial_dmg)
		pip_results.append("hit")
		_spawn_impact_popup(zone_pos, "💥 ¡IMPACTO!", Color(1.0, 0.38, 0.15))
		emit_signal("defense_action_resolved", "fist_clash_lost", zone["id"], false, 5.0, 0.0)

	note["defense_score"] = score
	defense_score_sum += score
	_check_ki_break_after_note()


func _resolve_hand_block(note: Dictionary, zone: Dictionary, hand_idx: int) -> void:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	if is_hammer:
		# El Martillazo de 2 manos rompe la defensa con 1 sola mano
		_resolve_unblocked_hit(note, zone)
		return

	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var zone_pos: Vector3 = zone["node"].global_position
	var score: float = 1.0

	if is_v3:
		# Cargado v3 SÍ se frena con 1 mano (mitiga 70%, cuesta -12 Ki, suma 0.75)
		var v3_mitigated: float = 420.0 * 0.30
		score = 0.75
		_modify_fighter_ki(defender, -12.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(v3_mitigated, Vector3.ZERO)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.stream = sfx_hit_heavy
			audio_player.play()
		_spawn_block_spark(zone_pos, Color(1.0, 0.55, 0.2))
		last_action_feedback = "✋ ¡CARGADO V3 FRENADO! (-12 Ki)"
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "✋ ¡FRENADO!", Color(0.25, 0.92, 1.0))
		emit_signal("defense_action_resolved", "hand_block_v3", zone["id"], true, -12.0, 0.0)
	elif is_charged:
		var mitigated_dmg: float = 140.0
		score = 0.50
		_modify_fighter_ki(defender, -8.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(mitigated_dmg, Vector3.ZERO)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(75.0)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.stream = sfx_hit_heavy
			audio_player.play()
		_spawn_block_spark(zone_pos, Color(1.0, 0.75, 0.2))
		last_action_feedback = "✋ ¡CARGADO BLOQUEADO! (-8 Ki)"
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "🛡️ ¡BLOQUEADO!", Color(0.25, 0.92, 1.0))
		emit_signal("defense_action_resolved", "partial_block", zone["id"], true, -8.0, 75.0)
	else:
		score = 1.00
		_modify_fighter_ki(defender, 12.0)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(150.0)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.stream = sfx_hit_light
			audio_player.pitch_scale = 1.25
			audio_player.play()
		_spawn_block_spark(zone_pos, Color(1.0, 0.9, 0.2))
		last_action_feedback = "✋ ¡DESVÍO LIMPIO! (+12 Ki)"
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "✋ ¡DESVÍO!", Color(0.35, 1.0, 0.70))
		emit_signal("defense_action_resolved", "hand_block", zone["id"], true, 12.0, 150.0)

	_pulse_defender_hand(hand_idx, 180.0, 0.85, 0.10)
	note["defense_score"] = score
	defense_score_sum += score
	_check_ki_break_after_note()


func _resolve_cross_arm_guard(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits += 1
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var zone_pos: Vector3 = zone["node"].global_position

	var raw_dmg: float = 580.0 if is_hammer else (420.0 if is_v3 else (280.0 if is_charged else 140.0))
	var final_dmg: float = raw_dmg * 0.15
	var cfg_ki: KiEconomyConfig = KiEconomyConfig.get_default()
	var base_ki_cost: float = cfg_ki.melee_hammer_guard_cost if is_hammer else (cfg_ki.melee_v3_cost if is_v3 else (cfg_ki.melee_charged_cost if is_charged else cfg_ki.melee_quick_cost))
	var ki_cost: float = base_ki_cost + float(consecutive_guard_hits - 1) * cfg_ki.melee_guard_escalation

	_modify_fighter_ki(defender, -ki_cost)
	_modify_fighter_ki(attacker, 2.0)
	if defender and defender.has_method("take_hit"):
		defender.take_hit(final_dmg, Vector3.ZERO)
	if defender and defender.has_method("increase_np"):
		defender.increase_np(20.0)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.stream = sfx_hit_heavy if (is_hammer or is_v3) else sfx_hit_light
		audio_player.pitch_scale = 0.85
		audio_player.play()

	_spawn_block_spark(zone_pos, Color(0.2, 0.7, 1.0))
	_pulse_defender_both_hands(140.0, 0.65, 0.10)

	note["defense_score"] = 0.25
	defense_score_sum += 0.25
	last_action_feedback = "🛡️ GUARDIA CRUZADA (-%d Ki)" % int(ki_cost)
	pip_results.append("blocked")
	_spawn_impact_popup(zone_pos, "🛡️ ¡BLOQUEADO!", Color(0.30, 0.78, 1.0))
	emit_signal("defense_action_resolved", "cross_arm_guard", zone["id"], true, -ki_cost, 20.0)
	_check_ki_break_after_note()


func _resolve_unblocked_hit(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var zone_pos: Vector3 = zone["node"].global_position
	var raw_dmg: float = 580.0 if is_hammer else (420.0 if is_v3 else (280.0 if is_charged else 140.0))

	_modify_fighter_ki(defender, -10.0)
	_modify_fighter_ki(attacker, 8.0)

	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(raw_dmg, -global_transform.basis.z)
		if defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(0.75 if (is_hammer or is_v3) else 0.45, -global_transform.basis.z)

	if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
		attacker.increase_np(raw_dmg * 0.40)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.stream = sfx_hit_heavy if (is_charged or is_v3 or is_hammer) else sfx_hit_light
		audio_player.play()

	_pulse_defender_both_hands(200.0, 0.80, 0.14)
	_spawn_hit_spark(zone_pos)

	note["defense_score"] = 0.0
	last_action_feedback = "💥 ¡IMPACTO CONECTADO!"
	pip_results.append("hit")
	_spawn_impact_popup(zone_pos, "💥 ¡IMPACTO!", Color(1.0, 0.42, 0.15))
	emit_signal("defense_action_resolved", "hit_taken", zone["id"], false, -10.0, 0.0)

	# Si el golpe no bloqueado fue Martillazo DBZ o Cargado v3: interrumpe y lanza al rival de inmediato
	if is_hammer:
		_trigger_finisher_and_close("hammer_strike", float(note.get("velocity", 4.0)))
		return
	if is_v3:
		var v3_mode: String = "charged_v3_up" if String(note.get("v3_launch_mode", "BACK")) == "UP" else "charged_v3_back"
		_trigger_finisher_and_close(v3_mode, float(note.get("velocity", 3.5)))
		return

	_check_ki_break_after_note()


func _resolve_ai_defense(note: Dictionary, zone: Dictionary) -> void:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var in_zenkai: bool = bool(defender.get("is_in_zenkai_state")) if defender else false
	var def_ki: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 50.0
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 9000.0, 100.0)
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 9000.0, 100.0)
	var r_bp: float = bp_def / bp_atk

	# Si la IA no tiene Ki suficiente, no puede frenar ataques pesados
	if def_ki <= 5.0:
		_resolve_unblocked_hit(note, zone)
		return

	var roll: float = randf()
	if is_hammer:
		if in_zenkai and roll < 0.12:
			_resolve_perfect_parry(note, zone)
		elif def_ki >= 22.0 and roll < 0.45:
			_resolve_cross_arm_guard(note, zone)
		else:
			_resolve_unblocked_hit(note, zone)
	elif is_v3:
		if in_zenkai and roll < 0.14:
			_resolve_perfect_parry(note, zone)
		elif r_bp >= 0.72 and roll < 0.35:
			_resolve_fist_clash(note, zone, 0)
		elif roll < 0.58:
			_resolve_hand_block(note, zone, 0)
		elif def_ki >= 16.0 and roll < 0.72:
			_resolve_cross_arm_guard(note, zone)
		else:
			_resolve_unblocked_hit(note, zone)
	elif is_charged:
		if in_zenkai and roll < 0.12:
			_resolve_perfect_parry(note, zone)
		elif r_bp >= 0.70 and roll < 0.32:
			_resolve_fist_clash(note, zone, 0)
		elif roll < 0.62:
			_resolve_hand_block(note, zone, 0)
		elif roll < 0.80:
			_resolve_cross_arm_guard(note, zone)
		else:
			_resolve_unblocked_hit(note, zone)
	else:
		if in_zenkai and roll < 0.10:
			_resolve_perfect_parry(note, zone)
		elif r_bp >= 0.70 and roll < 0.28:
			_resolve_fist_clash(note, zone, 0)
		elif roll < 0.58:
			_resolve_hand_block(note, zone, 0)
		elif roll < 0.74:
			_resolve_cross_arm_guard(note, zone)
		else:
			_resolve_unblocked_hit(note, zone)


func _check_ki_break_after_note() -> bool:
	if not defender or not attacker or not is_instance_valid(defender) or not is_instance_valid(attacker):
		return false
	var def_ki: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
	var atk_ki: float = float(attacker.get("current_ki")) if attacker.get("current_ki") != null else 0.0

	if def_ki <= 0.0 and atk_ki > 0.0:
		_start_unblockable_ki_break(attacker, defender)
		return true
	elif atk_ki <= 0.0 and def_ki > 0.0:
		_start_unblockable_ki_break(defender, attacker)
		return true
	elif def_ki <= 0.0 and atk_ki <= 0.0:
		# Doble agotamiento simultáneo: el duelo se separa por falta de energía
		finish_without_hits()
		return true
	return false


func _start_unblockable_ki_break(p_winner: Node3D, p_victim: Node3D) -> void:
	phase = DomePhase.UNBLOCKABLE_KI_BREAK
	ki_break_attacker = p_winner
	ki_break_victim = p_victim
	_reset_all_timing_rings()
	_hide_all_charge_spheres()

	if p_victim and is_instance_valid(p_victim):
		p_victim.set("is_blocking", false)
		p_victim.set("is_guard_broken", true)
		p_victim.set("guard_break_timer", 2.0)

	# Mostrar únicamente la caja central gigante dorada/roja
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		if z_node and is_instance_valid(z_node):
			z_node.visible = (z_id == 1)
			if z_id == 1:
				z_node.scale = Vector3.ONE * 1.65
				var bmat: StandardMaterial3D = zone.get("box_mat") as StandardMaterial3D
				if bmat:
					bmat.albedo_color = Color(1.0, 0.25, 0.1, 0.95)
					bmat.emission = Color(1.0, 0.75, 0.1)
					bmat.emission_energy_multiplier = 3.2
				var slbl: Label3D = zone.get("step_label") as Label3D
				if slbl:
					slbl.text = "💥"
					slbl.visible = true

	var winner_is_player: bool = bool(p_winner.get("is_player")) if p_winner else false
	ki_break_timer = 3.5 if winner_is_player else 0.90
	if header_label and is_instance_valid(header_label):
		header_label.modulate = Color(1.0, 0.25, 0.15)
		if winner_is_player:
			header_label.text = "💥 ¡RIVAL SIN KI! ¡INDEFENSO!\n¡GOLPEA LA CAJA CENTRAL (Grip+Trigger) PARA LANZARLO!"
		else:
			header_label.text = "⚠️ ¡TE QUEDASTE SIN KI! ¡GUARDIA ROTA!\n¡ATAQUE FUERTE IMBLOQUEABLE ENTRANTE!"


func _process_unblockable_ki_break(delta: float) -> void:
	_update_dome_transform()
	ki_break_timer -= delta

	var winner_is_player: bool = bool(ki_break_attacker.get("is_player")) if (ki_break_attacker and is_instance_valid(ki_break_attacker)) else false
	if winner_is_player:
		_update_controller_velocities(delta)
		_update_fist_states(delta, false)
		var zone_pos: Vector3 = target_zones[1]["node"].global_position if target_zones.size() > 1 else global_position
		for h_idx in [0, 1]:
			if is_fist_closed[h_idx]:
				var ctrl: XRController3D = _get_controller("LeftHand" if h_idx == 0 else "RightHand")
				var vel_len: float = (left_velocity if h_idx == 0 else right_velocity).length()
				if ctrl and ctrl.global_position.distance_to(zone_pos) <= 0.34 and vel_len >= 0.70:
					_execute_unblockable_ki_break_hit(vel_len)
					return

	if ki_break_timer <= 0.0:
		_execute_unblockable_ki_break_hit(4.2)


func _execute_unblockable_ki_break_hit(swing_vel: float) -> void:
	if ki_break_victim and is_instance_valid(ki_break_victim) and ki_break_victim.has_method("take_hit"):
		ki_break_victim.take_hit(500.0, Vector3.BACK)
	if ki_break_attacker and is_instance_valid(ki_break_attacker) and ki_break_attacker.has_method("increase_np"):
		ki_break_attacker.increase_np(250.0)
	if target_zones.size() > 1:
		_spawn_hit_spark(target_zones[1]["node"].global_position)

	attacker = ki_break_attacker
	defender = ki_break_victim
	_trigger_finisher_and_close("ki_break_launch", swing_vel)


func _trigger_finisher_and_close(finisher_name: String, swing_vel: float) -> void:
	if not is_active:
		return
	is_active = false
	phase = DomePhase.COMPLETED
	last_finisher_attacker = attacker
	last_finisher_victim = defender
	_hide_all_charge_spheres()
	_reset_all_timing_rings()
	emit_signal("finisher_triggered", finisher_name, swing_vel, hits, last_impact_vector)
	if dome_mesh and is_instance_valid(dome_mesh):
		var tw := create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()


## Evalúa si los golpes fueron mayormente bloqueados (invierte roles) o conectados (continúa ofensiva)
func evaluate_round_outcome() -> void:
	if not is_active:
		return
	_tutorial_controls_shown = true
	if _check_ki_break_after_note():
		return

	var n_hits: int = maxi(defense_round_total_hits, hits.size())
	var threshold: float = float(n_hits) * 0.5
	if n_hits > 0 and defense_score_sum > threshold:
		pending_attack_penalty = 0
		var pct: int = int(roundf((defense_score_sum / float(n_hits)) * 100.0))
		_begin_phase_transition(
			"restart_attacker",
			0.65,
			"🛡️➡️⚔️ ¡DEFENSA DOMINANTE (%d%%)! ¡INVERSIÓN DE ROLES!" % pct,
			Color(0.25, 1.0, 0.55)
		)
	else:
		pending_attack_penalty = clash_penalty_hits
		var atk_name: String = "TÚ SIGUES ATACANDO" if (attacker and attacker.get("is_player")) else "EL RIVAL SIGUE ATACANDO"
		var penalty_txt: String = (" (-%d golpes por Choque)" % pending_attack_penalty) if pending_attack_penalty > 0 else ""
		_begin_phase_transition(
			"continue_offense",
			0.65,
			"🔥 ¡OFENSIVA CONTINUA! %s%s" % [atk_name, penalty_txt],
			Color(1.0, 0.70, 0.20)
		)


func continue_attacker_offense() -> void:
	last_action_feedback = ""
	start_attack_phase(attacker, defender)


## Genera secuencia rítmica de la IA incluyendo posibles Cargados v3 o Martillazo al suelo
func generate_ai_attack_sequence() -> void:
	hits.clear()
	var ai_in_zenkai: bool = bool(attacker.get("is_in_zenkai_state")) if attacker else false
	var num_hits: int = max_allowed_hits
	var curr_time: float = NOTE_CADENCE_SEC
	var last_zone: int = -1

	for i in range(num_hits):
		var zone_id: int = randi() % ZONE_DEFINITIONS.size()
		if zone_id == last_zone:
			zone_id = (zone_id + 1) % ZONE_DEFINITIONS.size()
		last_zone = zone_id

		var is_last: bool = (i == num_hits - 1)
		var is_hammer: bool = false
		var is_v3: bool = false
		var is_charged: bool = false
		var power: float = 1.0
		var v3_mode: String = "BACK"

		if is_last and (ai_in_zenkai or (attacker and float(attacker.get("current_ki")) > 35.0)):
			var r: float = randf()
			if r < 0.22:
				is_hammer = true
				is_charged = true
				power = 4.5
				zone_id = 1
			elif r < 0.48:
				is_v3 = true
				is_charged = true
				power = 3.0
				v3_mode = "UP" if zone_id == 0 else "BACK"
			elif r < 0.78:
				is_charged = true
				power = 2.0

		var target_pos: Vector3 = target_zones[zone_id]["node"].global_position if zone_id < target_zones.size() else global_position
		var label_name: String = "Martillazo DBZ" if is_hammer else ("Cargado v3" if is_v3 else String(ZONE_DEFINITIONS[zone_id]["name"]))
		hits.append({
			"zone_id": zone_id,
			"name": label_name,
			"pos": target_pos,
			"hand": "Right" if (i % 2 == 0) else "Left",
			"time_offset": curr_time,
			"power": power,
			"is_charged": is_charged,
			"is_charged_v3": is_v3,
			"is_hammer": is_hammer,
			"v3_launch_mode": v3_mode,
			"velocity": 4.5,
			"swing_dir": Vector3.DOWN if is_hammer else (Vector3.FORWARD + Vector3.RIGHT * (0.2 if i % 2 == 0 else -0.2)),
			"defense_score": 0.0,
			"resolved": false
		})
		curr_time += NOTE_CADENCE_SEC


# ==============================================================================
# INVERSIÓN DE ROLES (TURNOVER) Y FINALIZACIÓN
# ==============================================================================

func restart_as_attacker() -> void:
	var temp: Node3D = attacker
	attacker = defender
	defender = temp
	last_action_feedback = ""

	emit_signal("perfect_parry_triggered", attacker, defender)
	print("[BulletTimeDome] 🔄 Cambio de turno. Nuevo atacante: %s" % [attacker.name if attacker else "None"])
	start_attack_phase(attacker, defender)


func finish_without_hits() -> void:
	if not is_active:
		return
	is_active = false
	phase = DomePhase.COMPLETED
	_hide_all_charge_spheres()
	_reset_all_timing_rings()
	emit_signal("bullet_time_completed", [], Vector3.ZERO)
	if dome_mesh and is_instance_valid(dome_mesh):
		var tw := create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()


# ==============================================================================
# SEGUIMIENTO BIOMECÁNICO, PUÑOS CERRADOS Y CONTROLES DEL DEFENSOR
# ==============================================================================

func _modify_fighter_ki(fighter: Node3D, delta_ki: float) -> void:
	if not fighter or not is_instance_valid(fighter):
		return
	var cur_ki: float = float(fighter.get("current_ki")) if fighter.get("current_ki") != null else 0.0
	var max_ki: float = 100.0
	var cdata: Resource = fighter.get("character_data")
	if cdata and "base_ki" in cdata:
		max_ki = float(cdata.base_ki)
	fighter.set("current_ki", clampf(cur_ki + delta_ki, 0.0, max_ki))
	if fighter.has_method("_notify_stats"):
		fighter._notify_stats()


func _update_defender_velocities(delta: float) -> void:
	if delta <= 0.0001 or not defender or not is_instance_valid(defender) or not bool(defender.get("is_player")):
		return
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D
	if not origin:
		return
	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand") as XRController3D

	if left_ctrl:
		var lp: Vector3 = left_ctrl.global_position
		if def_prev_left_pos != Vector3.ZERO:
			def_left_velocity = (lp - def_prev_left_pos) / delta
		def_prev_left_pos = lp
	if right_ctrl:
		var rp: Vector3 = right_ctrl.global_position
		if def_prev_right_pos != Vector3.ZERO:
			def_right_velocity = (rp - def_prev_right_pos) / delta
		def_prev_right_pos = rp


func _update_defender_input_buffers(delta: float) -> void:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D
	if not origin:
		return

	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand") as XRController3D

	if left_ctrl:
		def_grip_l = left_ctrl.get_float("grip") > 0.50 or left_ctrl.is_button_pressed("grip_click")
		def_trig_l = left_ctrl.get_float("trigger") > 0.50 or left_ctrl.is_button_pressed("trigger_click")
		if def_grip_l and not prev_grip_l:
			buffer_grip_timer_l = 0.09
		if def_trig_l and not prev_trig_l:
			buffer_trig_timer_l = 0.09
		prev_grip_l = def_grip_l
		prev_trig_l = def_trig_l

	if right_ctrl:
		def_grip_r = right_ctrl.get_float("grip") > 0.50 or right_ctrl.is_button_pressed("grip_click")
		def_trig_r = right_ctrl.get_float("trigger") > 0.50 or right_ctrl.is_button_pressed("trigger_click")
		if def_grip_r and not prev_grip_r:
			buffer_grip_timer_r = 0.09
		if def_trig_r and not prev_trig_r:
			buffer_trig_timer_r = 0.09
		prev_grip_r = def_grip_r
		prev_trig_r = def_trig_r

	buffer_grip_timer_l = maxf(buffer_grip_timer_l - delta, 0.0)
	buffer_grip_timer_r = maxf(buffer_grip_timer_r - delta, 0.0)
	buffer_trig_timer_l = maxf(buffer_trig_timer_l - delta, 0.0)
	buffer_trig_timer_r = maxf(buffer_trig_timer_r - delta, 0.0)


func _is_defender_fist_closed(hand_idx: int) -> bool:
	if hand_idx == 0:
		return def_grip_l and def_trig_l
	elif hand_idx == 1:
		return def_grip_r and def_trig_r
	return false


func _is_defender_just_guard_active(hand_idx: int) -> bool:
	if hand_idx == 0:
		return (buffer_grip_timer_l > 0.0 and def_trig_l) or (buffer_trig_timer_l > 0.0 and def_grip_l)
	elif hand_idx == 1:
		return (buffer_grip_timer_r > 0.0 and def_trig_r) or (buffer_trig_timer_r > 0.0 and def_grip_r)
	return false


func _get_defender_hand_near_zone(zone_pos: Vector3, threshold: float) -> int:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return -1
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D
	if not origin:
		return -1
	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand") as XRController3D

	if left_ctrl and left_ctrl.global_position.distance_to(zone_pos) <= threshold:
		return 0
	if right_ctrl and right_ctrl.global_position.distance_to(zone_pos) <= threshold:
		return 1
	return -1


func _is_defender_crossing_arms() -> bool:
	if not defender or not is_instance_valid(defender):
		return false
	if defender.get("is_blocking"):
		return true

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return false

	var cam: Camera3D = origin.get_node_or_null("XRCamera3D") as Camera3D
	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand") as XRController3D

	# Brazos cruzados en 'X': ambos puños cerrados (Grip+Trigger en las 2 manos) juntos al pecho
	if cam and left_ctrl and right_ctrl and def_grip_l and def_trig_l and def_grip_r and def_trig_r:
		var hands_dist: float = left_ctrl.global_position.distance_to(right_ctrl.global_position)
		var avg_pos: Vector3 = (left_ctrl.global_position + right_ctrl.global_position) * 0.5
		var rel_y: float = avg_pos.y - cam.global_position.y
		if hands_dist < 0.30 and rel_y > -0.32 and rel_y < 0.22:
			return true
	return false


func _trigger_hit_stop(freeze_time: float = 0.08) -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(freeze_time, true, false, true).timeout
	Engine.time_scale = 1.0


func _pulse_defender_hand(hand_idx: int, freq: float, amp: float, dur: float) -> void:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D
	if not origin:
		return
	var h_name: String = "LeftHand" if hand_idx == 0 else "RightHand"
	var ctrl: XRController3D = origin.get_node_or_null(h_name) as XRController3D
	if ctrl and ctrl.has_method("trigger_haptic_pulse"):
		ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _pulse_defender_both_hands(freq: float, amp: float, dur: float) -> void:
	_pulse_defender_hand(0, freq, amp, dur)
	_pulse_defender_hand(1, freq, amp, dur)


# ==============================================================================
# CONSTRUCCIÓN DE MALLAS Y RETÍCULAS HOLOGRÁFICAS
# ==============================================================================

func _build_visual_dome() -> void:
	dome_mesh = MeshInstance3D.new()
	dome_mesh.name = "MeleeDomeSphere"
	var sphere := SphereMesh.new()
	sphere.radius = 1.25
	sphere.height = 2.50
	sphere.radial_segments = 32
	sphere.rings = 16
	dome_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.08)
	dome_mesh.material_override = mat
	add_child(dome_mesh)


func _build_target_boxes() -> void:
	target_zones.clear()

	for def in ZONE_DEFINITIONS:
		var zone_node := Node3D.new()
		zone_node.name = "Zone_%d_%s" % [def.id, def.name.replace(" / ", "_").replace(" ", "_")]
		zone_node.position = def.offset
		add_child(zone_node)

		var box_mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.16, 0.05)
		box_mesh_inst.mesh = box

		var mat_box := StandardMaterial3D.new()
		mat_box.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_box.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		mat_box.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_box.albedo_color = def.color
		mat_box.emission_enabled = true
		mat_box.emission = Color(def.color.r, def.color.g, def.color.b)
		mat_box.emission_energy_multiplier = 1.2
		mat_box.no_depth_test = true
		mat_box.render_priority = 115
		box_mesh_inst.material_override = mat_box
		zone_node.add_child(box_mesh_inst)

		var inner_quad := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.12, 0.12)
		inner_quad.mesh = quad
		inner_quad.position = Vector3(0.0, 0.0, 0.028)

		var mat_quad := StandardMaterial3D.new()
		mat_quad.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_quad.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_quad.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		mat_quad.no_depth_test = true
		mat_quad.render_priority = 116
		inner_quad.material_override = mat_quad
		zone_node.add_child(inner_quad)

		var timing_ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.08
		torus.outer_radius = 0.095
		torus.rings = 16
		torus.ring_segments = 16
		timing_ring.mesh = torus
		timing_ring.rotation.x = PI * 0.5
		timing_ring.position = Vector3(0.0, 0.0, 0.035)
		timing_ring.visible = false

		var mat_ring := StandardMaterial3D.new()
		mat_ring.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_ring.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_ring.albedo_color = Color(1.0, 0.9, 0.2, 0.95)
		mat_ring.no_depth_test = true
		mat_ring.render_priority = 117
		timing_ring.material_override = mat_ring
		zone_node.add_child(timing_ring)

		var step_lbl := Label3D.new()
		step_lbl.name = "StepNumberLabel"
		step_lbl.text = ""
		step_lbl.font_size = 38
		step_lbl.pixel_size = 0.0022
		step_lbl.outline_size = 10
		step_lbl.modulate = Color(1.0, 0.95, 0.25, 1.0)
		step_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		step_lbl.no_depth_test = true
		step_lbl.render_priority = 112
		step_lbl.position = Vector3(0.0, 0.0, 0.048)
		step_lbl.visible = false
		zone_node.add_child(step_lbl)

		target_zones.append({
			"id": def.id,
			"name": def.name,
			"node": zone_node,
			"box_mesh": box_mesh_inst,
			"box_mat": mat_box,
			"inner_mesh": inner_quad,
			"inner_mat": mat_quad,
			"timing_ring": timing_ring,
			"step_label": step_lbl,
			"hit": false,
			"cooldown": 0.0,
			"color": def.color
		})


func _get_player_camera() -> Camera3D:
	for f in [attacker, defender]:
		if f and is_instance_valid(f) and bool(f.get("is_player")):
			var orig: Node = f.get_parent()
			if orig:
				var c: Camera3D = orig.get_node_or_null("XRCamera3D") as Camera3D
				if c and is_instance_valid(c):
					return c
	return get_viewport().get_camera_3d() if get_viewport() else null


func _build_header_hud() -> void:
	header_label = Label3D.new()
	header_label.name = "HeaderLabel"
	header_label.text = "🥊 FASE DE ATAQUE 🥊"
	header_label.font_size = 24
	header_label.pixel_size = 0.0014
	header_label.no_depth_test = true
	header_label.render_priority = 125
	header_label.outline_size = 10
	header_label.modulate = Color(1.0, 0.95, 0.3)
	header_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	var cam: Camera3D = _get_player_camera()
	if cam and is_instance_valid(cam):
		melee_hud_anchor = Node3D.new()
		melee_hud_anchor.name = "MeleeHUDAnchor"
		melee_hud_anchor.position = Vector3(0.0, 0.23, -1.15)
		cam.add_child(melee_hud_anchor)
		header_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		header_label.position = Vector3.ZERO
		melee_hud_anchor.add_child(header_label)
	else:
		header_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		header_label.position = Vector3(0.0, 0.42, -0.75)
		add_child(header_label)


func _get_fighter_chest_pos(fighter: Node3D) -> Vector3:
	if not fighter or not is_instance_valid(fighter):
		return global_position
	if fighter.get("is_player"):
		var my_origin: Node = fighter.get_parent()
		var cam: Camera3D = my_origin.get_node_or_null("XRCamera3D") as Camera3D if my_origin else null
		if cam and is_instance_valid(cam):
			return cam.global_position - Vector3(0.0, 0.22, 0.0)
	return fighter.global_position + Vector3(0.0, 1.22, 0.0)


func _get_atk_to_def_dir() -> Vector3:
	if attacker and defender and is_instance_valid(attacker) and is_instance_valid(defender):
		var atk_c: Vector3 = _get_fighter_chest_pos(attacker)
		var def_c: Vector3 = _get_fighter_chest_pos(defender)
		var diff: Vector3 = Vector3(def_c.x - atk_c.x, 0.0, def_c.z - atk_c.z)
		if diff.length_squared() >= 0.0025:
			locked_atk_to_def_dir = diff.normalized()
			return locked_atk_to_def_dir
	if locked_atk_to_def_dir.length_squared() >= 0.01:
		return locked_atk_to_def_dir.normalized()
	return Vector3.FORWARD


func _clamp_dome_y_to_player(raw_y: float, atk_chest: Vector3, def_chest: Vector3) -> float:
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_player")):
		return clampf(raw_y, atk_chest.y - 0.30, atk_chest.y + 0.30)
	if defender and is_instance_valid(defender) and bool(defender.get("is_player")):
		return clampf(raw_y, def_chest.y - 0.30, def_chest.y + 0.30)
	return raw_y


func _get_player_and_ai() -> Array[Node3D]:
	var p_node: Node3D = null
	var ai_node: Node3D = null
	for f in [attacker, defender]:
		if f and is_instance_valid(f):
			if bool(f.get("is_player")):
				p_node = f
			else:
				ai_node = f
	return [p_node, ai_node]


func _keep_ai_face_to_face(delta: float) -> void:
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var ai_node: Node3D = pair[1]
	if not p_node or not ai_node:
		return
	var cam: Camera3D = _get_player_camera()
	if not cam or not is_instance_valid(cam):
		return
	var cam_fwd_xz: Vector3 = -cam.global_transform.basis.z
	cam_fwd_xz.y = 0.0
	cam_fwd_xz = cam_fwd_xz.normalized() if cam_fwd_xz.length_squared() > 0.001 else Vector3.FORWARD
	var p_orig: Node3D = p_node.get_parent() as Node3D if p_node.get_parent() is Node3D else null
	var target_y: float = p_orig.global_position.y if p_orig else p_node.global_position.y
	var desired_ai_pos: Vector3 = Vector3(cam.global_position.x, target_y, cam.global_position.z) + cam_fwd_xz * 0.85
	var w: float = clampf(delta * 10.0, 0.0, 1.0)
	ai_node.global_position = ai_node.global_position.lerp(desired_ai_pos, w)
	if ai_node.has_method("_clamp_to_arena"):
		ai_node._clamp_to_arena(ai_node)


func _update_dome_transform() -> void:
	var cam: Camera3D = _get_player_camera()
	if cam and is_instance_valid(cam):
		var cam_fwd_xz: Vector3 = -cam.global_transform.basis.z
		cam_fwd_xz.y = 0.0
		cam_fwd_xz = cam_fwd_xz.normalized() if cam_fwd_xz.length_squared() > 0.001 else Vector3.FORWARD
		var chest_y: float = cam.global_position.y - 0.22
		global_position = Vector3(cam.global_position.x, chest_y, cam.global_position.z) + cam_fwd_xz * 0.48
		rotation.y = atan2(-cam_fwd_xz.x, -cam_fwd_xz.z)
		rotation.x = 0.0
		return

	var atk_chest: Vector3 = _get_fighter_chest_pos(attacker) if (attacker and is_instance_valid(attacker)) else global_position
	var def_chest: Vector3 = _get_fighter_chest_pos(defender) if (defender and is_instance_valid(defender)) else (atk_chest + Vector3.FORWARD * 0.65)
	var dir_to_def: Vector3 = _get_atk_to_def_dir()
	var horiz_dist: float = Vector2(def_chest.x - atk_chest.x, def_chest.z - atk_chest.z).length()
	var dome_offset: float = clampf(horiz_dist * 0.62, 0.36, 0.52) if horiz_dist > 0.05 else 0.45
	var dome_y: float = _clamp_dome_y_to_player((atk_chest.y + def_chest.y) * 0.5 - 0.03, atk_chest, def_chest)

	global_position = Vector3(atk_chest.x, dome_y, atk_chest.z) + dir_to_def * dome_offset
	rotation.y = atan2(-dir_to_def.x, -dir_to_def.z)
	rotation.x = 0.0


func _update_dome_transform_for_defender() -> void:
	# Tanto en ataque como en defensa, las cajas quedan siempre a 0.48m frente al jugador
	_update_dome_transform()


# ==============================================================================
# REGISTRO DE GOLPES DEL ATACANTE (PUÑO CERRADO OBLIGATORIO GRIP+TRIGGER)
# ==============================================================================

func _check_controller_punches() -> void:
	if not attacker or not is_instance_valid(attacker):
		return
	if current_attack_step >= max_allowed_hits or attack_step_cooldown > 0.0:
		return

	var origin: XROrigin3D = attacker.get_parent() as XROrigin3D if attacker.get("is_player") else null
	if not origin:
		return

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")

	var best_zone: Dictionary = {}
	var best_ctrl: XRController3D = null
	var best_hand_name: String = ""
	var best_hand_idx: int = -1
	var best_dist: float = 0.25
	var best_vel: Vector3 = Vector3.ZERO
	var best_vmag: float = 0.0

	for hand_idx in [0, 1]:
		var ctrl: XRController3D = left_ctrl if hand_idx == 0 else right_ctrl
		if not ctrl:
			continue

		var hand_pos: Vector3 = ctrl.global_position
		var min_dist_to_any_zone: float = 999.0
		for zone in target_zones:
			var z_node: Node3D = zone.get("node") as Node3D
			if z_node and is_instance_valid(z_node):
				var d_any: float = hand_pos.distance_to(z_node.global_position)
				if d_any < min_dist_to_any_zone:
					min_dist_to_any_zone = d_any

		if hand_must_retract[hand_idx] and min_dist_to_any_zone > 0.26:
			hand_must_retract[hand_idx] = false

		# Exigir puño cerrado (Grip+Trigger) y no estar en retracción
		if hand_must_retract[hand_idx] or not is_fist_closed[hand_idx]:
			continue

		var cur_vel: Vector3 = left_velocity if hand_idx == 0 else right_velocity
		var v_mag: float = cur_vel.length()
		if v_mag < 0.80:
			continue

		for zone in target_zones:
			if zone.get("cooldown", 0.0) > 0.0:
				continue
			var z_node: Node3D = zone.get("node") as Node3D
			if not z_node or not is_instance_valid(z_node):
				continue
			var d: float = hand_pos.distance_to(z_node.global_position)
			if d <= 0.24 and d < best_dist:
				best_dist = d
				best_zone = zone
				best_ctrl = ctrl
				best_hand_name = "LeftHand" if hand_idx == 0 else "RightHand"
				best_hand_idx = hand_idx
				best_vel = cur_vel
				best_vmag = v_mag

	if best_hand_idx != -1 and not best_zone.is_empty():
		attack_step_cooldown = 0.28
		_register_hit(best_zone, best_ctrl, best_hand_name, best_hand_idx, best_vel, best_vmag)
		hand_must_retract[best_hand_idx] = true


func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String, hand_idx: int, cur_vel: Vector3, v_mag: float) -> void:
	zone["cooldown"] = 0.28
	var hit_pos: Vector3 = zone["node"].global_position

	var charge_t: float = fist_charge_times[hand_idx]
	var is_v3: bool = charge_t >= 1.10
	var is_charged: bool = charge_t >= 0.50
	var cfg_ki: KiEconomyConfig = KiEconomyConfig.get_default()
	var ki_cost: float = cfg_ki.melee_v3_cost if is_v3 else (cfg_ki.melee_charged_cost if is_charged else cfg_ki.melee_quick_cost)
	_modify_fighter_ki(attacker, -ki_cost)

	var swing_dir: Vector3 = cur_vel.normalized() if cur_vel.length_squared() > 0.01 else -global_transform.basis.z
	var v3_mode: String = "UP" if (swing_dir.y > 0.25 or int(zone["id"]) == 0) else "BACK"
	var punch_power: float = 3.0 if is_v3 else (2.0 if is_charged else 1.0)
	var fwd: Vector3 = -global_transform.basis.z

	if is_v3:
		was_last_hit_charged = true
		last_impact_vector = (fwd * 1.8 + Vector3.UP * 2.4).normalized() * 10.0 if v3_mode == "UP" else (fwd * 3.8 + Vector3.UP * 0.55).normalized() * 10.0
	elif is_charged:
		was_last_hit_charged = true
		last_impact_vector = (swing_dir + Vector3.UP * 0.25).normalized() * 7.5
	else:
		was_last_hit_charged = false
		last_impact_vector = (fwd + Vector3.UP * 0.15).normalized() * 4.0

	var clean_time_offset: float = float(hits.size() + 1) * NOTE_CADENCE_SEC
	hits.append({
		"zone_id": zone["id"],
		"name": "Cargado v3 (%s)" % ("Arriba" if v3_mode == "UP" else "Atrás") if is_v3 else String(zone["name"]),
		"pos": hit_pos,
		"hand": hand_name,
		"time_offset": clean_time_offset,
		"power": punch_power,
		"is_charged": is_charged,
		"is_charged_v3": is_v3,
		"is_hammer": false,
		"v3_launch_mode": v3_mode,
		"velocity": v_mag,
		"swing_dir": swing_dir,
		"defense_score": 0.0,
		"resolved": false
	})

	_spawn_hit_spark(hit_pos)

	var box_inst: MeshInstance3D = zone["box_mesh"] as MeshInstance3D
	var orig_col: Color = zone["color"] as Color
	if box_inst and is_instance_valid(box_inst):
		var mat := box_inst.material_override as StandardMaterial3D
		if mat:
			var flash_col: Color = Color(1.0, 0.2, 0.1) if is_v3 else (Color(1.0, 0.45, 0.1) if is_charged else Color(1.0, 1.0, 0.4))
			mat.albedo_color = flash_col
			mat.emission = flash_col
			mat.emission_energy_multiplier = 4.5 if is_charged else 3.0

		var tw := create_tween().set_parallel(true)
		tw.tween_property(zone["node"], "scale", Vector3.ONE * (1.45 if is_charged else 1.28), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(zone["node"], "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if mat:
			tw.parallel().tween_property(mat, "albedo_color", Color(orig_col.r, orig_col.g, orig_col.b, 0.58), 0.14)
			tw.parallel().tween_property(mat, "emission", Color(orig_col.r, orig_col.g, orig_col.b), 0.14)
			tw.parallel().tween_property(mat, "emission_energy_multiplier", 1.25, 0.14)

	if audio_player:
		audio_player.global_position = hit_pos
		audio_player.stream = sfx_hit_heavy if (is_charged or is_v3) else sfx_hit_light
		audio_player.pitch_scale = randf_range(0.92, 1.08)
		audio_player.play()

	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		ctrl_node.trigger_haptic_pulse("haptic", 220.0 if is_charged else 180.0, 1.0 if is_charged else 0.80, 0.20 if is_charged else 0.08, 0.0)

	fist_charge_times[hand_idx] = 0.0
	fist_locked_haptic[hand_idx] = false
	fist_v3_locked_haptic[hand_idx] = false
	_update_hand_charge_sphere(hand_idx, ctrl_node, 0.0)

	emit_signal("target_hit", hits.size(), String(zone["name"]), hit_pos, is_charged, punch_power)

	current_attack_step += 1
	_update_sequential_target_highlights()

	var atk_ki_left: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0
	if is_v3 or atk_ki_left <= 0.0 or current_attack_step >= max_allowed_hits:
		var msg_tag: String = "🔥 ¡CARGADO V3 LANZADO!" if is_v3 else "💥 ¡SECUENCIA REGISTRADA!"
		_begin_phase_transition("start_defense", 0.50, msg_tag, Color(1.0, 0.75, 0.2))


func _check_hammer_finisher() -> bool:
	if not hammer_primed and hammer_charge_time < HAMMER_CHARGE_REQ:
		return false

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var down_l: float = -left_velocity.y
	var down_r: float = -right_velocity.y
	var avg_down: float = (down_l + down_r) * 0.5
	var peak_speed: float = maxf(left_velocity.length(), right_velocity.length())

	if avg_down > 0.55 or down_l > 0.65 or down_r > 0.65 or (avg_down > 0.40 and peak_speed > 0.95):
		_modify_fighter_ki(attacker, -20.0)
		var to_def: Vector3 = -global_transform.basis.z
		if defender and is_instance_valid(defender) and attacker and is_instance_valid(attacker):
			var diff: Vector3 = defender.global_position - attacker.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				to_def = diff.normalized()

		last_impact_vector = (to_def * 1.4 + Vector3.DOWN * 3.8).normalized() * 12.0
		was_last_hit_charged = true

		var clean_time_offset: float = float(hits.size() + 1) * NOTE_CADENCE_SEC
		hits.append({
			"zone_id": 1,
			"name": "Martillazo DBZ",
			"pos": target_zones[1]["node"].global_position,
			"hand": "BothHands",
			"time_offset": clean_time_offset,
			"power": 4.5,
			"is_charged": true,
			"is_charged_v3": false,
			"is_hammer": true,
			"v3_launch_mode": "DOWN",
			"velocity": maxf(peak_speed, 3.2),
			"swing_dir": Vector3.DOWN,
			"defense_score": 0.0,
			"resolved": false
		})

		hammer_charge_time = 0.0
		hammer_primed = false
		hammer_locked_haptic = false
		_begin_phase_transition("start_defense", 0.50, "🔨 ¡MARTILLAZO DBZ LANZADO!", Color(0.95, 0.35, 1.0))
		return true

	return false


# ==============================================================================
# AUXILIARES DE MANDOS, CARGA EN PUÑO Y EFECTOS VISUALES
# ==============================================================================

func _get_controller(hand_name: String) -> XRController3D:
	if attacker and is_instance_valid(attacker):
		var p: Node = attacker.get_parent()
		if p:
			var c: XRController3D = p.get_node_or_null(hand_name) as XRController3D
			if c:
				return c
	var scene: Node = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	if scene:
		var xr: Node = scene.find_child("Player_XROrigin3D", true, false)
		if not xr:
			xr = scene.find_child("XROrigin3D", true, false)
		if xr:
			return xr.get_node_or_null(hand_name) as XRController3D
	return null


func _update_controller_velocities(delta: float) -> void:
	if delta <= 0.0001:
		return

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")

	if left_ctrl:
		var cur_pos: Vector3 = left_ctrl.global_position
		if prev_left_pos != Vector3.ZERO:
			left_velocity = (cur_pos - prev_left_pos) / delta
		prev_left_pos = cur_pos

	if right_ctrl:
		var cur_pos: Vector3 = right_ctrl.global_position
		if prev_right_pos != Vector3.ZERO:
			right_velocity = (cur_pos - prev_right_pos) / delta
		prev_right_pos = cur_pos


func _update_fist_states(delta: float, is_charging_hammer: bool) -> void:
	for i in [0, 1]:
		var hand_name: String = "LeftHand" if i == 0 else "RightHand"
		var c: XRController3D = _get_controller(hand_name)
		if not c:
			is_fist_closed[i] = false
			continue

		var cam: Camera3D = attacker.get_parent().get_node_or_null("XRCamera3D") as Camera3D if (attacker and attacker.get_parent()) else null
		var cam_pos: Vector3 = cam.global_position if cam else global_position
		var dist_to_body: float = c.global_position.distance_to(cam_pos)

		if hand_must_retract[i] and dist_to_body < 0.50:
			hand_must_retract[i] = false

		var trig_val: float = c.get_float("trigger")
		var grip_val: float = c.get_float("grip")
		var strictly_closed: bool = (trig_val > 0.50 and grip_val > 0.50) or (c.is_button_pressed("trigger_click") and c.is_button_pressed("grip_click"))

		if strictly_closed:
			fist_buffer_timers[i] = 0.09
		elif fist_buffer_timers[i] > 0.0:
			fist_buffer_timers[i] = maxf(fist_buffer_timers[i] - delta, 0.0)

		var eff_closed: bool = strictly_closed or fist_buffer_timers[i] > 0.0
		is_fist_closed[i] = eff_closed

		if strictly_closed and not hand_must_retract[i] and not is_charging_hammer:
			var v_mag: float = (left_velocity if i == 0 else right_velocity).length()
			if v_mag < 0.85:
				fist_charge_times[i] += delta
				if fist_charge_times[i] >= 0.50 and not fist_locked_haptic[i]:
					fist_locked_haptic[i] = true
					if c.has_method("trigger_haptic_pulse"):
						c.trigger_haptic_pulse("haptic", 160.0, 0.85, 0.12, 0.0)
				if fist_charge_times[i] >= 1.10 and not fist_v3_locked_haptic[i]:
					fist_v3_locked_haptic[i] = true
					if c.has_method("trigger_haptic_pulse"):
						c.trigger_haptic_pulse("haptic", 220.0, 1.0, 0.22, 0.0)
			_update_hand_charge_sphere(i, c, fist_charge_times[i])
		elif not eff_closed:
			fist_charge_times[i] = 0.0
			fist_locked_haptic[i] = false
			fist_v3_locked_haptic[i] = false
			_update_hand_charge_sphere(i, c, 0.0)


func _update_hand_charge_sphere(hand_idx: int, ctrl: XRController3D, charge_t: float) -> void:
	var sphere_inst: MeshInstance3D = charge_spheres[hand_idx]
	if charge_t < 0.25 or not ctrl:
		if sphere_inst and is_instance_valid(sphere_inst):
			sphere_inst.visible = false
		return

	if not sphere_inst or not is_instance_valid(sphere_inst):
		sphere_inst = MeshInstance3D.new()
		sphere_inst.name = "FistChargeSphere_%d" % hand_idx
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 12
		sm.rings = 6
		sphere_inst.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		sphere_inst.material_override = mat
		var root_node: Node = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else self
		root_node.add_child(sphere_inst)
		charge_spheres[hand_idx] = sphere_inst

	sphere_inst.visible = true
	sphere_inst.global_position = ctrl.global_position
	var ratio: float = clampf((charge_t - 0.25) / 1.0, 0.15, 1.4)
	sphere_inst.scale = Vector3.ONE * (0.7 + ratio)
	var m := sphere_inst.material_override as StandardMaterial3D
	if m:
		if charge_t >= 1.10:
			m.albedo_color = Color(1.0, 0.2, 0.1, 0.85)
		elif charge_t >= 0.50:
			m.albedo_color = Color(1.0, 0.65, 0.15, 0.75)
		else:
			m.albedo_color = Color(0.25, 0.85, 1.0, 0.45)


func _hide_all_charge_spheres() -> void:
	for i in [0, 1]:
		if charge_spheres[i] and is_instance_valid(charge_spheres[i]):
			charge_spheres[i].queue_free()
			charge_spheres[i] = null


func _process_hammer_charge(delta: float) -> bool:
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var hands_dist: float = left_ctrl.global_position.distance_to(right_ctrl.global_position)
	var cam: Camera3D = attacker.get_parent().get_node_or_null("XRCamera3D") as Camera3D if (attacker and attacker.get_parent()) else null
	var cam_pos: Vector3 = cam.global_position if cam else global_position
	var avg_pos: Vector3 = (left_ctrl.global_position + right_ctrl.global_position) * 0.5
	var rel_y: float = avg_pos.y - cam_pos.y

	var l_closed: bool = (left_ctrl.get_float("trigger") > 0.50 and left_ctrl.get_float("grip") > 0.50) or (left_ctrl.is_button_pressed("trigger_click") and left_ctrl.is_button_pressed("grip_click"))
	var r_closed: bool = (right_ctrl.get_float("trigger") > 0.50 and right_ctrl.get_float("grip") > 0.50) or (right_ctrl.is_button_pressed("trigger_click") and right_ctrl.is_button_pressed("grip_click"))
	var is_hammer_pose: bool = (hands_dist <= 0.30) and (rel_y >= 0.05) and l_closed and r_closed

	if is_hammer_pose:
		hammer_interruption_timer = 0.0
		hammer_charge_time += delta
		if hammer_charge_time >= HAMMER_CHARGE_REQ:
			if not hammer_locked_haptic:
				hammer_locked_haptic = true
				hammer_primed = true
				hammer_primed_window = 1.4
				for c in [left_ctrl, right_ctrl]:
					if c and c.has_method("trigger_haptic_pulse"):
						c.trigger_haptic_pulse("haptic", 220.0, 1.0, 0.25, 0.0)
		return true
	else:
		if hammer_primed:
			hammer_primed_window -= delta
			if hammer_primed_window <= 0.0:
				hammer_primed = false
				hammer_charge_time = 0.0
				hammer_locked_haptic = false
		else:
			hammer_interruption_timer += delta
			if hammer_interruption_timer > 0.20:
				hammer_charge_time = 0.0
				hammer_locked_haptic = false
		return false


func _spawn_hit_spark(pos: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	spark.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5, 0.95)
	spark.material_override = mat

	var scene_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(spark)
	else:
		add_child(spark)
	spark.global_position = pos

	var tw := spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 0.35, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.10)
	tw.chain().tween_callback(spark.queue_free)


func _spawn_block_spark(pos: Vector3, col: Color) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.10
	sphere.height = 0.20
	spark.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	spark.material_override = mat

	var scene_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(spark)
	else:
		add_child(spark)
	spark.global_position = pos

	var tw := spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 0.40, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.chain().tween_callback(spark.queue_free)


func _spawn_parry_shockwave(pos: Vector3) -> void:
	var wave := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.25
	wave.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.3, 0.95)
	wave.material_override = mat

	var scene_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(wave)
	else:
		add_child(wave)
	wave.global_position = pos

	var tw := wave.create_tween().set_parallel(true)
	tw.tween_property(wave, "scale", Vector3.ONE * 2.2, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.20)
	tw.chain().tween_callback(wave.queue_free)


func _exit_tree() -> void:
	_hide_all_charge_spheres()
	if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		melee_hud_anchor.queue_free()
		melee_hud_anchor = null
