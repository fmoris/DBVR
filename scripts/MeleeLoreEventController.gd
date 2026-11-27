class_name MeleeLoreEventController
extends Node3D

## MeleeLoreEventController (Godot 4.3+ / 4.8 VR)
## Orquesta los 7 Eventos Dinámicos del Lore de Dragon Ball Z dentro de la fase Melee:
## 1. FIST_FLURRY_CLASH (Ataque simultáneo de ráfaga con tira y afloja)
## 2. METEOR_SMASH (Lanzar al aire, Z-Vanish arriba y estrellar en cráter -> listo para Super)
## 3. Z_VANISH_WAR (Cadena de teletransportes tácticos quemando Ki)
## 4. GUARD_PRESSURE_BREAK (Presión contra Guardia Cruzada / Onda de defensa)
## 5. EXPLOSIVE_WAVE (Kiai explosivo de emergencia para cortar combos a costa de Ki)
## 6. SONIC_Z_BURST (Persecución aérea en 3 saltos tras múltiples golpes sónicos)
## 7. TACTICAL_STANDOFF (Desenganche Z / salto atrás neutro al agotar Ki, cancelar o empatar)

enum LoreEventType {
	NONE = 0,
	FIST_FLURRY_CLASH = 1,
	METEOR_SMASH = 2,
	Z_VANISH_WAR = 3,
	GUARD_PRESSURE_BREAK = 4,
	EXPLOSIVE_WAVE = 5,
	SONIC_Z_BURST = 6,
	TACTICAL_STANDOFF = 7
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
var _clash_punch_count: int = 0
var _stick_debounce: float = 0.0
var _crater_target_pos: Vector3 = Vector3.ZERO
var _meteor_smash_positions: Dictionary = {}
var _base_title_txt: String = ""
var _kiai_sep_dist: float = 10.0
var _vanish_hop_grace: float = 0.0
var _burst_hop_window: float = 1.05
var _burst_guard_hold_cd: float = 0.0
var _char_script_cache_lore: GDScript = null
var _standoff_mode: String = "cancel"
var _standoff_sep_dist: float = 8.5
var _standoff_reason: String = ""

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
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()

	if src == "explosive_wave_input":
		var ew_req: float = float(cfg.melee_explosive_wave_cost) if cfg.get("melee_explosive_wave_cost") != null else 16.0
		if def_ki >= ew_req and consec_hits_taken >= 2:
			return LoreEventType.EXPLOSIVE_WAVE
		return LoreEventType.NONE

	if src == "z_vanish":
		var zv_req: float = float(ctx.get("vanish_cost", float(cfg.melee_vanish_cost) if cfg.get("melee_vanish_cost") != null else 10.0))
		if last_ev != LoreEventType.Z_VANISH_WAR and atk_ki >= zv_req and bp_ratio >= 0.70:
			return LoreEventType.Z_VANISH_WAR
		return LoreEventType.NONE

	if src == "fist_clash":
		if last_ev != LoreEventType.FIST_FLURRY_CLASH and atk_ki >= 16.0 and def_ki >= 16.0 and bp_ratio >= 0.70 and bp_ratio <= 1.43:
			return LoreEventType.FIST_FLURRY_CLASH
		return LoreEventType.NONE

	if src == "guard_abuse":
		if last_ev != LoreEventType.GUARD_PRESSURE_BREAK and ((consec_guard_x >= 2) or (consec_guard_x >= 1 and bp_ratio >= 1.80 and def_ki <= 26.0) or (consec_guard_x >= 1 and def_ki <= 22.0)):
			return LoreEventType.GUARD_PRESSURE_BREAK
		return LoreEventType.NONE

	if src == "combo_end":
		var chase_req: float = float(cfg.melee_meteor_chase_cost) if cfg.get("melee_meteor_chase_cost") != null else 8.0
		if last_ev != LoreEventType.METEOR_SMASH and (has_v3_up or sonic_hits >= 1) and hits_landed >= 2 and atk_ki >= chase_req:
			return LoreEventType.METEOR_SMASH
		return LoreEventType.NONE

	if src == "combo_mid":
		var max_hits: int = int(ctx.get("max_hits", 4))
		var charged_hits: int = int(ctx.get("charged_hits", 0))
		var min_hits_req: int = maxi(3, ceili(float(max_hits) * 0.65))
		var sonic_merit: bool = (sonic_hits >= 3) or (sonic_hits >= 2 and (charged_hits >= 1 or is_furia_or_trans))
		if last_ev != LoreEventType.SONIC_Z_BURST and hits_landed >= min_hits_req and sonic_merit and atk_ki >= 18.0:
			return LoreEventType.SONIC_Z_BURST
		return LoreEventType.NONE

	return LoreEventType.NONE


## Actualización pura de la barra de tira y afloja para Choque Frenético de Puños
static func compute_fist_clash_step(current_progress: float, player_punches: int, bp_ratio: float, delta: float) -> float:
	var bp_scale: float = clampf(sqrt(maxf(bp_ratio, 0.1)), 0.70, 1.45)
	var player_push: float = float(maxi(player_punches, 0)) * 0.085 * bp_scale
	var enemy_pull: float = (0.28 / bp_scale) * maxf(delta, 0.0)
	return clampf(current_progress + player_push - enemy_pull, 0.0, 1.0)


## Exige puño cerrado (G+T) + empuje frontal hacia el rival cerca del orbe para contar golpes reales en ráfaga
static func evaluate_flurry_clash_punch(vel: Vector3, duel_axis: Vector3, fist_closed: bool, dist_to_orb: float) -> bool:
	if not fist_closed:
		return false
	var fwd: Vector3 = Vector3(duel_axis.x, 0.0, duel_axis.z)
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var spd: float = vel.length()
	var fwd_spd: float = vel.dot(fwd)
	return spd >= 1.30 and fwd_spd >= 1.05 and (dist_to_orb <= 0.55 or fwd_spd >= 1.45)


## Valida golpe frontal real para Intercambio Sónico Z-Burst y Desgarre de Guardia (elimina waggle de muñeca)
static func evaluate_sonic_burst_punch(vel: Vector3, duel_axis: Vector3, fist_closed: bool, dist_to_orb: float) -> bool:
	if not fist_closed:
		return false
	var fwd: Vector3 = Vector3(duel_axis.x, 0.0, duel_axis.z)
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var spd: float = vel.length()
	var fwd_spd: float = vel.dot(fwd)
	return spd >= 1.45 and fwd_spd >= 0.85 and (dist_to_orb <= 0.42 or fwd_spd >= 1.35)


## Pasiva canon simétrica de Goku: en Furia o Kaioken consume 30% menos Ki durante el choque de puños
static func compute_flurry_clash_ki_drain_rate(base_drain: float, char_name: String, is_furia: bool, form_name: String) -> float:
	var cn_l: String = char_name.to_lower()
	var fn_l: String = form_name.to_lower()
	if "goku" in cn_l and (is_furia or "kaioken" in fn_l):
		return base_drain * 0.70
	return base_drain


static func _extract_char_and_form(fighter: Node3D) -> Array[String]:
	var c_name: String = ""
	var f_name: String = ""
	if fighter and is_instance_valid(fighter):
		var cd: Variant = fighter.get("character_data")
		if cd and cd.get("character_name") != null:
			c_name = String(cd.get("character_name"))
		var tf: Variant = fighter.get("current_transformation")
		if tf and tf.get("form_name") != null:
			f_name = String(tf.get("form_name"))
	return [c_name, f_name]


## Calcula posiciones 3D en diagonal dentro de la arena para Meteor Smash (nunca recto vertical)
static func compute_meteor_smash_positions(crater_pos: Vector3, duel_axis: Vector3, ground_y: float) -> Dictionary:
	var axis := Vector3(duel_axis.x, 0.0, duel_axis.z)
	axis = axis.normalized() if axis.length_squared() > 0.001 else Vector3.FORWARD
	var cx: float = clampf(crater_pos.x, -74.0, 74.0)
	var cz: float = clampf(crater_pos.z, -74.0, 74.0)
	var air_x: float = clampf(cx + axis.x * 7.5, -74.0, 74.0)
	var air_z: float = clampf(cz + axis.z * 7.5, -74.0, 74.0)
	var crater_x: float = clampf(cx + axis.x * 13.5, -74.0, 74.0)
	var crater_z: float = clampf(cz + axis.z * 13.5, -74.0, 74.0)
	var px: float = clampf(crater_x - axis.x * 14.5, -74.0, 74.0)
	var pz: float = clampf(crater_z - axis.z * 14.5, -74.0, 74.0)
	return {
		"air_victim_pos": Vector3(air_x, ground_y + 11.5, air_z),
		"above_attacker_pos": Vector3(clampf(air_x - axis.x * 1.2, -74.0, 74.0), ground_y + 12.8, clampf(air_z - axis.z * 1.2, -74.0, 74.0)),
		"crater_ground_pos": Vector3(crater_x, ground_y, crater_z),
		"post_slam_attacker_pos": Vector3(px, ground_y + 5.2, pz)
	}


func configure_standoff(mode: String) -> void:
	_standoff_mode = mode


static func get_standoff_preset(mode: String) -> Dictionary:
	match mode:
		"mutual_exhaustion":
			return {
				"title": "😤 ¡AGOTAMIENTO MUTUO — RESPIRO Z!",
				"prompt": "Ambos al límite de Ki — salto atrás sincronizado (+10 Ki)",
				"color": Color(0.55, 0.88, 1.0),
				"distance": 9.5,
				"ki_recovery": 10.0,
				"reason": "😤 Agotamiento mutuo: Respiro Z y separación táctica (9.5m)."
			}
		"sim_draw":
			return {
				"title": "⚡ ¡TABLAS EN EL INTERCAMBIO!",
				"prompt": "Nadie rompió la guardia — Desenganche Z táctico",
				"color": Color(1.0, 0.88, 0.25),
				"distance": 9.0,
				"ki_recovery": 0.0,
				"reason": "⚡ Tablas defensivas en el intercambio: Desenganche Z (9.0m)."
			}
		"no_ki_turnover":
			return {
				"title": "💨 ¡SIN KI PARA CONTRAATACAR!",
				"prompt": "Desenganche Z — distancia para recargar Ki",
				"color": Color(0.35, 0.92, 1.0),
				"distance": 8.5,
				"ki_recovery": 0.0,
				"reason": "💨 Sin Ki suficiente para continuar ofensiva: Desenganche Z (8.5m)."
			}
		"ki_break_pass":
			return {
				"title": "💨 ¡DESENGANCHE Z!",
				"prompt": "Rival exhausto se recompone — reposicionamiento",
				"color": Color(0.45, 0.95, 0.85),
				"distance": 8.0,
				"ki_recovery": 0.0,
				"reason": "💨 Oportunidad expirada: Desenganche Z limpio (8.0m)."
			}
		_:
			return {
				"title": "💨 ¡DESENGANCHE Z — REPOSICIONAMIENTO!",
				"prompt": "Salto atrás táctico (Kensēi) — midiendo distancia",
				"color": Color(0.35, 0.92, 1.0),
				"distance": 8.5,
				"ki_recovery": 0.0,
				"reason": "💨 Desenganche Z táctico: separación limpia (8.5m)."
			}


static func evaluate_flurry_clash_resolution(p_ki: float, e_ki: float, tug_progress: float, p_punches: int, timer_left: float) -> String:
	if p_ki <= 0.0 and e_ki <= 0.0:
		return "standoff_mutual"
	if e_ki <= 0.0 and p_punches <= 0:
		return "standoff_draw"
	if p_ki <= 0.0:
		return "enemy_win"
	if e_ki <= 0.0 or tug_progress >= 0.98:
		return "player_win"
	if tug_progress <= 0.02:
		return "enemy_win"
	if timer_left <= 0.0:
		if p_punches <= 0 and tug_progress >= 0.45 and tug_progress <= 0.55:
			return "standoff_draw"
		return "player_win" if tug_progress >= 0.50 else "enemy_win"
	return "continue"


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
	_clash_punch_count = 0
	_stick_debounce = 0.0
	_vanish_hop_grace = 0.0
	_burst_guard_hold_cd = 0.0
	_kiai_sep_dist = 10.0
	_base_title_txt = ""

