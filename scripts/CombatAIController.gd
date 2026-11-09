class_name CombatAIController
extends Node

## CombatAIController (Godot 4.3+ VR)
## Inteligencia Artificial reactiva y táctica para el oponente (Goku / CPU) en Dragon Ball VR.
## Maneja:
## - Posicionamiento cinemático (Spacing y órbita reactiva 1v1)
## - Recarga táctica de Ki en Fase 1/Fase 2 cuando baja del umbral
## - Ráfagas de Ki Blasts rápidos hacia el jugador
## - Carga y lanzamiento de Kamehameha (Super Beam) con aviso visual y sonoro
## - Desplazamiento ofensivo Melee Dash si el jugador baja la guardia
## - Reacciones defensivas en tiempo real: Z-Vanish (teletransporte) y Bloqueo
## - Despertar de transformaciones dinámicas (Kaioken / Super Saiyan) en combate

const ProceduralKiProjectileScript = preload("res://scripts/ProceduralKiProjectile.gd")
const KiSphereShader = preload("res://ki_sphere.gdshader")
const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")

enum AIState {
	IDLE_SPACING,
	KI_RECHARGE,
	KI_BLAST_VOLLEY,
	KAMEHAMEHA_CHARGE,
	MELEE_RUSH,
	STEP_DODGE,
	DEFENSIVE_BLOCK
}

@export var enabled: bool = true

# Referencias
var host: CharacterInstance = null
var player: CharacterInstance = null

# Estado y temporizadores FSM
var current_state: AIState = AIState.IDLE_SPACING
var state_timer: float = 0.0
var decision_timer: float = 0.0
var attack_cooldown: float = 2.5
var dodge_cooldown: float = 0.0
var block_cooldown: float = 0.0
var spacing_step_timer: float = 0.0
var next_spacing_interval: float = 1.6
var is_stepping: bool = false

# Parámetros de combate por casillas / pasos
const AI_STEP_DISTANCE: float = 2.0
const VERTICAL_STEP: float = 1.4
const MIN_ALLOWED_DISTANCE: float = 2.4
const OPTIMAL_DIST_MIN: float = 3.2
const OPTIMAL_DIST_MAX: float = 5.8

# Ráfaga de Ki Blasts
var blast_volley_count: int = 0
var blast_volley_target: int = 3
var blast_interval_timer: float = 0.0

# Carga de Kamehameha
const KAMEHAMEHA_CHARGE_DURATION: float = 1.8
var kamehameha_charge_timer: float = 0.0
var kamehameha_vfx_sphere: MeshInstance3D = null

# Audio 3D del rival
var audio_player_3d: AudioStreamPlayer3D = null
var snd_kamehameha: AudioStream = null
var snd_aura: AudioStream = null
var snd_vanish: AudioStream = null
var snd_ki_blast: AudioStream = null


func _ready() -> void:
	host = get_parent() as CharacterInstance
	if not host:
		set_physics_process(false)
		return

	# Configurar reproductor de audio 3D para la IA
	audio_player_3d = AudioStreamPlayer3D.new()
	audio_player_3d.name = "AIAudioPlayer3D"
	audio_player_3d.unit_size = 5.0
	audio_player_3d.max_distance = 60.0
	add_child(audio_player_3d)

	# Cargar efectos de sonido canónicos
	if ResourceLoader.exists("res://assets/sfx/Kamehameha Regular.mp3"):
		snd_kamehameha = load("res://assets/sfx/Kamehameha Regular.mp3")
	if ResourceLoader.exists("res://assets/sfx/AURA.mp3"):
		snd_aura = load("res://assets/sfx/AURA.mp3")
	if ResourceLoader.exists("res://assets/audio/gekishin_test/003074_s4.wav"):
		snd_vanish = load("res://assets/audio/gekishin_test/003074_s4.wav")
	if ResourceLoader.exists("res://assets/sfx/Charged_KI_Blast_1.mp3"):
		snd_ki_blast = load("res://assets/sfx/Charged_KI_Blast_1.mp3")

	print("[CombatAIController] IA inicializada para %s" % (host.character_data.character_name if host.character_data else host.name))


