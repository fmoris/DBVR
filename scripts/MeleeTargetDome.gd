class_name MeleeTargetDome
extends Node3D

const MeleeLoreEventScript = preload("res://scripts/MeleeLoreEventController.gd")

## MeleeTargetDome (Godot 4.3+ VR)
## Cúpula holográfica anime para combate Melee secuencial con economía de Ki y dominio de ronda:
## - Ataques (100% con puño cerrado Grip+Trigger):
##   * Nv.1 Golpe Rápido (< 0.50s), Nv.2 Golpe Cargado (0.50s..1.09s)
##   * Nv.3 Ataque Cargado v3 (>= 1.10s): interrumpe y lanza atrás o arriba (sí se frena con 1 mano)
##   * Martillazo DBZ (2 manos arriba 0.85s -> abajo): rompe 1 mano y estrella contra el suelo
##   * Cancelación de Ataque: Joystick derecho hacia atrás (separa a 5.5m)
## - Defensas:
##   * Trigger en caja (Verde/Ámbar) = Bloqueo / Desvío 1 Mano (+1.00 pto Verde, +Ki; sin Grip)
##   * Puñetazo contra caja (G+T frontal) = Choque de Puños (0 daño y ++Ki ambos si BP parejo, -1 ataque al rival)
##   * Grip+Trigger al impacto (Dorado ≤120ms) = Bloqueo Perfecto (Parry + inversión inmediata)
##   * Ambos puños al pecho en 'X' = Guardia Cruzada (-85% daño, +0.25 ptos, consume Ki)
## - Iniciativa por Dominio: Si S_def > N/2 -> invierte roles; si S_def <= N/2 -> continúa ofensiva.
## - Ruptura por Ki == 0: Golpe Fuerte Imbloqueable que expulsa al luchador sin Ki.

enum DomePhase {
	PHASE_TRANSITION,
	ATTACK_RECORDING,
	DEFENSE_RHYTHM,
	SIMULTANEOUS_EXCHANGE,
	UNBLOCKABLE_KI_BREAK,
	COMPLETED,
	LORE_EVENT
}

signal target_hit(hit_count: int, zone_name: String, hit_pos: Vector3, is_charged: bool, power: float)
signal bullet_time_completed(recorded_hits: Array, launch_vector: Vector3)
signal finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3)
signal perfect_parry_triggered(new_attacker: Node3D, new_defender: Node3D)
signal defense_action_resolved(action_type: String, zone_id: int, was_successful: bool, reward_ki: float, reward_bp: float)
signal meteor_smash_completed(p_attacker: Node3D, p_victim: Node3D, crater_pos: Vector3)

var phase: DomePhase = DomePhase.ATTACK_RECORDING

var attacker: Node3D = null
var defender: Node3D = null
var locked_atk_to_def_dir: Vector3 = Vector3.FORWARD
var duration: float = 5.5
var time_left: float = 5.5
var is_active: bool = false
var hits: Array = []
var attacker_damage_mult: float = 1.0
var defender_is_defenseless: bool = false

# Transición legible entre turnos y estado de ronda
var transition_timer: float = 0.0
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
var current_attack_step: int = 0
var attack_step_cooldown: float = 0.0

# Velocidades de atacante y defensor (calculadas en espacio local XR para inmunidad al Arena Surge)
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO
var def_left_velocity: Vector3 = Vector3.ZERO
var def_right_velocity: Vector3 = Vector3.ZERO
var _prev_l_local: Vector3 = Vector3.ZERO
var _prev_r_local: Vector3 = Vector3.ZERO
var _has_prev_atk_local: bool = false
var _def_prev_l_local: Vector3 = Vector3.ZERO
var _def_prev_r_local: Vector3 = Vector3.ZERO
var _has_prev_def_local: bool = false
var _punch_origin_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _punch_origin_depth: Array[float] = [0.0, 0.0]
var _punch_origin_init: Array[bool] = [false, false]
var _last_hit_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _last_hit_depth: Array[float] = [0.0, 0.0]
var _pending_finisher_mode: String = ""
var _pending_finisher_vel: float = 0.0
var _skip_btn_prev: bool = false
var _rounds_completed_in_dome: int = 0
static var _sim_exchange_cooldown_melees: int = 0
var _sim_used_this_dome: bool = false
var _custom_separation_dist: float = -1.0
var _custom_separation_reason: String = ""
var _comeback_momentum_active: bool = false
var _explosive_wave_used_this_dome: bool = false
var _char_script_cache: GDScript = null
var _sim_nodes: Array[Dictionary] = []
var _sim_player_hits_taken: int = 0
var _sim_enemy_hits_taken: int = 0
var _sim_clash_count: int = 0
var _sim_spawn_timer: float = 0.0
var _sim_duration: float = 12.0
var _sim_hand_retract: Array[bool] = [false, false]
var _sim_last_hit_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sim_last_hit_depth: Array[float] = [0.0, 0.0]
var _sim_origin_depth: Array[float] = [0.0, 0.0]
var _sim_origin_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sim_origin_init: Array[bool] = [false, false]
var _sim_last_impact_zone: int = 1

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

# Cajas holográficas y HUD
var target_zones: Array = []
var dome_mesh: MeshInstance3D = null
var header_label: Label3D = null
var melee_hud_anchor: Node3D = null
var melee_boxes_anchor: Node3D = null
var action_card_anchor: Node3D = null
var _action_card_label: Label3D = null
var _action_card_border_mat: StandardMaterial3D = null
var _last_role_is_attack: int = -1
const SCENIC_ARENA_SPOTS: Array[Vector3] = [
	Vector3(0.0, 2.5, 0.0),
	Vector3(24.0, 8.5, -18.0),
	Vector3(-28.0, 12.0, -22.0),
	Vector3(38.0, 6.0, 22.0),
	Vector3(-34.0, 14.0, 24.0),
	Vector3(0.0, 18.0, -35.0),
	Vector3(44.0, 4.5, -6.0),
	Vector3(-42.0, 7.0, 4.0)
]

var _duel_axis: Vector3 = Vector3.FORWARD
var _active_impact_popup: Label3D = null
var _impact_popup_tween: Tween = null
var _surge_tween: Tween = null
var charge_spheres: Array[MeshInstance3D] = [null, null]

# Overhaul Melee: Eventos Lore, Ki HUD, Semáforo y Control Físico (zero-alloc)
var _lore_ctrl: Node3D = null
var _last_lore_event_type: int = 0
var _lore_return_mode: String = ""
var _scenic_spot_idx: int = 0
var hammer_ki_paid: bool = false
static var _sonic_burst_cooldown_melees: int = 0
static var _flurry_clash_cooldown_melees: int = 0
static var _meteor_smash_cooldown_melees: int = 0
static var _z_vanish_war_cooldown_melees: int = 0
static var _guard_break_cooldown_melees: int = 0
var _sonic_burst_used_this_dome: bool = false
var _sonic_burst_rolled_this_round: bool = false
var _declared_full_combo: bool = false
var _round_sonic_hits: int = 0
var _round_charged_hits: int = 0
var _round_clean_sonic_hits: int = 0
var _round_clean_charged_hits: int = 0
var _round_unblocked_hits_taken: int = 0
var _surge_active_timer: float = 0.0
var _timing_cue_note_idx: int = -1
var _def_stick_used_for_note_idx: int = -1
var _def_stick_prev: bool = false
var _def_stick_diag_str: String = ""
var _hitstop_end_msec: int = 0
var _ki_bar_root: Node3D = null
var _player_ki_fill: MeshInstance3D = null
var _player_ki_mat: StandardMaterial3D = null
var _enemy_ki_fill: MeshInstance3D = null
var _enemy_ki_mat: StandardMaterial3D = null
var _ki_bar_label: Label3D = null
var _ki_delta_label: Label3D = null
var _ki_delta_timer: float = 0.0
var _last_shown_p_ki: int = -1
var _last_shown_e_ki: int = -1

# Cache XR / HUD / Dirty-check (90 FPS zero-alloc)
var _cached_player: Node3D = null
var _cached_ai: Node3D = null
var _cached_xr_origin: XROrigin3D = null
var _cached_camera: Camera3D = null
var _cached_left_ctrl: XRController3D = null
var _cached_right_ctrl: XRController3D = null
var _cached_desktop_sim: Node = null
var _last_header_text: String = ""
var _last_header_col: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _last_def_hl_key: String = ""

# Parámetros de Defensa Rítmica (0.90s por nota para mayor agilidad)
const NOTE_CADENCE_SEC: float = 0.90
const RING_PREWARN_SEC: float = 0.85
const PARRY_CHORD_GRACE_SEC: float = 0.055
var defense_timer: float = 0.0
var defense_total_duration: float = 0.0
var consecutive_guard_hits: int = 0
var last_animated_note_idx: int = -1
var buffer_grip_timer_l: float = 0.0
var buffer_grip_timer_r: float = 0.0
var buffer_trig_timer_l: float = 0.0
var buffer_trig_timer_r: float = 0.0
var _trig_press_age_l: float = 0.0
var _trig_press_age_r: float = 0.0
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

const ZONE_DEFINITIONS = [
	{ "id": 0, "name": "Rostro / Cabeza", "offset": Vector3(0.0, 0.20, 0.0), "color": Color(1.0, 0.3, 0.2, 0.85) },
	{ "id": 1, "name": "Plexo Solar", "offset": Vector3(0.0, -0.01, 0.0), "color": Color(0.2, 0.85, 1.0, 0.85) },
	{ "id": 2, "name": "Hombro Izquierdo", "offset": Vector3(-0.19, 0.17, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 3, "name": "Hombro Derecho", "offset": Vector3(0.19, 0.17, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 4, "name": "Flanco Izquierdo", "offset": Vector3(-0.19, -0.15, 0.0), "color": Color(1.0, 0.55, 0.15, 0.85) },
	{ "id": 5, "name": "Flanco Derecho", "offset": Vector3(0.19, -0.15, 0.0), "color": Color(1.0, 0.55, 0.15, 0.85) }
]


static func reset_match_static_state() -> void:
	_sim_exchange_cooldown_melees = 0
	_sonic_burst_cooldown_melees = 0
	_flurry_clash_cooldown_melees = 0
	_meteor_smash_cooldown_melees = 0
	_z_vanish_war_cooldown_melees = 0
	_guard_break_cooldown_melees = 0
	_tutorial_controls_shown = false


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


func _refresh_cached_refs() -> void:
	_cached_player = null
	_cached_ai = null
	_cached_xr_origin = null
	_cached_camera = null
	_cached_left_ctrl = null
	_cached_right_ctrl = null
	_cached_desktop_sim = null
	for f_c in [attacker, defender]:
		if f_c and is_instance_valid(f_c):
			if bool(f_c.get("is_player")):
				_cached_player = f_c
			else:
				_cached_ai = f_c
	if _cached_player and is_instance_valid(_cached_player):
		var p_node_c: Node = _cached_player.get_parent()
		if p_node_c is XROrigin3D:
			_cached_xr_origin = p_node_c as XROrigin3D
		if p_node_c:
			_cached_camera = p_node_c.get_node_or_null("XRCamera3D") as Camera3D
			_cached_left_ctrl = p_node_c.get_node_or_null("LeftHand") as XRController3D
			_cached_right_ctrl = p_node_c.get_node_or_null("RightHand") as XRController3D
			_cached_desktop_sim = p_node_c.get_node_or_null("DesktopXRSimulator")
	if (_cached_camera == null or _cached_left_ctrl == null or _cached_desktop_sim == null) and is_inside_tree() and get_tree() and get_tree().current_scene:
		var sc: Node = get_tree().current_scene
		var xr: Node = sc.find_child("Player_XROrigin3D", true, false)
		if not xr:
			xr = sc.find_child("XROrigin3D", true, false)
		if xr:
			if not _cached_xr_origin and xr is XROrigin3D:
				_cached_xr_origin = xr as XROrigin3D
			if not _cached_camera:
				_cached_camera = xr.get_node_or_null("XRCamera3D") as Camera3D
			if not _cached_left_ctrl:
				_cached_left_ctrl = xr.get_node_or_null("LeftHand") as XRController3D
			if not _cached_right_ctrl:
				_cached_right_ctrl = xr.get_node_or_null("RightHand") as XRController3D
			if not _cached_desktop_sim:
				_cached_desktop_sim = xr.get_node_or_null("DesktopXRSimulator")
	if not _cached_camera and is_inside_tree() and get_viewport():
		_cached_camera = get_viewport().get_camera_3d()


func _ctrl_pressed(ctrl: XRController3D, action: StringName) -> bool:
	if not ctrl:
		return false
	if _cached_desktop_sim and is_instance_valid(_cached_desktop_sim) and _cached_desktop_sim.get("sim_active"):
		return bool(_cached_desktop_sim.call("get_button_pressed", ctrl == _cached_left_ctrl, action))
	return ctrl.is_button_pressed(action)


func _ctrl_float(ctrl: XRController3D, action: StringName) -> float:
	if not ctrl:
		return 0.0
	if _cached_desktop_sim and is_instance_valid(_cached_desktop_sim) and _cached_desktop_sim.get("sim_active"):
		return float(_cached_desktop_sim.call("get_float", ctrl == _cached_left_ctrl, action))
	return ctrl.get_float(action)


func _ctrl_vec2(ctrl: XRController3D, action: StringName) -> Vector2:
	if not ctrl:
		return Vector2.ZERO
	if _cached_desktop_sim and is_instance_valid(_cached_desktop_sim) and _cached_desktop_sim.get("sim_active"):
		return _cached_desktop_sim.call("get_vector2", ctrl == _cached_left_ctrl, action) as Vector2
	return ctrl.get_vector2(action)


func _set_header(txt: String, col: Color) -> void:
	if not header_label or not is_instance_valid(header_label):
		return
	if txt != _last_header_text:
		_last_header_text = txt
		header_label.text = txt
	if col != _last_header_col:
		_last_header_col = col
		header_label.modulate = col


func _get_vanish_cost_and_label(fighter: Node3D) -> Dictionary:
	var cfg_zv: KiEconomyConfig = KiEconomyConfig.get_default()
	var base_cost: float = float(cfg_zv.melee_vanish_cost) if cfg_zv.get("melee_vanish_cost") != null else 10.0
	if fighter and is_instance_valid(fighter):
		var cdata: Resource = fighter.get("character_data") as Resource
		var c_name: String = String(cdata.character_name).to_lower() if (cdata and "character_name" in cdata) else ""
		if "goku" in c_name:
			return { "cost": maxf(base_cost - 2.0, 4.0), "label": "💨 ¡SHUNKAN IDŌ!" }
		if "vegeta" in c_name:
			return { "cost": base_cost, "label": "💨 ¡ZANZOKEN!" }
	return { "cost": base_cost, "label": "💨 ¡Z-VANISH!" }


func setup(p_attacker: Node3D, p_defender: Node3D, p_duration: float = -1.0, p_max_hits: int = -1) -> void:
	attacker = p_attacker
	defender = p_defender
	is_active = true
	clash_penalty_hits = 0
	pending_attack_penalty = 0
	last_action_feedback = ""
	_last_header_text = ""
	_last_header_col = Color(-1.0, -1.0, -1.0, -1.0)
	_last_def_hl_key = ""
	_rounds_completed_in_dome = 0
	_sim_used_this_dome = false
	_custom_separation_dist = -1.0
	_custom_separation_reason = ""
	_comeback_momentum_active = false
	_explosive_wave_used_this_dome = false
	_sim_exchange_cooldown_melees = maxi(_sim_exchange_cooldown_melees - 1, 0)
	_sonic_burst_used_this_dome = false
	_sonic_burst_cooldown_melees = maxi(_sonic_burst_cooldown_melees - 1, 0)
	_flurry_clash_cooldown_melees = maxi(_flurry_clash_cooldown_melees - 1, 0)
	_meteor_smash_cooldown_melees = maxi(_meteor_smash_cooldown_melees - 1, 0)
	_z_vanish_war_cooldown_melees = maxi(_z_vanish_war_cooldown_melees - 1, 0)
	_guard_break_cooldown_melees = maxi(_guard_break_cooldown_melees - 1, 0)
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_blocking", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_blocking", false)

	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BulletTimeAudio"
	audio_player.unit_size = 5.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

	_refresh_cached_refs()
	_update_dome_transform()
	# Punto 1: Fijar eje inicial del duelo (jugador -> IA) para que la IA no orbite al girar la cabeza
	var pair_init: Array[Node3D] = _get_player_and_ai()
	if pair_init[0] and pair_init[1]:
		var cam_init: Camera3D = _get_player_camera()
		var p_ref: Vector3 = cam_init.global_position if (cam_init and is_instance_valid(cam_init)) else pair_init[0].global_position
		var axis: Vector3 = pair_init[1].global_position - p_ref
		axis.y = 0.0
		_duel_axis = axis.normalized() if axis.length_squared() > 0.001 else Vector3.FORWARD
	_build_visual_dome()
	_build_target_boxes()
	_build_header_hud()
	_ensure_action_card()

	if _lore_ctrl == null:
		_lore_ctrl = MeleeLoreEventScript.new() as Node3D
		_lore_ctrl.name = "MeleeLoreEventController"
		add_child(_lore_ctrl)
		if not _lore_ctrl.is_connected("lore_event_finished", _on_lore_event_finished):
			_lore_ctrl.connect("lore_event_finished", _on_lore_event_finished)

	start_attack_phase(p_attacker, p_defender, p_duration, p_max_hits)


static func compute_melee_kinetic_power(stroke_dist: float, speed_mps: float, is_charged: bool, is_v3: bool) -> float:
	var stroke_factor: float = clampf(stroke_dist / 0.38, 0.70, 1.45)
	var speed_factor: float = clampf(speed_mps / 2.20, 0.75, 1.65)
	var charge_base: float = 2.40 if is_v3 else (1.65 if is_charged else 1.00)
	return clampf(charge_base * (0.45 * stroke_factor + 0.55 * speed_factor), 0.75, 4.50)


## Clasifica un golpe físico VR en 3 niveles según velocidad real, recorrido del brazo y carga
static func classify_melee_punch_tier(stroke_dist: float, speed_mps: float, is_charged: bool) -> Dictionary:
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var sonic_ref: float = float(cfg.melee_sonic_ki_refund) if cfg.get("melee_sonic_ki_refund") != null else 10.0
	var clean_ref: float = float(cfg.melee_clean_hit_ki_refund) if cfg.get("melee_clean_hit_ki_refund") != null else 8.0
	var charged_ref: float = float(cfg.melee_charged_clean_ki_refund) if cfg.get("melee_charged_clean_ki_refund") != null else 2.0
	if (speed_mps >= 2.85 and stroke_dist >= 0.30) or (is_charged and speed_mps >= 2.40 and stroke_dist >= 0.28):
		return {
			"tier": "SONICO",
			"label": "⚡ ¡SÓNICO!",
			"dmg_mult": 1.35,
			"ki_refund": charged_ref if is_charged else sonic_ref,
			"color": Color(1.0, 0.92, 0.25)
		}
	if (speed_mps >= 1.95 and stroke_dist >= 0.24) or (is_charged and speed_mps >= 1.60):
		return {
			"tier": "SOLIDO",
			"label": "💥 ¡SÓLIDO!",
			"dmg_mult": 1.00,
			"ki_refund": charged_ref if is_charged else clean_ref,
			"color": Color(1.0, 0.50, 0.15)
		}
	return {
		"tier": "SUAVE",
		"label": "~ Suave",
		"dmg_mult": 0.60,
		"ki_refund": charged_ref if is_charged else 4.0,
		"color": Color(0.65, 0.72, 0.80)
	}


static func can_z_vanish_attack(is_charged: bool, is_v3: bool, is_hammer: bool) -> bool:
	return is_hammer or is_v3 or is_charged


static func get_defense_green_start_sec(is_charged: bool, is_v3: bool, is_hammer: bool) -> float:
	if is_hammer or is_v3 or is_charged:
		return 0.28
	return 0.18


static func evaluate_defensive_z_vanish_input(
	t_diff: float,
	note_prewarn: float,
	stick_mag: float,
	stick_clicked: bool,
	is_charged: bool,
	is_v3: bool,
	is_hammer: bool,
	cur_ki: float,
	vanish_cost: float
) -> String:
	var triggered: bool = stick_clicked or stick_mag >= 0.50
	if not triggered or t_diff > note_prewarn or t_diff < -0.22:
		return "NONE"
	if not can_z_vanish_attack(is_charged, is_v3, is_hammer):
		return "BLOCKED_QUICK"
	var green_start: float = get_defense_green_start_sec(is_charged, is_v3, is_hammer)
	if t_diff > green_start:
		return "EARLY_FAIL"
	if t_diff >= -0.18:
		return "EXECUTE" if cur_ki >= vanish_cost else "NO_KI"
	return "NONE"


static func get_attack_visual_meta(note: Dictionary) -> Dictionary:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var tier: String = String(note.get("tier", note.get("punch_tier", "SOLIDO"))).to_upper()
	if is_hammer:
		return {
			"type": "HAMMER",
			"icon": "🔨",
			"tag": "🔨 MARTILLO",
			"hud_hint": "🔨 ¡SOLO Z-VANISH (Stick)! ❌ 1M / Guardia X / Parry / Choque rotos",
			"color": Color(0.95, 0.20, 1.0, 0.95),
			"label_color": Color(1.0, 0.92, 0.30, 1.0),
			"scale": 1.28
		}
	if is_v3:
		return {
			"type": "CHARGED_V3",
			"icon": "🔥",
			"tag": "🔥 V3",
			"hud_hint": "🔥 Parry(Dorado+G+T) | Choque | Z-Vanish | 🐢X(-10Ki/50% chip) | ❌ 1M rota",
			"color": Color(1.0, 0.24, 0.10, 0.95),
			"label_color": Color(1.0, 0.62, 0.25, 1.0),
			"scale": 1.24
		}
	if is_charged:
		return {
			"type": "CHARGED_V2",
			"icon": "⚡",
			"tag": "⚡ CARGADO",
			"hud_hint": "⚡ Guardia X(+Ki) | Parry(G+T) | Choque | Z-Vanish | ❌ 1M rota",
			"color": Color(1.0, 0.55, 0.12, 0.95),
			"label_color": Color(1.0, 0.88, 0.35, 1.0),
			"scale": 1.18
		}
	if tier == "SUAVE":
		return {
			"type": "QUICK_SOFT",
			"icon": "~👊",
			"tag": "~👊 JAB SUAVE",
			"hud_hint": "~👊 Trigger 1 Mano | Guardia X(+Ki) | Absorbe y toma turno",
			"color": Color(0.45, 0.80, 0.95, 0.95),
			"label_color": Color(0.75, 0.92, 1.0, 1.0),
			"scale": 1.08
		}
	return {
		"type": "QUICK",
		"icon": "👊",
		"tag": "👊 RÁPIDO",
		"hud_hint": "👊 Trigger 1 Mano | Guardia X(+Ki) | ❌ Sin Parry/Choque/Vanish",
		"color": Color(0.20, 0.92, 1.0, 0.95),
		"label_color": Color(0.30, 0.95, 1.0, 1.0),
		"scale": 1.14
	}


static func should_jab_lack_intent_turnover(clean_hits: int, clean_soft_hits: int, clean_charged_hits: int, clean_sonic_hits: int) -> bool:
	if clean_hits <= 0:
		return false
	return (clean_soft_hits == clean_hits) or (clean_charged_hits == 0 and clean_sonic_hits == 0)


static func evaluate_real_punch_motion(vel: Vector3, punch_fwd: Vector3, stroke_dist: float, fwd_stroke: float, is_charged: bool) -> Dictionary:
	var fwd_n: Vector3 = punch_fwd.normalized() if punch_fwd.length_squared() > 0.0001 else Vector3.FORWARD
	var v_mag: float = vel.length()
	var fwd_vel: float = vel.dot(fwd_n)
	var min_vel: float = 1.35 if is_charged else 1.50
	var min_fwd_vel: float = 0.95 if is_charged else 1.15
	var min_stroke: float = 0.20
	var min_fwd_stroke: float = 0.12
	var valid: bool = (v_mag >= min_vel) and (fwd_vel >= min_fwd_vel) and (fwd_vel >= v_mag * 0.55) and (stroke_dist >= min_stroke) and (fwd_stroke >= min_fwd_stroke)
	return {
		"valid": valid,
		"v_mag": v_mag,
		"fwd_vel": fwd_vel,
		"punch_speed": v_mag
	}


static func should_release_punch_retraction(last_hit_depth: float, cur_depth: float, cur_fwd_vel: float) -> bool:
	return (last_hit_depth - cur_depth) >= 0.13 or (cur_depth <= 0.24 and cur_fwd_vel <= 0.25)


static func should_trigger_individual_flurry_clash(roll: float, chance: float, cooldown_melees: int) -> bool:
	if cooldown_melees > 0:
		return false
	return roll < clampf(chance, 0.0, 1.0)


static func should_trigger_surprise_lore_event(roll: float, chance: float, cooldown_melees: int) -> bool:
	if cooldown_melees > 0:
		return false
	return roll < clampf(chance, 0.0, 1.0)


func _get_bp_profile(p_atk: Node3D, p_def: Node3D, is_heavy: bool = false) -> Dictionary:
	var atk_bp: float = maxf(float(p_atk.get("current_np")) if (p_atk and is_instance_valid(p_atk) and p_atk.get("current_np") != null) else 10000.0, 100.0)
	var def_bp: float = maxf(float(p_def.get("current_np")) if (p_def and is_instance_valid(p_def) and p_def.get("current_np") != null) else 10000.0, 100.0)
	var atk_furia: bool = p_atk != null and is_instance_valid(p_atk) and bool(p_atk.get("is_in_furia"))
	var atk_t: float = float(p_atk.call("get_transformation_multiplier")) if (p_atk and is_instance_valid(p_atk) and p_atk.has_method("get_transformation_multiplier")) else 1.0
	var def_t: float = float(p_def.call("get_transformation_multiplier")) if (p_def and is_instance_valid(p_def) and p_def.has_method("get_transformation_multiplier")) else 1.0
	var cm: bool = _comeback_momentum_active and (p_atk == attacker)
	if _char_script_cache == null:
		_char_script_cache = ResourceLoader.load("res://scripts/character_instance.gd") as GDScript
	if _char_script_cache:
		return _char_script_cache.call("compute_melee_bp_profile", atk_bp, def_bp, atk_furia, is_heavy, atk_t, def_t, cm) as Dictionary
	return {
		"raw_ratio": 1.0, "effective_ratio": 1.0, "match_trans_scale": 1.0,
		"dmg_mult": 1.0, "damage_scale": 1.0, "def_time_mult": 1.0, "ki_mult": 1.0,
		"bp_gain_mult": 1.0, "defender_underdog_bp_mult": 1.0, "attacker_underdog_bp_mult": 1.0,
		"is_dominance": false
	}


func _resync_unresolved_defense_notes(min_lead_sec: float = 0.70) -> void:
	var min_off: float = 999999.0
	var found: bool = false
	for h_chk in hits:
		if not h_chk.get("resolved", false):
			var toff: float = float(h_chk.get("time_offset", 0.0))
			if toff < min_off:
				min_off = toff
				found = true
	if not found:
		return
	var lead: float = min_off - defense_timer
	if lead < min_lead_sec:
		var shift: float = min_lead_sec - lead
		for h_shift in hits:
			if not h_shift.get("resolved", false):
				h_shift["time_offset"] = float(h_shift.get("time_offset", 0.0)) + shift
		defense_total_duration += shift


static func should_trigger_sim_flurry_clash(clash_count: int, thresh: int, roll: float, base_chance: float, cooldown_melees: int) -> bool:
	if cooldown_melees > 0 or clash_count < thresh:
		return false
	var effective_chance: float = clampf(base_chance + float(clash_count - thresh) * 0.25, 0.0, 0.85)
	return roll < effective_chance


static func is_hand_winding_clash_in_red(grip_held: bool, trig_held: bool, dist_to_zone: float, fwd_vel: float, is_hammer: bool, is_heavy_attack: bool = true) -> bool:
	return (not is_hammer) and is_heavy_attack and grip_held and (dist_to_zone > 0.34 or (trig_held and fwd_vel <= -0.35))


static func evaluate_one_hand_defense_input(
	t_diff: float,
	trig_held: bool,
	grip_held: bool,
	trig_buffer_active: bool,
	grip_buffer_active: bool,
	just_guard_active: bool,
	trig_press_age: float,
	fwd_clash_spd: float,
	vel_mag: float,
	is_hammer: bool,
	is_heavy_attack: bool = true
) -> String:
	if is_hammer:
		if t_diff <= 0.30 and t_diff >= -0.22 and (trig_held or grip_held or just_guard_active or trig_buffer_active):
			return "HAMMER_UNBLOCKABLE"
		if t_diff > 0.30 and (trig_buffer_active or grip_buffer_active):
			return "HAMMER_UNBLOCKABLE"
		return "NONE"
	if t_diff > 0.30:
		if trig_buffer_active or grip_buffer_active:
			return "EARLY_LOCKOUT"
		return "NONE"
	if t_diff <= 0.30 and t_diff >= -0.22:
		if is_heavy_attack and absf(t_diff) <= 0.22 and grip_held and trig_held and vel_mag >= 1.55 and fwd_clash_spd >= 1.05:
			return "CLASH"
		if is_heavy_attack and absf(t_diff) <= 0.12 and just_guard_active and fwd_clash_spd < 1.05:
			return "PARRY"
		if not is_heavy_attack:
			if absf(t_diff) <= 0.12 and just_guard_active:
				return "NO_PARRY_QUICK"
			if grip_held and trig_held and vel_mag >= 1.55 and fwd_clash_spd >= 1.05:
				return "NO_PARRY_QUICK"
			if t_diff <= 0.30 and t_diff >= -0.16 and trig_held and trig_buffer_active and not grip_held:
				return "BLOCK_GREEN" if t_diff <= 0.18 else "BLOCK_YELLOW"
			return "NONE"
		if t_diff <= 0.30 and t_diff >= -0.16 and trig_held and trig_buffer_active:
			if not grip_held:
				if absf(t_diff) <= 0.12 and trig_press_age < PARRY_CHORD_GRACE_SEC and t_diff > -0.10:
					return "WAIT_CHORD"
				return "BLOCK_GREEN" if t_diff <= 0.18 else "BLOCK_YELLOW"
			elif t_diff > 0.12:
				return "BLOCK_YELLOW"
	return "NONE"


func _get_punch_forward_world() -> Vector3:
	var fwd: Vector3 = _duel_axis
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		return fwd.normalized()
	var cam: Camera3D = _get_player_camera()
	if cam and is_instance_valid(cam):
		var cam_f: Vector3 = -cam.global_transform.basis.z
		cam_f.y = 0.0
		if cam_f.length_squared() > 0.0001:
			return cam_f.normalized()
	return Vector3.FORWARD


func _get_hand_depth_local(ctrl: XRController3D) -> float:
	if not ctrl:
		return 0.0
	var origin: XROrigin3D = _cached_xr_origin if (_cached_xr_origin and is_instance_valid(_cached_xr_origin)) else null
	if not origin:
		var p_node: Node3D = attacker if (attacker and is_instance_valid(attacker) and bool(attacker.get("is_player"))) else (defender if (defender and is_instance_valid(defender) and bool(defender.get("is_player"))) else null)
		if p_node and p_node.get_parent() is XROrigin3D:
			origin = p_node.get_parent() as XROrigin3D
	var orig_basis: Basis = origin.global_transform.basis.orthonormalized() if (origin and is_instance_valid(origin)) else Basis.IDENTITY
	var cam: Camera3D = _get_player_camera()
	var cam_loc: Vector3 = cam.position if (cam and is_instance_valid(cam) and (origin == null or cam.get_parent() == origin)) else Vector3.ZERO
	var fwd_w: Vector3 = _get_punch_forward_world()
	var fwd_loc: Vector3 = (orig_basis.inverse() * fwd_w).normalized()
	if fwd_loc.length_squared() < 0.0001:
		fwd_loc = Vector3.FORWARD
	return (ctrl.position - cam_loc).dot(fwd_loc)


func start_attack_phase(p_attacker: Node3D, p_defender: Node3D, p_duration: float = -1.0, p_max_hits: int = -1) -> void:
	attacker = p_attacker
	defender = p_defender
	hits.clear()
	current_attack_step = 0
	attack_step_cooldown = 0.16
	clash_penalty_hits = 0
	defense_score_sum = 0.0
	defense_round_total_hits = 0
	fist_charge_times = [0.0, 0.0]
	fist_locked_haptic = [false, false]
	fist_v3_locked_haptic = [false, false]
	hand_must_retract = [false, false]
	_has_prev_atk_local = false
	_punch_origin_local = [Vector3.ZERO, Vector3.ZERO]
	_punch_origin_depth = [0.0, 0.0]
	_punch_origin_init = [false, false]
	_last_hit_local = [Vector3.ZERO, Vector3.ZERO]
	_last_hit_depth = [0.0, 0.0]
	_pending_finisher_mode = ""
	_pending_finisher_vel = 0.0
	_skip_btn_prev = false
	hammer_charge_time = 0.0
	hammer_primed = false
	hammer_locked_haptic = false
	hammer_ki_paid = false
	_declared_full_combo = false
	_round_sonic_hits = 0
	_round_charged_hits = 0
	_round_clean_sonic_hits = 0
	_round_clean_charged_hits = 0
	_sonic_burst_rolled_this_round = false
	_round_unblocked_hits_taken = 0
	_timing_cue_note_idx = -1
	_def_stick_used_for_note_idx = -1
	_def_stick_prev = false
	_def_stick_diag_str = ""
	_last_def_hl_key = ""
	_set_target_zones_visible(true)
	_hide_all_charge_spheres()
	_refresh_melee_ki_bar()
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_blocking", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_blocking", false)

	var base_hits: int = 3
	if p_max_hits > 0:
		base_hits = p_max_hits
	elif attacker and is_instance_valid(attacker) and attacker.has_method("calculate_melee_attack_count"):
		base_hits = attacker.calculate_melee_attack_count(attacker, defender, _comeback_momentum_active)

	max_allowed_hits = clampi(base_hits - pending_attack_penalty, 1, 9)
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
		_apply_role_dome_tint(false)
		generate_ai_attack_sequence()
		_begin_phase_transition("start_defense", 0.55, "🛡️ ¡TURNO DE DEFENSA! (%d GOLPES)" % hits.size(), Color(0.25, 0.88, 1.0))
	else:
		_apply_role_dome_tint(true)
		_update_sequential_target_highlights()
		_refresh_header_hud()

	print("[BulletTimeDome] Ataque listo: %d golpes permitidos en %.2fs." % [max_allowed_hits, duration])


