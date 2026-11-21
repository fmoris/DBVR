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

# Velocidades de atacante y defensor (calculadas en espacio local XR para inmunidad al Arena Surge)
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO
var def_prev_left_pos: Vector3 = Vector3.ZERO
var def_prev_right_pos: Vector3 = Vector3.ZERO
var def_left_velocity: Vector3 = Vector3.ZERO
var def_right_velocity: Vector3 = Vector3.ZERO
var _prev_l_local: Vector3 = Vector3.ZERO
var _prev_r_local: Vector3 = Vector3.ZERO
var _has_prev_atk_local: bool = false
var _def_prev_l_local: Vector3 = Vector3.ZERO
var _def_prev_r_local: Vector3 = Vector3.ZERO
var _has_prev_def_local: bool = false
var _punch_origin_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _punch_origin_init: Array[bool] = [false, false]
var _last_hit_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _pending_finisher_mode: String = ""
var _pending_finisher_vel: float = 0.0

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
var _surge_tween: Tween = null
var charge_spheres: Array[MeshInstance3D] = [null, null]

# Overhaul Melee: Eventos Lore, Ki HUD, Semáforo y Control Físico (zero-alloc)
var _lore_ctrl: Node3D = null
var _last_lore_event_type: int = 0
var _lore_return_mode: String = ""
var _scenic_spot_idx: int = 0
var hammer_ki_paid: bool = false
var _round_sonic_hits: int = 0
var _round_unblocked_hits_taken: int = 0
var _surge_active_timer: float = 0.0
var _timing_cue_note_idx: int = -1
var _def_stick_used_for_note_idx: int = -1
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

