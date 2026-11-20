class_name DramaticMiniSceneController
extends Node3D

## DramaticMiniSceneController (Godot 4.8 VR - 90 FPS)
## Orquesta mini-escenas dramáticas aleatorias, contextuales y no repetitivas para ambos luchadores.
## Cuando se dispara para el jugador, pausa el mundo (Engine.time_scale = 0.04) sin mover XRCamera3D
## y presenta un minijuego táctil 3D en VR; si se dispara para la IA, el jugador observa su despertar.

signal miniscene_started(fighter: Node3D, event_data: DramaticMiniEventData)
signal miniscene_finished(fighter: Node3D, event_data: DramaticMiniEventData, succeeded: bool)

const EVENT_PATHS: Array[String] = [
	"res://resources/dramatic_events/sobrecarga_ki.tres",
	"res://resources/dramatic_events/instinto_defensivo.tres",
	"res://resources/dramatic_events/ruptura_limites.tres",
	"res://resources/dramatic_events/goku_corazon_calma.tres",
	"res://resources/dramatic_events/goku_kaioken_pulso.tres",
	"res://resources/dramatic_events/vegeta_orgullo_saiyan.tres",
	"res://resources/dramatic_events/vegeta_lluvia_principe.tres"
]

enum MiniState { IDLE, PLAYER_ACTIVE, AI_WATCHING, RESULT_HOLD }

var director: Node = null
var _events_catalog: Array[DramaticMiniEventData] = []
var _used_player_events: Array[String] = []
var _used_ai_events: Array[String] = []

var _state: MiniState = MiniState.IDLE
var _active_event: DramaticMiniEventData = null
var _active_fighter: Node3D = null
var _active_opponent: Node3D = null

var _match_elapsed: float = 0.0
var _global_cooldown: float = 16.0
var _eval_timer: float = 2.5
var _events_triggered_total: int = 0
var _player_events_count: int = 0
var _ai_events_count: int = 0
var _prefer_ai_next: bool = false
var _recent_melee_timer: float = 0.0

# Estado interno del minijuego VR activo (cero alocaciones por frame)
var _mini_time_left: float = 0.0
var _mini_elapsed: float = 0.0
var _result_hold_timer: float = 0.0
var _progress_count: int = 0
var _progress_float: float = 0.0
var _action_debounce: float = 0.0
var _prev_l_pos: Vector3 = Vector3.ZERO
var _prev_r_pos: Vector3 = Vector3.ZERO
var _prev_trig_l: bool = false
var _prev_trig_r: bool = false
var _was_in_pulse_window: bool = false
var _last_pulse_cycle_hit: int = -1

# Nodos visuales reutilizables para minijuegos VR (creados bajo la vista del jugador o IA)
var _vr_stage_root: Node3D = null
var _prop_nodes: Array[MeshInstance3D] = []
var _ai_ring_mesh: MeshInstance3D = null
var _hud_title_lbl: Label3D = null
var _hud_progress_lbl: Label3D = null

# Cachés de nodos VR
var _cached_cam: Camera3D = null
var _cached_l_ctrl: XRController3D = null
var _cached_r_ctrl: XRController3D = null


func _ready() -> void:
	_load_events_catalog()
	_build_visual_props()


func _exit_tree() -> void:
	_cleanup_stage_props()


func _load_events_catalog() -> void:
	_events_catalog.clear()
	for path in EVENT_PATHS:
		if ResourceLoader.exists(path):
			var ev: Resource = load(path)
			if ev is DramaticMiniEventData:
				_events_catalog.append(ev as DramaticMiniEventData)


