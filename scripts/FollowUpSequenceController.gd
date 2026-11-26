class_name FollowUpSequenceController
extends Node3D

## FollowUpSequenceController (Squad 1A — Godot 4.3+ VR)
## Orquesta de forma unificada las secuencias Post-Lanzamiento en tiempo real (real_dt):
## HITSTOP (Stop Game) -> RAMP_TO_BT -> DECISION_WINDOW -> 4 Minijuegos (Atacante y Defensor):
## 1. Otro Melee (Meteor Chase + Rebotes Z emergentes por V3/Martillo)
## 2. Vanish + Martillazo (Z-Vanish encima + diana inferior / defensa cuadrada estilo Melee)
## 3. Súper Ataque Acelerado (carga 2.4x en real_dt, bypass si rival indefenso)
## 4. Lluvia de Ki Blasts (Renzoku curvo 1..12 proyectiles / defensa en cajas cuadradas)
##
## Incluye registro extensible de movimientos para futuras secuencias por personaje/transformación.

enum FollowUpState {
	IDLE,
	HITSTOP,
	RAMP_TO_BT,
	DECISION_WINDOW,
	MINI_MELEE_CHASE,
	MINI_VANISH_HAMMER,
	MINI_FAST_SUPER_CHARGE,
	MINI_KI_BARRAGE_ATK,
	MINI_KI_BARRAGE_DEF,
	MINI_HAMMER_DEF,
	COMPLETED
}

signal sequence_finished(action_chosen: String, chain_depth: int)

const ProceduralKiProjectileScript = preload("res://scripts/ProceduralKiProjectile.gd")
const ZENKAI_UI_DIR: String = "res://assets/ui_zenkai/"

var state: FollowUpState = FollowUpState.IDLE
var is_active: bool = false
var attacker: Node3D = null
var defender: Node3D = null
var chain_depth: int = 1
var strike_factor: float = 1.0
var launch_reason: String = ""
var last_action_chosen: String = "none"

var _state_timer: float = 0.0
var _decision_total: float = 3.2
var _decision_remaining: float = 3.2
var _hitstop_total: float = 0.18
var _intro_pause_total: float = 1.0
var _intro_pause_reason: String = ""
var _ramp_total: float = 0.38
var _hammer_window_total: float = 1.1
var _barrage_total: float = 2.2
var _ai_sim_delay: float = 0.0

# Contadores del minijuego Renzoku Ki Barrage (Atacante)
var _barrage_shots_fired: int = 0
var _barrage_max_shots: int = 12
var _barrage_shot_cd: float = 0.0
var _barrage_next_hand: int = 0
var _barrage_prev_trig_l: bool = false
var _barrage_prev_trig_r: bool = false
var _barrage_entry_hold: float = 0.0
var _hammer_entry_hold: float = 0.0
var _melee_entry_armed: bool = false

# Minijuego Defensivo (Reutiliza cajas cuadradas + semáforo de Melee)
var _def_notes: Array[Dictionary] = []
var _def_note_idx: int = 0
var _def_elapsed: float = 0.0
var _def_stick_prev: bool = false
var _def_trig_prev_l: bool = false
var _def_trig_prev_r: bool = false
var _def_ai_hammer_windup: float = 0.0
var _def_barrage_unblockable_shots: int = 0
var _def_barrage_spawn_cd: float = 0.0

# Registro extensible de movimientos de seguimiento
var _move_registry: Array[Dictionary] = []

# Velocidades locales en tiempo real para el minijuego Martillo / Renzoku (inmunes a time_scale)
var _has_prev_hands: bool = false
var _prev_l_loc: Vector3 = Vector3.ZERO
var _prev_r_loc: Vector3 = Vector3.ZERO
var _vel_l_real: Vector3 = Vector3.ZERO
var _vel_r_real: Vector3 = Vector3.ZERO

# Caches y nodos HUD fijados al visor
var _ui_tex_cache: Dictionary = {}
var _hud_anchor: Node3D = null
var _title_label: Label3D = null
var _subtitle_label: Label3D = null
var _status_label: Label3D = null
var _def_actions_label: Label3D = null
var _timer_fill: MeshInstance3D = null
var _timer_fill_mat: StandardMaterial3D = null
var _card_slots: Array[Dictionary] = []
var _hammer_target_node: Node3D = null
var _hammer_ring_mat: StandardMaterial3D = null
var _barrage_rings: Array[Node3D] = []
var _def_box_node: Node3D = null
var _def_box_mat: StandardMaterial3D = null
var _def_ring_mesh: MeshInstance3D = null
var _def_ring_mat: StandardMaterial3D = null
var _def_icon_label: Label3D = null
var _def_hint_label: Label3D = null
var _audio_player: AudioStreamPlayer3D = null
var _last_ai_stab_progress: float = 0.0


func _ready() -> void:
	_register_default_moves()


func _register_default_moves() -> void:
	_move_registry.clear()
	_move_registry.append({ "id": "melee_chase", "title": "MELEE", "cue": "👊 1 Puño", "icon": "icon_fist.png" })
	_move_registry.append({ "id": "vanish_hammer", "title": "MARTILLO", "cue": "🔨 2P Arriba", "icon": "icon_burst.png" })
	_move_registry.append({ "id": "fast_super", "title": "SÚPER 2.4x", "cue": "🔥 Pose Súper", "icon": "target_fight.png" })
	_move_registry.append({ "id": "ki_barrage", "title": "LLUVIA KI", "cue": "💥 2 Palmas", "icon": "icon_ki_blast.png" })


func is_in_intro_pause() -> bool:
	return is_active and state == FollowUpState.HITSTOP


func get_intro_pause_remaining() -> float:
	return maxf(_state_timer, 0.0) if is_in_intro_pause() else 0.0


## Punto de extensión futuro para secuencias exclusivas por personaje o transformación.
func register_custom_move(move_def: Dictionary) -> void:
	if move_def.has("id") and not String(move_def["id"]).is_empty():
		_move_registry.append(move_def)


func get_registered_moves() -> Array[Dictionary]:
	return _move_registry


func get_chain_cost_multiplier() -> float:
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var step: float = float(cfg.chain_ki_cost_step) if cfg.get("chain_ki_cost_step") != null else 0.18
	return 1.0 + float(maxi(chain_depth - 1, 0)) * step


func get_move_ki_cost(move_id: String) -> float:
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var mult: float = get_chain_cost_multiplier()
	match move_id:
		"melee_chase":
			return (float(cfg.followup_melee_cost) if cfg.get("followup_melee_cost") != null else 12.0) * mult
		"vanish_hammer":
			return (float(cfg.followup_vanish_hammer_cost) if cfg.get("followup_vanish_hammer_cost") != null else 18.0) * mult
		"ki_barrage":
			return (float(cfg.followup_barrage_entry_cost) if cfg.get("followup_barrage_entry_cost") != null else 10.0) * mult
		"fast_super":
			return 24.0
	return 12.0


func start_sequence(p_attacker: Node3D, p_defender: Node3D, p_strike_factor: float = 1.0, p_reason: String = "", p_award_launch_bonus: bool = true) -> void:
	if not p_attacker or not is_instance_valid(p_attacker) or not p_defender or not is_instance_valid(p_defender):
		queue_free()
		return

	attacker = p_attacker
	defender = p_defender
	strike_factor = clampf(p_strike_factor, 0.75, 2.0)
	launch_reason = p_reason
	last_action_chosen = "none"

	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	_hitstop_total = float(cfg.followup_hitstop_sec) if cfg.get("followup_hitstop_sec") != null else 0.18
	_intro_pause_total = float(cfg.followup_intro_pause_sec) if cfg.get("followup_intro_pause_sec") != null else 1.0
	_ramp_total = float(cfg.followup_ramp_sec) if cfg.get("followup_ramp_sec") != null else 0.38
	_decision_total = float(cfg.followup_decision_duration) if cfg.get("followup_decision_duration") != null else 3.2
	_decision_remaining = _decision_total
	_hammer_window_total = float(cfg.followup_hammer_window_sec) if cfg.get("followup_hammer_window_sec") != null else 1.1
	_barrage_total = float(cfg.followup_barrage_duration) if cfg.get("followup_barrage_duration") != null else 2.2
	_barrage_max_shots = int(cfg.followup_barrage_max_shots) if cfg.get("followup_barrage_max_shots") != null else 12

	var prev_depth: int = int(attacker.get("combat_chain_depth")) if attacker.get("combat_chain_depth") != null else 0
	chain_depth = prev_depth + 1
	attacker.set("combat_chain_depth", chain_depth)
	attacker.set("active_followup_controller", self)
	attacker.set("opponent_airborne_target", defender)
	attacker.set("is_in_followup_bullet_time", true)
	attacker.set("followup_bullet_time_timer", _intro_pause_total + _ramp_total + _decision_total + 4.0)

	if p_award_launch_bonus:
		var launch_bonus: float = float(cfg.followup_launch_ki_bonus) if cfg.get("followup_launch_ki_bonus") != null else 14.0
		if attacker.has_method("recharge_ki"):
			attacker.recharge_ki(launch_bonus)

	var atk_bp: float = float(attacker.get("current_np")) if attacker.get("current_np") != null else 10000.0
	var already_crashed: bool = bool(defender.get("is_defenseless_crash")) or (int(defender.get("vulnerability_state")) if defender.get("vulnerability_state") != null else 0) == 3
	if not already_crashed and defender.has_method("enter_airborne_launched"):
		defender.enter_airborne_launched(atk_bp, strike_factor, 24.0)

	# Cargar posibles secuencias personalizadas del personaje o transformación
	if attacker.has_method("get_custom_followup_moves"):
		var custom_list: Variant = attacker.call("get_custom_followup_moves")
		if custom_list is Array:
			for cm in custom_list:
				if cm is Dictionary:
					register_custom_move(cm)

	is_active = true
	_ai_sim_delay = 0.0
	_last_ai_stab_progress = 0.0
	_enter_intro_pause(p_reason)

	_audio_player = AudioStreamPlayer3D.new()
	add_child(_audio_player)
	AudioActionManager.play_action("common.melee_hit_heavy", _audio_player)
	_pulse_attacker_hands(220.0, 0.95, 0.16)

	var bounce_tag: String = (" ⚡ ¡REBOTE Z x%d!" % chain_depth) if chain_depth >= 2 else ""
	if bool(attacker.get("is_player")):
		if attacker.has_method("_log_combat_event"):
			attacker._log_combat_event("⚡ ¡LANZAMIENTO EXITOSO! (+14 Ki)%s Elige continuación..." % bounce_tag, "success")
	else:
		if defender.has_method("_log_combat_event"):
			defender._log_combat_event("⚠️ ¡SALISTE VOLANDO!%s ¡Agita los controles para estabilizarte!" % bounce_tag, "warning")


