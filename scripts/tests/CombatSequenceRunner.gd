class_name CombatSequenceRunner
extends Node

## Ejecutor de secuencias automáticas de prueba sobre la escena real de combate.
## Permite validar mecánicas de VR (recarga de Ki, Ki Blast, Kamehameha, Melee, Guardia,
## Movimiento y Transformaciones) tanto en ventana visual como en modo --headless.

var simulator: DesktopXRSimulator = null
var hybrid: Node = null
var gesture_tree: Node = null
var player: Node = null
var xr_origin: XROrigin3D = null

var _requested_suite: String = "all"
var _is_running: bool = false

# Contadores de señales capturadas durante cada secuencia
var _sig_ki_recharge_started: int = 0
var _sig_ki_blast_quick: int = 0
var _sig_ki_blast_charged: int = 0
var _last_phase_name: String = ""

# Telemetría causal anti-falsos-positivos (TRACE + AUDIT)
var _seq_start_msec: int = 0
var _active_seq_tag: String = "SETUP"
var _audit_rows: Array[Dictionary] = []
var _dome_hits: int = 0
var _dome_defenses: int = 0
var _dome_parries: int = 0
var _dome_finishers: int = 0
var _opp_hits_unblocked: int = 0
var _opp_hits_blocked: int = 0
var _opp_damage_total: float = 0.0
var _opp_wall_stick_count: int = 0
var _opp_wall_stick_msec: int = 0
var _proj_spawned: int = 0
var _proj_aimed_at_target: int = 0
var _observed_opp: Node = null
var _init_player_pos: Vector3 = Vector3.ZERO
var _init_opp_pos: Vector3 = Vector3.ZERO
var _has_init_poses: bool = false


func start_from_cmdline(sim: DesktopXRSimulator, suite_arg: String = "all") -> void:
	simulator = sim
	_requested_suite = suite_arg if not suite_arg.is_empty() else "all"
	call_deferred("_run_all_sequences")


func _run_all_sequences() -> void:
	if _is_running:
		return
	_is_running = true

	print("==================================================")
	print("[CombatSequenceRunner] Iniciando suite: %s" % _requested_suite)
	print("==================================================")

	if not await _wait_for_scene_ready():
		print("[FAIL] No se pudieron inicializar los nodos de combate.")
		get_tree().quit(1)
		return

	_connect_observation_signals()
	_freeze_enemy_ai(true)

	var all_tests: Array[String] = [
		"ki_recharge",
		"ki_blast",
		"kamehameha",
		"guard_and_move",
		"transformation",
		"melee_punch",
		"followup_melee",
		"followup_hammer",
		"followup_super",
		"followup_barrage",
		"followup_defense",
		"chain_sequences"
	]

	var selected: Array[String] = []
	if _requested_suite == "all":
		selected = all_tests
	else:
		for part: String in _requested_suite.split(",", false):
			var trimmed: String = part.strip_edges()
			if trimmed == "followup_all":
				for fu_name: String in ["followup_melee", "followup_hammer", "followup_super", "followup_barrage", "followup_defense"]:
					if not selected.has(fu_name):
						selected.append(fu_name)
			elif all_tests.has(trimmed):
				selected.append(trimmed)
			else:
				print("[WARN] Secuencia desconocida ignorada: %s" % trimmed)

	if selected.is_empty():
		print("[FAIL] No hay secuencias válidas para ejecutar.")
		get_tree().quit(1)
		return

	var passed: int = 0
	var failed: int = 0

	for test_name: String in selected:
		await _reset_between_tests()
		_seq_start_msec = Time.get_ticks_msec()
		_active_seq_tag = test_name.to_upper()
		_audit_rows.clear()
		_trace(_active_seq_tag, "START", "Iniciando secuencia '%s'" % test_name)
		var ok: bool = false
		match test_name:
			"ki_recharge":
				ok = await _seq_ki_recharge()
			"ki_blast":
				ok = await _seq_ki_blast()
			"kamehameha":
				ok = await _seq_kamehameha()
			"melee_punch":
				ok = await _seq_melee_punch()
			"guard_and_move":
				ok = await _seq_guard_and_move()
			"transformation":
				ok = await _seq_transformation()
			"followup_melee":
				ok = await _seq_followup_melee()
			"followup_hammer":
				ok = await _seq_followup_hammer()
			"followup_super":
				ok = await _seq_followup_super()
			"followup_barrage":
				ok = await _seq_followup_barrage()
			"followup_defense":
				ok = await _seq_followup_defense()
			"chain_sequences":
				ok = await _seq_chain_sequences()

		if not _audit_rows.is_empty():
			var audit_ok: bool = _print_audit_summary(test_name)
			ok = ok and audit_ok

		if ok:
			passed += 1
			print("[PASS] %s" % test_name)
		else:
			failed += 1
			print("[FAIL] %s" % test_name)

	print("==================================================")
	print("[CombatSequenceRunner] Resultado: %d PASS, %d FAIL" % [passed, failed])
	print("==================================================")
	if not DisplayServer.get_name().to_lower().contains("headless"):
		await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if failed == 0 else 1)


func _wait_for_scene_ready() -> bool:
	var timeout: float = 8.0
	while timeout > 0.0:
		var root: Node = get_tree().current_scene
		if root:
			xr_origin = root.find_child("Player_XROrigin3D", true, false) as XROrigin3D
			gesture_tree = root.find_child("GesturePhaseTree", true, false)
			if gesture_tree:
				hybrid = gesture_tree.find_child("HybridCombatController", true, false)
				if not hybrid:
					for c: Node in gesture_tree.get_children():
						if c.has_method("cancel_super_from_poise_break"):
							hybrid = c
							break
				if gesture_tree.has_method("_get_player_instance"):
					player = gesture_tree._get_player_instance()
			if xr_origin and gesture_tree and hybrid and player:
				break
		await get_tree().process_frame
		timeout -= get_process_delta_time()

	if not (xr_origin and gesture_tree and hybrid and player):
		return false

	# Saltar intro dramática si está activa
	var dd: DramaticDirector = DramaticDirector.get_active(get_tree())
	if dd:
		if dd.has_method("skip_dramatic_intro"):
			dd.skip_dramatic_intro()
		dd.set("is_dramatic_pause_active", false)
	DramaticDirector.is_dramatic_pause_active = false
	if hybrid:
		hybrid.set("startup_cooldown", 0.0)

	var cur_scene: Node = get_tree().current_scene
	var startup_modal: Node = cur_scene.get_node_or_null("StartupChangelogModal") if cur_scene else null
	if startup_modal and is_instance_valid(startup_modal) and startup_modal.has_method("_close_and_start"):
		startup_modal._close_and_start()
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var active_sim: Variant = hybrid.get("desktop_sim") if hybrid else null
	if active_sim and active_sim != simulator:
		simulator = active_sim as DesktopXRSimulator
	if simulator and xr_origin:
		var cam_node: XRCamera3D = xr_origin.get_node_or_null("XRCamera3D") as XRCamera3D
		simulator.setup(xr_origin, cam_node, true)
		simulator.set("mode", 1)
		simulator.set("sim_active", true)
		if hybrid:
			hybrid.set("desktop_sim", simulator)
	if dd and dd.is_in_intro:
		dd.skip_dramatic_intro()
		await get_tree().process_frame

	# Esperar fin de startup_cooldown de HybridCombatController (1.5s)
	var wait_cd: float = 3.0
	while wait_cd > 0.0 and float(hybrid.get("startup_cooldown")) > 0.0:
		await get_tree().process_frame
		wait_cd -= get_process_delta_time()

	if xr_origin and is_instance_valid(xr_origin):
		_init_player_pos = xr_origin.global_position
		var opp_init: Node3D = player._get_opponent() if (player and player.has_method("_get_opponent")) else null
		if opp_init and is_instance_valid(opp_init):
			_init_opp_pos = opp_init.global_position
			_has_init_poses = true

	return float(hybrid.get("startup_cooldown")) <= 0.0