func _build_visual_props() -> void:
	_vr_stage_root = Node3D.new()
	_vr_stage_root.name = "MiniSceneVRStage"
	_vr_stage_root.visible = false
	add_child(_vr_stage_root)

	_hud_title_lbl = Label3D.new()
	_hud_title_lbl.font_size = 24
	_hud_title_lbl.pixel_size = 0.0014
	_hud_title_lbl.no_depth_test = true
	_hud_title_lbl.render_priority = 122
	_hud_title_lbl.outline_size = 10
	_hud_title_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_hud_title_lbl.position = Vector3(0.0, 0.14, -1.05)
	_vr_stage_root.add_child(_hud_title_lbl)

	_hud_progress_lbl = Label3D.new()
	_hud_progress_lbl.font_size = 22
	_hud_progress_lbl.pixel_size = 0.0013
	_hud_progress_lbl.no_depth_test = true
	_hud_progress_lbl.render_priority = 122
	_hud_progress_lbl.outline_size = 8
	_hud_progress_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_hud_progress_lbl.position = Vector3(0.0, -0.22, -1.05)
	_vr_stage_root.add_child(_hud_progress_lbl)

	for i in range(3):
		var m_inst := MeshInstance3D.new()
		m_inst.name = "MiniProp_%d" % i
		var sph := SphereMesh.new()
		sph.radius = 0.085
		sph.height = 0.17
		sph.radial_segments = 14
		sph.rings = 8
		m_inst.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 118
		mat.albedo_color = Color(0.2, 0.9, 1.0, 0.88)
		m_inst.material_override = mat
		m_inst.visible = false
		_vr_stage_root.add_child(m_inst)
		_prop_nodes.append(m_inst)

	_ai_ring_mesh = MeshInstance3D.new()
	_ai_ring_mesh.name = "AIMiniSceneRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.85
	torus.rings = 24
	torus.ring_segments = 8
	_ai_ring_mesh.mesh = torus
	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.albedo_color = Color(1.0, 0.82, 0.2, 0.85)
	_ai_ring_mesh.material_override = r_mat
	_ai_ring_mesh.visible = false
	add_child(_ai_ring_mesh)


func _cleanup_stage_props() -> void:
	if _vr_stage_root and is_instance_valid(_vr_stage_root):
		_vr_stage_root.visible = false
	for m in _prop_nodes:
		if m and is_instance_valid(m):
			m.visible = false
	if _ai_ring_mesh and is_instance_valid(_ai_ring_mesh):
		_ai_ring_mesh.visible = false


func reset_match_state() -> void:
	_used_player_events.clear()
	_used_ai_events.clear()
	_state = MiniState.IDLE
	_active_event = null
	_active_fighter = null
	_active_opponent = null
	_match_elapsed = 0.0
	_global_cooldown = 16.0
	_eval_timer = 2.5
	_events_triggered_total = 0
	_player_events_count = 0
	_ai_events_count = 0
	_prefer_ai_next = false
	_recent_melee_timer = 0.0
	_cleanup_stage_props()


func notify_melee_completed() -> void:
	_recent_melee_timer = 10.0


func tick_controller(delta: float, player: Node3D, enemy: Node3D) -> void:
	var real_delta: float = minf(delta / maxf(Engine.time_scale, 0.01), 0.05)

	match _state:
		MiniState.IDLE:
			_match_elapsed += delta
			if _recent_melee_timer > 0.0:
				_recent_melee_timer = maxf(_recent_melee_timer - delta, 0.0)
			if _global_cooldown > 0.0:
				_global_cooldown = maxf(_global_cooldown - delta, 0.0)
				return
			_eval_timer -= delta
			if _eval_timer <= 0.0:
				_eval_timer = 2.5
				_try_trigger_contextual_miniscene(player, enemy)
		MiniState.PLAYER_ACTIVE:
			_process_player_miniscene(real_delta)
		MiniState.AI_WATCHING:
			_process_ai_miniscene(real_delta)
		MiniState.RESULT_HOLD:
			_result_hold_timer -= real_delta
			if _result_hold_timer <= 0.0:
				_end_miniscene()


func _is_clean_free_phase(player: Node3D, enemy: Node3D) -> bool:
	if not player or not is_instance_valid(player) or not enemy or not is_instance_valid(enemy):
		return false
	if bool(player.get("is_match_over")) or bool(enemy.get("is_match_over")):
		return false
	if director and bool(director.get("is_in_intro")):
		return false
	if Engine.time_scale < 0.85:
		return false
	if bool(player.get("is_in_bullet_time")) or bool(enemy.get("is_in_bullet_time")):
		return false
	if (player.get("active_target_dome") != null and is_instance_valid(player.get("active_target_dome"))) or (enemy.get("active_target_dome") != null and is_instance_valid(enemy.get("active_target_dome"))):
		return false
	if bool(player.get("is_in_beam_sequence")) or bool(enemy.get("is_in_beam_sequence")):
		return false
	if bool(player.get("is_flying_to_opponent")) or bool(enemy.get("is_flying_to_opponent")):
		return false
	if bool(player.get("is_charging_super")) or bool(enemy.get("is_charging_super")):
		return false
	if bool(player.get("is_charging_ki")) or bool(enemy.get("is_ragdoll_active")):
		return false
	if player.has_method("is_airborne_incapacitated") and player.is_airborne_incapacitated():
		return false
	return true