func _physics_process(delta: float) -> void:
	if not enabled or not host or not is_instance_valid(host):
		return

	# Si el personaje está en ragdoll, volando o noqueado, pausar toma de decisiones
	if host.is_ragdoll_active or host.is_flying_to_opponent or host.is_knocked_back or host.is_in_bullet_time or host.wall_stick_timer > 0.0:
		if host.is_charging_ki and current_state != AIState.KI_RECHARGE:
			host.is_charging_ki = false
		return

	# Buscar jugador si no está asignado
	if not player or not is_instance_valid(player):
		var opp = host._get_opponent()
		if opp is CharacterInstance:
			player = opp
		if not player:
			return

	# Actualizar temporizadores
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if dodge_cooldown > 0.0:
		dodge_cooldown -= delta
	if block_cooldown > 0.0:
		block_cooldown -= delta
	if decision_timer > 0.0:
		decision_timer -= delta

	state_timer += delta

	# Capa reactiva defensiva inmediata (Esquive por paso o Bloqueo ante proyectiles)
	_check_incoming_threats()

	# Capa de transformaciones autónomas de la IA
	_check_ai_transformation()

	# Ejecutar máquina de estados principal
	match current_state:
		AIState.IDLE_SPACING:
			_process_state_idle_spacing(delta)
		AIState.KI_RECHARGE:
			_process_state_ki_recharge(delta)
		AIState.KI_BLAST_VOLLEY:
			_process_state_ki_blast_volley(delta)
		AIState.KAMEHAMEHA_CHARGE:
			_process_state_kamehameha_charge(delta)
		AIState.DEFENSIVE_BLOCK:
			_process_state_defensive_block(delta)


## Estado 1: Mantenimiento de distancia (Spacing) y órbita por casillas
func _process_state_idle_spacing(delta: float) -> void:
	var my_pos = host.global_position
	var opp_pos = player.global_position
	var diff = opp_pos - my_pos
	diff.y = 0.0
	var dist = diff.length()
	var fwd = diff.normalized() if dist > 0.01 else -host.global_transform.basis.z

	# Pasos de reposicionamiento cada 1.2s - 2.2s
	spacing_step_timer += delta
	if spacing_step_timer >= next_spacing_interval and not is_stepping:
		spacing_step_timer = 0.0
		next_spacing_interval = randf_range(1.2, 2.2)

		var right_vec = host.global_transform.basis.x.normalized()
		var lateral = right_vec * (1.0 if randf() > 0.5 else -1.0)

		# Evaluar nivel de elevación vertical con el jugador
		var y_diff = player.global_position.y - host.global_position.y
		if y_diff > 1.2:
			execute_vertical_step(true)
		elif y_diff < -1.2:
			execute_vertical_step(false)
		elif dist > OPTIMAL_DIST_MAX:
			# Acercarse un paso hacia adelante si no invade distancia mínima
			execute_step_movement(fwd)
		elif dist < OPTIMAL_DIST_MIN:
			# Paso atrás para recuperar espacio
			execute_step_movement(-fwd)
		else:
			# Paso lateral (órbita)
			execute_step_movement(lateral)

	# Evaluación de transiciones tácticas cada 0.35s
	if decision_timer <= 0.0:
		decision_timer = 0.35
		_evaluate_tactical_transition(dist)


## Evalúa el cambio de estado según Ki, distancia y estado del jugador
func _evaluate_tactical_transition(dist: float) -> void:
	# 1. Si el Ki de Goku está bajo (< 32.0), priorizar recarga
	if host.current_ki < 32.0:
		_transition_to(AIState.KI_RECHARGE)
		return

	# Si los ataques están en cooldown, seguir en Spacing
	if attack_cooldown > 0.0:
		return

	# 2. Si tiene Ki suficiente (>= 50) y distancia media/larga, probabilidad de Kamehameha
	if host.current_ki >= 50.0 and dist >= 3.5 and dist <= 10.0 and randf() < 0.45:
		_transition_to(AIState.KAMEHAMEHA_CHARGE)
		return

	# 3. Disparar ráfaga de Ki Blasts
	if host.current_ki >= 18.0 and dist >= 3.0 and randf() < 0.70:
		_transition_to(AIState.KI_BLAST_VOLLEY)
		return

	# 4. Melee Dash si el jugador tiene la guardia baja o Ki agotado y está cerca (< 6.0m)
	if host.current_ki >= 25.0 and dist <= 6.0 and (player.current_ki < 20.0 or player.is_penalized):
		_transition_to(AIState.MELEE_RUSH)