func _get_player_fighter() -> Node3D:
	if attacker and is_instance_valid(attacker) and bool(attacker.get("is_player")):
		return attacker
	if defender and is_instance_valid(defender) and bool(defender.get("is_player")):
		return defender
	return null


func _get_player_camera() -> Camera3D:
	var pf: Node3D = _get_player_fighter()
	if pf and is_instance_valid(pf):
		var orig: Node = pf.get_parent()
		if orig:
			var cam: Camera3D = orig.get_node_or_null("XRCamera3D") as Camera3D
			if cam and is_instance_valid(cam):
				return cam
	return get_viewport().get_camera_3d() if (is_inside_tree() and get_viewport()) else null


func _get_player_controller(hand_name: String) -> XRController3D:
	var pf: Node3D = _get_player_fighter()
	if not pf or not is_instance_valid(pf):
		return null
	var orig: Node = pf.get_parent()
	if not orig:
		return null
	var c: XRController3D = orig.get_node_or_null(hand_name) as XRController3D
	if c and is_instance_valid(c):
		return c
	return null


func _ctrl_pressed(ctrl: XRController3D, action_name: StringName) -> bool:
	return ctrl != null and is_instance_valid(ctrl) and ctrl.is_button_pressed(action_name)


func _ctrl_float(ctrl: XRController3D, action_name: StringName) -> float:
	if not ctrl or not is_instance_valid(ctrl):
		return 0.0
	return ctrl.get_float(action_name)


func _ctrl_vec2(ctrl: XRController3D, action_name: StringName) -> Vector2:
	if not ctrl or not is_instance_valid(ctrl):
		return Vector2.ZERO
	return ctrl.get_vector2(action_name)


func _pulse_attacker_hands(freq: float, amp: float, dur: float) -> void:
	if not attacker or not is_instance_valid(attacker) or not bool(attacker.get("is_player")):
		return
	for hn in ["LeftHand", "RightHand"]:
		var c: XRController3D = _get_player_controller(hn)
		if c and c.has_method("trigger_haptic_pulse"):
			c.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _pulse_defender_hands(freq: float, amp: float, dur: float) -> void:
	if not defender or not is_instance_valid(defender) or not bool(defender.get("is_player")):
		return
	for hn in ["LeftHand", "RightHand"]:
		var c: XRController3D = _get_player_controller(hn)
		if c and c.has_method("trigger_haptic_pulse"):
			c.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)


func _get_ui_tex(fn: String) -> Texture2D:
	if fn.is_empty():
		return null
	if _ui_tex_cache.has(fn):
		return _ui_tex_cache[fn] as Texture2D
	var path: String = fn if fn.begins_with("res://") else (ZENKAI_UI_DIR + fn)
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null
	_ui_tex_cache[fn] = tex
	return tex


func _update_real_hand_velocities(real_dt: float) -> void:
	var lc: XRController3D = _get_player_controller("LeftHand")
	var rc: XRController3D = _get_player_controller("RightHand")
	var pf: Node3D = _get_player_fighter()
	var orig: Node3D = pf.get_parent() as Node3D if (pf and pf.get_parent() is Node3D) else null
	var orig_basis: Basis = orig.global_transform.basis.orthonormalized() if orig else Basis.IDENTITY
	var l_loc: Vector3 = lc.position if lc else Vector3.ZERO
	var r_loc: Vector3 = rc.position if rc else Vector3.ZERO
	if _has_prev_hands and real_dt > 0.0005:
		_vel_l_real = orig_basis * ((l_loc - _prev_l_loc) / real_dt)
		_vel_r_real = orig_basis * ((r_loc - _prev_r_loc) / real_dt)
	_prev_l_loc = l_loc
	_prev_r_loc = r_loc
	_has_prev_hands = true


func _is_defender_stabilized() -> bool:
	if not defender or not is_instance_valid(defender):
		return true
	if defender.has_method("is_vulnerable_defenseless"):
		return not bool(defender.is_vulnerable_defenseless())
	return not bool(defender.get("is_defenseless_crash"))


func _process(delta: float) -> void:
	if not is_active:
		return
	if not attacker or not is_instance_valid(attacker) or not defender or not is_instance_valid(defender):
		_finish_sequence("invalid", true)
		return
	if bool(attacker.get("is_match_over")) or bool(defender.get("is_match_over")):
		_finish_sequence("match_over", false)
		return

	var real_dt: float = clampf(delta / maxf(Engine.time_scale, 0.005), 0.001, 0.08)
	_update_real_hand_velocities(real_dt)

	match state:
		FollowUpState.HITSTOP:
			if _state_timer > 0.0 and Engine.time_scale > 0.01:
				Engine.time_scale = 0.005
			_state_timer -= real_dt
			_refresh_intro_pause_hud()
			if _state_timer <= 0.0:
				state = FollowUpState.RAMP_TO_BT
				_state_timer = _ramp_total
				Engine.time_scale = 1.0
				_on_intro_pause_unlocked()
		FollowUpState.RAMP_TO_BT:
			_state_timer -= real_dt
			var t_ramp: float = clampf(1.0 - (_state_timer / maxf(_ramp_total, 0.01)), 0.0, 1.0)
			Engine.time_scale = lerpf(1.0, 0.12, t_ramp)
			_tick_ai_stabilization(real_dt)
			_refresh_decision_hud()
			if _state_timer <= 0.0:
				_enter_decision_window()
		FollowUpState.DECISION_WINDOW:
			_process_decision_window(real_dt)
		FollowUpState.MINI_VANISH_HAMMER:
			_process_mini_vanish_hammer(real_dt)
		FollowUpState.MINI_HAMMER_DEF:
			_process_mini_hammer_def(real_dt)
		FollowUpState.MINI_KI_BARRAGE_ATK:
			_process_mini_ki_barrage_atk(real_dt)
		FollowUpState.MINI_KI_BARRAGE_DEF:
			_process_mini_ki_barrage_def(real_dt)
		FollowUpState.MINI_FAST_SUPER_CHARGE:
			# El temporizador de decisión queda pausado mientras carga Súper; el fin lo notifica HybridCombatController
			Engine.time_scale = 0.12
			_refresh_status_hud_for_defender()


func _enter_intro_pause(p_reason: String = "") -> void:
	state = FollowUpState.HITSTOP
	_intro_pause_reason = p_reason
	_state_timer = _intro_pause_total
	Engine.time_scale = 0.005
	_hammer_entry_hold = 0.0
	_barrage_entry_hold = 0.0
	_melee_entry_armed = false
	_build_visor_hud()
	_refresh_intro_pause_hud()
	var pf: Node3D = _get_player_fighter()
	if pf and is_instance_valid(pf) and pf.has_method("_get_gesture_tree"):
		var gss: Node = pf._get_gesture_tree()
		if gss and gss.has_signal("phase_changed"):
			gss.emit_signal("phase_changed", "⏸️ ¡SIGUIENTE SECUENCIA! (%.1fs) — LEE TUS ACCIONES" % _intro_pause_total)