func _try_trigger_contextual_miniscene(player: Node3D, enemy: Node3D) -> void:
	if _events_triggered_total >= 4 or _events_catalog.is_empty():
		return
	if not _is_clean_free_phase(player, enemy):
		return

	var target_is_player: bool = not _prefer_ai_next
	if target_is_player and _player_events_count >= 2:
		target_is_player = false
	elif not target_is_player and _ai_events_count >= 2:
		target_is_player = true

	var fighter: Node3D = player if target_is_player else enemy
	var opp: Node3D = enemy if target_is_player else player
	var used_deck: Array[String] = _used_player_events if target_is_player else _used_ai_events

	var eligible: Array[DramaticMiniEventData] = get_eligible_events(fighter, opp, used_deck, _match_elapsed, _recent_melee_timer > 0.0)
	if eligible.is_empty():
		# Intentar con el otro luchador antes de esperar al siguiente pulso
		target_is_player = not target_is_player
		if (target_is_player and _player_events_count >= 2) or (not target_is_player and _ai_events_count >= 2):
			return
		fighter = player if target_is_player else enemy
		opp = enemy if target_is_player else player
		used_deck = _used_player_events if target_is_player else _used_ai_events
		eligible = get_eligible_events(fighter, opp, used_deck, _match_elapsed, _recent_melee_timer > 0.0)
		if eligible.is_empty():
			return

	# Probabilidad contextual: sube con Furia / intensidad para que no sea determinista ni predecible
	var trigger_chance: float = 0.42
	if bool(fighter.get("is_in_furia")):
		trigger_chance = 0.65
	if randf() > trigger_chance:
		return

	var chosen: DramaticMiniEventData = pick_weighted_event(eligible)
	if not chosen:
		return

	used_deck.append(chosen.event_id)
	_events_triggered_total += 1
	_global_cooldown = 28.0
	_prefer_ai_next = target_is_player

	if target_is_player:
		_player_events_count += 1
		_start_player_miniscene(chosen, player, enemy)
	else:
		_ai_events_count += 1
		_start_ai_miniscene(chosen, enemy, player)


## Evalúa eventos elegibles de forma pura y testeable en headless (no repetitivos por luchador).
func get_eligible_events(
	fighter: Node3D,
	opponent: Node3D,
	used_ids: Array[String],
	elapsed_sec: float = 0.0,
	recent_melee: bool = false
) -> Array[DramaticMiniEventData]:
	var res: Array[DramaticMiniEventData] = []
	if not fighter:
		return res

	var c_data: Variant = fighter.get("character_data")
	var c_name_low: String = String(c_data.character_name).to_lower() if (c_data and "character_name" in c_data) else ""
	var max_ki: float = float(c_data.base_ki) if (c_data and "base_ki" in c_data) else 100.0
	var cur_ki: float = float(fighter.get("current_ki")) if fighter.get("current_ki") != null else 50.0
	var ki_ratio: float = cur_ki / maxf(max_ki, 1.0)
	var cur_np: float = float(fighter.get("current_np")) if fighter.get("current_np") != null else 10000.0
	var opp_np: float = float(opponent.get("current_np")) if (opponent and opponent.get("current_np") != null) else 10000.0
	var threshold_ratio: float = float(fighter.get("secured_np_threshold_ratio")) if fighter.get("secured_np_threshold_ratio") != null else 0.0
	var is_furia: bool = bool(fighter.get("is_in_furia"))
	var has_trans: bool = fighter.get("current_transformation") != null

	for ev in _events_catalog:
		if not ev or used_ids.has(ev.event_id):
			continue
		if ev.character_filter != "" and not (ev.character_filter.to_lower() in c_name_low):
			continue

		var cond_ok: bool = false
		match ev.condition_type:
			"low_ki_or_even":
				cond_ok = (ki_ratio <= 0.50) or (absf(cur_np - opp_np) <= opp_np * 0.18)
			"after_melee_or_behind":
				cond_ok = recent_melee or (cur_np <= opp_np)
			"threshold_50_plus":
				cond_ok = threshold_ratio >= 0.50 or elapsed_sec >= 42.0
			"base_or_behind":
				cond_ok = (not has_trans) or (cur_np < opp_np * 0.92)
			"intense_or_furia":
				cond_ok = is_furia or elapsed_sec >= 28.0
			"pressure_or_furia":
				cond_ok = is_furia or (cur_np < opp_np)
			"dominating_or_ssj":
				cond_ok = has_trans or (cur_np > opp_np * 1.10)
			_:
				cond_ok = true

		if cond_ok:
			res.append(ev)

	return res


