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

enum AIDifficulty {
	TRAINING = 0,
	NORMAL = 1,
	Z_HARD = 2
}

@export var enabled: bool = true
@export var difficulty: AIDifficulty = AIDifficulty.NORMAL

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
	if not enabled or not host or not is_instance_valid(host) or bool(host.get("is_match_over")):
		return

	# Si la IA está en Bullet-Time (Minijuego Melee Rítmico), mantener guardia y esperar resolución rítmica
	if host.is_in_bullet_time:
		if not host.is_blocking and not host.is_guard_broken and host.current_ki > 5.0:
			host.is_blocking = true
		return

	# Si la IA está en secuencia de Super Haz de Ki, la resolución la gestiona SuperBeamSequenceController
	if host.get("is_in_beam_sequence"):
		return

	# Si el personaje está en ragdoll, volando o noqueado, pausar toma de decisiones
	if host.is_ragdoll_active or host.is_flying_to_opponent or host.is_knocked_back or host.wall_stick_timer > 0.0:
		if host.is_charging_ki and current_state != AIState.KI_RECHARGE:
			host.is_charging_ki = false
		if host.procedural_animator and host.procedural_animator.has_method("set_ki_recharge_phase"):
			host.procedural_animator.set_ki_recharge_phase(0)
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

	# Evaluación de transiciones tácticas según dificultad
	if decision_timer <= 0.0:
		decision_timer = 0.85 if difficulty == AIDifficulty.TRAINING else (0.22 if difficulty == AIDifficulty.Z_HARD else 0.35)
		_evaluate_tactical_transition(dist)


## Evalúa el cambio de estado según Ki, distancia, dificultad y CharacterData
func _evaluate_tactical_transition(dist: float) -> void:
	var host_max_ki: float = host.character_data.base_ki if host.character_data else 100.0
	var recharge_thresh: float = host_max_ki * 0.32
	if host.current_ki < recharge_thresh:
		_transition_to(AIState.KI_RECHARGE)
		return

	if attack_cooldown > 0.0:
		return

	if difficulty == AIDifficulty.TRAINING:
		# En modo entrenamiento solo lanza ráfagas esporádicas para practicar desvíos/esquives
		if host.current_ki >= 20.0 and dist >= 3.0 and randf() < 0.30:
			_transition_to(AIState.KI_BLAST_VOLLEY)
		else:
			attack_cooldown = 2.8
		return

	var super_chance: float = 0.62 if difficulty == AIDifficulty.Z_HARD else 0.45
	var super_info: Dictionary = _select_ai_super_power()
	var super_cost: float = float(super_info.get("ki_cost", 50.0))
	if host.current_ki >= super_cost and dist >= 3.5 and dist <= 12.0 and randf() < super_chance:
		_transition_to(AIState.KAMEHAMEHA_CHARGE)
		return

	var volley_chance: float = 0.82 if difficulty == AIDifficulty.Z_HARD else 0.70
	if host.current_ki >= 18.0 and dist >= 3.0 and randf() < volley_chance:
		_transition_to(AIState.KI_BLAST_VOLLEY)
		return

	var melee_chance: float = 0.60 if difficulty == AIDifficulty.Z_HARD else 0.40
	if host.current_ki >= 22.0 and dist <= 7.5:
		if player.current_ki < 20.0 or player.is_penalized or randf() < melee_chance:
			var cd_mult: float = 0.65 if difficulty == AIDifficulty.Z_HARD else 1.0
			attack_cooldown = randf_range(3.5, 6.0) * cd_mult
			_transition_to(AIState.MELEE_RUSH)
			return


## Estado 2: Recarga táctica de Ki
func _process_state_ki_recharge(delta: float) -> void:
	host.is_charging_ki = true
	if host.procedural_animator and host.procedural_animator.has_method("set_ki_recharge_phase"):
		host.procedural_animator.set_ki_recharge_phase(1 if state_timer < 0.35 else 2)
	var rate: float = 24.0 if difficulty == AIDifficulty.Z_HARD else 18.0
	host.recharge_ki(rate * delta)

	var diff = player.global_position - host.global_position
	diff.y = 0.0
	if diff.length() < 5.0:
		var back_dir = -diff.normalized()
		host.global_position += back_dir * 1.5 * delta
		host._clamp_to_arena(host)

	var max_ki: float = host.character_data.base_ki if host.character_data else 100.0
	if host.current_ki >= max_ki * 0.75 or state_timer >= 3.2:
		host.is_charging_ki = false
		if host.procedural_animator and host.procedural_animator.has_method("set_ki_recharge_phase"):
			host.procedural_animator.set_ki_recharge_phase(0)
		attack_cooldown = 0.5 if difficulty == AIDifficulty.Z_HARD else 0.8
		_transition_to(AIState.IDLE_SPACING)


