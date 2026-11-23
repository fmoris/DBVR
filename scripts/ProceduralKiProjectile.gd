extends Node3D

## ProceduralKiProjectile: Motor de colisiones y comportamiento físico para proyectiles de Ki y Super Poderes.
## Soporta desvíos con las manos (Deflection), choques de Ki (Clashing) y daño en área (AoE).
## Optimizado para Meta Quest 3 en Godot 4.3+/4.8.

const ShockwaveShader = preload("res://shaders/shockwave.gdshader")
static var _cached_hybrid_ctrl: Node = null
static var _cached_gss: Node = null
static var _cached_player_char: Node = null

enum ProjectileTier { RAPID = 1, CHARGED = 2, SUPER_BEAM = 3, ULTIMATE = 4 }

var speed_velocity: Vector3 = Vector3.ZERO
var lifetime_left: float = 4.0
var initial_lifetime: float = 4.0
var p_radius: float = 0.05
var p_color: Color = Color.WHITE
var is_dead: bool = false
var ray_query_exclude: Array[RID] = []
var _ray_params: PhysicsRayQueryParameters3D = null
var _ray_exclude_synced: bool = false

# Metadatos del Motor de Colisiones
var tier: int = 1
var base_damage: float = 200.0
var explosion_radius: float = 1.2
var is_deflected: bool = false
var deflection_count: int = 0
var shooter_node: Node = null
var shooter_bp: float = -1.0
var shooter_in_furia: bool = false
var is_volley_final: bool = false
var is_perfect_return: bool = false
var original_shooter: Node = null
var homing_target: Node3D = null
var homing_strength: float = 0.0
var pierce_damage_mult: float = 1.0
var was_launched_in_zenkai: bool = false

# Red de seguridad de ciclo de vida (Punto 10: Ki blasts que no desaparecen)
const HARD_MAX_AGE: float = 8.0
const ARENA_FREE_RADIUS_SQ: float = 160.0 * 160.0
var _hard_age: float = 0.0
var _dead_timeout: float = 0.0
var _last_deflect_age: float = -1.0
var _spawn_origin: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("ki_projectiles")
	if tier >= 2:
		lifetime_left = maxf(lifetime_left, 6.0)
	initial_lifetime = lifetime_left
	_spawn_origin = global_position
	_ray_params = PhysicsRayQueryParameters3D.new()


func _exit_tree() -> void:
	if is_in_group("ki_projectiles"):
		remove_from_group("ki_projectiles")


func _physics_process(delta: float) -> void:
	if DramaticDirector.is_dramatic_pause_active:
		return
	# Red de seguridad anti-proyectiles eternos: tope duro de vida independiente del estado
	_hard_age += delta
	if _hard_age >= HARD_MAX_AGE or global_position.length_squared() > ARENA_FREE_RADIUS_SQ:
		queue_free()
		return

	if is_dead:
		# Si quedó marcado como muerto sin llegar a explotar (deferred perdido), liberarlo igualmente
		_dead_timeout += delta
		if _dead_timeout >= 0.5:
			queue_free()
		return

	# 1. Comprobar choque con otros proyectiles de Ki en vuelo
	_check_projectile_clash()
	if is_dead:
		return

	# 2. Comprobar desvío por proximidad de manos a alta velocidad (Ki Deflection)
	# (Solo se salta el frame exacto del desvío; luego el proyectil sigue volando y envejeciendo)
	var deflections_before: int = deflection_count
	_check_hand_deflection_proximity()
	if is_dead or deflection_count != deflections_before:
		return

	# 2b. Guiado suave de seguimiento (Cargados y Devoluciones Perfectas, cero allocs)
	if homing_strength > 0.0 and homing_target != null and is_instance_valid(homing_target):
		var spd: float = speed_velocity.length()
		if spd > 0.1:
			var target_pt: Vector3 = homing_target.global_position + Vector3(0.0, 1.15, 0.0)
			if bool(homing_target.get("is_player")):
				var t_orig: Node = homing_target.get_parent()
				var t_cam: Node3D = t_orig.get_node_or_null("XRCamera3D") as Node3D if t_orig else null
				if t_cam and is_instance_valid(t_cam):
					target_pt = t_cam.global_position - Vector3(0.0, 0.25, 0.0)
			var to_tgt: Vector3 = target_pt - global_position
			if to_tgt.length_squared() > 0.04:
				var desired_dir: Vector3 = to_tgt.normalized()
				var cur_dir: Vector3 = speed_velocity / spd
				if cur_dir.dot(desired_dir) > 0.25:
					var steer_alpha: float = clampf(homing_strength * delta, 0.0, 0.35)
					speed_velocity = cur_dir.lerp(desired_dir, steer_alpha).normalized() * spd

	# 3. Desplazamiento lineal
	var step = speed_velocity * delta
	var prev_pos = global_position
	global_position += step

	lifetime_left -= delta
	if lifetime_left <= 0.0:
		queue_free()
		return

	# Impacto directo contra el suelo del ring o el terreno (superficie en Y = 0.1)
	if global_position.y <= 0.15:
		is_dead = true
		var ground_impact_pos = Vector3(global_position.x, 0.1, global_position.z)
		call_deferred("_trigger_explosion", ground_impact_pos, null)
		return

	# 4. Raycast continuo para detección de colisiones de alta velocidad
	var space = get_world_3d().direct_space_state
	if not space:
		return

	if _ray_params == null:
		_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.from = prev_pos
	_ray_params.to = global_position
	if not _ray_exclude_synced:
		_ray_params.exclude = ray_query_exclude
		_ray_exclude_synced = true
	var collision = space.intersect_ray(_ray_params)

	if collision and collision.collider:
		var collider = collision.collider
		var col_name = collider.name

		# --- A. DETECCIÓN DE DESVÍO CON LAS MANOS (DEFLECTION) ---
		var is_hand_col = col_name.begins_with("KiCombatFist") or "Hand" in col_name or "Fist" in col_name
		if is_hand_col:
			# Si el proyectil acaba de nacer (menos de 0.12s), ignorar la mano del propio tirador
			if (initial_lifetime - lifetime_left) < 0.12:
				pass
			else:
				# Obtener la velocidad lineal de la mano
				var hand_vel = Vector3.ZERO
				if collider is RigidBody3D:
					hand_vel = collider.linear_velocity
				else:
					var ctrl = _get_hybrid_ctrl()
					if ctrl:
						hand_vel = ctrl.left_velocity if "left" in col_name.to_lower() else ctrl.right_velocity

				# Proyectiles de Tier 1 y 2 se pueden desviar según velocidad y ratio de BP
				var def_check: Dictionary = _can_hand_deflect(hand_vel, collider)
				if bool(def_check.get("allowed", false)):
					_execute_deflection(collision, hand_vel, collider)
					return
				else:
					# Si la mano no cumple umbral de desvío, detona
					is_dead = true
					call_deferred("_trigger_explosion", collision.position, collider)
					return
		else:
			# --- B. IMPACTO CON PERSONAJE O ENTORNO ---
			var is_char_hit: bool = collider.has_method("take_hit") or (collider.get_parent() != null and collider.get_parent().has_method("take_hit"))
			# Evitar autodetonación contra pared/roca en los primeros 0.08s al disparar de espaldas al muro
			if not is_char_hit and _hard_age < 0.08 and global_position.distance_squared_to(_spawn_origin) < 0.36:
				return
			is_dead = true
			call_deferred("_trigger_explosion", collision.position, collider)
			return