func _on_intro_pause_unlocked() -> void:
	if bool(attacker.get("is_player")):
		_pulse_attacker_hands(160.0, 0.45, 0.06)
		if _title_label and is_instance_valid(_title_label):
			_title_label.text = ("⚡ ¡REBOTE Z x%d! ¡ACTÚA AHORA!" % chain_depth) if chain_depth >= 2 else "⚡ ¡ELIGE SEGUIMIENTO!"
			_title_label.modulate = Color(1.0, 0.94, 0.30)
		if _subtitle_label and is_instance_valid(_subtitle_label):
			_subtitle_label.text = "⚡ ¡ELIGE TU ACCIÓN AHORA!"
			_subtitle_label.modulate = Color(0.30, 1.0, 0.55)
		if _timer_fill_mat:
			_timer_fill_mat.albedo_color = Color(1.0, 0.88, 0.22)
	elif bool(defender.get("is_player")):
		_pulse_defender_hands(160.0, 0.45, 0.06)
		if _title_label and is_instance_valid(_title_label):
			_title_label.text = "⚡ ¡SIGUIENTE SECUENCIA EN CURSO!"
			_title_label.modulate = Color(1.0, 0.88, 0.30)
		if _timer_fill and is_instance_valid(_timer_fill):
			_timer_fill.visible = false
		_refresh_status_hud_for_defender()


func _enter_decision_window() -> void:
	state = FollowUpState.DECISION_WINDOW
	Engine.time_scale = 0.12
	_decision_remaining = _decision_total
	_ai_sim_delay = 0.0
	_hammer_entry_hold = 0.0
	_barrage_entry_hold = 0.0
	_melee_entry_armed = false
	if not _hud_anchor or not is_instance_valid(_hud_anchor) or (bool(attacker.get("is_player")) and _card_slots.is_empty()):
		_build_visor_hud()
	if bool(attacker.get("is_player")):
		if _title_label and is_instance_valid(_title_label):
			_title_label.text = ("⚡ ¡REBOTE Z x%d!" % chain_depth) if chain_depth >= 2 else "⚡ ¡ELIGE SEGUIMIENTO!"
			_title_label.modulate = Color(1.0, 0.94, 0.30)
		if _subtitle_label and is_instance_valid(_subtitle_label):
			_subtitle_label.text = "⚡ ¡ELIGE TU ACCIÓN AHORA!"
			_subtitle_label.modulate = Color(0.30, 1.0, 0.55)
		if _timer_fill_mat:
			_timer_fill_mat.albedo_color = Color(1.0, 0.88, 0.22)
		if _timer_fill and is_instance_valid(_timer_fill):
			_timer_fill.visible = true
		var gss: Node = attacker._get_gesture_tree() if attacker.has_method("_get_gesture_tree") else null
		if gss and gss.has_signal("phase_changed"):
			gss.emit_signal("phase_changed", "⚡ ¡ELIGE SEGUIMIENTO! (MELEE / MARTILLO / SÚPER / LLUVIA)")
	else:
		if _title_label and is_instance_valid(_title_label):
			_title_label.text = "⚡ ¡SIGUIENTE SECUENCIA EN CURSO!"
			_title_label.modulate = Color(1.0, 0.88, 0.30)
		if _timer_fill and is_instance_valid(_timer_fill):
			_timer_fill.visible = false
	_refresh_decision_hud()


func _tick_ai_stabilization(real_dt: float) -> void:
	if not defender or not is_instance_valid(defender) or bool(defender.get("is_player")):
		return
	var v_state: int = int(defender.get("vulnerability_state")) if defender.get("vulnerability_state") != null else 0
	if v_state != 1: # AIRBORNE_LAUNCHED
		return
	var req: float = maxf(float(defender.get("air_brake_required_effort")) if defender.get("air_brake_required_effort") != null else 5.0, 2.0)
	var rate: float = clampf(1.55 / req, 0.12, 0.55)
	_last_ai_stab_progress = minf(_last_ai_stab_progress + rate * real_dt, 1.0)
	defender.set("air_brake_progress", _last_ai_stab_progress)
	if _last_ai_stab_progress >= 1.0:
		if defender.has_method("complete_air_brake"):
			defender.complete_air_brake()
		else:
			defender.set("vulnerability_state", 2)
			defender.set("airborne_recovery_state", "RECOVERED")


func _process_decision_window(real_dt: float) -> void:
	_decision_remaining -= real_dt
	_tick_ai_stabilization(real_dt)
	_refresh_decision_hud()

	if _decision_remaining <= 0.0:
		_finish_sequence("timeout", true)
		return

	if bool(attacker.get("is_player")):
		_poll_player_decision_gestures(real_dt)
	else:
		_poll_ai_decision(real_dt)


func _poll_player_decision_gestures(real_dt: float) -> void:
	var lc: XRController3D = _get_player_controller("LeftHand")
	var rc: XRController3D = _get_player_controller("RightHand")
	var cam: Camera3D = _get_player_camera()
	if not lc or not rc or not cam:
		return

	var l_grip: bool = _ctrl_float(lc, &"grip") > 0.45 or _ctrl_pressed(lc, &"grip_click")
	var l_trig: bool = _ctrl_float(lc, &"trigger") > 0.45 or _ctrl_pressed(lc, &"trigger_click")
	var r_grip: bool = _ctrl_float(rc, &"grip") > 0.45 or _ctrl_pressed(rc, &"grip_click")
	var r_trig: bool = _ctrl_float(rc, &"trigger") > 0.45 or _ctrl_pressed(rc, &"trigger_click")
	var l_fist: bool = l_grip and l_trig
	var r_fist: bool = r_grip and r_trig

	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.001 else Vector3.FORWARD
	var head_p: Vector3 = cam.global_position
	var l_rel_y: float = lc.global_position.y - head_p.y
	var r_rel_y: float = rc.global_position.y - head_p.y
	var l_fwd_z: float = (lc.global_position - head_p).dot(cam_fwd)
	var r_fwd_z: float = (rc.global_position - head_p).dot(cam_fwd)

	# 1. VANISH + MARTILLO: ambos puños cerrados elevados sobre la cabeza
	if l_fist and r_fist and (l_rel_y >= -0.04 and r_rel_y >= -0.04):
		_hammer_entry_hold += real_dt
		if _hammer_entry_hold >= 0.08:
			if choose_vanish_hammer():
				return
	else:
		_hammer_entry_hold = 0.0

	# 2. LLUVIA DE KI BLASTS: ambas palmas con gatillo al frente (sin Grip)
	if not l_grip and not r_grip and (l_trig and r_trig) and l_fwd_z >= 0.24 and r_fwd_z >= 0.24:
		_barrage_entry_hold += real_dt
		if _barrage_entry_hold >= 0.07:
			if choose_ki_barrage():
				return
	else:
		_barrage_entry_hold = 0.0

	# 3. OTRO MELEE (Meteor Chase): un solo puño cerrado empujado al frente
	if l_fist != r_fist:
		var act_z: float = l_fwd_z if l_fist else r_fwd_z
		var act_vz: float = (_vel_l_real if l_fist else _vel_r_real).dot(cam_fwd)
		if act_z <= 0.32:
			_melee_entry_armed = true
		if (_melee_entry_armed and act_z >= 0.33 and act_vz >= 1.20) or (act_z >= 0.38 and act_vz >= 1.75):
			choose_melee_chase()


func _poll_ai_decision(real_dt: float) -> void:
	_ai_sim_delay += real_dt
	var wait_s: float = 0.65
	if _ai_sim_delay < wait_s:
		return

	var def_crashed: bool = int(defender.get("vulnerability_state")) == 3 or bool(defender.get("is_defenseless_crash"))
	var def_vuln: bool = defender.has_method("is_vulnerable_defenseless") and bool(defender.is_vulnerable_defenseless())
	var atk_ki: float = float(attacker.get("current_ki")) if attacker.get("current_ki") != null else 0.0

	# Priorizar Martillo sobre objetivo aéreo, Súper/Lluvia sobre objetivo estampado y Melee para Rebotes Z
	if def_crashed and atk_ki >= 28.0 and randf() < 0.55:
		if choose_ai_fast_super():
			return
	if not def_crashed and atk_ki >= get_move_ki_cost("vanish_hammer") and randf() < (0.50 if def_vuln else 0.30):
		if choose_vanish_hammer():
			return
	if atk_ki >= get_move_ki_cost("ki_barrage") and randf() < 0.50:
		if choose_ki_barrage():
			return
	if atk_ki >= get_move_ki_cost("melee_chase") and chain_depth < 5:
		if choose_melee_chase():
			return
	if atk_ki >= get_move_ki_cost("ki_barrage"):
		if choose_ki_barrage():
			return
	_finish_sequence("no_ki", true)


func notify_super_charge_started(_tech_name: String = "") -> void:
	if not is_active:
		return
	if state == FollowUpState.DECISION_WINDOW or state == FollowUpState.RAMP_TO_BT or state == FollowUpState.HITSTOP:
		state = FollowUpState.MINI_FAST_SUPER_CHARGE
		last_action_chosen = "fast_super"
		Engine.time_scale = 0.12
		_clear_action_hud()
		_build_defender_status_only_hud()


func notify_super_fired() -> void:
	if not is_active:
		return
	last_action_chosen = "fast_super"
	_finish_sequence("fast_super", false)