# Parámetros de Defensa Rítmica (0.90s por nota para mayor agilidad)
const NOTE_CADENCE_SEC: float = 0.90
const RING_PREWARN_SEC: float = 0.85
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
	{ "id": 0, "name": "Rostro / Cabeza", "offset": Vector3(0.0, 0.20, 0.0), "color": Color(1.0, 0.3, 0.2, 0.85) },
	{ "id": 1, "name": "Plexo Solar", "offset": Vector3(0.0, -0.01, 0.0), "color": Color(0.2, 0.85, 1.0, 0.85) },
	{ "id": 2, "name": "Hombro Izquierdo", "offset": Vector3(-0.19, 0.17, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 3, "name": "Hombro Derecho", "offset": Vector3(0.19, 0.17, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 4, "name": "Flanco Izquierdo", "offset": Vector3(-0.19, -0.15, 0.0), "color": Color(1.0, 0.55, 0.15, 0.85) },
	{ "id": 5, "name": "Flanco Derecho", "offset": Vector3(0.19, -0.15, 0.0), "color": Color(1.0, 0.55, 0.15, 0.85) }
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

	sfx_hit_light = null
	sfx_hit_heavy = null
	sfx_parry = null

	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BulletTimeAudio"
	audio_player.unit_size = 5.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

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
	var sonic_ref: float = float(cfg.melee_sonic_ki_refund) if cfg.get("melee_sonic_ki_refund") != null else 1.5
	if (speed_mps >= 2.85 and stroke_dist >= 0.30) or (is_charged and speed_mps >= 2.40 and stroke_dist >= 0.28):
		return {
			"tier": "SONICO",
			"label": "⚡ ¡SÓNICO!",
			"dmg_mult": 1.35,
			"ki_refund": sonic_ref,
			"color": Color(1.0, 0.92, 0.25)
		}
	if (speed_mps >= 1.95 and stroke_dist >= 0.24) or (is_charged and speed_mps >= 1.60):
		return {
			"tier": "SOLIDO",
			"label": "💥 ¡SÓLIDO!",
			"dmg_mult": 1.00,
			"ki_refund": 0.0,
			"color": Color(1.0, 0.50, 0.15)
		}
	return {
		"tier": "SUAVE",
		"label": "~ Suave",
		"dmg_mult": 0.60,
		"ki_refund": 0.0,
		"color": Color(0.65, 0.72, 0.80)
	}


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
	_punch_origin_init = [false, false]
	_pending_finisher_mode = ""
	_pending_finisher_vel = 0.0
	hammer_charge_time = 0.0
	hammer_primed = false
	hammer_locked_haptic = false
	hammer_ki_paid = false
	_round_sonic_hits = 0
	_round_unblocked_hits_taken = 0
	_timing_cue_note_idx = -1
	_def_stick_used_for_note_idx = -1
	_set_target_zones_visible(true)
	_hide_all_charge_spheres()
	_refresh_melee_ki_bar()

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
		_apply_role_dome_tint(false)
		_generate_planned_attack_sequence(max_allowed_hits)
		generate_ai_attack_sequence()
		_begin_phase_transition("start_defense", 0.55, "🛡️ ¡TURNO DE DEFENSA! (%d GOLPES)" % hits.size(), Color(0.25, 0.88, 1.0))
	else:
		_apply_role_dome_tint(true)
		planned_attack_zones.clear()
		_update_sequential_target_highlights()
		_refresh_header_hud()

	print("[BulletTimeDome] Ataque listo: %d golpes permitidos en %.2fs." % [max_allowed_hits, duration])


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
	action_card_anchor.position = Vector3(0.0, -0.36, -1.10)
	action_card_anchor.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	cam.add_child(action_card_anchor)

	var border := MeshInstance3D.new()
	border.name = "CardBorder"
	var b_q := QuadMesh.new()
	b_q.size = Vector2(0.58, 0.25)
	border.mesh = b_q
	_action_card_border_mat = StandardMaterial3D.new()
	_action_card_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_action_card_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_action_card_border_mat.no_depth_test = false
	_action_card_border_mat.render_priority = 10
	_action_card_border_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.90)
	border.material_override = _action_card_border_mat
	action_card_anchor.add_child(border)

	var bg := MeshInstance3D.new()
	bg.name = "CardBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.565, 0.235)
	bg.mesh = bg_q
	bg.position = Vector3(0.0, 0.0, 0.001)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = false
	bg_mat.render_priority = 11
	bg_mat.albedo_color = Color(0.03, 0.06, 0.11, 0.88)
	bg.material_override = bg_mat
	action_card_anchor.add_child(bg)

	_action_card_label = Label3D.new()
	_action_card_label.name = "MeleeCardText"
	_action_card_label.font_size = 21
	_action_card_label.pixel_size = 0.00125
	_action_card_label.no_depth_test = false
	_action_card_label.render_priority = 12
	_action_card_label.outline_size = 6
	_action_card_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_action_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_action_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_card_label.position = Vector3(-0.26, 0.0, 0.002)
	action_card_anchor.add_child(_action_card_label)


func _update_action_card(is_attack_mode: bool) -> void:
	_ensure_action_card()
	if not _action_card_label or not is_instance_valid(_action_card_label):
		return
	if is_attack_mode:
		if _action_card_border_mat:
			_action_card_border_mat.albedo_color = Color(1.0, 0.52, 0.15, 0.90)
		_action_card_label.modulate = Color(1.0, 0.93, 0.72)
		_action_card_label.text = "⚔️ ATACAR (⭕ CÍRCULOS) | Administra tu Ki\n• Puño (G+T) + Golpe veloz: -5 Ki (Sónico +1.5)\n• Mantén 0.5s: Cargado (-11) | 1.1s: V3 (-16)\n• 2 Puños Arriba→Abajo: Martillazo (-22 Ki)\n• Stick ↓: Cancelar y ahorrar Ki"
	else:
		if _action_card_border_mat:
			_action_card_border_mat.albedo_color = Color(0.20, 0.88, 1.0, 0.90)
		_action_card_label.modulate = Color(0.88, 0.97, 1.0)
		_action_card_label.text = "🛡️ DEFENDER (⬜ CUADRADOS) | Aro Verde/Oro = ¡YA!\n• Palma o Trig en ⬜ a tiempo: Desvío (+5 Ki)\n• Aro Dorado (≤0.14s): Parry Perfecto (+14 Ki)\n• Guardia X pecho: -7~20 Ki | Stick: Z-Vanish (-14)\n• Abre brazos + 2 Grips (tras 2 golpes): Kiai (-22)"


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
	if _active_impact_popup and is_instance_valid(_active_impact_popup):
		_active_impact_popup.queue_free()
		_active_impact_popup = null
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 28
	lbl.pixel_size = 0.0014
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	lbl.no_depth_test = true
	lbl.render_priority = 126
	_active_impact_popup = lbl

	if not force_camera_child and melee_hud_anchor and is_instance_valid(melee_hud_anchor):
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		melee_hud_anchor.add_child(lbl)
		lbl.position = Vector3(0.0, -0.11, 0.0)
		var tw_h: Tween = lbl.create_tween().set_parallel(true)
		tw_h.tween_property(lbl, "position:y", -0.04, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_h.tween_property(lbl, "modulate:a", 0.0, 0.45).set_delay(0.14)
		tw_h.chain().tween_callback(lbl.queue_free)
		return

	var cam: Camera3D = _get_player_camera()
	if not cam or not is_instance_valid(cam):
		lbl.queue_free()
		return
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	cam.add_child(lbl)
	lbl.position = Vector3(0.0, 0.10, -1.15)
	var tw: Tween = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", 0.18, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_delay(0.16)
	tw.chain().tween_callback(lbl.queue_free)


func _begin_phase_transition(mode: String, wait_sec: float, msg: String, col: Color) -> void:
	phase = DomePhase.PHASE_TRANSITION
	transition_on_complete_mode = mode
	var ai_defending: bool = (mode == "start_defense") and defender != null and is_instance_valid(defender) and not bool(defender.get("is_player"))
	var min_wait: float = 0.16 if ai_defending else 0.45
	var actual_wait: float = minf(wait_sec, 0.18) if ai_defending else wait_sec
	# Pausa mínima de 0.45s para jugador (legibilidad) y 0.16s-0.18s cuando defiende la IA (agilidad)
	transition_timer = maxf(actual_wait, min_wait) if mode in ["start_defense", "restart_attacker", "continue_offense"] else wait_sec
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
	if audio_player:
		audio_player.pitch_scale = 1.15 if player_will_attack else 0.85
		AudioActionManager.play_action("common.block_perfect", audio_player, sfx_parry)
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


func _update_sequential_target_highlights() -> void:
	var player_free_choice: bool = attacker != null and is_instance_valid(attacker) and bool(attacker.get("is_player"))
	if player_free_choice:
		for zone in target_zones:
			var z_id: int = int(zone["id"])
			var z_node: Node3D = zone["node"] as Node3D
			var step_lbl: Label3D = zone.get("step_label") as Label3D
			var orig_col: Color = zone["color"] as Color

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
		return

	var active_zone_id: int = -1
	if current_attack_step >= 0 and current_attack_step < planned_attack_zones.size() and current_attack_step < max_allowed_hits:
		active_zone_id = planned_attack_zones[current_attack_step]

	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color
		if z_node and is_instance_valid(z_node):
			z_node.visible = true

		if z_id == active_zone_id:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 1.15
			_tint_zone_shapes(zone, Color(orig_col.r, orig_col.g, orig_col.b, 0.92), Color(orig_col.r, orig_col.g, orig_col.b), 2.0, Color(1.0, 1.0, 1.0, 0.92))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = str(current_attack_step + 1)
				step_lbl.modulate = Color(1.0, 0.95, 0.25, 1.0)
				step_lbl.visible = true
		else:
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * 0.72
			_tint_zone_shapes(zone, Color(orig_col.r, orig_col.g, orig_col.b, 0.12), Color(orig_col.r, orig_col.g, orig_col.b), 0.15, Color(1.0, 1.0, 1.0, 0.12))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.visible = false


func _update_defense_zone_highlights(active_zone_id: int, step_num: int, next_zone_id: int = -1, is_heavy_note: bool = false, is_hammer_note: bool = false) -> void:
	for zone in target_zones:
		var z_id: int = int(zone["id"])
		var z_node: Node3D = zone["node"] as Node3D
		var step_lbl: Label3D = zone.get("step_label") as Label3D
		var orig_col: Color = zone["color"] as Color
		if z_node and is_instance_valid(z_node):
			z_node.visible = true

		if z_id == active_zone_id:
			var hi_col: Color = Color(0.95, 0.2, 1.0, 0.95) if is_hammer_note else (Color(1.0, 0.4, 0.15, 0.95) if is_heavy_note else Color(0.2, 0.92, 1.0, 0.95))
			if z_node and is_instance_valid(z_node):
				z_node.scale = Vector3.ONE * (1.28 if is_hammer_note else 1.15)
			_tint_zone_shapes(zone, hi_col, Color(hi_col.r, hi_col.g, hi_col.b), 2.2, Color(1.0, 1.0, 1.0, 0.92))
			if step_lbl and is_instance_valid(step_lbl):
				step_lbl.text = "🔨" if is_hammer_note else str(step_num)
				step_lbl.modulate = Color(1.0, 0.95, 0.3, 1.0) if is_hammer_note else Color(0.3, 0.95, 1.0, 1.0)
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

		var tut: String = "\nPuño(G+T)=Golpe | Stick↓=Cancelar" if not _tutorial_controls_shown else ""
		header_label.text = "⚔️ ATACAS (%d/%d)%s  [%s]%s%s" % [step_shown, max_allowed_hits, charge_tag, bar_str, fb_line, tut]
	elif phase == DomePhase.DEFENSE_RHYTHM:
		var pips: String = _get_pips_string(hits.size())
		if defender and defender.get("is_player"):
			_apply_role_dome_tint(false)
			header_label.modulate = Color(0.25, 0.90, 1.0)
			var def_ki_now: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
			var kiai_hint: String = "\n🔥 ¡ABRE BRAZOS+2 GRIPS=ONDA KIAI (-22 Ki)!" if (_round_unblocked_hits_taken >= 2 and def_ki_now >= 22.0) else ""
			var tut_def: String = "\nAro Verde/Oro=¡YA! | Stick=Z-Vanish" if not _tutorial_controls_shown else ""
			header_label.text = "🛡️ DEFIENDES (%d/%d) %s  %s%s%s%s" % [step_num, hits.size(), active_zone_name, pips, fb_line, kiai_hint, tut_def]
		else:
			_apply_role_dome_tint(true)
			header_label.modulate = Color(1.0, 0.55, 0.20)
			header_label.text = "⚔️ ATACAS (%d/%d) %s  %s%s" % [step_num, hits.size(), active_zone_name, pips, fb_line]


# ==============================================================================
# FASE 2: DEFENSA RÍTMICA SECUENCIAL (1.25s POR GOLPE)
# ==============================================================================

func _compute_note_prewarn_sec(note: Dictionary) -> float:
	var vel: float = float(note.get("velocity", 1.8))
	var base_t: float = clampf(0.95 - (vel - 1.2) * 0.08, 0.65, 0.95)
	if bool(note.get("is_hammer", false)):
		base_t = 1.70
	elif bool(note.get("is_charged_v3", false)):
		base_t = 1.55
	elif bool(note.get("is_charged", false)):
		base_t = 1.35

	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and is_instance_valid(attacker) and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if (defender and is_instance_valid(defender) and defender.get("current_np") != null) else 10000.0, 100.0)
	var bp_factor: float = clampf(pow(bp_def / bp_atk, 0.35), 0.65, 1.55)
	return clampf(base_t * bp_factor, 0.50, 2.60)


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
	_round_unblocked_hits_taken = 0
	defense_score_sum = 0.0
	defense_round_total_hits = hits.size()
	def_prev_left_pos = Vector3.ZERO
	def_prev_right_pos = Vector3.ZERO
	def_left_velocity = Vector3.ZERO
	def_right_velocity = Vector3.ZERO
	_has_prev_def_local = false
	_pending_finisher_mode = ""
	_pending_finisher_vel = 0.0
	_set_target_zones_visible(true)
	_reset_all_timing_rings()
	_apply_role_dome_tint(not bool(defender and is_instance_valid(defender) and defender.get("is_player")))
	_refresh_melee_ki_bar()

	var def_is_ai: bool = defender != null and is_instance_valid(defender) and not bool(defender.get("is_player"))
	var accum_time: float = 0.0
	for h in hits:
		if def_is_ai:
			var is_heavy_h: bool = bool(h.get("is_charged", false)) or bool(h.get("is_charged_v3", false)) or bool(h.get("is_hammer", false))
			var ai_gap: float = 0.36 if is_heavy_h else 0.26
			h["prewarn_sec"] = minf(_compute_note_prewarn_sec(h), ai_gap)
			accum_time += (0.16 if accum_time == 0.0 else ai_gap)
		else:
			var prewarn: float = _compute_note_prewarn_sec(h)
			h["prewarn_sec"] = prewarn
			accum_time += prewarn + 0.16
		h["time_offset"] = accum_time
	defense_total_duration = accum_time + (0.28 if def_is_ai else 0.90)

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

	# Onda Explosiva (Kiai de Emergencia) al recibir >= 2 golpes sin bloquear en la ronda y tener >= 22 Ki
	if defender_is_player and _round_unblocked_hits_taken >= 2 and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var def_orig: XROrigin3D = defender.get_parent() as XROrigin3D
		if def_orig:
			var l_c: XRController3D = def_orig.get_node_or_null("LeftHand") as XRController3D
			var r_c: XRController3D = def_orig.get_node_or_null("RightHand") as XRController3D
			if l_c and r_c and def_grip_l and def_grip_r and l_c.global_position.distance_to(r_c.global_position) >= 0.75:
				var def_ki_ew: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
				var ew_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
					"trigger_source": "explosive_wave_input",
					"def_ki": def_ki_ew,
					"consecutive_hits_taken": _round_unblocked_hits_taken
				})
				if ew_ev == MeleeLoreEventScript.LoreEventType.EXPLOSIVE_WAVE:
					_start_lore_event(ew_ev, "explosive_wave")
					return

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

		# Semáforo claro de timing (Cian/Violeta Espera -> Verde <= 0.24s ¡YA! -> Dorado <= 0.14s PARRY)
		var note_prewarn: float = float(active_note.get("prewarn_sec", RING_PREWARN_SEC))
		if t_diff >= -0.24 and t_diff <= note_prewarn:
			if active_ring and is_instance_valid(active_ring):
				active_ring.visible = true
				var t_factor: float = clampf(maxf(t_diff, 0.0) / maxf(note_prewarn, 0.01), 0.0, 1.0)
				var base_ring_scale: float = 1.08 if absf(t_diff) <= 0.14 else 1.0
				active_ring.scale = Vector3.ONE * (base_ring_scale + t_factor * 1.65)
				var r_mat: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
				if r_mat:
					if absf(t_diff) <= 0.14:
						r_mat.albedo_color = Color(1.0, 0.92, 0.18, 1.0)
					elif t_diff <= 0.24:
						r_mat.albedo_color = Color(0.20, 1.0, 0.42, 0.98)
						if defender_is_player and _timing_cue_note_idx != first_unresolved_idx:
							_timing_cue_note_idx = first_unresolved_idx
							_pulse_defender_both_hands(140.0, 0.35, 0.04)
					elif is_hammer:
						r_mat.albedo_color = Color(0.78, 0.32, 1.0, 0.88)
					else:
						r_mat.albedo_color = Color(0.20, 0.85, 1.0, 0.88)
		elif t_diff > note_prewarn and active_ring and is_instance_valid(active_ring):
			active_ring.visible = false

		# Fix bug: early_lockout SOLO castiga parry/desvío por spam prematuro (>0.32s), NUNCA bloquea Guardia Cruzada X ni Z-Vanish
		var crossing_now: bool = _is_defender_crossing_arms() if defender_is_player else false
		if defender_is_player and t_diff > 0.32 and t_diff <= note_prewarn and not crossing_now and not bool(active_note.get("early_lockout", false)):
			if buffer_trig_timer_l > 0.08 or buffer_trig_timer_r > 0.08:
				active_note["early_lockout"] = true
				if active_ring and is_instance_valid(active_ring):
					var r_mat_e: StandardMaterial3D = active_ring.material_override as StandardMaterial3D
					if r_mat_e:
						r_mat_e.albedo_color = Color(1.0, 0.15, 0.15, 0.98)
				_pulse_defender_both_hands(95.0, 0.45, 0.12)
				_spawn_impact_popup(active_zone["node"].global_position, "⚠️ ¡MUY PRONTO! (Usa X)", Color(1.0, 0.28, 0.20))

		# Ventana de resolución defensiva (hasta ±0.28s para Choque de Puños / Z-Vanish)
		if absf(t_diff) <= 0.28:
			var zone_pos: Vector3 = active_zone["node"].global_position
			if defender_is_player:
				# 1. Z-Vanish Defensivo real con Stick en timing (-14 Ki)
				var def_orig_zv: XROrigin3D = defender.get_parent() as XROrigin3D
				if def_orig_zv and _def_stick_used_for_note_idx != first_unresolved_idx:
					var l_zv: XRController3D = def_orig_zv.get_node_or_null("LeftHand") as XRController3D
					var r_zv: XRController3D = def_orig_zv.get_node_or_null("RightHand") as XRController3D
					var st_l: Vector2 = l_zv.get_vector2("primary") if l_zv else Vector2.ZERO
					var st_r: Vector2 = r_zv.get_vector2("primary") if r_zv else Vector2.ZERO
					if st_l.length() >= 0.72 or st_r.length() >= 0.72:
						var cfg_zv: KiEconomyConfig = KiEconomyConfig.get_default()
						var vanish_cost: float = float(cfg_zv.melee_vanish_cost) if cfg_zv.get("melee_vanish_cost") != null else 14.0
						var cur_def_ki: float = float(defender.get("current_ki")) if defender.get("current_ki") != null else 0.0
						_def_stick_used_for_note_idx = first_unresolved_idx
						if cur_def_ki >= vanish_cost:
							_resolve_defensive_z_vanish(active_note, active_zone)
							return

				var not_locked_out: bool = not bool(active_note.get("early_lockout", false))
				var hand_parry_idx: int = _get_defender_hand_near_zone(zone_pos, 0.26) if not crossing_now else -1
				var hand_clash_idx: int = _get_defender_hand_near_zone(zone_pos, 0.28) if not crossing_now else -1

				# 2. Bloqueo Perfecto en Aro Dorado (<= 0.14s)
				if not_locked_out and hand_parry_idx != -1 and absf(t_diff) <= 0.14:
					var parry_vel: float = (def_left_velocity if hand_parry_idx == 0 else def_right_velocity).length()
					var p_trig: bool = (def_trig_l if hand_parry_idx == 0 else def_trig_r)
					if parry_vel < 0.95 and (_is_defender_just_guard_active(hand_parry_idx) or p_trig):
						_resolve_perfect_parry(active_note, active_zone)
						return

				# 3. Choque de Puños (Grip+Trigger cerrado + puñetazo veloz >= 0.85 m/s, no aplica a Martillazo)
				if hand_clash_idx != -1 and not is_hammer:
					var clash_closed: bool = _is_defender_fist_closed(hand_clash_idx)
					var clash_vel: float = (def_left_velocity if hand_clash_idx == 0 else def_right_velocity).length()
					if clash_closed and clash_vel >= 0.85:
						_resolve_fist_clash(active_note, active_zone, hand_clash_idx)
						return

				# 4. Desvío con 1 mano en Aro Verde/Dorado (<= 0.24s): Palma abierta (>= 0.45 m/s) O Trigger sin Grip
				if not_locked_out and absf(t_diff) <= 0.24 and hand_parry_idx != -1:
					var h_vel: float = (def_left_velocity if hand_parry_idx == 0 else def_right_velocity).length()
					var h_trig: bool = def_trig_l if hand_parry_idx == 0 else def_trig_r
					var h_grip: bool = def_grip_l if hand_parry_idx == 0 else def_grip_r
					var trig_only_ok: bool = h_trig and not h_grip
					var open_palm_ok: bool = (not h_grip) and (not h_trig) and h_vel >= 0.45
					if trig_only_ok or open_palm_ok:
						_resolve_hand_block(active_note, active_zone, hand_parry_idx)
						if phase != DomePhase.DEFENSE_RHYTHM:
							return

				# 5. Guardia Cruzada X: SIEMPRE permitida aunque haya habido early_lockout
				if crossing_now and absf(t_diff) <= 0.26:
					_resolve_cross_arm_guard(active_note, active_zone)
					if phase != DomePhase.DEFENSE_RHYTHM:
						return
			elif not defender_is_player and t_diff <= 0.05:
				_resolve_ai_defense(active_note, active_zone)
				if phase != DomePhase.DEFENSE_RHYTHM:
					return
		elif t_diff < -0.24:
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
	var parry_ki: float = float(cfg_pp.melee_parry_ki_reward) if cfg_pp.get("melee_parry_ki_reward") != null else 14.0
	_modify_fighter_ki(defender, parry_ki)
	_modify_fighter_ki(attacker, -10.0)
	if defender and is_instance_valid(defender) and defender.has_method("increase_np"):
		defender.increase_np(400.0)

	if audio_player:
		audio_player.global_position = zone["node"].global_position
		audio_player.pitch_scale = 1.30
		AudioActionManager.play_action("common.block_perfect", audio_player, sfx_parry)

	_spawn_parry_shockwave(zone["node"].global_position)
	_pulse_defender_both_hands(250.0, 1.0, 0.25)
	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		defender.procedural_animator.trigger_melee_block(3)
	perform_z_blink_relocation(_pick_aggressive_melee_spot(1.85, true))

	last_action_feedback = "⚡ ¡PARRY PERFECTO! (+%d Ki)" % int(parry_ki)
	pip_results.append("blocked")
	_spawn_impact_popup(zone["node"].global_position, "✨ ¡PARRY!", Color(1.0, 0.92, 0.25))
	emit_signal("defense_action_resolved", "perfect_parry", zone["id"], true, parry_ki, 400.0)
	_trigger_hit_stop(0.08)

	for h in hits:
		h["resolved"] = true

	# GDD Canon: Parry Perfecto en estado Furia desata Comeback Zenkai en el defensor (antes del swap)
	if defender and is_instance_valid(defender) and bool(defender.get("is_in_furia")) and not bool(defender.get("is_in_zenkai_state")) and defender.has_method("trigger_comeback_zenkai"):
		defender.trigger_comeback_zenkai()

	if _check_ki_break_after_note():
		return

	# Punto 3: Si fue Martillazo y el defensor tiene BP igual o menor (< 1.25x), corta el melee y gana distancia
	if bool(note.get("is_hammer", false)):
		var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var bp_def: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
		if bp_def < bp_atk * 1.25:
			_cut_melee_hammer_defended(defender, attacker, 50.0)
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
	var cfg_fc: KiEconomyConfig = KiEconomyConfig.get_default()
	var clash_cost: float = float(cfg_fc.melee_clash_cost) if cfg_fc.get("melee_clash_cost") != null else 4.0
	var clash_win: float = float(cfg_fc.melee_clash_win_reward) if cfg_fc.get("melee_clash_win_reward") != null else 8.0

	var score: float = 0.25
	if r_bp >= 0.70:
		clash_penalty_hits += 1
		var def_ki_gain: float = clash_win if r_bp > 1.40 else clash_cost
		var atk_ki_gain: float = -clash_cost if r_bp > 1.40 else 2.0
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
			audio_player.pitch_scale = 1.15
			AudioActionManager.play_action("common.block_perfect", audio_player, sfx_parry)
		_spawn_parry_shockwave(zone_pos)
		_pulse_defender_hand(hand_idx, 210.0, 1.0, 0.16)
		if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
			defender.procedural_animator.trigger_melee_block(2)
		var lat_c: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
		_trigger_dynamic_melee_mobility(float(note.get("power", 1.35)), bool(note.get("is_charged", false)), bool(note.get("is_charged_v3", false)), false, defender, attacker, lat_c * 7.5 + Vector3.UP * 2.4, 0.22, true)
		_trigger_hit_stop(0.08)

		last_action_feedback = "⚡ ¡CHOQUE DE PUÑOS! +%d Ki (-1 golpe)" % int(def_ki_gain)
		pip_results.append("clash")
		_spawn_impact_popup(zone_pos, "⚡ ¡CHOQUE!", Color(1.0, 1.0, 0.85))
		emit_signal("defense_action_resolved", "fist_clash", zone["id"], true, def_ki_gain, def_bp_gain)
	else:
		var raw_dmg: float = 360.0 if bool(note.get("is_charged_v3", false)) else (240.0 if bool(note.get("is_charged", false)) else 140.0)
		var partial_dmg: float = raw_dmg * 0.50
		_modify_fighter_ki(defender, -clash_cost)
		_modify_fighter_ki(attacker, 4.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(partial_dmg, Vector3.ZERO)
		if attacker and attacker.has_method("increase_np"):
			attacker.increase_np(200.0)
		_spawn_hit_spark(zone_pos)
		_pulse_defender_hand(hand_idx, 160.0, 0.75, 0.14)
		var lat_cl: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
		_trigger_dynamic_melee_mobility(float(note.get("power", 1.2)), bool(note.get("is_charged", false)), bool(note.get("is_charged_v3", false)), false, attacker, defender, -_duel_axis * 6.5 + lat_cl * 2.4 + Vector3.UP * 1.4, 0.22, false)

		last_action_feedback = "💥 ¡SUPERADO EN CHOQUE! (-%d BP)" % int(partial_dmg)
		pip_results.append("hit")
		_spawn_impact_popup(zone_pos, "💥 ¡IMPACTO!", Color(1.0, 0.38, 0.15))
		emit_signal("defense_action_resolved", "fist_clash_lost", zone["id"], false, -clash_cost, 0.0)

	note["defense_score"] = score
	defense_score_sum += score
	if _check_ki_break_after_note():
		return

	# Evento Lore 1: Choque Frenético de Puños si ambos peleadores tienen buen Ki y BP competitivo
	if phase == DomePhase.DEFENSE_RHYTHM and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var atk_ki_fc: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		var def_ki_fc: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 0.0
		var fc_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "fist_clash",
			"last_event_type": _last_lore_event_type,
			"atk_ki": atk_ki_fc,
			"def_ki": def_ki_fc,
			"bp_ratio": r_bp
		})
		if fc_ev == MeleeLoreEventScript.LoreEventType.FIST_FLURRY_CLASH:
			_start_lore_event(fc_ev, "fist_clash")