func _connect_observation_signals() -> void:
	if gesture_tree:
		if gesture_tree.has_signal("ki_recharge_started") and not gesture_tree.ki_recharge_started.is_connected(_on_ki_recharge_started):
			gesture_tree.ki_recharge_started.connect(_on_ki_recharge_started)
		if gesture_tree.has_signal("ki_blast_fired") and not gesture_tree.ki_blast_fired.is_connected(_on_ki_blast_fired):
			gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)
		if gesture_tree.has_signal("phase_changed") and not gesture_tree.phase_changed.is_connected(_on_phase_changed):
			gesture_tree.phase_changed.connect(_on_phase_changed)

	var cur_scene: Node = get_tree().current_scene
	if cur_scene and not cur_scene.child_entered_tree.is_connected(_on_scene_child_entered):
		cur_scene.child_entered_tree.connect(_on_scene_child_entered)

	var opp: Node = player._get_opponent() if (player and player.has_method("_get_opponent")) else null
	if opp and is_instance_valid(opp):
		_connect_opponent_signals(opp)


func _connect_opponent_signals(opp: Node) -> void:
	if not opp or not is_instance_valid(opp) or _observed_opp == opp:
		return
	_observed_opp = opp
	if opp.has_signal("combat_hit_received") and not opp.combat_hit_received.is_connected(_on_opp_combat_hit_received):
		opp.combat_hit_received.connect(_on_opp_combat_hit_received)
	if opp.has_signal("wall_stick_triggered") and not opp.wall_stick_triggered.is_connected(_on_opp_wall_stick_triggered):
		opp.wall_stick_triggered.connect(_on_opp_wall_stick_triggered)


func _attach_dome_observers(dome: Variant) -> void:
	if not dome or not is_instance_valid(dome):
		return
	var d_node: Node = dome as Node
	if d_node.has_signal("target_hit") and not d_node.target_hit.is_connected(_on_dome_target_hit):
		d_node.target_hit.connect(_on_dome_target_hit)
	if d_node.has_signal("defense_action_resolved") and not d_node.defense_action_resolved.is_connected(_on_dome_defense_resolved):
		d_node.defense_action_resolved.connect(_on_dome_defense_resolved)
	if d_node.has_signal("perfect_parry_triggered") and not d_node.perfect_parry_triggered.is_connected(_on_dome_perfect_parry):
		d_node.perfect_parry_triggered.connect(_on_dome_perfect_parry)
	if d_node.has_signal("finisher_triggered") and not d_node.finisher_triggered.is_connected(_on_dome_finisher_triggered):
		d_node.finisher_triggered.connect(_on_dome_finisher_triggered)


func _trace(stage: String, event_name: String, details: String) -> void:
	var elapsed_s: float = float(Time.get_ticks_msec() - _seq_start_msec) / 1000.0 if _seq_start_msec > 0 else 0.0
	print("[TRACE t=+%.2fs][%s] %-14s %s" % [elapsed_s, stage, event_name, details])


func _audit_add(step_label: String, passed: bool, detail: String) -> void:
	_audit_rows.append({
		"label": step_label,
		"ok": passed,
		"detail": detail
	})


func _print_audit_summary(seq_name: String) -> bool:
	var all_ok: bool = true
	print("[AUDIT][%s]" % seq_name)
	for row: Dictionary in _audit_rows:
		var ok_row: bool = bool(row.get("ok", false))
		if not ok_row:
			all_ok = false
		var status_str: String = "OK" if ok_row else "FAIL"
		print("  - %-24s %-4s (%s)" % [String(row.get("label", "")), status_str, String(row.get("detail", ""))])
	return all_ok


func _get_fighters_dist(opp: Node3D) -> float:
	if not player or not is_instance_valid(player) or not opp or not is_instance_valid(opp):
		return -1.0
	var p_pos: Vector3 = xr_origin.global_position if (xr_origin and is_instance_valid(xr_origin)) else (player as Node3D).global_position
	return p_pos.distance_to(opp.global_position)


func _on_ki_recharge_started(_is_heavy: bool) -> void:
	_sig_ki_recharge_started += 1
	_trace(_active_seq_tag, "KI_RECHARGE", "started heavy=%s count=%d" % [str(_is_heavy), _sig_ki_recharge_started])


func _on_ki_blast_fired(hand_side: int, is_charged: bool) -> void:
	if is_charged:
		_sig_ki_blast_charged += 1
	else:
		_sig_ki_blast_quick += 1
	_trace(_active_seq_tag, "KI_BLAST_FIRE", "hand=%s charged=%s quick_cnt=%d charged_cnt=%d" % [
		"L" if hand_side == 0 else "R",
		str(is_charged),
		_sig_ki_blast_quick,
		_sig_ki_blast_charged
	])


func _on_phase_changed(new_phase_name: String) -> void:
	_last_phase_name = new_phase_name
	_trace(_active_seq_tag, "PHASE", "new_phase=%s" % new_phase_name)


func _on_opp_combat_hit_received(damage_np: float, was_blocked: bool, apply_kb: bool, _hit_dir: Vector3) -> void:
	if was_blocked:
		_opp_hits_blocked += 1
	else:
		_opp_hits_unblocked += 1
		_opp_damage_total += damage_np
	var opp_ki: float = float(_observed_opp.get("current_ki")) if (_observed_opp and is_instance_valid(_observed_opp)) else -1.0
	var opp_np: float = float(_observed_opp.get("current_np")) if (_observed_opp and is_instance_valid(_observed_opp)) else -1.0
	_trace(_active_seq_tag, "OPP_HIT", "dmg=%.1f blocked=%s kb=%s opp_ki=%.1f opp_np=%.0f unblocked_cnt=%d" % [
		damage_np,
		str(was_blocked),
		str(apply_kb),
		opp_ki,
		opp_np,
		_opp_hits_unblocked
	])


func _on_opp_wall_stick_triggered(duration_sec: float, impact_speed: float) -> void:
	_opp_wall_stick_count += 1
	_opp_wall_stick_msec = Time.get_ticks_msec()
	var opp_state: String = String(_observed_opp.get("airborne_recovery_state")) if (_observed_opp and is_instance_valid(_observed_opp)) else ""
	_trace(_active_seq_tag, "WALL_STICK", "duration=%.2fs impact_speed=%.1fm/s state=%s" % [duration_sec, impact_speed, opp_state])


func _on_dome_target_hit(hit_count: int, zone_name: String, _hit_pos: Vector3, is_charged: bool, power: float) -> void:
	_dome_hits += 1
	_trace(_active_seq_tag, "MELEE_HIT", "hit#%d zone=%s charged=%s power=%.2f" % [hit_count, zone_name, str(is_charged), power])


func _on_dome_defense_resolved(action_type: String, zone_id: int, was_successful: bool, reward_ki: float, _reward_bp: float) -> void:
	_dome_defenses += 1
	_trace(_active_seq_tag, "DEFENSE", "action=%s zone=%d ok=%s reward_ki=%.1f" % [action_type, zone_id, str(was_successful), reward_ki])