func pick_weighted_event(candidates: Array[DramaticMiniEventData]) -> DramaticMiniEventData:
	if candidates.is_empty():
		return null
	var total_w: float = 0.0
	for ev in candidates:
		total_w += maxf(ev.weight, 0.1)
	var roll: float = randf() * total_w
	var acc: float = 0.0
	for ev in candidates:
		acc += maxf(ev.weight, 0.1)
		if roll <= acc:
			return ev
	return candidates[0]


func _resolve_vr_nodes(player: Node3D) -> void:
	if not player or not is_instance_valid(player):
		return
	var origin: Node = player.get_parent()
	if origin:
		_cached_cam = origin.get_node_or_null("XRCamera3D") as Camera3D
		_cached_l_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
		_cached_r_ctrl = origin.get_node_or_null("RightHand") as XRController3D
	if not _cached_cam and get_viewport():
		_cached_cam = get_viewport().get_camera_3d()


func _attach_stage_to_camera() -> void:
	if not _vr_stage_root or not is_instance_valid(_vr_stage_root):
		return
	if _cached_cam and is_instance_valid(_cached_cam):
		# Anclaje cómodo frente al visor manteniendo el ángulo del horizonte
		var fwd: Vector3 = -_cached_cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
		_vr_stage_root.global_position = _cached_cam.global_position
		_vr_stage_root.look_at(_cached_cam.global_position + fwd, Vector3.UP)
		_vr_stage_root.visible = true


func _start_player_miniscene(ev: DramaticMiniEventData, player: Node3D, enemy: Node3D) -> void:
	_active_event = ev
	_active_fighter = player
	_active_opponent = enemy
	_state = MiniState.PLAYER_ACTIVE
	_mini_time_left = ev.duration_sec
	_mini_elapsed = 0.0
	_progress_count = 0
	_progress_float = 0.0
	_action_debounce = 0.12
	_was_in_pulse_window = false
	_last_pulse_cycle_hit = -1

	_resolve_vr_nodes(player)
	_prev_l_pos = _cached_l_ctrl.global_position if _cached_l_ctrl else Vector3.ZERO
	_prev_r_pos = _cached_r_ctrl.global_position if _cached_r_ctrl else Vector3.ZERO
	_prev_trig_l = true
	_prev_trig_r = true

	if director and director.has_method("set_dramatic_pause"):
		director.set_dramatic_pause(true)
	Engine.time_scale = 0.04
	if director and director.has_method("begin_miniscene_atmosphere"):
		director.begin_miniscene_atmosphere(player, ev.bonus_color)
	if director and director.has_method("play_dramatic_sfx"):
		director.play_dramatic_sfx("dramatic.miniscene_trigger", "common.zenkai_activate")
		director.play_character_dramatic_voice(player, "dramatic_miniscene", "attack_effort")

	_attach_stage_to_camera()
	_configure_player_minigame_props(ev)
	_pulse_both_hands(150.0, 0.85, 0.18)
	emit_signal("miniscene_started", player, ev)