func _set_single_zone_shape(zone: Dictionary, role: String) -> void:
	var z_node: Node3D = zone.get("node") as Node3D
	var box_m: MeshInstance3D = zone.get("box_mesh") as MeshInstance3D
	var inner_m: MeshInstance3D = zone.get("inner_mesh") as MeshInstance3D
	var circ_m: MeshInstance3D = zone.get("circle_mesh") as MeshInstance3D
	var ring_m: MeshInstance3D = zone.get("circle_ring") as MeshInstance3D
	var active_vis: bool = (role != "NONE")
	if z_node and is_instance_valid(z_node):
		z_node.visible = active_vis
	var show_box: bool = (role == "DEFEND" or role == "CLASH")
	var show_circ: bool = (role == "ATTACK" or role == "CLASH")
	if box_m and is_instance_valid(box_m):
		box_m.visible = show_box
	if inner_m and is_instance_valid(inner_m):
		inner_m.visible = show_box
	if circ_m and is_instance_valid(circ_m):
		circ_m.visible = show_circ
	if ring_m and is_instance_valid(ring_m):
		ring_m.visible = show_circ


func _apply_zone_role_shapes(is_attack_mode: bool) -> void:
	for zone in target_zones:
		var box_m: MeshInstance3D = zone.get("box_mesh") as MeshInstance3D
		var inner_m: MeshInstance3D = zone.get("inner_mesh") as MeshInstance3D
		var circ_m: MeshInstance3D = zone.get("circle_mesh") as MeshInstance3D
		var ring_m: MeshInstance3D = zone.get("circle_ring") as MeshInstance3D
		if box_m and is_instance_valid(box_m):
			box_m.visible = not is_attack_mode
		if inner_m and is_instance_valid(inner_m):
			inner_m.visible = not is_attack_mode
		if circ_m and is_instance_valid(circ_m):
			circ_m.visible = is_attack_mode
		if ring_m and is_instance_valid(ring_m):
			ring_m.visible = is_attack_mode


func _ensure_action_card() -> void:
	var cam: Camera3D = _get_player_camera()
	if not cam or not is_instance_valid(cam):
		return
	if action_card_anchor and is_instance_valid(action_card_anchor):
		return

	action_card_anchor = Node3D.new()
	action_card_anchor.name = "MeleeActionGuideCardAnchor"
	action_card_anchor.position = Vector3(-0.62, -0.34, -1.15)
	action_card_anchor.rotation_degrees = Vector3(6.0, 18.0, 0.0)
	cam.add_child(action_card_anchor)

	var border := MeshInstance3D.new()
	border.name = "CardBorder"
	var b_q := QuadMesh.new()
	b_q.size = Vector2(0.50, 0.22)
	border.mesh = b_q
	_action_card_border_mat = StandardMaterial3D.new()
	_action_card_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_action_card_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_action_card_border_mat.no_depth_test = true
	_action_card_border_mat.render_priority = 110
	_action_card_border_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.90)
	border.material_override = _action_card_border_mat
	action_card_anchor.add_child(border)

	var bg := MeshInstance3D.new()
	bg.name = "CardBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.485, 0.205)
	bg.mesh = bg_q
	bg.position = Vector3(0.0, 0.0, 0.001)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 111
	bg_mat.albedo_color = Color(0.03, 0.06, 0.11, 0.92)
	bg.material_override = bg_mat
	action_card_anchor.add_child(bg)

	_action_card_label = Label3D.new()
	_action_card_label.name = "MeleeCardText"
	_action_card_label.font_size = 19
	_action_card_label.pixel_size = 0.00118
	_action_card_label.no_depth_test = true
	_action_card_label.render_priority = 112
	_action_card_label.outline_size = 6
	_action_card_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_action_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_action_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_card_label.position = Vector3(-0.225, 0.0, 0.002)
	action_card_anchor.add_child(_action_card_label)


func _update_action_card(is_attack_mode: bool) -> void:
	_ensure_action_card()
	if not _action_card_label or not is_instance_valid(_action_card_label):
		return
	var cfg_c: KiEconomyConfig = KiEconomyConfig.get_default()
	var q_c: int = int(cfg_c.melee_quick_cost)
	var chg_c: int = int(cfg_c.melee_charged_cost)
	var v3_c: int = int(cfg_c.melee_v3_cost)
	var hm_c: int = int(cfg_c.melee_hammer_cost)
	var clean_r: int = int(cfg_c.melee_clean_hit_ki_refund)
	var sonic_r: int = int(cfg_c.melee_sonic_ki_refund)
	var defl_r: int = int(cfg_c.melee_deflect_ki_reward)
	var parry_r: int = int(cfg_c.melee_parry_ki_reward)
	var gx_c: int = int(cfg_c.melee_guard_charged_cost)
	var zv_c: int = int(_get_vanish_cost_and_label(defender).get("cost", cfg_c.melee_vanish_cost))
	var ew_c: int = int(cfg_c.melee_explosive_wave_cost)
	var cl_even_r: int = int(cfg_c.melee_clash_even_ki_reward) if cfg_c.get("melee_clash_even_ki_reward") != null else 6
	var cl_r: int = int(cfg_c.melee_clash_win_reward)
	if is_attack_mode:
		if _action_card_border_mat:
			_action_card_border_mat.albedo_color = Color(1.0, 0.52, 0.15, 0.90)
		_action_card_label.modulate = Color(1.0, 0.93, 0.72)
		_action_card_label.text = "⚔️ ATACAR (⭕ CÍRCULOS) | Táctica por Golpe\n• 👊 Rápido (-%d Ki): Sin Parry/Choque/Vanish (+%d~%d Ki limpio; Suave no lanza)\n• ⚡ Cargado 0.5s (-%d Ki): Alto BP (+2 Ki), rompe 1 Mano\n• 🔥 V3 1.1s (-%d Ki): Rompe 1M y ¡LANZA ya! (X frena c/ -10Ki)\n• 🔨 Martillo (-%d Ki): ¡INBLOQUEABLE! Solo Stick Z-Vanish | [A/X]: Ya" % [q_c, clean_r, sonic_r, chg_c, v3_c, hm_c]
	else:
		if _action_card_border_mat:
			_action_card_border_mat.albedo_color = Color(0.20, 0.88, 1.0, 0.90)
		_action_card_label.modulate = Color(0.88, 0.97, 1.0)
		_action_card_label.text = "🛡️ DEFENDER (⬜) | Lee el Icono del Objetivo\n• 👊 Rápido: Trigger 1M (+%d Ki) o Guardia X Tortuga (+Ki) | ❌ Sin Parry/Choque/Vanish\n• ⚡/🔥 Cargado: Guardia X (+10Ki en Nv2, -%dKi/50pct en V3) | Parry(Dorado+G+T: +%d Ki) | Choque(G+T: +%d~%d)\n• 🔨 Martillo: SOLO Stick %s (-%d Ki) | 2 Grips abiertos: Kiai (-%d)" % [defl_r, gx_c, parry_r, cl_even_r, cl_r, ("Shunkan" if ("goku" in String((defender.get("character_data").character_name if (defender and defender.get("character_data") and "character_name" in defender.get("character_data")) else "")).to_lower()) else "Z-Vanish"), zv_c, ew_c]


func _apply_role_dome_tint(player_attacks: bool) -> void:
	var role_int: int = 1 if player_attacks else 0
	if role_int != _last_role_is_attack:
		_last_role_is_attack = role_int
		_apply_zone_role_shapes(player_attacks)
		_update_action_card(player_attacks)
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


func _spawn_impact_popup(_world_pos: Vector3, txt: String, col: Color, force_camera_child: bool = false) -> void:
	if _impact_popup_tween and is_instance_valid(_impact_popup_tween):
		_impact_popup_tween.kill()
		_impact_popup_tween = null

	var target_parent: Node3D = null
	var start_pos: Vector3 = Vector3.ZERO
	var end_y: float = 0.0
	var dur: float = 0.45
	var delay_a: float = 0.14

	if not force_camera_child and melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		target_parent = melee_hud_anchor
		start_pos = Vector3(0.0, -0.11, 0.0)
		end_y = -0.04
	else:
		var cam: Camera3D = _get_player_camera()
		if not cam or not is_instance_valid(cam):
			return
		target_parent = cam
		start_pos = Vector3(0.0, 0.10, -1.15)
		end_y = 0.18
		dur = 0.55
		delay_a = 0.16

	var lbl: Label3D = _active_impact_popup
	if not lbl or not is_instance_valid(lbl):
		lbl = Label3D.new()
		lbl.name = "MeleeImpactPopup"
		lbl.font_size = 28
		lbl.pixel_size = 0.0014
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		lbl.no_depth_test = true
		lbl.render_priority = 126
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_active_impact_popup = lbl

	if lbl.get_parent() != target_parent:
		if lbl.get_parent():
			lbl.get_parent().remove_child(lbl)
		target_parent.add_child(lbl)

	lbl.text = txt
	lbl.modulate = col
	lbl.position = start_pos
	lbl.visible = true

	if lbl.is_inside_tree():
		_impact_popup_tween = lbl.create_tween().set_parallel(true)
		_impact_popup_tween.tween_property(lbl, "position:y", end_y, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_impact_popup_tween.tween_property(lbl, "modulate:a", 0.0, dur).set_delay(delay_a)
		_impact_popup_tween.chain().tween_callback(func() -> void:
			if lbl and is_instance_valid(lbl):
				lbl.visible = false
		)


func _begin_phase_transition(mode: String, wait_sec: float, msg: String, col: Color) -> void:
	phase = DomePhase.PHASE_TRANSITION
	transition_on_complete_mode = mode
	var ai_defending: bool = (mode == "start_defense") and defender != null and is_instance_valid(defender) and not bool(defender.get("is_player"))
	var min_wait: float = 0.16 if ai_defending else 0.45
	var actual_wait: float = minf(wait_sec, 0.18) if ai_defending else wait_sec
	# Pausa mínima de 0.45s para jugador (legibilidad) y 0.16s-0.18s cuando defiende la IA (agilidad)
	transition_timer = maxf(actual_wait, min_wait) if mode in ["start_defense", "restart_attacker", "continue_offense"] else wait_sec
	_reset_all_timing_rings()
	_hide_all_charge_spheres()
	var player_will_attack: bool = false
	if mode == "start_defense":
		player_will_attack = attacker != null and bool(attacker.get("is_player"))
	elif mode == "restart_attacker":
		player_will_attack = defender != null and bool(defender.get("is_player"))
	elif mode == "continue_offense":
		player_will_attack = attacker != null and bool(attacker.get("is_player"))
	elif mode == "start_simultaneous":
		player_will_attack = true
	_apply_role_dome_tint(player_will_attack)
	if audio_player:
		audio_player.pitch_scale = 1.15 if player_will_attack else 0.85
		AudioActionManager.play_action("common.block_perfect", audio_player)
	if player_will_attack:
		_pulse_player_hand(0, 150.0, 0.75, 0.14)
		_pulse_player_hand(1, 150.0, 0.75, 0.14)
	else:
		_pulse_defender_both_hands(110.0, 0.50, 0.07)
	_set_header(msg, col)


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
	elif mode == "start_simultaneous":
		start_simultaneous_exchange()
	else:
		evaluate_round_outcome()


func _reset_all_timing_rings() -> void:
	for zone in target_zones:
		var r: Variant = zone.get("timing_ring")
		if r is MeshInstance3D and is_instance_valid(r):
			(r as MeshInstance3D).visible = false


func _tint_zone_shapes(zone: Dictionary, albedo_col: Color, em_col: Color, em_energy: float, inner_col: Color) -> void:
	var box_mat: StandardMaterial3D = zone.get("box_mat") as StandardMaterial3D
	var inner_mat: StandardMaterial3D = zone.get("inner_mat") as StandardMaterial3D
	var circ_mat: StandardMaterial3D = zone.get("circle_mat") as StandardMaterial3D
	var circ_ring_mat: StandardMaterial3D = zone.get("circle_ring_mat") as StandardMaterial3D
	if box_mat:
		box_mat.albedo_color = albedo_col
		box_mat.emission = em_col
		box_mat.emission_energy_multiplier = em_energy
	if inner_mat:
		inner_mat.albedo_color = inner_col
	if circ_mat:
		circ_mat.albedo_color = Color(albedo_col.r, albedo_col.g, albedo_col.b, clampf(albedo_col.a * 0.78, 0.08, 0.72))
		circ_mat.emission = em_col
		circ_mat.emission_energy_multiplier = em_energy
	if circ_ring_mat:
		circ_ring_mat.albedo_color = Color(albedo_col.r, albedo_col.g, albedo_col.b, clampf(albedo_col.a + 0.25, 0.20, 0.98))
		circ_ring_mat.emission = em_col
		circ_ring_mat.emission_energy_multiplier = em_energy * 1.15


func _update_sequential_target_highlights(skip_tint_zone_id: int = -1) -> void:
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color

		if z_id != skip_tint_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.visible = true
				z_node.scale = Vector3.ONE
			_tint_zone_shapes(zone, Color(orig_col.r, orig_col.g, orig_col.b, 0.58), Color(orig_col.r, orig_col.g, orig_col.b), 1.25, Color(orig_col.r, orig_col.g, orig_col.b, 0.90))

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


func _update_defense_zone_highlights(active_zone_id: int, step_num: int, next_zone_id: int = -1, is_heavy_note: bool = false, is_hammer_note: bool = false, is_v3_note: bool = false, attack_icon: String = "") -> void:
	var icon_str: String = attack_icon if not attack_icon.is_empty() else ("🔨" if is_hammer_note else ("🔥" if is_v3_note else ("⚡" if is_heavy_note else "👊")))
	var hl_key: String = "%d_%d_%d_%d_%d_%d_%s" % [active_zone_id, step_num, next_zone_id, int(is_heavy_note), int(is_hammer_note), int(is_v3_note), icon_str]
	if hl_key == _last_def_hl_key:
		return
	_last_def_hl_key = hl_key
	var hi_col: Color = Color(0.95, 0.2, 1.0, 0.95) if is_hammer_note else (Color(1.0, 0.24, 0.10, 0.95) if is_v3_note else (Color(1.0, 0.55, 0.12, 0.95) if is_heavy_note else Color(0.2, 0.92, 1.0, 0.95)))
	var hi_scale: float = 1.28 if is_hammer_note else (1.24 if is_v3_note else (1.18 if is_heavy_note else (1.08 if icon_str == "~👊" else 1.14)))
	var lbl_col: Color = Color(1.0, 0.92, 0.30, 1.0) if is_hammer_note else (Color(1.0, 0.62, 0.25, 1.0) if is_v3_note else (Color(1.0, 0.88, 0.35, 1.0) if is_heavy_note else Color(0.30, 0.95, 1.0, 1.0)))
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color
		if z_node and is_instance_valid(z_node):
			z_node.visible = true

		if z_id == active_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * hi_scale
			_tint_zone_shapes(zone, hi_col, Color(hi_col.r, hi_col.g, hi_col.b), 2.2, Color(1.0, 1.0, 1.0, 0.92))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "%s%d" % [icon_str, step_num]
				step_lbl.modulate = lbl_col
				step_lbl.visible = true
		elif z_id == next_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.86
			_tint_zone_shapes(zone, Color(0.55, 0.45, 0.95, 0.36), Color(0.55, 0.45, 0.95), 0.45, Color(1.0, 1.0, 1.0, 0.28))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "SIG"
				step_lbl.modulate = Color(0.75, 0.85, 1.0, 0.85)
				step_lbl.visible = true
		else:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.70
			_tint_zone_shapes(zone, Color(orig_col.r, orig_col.g, orig_col.b, 0.10), Color(orig_col.r, orig_col.g, orig_col.b), 0.12, Color(1.0, 1.0, 1.0, 0.08))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.visible = false


func _process(delta: float) -> void:
	if _hitstop_end_msec > 0 and Time.get_ticks_msec() >= _hitstop_end_msec:
		_hitstop_end_msec = 0
		if Engine.time_scale < 1.0:
			Engine.time_scale = 1.0

	if not is_active:
		return

	_surge_active_timer = maxf(_surge_active_timer - delta, 0.0)
	if _ki_delta_timer > 0.0:
		_ki_delta_timer -= delta
		if _ki_delta_timer <= 0.0 and _ki_delta_label and is_instance_valid(_ki_delta_label):
			_ki_delta_label.visible = false

	_refresh_melee_ki_bar()

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
		DomePhase.SIMULTANEOUS_EXCHANGE:
			_process_simultaneous_exchange(delta)
		DomePhase.UNBLOCKABLE_KI_BREAK:
			_process_unblockable_ki_break(delta)
		DomePhase.LORE_EVENT:
			_process_lore_event(delta)


# ==============================================================================
# FASE 1: ATAQUE (PUÑO CERRADO GRIP+TRIGGER + CARGA NV.1/NV.2/V3 + MARTILLAZO)
# ==============================================================================

func _process_attack_recording(delta: float) -> void:
	if attack_step_cooldown > 0.0:
		attack_step_cooldown -= delta

	_update_dome_transform()

	# Cancelación explícita de ataque (Stick ↓) o Skip / Confirmar golpes actuales (Botón A/X)
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_player")):
		var l_ctrl_skip: XRController3D = _get_controller("LeftHand")
		var r_ctrl: XRController3D = _get_controller("RightHand")
		if r_ctrl and _ctrl_vec2(r_ctrl, &"primary").y <= -0.55:
			hits.clear()
			if attacker.has_method("_log_combat_event"):
				attacker._log_combat_event("↩️ ¡Ataque cancelado! Te alejas del oponente.", "info")
			finish_without_hits(true)
			return
		var ax_now: bool = (l_ctrl_skip != null and _ctrl_pressed(l_ctrl_skip, &"ax_button")) or (r_ctrl != null and _ctrl_pressed(r_ctrl, &"ax_button"))
		if ax_now and not _skip_btn_prev and hits.size() >= 1:
			_skip_btn_prev = true
			_begin_phase_transition("start_defense", 0.35, "⏩ ¡ATAQUE CONFIRMADO (%d/%d)!" % [hits.size(), max_allowed_hits], Color(0.35, 0.96, 1.0))
			return
		_skip_btn_prev = ax_now

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


func _refresh_header_hud(is_charging_hammer: bool = false, active_zone_name: String = "", step_num: int = 0, remaining: float = 0.0, active_note: Dictionary = {}) -> void:
	if not header_label or not is_instance_valid(header_label):
		return

	var fb_line: String = ("\n%s" % last_action_feedback) if not last_action_feedback.is_empty() else ""

	if phase == DomePhase.ATTACK_RECORDING:
		_apply_role_dome_tint(true)
		var hud_col: Color = Color(1.0, 0.45, 0.18)
		var pct: float = clampf(time_left / maxf(duration, 0.1), 0.0, 1.0)
		var bar_len: int = int(pct * 8.0)
		var bar_str: String = "█".repeat(bar_len) + "░".repeat(8 - bar_len)
		var step_shown: int = mini(current_attack_step + 1, max_allowed_hits)

		if hammer_charge_time >= HAMMER_CHARGE_REQ or hammer_primed:
			_set_header("⚔️ ATACAS — 🔨 ¡BAJA AMBOS PUÑOS!", hud_col)
			return
		if is_charging_hammer:
			var h_pct: float = clampf(hammer_charge_time / maxf(HAMMER_CHARGE_REQ, 0.01), 0.0, 1.0)
			var h_len: int = int(roundf(h_pct * 8.0))
			var h_bar: String = "█".repeat(h_len) + "░".repeat(8 - h_len)
			_set_header("⚔️ ATACAS — 🔨 MARTILLAZO [%s]" % h_bar, hud_col)
			return

		var max_fist_charge: float = maxf(fist_charge_times[0], fist_charge_times[1])
		var charge_tag: String = ""
		if max_fist_charge >= 1.10:
			charge_tag = " 🔥V3 (ROMPE X)"
			hud_col = Color(1.0, 0.30, 0.12)
		elif max_fist_charge >= 0.50:
			charge_tag = " ⚡CARGADO (ROMPE 1M)"
			hud_col = Color(1.0, 0.65, 0.2)

		var tut: String = "\n[A/X]=Ejecutar ya (%d/%d) | Stick↓=Cancelar" % [hits.size(), max_allowed_hits] if hits.size() >= 1 else ("\nPuño(G+T)=Golpe | Stick↓=Cancelar" if not _tutorial_controls_shown else "")
		_set_header("⚔️ ATACAS (%d/%d)%s  [%s]%s%s" % [step_shown, max_allowed_hits, charge_tag, bar_str, fb_line, tut], hud_col)
	elif phase == DomePhase.DEFENSE_RHYTHM:
		var pips: String = _get_pips_string(hits.size())
		if defender and defender.get("is_player"):
			_apply_role_dome_tint(false)
			var def_ki_now: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
			var cfg_ew_h: KiEconomyConfig = KiEconomyConfig.get_default()
			var kiai_cost_h: float = float(cfg_ew_h.melee_explosive_wave_cost) if cfg_ew_h.get("melee_explosive_wave_cost") != null else 16.0
			var kiai_hint: String = "\n🔥 ¡ABRE BRAZOS+2 GRIPS=ONDA KIAI (-%d Ki)!" % int(kiai_cost_h) if (_round_unblocked_hits_taken >= 2 and def_ki_now >= kiai_cost_h) else ""
			var tut_def: String = "\nTrigger=Bloqueo 1 Mano | Dorado+G+T=Parry | Stick=Z-Vanish" if not _tutorial_controls_shown else ""
			var note_meta: Dictionary = get_attack_visual_meta(active_note) if not active_note.is_empty() else {}
			var note_tag: String = (" [" + String(note_meta.get("tag", "")) + "]") if not note_meta.is_empty() else ""
			var note_hint: String = ("\n" + String(note_meta.get("hud_hint", ""))) if not note_meta.is_empty() else ""
			var hdr_col: Color = (note_meta.get("color", Color(0.25, 0.90, 1.0)) as Color) if not note_meta.is_empty() else Color(0.25, 0.90, 1.0)
			var hdr_txt: String = ("🛡️ DEFIENDES (%d/%d) %s%s  %s%s" % [step_num, hits.size(), active_zone_name, note_tag, pips, _def_stick_diag_str]) + note_hint + fb_line + kiai_hint + tut_def
			_set_header(hdr_txt, hdr_col)
		else:
			_apply_role_dome_tint(true)
			_set_header("⚔️ ATACAS (%d/%d) %s  %s%s" % [step_num, hits.size(), active_zone_name, pips, fb_line], Color(1.0, 0.55, 0.20))
	elif phase == DomePhase.SIMULTANEOUS_EXCHANGE:
		_set_header("⚡ ¡INTERCAMBIO SIMULTÁNEO! (%.1fs) ⚡\n⭕ Golpea: %d/4  |  ⬜ Daño recibido: %d/4  |  💥 Choques: %d%s" % [_sim_duration, _sim_enemy_hits_taken, _sim_player_hits_taken, _sim_clash_count, fb_line], Color(1.0, 0.88, 0.22))


# ==============================================================================
# FASE 2: DEFENSA RÍTMICA SECUENCIAL (1.25s POR GOLPE)
# ==============================================================================

func _compute_note_prewarn_sec(note: Dictionary) -> float:
	var vel: float = float(note.get("velocity", 1.8))
	var base_t: float = clampf(0.76 - (vel - 1.2) * 0.06, 0.58, 0.76)
	if bool(note.get("is_hammer", false)):
		base_t = 1.55
	elif bool(note.get("is_charged_v3", false)):
		base_t = 1.42
	elif bool(note.get("is_charged", false)):
		base_t = 1.22

	var is_heavy_pw: bool = bool(note.get("is_charged", false)) or bool(note.get("is_charged_v3", false)) or bool(note.get("is_hammer", false))
	var prof_pw: Dictionary = _get_bp_profile(attacker, defender, is_heavy_pw)
	var bp_factor: float = clampf(float(prof_pw["def_time_mult"]), 0.78, 1.35)
	return clampf(base_t * bp_factor, 0.55, 2.20)


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
	_timing_cue_note_idx = -1
	_def_stick_used_for_note_idx = -1
	_def_stick_prev = false
	_def_stick_diag_str = ""
	_round_unblocked_hits_taken = 0
	_round_clean_sonic_hits = 0
	_round_clean_charged_hits = 0
	_last_def_hl_key = ""
	defense_score_sum = 0.0
	defense_round_total_hits = hits.size()
	def_left_velocity = Vector3.ZERO
	def_right_velocity = Vector3.ZERO
	_has_prev_def_local = false
	buffer_grip_timer_l = 0.0
	buffer_grip_timer_r = 0.0
	buffer_trig_timer_l = 0.0
	buffer_trig_timer_r = 0.0
	_trig_press_age_l = 0.0
	_trig_press_age_r = 0.0
	def_grip_l = false
	def_grip_r = false
	def_trig_l = false
	def_trig_r = false
	prev_grip_l = false
	prev_grip_r = false
	prev_trig_l = false
	prev_trig_r = false
	if attacker and is_instance_valid(attacker) and attacker.has_method("set"):
		attacker.set("is_blocking", false)
	if defender and is_instance_valid(defender) and defender.has_method("set"):
		defender.set("is_blocking", false)
		if bool(defender.get("is_player")):
			var lc_sd: XRController3D = _get_controller("LeftHand")
			var rc_sd: XRController3D = _get_controller("RightHand")
			if lc_sd:
				def_grip_l = _ctrl_float(lc_sd, &"grip") > 0.50 or _ctrl_pressed(lc_sd, &"grip_click")
				def_trig_l = _ctrl_float(lc_sd, &"trigger") > 0.50 or _ctrl_pressed(lc_sd, &"trigger_click")
				prev_grip_l = def_grip_l
				prev_trig_l = def_trig_l
			if rc_sd:
				def_grip_r = _ctrl_float(rc_sd, &"grip") > 0.50 or _ctrl_pressed(rc_sd, &"grip_click")
				def_trig_r = _ctrl_float(rc_sd, &"trigger") > 0.50 or _ctrl_pressed(rc_sd, &"trigger_click")
				prev_grip_r = def_grip_r
				prev_trig_r = def_trig_r
	_pending_finisher_mode = ""
	_pending_finisher_vel = 0.0
	_skip_btn_prev = false
	_set_target_zones_visible(true)
	_reset_all_timing_rings()
	_apply_role_dome_tint(not bool(defender and is_instance_valid(defender) and defender.get("is_player")))
	_refresh_melee_ki_bar()

	var def_is_ai: bool = defender != null and is_instance_valid(defender) and not bool(defender.get("is_player"))
	var accum_time: float = 0.0
	for h in hits:
		if def_is_ai:
			var is_heavy_h: bool = bool(h.get("is_charged", false)) or bool(h.get("is_charged_v3", false)) or bool(h.get("is_hammer", false))
			var ai_gap: float = 0.38 if is_heavy_h else 0.30
			h["prewarn_sec"] = minf(_compute_note_prewarn_sec(h), ai_gap)
			accum_time += (0.22 if accum_time == 0.0 else ai_gap)
		else:
			var prewarn: float = _compute_note_prewarn_sec(h)
			h["prewarn_sec"] = prewarn
			accum_time += prewarn + 0.16
		h["time_offset"] = accum_time
	defense_total_duration = accum_time + (0.30 if def_is_ai else 0.90)

	if dome_mesh and is_instance_valid(dome_mesh):
		var mat := dome_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.5, 0.9, 0.08)

	_update_dome_transform_for_defender()

	var first_z: int = int(hits[0].get("zone_id", 0))
	var next_z: int = int(hits[1].get("zone_id", -1)) if hits.size() > 1 else -1
	var first_meta: Dictionary = get_attack_visual_meta(hits[0])
	_update_defense_zone_highlights(first_z, 1, next_z, bool(hits[0].get("is_charged", false)), bool(hits[0].get("is_hammer", false)), bool(hits[0].get("is_charged_v3", false)), String(first_meta.get("icon", "")))
	_refresh_header_hud(false, String(hits[0].get("name", "Centro")), 1, defense_total_duration, hits[0])