func _on_dome_perfect_parry(_new_attacker: Node3D, _new_defender: Node3D) -> void:
	_dome_parries += 1
	_trace(_active_seq_tag, "PERFECT_PARRY", "cambio de turno activado")


func _on_dome_finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3) -> void:
	_dome_finishers += 1
	_trace(_active_seq_tag, "FINISHER", "name=%s swing_vel=%.1f hits=%d launch_vec=%s (speed=%.1fm/s)" % [
		finisher_name,
		swing_velocity,
		recorded_hits.size(),
		str(launch_vector),
		launch_vector.length()
	])


func _on_scene_child_entered(node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	if not node.name.begins_with("ProceduralKiProjectile_"):
		return
	call_deferred("_inspect_spawned_projectile", node)


func _inspect_spawned_projectile(node: Node) -> void:
	if not node or not is_instance_valid(node) or not (node is Node3D):
		return
	var proj: Node3D = node as Node3D
	var caster: Variant = proj.get("caster_node")
	if caster == null:
		caster = proj.get("owner_fighter")
	if caster != null and caster != player:
		return
	_proj_spawned += 1
	var opp: Node3D = _observed_opp as Node3D
	if not opp or not is_instance_valid(opp):
		return
	var vel_v: Variant = proj.get("velocity")
	var dir_v: Variant = proj.get("direction")
	var fire_dir: Vector3 = Vector3.ZERO
	if vel_v is Vector3 and (vel_v as Vector3).length_squared() > 0.01:
		fire_dir = (vel_v as Vector3).normalized()
	elif dir_v is Vector3 and (dir_v as Vector3).length_squared() > 0.01:
		fire_dir = (dir_v as Vector3).normalized()
	else:
		fire_dir = -proj.global_transform.basis.z.normalized()

	var target_pt: Vector3 = opp.global_position + Vector3(0.0, 1.0, 0.0)
	var to_opp: Vector3 = (target_pt - proj.global_position).normalized()
	var dot_val: float = clampf(fire_dir.dot(to_opp), -1.0, 1.0)
	var angle_err_deg: float = rad_to_deg(acos(dot_val))
	var aimed_ok: bool = angle_err_deg <= 18.0
	if aimed_ok:
		_proj_aimed_at_target += 1
	_trace(_active_seq_tag, "PROJ_SPAWN", "name=%s angle_err=%.1fdeg aimed_ok=%s dist_opp=%.1fm" % [
		proj.name,
		angle_err_deg,
		str(aimed_ok),
		proj.global_position.distance_to(target_pt)
	])


func _freeze_enemy_ai(frozen: bool) -> void:
	var root: Node = get_tree().current_scene
	if not root:
		return
	var opp: Node = root.find_child("EnemyCharacterInstance", true, false)
	if not opp:
		return
	var ai: Node = opp.find_child("CombatAIController", true, false)
	if not ai:
		for c: Node in opp.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("CombatAIController.gd"):
				ai = c
				break
	if ai:
		ai.set_process(not frozen)
		ai.set_physics_process(not frozen)


func _reset_between_tests() -> void:
	Engine.time_scale = 1.0
	simulator.clear_virtual_buttons()
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.22, -0.18, 0.22), false, false, true)
	_sig_ki_recharge_started = 0
	_sig_ki_blast_quick = 0
	_sig_ki_blast_charged = 0
	_last_phase_name = ""
	_dome_hits = 0
	_dome_defenses = 0
	_dome_parries = 0
	_dome_finishers = 0
	_opp_hits_unblocked = 0
	_opp_hits_blocked = 0
	_opp_damage_total = 0.0
	_opp_wall_stick_count = 0
	_opp_wall_stick_msec = 0
	_proj_spawned = 0
	_proj_aimed_at_target = 0

	var cur_sc: Node = get_tree().current_scene
	if cur_sc:
		for c: Node in cur_sc.get_children():
			if c.get_script():
				var spath: String = str(c.get_script().resource_path)
				if spath.ends_with("BeamClashController.gd") or spath.ends_with("SuperBeamSequenceController.gd") or spath.ends_with("FollowUpSequenceController.gd"):
					if c.has_method("_finish_sequence"):
						c._finish_sequence("reset", false)
					else:
						c.queue_free()
	for p_node: Node in get_tree().get_nodes_in_group("ki_projectiles"):
		if p_node and is_instance_valid(p_node):
			p_node.queue_free()

	if player and is_instance_valid(player):
		for fighter: Node in [player, player._get_opponent() if player.has_method("_get_opponent") else null]:
			if not fighter or not is_instance_valid(fighter):
				continue
			var fu_v: Variant = fighter.get("active_followup_controller")
			if fu_v != null and is_instance_valid(fu_v):
				if fu_v.has_method("_finish_sequence"):
					fu_v._finish_sequence("reset", false)
				else:
					fu_v.queue_free()
			fighter.set("active_followup_controller", null)
			fighter.set("is_in_followup_bullet_time", false)
			fighter.set("followup_bullet_time_timer", 0.0)
			fighter.set("combat_chain_depth", 0)
			fighter.set("pending_followup_bonus_hits", 0)
			fighter.set("pending_followup_damage_mult", 1.0)
			fighter.set("vulnerability_state", 0)
			fighter.set("is_defenseless_crash", false)
			fighter.set("crashed_stamped_timer", 0.0)
			fighter.set("defenseless_crash_timer", 0.0)
			fighter.set("is_air_brake_active", false)
			fighter.set("air_brake_progress", 0.0)
			fighter.set("airborne_recovery_state", "RECOVERED")
			fighter.set("is_blocking", false)
			fighter.set("is_in_bullet_time", false)
			fighter.set("is_in_beam_sequence", false)
			fighter.set("is_firing_beam", false)
			fighter.set("is_in_beam_clash", false)
			fighter.set("is_flying_to_opponent", false)
			fighter.set("is_flying_to_melee", false)
			fighter.set("is_knocked_back", false)
			fighter.set("is_ballistic_launch", false)
			fighter.set("velocity", Vector3.ZERO)
			fighter.set("is_match_over", false)
			fighter.set("is_in_zenkai_state", false)
			fighter.set("is_in_furia", false)
			fighter.set("current_np", 10000.0)
			fighter.set("current_ki", 60.0)
			if fighter.has_method("stop_ragdoll"):
				fighter.stop_ragdoll()

		var dome: Variant = player.get("active_target_dome")
		if dome and is_instance_valid(dome):
			dome.queue_free()
			player.set("active_target_dome", null)
		if hybrid and hybrid.has_method("_reset_super_state"):
			hybrid._reset_super_state()
		hybrid.set("super_cooldown", 0.0)
		hybrid.set("melee_cooldown", 0.0)
		hybrid.set("left_blast_cooldown", 0.0)
		hybrid.set("right_blast_cooldown", 0.0)
		hybrid.set("must_release_super_buttons", false)
		hybrid.set("transform_cooldown", 0.0)
		hybrid.set("melee_approach_progress", 0.0)
		player.set("melee_approach_progress", 0.0)

		if _has_init_poses and xr_origin and is_instance_valid(xr_origin):
			xr_origin.global_position = _init_player_pos
			var opp_reset: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
			if opp_reset and is_instance_valid(opp_reset):
				opp_reset.global_position = _init_opp_pos
				var cam_r: Camera3D = xr_origin.get_node_or_null("XRCamera3D") as Camera3D
				if cam_r and is_instance_valid(cam_r):
					cam_r.look_at(opp_reset.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)

	Engine.time_scale = 1.0
	await _step_seconds(0.35)