	_ensure_visuals()
	_hide_all_visuals()

	var title_txt: String = ""
	var axis: Vector3 = _dome.get("_duel_axis") if (_dome and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var vic_origin: Vector3 = _defender.global_position
	var gy: float = 0.15
	if _defender.has_method("get_ground_elevation"):
		gy = float(_defender.get_ground_elevation(vic_origin))
	_crater_target_pos = Vector3(vic_origin.x, gy, vic_origin.z)

	var cfg_ev: KiEconomyConfig = KiEconomyConfig.get_default()
	match event_type:
		LoreEventType.FIST_FLURRY_CLASH:
			_event_timer = 3.2
			title_txt = "⚡ ¡CHOQUE DE PUÑOS! — LLENA TU BARRA ⚡"
			if _hud_root:
				_hud_root.visible = true
			if _tug_bar_root:
				_tug_bar_root.visible = true
			if _event_orb:
				_event_orb.visible = true
				_event_orb.scale = Vector3.ONE
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(1.0, 0.88, 0.18, 0.90)
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(1.0, 0.92, 0.25)
			if _prompt_label:
				_prompt_label.text = "¡PUÑO FRONTAL (G+T)! TÚ 50%% ⚔️ 50%% RIVAL  |  ⏱ %.1fs" % _event_timer
			_update_tug_bar_visual()
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation(Vector3(clampf(vic_origin.x, -55.0, 55.0), gy + 5.5, clampf(vic_origin.z, -55.0, 55.0)))

		LoreEventType.METEOR_SMASH:
			_event_timer = 0.95
			_substep = 0
			var ms_cost: int = int(cfg_ev.melee_meteor_chase_cost) if cfg_ev.get("melee_meteor_chase_cost") != null else 8
			_base_title_txt = "🌌 ¡CAÍDA DEL METEORO!"
			title_txt = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			_meteor_smash_positions = compute_meteor_smash_positions(_crater_target_pos, axis, gy)
			_crater_target_pos = _meteor_smash_positions["crater_ground_pos"]
			if not bool(_defender.get("is_player")):
				_defender.global_position = _meteor_smash_positions["air_victim_pos"]
			elif _dome and _dome.has_method("_apply_melee_arena_surge"):
				_dome._apply_melee_arena_surge(-axis * 6.5 + Vector3.UP * 4.0, 0.25)
			_play_event_sfx("common.dodge_vanish", 1.05)
			_pulse_player_haptics(170.0, 0.70, 0.10)
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.95, 0.35, 1.0)
			if _prompt_label:
				if bool(_attacker.get("is_player")):
					_prompt_label.text = "¡PERSECUCIÓN AÉREA! Puño cerrado (G+T) arriba o Stick ↑ (%d Ki)" % ms_cost
				else:
					_prompt_label.text = "⚠️ ¡EL RIVAL TE LANZÓ AL CIELO! Prepárate para frenar..."