func _resolve_defensive_z_vanish(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var cfg_zv: KiEconomyConfig = KiEconomyConfig.get_default()
	var vanish_cost: float = float(cfg_zv.melee_vanish_cost) if cfg_zv.get("melee_vanish_cost") != null else 14.0
	_modify_fighter_ki(defender, -vanish_cost)
	var zone_pos: Vector3 = zone["node"].global_position

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.pitch_scale = 1.45
		AudioActionManager.play_action("common.block_perfect", audio_player, sfx_parry)
	_pulse_defender_both_hands(190.0, 0.70, 0.10)
	perform_z_blink_relocation()

	note["defense_score"] = 1.00
	defense_score_sum += 1.00
	last_action_feedback = "💨 ¡Z-VANISH! (-%d Ki)" % int(vanish_cost)
	pip_results.append("blocked")
	_spawn_impact_popup(zone_pos, "💨 ¡Z-VANISH!", Color(0.35, 0.96, 1.0))
	emit_signal("defense_action_resolved", "z_vanish", zone["id"], true, -vanish_cost, 120.0)
	if _check_ki_break_after_note():
		return

	# Evento Lore 3: Guerra de Z-Vanish si el atacante tiene Ki para perseguir
	if phase == DomePhase.DEFENSE_RHYTHM and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var atk_ki_zv: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		var bp_d: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
		var bp_a: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var zv_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "z_vanish",
			"last_event_type": _last_lore_event_type,
			"atk_ki": atk_ki_zv,
			"bp_ratio": bp_a / bp_d
		})
		if zv_ev == MeleeLoreEventScript.LoreEventType.Z_VANISH_WAR:
			_start_lore_event(zv_ev, "z_vanish_war")


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
	var cfg_hb: KiEconomyConfig = KiEconomyConfig.get_default()
	var deflect_reward: float = float(cfg_hb.melee_deflect_ki_reward) if cfg_hb.get("melee_deflect_ki_reward") != null else 5.0

	if is_v3:
		# Cargado v3 SÍ se frena con 1 mano (mitiga 70%, cuesta -10 Ki, suma 0.75)
		var v3_mitigated: float = 420.0 * 0.30
		score = 0.75
		_modify_fighter_ki(defender, -10.0)
		_modify_fighter_ki(attacker, -2.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(v3_mitigated, Vector3.ZERO)
		if audio_player:
			audio_player.global_position = zone_pos
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player, sfx_hit_heavy)
		_spawn_block_spark(zone_pos, Color(1.0, 0.55, 0.2))
		last_action_feedback = "✋ ¡CARGADO V3 FRENADO! (-10 Ki)"
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "✋ ¡FRENADO!", Color(0.25, 0.92, 1.0))
		emit_signal("defense_action_resolved", "hand_block_v3", zone["id"], true, -10.0, 0.0)
	elif is_charged:
		var mitigated_dmg: float = 140.0
		score = 0.50
		_modify_fighter_ki(defender, -6.0)
		_modify_fighter_ki(attacker, -2.0)
		if defender and defender.has_method("take_hit"):
			defender.take_hit(mitigated_dmg, Vector3.ZERO)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(75.0)
		if audio_player:
			audio_player.global_position = zone_pos
			AudioActionManager.play_action("common.melee_hit_heavy", audio_player, sfx_hit_heavy)
		_spawn_block_spark(zone_pos, Color(1.0, 0.75, 0.2))
		last_action_feedback = "✋ ¡CARGADO BLOQUEADO! (-6 Ki)"
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "🛡️ ¡BLOQUEADO!", Color(0.25, 0.92, 1.0))
		emit_signal("defense_action_resolved", "partial_block", zone["id"], true, -6.0, 75.0)
	else:
		score = 1.00
		_modify_fighter_ki(defender, deflect_reward)
		_modify_fighter_ki(attacker, -4.0)
		if defender and defender.has_method("increase_np"):
			defender.increase_np(150.0)
		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.pitch_scale = 1.25
			AudioActionManager.play_action("common.melee_hit_light", audio_player, sfx_hit_light)
		_spawn_block_spark(zone_pos, Color(1.0, 0.9, 0.2))
		last_action_feedback = "✋ ¡DESVÍO LIMPIO! (+%d Ki)" % int(deflect_reward)
		pip_results.append("blocked")
		_spawn_impact_popup(zone_pos, "✋ ¡DESVÍO!", Color(0.35, 1.0, 0.70))
		emit_signal("defense_action_resolved", "hand_block", zone["id"], true, deflect_reward, 150.0)

	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		defender.procedural_animator.trigger_melee_block(0)
	var lat_b: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * (1.0 if hand_idx == 1 else -1.0)
	var back_dist: float = 5.5 if is_v3 else (4.4 if is_charged else 3.4)
	_trigger_dynamic_melee_mobility(float(note.get("power", 1.0)), is_charged, is_v3, false, defender, attacker, -_duel_axis * back_dist + lat_b * 2.2 + Vector3.UP * 1.1, 0.20, is_v3)

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
	var g_quick: float = float(cfg_ki.melee_guard_quick_cost) if cfg_ki.get("melee_guard_quick_cost") != null else cfg_ki.melee_quick_cost
	var g_chg: float = float(cfg_ki.melee_guard_charged_cost) if cfg_ki.get("melee_guard_charged_cost") != null else cfg_ki.melee_charged_cost
	var g_v3: float = float(cfg_ki.melee_guard_v3_cost) if cfg_ki.get("melee_guard_v3_cost") != null else cfg_ki.melee_v3_cost
	var base_ki_cost: float = cfg_ki.melee_hammer_guard_cost if is_hammer else (g_v3 if is_v3 else (g_chg if is_charged else g_quick))
	var ki_cost: float = base_ki_cost + float(consecutive_guard_hits - 1) * cfg_ki.melee_guard_escalation

	_modify_fighter_ki(defender, -ki_cost)
	_modify_fighter_ki(attacker, 2.0)
	if defender and defender.has_method("take_hit"):
		defender.take_hit(final_dmg, Vector3.ZERO)
	if defender and defender.has_method("increase_np"):
		defender.increase_np(20.0)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.pitch_scale = 0.85
		var act_id := "common.melee_hit_heavy" if (is_hammer or is_v3) else "common.melee_hit_light"
		var fb := sfx_hit_heavy if (is_hammer or is_v3) else sfx_hit_light
		AudioActionManager.play_action(act_id, audio_player, fb)

	_spawn_block_spark(zone_pos, Color(0.2, 0.7, 1.0))
	_pulse_defender_both_hands(140.0, 0.65, 0.10)
	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		defender.procedural_animator.trigger_melee_block(1)
	var defender_is_player_g: bool = bool(defender.get("is_player")) if (defender and is_instance_valid(defender)) else false
	var push_back: Vector3 = (-_duel_axis if defender_is_player_g else _duel_axis) * (6.2 if (is_hammer or is_v3) else 4.2)
	_apply_melee_arena_surge(push_back + Vector3.UP * (-0.8 if is_hammer else 0.5), 0.22)

	note["defense_score"] = 0.25
	defense_score_sum += 0.25
	last_action_feedback = "🛡️ GUARDIA CRUZADA (-%d Ki)" % int(ki_cost)
	pip_results.append("blocked")
	_spawn_impact_popup(zone_pos, "🛡️ ¡BLOQUEADO!", Color(0.30, 0.78, 1.0))
	emit_signal("defense_action_resolved", "cross_arm_guard", zone["id"], true, -ki_cost, 20.0)
	if _check_ki_break_after_note():
		return

	# Punto 3: Martillazo bloqueado con BP igual o menor (< 1.25x) corta el melee y empuja hacia atrás (sin daño completo)
	if is_hammer:
		var bp_atk_h: float = maxf(float(attacker.get("current_np")) if (attacker and attacker.get("current_np") != null) else 10000.0, 100.0)
		var bp_def_h: float = maxf(float(defender.get("current_np")) if (defender and defender.get("current_np") != null) else 10000.0, 100.0)
		if bp_def_h < bp_atk_h * 1.25:
			_cut_melee_hammer_defended(defender, attacker, final_dmg)
			return

	# Evento Lore 4: Desgarre de Guardia si abusa de Guardia Cruzada (2+ segundas notas) o Ki crítico
	if phase == DomePhase.DEFENSE_RHYTHM and _has_unresolved_notes() and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var def_ki_g: float = float(defender.get("current_ki")) if (defender and defender.get("current_ki") != null) else 50.0
		var gb_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "guard_abuse",
			"last_event_type": _last_lore_event_type,
			"consecutive_guard_x": consecutive_guard_hits,
			"def_ki": def_ki_g
		})
		if gb_ev == MeleeLoreEventScript.LoreEventType.GUARD_PRESSURE_BREAK:
			_start_lore_event(gb_ev, "guard_break")