## Estado 2: Recarga táctica de Ki
func _process_state_ki_recharge(delta: float) -> void:
	host.is_charging_ki = true
	host.recharge_ki(18.0 * delta)

	# Retroceder lentamente mientras recarga para mantener distancia
	var diff = player.global_position - host.global_position
	diff.y = 0.0
	if diff.length() < 5.0:
		var back_dir = -diff.normalized()
		host.global_position += back_dir * 1.5 * delta
		host._clamp_to_arena(host)

	# Salir de recarga si el Ki llega al 75% o si pasó el tiempo límite
	if host.current_ki >= 75.0 or state_timer >= 3.2:
		host.is_charging_ki = false
		attack_cooldown = 0.8
		_transition_to(AIState.IDLE_SPACING)


## Estado 3: Ráfaga de Ki Blasts rápidos hacia el jugador
func _process_state_ki_blast_volley(delta: float) -> void:
	blast_interval_timer += delta
	if blast_interval_timer >= 0.28:
		blast_interval_timer = 0.0
		var target_pos = player.global_position + Vector3(0.0, 1.35, 0.0) # Apuntar al pecho
		_spawn_ki_blast(target_pos, false)
		blast_volley_count += 1

		if blast_volley_count >= blast_volley_target:
			attack_cooldown = randf_range(2.0, 3.8)
			_transition_to(AIState.IDLE_SPACING)


## Estado 4: Carga y disparo del Kamehameha
func _process_state_kamehameha_charge(delta: float) -> void:
	kamehameha_charge_timer += delta
	host.is_charging_ki = true

	# Crear y expandir esfera de Ki azul entre las manos
	if not kamehameha_vfx_sphere or not is_instance_valid(kamehameha_vfx_sphere):
		kamehameha_vfx_sphere = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		sphere.radial_segments = 16
		sphere.rings = 8
		kamehameha_vfx_sphere.mesh = sphere

		var mat = ShaderMaterial.new()
		mat.shader = KiSphereShader
		mat.set_shader_parameter("base_color", Color(0.1, 0.75, 1.0, 0.95))
		mat.set_shader_parameter("core_glow", 5.0)
		kamehameha_vfx_sphere.material_override = mat

		host.add_child(kamehameha_vfx_sphere)
		kamehameha_vfx_sphere.position = Vector3(0.18, 1.05, 0.35)

		# Reproducir audio de Kamehameha
		_play_ai_sfx("kamehameha_charge")
	else:
		# Escalar con la carga
		var progress = clampf(kamehameha_charge_timer / KAMEHAMEHA_CHARGE_DURATION, 0.1, 1.0)
		kamehameha_vfx_sphere.scale = Vector3.ONE * (0.8 + progress * 1.5)

	# Al completar la carga: ¡DISPARAR!
	if kamehameha_charge_timer >= KAMEHAMEHA_CHARGE_DURATION:
		host.is_charging_ki = false
		if kamehameha_vfx_sphere and is_instance_valid(kamehameha_vfx_sphere):
			kamehameha_vfx_sphere.queue_free()
			kamehameha_vfx_sphere = null

		var target_pos = player.global_position + Vector3(0.0, 1.35, 0.0)
		_spawn_kamehameha_beam(target_pos)
		attack_cooldown = 5.0
		_transition_to(AIState.IDLE_SPACING)


## Estado 5: Guardia Defensiva
func _process_state_defensive_block(delta: float) -> void:
	host.is_blocking = true
	if state_timer >= 0.85:
		host.is_blocking = false
		_transition_to(AIState.IDLE_SPACING)


## Transición limpia entre estados
func _transition_to(new_state: AIState) -> void:
	state_timer = 0.0
	current_state = new_state

	match new_state:
		AIState.IDLE_SPACING:
			host.is_blocking = false
			host.is_charging_ki = false
		AIState.KI_RECHARGE:
			_play_ai_sfx("aura")
		AIState.KI_BLAST_VOLLEY:
			blast_volley_count = 0
			blast_volley_target = randi_range(2, 4)
			blast_interval_timer = 0.20 # Disparo casi inmediato del primer blast
		AIState.KAMEHAMEHA_CHARGE:
			kamehameha_charge_timer = 0.0
		AIState.MELEE_RUSH:
			host.start_flight_to_opponent()
			_transition_to(AIState.IDLE_SPACING)
		AIState.DEFENSIVE_BLOCK:
			host.is_blocking = true
			block_cooldown = 1.8