		LoreEventType.Z_VANISH_WAR:
			_vanish_hop = 1
			_vanish_defender_is_player = bool(_attacker.get("is_player"))
			var chaser_init: Node3D = _enemy_char if _vanish_defender_is_player else _player_char
			var reactor_init: Node3D = _player_char if _vanish_defender_is_player else _enemy_char
			var prof_zv_i: Dictionary = _get_bp_profile_for(chaser_init, reactor_init, true)
			_event_timer = clampf(0.95 * float(prof_zv_i["def_time_mult"]), 0.74, 1.30) if _vanish_defender_is_player else 0.70
			_vanish_hop_grace = 0.15
			var zv_cost_lbl: int = int(_get_vanish_info(_player_char).get("cost", 10.0))
			_base_title_txt = "💨 ¡GUERRA DE Z-VANISH! (1/3)"
			title_txt = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.30, 0.95, 1.0)
			if _prompt_label:
				if _vanish_defender_is_player:
					_prompt_label.text = "Stick (%d Ki) = ¡Contra-Blink! | Guardia X = Plantarse" % zv_cost_lbl
				else:
					_prompt_label.text = "⚡ ¡ESQUIVASTE CON Z-VANISH! A ver si el rival reacciona..."

		LoreEventType.GUARD_PRESSURE_BREAK:
			var prof_gb_i: Dictionary = _get_bp_profile_for(_attacker, _defender, true)
			_event_timer = clampf(1.70 * float(prof_gb_i["def_time_mult"]), 1.33, 2.30)
			var ew_gb_cost: int = int(cfg_ev.melee_explosive_wave_cost) if cfg_ev.get("melee_explosive_wave_cost") != null else 16
			var zv_gb_cost: int = int(_get_vanish_info(_defender).get("cost", 10.0))
			var def_ki_gb_i: float = float(_defender.get("current_ki")) if (_defender and _defender.get("current_ki") != null) else 0.0
			_base_title_txt = "💥 ¡DESGARRE DE GUARDIA!"
			title_txt = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			_play_event_sfx("common.block_guard", 0.85)
			_pulse_player_haptics(160.0, 0.75, 0.12)
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
					_prompt_label.text = "¡Puñetazo frontal (G+T) a la grieta para QUEBRAR su Guardia!"
				elif def_ki_gb_i >= float(ew_gb_cost):
					_prompt_label.text = "¡GUARDIA AGRIETADA! Abre brazos+Grips (%d Ki) o Stick=Z-Vanish (%d Ki)" % [ew_gb_cost, zv_gb_cost]
				elif def_ki_gb_i >= float(zv_gb_cost):
					_prompt_label.text = "¡GUARDIA AGRIETADA! Stick=Z-Vanish (%d Ki) o Desvío final" % zv_gb_cost
				else:
					_prompt_label.text = "⚠️ ¡SIN KI! En el último instante haz ¡DESVÍO RÁPIDO (0 Ki)!"

		LoreEventType.EXPLOSIVE_WAVE:
			_event_timer = 0.65
			_base_title_txt = "🛡️ ¡ONDA EXPLOSIVA (KIAI)!"
			title_txt = _base_title_txt
			var ew_cost: float = float(cfg_ev.melee_explosive_wave_cost) if cfg_ev.get("melee_explosive_wave_cost") != null else 16.0
			var prof_kiai: Dictionary = _get_bp_profile_for(_defender, _attacker, true)
			_kiai_sep_dist = clampf(10.0 * pow(float(prof_kiai["raw_ratio"]), 0.35), 5.5, 13.5)
			_modify_ki(_defender, -ew_cost)
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(0.25, 0.92, 1.0)
			if _prompt_label:
				_prompt_label.text = "¡Explosión de Ki liberada! (-%d Ki | Empuje %.1fm)" % [int(ew_cost), _kiai_sep_dist]
			if _attacker and _attacker.has_method("take_hit"):
				_attacker.take_hit(160.0 * float(prof_kiai["damage_scale"]), Vector3.ZERO, false)
			if _attacker and _attacker.get("procedural_animator"):
				var flinch_dir_k: Vector3 = (_attacker.global_position - _defender.global_position).normalized()
				_attacker.procedural_animator.trigger_hit_flinch(0.85, flinch_dir_k if flinch_dir_k.length_squared() > 0.01 else Vector3.BACK)
			_play_event_sfx("common.aura_burst", 1.08)
			_play_event_sfx("common.melee_hit_heavy", 0.94)
			_pulse_player_haptics(220.0, 0.95, 0.18)
			if _dome and _dome.has_method("_spawn_parry_shockwave") and _defender:
				_dome._spawn_parry_shockwave(_defender.global_position + Vector3(0.0, 0.9, 0.0))
			if get_tree() and _defender and is_instance_valid(_defender):
				var exp_pos: Vector3 = _defender.global_position + Vector3(0.0, 0.9, 0.0)
				ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), exp_pos, 3, Color(0.25, 0.92, 1.0, 0.95), true)
				KiSmokeFX.spawn_smoke(get_tree(), _defender.global_position + Vector3(0.0, 0.8, 0.0), 1.4)
				if not bool(_defender.get("is_player")):
					var dd_ew: DramaticDirector = DramaticDirector.get_active(get_tree())
					if dd_ew:
						dd_ew.show_camera_banner("💥 ¡EL RIVAL LIBERÓ ONDA EXPLOSIVA (KIAI)!", Color(0.25, 0.92, 1.0), 1.45)

		LoreEventType.SONIC_Z_BURST:
			var prof_sb_i: Dictionary = _get_bp_profile_for(_attacker, _defender, true)
			var atk_p_sb: bool = bool(_attacker.get("is_player"))
			if atk_p_sb:
				_burst_hop_window = clampf(1.05 * clampf(pow(float(prof_sb_i["raw_ratio"]), 0.20), 0.88, 1.18), 0.90, 1.25)
			else:
				_burst_hop_window = clampf(1.05 * float(prof_sb_i["def_time_mult"]), 0.82, 1.42)
			_event_timer = _burst_hop_window
			_burst_hop_timer = _burst_hop_window
			_substep = 0
			_base_title_txt = "🔥 ¡INTERCAMBIO SÓNICO Z-BURST!"
			title_txt = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			if _hud_root:
				_hud_root.visible = true
			if _event_orb:
				_event_orb.visible = true
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(1.0, 0.88, 0.18, 0.92) if atk_p_sb else Color(1.0, 0.30, 0.18, 0.94)
			if _title_label:
				_title_label.text = title_txt
				_title_label.modulate = Color(1.0, 0.88, 0.20) if atk_p_sb else Color(1.0, 0.35, 0.20)
			if _prompt_label:
				var sb_hop_lbl: int = int(cfg_ev.melee_sonic_burst_hop_cost) if cfg_ev.get("melee_sonic_burst_hop_cost") != null else 6
				if atk_p_sb:
					_prompt_label.text = "¡Golpe frontal (G+T) al Orbe! (1/3 · -%d Ki/salto | Stick ↓=Guardar Ki)" % sb_hop_lbl
				else:
					var zv_sb_lbl: int = int(_get_vanish_info(_defender).get("cost", 10.0))
					_prompt_label.text = "⚠️ ¡Z-BURST RIVAL (1/3)! Stick (%d Ki)=Cortar | Guardia X=Amortiguar" % zv_sb_lbl
			_play_event_sfx("common.dodge_vanish", 1.20)
			_pulse_player_haptics(190.0, 0.75, 0.10)
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation(Vector3(clampf(vic_origin.x + 10.0, -60.0, 60.0), gy + 9.0, clampf(vic_origin.z - 8.0, -60.0, 60.0)))

		LoreEventType.TACTICAL_STANDOFF:
			var preset_st: Dictionary = get_standoff_preset(_standoff_mode)
			_event_timer = 0.65
			_standoff_sep_dist = float(preset_st["distance"])
			_standoff_reason = String(preset_st["reason"])
			_base_title_txt = String(preset_st["title"])
			title_txt = _base_title_txt
			var ki_rec_st: float = float(preset_st["ki_recovery"])
			if ki_rec_st > 0.0:
				_modify_ki(_player_char, ki_rec_st)
				_modify_ki(_enemy_char, ki_rec_st)
			if _hud_root:
				_hud_root.visible = true
			if _title_label:
				_title_label.text = _base_title_txt
				_title_label.modulate = preset_st["color"] as Color
			if _prompt_label:
				_prompt_label.text = String(preset_st["prompt"])
			_play_event_sfx("common.dodge_vanish", 1.05)
			_pulse_player_haptics(145.0, 0.50, 0.08)
			if is_inside_tree() and get_tree():
				if _enemy_char and is_instance_valid(_enemy_char):
					KiSmokeFX.spawn_smoke(get_tree(), _enemy_char.global_position + Vector3(0.0, 0.35, 0.0), 1.1)
				var dd_st: DramaticDirector = DramaticDirector.get_active(get_tree())
				if dd_st:
					dd_st.show_camera_banner(_base_title_txt, preset_st["color"] as Color, 1.30)

	_sync_event_orb_world_pos()
	emit_signal("lore_event_started", event_type, title_txt)
	return true


func process_event(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3) -> void:
	if not is_event_active:
		return

	_sync_event_orb_world_pos()
	_clash_punch_cd_l = maxf(_clash_punch_cd_l - delta, 0.0)
	_clash_punch_cd_r = maxf(_clash_punch_cd_r - delta, 0.0)
	_stick_debounce = maxf(_stick_debounce - delta, 0.0)
	_vanish_hop_grace = maxf(_vanish_hop_grace - delta, 0.0)
	_burst_guard_hold_cd = maxf(_burst_guard_hold_cd - delta, 0.0)
	_event_timer -= delta

	var l_closed: bool = _is_fist_closed_ctrl(l_ctrl)
	var r_closed: bool = _is_fist_closed_ctrl(r_ctrl)
	var l_grip: bool = _ctrl_float(l_ctrl, &"grip") > 0.50 or _ctrl_pressed(l_ctrl, &"grip_click")
	var r_grip: bool = _ctrl_float(r_ctrl, &"grip") > 0.50 or _ctrl_pressed(r_ctrl, &"grip_click")
	var stick_l: Vector2 = _ctrl_vec2(l_ctrl, &"primary")
	var stick_r: Vector2 = _ctrl_vec2(r_ctrl, &"primary")

	if _title_label and _base_title_txt != "" and active_event_type in [LoreEventType.METEOR_SMASH, LoreEventType.Z_VANISH_WAR, LoreEventType.GUARD_PRESSURE_BREAK, LoreEventType.SONIC_Z_BURST]:
		var disp_t: float = maxf(_burst_hop_timer if active_event_type == LoreEventType.SONIC_Z_BURST else _event_timer, 0.0)
		_title_label.text = "%s (%.1fs)" % [_base_title_txt, disp_t]

	match active_event_type:
		LoreEventType.FIST_FLURRY_CLASH:
			_process_fist_clash(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed)
		LoreEventType.METEOR_SMASH:
			_process_meteor_smash(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed, stick_l, stick_r)
		LoreEventType.Z_VANISH_WAR:
			_process_z_vanish_war(delta, l_ctrl, r_ctrl, l_closed, r_closed, stick_l, stick_r)
		LoreEventType.GUARD_PRESSURE_BREAK:
			_process_guard_break(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed, l_grip, r_grip, stick_l, stick_r)
		LoreEventType.EXPLOSIVE_WAVE:
			if _event_timer <= 0.0:
				_finish_event({ "action": "separate", "distance": _kiai_sep_dist, "reason": "🛡️ ¡Onda Explosiva (Kiai)! Separación %.1fm." % _kiai_sep_dist })
		LoreEventType.SONIC_Z_BURST:
			_process_sonic_z_burst(delta, l_ctrl, r_ctrl, l_vel, r_vel, l_closed, r_closed, stick_l, stick_r)
		LoreEventType.TACTICAL_STANDOFF:
			if _event_timer <= 0.0:
				_finish_event({ "action": "separate", "distance": _standoff_sep_dist, "reason": _standoff_reason })


func inject_virtual_clash_punch() -> void:
	if not is_event_active or active_event_type != LoreEventType.FIST_FLURRY_CLASH:
		return
	_clash_punch_count += 1
	var bp_r: float = _get_player_bp_ratio()
	_tug_progress = compute_fist_clash_step(_tug_progress, 1, bp_r, 0.0)
	_update_tug_bar_visual()
	if _event_orb and is_instance_valid(_event_orb) and _dome and _dome.has_method("_spawn_hit_spark"):
		_dome._spawn_hit_spark(_event_orb.global_position)
	if _dome and _dome.get("audio_player"):
		var ap_v: AudioStreamPlayer3D = _dome.get("audio_player") as AudioStreamPlayer3D
		if ap_v:
			ap_v.pitch_scale = clampf(0.95 + _tug_progress * 0.35 + minf(float(_clash_punch_count) * 0.015, 0.15), 0.90, 1.45)
			var act_v: String = "common.melee_hit_heavy" if (_clash_punch_count % 3 == 0) else "common.melee_hit_light"
			AudioActionManager.play_action(act_v, ap_v)