func _read_defender_stick_state() -> Dictionary:
	var l_zv: XRController3D = _get_controller("LeftHand")
	var r_zv: XRController3D = _get_controller("RightHand")
	var st_l_p: Vector2 = _ctrl_vec2(l_zv, &"primary") if l_zv else Vector2.ZERO
	var st_l_s: Vector2 = _ctrl_vec2(l_zv, &"secondary") if l_zv else Vector2.ZERO
	var st_r_p: Vector2 = _ctrl_vec2(r_zv, &"primary") if r_zv else Vector2.ZERO
	var st_r_s: Vector2 = _ctrl_vec2(r_zv, &"secondary") if r_zv else Vector2.ZERO
	var stick_mag: float = maxf(maxf(st_l_p.length(), st_l_s.length()), maxf(st_r_p.length(), st_r_s.length()))
	var stick_clicked: bool = (
		(l_zv != null and (_ctrl_pressed(l_zv, &"primary_click") or _ctrl_pressed(l_zv, &"secondary_click")))
		or (r_zv != null and (_ctrl_pressed(r_zv, &"primary_click") or _ctrl_pressed(r_zv, &"secondary_click")))
	)
	var stick_active: bool = stick_clicked or stick_mag >= 0.50
	var stick_fresh: bool = stick_active and not _def_stick_prev
	_def_stick_prev = stick_active
	if stick_clicked:
		_def_stick_diag_str = " [🕹️ CLICK]"
	elif stick_mag >= 0.15:
		_def_stick_diag_str = " [🕹️ %.2f]" % stick_mag
	else:
		_def_stick_diag_str = ""
	return {
		"mag": stick_mag,
		"clicked": stick_clicked,
		"active": stick_active,
		"fresh": stick_fresh
	}


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
	var is_def_crashed: bool = defender_is_defenseless or (defender != null and is_instance_valid(defender) and bool(defender.get("is_defenseless_crash")))
	var defender_is_player: bool = (defender != null and is_instance_valid(defender) and bool(defender.get("is_player")))
	var stick_state: Dictionary = _read_defender_stick_state() if defender_is_player else { "mag": 0.0, "clicked": false, "active": false, "fresh": false }
	if not defender_is_player:
		_def_stick_prev = false
		_def_stick_diag_str = ""

	# Onda Explosiva (Kiai de Emergencia) al recibir >= 2 golpes sin bloquear en la ronda (máx. 1 por cúpula)
	if defender_is_player and not is_def_crashed and not _explosive_wave_used_this_dome and _round_unblocked_hits_taken >= 2 and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var l_c: XRController3D = _get_controller("LeftHand")
		var r_c: XRController3D = _get_controller("RightHand")
		if l_c and r_c and def_grip_l and def_grip_r and l_c.global_position.distance_to(r_c.global_position) >= 0.75:
			var def_ki_ew: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
			var ew_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
				"trigger_source": "explosive_wave_input",
				"def_ki": def_ki_ew,
				"consecutive_hits_taken": _round_unblocked_hits_taken
			})
			if ew_ev == MeleeLoreEventScript.LoreEventType.EXPLOSIVE_WAVE:
				_explosive_wave_used_this_dome = true
				_start_lore_event(ew_ev, "explosive_wave")
				return

	if not all_resolved:
		var active_note: Dictionary = hits[first_unresolved_idx]
		var active_z_id: int = int(active_note.get("zone_id", 0))
		var next_z_id: int = int(hits[first_unresolved_idx + 1].get("zone_id", -1)) if (first_unresolved_idx + 1 < hits.size()) else -1
		var is_heavy: bool = bool(active_note.get("is_charged", false)) or bool(active_note.get("is_charged_v3", false))
		var is_hammer: bool = bool(active_note.get("is_hammer", false))
		var is_v3_hl: bool = bool(active_note.get("is_charged_v3", false))
		var active_meta: Dictionary = get_attack_visual_meta(active_note)
		_update_defense_zone_highlights(active_z_id, first_unresolved_idx + 1, next_z_id, is_heavy, is_hammer, is_v3_hl, String(active_meta.get("icon", "")))

		var remaining: float = maxf(defense_total_duration - defense_timer, 0.0)
		var active_name: String = String(ZONE_DEFINITIONS[active_z_id]["name"]) if active_z_id < ZONE_DEFINITIONS.size() else "Centro"
		_refresh_header_hud(false, active_name, first_unresolved_idx + 1, remaining, active_note)

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

		# Semáforo legible sincronizado con la ventana real:
		# Nv.1: Rojo (>0.30) -> Ámbar (0.18..0.30) -> Verde (<=0.18..-0.16)
		# Cargado/V3: Rojo (>0.38) -> Ámbar (0.28..0.38) -> Verde (<=0.28..-0.18) -> Dorado (±0.11)
		# Martillo: Púrpura/Rojo (>0.28 ESPERAR) -> Verde (<=0.28..-0.18 ¡Z-VANISH!)
		var note_prewarn: float = float(active_note.get("prewarn_sec", RING_PREWARN_SEC))
		var crossing_now: bool = _is_defender_crossing_arms() if (defender_is_player and not is_def_crashed) else false
		var is_early_locked: bool = bool(active_note.get("early_lockout", false))
		var note_is_chg: bool = bool(active_note.get("is_charged", false))
		var note_is_v3: bool = bool(active_note.get("is_charged_v3", false))
		var green_start_vis: float = get_defense_green_start_sec(note_is_chg, note_is_v3, is_hammer)
		var amber_start_vis: float = green_start_vis if is_hammer else (0.38 if is_heavy else 0.30)
		var green_end_vis: float = -0.18 if (is_heavy or is_hammer) else -0.16

		if t_diff >= -0.22 and t_diff <= note_prewarn:
			if active_ring and is_instance_valid(active_ring):
				active_ring.visible = true
				var t_factor: float = clampf(maxf(t_diff, 0.0) / maxf(note_prewarn, 0.01), 0.0, 1.0)
				var base_ring_scale: float = 1.08 if (not is_hammer and absf(t_diff) <= 0.11) else 1.0
				active_ring.scale = Vector3.ONE * (base_ring_scale + t_factor * 1.65)
				var r_mat: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
				var ring_tint: Color
				var shape_tint: Color
				if is_early_locked:
					ring_tint = Color(1.0, 0.08, 0.08, 1.0)
					shape_tint = ring_tint
				elif not is_hammer and absf(t_diff) <= 0.11:
					ring_tint = Color(1.0, 0.96, 0.62, 1.0)
					shape_tint = ring_tint
				elif t_diff <= green_start_vis and t_diff >= green_end_vis:
					ring_tint = Color(0.15, 1.0, 0.35, 1.0)
					shape_tint = ring_tint
					if defender_is_player and not is_def_crashed and _timing_cue_note_idx != first_unresolved_idx:
						_timing_cue_note_idx = first_unresolved_idx
						_pulse_defender_both_hands(140.0, 0.35, 0.04)
				elif not is_hammer and t_diff <= amber_start_vis and t_diff > green_start_vis:
					ring_tint = Color(1.0, 0.56, 0.08, 0.96)
					shape_tint = ring_tint
				else:
					ring_tint = Color(0.95, 0.16, 0.16, 0.90)
					if is_hammer:
						shape_tint = Color(0.82, 0.28, 1.0, 0.90)
					elif note_is_v3:
						shape_tint = Color(1.0, 0.22, 0.10, 0.92)
					elif note_is_chg:
						shape_tint = Color(1.0, 0.55, 0.14, 0.92)
					else:
						shape_tint = ring_tint
				if r_mat:
					r_mat.albedo_color = ring_tint
				_tint_zone_shapes(active_zone, shape_tint, shape_tint, 2.4 if (t_diff <= amber_start_vis and t_diff >= green_end_vis) else 1.6, Color(1.0, 1.0, 1.0, 0.92))
		elif t_diff > note_prewarn and active_ring and is_instance_valid(active_ring):
			active_ring.visible = false

		# 1. Z-Vanish Defensivo estricto: SOLO válido cuando el aro está VERDE; antes de Verde -> FALLO (early_lockout)
		if defender_is_player and not is_def_crashed and not is_early_locked and bool(stick_state.get("fresh", false)) and _def_stick_used_for_note_idx != first_unresolved_idx and t_diff <= note_prewarn and t_diff >= -0.22:
			var stick_mag_now: float = float(stick_state.get("mag", 0.0))
			var stick_clicked_now: bool = bool(stick_state.get("clicked", false))
			var zv_info: Dictionary = _get_vanish_cost_and_label(defender)
			var vanish_cost: float = float(zv_info.get("cost", 10.0))
			var cur_def_ki: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
			var zv_res: String = evaluate_defensive_z_vanish_input(
				t_diff,
				note_prewarn,
				stick_mag_now,
				stick_clicked_now,
				note_is_chg,
				note_is_v3,
				is_hammer,
				cur_def_ki,
				vanish_cost
			)
			var zone_pos_zv: Vector3 = active_zone["node"].global_position
			match zv_res:
				"EXECUTE":
					_def_stick_used_for_note_idx = first_unresolved_idx
					_consume_defender_note_buffers()
					print("[ZVanish] EXECUTE t_diff=%.2f mag=%.2f click=%s ki=%.1f" % [t_diff, stick_mag_now, str(stick_clicked_now), cur_def_ki])
					_resolve_defensive_z_vanish(active_note, active_zone)
					return
				"EARLY_FAIL":
					active_note["early_lockout"] = true
					is_early_locked = true
					_def_stick_used_for_note_idx = first_unresolved_idx
					_consume_defender_note_buffers()
					if active_ring and is_instance_valid(active_ring):
						var r_mat_zv_e: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
						if r_mat_zv_e:
							r_mat_zv_e.albedo_color = Color(1.0, 0.08, 0.08, 1.0)
					_tint_zone_shapes(active_zone, Color(1.0, 0.08, 0.08, 1.0), Color(1.0, 0.08, 0.08), 2.5, Color(1.0, 0.3, 0.3, 0.95))
					_pulse_defender_both_hands(95.0, 0.55, 0.14)
					last_action_feedback = "❌ ¡Z-VANISH MUY PRONTO! (Espera VERDE)"
					_spawn_impact_popup(zone_pos_zv, "❌ ¡MUY PRONTO! FALLO Z-VANISH", Color(1.0, 0.16, 0.12))
					print("[ZVanish] EARLY_FAIL t_diff=%.2f mag=%.2f click=%s" % [t_diff, stick_mag_now, str(stick_clicked_now)])
				"NO_KI":
					if not bool(active_note.get("zv_noki_hint_shown", false)):
						active_note["zv_noki_hint_shown"] = true
						last_action_feedback = "⚠️ ¡SIN KI PARA Z-VANISH! (%d/%d Ki)" % [int(cur_def_ki), int(vanish_cost)]
						_spawn_impact_popup(zone_pos_zv, "⚠️ ¡SIN KI PARA Z-VANISH! (%d/%d)" % [int(cur_def_ki), int(vanish_cost)], Color(1.0, 0.35, 0.15))
						_pulse_defender_both_hands(110.0, 0.55, 0.08)
						print("[ZVanish] NO_KI t_diff=%.2f ki=%.1f cost=%.1f" % [t_diff, cur_def_ki, vanish_cost])
				"BLOCKED_QUICK":
					if not bool(active_note.get("zv_quick_hint_shown", false)):
						active_note["zv_quick_hint_shown"] = true
						last_action_feedback = "👊 ¡Z-VANISH NO SIRVE VS RÁPIDO! Usa Trigger o X"
						_spawn_impact_popup(zone_pos_zv, "👊 ¡Z-VANISH NO SIRVE VS RÁPIDO! Usa Trigger o X", Color(1.0, 0.55, 0.15))
						_pulse_defender_both_hands(90.0, 0.35, 0.06)

		# Castigo estricto por pulsar defensa ANTES de Ámbar/Verde, sin penalizar Guardia X/Kiai ni preparar puño de Choque
		var is_heavy_atk: bool = is_heavy or is_hammer
		if defender_is_player and not is_def_crashed and t_diff > amber_start_vis and not crossing_now and not is_early_locked:
			var forming_x_or_kiai: bool = false
			var lc_el: XRController3D = _get_controller("LeftHand")
			var rc_el: XRController3D = _get_controller("RightHand")
			if lc_el and rc_el and def_grip_l and def_grip_r:
				var hands_dist_el: float = lc_el.global_position.distance_to(rc_el.global_position)
				if hands_dist_el < 0.38 or hands_dist_el >= 0.65:
					forming_x_or_kiai = true
			if not forming_x_or_kiai:
				var zone_pos_el: Vector3 = active_zone["node"].global_position
				var fwd_el: Vector3 = _get_punch_forward_world()
				var d_l_el: float = lc_el.global_position.distance_to(zone_pos_el) if lc_el else 999.0
				var d_r_el: float = rc_el.global_position.distance_to(zone_pos_el) if rc_el else 999.0
				var fv_l_el: float = def_left_velocity.dot(fwd_el)
				var fv_r_el: float = def_right_velocity.dot(fwd_el)
				var wind_l: bool = is_hand_winding_clash_in_red(def_grip_l, def_trig_l, d_l_el, fv_l_el, is_hammer, is_heavy_atk) or (not is_hammer and def_grip_l and def_trig_l and d_l_el > 0.34)
				var wind_r: bool = is_hand_winding_clash_in_red(def_grip_r, def_trig_r, d_r_el, fv_r_el, is_hammer, is_heavy_atk) or (not is_hammer and def_grip_r and def_trig_r and d_r_el > 0.34)
				var early_trig_any: bool = (not wind_l and buffer_trig_timer_l > 0.0) or (not wind_r and buffer_trig_timer_r > 0.0)
				var early_grip_any: bool = (not wind_l and buffer_grip_timer_l > 0.0) or (not wind_r and buffer_grip_timer_r > 0.0)
				var early_res: String = evaluate_one_hand_defense_input(t_diff, false, false, early_trig_any, early_grip_any, false, 0.0, 0.0, 0.0, is_hammer, is_heavy_atk)
				if early_res == "EARLY_LOCKOUT":
					active_note["early_lockout"] = true
					is_early_locked = true
					_consume_defender_note_buffers()
					if active_ring and is_instance_valid(active_ring):
						var r_mat_e: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
						if r_mat_e:
							r_mat_e.albedo_color = Color(1.0, 0.08, 0.08, 1.0)
					_tint_zone_shapes(active_zone, Color(1.0, 0.08, 0.08, 1.0), Color(1.0, 0.08, 0.08), 2.5, Color(1.0, 0.3, 0.3, 0.95))
					_pulse_defender_both_hands(95.0, 0.50, 0.14)
					_spawn_impact_popup(active_zone["node"].global_position, "❌ ¡MUY PRONTO! FALLO DE BLOQUEO", Color(1.0, 0.18, 0.14))

		if is_def_crashed and t_diff <= 0.0:
			_resolve_unblocked_hit(active_note, active_zone)
			return

		if is_early_locked and defender_is_player and t_diff <= 0.0 and not crossing_now:
			_resolve_unblocked_hit(active_note, active_zone)
			return

		# Ventana de resolución defensiva (hasta ±0.30s incluyendo Ámbar 0.18..0.30s, Verde <=0.18s, Dorado <=0.12s)
		if not is_def_crashed and t_diff <= 0.30 and t_diff >= -0.22:
			if defender_is_player:
				var not_locked_out: bool = not is_early_locked
				var zone_pos: Vector3 = active_zone["node"].global_position
				var hand_parry_idx: int = _get_defender_hand_near_zone(zone_pos, 0.28) if not crossing_now else -1

				# 2-4. Bloqueo Perfecto (G+T Dorado <=0.12s), Choque de Puños (G+T frontal) y Bloqueo 1 Mano (Trigger fresco sin Grip)
				if not_locked_out and hand_parry_idx != -1:
					var h_vec: Vector3 = def_left_velocity if hand_parry_idx == 0 else def_right_velocity
					var h_vel: float = h_vec.length()
					var fwd_dir_def: Vector3 = _get_punch_forward_world()
					var fwd_clash_spd: float = h_vec.dot(fwd_dir_def)
					var h_trig: bool = def_trig_l if hand_parry_idx == 0 else def_trig_r
					var h_grip: bool = def_grip_l if hand_parry_idx == 0 else def_grip_r
					var h_trig_buf: bool = (buffer_trig_timer_l > 0.0) if hand_parry_idx == 0 else (buffer_trig_timer_r > 0.0)
					var h_grip_buf: bool = (buffer_grip_timer_l > 0.0) if hand_parry_idx == 0 else (buffer_grip_timer_r > 0.0)
					var h_trig_age: float = _trig_press_age_l if hand_parry_idx == 0 else _trig_press_age_r
					var h_just_guard: bool = _is_defender_just_guard_active(hand_parry_idx)
					var def_action: String = evaluate_one_hand_defense_input(t_diff, h_trig, h_grip, h_trig_buf, h_grip_buf, h_just_guard, h_trig_age, fwd_clash_spd, h_vel, is_hammer, is_heavy_atk)
					match def_action:
						"PARRY":
							_consume_defender_note_buffers()
							_resolve_perfect_parry(active_note, active_zone)
							return
						"CLASH":
							_consume_defender_note_buffers()
							_resolve_fist_clash(active_note, active_zone, hand_parry_idx)
							return
						"BLOCK_GREEN", "BLOCK_YELLOW":
							_consume_defender_note_buffers()
							var timing_grade: String = "GREEN" if def_action == "BLOCK_GREEN" else "YELLOW"
							_resolve_hand_block(active_note, active_zone, hand_parry_idx, timing_grade)
							if phase != DomePhase.DEFENSE_RHYTHM:
								return
						"HAMMER_UNBLOCKABLE":
							if not bool(active_note.get("hammer_hint_shown", false)):
								active_note["hammer_hint_shown"] = true
								last_action_feedback = "🔨 ¡MARTILLO INBLOQUEABLE! ¡Usa Stick (Z-Vanish)!"
								_spawn_impact_popup(zone_pos, "🔨 ¡SOLO Z-VANISH (Stick)!", Color(0.95, 0.25, 1.0))
								_pulse_defender_both_hands(95.0, 0.45, 0.08)
						"NO_PARRY_QUICK":
							if not bool(active_note.get("no_parry_hint_shown", false)):
								active_note["no_parry_hint_shown"] = true
								last_action_feedback = "👊 ¡RÁPIDO SIN PARRY/CHOQUE! Usa Trigger o Guardia X"
								_spawn_impact_popup(zone_pos, "👊 ¡SOLO 1M o GUARDIA X!", Color(0.25, 0.90, 1.0))
								_pulse_defender_both_hands(90.0, 0.35, 0.06)

				# 5. Guardia Cruzada X (Martillo no roba la ventana Verde de Z-Vanish: atraviesa al impacto t_diff <= 0.0)
				if crossing_now and ((not is_hammer and absf(t_diff) <= 0.28) or (is_hammer and t_diff <= 0.0)):
					_consume_defender_note_buffers()
					_resolve_cross_arm_guard(active_note, active_zone)
					if phase != DomePhase.DEFENSE_RHYTHM:
						return
			elif not defender_is_player and t_diff <= 0.05:
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
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var cfg_pp: KiEconomyConfig = KiEconomyConfig.get_default()
	var parry_ki: float = float(cfg_pp.melee_parry_ki_reward) if cfg_pp.get("melee_parry_ki_reward") != null else 20.0
	var parry_atk_drain: float = float(cfg_pp.melee_parry_attacker_ki_drain) if cfg_pp.get("melee_parry_attacker_ki_drain") != null else 10.0
	var prof_pp: Dictionary = _get_bp_profile(attacker, defender, true)
	var def_was_furia_pp: bool = defender != null and is_instance_valid(defender) and bool(defender.get("is_in_furia"))
	var pp_bp_gain: float = 400.0 * float(prof_pp["defender_underdog_bp_mult"])
	var pp_underdog_comeback: bool = float(prof_pp["raw_ratio"]) > 1.15
	_modify_fighter_ki(defender, parry_ki, true)
	_modify_fighter_ki(attacker, -parry_atk_drain)
	if defender and is_instance_valid(defender) and defender.has_method("increase_np"):
		defender.increase_np(pp_bp_gain)
	if pp_underdog_comeback and attacker and is_instance_valid(attacker) and attacker.has_method("take_hit"):
		var parry_punish_bp: float = lerpf(250.0, 400.0, clampf((float(prof_pp["raw_ratio"]) - 1.15) / 0.85, 0.0, 1.0))
		attacker.take_hit(parry_punish_bp, Vector3.ZERO, false)

	if audio_player:
		audio_player.global_position = zone["node"].global_position
		audio_player.pitch_scale = 1.30
		AudioActionManager.play_action("common.block_perfect", audio_player)

	_spawn_parry_shockwave(zone["node"].global_position)
	_pulse_defender_both_hands(250.0, 1.0, 0.25)
	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		defender.procedural_animator.trigger_melee_block(3)
	perform_z_blink_relocation(_pick_aggressive_melee_spot(1.85, true))

	last_action_feedback = "⚡ ¡PARRY PERFECTO! (+%d Ki)" % int(parry_ki)
	pip_results.append("blocked")
	_spawn_impact_popup(zone["node"].global_position, "✨ ¡PARRY!", Color(1.0, 0.92, 0.25))
	emit_signal("defense_action_resolved", "perfect_parry", zone["id"], true, parry_ki, pp_bp_gain)
	_trigger_hit_stop(0.08)

	for h in hits:
		h["resolved"] = true

	# GDD Canon: Parry Perfecto en estado Furia desata Comeback Zenkai en el defensor (antes del swap)
	if def_was_furia_pp and defender and is_instance_valid(defender) and not bool(defender.get("is_in_zenkai_state")) and defender.has_method("trigger_comeback_zenkai"):
		defender.trigger_comeback_zenkai()

	if _check_ki_break_after_note():
		return

	# Punto 3: Si fue Martillazo y el defensor tiene BP igual o menor (< 1.25x), corta el melee y gana distancia
	if bool(note.get("is_hammer", false)):
		var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
		if bp_def < bp_atk * 1.25:
			_cut_melee_hammer_defended(defender, attacker, 0.0)
			return

	pending_attack_penalty = 0
	if pp_underdog_comeback:
		_comeback_momentum_active = true
	restart_as_attacker(pp_underdog_comeback)


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
	var prof_fc: Dictionary = _get_bp_profile(attacker, defender, true)
	var cfg_fc: KiEconomyConfig = KiEconomyConfig.get_default()
	var clash_cost: float = float(cfg_fc.melee_clash_cost) if cfg_fc.get("melee_clash_cost") != null else 3.0
	var clash_even_reward: float = float(cfg_fc.melee_clash_even_ki_reward) if cfg_fc.get("melee_clash_even_ki_reward") != null else 6.0
	var clash_win: float = float(cfg_fc.melee_clash_win_reward) if cfg_fc.get("melee_clash_win_reward") != null else 14.0

	var score: float = 0.25
	if r_bp >= 0.70:
		clash_penalty_hits += 1
		var fc_ev: int = MeleeLoreEventScript.LoreEventType.NONE
		var flurry_chance: float = float(cfg_fc.melee_flurry_clash_trigger_chance) if cfg_fc.get("melee_flurry_clash_trigger_chance") != null else 0.45
		if phase == DomePhase.DEFENSE_RHYTHM and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")) and should_trigger_individual_flurry_clash(randf(), flurry_chance, _flurry_clash_cooldown_melees):
			var atk_ki_fc: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
			var def_ki_fc: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 0.0
			fc_ev = MeleeLoreEventScript.evaluate_lore_event_trigger({
				"trigger_source": "fist_clash",
				"last_event_type": _last_lore_event_type,
				"atk_ki": atk_ki_fc,
				"def_ki": def_ki_fc,
				"bp_ratio": r_bp
			})

		if fc_ev == MeleeLoreEventScript.LoreEventType.FIST_FLURRY_CLASH:
			score = 0.65
			note["defense_score"] = score
			defense_score_sum += score
			if audio_player:
				audio_player.global_position = zone_pos
				audio_player.pitch_scale = 1.08
				AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
			_spawn_parry_shockwave(zone_pos)
			_pulse_defender_hand(hand_idx, 210.0, 1.0, 0.16)
			if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
				defender.procedural_animator.trigger_melee_block(2)
			last_action_feedback = "⚡ ¡CHOQUE → RÁFAGA!"
			pip_results.append("clash")
			_spawn_impact_popup(zone_pos, "⚡ ¡CHOQUE → RÁFAGA!", Color(1.0, 0.92, 0.25))
			emit_signal("defense_action_resolved", "fist_clash", zone["id"], true, 0.0, 0.0)
			if _check_ki_break_after_note():
				return
			_start_lore_event(fc_ev, "fist_clash")
			return

		var def_ki_gain: float = clash_win if r_bp > 1.43 else clash_even_reward
		var atk_ki_gain: float = -clash_cost if r_bp > 1.43 else 2.0
		var def_bp_gain: float = (350.0 if r_bp > 1.43 else 300.0) * float(prof_fc["defender_underdog_bp_mult"])
		var atk_bp_gain: float = (100.0 if r_bp > 1.43 else 250.0) * float(prof_fc["bp_gain_mult"])
		score = 1.00 if r_bp > 1.43 else 0.65

		_modify_fighter_ki(defender, def_ki_gain, true)
		_modify_fighter_ki(attacker, atk_ki_gain)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(def_bp_gain)
		if attacker and attacker.has_method("increase_np"):
			attacker.increase_np(atk_bp_gain)

		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 1.12
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
		_spawn_parry_shockwave(zone_pos)
		_pulse_defender_hand(hand_idx, 210.0, 1.0, 0.16)
		if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
			defender.procedural_animator.trigger_melee_block(2)
		var lat_c: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
		_trigger_dynamic_melee_mobility(float(note.get("power", 1.35)), bool(note.get("is_charged", false)), bool(note.get("is_charged_v3", false)), false, defender, attacker, lat_c * 7.5 + Vector3.UP * 2.4, 0.22, true)
		_trigger_hit_stop(0.08)

		last_action_feedback = "⚡ ¡CHOQUE DE PUÑOS! +%d Ki" % int(def_ki_gain)
		pip_results.append("clash")
		_spawn_impact_popup(zone_pos, "⚡ ¡CHOQUE!", Color(1.0, 1.0, 0.85))
		emit_signal("defense_action_resolved", "fist_clash", zone["id"], true, def_ki_gain, def_bp_gain)
	else:
		var raw_dmg: float = 360.0 if bool(note.get("is_charged_v3", false)) else (240.0 if bool(note.get("is_charged", false)) else 140.0)
		var partial_dmg: float = raw_dmg * 0.50 * float(prof_fc["damage_scale"])
		_modify_fighter_ki(defender, -clash_cost)
		_modify_fighter_ki(attacker, 4.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(partial_dmg, Vector3.ZERO)
		if attacker and attacker.has_method("increase_np"):
			attacker.increase_np(200.0 * float(prof_fc["bp_gain_mult"]))
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 0.88
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
		_spawn_hit_spark(zone_pos)
		_pulse_defender_hand(hand_idx, 160.0, 0.75, 0.14)
		var lat_cl: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
		var atk_to_def_fc: Vector3 = (-_duel_axis if (defender and is_instance_valid(defender) and bool(defender.get("is_player"))) else _duel_axis)
		_trigger_dynamic_melee_mobility(float(note.get("power", 1.2)), bool(note.get("is_charged", false)), bool(note.get("is_charged_v3", false)), false, attacker, defender, atk_to_def_fc * 6.5 + lat_cl * 2.4 + Vector3.UP * 1.4, 0.22, false)

		last_action_feedback = "💥 ¡SUPERADO EN CHOQUE! (-%d BP)" % int(partial_dmg)
		pip_results.append("hit")
		_spawn_impact_popup(zone_pos, "💥 ¡IMPACTO!", Color(1.0, 0.38, 0.15))
		emit_signal("defense_action_resolved", "fist_clash_lost", zone["id"], false, -clash_cost, 0.0)

	note["defense_score"] = score
	defense_score_sum += score
	_check_ki_break_after_note()


func _resolve_defensive_z_vanish(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var zv_info: Dictionary = _get_vanish_cost_and_label(defender)
	var vanish_cost: float = float(zv_info.get("cost", 10.0))
	var vanish_lbl: String = String(zv_info.get("label", "💨 ¡Z-VANISH!"))
	var prof_zv: Dictionary = _get_bp_profile(attacker, defender, true)
	var zv_bp_reward: float = 120.0 * float(prof_zv["defender_underdog_bp_mult"])
	_modify_fighter_ki(defender, -vanish_cost)
	if defender and is_instance_valid(defender) and defender.has_method("increase_np"):
		defender.increase_np(zv_bp_reward)
	var zone_pos: Vector3 = zone["node"].global_position

	_spawn_parry_shockwave(zone_pos)
	perform_z_blink_relocation()
	var new_cam: Camera3D = _get_player_camera()
	var listen_pos: Vector3 = new_cam.global_position if (new_cam and is_instance_valid(new_cam)) else global_position
	if audio_player:
		audio_player.global_position = listen_pos
		audio_player.pitch_scale = 1.15
		AudioActionManager.play_action("common.dodge_vanish", audio_player)
	_pulse_defender_both_hands(210.0, 0.90, 0.14)
	_spawn_parry_shockwave(global_position)
	if attacker and is_instance_valid(attacker) and attacker.get("procedural_animator"):
		var opp_dir_zv: Vector3 = _duel_axis if (defender and is_instance_valid(defender) and bool(defender.get("is_player"))) else -_duel_axis
		attacker.procedural_animator.trigger_hit_flinch(0.35, opp_dir_zv.normalized() if opp_dir_zv.length_squared() > 0.01 else Vector3.FORWARD)

	note["defense_score"] = 1.00
	defense_score_sum += 1.00
	last_action_feedback = "%s (-%d Ki, +%d BP)" % [vanish_lbl, int(vanish_cost), int(roundf(zv_bp_reward))]
	pip_results.append("blocked")
	_spawn_impact_popup(global_position, "%s (-%d Ki, +%d BP)" % [vanish_lbl, int(vanish_cost), int(roundf(zv_bp_reward))], Color(0.25, 0.98, 1.0), true)
	emit_signal("defense_action_resolved", "z_vanish", zone["id"], true, -vanish_cost, zv_bp_reward)
	if _check_ki_break_after_note():
		return

	# Evento Lore 3: Guerra de Z-Vanish sorpresa si el atacante tiene Ki para perseguir
	if phase == DomePhase.DEFENSE_RHYTHM and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var cfg_zv2: KiEconomyConfig = KiEconomyConfig.get_default()
		var zv_chance: float = float(cfg_zv2.melee_z_vanish_war_chance) if cfg_zv2.get("melee_z_vanish_war_chance") != null else 0.50
		var zv_cd_cfg: int = int(cfg_zv2.melee_lore_event_cooldown_melees) if cfg_zv2.get("melee_lore_event_cooldown_melees") != null else 2
		var atk_ki_zv: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		var bp_d: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
		var bp_a: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var atk_zv_cost: float = float(_get_vanish_cost_and_label(attacker).get("cost", 10.0))
		var zv_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "z_vanish",
			"last_event_type": _last_lore_event_type,
			"atk_ki": atk_ki_zv,
			"vanish_cost": atk_zv_cost,
			"bp_ratio": bp_a / bp_d
		})
		if zv_ev == MeleeLoreEventScript.LoreEventType.Z_VANISH_WAR and should_trigger_surprise_lore_event(randf(), zv_chance, _z_vanish_war_cooldown_melees):
			_z_vanish_war_cooldown_melees = zv_cd_cfg
			_start_lore_event(zv_ev, "z_vanish_war")
			return

	# Si no disparó Guerra de Z-Vanish, corta la ráfaga rival e invierte el turno para contraatacar
	if phase == DomePhase.DEFENSE_RHYTHM:
		for h_rem in hits:
			if not h_rem.get("resolved", false):
				h_rem["resolved"] = true
				h_rem["defense_score"] = 1.0
		pending_attack_penalty = 0
		_begin_phase_transition(
			"restart_attacker",
			0.65,
			"%s ¡CONTRAATACA! (-%d Ki)" % [vanish_lbl, int(vanish_cost)],
			Color(0.25, 0.98, 1.0)
		)