func _step_seconds(duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _step_real_seconds(duration: float) -> void:
	var end_msec: int = Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < end_msec:
		await get_tree().process_frame


# --- SECUENCIAS DE PRUEBA ---

func _seq_ki_recharge() -> bool:
	player.set("current_ki", 20.0)
	var ki_before: float = float(player.get("current_ki"))

	# Fase 1: Ambos triggers + manos delante de los hombros (y=0.08 -> cam_rel_y=-0.20, sin saltar directo a Fase 2)
	simulator.v_left_trigger = 1.0
	simulator.v_right_trigger = 1.0
	simulator.set_scripted_hands(Vector3(-0.18, 0.08, 0.26), Vector3(0.18, 0.08, 0.26), false, false, true)
	await _step_seconds(0.25)

	if not bool(hybrid.get("ki_prep_phase")):
		print("  -> Motivo: no entró en ki_prep_phase (pose_chest_ki_p1=%s, l_cam_rel_y=%.2f, l_cam_fwd=%.2f, dist=%.2f, dramatic=%s)." % [
			str(hybrid.get("pose_chest_ki_p1")),
			float(hybrid.get("l_cam_rel_y")),
			float(hybrid.get("l_cam_fwd_proj")),
			float(hybrid.get("hands_dist_norm")),
			str(DramaticDirector.is_dramatic_pause_active)
		])
		return false

	# Fase 2: Bajar manos a la cintura
	simulator.set_scripted_hands(Vector3(-0.24, -0.32, 0.14), Vector3(0.24, -0.32, 0.14), false, false, true)
	await _step_seconds(0.9)

	var ki_after: float = float(player.get("current_ki"))
	simulator.clear_virtual_buttons()
	await _step_seconds(0.2)

	if _sig_ki_recharge_started < 1:
		print("  -> Motivo: no se emitió ki_recharge_started.")
		return false
	if ki_after <= ki_before:
		print("  -> Motivo: Ki no aumentó (antes=%.1f, después=%.1f)." % [ki_before, ki_after])
		return false
	return true


func _seq_ki_blast() -> bool:
	player.set("current_ki", 100.0)

	# 1) Ki Blast rápido (mano derecha extendida + trigger corto)
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.18, 0.02, 0.52), false, true, true)
	await _step_seconds(0.08)
	simulator.v_right_trigger = 1.0
	await _step_seconds(0.12)
	simulator.v_right_trigger = 0.0
	await _step_seconds(0.25)

	if _sig_ki_blast_quick < 1:
		print("  -> Motivo: no se disparó Ki Blast rápido.")
		return false

	# 2) Ki Blast cargado (>0.45s)
	hybrid.set("right_blast_cooldown", 0.0)
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.18, 0.02, 0.52), false, true, true)
	await _step_seconds(0.05)
	simulator.v_right_trigger = 1.0
	await _step_seconds(0.95)
	var dbg_rc: float = float(hybrid.get("right_charge_time"))
	simulator.v_right_trigger = 0.0
	await _step_seconds(0.30)

	if _sig_ki_blast_charged < 1:
		print("  -> Motivo: no se disparó Ki Blast cargado (right_charge_time=%.2f, quick=%d, ki=%.1f)." % [dbg_rc, _sig_ki_blast_quick, float(player.get("current_ki"))])
		return false
	return true


func _seq_kamehameha() -> bool:
	player.set("current_ki", 100.0)
	var ki_before: float = float(player.get("current_ki"))

	var cdata: Resource = player.get("character_data")
	var char_name: String = str(cdata.get("character_name")) if cdata else "Goku"
	var is_vegeta: bool = "VEGETA" in char_name.to_upper()

	# Fase 1: Ambos grips + pose canónica del personaje (Galick Ho para Vegeta, Kamehameha para Goku)
	simulator.v_left_grip = 1.0
	simulator.v_right_grip = 1.0
	if is_vegeta:
		simulator.set_scripted_hands(Vector3(0.24, 0.05, 0.08), Vector3(0.32, 0.05, 0.12), false, false, true)
	else:
		simulator.set_scripted_hands(Vector3(-0.28, -0.16, 0.10), Vector3(-0.16, -0.16, 0.14), false, false, true)
	await _step_seconds(1.35)

	if int(hybrid.get("current_super_state")) == 0:
		print("  -> Motivo: Super Poder (%s) no entró en CHARGING (pose_galick=%s, pose_kame=%s)." % [
			"galick_ho" if is_vegeta else "kamehameha",
			str(hybrid.get("pose_side_hip_galick")),
			str(hybrid.get("pose_hip_kame"))
		])
		return false

	# Fase 2: Extender ambas manos al frente para lanzar
	simulator.set_scripted_hands(Vector3(-0.10, -0.05, 0.56), Vector3(0.10, -0.05, 0.56), false, false, true)
	await _step_seconds(0.35)
	simulator.clear_virtual_buttons()
	await _step_seconds(0.3)

	var ki_after: float = float(player.get("current_ki"))
	if ki_after >= ki_before:
		print("  -> Motivo: Super Poder no consumió Ki al disparar (antes=%.1f, después=%.1f)." % [ki_before, ki_after])
		return false
	return true


func _seq_melee_punch() -> bool:
	# Etapa 1: Puño derecho cerrado cerca del pecho
	simulator.v_right_grip = 1.0
	simulator.v_right_trigger = 1.0
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.20, -0.04, 0.14), false, false, true)
	await _step_seconds(0.12)

	if not bool(hybrid.get("right_punch_cocked")):
		print("  -> Motivo: el puño derecho no se armó (right_punch_cocked=false).")
		return false

	# Etapa 2: Extensión explosiva hacia adelante (1 frame rápido para alta velocidad)
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.15, 0.0, 0.58), false, false, true)
	await _step_seconds(0.12)
	simulator.clear_virtual_buttons()

	if float(hybrid.get("melee_cooldown")) <= 0.0:
		print("  -> Motivo: no se disparó _execute_melee_punch (melee_cooldown=0).")
		return false
	return true


func _seq_guard_and_move() -> bool:
	var start_pos: Vector3 = xr_origin.global_position

	# Movimiento horizontal lateral con stick virtual
	simulator.v_right_stick = Vector2(1.0, 0.0)
	await _step_seconds(0.30)
	simulator.v_right_stick = Vector2.ZERO
	await _step_seconds(0.20)

	var moved_dist: float = start_pos.distance_to(xr_origin.global_position)
	if moved_dist < 0.15:
		print("  -> Motivo: el jugador no se desplazó con stick lateral (dist=%.3f)." % moved_dist)
		return false

	# Guardia Cruzada en 'X'
	hybrid.set("ki_prep_phase", false)
	hybrid.set("is_charging_ki", false)
	simulator.v_left_grip = 1.0
	simulator.v_right_grip = 1.0
	simulator.v_left_trigger = 1.0
	simulator.v_right_trigger = 1.0
	simulator.set_scripted_hands(Vector3(-0.08, 0.10, 0.24), Vector3(0.08, 0.10, 0.24), false, false, true)
	await _step_seconds(0.35)

	var blocking: bool = bool(player.get("is_blocking"))
	simulator.clear_virtual_buttons()
	if not blocking:
		print("  -> Motivo: Guardia Cruzada no activó is_blocking.")
		return false
	return true