func _get_hybrid_ctrl() -> Node:
	if _cached_hybrid_ctrl and is_instance_valid(_cached_hybrid_ctrl) and _cached_hybrid_ctrl.is_inside_tree():
		return _cached_hybrid_ctrl
	if is_inside_tree() and get_tree() and get_tree().current_scene:
		_cached_hybrid_ctrl = get_tree().current_scene.find_child("HybridCombatController", true, false)
	return _cached_hybrid_ctrl


func _get_player_char() -> Node:
	if _cached_player_char and is_instance_valid(_cached_player_char) and _cached_player_char.is_inside_tree():
		return _cached_player_char
	if is_inside_tree() and get_tree() and get_tree().current_scene:
		_cached_player_char = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
	return _cached_player_char


func _get_gss() -> Node:
	if _cached_gss and is_instance_valid(_cached_gss) and _cached_gss.is_inside_tree():
		return _cached_gss
	if is_inside_tree() and get_tree() and get_tree().root:
		_cached_gss = get_tree().root.find_child("GesturePhaseTree", true, false)
	return _cached_gss


func _get_vfx_parent() -> Node:
	if is_inside_tree() and get_tree():
		if get_tree().current_scene:
			return get_tree().current_scene
		if get_parent():
			return get_parent()
		return get_tree().root
	return get_parent()


func _get_effective_shooter_bp(caster: Node) -> float:
	if shooter_bp >= 0.0:
		return maxf(shooter_bp, 100.0)
	if caster and is_instance_valid(caster) and caster.get("current_np") != null:
		return maxf(float(caster.get("current_np")), 100.0)
	return 10000.0


func _get_defender_from_hand_or_ctrl(hand_node: Node) -> Node:
	if hand_node and is_instance_valid(hand_node):
		var p: Node = hand_node.get_parent()
		if p and p.has_method("recharge_ki"):
			return p
		if hand_node.has_method("recharge_ki"):
			return hand_node
	return _get_player_char()


func _can_hand_deflect(hand_vel: Vector3, hand_node: Node) -> Dictionary:
	if tier > ProjectileTier.CHARGED:
		return { "allowed": false, "defender": null, "profile": {} }
	var defender: Node = _get_defender_from_hand_or_ctrl(hand_node)
	var def_bp: float = float(defender.get("current_np")) if (defender and is_instance_valid(defender) and defender.get("current_np") != null) else 10000.0
	var atk_bp: float = _get_effective_shooter_bp(shooter_node)
	var prof: Dictionary = CharacterInstance.compute_ki_blast_bp_profile(atk_bp, def_bp, tier >= ProjectileTier.CHARGED, shooter_in_furia)
	var speed_h: float = hand_vel.length()
	var incoming_dir: Vector3 = speed_velocity.normalized() if speed_velocity.length_squared() > 0.001 else Vector3.FORWARD
	var swipe_dir: Vector3 = (hand_vel / speed_h) if speed_h > 0.001 else Vector3.FORWARD
	var is_counter_swipe: bool = (speed_h >= 2.2 and swipe_dir.dot(-incoming_dir) >= 0.40)

	if tier == ProjectileTier.CHARGED and not bool(prof.get("can_1hand_deflect_charged", false)):
		return { "allowed": is_counter_swipe, "defender": defender, "profile": prof }
	var min_v: float = float(prof.get("deflect_min_vel", 1.0))
	return { "allowed": speed_h >= min_v, "defender": defender, "profile": prof }