func notify_super_cancelled() -> void:
	if not is_active:
		return
	if state == FollowUpState.MINI_FAST_SUPER_CHARGE:
		if _decision_remaining > 0.35:
			_enter_decision_window()
		else:
			_finish_sequence("super_cancelled", true)


func choose_melee_chase() -> bool:
	if not is_active:
		return false
	var cost: float = get_move_ki_cost("melee_chase")
	if float(attacker.get("current_ki")) < cost:
		return false
	attacker.consume_ki(cost)
	last_action_chosen = "melee_chase"
	state = FollowUpState.MINI_MELEE_CHASE
	var is_def_vuln: bool = defender.has_method("is_vulnerable_defenseless") and bool(defender.is_vulnerable_defenseless())
	defender.set_meta("followup_melee_defenseless", is_def_vuln)
	if attacker.has_method("start_flight_to_opponent"):
		attacker.start_flight_to_opponent()
	attacker.set("pending_followup_bonus_hits", 2 if is_def_vuln else 0)
	attacker.set("pending_followup_damage_mult", 1.25 if is_def_vuln else 1.0)
	_finish_sequence("melee_chase", false)
	return true


func choose_ai_fast_super() -> bool:
	if not is_active or bool(attacker.get("is_player")):
		return false
	var ai_ctrl: Node = attacker.get("cached_ai_controller") as Node
	if not ai_ctrl or not is_instance_valid(ai_ctrl):
		return false
	last_action_chosen = "fast_super"
	_finish_sequence("fast_super", false)
	if ai_ctrl.has_method("_transition_to"):
		ai_ctrl.call("_transition_to", 3) # AIState.KAMEHAMEHA_CHARGE
	return true


func choose_vanish_hammer() -> bool:
	if not is_active:
		return false
	var cost: float = get_move_ki_cost("vanish_hammer")
	if float(attacker.get("current_ki")) < cost:
		return false
	attacker.consume_ki(cost)
	last_action_chosen = "vanish_hammer"
	_clear_action_hud()

	# Teletransporte instantáneo encima y frente al defensor
	_teleport_attacker_above_defender()

	if bool(attacker.get("is_player")):
		state = FollowUpState.MINI_VANISH_HAMMER
		_state_timer = _hammer_window_total
		Engine.time_scale = 0.22
		_build_hammer_attacker_target()
		_pulse_attacker_hands(190.0, 0.90, 0.14)
	else:
		# IA atacando: si jugador se estabilizó -> abrir caja cuadrada púrpura con semáforo
		if _is_defender_stabilized() and bool(defender.get("is_player")):
			state = FollowUpState.MINI_HAMMER_DEF
			_state_timer = 0.92
			_def_ai_hammer_windup = 0.92
			_def_stick_prev = false
			Engine.time_scale = 0.25
			_build_defense_box_hud("🔨", Color(0.95, 0.22, 1.0, 0.95), "¡Z-VANISH (Stick)!")
		else:
			state = FollowUpState.MINI_VANISH_HAMMER
			_state_timer = 0.35
			Engine.time_scale = 0.40
			_build_defender_status_only_hud()
	return true


func choose_ki_barrage() -> bool:
	if not is_active:
		return false
	var cost: float = get_move_ki_cost("ki_barrage")
	if float(attacker.get("current_ki")) < cost:
		return false
	attacker.consume_ki(cost)
	last_action_chosen = "ki_barrage"
	_clear_action_hud()

	_barrage_shots_fired = 0
	_barrage_shot_cd = 0.0
	_barrage_next_hand = 0
	_barrage_prev_trig_l = false
	_barrage_prev_trig_r = false

	if bool(attacker.get("is_player")):
		state = FollowUpState.MINI_KI_BARRAGE_ATK
		_state_timer = _barrage_total
		Engine.time_scale = 0.58
		_build_barrage_attacker_hud()
	else:
		if _is_defender_stabilized() and bool(defender.get("is_player")):
			state = FollowUpState.MINI_KI_BARRAGE_DEF
			_setup_barrage_defense_notes()
			Engine.time_scale = 0.35
			_build_defense_box_hud("💥", Color(0.20, 0.88, 1.0, 0.95), "¡TRIGGER DESVÍO o GUARDIA X!")
		else:
			state = FollowUpState.MINI_KI_BARRAGE_DEF
			_def_notes.clear()
			_def_barrage_unblockable_shots = 6
			_def_barrage_spawn_cd = 0.0
			_state_timer = 1.15
			Engine.time_scale = 0.55
			_build_defender_status_only_hud()
	return true


func _teleport_attacker_above_defender() -> void:
	var def_pos: Vector3 = defender.global_position
	var atk_root: Node3D = attacker.get_spatial_root() if attacker.has_method("get_spatial_root") else attacker
	var to_atk: Vector3 = atk_root.global_position - def_pos
	to_atk.y = 0.0
	var horiz: Vector3 = to_atk.normalized() if to_atk.length_squared() > 0.01 else Vector3.BACK
	var dest: Vector3 = def_pos + horiz * 0.95 + Vector3(0.0, 1.65, 0.0)
	var ground_y: float = attacker.get_ground_elevation(dest) if attacker.has_method("get_ground_elevation") else 0.0
	dest.y = maxf(dest.y, ground_y + 1.8)
	if is_inside_tree() and get_tree():
		KiSmokeFX.spawn_smoke(get_tree(), atk_root.global_position + Vector3.UP * 0.9, 0.85)
		KiSmokeFX.spawn_smoke(get_tree(), dest + Vector3.UP * 0.5, 0.95)
	atk_root.global_position = dest
	attacker.set("velocity", Vector3.ZERO)
	attacker.set("is_knocked_back", false)
	if not bool(attacker.get("is_player")):
		var look_d: Vector3 = def_pos - dest
		look_d.y = 0.0
		if look_d.length_squared() > 0.001:
			attacker.rotation.y = atan2(look_d.x, look_d.z)
	if _audio_player:
		AudioActionManager.play_action("common.dodge_vanish", _audio_player)


func _process_mini_vanish_hammer(real_dt: float) -> void:
	_state_timer -= real_dt
	if bool(attacker.get("is_player")):
		var lc: XRController3D = _get_player_controller("LeftHand")
		var rc: XRController3D = _get_player_controller("RightHand")
		var cam: Camera3D = _get_player_camera()
		var l_fist: bool = lc != null and (_ctrl_float(lc, &"grip") > 0.40 or _ctrl_pressed(lc, &"grip_click"))
		var r_fist: bool = rc != null and (_ctrl_float(rc, &"grip") > 0.40 or _ctrl_pressed(rc, &"grip_click"))
		var avg_vy: float = (_vel_l_real.y + _vel_r_real.y) * 0.5
		var below_chest: bool = false
		if cam and lc and rc:
			below_chest = ((lc.global_position.y + rc.global_position.y) * 0.5 - cam.global_position.y) <= -0.14
		if _hammer_target_node and is_instance_valid(_hammer_target_node):
			var frac: float = clampf(_state_timer / maxf(_hammer_window_total, 0.01), 0.0, 1.0)
			_hammer_target_node.scale = Vector3.ONE * (0.85 + frac * 0.35)
		if (l_fist or r_fist) and ((avg_vy <= -1.05 and below_chest) or avg_vy <= -1.95):
			_execute_hammer_slam_impact(clampf(absf(avg_vy), 2.2, 5.2))
			return
		if _state_timer <= 0.0:
			# Si expira con algún gesto abajo, ejecutar golpe suave; sino cancelar
			if below_chest and (l_fist or r_fist):
				_execute_hammer_slam_impact(2.4)
			else:
				_finish_sequence("hammer_timeout", true)
	else:
		# IA ejecutora cuando jugador NO se estabilizó
		if _state_timer <= 0.0:
			_execute_hammer_slam_impact(3.6)


func _process_mini_hammer_def(real_dt: float) -> void:
	_state_timer -= real_dt
	var total_t: float = 0.92
	var norm_t: float = clampf(_state_timer / total_t, 0.0, 1.0)
	var in_green: bool = (_state_timer <= 0.34 and _state_timer >= -0.10)
	if _def_ring_mesh and is_instance_valid(_def_ring_mesh):
		_def_ring_mesh.scale = Vector3.ONE * (1.0 + norm_t * 1.45)
	if _def_ring_mat:
		_def_ring_mat.albedo_color = Color(0.15, 1.0, 0.35, 1.0) if in_green else Color(0.95, 0.20, 1.0, 0.96)

	var lc: XRController3D = _get_player_controller("LeftHand")
	var rc: XRController3D = _get_player_controller("RightHand")
	var stick_l: float = _ctrl_vec2(lc, &"primary").length()
	var stick_r: float = _ctrl_vec2(rc, &"primary").length()
	var stick_clk: bool = _ctrl_pressed(lc, &"primary_click") or _ctrl_pressed(rc, &"primary_click")
	var stick_now: bool = maxf(stick_l, stick_r) >= 0.55 or stick_clk
	var fresh_stick: bool = stick_now and not _def_stick_prev
	_def_stick_prev = stick_now

	if fresh_stick and in_green:
		var cfg_z: KiEconomyConfig = KiEconomyConfig.get_default()
		var zv_cost: float = float(cfg_z.melee_vanish_cost) if cfg_z.get("melee_vanish_cost") != null else 10.0
		if float(defender.get("current_ki")) >= zv_cost:
			defender.consume_ki(zv_cost)
			if defender.has_method("recharge_ki"):
				defender.recharge_ki(10.0)
			if defender.has_method("_log_combat_event"):
				defender._log_combat_event("💨 ¡Z-VANISH VS MARTILLO! Esquivaste la caída.", "success")
			if _audio_player:
				AudioActionManager.play_action("common.dodge_vanish", _audio_player)
			_finish_sequence("hammer_evaded", true)
			return

	if _state_timer <= -0.10:
		_execute_hammer_slam_impact(3.6)