## Estado 3: Ráfaga de Ki Blasts rápidos hacia el jugador
func _process_state_ki_blast_volley(delta: float) -> void:
	blast_interval_timer += delta
	var interval: float = 0.20 if difficulty == AIDifficulty.Z_HARD else (0.42 if difficulty == AIDifficulty.TRAINING else 0.28)
	if blast_interval_timer >= interval:
		blast_interval_timer = 0.0
		var target_pos = player.global_position + Vector3(0.0, 1.35, 0.0)
		_spawn_ki_blast(target_pos, false)
		blast_volley_count += 1

		if blast_volley_count >= blast_volley_target:
			var mult: float = 2.0 if difficulty == AIDifficulty.TRAINING else (0.65 if difficulty == AIDifficulty.Z_HARD else 1.0)
			attack_cooldown = randf_range(2.0, 3.8) * mult
			_transition_to(AIState.IDLE_SPACING)


## Estado 4: Carga y disparo del Super Ataque dinámico (Kamehameha / Galick Ho / Final Flash)
func _process_state_kamehameha_charge(delta: float) -> void:
	kamehameha_charge_timer += delta
	host.is_charging_ki = true
	var super_info: Dictionary = _select_ai_super_power()
	var s_name: String = String(super_info.get("name", "Kamehameha"))
	var s_color: Color = super_info.get("color", _get_host_energy_color())

	if host.procedural_animator and host.procedural_animator.has_method("set_super_pose"):
		host.procedural_animator.set_super_pose(s_name, 1)

	var sphere_offset: Vector3 = Vector3(-0.24, 0.96, 0.12)
	var s_low: String = s_name.to_lower()
	if "galick" in s_low:
		sphere_offset = Vector3(-0.28, 1.15, 0.10)
	elif "final" in s_low:
		sphere_offset = Vector3(0.0, 1.18, 0.28)

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
		mat.set_shader_parameter("base_color", Color(s_color.r, s_color.g, s_color.b, 0.95))
		mat.set_shader_parameter("core_glow", 5.0)
		kamehameha_vfx_sphere.material_override = mat

		host.add_child(kamehameha_vfx_sphere)
		kamehameha_vfx_sphere.position = sphere_offset
		_play_ai_sfx("kamehameha_charge")
	else:
		var progress = clampf(kamehameha_charge_timer / KAMEHAMEHA_CHARGE_DURATION, 0.1, 1.0)
		kamehameha_vfx_sphere.position = sphere_offset
		kamehameha_vfx_sphere.scale = Vector3.ONE * (0.8 + progress * 1.5)

	if kamehameha_charge_timer >= KAMEHAMEHA_CHARGE_DURATION:
		host.is_charging_ki = false
		host.stop_charging_super()
		if kamehameha_vfx_sphere and is_instance_valid(kamehameha_vfx_sphere):
			kamehameha_vfx_sphere.queue_free()
			kamehameha_vfx_sphere = null

		if host.procedural_animator and host.procedural_animator.has_method("set_super_pose"):
			host.procedural_animator.set_super_pose(s_name, 2)

		var target_pos = player.global_position + Vector3(0.0, 1.35, 0.0)
		_spawn_kamehameha_beam(target_pos)
		attack_cooldown = 3.6 if difficulty == AIDifficulty.Z_HARD else 5.0
		_transition_to(AIState.IDLE_SPACING)


## Cancela el Super Ataque por rotura de concentración
func interrupt_kamehameha() -> void:
	if current_state == AIState.KAMEHAMEHA_CHARGE:
		host.is_charging_ki = false
		host.stop_charging_super()
		if host.procedural_animator and host.procedural_animator.has_method("set_super_pose"):
			host.procedural_animator.set_super_pose("", 0)
		if kamehameha_vfx_sphere and is_instance_valid(kamehameha_vfx_sphere):
			kamehameha_vfx_sphere.queue_free()
			kamehameha_vfx_sphere = null
		_play_ai_sfx("hit_light")
		attack_cooldown = 2.5
		_transition_to(AIState.IDLE_SPACING)
		var super_name: String = String(_select_ai_super_power().get("name", "Super Ataque"))
		host._log_combat_event("[CONCENTRACIÓN ROTA] ¡El %s de %s fue interrumpido!" % [super_name, _get_host_name()], "warning")