func _process_fist_clash(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool) -> void:
	# Ambos luchadores queman Ki/s durante el choque de poder cuerpo a cuerpo (con pasiva de resistencia de Goku)
	var cfg_fc: KiEconomyConfig = KiEconomyConfig.get_default()
	var fc_drain: float = float(cfg_fc.melee_flurry_clash_drain_per_sec) if cfg_fc.get("melee_flurry_clash_drain_per_sec") != null else 5.0
	var p_cf: Array[String] = _extract_char_and_form(_player_char)
	var e_cf: Array[String] = _extract_char_and_form(_enemy_char)
	var p_furia: bool = _player_char != null and is_instance_valid(_player_char) and bool(_player_char.get("is_in_furia"))
	var e_furia: bool = _enemy_char != null and is_instance_valid(_enemy_char) and bool(_enemy_char.get("is_in_furia"))
	var p_drain: float = compute_flurry_clash_ki_drain_rate(fc_drain, p_cf[0], p_furia, p_cf[1])
	var e_drain: float = compute_flurry_clash_ki_drain_rate(fc_drain, e_cf[0], e_furia, e_cf[1])
	_modify_ki(_player_char, -p_drain * delta)
	_modify_ki(_enemy_char, -e_drain * delta)

	var p_ki: float = float(_player_char.get("current_ki")) if (_player_char and _player_char.get("current_ki") != null) else 0.0
	var e_ki: float = float(_enemy_char.get("current_ki")) if (_enemy_char and _enemy_char.get("current_ki") != null) else 0.0

	var axis_fc: Vector3 = _dome.get("_duel_axis") if (_dome and is_instance_valid(_dome) and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var orb_pos: Vector3 = _event_orb.global_position if (_event_orb and is_instance_valid(_event_orb)) else global_position
	var d_orb_l: float = l_ctrl.global_position.distance_to(orb_pos) if (l_ctrl and is_instance_valid(l_ctrl)) else 0.45
	var d_orb_r: float = r_ctrl.global_position.distance_to(orb_pos) if (r_ctrl and is_instance_valid(r_ctrl)) else 0.45

	var p_punches: int = 0
	if _clash_punch_cd_l <= 0.0 and evaluate_flurry_clash_punch(l_vel, axis_fc, l_closed, d_orb_l):
		_clash_punch_cd_l = 0.09
		p_punches += 1
		if _event_orb:
			if _dome and _dome.has_method("_spawn_hit_spark"):
				_dome._spawn_hit_spark(_event_orb.global_position)
			if is_inside_tree() and get_tree():
				ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), _event_orb.global_position, Color(0.25, 0.92, 1.0, 0.95), 0.75)
	if _clash_punch_cd_r <= 0.0 and evaluate_flurry_clash_punch(r_vel, axis_fc, r_closed, d_orb_r):
		_clash_punch_cd_r = 0.09
		p_punches += 1
		if _event_orb:
			if _dome and _dome.has_method("_spawn_hit_spark"):
				_dome._spawn_hit_spark(_event_orb.global_position)
			if is_inside_tree() and get_tree():
				ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), _event_orb.global_position, Color(1.0, 0.85, 0.25, 0.95), 0.75)

	if p_punches > 0:
		_clash_punch_count += p_punches
		if _enemy_char and is_instance_valid(_enemy_char) and _enemy_char.get("procedural_animator"):
			_enemy_char.procedural_animator.trigger_melee_strike(randi() % 4)
		if _dome:
			if _dome.has_method("_pulse_player_both_hands"):
				_dome._pulse_player_both_hands(190.0, 0.85, 0.05)
			elif _dome.has_method("_pulse_defender_both_hands"):
				_dome._pulse_defender_both_hands(190.0, 0.85, 0.05)
			var ap: AudioStreamPlayer3D = _dome.get("audio_player") as AudioStreamPlayer3D
			if ap:
				ap.global_position = orb_pos
				ap.pitch_scale = clampf(0.95 + _tug_progress * 0.35 + minf(float(_clash_punch_count) * 0.015, 0.15), 0.90, 1.45)
				var clash_sfx: String = "common.melee_hit_heavy" if (_clash_punch_count % 3 == 0) else "common.melee_hit_light"
				AudioActionManager.play_action(clash_sfx, ap)

	var bp_r: float = _get_player_bp_ratio()
	var passive_tag: String = ""
	# Asimetría Canon Vegeta (Orgullo Saiyan): +15% de empuje en choque si está en Furia
	if p_furia and "vegeta" in p_cf[0].to_lower():
		bp_r *= 1.15
		passive_tag = " | 🔥 ORGULLO x1.15"
	if e_furia and "vegeta" in e_cf[0].to_lower():
		bp_r /= 1.15
	if passive_tag.is_empty() and p_drain < fc_drain - 0.01:
		passive_tag = " | ⚡ ESPÍRITU -30% KI"
	_tug_progress = compute_fist_clash_step(_tug_progress, p_punches, bp_r, delta)
	_update_tug_bar_visual()
	_sync_event_orb_world_pos()

	if _event_orb and is_instance_valid(_event_orb):
		var pulse_s: float = 0.95 + sin(Time.get_ticks_msec() * 0.035) * 0.18 + float(p_punches) * 0.22
		_event_orb.scale = Vector3.ONE * pulse_s
		if _event_orb_mat:
			if _tug_progress < 0.40:
				_event_orb_mat.albedo_color = Color(1.0, 0.30, 0.18, 0.92)
			elif _tug_progress > 0.60:
				_event_orb_mat.albedo_color = Color(0.28, 0.94, 1.0, 0.94)
			else:
				_event_orb_mat.albedo_color = Color(1.0, 0.88, 0.18, 0.90)
	if _prompt_label:
		var p_pct: int = int(roundf(_tug_progress * 100.0))
		var e_pct: int = 100 - p_pct
		_prompt_label.text = "¡PUÑO FRONTAL (G+T)! TÚ %d%% ⚔️ %d%% RIVAL  |  ⏱ %.1fs%s" % [p_pct, e_pct, maxf(_event_timer, 0.0), passive_tag]

	match evaluate_flurry_clash_resolution(p_ki, e_ki, _tug_progress, _clash_punch_count, _event_timer):
		"standoff_mutual":
			_modify_ki(_player_char, 10.0)
			_modify_ki(_enemy_char, 10.0)
			_finish_event({ "action": "separate", "distance": 9.5, "reason": "😤 Agotamiento mutuo en Choque de Puños: Respiro Z (+10 Ki)." })
		"standoff_draw":
			_finish_event({ "action": "separate", "distance": 9.0, "reason": "⚡ Tablas en Choque de Puños sin golpe decisivo: Desenganche Z." })
		"player_win":
			_resolve_fist_clash_winner(_player_char, _enemy_char, _tug_progress)
		"enemy_win":
			_resolve_fist_clash_winner(_enemy_char, _player_char, 1.0 - _tug_progress)


func _resolve_fist_clash_winner(win_node: Node3D, lose_node: Node3D, win_prog: float) -> void:
	var margin: float = clampf((win_prog - 0.50) * 2.0, 0.0, 1.0)
	var win_was_furia: bool = win_node != null and is_instance_valid(win_node) and bool(win_node.get("is_in_furia"))
	var prof_fcw: Dictionary = _get_bp_profile_for(win_node, lose_node, true)
	var dmg: float = lerpf(900.0, 1300.0, margin) * float(prof_fcw["damage_scale"])
	var win_is_p: bool = win_node != null and is_instance_valid(win_node) and bool(win_node.get("is_player"))
	if win_is_p and _clash_punch_count <= 0 and win_prog <= 0.55:
		_finish_event({ "action": "separate", "distance": 8.5, "reason": "⚡ Empuje contenido sin ráfaga: Desenganche Z." })
		return
	var exp_pos: Vector3 = _event_orb.global_position if (_event_orb and is_instance_valid(_event_orb)) else global_position

	if lose_node and is_instance_valid(lose_node) and lose_node.has_method("take_hit"):
		lose_node.take_hit(dmg, Vector3.ZERO, false)
	var cfg_fcw: KiEconomyConfig = KiEconomyConfig.get_default()
	var fc_win_ki: float = float(cfg_fcw.melee_flurry_clash_win_ki_reward) if cfg_fcw.get("melee_flurry_clash_win_ki_reward") != null else 18.0
	var fc_win_bp: float = 500.0 * float(prof_fcw["attacker_underdog_bp_mult"])
	if win_node and is_instance_valid(win_node):
		_modify_ki(win_node, fc_win_ki)
		if win_node.has_method("increase_np"):
			win_node.increase_np(fc_win_bp)
		if win_was_furia and not bool(win_node.get("is_in_zenkai_state")) and win_node.has_method("trigger_comeback_zenkai"):
			win_node.trigger_comeback_zenkai()
		if win_node.has_method("_log_combat_event"):
			win_node._log_combat_event("💥 ¡GANÓ EL CHOQUE DE PUÑOS! (-%.0f BP rival | +%d Ki | +%d BP)" % [dmg, int(fc_win_ki), int(roundf(fc_win_bp))], "success")

	if _dome and _dome.has_method("_trigger_hit_stop"):
		_dome._trigger_hit_stop(0.10)
	if _dome and _dome.has_method("_spawn_parry_shockwave"):
		_dome._spawn_parry_shockwave(exp_pos)
	if is_inside_tree() and get_tree():
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), exp_pos, 3, Color(0.25, 0.92, 1.0, 0.95) if win_is_p else Color(1.0, 0.28, 0.16, 0.95), true)
		var dd_fc: DramaticDirector = DramaticDirector.get_active(get_tree())
		if dd_fc:
			var ban_txt: String = "💥 ¡CHOQUE DE PUÑOS GANADO! (+%d KI / +%d BP)" % [int(fc_win_ki), int(roundf(fc_win_bp))] if win_is_p else "⚠️ ¡PERDISTE EL CHOQUE DE PUÑOS!"
			dd_fc.show_camera_banner(ban_txt, Color(0.25, 0.96, 1.0) if win_is_p else Color(1.0, 0.30, 0.22), 1.65)
	_play_event_sfx("common.melee_hit_heavy", 0.90)

	var lose_ki: float = float(lose_node.get("current_ki")) if (lose_node and is_instance_valid(lose_node) and lose_node.get("current_ki") != null) else 50.0
	if (win_prog >= 0.72 or lose_ki < 10.0) and (not win_is_p or _clash_punch_count >= 2):
		_finish_event({
			"action": "launch",
			"victim": lose_node
		})
	else:
		_finish_event({
			"action": "winner_offense",
			"winner": win_node,
			"loser": lose_node,
			"bonus_hits": 2,
			"comeback_momentum": float(prof_fcw["raw_ratio"]) < 0.85
		})