func _execute_hammer_slam_impact(swing_speed: float) -> void:
	var bp_atk: float = maxf(float(attacker.get("current_np")) if attacker.get("current_np") != null else 10000.0, 1000.0)
	var bp_def: float = maxf(float(defender.get("current_np")) if defender.get("current_np") != null else 10000.0, 1000.0)
	var ratio_bp: float = clampf(pow(bp_atk / bp_def, 0.6), 0.55, 2.2)
	var dmg: float = clampf((540.0 + swing_speed * 65.0) * ratio_bp, 420.0, 1250.0)

	if defender.has_method("take_hit"):
		defender.take_hit(dmg, Vector3.DOWN, true)
	if attacker.has_method("increase_np"):
		attacker.increase_np(dmg * 0.75)

	# Llevar a la víctima directo al suelo y activar CRASHED_STAMPED + +18 Ki
	var def_root: Node3D = defender.get_spatial_root() if defender.has_method("get_spatial_root") else defender
	var cur_p: Vector3 = def_root.global_position
	var g_h: float = attacker.get_ground_elevation(cur_p) if attacker.has_method("get_ground_elevation") else 0.0
	def_root.global_position = Vector3(cur_p.x, g_h, cur_p.z)
	if defender.has_method("_on_ground_crash_impact"):
		defender.set("_last_launch_strike_factor", 1.85)
		defender.call("_on_ground_crash_impact", clampf(swing_speed * 4.5, 14.0, 26.0), def_root.global_position, g_h)
	elif defender.has_method("enter_crashed_stamped"):
		defender.enter_crashed_stamped(attacker, 1.85)

	_pulse_attacker_hands(220.0, 1.0, 0.25)
	_pulse_defender_hands(220.0, 1.0, 0.30)
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), def_root.global_position + Vector3.UP * 0.4, 3, Color(0.92, 0.24, 1.0, 0.95), true)
	if _audio_player:
		AudioActionManager.play_action("common.melee_hit_heavy", _audio_player)

	if bool(attacker.get("is_player")) and attacker.has_method("_log_combat_event"):
		attacker._log_combat_event("🔨 ¡MARTILLAZO DE SEGUIMIENTO! Rival estampado (+18 Ki) [Daño: %d NP]" % int(dmg), "success")

	# Si todavía hay Ki suficiente para rematar al rival estampado y no superamos tope de cadena, volver a pausa introductoria de siguiente secuencia
	if not bool(attacker.get("is_match_over")) and float(attacker.get("current_ki")) >= 10.0 and chain_depth < 6:
		chain_depth += 1
		attacker.set("combat_chain_depth", chain_depth)
		_clear_action_hud()
		_enter_intro_pause("hammer_slam_chain")
	else:
		_finish_sequence("vanish_hammer", true)


func _process_mini_ki_barrage_atk(real_dt: float) -> void:
	_state_timer -= real_dt
	_barrage_shot_cd = maxf(_barrage_shot_cd - real_dt, 0.0)
	var lc: XRController3D = _get_player_controller("LeftHand")
	var rc: XRController3D = _get_player_controller("RightHand")
	var l_trig: bool = _ctrl_float(lc, &"trigger") > 0.45 or _ctrl_pressed(lc, &"trigger_click")
	var r_trig: bool = _ctrl_float(rc, &"trigger") > 0.45 or _ctrl_pressed(rc, &"trigger_click")
	var fresh_l: bool = l_trig and not _barrage_prev_trig_l
	var fresh_r: bool = r_trig and not _barrage_prev_trig_r
	_barrage_prev_trig_l = l_trig
	_barrage_prev_trig_r = r_trig

	var palm_push_l: bool = _vel_l_real.length() >= 1.65 and not l_trig
	var palm_push_r: bool = _vel_r_real.length() >= 1.65 and not r_trig
	var want_fire: bool = fresh_l or fresh_r or ((l_trig or r_trig or palm_push_l or palm_push_r) and _barrage_shot_cd <= 0.0)

	if want_fire and _barrage_shot_cd <= 0.0 and _barrage_shots_fired < _barrage_max_shots:
		var use_hand: int = 0 if fresh_l else (1 if fresh_r else _barrage_next_hand)
		if fire_barrage_shot(use_hand):
			_barrage_next_hand = 1 - use_hand
			_barrage_shot_cd = 0.095
			if _barrage_shots_fired >= _barrage_max_shots:
				_finish_sequence("ki_barrage", true)
				return

	if _timer_fill and is_instance_valid(_timer_fill):
		var frac: float = clampf(_state_timer / maxf(_barrage_total, 0.01), 0.02, 1.0)
		_timer_fill.scale = Vector3(frac * 0.36, 1.0, 1.0)

	if _state_timer <= 0.0:
		if _barrage_shots_fired > 0 and is_inside_tree() and get_tree():
			KiSmokeFX.spawn_smoke(get_tree(), defender.global_position + Vector3.UP * 0.9, 1.55)
		_finish_sequence("ki_barrage", true)


## Dispara un proyectil curvo Renzoku; también invocable directamente en tests headless.
func fire_barrage_shot(hand_side: int) -> bool:
	if not attacker or not is_instance_valid(attacker) or not defender or not is_instance_valid(defender):
		return false
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var shot_cost: float = float(cfg.followup_barrage_shot_cost) if cfg.get("followup_barrage_shot_cost") != null else 1.5
	if float(attacker.get("current_ki")) < shot_cost:
		return false
	attacker.consume_ki(shot_cost)
	_barrage_shots_fired += 1

	var is_final: bool = (_barrage_shots_fired >= _barrage_max_shots)
	var atk_root: Node3D = attacker.get_spatial_root() if attacker.has_method("get_spatial_root") else attacker
	var spawn_pos: Vector3 = atk_root.global_position + Vector3(0.0, 1.25, 0.0)
	var ctrl: XRController3D = _get_player_controller("LeftHand" if hand_side == 0 else "RightHand") if bool(attacker.get("is_player")) else null
	if ctrl:
		spawn_pos = ctrl.global_position
	else:
		var side_x: float = -0.35 if hand_side == 0 else 0.35
		spawn_pos += attacker.global_transform.basis * Vector3(side_x, 0.0, 0.45)

	var def_pos: Vector3 = defender.global_position + Vector3(0.0, 1.05, 0.0)
	var to_def: Vector3 = (def_pos - spawn_pos).normalized()
	if to_def.length_squared() < 0.001:
		to_def = Vector3.FORWARD
	var side_vec: Vector3 = to_def.cross(Vector3.UP).normalized()
	if side_vec.length_squared() < 0.001:
		side_vec = Vector3.RIGHT
	var arc_sign: float = -1.0 if (hand_side == 0) else 1.0
	var spread_dir: Vector3 = (to_def + side_vec * arc_sign * 0.36 + Vector3.UP * randf_range(0.06, 0.24)).normalized()

	var energy_col := Color(0.20, 0.85, 1.0, 0.95)
	if attacker.get("character_data") and attacker.character_data.powers.size() > 0:
		energy_col = attacker.character_data.powers[0].energy_color

	var proj := Node3D.new()
	proj.name = "RenzokuKiBlast_%d" % _barrage_shots_fired
	var p_rad: float = 0.22 if is_final else 0.09
	ZenkaiVFXManager.build_zenkai_orb_visual(proj, p_rad, energy_col, is_final, is_final)
	proj.set_script(ProceduralKiProjectileScript)
	proj.set("speed_velocity", spread_dir * (64.0 if is_final else 54.0))
	proj.set("p_radius", p_rad)
	proj.set("p_color", energy_col)
	proj.set("tier", 2 if is_final else 1)
	proj.set("base_damage", 420.0 if is_final else 185.0)
	proj.set("explosion_radius", 2.4 if is_final else 1.1)
	proj.set("shooter_node", attacker)
	proj.set("original_shooter", attacker)
	proj.set("homing_target", defender)
	proj.set("homing_strength", 15.5)
	proj.set("is_volley_final", is_final)
	var is_def_vuln: bool = defender.has_method("is_vulnerable_defenseless") and bool(defender.is_vulnerable_defenseless())
	proj.set("unblockable_defenseless", is_def_vuln)
	if attacker.has_method("get_projectile_exclude_rids"):
		proj.set("ray_query_exclude", attacker.get_projectile_exclude_rids().duplicate())

	var scene_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(proj)
		proj.global_position = spawn_pos

	if _audio_player:
		_audio_player.pitch_scale = randf_range(0.92, 1.12)
		AudioActionManager.play_action("common.ki_blast_fire", _audio_player)
	if ctrl and ctrl.has_method("trigger_haptic_pulse"):
		ctrl.trigger_haptic_pulse("haptic", 145.0, 0.72, 0.08, 0.0)
	return true