## Detección proactiva por proximidad de barrido de manos (previene tunneling a alta velocidad)
func _check_hand_deflection_proximity() -> void:
	if is_dead or tier > ProjectileTier.CHARGED or deflection_count >= 3:
		return
	if (initial_lifetime - lifetime_left) < 0.12:
		return
	if _last_deflect_age >= 0.0 and (_hard_age - _last_deflect_age) < 0.14:
		return

	var player_c: Node = _get_player_char()
	if shooter_node == player_c:
		return

	var ctrl = _get_hybrid_ctrl()
	if not ctrl or not is_instance_valid(ctrl):
		return

	var def_bp: float = float(player_c.get("current_np")) if (player_c and is_instance_valid(player_c) and player_c.get("current_np") != null) else 10000.0
	var prof: Dictionary = CharacterInstance.compute_ki_blast_bp_profile(_get_effective_shooter_bp(shooter_node), def_bp, tier >= ProjectileTier.CHARGED, shooter_in_furia)
	var deflect_radius: float = float(prof.get("deflect_radius", 0.30))

	# Chequear mano izquierda del jugador
	if ctrl.left_controller and is_instance_valid(ctrl.left_controller):
		var l_pos = ctrl.left_controller.global_position
		if global_position.distance_to(l_pos) <= deflect_radius:
			var l_vel = ctrl.left_velocity
			var chk_l: Dictionary = _can_hand_deflect(l_vel, ctrl.left_controller)
			if bool(chk_l.get("allowed", false)):
				var col_dict = {
					"position": global_position,
					"normal": (global_position - l_pos).normalized()
				}
				_execute_deflection(col_dict, l_vel, ctrl.left_controller)
				return

	# Chequear mano derecha del jugador
	if ctrl.right_controller and is_instance_valid(ctrl.right_controller):
		var r_pos = ctrl.right_controller.global_position
		if global_position.distance_to(r_pos) <= deflect_radius:
			var r_vel = ctrl.right_velocity
			var chk_r: Dictionary = _can_hand_deflect(r_vel, ctrl.right_controller)
			if bool(chk_r.get("allowed", false)):
				var col_dict = {
					"position": global_position,
					"normal": (global_position - r_pos).normalized()
				}
				_execute_deflection(col_dict, r_vel, ctrl.right_controller)
				return


## Desvío manual invocado directamente por la IA
func deflect_by_ai(hand_pos: Vector3, swipe_vel: Vector3, ai_host: Node) -> void:
	if is_dead or is_deflected:
		return
	var col_dict = {
		"position": global_position,
		"normal": (global_position - hand_pos).normalized()
	}
	_execute_deflection(col_dict, swipe_vel, ai_host)