## Capa reactiva: Detecta proyectiles enemigos entrantes y reacciona con Esquive por pasos o Bloqueo
func _check_incoming_threats() -> void:
	if is_stepping:
		return

	var my_pos = host.global_position
	for proj in get_tree().get_nodes_in_group("ki_projectiles"):
		if not is_instance_valid(proj) or proj.get("is_dead") or proj.get("shooter_node") == host:
			continue

		var p_pos: Vector3 = proj.global_position
		var dist = my_pos.distance_to(p_pos)
		if dist < 4.2:
			var p_vel: Vector3 = proj.get("speed_velocity") if proj.get("speed_velocity") != null else Vector3.ZERO
			var to_me = (my_pos - p_pos).normalized()
			# Si el proyectil vuela directo hacia Goku
			if p_vel.normalized().dot(to_me) > 0.65:
				# 1. Esquive con paso lateral por casillas si tiene Ki >= 8.0 y no está en cooldown
				if host.current_ki >= 8.0 and dodge_cooldown <= 0.0:
					var right_vec = host.global_transform.basis.x.normalized()
					var dodge_dir = right_vec * (1.0 if randf() > 0.5 else -1.0)
					if execute_step_movement(dodge_dir):
						host.consume_ki(8.0)
						dodge_cooldown = 1.8
						host._log_combat_event("[ESQUIVE] ¡%s dio un paso lateral evasivo para esquivar el ataque!" % (host.character_data.character_name if host.character_data else "Goku"), "info")
						return
				# 2. Bloqueo con guardia si no puede dar un paso
				elif block_cooldown <= 0.0 and current_state != AIState.DEFENSIVE_BLOCK:
					_transition_to(AIState.DEFENSIVE_BLOCK)
					return


## Ejecuta un paso discreto por casillas en el plano horizontal
func execute_step_movement(move_dir: Vector3) -> bool:
	if not host or not is_instance_valid(host) or is_stepping:
		return false

	var target_pos = host.global_position + move_dir * AI_STEP_DISTANCE

	# 1. Comprobación estricta de distancia mínima con el jugador (2.4m)
	if player and is_instance_valid(player):
		var p_pos = player.global_position
		var current_diff = p_pos - host.global_position
		current_diff.y = 0.0
		var current_dist = current_diff.length()

		var future_diff = p_pos - target_pos
		future_diff.y = 0.0
		var future_dist = future_diff.length()

		# Si el paso nos acerca al rival y nos deja a menos de 2.4m, bloquear el paso
		if future_dist < current_dist and future_dist < MIN_ALLOWED_DISTANCE:
			return false

	# 2. Comprobar límites de arena
	var dist_center = Vector2(target_pos.x, target_pos.z).length()
	if dist_center > host.arena_half_limit:
		return false

	# 3. Desplazamiento ágil estilo anime (0.16s Tween)
	is_stepping = true
	_play_ai_sfx("step")

	var tween = host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(host, "global_position", target_pos, 0.16)
	tween.tween_callback(func(): is_stepping = false)
	return true


## Ejecuta un paso vertical (subir o bajar en el aire)
func execute_vertical_step(is_up: bool) -> bool:
	if not host or not is_instance_valid(host) or is_stepping:
		return false

	var current_pos = host.global_position
	var ground_h = host.get_ground_elevation(current_pos)
	var target_y = current_pos.y + (VERTICAL_STEP if is_up else -VERTICAL_STEP)

	if is_up:
		if target_y > ground_h + 9.0:
			return false
	else:
		if target_y < ground_h + 0.05:
			target_y = ground_h + 0.05

	var target_pos = Vector3(current_pos.x, target_y, current_pos.z)
	is_stepping = true
	_play_ai_sfx("step")

	var tween = host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(host, "global_position", target_pos, 0.16)
	tween.tween_callback(func(): is_stepping = false)
	return true