func _setup_barrage_defense_notes() -> void:
	_def_notes.clear()
	_def_note_idx = 0
	_def_elapsed = 0.0
	for i in range(4):
		_def_notes.append({ "time": 0.55 + float(i) * 0.52, "resolved": false })


func _process_mini_ki_barrage_def(real_dt: float) -> void:
	if _def_notes.is_empty():
		_state_timer -= real_dt
		_def_barrage_spawn_cd -= real_dt
		if _def_barrage_unblockable_shots > 0 and _def_barrage_spawn_cd <= 0.0:
			fire_barrage_shot(_def_barrage_unblockable_shots % 2)
			_def_barrage_unblockable_shots -= 1
			_def_barrage_spawn_cd = 0.095
		if _state_timer <= 0.0:
			if is_inside_tree() and get_tree():
				KiSmokeFX.spawn_smoke(get_tree(), defender.global_position + Vector3.UP * 0.9, 1.45)
			_finish_sequence("ki_barrage_hit", true)
		return

	_def_elapsed += real_dt
	if _def_note_idx >= _def_notes.size():
		_finish_sequence("ki_barrage_defended", true)
		return

	var note: Dictionary = _def_notes[_def_note_idx]
	var t_diff: float = float(note["time"]) - _def_elapsed
	var norm_t: float = clampf(maxf(t_diff, 0.0) / 0.55, 0.0, 1.0)
	var in_green: bool = (t_diff <= 0.24 and t_diff >= -0.16)
	if _def_ring_mesh and is_instance_valid(_def_ring_mesh):
		_def_ring_mesh.scale = Vector3.ONE * (1.0 + norm_t * 1.45)
	if _def_ring_mat:
		_def_ring_mat.albedo_color = Color(0.15, 1.0, 0.35, 1.0) if in_green else (Color(1.0, 0.58, 0.10, 0.96) if t_diff <= 0.34 else Color(0.95, 0.16, 0.16, 0.92))

	var lc: XRController3D = _get_player_controller("LeftHand")
	var rc: XRController3D = _get_player_controller("RightHand")
	var l_grip: bool = _ctrl_float(lc, &"grip") > 0.45 or _ctrl_pressed(lc, &"grip_click")
	var r_grip: bool = _ctrl_float(rc, &"grip") > 0.45 or _ctrl_pressed(rc, &"grip_click")
	var l_trig: bool = _ctrl_float(lc, &"trigger") > 0.45 or _ctrl_pressed(lc, &"trigger_click")
	var r_trig: bool = _ctrl_float(rc, &"trigger") > 0.45 or _ctrl_pressed(rc, &"trigger_click")
	var fresh_deflect: bool = ((l_trig and not l_grip and not _def_trig_prev_l) or (r_trig and not r_grip and not _def_trig_prev_r))
	_def_trig_prev_l = l_trig
	_def_trig_prev_r = r_trig

	var is_guard_x: bool = l_grip and r_grip and lc != null and rc != null and lc.global_position.distance_to(rc.global_position) <= 0.42
	if fresh_deflect and t_diff <= 0.28 and t_diff >= -0.16:
		note["resolved"] = true
		_def_note_idx += 1
		if defender.has_method("recharge_ki"):
			defender.recharge_ki(6.0)
		_pulse_defender_hands(175.0, 0.85, 0.10)
		if _audio_player:
			AudioActionManager.play_action("common.ki_blast_deflect", _audio_player)
		if _def_note_idx >= _def_notes.size():
			_finish_sequence("ki_barrage_defended", true)
		return

	if t_diff <= -0.16:
		note["resolved"] = true
		_def_note_idx += 1
		var dmg: float = 65.0 if is_guard_x else 210.0
		if defender.has_method("take_hit"):
			defender.take_hit(dmg, Vector3.BACK, not is_guard_x)
		if defender.has_method("drain_ki"):
			defender.drain_ki(4.0 if not is_guard_x else 2.0)
		_pulse_defender_hands(140.0 if is_guard_x else 200.0, 0.60 if is_guard_x else 0.90, 0.12)
		if _def_note_idx >= _def_notes.size():
			_finish_sequence("ki_barrage_defended", true)


func _build_visor_hud() -> void:
	_clear_action_hud()
	var cam: Camera3D = _get_player_camera()
	if not cam or not is_instance_valid(cam):
		return
	_hud_anchor = Node3D.new()
	_hud_anchor.name = "FollowUpVisorHUD"
	_hud_anchor.position = Vector3(0.0, 0.20, -1.06)
	cam.add_child(_hud_anchor)

	if bool(attacker.get("is_player")):
		var obi_m := MeshInstance3D.new()
		var oq := QuadMesh.new()
		oq.size = Vector2(0.70, 0.075)
		obi_m.mesh = oq
		obi_m.position = Vector3(0.0, 0.105, -0.002)
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		om.no_depth_test = true
		om.render_priority = 123
		var otex: Texture2D = _get_ui_tex("info_obi.png")
		if otex:
			om.albedo_texture = otex
		om.albedo_color = Color(1.0, 0.92, 0.35, 0.90)
		obi_m.material_override = om
		_hud_anchor.add_child(obi_m)

		_title_label = Label3D.new()
		_title_label.text = ("⚡ ¡REBOTE Z x%d!" % chain_depth) if chain_depth >= 2 else "⚡ ¡ELIGE SEGUIMIENTO!"
		_title_label.font_size = 22
		_title_label.pixel_size = 0.00122
		_title_label.no_depth_test = true
		_title_label.render_priority = 126
		_title_label.modulate = Color(1.0, 0.94, 0.30)
		_title_label.outline_size = 8
		_title_label.position = Vector3(0.0, 0.105, 0.002)
		_hud_anchor.add_child(_title_label)

		_subtitle_label = Label3D.new()
		_subtitle_label.text = "ACCIONES DISPONIBLES — ¡PREPÁRATE!"
		_subtitle_label.font_size = 15
		_subtitle_label.pixel_size = 0.00115
		_subtitle_label.no_depth_test = true
		_subtitle_label.render_priority = 126
		_subtitle_label.modulate = Color(0.55, 0.95, 1.0)
		_subtitle_label.outline_size = 6
		_subtitle_label.position = Vector3(0.0, 0.056, 0.003)
		_hud_anchor.add_child(_subtitle_label)

		var cd_atk: Variant = attacker.get("character_data")
		var is_vegeta_atk: bool = cd_atk != null and ("VEGETA" in String(cd_atk.get("character_name")).to_upper())

		_card_slots.clear()
		var xs: Array[float] = [-0.255, -0.085, 0.085, 0.255]
		var cq := QuadMesh.new()
		cq.size = Vector2(0.155, 0.086)
		var iq := QuadMesh.new()
		iq.size = Vector2(0.042, 0.042)
		for i in range(mini(_move_registry.size(), 4)):
			var mv: Dictionary = _move_registry[i]
			var mv_id: String = String(mv["id"])
			var mv_title: String = String(mv["title"])
			var mv_cue: String = String(mv["cue"])
			if mv_id == "melee_chase" and chain_depth >= 2:
				mv_title = "MELEE (Z)"
				mv_cue = "👊 Rebote Z"
			elif mv_id == "fast_super":
				mv_cue = "🔥 Galick/Final" if is_vegeta_atk else "🔥 Kamehameha"

			var slot_r := Node3D.new()
			slot_r.position = Vector3(xs[i], -0.006, 0.0)
			_hud_anchor.add_child(slot_r)

			var bg := MeshInstance3D.new()
			bg.mesh = cq
			var bgm := StandardMaterial3D.new()
			bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bgm.no_depth_test = true
			bgm.render_priority = 122
			bgm.albedo_color = Color(0.02, 0.05, 0.11, 0.86)
			bg.material_override = bgm
			slot_r.add_child(bg)

			var ic := MeshInstance3D.new()
			ic.mesh = iq
			ic.position = Vector3(-0.048, 0.012, 0.002)
			var icm := StandardMaterial3D.new()
			icm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			icm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			icm.no_depth_test = true
			icm.render_priority = 124
			var itex: Texture2D = _get_ui_tex(String(mv.get("icon", "")))
			if itex:
				icm.albedo_texture = itex
			ic.material_override = icm
			slot_r.add_child(ic)

			var lbl := Label3D.new()
			lbl.font_size = 14
			lbl.pixel_size = 0.00115
			lbl.no_depth_test = true
			lbl.render_priority = 125
			lbl.outline_size = 6
			lbl.position = Vector3(0.022, 0.0, 0.003)
			slot_r.add_child(lbl)

			_card_slots.append({ "id": mv_id, "title": mv_title, "cue": mv_cue, "bg_mat": bgm, "ic_mat": icm, "lbl": lbl })

		_timer_fill = MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(1.0, 0.010)
		_timer_fill.mesh = tq
		_timer_fill.position = Vector3(0.0, -0.064, 0.003)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.no_depth_test = true
		tm.render_priority = 125
		tm.albedo_color = Color(1.0, 0.88, 0.22)
		_timer_fill.material_override = tm
		_timer_fill_mat = tm
		_timer_fill.scale = Vector3(0.68, 1.0, 1.0)
		_hud_anchor.add_child(_timer_fill)
		_refresh_decision_hud()
	else:
		_build_defender_status_only_hud()