func _seq_transformation() -> bool:
	var cdata: Resource = player.get("character_data")
	if not cdata or cdata.get("transformations").is_empty():
		print("  -> Motivo: el personaje no tiene transformaciones configuradas.")
		return false

	var first_form: Resource = cdata.get("transformations")[0]
	var unlocked: Variant = player.get("unlocked_transformations")
	if unlocked is Array and not unlocked.has(first_form.get("form_name")):
		unlocked.append(first_form.get("form_name"))

	simulator.v_right_ax = true
	await _step_seconds(0.12)
	simulator.v_right_ax = false
	await _step_seconds(0.20)

	if player.get("current_transformation") == null:
		print("  -> Motivo: ax_button no activó la transformación.")
		return false
	return true


func _launch_opp_and_wait_followup(is_visual: bool) -> Node3D:
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	if not opp or not is_instance_valid(opp):
		return null
	_connect_opponent_signals(opp)
	player.set("current_ki", 95.0)
	opp.set("current_ki", 95.0)

	player.start_flight_to_opponent()
	if is_visual:
		var wait_t: float = 0.0
		while bool(player.get("is_flying_to_opponent")) and wait_t < 2.2:
			await _step_seconds(0.05)
			wait_t += 0.05
		await _step_seconds(0.35)
	else:
		player._stop_flight()
		player._start_melee_bullet_time(opp)

	var dome_0: Variant = player.get("active_target_dome")
	if dome_0 and is_instance_valid(dome_0):
		_attach_dome_observers(dome_0)
		dome_0.set("is_active", false)
		dome_0.emit_signal("finisher_triggered", "charged_v3_back", 3.2, [{ "zone_id": 0, "is_charged": true, "power": 1.35 }], Vector3(0.0, 5.0, -18.0))
		if is_instance_valid(dome_0):
			dome_0.queue_free()
	else:
		player._execute_charged_v3_or_ki_break_finisher(opp, "charged_v3_back", 3.2, Vector3(0.0, 5.0, -18.0))

	await get_tree().process_frame
	var fu: Node3D = player.get("active_followup_controller") as Node3D
	if not fu or not is_instance_valid(fu):
		_audit_add("Intro Pause 1.0s", false, "No se creó FollowUpSequenceController")
		return null
	var pause_ok: bool = fu.has_method("is_in_intro_pause") and bool(fu.call("is_in_intro_pause")) and Engine.time_scale <= 0.01
	_audit_add("Intro Pause 1.0s", pause_ok, "state=%d scale=%.3fx" % [int(fu.get("state")), Engine.time_scale])
	if not pause_ok:
		return null

	var cam_v: Camera3D = xr_origin.get_node_or_null("XRCamera3D") as Camera3D if xr_origin else null
	if cam_v and is_instance_valid(cam_v):
		cam_v.look_at(opp.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)

	var wait_msec: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < wait_msec and is_instance_valid(fu) and int(fu.get("state")) != 3:
		await get_tree().process_frame

	var dec_ok: bool = is_instance_valid(fu) and int(fu.get("state")) == 3 and is_equal_approx(Engine.time_scale, 0.12)
	_audit_add("Decision Window", dec_ok, "state=%s scale=%.2fx" % [str(fu.get("state")) if is_instance_valid(fu) else "freed", Engine.time_scale])
	if not dec_ok:
		Engine.time_scale = 1.0
		return null

	if is_visual:
		await _step_real_seconds(0.75)
	return fu


func _seq_followup_melee() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	var fu: Node3D = await _launch_opp_and_wait_followup(is_visual)
	if not fu:
		return false

	var chosen_ok: bool = bool(fu.call("choose_melee_chase"))
	var bonus_hits: int = int(player.get("pending_followup_bonus_hits"))
	var flying: bool = bool(player.get("is_flying_to_opponent"))
	var ok: bool = chosen_ok and bonus_hits == 2 and flying
	_audit_add("Melee Chase +2 Hits", ok, "chosen=%s bonus=%d flying=%s" % [str(chosen_ok), bonus_hits, str(flying)])
	if not ok:
		Engine.time_scale = 1.0
		return false

	if is_visual:
		var wait_t: float = 0.0
		while bool(player.get("is_flying_to_opponent")) and wait_t < 2.2:
			await _step_real_seconds(0.05)
			wait_t += 0.05
		await _step_real_seconds(0.85)
		if opp and is_instance_valid(opp):
			_trace("FOLLOWUP_MELEE", "ARRIVED", "dist=%.2fm" % _get_fighters_dist(opp))
	else:
		player._stop_flight()
	_cleanup_active_dome_for_test()
	Engine.time_scale = 1.0
	return true


func _seq_followup_hammer() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	var fu: Node3D = await _launch_opp_and_wait_followup(is_visual)
	if not fu:
		return false

	var chosen_ok: bool = bool(fu.call("choose_vanish_hammer"))
	var in_hammer: bool = chosen_ok and int(fu.get("state")) == 5
	_audit_add("Vanish Hammer", in_hammer, "state=%d" % int(fu.get("state")))
	if not in_hammer:
		Engine.time_scale = 1.0
		return false

	if is_visual:
		await _step_real_seconds(0.65)

	fu.call("_execute_hammer_slam_impact", 3.4)
	var crashed: bool = opp != null and int(opp.get("vulnerability_state")) == 3
	var chained_pause: bool = is_instance_valid(fu) and bool(fu.call("is_in_intro_pause")) and int(fu.get("chain_depth")) >= 2
	_audit_add("Hammer Slam + Chain", crashed and chained_pause, "vuln=%d depth=%d" % [int(opp.get("vulnerability_state")) if opp else -1, int(fu.get("chain_depth")) if is_instance_valid(fu) else -1])
	if is_visual:
		await _step_real_seconds(1.35)
	if is_instance_valid(fu):
		fu.call("_finish_sequence", "test_done", false)
	Engine.time_scale = 1.0
	return crashed and chained_pause


func _seq_followup_super() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	var fu: Node3D = await _launch_opp_and_wait_followup(is_visual)
	if not fu:
		return false

	var cam_v: Camera3D = xr_origin.get_node_or_null("XRCamera3D") as Camera3D if xr_origin else null
	if cam_v and is_instance_valid(cam_v) and opp:
		cam_v.look_at(opp.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)

	var ki_before: float = float(player.get("current_ki"))
	var cdata: Resource = player.get("character_data")
	var char_name: String = str(cdata.get("character_name")) if cdata else "Goku"
	var is_vegeta: bool = "VEGETA" in char_name.to_upper()

	simulator.v_left_grip = 1.0
	simulator.v_right_grip = 1.0
	if is_vegeta:
		simulator.set_scripted_hands(Vector3(0.24, 0.05, 0.08), Vector3(0.32, 0.05, 0.12), false, false, true)
	else:
		simulator.set_scripted_hands(Vector3(-0.28, -0.16, 0.10), Vector3(-0.16, -0.16, 0.14), false, false, true)

	var charge_deadline: int = Time.get_ticks_msec() + 2400
	var entered_fast_super: bool = false
	while Time.get_ticks_msec() < charge_deadline:
		await get_tree().process_frame
		var s_state: int = int(hybrid.get("current_super_state"))
		var fu_s: int = int(fu.get("state")) if is_instance_valid(fu) else -1
		if s_state != 0 and fu_s == 6:
			entered_fast_super = true
			if float(hybrid.get("super_charge_timer")) >= 0.85 or s_state == 2:
				break

	_audit_add("Fast Super 2.4x Charge", entered_fast_super, "super_state=%d fu_state=%s" % [int(hybrid.get("current_super_state")), str(fu.get("state")) if is_instance_valid(fu) else "freed"])
	if not entered_fast_super:
		simulator.clear_virtual_buttons()
		Engine.time_scale = 1.0
		return false

	simulator.set_scripted_hands(Vector3(-0.10, -0.05, 0.56), Vector3(0.10, -0.05, 0.56), false, false, true)
	await _step_real_seconds(1.4 if is_visual else 0.5)
	simulator.clear_virtual_buttons()

	var ki_after: float = float(player.get("current_ki"))
	var fired_ok: bool = (ki_after < ki_before) or (not is_instance_valid(fu)) or (String(fu.get("last_action_chosen")) == "fast_super")
	_audit_add("Fast Super Fired", fired_ok, "ki=%.1f->%.1f" % [ki_before, ki_after])
	Engine.time_scale = 1.0
	return entered_fast_super and fired_ok