## Despierta transformaciones para Goku en tiempo real según el peligro
func _check_ai_transformation() -> void:
	if not host or not host.character_data or host.character_data.transformations.is_empty():
		return
	if host.current_transformation != null:
		return

	var active_max: float = host.character_data.max_np
	var hp_ratio: float = host.current_np / maxf(1.0, active_max)
	var player_trans = player.get("current_transformation") if (player and is_instance_valid(player)) else null

	# Si el jugador se transformó o Goku tiene daño crítico (<= 65% NP):
	if player_trans != null or hp_ratio <= 0.65:
		var target_idx = 0
		# Si el jugador ya está en SSJ y Goku tiene SSJ disponible, igualar a SSJ
		if player_trans != null and host.character_data.transformations.size() > 1:
			target_idx = 1

		var trans = host.character_data.transformations[target_idx]
		if not host.is_transformation_unlocked(trans.form_name):
			host.unlock_transformation(trans.form_name)

		host.transform_to(target_idx)
		_play_ai_sfx("aura")
		host._log_combat_event("🔥 ¡Goku ha despertado %s para igualar la batalla!" % trans.form_name, "warning")


## Instancia un Ki Blast procedural de Goku
func _spawn_ki_blast(target_pos: Vector3, is_charged: bool = false) -> void:
	if not host.consume_ki(14.0 if is_charged else 6.0):
		return

	var fwd = (target_pos - host.global_position).normalized()
	if fwd.length_squared() < 0.01:
		fwd = -host.global_transform.basis.z

	var lateral = host.global_transform.basis.x * (0.20 if (blast_volley_count % 2 == 0) else -0.20)
	var spawn_pos = host.global_position + Vector3(0.0, 1.25, 0.0) + fwd * 0.45 + lateral
	var dir = (target_pos - spawn_pos).normalized()

	var projectile_radius = 0.16 if is_charged else 0.06
	var speed = 16.0 if is_charged else 26.0
	var energy_color = Color(0.15, 0.65, 1.0, 0.95) # Celeste de Goku

	var projectile = Node3D.new()
	projectile.name = "EnemyKiProjectile_" + str(Time.get_ticks_msec())

	var mesh_core = MeshInstance3D.new()
	var sphere_core = SphereMesh.new()
	sphere_core.radius = projectile_radius
	sphere_core.height = projectile_radius * 2.0
	sphere_core.radial_segments = 16
	sphere_core.rings = 8
	mesh_core.mesh = sphere_core

	var mat_core = ShaderMaterial.new()
	mat_core.shader = KiSphereShader
	mat_core.set_shader_parameter("base_color", energy_color)
	mat_core.set_shader_parameter("core_glow", 4.5)
	mesh_core.material_override = mat_core
	projectile.add_child(mesh_core)

	var mesh_corona = MeshInstance3D.new()
	var sphere_corona = SphereMesh.new()
	sphere_corona.radius = projectile_radius * 1.15
	sphere_corona.height = projectile_radius * 2.30
	sphere_corona.radial_segments = 16
	sphere_corona.rings = 8
	mesh_corona.mesh = sphere_corona

	var mat_corona = ShaderMaterial.new()
	mat_corona.shader = KiCoronaShader
	mat_corona.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.85))
	mat_corona.set_shader_parameter("vertex_displacement", 0.04)
	mesh_corona.material_override = mat_corona
	projectile.add_child(mesh_corona)

	var light = OmniLight3D.new()
	light.light_color = energy_color
	light.light_energy = 2.0 if is_charged else 1.2
	light.omni_range = 2.2 if is_charged else 1.2
	projectile.add_child(light)

	projectile.set_script(ProceduralKiProjectileScript)
	projectile.set("speed_velocity", dir * speed)
	projectile.set("p_radius", projectile_radius)
	projectile.set("p_color", energy_color)
	projectile.set("tier", 2 if is_charged else 1)
	projectile.set("base_damage", 550.0 if is_charged else 220.0)
	projectile.set("explosion_radius", 2.0 if is_charged else 1.2)
	projectile.set("shooter_node", host)

	var excludes: Array[RID] = []
	for child in host.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			excludes.append(child.get_rid())
	projectile.set("ray_query_exclude", excludes)

	var current_scene = host.get_tree().current_scene
	current_scene.add_child(projectile)
	projectile.global_position = spawn_pos

	_play_ai_sfx("ki_blast")