func _build_defender_status_only_hud() -> void:
	if not _hud_anchor or not is_instance_valid(_hud_anchor):
		var cam: Camera3D = _get_player_camera()
		if not cam or not is_instance_valid(cam):
			return
		_hud_anchor = Node3D.new()
		_hud_anchor.name = "FollowUpVisorHUD"
		_hud_anchor.position = Vector3(0.0, 0.16, -1.06)
		cam.add_child(_hud_anchor)
	else:
		_hud_anchor.position = Vector3(0.0, 0.16, -1.06)

	if not _title_label or not is_instance_valid(_title_label):
		var obi_m := MeshInstance3D.new()
		var oq := QuadMesh.new()
		oq.size = Vector2(0.70, 0.070)
		obi_m.mesh = oq
		obi_m.position = Vector3(0.0, 0.088, -0.002)
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		om.no_depth_test = true
		om.render_priority = 123
		var otex: Texture2D = _get_ui_tex("info_obi.png")
		if otex:
			om.albedo_texture = otex
		om.albedo_color = Color(1.0, 0.48, 0.20, 0.90) if not bool(attacker.get("is_player")) else Color(1.0, 0.85, 0.25, 0.90)
		obi_m.material_override = om
		_hud_anchor.add_child(obi_m)

		_title_label = Label3D.new()
		_title_label.text = "🔥 CARGANDO SÚPER 2.4x" if bool(attacker.get("is_player")) else "⚡ ¡SIGUIENTE SECUENCIA!"
		_title_label.font_size = 21
		_title_label.pixel_size = 0.0012
		_title_label.no_depth_test = true
		_title_label.render_priority = 126
		_title_label.modulate = Color(1.0, 0.92, 0.35)
		_title_label.outline_size = 8
		_title_label.position = Vector3(0.0, 0.088, 0.002)
		_hud_anchor.add_child(_title_label)

	if not _status_label or not is_instance_valid(_status_label):
		_status_label = Label3D.new()
		_status_label.font_size = 22
		_status_label.pixel_size = 0.00122
		_status_label.no_depth_test = true
		_status_label.render_priority = 126
		_status_label.outline_size = 8
		_status_label.position = Vector3(0.0, 0.026, 0.002)
		_hud_anchor.add_child(_status_label)

	if not _def_actions_label or not is_instance_valid(_def_actions_label):
		_def_actions_label = Label3D.new()
		_def_actions_label.font_size = 15
		_def_actions_label.pixel_size = 0.00115
		_def_actions_label.no_depth_test = true
		_def_actions_label.render_priority = 126
		_def_actions_label.modulate = Color(0.88, 0.95, 1.0)
		_def_actions_label.outline_size = 6
		_def_actions_label.position = Vector3(0.0, -0.024, 0.002)
		_hud_anchor.add_child(_def_actions_label)

	if not _timer_fill or not is_instance_valid(_timer_fill):
		_timer_fill = MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(1.0, 0.010)
		_timer_fill.mesh = tq
		_timer_fill.position = Vector3(0.0, -0.058, 0.003)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.no_depth_test = true
		tm.render_priority = 125
		tm.albedo_color = Color(1.0, 0.72, 0.22)
		_timer_fill.material_override = tm
		_timer_fill_mat = tm
		_timer_fill.scale = Vector3(0.68, 1.0, 1.0)
		_timer_fill.visible = is_in_intro_pause()
		_hud_anchor.add_child(_timer_fill)

	_refresh_status_hud_for_defender()


func _refresh_intro_pause_hud() -> void:
	if not _hud_anchor or not is_instance_valid(_hud_anchor):
		return
	var rem_s: float = maxf(_state_timer, 0.0)
	var frac: float = clampf(rem_s / maxf(_intro_pause_total, 0.01), 0.02, 1.0)
	if bool(attacker.get("is_player")):
		if _title_label and is_instance_valid(_title_label):
			if _intro_pause_reason == "hammer_slam_chain":
				_title_label.text = "⏸️ ¡RIVAL ESTAMPADO — SIGUIENTE SECUENCIA! (%.1fs)" % rem_s
			elif chain_depth >= 2:
				_title_label.text = "⏸️ ¡SIGUIENTE SECUENCIA — REBOTE Z x%d! (%.1fs)" % [chain_depth, rem_s]
			else:
				_title_label.text = "⏸️ ¡SIGUIENTE SECUENCIA! (%.1fs)" % rem_s
			_title_label.modulate = Color(1.0, 0.94, 0.45)
		if _subtitle_label and is_instance_valid(_subtitle_label):
			_subtitle_label.text = "ACCIONES DISPONIBLES — ¡PREPÁRATE!"
			_subtitle_label.modulate = Color(0.55, 0.95, 1.0)
		if _timer_fill_mat:
			_timer_fill_mat.albedo_color = Color(1.0, 0.72, 0.22)
		if _timer_fill and is_instance_valid(_timer_fill):
			_timer_fill.visible = true
			_timer_fill.scale = Vector3(frac * 0.68, 1.0, 1.0)
		_refresh_card_slots_visuals()
	else:
		var v_state: int = int(defender.get("vulnerability_state")) if defender.get("vulnerability_state") != null else 0
		if _title_label and is_instance_valid(_title_label):
			if v_state == 3:
				_title_label.text = "⏸️ ¡SIGUIENTE SECUENCIA! — ¡ESTAMPADO! (%.1fs)" % rem_s
			else:
				_title_label.text = "⏸️ ¡SIGUIENTE SECUENCIA! — ¡FUISTE LANZADO! (%.1fs)" % rem_s
			_title_label.modulate = Color(1.0, 0.92, 0.40)
		if _timer_fill_mat:
			_timer_fill_mat.albedo_color = Color(1.0, 0.55, 0.22)
		if _timer_fill and is_instance_valid(_timer_fill):
			_timer_fill.visible = true
			_timer_fill.scale = Vector3(frac * 0.68, 1.0, 1.0)
		_refresh_status_hud_for_defender()


func _refresh_status_hud_for_defender() -> void:
	if not _status_label or not is_instance_valid(_status_label):
		return
	var v_state: int = int(defender.get("vulnerability_state")) if defender.get("vulnerability_state") != null else 0
	if v_state == 3:
		var t_rem: float = float(defender.get("crashed_stamped_timer")) if defender.get("crashed_stamped_timer") != null else 0.0
		_status_label.text = "💥 ESTAMPADO (%.1fs) — SIN DEFENSA" % maxf(t_rem, 0.0)
		_status_label.modulate = Color(1.0, 0.28, 0.18)
		if _def_actions_label and is_instance_valid(_def_actions_label):
			_def_actions_label.text = "No puedes despertar ni bloquear el siguiente ataque"
			_def_actions_label.modulate = Color(1.0, 0.62, 0.55)
	elif v_state == 2:
		_status_label.text = "✅ ¡ESTABILIZADO! — PREPÁRATE A DEFENDER"
		_status_label.modulate = Color(0.28, 1.0, 0.55)
		if _def_actions_label and is_instance_valid(_def_actions_label):
			_def_actions_label.text = "🕹️ Stick Z-Vanish | 💥 Trigger Desvío | 🛡️ Guardia X"
			_def_actions_label.modulate = Color(0.75, 1.0, 0.85)
	elif v_state == 1:
		var diff_lbl: String = String(defender.get("air_brake_difficulty_label")) if defender.get("air_brake_difficulty_label") != null else "NORMAL"
		if diff_lbl.is_empty():
			diff_lbl = "NORMAL"
		_status_label.text = "⚡ ACCIÓN: AGITA AMBOS CONTROLES (%s)" % diff_lbl
		_status_label.modulate = Color(1.0, 0.85, 0.25)
		if _def_actions_label and is_instance_valid(_def_actions_label):
			_def_actions_label.text = "Al estabilizarte: 🕹️ Stick Z-Vanish | 💥 Trigger Desvío | 🛡️ Guardia X"
			_def_actions_label.modulate = Color(0.85, 0.94, 1.0)
	else:
		_status_label.text = ""
		if _def_actions_label and is_instance_valid(_def_actions_label):
			_def_actions_label.text = ""