## Ejecuta la física de desvío angular o Devolución Perfecta teledirigida del proyectil
func _execute_deflection(collision: Dictionary, hand_vel: Vector3, hand_collider: Node) -> void:
	var swipe_len: float = hand_vel.length()
	var swipe_dir: Vector3 = (hand_vel / swipe_len) if swipe_len > 0.001 else Vector3.FORWARD
	var incoming_dir: Vector3 = speed_velocity.normalized() if speed_velocity.length_squared() > 0.001 else Vector3.FORWARD
	var prev_shooter: Node = shooter_node
	var prev_shooter_bp: float = _get_effective_shooter_bp(prev_shooter)
	var defender: Node = _get_defender_from_hand_or_ctrl(hand_collider)

	var perfect_ret: bool = (is_volley_final or tier == ProjectileTier.CHARGED) and swipe_len >= 2.2 and swipe_dir.dot(-incoming_dir) >= 0.40
	var return_tgt: Node3D = null
	if original_shooter and is_instance_valid(original_shooter) and original_shooter is Node3D:
		return_tgt = original_shooter as Node3D
	elif prev_shooter and is_instance_valid(prev_shooter) and prev_shooter is Node3D:
		return_tgt = prev_shooter as Node3D

	var new_dir: Vector3 = swipe_dir
	if perfect_ret:
		is_perfect_return = true
		homing_target = return_tgt
		homing_strength = 2.6
		if return_tgt and is_instance_valid(return_tgt):
			var tgt_pt: Vector3 = return_tgt.global_position + Vector3(0.0, 1.15, 0.0)
			if bool(return_tgt.get("is_player")):
				var t_orig: Node = return_tgt.get_parent()
				var t_cam: Node3D = t_orig.get_node_or_null("XRCamera3D") as Node3D if t_orig else null
				if t_cam and is_instance_valid(t_cam):
					tgt_pt = t_cam.global_position - Vector3(0.0, 0.25, 0.0)
			var to_ret: Vector3 = tgt_pt - global_position
			new_dir = to_ret.normalized() if to_ret.length_squared() > 0.01 else (-incoming_dir)
		else:
			new_dir = -incoming_dir
		speed_velocity = new_dir * clampf(speed_velocity.length() * 1.45, 30.0, 44.0)
	else:
		var reflected: Vector3 = incoming_dir.bounce(collision.normal)
		new_dir = (reflected * 0.35 + swipe_dir * 0.65).normalized()
		if new_dir.dot(incoming_dir) > -0.1:
			new_dir = (new_dir + swipe_dir * 0.5).normalized()
		speed_velocity = new_dir * (speed_velocity.length() * 1.4)

	is_deflected = true
	deflection_count += 1
	_last_deflect_age = _hard_age
	lifetime_left = 3.5

	# Excluir la mano y el cuerpo del defensor para evitar autodetonación al devolver
	ray_query_exclude.clear()
	if hand_collider is CollisionObject3D:
		ray_query_exclude.append(hand_collider.get_rid())
	if defender and is_instance_valid(defender) and defender.has_method("get_projectile_exclude_rids"):
		for ex_rid in defender.get_projectile_exclude_rids():
			if not ray_query_exclude.has(ex_rid):
				ray_query_exclude.append(ex_rid)
	_ray_exclude_synced = false

	_spawn_deflection_vfx(collision.position)

	var cfg_def: KiEconomyConfig = KiEconomyConfig.get_default()
	var reward_ki: float = cfg_def.ki_blast_deflect_ki_reward
	var reward_bp: float = cfg_def.ki_blast_deflect_bp_reward

	if defender and is_instance_valid(defender):
		shooter_node = defender
		shooter_in_furia = bool(defender.get("is_in_furia"))
		original_shooter = prev_shooter
		var def_bp_val: float = float(defender.get("current_np")) if defender.get("current_np") != null else 10000.0
		if perfect_ret:
			shooter_bp = maxf(def_bp_val, prev_shooter_bp * 1.20) if shooter_in_furia else def_bp_val
		else:
			shooter_bp = def_bp_val
		if defender.has_method("recharge_ki"):
			defender.recharge_ki(reward_ki)
		if defender.has_method("increase_np"):
			defender.increase_np(reward_bp)

	var ctrl = _get_hybrid_ctrl()
	if ctrl and hand_collider and defender == _get_player_char():
		var controller_node = ctrl.left_controller if "left" in hand_collider.name.to_lower() else ctrl.right_controller
		if controller_node and controller_node.has_method("trigger_haptic_pulse"):
			controller_node.trigger_haptic_pulse("haptic", 200.0 if perfect_ret else 180.0, 1.0 if perfect_ret else 0.90, 0.14 if perfect_ret else 0.10, 0.0)

	var gss = _get_gss()
	if gss and gss.has_signal("gesture_logged"):
		if perfect_ret:
			gss.emit_signal("gesture_logged", "[DEVOLUCIÓN PERFECTA] ¡Contraataque de Ki teledirigido! (+%d Ki, +%d BP)" % [int(reward_ki), int(reward_bp)], "success")
		else:
			gss.emit_signal("gesture_logged", "[DESVÍO] ¡Ki Blast desviado con la mano! (+%d Ki, +%d BP)" % [int(reward_ki), int(reward_bp)], "success")


## Detecta y resuelve colisiones entre proyectiles en vuelo (Choques de Ki con Escalado de BP)
func _check_projectile_clash() -> void:
	for other in get_tree().get_nodes_in_group("ki_projectiles"):
		if other != self and is_instance_valid(other) and not other.get("is_dead"):
			var dist = global_position.distance_to(other.global_position)
			var other_r: float = float(other.get("p_radius")) if other.get("p_radius") != null else 0.05
			var contact_threshold = p_radius + other_r + 0.12
			if dist <= contact_threshold:
				var other_tier = int(other.get("tier")) if other.get("tier") != null else 1
				if self.tier == other_tier:
					var my_bp: float = _get_effective_shooter_bp(shooter_node)
					var other_bp_val: Variant = other.get("shooter_bp")
					var other_bp: float = float(other_bp_val) if (other_bp_val != null and float(other_bp_val) >= 0.0) else 10000.0
					if (other_bp_val == null or float(other_bp_val) < 0.0) and other.get("shooter_node") != null:
						var o_shooter: Node = other.get("shooter_node")
						if o_shooter and is_instance_valid(o_shooter) and o_shooter.get("current_np") != null:
							other_bp = maxf(float(o_shooter.get("current_np")), 100.0)

					if my_bp >= other_bp * 1.40:
						pierce_damage_mult = maxf(pierce_damage_mult * 0.65, 0.45)
						other.set("is_dead", true)
						other.call_deferred("queue_free")
						_spawn_deflection_vfx(other.global_position)
						if shooter_node and is_instance_valid(shooter_node) and shooter_node.has_method("_log_combat_event"):
							shooter_node._log_combat_event("💥 ¡TU KI DEVORÓ EL PROYECTIL RIVAL!", "success")
						break
					elif other_bp >= my_bp * 1.40:
						var o_pm: float = float(other.get("pierce_damage_mult")) if other.get("pierce_damage_mult") != null else 1.0
						other.set("pierce_damage_mult", maxf(o_pm * 0.65, 0.45))
						is_dead = true
						_spawn_deflection_vfx(global_position)
						queue_free()
						break
					else:
						# Choque parejo: ambos detonan en el aire
						var clash_pos = (global_position + other.global_position) * 0.5
						is_dead = true
						other.set("is_dead", true)
						other.call_deferred("queue_free")
						call_deferred("_trigger_air_clash_explosion", clash_pos)
						break
				elif self.tier > other_tier:
					# Poder superior devora al inferior
					other.set("is_dead", true)
					other.call_deferred("queue_free")
					_spawn_deflection_vfx(other.global_position)
				elif self.tier < other_tier:
					# Proyectil inferior destruido
					is_dead = true
					queue_free()
					break