## Instancia el Super Kamehameha de Goku
func _spawn_kamehameha_beam(target_pos: Vector3) -> void:
	if not host.consume_ki(50.0):
		return

	var fwd = (target_pos - host.global_position).normalized()
	if fwd.length_squared() < 0.01:
		fwd = -host.global_transform.basis.z

	var spawn_pos = host.global_position + Vector3(0.0, 1.25, 0.0) + fwd * 0.70
	var dir = (target_pos - spawn_pos).normalized()
	var projectile_radius = 0.36
	var speed = 30.0
	var energy_color = Color(0.12, 0.78, 1.0, 0.98)

	var projectile = Node3D.new()
	projectile.name = "EnemyKamehameha_" + str(Time.get_ticks_msec())

	var mesh_core = MeshInstance3D.new()
	var sphere_core = SphereMesh.new()
	sphere_core.radius = projectile_radius
	sphere_core.height = projectile_radius * 2.8
	sphere_core.radial_segments = 20
	sphere_core.rings = 10
	mesh_core.mesh = sphere_core

	var mat_core = ShaderMaterial.new()
	mat_core.shader = KiSphereShader
	mat_core.set_shader_parameter("base_color", energy_color)
	mat_core.set_shader_parameter("core_glow", 6.0)
	mesh_core.material_override = mat_core
	projectile.add_child(mesh_core)

	var mesh_corona = MeshInstance3D.new()
	var sphere_corona = SphereMesh.new()
	sphere_corona.radius = projectile_radius * 1.30
	sphere_corona.height = projectile_radius * 3.50
	sphere_corona.radial_segments = 20
	sphere_corona.rings = 10
	mesh_corona.mesh = sphere_corona

	var mat_corona = ShaderMaterial.new()
	mat_corona.shader = KiCoronaShader
	mat_corona.set_shader_parameter("base_color", Color(0.35, 0.85, 1.0, 0.85))
	mat_corona.set_shader_parameter("vertex_displacement", 0.07)
	mesh_corona.material_override = mat_corona
	projectile.add_child(mesh_corona)

	var light = OmniLight3D.new()
	light.light_color = energy_color
	light.light_energy = 3.5
	light.omni_range = 4.0
	projectile.add_child(light)

	projectile.set_script(ProceduralKiProjectileScript)
	projectile.set("speed_velocity", dir * speed)
	projectile.set("p_radius", projectile_radius)
	projectile.set("p_color", energy_color)
	projectile.set("tier", 3)
	projectile.set("base_damage", 1800.0)
	projectile.set("explosion_radius", 3.2)
	projectile.set("shooter_node", host)

	var excludes: Array[RID] = []
	for child in host.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			excludes.append(child.get_rid())
	projectile.set("ray_query_exclude", excludes)

	var current_scene = host.get_tree().current_scene
	current_scene.add_child(projectile)
	projectile.global_position = spawn_pos

	_play_ai_sfx("kamehameha_fire")
	if host.has_method("_spawn_melee_shockwave"):
		host._spawn_melee_shockwave(spawn_pos)


## Reproductor de audio SFX para la IA
func _play_ai_sfx(sfx_type: String) -> void:
	if not audio_player_3d:
		return

	match sfx_type:
		"kamehameha_charge":
			if snd_kamehameha:
				audio_player_3d.stream = snd_kamehameha
				audio_player_3d.pitch_scale = 1.0
				audio_player_3d.play()
		"kamehameha_fire":
			if snd_ki_blast:
				audio_player_3d.stream = snd_ki_blast
				audio_player_3d.pitch_scale = 0.85
				audio_player_3d.play()
		"ki_blast":
			if snd_ki_blast:
				audio_player_3d.stream = snd_ki_blast
				audio_player_3d.pitch_scale = randf_range(1.05, 1.25)
				audio_player_3d.play()
		"aura":
			if snd_aura:
				audio_player_3d.stream = snd_aura
				audio_player_3d.pitch_scale = 1.0
				audio_player_3d.play()
		"step", "vanish":
			if snd_vanish:
				audio_player_3d.stream = snd_vanish
				audio_player_3d.pitch_scale = randf_range(1.15, 1.35)
				audio_player_3d.volume_db = -4.0
				audio_player_3d.play()