func _process_meteor_smash(_delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var cfg_m: KiEconomyConfig = KiEconomyConfig.get_default()
	var chase_cost: float = float(cfg_m.melee_meteor_chase_cost) if cfg_m.get("melee_meteor_chase_cost") != null else 8.0
	var axis: Vector3 = _dome.get("_duel_axis") if (_dome and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var gy: float = _crater_target_pos.y
	var m_pos: Dictionary = _meteor_smash_positions if not _meteor_smash_positions.is_empty() else compute_meteor_smash_positions(_crater_target_pos, axis, gy)
	var prof_ms: Dictionary = _get_bp_profile_for(_attacker, _defender, true)

	if _substep == 0:
		var chase_triggered: bool = false
		if atk_is_player:
			var cam: Camera3D = _get_cam()
			var high_hands: bool = cam != null and (l_closed or r_closed) and ((l_ctrl and l_ctrl.global_position.y > cam.global_position.y + 0.08) or (r_ctrl and r_ctrl.global_position.y > cam.global_position.y + 0.08))
			var up_vel: bool = (l_vel.y >= 0.85 or r_vel.y >= 0.85) and (l_closed or r_closed)
			if high_hands or up_vel or stick_l.y >= 0.55 or stick_r.y >= 0.55:
				chase_triggered = true
		else:
			if _event_timer <= 0.45 and float(_attacker.get("current_ki")) >= chase_cost:
				chase_triggered = true

		if chase_triggered and float(_attacker.get("current_ki")) >= chase_cost:
			_modify_ki(_attacker, -chase_cost)
			_substep = 1
			_event_timer = 1.80 if atk_is_player else clampf(1.45 * float(prof_ms["def_time_mult"]), 1.13, 1.95)
			if atk_is_player:
				if _dome and _dome.has_method("perform_z_blink_relocation"):
					_dome.perform_z_blink_relocation(m_pos["above_attacker_pos"])
			elif _attacker and is_instance_valid(_attacker):
				var cam_ms: Camera3D = _get_cam()
				if cam_ms and is_instance_valid(cam_ms):
					var fwd_ms: Vector3 = -cam_ms.global_transform.basis.z
					fwd_ms.y = 0.0
					fwd_ms = fwd_ms.normalized() if fwd_ms.length_squared() > 0.001 else Vector3.FORWARD
					_attacker.global_position = cam_ms.global_position + fwd_ms * 1.45 + Vector3.UP * 1.15
				else:
					_attacker.global_position = m_pos["above_attacker_pos"]
			_play_event_sfx("common.dodge_vanish", 1.20)
			_pulse_player_haptics(185.0, 0.80, 0.12)
			_sync_event_orb_world_pos()
			if _event_orb:
				_event_orb.visible = true
			if _event_orb_mat:
				_event_orb_mat.albedo_color = Color(0.92, 0.18, 1.0, 0.95)
			_base_title_txt = "🔨 ¡ESTRÉLLALO AL SUELO!" if atk_is_player else "🔨 ¡FRENA LA CAÍDA DEL METEORO!"
			if _title_label:
				_title_label.text = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			if _prompt_label:
				if atk_is_player:
					_prompt_label.text = "¡Baja ambos puños cerrados (G+T) o golpea fuerte el orbe!"
				else:
					_prompt_label.text = "🛡️ ¡GUARDIA X (pecho) O STICK (Z-VANISH %d Ki) PARA EVITAR CRÁTER!" % int(_get_z_vanish_hop_cost(_defender))
			return

		if _event_timer <= 0.0:
			_finish_event({ "action": "complete_normal" })
	elif _substep == 1:
		var slam_hit: bool = false
		if atk_is_player:
			var down_avg: float = -(l_vel.y + r_vel.y) * 0.5
			var near_orb: bool = _event_orb != null and ((l_closed and l_ctrl and l_ctrl.global_position.distance_to(_event_orb.global_position) <= 0.34 and l_vel.length() >= 1.65) or (r_closed and r_ctrl and r_ctrl.global_position.distance_to(_event_orb.global_position) <= 0.34 and r_vel.length() >= 1.65))
			if (down_avg >= 1.10 and (l_closed or r_closed)) or near_orb:
				slam_hit = true
		else:
			var def_ki_ms: float = float(_defender.get("current_ki")) if (_defender and _defender.get("current_ki") != null) else 0.0
			var zv_ms: float = _get_z_vanish_hop_cost(_defender)
			var cam_ms_d: Camera3D = _get_cam()
			var chest_ok_ms: bool = true
			if cam_ms_d and is_instance_valid(cam_ms_d) and l_ctrl != null and r_ctrl != null:
				var mid_y_ms: float = (l_ctrl.global_position.y + r_ctrl.global_position.y) * 0.5
				chest_ok_ms = (mid_y_ms <= cam_ms_d.global_position.y + 0.10) and (mid_y_ms >= cam_ms_d.global_position.y - 0.55)
			if (stick_l.length() >= 0.65 or stick_r.length() >= 0.65) and def_ki_ms >= zv_ms:
				_modify_ki(_defender, -zv_ms)
				_play_event_sfx("common.dodge_vanish", 1.15)
				_pulse_player_haptics(195.0, 0.80, 0.12)
				if _defender and _defender.has_method("increase_np"):
					_defender.increase_np(120.0 * float(prof_ms["defender_underdog_bp_mult"]))
				if get_tree() and _defender:
					KiSmokeFX.spawn_smoke(get_tree(), _defender.global_position + Vector3(0.0, 0.8, 0.0), 1.2)
				_finish_event({ "action": "separate", "distance": 9.0, "reason": "💨 ¡Escapaste de la Caída del Meteoro con Z-Vanish!" })
				return
			elif chest_ok_ms and l_closed and r_closed and l_ctrl != null and r_ctrl != null and l_ctrl.global_position.distance_to(r_ctrl.global_position) < 0.34:
				var g_ms_cost: float = float(cfg_m.melee_guard_charged_cost) if cfg_m.get("melee_guard_charged_cost") != null else 8.0
				_modify_ki(_defender, -g_ms_cost)
				_play_event_sfx("common.block_guard", 0.92)
				_pulse_player_haptics(200.0, 0.85, 0.14)
				if _defender and _defender.has_method("take_hit"):
					_defender.take_hit(180.0 * float(prof_ms["damage_scale"]), Vector3.DOWN, false)
				if _dome and _dome.has_method("_spawn_block_spark") and _defender:
					_dome._spawn_block_spark(_defender.global_position + Vector3.UP * 1.0, Color(0.25, 0.85, 1.0))
				_finish_event({ "action": "separate", "distance": 8.0, "reason": "🛡️ ¡Caída del Meteoro amortiguada con Guardia X!" })
				return
			elif _event_timer <= 0.0:
				slam_hit = true

		if slam_hit:
			_play_event_sfx("common.melee_hit_heavy", 0.88)
			_pulse_player_haptics(240.0, 1.0, 0.24)
			if _defender and _defender.has_method("take_hit"):
				_defender.take_hit(480.0 * float(prof_ms["damage_scale"]), Vector3.DOWN, false)
			if _attacker and _attacker.has_method("increase_np"):
				_attacker.increase_np(320.0 * float(prof_ms["bp_gain_mult"]))
			var crater_stun: float = clampf(3.5 * pow(float(prof_ms["raw_ratio"]), 0.25), 2.8, 4.0)
			_finish_event({
				"action": "meteor_crater",
				"winner": _attacker,
				"victim": _defender,
				"crater_pos": _crater_target_pos,
				"crater_stun": crater_stun
			})
			return

		if _event_timer <= 0.0:
			_finish_event({ "action": "complete_normal" })


func _get_bp_profile_for(p_atk: Node3D, p_def: Node3D, is_heavy: bool = true) -> Dictionary:
	if _dome and is_instance_valid(_dome) and _dome.has_method("_get_bp_profile"):
		return _dome.call("_get_bp_profile", p_atk, p_def, is_heavy) as Dictionary
	var atk_bp: float = maxf(float(p_atk.get("current_np")) if (p_atk and is_instance_valid(p_atk) and p_atk.get("current_np") != null) else 10000.0, 100.0)
	var def_bp: float = maxf(float(p_def.get("current_np")) if (p_def and is_instance_valid(p_def) and p_def.get("current_np") != null) else 10000.0, 100.0)
	var atk_furia: bool = p_atk != null and is_instance_valid(p_atk) and bool(p_atk.get("is_in_furia"))
	var atk_t: float = float(p_atk.call("get_transformation_multiplier")) if (p_atk and is_instance_valid(p_atk) and p_atk.has_method("get_transformation_multiplier")) else 1.0
	var def_t: float = float(p_def.call("get_transformation_multiplier")) if (p_def and is_instance_valid(p_def) and p_def.has_method("get_transformation_multiplier")) else 1.0
	if _char_script_cache_lore == null:
		_char_script_cache_lore = ResourceLoader.load("res://scripts/character_instance.gd") as GDScript
	if _char_script_cache_lore:
		return _char_script_cache_lore.call("compute_melee_bp_profile", atk_bp, def_bp, atk_furia, is_heavy, atk_t, def_t, false) as Dictionary
	return {
		"raw_ratio": 1.0, "effective_ratio": 1.0, "match_trans_scale": 1.0,
		"dmg_mult": 1.0, "damage_scale": 1.0, "def_time_mult": 1.0, "ki_mult": 1.0,
		"bp_gain_mult": 1.0, "defender_underdog_bp_mult": 1.0, "attacker_underdog_bp_mult": 1.0,
		"is_dominance": false
	}


func _get_vanish_info(fighter: Node3D) -> Dictionary:
	if _dome and is_instance_valid(_dome) and _dome.has_method("_get_vanish_cost_and_label"):
		return _dome.call("_get_vanish_cost_and_label", fighter) as Dictionary
	var cfg_zv: KiEconomyConfig = KiEconomyConfig.get_default()
	var base_cost: float = float(cfg_zv.melee_vanish_cost) if cfg_zv.get("melee_vanish_cost") != null else 10.0
	if fighter and is_instance_valid(fighter):
		var cdata: Variant = fighter.get("character_data")
		if cdata and "character_name" in cdata:
			var cn: String = String(cdata.character_name).to_lower()
			if "goku" in cn:
				return { "cost": maxf(base_cost - 2.0, 4.0), "label": "💨 ¡SHUNKAN IDŌ!" }
			if "vegeta" in cn:
				return { "cost": base_cost, "label": "💨 ¡ZANZOKEN!" }
	return { "cost": base_cost, "label": "💨 ¡Z-VANISH!" }


func _get_z_vanish_hop_cost(fighter: Node3D) -> float:
	return float(_get_vanish_info(fighter).get("cost", 10.0))


func _play_event_sfx(action_id: String, pitch: float = 1.0) -> void:
	if not _dome or not is_instance_valid(_dome):
		return
	var ap: AudioStreamPlayer3D = _dome.get("audio_player") as AudioStreamPlayer3D
	if not ap or not is_instance_valid(ap):
		return
	if _event_orb and is_instance_valid(_event_orb):
		ap.global_position = _event_orb.global_position
	elif _defender and is_instance_valid(_defender):
		ap.global_position = _defender.global_position + Vector3.UP * 1.0
	ap.pitch_scale = pitch
	AudioActionManager.play_action(action_id, ap)


func _pulse_player_haptics(freq: float, amp: float, dur: float) -> void:
	if not _dome or not is_instance_valid(_dome):
		return
	if _dome.has_method("_pulse_player_both_hands"):
		_dome._pulse_player_both_hands(freq, amp, dur)
	elif _dome.has_method("_pulse_defender_both_hands"):
		_dome._pulse_defender_both_hands(freq, amp, dur)


func _process_z_vanish_war(_delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_closed: bool, r_closed: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	var reactor: Node3D = _player_char if _vanish_defender_is_player else _enemy_char
	var chaser: Node3D = _enemy_char if _vanish_defender_is_player else _player_char
	var zv_info_r: Dictionary = _get_vanish_info(reactor)
	var hop_cost: float = float(zv_info_r.get("cost", 10.0))
	var prof_zv: Dictionary = _get_bp_profile_for(chaser, reactor, true)

	if _vanish_defender_is_player:
		var stick_clicked_zw: bool = (l_ctrl != null and _ctrl_pressed(l_ctrl, &"primary_click")) or (r_ctrl != null and _ctrl_pressed(r_ctrl, &"primary_click"))
		var stick_flick: bool = _stick_debounce <= 0.0 and (stick_clicked_zw or stick_l.length() >= 0.50 or stick_r.length() >= 0.50)
		var guard_x: bool = _vanish_hop_grace <= 0.0 and l_closed and r_closed and l_ctrl != null and r_ctrl != null and l_ctrl.global_position.distance_to(r_ctrl.global_position) < 0.34
		var r_ki: float = float(reactor.get("current_ki")) if reactor and reactor.get("current_ki") != null else 0.0
		if stick_flick and r_ki >= hop_cost:
			_stick_debounce = 0.24
			_modify_ki(reactor, -hop_cost)
			_vanish_hop += 1
			_play_event_sfx("common.dodge_vanish", 1.15 + float(_vanish_hop) * 0.08)
			_pulse_player_haptics(195.0, 0.80, 0.10)
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation()
			if _vanish_hop > 3:
				_finish_event({ "action": "separate", "distance": 8.5, "reason": "💨 ¡Triple Z-Vanish empatado! Separación táctica." })
				return
			_vanish_defender_is_player = false
			_event_timer = 0.65
			_base_title_txt = "💨 ¡GUERRA DE Z-VANISH! (%d/3)" % _vanish_hop
			if _title_label:
				_title_label.text = "%s (%.1fs)" % [_base_title_txt, _event_timer]
			if _prompt_label:
				_prompt_label.text = "%s (%d/3) — A ver si el rival responde..." % [String(zv_info_r.get("label", "💨 ¡Z-VANISH!")), _vanish_hop]
			return
		elif guard_x:
			_play_event_sfx("common.block_guard", 0.95)
			_pulse_player_haptics(180.0, 0.75, 0.12)
			if reactor and reactor.has_method("take_hit"):
				reactor.take_hit(140.0 * float(prof_zv["damage_scale"]), Vector3.ZERO, false)
			_finish_event({ "action": "separate", "distance": 7.5, "reason": "🛡️ ¡Te plantaste en Guardia X tras la Guerra de Z-Vanish!" })
			return
	else:
		if _event_timer <= 0.28:
			var e_ki: float = float(reactor.get("current_ki")) if reactor and reactor.get("current_ki") != null else 0.0
			var ai_chase_prob: float = clampf(0.65 * pow(float(prof_zv["raw_ratio"]), -0.35), 0.35, 0.85)
			if _vanish_hop <= 3 and e_ki >= hop_cost + 6.0 and randf() < ai_chase_prob:
				_modify_ki(reactor, -hop_cost)
				_vanish_hop += 1
				_play_event_sfx("common.dodge_vanish", 1.15 + float(_vanish_hop) * 0.08)
				if _dome and _dome.has_method("perform_z_blink_relocation"):
					_dome.perform_z_blink_relocation()
				if _vanish_hop > 3:
					_finish_event({ "action": "separate", "distance": 8.5, "reason": "💨 ¡Triple Z-Vanish empatado! Separación táctica." })
					return
				_vanish_defender_is_player = true
				var prof_zv_next: Dictionary = _get_bp_profile_for(_enemy_char, _player_char, true)
				_event_timer = clampf(0.95 * float(prof_zv_next["def_time_mult"]), 0.74, 1.30)
				_vanish_hop_grace = 0.15
				_base_title_txt = "💨 ¡GUERRA DE Z-VANISH! (%d/3)" % _vanish_hop
				if _title_label:
					_title_label.text = "%s (%.1fs)" % [_base_title_txt, _event_timer]
				if _prompt_label:
					_prompt_label.text = "Stick (%d Ki) = ¡Contra-Blink! | Guardia X = Plantarse" % int(_get_z_vanish_hop_cost(_player_char))
				return
			else:
				_play_event_sfx("common.melee_hit_heavy", 1.05)
				_pulse_player_haptics(220.0, 0.95, 0.18)
				if _dome and _dome.has_method("_spawn_parry_shockwave") and reactor:
					_dome._spawn_parry_shockwave(reactor.global_position + Vector3.UP * 1.0)
				if get_tree() and reactor:
					KiSmokeFX.spawn_smoke(get_tree(), reactor.global_position + Vector3.UP * 0.8, 1.1)
				if reactor and reactor.has_method("take_hit"):
					reactor.take_hit(360.0 * float(prof_zv["damage_scale"]), Vector3.ZERO, false)
				if chaser and chaser.has_method("increase_np"):
					chaser.increase_np(240.0 * float(prof_zv["bp_gain_mult"]))
				_finish_event({ "action": "launch", "victim": reactor })
				return

	if _event_timer <= 0.0:
		# Reactor no contra-blinkeó ni bloqueó a tiempo -> Patada a la espalda
		_play_event_sfx("common.melee_hit_heavy", 1.0)
		_pulse_player_haptics(225.0, 0.95, 0.18)
		if _dome and _dome.has_method("_spawn_parry_shockwave") and reactor:
			_dome._spawn_parry_shockwave(reactor.global_position + Vector3.UP * 1.0)
		if get_tree() and reactor:
			KiSmokeFX.spawn_smoke(get_tree(), reactor.global_position + Vector3.UP * 0.8, 1.1)
		if reactor and reactor.has_method("take_hit"):
			reactor.take_hit(360.0 * float(prof_zv["damage_scale"]), Vector3.ZERO, false)
		if chaser and chaser.has_method("increase_np"):
			chaser.increase_np(240.0 * float(prof_zv["bp_gain_mult"]))
		_finish_event({ "action": "launch", "victim": reactor })


func _process_guard_break(_delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool, l_grip: bool, r_grip: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var orb_pos: Vector3 = _event_orb.global_position if _event_orb else global_position
	var axis_gb: Vector3 = _dome.get("_duel_axis") if (_dome and is_instance_valid(_dome) and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var prof_gb: Dictionary = _get_bp_profile_for(_attacker, _defender, true)

	if atk_is_player:
		var l_d_gb: float = l_ctrl.global_position.distance_to(orb_pos) if l_ctrl != null else 999.0
		var r_d_gb: float = r_ctrl.global_position.distance_to(orb_pos) if r_ctrl != null else 999.0
		var l_hit: bool = l_d_gb <= 0.36 and evaluate_sonic_burst_punch(l_vel, axis_gb, l_closed, l_d_gb)
		var r_hit: bool = r_d_gb <= 0.36 and evaluate_sonic_burst_punch(r_vel, axis_gb, r_closed, r_d_gb)
		if l_hit or r_hit:
			_play_event_sfx("common.melee_hit_heavy", 0.92)
			_pulse_player_haptics(230.0, 1.0, 0.20)
			if _dome and _dome.has_method("_spawn_parry_shockwave"):
				_dome._spawn_parry_shockwave(orb_pos)
			if _defender and is_instance_valid(_defender):
				_defender.set("is_blocking", false)
				_defender.set("is_guard_broken", true)
				_defender.set("guard_break_timer", 1.6)
				_defender.set("is_staggered", true)
				_defender.set("stagger_timer", 1.2)
				if _defender.has_method("take_hit"):
					_defender.take_hit(320.0 * float(prof_gb["damage_scale"]), Vector3.ZERO, false)
			if _attacker and is_instance_valid(_attacker) and _attacker.has_method("increase_np"):
				_attacker.increase_np(180.0 * float(prof_gb["bp_gain_mult"]))
			_finish_event({ "action": "winner_offense", "winner": _attacker, "loser": _defender, "bonus_hits": 1 })
			return
	else:
		var cfg_gb: KiEconomyConfig = KiEconomyConfig.get_default()
		var ew_gb: float = float(cfg_gb.melee_explosive_wave_cost) if cfg_gb.get("melee_explosive_wave_cost") != null else 16.0
		var zv_gb: float = _get_z_vanish_hop_cost(_defender)
		var def_ki: float = float(_defender.get("current_ki")) if (_defender and _defender.get("current_ki") != null) else 0.0
		var hands_spread: bool = l_ctrl != null and r_ctrl != null and l_ctrl.global_position.distance_to(r_ctrl.global_position) >= 0.72 and l_grip and r_grip
		var stick_flick_gb: bool = _stick_debounce <= 0.0 and (stick_l.length() >= 0.65 or stick_r.length() >= 0.65)
		var desperate_deflect: bool = _event_timer <= 0.55 and (l_vel.length() >= 1.85 or r_vel.length() >= 1.85) and (not l_closed or not r_closed)

		if _prompt_label and def_ki < zv_gb and _event_timer <= 0.55:
			_prompt_label.text = "⚡ ¡AHORA! ¡MANOTAZO RÁPIDO (SIN PUÑO = DESVÍO 0 KI)!"

		if hands_spread and def_ki >= ew_gb:
			var prof_kiai_gb: Dictionary = _get_bp_profile_for(_defender, _attacker, true)
			_modify_ki(_defender, -ew_gb)
			_play_event_sfx("common.aura_burst", 1.05)
			_play_event_sfx("common.melee_hit_heavy", 0.92)
			_pulse_player_haptics(220.0, 0.95, 0.18)
			if _dome and _dome.has_method("_spawn_parry_shockwave") and _defender:
				_dome._spawn_parry_shockwave(_defender.global_position + Vector3.UP * 0.9)
			if get_tree() and _defender:
				ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), _defender.global_position + Vector3.UP * 0.9, 2, Color(0.25, 0.92, 1.0, 0.95), true)
			if _attacker and _attacker.has_method("take_hit"):
				_attacker.take_hit(140.0 * float(prof_kiai_gb["damage_scale"]), Vector3.ZERO, false)
			_finish_event({ "action": "separate", "distance": 9.0, "reason": "🛡️ ¡Escapaste del Desgarre de Guardia con Onda Kiai!" })
			return
		elif stick_flick_gb and def_ki >= zv_gb:
			_stick_debounce = 0.24
			_modify_ki(_defender, -zv_gb)
			_play_event_sfx("common.dodge_vanish", 1.15)
			_pulse_player_haptics(190.0, 0.75, 0.10)
			if _defender and _defender.has_method("increase_np"):
				_defender.increase_np(120.0 * float(prof_gb["defender_underdog_bp_mult"]))
			if get_tree() and _defender:
				KiSmokeFX.spawn_smoke(get_tree(), _defender.global_position + Vector3.UP * 0.8, 1.1)
			_finish_event({ "action": "separate", "distance": 8.5, "reason": "💨 ¡Escapaste del Desgarre de Guardia con Z-Vanish!" })
			return
		elif desperate_deflect:
			_play_event_sfx("common.block_perfect", 1.25)
			_pulse_player_haptics(240.0, 0.95, 0.16)
			if _dome and _dome.has_method("_spawn_parry_shockwave"):
				_dome._spawn_parry_shockwave(orb_pos)
			_modify_ki(_defender, 8.0)
			if _defender and _defender.has_method("increase_np"):
				_defender.increase_np(150.0 * float(prof_gb["defender_underdog_bp_mult"]))
			_finish_event({ "action": "separate", "distance": 7.5, "reason": "⚡ ¡DESVÍO DESESPERADO! Escapaste sin Ki del Desgarre de Guardia." })
			return

	if _event_timer <= 0.0:
		if not atk_is_player and _defender:
			_play_event_sfx("common.melee_hit_heavy", 0.88)
			_pulse_player_haptics(235.0, 1.0, 0.22)
			if _dome and _dome.has_method("_spawn_hit_spark"):
				_dome._spawn_hit_spark(orb_pos)
			_defender.set("is_guard_broken", true)
			_defender.set("guard_break_timer", 1.2)
			if _defender.has_method("take_hit"):
				_defender.take_hit(280.0 * float(prof_gb["damage_scale"]), Vector3.ZERO, false)
			if _attacker and is_instance_valid(_attacker) and _attacker.has_method("increase_np"):
				_attacker.increase_np(160.0 * float(prof_gb["bp_gain_mult"]))
			_finish_event({ "action": "launch", "victim": _defender })
		else:
			_finish_event({ "action": "complete_normal" })


func _process_sonic_z_burst(delta: float, l_ctrl: XRController3D, r_ctrl: XRController3D, l_vel: Vector3, r_vel: Vector3, l_closed: bool, r_closed: bool, stick_l: Vector2, stick_r: Vector2) -> void:
	_burst_hop_timer -= delta
	var atk_is_player: bool = bool(_attacker.get("is_player"))
	var orb_pos: Vector3 = _event_orb.global_position if _event_orb else global_position
	var axis_sb: Vector3 = _dome.get("_duel_axis") if (_dome and is_instance_valid(_dome) and _dome.get("_duel_axis") != null) else Vector3.FORWARD
	var prof_sb: Dictionary = _get_bp_profile_for(_attacker, _defender, true)
	var cfg_sb: KiEconomyConfig = KiEconomyConfig.get_default()
	var sb_hop_cost: float = float(cfg_sb.melee_sonic_burst_hop_cost) if cfg_sb.get("melee_sonic_burst_hop_cost") != null else 6.0

	if atk_is_player:
		if stick_r.y <= -0.55:
			_finish_event({ "action": "separate", "distance": 8.0, "reason": "⚡ Intercambio Sónico cancelado para conservar Ki." })
			return

		var d_l_sb: float = l_ctrl.global_position.distance_to(orb_pos) if l_ctrl != null else 999.0
		var d_r_sb: float = r_ctrl.global_position.distance_to(orb_pos) if r_ctrl != null else 999.0
		var l_ok: bool = _clash_punch_cd_l <= 0.0 and d_l_sb <= 0.36 and evaluate_sonic_burst_punch(l_vel, axis_sb, l_closed, d_l_sb)
		var r_ok: bool = _clash_punch_cd_r <= 0.0 and d_r_sb <= 0.36 and evaluate_sonic_burst_punch(r_vel, axis_sb, r_closed, d_r_sb)
		if l_ok or r_ok:
			_clash_punch_cd_l = 0.25
			_clash_punch_cd_r = 0.25
			var atk_ki: float = float(_attacker.get("current_ki")) if (_attacker and _attacker.get("current_ki") != null) else 0.0
			if atk_ki >= sb_hop_cost:
				_modify_ki(_attacker, -sb_hop_cost)
				_burst_hits += 1
				_substep += 1
				if _defender and _defender.has_method("take_hit"):
					_defender.take_hit(240.0 * float(prof_sb["damage_scale"]), Vector3.ZERO, false)
				if _defender and _defender.get("procedural_animator"):
					_defender.procedural_animator.trigger_hit_flinch(0.75, axis_sb)
				if _attacker and _attacker.has_method("increase_np"):
					_attacker.increase_np(140.0 * float(prof_sb["bp_gain_mult"]))
				if _dome and _dome.has_method("_spawn_parry_shockwave"):
					_dome._spawn_parry_shockwave(orb_pos)
				if is_inside_tree() and get_tree():
					ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), orb_pos, Color(1.0, 0.88, 0.20, 0.95), 0.90)
				_play_event_sfx("common.melee_hit_heavy", 1.0 + float(_burst_hits - 1) * 0.14)
				_pulse_player_haptics(210.0 + float(_burst_hits) * 15.0, 0.95, 0.14)
				if _substep >= 3:
					_finish_event({ "action": "launch", "victim": _defender, "hits": _burst_hits })
					return
				_burst_hop_timer = _burst_hop_window
				_event_timer = _burst_hop_window
				_play_event_sfx("common.dodge_vanish", 1.25)
				if _dome and _dome.has_method("perform_z_blink_relocation"):
					_dome.perform_z_blink_relocation()
				if _prompt_label:
					_prompt_label.text = "¡Golpe frontal (G+T) al Orbe! (%d/3 · -%d Ki/salto | Stick ↓=Guardar Ki)" % [_substep + 1, int(sb_hop_cost)]
				return

		if _burst_hop_timer <= 0.0 or _event_timer <= 0.0:
			if _burst_hits > 0:
				_finish_event({ "action": "launch", "victim": _defender, "hits": _burst_hits })
			else:
				_finish_event({ "action": "complete_normal" })
	else:
		# IA ejecutando Intercambio Sónico -> Jugador defiende (Z-Vanish corta / Guardia X amortigua 55%)
		var def_ki_sb: float = float(_defender.get("current_ki")) if (_defender and _defender.get("current_ki") != null) else 0.0
		var zv_sb: float = _get_z_vanish_hop_cost(_defender)
		var stick_sb_d: bool = _stick_debounce <= 0.0 and (stick_l.length() >= 0.65 or stick_r.length() >= 0.65)
		if stick_sb_d and def_ki_sb >= zv_sb:
			_stick_debounce = 0.24
			_modify_ki(_defender, -zv_sb)
			_play_event_sfx("common.dodge_vanish", 1.18)
			_pulse_player_haptics(195.0, 0.80, 0.12)
			if _defender and _defender.has_method("increase_np"):
				_defender.increase_np(140.0 * float(prof_sb["defender_underdog_bp_mult"]))
			if get_tree() and _defender:
				KiSmokeFX.spawn_smoke(get_tree(), _defender.global_position + Vector3.UP * 0.8, 1.2)
			_finish_event({ "action": "separate", "distance": 9.0, "reason": "💨 ¡Cortaste el Intercambio Sónico rival con Z-Vanish!" })
			return

		var cam_sb_d: Camera3D = _get_cam()
		var chest_ok_sb: bool = true
		if cam_sb_d and is_instance_valid(cam_sb_d) and l_ctrl != null and r_ctrl != null:
			var mid_y_sb: float = (l_ctrl.global_position.y + r_ctrl.global_position.y) * 0.5
			chest_ok_sb = (mid_y_sb <= cam_sb_d.global_position.y + 0.10) and (mid_y_sb >= cam_sb_d.global_position.y - 0.55)
		var guard_x_sb: bool = chest_ok_sb and l_closed and r_closed and l_ctrl != null and r_ctrl != null and l_ctrl.global_position.distance_to(r_ctrl.global_position) < 0.34
		if guard_x_sb and _burst_guard_hold_cd <= 0.0 and _burst_hop_timer <= minf(0.45, _burst_hop_window * 0.55):
			_burst_guard_hold_cd = _burst_hop_window * 0.80
			var gq_sb: float = float(cfg_sb.melee_guard_quick_cost) if cfg_sb.get("melee_guard_quick_cost") != null else 5.0
			_modify_ki(_defender, -gq_sb)
			_modify_ki(_attacker, -sb_hop_cost)
			_substep += 1
			if _defender and _defender.has_method("take_hit"):
				_defender.take_hit(240.0 * 0.45 * float(prof_sb["damage_scale"]), -axis_sb, false)
			_play_event_sfx("common.block_guard", 0.96)
			_pulse_player_haptics(185.0, 0.78, 0.12)
			if _dome and _dome.has_method("_spawn_block_spark"):
				_dome._spawn_block_spark(orb_pos, Color(0.25, 0.85, 1.0))
			if _substep >= 3:
				_finish_event({ "action": "separate", "distance": 8.0, "reason": "🛡️ ¡Amortiguaste el Intercambio Sónico con Guardia X!" })
				return
			_burst_hop_timer = _burst_hop_window
			_event_timer = _burst_hop_window
			_play_event_sfx("common.dodge_vanish", 1.25)
			if _dome and _dome.has_method("perform_z_blink_relocation"):
				_dome.perform_z_blink_relocation()
			if _prompt_label:
				_prompt_label.text = "⚠️ ¡Z-BURST RIVAL (%d/3)! Stick (%d Ki)=Cortar | Guardia X=Amortiguar" % [_substep + 1, int(zv_sb)]
			return

		if _burst_hop_timer <= 0.0 or _event_timer <= 0.0:
			var ai_ki_sb: float = float(_attacker.get("current_ki")) if (_attacker and _attacker.get("current_ki") != null) else 0.0
			if ai_ki_sb >= sb_hop_cost:
				_modify_ki(_attacker, -sb_hop_cost)
				_burst_hits += 1
				_substep += 1
				if _defender and _defender.has_method("take_hit"):
					_defender.take_hit(240.0 * float(prof_sb["damage_scale"]), -axis_sb, false)
				if _attacker and _attacker.has_method("increase_np"):
					_attacker.increase_np(140.0 * float(prof_sb["bp_gain_mult"]))
				if _dome and _dome.has_method("_spawn_parry_shockwave"):
					_dome._spawn_parry_shockwave(orb_pos)
				if is_inside_tree() and get_tree():
					ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), orb_pos, Color(1.0, 0.30, 0.18, 0.95), 0.90)
				_play_event_sfx("common.melee_hit_heavy", 1.0 + float(_burst_hits - 1) * 0.14)
				_pulse_player_haptics(220.0 + float(_burst_hits) * 15.0, 0.95, 0.16)
				if _substep >= 3 or float(_attacker.get("current_ki")) < sb_hop_cost:
					_finish_event({ "action": "launch", "victim": _defender, "hits": _burst_hits })
					return
				_burst_hop_timer = _burst_hop_window
				_event_timer = _burst_hop_window
				_play_event_sfx("common.dodge_vanish", 1.25)
				if _dome and _dome.has_method("perform_z_blink_relocation"):
					_dome.perform_z_blink_relocation()
				if _prompt_label:
					_prompt_label.text = "⚠️ ¡Z-BURST RIVAL (%d/3)! Stick (%d Ki)=Cortar | Guardia X=Amortiguar" % [_substep + 1, int(zv_sb)]
				return
			elif _burst_hits > 0:
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
	_title_label.position = Vector3(0.0, 0.21, 0.0)
	_hud_root.add_child(_title_label)

	_prompt_label = Label3D.new()
	_prompt_label.font_size = 20
	_prompt_label.pixel_size = 0.00125
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	_prompt_label.no_depth_test = true
	_prompt_label.render_priority = 127
	_prompt_label.position = Vector3(0.0, 0.13, 0.0)
	_hud_root.add_child(_prompt_label)

	_tug_bar_root = Node3D.new()
	_tug_bar_root.name = "LoreTugBar"
	_tug_bar_root.position = Vector3(0.0, 0.05, 0.0)
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
	var orb_parent: Node3D = _dome if (_dome and is_instance_valid(_dome)) else self
	orb_parent.add_child(_event_orb)
	_sync_event_orb_world_pos()