func _cut_melee_hammer_defended(p_def: Node3D, p_atk: Node3D, chip_dmg: float) -> void:
	is_active = false
	if p_def and is_instance_valid(p_def):
		p_def.set("is_in_bullet_time", false)
		var push_dir: Vector3 = (p_def.global_position - p_atk.global_position).normalized() if (p_atk and is_instance_valid(p_atk)) else Vector3.BACK
		push_dir.y = 0.0
		if push_dir.length_squared() < 0.001:
			push_dir = Vector3.BACK
		if p_def.has_method("apply_knockback"):
			p_def.apply_knockback(push_dir.normalized(), 6.5)
	if p_atk and is_instance_valid(p_atk):
		p_atk.set("is_in_bullet_time", false)
		p_atk.set("active_target_dome", null)
	if p_def and p_def.has_method("_separate_fighters_to_canonical_distance") and p_atk:
		p_def._separate_fighters_to_canonical_distance(p_atk, 5.5)
	elif p_atk and p_atk.has_method("_separate_fighters_to_canonical_distance") and p_def:
		p_atk._separate_fighters_to_canonical_distance(p_def, 5.5)
	_spawn_impact_popup(global_position, "🛡️ ¡MARTILLO FRENADO! (-%d BP)" % int(chip_dmg), Color(0.4, 0.9, 1.0), true)
	queue_free()