func _resolve_hand_block(note: Dictionary, zone: Dictionary, hand_idx: int, timing_grade: String = "GREEN") -> void:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	if is_hammer:
		_resolve_unblocked_hit(note, zone, "🔨 ¡1 MANO ROTA POR MARTILLAZO!")
		return
	if is_v3:
		_resolve_unblocked_hit(note, zone, "🔥 ¡1 MANO ROTA POR V3!")
		return

	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var zone_pos: Vector3 = zone["node"].global_position
	var score: float = 1.0
	var cfg_hb: KiEconomyConfig = KiEconomyConfig.get_default()
	var prof_hb: Dictionary = _get_bp_profile(attacker, defender, is_charged)
	var deflect_reward: float = float(cfg_hb.melee_deflect_ki_reward) if cfg_hb.get("melee_deflect_ki_reward") != null else 16.0
	var atk_to_def_hb: Vector3 = (-_duel_axis if (defender and is_instance_valid(defender) and bool(defender.get("is_player"))) else _duel_axis)
	if atk_to_def_hb.length_squared() < 0.01:
		atk_to_def_hb = -global_transform.basis.z
	atk_to_def_hb = atk_to_def_hb.normalized()

	if is_charged:
		# Cargado rompe el bloqueo de 1 Mano: 65% daño escalado, coste broken_1hand y empuje fuerte (obliga a Guardia X o Parry)
		var broken_dmg: float = 300.0 * 0.65 * attacker_damage_mult * float(prof_hb["damage_scale"])
		var broken_cost: float = clampf((float(cfg_hb.melee_broken_1hand_ki_cost) if cfg_hb.get("melee_broken_1hand_ki_cost") != null else 10.0) * float(prof_hb["ki_mult"]), 5.0, 18.0)
		score = 0.0
		_modify_fighter_ki(defender, -broken_cost)
		_modify_fighter_ki(attacker, -1.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(broken_dmg, Vector3.ZERO)
		if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
			attacker.increase_np(90.0 * float(prof_hb["bp_gain_mult"]))
		if defender and defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(0.55, atk_to_def_hb)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 1.0
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
		_spawn_block_spark(zone_pos, Color(1.0, 0.45, 0.12))
		last_action_feedback = "💥 ¡CARGADO ROMPE 1 MANO! (Usa X o Parry)"
		pip_results.append("hit")
		_spawn_impact_popup(zone_pos, "💥 ¡1 MANO ROTA!", Color(1.0, 0.50, 0.15))
		emit_signal("defense_action_resolved", "hand_block_broken", zone["id"], false, -broken_cost, 0.0)
	elif timing_grade == "YELLOW":
		# Bloqueo Amarillo (Parcial): reduce solo 55% (recibe 45% daño escalado), -4 Ki, 0.45 pto
		var partial_dmg: float = 110.0 * 0.45 * attacker_damage_mult * float(prof_hb["damage_scale"])
		var yellow_cost: float = float(cfg_hb.melee_yellow_block_ki_cost) if cfg_hb.get("melee_yellow_block_ki_cost") != null else 4.0
		score = 0.45
		_modify_fighter_ki(defender, -yellow_cost)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(partial_dmg, Vector3.ZERO)
		if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
			attacker.increase_np(40.0 * float(prof_hb["bp_gain_mult"]))
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 1.0
			AudioActionManager.play_action("common.melee_hit_light", audio_player)
		_spawn_block_spark(zone_pos, Color(1.0, 0.85, 0.18))
		last_action_feedback = "⚠️ ¡BLOQUEO AMARILLO! (-%d Ki, 45%% daño)" % int(yellow_cost)
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "⚠️ ¡AMARILLO! (Parcial)", Color(1.0, 0.85, 0.18))
		emit_signal("defense_action_resolved", "hand_block_yellow", zone["id"], true, -yellow_cost, 0.0)
	else:
		score = 1.00
		var defl_atk_drain: float = float(cfg_hb.melee_deflect_attacker_ki_drain) if cfg_hb.get("melee_deflect_attacker_ki_drain") != null else 4.0
		var defl_bp_gain: float = 150.0 * float(prof_hb["defender_underdog_bp_mult"])
		_modify_fighter_ki(defender, deflect_reward, true)
		_modify_fighter_ki(attacker, -defl_atk_drain)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(defl_bp_gain)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 1.25
			AudioActionManager.play_action("common.melee_hit_light", audio_player)
		_spawn_block_spark(zone_pos, Color(0.25, 1.0, 0.50))
		last_action_feedback = "✋ ¡DESVÍO VERDE! (+%d Ki)" % int(deflect_reward)
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "✋ ¡DESVÍO (+%d Ki)!" % int(deflect_reward), Color(0.35, 1.0, 0.65))
		emit_signal("defense_action_resolved", "hand_block", zone["id"], true, deflect_reward, defl_bp_gain)

	if defender and is_instance_valid(defender) and defender.get("procedural_animator") and not is_charged:
		defender.procedural_animator.trigger_melee_block(0)
	var lat_b: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
	var back_dist: float = 5.4 if is_charged else 3.4
	_trigger_dynamic_melee_mobility(float(note.get("power", 1.0)), is_charged, false, false, defender, attacker, atk_to_def_hb * back_dist + lat_b * 2.2 + Vector3.UP * 1.1, 0.20, false)

	_pulse_defender_hand(hand_idx, 180.0, 0.85, 0.10)
	note["defense_score"] = score
	defense_score_sum += score
	_check_ki_break_after_note()


func _resolve_cross_arm_guard(note: Dictionary, zone: Dictionary) -> void:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	if is_hammer:
		# El Martillazo es inbloqueable: atraviesa Guardia X y solo puede esquivarse con Z-Vanish
		_resolve_unblocked_hit(note, zone, "🔨 ¡MARTILLO ATRAVIESA GUARDIA X!")
		return

	note["resolved"] = true
	consecutive_guard_hits += 1
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var zone_pos: Vector3 = zone["node"].global_position

	var raw_dmg: float = 440.0 if is_v3 else (300.0 if is_charged else 110.0)
	var dmg_pct: float = 0.50 if is_v3 else (0.20 if is_charged else 0.15)
	var final_dmg: float = raw_dmg * dmg_pct
	var cfg_ki: KiEconomyConfig = KiEconomyConfig.get_default()
	var prof_cg: Dictionary = _get_bp_profile(attacker, defender, is_charged or is_v3)
	var final_dmg_scaled: float = final_dmg * attacker_damage_mult * float(prof_cg["damage_scale"])
	if defender and defender.has_method("take_hit"):
		defender.take_hit(final_dmg_scaled, Vector3.ZERO, false)

	_modify_fighter_ki(attacker, 2.0)
	if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
		var press_bp: float = (70.0 if (is_charged or is_v3) else 45.0) * float(prof_cg["bp_gain_mult"])
		attacker.increase_np(press_bp)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.pitch_scale = 0.92 if is_v3 else 1.0
		var act_id := "common.melee_hit_heavy" if is_v3 else "common.block_guard"
		AudioActionManager.play_action(act_id, audio_player)

	_spawn_block_spark(zone_pos, Color(1.0, 0.35, 0.12) if is_v3 else Color(0.2, 0.7, 1.0))
	_pulse_defender_both_hands(180.0 if is_v3 else 130.0, 0.90 if is_v3 else 0.60, 0.16 if is_v3 else 0.10)
	var defender_is_player_g: bool = bool(defender.get("is_player")) if (defender and is_instance_valid(defender)) else false
	var atk_to_def_g: Vector3 = (-_duel_axis if defender_is_player_g else _duel_axis)
	if atk_to_def_g.length_squared() < 0.01:
		atk_to_def_g = -global_transform.basis.z
	atk_to_def_g = atk_to_def_g.normalized()
	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		if is_v3:
			defender.procedural_animator.trigger_hit_flinch(0.70, atk_to_def_g)
		else:
			defender.procedural_animator.trigger_melee_block(1)

	var push_back: Vector3 = atk_to_def_g * (5.2 if is_v3 else 3.2)
	_apply_melee_arena_surge(push_back + Vector3.UP * 0.35, 0.20)

	if is_v3:
		# Guardia X logra frenar el vuelo de V3, pero cuesta -10 Ki + 50% chip + 0 BP + 75% Guard Break
		var g_v3: float = float(cfg_ki.melee_guard_v3_cost) if cfg_ki.get("melee_guard_v3_cost") != null else 10.0
		var ki_cost: float = clampf((g_v3 + float(consecutive_guard_hits - 1) * cfg_ki.melee_guard_escalation) * float(prof_cg["ki_mult"]), 2.0, 28.0)
		_modify_fighter_ki(defender, -ki_cost)
		note["defense_score"] = 0.15
		defense_score_sum += 0.15
		last_action_feedback = "🐢 ¡V3 CONTENIDO CON X! (-%d Ki, 50%% chip)" % int(roundf(ki_cost))
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "🐢 ¡V3 FRENADO! (-%d Ki)" % int(roundf(ki_cost)), Color(1.0, 0.52, 0.16))
		emit_signal("defense_action_resolved", "cross_arm_guard_v3", zone["id"], true, -ki_cost, 0.0)
	else:
		# Modo Tortuga (Nv.1 / Nv.2): gana Ki (+6 / +10 con decaimiento -2, piso +2), poco BP (+15), no roba turno
		var base_turtle_ki: float = (float(cfg_ki.melee_guard_turtle_charged_ki_gain) if cfg_ki.get("melee_guard_turtle_charged_ki_gain") != null else 10.0) if is_charged else (float(cfg_ki.melee_guard_turtle_quick_ki_gain) if cfg_ki.get("melee_guard_turtle_quick_ki_gain") != null else 6.0)
		var turtle_ki_gain: float = maxf(base_turtle_ki - float(consecutive_guard_hits - 1) * 2.0, 2.0)
		_modify_fighter_ki(defender, turtle_ki_gain)
		var cg_def_bp: float = 15.0 * float(prof_cg["defender_underdog_bp_mult"])
		if defender and defender.has_method("increase_np"):
			defender.increase_np(cg_def_bp)
		var g_score: float = 0.35 if is_charged else 0.25
		note["defense_score"] = g_score
		defense_score_sum += g_score
		last_action_feedback = "🐢 ¡CARGADO X! (+%d Ki)" % int(roundf(turtle_ki_gain)) if is_charged else "🐢 GUARDIA X (+%d Ki)" % int(roundf(turtle_ki_gain))
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "🐢 +%d KI" % int(roundf(turtle_ki_gain)), Color(0.30, 0.90, 1.0))
		emit_signal("defense_action_resolved", "cross_arm_guard", zone["id"], true, turtle_ki_gain, cg_def_bp)

	if _check_ki_break_after_note():
		return

	# Evento Lore 4: Desgarre de Guardia sorpresa (75% tras contener V3, o por abuso consecutivo de Guardia X)
	if phase == DomePhase.DEFENSE_RHYTHM and _has_unresolved_notes() and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var gb_cd_cfg: int = int(cfg_ki.melee_lore_event_cooldown_melees) if cfg_ki.get("melee_lore_event_cooldown_melees") != null else 2
		if is_v3:
			if _last_lore_event_type != MeleeLoreEventScript.LoreEventType.GUARD_PRESSURE_BREAK and should_trigger_surprise_lore_event(randf(), 0.75, _guard_break_cooldown_melees):
				_guard_break_cooldown_melees = gb_cd_cfg
				_start_lore_event(MeleeLoreEventScript.LoreEventType.GUARD_PRESSURE_BREAK, "guard_break")
		else:
			var def_ki_g: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 50.0
			var gb_chance: float = float(cfg_ki.melee_guard_break_chance) if cfg_ki.get("melee_guard_break_chance") != null else 0.55
			var gb_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
				"trigger_source": "guard_abuse",
				"last_event_type": _last_lore_event_type,
				"consecutive_guard_x": consecutive_guard_hits,
				"def_ki": def_ki_g,
				"bp_ratio": float(prof_cg["raw_ratio"])
			})
			if gb_ev == MeleeLoreEventScript.LoreEventType.GUARD_PRESSURE_BREAK and should_trigger_surprise_lore_event(randf(), gb_chance, _guard_break_cooldown_melees):
				_guard_break_cooldown_melees = gb_cd_cfg
				_start_lore_event(gb_ev, "guard_break")


func _cut_melee_hammer_defended(p_def: Node3D, p_atk: Node3D, chip_dmg: float) -> void:
	if not is_active:
		return
	is_active = false
	_kill_surge_tween()
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	phase = DomePhase.COMPLETED
	_hide_all_charge_spheres()
	_reset_all_timing_rings()
	for f_cut in [p_def, p_atk]:
		if f_cut and is_instance_valid(f_cut):
			f_cut.set("is_in_bullet_time", false)
			f_cut.set("is_blocking", false)
			f_cut.set("active_target_dome", null)
	_custom_separation_dist = 8.5
	_custom_separation_reason = "🛡️ Martillazo frenado: separación táctica."
	_spawn_impact_popup(global_position, "🛡️ ¡MARTILLO FRENADO! (-%d BP)" % int(chip_dmg), Color(0.4, 0.9, 1.0), true)
	emit_signal("bullet_time_completed", [], Vector3.ZERO)
	queue_free()


func _resolve_unblocked_hit(note: Dictionary, zone: Dictionary, custom_popup: String = "") -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	_round_unblocked_hits_taken += 1
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var is_sonic_note: bool = String(note.get("tier", "")) == "SONICO"
	var tier_name_uh: String = String(note.get("tier", "SOLIDO")).to_upper()
	var is_soft_jab: bool = (not is_charged and not is_v3 and not is_hammer and tier_name_uh == "SUAVE")
	var prof_uh: Dictionary = _get_bp_profile(attacker, defender, is_charged or is_v3 or is_hammer or is_sonic_note)
	var tier_mult: float = float(note.get("tier_dmg_mult", 1.0))
	var zone_pos: Vector3 = zone["node"].global_position
	var base_dmg: float = 580.0 if is_hammer else (440.0 if is_v3 else (300.0 if is_charged else 110.0))
	var charge_base_ref: float = 2.40 if (is_v3 or is_hammer) else (1.65 if is_charged else 1.00)
	var note_power: float = float(note.get("power", charge_base_ref))
	var raw_dmg: float = base_dmg * clampf(note_power / charge_base_ref, 0.75, 1.55) * tier_mult

	var cfg_uh: KiEconomyConfig = KiEconomyConfig.get_default()
	var base_def_ki_loss: float = float(cfg_uh.melee_hit_taken_heavy_ki_drain) if (is_v3 or is_hammer) else (float(cfg_uh.melee_hit_taken_charged_ki_drain) if is_charged else float(cfg_uh.melee_hit_taken_quick_ki_drain))
	var def_ki_loss: float = -clampf(base_def_ki_loss * float(prof_uh["ki_mult"]), 3.0, 24.0)
	_modify_fighter_ki(defender, def_ki_loss)
	# Reembolso táctico diferido: se otorga al atacante ÚNICAMENTE cuando el golpe conecta limpio
	var note_refund: float = float(note.get("ki_refund", 0.0))
	if note_refund > 0.0:
		_modify_fighter_ki(attacker, note_refund)
	if is_sonic_note:
		_round_clean_sonic_hits += 1
	if is_charged or is_v3:
		_round_clean_charged_hits += 1

	var raw_lv: Variant = note.get("launch_vec", null)
	var real_launch_vec: Vector3 = raw_lv if (raw_lv is Vector3 and (raw_lv as Vector3).length_squared() > 0.1) else _compute_zone_launch_vector(int(zone["id"]), is_hammer, 11.0 if is_v3 else (8.5 if is_charged else 5.5), note.get("swing_dir", Vector3.ZERO) as Vector3)
	last_impact_vector = real_launch_vec
	var surge_dir: Vector3 = real_launch_vec.normalized()
	var surge_mag: float = 8.2 if (is_charged or is_v3 or is_hammer) else 5.5
	if not is_soft_jab:
		_trigger_dynamic_melee_mobility(note_power, is_charged, is_v3, is_hammer, attacker, defender, surge_dir * surge_mag, 0.22, real_launch_vec.y > 4.0)

	var atk_to_def_uh: Vector3 = (-_duel_axis if (defender and is_instance_valid(defender) and bool(defender.get("is_player"))) else _duel_axis)
	if atk_to_def_uh.length_squared() < 0.01:
		atk_to_def_uh = -global_transform.basis.z
	atk_to_def_uh = atk_to_def_uh.normalized()
	if defender and is_instance_valid(defender):
		var raw_dmg_scaled: float = raw_dmg * attacker_damage_mult * float(prof_uh["damage_scale"])
		if defender.has_method("take_hit"):
			defender.take_hit(raw_dmg_scaled, atk_to_def_uh, not is_soft_jab)
		if defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(0.75 if (is_hammer or is_v3) else (0.25 if is_soft_jab else 0.45), atk_to_def_uh)

	if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
		# Ganancia ofensiva justa sobre daño BASE x freno anti-snowball (evita que el líder escale exponencialmente pero sienta avance)
		attacker.increase_np(raw_dmg * 0.90 * float(prof_uh["bp_gain_mult"]))

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.pitch_scale = 1.0
		var act_id := "common.melee_hit_heavy" if (is_charged or is_v3 or is_hammer) else "common.melee_hit_light"
		AudioActionManager.play_action(act_id, audio_player)

	_pulse_defender_both_hands(200.0, 0.80, 0.14)
	_spawn_hit_spark(zone_pos)

	note["defense_score"] = 0.0
	var refund_tag: String = " (+%d Ki)" % int(note_refund) if note_refund > 0.0 else ""
	var pwr_lbl: String = ("🔥 V3 x%.1f%s" % [note_power, refund_tag]) if is_v3 else (("⚡ CARGADO x%.1f%s" % [note_power, refund_tag]) if is_charged else ("💥 RÁPIDO x%.1f%s" % [note_power, refund_tag]))
	if is_hammer:
		pwr_lbl = "🔨 MARTILLAZO x%.1f%s" % [note_power, refund_tag]
	last_action_feedback = custom_popup if not custom_popup.is_empty() else pwr_lbl
	pip_results.append("hit")
	_spawn_impact_popup(zone_pos, custom_popup if not custom_popup.is_empty() else pwr_lbl, Color(1.0, 0.42, 0.15))
	if is_charged or is_v3 or is_hammer:
		_spawn_parry_shockwave(zone_pos)
		if is_hammer and is_inside_tree() and get_tree():
			KiSmokeFX.spawn_smoke(get_tree(), zone_pos, 1.2)
	emit_signal("defense_action_resolved", "hit_taken", zone["id"], false, def_ki_loss, 0.0)

	var has_remaining_notes: bool = _has_unresolved_notes()

	if is_hammer:
		_trigger_finisher_and_close("hammer_strike", float(note.get("velocity", 4.0)))
		return
	elif is_v3:
		var v3_mode: String = "charged_v3_up" if (String(note.get("v3_launch_mode", "BACK")) == "UP" or real_launch_vec.y > 4.0) else "charged_v3_back"
		if v3_mode == "charged_v3_up" and _last_lore_event_type != MeleeLoreEventScript.LoreEventType.METEOR_SMASH and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
			var ms_chance_v3: float = float(cfg_uh.melee_meteor_smash_v3_chance) if cfg_uh.get("melee_meteor_smash_v3_chance") != null else 0.75
			var ms_cd_v3: int = int(cfg_uh.melee_lore_event_cooldown_melees) if cfg_uh.get("melee_lore_event_cooldown_melees") != null else 2
			var atk_ki_v3: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
			var ms_ev_v3: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
				"trigger_source": "combo_end",
				"last_event_type": _last_lore_event_type,
				"has_v3_up": true,
				"sonic_hits": _round_clean_sonic_hits,
				"hits_landed": _round_unblocked_hits_taken,
				"atk_ki": atk_ki_v3
			})
			if ms_ev_v3 == MeleeLoreEventScript.LoreEventType.METEOR_SMASH and should_trigger_surprise_lore_event(randf(), ms_chance_v3, _meteor_smash_cooldown_melees):
				_meteor_smash_cooldown_melees = ms_cd_v3
				_pending_finisher_mode = ""
				_start_lore_event(ms_ev_v3, "combo_end")
				return
		_trigger_finisher_and_close(v3_mode, float(note.get("velocity", 3.5)))
		return

	if _check_ki_break_after_note():
		return

	# Evento Lore 6: Intercambio Sónico Z-Burst habilitado para ambos (jugador e IA) tras CONECTAR golpes reales limpios
	if has_remaining_notes and not is_hammer and attacker and is_instance_valid(attacker):
		var atk_ki_sb: float = float(attacker.get("current_ki")) if attacker.get("current_ki") != null else 0.0
		if not _sonic_burst_used_this_dome and not _sonic_burst_rolled_this_round and _sonic_burst_cooldown_melees <= 0 and _round_unblocked_hits_taken >= 3 and atk_ki_sb >= 18.0 and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
			var is_fur_t: bool = bool(attacker.get("is_in_furia")) or (int(attacker.get("current_transformation_index")) if attacker.get("current_transformation_index") != null else -1) >= 0
			var sz_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
				"trigger_source": "combo_mid",
				"last_event_type": _last_lore_event_type,
				"hits_landed": _round_unblocked_hits_taken,
				"max_hits": maxi(defense_round_total_hits, hits.size()),
				"sonic_hits": _round_clean_sonic_hits,
				"charged_hits": _round_clean_charged_hits,
				"is_furia_or_trans": is_fur_t,
				"atk_ki": atk_ki_sb
			})
			if sz_ev == MeleeLoreEventScript.LoreEventType.SONIC_Z_BURST:
				_sonic_burst_rolled_this_round = true
				var sb_prob: float = 0.28
				if is_fur_t:
					sb_prob += 0.12
				if _round_clean_sonic_hits >= 4 or (_round_clean_sonic_hits >= 3 and _round_clean_charged_hits >= 1):
					sb_prob += 0.10
				sb_prob = clampf(sb_prob, 0.20, 0.50)
				if randf() < sb_prob:
					_sonic_burst_used_this_dome = true
					_sonic_burst_cooldown_melees = 3
					_start_lore_event(sz_ev, "combo_mid")
					return