func _configure_player_minigame_props(ev: DramaticMiniEventData) -> void:
	for m in _prop_nodes:
		m.visible = false
		m.scale = Vector3.ONE

	if _hud_title_lbl:
		_hud_title_lbl.text = "⚡ %s ⚡\n%s" % [ev.display_name.to_upper(), ev.instruction_text]
		_hud_title_lbl.modulate = ev.bonus_color

	match ev.minigame_type:
		"shake_pump", "rapid_punch":
			_set_prop_color(_prop_nodes[0], ev.bonus_color)
			_prop_nodes[0].position = Vector3(0.0, -0.08, -0.48)
			_prop_nodes[0].scale = Vector3.ONE * 1.15
			_prop_nodes[0].visible = true
		"orb_tap":
			var offsets: Array[Vector3] = [Vector3(-0.26, -0.05, -0.48), Vector3(0.0, 0.06, -0.48), Vector3(0.26, -0.05, -0.48)]
			for i in range(3):
				_prop_nodes[i].position = offsets[i]
				_prop_nodes[i].visible = true
				_set_prop_color(_prop_nodes[i], ev.bonus_color if i == 0 else Color(0.35, 0.45, 0.55, 0.45))
				_prop_nodes[i].scale = Vector3.ONE * (1.25 if i == 0 else 0.75)
		"hold_expand":
			_prop_nodes[0].position = Vector3(0.0, -0.04, -0.56)
			_prop_nodes[0].visible = true
			_set_prop_color(_prop_nodes[0], ev.bonus_color)
		"sky_absorb":
			_prop_nodes[0].position = Vector3(-0.22, 0.22, -0.45)
			_prop_nodes[1].position = Vector3(0.22, 0.22, -0.45)
			_prop_nodes[0].visible = true
			_prop_nodes[1].visible = true
			_set_prop_color(_prop_nodes[0], ev.bonus_color)
			_set_prop_color(_prop_nodes[1], ev.bonus_color)
		"rhythm_pulse":
			_prop_nodes[0].position = Vector3(0.0, -0.06, -0.52)
			_prop_nodes[0].visible = true
			_set_prop_color(_prop_nodes[0], ev.bonus_color)
		"aim_targets":
			var aim_offsets: Array[Vector3] = [Vector3(-0.34, 0.04, -1.25), Vector3(0.0, 0.20, -1.25), Vector3(0.34, 0.04, -1.25)]
			for i in range(3):
				_prop_nodes[i].position = aim_offsets[i]
				_prop_nodes[i].visible = true
				_set_prop_color(_prop_nodes[i], ev.bonus_color)


func _set_prop_color(mesh_inst: MeshInstance3D, col: Color) -> void:
	if not mesh_inst or not is_instance_valid(mesh_inst):
		return
	var mat := mesh_inst.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = col