func _resolve_unblocked_hit(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	_round_unblocked_hits_taken += 1
	var ring: MeshInstance3D = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_hammer: bool = bool(note.get("is_hammer", false))
	var is_v3: bool = bool(note.get("is_charged_v3", false))
	var is_charged: bool = bool(note.get("is_charged", false))
	var tier_mult: float = float(note.get("tier_dmg_mult", 1.0))
	var zone_pos: Vector3 = zone["node"].global_position
	var base_dmg: float = 580.0 if is_hammer else (420.0 if is_v3 else (280.0 if is_charged else 140.0))
	var charge_base_ref: float = 2.40 if (is_v3 or is_hammer) else (1.65 if is_charged else 1.00)
	var note_power: float = float(note.get("power", charge_base_ref))
	var raw_dmg: float = base_dmg * clampf(note_power / charge_base_ref, 0.75, 1.55) * tier_mult

	# Overhaul Ki: se elimina el regalo gratuito al atacante; solo drena al receptor aturdido
	var def_ki_loss: float = -16.0 if (is_v3 or is_hammer) else (-12.0 if is_charged else -6.0)
	_modify_fighter_ki(defender, def_ki_loss)
	var lat_h: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * randf_range(-2.2, 2.2)
	var def_is_player_h: bool = bool(defender.get("is_player")) if (defender and is_instance_valid(defender)) else false
	var hit_fwd: Vector3 = (-_duel_axis if def_is_player_h else _duel_axis) * (8.2 if (is_charged or is_v3 or is_hammer) else 5.5)
	var hit_vert: Vector3 = Vector3.UP * (2.8 if (is_v3 and String(note.get("v3_launch_mode", "")) == "UP") else (-1.8 if is_hammer else 0.9))
	_trigger_dynamic_melee_mobility(note_power, is_charged, is_v3, is_hammer, attacker, defender, hit_fwd + lat_h + hit_vert, 0.22, is_v3 and String(note.get("v3_launch_mode", "")) == "UP")

	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(raw_dmg, -global_transform.basis.z)
		if defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(0.75 if (is_hammer or is_v3) else 0.45, -global_transform.basis.z)

	if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
		attacker.increase_np(raw_dmg * 0.40)

	if audio_player:
		audio_player.global_position = zone_pos
		var act_id := "common.melee_hit_heavy" if (is_charged or is_v3 or is_hammer) else "common.melee_hit_light"
		var fb := sfx_hit_heavy if (is_charged or is_v3 or is_hammer) else sfx_hit_light
		AudioActionManager.play_action(act_id, audio_player, fb)

	_pulse_defender_both_hands(200.0, 0.80, 0.14)
	_spawn_hit_spark(zone_pos)

	note["defense_score"] = 0.0
	var pwr_lbl: String = "🔥 V3 x%.1f" % note_power if is_v3 else ("⚡ CARGADO x%.1f" % note_power if is_charged else "💥 RÁPIDO x%.1f" % note_power)
	if is_hammer:
		pwr_lbl = "🔨 MARTILLAZO x%.1f" % note_power
	last_action_feedback = pwr_lbl
	pip_results.append("hit")
	_spawn_impact_popup(zone_pos, pwr_lbl, Color(1.0, 0.42, 0.15))
	if is_charged or is_v3 or is_hammer:
		_spawn_parry_shockwave(zone_pos)
		if is_hammer:
			KiSmokeFX.spawn_smoke(get_tree(), zone_pos, 1.2)
	emit_signal("defense_action_resolved", "hit_taken", zone["id"], false, def_ki_loss, 0.0)

	# Si todavía quedan golpes sin resolver en la secuencia, no cortar el combo: diferir remate hasta evaluar la ronda
	var has_remaining_notes: bool = _has_unresolved_notes()

	if is_hammer:
		if has_remaining_notes:
			_pending_finisher_mode = "hammer_strike"
			_pending_finisher_vel = float(note.get("velocity", 4.0))
		else:
			_trigger_finisher_and_close("hammer_strike", float(note.get("velocity", 4.0)))
			return
	elif is_v3:
		var v3_mode: String = "charged_v3_up" if String(note.get("v3_launch_mode", "BACK")) == "UP" else "charged_v3_back"
		if has_remaining_notes:
			_pending_finisher_mode = v3_mode
			_pending_finisher_vel = float(note.get("velocity", 3.5))
		else:
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
				_tint_zone_shapes(zone, Color(1.0, 0.25, 0.1, 0.95), Color(1.0, 0.75, 0.1), 3.2, Color(1.0, 1.0, 1.0, 0.95))
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
	_last_lore_event_type = event_type
	_lore_return_mode = return_mode
	phase = DomePhase.LORE_EVENT
	_reset_all_timing_rings()
	_hide_all_charge_spheres()
	_set_target_zones_visible(false)
	_lore_ctrl.call("start_event", event_type, self, attacker, defender)


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


func _close_dome_with_separation(sep_dist: float) -> void:
	if not is_active:
		return
	is_active = false
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	phase = DomePhase.COMPLETED
	_hide_all_charge_spheres()
	_reset_all_timing_rings()
	if attacker and defender and is_instance_valid(attacker) and is_instance_valid(defender):
		if attacker.has_method("_separate_fighters_to_canonical_distance"):
			attacker._separate_fighters_to_canonical_distance(defender, sep_dist)
		elif defender.has_method("_separate_fighters_to_canonical_distance"):
			defender._separate_fighters_to_canonical_distance(attacker, sep_dist)
	emit_signal("bullet_time_completed", hits, last_impact_vector)
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
		_hitstop_end_msec = 0
		if Engine.time_scale < 1.0:
			Engine.time_scale = 1.0
		phase = DomePhase.COMPLETED
		_hide_all_charge_spheres()
		_reset_all_timing_rings()
		var win_m: Node3D = outcome.get("winner", attacker) as Node3D
		var vic_m: Node3D = outcome.get("victim", defender) as Node3D
		var c_pos: Vector3 = outcome.get("crater_pos", global_position)
		emit_signal("meteor_smash_completed", win_m, vic_m, c_pos)
		queue_free()
		return
	elif act == "winner_offense":
		_set_target_zones_visible(true)
		var winner: Node3D = outcome.get("winner") as Node3D
		var loser: Node3D = outcome.get("loser") as Node3D
		if winner and is_instance_valid(winner) and loser and is_instance_valid(loser):
			attacker = winner
			defender = loser
		pending_attack_penalty = 0
		var w_is_p: bool = attacker != null and bool(attacker.get("is_player"))
		_begin_phase_transition("continue_offense", 0.45, "🔥 ¡%s TOMAS LA INICIATIVA!" % ("TÚ" if w_is_p else "EL RIVAL"), Color(1.0, 0.78, 0.20))
		return
	elif act == "separate":
		_close_dome_with_separation(float(outcome.get("distance", 9.0)))
		return
	elif act == "launch":
		var victim: Node3D = outcome.get("victim") as Node3D
		if victim == attacker and defender != null:
			var tmp_a: Node3D = attacker
			attacker = defender
			defender = tmp_a
		_trigger_finisher_and_close("charged_v3_back", 4.0)
		return

	# Caso complete_normal
	_set_target_zones_visible(true)
	if _lore_return_mode == "combo_mid":
		phase = DomePhase.ATTACK_RECORDING
		_update_sequential_target_highlights()
	elif _lore_return_mode in ["fist_clash", "guard_break", "z_vanish_war"] and _has_unresolved_notes():
		phase = DomePhase.DEFENSE_RHYTHM
	else:
		evaluate_round_outcome()


## Evalúa si los golpes fueron mayormente bloqueados (invierte roles) o conectados (continúa ofensiva)
func evaluate_round_outcome() -> void:
	if not is_active:
		return
	_tutorial_controls_shown = true
	if _check_ki_break_after_note():
		return
	if _pending_finisher_mode != "":
		var fin_mode: String = _pending_finisher_mode
		var fin_vel: float = _pending_finisher_vel
		_pending_finisher_mode = ""
		_trigger_finisher_and_close(fin_mode, fin_vel)
		return

	# Evento Lore 2: Caída del Meteoro (tras conectar golpes sónicos o V3 arriba al terminar la ronda)
	if _last_lore_event_type != MeleeLoreEventScript.LoreEventType.METEOR_SMASH and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var hits_landed: int = 0
		var has_v3_up: bool = false
		for h_chk in hits:
			if h_chk.get("resolved", false) and float(h_chk.get("defense_score", 0.0)) < 0.5:
				hits_landed += 1
			if bool(h_chk.get("is_charged_v3", false)) and String(h_chk.get("v3_launch_mode", "")) == "UP":
				has_v3_up = true
		var atk_ki_end: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 0.0
		var m_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "combo_end",
			"last_event_type": _last_lore_event_type,
			"has_v3_up": has_v3_up,
			"sonic_hits": _round_sonic_hits,
			"hits_landed": hits_landed,
			"atk_ki": atk_ki_end
		})
		if m_ev == MeleeLoreEventScript.LoreEventType.METEOR_SMASH:
			_start_lore_event(m_ev, "combo_end")
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
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	phase = DomePhase.COMPLETED
	_modify_fighter_ki(attacker, -6.0 * float(maxi(max_allowed_hits, 1)))
	_modify_fighter_ki(defender, 5.0)
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
	_refresh_melee_ki_bar()
	if absf(delta_ki) >= 1.0:
		_show_ki_delta_popup(fighter, delta_ki)


