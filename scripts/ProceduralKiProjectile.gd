extends Node3D

## ProceduralKiProjectile: Motor de colisiones y comportamiento físico para proyectiles de Ki y Super Poderes.
## Soporta desvíos con las manos (Deflection), choques de Ki (Clashing) y daño en área (AoE).
## Optimizado para Meta Quest 3 en Godot 4.3+/4.8.

const ShockwaveShader = preload("res://shaders/shockwave.gdshader")

enum ProjectileTier { RAPID = 1, CHARGED = 2, SUPER_BEAM = 3, ULTIMATE = 4 }

var speed_velocity: Vector3 = Vector3.ZERO
var lifetime_left: float = 4.0
var initial_lifetime: float = 4.0
var p_radius: float = 0.05
var p_color: Color = Color.WHITE
var is_dead: bool = false
var ray_query_exclude: Array[RID] = []

# Metadatos del Motor de Colisiones
var tier: int = 1
var base_damage: float = 200.0
var explosion_radius: float = 1.2
var is_deflected: bool = false
var deflection_count: int = 0
var shooter_node: Node = null


func _ready() -> void:
	add_to_group("ki_projectiles")
	initial_lifetime = lifetime_left


func _exit_tree() -> void:
	if is_in_group("ki_projectiles"):
		remove_from_group("ki_projectiles")


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 1. Comprobar choque con otros proyectiles de Ki en vuelo
	_check_projectile_clash()
	if is_dead:
		return

	# 2. Comprobar desvío por proximidad de manos a alta velocidad (Ki Deflection)
	_check_hand_deflection_proximity()
	if is_dead or is_deflected:
		return

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

	var parameters = PhysicsRayQueryParameters3D.create(prev_pos, global_position)
	parameters.exclude = ray_query_exclude
	var collision = space.intersect_ray(parameters)

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
					var ctrl = get_tree().current_scene.find_child("HybridCombatController", true, false)
					if ctrl:
						hand_vel = ctrl.left_velocity if "left" in col_name.to_lower() else ctrl.right_velocity

				# Proyectiles de Tier 1 y 2 se pueden desviar con manotazo veloz (>= 0.85 m/s)
				if tier <= ProjectileTier.CHARGED and hand_vel.length() >= 0.85:
					_execute_deflection(collision, hand_vel, collider)
					return
				else:
					# Si la mano no tiene velocidad de desvío, la explosión impacta
					is_dead = true
					call_deferred("_trigger_explosion", collision.position, collider)
					return
		else:
			# --- B. IMPACTO CON PERSONAJE O ENTORNO ---
			is_dead = true
			call_deferred("_trigger_explosion", collision.position, collider)
			return


## Detección proactiva por proximidad de barrido de manos (previene tunneling a alta velocidad)
func _check_hand_deflection_proximity() -> void:
	if is_dead or is_deflected or tier > ProjectileTier.CHARGED:
		return
	if (initial_lifetime - lifetime_left) < 0.12:
		return

	var ctrl = get_tree().current_scene.find_child("HybridCombatController", true, false)
	if not ctrl or not is_instance_valid(ctrl):
		return

	# Chequear mano izquierda del jugador
	if ctrl.left_controller and is_instance_valid(ctrl.left_controller):
		var l_pos = ctrl.left_controller.global_position
		if global_position.distance_to(l_pos) <= 0.28:
			var l_vel = ctrl.left_velocity
			if l_vel.length() >= 0.85:
				var col_dict = {
					"position": global_position,
					"normal": (global_position - l_pos).normalized()
				}
				_execute_deflection(col_dict, l_vel, ctrl.left_controller)
				return

	# Chequear mano derecha del jugador
	if ctrl.right_controller and is_instance_valid(ctrl.right_controller):
		var r_pos = ctrl.right_controller.global_position
		if global_position.distance_to(r_pos) <= 0.28:
			var r_vel = ctrl.right_velocity
			if r_vel.length() >= 0.85:
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