func _refresh_card_slots_visuals() -> void:
	var cur_ki: float = float(attacker.get("current_ki")) if attacker.get("current_ki") != null else 0.0
	for slot in _card_slots:
		var mid: String = String(slot["id"])
		var cost: float = get_move_ki_cost(mid)
		var afford: bool = cur_ki >= cost
		var lbl: Label3D = slot["lbl"] as Label3D
		var bgm: StandardMaterial3D = slot["bg_mat"] as StandardMaterial3D
		var icm: StandardMaterial3D = slot["ic_mat"] as StandardMaterial3D
		var disp_title: String = "MELEE (Z)" if (mid == "melee_chase" and chain_depth >= 2) else String(slot["title"])
		var disp_cue: String = "👊 Rebote Z" if (mid == "melee_chase" and chain_depth >= 2) else String(slot["cue"])
		if lbl:
			lbl.text = "%s\n%s\n[-%d Ki]" % [disp_title, disp_cue, int(roundf(cost))]
			lbl.modulate = Color(0.95, 0.98, 1.0) if afford else Color(0.45, 0.48, 0.55, 0.65)
		if bgm:
			bgm.albedo_color = Color(0.02, 0.06, 0.14, 0.88) if afford else Color(0.04, 0.04, 0.06, 0.60)
		if icm:
			icm.albedo_color = Color.WHITE if afford else Color(0.45, 0.45, 0.50, 0.50)


func _refresh_decision_hud() -> void:
	if not bool(attacker.get("is_player")):
		_refresh_status_hud_for_defender()
		return
	_refresh_card_slots_visuals()
	if _timer_fill and is_instance_valid(_timer_fill):
		var frac: float = clampf(_decision_remaining / maxf(_decision_total, 0.01), 0.02, 1.0)
		_timer_fill.scale = Vector3(frac * 0.68, 1.0, 1.0)


func _build_hammer_attacker_target() -> void:
	var cam: Camera3D = _get_player_camera()
	if not cam:
		return
	_hammer_target_node = Node3D.new()
	_hammer_target_node.position = Vector3(0.0, -0.18, -0.48)
	cam.add_child(_hammer_target_node)

	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.16
	dm.bottom_radius = 0.16
	dm.height = 0.02
	disc.mesh = dm
	disc.rotation.x = PI * 0.5
	_hammer_ring_mat = StandardMaterial3D.new()
	_hammer_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hammer_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hammer_ring_mat.no_depth_test = true
	_hammer_ring_mat.render_priority = 122
	_hammer_ring_mat.albedo_color = Color(0.95, 0.25, 1.0, 0.72)
	disc.material_override = _hammer_ring_mat
	_hammer_target_node.add_child(disc)

	var lbl := Label3D.new()
	lbl.text = "🔨 ¡APLASTA ABAJO!"
	lbl.font_size = 24
	lbl.pixel_size = 0.0013
	lbl.no_depth_test = true
	lbl.render_priority = 125
	lbl.modulate = Color(1.0, 0.90, 0.30)
	lbl.outline_size = 8
	lbl.position = Vector3(0.0, 0.0, 0.03)
	_hammer_target_node.add_child(lbl)


func _build_barrage_attacker_hud() -> void:
	_build_defender_status_only_hud()
	if _status_label:
		_status_label.text = "💥 ¡LLUVIA RENZOKU! Alterna Gatillos o Palmas"
		_status_label.modulate = Color(0.35, 0.96, 1.0)
	var cam: Camera3D = _get_player_camera()
	if not cam:
		return
	_barrage_rings.clear()
	for sx in [-0.18, 0.18]:
		var r_node := Node3D.new()
		r_node.position = Vector3(sx, -0.06, -0.48)
		cam.add_child(r_node)
		var qm := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.16, 0.16)
		qm.mesh = q
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.no_depth_test = true
		rm.render_priority = 122
		var t_tex: Texture2D = _get_ui_tex("target_fight.png")
		if t_tex:
			rm.albedo_texture = t_tex
		rm.albedo_color = Color(0.30, 0.92, 1.0, 0.90)
		qm.material_override = rm
		r_node.add_child(qm)
		_barrage_rings.append(r_node)

	if _hud_anchor and is_instance_valid(_hud_anchor):
		_timer_fill = MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(1.0, 0.010)
		_timer_fill.mesh = tq
		_timer_fill.position = Vector3(0.0, -0.05, 0.002)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.no_depth_test = true
		tm.render_priority = 125
		tm.albedo_color = Color(0.35, 0.96, 1.0)
		_timer_fill.material_override = tm
		_timer_fill.scale = Vector3(0.36, 1.0, 1.0)
		_hud_anchor.add_child(_timer_fill)


func _build_defense_box_hud(icon_txt: String, col: Color, hint_txt: String) -> void:
	var cam: Camera3D = _get_player_camera()
	if not cam:
		return
	_def_box_node = Node3D.new()
	_def_box_node.position = Vector3(0.0, 0.02, -0.56)
	cam.add_child(_def_box_node)

	var bm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.04)
	bm.mesh = box
	_def_box_mat = StandardMaterial3D.new()
	_def_box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_def_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_def_box_mat.no_depth_test = true
	_def_box_mat.render_priority = 122
	_def_box_mat.albedo_color = Color(col.r, col.g, col.b, 0.34)
	bm.material_override = _def_box_mat
	_def_box_node.add_child(bm)

	_def_ring_mesh = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.088
	tm.outer_radius = 0.106
	_def_ring_mesh.mesh = tm
	_def_ring_mesh.rotation.x = PI * 0.5
	_def_ring_mesh.position = Vector3(0.0, 0.0, 0.028)
	_def_ring_mat = StandardMaterial3D.new()
	_def_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_def_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_def_ring_mat.no_depth_test = true
	_def_ring_mat.render_priority = 124
	_def_ring_mat.albedo_color = col
	_def_ring_mesh.material_override = _def_ring_mat
	_def_box_node.add_child(_def_ring_mesh)

	_def_icon_label = Label3D.new()
	_def_icon_label.text = icon_txt
	_def_icon_label.font_size = 40
	_def_icon_label.pixel_size = 0.0022
	_def_icon_label.no_depth_test = true
	_def_icon_label.render_priority = 126
	_def_icon_label.outline_size = 10
	_def_icon_label.position = Vector3(0.0, 0.0, 0.04)
	_def_box_node.add_child(_def_icon_label)

	_def_hint_label = Label3D.new()
	_def_hint_label.text = hint_txt
	_def_hint_label.font_size = 20
	_def_hint_label.pixel_size = 0.0012
	_def_hint_label.no_depth_test = true
	_def_hint_label.render_priority = 126
	_def_hint_label.outline_size = 8
	_def_hint_label.modulate = Color(1.0, 0.92, 0.30)
	_def_hint_label.position = Vector3(0.0, -0.15, 0.03)
	_def_box_node.add_child(_def_hint_label)


func _clear_minigame_meshes() -> void:
	if _hammer_target_node and is_instance_valid(_hammer_target_node):
		_hammer_target_node.queue_free()
	_hammer_target_node = null
	for rn in _barrage_rings:
		if rn and is_instance_valid(rn):
			rn.queue_free()
	_barrage_rings.clear()
	if _def_box_node and is_instance_valid(_def_box_node):
		_def_box_node.queue_free()
	_def_box_node = null


func _clear_action_hud() -> void:
	_clear_minigame_meshes()
	if _hud_anchor and is_instance_valid(_hud_anchor):
		_hud_anchor.queue_free()
	_hud_anchor = null
	_title_label = null
	_subtitle_label = null
	_status_label = null
	_def_actions_label = null
	_timer_fill = null
	_timer_fill_mat = null
	_card_slots.clear()


func _finish_sequence(reason: String, restore_distance: bool) -> void:
	if not is_active and state == FollowUpState.COMPLETED:
		return
	is_active = false
	state = FollowUpState.COMPLETED
	Engine.time_scale = 1.0
	_clear_action_hud()

	if attacker and is_instance_valid(attacker):
		attacker.set("is_in_followup_bullet_time", false)
		attacker.set("active_followup_controller", null)
		attacker.set("opponent_airborne_target", null)
		if restore_distance:
			attacker.set("combat_chain_depth", 0)
			if defender and is_instance_valid(defender) and attacker.has_method("_separate_fighters_to_canonical_distance"):
				var my_p: Vector3 = attacker.get_spatial_root().global_position if attacker.has_method("get_spatial_root") else attacker.global_position
				var def_p: Vector3 = defender.get_spatial_root().global_position if defender.has_method("get_spatial_root") else defender.global_position
				if my_p.distance_to(def_p) < 6.5:
					attacker._separate_fighters_to_canonical_distance(defender, 8.0)

	emit_signal("sequence_finished", last_action_chosen if last_action_chosen != "none" else reason, chain_depth)
	queue_free()


func _exit_tree() -> void:
	if Engine.time_scale < 0.99:
		Engine.time_scale = 1.0
	_clear_action_hud()
	if attacker and is_instance_valid(attacker) and attacker.get("active_followup_controller") == self:
		attacker.set("active_followup_controller", null)
		attacker.set("is_in_followup_bullet_time", false)
