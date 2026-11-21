class_name MeleeLoreEventController
extends Node3D

## MeleeLoreEventController (Godot 4.3+ / 4.8 VR)
## Orquesta los 6 Eventos Dinámicos del Lore de Dragon Ball Z dentro de la fase Melee:
## 1. FIST_FLURRY_CLASH (Ataque simultáneo de ráfaga con tira y afloja)
## 2. METEOR_SMASH (Lanzar al aire, Z-Vanish arriba y estrellar en cráter -> listo para Super)
## 3. Z_VANISH_WAR (Cadena de teletransportes tácticos quemando Ki)
## 4. GUARD_PRESSURE_BREAK (Presión contra Guardia Cruzada / Onda de defensa)
## 5. EXPLOSIVE_WAVE (Kiai explosivo de emergencia para cortar combos a costa de Ki)
## 6. SONIC_Z_BURST (Persecución aérea en 3 saltos tras múltiples golpes sónicos)

enum LoreEventType {
	NONE = 0,
	FIST_FLURRY_CLASH = 1,
	METEOR_SMASH = 2,
	Z_VANISH_WAR = 3,
	GUARD_PRESSURE_BREAK = 4,
	EXPLOSIVE_WAVE = 5,
	SONIC_Z_BURST = 6
}

signal lore_event_started(event_type: int, title: String)
signal lore_event_finished(event_type: int, outcome: Dictionary)

var active_event_type: int = LoreEventType.NONE
var is_event_active: bool = false
var _dome: Node3D = null
var _attacker: Node3D = null
var _defender: Node3D = null
var _player_char: Node3D = null
var _enemy_char: Node3D = null

var _event_timer: float = 0.0
var _substep: int = 0
var _tug_progress: float = 0.5
var _vanish_hop: int = 0
var _vanish_defender_is_player: bool = true
var _burst_hits: int = 0
var _burst_hop_timer: float = 0.0
var _clash_punch_cd_l: float = 0.0
var _clash_punch_cd_r: float = 0.0
var _stick_debounce: float = 0.0
var _ai_tick_accum: float = 0.0
var _crater_target_pos: Vector3 = Vector3.ZERO

# Nodos visuales reutilizables (cero alocaciones por frame)
var _hud_root: Node3D = null
var _title_label: Label3D = null
var _prompt_label: Label3D = null
var _tug_bar_root: Node3D = null
var _tug_player_fill: MeshInstance3D = null
var _tug_enemy_fill: MeshInstance3D = null
var _tug_divider: MeshInstance3D = null
var _event_orb: MeshInstance3D = null
var _event_orb_mat: StandardMaterial3D = null
var _aura_sphere: MeshInstance3D = null
var _aura_mat: StandardMaterial3D = null


## Evalúa de forma pura y determinística qué evento Lore disparar según el contexto de combate
static func evaluate_lore_event_trigger(ctx: Dictionary) -> int:
	var src: String = String(ctx.get("trigger_source", ""))
	var last_ev: int = int(ctx.get("last_event_type", LoreEventType.NONE))
	var atk_ki: float = float(ctx.get("atk_ki", 0.0))
	var def_ki: float = float(ctx.get("def_ki", 0.0))
	var bp_ratio: float = float(ctx.get("bp_ratio", 1.0))
	var sonic_hits: int = int(ctx.get("sonic_hits", 0))
	var hits_landed: int = int(ctx.get("hits_landed", 0))
	var consec_guard_x: int = int(ctx.get("consecutive_guard_x", 0))
	var consec_hits_taken: int = int(ctx.get("consecutive_hits_taken", 0))
	var has_v3_up: bool = bool(ctx.get("has_v3_up", false))
	var is_furia_or_trans: bool = bool(ctx.get("is_furia_or_trans", false))

	if src == "explosive_wave_input":
		if def_ki >= 22.0 and consec_hits_taken >= 2:
			return LoreEventType.EXPLOSIVE_WAVE
		return LoreEventType.NONE

	if src == "z_vanish":
		if atk_ki >= 18.0 and bp_ratio >= 0.70:
			return LoreEventType.Z_VANISH_WAR
		return LoreEventType.NONE

	if src == "fist_clash":
		if last_ev != LoreEventType.FIST_FLURRY_CLASH and atk_ki >= 20.0 and def_ki >= 20.0 and bp_ratio >= 0.65 and bp_ratio <= 1.50:
			return LoreEventType.FIST_FLURRY_CLASH
		return LoreEventType.NONE

	if src == "guard_abuse":
		if last_ev != LoreEventType.GUARD_PRESSURE_BREAK and (consec_guard_x >= 2 or def_ki <= 22.0):
			return LoreEventType.GUARD_PRESSURE_BREAK
		return LoreEventType.NONE

	if src == "combo_end":
		if last_ev != LoreEventType.METEOR_SMASH and (has_v3_up or sonic_hits >= 1) and hits_landed >= 2 and atk_ki >= 12.0:
			return LoreEventType.METEOR_SMASH
		return LoreEventType.NONE

	if src == "combo_mid":
		if last_ev != LoreEventType.SONIC_Z_BURST and hits_landed >= 3 and (sonic_hits >= 2 or is_furia_or_trans) and atk_ki >= 15.0:
			return LoreEventType.SONIC_Z_BURST
		return LoreEventType.NONE

	return LoreEventType.NONE