func _process_player_miniscene(real_delta: float) -> void:
	if not _active_event or not _active_fighter or not is_instance_valid(_active_fighter):
		_end_miniscene()
		return

	_mini_elapsed += real_delta
	_mini_time_left -= real_delta
	if _action_debounce > 0.0:
		_action_debounce = maxf(_action_debounce - real_delta, 0.0)

	var l_pos: Vector3 = _cached_l_ctrl.global_position if _cached_l_ctrl else Vector3.ZERO
	var r_pos: Vector3 = _cached_r_ctrl.global_position if _cached_r_ctrl else Vector3.ZERO
	var l_vel: Vector3 = (l_pos - _prev_l_pos) / maxf(real_delta, 0.004)
	var r_vel: Vector3 = (r_pos - _prev_r_pos) / maxf(real_delta, 0.004)
	_prev_l_pos = l_pos
	_prev_r_pos = r_pos

	var l_grip: bool = _cached_l_ctrl != null and (_cached_l_ctrl.get_float("grip") > 0.5 or _cached_l_ctrl.is_button_pressed("grip_click"))
	var r_grip: bool = _cached_r_ctrl != null and (_cached_r_ctrl.get_float("grip") > 0.5 or _cached_r_ctrl.is_button_pressed("grip_click"))
	var l_trig: bool = _cached_l_ctrl != null and (_cached_l_ctrl.get_float("trigger") > 0.5 or _cached_l_ctrl.is_button_pressed("trigger_click"))
	var r_trig: bool = _cached_r_ctrl != null and (_cached_r_ctrl.get_float("trigger") > 0.5 or _cached_r_ctrl.is_button_pressed("trigger_click"))
	var just_trig_l: bool = l_trig and not _prev_trig_l
	var just_trig_r: bool = r_trig and not _prev_trig_r
	_prev_trig_l = l_trig
	_prev_trig_r = r_trig

	var completed: bool = false
	var target: int = maxi(_active_event.target_count, 1)

	match _active_event.minigame_type:
		"shake_pump":
			var peak_spd: float = maxf(l_vel.length(), r_vel.length())
			if _action_debounce <= 0.0 and peak_spd >= 1.35:
				_action_debounce = 0.16
				_progress_count += 1
				_on_minigame_step_hit()
			var osc: float = 1.0 + (float(_progress_count) / float(target)) * 0.75 + sin(_mini_elapsed * 20.0) * 0.08
			_prop_nodes[0].scale = Vector3.ONE * osc
			completed = _progress_count >= target

		"orb_tap":
			if _progress_count < 3:
				var cur_orb: MeshInstance3D = _prop_nodes[_progress_count]
				var hit_l: bool = _cached_l_ctrl != null and l_pos.distance_to(cur_orb.global_position) <= 0.24
				var hit_r: bool = _cached_r_ctrl != null and r_pos.distance_to(cur_orb.global_position) <= 0.24
				if hit_l or hit_r:
					cur_orb.visible = false
					_progress_count += 1
					_on_minigame_step_hit()
					if _progress_count < 3:
						_set_prop_color(_prop_nodes[_progress_count], Color(1.0, 0.92, 0.25, 0.95))
						_prop_nodes[_progress_count].scale = Vector3.ONE * 1.30
			completed = _progress_count >= target

		"hold_expand":
			var hands_dist: float = l_pos.distance_to(r_pos)
			if l_grip and r_grip and hands_dist >= 0.50:
				_progress_float += real_delta * 1.45
				var step_now: int = mini(int(floor(_progress_float)), target)
				if step_now > _progress_count:
					_progress_count = step_now
					_on_minigame_step_hit()
			_prop_nodes[0].scale = Vector3.ONE * (0.8 + clampf(_progress_float / float(target), 0.0, 1.0) * 1.4)
			completed = _progress_float >= float(target)

		"sky_absorb":
			var near_rings: bool = false
			if _cached_l_ctrl and _cached_r_ctrl:
				var d_l: float = l_pos.distance_to(_prop_nodes[0].global_position)
				var d_r: float = r_pos.distance_to(_prop_nodes[1].global_position)
				var cam_y: float = _cached_cam.global_position.y if _cached_cam else 1.5
				near_rings = (d_l <= 0.30 and d_r <= 0.30) or (l_pos.y >= cam_y - 0.04 and r_pos.y >= cam_y - 0.04)
			if near_rings:
				_progress_float += real_delta * 1.65
				var absorbed: int = mini(int(floor(_progress_float)), target)
				if absorbed > _progress_count:
					_progress_count = absorbed
					_on_minigame_step_hit()
			var sky_col: Color = Color(1.0, 0.95, 0.35, 0.98) if near_rings else _active_event.bonus_color
			_set_prop_color(_prop_nodes[0], sky_col)
			_set_prop_color(_prop_nodes[1], sky_col)
			completed = _progress_float >= float(target)

		"rhythm_pulse":
			var cycle_len: float = 1.10
			var cycle_idx: int = int(floor(_mini_elapsed / cycle_len))
			var cycle_t: float = fmod(_mini_elapsed, cycle_len) / cycle_len
			var in_beat: bool = absf(cycle_t - 0.5) <= 0.24
			_prop_nodes[0].scale = Vector3.ONE * (0.65 + cycle_t * 1.15)
			_set_prop_color(_prop_nodes[0], Color(1.0, 0.95, 0.25, 0.98) if in_beat else Color(0.95, 0.18, 0.18, 0.72))
			var surge_act: bool = (just_trig_l or just_trig_r or l_vel.length() >= 1.20 or r_vel.length() >= 1.20)
			if in_beat and surge_act and cycle_idx != _last_pulse_cycle_hit and _action_debounce <= 0.0:
				_last_pulse_cycle_hit = cycle_idx
				_action_debounce = 0.25
				_progress_count += 1
				_on_minigame_step_hit()
			completed = _progress_count >= target

		"rapid_punch":
			if _action_debounce <= 0.0:
				var punch_l: bool = _cached_l_ctrl != null and l_pos.distance_to(_prop_nodes[0].global_position) <= 0.28 and l_vel.length() >= 1.10
				var punch_r: bool = _cached_r_ctrl != null and r_pos.distance_to(_prop_nodes[0].global_position) <= 0.28 and r_vel.length() >= 1.10
				if punch_l or punch_r:
					_action_debounce = 0.14
					_progress_count += 1
					_on_minigame_step_hit()
			_prop_nodes[0].scale = Vector3.ONE * (1.25 - (float(_progress_count) / float(target)) * 0.55)
			completed = _progress_count >= target

		"aim_targets":
			if _progress_count < 3 and (just_trig_l or just_trig_r):
				var active_ctrl: XRController3D = _cached_r_ctrl if just_trig_r else _cached_l_ctrl
				if active_ctrl:
					var aim_dir: Vector3 = (-active_ctrl.global_transform.basis.z).normalized()
					var ctrl_origin: Vector3 = active_ctrl.global_position
					for i in range(3):
						if not _prop_nodes[i].visible:
							continue
						var to_t: Vector3 = (_prop_nodes[i].global_position - ctrl_origin).normalized()
						if aim_dir.dot(to_t) >= 0.84:
							_prop_nodes[i].visible = false
							_progress_count += 1
							_on_minigame_step_hit()
							break
			completed = _progress_count >= target

	if _hud_progress_lbl:
		_hud_progress_lbl.text = "PROGRESO: %d / %d  |  ⏱ %.1fs" % [mini(_progress_count, target), target, maxf(_mini_time_left, 0.0)]

	if completed:
		_resolve_miniscene(true)
	elif _mini_time_left <= 0.0:
		_resolve_miniscene(false)