func _update_defender_velocities(delta: float) -> void:
	if delta <= 0.0001 or not defender or not is_instance_valid(defender) or not bool(defender.get("is_player")):
		return
	var origin: XROrigin3D = defender.get_parent() as XROrigin3D
	if not origin:
		return
	var orig_basis: Basis = origin.global_transform.basis.orthonormalized()
	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand") as XRController3D
	var l_loc: Vector3 = left_ctrl.position if left_ctrl else Vector3.ZERO
	var r_loc: Vector3 = right_ctrl.position if right_ctrl else Vector3.ZERO
	if _has_prev_def_local:
		if left_ctrl:
			def_left_velocity = orig_basis * ((l_loc - _def_prev_l_local) / delta)
		if right_ctrl:
			def_right_velocity = orig_basis * ((r_loc - _def_prev_r_local) / delta)
	_def_prev_l_local = l_loc
	_def_prev_r_local = r_loc
	_has_prev_def_local = true
	if left_ctrl:
		def_prev_left_pos = left_ctrl.global_position
	if right_ctrl:
		def_prev_right_pos = right_ctrl.global_position


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
	_hitstop_end_msec = Time.get_ticks_msec() + int(maxf(freeze_time, 0.01) * 1000.0)


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
	melee_boxes_anchor = Node3D.new()
	melee_boxes_anchor.name = "MeleeBoxesAnchor"
	melee_boxes_anchor.position = Vector3.ZERO
	add_child(melee_boxes_anchor)
	var boxes_parent: Node3D = melee_boxes_anchor

	for def in ZONE_DEFINITIONS:
		var zone_node := Node3D.new()
		zone_node.name = "Zone_%d_%s" % [def.id, def.name.replace(" / ", "_").replace(" ", "_")]
		zone_node.position = def.offset
		boxes_parent.add_child(zone_node)

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

		var circle_mesh_inst := MeshInstance3D.new()
		circle_mesh_inst.name = "AttackCircleDisc"
		var disc := CylinderMesh.new()
		disc.top_radius = 0.088
		disc.bottom_radius = 0.088
		disc.height = 0.016
		disc.radial_segments = 24
		circle_mesh_inst.mesh = disc
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
		var c_torus := TorusMesh.new()
		c_torus.inner_radius = 0.080
		c_torus.outer_radius = 0.096
		c_torus.rings = 24
		c_torus.ring_segments = 10
		circle_ring.mesh = c_torus
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

	var cam: Camera3D = _get_player_camera()
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized() if (cam and is_instance_valid(cam)) else -global_transform.basis.z
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
		var cur_vel: Vector3 = left_velocity if hand_idx == 0 else right_velocity
		var v_mag: float = cur_vel.length()

		var min_dist_to_any_zone: float = 999.0
		for zone in target_zones:
			var z_node: Node3D = zone.get("node") as Node3D
			if z_node and is_instance_valid(z_node):
				var d_any: float = hand_pos.distance_to(z_node.global_position)
				if d_any < min_dist_to_any_zone:
					min_dist_to_any_zone = d_any

		# Liberar retracción solo tras retirar físicamente >= 20cm desde el impacto o salir quieto fuera del rango
		if hand_must_retract[hand_idx]:
			if hand_loc.distance_to(_last_hit_local[hand_idx]) >= 0.20 or (min_dist_to_any_zone > 0.32 and v_mag < 0.55):
				hand_must_retract[hand_idx] = false
				_punch_origin_local[hand_idx] = hand_loc
				_punch_origin_init[hand_idx] = true

		# Exigir puño cerrado (Grip+Trigger), no en retracción, y velocidad real de puñetazo
		if hand_must_retract[hand_idx] or not is_fist_closed[hand_idx]:
			continue

		var is_chg_ready: bool = fist_charge_times[hand_idx] >= 0.50
		var min_vel: float = 1.35 if is_chg_ready else 1.55
		if v_mag < min_vel:
			continue

		# Exigir recorrido real de brazo (>= 22cm desde el inicio del puñetazo) para evitar pasadas pasivas entre cajas
		var stroke_dist: float = hand_loc.distance_to(_punch_origin_local[hand_idx]) if _punch_origin_init[hand_idx] else 0.0
		if stroke_dist < 0.22:
			continue

		var vel_dir: Vector3 = cur_vel / v_mag
		for zone in target_zones:
			if zone.get("cooldown", 0.0) > 0.0:
				continue
			var z_node: Node3D = zone.get("node") as Node3D
			if not z_node or not is_instance_valid(z_node):
				continue
			var d: float = hand_pos.distance_to(z_node.global_position)
			if d <= 0.24 and d < best_dist:
				var to_zone_dir: Vector3 = (z_node.global_position - hand_pos).normalized()
				var fwd_ok: bool = (vel_dir.dot(to_zone_dir) >= 0.45) or (vel_dir.dot(cam_fwd) >= 0.55)
				if not fwd_ok:
					continue
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
		_register_hit(best_zone, best_ctrl, best_hand_name, best_hand_idx, best_vel, best_vmag, best_stroke_dist)
		hand_must_retract[best_hand_idx] = true