## Estado 5: Guardia Defensiva
func _process_state_defensive_block(delta: float) -> void:
	host.is_blocking = true
	if state_timer >= 0.85:
		host.is_blocking = false
		_transition_to(AIState.IDLE_SPACING)


## Transición limpia entre estados
func _transition_to(new_state: AIState) -> void:
	if current_state == AIState.KAMEHAMEHA_CHARGE and new_state != AIState.KAMEHAMEHA_CHARGE:
		host.stop_charging_super()
		if not bool(host.get("is_firing_beam")) and host.procedural_animator and host.procedural_animator.has_method("set_super_pose"):
			host.procedural_animator.set_super_pose("", 0)
	if current_state == AIState.KI_RECHARGE and new_state != AIState.KI_RECHARGE:
		if host.procedural_animator and host.procedural_animator.has_method("set_ki_recharge_phase"):
			host.procedural_animator.set_ki_recharge_phase(0)

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
			host.start_charging_super()
		AIState.MELEE_RUSH:
			host.start_flight_to_opponent()
			_transition_to(AIState.IDLE_SPACING)
		AIState.DEFENSIVE_BLOCK:
			host.is_blocking = true
			block_cooldown = 1.8


## Capa reactiva: Detecta proyectiles enemigos entrantes y reacciona con Desvío con la mano, Esquive por pasos o Guardia Cruzada
func _check_incoming_threats() -> void:
	if is_stepping or current_state == AIState.KAMEHAMEHA_CHARGE:
		# Durante la carga del Kamehameha, Goku confía en su Super Armor / Poise
		return

	var my_pos = host.global_position
	for proj in get_tree().get_nodes_in_group("ki_projectiles"):
		if not is_instance_valid(proj) or proj.get("is_dead") or proj.get("shooter_node") == host:
			continue

		var p_pos: Vector3 = proj.global_position
		var dist = my_pos.distance_to(p_pos)
		if dist < 3.8:
			var p_vel: Vector3 = proj.get("speed_velocity") if proj.get("speed_velocity") != null else Vector3.ZERO
			var to_me = (my_pos - p_pos).normalized()
			# Si el proyectil vuela directo hacia el rival IA
			if p_vel.normalized().dot(to_me) > 0.65:
				var deflect_thresh: float = 0.15 if difficulty == AIDifficulty.TRAINING else (0.58 if difficulty == AIDifficulty.Z_HARD else 0.38)
				var rand_choice = randf()
				# A. Desvío activo con la mano (Ki Deflection) si está a corta distancia (< 2.4m)
				if rand_choice < deflect_thresh and dist < 2.4 and proj.get("tier") == 1:
					var hand_pos = my_pos + Vector3(0.2, 1.25, 0.4)
					var swipe_vel = Vector3(randf_range(-1.5, 1.5), 1.2, -1.8)
					proj.deflect_by_ai(hand_pos, swipe_vel, host)
					if host.procedural_animator:
						host.procedural_animator.trigger_hit_flinch(0.2, -swipe_vel.normalized())
					host._log_combat_event("[DESVÍO] ¡%s desvió tu Ki Blast con un golpe de mano! (+15 Ki, +150 BP)" % _get_host_name(), "info")
					return
				# B. Esquive con paso lateral por casillas si tiene Ki >= 8.0 y no está en cooldown
				elif difficulty != AIDifficulty.TRAINING and host.current_ki >= 8.0 and dodge_cooldown <= 0.0:
					var right_vec = host.global_transform.basis.x.normalized()
					var dodge_dir = right_vec * (1.0 if randf() > 0.5 else -1.0)
					if execute_step_movement(dodge_dir):
						host.consume_ki(8.0)
						dodge_cooldown = 1.1 if difficulty == AIDifficulty.Z_HARD else 1.8
						host._log_combat_event("[ESQUIVE] ¡%s dio un paso lateral evasivo para esquivar el ataque!" % _get_host_name(), "info")
						return
				# C. Bloqueo con Guardia Cruzada si no puede desviar ni esquivar
				elif difficulty != AIDifficulty.TRAINING and block_cooldown <= 0.0 and current_state != AIState.DEFENSIVE_BLOCK:
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


## Cambia el nivel de dificultad en caliente y retorna su etiqueta legible
func set_difficulty(new_diff: int) -> void:
	difficulty = clampi(new_diff, AIDifficulty.TRAINING, AIDifficulty.Z_HARD) as AIDifficulty
	if host and is_instance_valid(host):
		host._log_combat_event("[IA] Dificultad ajustada a: %s" % get_difficulty_label(), "info")