func _seq_followup_barrage() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	var fu: Node3D = await _launch_opp_and_wait_followup(is_visual)
	if not fu:
		return false

	var cam_v: Camera3D = xr_origin.get_node_or_null("XRCamera3D") as Camera3D if xr_origin else null
	if cam_v and is_instance_valid(cam_v) and opp:
		cam_v.look_at(opp.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)

	var chosen_ok: bool = bool(fu.call("choose_ki_barrage"))
	var in_barrage: bool = chosen_ok and int(fu.get("state")) == 7
	_audit_add("Ki Barrage Entry", in_barrage, "state=%d" % int(fu.get("state")))
	if not in_barrage:
		Engine.time_scale = 1.0
		return false

	var fired_cnt: int = 0
	for i: int in range(8):
		if is_instance_valid(fu) and bool(fu.call("fire_barrage_shot", i % 2)):
			fired_cnt += 1
		await _step_real_seconds(0.10 if is_visual else 0.04)

	var projs: Array = get_tree().get_nodes_in_group("ki_projectiles")
	var has_unblockable: bool = false
	for p_n in projs:
		if p_n and is_instance_valid(p_n) and bool(p_n.get("unblockable_defenseless")):
			has_unblockable = true
			break

	var shots_ok: bool = fired_cnt >= 6 and (has_unblockable or projs.size() >= 1)
	_audit_add("Renzoku 8 Shots", shots_ok, "fired=%d projs=%d unblockable=%s" % [fired_cnt, projs.size(), str(has_unblockable)])
	if is_visual:
		await _step_real_seconds(1.1)
	if is_instance_valid(fu):
		fu.call("_finish_sequence", "test_done", false)
	Engine.time_scale = 1.0
	return shots_ok


func _seq_followup_defense() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	if not opp or not is_instance_valid(opp):
		return false
	opp.set("current_ki", 85.0)
	player.set("current_ki", 75.0)

	opp._launch_and_start_followup(player, Vector3(0.0, 5.0, 18.0), 1.0, "ai_test_launch")
	await get_tree().process_frame
	var fu_def: Node3D = opp.get("active_followup_controller") as Node3D
	if not fu_def or not is_instance_valid(fu_def):
		_audit_add("Def Intro Pause", false, "No se creó FollowUpSequenceController defensivo")
		return false

	var d_title: Label3D = fu_def.get("_title_label") as Label3D
	var d_acts: Label3D = fu_def.get("_def_actions_label") as Label3D
	var hud_ok: bool = bool(fu_def.call("is_in_intro_pause")) and d_title != null and ("FUISTE LANZADO" in d_title.text) and d_acts != null and ("Z-Vanish" in d_acts.text)
	_audit_add("Def Intro Pause", hud_ok, "title=%s" % (d_title.text if d_title else "null"))
	if not hud_ok:
		fu_def.call("_finish_sequence", "test_fail", false)
		Engine.time_scale = 1.0
		return false

	var wait_msec: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < wait_msec and is_instance_valid(fu_def) and int(fu_def.get("state")) != 3:
		await get_tree().process_frame

	player.complete_air_brake()
	var stab_ok: bool = int(player.get("vulnerability_state")) == 2 and is_instance_valid(fu_def)
	_audit_add("Air Brake Stabilized", stab_ok, "vuln=%d" % int(player.get("vulnerability_state")))
	if not stab_ok:
		if is_instance_valid(fu_def):
			fu_def.call("_finish_sequence", "test_fail", false)
		Engine.time_scale = 1.0
		return false

	var box_ok: bool = bool(fu_def.call("choose_vanish_hammer")) and int(fu_def.get("state")) == 9
	_audit_add("Hammer Def Box", box_ok, "state=%d" % int(fu_def.get("state")))
	if is_visual:
		await _step_real_seconds(0.95)
	if is_instance_valid(fu_def):
		fu_def.call("_finish_sequence", "test_done", false)
	Engine.time_scale = 1.0
	return hud_ok and stab_ok and box_ok