## Actualización pura de la barra de tira y afloja para Choque Frenético de Puños
static func compute_fist_clash_step(current_progress: float, player_punches: int, bp_ratio: float, delta: float) -> float:
	var bp_scale: float = clampf(sqrt(maxf(bp_ratio, 0.1)), 0.70, 1.45)
	var player_push: float = float(maxi(player_punches, 0)) * 0.085 * bp_scale
	var enemy_pull: float = (0.28 / bp_scale) * maxf(delta, 0.0)
	return clampf(current_progress + player_push - enemy_pull, 0.0, 1.0)


## Calcula posiciones 3D seguras dentro de la arena para Meteor Smash (sin rotar XRCamera3D)
static func compute_meteor_smash_positions(crater_pos: Vector3, duel_axis: Vector3, ground_y: float) -> Dictionary:
	var axis := Vector3(duel_axis.x, 0.0, duel_axis.z)
	axis = axis.normalized() if axis.length_squared() > 0.001 else Vector3.FORWARD
	var cx: float = clampf(crater_pos.x, -74.0, 74.0)
	var cz: float = clampf(crater_pos.z, -74.0, 74.0)
	var px: float = clampf(cx - axis.x * 11.0, -74.0, 74.0)
	var pz: float = clampf(cz - axis.z * 11.0, -74.0, 74.0)
	return {
		"air_victim_pos": Vector3(cx, ground_y + 15.5, cz),
		"above_attacker_pos": Vector3(cx - axis.x * 0.85, ground_y + 17.0, cz - axis.z * 0.85),
		"crater_ground_pos": Vector3(cx, ground_y, cz),
		"post_slam_attacker_pos": Vector3(px, ground_y + 7.5, pz)
	}