## Ejecuta la física de desvío angular del proyectil al ser golpeado por una mano
func _execute_deflection(collision: Dictionary, hand_vel: Vector3, hand_collider: Node) -> void:
	var swipe_dir = hand_vel.normalized()
	var incoming_dir = speed_velocity.normalized()

	# Calcular trayectoria reflejada oblicua impulsada por el manotazo
	var reflected = incoming_dir.bounce(collision.normal)
	var new_dir = (reflected * 0.35 + swipe_dir * 0.65).normalized()
	if new_dir.dot(incoming_dir) > -0.1:
		new_dir = (new_dir + swipe_dir * 0.5).normalized()

	# Acelerar el proyectil desviado (+40% de velocidad con estela anime)
	speed_velocity = new_dir * (speed_velocity.length() * 1.4)
	is_deflected = true
	deflection_count += 1
	lifetime_left = 3.5

	# Excluir la mano que desvió para evitar colisión inmediata en el siguiente frame
	ray_query_exclude.clear()
	if hand_collider is CollisionObject3D:
		ray_query_exclude.append(hand_collider.get_rid())

	# Destello de chispas doradas de desvío y sonido metálico de impacto
	_spawn_deflection_vfx(collision.position)

	# Identificar defensor que desvió el ataque
	var defender = hand_collider.get_parent()
	if defender and not defender.has_method("recharge_ki"):
		defender = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
	if not defender and hand_collider.has_method("recharge_ki"):
		defender = hand_collider

	if defender:
		# Cambiar la autoría del proyectil para que no colisione con el defensor
		shooter_node = defender
		if defender.has_method("recharge_ki"):
			defender.recharge_ki(15.0)
		if defender.has_method("increase_np"):
			defender.increase_np(150.0)

	# Pulso háptico en el mando si fue el jugador
	var ctrl = get_tree().current_scene.find_child("HybridCombatController", true, false)
	if ctrl:
		var controller_node = ctrl.left_controller if "left" in hand_collider.name.to_lower() else ctrl.right_controller
		if controller_node and controller_node.has_method("trigger_haptic_pulse"):
			controller_node.trigger_haptic_pulse("haptic", 180.0, 0.90, 0.10, 0.0)

	var gss = get_tree().root.find_child("GesturePhaseTree", true, false)
	if gss and gss.has_signal("gesture_logged"):
		gss.emit_signal("gesture_logged", "[DESVÍO] ¡Ki Blast desviado con la mano! (+15 Ki, +150 BP)", "success")


## Detecta y resuelve colisiones entre proyectiles en vuelo (Choques de Ki)
func _check_projectile_clash() -> void:
	for other in get_tree().get_nodes_in_group("ki_projectiles"):
		if other != self and is_instance_valid(other) and not other.get("is_dead"):
			var dist = global_position.distance_to(other.global_position)
			var contact_threshold = p_radius + other.get("p_radius") + 0.12
			if dist <= contact_threshold:
				var other_tier = other.get("tier")
				if self.tier == other_tier:
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
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = p_radius * 3.0
	sphere_mesh.height = p_radius * 6.0
	flash.mesh = sphere_mesh

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.7, 1.0)
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(1.0, 0.8, 0.2, 0.0), 0.25)
	tween.chain().tween_callback(flash.queue_free)

	var gss = get_tree().root.find_child("GesturePhaseTree", true, false)
	if gss and gss.has_signal("gesture_logged"):
		gss.emit_signal("gesture_logged", "[CHOQUE DE KI] ¡Dos poderes colisionaron y detonaron en el aire!", "warning")

	queue_free()