## Detonación de choque de energías en el aire
func _trigger_air_clash_explosion(pos: Vector3) -> void:
	ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, p_color, clampf(p_radius * 5.0, 1.0, 2.5))
	ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), pos, 2, p_color, false)

	var gss = _get_gss()
	if gss and gss.has_signal("gesture_logged"):
		gss.emit_signal("gesture_logged", "[CHOQUE DE KI] ¡Dos poderes colisionaron y detonaron en el aire!", "warning")

	KiSmokeFX.spawn_smoke(get_tree(), pos, 1.1)
	queue_free()


func _apply_projectile_hit(char_node: Node, caster: Node, pos: Vector3, hit_dir: Vector3, raw_damage: float, is_splash_hit: bool, prox_factor: float) -> void:
	if not char_node or not is_instance_valid(char_node) or not char_node.has_method("take_hit"):
		return
	var power: Resource = get_meta("power_ref") if has_meta("power_ref") else null
	var effective_damage: float = raw_damage * pierce_damage_mult

	# --- PROYECTILES DE TIER 3+ (SUPER ESFERAS / DEFINITIVAS) ---
	if tier >= ProjectileTier.SUPER_BEAM:
		var splash_kb_override: float = -1.0
		if is_splash_hit and caster and is_instance_valid(caster) and char_node != caster:
			var atk_bp_proj: float = float(caster.get("current_np")) if (caster.get("current_np") != null) else 10000.0
			var def_bp_proj: float = float(char_node.get("current_np")) if (char_node.get("current_np") != null) else 10000.0
			var sp_res: Dictionary = SuperBeamSequenceController.compute_super_explosion_splash(
				pos,
				char_node.global_position + Vector3(0.0, 1.0, 0.0),
				maxf(explosion_radius, 0.5),
				raw_damage,
				atk_bp_proj,
				def_bp_proj
			)
			if not bool(sp_res.get("in_radius", false)):
				return
			if bool(sp_res.get("no_sell", false)):
				if char_node.has_method("_spawn_bp_delta_popup"):
					char_node._spawn_bp_delta_popup(0.0, "0 BP · INMUNE")
				if char_node.has_method("_log_combat_event"):
					char_node._log_combat_event("🛡️ ¡RESISTIÓ LA ONDA EXPANSIVA SIN MOVERSE! (0 BP)", "success")
				return
			effective_damage = float(sp_res.get("damage_bp", effective_damage))
			splash_kb_override = float(sp_res.get("knockback_speed", 0.0))

		var was_super_blocking: bool = bool(char_node.get("is_blocking")) and not bool(char_node.get("is_guard_broken"))
		if splash_kb_override >= 0.0:
			char_node.take_hit(effective_damage, hit_dir, false)
			if splash_kb_override >= 3.0 and char_node.has_method("apply_knockback"):
				char_node.apply_knockback(hit_dir, splash_kb_override, 2.2)
		else:
			char_node.take_hit(effective_damage, hit_dir)

		if char_node.has_method("recharge_ki"):
			char_node.recharge_ki(clampf(effective_damage * 0.02, 5.0, 25.0))

		if caster and is_instance_valid(caster) and char_node != caster and caster.has_method("increase_np"):
			caster.increase_np(effective_damage * 0.55)
			caster.check_zenkai_conditions(char_node.current_np)
			char_node.check_zenkai_conditions(caster.current_np)
			var is_zenkai_finisher: bool = was_launched_in_zenkai or bool(caster.get("is_in_zenkai_state")) or bool(caster.get("is_comeback_zenkai"))
			if power and power.is_finisher and (was_launched_in_zenkai or bool(caster.get("is_in_zenkai_state"))):
				caster.execute_finisher_hit(power)
			elif is_zenkai_finisher and caster.has_method("trigger_zenkai_match_finish"):
				var p_title: String = power.power_name if (power and "power_name" in power) else "Super Esfera Ki"
				caster.trigger_zenkai_match_finish(caster, char_node, p_title)
		return

	# --- OVERHAUL TÁCTICO DE KI BLASTS (TIER 1 Y 2 CON ESCALADO DE BP) ---
	if char_node == caster and not is_deflected:
		return

	var is_charged_blast: bool = (tier == ProjectileTier.CHARGED)
	var atk_bp: float = _get_effective_shooter_bp(caster)
	var def_bp: float = float(char_node.get("current_np")) if (char_node.get("current_np") != null) else 10000.0
	var atk_furia: bool = shooter_in_furia or (caster != null and is_instance_valid(caster) and bool(caster.get("is_in_furia")))
	var profile: Dictionary = CharacterInstance.compute_ki_blast_bp_profile(atk_bp, def_bp, is_charged_blast, atk_furia)

	# 1. No-Sell Saiyan (Defensor muy superior a Ki Blast Rápido)
	if bool(profile.get("no_sell_rapid", false)) and not is_perfect_return:
		if char_node.has_method("_spawn_bp_delta_popup"):
			char_node._spawn_bp_delta_popup(0.0, "🛡️ 0 BP · TANQUEADO")
		if char_node.has_method("_log_combat_event"):
			char_node._log_combat_event("🛡️ ¡Absorbió el Ki Blast sin inmutarse! (0 BP)", "info")
		return

	effective_damage *= float(profile.get("dmg_mult", 1.0))
	if is_perfect_return:
		effective_damage *= 1.35

	var extra_stacks: float = 2.0 if is_perfect_return else 0.0
	var is_counter: bool = false
	var extra_victim_ki_drain: float = 0.0

	# 2. Counter-Interrupt (Anti-Greedy Reads)
	if char_node != caster and (not is_splash_hit or prox_factor >= 0.55):
		if bool(char_node.get("is_charging_ki")) and (bool(profile.get("can_interrupt_ki_recharge", false)) or is_perfect_return):
			is_counter = true
			if char_node.has_method("interrupt_ki_recharge_from_blast"):
				char_node.interrupt_ki_recharge_from_blast()
			effective_damage *= float(profile.get("counter_dmg_mult", 2.0))
			extra_victim_ki_drain = 15.0 if is_charged_blast else 8.0
			if caster and is_instance_valid(caster) and caster.has_method("recharge_ki"):
				caster.recharge_ki(10.0 if is_charged_blast else 6.0)
			if char_node.has_method("_spawn_bp_delta_popup"):
				char_node._spawn_bp_delta_popup(0.0, "⚡ ¡INTERCEPCIÓN!")
		elif bool(char_node.get("is_charging_super")) and is_charged_blast and (bool(profile.get("can_interrupt_super_direct", false)) or is_perfect_return):
			is_counter = true
			char_node.set("current_charge_poise", 0.0)
			if char_node.has_method("interrupt_charging_super"):
				char_node.interrupt_charging_super()
			else:
				char_node.set("is_charging_super", false)
			effective_damage *= float(profile.get("counter_dmg_mult", 2.0))
			extra_victim_ki_drain = 12.0
			if caster and is_instance_valid(caster) and caster.has_method("recharge_ki"):
				caster.recharge_ki(8.0)
			if char_node.has_method("_spawn_bp_delta_popup"):
				char_node._spawn_bp_delta_popup(0.0, "⚡ ¡SUPER INTERRUMPIDO!")
		elif bool(char_node.get("is_flying_to_opponent")) and ((is_charged_blast and (float(profile.get("effective_ratio", 1.0)) >= 0.70 or is_perfect_return)) or ((not is_charged_blast) and (float(profile.get("effective_ratio", 1.0)) >= 1.35 or is_perfect_return))):
			is_counter = true
			if char_node.has_method("_stop_flight"):
				char_node._stop_flight()
			char_node.set("pending_ambush_bonus_hits", 0)
			char_node.set("is_ambush_dash", false)
			char_node.set("is_staggered", true)
			char_node.set("stagger_timer", maxf(float(char_node.get("stagger_timer")) if char_node.get("stagger_timer") != null else 0.0, 0.45))
			effective_damage *= float(profile.get("counter_dmg_mult", 2.0))
			extra_victim_ki_drain = 10.0 if is_charged_blast else 5.0
			if caster and is_instance_valid(caster) and caster.has_method("recharge_ki"):
				caster.recharge_ki(6.0 if is_charged_blast else 4.0)
			if char_node.has_method("_spawn_bp_delta_popup"):
				char_node._spawn_bp_delta_popup(0.0, "⚡ ¡DASH INTERCEPTADO!")

	# 3. Evaluación de Guardia Cruzada vs Ki Blast Cargado
	var was_char_blocking: bool = bool(char_node.get("is_blocking")) and not bool(char_node.get("is_guard_broken"))
	var forced_guard_break: bool = false
	if is_charged_blast and was_char_blocking:
		if bool(profile.get("triggers_guard_break", false)):
			forced_guard_break = true
			if char_node.has_method("drain_ki"):
				char_node.drain_ki(KiEconomyConfig.get_default().ki_blast_charged_guard_ki_drain)
			char_node.set("is_blocking", false)
			char_node.set("is_guard_broken", true)
			char_node.set("guard_break_timer", 1.4)
			was_char_blocking = false
			if char_node.has_method("_spawn_bp_delta_popup"):
				char_node._spawn_bp_delta_popup(0.0, "💥 ¡GUARDIA ROTA!")
		else:
			var expected_blk_cost: float = clampf(effective_damage * 0.03, 3.5, 18.0)
			var pre_drain: float = maxf(0.0, KiEconomyConfig.get_default().ki_blast_charged_guard_ki_drain - expected_blk_cost)
			if pre_drain > 0.0 and char_node.has_method("drain_ki"):
				char_node.drain_ki(pre_drain)

	# 4. Aplicar daño sin derribo prematuro: rápidos solo producen flinch; cargados empujan corto sin tumbar
	var apply_kb_hit: bool = forced_guard_break
	char_node.take_hit(effective_damage, hit_dir, apply_kb_hit)

	if is_perfect_return:
		char_node.set("is_staggered", true)
		char_node.set("stagger_timer", maxf(float(char_node.get("stagger_timer")) if char_node.get("stagger_timer") != null else 0.0, 0.60))
		if char_node.has_method("_spawn_bp_delta_popup"):
			char_node._spawn_bp_delta_popup(0.0, "✋ ¡DEVOLUCIÓN PERFECTA!")

	if forced_guard_break and char_node.has_method("apply_knockback"):
		char_node.apply_knockback(hit_dir, 15.0, 2.5)
	elif is_charged_blast and not was_char_blocking and char_node.has_method("apply_knockback"):
		var short_push_dir: Vector3 = Vector3(hit_dir.x, 0.0, hit_dir.z).normalized() if Vector3(hit_dir.x, 0.0, hit_dir.z).length_squared() > 0.01 else hit_dir
		char_node.apply_knockback(short_push_dir, 5.5, 4.2)

	if not was_char_blocking:
		var total_ki_drain: float = float(profile.get("ki_drain", 3.0)) + extra_victim_ki_drain
		if total_ki_drain > 0.0 and char_node.has_method("drain_ki"):
			char_node.drain_ki(total_ki_drain)
	elif extra_victim_ki_drain > 0.0 and char_node.has_method("drain_ki"):
		char_node.drain_ki(extra_victim_ki_drain)

	# 5. Saturación ➔ Apertura + Cortina de Humo Táctica (derribo solo al saturar 6.0/6.0 stacks)
	var saturated_now: bool = false
	if char_node.has_method("apply_ki_blast_pressure"):
		saturated_now = bool(char_node.apply_ki_blast_pressure(caster, is_charged_blast, was_char_blocking, profile, pos, extra_stacks))
	if saturated_now and not forced_guard_break and char_node.has_method("apply_knockback"):
		char_node.apply_knockback(hit_dir, 14.0, 2.5)

	# 6. Ganancia de BP del atacante y condiciones de Zenkai
	# Prohibido K.O. por Ki Blast cargado normal: solo remata si el defensor está SIN DEFENSA y el atacante en Zenkai
	if caster and is_instance_valid(caster) and char_node != caster and caster.has_method("increase_np"):
		caster.increase_np(effective_damage * 0.55)
		caster.check_zenkai_conditions(char_node.current_np)
		char_node.check_zenkai_conditions(caster.current_np)
		var victim_defenseless: bool = char_node.has_method("is_defenseless_for_ko") and bool(char_node.is_defenseless_for_ko())
		if is_charged_blast and not was_char_blocking and victim_defenseless and (was_launched_in_zenkai or bool(caster.get("is_in_zenkai_state"))) and caster.has_method("trigger_zenkai_match_finish"):
			var p_title_kb: String = power.power_name if (power and "power_name" in power) else "Ki Blast Cargado (Remate Final)"
			caster.trigger_zenkai_match_finish(caster, char_node, p_title_kb)