func _resolve_ai_defense(note: Dictionary, zone: Dictionary) -> void:
	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var in_zenkai: bool = bool(defender.get("is_in_zenkai_state")) if defender else false
	var def_ki: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 50.0
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 9000.0, 100.0)
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 9000.0, 100.0)
	var r_bp: float = bp_def / bp_atk
	var cfg_ai_d: KiEconomyConfig = KiEconomyConfig.get_default()
	var kiai_cost: float = float(cfg_ai_d.melee_explosive_wave_cost) if cfg_ai_d.get("melee_explosive_wave_cost") != null else 16.0
	var vanish_cost: float = float(_get_vanish_cost_and_label(defender).get("cost", cfg_ai_d.melee_vanish_cost))
	var guard_cost: float = float(cfg_ai_d.melee_hammer_guard_cost) if is_hammer else (float(cfg_ai_d.melee_guard_charged_cost) if is_charged else float(cfg_ai_d.melee_guard_quick_cost))

	# Onda Kiai de emergencia disponible también para la IA si recibe 2+ golpes limpios con Ki suficiente (máx. 1 por cúpula)
	if not _explosive_wave_used_this_dome and _round_unblocked_hits_taken >= 2 and def_ki >= kiai_cost and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")) and randf() < 0.35:
		var ew_ai: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "explosive_wave_input",
			"def_ki": def_ki,
			"consecutive_hits_taken": _round_unblocked_hits_taken
		})
		if ew_ai == MeleeLoreEventScript.LoreEventType.EXPLOSIVE_WAVE:
			_explosive_wave_used_this_dome = true
			_start_lore_event(ew_ai, "explosive_wave")
			return

	# Si la IA no tiene Ki suficiente, no puede frenar ataques
	if def_ki <= 5.0:
		_resolve_unblocked_hit(note, zone)
		return

	var roll: float = randf()
	var acc: float = 0.0
	if is_hammer:
		var vanish_w_h: float = (0.38 if in_zenkai else 0.24) if def_ki >= vanish_cost else 0.0
		if vanish_w_h > 0.0 and roll < vanish_w_h:
			_resolve_defensive_z_vanish(note, zone)
			return
		_resolve_unblocked_hit(note, zone)
	elif is_v3:
		var parry_w: float = 0.16 if in_zenkai else 0.0
		var clash_w: float = 0.24 if r_bp >= 0.72 else 0.0
		var vanish_w: float = 0.18 if def_ki >= vanish_cost else 0.0
		var guard_w_v3: float = 0.16 if def_ki >= guard_cost else 0.0
		acc += parry_w
		if parry_w > 0.0 and roll < acc:
			_resolve_perfect_parry(note, zone)
			return
		acc += clash_w
		if clash_w > 0.0 and roll < acc:
			_resolve_fist_clash(note, zone, 0)
			return
		acc += vanish_w
		if vanish_w > 0.0 and roll < acc:
			_resolve_defensive_z_vanish(note, zone)
			return
		acc += guard_w_v3
		if guard_w_v3 > 0.0 and roll < acc:
			_resolve_cross_arm_guard(note, zone)
			return
		_resolve_unblocked_hit(note, zone)
	elif is_charged:
		var parry_w: float = 0.12 if in_zenkai else 0.0
		var guard_w: float = 0.40 if def_ki >= guard_cost else 0.0
		var clash_w: float = 0.18 if r_bp >= 0.70 else 0.0
		var vanish_w_c: float = 0.12 if def_ki >= vanish_cost else 0.0
		acc += parry_w
		if parry_w > 0.0 and roll < acc:
			_resolve_perfect_parry(note, zone)
			return
		acc += guard_w
		if guard_w > 0.0 and roll < acc:
			_resolve_cross_arm_guard(note, zone)
			return
		acc += clash_w
		if clash_w > 0.0 and roll < acc:
			_resolve_fist_clash(note, zone, 0)
			return
		acc += vanish_w_c
		if vanish_w_c > 0.0 and roll < acc:
			_resolve_defensive_z_vanish(note, zone)
			return
		_resolve_unblocked_hit(note, zone)
	else:
		# Nv.1 Rápido: SOLO Bloqueo 1 Mano o Guardia X Tortuga (sin Parry, Choque ni Z-Vanish)
		var deflect_w: float = 0.46
		var guard_w: float = 0.24
		acc += deflect_w
		if roll < acc:
			var ai_grade: String = "YELLOW" if randf() < 0.20 else "GREEN"
			_resolve_hand_block(note, zone, 0, ai_grade)
			return
		acc += guard_w
		if roll < acc:
			_resolve_cross_arm_guard(note, zone)
			return
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
	_has_prev_atk_local = false
	hand_must_retract = [false, false]
	_reset_all_timing_rings()
	_hide_all_charge_spheres()

	if p_victim and is_instance_valid(p_victim):
		p_victim.set("is_blocking", false)
		p_victim.set("is_guard_broken", true)
		p_victim.set("guard_break_timer", 2.0)

	# Mostrar únicamente la caja central circular gigante dorada/roja
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		if z_node and is_instance_valid(z_node):
			if z_id == 1:
				_set_single_zone_shape(zone, "ATTACK")
				z_node.visible = true
				z_node.scale = Vector3.ONE * 1.65
				_tint_zone_shapes(zone, Color(1.0, 0.25, 0.1, 0.95), Color(1.0, 0.75, 0.1), 3.2, Color(1.0, 1.0, 1.0, 0.95))
				var slbl: Label3D = zone.get("step_label") as Label3D
				if slbl:
					slbl.text = "💥"
					slbl.visible = true
			else:
				z_node.visible = false

	var winner_is_player: bool = bool(p_winner.get("is_player")) if p_winner else false
	ki_break_timer = 3.5 if winner_is_player else 0.90
	if header_label and is_instance_valid(header_label):
		header_label.modulate = Color(1.0, 0.25, 0.15)
		if winner_is_player:
			header_label.text = "💥 ¡RIVAL SIN KI! ¡INDEFENSO!\n¡GOLPEA EL CÍRCULO CENTRAL (Grip+Trigger) PARA LANZARLO!"
		else:
			header_label.text = "⚠️ ¡TE QUEDASTE SIN KI! ¡GUARDIA ROTA!\n¡ATAQUE FUERTE IMBLOQUEABLE ENTRANTE!"


func _process_unblockable_ki_break(delta: float) -> void:
	_update_dome_transform()
	ki_break_timer -= delta

	var winner_is_player: bool = bool(ki_break_attacker.get("is_player")) if (ki_break_attacker and is_instance_valid(ki_break_attacker)) else false
	if winner_is_player:
		_update_controller_velocities(delta)
		_update_fist_states(delta, false)
		var punch_fwd_kb: Vector3 = _get_punch_forward_world()
		var zone_pos: Vector3 = target_zones[1]["node"].global_position if target_zones.size() > 1 else global_position
		for h_idx in [0, 1]:
			if is_fist_closed[h_idx]:
				var ctrl: XRController3D = _get_controller("LeftHand" if h_idx == 0 else "RightHand")
				var vel_vec_kb: Vector3 = left_velocity if h_idx == 0 else right_velocity
				var vel_len: float = vel_vec_kb.length()
				var fwd_len_kb: float = vel_vec_kb.dot(punch_fwd_kb)
				if ctrl and ctrl.global_position.distance_to(zone_pos) <= 0.34 and fwd_len_kb >= 0.85 and vel_len >= 1.10:
					_execute_unblockable_ki_break_hit(vel_len)
					return

	if ki_break_timer <= 0.0:
		_execute_unblockable_ki_break_hit(4.2)


func _execute_unblockable_ki_break_hit(swing_vel: float) -> void:
	attacker = ki_break_attacker
	defender = ki_break_victim
	last_impact_vector = _compute_zone_launch_vector(1, false, 13.0)
	var prof_kb: Dictionary = _get_bp_profile(ki_break_attacker, ki_break_victim, true)
	var atk_to_def_kb: Vector3 = (-_duel_axis if (ki_break_victim and is_instance_valid(ki_break_victim) and bool(ki_break_victim.get("is_player"))) else _duel_axis)
	if atk_to_def_kb.length_squared() < 0.01:
		atk_to_def_kb = Vector3.BACK
	atk_to_def_kb = atk_to_def_kb.normalized()
	if ki_break_victim and is_instance_valid(ki_break_victim) and ki_break_victim.has_method("take_hit"):
		ki_break_victim.take_hit(500.0 * float(prof_kb["damage_scale"]), atk_to_def_kb)
	if ki_break_attacker and is_instance_valid(ki_break_attacker) and ki_break_attacker.has_method("increase_np"):
		ki_break_attacker.increase_np(250.0 * float(prof_kb["bp_gain_mult"]))
	if target_zones.size() > 1:
		_spawn_hit_spark(target_zones[1]["node"].global_position)

	_trigger_finisher_and_close("ki_break_launch", swing_vel)


func _trigger_finisher_and_close(finisher_name: String, swing_vel: float) -> void:
	if not is_active:
		return
	is_active = false
	_kill_surge_tween()
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
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


func _has_unresolved_notes() -> bool:
	for h_rem in hits:
		if not h_rem.get("resolved", false):
			return true
	return false


func _set_target_zones_visible(v: bool) -> void:
	for zone in target_zones:
		var zn: Node3D = zone.get("node") as Node3D
		if zn and is_instance_valid(zn):
			zn.visible = v


func _start_lore_event(event_type: int, return_mode: String) -> void:
	if not is_active or not _lore_ctrl or bool(_lore_ctrl.get("is_event_active")):
		return
	var prev_phase: DomePhase = phase
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	_last_lore_event_type = event_type
	_lore_return_mode = return_mode
	_has_prev_atk_local = false
	_has_prev_def_local = false
	phase = DomePhase.LORE_EVENT
	_reset_all_timing_rings()
	_hide_all_charge_spheres()
	_set_target_zones_visible(false)
	if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		melee_hud_anchor.visible = true
		if header_label and is_instance_valid(header_label):
			header_label.visible = false
	elif header_label and is_instance_valid(header_label):
		header_label.visible = false
	if action_card_anchor and is_instance_valid(action_card_anchor):
		action_card_anchor.visible = false
	var started: bool = bool(_lore_ctrl.call("start_event", event_type, self, attacker, defender))
	if not started:
		phase = prev_phase
		_set_target_zones_visible(true)
		if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
			melee_hud_anchor.visible = true
		if header_label and is_instance_valid(header_label):
			header_label.visible = true
		if action_card_anchor and is_instance_valid(action_card_anchor):
			action_card_anchor.visible = true
	elif event_type == MeleeLoreEventScript.LoreEventType.FIST_FLURRY_CLASH:
		_flurry_clash_cooldown_melees = 2


func _process_lore_event(delta: float) -> void:
	if not _lore_ctrl or not bool(_lore_ctrl.get("is_event_active")):
		return
	var p_is_atk: bool = attacker != null and is_instance_valid(attacker) and bool(attacker.get("is_player"))
	var l_ctrl: XRController3D = _get_controller("LeftHand")
	var r_ctrl: XRController3D = _get_controller("RightHand")
	if p_is_atk:
		_update_controller_velocities(delta)
		_lore_ctrl.call("process_event", delta, l_ctrl, r_ctrl, left_velocity, right_velocity)
	else:
		_update_defender_velocities(delta)
		_lore_ctrl.call("process_event", delta, l_ctrl, r_ctrl, def_left_velocity, def_right_velocity)


func _close_dome_with_separation(sep_dist: float, reason_msg: String = "") -> void:
	if not is_active:
		return
	_custom_separation_dist = clampf(sep_dist, 4.5, 16.0)
	_custom_separation_reason = reason_msg
	is_active = false
	_kill_surge_tween()
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
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


func _on_lore_event_finished(event_type: int, outcome: Dictionary) -> void:
	if not is_active:
		return
	var act: String = String(outcome.get("action", "complete_normal"))
	if act == "meteor_crater":
		is_active = false
		_kill_surge_tween()
		_hitstop_end_msec = 0
		if Engine.time_scale < 1.0:
			Engine.time_scale = 1.0
		phase = DomePhase.COMPLETED
		_hide_all_charge_spheres()
		_reset_all_timing_rings()
		var win_m: Node3D = outcome.get("winner", attacker) as Node3D
		var vic_m: Node3D = outcome.get("victim", defender) as Node3D
		var c_pos: Vector3 = outcome.get("crater_pos", global_position)
		if win_m and is_instance_valid(win_m) and outcome.has("crater_stun"):
			win_m.set_meta("pending_meteor_crater_stun", float(outcome.get("crater_stun", 3.5)))
		emit_signal("meteor_smash_completed", win_m, vic_m, c_pos)
		queue_free()
		return
	elif act == "winner_offense":
		_set_target_zones_visible(true)
		if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
			melee_hud_anchor.visible = true
		if header_label and is_instance_valid(header_label):
			header_label.visible = true
		if action_card_anchor and is_instance_valid(action_card_anchor):
			action_card_anchor.visible = true
		var winner: Node3D = outcome.get("winner") as Node3D
		var loser: Node3D = outcome.get("loser") as Node3D
		if winner and is_instance_valid(winner) and loser and is_instance_valid(loser):
			attacker = winner
			defender = loser
		_comeback_momentum_active = bool(outcome.get("comeback_momentum", false))
		var bonus_h: int = int(outcome.get("bonus_hits", 0))
		pending_attack_penalty = -bonus_h
		var w_is_p: bool = attacker != null and bool(attacker.get("is_player"))
		var init_msg: String = "🔥 ¡TOMAS LA INICIATIVA!" if w_is_p else "🔥 ¡EL RIVAL TOMA LA INICIATIVA!"
		_begin_phase_transition("continue_offense", 0.45, init_msg, Color(1.0, 0.78, 0.20))
		return
	elif act == "separate":
		_close_dome_with_separation(float(outcome.get("distance", 9.0)), String(outcome.get("reason", "")))
		return
	elif act == "launch":
		var victim: Node3D = outcome.get("victim") as Node3D
		if victim == attacker and defender != null:
			var tmp_a: Node3D = attacker
			attacker = defender
			defender = tmp_a
		var launch_vel: float = 4.0
		if event_type == MeleeLoreEventScript.LoreEventType.SONIC_Z_BURST:
			var burst_hits: int = int(outcome.get("hits", 0))
			if burst_hits >= 3 and attacker and is_instance_valid(attacker):
				var prof_sb_fin: Dictionary = _get_bp_profile(attacker, defender, true)
				_modify_fighter_ki(attacker, 10.0)
				if attacker.has_method("increase_np"):
					attacker.increase_np(200.0 * float(prof_sb_fin["bp_gain_mult"]))
				_spawn_impact_popup(global_position, "🔥 ¡Z-BURST 3/3 PERFECTO! (+10 Ki)", Color(1.0, 0.90, 0.22), true)
				launch_vel = 4.6
		last_impact_vector = _compute_zone_launch_vector(1, false, 12.0)
		_trigger_finisher_and_close("charged_v3_back", launch_vel)
		return

	# Caso complete_normal
	_set_target_zones_visible(true)
	if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		melee_hud_anchor.visible = true
	if header_label and is_instance_valid(header_label):
		header_label.visible = true
	if action_card_anchor and is_instance_valid(action_card_anchor):
		action_card_anchor.visible = true
	if _lore_return_mode in ["combo_mid", "guard_break", "z_vanish_war"] and _has_unresolved_notes():
		_resync_unresolved_defense_notes(0.70)
		phase = DomePhase.DEFENSE_RHYTHM
	else:
		evaluate_round_outcome()


## Evalúa si los golpes fueron mayormente bloqueados (invierte roles) o conectados (continúa ofensiva)
func evaluate_round_outcome() -> void:
	if not is_active:
		return
	_tutorial_controls_shown = true
	_comeback_momentum_active = false
	if _check_ki_break_after_note():
		_declared_full_combo = false
		return

	var was_full_combo: bool = _declared_full_combo
	_declared_full_combo = false

	var n_hits_chk: int = maxi(defense_round_total_hits, hits.size())
	var scores: Array[float] = []
	var clean_hits: int = 0
	var clean_soft_hits: int = 0
	var clean_charged_hits: int = 0
	var clean_sonic_hits: int = 0
	var has_v3_up: bool = false
	for h_chk in hits:
		var sc: float = float(h_chk.get("defense_score", 0.0))
		scores.append(sc)
		if h_chk.get("resolved", false) and sc <= 0.05:
			clean_hits += 1
			var z_chk: int = int(h_chk.get("zone_id", -1))
			var tier_chk: String = String(h_chk.get("tier", "SOLIDO")).to_upper()
			var is_chg_chk: bool = bool(h_chk.get("is_charged", false)) or bool(h_chk.get("is_charged_v3", false)) or bool(h_chk.get("is_hammer", false))
			var is_sonic_chk: bool = tier_chk == "SONICO"
			if is_sonic_chk:
				clean_sonic_hits += 1
			if is_chg_chk:
				clean_charged_hits += 1
			elif tier_chk == "SUAVE":
				clean_soft_hits += 1
			if bool(h_chk.get("is_charged_v3", false)) and String(h_chk.get("v3_launch_mode", "")) == "UP":
				has_v3_up = true
			elif z_chk == 0 and (bool(h_chk.get("is_charged", false)) or is_sonic_chk):
				has_v3_up = true

	# Bono Momentum (+18 Ki): diferido hasta la evaluación real tras conectar mayoría limpia del combo completo
	if was_full_combo and n_hits_chk >= 2 and clean_hits >= ceili(float(n_hits_chk) * 0.60):
		var cfg_mom: KiEconomyConfig = KiEconomyConfig.get_default()
		var momentum_bonus: float = float(cfg_mom.melee_dome_complete_ki_bonus) if cfg_mom.get("melee_dome_complete_ki_bonus") != null else 18.0
		_modify_fighter_ki(attacker, momentum_bonus)
		_spawn_impact_popup(global_position, "⚡ +%d KI MOMENTUM!" % int(momentum_bonus), Color(0.35, 0.96, 1.0))

	# Regla #1 (Jabs sin intención / golpes normales sin Cargado ni Sónico): el defensor absorbe y toma el turno ofensivo
	if should_jab_lack_intent_turnover(clean_hits, clean_soft_hits, clean_charged_hits, clean_sonic_hits):
		pending_attack_penalty = 0
		_begin_phase_transition(
			"restart_attacker",
			0.65,
			"😤 ¡GOLPES SIN INTENCIÓN! ¡EL RIVAL ABSORBE Y ATACA!",
			Color(0.25, 0.95, 1.0)
		)
		return

	# Evento Lore 2: Caída del Meteoro sorpresa (excluyendo Martillazo; si no dispara, respeta _pending_finisher_mode V3)
	if _pending_finisher_mode != "hammer_strike" and _last_lore_event_type != MeleeLoreEventScript.LoreEventType.METEOR_SMASH and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var cfg_ms: KiEconomyConfig = KiEconomyConfig.get_default()
		var ms_chance: float = (float(cfg_ms.melee_meteor_smash_v3_chance) if cfg_ms.get("melee_meteor_smash_v3_chance") != null else 0.75) if has_v3_up else (float(cfg_ms.melee_meteor_smash_chance) if cfg_ms.get("melee_meteor_smash_chance") != null else 0.55)
		var ms_cd_cfg: int = int(cfg_ms.melee_lore_event_cooldown_melees) if cfg_ms.get("melee_lore_event_cooldown_melees") != null else 2
		var atk_ki_end: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		var m_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "combo_end",
			"last_event_type": _last_lore_event_type,
			"has_v3_up": has_v3_up,
			"sonic_hits": clean_sonic_hits,
			"hits_landed": clean_hits,
			"atk_ki": atk_ki_end
		})
		if m_ev == MeleeLoreEventScript.LoreEventType.METEOR_SMASH and should_trigger_surprise_lore_event(randf(), ms_chance, _meteor_smash_cooldown_melees):
			_meteor_smash_cooldown_melees = ms_cd_cfg
			_pending_finisher_mode = ""
			_start_lore_event(m_ev, "combo_end")
			return

	if _pending_finisher_mode != "":
		var fin_mode: String = _pending_finisher_mode
		var fin_vel: float = _pending_finisher_vel
		_pending_finisher_mode = ""
		_trigger_finisher_and_close(fin_mode, fin_vel)
		return

	# Secuencia Anime: Intercambio Simultáneo impredecible tras 1+ rondas con BP parejo (45%) o >=2 rondas (55%)
	_rounds_completed_in_dome += 1
	if not _sim_used_this_dome and _sim_exchange_cooldown_melees <= 0 and attacker and defender and is_instance_valid(attacker) and is_instance_valid(defender):
		var a_ki_s: float = float(attacker.get("current_ki")) if attacker.get("current_ki") != null else 0.0
		var d_ki_s: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
		if a_ki_s >= 18.0 and d_ki_s >= 18.0:
			var a_bp_s: float = maxf(float(attacker.get("current_np")) if attacker.get("current_np") != null else 10000.0, 100.0)
			var d_bp_s: float = maxf(float(defender.get("current_np")) if defender.get("current_np") != null else 10000.0, 100.0)
			var bp_r_s: float = a_bp_s / d_bp_s
			var bp_even: bool = bp_r_s >= 0.80 and bp_r_s <= 1.25
			var sim_prob: float = 0.45 if (bp_even and _rounds_completed_in_dome >= 1) else (0.55 if _rounds_completed_in_dome >= 2 else 0.0)
			if sim_prob > 0.0 and randf() < sim_prob:
				_sim_used_this_dome = true
				_sim_exchange_cooldown_melees = 2
				_begin_phase_transition("start_simultaneous", 0.55, "⚡🔥 ¡INTERCAMBIO SIMULTÁNEO ANIME! 🔥⚡\n⭕ ATACA Y ⬜ BLOQUEA A LA VEZ", Color(1.0, 0.88, 0.18))
				return

	var dec: Dictionary = compute_round_outcome_decision(scores, clash_penalty_hits, max_allowed_hits)
	if bool(dec.get("turnover", false)):
		pending_attack_penalty = 0
		var pct: int = int(roundf((float(dec.get("defense_score_sum", defense_score_sum)) / float(maxi(n_hits_chk, 1))) * 100.0))
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


# ==============================================================================
# FASE 3B: INTERCAMBIO SIMULTÁNEO ANIME (⭕ ATAQUE + ⬜ DEFENSA + EXPLOSIÓN EN CHOQUE)
# ==============================================================================

func start_simultaneous_exchange() -> void:
	var pair: Array[Node3D] = _get_player_and_ai()
	if not pair[0] or not pair[1]:
		evaluate_round_outcome()
		return
	phase = DomePhase.SIMULTANEOUS_EXCHANGE
	hits.clear()
	_hide_all_charge_spheres()
	_reset_all_timing_rings()
	_sim_nodes.clear()
	_sim_player_hits_taken = 0
	_sim_enemy_hits_taken = 0
	_sim_clash_count = 0
	_sim_spawn_timer = 0.15
	_sim_duration = 12.0
	_sim_hand_retract = [false, false]
	_sim_last_hit_local = [Vector3.ZERO, Vector3.ZERO]
	_sim_last_hit_depth = [0.0, 0.0]
	_sim_origin_depth = [0.0, 0.0]
	_sim_origin_local = [Vector3.ZERO, Vector3.ZERO]
	_sim_origin_init = [false, false]
	_sim_last_impact_zone = 1
	_has_prev_def_local = false
	def_left_velocity = Vector3.ZERO
	def_right_velocity = Vector3.ZERO
	def_grip_l = false
	def_grip_r = false
	def_trig_l = false
	def_trig_r = false
	prev_grip_l = false
	prev_grip_r = false
	prev_trig_l = false
	prev_trig_r = false
	buffer_grip_timer_l = 0.0
	buffer_grip_timer_r = 0.0
	buffer_trig_timer_l = 0.0
	buffer_trig_timer_r = 0.0
	_trig_press_age_l = 0.0
	_trig_press_age_r = 0.0
	if pair[0].has_method("set"):
		pair[0].set("is_blocking", false)
	if pair[1].has_method("set"):
		pair[1].set("is_blocking", false)
	last_action_feedback = ""
	_last_role_is_attack = -1

	if _action_card_label and is_instance_valid(_action_card_label):
		var cfg_sim_card: KiEconomyConfig = KiEconomyConfig.get_default()
		var sim_q_cost: int = int(cfg_sim_card.melee_quick_cost) if cfg_sim_card.get("melee_quick_cost") != null else 3
		var sim_cl_ki: int = int(cfg_sim_card.melee_sim_clash_ki_reward) if cfg_sim_card.get("melee_sim_clash_ki_reward") != null else 8
		if _action_card_border_mat:
			_action_card_border_mat.albedo_color = Color(1.0, 0.85, 0.18, 0.95)
		_action_card_label.modulate = Color(1.0, 0.96, 0.72)
		_action_card_label.text = "⚡ INTERCAMBIO SIMULTÁNEO ANIME\n• Golpea ⭕/💥 con puño (G+T): -%d Ki | 💥 Choque = +%d Ki ambos (¡puede desatar Ráfaga!)\n• Bloquea ⬜ con Trigger (Verde) o G+T rápido (¡CHOQUE!) / Dorado (¡PARRY!)\n• Gana el primero en 4 golpes, Parry o dejar sin Ki!" % [sim_q_cost, sim_cl_ki]

	_spawn_simultaneous_node("ATTACK")
	_spawn_simultaneous_node("DEFEND")
	_sync_simultaneous_zone_visuals()
	_refresh_header_hud()


func _spawn_simultaneous_node(forced_role: String = "") -> void:
	if _sim_nodes.size() >= 3:
		return
	var used: Array[int] = []
	for sn in _sim_nodes:
		used.append(int(sn["zone_id"]))
	var free_ids: Array[int] = []
	for z_def in ZONE_DEFINITIONS:
		var zid: int = int(z_def["id"])
		if not used.has(zid):
			free_ids.append(zid)
	if free_ids.is_empty():
		return
	var chosen_id: int = free_ids[randi() % free_ids.size()]
	var role: String = forced_role
	if role == "":
		var atk_cnt: int = 0
		var def_cnt: int = 0
		for sn in _sim_nodes:
			if String(sn["role"]) == "ATTACK":
				atk_cnt += 1
			else:
				def_cnt += 1
		role = "DEFEND" if (atk_cnt >= 2 or (def_cnt == 0 and randf() < 0.65)) else "ATTACK"
	if role == "DEFEND":
		var ai_sn: Node3D = _get_player_and_ai()[1]
		var cfg_sn: KiEconomyConfig = KiEconomyConfig.get_default()
		if ai_sn and is_instance_valid(ai_sn):
			_modify_fighter_ki(ai_sn, -float(cfg_sn.melee_quick_cost))
	var max_t: float = 1.55
	if role == "DEFEND":
		var pair_sn: Array[Node3D] = _get_player_and_ai()
		var prof_sn: Dictionary = _get_bp_profile(pair_sn[1], pair_sn[0], false)
		max_t = clampf(1.15 * float(prof_sn["def_time_mult"]), 0.78, 1.55)
	var ai_cl: bool = (role == "ATTACK" and randf() < 0.48)
	_sim_nodes.append({
		"zone_id": chosen_id,
		"role": role,
		"timer": max_t,
		"max_t": max_t,
		"ai_claiming": ai_cl,
		"early_lockout": false
	})