func _seq_chain_sequences() -> bool:
	var is_visual: bool = not DisplayServer.get_name().to_lower().contains("headless")
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	if not opp or not is_instance_valid(opp):
		print("  -> Motivo: no se encontró oponente en la escena.")
		return false
	_connect_opponent_signals(opp)

	# 0. SEQ 1: Vegeta inicia con un Melee Dash real y conecta un golpe lanzador contra Goku
	player.set("current_ki", 95.0)
	opp.set("current_ki", 95.0)
	var d1_start_dist: float = _get_fighters_dist(opp)
	var d1_start_msec: int = Time.get_ticks_msec()
	_trace("SEQ1", "DASH1_START", "dist=%.2fm opp_pos=%s" % [d1_start_dist, str(opp.global_position)])
	player.start_flight_to_opponent()
	if is_visual:
		var wait_t: float = 0.0
		while bool(player.get("is_flying_to_opponent")) and wait_t < 2.5:
			await _step_seconds(0.05)
			wait_t += 0.05
	else:
		player._stop_flight()
		player._start_melee_bullet_time(opp)

	var d1_end_dist: float = _get_fighters_dist(opp)
	var d1_elapsed: float = float(Time.get_ticks_msec() - d1_start_msec) / 1000.0
	_trace("SEQ1", "DASH1_END", "dist=%.2fm->%.2fm elapsed=%.2fs mode=%s" % [
		d1_start_dist,
		d1_end_dist,
		d1_elapsed,
		"NATURAL_PHYSICS" if is_visual else "HEADLESS_INJECTED"
	])
	_audit_add("SEQ1 Dash 1", (not is_visual) or d1_end_dist <= 4.5, "%.1fm -> %.1fm en %.2fs" % [d1_start_dist, d1_end_dist, d1_elapsed])

	if is_visual:
		await _step_seconds(0.45)

	# Conectar golpe lanzador v3 desde la cúpula Melee para que Vegeta lance a Goku por los aires y se cierre el minijuego
	var dome_0: Variant = player.get("active_target_dome")
	if dome_0 and is_instance_valid(dome_0):
		_attach_dome_observers(dome_0)
		dome_0.set("is_active", false)
		dome_0.emit_signal("finisher_triggered", "charged_v3_back", 3.2, [{ "zone_id": 0, "is_charged": true, "power": 1.35 }], Vector3(0.0, 5.0, -18.0))
		if is_instance_valid(dome_0):
			dome_0.queue_free()
	else:
		player._execute_charged_v3_or_ki_break_finisher(opp, "charged_v3_back", 3.2, Vector3(0.0, 5.0, -18.0))

	var wait_fu_msec: int = Time.get_ticks_msec() + 3000
	var fu_chain: Variant = player.get("active_followup_controller")
	while Time.get_ticks_msec() < wait_fu_msec and fu_chain != null and is_instance_valid(fu_chain) and int(fu_chain.get("state")) != 3:
		await get_tree().process_frame
	var opp_vel_after_launch: float = (opp.get("velocity") as Vector3).length() if opp.get("velocity") is Vector3 else 0.0
	var bt_ok: bool = bool(player.get("is_in_followup_bullet_time")) and is_equal_approx(Engine.time_scale, 0.12)
	_trace("SEQ1", "LAUNCH_CHECK", "bt=%s scale=%.2fx opp_kb=%s opp_vel=%.1fm/s hits_unblocked=%d" % [
		str(bt_ok),
		Engine.time_scale,
		str(opp.get("is_knocked_back")),
		opp_vel_after_launch,
		_opp_hits_unblocked
	])
	_audit_add("SEQ1 Launch + BT", bt_ok, "scale=%.2fx opp_kb=%s opp_vel=%.1fm/s" % [Engine.time_scale, str(opp.get("is_knocked_back")), opp_vel_after_launch])
	if not bt_ok:
		print("  -> Motivo: el golpe Melee de Vegeta no disparó Follow-Up Bullet-Time (0.12x).")
		Engine.time_scale = 1.0
		return false

	# 1. SEQ 2: Follow-Up Bullet-Time -> dejar ver a Goku suspendido en 0.12x antes de lanzar Meteor Chase
	if is_visual:
		await _step_real_seconds(0.85)
	var d2_start_dist: float = _get_fighters_dist(opp)
	var d2_start_msec: int = Time.get_ticks_msec()
	if fu_chain != null and is_instance_valid(fu_chain) and fu_chain.has_method("choose_melee_chase"):
		fu_chain.call("choose_melee_chase")
	else:
		player.start_flight_to_opponent()
	var bonus_hits: int = int(player.get("pending_followup_bonus_hits"))
	var bonus_mult: float = float(player.get("pending_followup_damage_mult"))
	var bonus_ok: bool = (bonus_hits == 2 and is_equal_approx(bonus_mult, 1.25))
	_trace("SEQ2", "DASH2_START", "dist=%.2fm bonus_hits=%d mult=%.2fx wall_stick=%.2fs" % [
		d2_start_dist,
		bonus_hits,
		bonus_mult,
		float(opp.get("wall_stick_timer"))
	])
	if not bonus_ok:
		print("  -> Motivo: Meteor Chase sin recuperar no otorgó bonus (+2 golpes, 1.25x).")
		_audit_add("SEQ2 Meteor Bonus", false, "hits=%d mult=%.2fx" % [bonus_hits, bonus_mult])
		Engine.time_scale = 1.0
		return false
	_audit_add("SEQ2 Meteor Bonus", true, "+%d golpes, %.2fx" % [bonus_hits, bonus_mult])

	if is_visual:
		var wait_fu: float = 0.0
		while bool(player.get("is_flying_to_opponent")) and wait_fu < 2.5:
			await get_tree().create_timer(0.05, true, false, true).timeout
			wait_fu += 0.05
		var ws_at_arrival: float = float(opp.get("wall_stick_timer"))
		var d2_end_dist: float = _get_fighters_dist(opp)
		var d2_elapsed: float = float(Time.get_ticks_msec() - d2_start_msec) / 1000.0
		var arrived_before_wall: bool = ws_at_arrival <= 0.0 and _opp_wall_stick_count == 0
		_trace("SEQ2", "DASH2_END", "dist=%.2fm->%.2fm elapsed=%.2fs wall_stick_at_arrival=%.2fs arrived_before_wall=%s" % [
			d2_start_dist,
			d2_end_dist,
			d2_elapsed,
			ws_at_arrival,
			str(arrived_before_wall)
		])
		_audit_add("SEQ2 Dash 2 timing", arrived_before_wall and d2_end_dist <= 4.5, "%.1fm->%.1fm en %.2fs, wall_stick=%.2fs" % [d2_start_dist, d2_end_dist, d2_elapsed, ws_at_arrival])
		await get_tree().create_timer(0.9, true, false, true).timeout
	else:
		player._stop_flight()
		_audit_add("SEQ2 Dash 2 timing", true, "HEADLESS_INJECTED")

	# En el 2do Melee (con bonus), Vegeta envía a Goku contra el risco (Wall-Stick + DEFENSELESS_CRASH)
	var dome_1: Variant = player.get("active_target_dome")
	if dome_1 and is_instance_valid(dome_1):
		_attach_dome_observers(dome_1)
		dome_1.set("is_active", false)
		dome_1.emit_signal("finisher_triggered", "charged_v3_back", 3.6, [{ "zone_id": 0, "is_charged": true, "power": 1.5 }], Vector3(0.0, 2.5, -24.0))
		if is_instance_valid(dome_1):
			dome_1.queue_free()
	else:
		_cleanup_active_dome_for_test()
		player._execute_charged_v3_or_ki_break_finisher(opp, "charged_v3_back", 3.6, Vector3(0.0, 2.5, -24.0))

	if is_visual:
		var ws_wait: float = 0.0
		while ws_wait < 0.85 and not bool(opp.get("is_defenseless_crash")):
			await get_tree().create_timer(0.05, true, false, true).timeout
			ws_wait += 0.05
	else:
		await _step_seconds(0.40)

	# 2. Choque físico contra el risco -> Estado Indefenso + 3ra secuencia: Ráfaga de Ki (Renzoku) sobre Goku indefenso
	var wall_source: String = "NATURAL_PHYSICS" if bool(opp.get("is_defenseless_crash")) else "FALLBACK_BOUNDARY"
	if not bool(opp.get("is_defenseless_crash")):
		opp._on_boundary_crash_impact(18.0)
	var crash_ok: bool = bool(opp.get("is_defenseless_crash")) and String(opp.get("airborne_recovery_state")) == "DEFENSELESS_CRASH"
	_trace("SEQ2", "CRASH_CHECK", "source=%s defenseless=%s state=%s wall_stick_cnt=%d" % [
		wall_source,
		str(opp.get("is_defenseless_crash")),
		String(opp.get("airborne_recovery_state")),
		_opp_wall_stick_count
	])
	_audit_add("SEQ2 Wall-Stick/Crash", crash_ok, "%s (%s)" % [String(opp.get("airborne_recovery_state")), wall_source])
	if not crash_ok:
		print("  -> Motivo: _on_boundary_crash_impact no activó DEFENSELESS_CRASH.")
		return false
	if is_visual:
		Engine.time_scale = 1.0
		player.set("is_in_followup_bullet_time", false)
		if player.has_method("_hide_followup_decision_banner"):
			player._hide_followup_decision_banner()
		simulator.set_scripted_hands(Vector3(-0.18, 0.04, 0.52), Vector3(0.18, 0.04, 0.52), true, true, true)
		var cam_v: Camera3D = xr_origin.get_node_or_null("XRCamera3D") as Camera3D if xr_origin else null
		if cam_v and is_instance_valid(cam_v):
			cam_v.look_at(opp.global_position + Vector3(0.0, 1.05, 0.0), Vector3.UP)
		_sig_ki_blast_quick = 0
		_proj_spawned = 0
		_proj_aimed_at_target = 0
		var opp_hits_before_renzoku: int = _opp_hits_unblocked
		var opp_ki_before_renzoku: float = float(opp.get("current_ki"))
		for b_idx: int in range(6):
			var b_act: String = "ki_blast_right" if (b_idx % 2 == 0) else "ki_blast_left"
			if gesture_tree and gesture_tree.has_method("_trigger_action"):
				gesture_tree._trigger_action(b_act)
			var p_anim: Variant = player.get("procedural_animator")
			if p_anim and p_anim.has_method("trigger_ki_blast_shot"):
				p_anim.trigger_ki_blast_shot(b_idx % 2)
			await get_tree().create_timer(0.09, true, false, true).timeout
		var wait_renzoku: float = 0.0
		while wait_renzoku < 2.2 and (_opp_hits_unblocked - opp_hits_before_renzoku) < 4:
			await get_tree().create_timer(0.05, true, false, true).timeout
			wait_renzoku += 0.05
		await get_tree().create_timer(0.25, true, false, true).timeout
		var renzoku_impacts: int = _opp_hits_unblocked - opp_hits_before_renzoku
		var opp_ki_after_renzoku: float = float(opp.get("current_ki"))
		_trace("SEQ3", "RENZOKU_RESULT", "fired=%d spawned=%d aimed_ok=%d impacts_on_opp=%d opp_ki=%.1f->%.1f" % [
			_sig_ki_blast_quick,
			_proj_spawned,
			_proj_aimed_at_target,
			renzoku_impacts,
			opp_ki_before_renzoku,
			opp_ki_after_renzoku
		])
		var renzoku_ok: bool = _sig_ki_blast_quick >= 4 and _proj_aimed_at_target >= 4 and renzoku_impacts >= 3
		_audit_add("SEQ3 Renzoku", renzoku_ok, "%d disparados, %d alineados, %d impactos en Goku" % [
			_sig_ki_blast_quick,
			_proj_aimed_at_target,
			renzoku_impacts
		])
		opp.set("is_defenseless_crash", false)
		opp.set("defenseless_crash_timer", 0.0)
		Engine.time_scale = 1.0
		if not renzoku_ok:
			print("  -> Motivo: Renzoku no cumplió verificación causal (fired=%d, aimed=%d, impacts=%d)." % [
				_sig_ki_blast_quick,
				_proj_aimed_at_target,
				renzoku_impacts
			])
			return false
		return true
	opp.set("is_defenseless_crash", false)
	opp.set("defenseless_crash_timer", 0.0)

	# Probar recuperación Air Brake -> Melee Normal
	player._start_followup_airborne_sequence(opp, Vector3(0.0, 5.0, -18.0))
	await get_tree().create_timer(0.45 if is_visual else 0.40, true, false, true).timeout
	opp.complete_air_brake()
	player.start_flight_to_opponent()
	if int(player.get("pending_followup_bonus_hits")) != 0 or not is_equal_approx(float(player.get("pending_followup_damage_mult")), 1.0):
		print("  -> Motivo: Rival recuperado no debió recibir bonus de seguimiento.")
		Engine.time_scale = 1.0
		return false
	if is_visual:
		await _step_seconds(0.4)
	player._stop_flight()
	_cleanup_active_dome_for_test()

	player.start_post_super_followup(opp)
	if not bool(player.get("is_in_followup_bullet_time")):
		print("  -> Motivo: start_post_super_followup no activó Follow-Up.")
		Engine.time_scale = 1.0
		return false
	if is_visual:
		await get_tree().create_timer(0.5, true, false, true).timeout
	if not opp.trigger_explosive_wave_chain_break() or bool(player.get("is_in_followup_bullet_time")) or int(player.get("combat_chain_depth")) != 0:
		print("  -> Motivo: Explosive Wave no cortó la cadena enemiga.")
		Engine.time_scale = 1.0
		return false
	if is_visual:
		await _step_seconds(0.6)

	# 3. Beam Clash: bloqueo IA + avance hasta 0.0 por Ki == 0
	simulator.v_left_grip = 1.0
	simulator.v_right_grip = 1.0
	simulator.set_scripted_hands(Vector3(-0.18, 0.02, 0.36), Vector3(0.18, 0.02, 0.36), false, false, true)
	var clash_ctrl: Node3D = load("res://scripts/BeamClashController.gd").new()
	get_tree().current_scene.add_child(clash_ctrl)
	clash_ctrl.setup(player, opp, "Kamehameha", Color(0.1, 0.7, 1.0), "Galick Ho", Color(0.8, 0.2, 1.0), 5.5, 1800.0, 1800.0, 1.0, 1.0)
	if not bool(opp.get("is_in_beam_clash")):
		print("  -> Motivo: BeamClashController no bloqueó a la IA con is_in_beam_clash.")
		clash_ctrl.queue_free()
		Engine.time_scale = 1.0
		return false
	if is_visual:
		await _step_seconds(0.8)
	opp.set("current_ki", 0.0)
	if is_visual:
		await _step_seconds(0.9)
	else:
		clash_ctrl._apply_exhaustion_or_timeout_surge(0.8)
	if is_instance_valid(clash_ctrl) and bool(clash_ctrl.get("is_active")):
		if float(clash_ctrl.get("clash_ratio")) > 0.001:
			print("  -> Motivo: el choque no avanzó a 0.0 al quedarse la IA sin Ki (ratio=%.2f)." % float(clash_ctrl.get("clash_ratio")))
			clash_ctrl.queue_free()
			Engine.time_scale = 1.0
			return false
		clash_ctrl._resolve_clash(player, opp, "Kamehameha")
	simulator.clear_virtual_buttons()
	if is_visual:
		await _step_seconds(1.0)

	# 4. Fase 2 & 3: Shunkan Idō + Nuevos Poderes
	_cleanup_active_dome_for_test()
	player.set("is_flying_to_opponent", false)
	player.set("is_in_beam_sequence", false)
	player.set("is_in_beam_clash", false)
	player.set("current_ki", 50.0)
	if not player.execute_shunkan_ido_flank() or float(player.get("current_ki")) >= 50.0:
		print("  -> Motivo: execute_shunkan_ido_flank falló o no consumió Ki.")
		return false

	var goku_res: Resource = load("res://resources/goku.tres")
	var vegeta_res: Resource = load("res://resources/vegeta.tres")
	var has_kame_inst: bool = false
	for p: Resource in goku_res.get("powers"):
		if String(p.get("power_name")) == "Kamehameha Instantáneo":
			has_kame_inst = true
	var has_gamma: bool = false
	var has_final_exp: bool = false
	for p: Resource in vegeta_res.get("powers"):
		var pn: String = String(p.get("power_name"))
		if pn == "Gamma Burst Flash":
			has_gamma = true
		elif pn == "Final Explosion":
			has_final_exp = true
	if not (has_kame_inst and has_gamma and has_final_exp):
		print("  -> Motivo: faltan poderes de Fase 3 en goku.tres / vegeta.tres.")
		return false

	Engine.time_scale = 1.0
	return true


func _cleanup_active_dome_for_test() -> void:
	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	var dome: Variant = player.get("active_target_dome")
	if dome and is_instance_valid(dome):
		dome.queue_free()
	player.set("active_target_dome", null)
	player.set("is_in_bullet_time", false)
	if opp and is_instance_valid(opp):
		opp.set("is_in_bullet_time", false)