func _on_minigame_step_hit() -> void:
	_pulse_both_hands(190.0, 0.90, 0.08)
	if director and director.has_method("play_dramatic_sfx"):
		director.play_dramatic_sfx("dramatic.miniscene_tick", "common.block_perfect")


func _start_ai_miniscene(ev: DramaticMiniEventData, ai_fighter: Node3D, player: Node3D) -> void:
	_active_event = ev
	_active_fighter = ai_fighter
	_active_opponent = player
	_state = MiniState.AI_WATCHING
	_mini_time_left = 2.30
	_mini_elapsed = 0.0

	_resolve_vr_nodes(player)
	if director and director.has_method("set_dramatic_pause"):
		director.set_dramatic_pause(true)
	Engine.time_scale = 0.05

	if director and director.has_method("begin_miniscene_atmosphere"):
		director.begin_miniscene_atmosphere(ai_fighter, ev.bonus_color)
	if director and director.has_method("play_dramatic_sfx"):
		director.play_dramatic_sfx("dramatic.miniscene_trigger", "common.zenkai_activate")
		director.play_character_dramatic_voice(ai_fighter, "dramatic_miniscene", "transform_ssj")

	var ai_anim: Variant = ai_fighter.get("procedural_animator")
	if ai_anim and ai_anim.has_method("trigger_transformation_roar"):
		ai_anim.trigger_transformation_roar()

	for m in _prop_nodes:
		m.visible = false
	_attach_stage_to_camera()
	var c_data: Variant = ai_fighter.get("character_data")
	var ai_name: String = String(c_data.character_name).to_upper() if (c_data and "character_name" in c_data) else "RIVAL"
	if _hud_title_lbl:
		_hud_title_lbl.text = "⚡ ¡DESPERTAR RIVAL! (%s) ⚡\n%s" % [ai_name, ev.display_name.to_upper()]
		_hud_title_lbl.modulate = ev.bonus_color
	if _hud_progress_lbl:
		_hud_progress_lbl.text = "(El oponente desata su concentración...)"

	if _ai_ring_mesh:
		_ai_ring_mesh.global_position = ai_fighter.global_position + Vector3(0.0, 1.05, 0.0)
		var r_mat := _ai_ring_mesh.material_override as StandardMaterial3D
		if r_mat:
			r_mat.albedo_color = ev.bonus_color
		_ai_ring_mesh.scale = Vector3.ONE * 0.5
		_ai_ring_mesh.visible = true

	_pulse_both_hands(110.0, 0.45, 0.15)
	emit_signal("miniscene_started", ai_fighter, ev)