func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String, hand_idx: int, cur_vel: Vector3, v_mag: float, stroke_dist: float = 0.28) -> void:
	zone["cooldown"] = 0.28
	var hit_pos: Vector3 = zone["node"].global_position

	var charge_t: float = fist_charge_times[hand_idx]
	var is_v3: bool = charge_t >= 1.10
	var is_charged: bool = charge_t >= 0.50
	var tier_info: Dictionary = classify_melee_punch_tier(stroke_dist, v_mag, is_charged or is_v3)
	var tier_name: String = String(tier_info.get("tier", "SOLIDO"))
	var tier_dmg_mult: float = float(tier_info.get("dmg_mult", 1.0))
	var tier_refund: float = float(tier_info.get("ki_refund", 0.0))

	var cfg_ki: KiEconomyConfig = KiEconomyConfig.get_default()
	var ki_cost: float = cfg_ki.melee_v3_cost if is_v3 else (cfg_ki.melee_charged_cost if is_charged else cfg_ki.melee_quick_cost)
	_modify_fighter_ki(attacker, -ki_cost + tier_refund)

	var swing_dir: Vector3 = cur_vel.normalized() if cur_vel.length_squared() > 0.01 else -global_transform.basis.z
	var v3_mode: String = "UP" if (swing_dir.y > 0.25 or int(zone["id"]) == 0) else "BACK"
	var punch_power: float = compute_melee_kinetic_power(stroke_dist, v_mag, is_charged, is_v3)
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
		"stroke_dist": stroke_dist,
		"tier": tier_name,
		"tier_dmg_mult": tier_dmg_mult,
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
	_spawn_impact_popup(hit_pos, String(tier_info.get("label", "💥 ¡SÓLIDO!")), tier_info.get("color", Color.WHITE) as Color)
	if defender and is_instance_valid(defender) and defender.get("procedural_animator"):
		defender.procedural_animator.trigger_hit_flinch(0.75 if tier_name == "SONICO" else (0.50 if tier_name == "SOLIDO" else 0.25), swing_dir)
	if tier_name == "SONICO":
		_round_sonic_hits += 1
		_spawn_parry_shockwave(hit_pos)
		if is_inside_tree():
			_trigger_hit_stop(0.045)

	var atk_lat_dir: float = 1.0 if (hits.size() % 2 == 0) else -1.0
	var atk_lat: Vector3 = _duel_axis.cross(Vector3.UP).normalized() * atk_lat_dir
	var base_surge: Vector3 = _duel_axis * 7.5 + atk_lat * 2.8 + Vector3.UP * (2.6 if v3_mode == "UP" else 0.9)
	if not is_v3:
		if is_charged:
			base_surge = _duel_axis * 6.0 + atk_lat * 2.2 + Vector3.UP * 1.2
		elif tier_name == "SONICO":
			base_surge = _duel_axis * 5.5 + atk_lat * 2.0 + Vector3.UP * 0.8
		else:
			base_surge = _duel_axis * 3.5 + atk_lat * 1.5 + Vector3.UP * randf_range(-0.6, 0.9)
	_trigger_dynamic_melee_mobility(punch_power, is_charged, is_v3, false, attacker, defender, base_surge, 0.18 if is_v3 else 0.16, is_v3 and v3_mode == "UP")

	var orig_col: Color = zone["color"] as Color
	var flash_col: Color = Color(1.0, 0.2, 0.1) if is_v3 else (Color(1.0, 0.45, 0.1) if is_charged else Color(1.0, 1.0, 0.4))
	_tint_zone_shapes(zone, flash_col, flash_col, 4.5 if is_charged else 3.0, Color(1.0, 1.0, 1.0, 0.96))
	var box_inst: MeshInstance3D = zone.get("box_mesh") as MeshInstance3D
	var circ_inst: MeshInstance3D = zone.get("circle_mesh") as MeshInstance3D
	var ring_inst: MeshInstance3D = zone.get("circle_ring") as MeshInstance3D
	if zone.get("node") and is_instance_valid(zone["node"]):
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
		audio_player.pitch_scale = randf_range(0.92, 1.08)
		var act_id := "common.melee_hit_heavy" if (is_charged or is_v3 or tier_name == "SONICO") else "common.melee_hit_light"
		var fb := sfx_hit_heavy if (is_charged or is_v3 or tier_name == "SONICO") else sfx_hit_light
		AudioActionManager.play_action(act_id, audio_player, fb)

	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		ctrl_node.trigger_haptic_pulse("haptic", 220.0 if (is_charged or tier_name == "SONICO") else 170.0, 1.0 if (is_charged or tier_name == "SONICO") else 0.72, 0.20 if (is_charged or tier_name == "SONICO") else 0.08, 0.0)

	fist_charge_times[hand_idx] = 0.0
	fist_locked_haptic[hand_idx] = false
	fist_v3_locked_haptic[hand_idx] = false
	_update_hand_charge_sphere(hand_idx, ctrl_node, 0.0)

	emit_signal("target_hit", hits.size(), String(zone["name"]), hit_pos, is_charged, punch_power)

	current_attack_step += 1
	_update_sequential_target_highlights()

	# Evento Lore 6: Intercambio Sónico Z-Burst a mitad de un combo largo (no interfiere con combos <= 2 golpes)
	var atk_ki_left: float = float(attacker.get("current_ki")) if (attacker and attacker.get("current_ki") != null) else 50.0
	if hits.size() >= 3 and current_attack_step < max_allowed_hits and atk_ki_left >= 15.0 and _lore_ctrl and not bool(_lore_ctrl.get("is_event_active")):
		var is_fur_t: bool = bool(attacker.get("is_in_furia")) or (int(attacker.get("current_form")) if attacker.get("current_form") != null else 0) > 0
		var sz_ev: int = MeleeLoreEventScript.evaluate_lore_event_trigger({
			"trigger_source": "combo_mid",
			"last_event_type": _last_lore_event_type,
			"hits_landed": hits.size(),
			"sonic_hits": _round_sonic_hits,
			"is_furia_or_trans": is_fur_t,
			"atk_ki": atk_ki_left
		})
		if sz_ev == MeleeLoreEventScript.LoreEventType.SONIC_Z_BURST:
			_start_lore_event(sz_ev, "combo_mid")
			return

	# Un golpe Cargado o V3 NO cancela los golpes restantes del combo; solo avanza al llegar al tope o agotar Ki
	if atk_ki_left <= 0.0 or current_attack_step >= max_allowed_hits:
		var msg_tag: String = "🔥 ¡CARGADO V3 EN COMBO!" if is_v3 else "💥 ¡SECUENCIA REGISTRADA!"
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
		var cfg_hm: KiEconomyConfig = KiEconomyConfig.get_default()
		var hm_cost: float = float(cfg_hm.melee_hammer_cost) if cfg_hm.get("melee_hammer_cost") != null else 22.0
		hammer_ki_paid = true
		_modify_fighter_ki(attacker, -hm_cost)
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
		# Punto 3: El Martillazo ya no corta los golpes restantes del atacante; avanza la secuencia normalmente
		current_attack_step += 1
		attack_step_cooldown = 0.16
		var hammer_pos: Vector3 = target_zones[1]["node"].global_position
		_spawn_parry_shockwave(hammer_pos)
		_trigger_dynamic_melee_mobility(4.5, true, false, true, attacker, defender, _duel_axis * 6.5 + Vector3.UP * 3.2, 0.20, true)
		_spawn_impact_popup(hammer_pos, "🔨 ¡MARTILLAZO REGISTRADO!", Color(0.95, 0.35, 1.0))
		if current_attack_step >= max_allowed_hits:
			_begin_phase_transition("start_defense", 0.50, "🔨 ¡MARTILLAZO DBZ LANZADO!", Color(0.95, 0.35, 1.0))
		else:
			_update_sequential_target_highlights()
		return true

	return false