## Detonación principal con daño en área (AoE), saturación táctica e impacto físico
func _trigger_explosion(pos: Vector3, collider: Node) -> void:
	var direct_target: Node = null
	if collider:
		if collider.has_method("take_hit"):
			direct_target = collider
		elif collider.get_parent() and collider.get_parent().has_method("take_hit"):
			direct_target = collider.get_parent()

	var charge_bonus = 1.0
	if has_meta("charge_time"):
		var ct = get_meta("charge_time")
		charge_bonus += ct * 0.75

	var final_damage = base_damage * charge_bonus
	var hit_dir = speed_velocity.normalized()
	if hit_dir.length_squared() < 0.01:
		hit_dir = Vector3.FORWARD

	var caster = get_meta("attacker") if has_meta("attacker") else shooter_node
	if not caster and is_inside_tree() and get_tree() and get_tree().current_scene:
		caster = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)

	# 1. Consulta esférica de área (AoE) para alcanzar a todos los personajes en el radio
	var space = get_world_3d().direct_space_state if (is_inside_tree() and get_world_3d()) else null
	var damaged_characters: Array[Node] = []

	if space:
		var shape_query = PhysicsShapeQueryParameters3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = explosion_radius
		shape_query.shape = sphere
		shape_query.transform = Transform3D(Basis(), pos)
		shape_query.collision_mask = 2 # Capa 2: Personajes Z

		var hits = space.intersect_shape(shape_query, 8)
		for hit in hits:
			var c = hit.collider
			var char_node = c if c.has_method("take_hit") else (c.get_parent() if c else null)
			if char_node and char_node.has_method("take_hit") and not damaged_characters.has(char_node):
				damaged_characters.append(char_node)
				var radial_dir = (char_node.global_position - pos).normalized()
				if radial_dir.length_squared() < 0.01:
					radial_dir = hit_dir
				var dist: float = pos.distance_to(char_node.global_position)
				var prox_factor: float = clampf(1.0 - (dist / maxf(explosion_radius, 0.5)), 0.25, 1.0)
				var is_splash_hit: bool = (direct_target == null) or (char_node != direct_target)
				_apply_projectile_hit(char_node, caster, pos, radial_dir, final_damage * (prox_factor if is_splash_hit else 1.0), is_splash_hit, prox_factor)

	# Fallback directo si el objetivo directo no cayó dentro de intersect_shape
	if direct_target and not damaged_characters.has(direct_target):
		_apply_projectile_hit(direct_target, caster, pos, hit_dir, final_damage, false, 1.0)

	# 2. Disipar proyectiles menores dentro de la onda expansiva
	if is_inside_tree() and get_tree():
		for proj in get_tree().get_nodes_in_group("ki_projectiles"):
			if proj != self and is_instance_valid(proj) and not proj.get("is_dead"):
				var p_dist = pos.distance_to(proj.global_position)
				if p_dist <= explosion_radius and int(proj.get("tier")) < self.tier:
					proj.call_deferred("queue_free")

	# 2.5 Destrucción física de pilares, rocas y cañón con daño secundario por escombros
	if is_inside_tree() and get_tree():
		var adm_proj: ArenaDestructionManager = ArenaDestructionManager.get_active(get_tree())
		if adm_proj:
			var is_env_hit: bool = collider != null and ("Spire" in collider.name or "Pillar" in collider.name or "TacticalRock" in collider.name or "Boulder" in collider.name or "Canyon" in collider.name)
			if is_env_hit or tier >= 2 or has_meta("charge_time"):
				var caster_bp: float = float(caster.get("current_np")) if (caster and is_instance_valid(caster) and caster.get("current_np") != null) else 10000.0
				var env_radius: float = maxf(explosion_radius, 3.2 if (tier >= 2 or has_meta("charge_time")) else 1.8)
				adm_proj.apply_power_aoe_destruction(pos, env_radius, final_damage, caster_bp)

	# 3. Visuales: Destello esférico + Onda refractiva
	_spawn_visual_explosion(pos)

	queue_free()


