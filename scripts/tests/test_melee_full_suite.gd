extends SceneTree

var _ran: bool = false

func _process(_delta: float) -> bool:
	if _ran:
		quit(1)
		return true
	_ran = true

	var ki_cfg_s: GDScript = load("res://scripts/resources/ki_economy_config.gd") as GDScript
	var lore_s: GDScript = load("res://scripts/MeleeLoreEventController.gd") as GDScript
	var dome_s: GDScript = load("res://scripts/MeleeTargetDome.gd") as GDScript
	var hcc_s: GDScript = load("res://scripts/HybridCombatController.gd") as GDScript
	var ai_s: GDScript = load("res://scripts/CombatAIController.gd") as GDScript
	var char_s: GDScript = load("res://scripts/character_instance.gd") as GDScript
	var dd_s: GDScript = load("res://scripts/DramaticDirector.gd") as GDScript
	var sim_s: GDScript = load("res://scripts/debug/DesktopXRSimulator.gd") as GDScript

	if not (ki_cfg_s and lore_s and dome_s and hcc_s and ai_s and char_s and dd_s and sim_s):
		printerr("FAIL: One or more scripts failed to load/compile.")
		quit(1)
		return true

	# 1. KiEconomyConfig new unified fields
	var cfg: Resource = ki_cfg_s.get_default()
	assert(absf(float(cfg.get("melee_cancel_cost")) - 6.0) < 0.01, "melee_cancel_cost mismatch")
	assert(absf(float(cfg.get("melee_parry_attacker_ki_drain")) - 10.0) < 0.01, "melee_parry_attacker_ki_drain mismatch")
	assert(absf(float(cfg.get("melee_deflect_attacker_ki_drain")) - 4.0) < 0.01, "melee_deflect_attacker_ki_drain mismatch")
	assert(absf(float(cfg.get("melee_yellow_block_ki_cost")) - 4.0) < 0.01, "melee_yellow_block_ki_cost mismatch")
	assert(absf(float(cfg.get("melee_broken_1hand_ki_cost")) - 10.0) < 0.01, "melee_broken_1hand_ki_cost mismatch")
	assert(absf(float(cfg.get("melee_hit_taken_quick_ki_drain")) - 6.0) < 0.01, "melee_hit_taken_quick_ki_drain mismatch")
	assert(absf(float(cfg.get("melee_hit_taken_charged_ki_drain")) - 12.0) < 0.01, "melee_hit_taken_charged_ki_drain mismatch")
	assert(absf(float(cfg.get("melee_hit_taken_heavy_ki_drain")) - 16.0) < 0.01, "melee_hit_taken_heavy_ki_drain mismatch")
	assert(absf(float(cfg.get("melee_flurry_clash_drain_per_sec")) - 5.0) < 0.01, "melee_flurry_clash_drain_per_sec mismatch")
	assert(absf(float(cfg.get("melee_flurry_clash_win_ki_reward")) - 18.0) < 0.01, "melee_flurry_clash_win_ki_reward mismatch")
	assert(absf(float(cfg.get("melee_sonic_burst_hop_cost")) - 6.0) < 0.01, "melee_sonic_burst_hop_cost mismatch")
	assert(absf(float(cfg.get("melee_sim_clash_ki_reward")) - 8.0) < 0.01, "melee_sim_clash_ki_reward mismatch")
	assert(absf(float(cfg.get("melee_sim_guard_x_cost")) - 6.0) < 0.01, "melee_sim_guard_x_cost mismatch")

	var goku_res: Resource = load("res://resources/goku.tres") as Resource
	var vegeta_res: Resource = load("res://resources/vegeta.tres") as Resource
	assert(goku_res != null and vegeta_res != null, "goku.tres / vegeta.tres must load")

	# Build lightweight in-tree XR rig + combatants
	var rig: XROrigin3D = XROrigin3D.new()
	var cam: XRCamera3D = XRCamera3D.new()
	cam.name = "XRCamera3D"
	var l_ctrl: XRController3D = XRController3D.new()
	l_ctrl.name = "LeftHand"
	var r_ctrl: XRController3D = XRController3D.new()
	r_ctrl.name = "RightHand"
	var sim_node: Node = sim_s.new() as Node
	sim_node.name = "DesktopXRSimulator"
	sim_node.set("sim_active", true)
	sim_node.set("v_left_trigger", 1.0)
	sim_node.set("v_left_grip", 1.0)
	sim_node.set("v_right_ax", true)
	sim_node.set("v_right_stick", Vector2(0.0, -1.0))

	var p_mock: Node3D = char_s.new() as Node3D
	p_mock.name = "PlayerCharacterInstance"
	p_mock.set("is_player", true)
	p_mock.set("character_data", goku_res)

	var ai_mock: Node3D = char_s.new() as Node3D
	ai_mock.name = "EnemyCharacterInstance"
	ai_mock.set("is_player", false)
	ai_mock.set("character_data", vegeta_res)

	rig.add_child(cam)
	rig.add_child(l_ctrl)
	rig.add_child(r_ctrl)
	rig.add_child(sim_node)
	rig.add_child(p_mock)
	root.add_child(rig)
	root.add_child(ai_mock)

	p_mock.set_physics_process(false)
	ai_mock.set_physics_process(false)
	var ai_ctrl_mock: Variant = ai_mock.get("cached_ai_controller")
	if ai_ctrl_mock and is_instance_valid(ai_ctrl_mock):
		(ai_ctrl_mock as Node).set_physics_process(false)
		ai_ctrl_mock.set("enabled", false)
	p_mock.set("current_ki", 60.0)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_ki", 60.0)
	ai_mock.set("current_np", 10000.0)

	var dome: Node3D = dome_s.new() as Node3D
	root.add_child(dome)
	dome.call("setup", p_mock, ai_mock, -1.0, 4)

	# 2. Fase 4 checks: DesktopXRSimulator routing + shared meshes + reset_match_static_state
	assert(bool(dome.call("_ctrl_pressed", l_ctrl, &"trigger_click")) == true, "_ctrl_pressed desktop trigger_click failed")
	assert(absf(float(dome.call("_ctrl_float", l_ctrl, &"grip")) - 1.0) < 0.01, "_ctrl_float desktop grip failed")
	assert(bool(dome.call("_ctrl_pressed", r_ctrl, &"ax_button")) == true, "_ctrl_pressed desktop ax_button failed")
	assert(dome.call("_ctrl_vec2", r_ctrl, &"primary") == Vector2(0.0, -1.0), "_ctrl_vec2 desktop stick failed")
	var zones: Array = dome.get("target_zones")
	assert(zones.size() == 6, "Expected 6 target zones")
	assert(zones[0]["box_mesh"].mesh == zones[1]["box_mesh"].mesh, "Zones must share BoxMesh")
	assert(zones[0]["timing_ring"].mesh == zones[2]["timing_ring"].mesh, "Zones must share timing TorusMesh")

	# 3. Deferred Ki & Deferred SONIC_Z_BURST: registering 4 rapid SONICO hits RESERVES 4 * 3 = 12 Ki without deducting upfront
	for i in range(4):
		dome.set("fist_charge_times", [0.0, 0.0])
		dome.call("_register_hit", zones[i], r_ctrl, "RightHand", 1, Vector3(0.0, 0.0, -3.5), 3.5, 0.35)
	assert(absf(float(p_mock.get("current_ki")) - 60.0) < 0.01, "Declaration must reserve Ki without draining attacker upfront (expected 60.0, got %.2f)" % float(p_mock.get("current_ki")))
	assert(absf(float(dome.get("_declared_ki_reserved")) - 12.0) < 0.01, "Reserved Ki must equal 12.0 after 4 declared quick hits")
	assert(bool(dome.get("_declared_full_combo")) == true, "Full combo flag must be latched on 4/4 declared hits")
	assert(bool(dome.get("_sonic_burst_rolled_this_round")) == false, "SONIC_Z_BURST must NOT roll during declaration")
	var lore_ctrl: Node3D = dome.get("_lore_ctrl") as Node3D
	assert(not bool(lore_ctrl.get("is_event_active")), "Lore event must NOT trigger during ATTACK_RECORDING")

	# 4. Defended hit pays hit Ki cost (-3) at defense execution and gives ZERO Ki refund (-4 Ki deflect drain on green hand block)
	dome.call("start_defense_phase")
	var hits_arr: Array = dome.get("hits")
	var ki_before_block: float = float(p_mock.get("current_ki"))
	dome.call("_resolve_hand_block", hits_arr[0], zones[0], 0, "GREEN")
	var exp_atk_after_blk: float = ki_before_block - float(hits_arr[0].get("ki_cost", 3.0)) - float(cfg.get("melee_deflect_attacker_ki_drain"))
	assert(absf(float(p_mock.get("current_ki")) - exp_atk_after_blk) < 0.01, "Deflected hit must charge hit cost + deflect drain with ZERO refund")

	# 5. Unblocked hit pays hit Ki cost (-3) and grants deferred tier_refund (+10 SONICO) -> net +7, and drains defender
	var ki_before_hit: float = float(p_mock.get("current_ki"))
	var ai_ki_before_hit: float = float(ai_mock.get("current_ki"))
	var ai_np_before_hit: float = float(ai_mock.get("current_np"))
	dome.call("_resolve_unblocked_hit", hits_arr[1], zones[1])
	var exp_atk_after_hit: float = ki_before_hit - float(hits_arr[1].get("ki_cost", 3.0)) + float(cfg.get("melee_sonic_ki_refund"))
	assert(absf(float(p_mock.get("current_ki")) - exp_atk_after_hit) < 0.01, "Unblocked SONICO hit must pay hit cost and refund SONICO Ki at execution")
	var ai_bp_lost: float = maxf(ai_np_before_hit - float(ai_mock.get("current_np")), 0.0)
	var expected_ai_ki: float = ai_ki_before_hit - float(cfg.get("melee_hit_taken_quick_ki_drain")) + ai_bp_lost * float(cfg.get("ki_regen_per_bp_lost"))
	assert(absf(float(ai_mock.get("current_ki")) - expected_ai_ki) < 0.05, "Unblocked quick hit Ki drain/regen mismatch (expected %.2f, got %.2f)" % [expected_ai_ki, float(ai_mock.get("current_ki"))])

	# Momentum BONUS check: when < 60% clean hits, evaluate_round_outcome grants 0 momentum bonus
	for h_m in hits_arr:
		if not h_m.get("resolved", false):
			h_m["resolved"] = true
			h_m["defense_score"] = 1.0
	var ki_before_eval_fail: float = float(p_mock.get("current_ki"))
	dome.call("evaluate_round_outcome")
	assert(absf(float(p_mock.get("current_ki")) - ki_before_eval_fail) < 0.01, "Momentum bonus must NOT be granted when mostly blocked")

	# When >= 60% clean hits AND _declared_full_combo == true, evaluate_round_outcome grants +18 Ki AND SONIC_Z_BURST rolls after 3 clean hits
	dome.call("start_attack_phase", p_mock, ai_mock, -1.0, 4)
	for j in range(4):
		dome.call("_register_hit", zones[j], r_ctrl, "RightHand", 1, Vector3(0.0, 0.0, -3.5), 3.5, 0.35)
	dome.call("start_defense_phase")
	var hits_2: Array = dome.get("hits")
	hits_2[3]["tier"] = "SOLIDO"
	for j in range(4):
		if int(dome.get("phase")) != 2: # DomePhase.DEFENSE_RHYTHM == 2
			break
		dome.call("_resolve_unblocked_hit", hits_2[j], zones[j])
	if bool(lore_ctrl.get("is_event_active")):
		lore_ctrl.call("_finish_event", { "action": "complete_normal" })
	for j in range(4):
		if not hits_2[j].get("resolved", false):
			hits_2[j]["resolved"] = true
			hits_2[j]["defense_score"] = 0.0
	assert(bool(dome.get("_sonic_burst_rolled_this_round")) == true or bool(dome.get("_sonic_burst_used_this_dome")) == true, "SONIC_Z_BURST should evaluate after 3+ real clean hits")
	p_mock.set("current_ki", 50.0)
	var ki_pre_mom: float = float(p_mock.get("current_ki"))
	dome.set("_declared_full_combo", true)
	dome.set("_last_lore_event_type", 2)
	dome.call("evaluate_round_outcome")
	assert(absf(float(p_mock.get("current_ki")) - (ki_pre_mom + float(cfg.get("melee_dome_complete_ki_bonus")))) < 0.01, "Momentum +18 Ki must trigger in evaluate_round_outcome on full clean combo")

	# 6. Fase 3 checks: cancel cost on fresh active dome, Goku vs Vegeta Z-Vanish, Furia x2 defensive Ki, launch vectors, block_hit floor, Zenkai 0.30/0.40
	var dome2: Node3D = dome_s.new() as Node3D
	root.add_child(dome2)
	dome2.call("setup", p_mock, ai_mock, -1.0, 4)
	p_mock.set("current_ki", 40.0)
	ai_mock.set("current_ki", 40.0)
	dome2.call("finish_without_hits", true)
	assert(absf(float(p_mock.get("current_ki")) - 34.0) < 0.01, "Manual cancel must cost only melee_cancel_cost (-6 Ki)")
	assert(absf(float(ai_mock.get("current_ki")) - 40.0) < 0.01, "Manual cancel must NOT gift Ki to defender")

	var dome3: Node3D = dome_s.new() as Node3D
	root.add_child(dome3)
	dome3.call("setup", p_mock, ai_mock, -1.0, 4)
	var zv_goku: Dictionary = dome3.call("_get_vanish_cost_and_label", p_mock)
	var zv_veg: Dictionary = dome3.call("_get_vanish_cost_and_label", ai_mock)
	assert(absf(float(zv_goku["cost"]) - 8.0) < 0.01 and "SHUNKAN" in String(zv_goku["label"]), "Goku Shunkan Ido cost/label mismatch")
	assert(absf(float(zv_veg["cost"]) - 10.0) < 0.01 and "ZANZOKEN" in String(zv_veg["label"]), "Vegeta Zanzoken cost/label mismatch")

	ai_mock.set("is_in_furia", true)
	ai_mock.set("current_ki", 20.0)
	dome3.call("_modify_fighter_ki", ai_mock, 10.0, true)
	assert(absf(float(ai_mock.get("current_ki")) - 40.0) < 0.01, "Furia x2 defensive Ki reward failed")
	p_mock.set("is_in_furia", true)
	p_mock.set("current_ki", 20.0)
	dome3.call("_modify_fighter_ki", p_mock, 7.0, false)
	assert(absf(float(p_mock.get("current_ki")) - 27.0) < 0.01, "Offensive refund must NOT double with Furia")

	var v_flank4: Vector3 = dome3.call("_compute_zone_launch_vector", 4, false, 10.0, Vector3.ZERO)
	var v_flank5: Vector3 = dome3.call("_compute_zone_launch_vector", 5, false, 10.0, Vector3.ZERO)
	var v_upper: Vector3 = dome3.call("_compute_zone_launch_vector", 1, false, 10.0, Vector3(0.0, 1.0, 0.0))
	assert(v_flank4.y > 0.0 and v_flank5.y > 0.0, "Flanks 4 & 5 launch must tilt upward (+Y), not downward")
	assert(v_upper.y > 4.0, "Uppercut swing_dir.y > 0.45 must launch strongly upward")

	# Irreversible NP floor on block_hit guard break + Zenkai 0.30/0.40 thresholds
	p_mock.set("is_in_furia", false)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("secured_np_threshold_ratio", 0.50)
	var active_max: float = float(p_mock.call("get_active_max_np"))
	p_mock.set("current_np", active_max * 0.52)
	p_mock.set("current_ki", 0.0)
	p_mock.call("block_hit", 5000.0)
	assert(float(p_mock.get("current_np")) >= active_max * 0.50 - 0.01, "Guard break in block_hit violated irreversible NP floor")

	p_mock.set("is_match_over", false)
	var g_trans: Array = goku_res.get("transformations")
	p_mock.set("current_transformation", g_trans[0] if g_trans.size() > 0 else null)
	p_mock.set("current_np", 6900.0)
	p_mock.call("check_zenkai_conditions", 10000.0) # behind_ratio = 0.31 >= 0.30
	assert(bool(p_mock.get("is_in_furia")) == true, "Furia must trigger at >= 30% behind")
	p_mock.set("is_in_furia", false)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("current_np", 15000.0)
	p_mock.call("check_zenkai_conditions", 9600.0) # lead = 0.36 < 0.40
	assert(bool(p_mock.get("is_in_zenkai_state")) == false, "Dominance Zenkai must NOT trigger at 0.36 (< 0.40)")
	p_mock.set("current_np", 17000.0)
	p_mock.call("check_zenkai_conditions", 10000.0) # lead = 7000/17000 = 0.411 >= 0.40
	assert(bool(p_mock.get("is_in_zenkai_state")) == true, "Dominance Zenkai must trigger at >= 0.40")

	# compute_round_outcome_decision parity check
	var dec_turn: Dictionary = dome_s.compute_round_outcome_decision([1.0, 1.0, 0.0], 1, 4)
	var dec_stay: Dictionary = dome_s.compute_round_outcome_decision([0.5, 0.0, 0.0], 1, 4)
	assert(dec_turn["turnover"] == true and dec_turn["next_attack_hits"] == 4, "compute_round_outcome_decision turnover mismatch")
	assert(dec_stay["turnover"] == false and dec_stay["next_attack_hits"] == 3, "compute_round_outcome_decision continue mismatch")

	# Reset match static state check
	dome3.set("_sim_exchange_cooldown_melees", 2)
	dome3.set("_sonic_burst_cooldown_melees", 3)
	dome3.set("_tutorial_controls_shown", true)
	dome_s.reset_match_static_state()
	assert(int(dome3.get("_sim_exchange_cooldown_melees")) == 0 and int(dome3.get("_sonic_burst_cooldown_melees")) == 0 and bool(dome3.get("_tutorial_controls_shown")) == false, "reset_match_static_state failed")

	# =========================================================================
	# 7. NEW 4 PLAYTEST IMPROVEMENTS VERIFICATION
	# =========================================================================

	# 7.1 Punto 1: Real Jab/Cross/Hook punches vs arm-sweeping + depth retraction
	var ev_sweep: Dictionary = dome_s.evaluate_real_punch_motion(Vector3(2.6, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), 0.30, 0.0, false)
	assert(not bool(ev_sweep["valid"]), "Pure lateral arm sweep must be rejected")
	var ev_diag_shallow: Dictionary = dome_s.evaluate_real_punch_motion(Vector3(2.2, 0.0, -0.5), Vector3(0.0, 0.0, -1.0), 0.30, 0.18, false)
	assert(not bool(ev_diag_shallow["valid"]), "Weak forward velocity during sweep must be rejected")
	var ev_no_thrust: Dictionary = dome_s.evaluate_real_punch_motion(Vector3(0.2, 0.0, -2.5), Vector3(0.0, 0.0, -1.0), 0.25, 0.05, false)
	assert(not bool(ev_no_thrust["valid"]), "Motion with < 0.12m forward stroke must be rejected")
	var ev_jab: Dictionary = dome_s.evaluate_real_punch_motion(Vector3(0.3, 0.1, -2.6), Vector3(0.0, 0.0, -1.0), 0.28, 0.22, false)
	assert(bool(ev_jab["valid"]), "Real forward jab must be accepted")
	var ev_upper: Dictionary = dome_s.evaluate_real_punch_motion(Vector3(0.2, 1.4, -2.1), Vector3(0.0, 0.0, -1.0), 0.30, 0.20, false)
	assert(bool(ev_upper["valid"]), "Real forward uppercut must be accepted")
	assert(not dome_s.should_release_punch_retraction(0.44, 0.42, 0.0), "Lateral shift without depth pullback must NOT release retraction")
	assert(dome_s.should_release_punch_retraction(0.44, 0.30, -1.0), "Real pullback >= 0.13m must release retraction")
	assert(dome_s.should_release_punch_retraction(0.30, 0.22, 0.10), "Returning close to guard <= 0.24m with low vel must release retraction")
	var t_sonic: Dictionary = dome_s.classify_melee_punch_tier(0.32, 3.2, false)
	var t_suave: Dictionary = dome_s.classify_melee_punch_tier(0.22, 1.6, false)
	assert(String(t_sonic["tier"]) == "SONICO" and String(t_suave["tier"]) == "SUAVE", "Speed bonus tiers must remain intact")

	# 7.2 Punto 2: 1-Hand Block requires fresh Trigger, Parry requires Trigger+Grip (with 55ms chord grace)
	assert(dome_s.evaluate_one_hand_defense_input(0.10, false, false, false, false, false, 0.0, 0.0, 1.5, false) == "NONE", "Empty open palm must NOT block")
	assert(dome_s.evaluate_one_hand_defense_input(0.10, true, false, false, false, false, 0.25, 0.0, 0.2, false) == "NONE", "Pre-held Trigger without fresh press buffer must NOT block")
	assert(dome_s.evaluate_one_hand_defense_input(0.45, false, false, false, false, false, 0.0, 0.0, 1.2, false) == "NONE", "Moving hand in Red without button press must NOT cause early_lockout")
	assert(dome_s.evaluate_one_hand_defense_input(0.45, true, false, true, false, false, 0.01, 0.0, 0.2, false) == "EARLY_LOCKOUT", "Pressing Trigger in Red must cause early_lockout")
	assert(dome_s.evaluate_one_hand_defense_input(0.24, true, false, true, false, false, 0.02, 0.0, 0.2, false) == "BLOCK_YELLOW", "Fresh Trigger in Amber must give BLOCK_YELLOW")
	assert(dome_s.evaluate_one_hand_defense_input(0.15, true, false, true, false, false, 0.02, 0.0, 0.2, false) == "BLOCK_GREEN", "Fresh Trigger in Green must give BLOCK_GREEN")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, false, true, false, false, 0.02, 0.0, 0.2, false) == "WAIT_CHORD", "Golden Trigger < 55ms must wait briefly so Grip chord is not stolen")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, true, 0.03, 0.3, 0.4, false) == "PARRY", "Golden Trigger+Grip must trigger PARRY")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, false, true, false, false, 0.06, 0.0, 0.2, false) == "BLOCK_GREEN", "Golden Trigger alone after 55ms chord grace must resolve BLOCK_GREEN")
	assert(dome_s.evaluate_one_hand_defense_input(0.10, true, true, true, true, false, 0.02, 1.9, 2.2, false) == "CLASH", "Fast forward punch with G+T must resolve CLASH")

	# 7.3 Punto 3: Lock AI transforms & dramatic events during active sequences + defer to Free Phase
	p_mock.set("is_knocked_back", false)
	p_mock.set("is_ballistic_launch", false)
	p_mock.set("velocity", Vector3.ZERO)
	ai_mock.set("is_knocked_back", false)
	ai_mock.set("is_ballistic_launch", false)
	ai_mock.set("velocity", Vector3.ZERO)
	p_mock.set("current_transformation", null)
	p_mock.set("current_transformation_index", -1)
	ai_mock.set("current_transformation", null)
	ai_mock.set("current_transformation_index", -1)
	ai_mock.set("is_match_over", false)
	ai_mock.set("_is_limit_break_running", false)
	ai_mock.set("_limit_break_tiers_used", [] as Array[int])
	ai_mock.set("_pending_limit_break_leader", null)
	ai_mock.set("_pending_zenkai_dramatic_source", "")
	ai_mock.set("is_in_bullet_time", false)
	p_mock.set("is_in_bullet_time", true)
	assert(bool(p_mock.call("is_in_active_combat_sequence")) == true, "Player active sequence check failed")
	assert(bool(ai_mock.call("is_in_active_combat_sequence")) == true, "Opponent active sequence check must see player bullet_time")

	var veg_forms: Array = vegeta_res.get("transformations")
	ai_mock.call("unlock_transformation", veg_forms[0].get("form_name"))
	ai_mock.call("transform_to", 0)
	assert(ai_mock.get("current_transformation") == null, "transform_to must be BLOCKED during active sequence")

	# Candado de tier: mientras el líder siga en Base (-1), el perdedor NO despierta SSJ gratis por Limit Break
	p_mock.set("current_transformation", null)
	p_mock.set("current_transformation_index", -1)
	p_mock.set("current_np", 25000.0)
	ai_mock.set("current_np", 10000.0)
	ai_mock.call("check_zenkai_conditions", 25000.0)
	assert(ai_mock.get("_pending_limit_break_leader") == null, "Limit Break must be LOCKED while leader is still in Base (-1)")

	# Cuando el líder ya alcanzó Fase 1 (SSJ = 0), el perdedor sí encola su Despertar Límite diferido
	p_mock.set("current_transformation_index", 0)
	ai_mock.set("current_ki", 30.0)
	ai_mock.call("check_zenkai_conditions", 25000.0)
	assert(ai_mock.get("current_transformation") == null, "Limit break must NOT transform mid-sequence")
	assert(ai_mock.get("_pending_limit_break_leader") == p_mock, "Limit break must queue for Free Phase")

	var mini_s: GDScript = load("res://scripts/DramaticMiniSceneController.gd") as GDScript
	var mini: Node3D = mini_s.new() as Node3D
	root.add_child(mini)
	p_mock.set("is_in_bullet_time", false)
	p_mock.set("is_in_followup_bullet_time", true)
	assert(not bool(mini.call("_is_clean_free_phase", p_mock, ai_mock)), "MiniScene must be blocked during followup_bullet_time")
	p_mock.set("is_in_followup_bullet_time", false)
	assert(bool(mini.call("_is_clean_free_phase", p_mock, ai_mock)), "MiniScene must allow clean Free Phase")

	# Returning to Free Phase settles 0.45s and dispatches queued Limit Break (tope 78% BP líder y +10 Ki)
	ai_mock.call("_tick_deferred_sequence_events", 0.50)
	assert(ai_mock.get("current_transformation") != null, "Queued Limit Break must fire once settled in Free Phase")
	assert(ai_mock.get("_pending_limit_break_leader") == null, "Pending Limit Break queue must clear after dispatch")
	assert(float(ai_mock.get("current_np")) <= 25000.0 * 0.78 + 0.1, "Limit Break catchup must stay capped at <= 78% of leader BP")
	assert(absf(float(ai_mock.get("current_ki")) - 40.0) < 0.01, "Limit Break must grant +10 Ki (30 -> 40)")

	# Explicit allow_during_sequence override works for sequence-specific mechanics
	ai_mock.call("unlock_transformation", veg_forms[1].get("form_name"))
	p_mock.set("is_in_bullet_time", true)
	ai_mock.call("transform_to", 1, true)
	assert(ai_mock.get("current_transformation") == veg_forms[1], "allow_during_sequence=true hook must allow explicit sequence events")
	p_mock.set("is_in_bullet_time", false)

	# 7.4 Punto 4: Ballistic Launch Physics (strong burst -> exponential slow-down -> downward drop, 18m..29m range)
	for launch_cfg in [[28.0, 7.8], [36.0, 8.8]]:
		var v_h0: float = float(launch_cfg[0])
		var v_y0: float = float(launch_cfg[1])
		var pos_sim: Vector3 = Vector3(0.0, 0.85, 0.0)
		var vel_sim: Vector3 = Vector3(0.0, v_y0, -v_h0)
		var dt_sim: float = 1.0 / 60.0
		var v_h_1s: float = -1.0
		var saw_drop: bool = false
		var t_sim: float = 0.0
		while t_sim < 4.0:
			pos_sim += vel_sim * dt_sim
			vel_sim = char_s.step_ballistic_launch_velocity(vel_sim, dt_sim, 1.18, 10.5)
			t_sim += dt_sim
			if v_h_1s < 0.0 and t_sim >= 1.0:
				v_h_1s = Vector2(vel_sim.x, vel_sim.z).length()
			if vel_sim.y < -3.0:
				saw_drop = true
			if pos_sim.y <= 0.0 and t_sim >= 0.08:
				break
		var skid_v: float = Vector2(vel_sim.x, vel_sim.z).length() * 0.65
		var skid_d: float = (skid_v * skid_v) / (2.0 * 9.0)
		var total_dist: float = absf(pos_sim.z) + skid_d
		assert(saw_drop, "Ballistic launch must arc downward and fall (v_y < -3.0)")
		assert(v_h_1s > 0.0 and v_h_1s < v_h0 * 0.40, "Ballistic launch must visibly decelerate (v_h@1s=%.2f vs init=%.2f)" % [v_h_1s, v_h0])
		assert(total_dist >= 18.0 and total_dist <= 29.0, "Ballistic launch total distance must be 18..29m (got %.2fm)" % total_dist)

	# Verify actual launcher function clamps extreme AI BP difference cleanly (not 100+ m/s!)
	p_mock.set("current_np", 90000.0)
	ai_mock.set("current_np", 5000.0)
	p_mock.set("current_ki", 5.0)
	ai_mock.set("global_position", Vector3(0.0, 0.5, -2.0))
	p_mock.call("_execute_charged_v3_or_ki_break_finisher", ai_mock, "ki_break_launch", 4.5, Vector3(0.0, 0.3, -1.0))
	assert(bool(ai_mock.get("is_ballistic_launch")) == true, "Launcher must activate is_ballistic_launch")
	var real_launch_vel: Vector3 = ai_mock.get("velocity") as Vector3
	var real_h_spd: float = Vector2(real_launch_vel.x, real_launch_vel.z).length()
	assert(real_h_spd >= 26.0 and real_h_spd <= 40.0 and real_launch_vel.y >= 6.0, "Launcher speed must be bounded 26..40 m/s with upward arc (got h=%.1f, y=%.1f)" % [real_h_spd, real_launch_vel.y])

	# =========================================================================
	# 8. PLAYTEST 3 FIXES VERIFICATION (Audio, Red Early-Lockout + Amber, Diagonal Launches)
	# =========================================================================
	# 8.1 Audio check: real punch SFX restored, dodge_vanish reserved for Z-Vanish, block_guard on cross-arm guard
	var dome_src: String = FileAccess.get_file_as_string("res://scripts/MeleeTargetDome.gd")
	assert(dome_src.length() > 1000, "Must read MeleeTargetDome.gd source")
	var reg_start: int = dome_src.find("func _register_hit(")
	var reg_end: int = dome_src.find("\nfunc ", reg_start + 10)
	assert(reg_start != -1 and reg_end > reg_start, "Must locate _register_hit")
	var reg_slice: String = dome_src.substr(reg_start, reg_end - reg_start)
	assert("common.melee_hit_heavy" in reg_slice and "common.melee_hit_light" in reg_slice, "_register_hit must play real melee hit SFX")
	assert(not ("common.dodge_vanish" in reg_slice), "_register_hit must not play dodge_vanish")

	var ham_start: int = dome_src.find("func _check_hammer_finisher(")
	var ham_end: int = dome_src.find("\nfunc ", ham_start + 10)
	assert(ham_start != -1 and ham_end > ham_start, "Must locate _check_hammer_finisher")
	var ham_slice: String = dome_src.substr(ham_start, ham_end - ham_start)
	assert("common.melee_hit_heavy" in ham_slice and not ("common.dodge_vanish" in ham_slice), "_check_hammer_finisher must play melee_hit_heavy instead of dodge_vanish")

	var zvan_start: int = dome_src.find("func _resolve_defensive_z_vanish(")
	var zvan_end: int = dome_src.find("\nfunc ", zvan_start + 10)
	assert(zvan_start != -1 and zvan_end > zvan_start, "Must locate _resolve_defensive_z_vanish")
	var zvan_slice: String = dome_src.substr(zvan_start, zvan_end - zvan_start)
	assert("common.dodge_vanish" in zvan_slice and not ("common.block_perfect" in zvan_slice), "_resolve_defensive_z_vanish must play dodge_vanish instead of block_perfect")

	var guard_start: int = dome_src.find("func _resolve_cross_arm_guard(")
	var guard_end: int = dome_src.find("\nfunc ", guard_start + 10)
	assert(guard_start != -1 and guard_end > guard_start, "Must locate _resolve_cross_arm_guard")
	var guard_slice: String = dome_src.substr(guard_start, guard_end - guard_start)
	assert("common.block_guard" in guard_slice, "_resolve_cross_arm_guard must play common.block_guard")

	# 8.2 Early-lockout in Red (> 0.30s) + Amber partial block preserved
	assert(dome_s.evaluate_one_hand_defense_input(0.35, true, false, true, false, false, 0.01, 0.0, 0.2, false) == "EARLY_LOCKOUT", "Red (>0.30s) Trigger press must return EARLY_LOCKOUT")
	assert(dome_s.evaluate_one_hand_defense_input(0.35, false, true, false, true, false, 0.10, 0.0, 0.2, false) == "EARLY_LOCKOUT", "Red (>0.30s) single Grip press must return EARLY_LOCKOUT")
	assert(dome_s.evaluate_one_hand_defense_input(0.24, true, false, true, false, false, 0.01, 0.0, 0.2, false) == "BLOCK_YELLOW", "Amber (0.18..0.30s) Trigger must remain BLOCK_YELLOW partial block")
	assert(dome_s.evaluate_one_hand_defense_input(0.10, true, false, true, false, false, 0.08, 0.0, 0.2, false) == "BLOCK_GREEN", "Green (-0.16..0.18s) Trigger must return BLOCK_GREEN")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, false, true, false, false, 0.01, 0.0, 0.2, false) == "WAIT_CHORD", "Gold Trigger only within chord grace must return WAIT_CHORD")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, false, false, true, 0.01, 0.0, 0.2, false) == "PARRY", "Gold G+T chord with just_guard_active must return PARRY")

	# Live DEFENSE_RHYTHM check: close hands WITHOUT Grips + Trigger press in Red (> 0.30s) must set early_lockout = true
	sim_node.set("sim_active", true)
	sim_node.set("v_left_grip", 0.0)
	sim_node.set("v_right_grip", 0.0)
	sim_node.set("v_left_trigger", 0.0)
	sim_node.set("v_right_trigger", 0.0)
	l_ctrl.global_position = Vector3(-0.08, 1.4, -0.2)
	r_ctrl.global_position = Vector3(0.08, 1.4, -0.2)
	dome3.set("_cached_desktop_sim", sim_node)
	dome3.set("_cached_left_ctrl", l_ctrl)
	dome3.set("_cached_right_ctrl", r_ctrl)
	dome3.set("attacker", ai_mock)
	dome3.set("defender", p_mock)
	var live_def_hits: Array = dome3.get("hits") as Array
	live_def_hits.clear()
	live_def_hits.append({
		"zone_id": 0,
		"name": "Centro",
		"pos": Vector3(0.0, 1.4, -0.4),
		"hand": "RightHand",
		"time_offset": 0.65,
		"power": 1.2,
		"ki_refund": 0.0,
		"is_charged": false,
		"is_charged_v3": false,
		"is_hammer": false,
		"velocity": 2.0,
		"swing_dir": Vector3.FORWARD,
		"defense_score": 0.0,
		"resolved": false
	})
	dome3.call("start_defense_phase")
	assert(not live_def_hits.is_empty(), "start_defense_phase must retain active defense notes")
	live_def_hits[0]["time_offset"] = float(dome3.get("defense_timer")) + 0.45
	live_def_hits[0]["resolved"] = false
	live_def_hits[0]["early_lockout"] = false
	sim_node.set("v_right_trigger", 1.0)
	dome3.call("_process_defense_rhythm", 0.016)
	assert(bool(live_def_hits[0].get("early_lockout", false)) == true, "Pressing Trigger in Red (>0.30s) with close hands and no Grips must trigger early_lockout")
	sim_node.set("v_right_trigger", 0.0)

	# 8.3 Diagonal launch angles (<= 32 deg pitch so finishers are always aimable)
	var clamped_dn: Vector3 = char_s.clamp_launch_angle_diagonal(Vector3(0.0, -30.0, -2.0), 32.0, Vector3(0.0, 0.0, -1.0))
	var clamped_dn_h: float = Vector2(clamped_dn.x, clamped_dn.z).length()
	var clamped_dn_pitch: float = rad_to_deg(atan2(absf(clamped_dn.y), clamped_dn_h))
	assert(clamped_dn_pitch <= 32.5 and clamped_dn_h > absf(clamped_dn.y), "clamp_launch_angle_diagonal must cap pitch <= 32.5 deg (got %.1f)" % clamped_dn_pitch)

	for zv_case in [
		{"id": 1, "ham": true, "dir": Vector3(0.0, -1.0, 0.0), "name": "Hammer"},
		{"id": 1, "ham": false, "dir": Vector3(0.0, 1.0, 0.0), "name": "Uppercut"},
		{"id": 0, "ham": false, "dir": Vector3(0.0, 0.0, -1.0), "name": "Zone0"}
	]:
		var zv: Vector3 = dome3.call("_compute_zone_launch_vector", zv_case["id"], zv_case["ham"], 10.0, zv_case["dir"]) as Vector3
		var zv_h: float = Vector2(zv.x, zv.z).length()
		var zv_pitch: float = rad_to_deg(atan2(absf(zv.y), maxf(zv_h, 0.001)))
		assert(zv_pitch <= 32.5, "%s zone launch vector must be diagonal <= 32.5 deg (got %.1f, v=%s)" % [zv_case["name"], zv_pitch, str(zv)])

	var meteor_pos: Dictionary = lore_s.compute_meteor_smash_positions(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 0.0)
	var m_crater: Vector3 = meteor_pos["crater_ground_pos"] as Vector3
	var m_perch: Vector3 = meteor_pos["post_slam_attacker_pos"] as Vector3
	var m_rel: Vector3 = m_perch - m_crater
	var m_rel_h: float = Vector2(m_rel.x, m_rel.z).length()
	var m_pitch: float = rad_to_deg(atan2(absf(m_rel.y), maxf(m_rel_h, 0.001)))
	assert(Vector2(m_crater.x, m_crater.z).length() >= 12.0, "Meteor Smash crater must project forward diagonally (got %s)" % str(m_crater))
	assert(m_rel_h >= 13.0 and m_pitch <= 25.0, "Meteor Smash attacker perch must be diagonal <= 25 deg (got pitch=%.1f)" % m_pitch)

	ai_mock.set("global_position", Vector3(0.0, 6.0, -2.0))
	p_mock.call("_execute_hammer_strike_finisher", ai_mock, 4.0, [], Vector3.ZERO, true)
	var real_ham_vel: Vector3 = ai_mock.get("velocity") as Vector3
	var real_ham_h: float = Vector2(real_ham_vel.x, real_ham_vel.z).length()
	var real_ham_pitch: float = rad_to_deg(atan2(absf(real_ham_vel.y), maxf(real_ham_h, 0.001)))
	assert(real_ham_h > 1.0 and real_ham_pitch <= 32.5, "Hammer finisher launch must be diagonal <= 32.5 deg (got pitch=%.1f, vel=%s)" % [real_ham_pitch, str(real_ham_vel)])
	p_mock.set("current_ki", 60.0)

	# =========================================================================
	# 9. FIST CLASH OVERHAUL VERIFICATION (3 Systems Unified & Refined)
	# =========================================================================
	# 9.1 KiEconomyConfig clash fields
	assert(absf(float(cfg.get("melee_clash_even_ki_reward")) - 6.0) < 0.01, "melee_clash_even_ki_reward must be 6.0")
	assert(int(cfg.get("melee_sim_clashes_to_flurry")) == 3, "melee_sim_clashes_to_flurry must be 3")
	assert(absf(float(cfg.get("melee_sim_clash_flurry_chance")) - 0.45) < 0.01, "melee_sim_clash_flurry_chance must be 0.45")
	assert(absf(float(cfg.get("melee_flurry_clash_trigger_chance")) - 0.45) < 0.01, "melee_flurry_clash_trigger_chance must be 0.45")

	# 9.2 Input separation & Red winding exclusion
	assert(dome_s.is_hand_winding_clash_in_red(true, false, 0.50, 0.0, false) == true, "Closed grip far from zone in Red must be allowed as clash windup")
	assert(dome_s.is_hand_winding_clash_in_red(true, true, 0.20, -0.80, false) == true, "Retracting G+T fist in Red must be allowed as clash windup")
	assert(dome_s.is_hand_winding_clash_in_red(false, true, 0.20, 0.0, false) == false, "Trigger-only press in Red must NOT count as clash windup")
	assert(dome_s.evaluate_one_hand_defense_input(0.08, true, true, true, true, true, 0.02, 1.4, 2.0, false) == "CLASH", "Fast forward G+T punch must prioritize CLASH over PARRY")
	assert(dome_s.evaluate_one_hand_defense_input(0.08, true, true, true, true, true, 0.02, 0.4, 0.5, false) == "PARRY", "Stationary G+T in Gold window must resolve PARRY")
	assert(dome_s.evaluate_one_hand_defense_input(0.22, true, true, true, true, false, 0.02, 0.2, 0.3, false) == "BLOCK_YELLOW", "Slow G+T in Amber must degrade cleanly to BLOCK_YELLOW")
	assert(dome_s.evaluate_one_hand_defense_input(0.08, true, true, true, true, false, 0.02, 2.0, 2.5, true) != "CLASH", "Hammer strike must NOT allow CLASH")

	# Live Red windup check: far closed fist (Grip+Trigger > 0.34m from zone) in Red must NOT set early_lockout
	sim_node.set("sim_active", true)
	sim_node.set("v_left_grip", 0.0)
	sim_node.set("v_right_grip", 0.0)
	sim_node.set("v_left_trigger", 0.0)
	sim_node.set("v_right_trigger", 0.0)
	l_ctrl.global_position = Vector3(-0.70, 1.4, 0.45)
	r_ctrl.global_position = Vector3(0.70, 1.4, 0.45)
	live_def_hits.clear()
	live_def_hits.append({
		"zone_id": 0,
		"name": "Centro",
		"pos": Vector3(0.0, 1.4, -0.4),
		"hand": "RightHand",
		"time_offset": 0.65,
		"power": 1.2,
		"ki_refund": 0.0,
		"is_charged": false,
		"is_charged_v3": false,
		"is_hammer": false,
		"velocity": 2.0,
		"swing_dir": Vector3.FORWARD,
		"defense_score": 0.0,
		"resolved": false
	})
	dome3.call("start_defense_phase")
	live_def_hits[0]["time_offset"] = float(dome3.get("defense_timer")) + 0.45
	live_def_hits[0]["resolved"] = false
	live_def_hits[0]["early_lockout"] = false
	sim_node.set("v_right_grip", 1.0)
	sim_node.set("v_right_trigger", 1.0)
	dome3.call("_process_defense_rhythm", 0.016)
	assert(bool(live_def_hits[0].get("early_lockout", false)) == false, "Far closed fist (G+T) winding up in Red must NOT trigger early_lockout")
	sim_node.set("v_right_grip", 0.0)
	sim_node.set("v_right_trigger", 0.0)

	# 9.3 FIST_FLURRY_CLASH: physical closed-fist forward punches, symmetric BP, Goku drain passive, HUD & Comeback Zenkai
	assert(lore_s.evaluate_flurry_clash_punch(Vector3(0.0, 0.0, -2.5), Vector3(0.0, 0.0, -1.0), false, 0.2) == false, "Open hand must be rejected in FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_flurry_clash_punch(Vector3(2.5, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), true, 0.2) == false, "Lateral waggle must be rejected in FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_flurry_clash_punch(Vector3(0.0, 0.0, 2.5), Vector3(0.0, 0.0, -1.0), true, 0.2) == false, "Backward pullback must be rejected in FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_flurry_clash_punch(Vector3(0.0, 0.0, -1.8), Vector3(0.0, 0.0, -1.0), true, 0.3) == true, "Closed-fist forward punch near orb must count in FIST_FLURRY_CLASH")

	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "fist_clash", "atk_ki": 20.0, "def_ki": 20.0, "bp_ratio": 0.66}) == 0, "bp_ratio 0.66 must NOT trigger FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "fist_clash", "atk_ki": 20.0, "def_ki": 20.0, "bp_ratio": 0.70}) == 1, "bp_ratio 0.70 must trigger FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "fist_clash", "atk_ki": 20.0, "def_ki": 20.0, "bp_ratio": 1.43}) == 1, "bp_ratio 1.43 must trigger FIST_FLURRY_CLASH")
	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "fist_clash", "atk_ki": 20.0, "def_ki": 20.0, "bp_ratio": 1.48}) == 0, "bp_ratio 1.48 must NOT trigger FIST_FLURRY_CLASH")

	assert(absf(lore_s.compute_flurry_clash_ki_drain_rate(5.0, "Goku", true, "") - 3.5) < 0.01, "Goku in Furia must drain 3.5 Ki/s (-30%)")
	assert(absf(lore_s.compute_flurry_clash_ki_drain_rate(5.0, "Goku", false, "Kaioken") - 3.5) < 0.01, "Goku in Kaioken must drain 3.5 Ki/s (-30%)")
	assert(absf(lore_s.compute_flurry_clash_ki_drain_rate(5.0, "Vegeta", true, "") - 5.0) < 0.01, "Vegeta Furia keeps base Ki drain rate (gets push x1.15 instead)")

	Engine.time_scale = 0.1
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	p_mock.set("current_np", 6500.0)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("is_match_over", false)
	ai_mock.set("is_match_over", false)
	p_mock.set("is_in_furia", true)
	p_mock.set("is_in_zenkai_state", false)
	dome3.set("is_active", true)
	dome3.set("attacker", ai_mock)
	dome3.set("defender", p_mock)
	dome3.set("_last_lore_event_type", 0)
	dome3.call("_start_lore_event", 1, "fist_clash")
	assert(absf(Engine.time_scale - 1.0) < 0.01, "_start_lore_event must reset residual hit-stop time_scale to 1.0")
	var hud_anc: Node3D = dome3.get("melee_hud_anchor") as Node3D
	var hdr_lbl: Label3D = dome3.get("header_label") as Label3D
	assert(hud_anc != null and hud_anc.visible == true, "Ki bar anchor (melee_hud_anchor) must stay visible during LORE_EVENT")
	assert(hdr_lbl != null and hdr_lbl.visible == false, "Header text must hide during LORE_EVENT so Ki bar does not overlap")
	var lore_3: Node3D = dome3.get("_lore_ctrl") as Node3D
	assert(bool(lore_3.get("is_event_active")) and int(lore_3.get("active_event_type")) == 1, "FIST_FLURRY_CLASH must be active on dome3")
	lore_3.call("_resolve_fist_clash_winner", p_mock, ai_mock, 0.80)
	assert(bool(p_mock.get("is_in_zenkai_state")) == true, "Winning FIST_FLURRY_CLASH while in Furia must trigger Comeback Zenkai")
	Engine.time_scale = 1.0
	p_mock.set("is_in_furia", false)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("is_comeback_zenkai", false)
	p_mock.set("zenkai_source", "")

	# 9.4 SIMULTANEOUS_EXCHANGE clash rewards, surprise probability, cooldown & escalation
	var dome_src_2: String = FileAccess.get_file_as_string("res://scripts/MeleeTargetDome.gd")
	assert("elif s_act == \"CLASH\":" in dome_src_2, "SIMULTANEOUS_EXCHANGE DEFEND must handle CLASH")
	assert("_set_single_zone_shape(zone, \"CLASH\" if is_clash_spot else role)" in dome_src_2, "SIMULTANEOUS_EXCHANGE visuals must use CLASH hybrid shape")

	assert(dome_s.should_trigger_individual_flurry_clash(0.20, 0.45, 2) == false, "Individual flurry must be blocked during cooldown")
	assert(dome_s.should_trigger_individual_flurry_clash(0.20, 0.45, 0) == true, "Individual flurry must trigger when roll < chance and cooldown == 0")
	assert(dome_s.should_trigger_individual_flurry_clash(0.60, 0.45, 0) == false, "Individual flurry must NOT trigger when roll >= chance")
	assert(dome_s.should_trigger_sim_flurry_clash(2, 3, 0.10, 0.45, 0) == false, "Sim flurry must NOT trigger below threshold (2 < 3)")
	assert(dome_s.should_trigger_sim_flurry_clash(3, 3, 0.40, 0.45, 0) == true, "Sim flurry at clash #3 passes when roll < 0.45")
	assert(dome_s.should_trigger_sim_flurry_clash(3, 3, 0.50, 0.45, 0) == false, "Sim flurry at clash #3 rejects when roll >= 0.45")
	assert(dome_s.should_trigger_sim_flurry_clash(4, 3, 0.65, 0.45, 0) == true, "Sim flurry at clash #4 scales chance up to 0.70")
	assert(dome_s.should_trigger_sim_flurry_clash(4, 3, 0.10, 0.45, 1) == false, "Sim flurry must be blocked while cooldown > 0")

	dome_s.reset_match_static_state()
	var dome4: Node3D = dome_s.new() as Node3D
	root.add_child(dome4)
	dome4.call("setup", p_mock, ai_mock, -1.0, 4)
	p_mock.set("current_ki", 40.0)
	ai_mock.set("current_ki", 40.0)
	p_mock.set("is_in_furia", false)
	ai_mock.set("is_in_furia", false)
	dome4.call("start_simultaneous_exchange")
	var p_ki_sim_pre: float = float(p_mock.get("current_ki"))
	var ai_ki_sim_pre: float = float(ai_mock.get("current_ki"))
	var esc1: bool = bool(dome4.call("_resolve_simultaneous_clash", p_mock, ai_mock, Vector3.ZERO, 0.01))
	assert(esc1 == false and int(dome4.get("_sim_clash_count")) == 1, "Clash #1 increments counter without escalating even on low roll")
	assert(absf(float(p_mock.get("current_ki")) - (p_ki_sim_pre + 8.0)) < 0.01 and absf(float(ai_mock.get("current_ki")) - (ai_ki_sim_pre + 8.0)) < 0.01, "Simultaneous clash must give clean symmetric +8 Ki to both fighters")
	var esc2: bool = bool(dome4.call("_resolve_simultaneous_clash", p_mock, ai_mock, Vector3.ZERO, 0.01))
	assert(esc2 == false and int(dome4.get("_sim_clash_count")) == 2, "Clash #2 no longer escalates automatically (threshold = 3)")
	var esc3: bool = bool(dome4.call("_resolve_simultaneous_clash", p_mock, ai_mock, Vector3.ZERO, 0.80))
	assert(esc3 == false and int(dome4.get("_sim_clash_count")) == 3, "Clash #3 with high roll (0.80 >= 0.45) stays unpredictable")
	var esc4: bool = bool(dome4.call("_resolve_simultaneous_clash", p_mock, ai_mock, Vector3.ZERO, 0.10))
	assert(esc4 == true and int(dome4.get("_sim_clash_count")) == 4, "Clash #4 with low roll (0.10 < 0.70) escalates to FIST_FLURRY_CLASH")
	assert(int(dome4.get("phase")) == int(dome_s.DomePhase.LORE_EVENT), "Simultaneous escalation must transition dome to LORE_EVENT")
	assert(int(dome4.get("_flurry_clash_cooldown_melees")) == 2, "FIST_FLURRY_CLASH launch must set 2-melee surprise cooldown")
	var lore_4: Node3D = dome4.get("_lore_ctrl") as Node3D
	assert(lore_4 != null and bool(lore_4.get("is_event_active")) and int(lore_4.get("active_event_type")) == 1, "Simultaneous escalation must launch FIST_FLURRY_CLASH")
	lore_4.call("_finish_event", { "action": "separate" })
	dome_s.reset_match_static_state()

	# 10. Melee Lore Events Overhaul + Unified Anti-Snowball BP System
	assert(absf(float(cfg.get("melee_meteor_smash_chance")) - 0.55) < 0.01, "melee_meteor_smash_chance mismatch")
	assert(absf(float(cfg.get("melee_meteor_smash_v3_chance")) - 0.75) < 0.01, "melee_meteor_smash_v3_chance mismatch")
	assert(absf(float(cfg.get("melee_z_vanish_war_chance")) - 0.50) < 0.01, "melee_z_vanish_war_chance mismatch")
	assert(absf(float(cfg.get("melee_guard_break_chance")) - 0.55) < 0.01, "melee_guard_break_chance mismatch")
	assert(int(cfg.get("melee_lore_event_cooldown_melees")) == 2, "melee_lore_event_cooldown_melees mismatch")

	# 10.1 Anti-Snowball compute_melee_bp_profile across 5 bands, Furia, match_trans_scale, comeback momentum
	var prof_ab_q: Dictionary = char_s.compute_melee_bp_profile(5000.0, 12000.0, false, false, 1.0, 1.0, false)
	var prof_ab_h: Dictionary = char_s.compute_melee_bp_profile(5000.0, 12000.0, false, true, 1.0, 1.0, false)
	assert(absf(float(prof_ab_q["dmg_mult"]) - 0.40) < 0.01 and absf(float(prof_ab_h["dmg_mult"]) - 0.70) < 0.01, "Abysmal band must floor quick=0.40, heavy=0.70")
	assert(absf(float(prof_ab_q["bp_gain_mult"]) - 1.55) < 0.01 and absf(float(prof_ab_q["def_time_mult"]) - 1.35) < 0.01, "Abysmal underdog attacker must earn 1.55x BP")
	var prof_fur_h: Dictionary = char_s.compute_melee_bp_profile(5000.0, 10000.0, true, true, 1.0, 1.0, false)
	assert(absf(float(prof_fur_h["effective_ratio"]) - 0.80) < 0.01, "Furia heavy attack must add +0.30 to effective_ratio")
	var prof_eq: Dictionary = char_s.compute_melee_bp_profile(10000.0, 10000.0, false, false, 1.0, 1.0, false)
	assert(absf(float(prof_eq["damage_scale"]) - 1.00) < 0.02 and absf(float(prof_eq["def_time_mult"]) - 1.02) < 0.03, "1:1 ratio must stay ~1.00 baseline")
	var prof_dom: Dictionary = char_s.compute_melee_bp_profile(24000.0, 10000.0, false, true, 2.0, 1.0, false)
	assert(float(prof_dom["dmg_mult"]) <= 1.451 and absf(float(prof_dom["bp_gain_mult"]) - 0.60) < 0.01, "Dominance must cap dmg_mult <= 1.45 and throttle leader bp_gain_mult to 0.60")
	assert(absf(float(prof_dom["def_time_mult"]) - 0.78) < 0.01 and absf(float(prof_dom["defender_underdog_bp_mult"]) - 1.35) < 0.01, "Dominance must keep VR floor 0.78 and max defender underdog reward 1.35")
	assert(absf(float(prof_dom["match_trans_scale"]) - (1.0 + (sqrt(2.0) - 1.0) * 0.45)) < 0.01, "Shared geometric trans_scale must temper SSJ vs Base gap")
	var prof_ssj2: Dictionary = char_s.compute_melee_bp_profile(30000.0, 30000.0, false, false, 2.0, 2.0, false)
	assert(absf(float(prof_ssj2["match_trans_scale"]) - 1.45) < 0.01, "SSJ vs SSJ shared trans_scale must be 1.45")
	var prof_cm: Dictionary = char_s.compute_melee_bp_profile(4000.0, 12000.0, false, true, 1.0, 1.0, true)
	assert(float(prof_cm["effective_ratio"]) >= 0.95, "Comeback momentum must raise eff_r >= 0.95")

	# 10.2 Fair winner unlocks (68%), attack count comeback override, 1.35x resistance Ki regen
	p_mock.set("current_transformation", null)
	p_mock.set("current_transformation_index", -1)
	ai_mock.set("current_transformation", null)
	ai_mock.set("current_transformation_index", -1)
	p_mock.set("current_np", 5000.0)
	ai_mock.set("current_np", 12000.0)
	assert(int(p_mock.call("calculate_melee_attack_count", p_mock, ai_mock, false)) == 3, "Underdog without momentum gets 3 hits")
	assert(int(p_mock.call("calculate_melee_attack_count", p_mock, ai_mock, true)) == 4, "Comeback momentum ignores -1 underdog hit penalty")

	var p_unlocked_fresh: Array[String] = []
	p_mock.set("unlocked_transformations", p_unlocked_fresh)
	var goku_max_np: float = float(goku_res.get("max_np"))
	p_mock.set("current_np", goku_max_np * 0.69)
	p_mock.call("_check_transformation_unlocks")
	assert(bool(p_mock.call("is_transformation_unlocked", "SSJ")), "Winner reaching 68% BP must unlock SSJ earlier than before")

	var ai_unlocked_fresh: Array[String] = []
	ai_mock.set("unlocked_transformations", ai_unlocked_fresh)
	p_mock.set("current_np", 16000.0)
	p_mock.set("current_transformation", null)
	p_mock.set("current_transformation_index", -1)
	ai_mock.set("current_np", 8000.0)
	ai_mock.set("is_in_furia", true)
	ai_mock.call("_check_transformation_unlocks")
	assert(not bool(ai_mock.call("is_transformation_unlocked", "SSJ")), "Losing fighter in Furia must NOT unlock SSJ via shortcut while leader is Base")
	ai_mock.set("is_in_furia", false)

	ai_mock.set("current_ki", 20.0)
	ai_mock.set("current_np", 8000.0)
	p_mock.set("current_np", 16000.0)
	ai_mock.call("_regen_ki_from_damage", 1000.0)
	var ki_underdog_regen: float = float(ai_mock.get("current_ki")) - 20.0
	ai_mock.set("current_ki", 20.0)
	ai_mock.set("current_np", 16000.0)
	ai_mock.call("_regen_ki_from_damage", 1000.0)
	var ki_even_regen: float = float(ai_mock.get("current_ki")) - 20.0
	assert(absf(ki_underdog_regen / maxf(ki_even_regen, 0.001) - 1.35) < 0.05, "Underdog >=15% behind must get 1.35x resistance Ki regen on hit")

	# 10.3 Surprise lore helpers, _resync_unresolved_defense_notes, Z-Vanish real +120 BP, Parry underdog punish + comeback, real separation
	assert(dome_s.should_trigger_surprise_lore_event(0.20, 0.55, 2) == false, "Lore surprise blocked while cooldown > 0")
	assert(dome_s.should_trigger_surprise_lore_event(0.20, 0.55, 0) == true, "Lore surprise fires when roll < chance and cd == 0")
	assert(dome_s.should_trigger_surprise_lore_event(0.60, 0.55, 0) == false, "Lore surprise does not fire when roll >= chance")

	dome_s.reset_match_static_state()
	var dome5: Node3D = dome_s.new() as Node3D
	root.add_child(dome5)
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	p_mock.set("current_np", 8000.0)
	ai_mock.set("current_np", 16000.0)
	p_mock.set("is_in_furia", false)
	ai_mock.set("is_in_furia", false)
	dome5.call("setup", ai_mock, p_mock, -1.0, 4)

	var zvan_note: Dictionary = { "zone_id": 1, "resolved": false, "prewarn_sec": 0.9, "time_offset": 1.2, "is_charged": false, "is_charged_v3": false, "is_hammer": false }
	var pending_note: Dictionary = { "zone_id": 2, "resolved": false, "prewarn_sec": 0.9, "time_offset": 1.1, "is_charged": false, "is_charged_v3": false, "is_hammer": false }
	dome5.set("hits", [zvan_note, pending_note])
	dome5.set("defense_timer", 1.0)
	var np_before_zv: float = float(p_mock.get("current_np"))
	dome5.call("_resolve_defensive_z_vanish", zvan_note, dome5.get("target_zones")[1])
	assert(float(p_mock.get("current_np")) > np_before_zv + 110.0, "_resolve_defensive_z_vanish must actually grant >=120 underdog-scaled BP to defender")
	if dome5.get("_lore_ctrl") and bool(dome5.get("_lore_ctrl").get("is_event_active")):
		dome5.get("_lore_ctrl").call("_finish_event", { "action": "complete_normal" })

	dome5.call("_resync_unresolved_defense_notes", 0.70)
	assert(float(pending_note.get("time_offset")) - float(dome5.get("defense_timer")) >= 0.699, "_resync_unresolved_defense_notes must push tight note >= 0.70s ahead")

	# Parry on underdog defender punishes attacker BP and preserves comeback momentum across restart_as_attacker(true)
	p_mock.set("current_np", 8000.0)
	ai_mock.set("current_np", 16000.0)
	var ai_bp_pre_parry: float = float(ai_mock.get("current_np"))
	var parry_note: Dictionary = { "zone_id": 1, "resolved": false, "prewarn_sec": 0.9, "time_offset": 2.0, "is_charged": false, "is_charged_v3": false, "is_hammer": false }
	dome5.set("attacker", ai_mock)
	dome5.set("defender", p_mock)
	dome5.set("hits", [parry_note])
	dome5.call("_resolve_perfect_parry", parry_note, dome5.get("target_zones")[1])
	assert(float(ai_mock.get("current_np")) < ai_bp_pre_parry - 150.0, "Underdog Perfect Parry must punish overconfident leader BP")
	assert(bool(dome5.get("_comeback_momentum_active")) == true and dome5.get("attacker") == p_mock, "Underdog Perfect Parry must activate comeback momentum on turnover")
	dome5.call("_close_dome_with_separation", 11.4, "Kiai custom test")
	assert(absf(float(dome5.get("_custom_separation_dist")) - 11.4) < 0.01 and String(dome5.get("_custom_separation_reason")) == "Kiai custom test", "_close_dome_with_separation must store real separation distance and reason")

	# 10.4 Sonic Z-Burst anti-waggle, trigger evaluations, 0-Ki Guard Break escape & dual-side Sonic Z-Burst
	assert(lore_s.evaluate_sonic_burst_punch(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -1.0), false, 0.15) == false, "Sonic burst punch must reject open hand")
	assert(lore_s.evaluate_sonic_burst_punch(Vector3(3.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), true, 0.15) == false, "Sonic burst punch must reject sideways wrist waggle")
	assert(lore_s.evaluate_sonic_burst_punch(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -1.0), true, 0.25) == true, "Sonic burst punch must accept crisp forward fist")
	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "z_vanish", "atk_ki": 8.5, "vanish_cost": 8.0, "bp_ratio": 1.0}) == 3, "Goku 8 Ki Shunkan Ido cost must be honored in z_vanish gate")
	assert(lore_s.evaluate_lore_event_trigger({"trigger_source": "guard_abuse", "consecutive_guard_x": 1, "def_ki": 24.0, "bp_ratio": 2.0}) == 4, "Dominance Guard Abuse must trigger at 1 guard when bp_ratio >= 1.8 and def_ki <= 26")

	var dome6: Node3D = dome_s.new() as Node3D
	root.add_child(dome6)
	p_mock.set("current_np", 9000.0)
	ai_mock.set("current_np", 18000.0)
	p_mock.set("current_ki", 2.0)
	ai_mock.set("current_ki", 50.0)
	dome6.call("setup", ai_mock, p_mock, -1.0, 4)
	var lore_6: Node3D = dome6.get("_lore_ctrl") as Node3D
	# Guard Pressure Break 0-Ki emergency deflect escape
	assert(bool(lore_6.call("start_event", 4, dome6, ai_mock, p_mock)) == true, "GUARD_PRESSURE_BREAK must start")
	lore_6.set("_event_timer", 0.35)
	var gb_outcome: Array = []
	lore_6.connect("lore_event_finished", func(_ev: int, out: Dictionary): gb_outcome.append(out), CONNECT_ONE_SHOT)
	lore_6.call("process_event", 0.01, l_ctrl, r_ctrl, Vector3(0.0, 2.2, 0.0), Vector3.ZERO)
	assert(gb_outcome.size() == 1 and String(gb_outcome[0].get("action", "")) == "separate", "0-Ki Guard Pressure Break final-window open-hand swipe must escape via Desperate Deflect")
	assert(float(p_mock.get("current_ki")) >= 9.5, "Desperate Deflect must grant +8 Ki recovery")

	# SONIC_Z_BURST works when AI attacks player (not restricted to is_player anymore!) & 3/3 bonus pays in dome
	p_mock.set("current_ki", 0.0) # zero Ki prevents accidental Z-Vanish; tests AI hop landing cleanly
	ai_mock.set("current_ki", 60.0)
	assert(bool(lore_6.call("start_event", 6, dome6, ai_mock, p_mock)) == true, "SONIC_Z_BURST must start cleanly for AI attacker")
	lore_6.set("_burst_hop_timer", 0.0)
	lore_6.call("process_event", 0.01, l_ctrl, r_ctrl, Vector3.ZERO, Vector3.ZERO)
	assert(int(lore_6.get("_burst_hits")) == 1, "AI SONIC_Z_BURST must land hop #1 on timeout")
	lore_6.set("_burst_hop_timer", 0.0)
	lore_6.call("process_event", 0.01, l_ctrl, r_ctrl, Vector3.ZERO, Vector3.ZERO)
	lore_6.set("_burst_hop_timer", 0.0)
	var sb_outcomes: Array = []
	lore_6.connect("lore_event_finished", func(_ev: int, out: Dictionary): sb_outcomes.append(out), CONNECT_ONE_SHOT)
	lore_6.call("process_event", 0.01, l_ctrl, r_ctrl, Vector3.ZERO, Vector3.ZERO)
	assert(sb_outcomes.size() == 1 and String(sb_outcomes[0].get("action", "")) == "launch" and int(sb_outcomes[0].get("hits", 0)) == 3, "AI SONIC_Z_BURST 3/3 must finish with launch and hits=3")

	dome6.set("is_active", true)
	dome6.set("attacker", p_mock)
	dome6.set("defender", ai_mock)
	p_mock.set("current_ki", 40.0)
	dome6.call("_on_lore_event_finished", 6, { "action": "launch", "victim": ai_mock, "hits": 3 })
	assert(absf(float(p_mock.get("current_ki")) - 50.0) < 0.01, "SONIC_Z_BURST 3/3 finish in dome must grant +10 Ki bonus")

	# Explosive wave BP separation scaling
	p_mock.set("current_ki", 40.0)
	p_mock.set("current_np", 24000.0)
	ai_mock.set("current_np", 10000.0)
	assert(bool(lore_6.call("start_event", 5, dome6, ai_mock, p_mock)) == true, "EXPLOSIVE_WAVE must start")
	var sep_kiai_val: float = float(lore_6.get("_kiai_sep_dist"))
	assert(sep_kiai_val >= 11.5 and sep_kiai_val <= 13.5, "Stronger defender Kiai separation distance must scale up toward 13.5m")
	lore_6.call("_finish_event", { "action": "separate", "distance": sep_kiai_val })
	dome_s.reset_match_static_state()

	# ========================================================================
	# 11. MATRIZ TÁCTICA V3: ICONOS, JABS SIN INTENCIÓN, GUARDIA TORTUGA X,
	#     Z-VANISH EXCLUSIVO PARA MARTILLO, SIN PARRY/CHOQUE VS RÁPIDOS Y V3 LAUNCH
	# ========================================================================
	assert(absf(float(cfg.get("melee_guard_v3_cost")) - 10.0) < 0.01, "V3 Guard X containment cost must be 10 Ki")
	assert(absf(float(cfg.get("melee_clean_hit_ki_refund")) - 8.0) < 0.01, "Nv1 Solido clean Ki refund must be 8 Ki")
	assert(absf(float(cfg.get("melee_sonic_ki_refund")) - 10.0) < 0.01, "Nv1 Sonico clean Ki refund must be 10 Ki")
	assert(absf(float(cfg.get("melee_charged_clean_ki_refund")) - 2.0) < 0.01, "Nv2 Cargado clean Ki refund must be 2 Ki")
	assert(absf(float(cfg.get("melee_guard_turtle_quick_ki_gain")) - 6.0) < 0.01, "Turtle Guard X quick Ki gain must be +6")
	assert(absf(float(cfg.get("melee_guard_turtle_charged_ki_gain")) - 10.0) < 0.01, "Turtle Guard X charged Ki gain must be +10")

	var t_sonic_v3: Dictionary = dome_s.classify_melee_punch_tier(0.35, 3.1, false)
	var t_solid_v3: Dictionary = dome_s.classify_melee_punch_tier(0.28, 2.2, false)
	var t_soft_v3: Dictionary = dome_s.classify_melee_punch_tier(0.18, 1.4, false)
	var t_chg_v3: Dictionary = dome_s.classify_melee_punch_tier(0.32, 2.5, true)
	assert(String(t_sonic_v3.get("tier")) == "SONICO" and absf(float(t_sonic_v3.get("ki_refund")) - 10.0) < 0.01, "Nv1 Sonico must refund +10 Ki")
	assert(String(t_solid_v3.get("tier")) == "SOLIDO" and absf(float(t_solid_v3.get("ki_refund")) - 8.0) < 0.01, "Nv1 Solido must refund +8 Ki")
	assert(String(t_soft_v3.get("tier")) == "SUAVE" and absf(float(t_soft_v3.get("ki_refund")) - 4.0) < 0.01, "Nv1 Suave must refund +4 Ki")
	assert(absf(float(t_chg_v3.get("ki_refund")) - 2.0) < 0.01, "Nv2 Cargado must refund +2 Ki")

	# Z-Vanish allowed ONLY for Cargado Nv2, V3, or Hammer (never Nv1 rapid)
	assert(dome_s.can_z_vanish_attack(false, false, false) == false, "Z-Vanish must be blocked on Nv1 rapid attacks")
	assert(dome_s.can_z_vanish_attack(true, false, false) == true, "Z-Vanish must be allowed on Nv2 Charged")
	assert(dome_s.can_z_vanish_attack(true, true, false) == true, "Z-Vanish must be allowed on Nv3 V3")
	assert(dome_s.can_z_vanish_attack(false, false, true) == true, "Z-Vanish must be allowed on Hammer")

	# One-Hand Matrix: Hammer unblockable; Nv1 blocks Parry/Clash & allows Trigger 1M; Heavy allows Parry/Clash
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, false, true, false, false, 0.2, 0.1, 0.2, true, true) == "HAMMER_UNBLOCKABLE", "Hammer must reject 1-Hand Trigger block")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, true, 0.05, 0.2, 0.5, true, true) == "HAMMER_UNBLOCKABLE", "Hammer must reject Parry")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, false, 0.1, 1.8, 2.2, true, true) == "HAMMER_UNBLOCKABLE", "Hammer must reject Fist Clash")
	assert(dome_s.is_hand_winding_clash_in_red(true, true, 0.5, -0.5, false, false) == false, "Nv1 rapid must not wind up Clash")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, true, 0.05, 0.2, 0.5, false, false) == "NO_PARRY_QUICK", "Nv1 rapid must disallow Parry")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, false, 0.1, 1.8, 2.2, false, false) == "NO_PARRY_QUICK", "Nv1 rapid must disallow Clash")
	assert(dome_s.evaluate_one_hand_defense_input(0.08, true, false, true, false, false, 0.02, 0.1, 0.2, false, false) == "BLOCK_GREEN", "Nv1 rapid Trigger must block cleanly with 1 Hand without waiting for Parry chord")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, true, 0.05, 0.2, 0.5, false, true) == "PARRY", "Heavy Nv2/V3 must allow Parry")
	assert(dome_s.evaluate_one_hand_defense_input(0.05, true, true, true, true, false, 0.1, 1.8, 2.2, false, true) == "CLASH", "Heavy Nv2/V3 must allow Fist Clash")

	# Visual attack metadata & zone step_label icons
	var meta_soft: Dictionary = dome_s.get_attack_visual_meta({ "tier": "SUAVE" })
	var meta_q: Dictionary = dome_s.get_attack_visual_meta({ "tier": "SOLIDO" })
	var meta_c: Dictionary = dome_s.get_attack_visual_meta({ "is_charged": true })
	var meta_v3: Dictionary = dome_s.get_attack_visual_meta({ "is_charged": true, "is_charged_v3": true })
	var meta_h: Dictionary = dome_s.get_attack_visual_meta({ "is_hammer": true })
	assert(String(meta_soft.get("icon")) == "~👊" and String(meta_q.get("icon")) == "👊", "Quick/Soft icons mismatch")
	assert(String(meta_c.get("icon")) == "⚡" and String(meta_v3.get("icon")) == "🔥" and String(meta_h.get("icon")) == "🔨", "Heavy/V3/Hammer icons mismatch")
	assert("50%" in String(meta_v3.get("hud_hint")), "V3 HUD hint must show 50% X chip warning")

	# Lack-of-intent helper checks
	assert(dome_s.should_jab_lack_intent_turnover(3, 3, 0, 0) == true, "All soft jabs must trigger turnover")
	assert(dome_s.should_jab_lack_intent_turnover(2, 0, 0, 0) == true, "Normal Solido jabs without Charged or Sonic must trigger turnover")
	assert(dome_s.should_jab_lack_intent_turnover(3, 0, 1, 0) == false, "Combo with Charged hit has intent")
	assert(dome_s.should_jab_lack_intent_turnover(3, 0, 0, 1) == false, "Combo with Sonic hit has intent")

	# Runtime Dome #7: Zone icons, Turtle Guard X (+6/+4/+10 Ki), V3 containment (-10 Ki, no launch), Hammer X bypass & launch
	var dome7: Node3D = dome_s.new()
	root.add_child(dome7)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("is_in_furia", false)
	ai_mock.set("is_in_furia", false)
	p_mock.set("current_ki", 50.0)
	ai_mock.set("current_ki", 50.0)
	dome7.call("setup", p_mock, ai_mock, -1.0, 4)
	dome7.set("phase", 2) # DEFENSE_RHYTHM
	dome7.set("is_active", true)
	var z0: Dictionary = dome7.get("target_zones")[0]
	dome7.call("_update_defense_zone_highlights", 0, 2, -1, true, false, true, "🔥")
	assert((z0.get("step_label") as Label3D).text == "🔥", "Active V3 zone label must show ONLY incoming strike icon without overlap")
	assert((z0.get("inner_mesh") as MeshInstance3D).visible == false, "Square defense box inner_mesh must stay hidden so two icons never overlap")

	# Turtle Guard X consecutive Nv1 (+6 -> +4) & Nv2 (+10)
	var cg_events: Array = []
	dome7.connect("defense_action_resolved", func(act: String, _zid: int, _blk: bool, ki_d: float, bp_d: float):
		cg_events.append({ "action": act, "ki": ki_d, "bp": bp_d })
	)
	dome7.set("consecutive_guard_hits", 0)
	ai_mock.set("secured_np_threshold_ratio", 0.0)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_ki", 50.0)
	var n_q1: Dictionary = { "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	var n_q2: Dictionary = { "zone_id": 1, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	dome7.set("hits", [n_q1, n_q2])
	dome7.call("_resolve_cross_arm_guard", n_q1, z0)
	var ki_after_q1: float = float(ai_mock.get("current_ki"))
	assert(cg_events.size() == 1 and absf(float(cg_events[0]["ki"]) - 6.0) < 0.01 and absf(float(cg_events[0]["bp"]) - 15.0) < 0.01, "1st Nv1 Turtle Guard X must grant +6 Ki and +15 BP")
	assert(ki_after_q1 >= 56.0 and ki_after_q1 < 56.25, "Defender Ki after 1st Nv1 Turtle Guard X must be ~56")
	dome7.call("_resolve_cross_arm_guard", n_q2, dome7.get("target_zones")[1])
	var ki_after_q2: float = float(ai_mock.get("current_ki"))
	assert(cg_events.size() == 2 and absf(float(cg_events[1]["ki"]) - 4.0) < 0.01, "2nd consecutive Nv1 Turtle Guard X must decay -2 -> +4 Ki")
	assert(ki_after_q2 >= ki_after_q1 + 4.0 and ki_after_q2 < ki_after_q1 + 4.25, "Defender Ki after 2nd Nv1 Turtle Guard X must increase by +4")

	dome7.set("consecutive_guard_hits", 0)
	ai_mock.set("current_ki", 50.0)
	var n_c2: Dictionary = { "zone_id": 0, "is_charged": true, "is_charged_v3": false, "is_hammer": false, "tier": "SONICO", "resolved": false }
	dome7.set("hits", [n_c2])
	dome7.call("_resolve_cross_arm_guard", n_c2, z0)
	assert(cg_events.size() == 3 and absf(float(cg_events[2]["ki"]) - 10.0) < 0.01, "Nv2 Cargado Turtle Guard X must grant +10 Ki")
	assert(float(ai_mock.get("current_ki")) >= 60.0 and float(ai_mock.get("current_ki")) < 61.0, "Defender Ki after Nv2 Turtle Guard X must be ~60 (+10 Ki + resilience)")

	# V3 vs Guard X: stops launch (dome stays active!), drains -10 Ki, 50% chip, 0 BP gain
	dome7.set("consecutive_guard_hits", 0)
	ai_mock.set("current_transformation_index", -1)
	p_mock.set("current_transformation_index", -1)
	ai_mock.set("is_in_furia", false)
	p_mock.set("is_in_furia", false)
	dome7.set("attacker_damage_mult", 1.0)
	ai_mock.set("secured_np_threshold_ratio", 0.0)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_ki", 50.0)
	var np_before_v3: float = float(ai_mock.get("current_np"))
	var v3_prof_before: Dictionary = dome7.call("_get_bp_profile", p_mock, ai_mock, true)
	var expected_v3_chip: float = 220.0 * float(v3_prof_before.get("damage_scale", 1.0))
	var n_v3_x: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": true, "is_hammer": false, "tier": "SONICO", "resolved": false }
	dome7.set("hits", [n_v3_x])
	dome7.call("_resolve_cross_arm_guard", n_v3_x, dome7.get("target_zones")[1])
	assert(bool(dome7.get("is_active")) == true, "Guard X must contain V3 without launching defender")
	assert(cg_events.size() == 4 and String(cg_events[3]["action"]) == "cross_arm_guard_v3" and absf(float(cg_events[3]["ki"]) + 10.0) < 0.01 and absf(float(cg_events[3]["bp"])) < 0.01, "Guard X vs V3 must emit -10 Ki and 0 BP")
	assert(float(ai_mock.get("current_ki")) <= 42.5 and float(ai_mock.get("current_ki")) >= 40.0, "Defender Ki after Guard X vs V3 must drop ~10 Ki (incl. resilience)")
	var v3_np_after: float = float(ai_mock.get("current_np"))
	assert(absf((np_before_v3 - v3_np_after) - expected_v3_chip) < 5.0 and (np_before_v3 - v3_np_after) > 200.0, "Guard X vs V3 must deal 50%% of 440 chip damage and +0 BP (before=%.1f after=%.1f exp=%.1f)" % [np_before_v3, v3_np_after, expected_v3_chip])

	# Hammer vs Guard X: bypasses X and launches immediately
	var n_ham_x: Dictionary = { "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": true, "tier": "SONICO", "resolved": false }
	dome7.set("hits", [n_ham_x])
	dome7.call("_resolve_cross_arm_guard", n_ham_x, z0)
	assert(bool(dome7.get("is_active")) == false, "Hammer must bypass Guard X and launch immediately")

	# Runtime Dome #8: Soft jabs without intent absorb and return turn via restart_attacker (no launch)
	var dome8: Node3D = dome_s.new()
	root.add_child(dome8)
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	dome8.call("setup", p_mock, ai_mock, -1.0, 4)
	dome8.set("phase", 2)
	dome8.set("is_active", true)
	dome8.set("defense_round_total_hits", 2)
	dome8.set("hits", [
		{ "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SUAVE", "resolved": true, "defense_score": 0.0 },
		{ "zone_id": 1, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SUAVE", "resolved": true, "defense_score": 0.0 }
	])
	dome8.call("evaluate_round_outcome")
	assert(bool(dome8.get("is_active")) == true and int(dome8.get("phase")) == int(dome_s.DomePhase.PHASE_TRANSITION), "No-intent jab round must stay in dome and enter PHASE_TRANSITION")
	assert(String(dome8.get("transition_on_complete_mode")) == "restart_attacker", "No-intent jab round must give turn to defender via restart_attacker")

	# Runtime Dome #9: Unblocked V3 mid-combo must launch IMMEDIATELY even with remaining unresolved notes
	var dome9: Node3D = dome_s.new()
	root.add_child(dome9)
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	dome9.call("setup", p_mock, ai_mock, -1.0, 4)
	dome9.set("phase", 2)
	dome9.set("is_active", true)
	var n_v3_mid: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": true, "is_hammer": false, "v3_launch_mode": "BACK", "tier": "SONICO", "power": 2.4, "velocity": 3.5, "resolved": false }
	var n_rem: Dictionary = { "zone_id": 2, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	dome9.set("hits", [n_v3_mid, n_rem])
	dome9.call("_resolve_unblocked_hit", n_v3_mid, dome9.get("target_zones")[1])
	assert(bool(dome9.get("is_active")) == false, "Unblocked V3 must trigger immediate launch without waiting for remaining notes")
	dome_s.reset_match_static_state()

	# ========================================================================
	# 12. Z-VANISH DEFENSIVO ESTRICTO EN VERDE (FALLO ANTES DE VERDE, LECTURA
	#     STICK / CLICK CON DIAGNOSTICO HUD, CORTE DE COMBO / CONTRAATAQUE)
	# ========================================================================
	assert(dome_s.get_defense_green_start_sec(false, false, false) == 0.18, "Nv1 green window must start at 0.18s")
	assert(dome_s.get_defense_green_start_sec(true, false, false) == 0.28, "Charged/V3/Hammer green window must start at 0.28s")
	assert(dome_s.evaluate_defensive_z_vanish_input(0.05, 1.4, 0.60, false, false, false, false, 50.0, 10.0) == "BLOCKED_QUICK", "Stick vs Nv1 rapid must return BLOCKED_QUICK")
	assert(dome_s.evaluate_defensive_z_vanish_input(0.60, 1.55, 0.65, false, false, false, true, 50.0, 10.0) == "EARLY_FAIL", "Stick in Red on Hammer (0.60s) must return EARLY_FAIL")
	assert(dome_s.evaluate_defensive_z_vanish_input(0.34, 1.42, 0.65, false, true, true, false, 50.0, 10.0) == "EARLY_FAIL", "Stick in Amber on V3 (0.34s) must return EARLY_FAIL")
	assert(dome_s.evaluate_defensive_z_vanish_input(0.24, 1.42, 0.55, false, true, true, false, 50.0, 10.0) == "EXECUTE", "0.55 stick in Green on V3 (0.24s) must EXECUTE Z-Vanish")
	assert(dome_s.evaluate_defensive_z_vanish_input(-0.08, 1.55, 0.0, true, false, false, true, 50.0, 10.0) == "EXECUTE", "primary_click in Green on Hammer (-0.08s) must EXECUTE Z-Vanish")
	assert(dome_s.evaluate_defensive_z_vanish_input(0.15, 1.42, 0.55, false, true, true, false, 5.0, 10.0) == "NO_KI", "Stick in Green with <vanish_cost Ki must return NO_KI")

	# Runtime Dome #10: Early stick flick in Red triggers early_lockout and FAILS; subsequent Green flick cannot save & Hammer hits
	sim_node.set("sim_active", true)
	sim_node.set("v_left_stick", Vector2.ZERO)
	sim_node.set("v_right_stick", Vector2.ZERO)
	sim_node.set("v_left_primary_click", false)
	sim_node.set("v_right_primary_click", false)
	var dome10: Node3D = dome_s.new()
	root.add_child(dome10)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_ki", 50.0)
	p_mock.set("current_ki", 50.0)
	dome10.call("setup", ai_mock, p_mock, -1.0, 4)
	dome10.set("phase", int(dome_s.DomePhase.DEFENSE_RHYTHM))
	dome10.set("is_active", true)
	dome10.set("defense_timer", 0.0)
	dome10.set("defense_total_duration", 3.0)
	var n_hm_early: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": false, "is_hammer": true, "tier": "SONICO", "prewarn_sec": 1.55, "time_offset": 0.55, "defense_score": 0.0, "resolved": false }
	dome10.set("hits", [n_hm_early])
	sim_node.set("v_right_stick", Vector2(0.55, 0.0))
	dome10.call("_process_defense_rhythm", 0.016)
	sim_node.set("v_right_stick", Vector2.ZERO)
	dome10.call("_process_defense_rhythm", 0.016)
	assert(bool(n_hm_early.get("early_lockout", false)) == true and bool(n_hm_early.get("resolved", false)) == false, "Z-Vanish before Green must trigger early_lockout and NOT resolve as dodge")
	dome10.set("defense_timer", 0.35)
	sim_node.set("v_right_stick", Vector2(0.65, 0.0))
	dome10.call("_process_defense_rhythm", 0.016)
	sim_node.set("v_right_stick", Vector2.ZERO)
	assert(bool(n_hm_early.get("resolved", false)) == false, "Locked-out note from premature Z-Vanish must NOT dodge when flicked again in Green")
	dome10.set("defense_timer", 0.56)
	dome10.call("_process_defense_rhythm", 0.016)
	assert(bool(dome10.get("is_active")) == false, "Failed premature Z-Vanish on Hammer must eat unblocked Hammer hit at t<=0")

	# Runtime Dome #11: Fresh stick 0.55 in Green on Hammer executes Z-Vanish, cuts remaining combo & turns over (or Z-Vanish War) + HUD indicator
	var dome11: Node3D = dome_s.new()
	root.add_child(dome11)
	p_mock.set("current_np", 10000.0)
	p_mock.set("current_ki", 50.0)
	dome11.call("setup", ai_mock, p_mock, -1.0, 4)
	dome11.set("phase", int(dome_s.DomePhase.DEFENSE_RHYTHM))
	dome11.set("is_active", true)
	dome11.set("defense_timer", 0.0)
	dome11.set("defense_total_duration", 3.0)
	var n_hm_ok: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": false, "is_hammer": true, "tier": "SONICO", "prewarn_sec": 1.55, "time_offset": 0.20, "defense_score": 0.0, "resolved": false }
	var n_hm_rem: Dictionary = { "zone_id": 2, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "prewarn_sec": 0.75, "time_offset": 1.10, "defense_score": 0.0, "resolved": false }
	dome11.set("hits", [n_hm_ok, n_hm_rem])
	sim_node.set("v_right_stick", Vector2(0.55, 0.0))
	dome11.call("_process_defense_rhythm", 0.016)
	sim_node.set("v_right_stick", Vector2.ZERO)
	assert(bool(n_hm_ok.get("resolved", false)) == true and absf(float(n_hm_ok.get("defense_score", 0.0)) - 1.0) < 0.01, "Fresh Stick 0.55 in Green on Hammer must execute Z-Vanish")
	assert(float(p_mock.get("current_ki")) < 50.0 and float(p_mock.get("current_np")) >= 10110.0, "Green Z-Vanish must drain Ki and award +120 BP")
	assert("🕹️" in String(dome11.get("_def_stick_diag_str")), "Active stick must update _def_stick_diag_str HUD indicator")
	var ph11: int = int(dome11.get("phase"))
	assert(ph11 == int(dome_s.DomePhase.PHASE_TRANSITION) or ph11 == int(dome_s.DomePhase.LORE_EVENT), "Successful Green Z-Vanish must trigger counterattack turnover or Z_VANISH_WAR")
	if ph11 == int(dome_s.DomePhase.PHASE_TRANSITION):
		assert(String(dome11.get("transition_on_complete_mode")) == "restart_attacker" and bool(n_hm_rem.get("resolved", false)) == true, "Turnover Z-Vanish must cut remaining combo and restart_attacker")

	# Runtime Dome #12: primary_click fresh in Green on V3 executes Z-Vanish cleanly
	var dome12: Node3D = dome_s.new()
	root.add_child(dome12)
	p_mock.set("current_ki", 50.0)
	dome12.call("setup", ai_mock, p_mock, -1.0, 4)
	dome12.set("phase", int(dome_s.DomePhase.DEFENSE_RHYTHM))
	dome12.set("is_active", true)
	dome12.set("defense_timer", 0.0)
	dome12.set("defense_total_duration", 3.0)
	var n_v3_clk: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": true, "is_hammer": false, "tier": "SONICO", "prewarn_sec": 1.42, "time_offset": 0.12, "defense_score": 0.0, "resolved": false }
	dome12.set("hits", [n_v3_clk])
	sim_node.set("v_left_primary_click", true)
	dome12.call("_process_defense_rhythm", 0.016)
	sim_node.set("v_left_primary_click", false)
	assert(bool(n_v3_clk.get("resolved", false)) == true and absf(float(n_v3_clk.get("defense_score", 0.0)) - 1.0) < 0.01, "Fresh primary_click in Green on V3 must execute Z-Vanish")

	# Runtime Dome #13: Low Ki (<vanish_cost) in Green warns player without early_lockout or burning stick
	var dome13: Node3D = dome_s.new()
	root.add_child(dome13)
	p_mock.set("current_ki", 5.0)
	dome13.call("setup", ai_mock, p_mock, -1.0, 4)
	dome13.set("phase", int(dome_s.DomePhase.DEFENSE_RHYTHM))
	dome13.set("is_active", true)
	dome13.set("defense_timer", 0.0)
	dome13.set("defense_total_duration", 3.0)
	var n_v3_noki: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": true, "is_hammer": false, "tier": "SONICO", "prewarn_sec": 1.42, "time_offset": 0.15, "defense_score": 0.0, "resolved": false }
	dome13.set("hits", [n_v3_noki])
	sim_node.set("v_right_stick", Vector2(0.65, 0.0))
	dome13.call("_process_defense_rhythm", 0.016)
	sim_node.set("v_right_stick", Vector2.ZERO)
	assert(bool(n_v3_noki.get("resolved", false)) == false and bool(n_v3_noki.get("zv_noki_hint_shown", false)) == true, "Low-Ki Z-Vanish in Green must leave note unresolved and show NO_KI feedback")
	assert(bool(n_v3_noki.get("early_lockout", false)) == false and int(dome13.get("_def_stick_used_for_note_idx")) == -1, "Low-Ki Z-Vanish must NOT trigger early_lockout or burn stick")

	# ========================================================================
	# 13. KI DE ATAQUE DIFERIDO A DEFENSA Y ANTI-LANZAMIENTO FANTASMA EN KI BREAK
	# ========================================================================
	var dome14: Node3D = dome_s.new()
	root.add_child(dome14)
	ai_mock.set("current_ki", 40.0)
	p_mock.set("current_ki", 60.0)
	dome14.call("setup", ai_mock, p_mock, -1.0, 4)
	dome14.set("max_allowed_hits", 4)
	dome14.call("generate_ai_attack_sequence")
	var ai_hits14: Array = dome14.get("hits")
	assert(absf(float(ai_mock.get("current_ki")) - 40.0) < 0.01, "AI sequence generation must NOT drain AI Ki upfront (deferred to defense)")
	assert(ai_hits14.size() >= 1 and float(dome14.get("_declared_ki_reserved")) > 0.0, "AI declaration must reserve Ki budget")
	for h14 in ai_hits14:
		assert(float(h14.get("ki_cost", 0.0)) > 0.0 and bool(h14.get("ki_cost_paid", false)) == false, "Generated AI notes must carry unpaid ki_cost")

	# Cutting a 3-hit combo on Hit #0 via Z-Vanish only pays Hit #0's ki_cost (Hits #1 and #2 stay unpaid)
	ai_mock.set("current_ki", 40.0)
	p_mock.set("current_ki", 60.0)
	var cut_n0: Dictionary = { "zone_id": 1, "is_charged": true, "is_charged_v3": false, "is_hammer": false, "ki_cost": 7.0, "ki_cost_paid": false, "prewarn_sec": 1.22, "time_offset": 0.20, "resolved": false }
	var cut_n1: Dictionary = { "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "ki_cost": 3.0, "ki_cost_paid": false, "prewarn_sec": 0.75, "time_offset": 1.10, "resolved": false }
	var cut_n2: Dictionary = { "zone_id": 2, "is_charged": true, "is_charged_v3": true, "is_hammer": false, "ki_cost": 11.0, "ki_cost_paid": false, "prewarn_sec": 1.42, "time_offset": 2.00, "resolved": false }
	dome14.set("phase", int(dome_s.DomePhase.DEFENSE_RHYTHM))
	dome14.set("hits", [cut_n0, cut_n1, cut_n2])
	dome14.call("_resolve_defensive_z_vanish", cut_n0, dome14.get("target_zones")[1])
	assert(bool(cut_n0.get("ki_cost_paid", false)) == true and absf(float(ai_mock.get("current_ki")) - 33.0) < 0.01, "Executed Hit #0 must charge -7 Ki from attacker")
	assert(bool(cut_n1.get("ki_cost_paid", false)) == false and bool(cut_n2.get("ki_cost_paid", false)) == false, "Cut hits #1 and #2 must NEVER charge Ki")

	# UNBLOCKABLE_KI_BREAK: Guard X must never trigger punch, and timeout with player winner separates without launch
	assert(dome_s.can_player_trigger_ki_break_punch(true, 0.25, true, 0.20, 2.0, 2.5) == false, "Crossing arms must NEVER trigger Ki Break punch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.28, true, 0.20, 2.0, 2.5) == false, "Close two-hand stance (<0.36m) must NEVER trigger Ki Break punch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.20, 0.90, 1.20) == false, "Slow nudge must NEVER trigger Ki Break punch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.25, 1.40, 1.80) == true, "Intentional extended forward punch must trigger Ki Break finisher")

	var lc14: Node3D = dome14.get("_lore_ctrl") as Node3D
	if lc14:
		lc14.set("is_event_active", false)
		lc14.set("active_event_type", 0)
	dome14.set("is_active", true)
	var fin_cnt14: Array[int] = [0]
	dome14.connect("finisher_triggered", func(_fn: String, _v: float, _h: Array, _lv: Vector3): fin_cnt14[0] += 1)
	dome14.call("_start_unblockable_ki_break", p_mock, ai_mock)
	dome14.set("ki_break_timer", 0.01)
	dome14.call("_process_unblockable_ki_break", 0.02)
	assert(int(dome14.get("phase")) == int(dome_s.DomePhase.LORE_EVENT), "Expired player Ki Break must enter TACTICAL_STANDOFF")
	dome14.call("_process_lore_event", 0.70)
	assert(fin_cnt14[0] == 0 and bool(dome14.get("is_active")) == false and float(dome14.get("_custom_separation_dist")) >= 7.5, "Expired player Ki Break opportunity must separate cleanly via TACTICAL_STANDOFF without phantom launch")

	# ========================================================================
	# 14. EVENTO LORE #7 TACTICAL_STANDOFF ("DESENGANCHE Z") Y CERO VUELO SIN GOLPE
	# ========================================================================
	for m_st in ["mutual_exhaustion", "sim_draw", "no_ki_turnover", "ki_break_pass", "cancel"]:
		var pr_st: Dictionary = lore_s.get_standoff_preset(m_st)
		assert(float(pr_st.get("distance", 0.0)) >= 8.0 and not String(pr_st.get("title", "")).is_empty(), "TACTICAL_STANDOFF preset valid for %s" % m_st)
	assert(absf(float(lore_s.get_standoff_preset("mutual_exhaustion").get("ki_recovery", 0.0)) - 10.0) < 0.01, "Mutual exhaustion must grant +10 Ki breath")

	# Simultaneous exchange zero-punch anti-launch checks
	var sim_0_draw: Dictionary = dome_s.evaluate_simultaneous_exchange_end(0, 0, 40.0, 1.5, 5.0)
	assert(String(sim_0_draw.get("state")) == "standoff" and String(sim_0_draw.get("mode")) == "sim_draw", "Blocking only (0 hits) while enemy hits <=2 Ki must trigger standoff, NOT launch")
	var sim_0_mut: Dictionary = dome_s.evaluate_simultaneous_exchange_end(0, 0, 1.0, 1.0, 5.0)
	assert(String(sim_0_mut.get("state")) == "standoff" and String(sim_0_mut.get("mode")) == "mutual_exhaustion", "Double low Ki in simultaneous exchange must trigger mutual_exhaustion")
	var sim_0_to: Dictionary = dome_s.evaluate_simultaneous_exchange_end(0, 0, 50.0, 40.0, 0.0)
	assert(String(sim_0_to.get("state")) == "standoff" and String(sim_0_to.get("mode")) == "sim_draw", "0-0 timeout in simultaneous exchange must trigger sim_draw standoff")
	var sim_1_win: Dictionary = dome_s.evaluate_simultaneous_exchange_end(1, 0, 40.0, 1.5, 5.0)
	assert(String(sim_1_win.get("state")) == "launch" and String(sim_1_win.get("winner")) == "player", "Landing >=1 hit and draining enemy <=2 Ki must launch")

	# Flurry clash anti-launch when no punches or both at 0 Ki
	assert(lore_s.evaluate_flurry_clash_resolution(0.0, 0.0, 0.50, 0, 1.0) == "standoff_mutual", "Double 0 Ki in Flurry Clash must trigger standoff_mutual")
	assert(lore_s.evaluate_flurry_clash_resolution(20.0, 0.0, 0.50, 0, 1.0) == "standoff_draw", "0 player punches when enemy reaches 0 Ki must trigger standoff_draw")
	assert(lore_s.evaluate_flurry_clash_resolution(20.0, 20.0, 0.52, 0, 0.0) == "standoff_draw", "Even 0-punch Flurry Clash timeout must trigger standoff_draw")

	# Hardened Ki Break anti-false-positive checks (grace period, release guard X, minimum stroke/forward)
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.20, 1.60, 2.0, 0.25, false, 0.25, 0.14) == false, "Grace timer > 0 must block accidental Ki Break launch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.20, 1.60, 2.0, 0.0, true, 0.25, 0.14) == false, "Unreleased Guard X state must block Ki Break launch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.20, 1.60, 2.0, 0.0, false, 0.05, 0.03) == false, "Tiny controller twitch (<0.12m stroke) must block Ki Break launch")
	assert(dome_s.can_player_trigger_ki_break_punch(false, 0.55, true, 0.20, 1.60, 2.0, 0.0, false, 0.22, 0.14) == true, "Real single-hand punch after releasing guard must trigger Ki Break")

	# Double 0 Ki on dome15 -> mutual_exhaustion grants +10 Ki and closes with 0 finishers
	var dome15: Node3D = dome_s.new() as Node3D
	root.add_child(dome15)
	p_mock.set("current_ki", 2.0)
	ai_mock.set("current_ki", 2.0)
	dome15.call("setup", p_mock, ai_mock, -1.0, 4)
	var fin_cnt15: Array[int] = [0]
	dome15.connect("finisher_triggered", func(_fn: String, _v: float, _h: Array, _lv: Vector3): fin_cnt15[0] += 1)
	assert(int(dome15.get("phase")) == int(dome_s.DomePhase.LORE_EVENT), "Starting attack phase when both <3 Ki must immediately enter TACTICAL_STANDOFF")
	assert(absf(float(p_mock.get("current_ki")) - 12.0) < 0.01 and absf(float(ai_mock.get("current_ki")) - 12.0) < 0.01, "Mutual exhaustion standoff must give +10 Ki breath to both fighters")
	dome15.call("_process_lore_event", 0.70)
	assert(fin_cnt15[0] == 0 and bool(dome15.get("is_active")) == false and float(dome15.get("_custom_separation_dist")) >= 9.0, "Mutual exhaustion standoff must separate at >=9.0m without finisher")

	# Physical tactical separation shield blocks 9.0 m/s proximity blast right after dome exit
	rig.global_position = Vector3.ZERO
	cam.global_position = Vector3(0.0, 1.6, 0.0)
	ai_mock.global_position = Vector3(0.0, 0.0, -1.10)
	p_mock.set("is_in_bullet_time", false)
	ai_mock.set("is_in_bullet_time", false)
	p_mock.set("is_flying_to_opponent", false)
	ai_mock.set("is_flying_to_opponent", false)
	p_mock.set("is_knocked_back", false)
	ai_mock.set("is_knocked_back", false)
	p_mock.set("velocity", Vector3.ZERO)
	ai_mock.set("velocity", Vector3.ZERO)
	p_mock.set("_proximity_repulsion_cooldown", 0.0)
	p_mock.set("_tactical_separation_timer", 0.0)
	p_mock.call("_separate_fighters_to_canonical_distance", ai_mock, 8.5)
	assert(float(p_mock.get("_tactical_separation_timer")) >= 0.70, "Canonical separation must arm _tactical_separation_timer shield")
	p_mock.call("_process_mutual_body_collision")
	assert((ai_mock.get("velocity") as Vector3).length_squared() < 0.001 and bool(ai_mock.get("is_knocked_back")) == false and bool(p_mock.get("is_knocked_back")) == false, "Separation shield must block 9 m/s proximity repulsion while separating")

	# --- 15. Cine Anime Minimalista HUD + Hex Portraits + Zenkai LockOn ---
	var goku_forms: Array[Array] = [
		["Goku", "", "res://assets/ui_zenkai/hex_goku_base.png"],
		["Goku (Zenkai)", "SSJ", "res://assets/ui_zenkai/hex_goku_ssj.png"],
		["Goku", "SSG", "res://assets/ui_zenkai/hex_goku_ssg.png"],
		["Goku", "SSJ3", "res://assets/ui_zenkai/hex_goku_ssj3.png"],
		["Goku", "SSB", "res://assets/ui_zenkai/hex_goku_ssb.png"]
	]
	for gf in goku_forms:
		var rp: String = dome_s.resolve_hex_portrait_path(String(gf[0]), String(gf[1]))
		assert(rp == String(gf[2]), "Expected %s for Goku form '%s', got %s" % [String(gf[2]), String(gf[1]), rp])
		assert(ResourceLoader.exists(rp), "Missing imported resource: %s" % rp)

	var vegeta_forms: Array[Array] = [
		["Vegeta", "", "res://assets/ui_zenkai/hex_vegeta_base.png"],
		["Vegeta", "SSJ", "res://assets/ui_zenkai/hex_vegeta_ssj.png"],
		["Vegeta", "Super Vegeta", "res://assets/ui_zenkai/hex_vegeta_super.png"],
		["Vegeta", "SSB", "res://assets/ui_zenkai/hex_vegeta_ssb.png"],
		["Vegeta", "Ultra Ego", "res://assets/ui_zenkai/hex_vegeta_ue.png"]
	]
	for vf in vegeta_forms:
		var rp: String = dome_s.resolve_hex_portrait_path(String(vf[0]), String(vf[1]))
		assert(rp == String(vf[2]), "Expected %s for Vegeta form '%s', got %s" % [String(vf[2]), String(vf[1]), rp])
		assert(ResourceLoader.exists(rp), "Missing imported resource: %s" % rp)

	for extra_icon in ["icon_ki_blast.png", "target_normal.png", "target_fight.png", "info_obi.png"]:
		assert(ResourceLoader.exists("res://assets/ui_zenkai/" + extra_icon), "Missing UI sprite: %s" % extra_icon)

	var visor_anc: Node3D = dome.get("melee_visor_anchor") as Node3D
	var flank_pips: Node3D = dome.get("_flank_pips_root") as Node3D
	var flank_stamp: Node3D = dome.get("_flank_stamp_root") as Node3D
	var ki_bar_r: Node3D = dome.get("_ki_bar_root") as Node3D
	var hdr_obi: MeshInstance3D = dome.get("_header_obi_mesh") as MeshInstance3D
	var p_hex_m: StandardMaterial3D = dome.get("_player_hex_mat") as StandardMaterial3D
	var e_hex_m: StandardMaterial3D = dome.get("_enemy_hex_mat") as StandardMaterial3D
	assert(visor_anc != null and visor_anc.get_parent() == cam, "Visor anchor must be attached to player camera")
	assert(flank_pips != null and flank_stamp != null and ki_bar_r != null, "Cine Anime HUD flanks and bottom Ki clash bar must exist")
	assert(flank_pips.get_parent() == visor_anc and flank_stamp.get_parent() == visor_anc and ki_bar_r.get_parent() == visor_anc, "Flanks and lower Ki bar must stay fixed to melee_visor_anchor inside at-a-glance FOV")
	assert(dome.get("action_card_anchor") == null, "Legacy giant bottom-left action_card_anchor must be disabled/removed")
	assert(hdr_obi != null, "Transient info_obi mesh must exist")
	assert(p_hex_m != null and p_hex_m.albedo_texture != null, "Player hex portrait material must bind a texture")
	assert(e_hex_m != null and e_hex_m.albedo_texture != null, "Enemy hex portrait material must bind a texture")

	var lockon_s: GDScript = load("res://scripts/ki_sense_and_lockon.gd") as GDScript
	var lockon_t: Node = lockon_s.new() as Node
	root.add_child(lockon_t)
	assert(lockon_t.get("_tex_target_normal") != null and lockon_t.get("_tex_target_fight") != null, "KiSenseAndLockOn must load Zenkai target_normal and target_fight textures")

	# --- 16. Left-hand Holographic VRHUD + Dynamic Hex Portraits & Zenkai Styling ---
	var hud_scene: PackedScene = load("res://vr_hud.tscn") as PackedScene
	assert(hud_scene != null, "vr_hud.tscn must load cleanly")
	var hud_t: Node3D = hud_scene.instantiate() as Node3D
	root.add_child(hud_t)
	var hud_gd: GDScript = hud_t.get_script() as GDScript
	for gf in goku_forms:
		assert(hud_gd.resolve_hex_portrait_path(String(gf[0]), String(gf[1])) == String(gf[2]), "vr_hud Goku hex path mismatch for %s" % String(gf[1]))
	for vf in vegeta_forms:
		assert(hud_gd.resolve_hex_portrait_path(String(vf[0]), String(vf[1])) == String(vf[2]), "vr_hud Vegeta hex path mismatch for %s" % String(vf[1]))
	p_mock.set("current_transformation", null)
	ai_mock.set("current_transformation", null)
	hud_t.set("player_instance", p_mock)
	hud_t.set("enemy_instance", ai_mock)
	hud_t.call("refresh_for_character_swap")
	var p_hex_r: TextureRect = hud_t.get("_player_hex_rect") as TextureRect
	var e_hex_r: TextureRect = hud_t.get("_enemy_hex_rect") as TextureRect
	var t_icons: Array = hud_t.get("_threshold_icons") as Array
	var hud_vp: SubViewport = hud_t.get("sub_viewport") as SubViewport
	assert(p_hex_r != null and p_hex_r.texture != null, "vr_hud must bind player hex portrait texture")
	assert(e_hex_r != null and e_hex_r.texture != null, "vr_hud must bind enemy hex portrait texture")
	assert(t_icons.size() == 4, "vr_hud must create 4 Zenkai threshold badge icons")
	assert(hud_vp != null and hud_vp.size == Vector2i(780, 480), "vr_hud SubViewport must be 780x480 for crisp square hex pixels")
	var first_tr: Resource = p_mock.character_data.transformations[0]
	p_mock.set("current_transformation", first_tr)
	hud_t.call("_refresh_hex_portraits")
	var expected_tr_hex: String = hud_gd.resolve_hex_portrait_path(String(p_mock.character_data.character_name), String(first_tr.form_name))
	assert(String(hud_t.get("_last_player_hex_path")) == expected_tr_hex, "vr_hud must dynamically switch hex portrait on transformation")
	hud_t.call("update_power_level", 15000.0, 20000.0)
	var ico0: TextureRect = t_icons[0] as TextureRect
	var ico2: TextureRect = t_icons[2] as TextureRect
	var ico3: TextureRect = t_icons[3] as TextureRect
	assert(ico0.texture != null and ico0.texture == ico2.texture, "25% and 75% thresholds must switch to alert_base_y.png")
	assert(ico3.texture != null and ico3.texture != ico0.texture, "100% locked threshold must stay alert_base_b.png")
	p_mock.set("current_transformation", null)

	dome_s.reset_match_static_state()

	# --- 17. Melee Opponent Head Look-At (Goku & Vegeta must aim at XRCamera3D, not skyward) ---
	var look_rig: XROrigin3D = XROrigin3D.new()
	look_rig.name = "LookAtTestRig"
	var cam_l: XRCamera3D = XRCamera3D.new()
	cam_l.name = "XRCamera3D"
	cam_l.position = Vector3(0.0, 1.60, 0.0)
	var p_look: Node3D = char_s.new() as Node3D
	p_look.name = "PlayerCharacterInstance"
	look_rig.add_child(cam_l)
	look_rig.add_child(p_look)
	root.add_child(look_rig)
	p_look.set("is_player", true)
	p_look.set_physics_process(false)

	var look_chars: Array = [["Goku", goku_res], ["Vegeta", vegeta_res]]
	for lc in look_chars:
		var cname: String = String(lc[0])
		var cres: Resource = lc[1] as Resource
		var ai_look: Node3D = char_s.new() as Node3D
		ai_look.name = "EnemyLookTest_" + cname
		ai_look.set("character_data", cres)
		root.add_child(ai_look)
		ai_look.set_physics_process(false)
		var ai_l_ctrl: Variant = ai_look.get("cached_ai_controller")
		if ai_l_ctrl and is_instance_valid(ai_l_ctrl):
			(ai_l_ctrl as Node).set_physics_process(false)
			ai_l_ctrl.set("enabled", false)
		ai_look.set("_cached_opponent", p_look)
		ai_look.global_position = Vector3(0.0, 0.0, -0.90)
		cam_l.position = Vector3(0.0, 1.60, 0.0)

		var anim_l: ProceduralCombatAnimator = ai_look.get("procedural_animator") as ProceduralCombatAnimator
		assert(anim_l != null and anim_l.skeleton != null, "%s procedural_animator/skeleton missing" % cname)
		var head_idx_l: int = int(anim_l.bone_indices.get("Head", -1))
		assert(head_idx_l != -1, "%s Head bone not mapped" % cname)

		var rest_head_y: float = anim_l.skeleton.to_global(anim_l.skeleton.get_bone_global_rest(head_idx_l).origin).y
		cam_l.position = Vector3(0.0, rest_head_y + 0.08, 0.0)
		for _step_i in range(30):
			ai_look._process(0.05)

		var head_world_pos: Vector3 = anim_l.skeleton.to_global(anim_l.skeleton.get_bone_global_pose(head_idx_l).origin)
		var rel_h: float = head_world_pos.y - ai_look.global_position.y
		var torso_pitch_deg: float = rad_to_deg(anim_l.current_hips_euler.x + anim_l.current_spine_euler.x + anim_l.current_chest_euler.x + anim_l.current_upper_chest_euler.x)
		var pitch_melee_deg: float = rad_to_deg(anim_l.current_neck_euler.x + anim_l.current_head_euler.x)
		var world_pitch_deg: float = torso_pitch_deg + pitch_melee_deg
		print("[LookAtTest] %s EyeLevel Melee 0.90m (cam_y=%.2fm): rel_h=%.3fm, local_pitch=%.2f deg, world_pitch=%.2f deg" % [cname, cam_l.position.y, rel_h, pitch_melee_deg, world_pitch_deg])
		assert(rel_h >= 1.10 and rel_h <= 1.75, "%s Head rel_h=%.3fm out of expected [1.10, 1.75]m range" % [cname, rel_h])
		assert(absf(world_pitch_deg) < 6.0 and absf(pitch_melee_deg) < 12.0, "%s eye-level Melee pitch must aim straight ahead (got local=%.2f, world=%.2f)" % [cname, pitch_melee_deg, world_pitch_deg])

		if cname == "Goku":
			cam_l.position = Vector3(0.0, 1.60, 0.0)
			for _step_g in range(25):
				ai_look._process(0.05)
			var g_pitch_deg: float = rad_to_deg(anim_l.current_neck_euler.x + anim_l.current_head_euler.x)
			print("[LookAtTest] Goku Standard Cam Y=1.60m: local_pitch=%.2f deg" % g_pitch_deg)
			assert(absf(g_pitch_deg) < 12.0, "Goku Melee 0.90m at Y=1.60m must aim near center, got %.2f" % g_pitch_deg)

		cam_l.position = Vector3(0.0, 2.60, 0.0)
		for _step_up in range(25):
			ai_look._process(0.05)
		var pitch_up_deg: float = rad_to_deg(anim_l.current_neck_euler.x + anim_l.current_head_euler.x)
		print("[LookAtTest] %s High target (Y=2.60m): pitch=%.2f deg" % [cname, pitch_up_deg])
		assert(pitch_up_deg < -10.0, "%s must tilt UP (< -10 deg) when target is high, got %.2f" % [cname, pitch_up_deg])

		cam_l.position = Vector3(0.0, 0.60, 0.0)
		for _step_dn in range(25):
			ai_look._process(0.05)
		var pitch_dn_deg: float = rad_to_deg(anim_l.current_neck_euler.x + anim_l.current_head_euler.x)
		print("[LookAtTest] %s Low target (Y=0.60m): pitch=%.2f deg" % [cname, pitch_dn_deg])
		assert(pitch_dn_deg > 10.0, "%s must tilt DOWN (> +10 deg) when target is low, got %.2f" % [cname, pitch_dn_deg])

		if ai_look.get_parent():
			ai_look.get_parent().remove_child(ai_look)
		ai_look.free()

	if look_rig.get_parent():
		look_rig.get_parent().remove_child(look_rig)
	look_rig.free()

	# --- 18. Goku KO Procedural Fall & 0-Ki Anti-Premature-Zenkai ---
	var ko_goku: Node3D = char_s.new() as Node3D
	ko_goku.name = "GokuKOFallTest"
	ko_goku.set("character_data", goku_res)
	root.add_child(ko_goku)
	ko_goku.set_physics_process(false)
	var ko_ai_ctrl: Variant = ko_goku.get("cached_ai_controller")
	if ko_ai_ctrl and is_instance_valid(ko_ai_ctrl):
		(ko_ai_ctrl as Node).set_physics_process(false)
		ko_ai_ctrl.set("enabled", false)
	assert(ko_goku.get("ragdoll_simulator") == null, "Complex 369-bone Goku rig must omit Jolt PhysicalBoneSimulator3D to avoid mesh melt")
	ko_goku.global_position = Vector3(0.0, 8.0, -4.0)
	ko_goku.set("ragdoll_recovery_timer", -1.0)
	ko_goku.call("start_ragdoll", Vector3(0.0, 0.0, -10.0))
	var ko_anim: ProceduralCombatAnimator = ko_goku.get("procedural_animator") as ProceduralCombatAnimator
	assert(ko_anim != null and ko_anim.enabled == false, "procedural_animator must pause during KO fall/ragdoll")
	for _f_step in range(45):
		ko_goku._physics_process(0.05)
	var ko_ground_h: float = float(ko_goku.call("get_ground_elevation", ko_goku.global_position))
	assert(bool(ko_goku.get("_ko_fall_landed")) == true, "Goku procedural KO fall must reach ground")
	assert(absf(ko_goku.global_position.y - ko_ground_h) < 0.05, "Goku KO position Y must rest cleanly at ground_h (got %.3f vs %.3f)" % [ko_goku.global_position.y, ko_ground_h])
	ko_goku.call("stop_ragdoll")
	var ko_mesh: Node3D = ko_goku.get("body_mesh_instance") as Node3D
	assert(ko_anim.enabled == true and ko_mesh.rotation == Vector3.ZERO, "stop_ragdoll must re-enable procedural_animator and reset mesh transform")
	if ko_goku.get_parent():
		ko_goku.get_parent().remove_child(ko_goku)
	ko_goku.free()

	# 18b. 0-Ki Super Beam direct hit without Zenkai must NOT finish match
	var beam_s: GDScript = load("res://scripts/SuperBeamSequenceController.gd") as GDScript
	var beam_t: Node3D = beam_s.new() as Node3D
	root.add_child(beam_t)
	p_mock.set("is_match_over", false)
	ai_mock.set("is_match_over", false)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("is_comeback_zenkai", false)
	p_mock.set("current_transformation", g_trans[0] if g_trans.size() > 0 else null)
	p_mock.set("current_np", 18000.0)
	ai_mock.set("current_transformation", null)
	ai_mock.set("current_np", 10000.0)
	ai_mock.set("current_ki", 0.0)
	ai_mock.set("is_guard_broken", true)
	beam_t.set("attacker", p_mock)
	beam_t.set("defender", ai_mock)
	beam_t.set("power_name", "Kamehameha")
	beam_t.set("base_damage", 1200.0)
	beam_t.set("beam_dir", Vector3.FORWARD)
	beam_t.set("is_active", true)
	beam_t.call("_resolve_direct_hit")
	assert(bool(ai_mock.get("is_match_over")) == false and bool(p_mock.get("is_match_over")) == false, "0-Ki defender hit by non-Zenkai Super Beam must NOT end the match")
	p_mock.set("is_firing_beam", false)
	p_mock.set("is_in_beam_sequence", false)
	if beam_t.get_parent():
		beam_t.get_parent().remove_child(beam_t)
	beam_t.free()

	# 18c. consume_ki_or_life_force at 0 Ki must respect NP floor and never end match
	ai_mock.set("is_match_over", false)
	ai_mock.set("secured_np_threshold_ratio", 0.25)
	ai_mock.set("current_ki", 0.0)
	ai_mock.set("current_np", 1500.0)
	ai_mock.call("consume_ki_or_life_force", 50.0)
	assert(bool(ai_mock.get("is_match_over")) == false, "consume_ki_or_life_force must NEVER trigger match finish")
	assert(float(ai_mock.get("current_np")) >= 1000.0, "consume_ki_or_life_force must respect NP floor")

	# 18d. revert_to_base() must grant 6s grace so opponent does not gain instant Dominio Zenkai
	p_mock.set("_cached_opponent", ai_mock)
	ai_mock.set("_cached_opponent", p_mock)
	p_mock.set("is_match_over", false)
	ai_mock.set("is_match_over", false)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("is_comeback_zenkai", false)
	ai_mock.set("is_in_zenkai_state", false)
	ai_mock.set("is_comeback_zenkai", false)
	p_mock.set("current_transformation", g_trans[0] if g_trans.size() > 0 else null)
	p_mock.set("_active_np_multiplier", 2.0)
	p_mock.set("current_np", 24000.0)
	var v_trans: Array = vegeta_res.get("transformations")
	ai_mock.set("current_transformation", v_trans[0] if v_trans.size() > 0 else null)
	ai_mock.set("_active_np_multiplier", 2.0)
	ai_mock.set("current_np", 24000.0)
	ai_mock.call("revert_to_base") # Vegeta drops to 12000 NP (50% behind Goku's 24000)
	assert(float(ai_mock.get("_revert_zenkai_grace_timer")) > 5.0, "revert_to_base must arm 6s anti-Zenkai grace")
	assert(bool(p_mock.get("is_in_zenkai_state")) == false, "Opponent must NOT receive instant Dominio Zenkai right after 0-Ki revert")
	ai_mock.set("_revert_zenkai_grace_timer", 0.0)
	p_mock.call("check_zenkai_conditions", float(ai_mock.get("current_np")))
	assert(bool(p_mock.get("is_in_zenkai_state")) == true, "After revert grace expires, real >= 40% BP gap must still activate Dominio Zenkai")

	# 18e. Base form 50% start cannot trigger Dominio Zenkai; >= 70% Base + >= 40% lead can
	p_mock.set("current_transformation", null)
	p_mock.set("_active_np_multiplier", 1.0)
	p_mock.set("is_in_zenkai_state", false)
	p_mock.set("current_np", 9000.0) # 50% of 18000
	p_mock.call("check_zenkai_conditions", 4000.0) # lead = 55% but still in Act I (< 70%)
	assert(bool(p_mock.get("is_in_zenkai_state")) == false, "Base 50% start must NOT trigger Dominio Zenkai before reaching 70% BP")
	p_mock.set("current_np", 13500.0) # 75% >= 70%
	p_mock.call("check_zenkai_conditions", 7000.0) # lead = 48.1% >= 40%
	assert(bool(p_mock.get("is_in_zenkai_state")) == true, "Base >= 70% BP with >= 40% BP lead must activate Dominio Zenkai")

	# --- 19. 3D Steep Aim Pose Detection & Diagonal Follow-Up Hammer Slam ---
	var hcc_aim: Node = hcc_s.new() as Node
	hcc_aim.name = "SteepAimTestHCC"
	rig.add_child(hcc_aim)
	hcc_aim.set_process(false)
	hcc_aim.set("xr_origin", rig)
	hcc_aim.set("camera", cam)
	hcc_aim.set("left_controller", l_ctrl)
	hcc_aim.set("right_controller", r_ctrl)
	rig.global_position = Vector3.ZERO
	rig.scale = Vector3.ONE
	cam.position = Vector3(0.0, 1.60, 0.0)

	# 19a. Looking steeply DOWN (-60 deg): arms extended along gaze must trigger Ki Blast & Phase 2 Super
	cam.rotation = Vector3(deg_to_rad(-60.0), 0.0, 0.0)
	var down_dir: Vector3 = (-cam.global_transform.basis.z).normalized()
	var sh_ref_d: Vector3 = cam.global_position - Vector3(0.0, 0.16, 0.0)
	l_ctrl.global_position = sh_ref_d + down_dir * 0.55 + Vector3(-0.14, 0.0, 0.0)
	r_ctrl.global_position = sh_ref_d + down_dir * 0.55 + Vector3(0.14, 0.0, 0.0)
	l_ctrl.global_transform = Transform3D(Basis(down_dir, Vector3.RIGHT, down_dir.cross(Vector3.RIGHT)).orthonormalized(), l_ctrl.global_position)
	r_ctrl.global_transform = Transform3D(Basis(-down_dir, Vector3.RIGHT, (-down_dir).cross(Vector3.RIGHT)).orthonormalized(), r_ctrl.global_position)
	hcc_aim.call("_update_body_space_metrics", p_mock)
	assert(bool(hcc_aim.call("_is_arm_extended_palm_forward", r_ctrl, false)) == true, "Right arm extended along -60 deg downward gaze must pass")
	assert(bool(hcc_aim.call("_is_arm_extended_palm_forward", l_ctrl, true)) == true, "Left arm extended along -60 deg downward gaze must pass")
	var eff_l_down: float = maxf(maxf(hcc_aim.get("l_torso_pos").z, float(hcc_aim.get("l_cam_fwd_proj"))), float(hcc_aim.get("l_cam_fwd_3d_proj")))
	var eff_r_down: float = maxf(maxf(hcc_aim.get("r_torso_pos").z, float(hcc_aim.get("r_cam_fwd_proj"))), float(hcc_aim.get("r_cam_fwd_3d_proj")))
	hcc_aim.set("super_phase1_anchor_z", -0.10)
	assert(bool(hcc_aim.call("_is_phase2_autofire_pose", "kamehameha", eff_l_down, eff_r_down, 1)) == true, "Kamehameha Phase 2 must autofire when extending arms steeply downward (-60 deg)")

	# 19b. Looking steeply UP (+55 deg): arm extended along gaze must pass
	cam.rotation = Vector3(deg_to_rad(55.0), 0.0, 0.0)
	var up_dir: Vector3 = (-cam.global_transform.basis.z).normalized()
	var sh_ref_u: Vector3 = cam.global_position - Vector3(0.0, 0.16, 0.0)
	r_ctrl.global_position = sh_ref_u + up_dir * 0.55 + Vector3(0.14, 0.0, 0.0)
	r_ctrl.global_transform = Transform3D(Basis(-up_dir, Vector3.RIGHT, (-up_dir).cross(Vector3.RIGHT)).orthonormalized(), r_ctrl.global_position)
	hcc_aim.call("_update_body_space_metrics", p_mock)
	assert(bool(hcc_aim.call("_is_arm_extended_palm_forward", r_ctrl, false)) == true, "Right arm extended along +55 deg upward gaze must pass")

	# 19c. Hands tucked at waist while looking down (-60 deg) must NOT falsely count as extended forward
	cam.rotation = Vector3(deg_to_rad(-60.0), 0.0, 0.0)
	l_ctrl.global_position = cam.global_position + Vector3(-0.14, -0.35, -0.12)
	r_ctrl.global_position = cam.global_position + Vector3(0.14, -0.35, -0.12)
	hcc_aim.call("_update_body_space_metrics", p_mock)
	assert(bool(hcc_aim.call("_is_arm_extended_palm_forward", r_ctrl, false)) == false, "Hands tucked at waist must NOT trigger extended palm check")

	cam.rotation = Vector3.ZERO
	if hcc_aim.get_parent():
		hcc_aim.get_parent().remove_child(hcc_aim)
	hcc_aim.free()

	# 19d. Diagonal Follow-Up Hammer Slam must place victim ahead at comfortable diagonal angle
	var fu_s: GDScript = load("res://scripts/FollowUpSequenceController.gd") as GDScript
	var fu_hm: Node3D = fu_s.new() as Node3D
	root.add_child(fu_hm)
	rig.global_position = Vector3(0.0, 10.0, 0.0)
	ai_mock.global_position = Vector3(0.0, 8.5, -0.95)
	p_mock.set("is_match_over", false)
	ai_mock.set("is_match_over", false)
	fu_hm.set("attacker", p_mock)
	fu_hm.set("defender", ai_mock)
	fu_hm.set("is_active", true)
	fu_hm.set("chain_depth", 1)
	fu_hm.call("_execute_hammer_slam_impact", 3.6)
	var hm_ground_h: float = float(ai_mock.call("get_ground_elevation", ai_mock.global_position))
	var hm_h_dist: float = Vector2(ai_mock.global_position.x - rig.global_position.x, ai_mock.global_position.z - rig.global_position.z).length()
	var hm_drop_angle_deg: float = rad_to_deg(atan2(maxf(rig.global_position.y - ai_mock.global_position.y, 0.0), maxf(hm_h_dist, 0.01)))
	assert(absf(ai_mock.global_position.y - hm_ground_h) < 0.05, "Diagonal hammer slam must land victim on ground_h")
	assert(hm_h_dist >= 5.5, "Diagonal hammer slam horizontal dist must be >= 5.5m (got %.2fm)" % hm_h_dist)
	assert(hm_drop_angle_deg <= 36.0, "Diagonal hammer slam pitch angle must be <= 36 deg (got %.2f deg)" % hm_drop_angle_deg)
	Engine.time_scale = 1.0
	if fu_hm.get_parent():
		fu_hm.get_parent().remove_child(fu_hm)
	fu_hm.free()

	# Runtime Dome #20: Melee zone Box -> Outcome Icon Morph (Success / Block / Parry / Clash / Hit Taken + Non-Collision)
	var dome16: Node3D = dome_s.new()
	root.add_child(dome16)
	p_mock.set("current_np", 10000.0)
	ai_mock.set("current_np", 10000.0)
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	dome16.call("setup", p_mock, ai_mock, -1.0, 4)
	dome16.set("phase", 2) # DEFENSE_RHYTHM
	dome16.set("is_active", true)
	var z16: Array = dome16.get("target_zones")
	assert(z16.size() == 6, "Expected 6 target zones")
	var icon_m0: MeshInstance3D = z16[0].get("outcome_icon_mesh") as MeshInstance3D
	var icon_m1: MeshInstance3D = z16[1].get("outcome_icon_mesh") as MeshInstance3D
	assert(icon_m0 != null and icon_m1 != null and icon_m0.mesh != null and icon_m0.mesh == icon_m1.mesh, "Zones must share OutcomeIconQuad mesh")
	assert(icon_m0.visible == false, "Outcome icon mesh must start hidden")

	# 20a. Player attacking -> unblocked hit morphs box/circle into green success check
	dome16.set("attacker", p_mock)
	dome16.set("defender", ai_mock)
	dome16.set("_last_role_is_attack", 1)
	var n_hit_ok: Dictionary = { "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	dome16.set("hits", [n_hit_ok])
	dome16.call("_resolve_unblocked_hit", n_hit_ok, z16[0])
	assert(String(z16[0].get("outcome_kind")) == "hit_success", "Player landing clean hit must morph zone to hit_success")
	assert((z16[0].get("box_mesh") as MeshInstance3D).visible == false, "box_mesh must hide during hit_success morph")
	assert((z16[0].get("circle_mesh") as MeshInstance3D).visible == false, "circle_mesh must hide during hit_success morph")
	assert((z16[0].get("inner_mesh") as MeshInstance3D).visible == true, "inner_mesh backdrop must show during hit_success morph")
	assert(icon_m0.visible == true, "outcome_icon_mesh must show during hit_success morph")
	var icon_mat0: StandardMaterial3D = z16[0].get("outcome_icon_mat") as StandardMaterial3D
	assert(icon_mat0 != null and icon_mat0.albedo_texture != null, "Outcome icon must bind non-null texture")

	# 20b. Non-collision: highlighting zone 2 preserves zone 0 outcome; highlighting zone 0 immediately clears zone 0 outcome
	dome16.call("_update_defense_zone_highlights", 2, 2, -1)
	assert(String(z16[0].get("outcome_kind")) == "hit_success" and icon_m0.visible == true, "Highlighting another zone must keep zone 0 outcome icon")
	dome16.call("_update_defense_zone_highlights", 0, 3, -1)
	assert(float(z16[0].get("outcome_timer")) <= 0.0 and icon_m0.visible == false, "Highlighting zone 0 as active note must clear its outcome immediately")

	# 20c. Player defending outcomes: GREEN deflect, YELLOW block, X guard, hit_taken, clash_win + expiry tick
	dome16.set("attacker", ai_mock)
	dome16.set("defender", p_mock)
	dome16.set("_last_role_is_attack", 0)
	var n_def_g: Dictionary = { "zone_id": 0, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	var n_def_y: Dictionary = { "zone_id": 1, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	var n_def_x: Dictionary = { "zone_id": 2, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	var n_def_t: Dictionary = { "zone_id": 3, "is_charged": false, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	var n_def_c: Dictionary = { "zone_id": 4, "is_charged": true, "is_charged_v3": false, "is_hammer": false, "tier": "SOLIDO", "resolved": false }
	dome16.set("hits", [n_def_g, n_def_y, n_def_x, n_def_t, n_def_c])
	dome16.call("_resolve_hand_block", n_def_g, z16[0], 0, "GREEN")
	dome16.call("_resolve_hand_block", n_def_y, z16[1], 1, "YELLOW")
	dome16.call("_resolve_cross_arm_guard", n_def_x, z16[2])
	dome16.call("_resolve_unblocked_hit", n_def_t, z16[3])
	dome16.call("_resolve_fist_clash", n_def_c, z16[4], 0)
	assert(String(z16[0].get("outcome_kind")) == "deflect_green", "GREEN block must morph to deflect_green")
	assert(String(z16[1].get("outcome_kind")) == "block_yellow", "YELLOW block must morph to block_yellow")
	assert(String(z16[2].get("outcome_kind")) == "guard_x", "Cross arm guard must morph to guard_x")
	assert(String(z16[3].get("outcome_kind")) == "hit_taken", "Unblocked hit on player must morph to hit_taken")
	assert(String(z16[4].get("outcome_kind")) == "clash_win", "Fist clash tie/win must morph to clash_win")
	assert((z16[2].get("box_mesh") as MeshInstance3D).visible == false and (z16[2].get("outcome_icon_mesh") as MeshInstance3D).visible == true, "Guard X must hide box and show shield icon")

	# Advance outcome timers past expiration and verify clean restore
	dome16.call("_tick_zone_outcomes", 0.75)
	assert(float(z16[0].get("outcome_timer")) == 0.0 and icon_m0.visible == false and (z16[0].get("inner_mesh") as MeshInstance3D).visible == false, "Outcome icon must expire after 0.75s")
	assert((z16[0].get("box_mesh") as MeshInstance3D).visible == true, "box_mesh must restore after defense outcome expiry")

	# Runtime Dome #21: Central Turn Prompts + 0.45s Attack Intro Pause (Option 2)
	var dd21_s: GDScript = load("res://scripts/DramaticDirector.gd") as GDScript
	var dd_test: Node3D = dd21_s.new() as Node3D
	root.add_child(dd_test)
	dd_test.set("is_in_intro", false)
	dd_test.set("_cam", cam)
	dd_test.call("_build_camera_overlays")
	var cp_anchor: Node3D = dd_test.get("_center_prompt_anchor") as Node3D
	var cp_title: Label3D = dd_test.get("_center_prompt_title") as Label3D
	assert(cp_anchor != null and cp_anchor.get_parent() == cam, "Center prompt anchor must be mounted directly on XRCamera3D")
	assert(absf(cp_anchor.position.x) < 0.01 and absf(cp_anchor.position.y) <= 0.05 and cp_anchor.position.z < -0.5, "Center prompt anchor must sit at center of camera view")
	assert(cp_anchor.visible == false, "Center prompt anchor must start hidden")

	var dome17: Node3D = dome_s.new()
	root.add_child(dome17)
	p_mock.set("current_ki", 60.0)
	ai_mock.set("current_ki", 60.0)
	dome17.call("setup", p_mock, ai_mock, -1.0, 4)
	assert(absf(float(dome17.get("attack_intro_pause_timer")) - 0.45) < 0.01, "Option 2 must initialize 0.45s attack intro pause when player attacks")
	assert(cp_anchor.visible == true and String(cp_title.text) == "¡TE TOCA ATACAR!", "Attack start must display central prompt '¡TE TOCA ATACAR!' (got '%s')" % String(cp_title.text))
	var t_before_pause: float = float(dome17.get("time_left"))
	dome17.call("_process_attack_recording", 0.20)
	assert(absf(float(dome17.get("time_left")) - t_before_pause) < 0.001, "time_left must NOT tick down during 0.45s attack intro pause")
	assert(float(dome17.get("attack_intro_pause_timer")) > 0.20, "attack_intro_pause_timer must still be active at 0.20s")
	dome17.call("_process_attack_recording", 0.30)
	assert(float(dome17.get("attack_intro_pause_timer")) == 0.0, "attack_intro_pause_timer must unlock after 0.45s")

	# 21b. Defense transition + Ki-Break finisher prompt
	dome17.set("attacker", ai_mock)
	dome17.set("defender", p_mock)
	dome17.set("hits", [{ "zone_id": 0, "resolved": false }])
	dome17.call("_begin_phase_transition", "start_defense", 0.55, "DEF", Color.CYAN)
	assert(cp_anchor.visible == true and String(cp_title.text) == "¡TE TOCA DEFENDER!", "Defense transition must show '¡TE TOCA DEFENDER!'")
	dome17.call("_start_unblockable_ki_break", p_mock, ai_mock)
	assert(cp_anchor.visible == true and String(cp_title.text) == "¡HAZ EL REMATE!", "Player Ki-Break finisher must show '¡HAZ EL REMATE!'")

	# 21c. FollowUp intro pauses (Continue Sequence vs Slam Finisher)
	var fu_ps: GDScript = load("res://scripts/FollowUpSequenceController.gd") as GDScript
	var fu_prompt: Node3D = fu_ps.new() as Node3D
	root.add_child(fu_prompt)
	fu_prompt.set("attacker", p_mock)
	fu_prompt.set("defender", ai_mock)
	fu_prompt.set("chain_depth", 1)
	fu_prompt.set("_intro_pause_total", 1.0)
	fu_prompt.call("_enter_intro_pause", "")
	assert(String(cp_title.text) == "¡CONTINUA LA SECUENCIA!", "FollowUp depth 1 must show '¡CONTINUA LA SECUENCIA!'")
	fu_prompt.call("_enter_intro_pause", "hammer_slam_chain")
	assert(String(cp_title.text) == "¡HAZ EL REMATE!", "Hammer slam follow-up chain must show '¡HAZ EL REMATE!'")
	Engine.time_scale = 1.0

	# 21d. Auto-expiry in real time hides center prompt without duplicate anchors (DramaticDirector caps real_delta at 0.05s/tick)
	for _t_cp in range(26):
		dd_test.call("_process", 0.05)
	assert(cp_anchor.visible == false, "Center prompt must auto-hide after real-time duration expires")
	Engine.time_scale = 1.0

	# Teardown cleanly without leaving leaked nodes
	for n in [mini, dome, dome2, dome3, dome4, dome5, dome6, dome7, dome8, dome9, dome10, dome11, dome12, dome13, dome14, dome15, dome16, dome17, fu_prompt, dd_test, lockon_t, hud_t, rig, ai_mock]:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.free()

	print("MELEE_FULL_SUITE_PASSED")
	quit(0)
	return true