func _sync_simultaneous_zone_visuals() -> void:
	var by_id: Dictionary = {}
	for sn in _sim_nodes:
		by_id[int(sn["zone_id"])] = sn

	for zone in target_zones:
		var zid: int = int(zone["id"])
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
		if not by_id.has(zid):
			_set_single_zone_shape(zone, "NONE")
			if ring and is_instance_valid(ring):
				ring.visible = false
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.visible = false
			continue

		var slot: Dictionary = by_id[zid]
		var role: String = String(slot["role"])
		var t_rem: float = float(slot["timer"])
		var max_t: float = maxf(float(slot["max_t"]), 0.01)
		var is_clash_spot: bool = (role == "ATTACK") and bool(slot["ai_claiming"]) and t_rem <= 0.55
		_set_single_zone_shape(zone, "CLASH" if is_clash_spot else role)

		if role == "ATTACK":
			var col_a: Color = Color(1.0, 0.25, 0.15, 0.95) if is_clash_spot else Color(1.0, 0.62, 0.14, 0.92)
			_tint_zone_shapes(zone, col_a, col_a, 2.6 if is_clash_spot else 1.8, Color(1.0, 0.95, 0.72, 0.95))
			if zone.get("node") and is_instance_valid(zone["node"]):
				(zone["node"] as Node3D).scale = Vector3.ONE * (1.16 if is_clash_spot else 1.04)
			if ring and is_instance_valid(ring):
				ring.visible = is_clash_spot
				if is_clash_spot:
					ring.scale = Vector3.ONE * (1.0 + clampf(t_rem / 0.55, 0.0, 1.0) * 0.9)
					var rm_a := ring.material_override as StandardMaterial3D
					if rm_a:
						rm_a.albedo_color = Color(1.0, 0.92, 0.20, 0.98)
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "💥" if is_clash_spot else "⭕"
				step_lbl.modulate = col_a
				step_lbl.visible = true
		else:
			var col_d: Color
			if bool(slot["early_lockout"]):
				col_d = Color(1.0, 0.08, 0.08, 1.0)
			elif absf(t_rem) <= 0.11:
				col_d = Color(1.0, 0.96, 0.62, 1.0)
			elif absf(t_rem) <= 0.16:
				col_d = Color(0.15, 1.0, 0.35, 1.0)
			elif t_rem <= 0.30 and t_rem > 0.16:
				col_d = Color(1.0, 0.56, 0.08, 0.96)
			else:
				col_d = Color(0.95, 0.16, 0.16, 0.90)
			_tint_zone_shapes(zone, col_d, col_d, 2.3 if absf(t_rem) <= 0.30 else 1.4, Color(1.0, 1.0, 1.0, 0.92))
			if zone.get("node") and is_instance_valid(zone["node"]):
				(zone["node"] as Node3D).scale = Vector3.ONE * 1.10
			if ring and is_instance_valid(ring):
				ring.visible = true
				ring.scale = Vector3.ONE * (1.0 + clampf(maxf(t_rem, 0.0) / max_t, 0.0, 1.0) * 1.55)
				var rm_d := ring.material_override as StandardMaterial3D
				if rm_d:
					rm_d.albedo_color = col_d
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "⬜"
				step_lbl.modulate = col_d
				step_lbl.visible = true


func _resolve_simultaneous_clash(p_node: Node3D, ai_node: Node3D, z_pos: Vector3, forced_roll: float = -1.0) -> bool:
	_sim_clash_count += 1
	var cfg_sc: KiEconomyConfig = KiEconomyConfig.get_default()
	var sim_clash_ki: float = float(cfg_sc.melee_sim_clash_ki_reward) if cfg_sc.get("melee_sim_clash_ki_reward") != null else 8.0
	var clash_thresh: int = int(cfg_sc.melee_sim_clashes_to_flurry) if cfg_sc.get("melee_sim_clashes_to_flurry") != null else 3
	var sim_flurry_chance: float = float(cfg_sc.melee_sim_clash_flurry_chance) if cfg_sc.get("melee_sim_clash_flurry_chance") != null else 0.45
	_modify_fighter_ki(p_node, sim_clash_ki)
	_modify_fighter_ki(ai_node, sim_clash_ki)
	if p_node and is_instance_valid(p_node) and p_node.has_method("increase_np"):
		p_node.increase_np(100.0)
	if ai_node and is_instance_valid(ai_node) and ai_node.has_method("increase_np"):
		ai_node.increase_np(100.0)
	_spawn_parry_shockwave(z_pos)
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), z_pos, 2, Color(1.0, 0.85, 0.25, 0.95), true)
	if ai_node and is_instance_valid(ai_node) and ai_node.get("procedural_animator"):
		ai_node.procedural_animator.trigger_melee_strike(randi() % 4)
	if audio_player:
		audio_player.global_position = z_pos
		audio_player.pitch_scale = 1.12 + minf(float(_sim_clash_count) * 0.06, 0.24)
		AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
	_pulse_player_both_hands(220.0, 0.95, 0.14)
	var lat_s: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if _sim_clash_count % 2 == 0 else -1.0)
	_trigger_dynamic_melee_mobility(2.2, true, false, false, p_node, ai_node, lat_s * 5.0 + Vector3.UP * 1.4, 0.18, false)
	last_action_feedback = "💥 ¡CHOQUE SIMULTÁNEO #%d! (+%d Ki, +100 BP)" % [_sim_clash_count, int(sim_clash_ki)]
	_spawn_impact_popup(z_pos, "💥 ¡CHOQUE #%d!" % _sim_clash_count, Color(1.0, 0.92, 0.25))

	var p_ki_chk: float = float(p_node.get("current_ki")) if (p_node and is_instance_valid(p_node) and p_node.get("current_ki") != null) else 0.0
	var ai_ki_chk: float = float(ai_node.get("current_ki")) if (ai_node and is_instance_valid(ai_node) and ai_node.get("current_ki") != null) else 0.0
	var roll_sc: float = forced_roll if forced_roll >= 0.0 else randf()
	if p_ki_chk >= 16.0 and ai_ki_chk >= 16.0 and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")) and should_trigger_sim_flurry_clash(_sim_clash_count, clash_thresh, roll_sc, sim_flurry_chance, _flurry_clash_cooldown_melees):
		attacker = p_node
		defender = ai_node
		_sim_nodes.clear()
		_start_lore_event(MeleeLoreEventScript.LoreEventType.FIST_FLURRY_CLASH, "sim_exchange")
		return true
	return false


func _process_simultaneous_exchange(delta: float) -> void:
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var ai_node: Node3D = pair[1]
	if not p_node or not ai_node:
		evaluate_round_outcome()
		return

	_sim_duration -= delta
	_sim_spawn_timer -= delta
	_update_dome_transform()

	var p_orig: XROrigin3D = p_node.get_parent() as XROrigin3D
	if not p_orig:
		_finish_simultaneous_exchange(p_node, ai_node, true)
		return

	var real_dt: float = maxf(delta / maxf(Engine.time_scale, 0.01), 0.001)
	var l_ctrl: XRController3D = _get_controller("LeftHand")
	var r_ctrl: XRController3D = _get_controller("RightHand")
	var orig_basis: Basis = p_orig.global_transform.basis.orthonormalized()
	var l_loc: Vector3 = l_ctrl.position if l_ctrl else Vector3.ZERO
	var r_loc: Vector3 = r_ctrl.position if r_ctrl else Vector3.ZERO
	if _has_prev_def_local:
		if l_ctrl:
			def_left_velocity = orig_basis * ((l_loc - _def_prev_l_local) / real_dt)
		if r_ctrl:
			def_right_velocity = orig_basis * ((r_loc - _def_prev_r_local) / real_dt)
	_def_prev_l_local = l_loc
	_def_prev_r_local = r_loc
	_has_prev_def_local = true

	var punch_fwd_s: Vector3 = _get_punch_forward_world()
	var l_depth_s: float = _get_hand_depth_local(l_ctrl) if l_ctrl else 0.0
	var r_depth_s: float = _get_hand_depth_local(r_ctrl) if r_ctrl else 0.0
	var l_fwd_vel_s: float = def_left_velocity.dot(punch_fwd_s)
	var r_fwd_vel_s: float = def_right_velocity.dot(punch_fwd_s)

	buffer_grip_timer_l = maxf(buffer_grip_timer_l - real_dt, 0.0)
	buffer_grip_timer_r = maxf(buffer_grip_timer_r - real_dt, 0.0)
	buffer_trig_timer_l = maxf(buffer_trig_timer_l - real_dt, 0.0)
	buffer_trig_timer_r = maxf(buffer_trig_timer_r - real_dt, 0.0)

	if l_ctrl:
		if _sim_hand_retract[0] and should_release_punch_retraction(_sim_last_hit_depth[0], l_depth_s, l_fwd_vel_s):
			_sim_hand_retract[0] = false
			_sim_origin_local[0] = l_loc
			_sim_origin_depth[0] = l_depth_s
			_sim_origin_init[0] = true
		if not _sim_hand_retract[0] and (not _sim_origin_init[0] or l_fwd_vel_s <= 0.15):
			_sim_origin_local[0] = l_loc
			_sim_origin_depth[0] = l_depth_s
			_sim_origin_init[0] = true
		def_grip_l = _ctrl_float(l_ctrl, &"grip") > 0.50 or _ctrl_pressed(l_ctrl, &"grip_click")
		def_trig_l = _ctrl_float(l_ctrl, &"trigger") > 0.50 or _ctrl_pressed(l_ctrl, &"trigger_click")
		if def_grip_l and not prev_grip_l:
			buffer_grip_timer_l = 0.12
		if def_trig_l and not prev_trig_l:
			buffer_trig_timer_l = 0.10
			_trig_press_age_l = 0.0
		elif def_trig_l:
			_trig_press_age_l += real_dt
		else:
			_trig_press_age_l = 0.0
		prev_grip_l = def_grip_l
		prev_trig_l = def_trig_l
	if r_ctrl:
		if _sim_hand_retract[1] and should_release_punch_retraction(_sim_last_hit_depth[1], r_depth_s, r_fwd_vel_s):
			_sim_hand_retract[1] = false
			_sim_origin_local[1] = r_loc
			_sim_origin_depth[1] = r_depth_s
			_sim_origin_init[1] = true
		if not _sim_hand_retract[1] and (not _sim_origin_init[1] or r_fwd_vel_s <= 0.15):
			_sim_origin_local[1] = r_loc
			_sim_origin_depth[1] = r_depth_s
			_sim_origin_init[1] = true
		def_grip_r = _ctrl_float(r_ctrl, &"grip") > 0.50 or _ctrl_pressed(r_ctrl, &"grip_click")
		def_trig_r = _ctrl_float(r_ctrl, &"trigger") > 0.50 or _ctrl_pressed(r_ctrl, &"trigger_click")
		if def_grip_r and not prev_grip_r:
			buffer_grip_timer_r = 0.12
		if def_trig_r and not prev_trig_r:
			buffer_trig_timer_r = 0.10
			_trig_press_age_r = 0.0
		elif def_trig_r:
			_trig_press_age_r += real_dt
		else:
			_trig_press_age_r = 0.0
		prev_grip_r = def_grip_r
		prev_trig_r = def_trig_r

	var crossing_now: bool = false
	if l_ctrl and r_ctrl and def_grip_l and def_trig_l and def_grip_r and def_trig_r:
		var cam_s: Camera3D = _get_player_camera()
		var chest_y: float = cam_s.global_position.y - 0.25 if cam_s else global_position.y
		crossing_now = l_ctrl.global_position.distance_to(r_ctrl.global_position) < 0.30 and l_ctrl.global_position.y <= chest_y + 0.18

	var cfg_s: KiEconomyConfig = KiEconomyConfig.get_default()
	var remove_indices: Array[int] = []
	var spawn_counter_def: bool = false

	for idx in range(_sim_nodes.size()):
		var slot: Dictionary = _sim_nodes[idx]
		slot["timer"] = float(slot["timer"]) - delta
		var zid: int = int(slot["zone_id"])
		var role: String = String(slot["role"])
		var z_dict: Dictionary = target_zones[zid] if zid < target_zones.size() else target_zones[0]
		var z_pos: Vector3 = (z_dict["node"] as Node3D).global_position
		var t_rem: float = float(slot["timer"])

		if role == "ATTACK":
			var punched_h: int = -1
			for hi in [0, 1]:
				if _sim_hand_retract[hi]:
					continue
				var c_h: XRController3D = l_ctrl if hi == 0 else r_ctrl
				if not c_h or not _is_defender_fist_closed(hi):
					continue
				if c_h.global_position.distance_to(z_pos) > 0.26:
					continue
				var v_vec_s: Vector3 = def_left_velocity if hi == 0 else def_right_velocity
				var cur_d_s: float = l_depth_s if hi == 0 else r_depth_s
				var stroke_s: float = c_h.position.distance_to(_sim_origin_local[hi]) if _sim_origin_init[hi] else 0.0
				var fwd_s: float = (cur_d_s - _sim_origin_depth[hi]) if _sim_origin_init[hi] else 0.0
				var eval_s: Dictionary = evaluate_real_punch_motion(v_vec_s, punch_fwd_s, stroke_s, fwd_s, true)
				if bool(eval_s.get("valid", false)):
					punched_h = hi
					break
			if punched_h != -1:
				var c_hit: XRController3D = l_ctrl if punched_h == 0 else r_ctrl
				_sim_hand_retract[punched_h] = true
				_sim_last_hit_local[punched_h] = c_hit.position
				_sim_last_hit_depth[punched_h] = l_depth_s if punched_h == 0 else r_depth_s
				_sim_last_impact_zone = zid
				if bool(slot["ai_claiming"]) and t_rem <= 0.55:
					if _resolve_simultaneous_clash(p_node, ai_node, z_pos):
						return
				else:
					var prof_pa: Dictionary = _get_bp_profile(p_node, ai_node, false)
					_modify_fighter_ki(p_node, -cfg_s.melee_quick_cost)
					_sim_enemy_hits_taken += 1
					_modify_fighter_ki(ai_node, -6.0 * float(prof_pa["ki_mult"]))
					if ai_node.has_method("take_hit"):
						ai_node.take_hit(220.0 * float(prof_pa["damage_scale"]), _duel_axis)
					if p_node.has_method("increase_np"):
						p_node.increase_np(200.0 * float(prof_pa["bp_gain_mult"]))
					if ai_node.get("procedural_animator"):
						ai_node.procedural_animator.trigger_hit_flinch(0.65, _duel_axis)
					_spawn_hit_spark(z_pos)
					if audio_player:
						audio_player.global_position = z_pos
						audio_player.pitch_scale = 1.0
						AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
					_pulse_player_hand(punched_h, 200.0, 0.9, 0.12)
					_trigger_dynamic_melee_mobility(1.6, true, false, false, p_node, ai_node, _duel_axis * 4.5 + Vector3.UP * 0.8, 0.18, false)
					last_action_feedback = "🥊 ¡IMPACTO (%d/4)!" % _sim_enemy_hits_taken
					_spawn_impact_popup(z_pos, "💥 ¡GOLPE!", Color(1.0, 0.65, 0.18))
					spawn_counter_def = true
				remove_indices.append(idx)
			elif t_rem <= -0.25:
				if bool(slot["ai_claiming"]):
					var prof_ap: Dictionary = _get_bp_profile(ai_node, p_node, false)
					_sim_player_hits_taken += 1
					_sim_last_impact_zone = zid
					_modify_fighter_ki(p_node, -6.0 * float(prof_ap["ki_mult"]))
					_modify_fighter_ki(ai_node, -cfg_s.melee_quick_cost)
					if p_node.has_method("take_hit"):
						p_node.take_hit(160.0 * float(prof_ap["damage_scale"]), -_duel_axis)
					if ai_node.has_method("increase_np"):
						ai_node.increase_np(144.0 * float(prof_ap["bp_gain_mult"]))
					if ai_node.get("procedural_animator"):
						ai_node.procedural_animator.trigger_melee_strike(randi() % 4)
					_pulse_player_both_hands(170.0, 0.80, 0.10)
					last_action_feedback = "💥 ¡TE GANÓ LA ZONA (%d/4)!" % _sim_player_hits_taken
					_spawn_impact_popup(z_pos, "💥 ¡CONTRA-GOLPE!", Color(1.0, 0.32, 0.15))
				remove_indices.append(idx)
		else:
			if t_rem > 0.30 and not crossing_now and not bool(slot["early_lockout"]):
				var e_hand: int = -1
				for hi_e in [0, 1]:
					var ch_e: XRController3D = l_ctrl if hi_e == 0 else r_ctrl
					if not ch_e:
						continue
					var d_def_e: float = ch_e.global_position.distance_to(z_pos)
					if d_def_e <= 0.38:
						var e_tb_s: bool = (buffer_trig_timer_l > 0.0) if hi_e == 0 else (buffer_trig_timer_r > 0.0)
						var e_gb_s: bool = (buffer_grip_timer_l > 0.0) if hi_e == 0 else (buffer_grip_timer_r > 0.0)
						var closer_to_attack_fist: bool = false
						var h_closed_e: bool = _is_defender_fist_closed(hi_e)
						if h_closed_e:
							for sn_chk in _sim_nodes:
								if String(sn_chk["role"]) == "ATTACK":
									var az_id: int = int(sn_chk["zone_id"])
									var az_pos: Vector3 = (target_zones[az_id]["node"] as Node3D).global_position
									if ch_e.global_position.distance_to(az_pos) < d_def_e:
										closer_to_attack_fist = true
										break
						if not closer_to_attack_fist and evaluate_one_hand_defense_input(t_rem, false, false, e_tb_s, e_gb_s, false, 0.0, 0.0, 0.0, false) == "EARLY_LOCKOUT":
							e_hand = hi_e
							break
				if e_hand != -1:
					slot["early_lockout"] = true
					_consume_defender_hand_buffer(e_hand)
					_spawn_impact_popup(z_pos, "❌ ¡MUY PRONTO!", Color(1.0, 0.15, 0.15))

			var is_locked_s: bool = bool(slot["early_lockout"])
			if not is_locked_s and t_rem <= 0.30 and t_rem >= -0.18:
				var parry_h: int = -1
				if not crossing_now:
					var d_l_s: float = l_ctrl.global_position.distance_to(z_pos) if l_ctrl else 999.0
					var d_r_s: float = r_ctrl.global_position.distance_to(z_pos) if r_ctrl else 999.0
					var in_l_s: bool = d_l_s <= 0.28
					var in_r_s: bool = d_r_s <= 0.28
					if in_l_s and in_r_s:
						parry_h = 0 if def_left_velocity.length() >= def_right_velocity.length() else 1
					elif in_l_s:
						parry_h = 0
					elif in_r_s:
						parry_h = 1
				if parry_h != -1:
					var h_vec_s: Vector3 = def_left_velocity if parry_h == 0 else def_right_velocity
					var h_vel_s: float = h_vec_s.length()
					var fwd_clash_s: float = h_vec_s.dot(punch_fwd_s)
					var h_grip_s: bool = def_grip_l if parry_h == 0 else def_grip_r
					var h_trig_s: bool = def_trig_l if parry_h == 0 else def_trig_r
					var h_tb_s: bool = (buffer_trig_timer_l > 0.0) if parry_h == 0 else (buffer_trig_timer_r > 0.0)
					var h_gb_s: bool = (buffer_grip_timer_l > 0.0) if parry_h == 0 else (buffer_grip_timer_r > 0.0)
					var h_age_s: float = _trig_press_age_l if parry_h == 0 else _trig_press_age_r
					var s_act: String = evaluate_one_hand_defense_input(t_rem, h_trig_s, h_grip_s, h_tb_s, h_gb_s, _is_defender_just_guard_active(parry_h), h_age_s, fwd_clash_s, h_vel_s, false)
					if s_act == "PARRY":
						_consume_defender_note_buffers()
						var parry_ki_s: float = float(cfg_s.melee_parry_ki_reward) if cfg_s.get("melee_parry_ki_reward") != null else 20.0
						var parry_ai_drain: float = float(cfg_s.melee_parry_attacker_ki_drain) if cfg_s.get("melee_parry_attacker_ki_drain") != null else 10.0
						_modify_fighter_ki(p_node, parry_ki_s, true)
						_modify_fighter_ki(ai_node, -parry_ai_drain)
						if p_node.has_method("increase_np"):
							p_node.increase_np(450.0)
						_spawn_parry_shockwave(z_pos)
						_pulse_player_both_hands(250.0, 1.0, 0.24)
						if audio_player:
							audio_player.global_position = z_pos
							audio_player.pitch_scale = 1.30
							AudioActionManager.play_action("common.block_perfect", audio_player)
						_sim_last_impact_zone = zid
						_spawn_impact_popup(z_pos, "✨ ¡PARRY DECISIVO!", Color(1.0, 0.94, 0.22))
						# GDD Canon: Parry Perfecto en Furia dispara Zenkai Comeback
						if bool(p_node.get("is_in_furia")) and not bool(p_node.get("is_in_zenkai_state")) and p_node.has_method("trigger_comeback_zenkai"):
							p_node.trigger_comeback_zenkai()
						_finish_simultaneous_exchange(p_node, ai_node, true, true)
						return
					elif s_act == "CLASH":
						_consume_defender_hand_buffer(parry_h)
						_sim_last_impact_zone = zid
						if _resolve_simultaneous_clash(p_node, ai_node, z_pos):
							return
						remove_indices.append(idx)
						continue
					elif s_act == "BLOCK_GREEN" or s_act == "BLOCK_YELLOW":
						_consume_defender_hand_buffer(parry_h)
						var prof_sim_b: Dictionary = _get_bp_profile(ai_node, p_node, false)
						if s_act == "BLOCK_GREEN":
							var defl_sim: float = float(cfg_s.melee_deflect_ki_reward) if cfg_s.get("melee_deflect_ki_reward") != null else 16.0
							_modify_fighter_ki(p_node, defl_sim, true)
							_modify_fighter_ki(ai_node, -6.0)
							if p_node.has_method("increase_np"):
								p_node.increase_np(100.0 * float(prof_sim_b["defender_underdog_bp_mult"]))
							_spawn_block_spark(z_pos, Color(0.25, 1.0, 0.50))
							if ai_node.get("procedural_animator"):
								ai_node.procedural_animator.trigger_hit_flinch(0.35, _duel_axis)
							if audio_player:
								audio_player.global_position = z_pos
								audio_player.pitch_scale = 1.25
								AudioActionManager.play_action("common.melee_hit_light", audio_player)
							last_action_feedback = "✋ ¡DESVÍO! (+%d Ki)" % int(defl_sim)
							_spawn_impact_popup(z_pos, "✋ ¡DESVÍO!", Color(0.25, 1.0, 0.50))
						else:
							var y_sim_cost: float = float(cfg_s.melee_yellow_block_ki_cost) if cfg_s.get("melee_yellow_block_ki_cost") != null else 4.0
							_modify_fighter_ki(p_node, -y_sim_cost)
							if p_node.has_method("take_hit"):
								p_node.take_hit(99.0 * float(prof_sim_b["damage_scale"]), -_duel_axis)
							last_action_feedback = "⚠️ ¡AMARILLO! (-%d Ki)" % int(y_sim_cost)
							_spawn_impact_popup(z_pos, "⚠️ ¡AMARILLO!", Color(1.0, 0.85, 0.18))
						remove_indices.append(idx)
						continue

				if crossing_now:
					_consume_defender_note_buffers()
					var prof_sim_x: Dictionary = _get_bp_profile(ai_node, p_node, false)
					var gx_sim_cost: float = clampf((float(cfg_s.melee_sim_guard_x_cost) if cfg_s.get("melee_sim_guard_x_cost") != null else 6.0) * float(prof_sim_x["ki_mult"]), 3.0, 12.0)
					_modify_fighter_ki(p_node, -gx_sim_cost)
					if p_node.has_method("take_hit"):
						p_node.take_hit(45.0 * float(prof_sim_x["damage_scale"]), -_duel_axis)
					if ai_node.has_method("increase_np"):
						ai_node.increase_np(35.0 * float(prof_sim_x["bp_gain_mult"]))
					_spawn_block_spark(z_pos, Color(0.25, 0.78, 1.0))
					last_action_feedback = "🛡️ ¡GUARDIA X! (-%d Ki)" % int(gx_sim_cost)
					remove_indices.append(idx)
					continue

			if (is_locked_s and t_rem <= 0.0) or t_rem <= -0.18:
				var prof_sim_h: Dictionary = _get_bp_profile(ai_node, p_node, false)
				_sim_player_hits_taken += 1
				_sim_last_impact_zone = zid
				_modify_fighter_ki(p_node, -8.0 * float(prof_sim_h["ki_mult"]))
				if p_node.has_method("take_hit"):
					p_node.take_hit(220.0 * float(prof_sim_h["damage_scale"]), -_duel_axis)
				if ai_node.has_method("increase_np"):
					ai_node.increase_np(198.0 * float(prof_sim_h["bp_gain_mult"]))
				if ai_node.get("procedural_animator"):
					ai_node.procedural_animator.trigger_melee_strike(randi() % 4)
				_trigger_dynamic_melee_mobility(1.5, true, false, false, ai_node, p_node, -_duel_axis * 4.5 + Vector3.UP * 0.6, 0.18, false)
				_pulse_player_both_hands(180.0, 0.85, 0.12)
				last_action_feedback = "💥 ¡GOLPE RECIBIDO (%d/4)!" % _sim_player_hits_taken
				_spawn_impact_popup(z_pos, "💥 ¡IMPACTO!", Color(1.0, 0.30, 0.15))
				remove_indices.append(idx)

	remove_indices.sort()
	for r_i in range(remove_indices.size() - 1, -1, -1):
		_sim_nodes.remove_at(remove_indices[r_i])

	if spawn_counter_def:
		_spawn_simultaneous_node("DEFEND")
	if _sim_spawn_timer <= 0.0 or _sim_nodes.size() < 2:
		_sim_spawn_timer = 0.72
		_spawn_simultaneous_node()

	_sync_simultaneous_zone_visuals()
	_refresh_header_hud()

	var p_ki_s: float = float(p_node.get("current_ki")) if p_node.get("current_ki") != null else 0.0
	var e_ki_s: float = float(ai_node.get("current_ki")) if ai_node.get("current_ki") != null else 0.0
	if _sim_enemy_hits_taken >= 4:
		_finish_simultaneous_exchange(p_node, ai_node, true)
	elif p_ki_s <= 2.0 or _sim_player_hits_taken >= 4:
		_finish_simultaneous_exchange(ai_node, p_node, false)
	elif e_ki_s <= 2.0:
		_finish_simultaneous_exchange(p_node, ai_node, true)
	elif _sim_duration <= 0.0:
		var p_won: bool = (_sim_enemy_hits_taken > _sim_player_hits_taken) or (_sim_enemy_hits_taken == _sim_player_hits_taken and p_ki_s >= e_ki_s)
		_finish_simultaneous_exchange(p_node if p_won else ai_node, ai_node if p_won else p_node, p_won)


func _finish_simultaneous_exchange(winner: Node3D, loser: Node3D, player_won: bool, from_parry: bool = false) -> void:
	attacker = winner
	defender = loser
	last_impact_vector = _compute_zone_launch_vector(_sim_last_impact_zone, false, 12.5)
	var prof_sfin: Dictionary = _get_bp_profile(winner, loser, true)
	var bp_bonus_s: float = (150.0 + float(_sim_clash_count) * 50.0) * float(prof_sfin["bp_gain_mult"]) * float(prof_sfin["attacker_underdog_bp_mult"])
	if winner and is_instance_valid(winner) and winner.has_method("increase_np"):
		winner.increase_np(bp_bonus_s)
	var dd_sim: DramaticDirector = DramaticDirector.get_active(get_tree())
	if dd_sim:
		var win_txt: String = "⚡ ¡GANASTE EL INTERCAMBIO SIMULTÁNEO! (+%d BP)" % int(bp_bonus_s) if player_won else "⚠️ ¡EL RIVAL ROMPIÓ EL INTERCAMBIO!"
		dd_sim.show_camera_banner(win_txt, Color(0.25, 0.96, 1.0) if player_won else Color(1.0, 0.28, 0.18), 1.6)
	var mode_sim: String = "sim_parry_launch" if from_parry else ("charged_v3_up" if last_impact_vector.y > 4.0 else "charged_v3_back")
	_trigger_finisher_and_close(mode_sim, 4.2)


func continue_attacker_offense() -> void:
	last_action_feedback = ""
	start_attack_phase(attacker, defender)