func get_difficulty_label() -> String:
	match difficulty:
		AIDifficulty.TRAINING: return "ENTRENAMIENTO"
		AIDifficulty.Z_HARD: return "Z-HARD"
		_: return "NORMAL"


func reset_ai_for_character() -> void:
	if kamehameha_vfx_sphere and is_instance_valid(kamehameha_vfx_sphere):
		kamehameha_vfx_sphere.queue_free()
		kamehameha_vfx_sphere = null
	attack_cooldown = 1.5
	dodge_cooldown = 0.0
	block_cooldown = 0.0
	_transition_to(AIState.IDLE_SPACING)


func _get_host_name() -> String:
	if host and host.character_data and host.character_data.character_name != "":
		return host.character_data.character_name
	return host.name if host else "Rival"


func _get_host_energy_color() -> Color:
	if host and host.character_data:
		var t: Variant = host.current_transformation
		if t and t.get("form_name") != null and "SSJ" in String(t.get("form_name")).to_upper():
			return Color(1.0, 0.85, 0.15, 0.95)
		if "VEGETA" in host.character_data.character_name.to_upper():
			return Color(0.85, 0.25, 1.0, 0.95)
	return Color(0.15, 0.65, 1.0, 0.95)


func _select_ai_super_power() -> Dictionary:
	var fallback_color: Color = _get_host_energy_color()
	if not host or not host.character_data or host.character_data.powers.is_empty():
		return { "name": "Kamehameha", "color": fallback_color, "damage": 1800.0, "ki_cost": 50.0, "tier": 3 }

	var current_form: String = host.current_transformation.form_name if host.current_transformation else ""
	var chosen: PowerData = null
	for p in host.character_data.powers:
		if not p:
			continue
		var trig_u: String = p.gesture_trigger.to_upper()
		var pname_u: String = p.power_name.to_upper()
		# Seleccionar super ataques tipo haz (excluyendo Ki Blast básico y esferas como Big Bang / Genkidama)
		var is_beam: bool = ("KAMEHAMEHA" in trig_u or "GALICK" in trig_u or "FINAL_FLASH" in trig_u or "KAMEHAMEHA" in pname_u or "GALICK" in pname_u or "FINAL FLASH" in pname_u)
		if not is_beam:
			continue
		if p.forbidden_transformations.has(current_form):
			continue
		if p.unlock_requirement_transformation != "" and not host.is_transformation_unlocked(p.unlock_requirement_transformation):
			continue
		if chosen == null or p.base_damage_np > chosen.base_damage_np:
			if host.current_ki >= p.ki_cost:
				chosen = p

	if chosen:
		var p_col: Color = chosen.energy_color if chosen.energy_color.a > 0.05 else fallback_color
		return {
			"name": chosen.power_name,
			"color": p_col,
			"damage": chosen.base_damage_np,
			"ki_cost": chosen.ki_cost,
			"tier": 4 if chosen.is_finisher else 3
		}
	return { "name": "Super Beam", "color": fallback_color, "damage": 1800.0, "ki_cost": 50.0, "tier": 3 }


## Despierta transformaciones progresivas para cualquier personaje en CharacterData según NP o rival
func _check_ai_transformation() -> void:
	if not host or not host.character_data or host.character_data.transformations.is_empty():
		return
	if difficulty == AIDifficulty.TRAINING:
		return

	var base_max: float = maxf(1.0, host.character_data.max_np)
	var np_ratio: float = host.current_np / base_max
	var player_trans = player.get("current_transformation") if (player and is_instance_valid(player)) else null
	var player_mult: float = float(player_trans.np_multiplier) if (player_trans and player_trans.get("np_multiplier") != null) else 1.0

	var current_idx: int = -1
	if host.current_transformation:
		current_idx = host.character_data.transformations.find(host.current_transformation)

	var desired_idx: int = current_idx
	var total_forms: int = host.character_data.transformations.size()

	# Igualar forma si el jugador supera en multiplicador, o despertar por presión de combate
	for i in range(total_forms):
		var form_cand: TransformationData = host.character_data.transformations[i]
		if not form_cand:
			continue
		var pressure_trigger: bool = (i == 0 and np_ratio <= 0.75) or (i == 1 and np_ratio <= 0.50) or (i >= 2 and np_ratio <= 0.30)
		var match_player: bool = (player_trans != null and form_cand.np_multiplier <= player_mult + 0.1)
		var z_hard_early: bool = (difficulty == AIDifficulty.Z_HARD and np_ratio <= 0.85 and i <= 1)
		if i > desired_idx and (pressure_trigger or match_player or z_hard_early):
			desired_idx = i

	if desired_idx > current_idx and desired_idx >= 0 and desired_idx < total_forms:
		var trans = host.character_data.transformations[desired_idx]
		if not host.is_transformation_unlocked(trans.form_name):
			host.unlock_transformation(trans.form_name)
		host.transform_to(desired_idx)
		_play_ai_sfx("aura")
		host._log_combat_event("🔥 ¡%s ha despertado %s para igualar la batalla!" % [_get_host_name(), trans.form_name], "warning")


