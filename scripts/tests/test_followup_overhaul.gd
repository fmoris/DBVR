extends SceneTree

var _ran: bool = false

func _fail(msg: String) -> void:
	printerr("FAIL: %s" % msg)
	Engine.time_scale = 1.0
	quit(1)

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
		return false
	return true

func _process(_delta: float) -> bool:
	if _ran:
		quit(1)
		return true
	_ran = true

	var ki_cfg_s: GDScript = load("res://scripts/resources/ki_economy_config.gd") as GDScript
	var trans_s: GDScript = load("res://scripts/resources/transformation_data.gd") as GDScript
	var fu_s: GDScript = load("res://scripts/FollowUpSequenceController.gd") as GDScript
	var char_s: GDScript = load("res://scripts/character_instance.gd") as GDScript
	var beam_s: GDScript = load("res://scripts/SuperBeamSequenceController.gd") as GDScript
	var proj_s: GDScript = load("res://scripts/ProceduralKiProjectile.gd") as GDScript
	var hcc_s: GDScript = load("res://scripts/HybridCombatController.gd") as GDScript
	var dome_s: GDScript = load("res://scripts/MeleeTargetDome.gd") as GDScript
	var ai_s: GDScript = load("res://scripts/CombatAIController.gd") as GDScript
	var hud_s: GDScript = load("res://scripts/vr_hud.gd") as GDScript

	if not _check(ki_cfg_s and trans_s and fu_s and char_s and beam_s and proj_s and hcc_s and dome_s and ai_s and hud_s, "All core scripts must compile & load"):
		return true

	# 1. KiEconomyConfig follow-up tuning check
	var cfg: Resource = ki_cfg_s.get_default()
	if not _check(absf(float(cfg.get("chain_ki_cost_step")) - 0.18) < 0.001, "chain_ki_cost_step == 0.18"): return true
	if not _check(absf(float(cfg.get("followup_launch_ki_bonus")) - 14.0) < 0.001, "followup_launch_ki_bonus == 14"): return true
	if not _check(absf(float(cfg.get("followup_crash_ki_bonus")) - 18.0) < 0.001, "followup_crash_ki_bonus == 18"): return true
	if not _check(absf(float(cfg.get("followup_melee_cost")) - 12.0) < 0.001, "followup_melee_cost == 12"): return true
	if not _check(absf(float(cfg.get("followup_vanish_hammer_cost")) - 18.0) < 0.001, "followup_vanish_hammer_cost == 18"): return true
	if not _check(absf(float(cfg.get("followup_barrage_entry_cost")) - 10.0) < 0.001, "followup_barrage_entry_cost == 10"): return true
	if not _check(absf(float(cfg.get("followup_intro_pause_sec")) - 1.0) < 0.001, "followup_intro_pause_sec == 1.0"): return true
	if not _check(absf(float(cfg.get("followup_super_charge_mult")) - 2.4) < 0.001, "followup_super_charge_mult == 2.4"): return true

	# 2. Load character resources & verify Transformation ki_max_bonus values
	var goku_res: Resource = load("res://resources/goku_zenkai.tres") as Resource
	var goku_alt: Resource = load("res://resources/goku.tres") as Resource
	var vegeta_res: Resource = load("res://resources/vegeta.tres") as Resource
	if not _check(goku_res != null and goku_alt != null and vegeta_res != null, "Character .tres files must load"):
		return true

	var gz_trs: Array = goku_res.get("transformations")
	if not _check(gz_trs.size() >= 3, "goku_zenkai must have >= 3 transformations"): return true
	if not _check(absf(float(gz_trs[0].get("ki_max_bonus")) - 30.0) < 0.01, "Goku Zenkai SSJ ki_max_bonus == 30"): return true
	if not _check(absf(float(gz_trs[1].get("ki_max_bonus")) - 90.0) < 0.01, "Goku Zenkai SSJ3 ki_max_bonus == 90"): return true
	if not _check(absf(float(gz_trs[2].get("ki_max_bonus")) - 90.0) < 0.01, "Goku Zenkai SSB ki_max_bonus == 90"): return true

	var ga_trs: Array = goku_alt.get("transformations")
	if not _check(ga_trs.size() >= 4, "goku.tres must have >= 4 transformations"): return true
	if not _check(absf(float(ga_trs[0].get("ki_max_bonus")) - 30.0) < 0.01, "Goku SSJ ki_max_bonus == 30"): return true
	if not _check(absf(float(ga_trs[1].get("ki_max_bonus")) - 60.0) < 0.01, "Goku SSJ2 ki_max_bonus == 60"): return true
	if not _check(absf(float(ga_trs[2].get("ki_max_bonus")) - 90.0) < 0.01, "Goku SSB ki_max_bonus == 90"): return true
	if not _check(absf(float(ga_trs[3].get("ki_max_bonus")) - 120.0) < 0.01, "Goku UI ki_max_bonus == 120"): return true

	var v_trs: Array = vegeta_res.get("transformations")
	if not _check(v_trs.size() >= 3, "Vegeta must have >= 3 transformations"): return true
	if not _check(absf(float(v_trs[0].get("ki_max_bonus")) - 30.0) < 0.01, "Vegeta SSJ ki_max_bonus == 30"): return true

	# 3. Build lightweight in-tree arena scene with two CharacterInstance fighters
	var test_scene := Node3D.new()
	test_scene.name = "FollowUpTestScene"
	get_root().add_child(test_scene)

	var rig := XROrigin3D.new()
	rig.name = "XROrigin3D"
	var cam := XRCamera3D.new()
	cam.name = "XRCamera3D"
	var l_ctrl := XRController3D.new()
	l_ctrl.name = "LeftHand"
	var r_ctrl := XRController3D.new()
	r_ctrl.name = "RightHand"
	rig.add_child(cam)
	rig.add_child(l_ctrl)
	rig.add_child(r_ctrl)
	test_scene.add_child(rig)

	var p_atk := char_s.new() as Node3D
	p_atk.name = "PlayerCharacterInstance"
	p_atk.set("is_player", true)
	p_atk.set("character_data", goku_res)
	rig.add_child(p_atk)
	p_atk.set("current_np", 10000.0)
	p_atk.set("current_ki", 50.0)
	var unlocked_names: Array[String] = []
	for t_r in gz_trs:
		if t_r and t_r.get("form_name") != null:
			unlocked_names.append(String(t_r.get("form_name")))
	p_atk.set("unlocked_transformations", unlocked_names)

	var e_def := char_s.new() as Node3D
	e_def.name = "EnemyCharacterInstance"
	e_def.set("is_player", false)
	e_def.set("character_data", vegeta_res)
	test_scene.add_child(e_def)
	e_def.global_position = Vector3(0.0, 2.5, -6.0)
	e_def.set("current_np", 20000.0)
	e_def.set("current_ki", 60.0)

	# 4. Transformation Ki scaling & restore
	if not _check(absf(p_atk.call("get_max_ki") - 100.0) < 0.01, "Base get_max_ki == 100"): return true
	p_atk.call("transform_to", 0) # SSJ: +30 max -> 130, +25 restore -> 75 (no Zenkai since e_def=20k)
	if not _check(absf(p_atk.call("get_max_ki") - 130.0) < 0.01, "SSJ get_max_ki == 130"): return true
	if not _check(absf(float(p_atk.get("current_ki")) - 75.0) < 0.01, "SSJ ki_transform_restore +25 -> 75, got %.1f" % float(p_atk.get("current_ki"))): return true
	p_atk.call("recharge_ki", 999.0)
	if not _check(absf(float(p_atk.get("current_ki")) - 130.0) < 0.01, "SSJ Ki capped at 130"): return true
	p_atk.call("revert_to_base")
	if not _check(absf(p_atk.call("get_max_ki") - 100.0) < 0.01, "Reverted get_max_ki == 100"): return true
	if not _check(float(p_atk.get("current_ki")) <= 100.0, "Reverted Ki clamped <= 100"): return true
	e_def.set("current_np", 10000.0)
	p_atk.set("is_in_furia", false)
	p_atk.set("is_in_zenkai_state", false)
	p_atk.set("is_penalized", false)

	# 5. Defenseless states: AIRBORNE_LAUNCHED -> STABILIZED vs CRASHED_STAMPED
	var eff_equal: float = e_def.call("compute_air_stabilize_effort", 10000.0, 10000.0, 1.0)
	var eff_stronger: float = e_def.call("compute_air_stabilize_effort", 25000.0, 10000.0, 1.4)
	if not _check(eff_stronger > eff_equal, "Stronger attacker/strike requires more stabilize effort"): return true

	var d_short: float = e_def.call("compute_crash_stamped_duration", 10000.0, 15000.0, 0.9)
	var d_long: float = e_def.call("compute_crash_stamped_duration", 20000.0, 10000.0, 1.6)
	if not _check(d_long > d_short and d_short >= 1.05 and d_long <= 3.40, "Crash duration scales with BP and strike"): return true

	e_def.call("enter_airborne_launched", 12000.0, 1.1, 24.0)
	if not _check(int(e_def.get("vulnerability_state")) == 1, "enter_airborne_launched sets state 1"): return true
	if not _check(bool(e_def.call("is_vulnerable_defenseless")), "AIRBORNE_LAUNCHED is vulnerable"): return true

	# Spawn FollowUpSequenceController via CharacterInstance
	p_atk.set("current_ki", 40.0)
	p_atk.call("_start_followup_controller", e_def, 1.1, "test_launch", true)
	var fu: Node3D = p_atk.get("active_followup_controller") as Node3D
	if not _check(fu != null and is_instance_valid(fu), "active_followup_controller created"): return true
	if not _check(int(fu.get("state")) == 1, "Initial state is HITSTOP (1)"): return true
	if not _check(bool(fu.call("is_in_intro_pause")), "is_in_intro_pause() active on start"): return true
	if not _check(Engine.time_scale <= 0.01, "Intro pause freezes Engine.time_scale <= 0.01"): return true
	if not _check(absf(float(fu.call("get_intro_pause_remaining")) - 1.0) < 0.01, "Intro pause starts at 1.0s"): return true
	var hud_a: Node3D = fu.get("_hud_anchor") as Node3D
	var title_l: Label3D = fu.get("_title_label") as Label3D
	var slots: Array = fu.get("_card_slots")
	if not _check(hud_a != null and is_instance_valid(hud_a), "HUD created immediately during 1s intro pause"): return true
	if not _check(title_l != null and ("SIGUIENTE SECUENCIA" in title_l.text), "Intro pause HUD announces SIGUIENTE SECUENCIA"): return true
	if not _check(slots.size() == 4, "Intro pause HUD renders 4 action cards"): return true
	if not _check(absf(float(p_atk.get("current_ki")) - 54.0) < 0.01, "+14 Ki awarded on launch (40 -> 54, got %.2f)" % float(p_atk.get("current_ki"))): return true

	# Complete Air Brake on defender while FollowUp is active -> must NOT cancel FollowUp!
	e_def.call("complete_air_brake")
	if not _check(int(e_def.get("vulnerability_state")) == 2, "complete_air_brake sets STABILIZED (2)"): return true
	if not _check(not bool(e_def.call("is_vulnerable_defenseless")), "STABILIZED is no longer defenseless"): return true
	if not _check(is_instance_valid(fu) and bool(fu.get("is_active")), "complete_air_brake must NOT cancel active FollowUp"): return true

	# Step FollowUp HITSTOP (0.48s still paused -> 1.12s unlocks to RAMP_TO_BT) -> DECISION_WINDOW using real_dt simulation
	for _k in range(6):
		fu.call("_process", 0.0004) # 6 * 0.08s = 0.48s < 1.0s
	if not _check(int(fu.get("state")) == 1 and bool(fu.call("is_in_intro_pause")), "Still in 1s intro pause at 0.48s"): return true
	for _i in range(8):
		fu.call("_process", 0.0004) # +0.64s -> total 1.12s > 1.0s
	if not _check(int(fu.get("state")) == 2 and not bool(fu.call("is_in_intro_pause")), "HITSTOP transitions to RAMP_TO_BT (2) after 1.0s"): return true
	var hud_still: Node3D = fu.get("_hud_anchor") as Node3D
	if not _check(hud_still != null and is_instance_valid(hud_still), "HUD stays alive across pause unlock into RAMP_TO_BT"): return true
	for _j in range(8):
		fu.call("_process", 0.06)
	if not _check(int(fu.get("state")) == 3, "RAMP_TO_BT transitions to DECISION_WINDOW (3)"): return true
	if not _check(absf(Engine.time_scale - 0.12) < 0.01, "DECISION_WINDOW sets Engine.time_scale = 0.12"): return true

	# Extensible registry check
	var moves_before: Array = fu.call("get_registered_moves")
	if not _check(moves_before.size() == 4, "Default 4 follow-up moves registered"): return true
	fu.call("register_custom_move", { "id": "dragon_fist", "title": "PUÑO DRAGÓN", "cue": "🐉", "icon": "icon_fist.png" })
	if not _check(fu.call("get_registered_moves").size() == 5, "Custom move registration works"): return true

	# Option 4: Ki Barrage + fire_barrage_shot while CRASHED_STAMPED vs STABILIZED
	if not _check(bool(fu.call("choose_ki_barrage")), "choose_ki_barrage succeeds"): return true
	if not _check(int(fu.get("state")) == 7, "Player Ki Barrage state is MINI_KI_BARRAGE_ATK (7)"): return true
	# Test stabilized shot -> unblockable_defenseless == false
	if not _check(bool(fu.call("fire_barrage_shot", 0)), "fire_barrage_shot(0) succeeds"): return true
	var projs: Array = get_nodes_in_group("ki_projectiles")
	if not _check(projs.size() >= 1, "Barrage spawned projectile in scene"): return true
	if not _check(not bool(projs[projs.size() - 1].get("unblockable_defenseless")), "Stabilized target projectile is blockable"): return true

	# Crash defender -> CRASHED_STAMPED + +18 Ki once -> barrage shot is unblockable_defenseless
	var ki_before_crash: float = float(p_atk.get("current_ki"))
	e_def.call("_on_ground_crash_impact", 18.0, e_def.global_position, 0.0)
	if not _check(int(e_def.get("vulnerability_state")) == 3, "Ground crash sets CRASHED_STAMPED (3)"): return true
	if not _check(not bool(e_def.get("is_air_brake_active")), "No air brake wake-up on crash"): return true
	if not _check(absf(float(p_atk.get("current_ki")) - (ki_before_crash + 18.0)) < 0.01, "Crash awards +18 Ki to attacker (got %.2f vs %.2f)" % [float(p_atk.get("current_ki")), ki_before_crash + 18.0]): return true
	# Second crash on same launch must NOT double-award +18 Ki
	e_def.call("_on_boundary_crash_impact", 16.0)
	if not _check(absf(float(p_atk.get("current_ki")) - (ki_before_crash + 18.0)) < 0.01, "Crash bonus awarded at most once per launch"): return true

	if not _check(bool(fu.call("fire_barrage_shot", 1)), "Second barrage shot while crashed succeeds"): return true
	projs = get_nodes_in_group("ki_projectiles")
	if not _check(bool(projs[projs.size() - 1].get("unblockable_defenseless")), "Crashed target projectile is unblockable_defenseless"): return true

	fu.call("_finish_sequence", "test_done", false)
	if not _check(absf(Engine.time_scale - 1.0) < 0.001, "_finish_sequence restores Engine.time_scale = 1.0"): return true

	# 6. Option 1 (Melee Chase) & Z-Bounce Chain Depth scaling + Option 2 (Vanish Hammer)
	p_atk.set("combat_chain_depth", 1)
	p_atk.set("current_ki", 80.0)
	e_def.call("enter_airborne_launched", 12000.0, 1.0, 24.0)
	p_atk.call("_start_followup_controller", e_def, 1.0, "chain2", true)
	var fu2: Node3D = p_atk.get("active_followup_controller") as Node3D
	if not _check(fu2 != null and int(fu2.get("chain_depth")) == 2, "Chain depth increments to 2 on Z-Bounce"): return true
	if not _check(absf(float(fu2.call("get_chain_cost_multiplier")) - 1.18) < 0.001, "Depth 2 multiplier == 1.18"): return true
	if not _check(bool(fu2.call("choose_vanish_hammer")), "choose_vanish_hammer succeeds"): return true
	if not _check(int(fu2.get("state")) == 5, "Player Hammer state is MINI_VANISH_HAMMER (5)"): return true
	fu2.call("_execute_hammer_slam_impact", 3.2)
	if not _check(int(e_def.get("vulnerability_state")) == 3, "Hammer slam stamps rival to CRASHED_STAMPED"): return true
	if not _check(int(fu2.get("state")) == 1 and bool(fu2.call("is_in_intro_pause")), "Hammer slam re-enters 1s intro pause when attacker has Ki"): return true
	if not _check(int(fu2.get("chain_depth")) == 3, "Hammer slam chain increments chain_depth to 3"): return true
	for _h in range(14):
		fu2.call("_process", 0.0004)
	for _r in range(8):
		fu2.call("_process", 0.06)
	if not _check(int(fu2.get("state")) == 3, "Hammer slam chain unlocks to DECISION_WINDOW after 1s + ramp"): return true
	if not _check(bool(fu2.call("choose_melee_chase")), "choose_melee_chase succeeds after slam"): return true
	if not _check(int(p_atk.get("pending_followup_bonus_hits")) == 2, "Defenseless Melee chase grants +2 bonus hits"): return true
	if not _check(bool(p_atk.get("is_flying_to_opponent")), "Melee chase starts flight cleanly"): return true
	p_atk.call("_stop_flight")

	# 7. Option 3 (Fast Super notification & SuperBeamSequenceController defenseless bypass)
	e_def.call("enter_crashed_stamped", p_atk, 1.5)
	p_atk.set("current_ki", 70.0)
	p_atk.call("_start_followup_controller", e_def, 1.2, "fast_sup_test", true)
	var fu3: Node3D = p_atk.get("active_followup_controller") as Node3D
	fu3.call("notify_super_charge_started", "kamehameha")
	if not _check(int(fu3.get("state")) == 6, "notify_super_charge_started puts state in MINI_FAST_SUPER_CHARGE (6)"): return true
	fu3.call("notify_super_fired")
	if not _check(absf(Engine.time_scale - 1.0) < 0.001, "notify_super_fired cleans up time_scale"): return true

	var beam := beam_s.new() as Node3D
	test_scene.add_child(beam)
	beam.call("setup", p_atk, e_def, "Kamehameha", Color(0.2, 0.7, 1.0), 1000.0, 3, Vector3.ZERO)
	if not _check(bool(beam.get("defender_is_defenseless")), "SuperBeam detects defenseless CRASHED defender"): return true
	if not _check(absf(float(beam.get("base_damage")) - 1150.0) < 0.1, "Crashed super damage boosted 1.15x (1000 -> 1150)"): return true
	if not _check(absf(float(beam.get("_reading_pause_timer"))) < 0.01 and absf(float(beam.get("reaction_duration")) - 0.70) < 0.01, "Defenseless Super uses direct 0.70s hit window"): return true
	beam.queue_free()

	# 8. Defender player HUD during 1s intro pause when AI launches player
	p_atk.set("combat_chain_depth", 0)
	p_atk.call("enter_airborne_launched", 12000.0, 1.0, 24.0)
	e_def.set("combat_chain_depth", 0)
	e_def.set("current_ki", 60.0)
	e_def.call("_start_followup_controller", p_atk, 1.0, "ai_launch_test", true)
	var fu_def: Node3D = e_def.get("active_followup_controller") as Node3D
	if not _check(fu_def != null and bool(fu_def.call("is_in_intro_pause")), "Defender follow-up starts in 1s intro pause"): return true
	var d_title: Label3D = fu_def.get("_title_label") as Label3D
	var d_acts: Label3D = fu_def.get("_def_actions_label") as Label3D
	if not _check(d_title != null and ("FUISTE LANZADO" in d_title.text), "Defender HUD announces FUISTE LANZADO"): return true
	if not _check(d_acts != null and ("Z-Vanish" in d_acts.text), "Defender HUD lists defense actions"): return true
	fu_def.call("_finish_sequence", "def_test_done", false)

	Engine.time_scale = 1.0
	test_scene.queue_free()
	print("FOLLOWUP_OVERHAUL_PASSED")
	quit(0)
	return true