## Genera el destello brillante y la onda de choque espacial
func _spawn_visual_explosion(pos: Vector3) -> void:
	var vfx_parent: Node = _get_vfx_parent()
	if not vfx_parent or not is_inside_tree() or not get_tree():
		return

	var exp_tier: int = 2
	if tier >= 4:
		exp_tier = 5
	elif tier == 3:
		exp_tier = 4
	elif tier == 2:
		exp_tier = 2
	else:
		exp_tier = 2

	var has_lightning: bool = false
	if shooter_node and is_instance_valid(shooter_node):
		var cur_tr: Variant = shooter_node.get("current_transformation")
		if cur_tr != null and cur_tr is Resource and "has_bio_lightning" in cur_tr:
			has_lightning = bool(cur_tr.get("has_bio_lightning"))
		if bool(shooter_node.get("is_in_zenkai_state")) or bool(shooter_node.get("is_in_furia")):
			has_lightning = true

	ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), pos, exp_tier, p_color, has_lightning)
	ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), pos, p_color, clampf(p_radius * 5.5, 0.9, 2.8))

	if AudioActionManager.has_action_sounds("common.ki_blast_impact"):
		var imp_sfx := AudioStreamPlayer3D.new()
		imp_sfx.unit_size = 5.0
		imp_sfx.max_distance = 40.0
		vfx_parent.add_child(imp_sfx)
		imp_sfx.global_position = pos
		imp_sfx.pitch_scale = randf_range(0.92, 1.08)
		if AudioActionManager.play_action("common.ki_blast_impact", imp_sfx):
			imp_sfx.finished.connect(imp_sfx.queue_free)
		else:
			imp_sfx.queue_free()

	if tier >= 2 and pos.y <= 2.5:
		_spawn_plasma_crater(Vector3(pos.x, 0.12, pos.z), clampf(explosion_radius * 0.55, 0.9, 2.8), p_color)
	if tier >= 3:
		var dd_proj: DramaticDirector = DramaticDirector.get_active(get_tree())
		if dd_proj:
			dd_proj.spawn_persistent_crater(Vector3(pos.x, 0.05, pos.z), 1.15 if tier == 3 else 1.45, true)
	if tier >= 2 or pos.y <= 1.2:
		KiSmokeFX.spawn_smoke(get_tree(), pos, 1.35 if tier >= 3 else 0.85)


func _spawn_plasma_crater(pos: Vector3, radius: float, col: Color) -> void:
	if not is_inside_tree() or not get_tree():
		return
	ZenkaiVFXManager.spawn_zenkai_crater_decal(get_tree(), pos, radius, col)


func _spawn_deflection_vfx(pos: Vector3) -> void:
	var vfx_parent: Node = _get_vfx_parent()
	if not vfx_parent or not is_inside_tree() or not get_tree():
		return
	ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), pos, 1, Color(1.0, 0.92, 0.35, 1.0), false)

	var sfx = AudioStreamPlayer3D.new()
	sfx.name = "DeflectSfx"
	var fallback_deflect: AudioStream = null
	sfx.unit_size = 5.0
	sfx.max_distance = 40.0
	vfx_parent.add_child(sfx)
	sfx.global_position = pos
	sfx.pitch_scale = randf_range(0.92, 1.08)
	if AudioActionManager.play_action("common.block_guard", sfx, fallback_deflect):
		sfx.finished.connect(sfx.queue_free)
	else:
		sfx.queue_free()