func _sync_event_orb_world_pos() -> void:
	if not _event_orb or not is_instance_valid(_event_orb) or not _event_orb.is_inside_tree():
		return
	var cam: Camera3D = _get_cam()
	var axis: Vector3 = Vector3.FORWARD
	if _dome and is_instance_valid(_dome) and _dome.get("_duel_axis") != null:
		axis = _dome.get("_duel_axis") as Vector3
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.001 else Vector3.FORWARD
	if cam and is_instance_valid(cam):
		var orb_dist: float = lerpf(0.34, 0.86, clampf(_tug_progress, 0.0, 1.0)) if active_event_type == LoreEventType.FIST_FLURRY_CLASH else 0.55
		_event_orb.global_position = cam.global_position + axis * orb_dist + Vector3(0.0, -0.10, 0.0)
	elif _dome and is_instance_valid(_dome):
		_event_orb.global_position = _dome.global_position


func _hide_all_visuals() -> void:
	if _hud_root and is_instance_valid(_hud_root):
		_hud_root.visible = false
	if _tug_bar_root and is_instance_valid(_tug_bar_root):
		_tug_bar_root.visible = false
	if _event_orb and is_instance_valid(_event_orb):
		_event_orb.visible = false


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


func _ctrl_pressed(c: XRController3D, action: StringName) -> bool:
	if not c:
		return false
	if _dome and is_instance_valid(_dome) and _dome.has_method("_ctrl_pressed"):
		return bool(_dome._ctrl_pressed(c, action))
	return c.is_button_pressed(action)


func _ctrl_float(c: XRController3D, action: StringName) -> float:
	if not c:
		return 0.0
	if _dome and is_instance_valid(_dome) and _dome.has_method("_ctrl_float"):
		return float(_dome._ctrl_float(c, action))
	return c.get_float(action)


func _ctrl_vec2(c: XRController3D, action: StringName) -> Vector2:
	if not c:
		return Vector2.ZERO
	if _dome and is_instance_valid(_dome) and _dome.has_method("_ctrl_vec2"):
		return _dome._ctrl_vec2(c, action) as Vector2
	return c.get_vector2(action)


func _is_fist_closed_ctrl(c: XRController3D) -> bool:
	if not c:
		return false
	return (_ctrl_float(c, &"trigger") > 0.50 and _ctrl_float(c, &"grip") > 0.50) or (_ctrl_pressed(c, &"trigger_click") and _ctrl_pressed(c, &"grip_click"))


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