## Genera secuencia rítmica de la IA incluyendo posibles Cargados v3 o Martillazo al suelo (con consumo real de Ki)
func generate_ai_attack_sequence() -> void:
	hits.clear()
	_round_sonic_hits = 0
	var ai_in_zenkai: bool = bool(attacker.get("is_in_zenkai_state")) if attacker else false
	var num_hits: int = max_allowed_hits
	var curr_time: float = NOTE_CADENCE_SEC
	var last_zone: int = -1
	var cfg_ai_a: KiEconomyConfig = KiEconomyConfig.get_default()
	var q_cost: float = float(cfg_ai_a.melee_quick_cost) if cfg_ai_a.get("melee_quick_cost") != null else 3.0
	var chg_cost: float = float(cfg_ai_a.melee_charged_cost) if cfg_ai_a.get("melee_charged_cost") != null else 7.0
	var v3_cost: float = float(cfg_ai_a.melee_v3_cost) if cfg_ai_a.get("melee_v3_cost") != null else 11.0
	var hm_cost: float = float(cfg_ai_a.melee_hammer_cost) if cfg_ai_a.get("melee_hammer_cost") != null else 15.0

	for i in range(num_hits):
		var ai_ki_now: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0
		if i > 0 and ai_ki_now < q_cost:
			break
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
		var hit_cost: float = q_cost

		if is_last and (ai_in_zenkai or ai_ki_now >= chg_cost):
			var r: float = randf()
			if r < 0.26 and ai_ki_now >= hm_cost:
				is_hammer = true
				is_charged = true
				power = 4.5
				zone_id = 1
				hit_cost = hm_cost
			elif r < 0.60 and ai_ki_now >= v3_cost:
				is_v3 = true
				is_charged = true
				power = 3.0
				v3_mode = "UP" if zone_id == 0 else "BACK"
				hit_cost = v3_cost
			elif ai_ki_now >= chg_cost:
				is_charged = true
				power = 2.0
				hit_cost = chg_cost
		elif i >= 1 and not is_last and ai_ki_now >= chg_cost + q_cost and randf() < 0.28:
			is_charged = true
			power = 2.0
			hit_cost = chg_cost

		_modify_fighter_ki(attacker, -minf(hit_cost, ai_ki_now))
		var is_sonic_ai: bool = is_hammer or is_v3 or ai_in_zenkai or (is_charged and randf() < 0.45) or (randf() < 0.25)
		var ai_tier: String = "SONICO" if is_sonic_ai else "SOLIDO"
		var ai_tier_mult: float = 1.35 if is_sonic_ai else 1.0
		if is_sonic_ai:
			_round_sonic_hits += 1

		var target_pos: Vector3 = target_zones[zone_id]["node"].global_position if zone_id < target_zones.size() else global_position
		var label_name: String = "Martillazo DBZ" if is_hammer else ("Cargado v3" if is_v3 else String(ZONE_DEFINITIONS[zone_id]["name"]))
		var ai_swing_dir: Vector3 = Vector3.DOWN if is_hammer else ((_duel_axis * -1.0) + Vector3.UP * (0.55 if (is_v3 and v3_mode == "UP") else 0.0) + Vector3.RIGHT * (0.2 if i % 2 == 0 else -0.2)).normalized()
		var ai_launch: Vector3 = _compute_zone_launch_vector(zone_id, is_hammer, 13.0 if is_hammer else (11.0 if is_v3 else (8.5 if is_charged else 5.5)), ai_swing_dir)
		var ai_refund: float = float(cfg_ai_a.melee_sonic_ki_refund if is_sonic_ai else cfg_ai_a.melee_clean_hit_ki_refund)
		hits.append({
			"zone_id": zone_id,
			"name": label_name,
			"pos": target_pos,
			"hand": "Right" if (i % 2 == 0) else "Left",
			"time_offset": curr_time,
			"power": power,
			"tier": ai_tier,
			"tier_dmg_mult": ai_tier_mult,
			"ki_refund": ai_refund,
			"is_charged": is_charged,
			"is_charged_v3": is_v3,
			"is_hammer": is_hammer,
			"v3_launch_mode": v3_mode,
			"launch_vec": ai_launch,
			"velocity": 4.5,
			"swing_dir": ai_swing_dir,
			"defense_score": 0.0,
			"resolved": false
		})
		curr_time += NOTE_CADENCE_SEC
	_declared_full_combo = (hits.size() >= max_allowed_hits)


# ==============================================================================
# INVERSIÓN DE ROLES (TURNOVER) Y FINALIZACIÓN
# ==============================================================================

func restart_as_attacker(keep_comeback_momentum: bool = false) -> void:
	var temp: Node3D = attacker
	attacker = defender
	defender = temp
	defender_is_defenseless = false
	attacker_damage_mult = 1.0
	if not keep_comeback_momentum:
		_comeback_momentum_active = false
	last_action_feedback = ""

	emit_signal("perfect_parry_triggered", attacker, defender)
	print("[BulletTimeDome] 🔄 Cambio de turno. Nuevo atacante: %s" % [attacker.name if attacker else "None"])
	start_attack_phase(attacker, defender)


func finish_without_hits(_is_manual_cancel: bool = false) -> void:
	if not is_active:
		return
	is_active = false
	_declared_full_combo = false
	_kill_surge_tween()
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	phase = DomePhase.COMPLETED
	var cfg_fw: KiEconomyConfig = KiEconomyConfig.get_default()
	var cancel_cost: float = float(cfg_fw.melee_cancel_cost) if cfg_fw.get("melee_cancel_cost") != null else 6.0
	_modify_fighter_ki(attacker, -cancel_cost)
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

func _modify_fighter_ki(fighter: Node3D, delta_ki: float, is_defensive_reward: bool = false) -> void:
	if not fighter or not is_instance_valid(fighter):
		return
	var actual_delta: float = delta_ki
	if is_defensive_reward and actual_delta > 0.0 and bool(fighter.get("is_in_furia")):
		actual_delta *= 2.0
	var cur_ki: float = float(fighter.get("current_ki")) if fighter.get("current_ki") != null else 0.0
	var max_ki: float = 100.0
	var cdata: Resource = fighter.get("character_data")
	if cdata and "base_ki" in cdata:
		max_ki = float(cdata.base_ki)
	fighter.set("current_ki", clampf(cur_ki + actual_delta, 0.0, max_ki))
	if actual_delta < 0.0 and fighter.has_method("_mark_ki_spent"):
		fighter._mark_ki_spent()
	if fighter.has_method("_notify_stats"):
		fighter._notify_stats()
	_refresh_melee_ki_bar()
	if absf(actual_delta) >= 1.0:
		_show_ki_delta_popup(fighter, actual_delta)


func _update_defender_velocities(delta: float) -> void:
	if delta <= 0.0001 or not defender or not is_instance_valid(defender) or not bool(defender.get("is_player")):
		return
	var origin: XROrigin3D = _cached_xr_origin if (_cached_xr_origin and is_instance_valid(_cached_xr_origin)) else (defender.get_parent() as XROrigin3D)
	var real_dt: float = maxf(delta / maxf(Engine.time_scale, 0.01), 0.001)
	var orig_basis: Basis = origin.global_transform.basis.orthonormalized() if origin else Basis.IDENTITY
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	var l_loc: Vector3 = left_ctrl.position if left_ctrl else Vector3.ZERO
	var r_loc: Vector3 = right_ctrl.position if right_ctrl else Vector3.ZERO
	if _has_prev_def_local:
		if left_ctrl:
			def_left_velocity = orig_basis * ((l_loc - _def_prev_l_local) / real_dt)
		if right_ctrl:
			def_right_velocity = orig_basis * ((r_loc - _def_prev_r_local) / real_dt)
	_def_prev_l_local = l_loc
	_def_prev_r_local = r_loc
	_has_prev_def_local = true


func _update_defender_input_buffers(delta: float) -> void:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return
	var real_dt: float = maxf(delta / maxf(Engine.time_scale, 0.01), 0.001)
	buffer_grip_timer_l = maxf(buffer_grip_timer_l - real_dt, 0.0)
	buffer_grip_timer_r = maxf(buffer_grip_timer_r - real_dt, 0.0)
	buffer_trig_timer_l = maxf(buffer_trig_timer_l - real_dt, 0.0)
	buffer_trig_timer_r = maxf(buffer_trig_timer_r - real_dt, 0.0)

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")

	if left_ctrl:
		def_grip_l = _ctrl_float(left_ctrl, &"grip") > 0.50 or _ctrl_pressed(left_ctrl, &"grip_click")
		def_trig_l = _ctrl_float(left_ctrl, &"trigger") > 0.50 or _ctrl_pressed(left_ctrl, &"trigger_click")
		if def_grip_l and not prev_grip_l:
			buffer_grip_timer_l = 0.12
		if def_trig_l and not prev_trig_l:
			buffer_trig_timer_l = 0.10
			_trig_press_age_l = 0.0
		elif def_trig_l:
			_trig_press_age_l += real_dt
		else:
			_trig_press_age_l = 0.0
		prev_grip_l = def_grip_l
		prev_trig_l = def_trig_l

	if right_ctrl:
		def_grip_r = _ctrl_float(right_ctrl, &"grip") > 0.50 or _ctrl_pressed(right_ctrl, &"grip_click")
		def_trig_r = _ctrl_float(right_ctrl, &"trigger") > 0.50 or _ctrl_pressed(right_ctrl, &"trigger_click")
		if def_grip_r and not prev_grip_r:
			buffer_grip_timer_r = 0.12
		if def_trig_r and not prev_trig_r:
			buffer_trig_timer_r = 0.10
			_trig_press_age_r = 0.0
		elif def_trig_r:
			_trig_press_age_r += real_dt
		else:
			_trig_press_age_r = 0.0
		prev_grip_r = def_grip_r
		prev_trig_r = def_trig_r


func _consume_defender_note_buffers() -> void:
	buffer_grip_timer_l = 0.0
	buffer_grip_timer_r = 0.0
	buffer_trig_timer_l = 0.0
	buffer_trig_timer_r = 0.0
	_trig_press_age_l = 0.0
	_trig_press_age_r = 0.0


func _consume_defender_hand_buffer(hand_idx: int) -> void:
	if hand_idx == 0:
		buffer_grip_timer_l = 0.0
		buffer_trig_timer_l = 0.0
		_trig_press_age_l = 0.0
	elif hand_idx == 1:
		buffer_grip_timer_r = 0.0
		buffer_trig_timer_r = 0.0
		_trig_press_age_r = 0.0


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
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	var dist_l: float = left_ctrl.global_position.distance_to(zone_pos) if left_ctrl else 999.0
	var dist_r: float = right_ctrl.global_position.distance_to(zone_pos) if right_ctrl else 999.0
	var in_l: bool = dist_l <= threshold
	var in_r: bool = dist_r <= threshold
	if in_l and in_r:
		var vel_l: float = def_left_velocity.length()
		var vel_r: float = def_right_velocity.length()
		if absf(vel_l - vel_r) > 0.12:
			return 0 if vel_l >= vel_r else 1
		return 0 if dist_l <= dist_r else 1
	if in_l:
		return 0
	if in_r:
		return 1
	return -1


func _is_defender_crossing_arms() -> bool:
	if not defender or not is_instance_valid(defender):
		return false
	if defender.get("is_blocking"):
		return true
	if not defender.get("is_player"):
		return false

	var cam: Camera3D = _get_player_camera()
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")

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
	_hitstop_end_msec = Time.get_ticks_msec() + int(maxf(freeze_time, 0.01) * 1000.0)


func _kill_surge_tween() -> void:
	_surge_active_timer = 0.0
	if _surge_tween and is_instance_valid(_surge_tween):
		_surge_tween.kill()
	_surge_tween = null


func _pulse_defender_hand(hand_idx: int, freq: float, amp: float, dur: float) -> void:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return
	var ctrl: XRController3D = _get_controller("LeftHand" if hand_idx == 0 else "RightHand")
	if ctrl and ctrl.has_method("trigger_haptic_pulse"):
		ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _pulse_defender_both_hands(freq: float, amp: float, dur: float) -> void:
	_pulse_defender_hand(0, freq, amp, dur)
	_pulse_defender_hand(1, freq, amp, dur)


func _pulse_player_hand(hand_idx: int, freq: float, amp: float, dur: float) -> void:
	var p_node: Node3D = _get_player_and_ai()[0]
	if not p_node or not is_instance_valid(p_node):
		return
	var ctrl: XRController3D = _get_controller("LeftHand" if hand_idx == 0 else "RightHand")
	if ctrl and ctrl.has_method("trigger_haptic_pulse"):
		ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _pulse_player_both_hands(freq: float, amp: float, dur: float) -> void:
	_pulse_player_hand(0, freq, amp, dur)
	_pulse_player_hand(1, freq, amp, dur)


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
	melee_boxes_anchor = Node3D.new()
	melee_boxes_anchor.name = "MeleeBoxesAnchor"
	melee_boxes_anchor.position = Vector3.ZERO
	add_child(melee_boxes_anchor)
	var boxes_parent: Node3D = melee_boxes_anchor

	# 5 mallas compartidas entre las 6 zonas (zero duplicate geometry allocations)
	var shared_box := BoxMesh.new()
	shared_box.size = Vector3(0.16, 0.16, 0.05)
	var shared_quad := QuadMesh.new()
	shared_quad.size = Vector2(0.12, 0.12)
	var shared_disc := CylinderMesh.new()
	shared_disc.top_radius = 0.088
	shared_disc.bottom_radius = 0.088
	shared_disc.height = 0.016
	shared_disc.radial_segments = 24
	var shared_c_torus := TorusMesh.new()
	shared_c_torus.inner_radius = 0.080
	shared_c_torus.outer_radius = 0.096
	shared_c_torus.rings = 24
	shared_c_torus.ring_segments = 10
	var shared_t_torus := TorusMesh.new()
	shared_t_torus.inner_radius = 0.08
	shared_t_torus.outer_radius = 0.095
	shared_t_torus.rings = 16
	shared_t_torus.ring_segments = 16

	for def in ZONE_DEFINITIONS:
		var zone_node := Node3D.new()
		zone_node.name = "Zone_%d_%s" % [def.id, def.name.replace(" / ", "_").replace(" ", "_")]
		zone_node.position = def.offset
		boxes_parent.add_child(zone_node)

		var box_mesh_inst := MeshInstance3D.new()
		box_mesh_inst.mesh = shared_box

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
		inner_quad.mesh = shared_quad
		inner_quad.position = Vector3(0.0, 0.0, 0.028)

		var mat_quad := StandardMaterial3D.new()
		mat_quad.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_quad.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_quad.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		mat_quad.no_depth_test = true
		mat_quad.render_priority = 116
		inner_quad.material_override = mat_quad
		zone_node.add_child(inner_quad)

		var circle_mesh_inst := MeshInstance3D.new()
		circle_mesh_inst.name = "AttackCircleDisc"
		circle_mesh_inst.mesh = shared_disc
		circle_mesh_inst.rotation.x = PI * 0.5

		var mat_circle := StandardMaterial3D.new()
		mat_circle.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_circle.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		mat_circle.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_circle.albedo_color = Color(def.color.r, def.color.g, def.color.b, 0.45)
		mat_circle.emission_enabled = true
		mat_circle.emission = Color(def.color.r, def.color.g, def.color.b)
		mat_circle.emission_energy_multiplier = 1.2
		mat_circle.no_depth_test = true
		mat_circle.render_priority = 115
		circle_mesh_inst.material_override = mat_circle
		circle_mesh_inst.visible = false
		zone_node.add_child(circle_mesh_inst)

		var circle_ring := MeshInstance3D.new()
		circle_ring.name = "AttackCircleRing"
		circle_ring.mesh = shared_c_torus
		circle_ring.rotation.x = PI * 0.5
		circle_ring.position = Vector3(0.0, 0.0, 0.016)

		var mat_c_ring := StandardMaterial3D.new()
		mat_c_ring.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_c_ring.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		mat_c_ring.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_c_ring.albedo_color = Color(def.color.r, def.color.g, def.color.b, 0.90)
		mat_c_ring.emission_enabled = true
		mat_c_ring.emission = Color(def.color.r, def.color.g, def.color.b)
		mat_c_ring.emission_energy_multiplier = 1.5
		mat_c_ring.no_depth_test = true
		mat_c_ring.render_priority = 116
		circle_ring.material_override = mat_c_ring
		circle_ring.visible = false
		zone_node.add_child(circle_ring)

		var timing_ring := MeshInstance3D.new()
		timing_ring.mesh = shared_t_torus
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
		step_lbl.render_priority = 118
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
			"circle_mesh": circle_mesh_inst,
			"circle_mat": mat_circle,
			"circle_ring": circle_ring,
			"circle_ring_mat": mat_c_ring,
			"timing_ring": timing_ring,
			"step_label": step_lbl,
			"hit": false,
			"cooldown": 0.0,
			"color": def.color
		})


func _get_player_camera() -> Camera3D:
	if _cached_camera and is_instance_valid(_cached_camera):
		return _cached_camera
	for f in [attacker, defender]:
		if f and is_instance_valid(f) and bool(f.get("is_player")):
			var orig: Node = f.get_parent()
			if orig:
				var c: Camera3D = orig.get_node_or_null("XRCamera3D") as Camera3D
				if c and is_instance_valid(c):
					_cached_camera = c
					return c
	return get_viewport().get_camera_3d() if (is_inside_tree() and get_viewport()) else null


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
		melee_hud_anchor.position = Vector3(0.0, 0.37, -1.18)
		cam.add_child(melee_hud_anchor)
		header_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		header_label.position = Vector3.ZERO
		melee_hud_anchor.add_child(header_label)
	else:
		header_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		header_label.position = Vector3(0.0, 0.42, -0.75)
		add_child(header_label)
	_build_melee_ki_bar()


func _build_melee_ki_bar() -> void:
	if _ki_bar_root and is_instance_valid(_ki_bar_root):
		return
	var hud_parent: Node3D = melee_hud_anchor if (melee_hud_anchor and is_instance_valid(melee_hud_anchor)) else header_label
	if not hud_parent or not is_instance_valid(hud_parent):
		return

	_ki_bar_root = Node3D.new()
	_ki_bar_root.name = "MeleeDoubleKiBar"
	_ki_bar_root.position = Vector3(0.0, -0.075, 0.0)
	hud_parent.add_child(_ki_bar_root)

	var bg := MeshInstance3D.new()
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.54, 0.048)
	bg.mesh = bg_q
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 123
	bg_mat.albedo_color = Color(0.02, 0.04, 0.09, 0.85)
	bg.material_override = bg_mat
	_ki_bar_root.add_child(bg)

	_player_ki_fill = MeshInstance3D.new()
	var p_q := QuadMesh.new()
	p_q.size = Vector2(1.0, 0.016)
	_player_ki_fill.mesh = p_q
	_player_ki_mat = StandardMaterial3D.new()
	_player_ki_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_ki_mat.no_depth_test = true
	_player_ki_mat.render_priority = 124
	_player_ki_mat.albedo_color = Color(0.18, 0.85, 1.0)
	_player_ki_fill.material_override = _player_ki_mat
	_ki_bar_root.add_child(_player_ki_fill)

	_enemy_ki_fill = MeshInstance3D.new()
	var e_q := QuadMesh.new()
	e_q.size = Vector2(1.0, 0.016)
	_enemy_ki_fill.mesh = e_q
	_enemy_ki_mat = StandardMaterial3D.new()
	_enemy_ki_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_enemy_ki_mat.no_depth_test = true
	_enemy_ki_mat.render_priority = 124
	_enemy_ki_mat.albedo_color = Color(1.0, 0.45, 0.15)
	_enemy_ki_fill.material_override = _enemy_ki_mat
	_ki_bar_root.add_child(_enemy_ki_fill)

	_ki_bar_label = Label3D.new()
	_ki_bar_label.name = "KiBarText"
	_ki_bar_label.font_size = 16
	_ki_bar_label.pixel_size = 0.00115
	_ki_bar_label.outline_size = 6
	_ki_bar_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_ki_bar_label.no_depth_test = true
	_ki_bar_label.render_priority = 125
	_ki_bar_label.position = Vector3(0.0, 0.015, 0.002)
	_ki_bar_root.add_child(_ki_bar_label)

	_ki_delta_label = Label3D.new()
	_ki_delta_label.name = "KiDeltaPopup"
	_ki_delta_label.font_size = 18
	_ki_delta_label.pixel_size = 0.0012
	_ki_delta_label.outline_size = 6
	_ki_delta_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_ki_delta_label.no_depth_test = true
	_ki_delta_label.render_priority = 126
	_ki_delta_label.position = Vector3(0.0, -0.032, 0.003)
	_ki_delta_label.visible = false
	_ki_bar_root.add_child(_ki_delta_label)

	_refresh_melee_ki_bar()


func _refresh_melee_ki_bar() -> void:
	if not _ki_bar_root or not is_instance_valid(_ki_bar_root):
		return
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0] if pair[0] else attacker
	var e_node: Node3D = pair[1] if pair[1] else defender

	var p_ki: float = float(p_node.get("current_ki")) if (p_node and is_instance_valid(p_node) and p_node.get("current_ki") != null) else 0.0
	var e_ki: float = float(e_node.get("current_ki")) if (e_node and is_instance_valid(e_node) and e_node.get("current_ki") != null) else 0.0
	var p_max: float = 100.0
	var e_max: float = 100.0
	var p_cd: Resource = p_node.get("character_data") if (p_node and is_instance_valid(p_node)) else null
	var e_cd: Resource = e_node.get("character_data") if (e_node and is_instance_valid(e_node)) else null
	if p_cd and "base_ki" in p_cd:
		p_max = maxf(float(p_cd.base_ki), 1.0)
	if e_cd and "base_ki" in e_cd:
		e_max = maxf(float(e_cd.base_ki), 1.0)

	var p_int: int = int(roundf(p_ki))
	var e_int: int = int(roundf(e_ki))
	if p_int == _last_shown_p_ki and e_int == _last_shown_e_ki:
		return
	_last_shown_p_ki = p_int
	_last_shown_e_ki = e_int

	var p_frac: float = clampf(p_ki / p_max, 0.0, 1.0)
	var e_frac: float = clampf(e_ki / e_max, 0.0, 1.0)
	var bar_half_w: float = 0.24

	if _player_ki_fill and is_instance_valid(_player_ki_fill):
		var pw: float = maxf(p_frac * bar_half_w, 0.004)
		_player_ki_fill.scale = Vector3(pw, 1.0, 1.0)
		_player_ki_fill.position = Vector3(-0.255 + pw * 0.5, -0.008, 0.002)
	if _enemy_ki_fill and is_instance_valid(_enemy_ki_fill):
		var ew: float = maxf(e_frac * bar_half_w, 0.004)
		_enemy_ki_fill.scale = Vector3(ew, 1.0, 1.0)
		_enemy_ki_fill.position = Vector3(0.015 + ew * 0.5, -0.008, 0.002)

	var critical: bool = p_ki < 22.0
	if _player_ki_mat:
		_player_ki_mat.albedo_color = Color(1.0, 0.22, 0.18) if critical else Color(0.18, 0.85, 1.0)
	if _ki_bar_label and is_instance_valid(_ki_bar_label):
		if critical:
			_ki_bar_label.modulate = Color(1.0, 0.30, 0.25)
			_ki_bar_label.text = "⚠️ KI CRÍTICO (%d)  |  RIVAL: %d" % [p_int, e_int]
		else:
			_ki_bar_label.modulate = Color(0.92, 0.98, 1.0)
			_ki_bar_label.text = "TU KI: %d  |  RIVAL KI: %d" % [p_int, e_int]


func _show_ki_delta_popup(fighter: Node3D, delta_ki: float) -> void:
	if not _ki_delta_label or not is_instance_valid(_ki_delta_label):
		return
	var pair: Array[Node3D] = _get_player_and_ai()
	if pair[0] != null and fighter != pair[0] and bool(fighter.get("is_player")) == false:
		return
	_ki_delta_label.visible = true
	_ki_delta_timer = 1.0
	if delta_ki >= 0.0:
		_ki_delta_label.modulate = Color(0.28, 1.0, 0.55)
		_ki_delta_label.text = "+%d KI" % int(roundf(delta_ki))
	else:
		_ki_delta_label.modulate = Color(1.0, 0.42, 0.22)
		_ki_delta_label.text = "%d KI" % int(roundf(delta_ki))


func _get_fighter_chest_pos(fighter: Node3D) -> Vector3:
	if not fighter or not is_instance_valid(fighter):
		return global_position
	if fighter.get("is_player"):
		var cam: Camera3D = _get_player_camera()
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
	var p_node: Node3D = _cached_player if (_cached_player and is_instance_valid(_cached_player)) else null
	var ai_node: Node3D = _cached_ai if (_cached_ai and is_instance_valid(_cached_ai)) else null
	if not p_node or not ai_node:
		for f in [attacker, defender]:
			if f and is_instance_valid(f):
				if bool(f.get("is_player")):
					p_node = f
				else:
					ai_node = f
	return [p_node, ai_node]


func _keep_ai_face_to_face(delta: float) -> void:
	if _surge_active_timer > 0.0 or phase == DomePhase.LORE_EVENT or (_lore_ctrl != null and bool(_lore_ctrl.get("is_event_active"))):
		return
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var ai_node: Node3D = pair[1]
	if not p_node or not ai_node:
		return
	var cam: Camera3D = _get_player_camera()
	var p_ref: Vector3 = cam.global_position if (cam and is_instance_valid(cam)) else p_node.global_position
	var p_orig: Node3D = p_node.get_parent() as Node3D if p_node.get_parent() is Node3D else null
	var target_y: float = p_orig.global_position.y if p_orig else p_node.global_position.y
	# Usar el eje fijo _duel_axis para que la IA acompañe al instante sin orbitar al mover la cabeza
	var axis: Vector3 = _duel_axis if _duel_axis.length_squared() > 0.001 else Vector3.FORWARD
	var desired_ai_pos: Vector3 = Vector3(p_ref.x, target_y, p_ref.z) + axis * 0.85
	var w: float = clampf(delta * 24.0, 0.0, 1.0)
	ai_node.global_position = ai_node.global_position.lerp(desired_ai_pos, w)
	if ai_node.has_method("_clamp_to_arena"):
		ai_node._clamp_to_arena(ai_node)