# ==============================================================================
# AUXILIARES DE MANDOS, CARGA EN PUÑO Y EFECTOS VISUALES
# ==============================================================================

func _get_controller(hand_name: String) -> XRController3D:
	for f_chk in [attacker, defender]:
		if f_chk and is_instance_valid(f_chk) and bool(f_chk.get("is_player")):
			var p: Node = f_chk.get_parent()
			if p:
				var c: XRController3D = p.get_node_or_null(hand_name) as XRController3D
				if c:
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

	var left_ctrl: XRController3D = _get_controller("LeftHand")
	var right_ctrl: XRController3D = _get_controller("RightHand")
	var p_node: Node3D = attacker if (attacker and is_instance_valid(attacker) and attacker.get("is_player")) else (defender if (defender and is_instance_valid(defender) and defender.get("is_player")) else null)
	var origin: XROrigin3D = p_node.get_parent() as XROrigin3D if (p_node and p_node.get_parent() is XROrigin3D) else null
	var orig_basis: Basis = origin.global_transform.basis.orthonormalized() if (origin and is_instance_valid(origin)) else Basis.IDENTITY

	var l_loc: Vector3 = left_ctrl.position if left_ctrl else Vector3.ZERO
	var r_loc: Vector3 = right_ctrl.position if right_ctrl else Vector3.ZERO

	if _has_prev_atk_local:
		if left_ctrl:
			left_velocity = orig_basis * ((l_loc - _prev_l_local) / delta)
		if right_ctrl:
			right_velocity = orig_basis * ((r_loc - _prev_r_local) / delta)
	_prev_l_local = l_loc
	_prev_r_local = r_loc
	_has_prev_atk_local = true

	if left_ctrl:
		prev_left_pos = left_ctrl.global_position
		if not _punch_origin_init[0] or (left_velocity.length() < 0.45 and not hand_must_retract[0]):
			_punch_origin_local[0] = l_loc
			_punch_origin_init[0] = true
	if right_ctrl:
		prev_right_pos = right_ctrl.global_position
		if not _punch_origin_init[1] or (right_velocity.length() < 0.45 and not hand_must_retract[1]):
			_punch_origin_local[1] = r_loc
			_punch_origin_init[1] = true


func _update_fist_states(delta: float, is_charging_hammer: bool) -> void:
	for i in [0, 1]:
		var hand_name: String = "LeftHand" if i == 0 else "RightHand"
		var c: XRController3D = _get_controller(hand_name)
		if not c:
			is_fist_closed[i] = false
			continue

		if hand_must_retract[i] and c.position.distance_to(_last_hit_local[i]) >= 0.14:
			hand_must_retract[i] = false
			_punch_origin_local[i] = c.position
			_punch_origin_init[i] = true

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
			_punch_origin_local[i] = c.position
			_punch_origin_init[i] = true
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
	_hitstop_end_msec = 0
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	_hide_all_charge_spheres()
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