## Detonación principal con daño en área (AoE), atenuación radial e impacto físico
func _trigger_explosion(pos: Vector3, collider: Node) -> void:
	var direct_target: Node = null
	if collider:
		if collider.has_method("take_hit"):
			direct_target = collider
		elif collider.get_parent() and collider.get_parent().has_method("take_hit"):
			direct_target = collider.get_parent()

	var power: Resource = null
	if has_meta("power_ref"):
		power = get_meta("power_ref")

	var charge_bonus = 1.0
	if has_meta("charge_time"):
		var ct = get_meta("charge_time")
		charge_bonus += ct * 0.75

	var final_damage = base_damage * charge_bonus
	var hit_dir = speed_velocity.normalized()
	if hit_dir.length_squared() < 0.01:
		hit_dir = Vector3.FORWARD

	# 1. Consulta esférica de área (AoE) para alcanzar a todos los personajes en el radio
	var space = get_world_3d().direct_space_state
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

				var dist = pos.distance_to(char_node.global_position)
				var prox_factor = clamp(1.0 - (dist / explosion_radius), 0.25, 1.0)
				var effective_damage = final_damage * prox_factor

				var radial_dir = (char_node.global_position - pos).normalized()
				if radial_dir.length_squared() < 0.01:
					radial_dir = hit_dir

				# Aplicar daño con soporte automático de bloqueo (Guardia)
				char_node.take_hit(effective_damage, radial_dir)

				# El defensor gana Ki de contraataque por absorber la explosión
				if char_node.has_method("recharge_ki"):
					var ki_gain = clamp(effective_damage * 0.02, 5.0, 25.0)
					char_node.recharge_ki(ki_gain)

				# Recompensa canónica de agresión (Punto 7): El atacante gana BP/NP al conectar
				var caster = get_meta("attacker") if has_meta("attacker") else null
				if not caster and get_tree() and get_tree().current_scene:
					caster = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
				if caster and is_instance_valid(caster) and char_node != caster and caster.has_method("increase_np"):
					caster.increase_np(effective_damage * 0.35)
					caster.check_zenkai_conditions(char_node.current_np)
					char_node.check_zenkai_conditions(caster.current_np)

					if power and power.is_finisher and caster.get("is_in_zenkai_state"):
						caster.execute_finisher_hit(power)

	# Si el objetivo directo no estaba en la consulta de área (fallback directo)
	if direct_target and not damaged_characters.has(direct_target):
		direct_target.take_hit(final_damage, hit_dir)
		var caster = get_meta("attacker") if has_meta("attacker") else null
		if not caster and get_tree() and get_tree().current_scene:
			caster = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
		if caster and is_instance_valid(caster) and direct_target != caster and caster.has_method("increase_np"):
			caster.increase_np(final_damage * 0.35)
			caster.check_zenkai_conditions(direct_target.current_np)
			direct_target.check_zenkai_conditions(caster.current_np)

	# 2. Disipar proyectiles menores dentro de la onda expansiva
	for proj in get_tree().get_nodes_in_group("ki_projectiles"):
		if proj != self and is_instance_valid(proj) and not proj.get("is_dead"):
			var p_dist = pos.distance_to(proj.global_position)
			if p_dist <= explosion_radius and proj.get("tier") < self.tier:
				proj.call_deferred("queue_free")

	# 3. Visuales: Destello esférico + Onda refractiva
	_spawn_visual_explosion(pos)

	queue_free()