func _apply_melee_arena_surge(step_vec: Vector3, duration_sec: float = 0.20) -> void:
	_surge_active_timer = duration_sec + 0.06
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var ai_node: Node3D = pair[1]
	if not p_node or not ai_node:
		return
	var p_orig: Node3D = p_node.get_parent() as Node3D if p_node.get_parent() is Node3D else null
	var p_target: Node3D = p_orig if p_orig else p_node

	var adjusted_step: Vector3 = step_vec
	var cur_pos: Vector3 = p_target.global_position
	var cur_xz := Vector2(cur_pos.x, cur_pos.z)
	var cur_rad: float = cur_xz.length()
	if cur_rad > 68.0:
		var out_dir_xz: Vector2 = cur_xz / cur_rad
		var step_xz := Vector2(adjusted_step.x, adjusted_step.z)
		var radial_proj: float = step_xz.dot(out_dir_xz)
		if radial_proj > 0.0:
			step_xz -= out_dir_xz * (radial_proj * 2.0)
			adjusted_step.x = step_xz.x
			adjusted_step.z = step_xz.y

	var p_dest: Vector3 = cur_pos + adjusted_step
	p_dest.x = clampf(p_dest.x, -76.0, 76.0)
	p_dest.z = clampf(p_dest.z, -76.0, 76.0)
	var ground_h: float = 0.15
	if p_node.has_method("get_ground_elevation"):
		ground_h = float(p_node.get_ground_elevation(p_dest))
	p_dest.y = clampf(p_dest.y, maxf(ground_h, 0.15), 28.0)

	var actual_step: Vector3 = p_dest - cur_pos
	var ai_dest: Vector3 = ai_node.global_position + actual_step
	ai_dest.x = clampf(ai_dest.x, -78.0, 78.0)
	ai_dest.z = clampf(ai_dest.z, -78.0, 78.0)
	ai_dest.y = p_dest.y

	if p_dest.y <= ground_h + 1.8 and actual_step.length() >= 2.5 and get_tree():
		KiSmokeFX.spawn_smoke(get_tree(), Vector3(cur_pos.x, maxf(cur_pos.y, ground_h + 0.1), cur_pos.z), 0.95)

	if _surge_tween and is_instance_valid(_surge_tween):
		_surge_tween.kill()
	_surge_tween = create_tween().set_parallel(true)
	_surge_tween.tween_property(p_target, "global_position", p_dest, duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_surge_tween.tween_property(ai_node, "global_position", ai_dest, duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _compute_melee_mobility_intensity(power_val: float, is_charged: bool, is_v3: bool, is_hammer: bool, mover: Node3D, opponent: Node3D) -> float:
	var base_i: float = clampf(power_val * 0.55, 0.55, 1.85)
	if is_hammer:
		base_i = maxf(base_i, 2.0)
	elif is_v3:
		base_i = maxf(base_i, 1.78)
	elif is_charged:
		base_i = maxf(base_i, 1.35)

	var bp_m: float = maxf(float(mover.get("current_np")) if (mover and is_instance_valid(mover) and mover.get("current_np") != null) else 10000.0, 100.0)
	var bp_o: float = maxf(float(opponent.get("current_np")) if (opponent and is_instance_valid(opponent) and opponent.get("current_np") != null) else 10000.0, 100.0)
	var r_bp: float = bp_m / bp_o
	if r_bp >= 1.35:
		base_i += 0.45
	elif r_bp >= 1.15:
		base_i += 0.25

	if mover and is_instance_valid(mover) and (bool(mover.get("is_in_zenkai_state")) or bool(mover.get("is_in_furia"))):
		base_i += 0.40

	return clampf(base_i, 0.50, 2.50)


func _pick_aggressive_melee_spot(intensity: float, prefer_aerial: bool = false) -> Vector3:
	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var cur_pos: Vector3 = Vector3.ZERO
	if p_node:
		var p_orig: Node3D = p_node.get_parent() as Node3D if p_node.get_parent() is Node3D else null
		cur_pos = (p_orig if p_orig else p_node).global_position

	var r_min: float = 28.0 if intensity >= 1.75 else (18.0 if intensity >= 1.15 else 12.0)
	var r_max: float = 58.0 if intensity >= 1.75 else (38.0 if intensity >= 1.15 else 24.0)
	var r: float = randf_range(r_min, r_max)
	var ang: float = randf_range(0.0, TAU)
	var cx: float = clampf(cos(ang) * r, -64.0, 64.0)
	var cz: float = clampf(sin(ang) * r, -64.0, 64.0)
	if Vector2(cx - cur_pos.x, cz - cur_pos.z).length() < 16.0:
		cx = clampf(-cx, -64.0, 64.0)
		cz = clampf(-cz, -64.0, 64.0)

	var go_high: bool = prefer_aerial or intensity >= 1.75 or (intensity >= 1.15 and randf() < 0.60)
	var cy: float = randf_range(14.0, 26.0) if go_high else randf_range(2.5, 11.5)
	return Vector3(cx, cy, cz)


func _trigger_dynamic_melee_mobility(power_val: float, is_charged: bool, is_v3: bool, is_hammer: bool, mover: Node3D, opponent: Node3D, surge_vec: Vector3, surge_dur: float, prefer_aerial: bool = false) -> void:
	var intensity: float = _compute_melee_mobility_intensity(power_val, is_charged, is_v3, is_hammer, mover, opponent)
	var vanish_prob: float = 0.0
	if intensity >= 1.75:
		vanish_prob = 1.0
	elif intensity >= 1.15:
		vanish_prob = 0.62
	elif intensity >= 0.90:
		vanish_prob = 0.18

	if randf() < vanish_prob:
		var dest: Vector3 = _pick_aggressive_melee_spot(intensity, prefer_aerial or is_v3 or is_hammer)
		perform_z_blink_relocation(dest)
	else:
		var mult: float = 1.85 if intensity >= 1.15 else 1.45
		_apply_melee_arena_surge(surge_vec * mult, surge_dur)


## Teletransporte instantáneo (Z-Blink) por puntos panorámicos de la arena SIN rotar XRCamera3D
func perform_z_blink_relocation(target_pos: Vector3 = Vector3.INF) -> void:
	_surge_active_timer = 0.22
	if _surge_tween and is_instance_valid(_surge_tween):
		_surge_tween.kill()
		_surge_tween = null

	var pair: Array[Node3D] = _get_player_and_ai()
	var p_node: Node3D = pair[0]
	var ai_node: Node3D = pair[1]
	if not p_node or not ai_node:
		return

	var p_orig: Node3D = p_node.get_parent() as Node3D if p_node.get_parent() is Node3D else null
	var p_target: Node3D = p_orig if p_orig else p_node
	var old_pos: Vector3 = p_target.global_position

	var dest: Vector3 = target_pos
	if dest == Vector3.INF:
		_scenic_spot_idx = (_scenic_spot_idx + 1) % SCENIC_ARENA_SPOTS.size()
		dest = SCENIC_ARENA_SPOTS[_scenic_spot_idx]
		if dest.distance_to(old_pos) < 8.0:
			_scenic_spot_idx = (_scenic_spot_idx + 1) % SCENIC_ARENA_SPOTS.size()
			dest = SCENIC_ARENA_SPOTS[_scenic_spot_idx]

	dest.x = clampf(dest.x, -68.0, 68.0)
	dest.z = clampf(dest.z, -68.0, 68.0)
	var gy: float = 0.15
	if p_node.has_method("get_ground_elevation"):
		gy = float(p_node.get_ground_elevation(dest))
	dest.y = clampf(dest.y, maxf(gy, 0.20), 28.0)

	var cam: Camera3D = _get_player_camera()
	var cam_off_xz := Vector3.ZERO
	if cam and is_instance_valid(cam):
		var d_cam: Vector3 = cam.global_position - p_target.global_position
		cam_off_xz = Vector3(d_cam.x, 0.0, d_cam.z)

	if get_tree() and get_tree().current_scene:
		KiSmokeFX.spawn_smoke(get_tree(), old_pos + Vector3(0.0, 0.8, 0.0), 1.0)
		KiSmokeFX.spawn_smoke(get_tree(), dest + Vector3(0.0, 0.8, 0.0), 1.0)

	# Solo desplazar posición global de XROrigin3D/Personaje; NUNCA rotar XRCamera3D
	p_target.global_position = dest
	var axis: Vector3 = _duel_axis if _duel_axis.length_squared() > 0.001 else Vector3.FORWARD
	var ai_pos: Vector3 = dest + cam_off_xz + axis * 0.90
	ai_pos.x = clampf(ai_pos.x, -76.0, 76.0)
	ai_pos.z = clampf(ai_pos.z, -76.0, 76.0)
	ai_pos.y = dest.y
	ai_node.global_position = ai_pos
	if ai_node.has_method("_clamp_to_arena"):
		ai_node._clamp_to_arena(ai_node)

	_update_dome_transform()


func _update_dome_transform() -> void:
	var cam: Camera3D = _get_player_camera()
	if cam and is_instance_valid(cam):
		# Anclar los círculos/cuadrados al eje fijo del duelo (_duel_axis), NO a la rotación de la cabeza
		var duel_dir: Vector3 = _duel_axis
		duel_dir.y = 0.0
		duel_dir = duel_dir.normalized() if duel_dir.length_squared() > 0.001 else Vector3.FORWARD
		var chest_y: float = cam.global_position.y - 0.16
		global_position = Vector3(cam.global_position.x, chest_y, cam.global_position.z) + duel_dir * 0.44
		rotation.y = atan2(-duel_dir.x, -duel_dir.z)
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

	var punch_fwd_w: Vector3 = _get_punch_forward_world()
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")

	var best_zone: Dictionary = {}
	var best_ctrl: XRController3D = null
	var best_hand_name: String = ""
	var best_hand_idx: int = -1
	var best_dist: float = 0.25
	var best_vel: Vector3 = Vector3.ZERO
	var best_vmag: float = 0.0
	var best_stroke_dist: float = 0.0

	for hand_idx in [0, 1]:
		var ctrl: XRController3D = left_ctrl if hand_idx == 0 else right_ctrl
		if not ctrl:
			continue

		var hand_pos: Vector3 = ctrl.global_position
		var hand_loc: Vector3 = ctrl.position
		var cur_depth: float = _get_hand_depth_local(ctrl)
		var cur_vel: Vector3 = left_velocity if hand_idx == 0 else right_velocity
		var v_mag: float = cur_vel.length()
		var fwd_vel: float = cur_vel.dot(punch_fwd_w)

		# Liberar retracción ÚNICAMENTE tras retirar el puño >= 13cm en profundidad o volver a guardia
		if hand_must_retract[hand_idx]:
			if should_release_punch_retraction(_last_hit_depth[hand_idx], cur_depth, fwd_vel):
				hand_must_retract[hand_idx] = false
				_punch_origin_local[hand_idx] = hand_loc
				_punch_origin_depth[hand_idx] = cur_depth
				_punch_origin_init[hand_idx] = true

		# Exigir puño cerrado (Grip+Trigger), no en retracción, y empuje real de jab/directo/gancho
		if hand_must_retract[hand_idx] or not is_fist_closed[hand_idx]:
			continue

		var is_chg_ready: bool = fist_charge_times[hand_idx] >= 0.50
		var stroke_dist: float = hand_loc.distance_to(_punch_origin_local[hand_idx]) if _punch_origin_init[hand_idx] else 0.0
		var fwd_stroke: float = (cur_depth - _punch_origin_depth[hand_idx]) if _punch_origin_init[hand_idx] else 0.0
		var punch_eval: Dictionary = evaluate_real_punch_motion(cur_vel, punch_fwd_w, stroke_dist, fwd_stroke, is_chg_ready)
		if not bool(punch_eval.get("valid", false)):
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
				best_stroke_dist = stroke_dist

	if best_hand_idx != -1 and not best_zone.is_empty():
		attack_step_cooldown = 0.16
		_last_hit_local[best_hand_idx] = best_ctrl.position
		_last_hit_depth[best_hand_idx] = _get_hand_depth_local(best_ctrl)
		_register_hit(best_zone, best_ctrl, best_hand_name, best_hand_idx, best_vel, best_vmag, best_stroke_dist)
		hand_must_retract[best_hand_idx] = true


func _compute_zone_launch_vector(zone_id: int, is_hammer: bool, power_scale: float = 10.0, swing_dir: Vector3 = Vector3.ZERO) -> Vector3:
	var atk_is_p: bool = attacker != null and is_instance_valid(attacker) and bool(attacker.get("is_player"))
	var fwd: Vector3 = _duel_axis if atk_is_p else -_duel_axis
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	var dome_right: Vector3 = global_transform.basis.x if is_inside_tree() else fwd.cross(Vector3.UP)
	dome_right.y = 0.0
	dome_right = dome_right.normalized() if dome_right.length_squared() > 0.01 else fwd.cross(Vector3.UP).normalized()

	if is_hammer:
		return (fwd * 2.8 + Vector3.DOWN * 1.75).normalized() * maxf(power_scale, 13.0)

	if swing_dir.length_squared() > 0.1 and swing_dir.y > 0.45:
		return (fwd * 2.7 + Vector3.UP * 1.45).normalized() * power_scale

	match zone_id:
		0:
			return (fwd * 2.8 + Vector3.UP * 1.40).normalized() * power_scale
		1:
			return (fwd * 3.6 + Vector3.UP * 0.40).normalized() * power_scale
		2:
			return (-dome_right * 2.4 + fwd * 1.8 + Vector3.UP * 1.4).normalized() * power_scale
		3:
			return (dome_right * 2.4 + fwd * 1.8 + Vector3.UP * 1.4).normalized() * power_scale
		4:
			return (-dome_right * 2.6 + fwd * 1.6 + Vector3.UP * 0.25).normalized() * power_scale
		5:
			return (dome_right * 2.6 + fwd * 1.6 + Vector3.UP * 0.25).normalized() * power_scale
	return (fwd * 2.5 + Vector3.UP * 0.5).normalized() * power_scale


func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String, hand_idx: int, cur_vel: Vector3, v_mag: float, stroke_dist: float = 0.28) -> void:
	zone["cooldown"] = 0.28
	var hit_pos: Vector3 = zone["node"].global_position

	var charge_t: float = fist_charge_times[hand_idx]
	var is_v3: bool = charge_t >= 1.10
	var is_charged: bool = charge_t >= 0.50

	var cfg_ki: KiEconomyConfig = KiEconomyConfig.get_default()
	var q_cost: float = float(cfg_ki.melee_quick_cost)
	var chg_cost: float = float(cfg_ki.melee_charged_cost)
	var v3_cost: float = float(cfg_ki.melee_v3_cost)
	var atk_ki: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0

	if is_v3 and atk_ki < v3_cost:
		is_v3 = false
		if atk_ki < chg_cost:
			is_charged = false
		_spawn_impact_popup(hit_pos, "⚠️ ¡KI INSUFICIENTE PARA V3!", Color(1.0, 0.55, 0.15))
	elif is_charged and atk_ki < chg_cost:
		is_charged = false
		_spawn_impact_popup(hit_pos, "⚠️ ¡KI INSUFICIENTE PARA CARGADO!", Color(1.0, 0.55, 0.15))

	if atk_ki < q_cost:
		fist_charge_times[hand_idx] = 0.0
		fist_locked_haptic[hand_idx] = false
		fist_v3_locked_haptic[hand_idx] = false
		_update_hand_charge_sphere(hand_idx, ctrl_node, 0.0)
		if hits.size() >= 1:
			_begin_phase_transition("start_defense", 0.45, "⚡ ¡SIN KI — EJECUTANDO %d GOLPES!" % hits.size(), Color(1.0, 0.75, 0.2))
		else:
			_spawn_impact_popup(hit_pos, "⚠️ ¡SIN KI!", Color(1.0, 0.25, 0.15))
		return

	var tier_info: Dictionary = classify_melee_punch_tier(stroke_dist, v_mag, is_charged or is_v3)
	var tier_name: String = String(tier_info.get("tier", "SOLIDO"))
	var tier_dmg_mult: float = float(tier_info.get("dmg_mult", 1.0))
	var tier_refund: float = 0.0 if is_v3 else float(tier_info.get("ki_refund", 0.0))

	var ki_cost: float = v3_cost if is_v3 else (chg_cost if is_charged else q_cost)
	_modify_fighter_ki(attacker, -ki_cost)

	var swing_dir: Vector3 = cur_vel.normalized() if cur_vel.length_squared() > 0.01 else -global_transform.basis.z
	var z_id: int = int(zone["id"])
	var v3_mode: String = "UP" if (is_v3 and (swing_dir.y > 0.25 or z_id == 0)) else "BACK"
	var punch_power: float = compute_melee_kinetic_power(stroke_dist, v_mag, is_charged, is_v3)
	var note_launch_vec: Vector3 = _compute_zone_launch_vector(z_id, false, 11.0 if is_v3 else (8.5 if is_charged else 5.5), swing_dir)

	last_impact_vector = note_launch_vec

	var clean_time_offset: float = float(hits.size() + 1) * NOTE_CADENCE_SEC
	hits.append({
		"zone_id": z_id,
		"name": "Cargado v3 (%s)" % ("Arriba" if v3_mode == "UP" else "Atrás") if is_v3 else String(zone["name"]),
		"pos": hit_pos,
		"hand": hand_name,
		"time_offset": clean_time_offset,
		"power": punch_power,
		"stroke_dist": stroke_dist,
		"tier": tier_name,
		"tier_dmg_mult": tier_dmg_mult,
		"ki_refund": tier_refund,
		"is_charged": is_charged,
		"is_charged_v3": is_v3,
		"is_hammer": false,
		"v3_launch_mode": v3_mode,
		"launch_vec": note_launch_vec,
		"velocity": v_mag,
		"swing_dir": swing_dir,
		"defense_score": 0.0,
		"resolved": false
	})

	var role_lbl: String = "🔥 ¡V3 ROMPE X!" if is_v3 else ("💥 ¡CARGADO!" if is_charged else String(tier_info.get("label", "💥 ¡SÓLIDO!")))
	var flash_col: Color = Color(1.0, 0.28, 0.12) if is_v3 else (Color(1.0, 0.55, 0.15) if is_charged else (tier_info.get("color", Color.WHITE) as Color))
	_spawn_declaration_mark(hit_pos, flash_col)
	_spawn_impact_popup(hit_pos, role_lbl, flash_col)
	if tier_name == "SONICO":
		_round_sonic_hits += 1
	if is_charged or is_v3:
		_round_charged_hits += 1

	var orig_col: Color = zone["color"] as Color
	var tint_col: Color = Color(1.0, 0.2, 0.1) if is_v3 else (Color(1.0, 0.45, 0.1) if is_charged else Color(1.0, 1.0, 0.4))
	_tint_zone_shapes(zone, tint_col, tint_col, 4.5 if is_charged else 3.0, Color(1.0, 1.0, 1.0, 0.96))
	var circ_inst: MeshInstance3D = zone.get("circle_mesh") as MeshInstance3D
	var ring_inst: MeshInstance3D = zone.get("circle_ring") as MeshInstance3D
	var box_inst: MeshInstance3D = zone.get("box_mesh") as MeshInstance3D
	if zone.get("node") and is_instance_valid(zone["node"]) and is_inside_tree():
		var tw := create_tween().set_parallel(true)
		tw.tween_property(zone["node"], "scale", Vector3.ONE * (1.45 if is_charged else 1.28), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(zone["node"], "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		for shape_inst in [box_inst, circ_inst, ring_inst]:
			if shape_inst and is_instance_valid(shape_inst):
				var smat := shape_inst.material_override as StandardMaterial3D
				if smat:
					var target_alpha: float = 0.90 if shape_inst == ring_inst else 0.58
					tw.parallel().tween_property(smat, "albedo_color", Color(orig_col.r, orig_col.g, orig_col.b, target_alpha), 0.14)
					tw.parallel().tween_property(smat, "emission", Color(orig_col.r, orig_col.g, orig_col.b), 0.14)
					tw.parallel().tween_property(smat, "emission_energy_multiplier", 1.25, 0.14)

	if audio_player:
		audio_player.global_position = hit_pos
		audio_player.pitch_scale = randf_range(0.95, 1.12)
		var hit_act: String = "common.melee_hit_heavy" if (is_charged or is_v3 or tier_name == "SONICO") else "common.melee_hit_light"
		AudioActionManager.play_action(hit_act, audio_player)

	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		var is_heavy_decl: bool = is_charged or is_v3 or tier_name == "SONICO"
		ctrl_node.trigger_haptic_pulse("haptic", 150.0 if is_heavy_decl else 130.0, 0.60 if is_heavy_decl else 0.40, 0.08 if is_heavy_decl else 0.04, 0.0)

	fist_charge_times[hand_idx] = 0.0
	fist_locked_haptic[hand_idx] = false
	fist_v3_locked_haptic[hand_idx] = false
	_update_hand_charge_sphere(hand_idx, ctrl_node, 0.0)

	emit_signal("target_hit", hits.size(), String(zone["name"]), hit_pos, is_charged, punch_power)

	current_attack_step += 1
	_update_sequential_target_highlights(z_id)

	# Auto-cierre inteligente si el Ki restante ya no alcanza para otro golpe rápido, o al completar el combo
	var atk_ki_left: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0
	if atk_ki_left < q_cost or current_attack_step >= max_allowed_hits:
		var msg_tag: String = "🔥 ¡CARGADO V3 EN COMBO!" if is_v3 else "💥 ¡SECUENCIA REGISTRADA!"
		if atk_ki_left < q_cost and current_attack_step < max_allowed_hits:
			msg_tag = "⚡ ¡KI AL LÍMITE — EJECUTANDO %d GOLPES!" % hits.size()
		elif current_attack_step >= max_allowed_hits and hits.size() >= max_allowed_hits:
			_declared_full_combo = true
			msg_tag = "💥 ¡SECUENCIA COMPLETA (%d GOLPES)!" % hits.size()
		_begin_phase_transition("start_defense", 0.50, msg_tag, Color(1.0, 0.75, 0.2))


func _check_hammer_finisher() -> bool:
	if not hammer_primed and hammer_charge_time < HAMMER_CHARGE_REQ:
		return false
	if current_attack_step >= max_allowed_hits or attack_step_cooldown > 0.0 or target_zones.size() <= 1:
		return false

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false
	if not is_fist_closed[0] or not is_fist_closed[1] or left_ctrl.global_position.distance_to(right_ctrl.global_position) > 0.42:
		return false

	var down_l: float = -left_velocity.y
	var down_r: float = -right_velocity.y
	var avg_down: float = (down_l + down_r) * 0.5
	var peak_speed: float = maxf(left_velocity.length(), right_velocity.length())

	if avg_down > 0.55 or down_l > 0.65 or down_r > 0.65 or (avg_down > 0.40 and peak_speed > 0.95):
		var cfg_hm: KiEconomyConfig = KiEconomyConfig.get_default()
		var hm_cost: float = float(cfg_hm.melee_hammer_cost) if cfg_hm.get("melee_hammer_cost") != null else 15.0
		var atk_ki_before: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		if atk_ki_before < hm_cost:
			hammer_charge_time = 0.0
			hammer_primed = false
			hammer_locked_haptic = false
			_spawn_impact_popup(target_zones[1]["node"].global_position, "⚠️ ¡KI INSUFICIENTE (-%d Ki)!" % int(hm_cost), Color(1.0, 0.35, 0.25))
			return false
		hammer_ki_paid = true
		_modify_fighter_ki(attacker, -hm_cost)

		var hammer_pos: Vector3 = target_zones[1]["node"].global_position
		var hm_launch: Vector3 = _compute_zone_launch_vector(1, true, 13.0)
		last_impact_vector = hm_launch

		var clean_time_offset: float = float(hits.size() + 1) * NOTE_CADENCE_SEC
		hits.append({
			"zone_id": 1,
			"name": "Martillazo DBZ",
			"pos": hammer_pos,
			"hand": "BothHands",
			"time_offset": clean_time_offset,
			"power": 4.5,
			"ki_refund": 0.0,
			"is_charged": true,
			"is_charged_v3": false,
			"is_hammer": true,
			"v3_launch_mode": "DOWN",
			"launch_vec": hm_launch,
			"velocity": maxf(peak_speed, 3.2),
			"swing_dir": Vector3.DOWN,
			"defense_score": 0.0,
			"resolved": false
		})

		hammer_charge_time = 0.0
		hammer_primed = false
		hammer_locked_haptic = false
		fist_charge_times = [0.0, 0.0]
		fist_locked_haptic = [false, false]
		fist_v3_locked_haptic = [false, false]
		hand_must_retract = [true, true]
		_last_hit_local = [left_ctrl.position, right_ctrl.position]
		_last_hit_depth = [_get_hand_depth_local(left_ctrl), _get_hand_depth_local(right_ctrl)]
		_hide_all_charge_spheres()
		current_attack_step += 1
		attack_step_cooldown = 0.16
		_spawn_declaration_mark(hammer_pos, Color(0.95, 0.35, 1.0))
		_spawn_impact_popup(hammer_pos, "🔨 ¡MARTILLAZO REGISTRADO!", Color(0.95, 0.35, 1.0))
		if audio_player:
			audio_player.global_position = hammer_pos
			audio_player.pitch_scale = 0.92
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player)
		_pulse_player_both_hands(175.0, 0.72, 0.12)
		emit_signal("target_hit", hits.size(), "Martillazo DBZ", hammer_pos, true, 4.5)
		var atk_ki_hm: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0
		var min_q_hm: float = float(cfg_hm.melee_quick_cost) if cfg_hm.get("melee_quick_cost") != null else 3.0
		if current_attack_step >= max_allowed_hits or atk_ki_hm < min_q_hm:
			var msg_hm: String = "🔨 ¡MARTILLAZO DBZ LISTO!"
			if current_attack_step >= max_allowed_hits and hits.size() >= max_allowed_hits:
				_declared_full_combo = true
				msg_hm = "🔨 ¡MARTILLAZO + COMBO REGISTRADO!"
			_begin_phase_transition("start_defense", 0.50, msg_hm, Color(0.95, 0.35, 1.0))
		else:
			_update_sequential_target_highlights()
		return true

	return false


# ==============================================================================
# AUXILIARES DE MANDOS, CARGA EN PUÑO Y EFECTOS VISUALES
# ==============================================================================

func _get_controller(hand_name: String) -> XRController3D:
	if hand_name == "LeftHand" and _cached_left_ctrl and is_instance_valid(_cached_left_ctrl):
		return _cached_left_ctrl
	if hand_name == "RightHand" and _cached_right_ctrl and is_instance_valid(_cached_right_ctrl):
		return _cached_right_ctrl
	for f_chk in [attacker, defender]:
		if f_chk and is_instance_valid(f_chk) and bool(f_chk.get("is_player")):
			var p: Node = f_chk.get_parent()
			if p:
				var c: XRController3D = p.get_node_or_null(hand_name) as XRController3D
				if c:
					if hand_name == "LeftHand":
						_cached_left_ctrl = c
					else:
						_cached_right_ctrl = c
					return c
	if attacker and is_instance_valid(attacker):
		var p_a: Node = attacker.get_parent()
		if p_a:
			var c_a: XRController3D = p_a.get_node_or_null(hand_name) as XRController3D
			if c_a:
				return c_a
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

	var real_dt: float = maxf(delta / maxf(Engine.time_scale, 0.01), 0.001)
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	var p_node: Node3D = attacker if (attacker and is_instance_valid(attacker) and attacker.get("is_player")) else (defender if (defender and is_instance_valid(defender) and defender.get("is_player")) else null)
	var origin: XROrigin3D = _cached_xr_origin if (_cached_xr_origin and is_instance_valid(_cached_xr_origin)) else (p_node.get_parent() as XROrigin3D if (p_node and p_node.get_parent() is XROrigin3D) else null)
	var orig_basis: Basis = origin.global_transform.basis.orthonormalized() if (origin and is_instance_valid(origin)) else Basis.IDENTITY

	var l_loc: Vector3 = left_ctrl.position if left_ctrl else Vector3.ZERO
	var r_loc: Vector3 = right_ctrl.position if right_ctrl else Vector3.ZERO

	if _has_prev_atk_local:
		if left_ctrl:
			left_velocity = orig_basis * ((l_loc - _prev_l_local) / real_dt)
		if right_ctrl:
			right_velocity = orig_basis * ((r_loc - _prev_r_local) / real_dt)
	_prev_l_local = l_loc
	_prev_r_local = r_loc
	_has_prev_atk_local = true

	var punch_fwd_c: Vector3 = _get_punch_forward_world()
	if left_ctrl:
		var l_fwd_v: float = left_velocity.dot(punch_fwd_c)
		if not hand_must_retract[0] and (not _punch_origin_init[0] or l_fwd_v <= 0.15):
			_punch_origin_local[0] = l_loc
			_punch_origin_depth[0] = _get_hand_depth_local(left_ctrl)
			_punch_origin_init[0] = true
	if right_ctrl:
		var r_fwd_v: float = right_velocity.dot(punch_fwd_c)
		if not hand_must_retract[1] and (not _punch_origin_init[1] or r_fwd_v <= 0.15):
			_punch_origin_local[1] = r_loc
			_punch_origin_depth[1] = _get_hand_depth_local(right_ctrl)
			_punch_origin_init[1] = true


func _update_fist_states(delta: float, is_charging_hammer: bool) -> void:
	for i in [0, 1]:
		var hand_name: String = "LeftHand" if i == 0 else "RightHand"
		var c: XRController3D = _get_controller(hand_name)
		if not c:
			is_fist_closed[i] = false
			continue

		var trig_val: float = _ctrl_float(c, &"trigger")
		var grip_val: float = _ctrl_float(c, &"grip")
		var strictly_closed: bool = (trig_val > 0.50 and grip_val > 0.50) or (_ctrl_pressed(c, &"trigger_click") and _ctrl_pressed(c, &"grip_click"))

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
		elif is_charging_hammer:
			_update_hand_charge_sphere(i, c, 0.0)
		elif not eff_closed:
			fist_charge_times[i] = 0.0
			fist_locked_haptic[i] = false
			fist_v3_locked_haptic[i] = false
			_punch_origin_local[i] = c.position
			_punch_origin_depth[i] = _get_hand_depth_local(c)
			_punch_origin_init[i] = true
			_update_hand_charge_sphere(i, c, 0.0)
		else:
			_update_hand_charge_sphere(i, c, fist_charge_times[i])


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
			charge_spheres[i].visible = false


func _process_hammer_charge(delta: float) -> bool:
	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var hands_dist: float = left_ctrl.global_position.distance_to(right_ctrl.global_position)
	var cam: Camera3D = _get_player_camera()
	var cam_pos: Vector3 = cam.global_position if cam else global_position
	var avg_pos: Vector3 = (left_ctrl.global_position + right_ctrl.global_position) * 0.5
	var rel_y: float = avg_pos.y - cam_pos.y

	var l_closed: bool = (_ctrl_float(left_ctrl, &"trigger") > 0.50 and _ctrl_float(left_ctrl, &"grip") > 0.50) or (_ctrl_pressed(left_ctrl, &"trigger_click") and _ctrl_pressed(left_ctrl, &"grip_click"))
	var r_closed: bool = (_ctrl_float(right_ctrl, &"trigger") > 0.50 and _ctrl_float(right_ctrl, &"grip") > 0.50) or (_ctrl_pressed(right_ctrl, &"trigger_click") and _ctrl_pressed(right_ctrl, &"grip_click"))
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


func _spawn_declaration_mark(pos: Vector3, col: Color) -> void:
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, col, 0.42)


func _spawn_hit_spark(pos: Vector3) -> void:
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, Color(1.0, 0.84, 0.30, 1.0), 0.72)


func _spawn_block_spark(pos: Vector3, col: Color) -> void:
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, col, 0.65)


func _spawn_parry_shockwave(pos: Vector3) -> void:
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), pos, 1, Color(1.0, 0.92, 0.30, 0.95), false)
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, Color(1.0, 0.96, 0.48, 1.0), 1.05)


func _exit_tree() -> void:
	_kill_surge_tween()
	if _impact_popup_tween and is_instance_valid(_impact_popup_tween):
		_impact_popup_tween.kill()
		_impact_popup_tween = null
	if _active_impact_popup and is_instance_valid(_active_impact_popup):
		_active_impact_popup.queue_free()
		_active_impact_popup = null
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	for i in [0, 1]:
		if charge_spheres[i] and is_instance_valid(charge_spheres[i]):
			charge_spheres[i].queue_free()
			charge_spheres[i] = null
	_lore_ctrl = null
	if _ki_bar_root and is_instance_valid(_ki_bar_root):
		_ki_bar_root.queue_free()
		_ki_bar_root = null
	if melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		melee_hud_anchor.queue_free()
		melee_hud_anchor = null
	if melee_boxes_anchor and is_instance_valid(melee_boxes_anchor):
		melee_boxes_anchor.queue_free()
		melee_boxes_anchor = null
	if action_card_anchor and is_instance_valid(action_card_anchor):
		action_card_anchor.queue_free()
		action_card_anchor = null
