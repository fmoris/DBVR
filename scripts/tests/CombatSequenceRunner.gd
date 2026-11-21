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
		"melee_punch"
	]

	var selected: Array[String] = []
	if _requested_suite == "all":
		selected = all_tests
	else:
		for part: String in _requested_suite.split(",", false):
			var trimmed: String = part.strip_edges()
			if all_tests.has(trimmed):
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

		if ok:
			passed += 1
			print("[PASS] %s" % test_name)
		else:
			failed += 1
			print("[FAIL] %s" % test_name)

	print("==================================================")
	print("[CombatSequenceRunner] Resultado: %d PASS, %d FAIL" % [passed, failed])
	print("==================================================")
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
	if dd and dd.is_in_intro:
		dd.skip_dramatic_intro()
		await get_tree().process_frame

	# Esperar fin de startup_cooldown de HybridCombatController (1.5s)
	var wait_cd: float = 3.0
	while wait_cd > 0.0 and float(hybrid.get("startup_cooldown")) > 0.0:
		await get_tree().process_frame
		wait_cd -= get_process_delta_time()

	return float(hybrid.get("startup_cooldown")) <= 0.0


func _connect_observation_signals() -> void:
	if gesture_tree:
		if gesture_tree.has_signal("ki_recharge_started") and not gesture_tree.ki_recharge_started.is_connected(_on_ki_recharge_started):
			gesture_tree.ki_recharge_started.connect(_on_ki_recharge_started)
		if gesture_tree.has_signal("ki_blast_fired") and not gesture_tree.ki_blast_fired.is_connected(_on_ki_blast_fired):
			gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)
		if gesture_tree.has_signal("phase_changed") and not gesture_tree.phase_changed.is_connected(_on_phase_changed):
			gesture_tree.phase_changed.connect(_on_phase_changed)


func _on_ki_recharge_started(_is_heavy: bool) -> void:
	_sig_ki_recharge_started += 1


func _on_ki_blast_fired(_hand_side: int, is_charged: bool) -> void:
	if is_charged:
		_sig_ki_blast_charged += 1
	else:
		_sig_ki_blast_quick += 1


func _on_phase_changed(new_phase_name: String) -> void:
	_last_phase_name = new_phase_name


func _freeze_enemy_ai(frozen: bool) -> void:
	var root: Node = get_tree().current_scene
	if not root:
		return
	var opp: Node = root.find_child("EnemyCharacterInstance", true, false)
	if not opp:
		return
	var ai: Node = opp.get("cached_ai_controller") as Node
	if not ai:
		ai = opp.find_child("CombatAIController", true, false)
	if not ai:
		ai = root.find_child("CombatAIController", true, false)
	if ai:
		ai.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
		ai.set_process(not frozen)
		ai.set_physics_process(not frozen)
	else:
		print("[WARN] CombatSequenceRunner: no se encontró CombatAIController en EnemyCharacterInstance.")


func _reset_between_tests() -> void:
	simulator.clear_virtual_buttons()
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.22, -0.18, 0.22), false, false, true)
	_sig_ki_recharge_started = 0
	_sig_ki_blast_quick = 0
	_sig_ki_blast_charged = 0
	_last_phase_name = ""

	if player and is_instance_valid(player):
		player.set("current_ki", 60.0)
		player.set("is_blocking", false)
		player.set("is_in_bullet_time", false)
		player.set("is_flying_to_opponent", false)
		player.set("is_flying_to_melee", false)
		player.set("is_in_beam_clash", false)
		player.set("is_in_beam_sequence", false)
		player.set("is_charging_super", false)
		player.set("is_firing_beam", false)
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

	await _step_seconds(0.35)


func _step_seconds(duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


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

	# 1) Ki Blast cargado (>1.0s) primero (evita que un impacto rápido previo dispare melee)
	simulator.set_scripted_hands(Vector3(-0.22, -0.18, 0.22), Vector3(0.18, 0.02, 0.52), false, true, true)
	await _step_seconds(0.08)
	simulator.v_right_trigger = 1.0
	await _step_seconds(1.25)
	simulator.v_right_trigger = 0.0
	await _step_seconds(0.25)

	if _sig_ki_blast_charged < 1:
		print("  -> Motivo: no se disparó Ki Blast cargado.")
		return false

	# 2) Ki Blast rápido (trigger corto)
	player.set("is_in_bullet_time", false)
	player.set("is_flying_to_opponent", false)
	hybrid.set("was_in_melee_minigame", false)
	hybrid.set("right_blast_cooldown", 0.0)
	simulator.v_right_trigger = 1.0
	await _step_seconds(0.12)
	simulator.v_right_trigger = 0.0
	await _step_seconds(0.25)

	if _sig_ki_blast_quick < 1:
		print("  -> Motivo: no se disparó Ki Blast rápido.")
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
	simulator.v_left_grip = 1.0
	simulator.v_right_grip = 1.0
	simulator.v_left_trigger = 1.0
	simulator.v_right_trigger = 1.0
	simulator.set_scripted_hands(Vector3(-0.08, 0.02, 0.24), Vector3(0.08, 0.02, 0.24), false, false, true)
	await _step_seconds(0.15)

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