## Genera el destello brillante y la onda de choque espacial
func _spawn_visual_explosion(pos: Vector3) -> void:
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = p_radius * 0.6
	sphere_mesh.height = p_radius * 1.2
	flash.mesh = sphere_mesh

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = p_color
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(p_color.r, p_color.g, p_color.b, 0.0), 0.2)
	tween.chain().tween_callback(flash.queue_free)

	var shockwave = MeshInstance3D.new()
	shockwave.name = "KiShockwave_" + str(Time.get_ticks_msec())
	var sphere_wave = SphereMesh.new()
	sphere_wave.radius = p_radius
	sphere_wave.height = p_radius * 2.0
	sphere_wave.radial_segments = 16
	sphere_wave.rings = 8
	shockwave.mesh = sphere_wave

	var mat_wave = ShaderMaterial.new()
	mat_wave.shader = ShockwaveShader
	mat_wave.set_shader_parameter("force", 0.15)
	mat_wave.set_shader_parameter("progress", 0.0)
	mat_wave.set_shader_parameter("thickness", 0.08)
	shockwave.material_override = mat_wave
	get_tree().current_scene.add_child(shockwave)
	shockwave.global_position = pos

	var wave_tween = get_tree().create_tween().set_parallel(true)
	var final_wave_scale = explosion_radius * 4.0
	wave_tween.tween_property(shockwave, "scale", Vector3.ONE * final_wave_scale, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wave_tween.tween_method(
		func(val: float): mat_wave.set_shader_parameter("progress", val),
		0.0, 1.0, 0.45
	)
	wave_tween.chain().tween_callback(shockwave.queue_free)

	# --- 3. EXPULSIÓN FÍSICA DE CHISPAS DE ENERGÍA KI (DEBRIS DINÁMICOS) ---
	var spark_count = 10 if tier >= 3 else (7 if tier == 2 else 5)
	for i in range(spark_count):
		var spark = RigidBody3D.new()
		var spark_visual = MeshInstance3D.new()
		var spark_mesh = SphereMesh.new()
		var spark_r = p_radius * 0.25
		spark_mesh.radius = spark_r
		spark_mesh.height = spark_r * 2.0
		spark_visual.mesh = spark_mesh
		
		var spark_mat = StandardMaterial3D.new()
		spark_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		spark_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		spark_mat.albedo_color = Color(p_color.r, p_color.g, p_color.b, 0.95)
		spark_visual.material_override = spark_mat
		spark.add_child(spark_visual)
		
		var spark_col = CollisionShape3D.new()
		var spark_shape = SphereShape3D.new()
		spark_shape.radius = spark_r
		spark_col.shape = spark_shape
		spark.add_child(spark_col)
		
		spark.gravity_scale = 0.5
		spark.linear_damp = 0.8
		spark.collision_layer = 0
		spark.collision_mask = 1
		get_tree().current_scene.add_child(spark)
		spark.global_position = pos
		
		var random_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.3, 1.3),
			randf_range(-1.0, 1.0)
		).normalized()
		var force = randf_range(2.5, 6.0) * (1.5 if tier >= 3 else 1.0)
		spark.apply_central_impulse(random_dir * force)
		
		var sp_tween = get_tree().create_tween()
		sp_tween.tween_property(spark_visual, "scale", Vector3.ZERO, randf_range(0.35, 0.65)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		sp_tween.chain().tween_callback(spark.queue_free)

	# --- 4. FLASH DE LUZ OMNIDIRECCIONAL PUNTUAL ---
	var exp_light = OmniLight3D.new()
	exp_light.light_color = p_color
	exp_light.light_energy = 8.0 if tier >= 3 else 4.0
	exp_light.omni_range = explosion_radius * 2.5
	get_tree().current_scene.add_child(exp_light)
	exp_light.global_position = pos
	var light_tween = get_tree().create_tween()
	light_tween.tween_property(exp_light, "light_energy", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
	light_tween.chain().tween_callback(exp_light.queue_free)


func _spawn_deflection_vfx(pos: Vector3) -> void:
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = p_radius * 1.8
	sphere.height = p_radius * 3.6
	spark.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.35, 1.0)
	spark.material_override = mat
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos

	# Audio 3D metálico de ping de desvío anime
	var sfx = AudioStreamPlayer3D.new()
	sfx.name = "DeflectSfx"
	if ResourceLoader.exists("res://assets/audio/gekishin_test/003073_s1.wav"):
		sfx.stream = load("res://assets/audio/gekishin_test/003073_s1.wav")
	sfx.unit_size = 5.0
	sfx.max_distance = 40.0
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = pos
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(spark, "scale", Vector3.ONE * 3.5, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), 0.15)
	tween.chain().tween_callback(spark.queue_free)