func start_event(event_type: int, p_dome: Node3D, p_attacker: Node3D, p_defender: Node3D) -> bool:
	if is_event_active or event_type == LoreEventType.NONE:
		return false
	if not p_attacker or not p_defender or not is_instance_valid(p_attacker) or not is_instance_valid(p_defender):
		return false

	_dome = p_dome
	_attacker = p_attacker
	_defender = p_defender
	_player_char = p_attacker if bool(p_attacker.get("is_player")) else p_defender
	_enemy_char = p_defender if bool(p_attacker.get("is_player")) else p_attacker
	active_event_type = event_type
	is_event_active = true
	_substep = 0
	_tug_progress = 0.50
	_vanish_hop = 0
	_burst_hits = 0
	_clash_punch_cd_l = 0.0
	_clash_punch_cd_r = 0.0
	_stick_debounce = 0.0
	_ai_tick_accum = 0.0

	_ensure_visuals()
	_hide_all_visuals()

	var title_txt: String = ""
	var axis: Vector3 = _dome.get("_duel_axis") if (_dome and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var vic_origin: Vector3 = _defender.global_position
	var gy: float = 0.15
	if _defender.has_method("get_ground_elevation"):
		gy = float(_defender.get_ground_elevation(vic_origin))
	_crater_target_pos = Vector3(vic_origin.x, gy, vic_origin.z)

	match event_type:
		LoreEventType.FIST_FLURRY_CLASH:
			_event_timer = 3.0
			title_txt = "⚡ ¡CHOQUE FRENÉTICO DE PUÑOS! ⚡"
			if _hud_root:
				_hud_root.visible = true
			if _tug_bar_root:
				_tug_bar_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(1.0, 0.90, 0.25)
			if _prompt_label:
				_prompt_label.text = "¡Lanza puñetazos IZQ-DER lo más rápido posible! (Drena Ki)"
			_update_tug_bar_visual()
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation(Vector3(clampf(vic_origin.x, -55.0, 55.0), gy + 5.5, clampf(vic_origin.z, -55.0, 55.0)))

		LoreEventType.METEOR_SMASH:
			_event_timer = 0.90
			_substep = 0
			title_txt = "🌌 ¡CAÍDA DEL METEORO!"
			var m_pos: Dictionary = compute_meteor_smash_positions(_crater_target_pos, axis, gy)
			if not bool(_defender.get("is_player")):
				_defender.global_position = m_pos["air_victim_pos"]
			elif _dome and _dome.has_method("_apply_melee_arena_surge"):
				_dome._apply_melee_arena_surge(Vector3.UP * 8.0, 0.25)
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.95, 0.35, 1.0)
			if _prompt_label:
				if bool(_attacker.get("is_player")):
					_prompt_label.text = "¡PERSECUCIÓN AÉREA! Puño arriba o Stick ↑ (12 Ki)"
				else:
					_prompt_label.text = "⚠️ ¡EL RIVAL TE LANZÓ AL CIELO! Prepárate para frenar..."

		LoreEventType.Z_VANISH_WAR:
			_event_timer = 0.65
			_vanish_hop = 1
			_vanish_defender_is_player = not bool(_attacker.get("is_player"))
			title_txt = "💨 ¡GUERRA DE Z-VANISH! (1/3)"
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.30, 0.95, 1.0)
			if _prompt_label:
				_prompt_label.text = "Stick (12 Ki) = ¡Contra-Blink! | Guardia X = Plantarse"
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation()

		LoreEventType.GUARD_PRESSURE_BREAK:
			_event_timer = 1.80
			title_txt = "💥 ¡DESGARRE DE GUARDIA!"
			if _hud_root:
				_hud_root.visible = true
			if _event_orb:
				_event_orb.visible = true
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(1.0, 0.45, 0.12, 0.88)
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(1.0, 0.50, 0.15)
			if _prompt_label:
				if bool(_attacker.get("is_player")):
					_prompt_label.text = "¡Golpea fuerte la grieta para QUEBRAR su Guardia!"
				else:
					_prompt_label.text = "¡TU GUARDIA SE AGRIETA! Abre ambos brazos + Grips (15 Ki)"

		LoreEventType.EXPLOSIVE_WAVE:
			_event_timer = 0.55
			title_txt = "🛡️ ¡ONDA EXPLOSIVA (KIAI)!"
			var cfg_ew: KiEconomyConfig = KiEconomyConfig.get_default()
			var ew_cost: float = float(cfg_ew.melee_explosive_wave_cost) if cfg_ew.get("melee_explosive_wave_cost") != null else 22.0
			_modify_ki(_defender, -ew_cost)
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.25, 0.92, 1.0)
			if _prompt_label:
				_prompt_label.text = "¡Explosión de Ki liberada! (-%d Ki)" % int(ew_cost)
			if _aura_sphere and is_instance_valid(_aura_sphere):
				_aura_sphere.visible = true
				_aura_sphere.scale = Vector3.ONE * 0.5
				var tw := create_tween().set_parallel(true)
				tw.tween_property(_aura_sphere, "scale", Vector3.ONE * 8.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				if _aura_mat:
					_aura_mat.albedo_color = Color(0.25, 0.92, 1.0, 0.72)
					tw.tween_property(_aura_mat, "albedo_color:a", 0.0, 0.48)
			if _attacker and _attacker.has_method("take_hit"):
				_attacker.take_hit(160.0, Vector3.ZERO, false)
			if get_tree():
				KiSmokeFX.spawn_smoke(get_tree(), _defender.global_position + Vector3(0.0, 0.8, 0.0), 1.4)

		LoreEventType.SONIC_Z_BURST:
			_event_timer = 0.75
			_burst_hop_timer = 0.75
			_substep = 0
			title_txt = "🔥 ¡INTERCAMBIO SÓNICO Z-BURST!"
			if _hud_root:
				_hud_root.visible = true
			if _event_orb:
				_event_orb.visible = true
				_event_orb.scale = Vector3.ONE * 1.25
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(1.0, 0.88, 0.18, 0.92)
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(1.0, 0.88, 0.20)
			if _prompt_label:
				if bool(_attacker.get("is_player")):
					_prompt_label.text = "⚡ ¡BONO SÓNICO! (1/3)\n👊 ¡GOLPEA EL ORBE = +240 DAÑO y +140 BP!\n(Stick ↓ = Guardar Ki)"
				else:
					_prompt_label.text = "⚠️ ¡EL RIVAL TE PERSIGUE A VELOCIDAD SÓNICA!"
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation(Vector3(clampf(vic_origin.x + 10.0, -60.0, 60.0), gy + 9.0, clampf(vic_origin.z - 8.0, -60.0, 60.0)))

	emit_signal("lore_event_started", event_type, title_txt)
	return true


func process_event(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3) -> void:
	if not is_event_active:
		return

	_clash_punch_cd_l = maxf(_clash_punch_cd_l - delta, 0.0)
	_clash_punch_cd_r = maxf(_clash_punch_cd_r - delta, 0.0)
	_stick_debounce = maxf(_stick_debounce - delta, 0.0)
	_event_timer -= delta

	var l_closed: bool = _is_fist_closed_ctrl(l_ctrl)
	var r_closed: bool = _is_fist_closed_ctrl(r_ctrl)
	var l_grip: bool = l_ctrl != null and (l_ctrl.get_float("grip") > 0.50 or l_ctrl.is_button_pressed("grip_click"))
	var r_grip: bool = r_ctrl != null and (r_ctrl.get_float("grip") > 0.50 or r_ctrl.is_button_pressed("grip_click"))
	var stick_l: Vector2 = l_ctrl.get_vector2("primary") if l_ctrl else Vector2.ZERO
	var stick_r: Vector2 = r_ctrl.get_vector2("primary") if r_ctrl else Vector2.ZERO

	match active_event_type:
		LoreEventType.FIST_FLURRY_CLASH:
			_process_fist_clash(delta, l_vel, r_vel, l_closed, r_closed)
		LoreEventType.METEOR_SMASH:
			_process_meteor_smash(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed, stick_l, stick_r)
		LoreEventType.Z_VANISH_WAR:
			_process_z_vanish_war(delta, l_closed, r_closed, stick_l, stick_r)
		LoreEventType.GUARD_PRESSURE_BREAK:
			_process_guard_break(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_grip, r_grip)
		LoreEventType.EXPLOSIVE_WAVE:
			if _event_timer <= 0.0:
				_finish_event({ "action": "separate", "distance": 10.0 })
		LoreEventType.SONIC_Z_BURST:
			_process_sonic_z_burst(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed, stick_r)


func inject_virtual_clash_punch() -> void:
	if not is_event_active or active_event_type != LoreEventType.FIST_FLURRY_CLASH:
		return
	var bp_r: float = _get_player_bp_ratio()
	_tug_progress = compute_fist_clash_step(_tug_progress, 1, bp_r, 0.0)
	_update_tug_bar_visual()


func _process_fist_clash(delta: float, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool) -> void:
	# Ambos luchadores queman 6 Ki/s durante el choque frenético
	_modify_ki(_player_char, -6.0 * delta)
	_modify_ki(_enemy_char, -6.0 * delta)

	var p_ki: float = float(_player_char.get("current_ki")) if (_player_char and _player_char.get("current_ki") != null) else 0.0
	var e_ki: float = float(_enemy_char.get("current_ki")) if (_enemy_char and _enemy_char.get("current_ki") != null) else 0.0

	var p_punches: int = 0
	if _clash_punch_cd_l <= 0.0 and (l_closed or l_vel.length() >= 1.9) and l_vel.length() >= 1.40:
		_clash_punch_cd_l = 0.11
		p_punches += 1
		if _dome and _dome.has_method("_spawn_hit_spark") and _event_orb:
			_dome._spawn_hit_spark(_event_orb.global_position)
	if _clash_punch_cd_r <= 0.0 and (r_closed or r_vel.length() >= 1.9) and r_vel.length() >= 1.40:
		_clash_punch_cd_r = 0.11
		p_punches += 1
		if _dome and _dome.has_method("_spawn_hit_spark") and _event_orb:
			_dome._spawn_hit_spark(_event_orb.global_position)

	if p_punches > 0 and _enemy_char and is_instance_valid(_enemy_char) and _enemy_char.get("procedural_animator"):
		_enemy_char.procedural_animator.trigger_melee_strike(randi() % 4)
		if _dome and _dome.has_method("_pulse_defender_both_hands"):
			_dome._pulse_defender_both_hands(190.0, 0.85, 0.05)

	var bp_r: float = _get_player_bp_ratio()
	_tug_progress = compute_fist_clash_step(_tug_progress, p_punches, bp_r, delta)
	_update_tug_bar_visual()

	if p_ki <= 0.0:
		_resolve_fist_clash_winner(_enemy_char, _player_char, 1.0 - _tug_progress)
	elif e_ki <= 0.0 or _tug_progress >= 0.96:
		_resolve_fist_clash_winner(_player_char, _enemy_char, _tug_progress)
	elif _tug_progress <= 0.04:
		_resolve_fist_clash_winner(_enemy_char, _player_char, 1.0 - _tug_progress)
	elif _event_timer <= 0.0:
		if _tug_progress >= 0.50:
			_resolve_fist_clash_winner(_player_char, _enemy_char, _tug_progress)
		else:
			_resolve_fist_clash_winner(_enemy_char, _player_char, 1.0 - _tug_progress)


func _resolve_fist_clash_winner(win_node: Node3D, lose_node: Node3D, win_prog: float) -> void:
	var margin: float = clampf((win_prog - 0.50) * 2.0, 0.0, 1.0)
	var dmg: float = lerpf(650.0, 950.0, margin)
	if lose_node and is_instance_valid(lose_node) and lose_node.has_method("take_hit"):
		lose_node.take_hit(dmg, Vector3.ZERO, false)
	if win_node and is_instance_valid(win_node):
		_modify_ki(win_node, 10.0)
		if win_node.has_method("increase_np"):
			win_node.increase_np(450.0)
		if win_node.has_method("_log_combat_event"):
			win_node._log_combat_event("⚡ ¡GANÓ EL CHOQUE FRENÉTICO DE PUÑOS! (%.0f BP, +10 Ki)" % dmg, "success")
	_finish_event({
		"action": "winner_offense",
		"winner": win_node,
		"loser": lose_node,
		"bonus_hits": 2
	})


func _process_meteor_smash(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var cfg_m: KiEconomyConfig = KiEconomyConfig.get_default()
	var chase_cost: float = float(cfg_m.melee_meteor_chase_cost) if cfg_m.get("melee_meteor_chase_cost") != null else 12.0
	var axis: Vector3 = _dome.get("_duel_axis") if (_dome and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var gy: float = _crater_target_pos.y
	var m_pos: Dictionary = compute_meteor_smash_positions(_crater_target_pos, axis, gy)

	if _substep == 0:
		var chase_triggered: bool = false
		if atk_is_player:
			var cam: Camera3D = _get_cam()
			var high_hands: bool = cam != null and ((l_ctrl and l_ctrl.global_position.y > cam.global_position.y + 0.08) or (r_ctrl and r_ctrl.global_position.y > cam.global_position.y + 0.08))
			var up_vel: bool = (l_vel.y >= 0.85 or r_vel.y >= 0.85) and (l_closed or r_closed)
			if (high_hands or up_vel or stick_l.y >= 0.55 or stick_r.y >= 0.55):
				chase_triggered = true
		else:
			if _event_timer <= 0.45 and float(_attacker.get("current_ki")) >= chase_cost:
				chase_triggered = true

		if chase_triggered and float(_attacker.get("current_ki")) >= chase_cost:
			_modify_ki(_attacker, -chase_cost)
			_substep = 1
			_event_timer = 1.80
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation(m_pos["above_attacker_pos"])
			if _event_orb:
				_event_orb.visible = true
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(0.92, 0.18, 1.0, 0.95)
			if _title_label:
				_title_label.text = "🔨 ¡ESTRÉLLALO AL SUELO!"
			if _prompt_label:
				_prompt_label.text = "¡Baja ambos puños o golpea fuerte hacia abajo!" if atk_is_player else "⚠️ ¡EL RIVAL APARECIÓ SOBRE TI!"
			return

		if _event_timer <= 0.0:
			_finish_event({ "action": "complete_normal" })
	elif _substep == 1:
		var slam_hit: bool = false
		if atk_is_player:
			var down_avg: float = -(l_vel.y + r_vel.y) * 0.5
			var near_orb: bool = _event_orb != null and ((l_ctrl and l_ctrl.global_position.distance_to(_event_orb.global_position) <= 0.34) or (r_ctrl and r_ctrl.global_position.distance_to(_event_orb.global_position) <= 0.34))
			if (down_avg >= 1.10 and (l_closed or r_closed)) or (near_orb and (l_vel.length() >= 1.65 or r_vel.length() >= 1.65)):
				slam_hit = true
		else:
			if _event_timer <= 0.90:
				slam_hit = true

		if slam_hit:
			if _defender and _defender.has_method("take_hit"):
				_defender.take_hit(480.0, Vector3.DOWN, false)
			if _attacker and _attacker.has_method("increase_np"):
				_attacker.increase_np(320.0)
			_finish_event({
				"action": "meteor_crater",
				"winner": _attacker,
				"victim": _defender,
				"crater_pos": _crater_target_pos
			})
			return

		if _event_timer <= 0.0:
			_finish_event({ "action": "complete_normal" })


func _process_z_vanish_war(delta: float, l_closed: bool, r_closed: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	var cfg_zv: KiEconomyConfig = KiEconomyConfig.get_default()
	var hop_cost: float = 12.0
	if cfg_zv.get("melee_meteor_chase_cost") != null:
		hop_cost = float(cfg_zv.melee_meteor_chase_cost)

	var reactor: Node3D = _player_char if _vanish_defender_is_player else _enemy_char
	var chaser: Node3D = _enemy_char if _vanish_defender_is_player else _player_char

	if _vanish_defender_is_player:
		var stick_flick: bool = _stick_debounce <= 0.0 and (stick_l.length() >= 0.65 or stick_r.length() >= 0.65)
		var guard_x: bool = l_closed and r_closed
		var r_ki: float = float(reactor.get("current_ki")) if reactor and reactor.get("current_ki") != null else 0.0
		if stick_flick and r_ki >= hop_cost:
			_stick_debounce = 0.24
			_modify_ki(reactor, -hop_cost)
			_vanish_hop += 1
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation()
			if _vanish_hop > 3:
				_finish_event({ "action": "separate", "distance": 8.0 })
				return
			_vanish_defender_is_player = false
			_event_timer = 0.55
			if _title_label:
				_title_label.text = "💨 ¡GUERRA DE Z-VANISH! (%d/3)" % _vanish_hop
			if _prompt_label:
				_prompt_label.text = "¡PERSEGUISTE A TU RIVAL! A ver si responde..."
			return
		elif guard_x and _event_timer <= 0.35:
			if reactor and reactor.has_method("take_hit"):
				reactor.take_hit(140.0, Vector3.ZERO, false)
			_finish_event({ "action": "separate", "distance": 7.5 })
			return
	else:
		if _event_timer <= 0.25:
			var e_ki: float = float(reactor.get("current_ki")) if reactor and reactor.get("current_ki") != null else 0.0
			if _vanish_hop < 3 and e_ki >= hop_cost + 6.0 and randf() < 0.65:
				_modify_ki(reactor, -hop_cost)
				_vanish_hop += 1
				_vanish_defender_is_player = true
				_event_timer = 0.65
				if _dome and _dome.has_method("perform_z_blink_relocation"):
					_dome.perform_z_blink_relocation()
				if _title_label:
					_title_label.text = "💨 ¡GUERRA DE Z-VANISH! (%d/3)" % _vanish_hop
				if _prompt_label:
					_prompt_label.text = "Stick (12 Ki) = ¡Contra-Blink! | Guardia X = Plantarse"
				return
			else:
				if reactor and reactor.has_method("take_hit"):
					reactor.take_hit(360.0, Vector3.BACK, true)
				if chaser and chaser.has_method("increase_np"):
					chaser.increase_np(240.0)
				_finish_event({ "action": "separate", "distance": 9.5 })
				return

	if _event_timer <= 0.0:
		# Jugador no contra-blinkeó ni bloqueó a tiempo -> Patada a la espalda
		if reactor and reactor.has_method("take_hit"):
			reactor.take_hit(360.0, Vector3.BACK, true)
		_finish_event({ "action": "launch", "victim": reactor })


func _process_guard_break(_delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_grip: bool, r_grip: bool) -> void:
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var orb_pos: Vector3 = _event_orb.global_position if _event_orb else global_position

	if atk_is_player:
		var l_hit: bool = l_ctrl != null and l_ctrl.global_position.distance_to(orb_pos) <= 0.34 and l_vel.length() >= 1.65
		var r_hit: bool = r_ctrl != null and r_ctrl.global_position.distance_to(orb_pos) <= 0.34 and r_vel.length() >= 1.65
		if l_hit or r_hit:
			if _defender and is_instance_valid(_defender):
				_defender.set("is_blocking", false)
				_defender.set("is_guard_broken", true)
				_defender.set("guard_break_timer", 1.6)
				_defender.set("is_staggered", true)
				_defender.set("stagger_timer", 1.2)
				if _defender.has_method("take_hit"):
					_defender.take_hit(320.0, Vector3.ZERO, false)
			_finish_event({ "action": "winner_offense", "winner": _attacker, "loser": _defender, "bonus_hits": 1 })
			return
	else:
		var def_ki: float = float(_defender.get("current_ki")) if (_defender and _defender.get("current_ki") != null) else 0.0
		var hands_spread: bool = l_ctrl != null and r_ctrl != null and l_ctrl.global_position.distance_to(r_ctrl.global_position) >= 0.72 and l_grip and r_grip
		if hands_spread and def_ki >= 15.0:
			_modify_ki(_defender, -15.0)
			if _attacker and _attacker.has_method("take_hit"):
				_attacker.take_hit(140.0, Vector3.ZERO, false)
			_finish_event({ "action": "separate", "distance": 9.0 })
			return

	if _event_timer <= 0.0:
		if not atk_is_player and _defender:
			_defender.set("is_guard_broken", true)
			_defender.set("guard_break_timer", 1.2)
			if _defender.has_method("take_hit"):
				_defender.take_hit(280.0, Vector3.ZERO, false)
			_finish_event({ "action": "launch", "victim": _defender })
		else:
			_finish_event({ "action": "complete_normal" })


func _process_sonic_z_burst(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool, stick_r: Vector2) -> void:
	_burst_hop_timer -= delta
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var orb_pos: Vector3 = _event_orb.global_position if _event_orb else global_position

	if atk_is_player and stick_r.y <= -0.55:
		_finish_event({ "action": "separate", "distance": 8.0 })
		return

	var hit_burst: bool = false
	if atk_is_player:
		var l_ok: bool = _clash_punch_cd_l <= 0.0 and l_closed and l_ctrl and l_ctrl.global_position.distance_to(orb_pos) <= 0.34 and l_vel.length() >= 1.50
		var r_ok: bool = _clash_punch_cd_r <= 0.0 and r_closed and r_ctrl and r_ctrl.global_position.distance_to(orb_pos) <= 0.34 and r_vel.length() >= 1.50
		if l_ok or r_ok:
			_clash_punch_cd_l = 0.25
			_clash_punch_cd_r = 0.25
			hit_burst = true
	else:
		if _burst_hop_timer <= 0.35:
			hit_burst = true

	if hit_burst:
		var atk_ki: float = float(_attacker.get("current_ki")) if (_attacker and _attacker.get("current_ki") != null) else 0.0
		if atk_ki >= 6.0:
			_modify_ki(_attacker, -6.0)
			_burst_hits += 1
			_substep += 1
			if _defender and _defender.has_method("take_hit"):
				_defender.take_hit(240.0, Vector3.ZERO, false)
			if _attacker and _attacker.has_method("increase_np"):
				_attacker.increase_np(140.0)
			if _dome and _dome.has_method("_spawn_parry_shockwave"):
				_dome._spawn_parry_shockwave(orb_pos)
			if _substep >= 3:
				_finish_event({ "action": "launch", "victim": _defender, "hits": _burst_hits })
				return
			_burst_hop_timer = 0.75
			_event_timer = 0.75
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation()
			if _prompt_label and atk_is_player:
				_prompt_label.text = "⚡ ¡BONO SÓNICO! (%d/3)\n👊 ¡GOLPEA EL ORBE = +240 DAÑO y +140 BP!\n(Stick ↓ = Guardar Ki)" % (_substep + 1)
			return

	if _burst_hop_timer <= 0.0 or _event_timer <= 0.0:
		if _burst_hits > 0:
			_finish_event({ "action": "launch", "victim": _defender, "hits": _burst_hits })
		else:
			_finish_event({ "action": "complete_normal" })


func _finish_event(outcome: Dictionary) -> void:
	if not is_event_active:
		return
	var ev: int = active_event_type
	is_event_active = false
	active_event_type = LoreEventType.NONE
	_hide_all_visuals()
	emit_signal("lore_event_finished", ev, outcome)


func _ensure_visuals() -> void:
	if _hud_root and is_instance_valid(_hud_root):
		return
	var cam: Camera3D = _get_cam()
	var parent_node: Node3D = cam if (cam and is_instance_valid(cam)) else self
	var base_pos: Vector3 = Vector3(0.0, 0.0, -1.05) if (parent_node == cam) else Vector3(0.0, 0.35, -0.8)

	_hud_root = Node3D.new()
	_hud_root.name = "MeleeLoreEventHUD"
	_hud_root.position = base_pos
	parent_node.add_child(_hud_root)

	_title_label = Label3D.new()
	_title_label.font_size = 28
	_title_label.pixel_size = 0.0014
	_title_label.outline_size = 10
	_title_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	_title_label.no_depth_test = true
	_title_label.render_priority = 127
	_title_label.position = Vector3(0.0, 0.25, 0.0)
	_hud_root.add_child(_title_label)

	_prompt_label = Label3D.new()
	_prompt_label.font_size = 20
	_prompt_label.pixel_size = 0.00125
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	_prompt_label.no_depth_test = true
	_prompt_label.render_priority = 127
	_prompt_label.position = Vector3(0.0, 0.16, 0.0)
	_hud_root.add_child(_prompt_label)

	_tug_bar_root = Node3D.new()
	_tug_bar_root.name = "LoreTugBar"
	_tug_bar_root.position = Vector3(0.0, 0.08, 0.0)
	_hud_root.add_child(_tug_bar_root)

	var bg_m := MeshInstance3D.new()
	var bg_b := BoxMesh.new()
	bg_b.size = Vector3(0.56, 0.044, 0.008)
	bg_m.mesh = bg_b
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.albedo_color = Color(0.04, 0.06, 0.10, 0.85)
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 126
	bg_m.material_override = bg_mat
	_tug_bar_root.add_child(bg_m)

	_tug_player_fill = MeshInstance3D.new()
	var pf_b := BoxMesh.new()
	pf_b.size = Vector3(1.0, 0.032, 0.010)
	_tug_player_fill.mesh = pf_b
	var pf_mat := StandardMaterial3D.new()
	pf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pf_mat.albedo_color = Color(0.18, 0.85, 1.0)
	pf_mat.no_depth_test = true
	pf_mat.render_priority = 127
	_tug_player_fill.material_override = pf_mat
	_tug_bar_root.add_child(_tug_player_fill)

	_tug_enemy_fill = MeshInstance3D.new()
	var ef_b := BoxMesh.new()
	ef_b.size = Vector3(1.0, 0.032, 0.010)
	_tug_enemy_fill.mesh = ef_b
	var ef_mat := StandardMaterial3D.new()
	ef_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ef_mat.albedo_color = Color(1.0, 0.25, 0.22)
	ef_mat.no_depth_test = true
	ef_mat.render_priority = 127
	_tug_enemy_fill.material_override = ef_mat
	_tug_bar_root.add_child(_tug_enemy_fill)

	_tug_divider = MeshInstance3D.new()
	var div_s := SphereMesh.new()
	div_s.radius = 0.026
	div_s.height = 0.052
	_tug_divider.mesh = div_s
	var div_mat := StandardMaterial3D.new()
	div_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	div_mat.albedo_color = Color(1.0, 0.95, 0.30)
	div_mat.no_depth_test = true
	div_mat.render_priority = 127
	_tug_divider.material_override = div_mat
	_tug_bar_root.add_child(_tug_divider)

	_event_orb = MeshInstance3D.new()
	var orb_s := SphereMesh.new()
	orb_s.radius = 0.13
	orb_s.height = 0.26
	orb_s.radial_segments = 16
	orb_s.rings = 8
	_event_orb.mesh = orb_s
	_event_orb_mat = StandardMaterial3D.new()
	_event_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_event_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_event_orb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_event_orb_mat.no_depth_test = true
	_event_orb_mat.render_priority = 125
	_event_orb.material_override = _event_orb_mat
	_event_orb.position = Vector3(0.0, -0.10, -0.52) if (parent_node == cam) else Vector3(0.0, 0.0, -0.52)
	parent_node.add_child(_event_orb)

	_aura_sphere = MeshInstance3D.new()
	var aura_s := SphereMesh.new()
	aura_s.radius = 0.40
	aura_s.height = 0.80
	_aura_sphere.mesh = aura_s
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_mat.albedo_color = Color(0.25, 0.92, 1.0, 0.65)
	_aura_sphere.material_override = _aura_mat
	add_child(_aura_sphere)


func _hide_all_visuals() -> void:
	if _hud_root and is_instance_valid(_hud_root):
		_hud_root.visible = false
	if _tug_bar_root and is_instance_valid(_tug_bar_root):
		_tug_bar_root.visible = false
	if _event_orb and is_instance_valid(_event_orb):
		_event_orb.visible = false
	if _aura_sphere and is_instance_valid(_aura_sphere):
		_aura_sphere.visible = false


func _update_tug_bar_visual() -> void:
	if not _tug_player_fill or not _tug_enemy_fill or not _tug_divider:
		return
	var total_w: float = 0.52
	var pw: float = clampf(_tug_progress, 0.04, 0.96) * total_w
	var ew: float = total_w - pw
	_tug_player_fill.scale = Vector3(pw, 1.0, 1.0)
	_tug_player_fill.position = Vector3(-total_w * 0.5 + pw * 0.5, 0.0, 0.002)
	_tug_enemy_fill.scale = Vector3(ew, 1.0, 1.0)
	_tug_enemy_fill.position = Vector3(total_w * 0.5 - ew * 0.5, 0.0, 0.002)
	_tug_divider.position = Vector3(-total_w * 0.5 + pw, 0.0, 0.005)


func _get_cam() -> Camera3D:
	if _dome and is_instance_valid(_dome) and _dome.has_method("_get_player_camera"):
		return _dome._get_player_camera()
	return get_viewport().get_camera_3d() if get_viewport() else null


func _get_player_bp_ratio() -> float:
	var p_bp: float = float(_player_char.get("current_np")) if (_player_char and _player_char.get("current_np") != null) else 10000.0
	var e_bp: float = float(_enemy_char.get("current_np")) if (_enemy_char and _enemy_char.get("current_np") != null) else 10000.0
	return maxf(p_bp, 100.0) / maxf(e_bp, 100.0)


func _is_fist_closed_ctrl(c: XRController3D) -> bool:
	if not c:
		return false
	return (c.get_float("trigger") > 0.50 and c.get_float("grip") > 0.50) or (c.is_button_pressed("trigger_click") and c.is_button_pressed("grip_click"))


func _modify_ki(fighter: Node3D, delta_ki: float) -> void:
	if _dome and is_instance_valid(_dome) and _dome.has_method("_modify_fighter_ki"):
		_dome._modify_fighter_ki(fighter, delta_ki)
	elif fighter and is_instance_valid(fighter):
		var cur: float = float(fighter.get("current_ki")) if fighter.get("current_ki") != null else 0.0
		fighter.set("current_ki", clampf(cur + delta_ki, 0.0, 100.0))


func _exit_tree() -> void:
	if _hud_root and is_instance_valid(_hud_root):
		_hud_root.queue_free()
		_hud_root = null
	if _event_orb and is_instance_valid(_event_orb):
		_event_orb.queue_free()
		_event_orb = null
	if _aura_sphere and is_instance_valid(_aura_sphere):
		_aura_sphere.queue_free()
		_aura_sphere = null