func _process_ai_miniscene(real_delta: float) -> void:
	_mini_elapsed += real_delta
	_mini_time_left -= real_delta

	if _ai_ring_mesh and _active_fighter and is_instance_valid(_active_fighter):
		_ai_ring_mesh.global_position = _active_fighter.global_position + Vector3(0.0, 1.05, 0.0)
		_ai_ring_mesh.rotate_y(real_delta * 4.5)
		var s: float = 0.55 + clampf(_mini_elapsed / 2.30, 0.0, 1.0) * 1.15
		_ai_ring_mesh.scale = Vector3.ONE * s

	if _hud_progress_lbl:
		var pct: int = int(clampf(_mini_elapsed / 2.30, 0.0, 1.0) * 100.0)
		_hud_progress_lbl.text = "CONCENTRACIÓN RIVAL: %d%%" % pct

	if _mini_time_left <= 0.0:
		var ai_ctrl: Variant = _active_fighter.get("cached_ai_controller") if (_active_fighter and is_instance_valid(_active_fighter)) else null
		var diff: int = int(ai_ctrl.get("difficulty")) if (ai_ctrl and ai_ctrl.get("difficulty") != null) else 1
		var win_prob: float = 0.45 if diff == 0 else (0.85 if diff == 2 else 0.70)
		_resolve_miniscene(randf() <= win_prob)


func _resolve_miniscene(succeeded: bool) -> void:
	_state = MiniState.RESULT_HOLD
	_result_hold_timer = 1.05 if succeeded else 0.75
	for m in _prop_nodes:
		m.visible = false
	if _ai_ring_mesh:
		_ai_ring_mesh.visible = false

	var c_data: Variant = _active_fighter.get("character_data") if (_active_fighter and is_instance_valid(_active_fighter)) else null
	var f_name: String = String(c_data.character_name).to_upper() if (c_data and "character_name" in c_data) else "LUCHADOR"

	if succeeded:
		if _active_fighter and is_instance_valid(_active_fighter) and _active_fighter.has_method("apply_dramatic_event_bonus"):
			_active_fighter.apply_dramatic_event_bonus(_active_event)
		if director and director.has_method("play_dramatic_sfx"):
			director.play_dramatic_sfx("dramatic.miniscene_success", "common.aura_burst")
		_pulse_both_hands(220.0, 1.0, 0.25)
		if _hud_title_lbl:
			var dur_tag: String = "PERMANENTE" if _active_event.is_permanent_bonus else "%ds" % int(_active_event.bonus_duration_sec)
			_hud_title_lbl.text = "★ ¡%s OBTUVO BONO! ★\n[%s · %s]" % [f_name, _active_event.bonus_label, dur_tag]
			_hud_title_lbl.modulate = Color(1.0, 0.90, 0.20)
		if _hud_progress_lbl:
			var eff_str: String = _active_event.bonus_effect_text if _active_event.bonus_effect_text != "" else "¡PODER DESBLOQUEADO!"
			_hud_progress_lbl.text = eff_str
	else:
		if director and director.has_method("play_dramatic_sfx"):
			director.play_dramatic_sfx("dramatic.miniscene_fail", "common.melee_hit_light")
		if _hud_title_lbl:
			_hud_title_lbl.text = "💨 %s NO COMPLETÓ LA ESCENA" % f_name
			_hud_title_lbl.modulate = Color(0.75, 0.80, 0.88)
		if _hud_progress_lbl:
			_hud_progress_lbl.text = "El combate continúa..."

	emit_signal("miniscene_finished", _active_fighter, _active_event, succeeded)


func _end_miniscene() -> void:
	_state = MiniState.IDLE
	_active_event = null
	_active_fighter = null
	_active_opponent = null
	_cleanup_stage_props()
	if director and director.has_method("set_dramatic_pause"):
		director.set_dramatic_pause(false)
	Engine.time_scale = 1.0
	if director and director.has_method("restore_atmosphere"):
		director.restore_atmosphere()


func _pulse_both_hands(freq: float, amp: float, dur: float) -> void:
	if _cached_l_ctrl and is_instance_valid(_cached_l_ctrl) and _cached_l_ctrl.has_method("trigger_haptic_pulse"):
		_cached_l_ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)
	if _cached_r_ctrl and is_instance_valid(_cached_r_ctrl) and _cached_r_ctrl.has_method("trigger_haptic_pulse"):
		_cached_r_ctrl.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)