## Instancia un Ki Blast procedural dinámico según CharacterData del rival
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
	var energy_color = _get_host_energy_color()
	if host.procedural_animator and host.procedural_animator.has_method("trigger_ki_blast_shot"):
		host.procedural_animator.trigger_ki_blast_shot(blast_volley_count % 2)

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
	projectile.set("was_launched_in_zenkai", bool(host.get("is_in_zenkai_state")))

	var excludes: Array[RID] = []
	if host.has_method("get_projectile_exclude_rids"):
		excludes = host.get_projectile_exclude_rids().duplicate()
	else:
		for child in host.get_children():
			if child is CollisionObject3D:
				excludes.append(child.get_rid())
	projectile.set("ray_query_exclude", excludes)

	var current_scene = host.get_tree().current_scene
	current_scene.add_child(projectile)
	projectile.global_position = spawn_pos

	_play_ai_sfx("ki_blast")


## Instancia el Super Haz dinámico según CharacterData del rival
func _spawn_kamehameha_beam(target_pos: Vector3) -> void:
	var super_info: Dictionary = _select_ai_super_power()
	var s_name: String = String(super_info.get("name", "Kamehameha"))
	var s_color: Color = super_info.get("color", _get_host_energy_color())
	var s_dmg: float = float(super_info.get("damage", 1800.0))
	var s_cost: float = float(super_info.get("ki_cost", 50.0))
	var s_tier: int = int(super_info.get("tier", 3))

	if not host.consume_ki(s_cost):
		return

	# Activación de la Secuencia Cinemática y Bullet-Time de Super Ataque para la IA
	if host and host.has_method("start_super_beam_sequence"):
		var opp = host._get_opponent()
		if opp and is_instance_valid(opp):
			host.start_super_beam_sequence(s_name, s_color, s_dmg, s_tier)
			_play_ai_sfx("kamehameha_fire")
			return

	var fwd = (target_pos - host.global_position).normalized()
	if fwd.length_squared() < 0.01:
		fwd = -host.global_transform.basis.z

	var spawn_pos = host.global_position + Vector3(0.0, 1.25, 0.0) + fwd * 0.70
	var dir = (target_pos - spawn_pos).normalized()
	var projectile_radius = 0.36
	var speed = 30.0
	var energy_color = Color(s_color.r, s_color.g, s_color.b, 0.98)

	var projectile = Node3D.new()
	projectile.name = "EnemySuper_" + s_name.replace(" ", "") + "_" + str(Time.get_ticks_msec())

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
	projectile.set("was_launched_in_zenkai", bool(host.get("is_in_zenkai_state")))

	var excludes: Array[RID] = []
	if host.has_method("get_projectile_exclude_rids"):
		excludes = host.get_projectile_exclude_rids().duplicate()
	else:
		for child in host.get_children():
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
				audio_player_3d.pitch_scale = randf_range(0.92, 1.08)
				audio_player_3d.play()
		"kamehameha_fire":
			if snd_ki_blast:
				audio_player_3d.stream = snd_ki_blast
				audio_player_3d.pitch_scale = 0.85 * randf_range(0.92, 1.08)
				audio_player_3d.play()
		"ki_blast":
			if snd_ki_blast:
				audio_player_3d.stream = snd_ki_blast
				audio_player_3d.pitch_scale = randf_range(1.05, 1.25)
				audio_player_3d.play()
		"aura":
			if snd_aura:
				audio_player_3d.stream = snd_aura
				audio_player_3d.pitch_scale = randf_range(0.92, 1.08)
				audio_player_3d.play()
		"step", "vanish":
			if snd_vanish:
				audio_player_3d.stream = snd_vanish
				audio_player_3d.pitch_scale = randf_range(1.15, 1.35)
				audio_player_3d.volume_db = -4.0
				audio_player_3d.play()
