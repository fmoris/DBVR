class_name CharacterInstance
extends Node3D

signal stats_changed(ki: float, np: float, is_zenkai: bool)
signal transformed(transformation: Resource)
signal power_unlocked(power_name: String)
signal game_finished(winner_name: String)
signal zenkai_activated(source: String) # "brecha", "comeback"

@export var character_data: Resource

# Estadísticas activas en runtime
var current_ki: float = 50.0
var current_np: float = 9000.0

var current_transformation: Resource = null
var unlocked_powers: Array[String] = []

# Estado de Zenkai y Comebacks
var is_in_zenkai_state: bool = false
var is_comeback_zenkai: bool = false # Si es true, el Zenkai se activó por remontada y dura solo un ataque
var is_penalized: bool = false
var penalty_timer: float = 0.0
# Umbrales irreversibles de NP (Canon GDD: 25%, 50%, 75%, 100%)
var secured_np_threshold_ratio: float = 0.0

# --- Físicas 3D, Colisiones y Knockback ---
var velocity: Vector3 = Vector3.ZERO
var knockback_drag: float = 24.0 # Fricción alta para frenado realista de cuerpos (cero rebote excesivo)
var gravity: float = 9.8
var is_knocked_back: bool = false
var arena_half_limit: float = 92.0 # Límite en las faldas del cañón de Akira Toriyama
const RING_HALF_SIZE: float = 16.0 # Límite del cuadrilátero de piedra de Cell (32x32m)
var wall_stick_timer: float = 0.0 # Efecto de quedar incrustado en la roca de la montaña (Toriyama canon)

# --- Estado de Guardia y Bloqueo Defensivo ---
var is_blocking: bool = false
var is_guard_broken: bool = false
var guard_break_timer: float = 0.0

# Referencias visuales internas
var body_mesh_instance: Node3D = null
var aura_particles: Node3D = null
var aura_mesh_ref: MeshInstance3D = null
var aura_light_ref: OmniLight3D = null

# Variables para seguimiento de jugador y prevención de clipping
var is_player: bool = false
var skeleton: Skeleton3D = null
const ProceduralCombatAnimatorClass = preload("res://scripts/ProceduralCombatAnimator.gd")
var procedural_animator: RefCounted = null
var combat_anim_player: AnimationPlayer = null
var head_bone_idx: int = -1
var neck_bone_idx: int = -1
var torso_yaw: float = 0.0

# Índices óseos para Cinemática Inversa (IK) de brazos en 1ra persona
var left_arm_idx: int = -1
var left_forearm_idx: int = -1
var left_hand_idx: int = -1
var right_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1

const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const MeleeTargetDomeClass = preload("res://scripts/MeleeTargetDome.gd")
var is_charging_ki: bool = false
var aura_node: Node3D = null

# Estado y control de Bullet-Time (Dilatación temporal en combate cuerpo a cuerpo)
var is_in_bullet_time: bool = false
var active_target_dome: Node3D = null
var is_target_locked: bool = false # Requisito canónico de fijación visual para Melee Dash
var is_in_followup_bullet_time: bool = false
var followup_bullet_time_timer: float = 0.0
var opponent_airborne_target: Node3D = null

# Variables de vuelo hacia el contrincante
var is_flying_to_opponent: bool = false
var flight_speed: float = 35.0

# Instancias de manos para el jugador
var hand_left_instance: Node3D = null
var hand_right_instance: Node3D = null

# Sistema de Ragdoll físico autónomo (Godot PhysicalBoneSimulator3D)
var ragdoll_simulator: PhysicalBoneSimulator3D = null
var is_ragdoll_active: bool = false
var ragdoll_recovery_timer: float = 0.0


func _ready() -> void:
	if character_data:
		setup_character()

func setup_character() -> void:
	current_ki = character_data.base_ki / 2.0
	current_np = character_data.base_np
	_update_secured_threshold(character_data.max_np)
	
	is_player = get_parent() is XROrigin3D
	
	if is_player:
		# Escalar el XROrigin3D (espacio de seguimiento) para alinear la altura física y el alcance de brazos
		var origin = get_parent()
		var s_factor = character_data.scale_factor if character_data.scale_factor > 0.01 else 1.0
		origin.scale = Vector3.ONE * s_factor
		scale = Vector3.ONE # La escala de la instancia del jugador debe ser 1.0 para evitar doble escalado
		print("[CharacterInstance] Jugador: Origen XR escalado a %.2f (Estatura canon: %.2fm)" % [s_factor, 1.75 * s_factor])
	else:
		scale = Vector3.ONE * character_data.scale_factor
	
	# Desbloquear técnicas base
	unlocked_powers.clear()
	for power in character_data.powers:
		if power.unlock_requirement_transformation == "":
			unlocked_powers.append(power.power_name)
			
	# Instanciar el modelo del cuerpo en runtime (tanto para el rival como para el jugador en 1ra persona)
	if character_data.body_model_path != "":
		var scene = load(character_data.body_model_path)
		if scene:
			body_mesh_instance = scene.instantiate()
			body_mesh_instance.scale = Vector3.ONE * character_data.model_asset_scale
			add_child(body_mesh_instance)
			
			# Obtener esqueleto tanto para el jugador como para el oponente
			skeleton = _find_skeleton(body_mesh_instance)
			if skeleton:
				skeleton.name = "Skeleton3D" # Asegura resolución exacta de tracks para AnimationPlayer y Ragdoll
				if is_player:
					head_bone_idx = skeleton.find_bone("Head")
					if head_bone_idx == -1:
						head_bone_idx = skeleton.find_bone("head")
					if head_bone_idx == -1:
						for i in range(skeleton.get_bone_count()):
							var bone_name = skeleton.get_bone_name(i).to_lower()
							if "head" in bone_name:
								head_bone_idx = i
								break
					if head_bone_idx != -1:
						skeleton.set_bone_pose_scale(head_bone_idx, Vector3.ZERO)
						
					neck_bone_idx = skeleton.find_bone("Neck")
					if neck_bone_idx == -1:
						neck_bone_idx = skeleton.find_bone("neck")

					left_arm_idx = skeleton.find_bone("LeftArm")
					left_forearm_idx = skeleton.find_bone("LeftForeArm")
					left_hand_idx = skeleton.find_bone("LeftHand")

					right_arm_idx = skeleton.find_bone("RightArm")
					right_forearm_idx = skeleton.find_bone("RightForeArm")
					right_hand_idx = skeleton.find_bone("RightHand")

					var cam = get_parent().get_node_or_null("XRCamera3D") if get_parent() else null
					torso_yaw = cam.rotation.y if cam else 0.0
							
					print("[CharacterInstance] Cuerpo 1ra persona configurado. Head: %d, Neck: %d, ArmIK: [L:%d, R:%d]" % [head_bone_idx, neck_bone_idx, left_arm_idx, right_arm_idx])
				else:
					# 1. Configurar animador procedural para dar vida orgánica al oponente en VR
					# Utiliza la anatomía y rest pose canónica de Dragon Ball (Look-At interactivo, respiración, guardia DBZ, Ki jitter y flinch)
					# No se aplica animación Mixamo FBX ya que colapsa los huesos y rota la pelvis 180°
					procedural_animator = ProceduralCombatAnimatorClass.new()
					procedural_animator.setup(skeleton, self)

					# 2. Generar PhysicalBoneSimulator3D para la simulación física de impactos (Ragdoll)
					ragdoll_simulator = RuntimeRagdollGenerator.generate_ragdoll(skeleton, {"total_mass": 75.0})
					if ragdoll_simulator:
						ragdoll_simulator.physical_bones_stop_simulation()
			_disable_frustum_culling_in_children(body_mesh_instance)
			
	# Instanciar el modelo de las manos en runtime (solo si ES el jugador, para ver nuestras manos en primera persona)
	if is_player and character_data.hands_model_path != "":
		_setup_player_hands.call_deferred()

	# Configurar colisiones físicas y hitbox para ambos personajes
	_setup_character_physics()

	_notify_stats()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Control de simulación y recuperación Ragdoll
	if is_ragdoll_active:
		if ragdoll_recovery_timer > 0.0:
			ragdoll_recovery_timer -= delta
			if ragdoll_recovery_timer <= 0.0:
				stop_ragdoll()
		return

	# 0. Temporizador de Follow-Up Bullet-Time en el aire
	if is_in_followup_bullet_time:
		followup_bullet_time_timer -= delta
		if followup_bullet_time_timer <= 0.0:
			_end_followup_bullet_time(true)

	# 1. Movimiento de vuelo rápido hacia el oponente (Melee Dash con seguimiento 3D completo)
	if is_flying_to_opponent:
		var opponent = _get_opponent()
		if opponent and is_instance_valid(opponent):
			var cam = get_parent().get_node_or_null("XRCamera3D") if (is_player and get_parent()) else null
			var my_pos = cam.global_position if cam else (get_parent().global_position if is_player else global_position)
			var opponent_pos = opponent.global_position + Vector3(0.0, 0.9, 0.0) # Apuntar al torso del rival
			var diff = opponent_pos - my_pos
			var dist = diff.length()
			var target_dist = 0.65 # Distancia canónica exacta para golpear en VR

			if dist > target_dist:
				var dir = diff.normalized() if dist > 0.01 else Vector3.FORWARD
				var move_amount = min(flight_speed * delta, dist - target_dist)
				if is_player:
					var origin = get_parent()
					if origin:
						origin.global_position += dir * move_amount
						_clamp_to_arena(origin)
				else:
					global_position += dir * move_amount
					_clamp_to_arena(self)

				if dist - move_amount <= target_dist + 0.05:
					_stop_flight()
					if is_player:
						_start_melee_bullet_time(opponent)
					else:
						_execute_melee_impact(opponent)
			else:
				_stop_flight()
				if is_player:
					_start_melee_bullet_time(opponent)
				else:
					_execute_melee_impact(opponent)
		else:
			_stop_flight()

	# 2. Físicas de Velocidad y Knockback
	if wall_stick_timer > 0.0:
		wall_stick_timer -= delta
		velocity = Vector3.ZERO
	elif velocity.length_squared() > 0.001:
		var move_step = velocity * delta
		if is_player:
			var origin = get_parent()
			if origin:
				origin.global_position += move_step
				_clamp_to_arena(origin)
		else:
			global_position += move_step
			_clamp_to_arena(self)

		# Resistencia aerodinámica / fricción
		velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
		velocity.z = move_toward(velocity.z, 0.0, knockback_drag * delta)

		# Gravedad si está en el aire (adaptable dinámicamente al ring Y=0.5 o llanura exterior Y=0.0)
		var current_pos = (get_parent().global_position if is_player else global_position)
		var ground_h = get_ground_elevation(current_pos)
		if current_pos.y > ground_h + 0.005:
			velocity.y -= gravity * delta
		else:
			# Si caía a gran velocidad hacia el suelo (impacto sísmico / crash damage)
			if velocity.y < -7.0 and is_knocked_back:
				_on_ground_crash_impact(abs(velocity.y), current_pos, ground_h)
			velocity.y = 0.0
			is_knocked_back = false

	# 3. Colisión mutua de cuerpos anti-clipping (No atravesar al rival)
	_process_mutual_body_collision()

	# 4. Temporizador de rotura de guardia
	if is_guard_broken:
		guard_break_timer -= delta
		if guard_break_timer <= 0.0:
			is_guard_broken = false
			print("[Combat] %s recuperó la estabilidad de guardia." % (character_data.character_name if character_data else name))


func _process(delta: float) -> void:
	# Manejar temporizador de penalización por fallo de remate
	if is_penalized:
		penalty_timer -= delta
		if penalty_timer <= 0.0:
			is_penalized = false
			print("[CharacterInstance] %s: Penalización finalizada." % character_data.character_name)

	# Consumo de Ki por segundo si está transformado
	if current_transformation:
		var drain = current_transformation.ki_drain_per_sec * delta
		if current_ki > drain:
			current_ki -= drain
			_notify_stats()
		else:
			current_ki = 0.0
			revert_to_base()

	# Reversión canónica a estado base si el Ki se agota por cualquier causa (Punto 13)
	if current_transformation and current_ki <= 0.0:
		revert_to_base()

	# Alinear el aura con la cámara para el jugador en primera persona
	if is_player and aura_node and is_instance_valid(aura_node):
		var camera = get_parent().get_node_or_null("XRCamera3D")
		if camera:
			aura_node.position = Vector3(camera.position.x, 0.0, camera.position.z)

	# Alinear el cuerpo con la cámara y mover cuello según la dirección de mirada con deadzone
	if is_player and is_instance_valid(body_mesh_instance):
		var camera = get_parent().get_node_or_null("XRCamera3D")
		if camera:
			var local_cam_pos = camera.position
			
			# 1. Torso Deadzone: El torso no gira bruscamente; solo cuando la cabeza gira más de 35 grados
			var cam_yaw: float = camera.rotation.y
			var yaw_diff: float = wrapf(cam_yaw - torso_yaw, -PI, PI)
			var max_neck_angle: float = deg_to_rad(35.0)
			if abs(yaw_diff) > max_neck_angle:
				var target_yaw: float = cam_yaw - sign(yaw_diff) * max_neck_angle
				torso_yaw = lerp_angle(torso_yaw, target_yaw, 8.0 * delta)
				
			# Offset hacia atrás del torso respecto a los ojos (10cm) para alineación anatómica
			var torso_back: Vector3 = Vector3(sin(torso_yaw), 0.0, cos(torso_yaw)) * 0.10
			body_mesh_instance.position = Vector3(local_cam_pos.x + torso_back.x, 0.0, local_cam_pos.z + torso_back.z)
			# El modelo mira hacia +Z en local; para mirar hacia adelante (-Z del visor VR) rotamos torso_yaw + PI (180 grados)
			body_mesh_instance.rotation = Vector3(0.0, torso_yaw + PI, 0.0)
			
			if skeleton:
				# Ocultar únicamente el hueso "Head" a escala cero para evitar clipping con la cámara
				if head_bone_idx != -1 and skeleton.get_bone_pose_scale(head_bone_idx) != Vector3.ZERO:
					skeleton.set_bone_pose_scale(head_bone_idx, Vector3.ZERO)
				
				# Mover el cuello para acompañar la mirada del jugador (Pitch y Yaw natural)
				if neck_bone_idx != -1:
					var neck_yaw: float = wrapf(cam_yaw - torso_yaw, -PI, PI)
					var neck_pitch: float = camera.rotation.x
					var neck_rot = Quaternion.from_euler(Vector3(neck_pitch * 0.65, neck_yaw * 0.65, 0.0))
					skeleton.set_bone_pose_rotation(neck_bone_idx, neck_rot)

	# Cinemática Inversa (IK) de brazos y animación de dedos en primera persona
	if is_player:
		_process_player_arms_ik()

	# Rotar al oponente para mirar directamente al jugador cara a cara y actualizar animación procedural
	if not is_player:
		var opp = _get_opponent()
		if opp and is_instance_valid(opp):
			var opp_pos = opp.global_position
			var diff = opp_pos - global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				# Alinear frontalmente al oponente cara a cara hacia el jugador (el modelo tiene su frente canónico en +Z)
				rotation.y = atan2(diff.x, diff.z)

			if procedural_animator:
				# Altura de los ojos del jugador estimada a 1.45m o posición del visor
				var eye_target = opp_pos + Vector3(0.0, 1.45, 0.0)
				procedural_animator.update(delta, eye_target, is_charging_ki, is_blocking, is_flying_to_opponent)


	# Actualizar aura visual
	_update_aura_visuals(delta)

func take_hit(amount_np: float, hit_direction: Vector3 = Vector3.ZERO) -> void:
	# Si está en postura de Guardia y no tiene la guardia rota, absorber con Bloqueo
	if is_blocking and not is_guard_broken and amount_np >= 10.0:
		block_hit(amount_np, hit_direction)
		return

	# Recibir golpes disminuye nuestro NP, pero nunca por debajo de los umbrales irreversibles asegurados (25%, 50%, 75%, 100%)
	var active_max: float = character_data.max_np
	if current_transformation:
		active_max *= current_transformation.np_multiplier
	var floor_limit: float = max(active_max * secured_np_threshold_ratio, 100.0)
	current_np = max(current_np - amount_np, floor_limit)
	_notify_stats()

	# Solo aplicar retroceso físico a impactos reales (no a decaimiento pasivo por delta)
	if amount_np >= 10.0:
		var dir = hit_direction
		if dir.length_squared() < 0.01:
			var opp = _get_opponent()
			if opp and is_instance_valid(opp):
				var my_pos = get_parent().global_position if is_player else global_position
				dir = (my_pos - opp.global_position).normalized()
			else:
				dir = -global_transform.basis.z

		# Escala dinámica de retroceso según la potencia del impacto
		var force = clamp(amount_np * 0.015 + 3.0, 3.5, 22.0)
		apply_knockback(dir, force)

		# Flinch visual reactivo en animación procedural
		if procedural_animator:
			procedural_animator.trigger_hit_flinch(clampf(amount_np * 0.005, 0.2, 1.2), dir)


## Absorbe el impacto reduciendo 75% del daño a cambio de Ki (Mecánica de Bloqueo / Guardia)
func block_hit(amount_np: float, hit_direction: Vector3 = Vector3.ZERO) -> void:
	var ki_cost = clamp(amount_np * 0.04, 6.0, 28.0)
	var dir = hit_direction
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z

	if current_ki >= ki_cost:
		current_ki -= ki_cost
		_notify_stats()

		# Daño fuertemente mitigado (-75%)
		var mitigated_damage = amount_np * 0.25
		var active_max: float = character_data.max_np
		if current_transformation:
			active_max *= current_transformation.np_multiplier
		var floor_limit: float = max(active_max * secured_np_threshold_ratio, 100.0)
		current_np = max(current_np - mitigated_damage, floor_limit)
		_notify_stats()

		# Retroceso firme amortiguado
		apply_knockback(dir, 4.5)

		# Destello de escudo de choque de Ki
		_spawn_block_shield_vfx()

		if is_player:
			var origin = get_parent()
			if origin:
				for hand in ["LeftHand", "RightHand"]:
					var ctrl = origin.get_node_or_null(hand)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 160.0, 0.65, 0.15, 0.0)
			_log_combat_event("[GUARDIA] ¡Ataque bloqueado! Daño mitigado: %.0f NP (-75%%)" % mitigated_damage, "info")
	else:
		# ¡GUARD BREAK! El Ki se agotó bloqueando
		current_ki = 0.0
		_notify_stats()
		is_blocking = false
		is_guard_broken = true
		guard_break_timer = 1.2

		# Daño parcial penetra la guardia (55% de daño)
		var break_damage = amount_np * 0.55
		current_np = max(current_np - break_damage, 100.0)
		_notify_stats()

		apply_knockback(dir, 12.0)

		if is_player:
			var origin = get_parent()
			if origin:
				for hand in ["LeftHand", "RightHand"]:
					var ctrl = origin.get_node_or_null(hand)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 220.0, 1.0, 0.40, 0.0)
			_log_combat_event("[GUARD BREAK] ¡Guardia rota por agotamiento de Ki!", "error")


## Instancia un escudo visual de chispas y energía frente al pecho al bloquear
func _spawn_block_shield_vfx() -> void:
	var shield = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.90
	shield.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.85, 1.0, 0.75)
	shield.material_override = mat

	add_child(shield)
	shield.position = Vector3(0.0, 1.1, -0.28)

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(shield, "scale", Vector3.ONE * 1.6, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), 0.2)
	tween.chain().tween_callback(shield.queue_free)

func recharge_ki(amount: float) -> void:
	if is_penalized:
		# Penalización reduce a la mitad la velocidad de recarga
		amount *= 0.5
	current_ki = min(current_ki + amount, character_data.base_ki)
	_notify_stats()

func consume_ki(amount: float) -> bool:
	if is_penalized:
		# Penalizado no puede consumir Ki para ataques avanzados
		return false
	if current_ki >= amount:
		current_ki -= amount
		_notify_stats()
		return true
	return false

## Consume Ki para técnicas especiales; si el Ki es insuficiente (último aliento),
## permite ejecutar la técnica sacrificando Fuerza Vital / Battle Power (NP) directamente.
func consume_ki_or_life_force(ki_amount: float) -> Dictionary:
	if is_penalized:
		return { "success": false, "sacrificed_np": 0.0, "is_life_sacrifice": false }
		
	# Caso 1: Ki ordinario suficiente
	if current_ki >= ki_amount:
		current_ki -= ki_amount
		_notify_stats()
		return { "success": true, "sacrificed_np": 0.0, "is_life_sacrifice": false }
		
	# Caso 2: SOBRE-ESFUERZO DE ÚLTIMO ALIENTO (Quema de Fuerza Vital / NP)
	var deficit = ki_amount - current_ki
	current_ki = 0.0
	
	# El costo en NP es proporcional al déficit de Ki respecto al nivel de poder actual
	# Por ejemplo: un déficit de 40 Ki quema ~25% del Battle Power actual del guerrero
	var deficit_factor = clamp(deficit / 100.0, 0.10, 1.0)
	var np_cost = current_np * (deficit_factor * 0.55)
	
	# Mínimo de quema para que siempre tenga peso dramático
	var min_cost = 500.0 if not current_transformation else (500.0 * current_transformation.np_multiplier)
	np_cost = max(np_cost, min_cost)
	
	# Reducir NP voluntariamente (sacrificio vital de último aliento)
	current_np = max(0.0, current_np - np_cost)
	_notify_stats()
	
	# Si el NP cae a 0 por el sacrificio vital, el luchador colapsa (K.O. por Agotamiento Extremo)
	if current_np <= 0.0:
		print("[CharacterInstance] %s: ¡COLAPSO POR SACRIFICIO VITAL! Fuerza vital agotada por completo." % character_data.character_name)
		var opp = _get_opponent()
		var winner_name = opp.character_data.character_name if (opp and opp.character_data) else "Rival"
		emit_signal("game_finished", winner_name)
		
	return { "success": true, "sacrificed_np": np_cost, "is_life_sacrifice": true }

func increase_np(amount: float) -> void:
	if is_penalized:
		amount *= 0.25 # Penalización reduce drásticamente la ganancia de NP
	var active_max: float = character_data.max_np
	if current_transformation:
		active_max *= current_transformation.np_multiplier
	current_np = min(current_np + amount, active_max)
	_update_secured_threshold(active_max)
	_notify_stats()

func _update_secured_threshold(active_max: float) -> void:
	if active_max <= 0.0:
		return
	var ratio: float = current_np / active_max
	if ratio >= 1.0:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 1.0)
	elif ratio >= 0.75:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.75)
	elif ratio >= 0.50:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.50)
	elif ratio >= 0.25:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.25)

func check_zenkai_conditions(opponent_np: float) -> void:
	# Evitar recalcular si el Zenkai se activó por Comeback (ya que dura exactamente 1 ataque)
	if is_comeback_zenkai:
		return
		
	var active_max = character_data.max_np
	if current_transformation:
		active_max *= current_transformation.np_multiplier
		
	# Trigger 1: Brecha notable de NP a nuestro favor (ej. +40% de ventaja)
	var ratio_diff = (current_np - opponent_np) / active_max
	if ratio_diff >= 0.40:
		if not is_in_zenkai_state:
			is_in_zenkai_state = true
			emit_signal("zenkai_activated", "brecha")
			_notify_stats()
	else:
		if is_in_zenkai_state:
			is_in_zenkai_state = false
			_notify_stats()

func trigger_comeback_zenkai() -> void:
	if not is_in_zenkai_state:
		is_in_zenkai_state = true
		is_comeback_zenkai = true
		emit_signal("zenkai_activated", "comeback")
		_notify_stats()
		print("[CharacterInstance] %s: ¡ZENKAI COMEBACK ACTIVADO! Tienes un ataque para liquidar o serás penalizado." % character_data.character_name)

func notify_attack_launched(p_power: Resource) -> void:
	# REQUISITO CANÓNICO: Si se lanza un Super Ataque de Ki durante el Follow-Up Bullet-Time, corta el tiempo
	if is_in_followup_bullet_time:
		var p_name = p_power.power_name.to_lower() if (p_power and "power_name" in p_power) else ""
		if not ("ki blast" in p_name):
			_end_followup_bullet_time(false)

	# Si lanzamos un ataque siendo Comeback Zenkai, consumimos el intento
	if is_comeback_zenkai:
		# Dejamos de estar en estado Zenkai Comeback inmediatamente (se consume el tiro)
		is_in_zenkai_state = false
		is_comeback_zenkai = false
		_notify_stats()
		
		# Guardamos una referencia para validar si impactó o falló
		# En este caso, si falla (es esquivado/desviado), el combate penalizará al personaje.
		# La llamada a `notify_attack_failed()` se hará desde el proyectil o colisión.

func notify_attack_failed() -> void:
	# Penalización severa por fallar el remate en Comeback:
	# 1. NP cae a la mitad (o un valor mínimo).
	# 2. Ki cae a 0.
	# 3. Estado de penalización por 8 segundos.
	current_np = max(current_np * 0.4, 100.0)
	current_ki = 0.0
	is_penalized = true
	penalty_timer = 8.0
	_notify_stats()
	print("[CharacterInstance] %s: ¡FALLO DE REMATE! Penalizado: Ki a 0, NP reducido a la mitad y recarga mermada." % character_data.character_name)

func transform_to(index: int) -> void:
	if index >= 0 and index < character_data.transformations.size():
		var trans = character_data.transformations[index]
		current_transformation = trans
		
		# Desbloquear técnicas de esta fase
		for power in character_data.powers:
			if power.unlock_requirement_transformation == trans.form_name:
				if not unlocked_powers.has(power.power_name):
					unlocked_powers.append(power.power_name)
					emit_signal("power_unlocked", power.power_name)
					
		emit_signal("transformed", trans)
		_notify_stats()
		_update_aura_visuals()

func revert_to_base() -> void:
	if current_transformation == null:
		return
	var char_name = character_data.character_name if character_data else ""
	# Excepción canónica: personajes como Freezer no se destransforman por agotamiento de Ki
	if char_name == "Freezer" or char_name == "Frieza":
		return
	print("[CharacterInstance] %s: ¡Ki agotado! Destransformación forzada al estado base." % char_name)
	current_transformation = null
	emit_signal("transformed", null)
	_notify_stats()
	_update_aura_visuals()

func is_power_usable(power: Resource) -> bool:
	if is_penalized:
		return false
	# 1. ¿Está desbloqueado o es técnica base/finisher en Zenkai?
	var is_unlocked = unlocked_powers.has(power.power_name) or power.unlock_requirement_transformation == ""
	if is_in_zenkai_state and power.is_finisher:
		is_unlocked = true
	if not is_unlocked:
		return false
	# 2. ¿Prohibido en esta forma?
	if current_transformation and power.forbidden_transformations.has(current_transformation.form_name):
		return false
	# 3. Super Poderes y Finishers ejecutables con Ki o mediante Último Aliento (Fuerza Vital)
	return true

func execute_finisher_hit(power: Resource) -> void:
	if power.is_finisher:
		# ¡Partida finalizada! Activar ragdoll definitivo de K.O.
		if not is_player:
			start_ragdoll(Vector3.BACK * 35.0 + Vector3.DOWN * 15.0)
			ragdoll_recovery_timer = -1.0 # Permanece derribado por K.O.
		emit_signal("game_finished", character_data.character_name)

func _update_aura_visuals(delta: float = 0.0) -> void:
	# El Aura de Ki SIEMPRE está activa, reflejando el BP y el Ki restante (Punto 12)
	if aura_node == null or not is_instance_valid(aura_node):
		# Crear contenedor del Aura
		aura_node = Node3D.new()
		aura_node.name = "CharacterKiAura"
		add_child(aura_node)
		aura_node.position = Vector3(0, 0, 0)
		
		# 1. Crear cilindro procedural
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "AuraMesh"
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.85
		cylinder.bottom_radius = 0.95
		cylinder.height = 2.4
		cylinder.radial_segments = 24
		cylinder.rings = 4
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		mesh_inst.mesh = cylinder
		
		var mat = ShaderMaterial.new()
		mat.shader = KiCoronaShader
		mat.set_shader_parameter("base_color", Color(0.85, 0.95, 1.0, 0.35))
		mat.set_shader_parameter("vertex_displacement", 0.04)
		mat.set_shader_parameter("speed", 3.0)
		mat.set_shader_parameter("scale", 5.0)
		mesh_inst.material_override = mat
		aura_node.add_child(mesh_inst)
		mesh_inst.position = Vector3(0, 1.2, 0)
		aura_mesh_ref = mesh_inst
		
		# 2. Luz dinámica omnidireccional
		var light = OmniLight3D.new()
		light.name = "AuraLight"
		light.light_color = Color(0.8, 0.9, 1.0)
		light.light_energy = 2.5
		light.omni_range = 3.5
		light.position = Vector3(0, 1.2, 0)
		aura_node.add_child(light)
		aura_light_ref = light
		
	# Rotar el aura continuamente
	aura_node.rotate_y(delta * 0.5)
	
	# Calcular ratios normalizados de BP (NP) y Ki restante
	var active_max: float = character_data.max_np if character_data else 20000.0
	if current_transformation:
		active_max *= current_transformation.np_multiplier
	var base_np: float = character_data.base_np if character_data else 9000.0
	var base_ki: float = character_data.base_ki if character_data else 100.0
	
	var bp_ratio: float = clampf((current_np - base_np) / maxf(1.0, (active_max - base_np)), 0.0, 1.0)
	var ki_ratio: float = clampf(current_ki / maxf(1.0, base_ki), 0.0, 1.0)
	
	# Factor combinado de potencia activa
	var power_factor: float = bp_ratio * 0.55 + ki_ratio * 0.45
	if current_transformation:
		power_factor = maxf(power_factor, 0.65)
	
	# Escala física del aura: proporcional al BP y amplificada por recarga o vuelo
	var target_scale: float = lerp(0.72, 1.85, bp_ratio)
	if is_charging_ki:
		target_scale *= 1.40
	elif is_flying_to_opponent:
		target_scale *= 1.22

	# Efectos visuales de Ki Lleno vs Ki Agotado (Punto 7):
	if ki_ratio >= 0.88:
		# KI LLENO / CASI LLENO: Expansión de aura con llamaradas vivas
		target_scale *= 1.25
	elif ki_ratio <= 0.20:
		# KI BAJO / AGOTÁNDOSE: Aura reducida y desfalleciente
		var low_factor = clampf(ki_ratio / 0.20, 0.0, 1.0)
		target_scale *= lerp(0.50, 0.85, low_factor)

	aura_node.scale = Vector3.ONE * target_scale
	
	# Determinar el color base según estado y transformación
	var target_color = Color(0.75, 0.92, 1.0, 0.35) # Blanco-celeste de Ki base
	if current_transformation:
		target_color = current_transformation.aura_color
	elif character_data and character_data.character_name == "Vegeta":
		target_color = Color(0.85, 0.35, 1.0, 0.40) # Púrpura característico de Vegeta
	elif is_in_zenkai_state:
		target_color = Color(1.0, 0.25, 0.1, 0.65) # Carmesí ardiente de Zenkai / Furia
		
	# Modulación de color y alfa según Ki lleno o agotado (Punto 7)
	var active_alpha = lerp(0.08, 0.85, ki_ratio)
	if ki_ratio >= 0.88:
		active_alpha = maxf(active_alpha, 0.75)
		target_color = target_color.lightened(0.20)
	elif ki_ratio <= 0.20:
		var low_t = clampf(ki_ratio / 0.20, 0.0, 1.0)
		active_alpha = lerp(0.04, 0.18, low_t)
		target_color = target_color.lerp(Color(0.45, 0.45, 0.50, 0.15), 0.60)

	if is_charging_ki:
		active_alpha = 1.0
	elif is_player and not is_charging_ki:
		active_alpha = minf(active_alpha, 0.40)
	target_color.a = active_alpha
	
	if is_instance_valid(aura_mesh_ref) and aura_mesh_ref.material_override is ShaderMaterial:
		var smat = aura_mesh_ref.material_override as ShaderMaterial
		smat.set_shader_parameter("base_color", target_color)
		var aura_speed = lerp(1.5, 6.0, ki_ratio)
		if ki_ratio >= 0.88:
			aura_speed = 7.5
		elif ki_ratio <= 0.20:
			aura_speed = 1.2
		if is_charging_ki:
			aura_speed = 8.5
		smat.set_shader_parameter("speed", aura_speed)

		var displacement = lerp(0.02, 0.08, bp_ratio)
		if ki_ratio >= 0.88:
			displacement = 0.09
		elif ki_ratio <= 0.20:
			displacement = 0.015
		if is_charging_ki:
			displacement = 0.12
		smat.set_shader_parameter("vertex_displacement", displacement)
		
	if is_instance_valid(aura_light_ref):
		aura_light_ref.light_color = target_color
		var light_energy = lerp(0.8, 8.0, power_factor)
		if ki_ratio >= 0.88:
			light_energy += 3.0
		elif ki_ratio <= 0.20:
			light_energy = lerp(0.3, 1.0, ki_ratio / 0.20)
		if is_charging_ki:
			light_energy += 4.5
		aura_light_ref.light_energy = light_energy
		aura_light_ref.omni_range = lerp(2.2, 6.5, bp_ratio)

func _notify_stats() -> void:
	emit_signal("stats_changed", current_ki, current_np, is_in_zenkai_state)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var skel = _find_skeleton(child)
		if skel:
			return skel
	return null

func start_flight_to_opponent() -> void:
	if is_in_followup_bullet_time:
		is_in_followup_bullet_time = false

	if is_player and not is_target_locked:
		_log_combat_event("⚠️ ¡Debes fijar al rival con la mirada antes de embestir!", "warning")
		var my_origin = get_parent()
		if my_origin:
			for hand in ["LeftHand", "RightHand"]:
				var ctrl = my_origin.get_node_or_null(hand)
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 120.0, 0.65, 0.22, 0.0)
		return
	is_flying_to_opponent = true
	_update_aura_visuals()
	print("[CharacterInstance] %s: Iniciando vuelo rápido hacia el oponente." % character_data.character_name)

func _stop_flight() -> void:
	is_flying_to_opponent = false
	_update_aura_visuals()
	print("[CharacterInstance] %s: Vuelo finalizado a distancia de melee." % character_data.character_name)
	
	# Si somos el jugador, loguear la llegada en el GSS
	if is_player:
		var gss = get_tree().root.find_child("GesturePhaseTree", true, false)
		if gss:
			gss.emit_signal("gesture_logged", "[Melee] ¡Llegada al oponente a distancia de Melee!", "success")
			gss.emit_signal("phase_changed", "DISTANCIA DE MELEE")

func _get_opponent() -> Node3D:
	if is_player:
		return get_node_or_null("/root/cell_games_arena/EnemyCharacterInstance")
	else:
		return get_node_or_null("/root/cell_games_arena/Player_XROrigin3D/PlayerCharacterInstance")

func _setup_player_hands() -> void:
	var origin = get_parent()
	var left_controller = origin.get_node_or_null("LeftHand")
	var right_controller = origin.get_node_or_null("RightHand")
	
	if not left_controller or not right_controller:
		print("[CharacterInstance] Error: No se encontraron los controladores LeftHand o RightHand para instanciar las manos.")
		return
		
	# Limpiar cualquier visualizador de manos previo si existe en los controladores
	for child in left_controller.get_children():
		if child.name == "PlayerVisualHandLeft":
			child.queue_free()
	for child in right_controller.get_children():
		if child.name == "PlayerVisualHandRight":
			child.queue_free()
			
	var hands_scene = load(character_data.hands_model_path)
	if not hands_scene:
		print("[CharacterInstance] Error: No se pudo cargar el modelo de manos desde: ", character_data.hands_model_path)
		return
		
	var _is_goku_model = character_data.hands_model_path.contains("goku")
	var base_scale = 0.01
	
	# --- 1. CONFIGURAR MANO IZQUIERDA ---
	hand_left_instance = hands_scene.instantiate()
	hand_left_instance.name = "PlayerVisualHandLeft"
	left_controller.add_child(hand_left_instance)
	
	var skel_left = _find_skeleton(hand_left_instance)
	if skel_left:
		# Escalar huesos del esqueleto a metros (factor 0.01 de centímetro a metro canónico OpenXR)
		for i in range(skel_left.get_bone_count()):
			var rest = skel_left.get_bone_rest(i)
			rest.origin *= base_scale
			skel_left.set_bone_rest(i, rest)
		_scale_skins_in_children(hand_left_instance, base_scale)
			
		# 2. Obtener la transformación acumulada original del hueso LeftWrist en el GLB (con huesos ya a escala de metros)
		var wrist_transform = _get_wrist_transform_in_glb(skel_left, "LeftWrist", hand_left_instance)
		
		# Cancela la escala de importación del GLB aplicando la inversa de la muñeca escalada.
		# Esto aplica un factor de escala 100.0 al root (cancelando el 0.01 de Vegeta_DBFZ),
		# y traslada el root por -wrist_rest_escalada, alineando la muñeca virtual exactamente en (0,0,0) sobre el controlador.
		var wrist_inverse = wrist_transform.inverse()
		hand_left_instance.transform = wrist_inverse
		
		# Ocultar la mano derecha colapsando su hueso raíz (RightWrist)
		var right_wrist_idx = skel_left.find_bone("RightWrist")
		if right_wrist_idx != -1:
			skel_left.set_bone_pose_scale(right_wrist_idx, Vector3.ZERO)
			
	_disable_frustum_culling_in_children(hand_left_instance)
	hand_left_instance.visible = false # Ocultar manos flotantes duplicadas: el cuerpo renderiza brazos completos
	left_controller.visible = true

	# Solo instanciar XRHandModifier3D si las manos estuvieran visibles (evita 50+ advertencias de huesos faltantes en C++)
	if hand_left_instance.visible:
		var modifier = XRHandModifier3D.new()
		modifier.name = "XRHandModifierLeft"
		modifier.hand_tracker = "/user/hand_tracker/left"
		modifier.bone_update = XRHandModifier3D.BONE_UPDATE_ROTATION_ONLY
		skel_left.add_child(modifier)
		
	# --- 2. CONFIGURAR MANO DERECHA ---
	hand_right_instance = hands_scene.instantiate()
	hand_right_instance.name = "PlayerVisualHandRight"
	right_controller.add_child(hand_right_instance)
	
	var skel_right = _find_skeleton(hand_right_instance)
	if skel_right:
		for i in range(skel_right.get_bone_count()):
			var rest = skel_right.get_bone_rest(i)
			rest.origin *= base_scale
			skel_right.set_bone_rest(i, rest)
		_scale_skins_in_children(hand_right_instance, base_scale)
			
		# 2. Obtener la transformación acumulada original del hueso RightWrist en el GLB (con huesos ya a escala de metros)
		var wrist_transform = _get_wrist_transform_in_glb(skel_right, "RightWrist", hand_right_instance)
		
		# Cancela la escala de importación aplicando la inversa.
		var wrist_inverse = wrist_transform.inverse()
		hand_right_instance.transform = wrist_inverse
		
		# Ocultar la mano izquierda colapsando su hueso raíz (LeftWrist)
		var left_wrist_idx = skel_right.find_bone("LeftWrist")
		if left_wrist_idx != -1:
			skel_right.set_bone_pose_scale(left_wrist_idx, Vector3.ZERO)
			
	_disable_frustum_culling_in_children(hand_right_instance)
	hand_right_instance.visible = false # Ocultar manos flotantes duplicadas: el cuerpo renderiza brazos completos
	right_controller.visible = true

	# Solo instanciar XRHandModifier3D si las manos estuvieran visibles (evita 50+ advertencias de huesos faltantes en C++)
	if hand_right_instance.visible:
		var modifier = XRHandModifier3D.new()
		modifier.name = "XRHandModifierRight"
		modifier.hand_tracker = "/user/hand_tracker/right"
		modifier.bone_update = XRHandModifier3D.BONE_UPDATE_ROTATION_ONLY
		skel_right.add_child(modifier)
		
	print("[CharacterInstance] ¡Manos VR configuradas y compensadas con éxito para el jugador (%s) bajo controladores!" % character_data.character_name)

## Desactiva el frustum culling estricto para evitar que las manos desaparezcan en la vista VR
func _disable_frustum_culling_in_children(node: Node) -> void:
	if not node:
		return
	if node is GeometryInstance3D:
		node.extra_cull_margin = 250.0
		node.ignore_occlusion_culling = true
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if node is MeshInstance3D:
		node.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	for child in node.get_children():
		_disable_frustum_culling_in_children(child)

## Resuelve la cinemática inversa (IK) de 2 huesos para que los brazos y manos del cuerpo sigan los mandos VR
func _process_player_arms_ik() -> void:
	if not skeleton:
		return
	var origin = get_parent()
	if not origin:
		return

	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand")
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand")

	if left_ctrl and left_ctrl.get_is_active():
		var l_basis = left_ctrl.global_transform.basis
		var l_wrist_pos = left_ctrl.global_position + l_basis * Vector3(0.0, -0.015, 0.065)
		_solve_arm_ik(
			left_arm_idx,
			left_forearm_idx,
			left_hand_idx,
			l_wrist_pos,
			l_basis,
			true
		)
		var l_trig = left_ctrl.get_float("trigger")
		var l_grip = left_ctrl.get_float("grip")
		_apply_finger_curls_to_skeleton(skeleton, "Left", l_trig, l_grip)

	if right_ctrl and right_ctrl.get_is_active():
		var r_basis = right_ctrl.global_transform.basis
		var r_wrist_pos = right_ctrl.global_position + r_basis * Vector3(0.0, -0.015, 0.065)
		_solve_arm_ik(
			right_arm_idx,
			right_forearm_idx,
			right_hand_idx,
			r_wrist_pos,
			r_basis,
			false
		)
		var r_trig = right_ctrl.get_float("trigger")
		var r_grip = right_ctrl.get_float("grip")
		_apply_finger_curls_to_skeleton(skeleton, "Right", r_trig, r_grip)


## Algoritmo analítico de 2 huesos (Hombro -> Codo -> Mano) con orientación de muñeca y pole vector
func _solve_arm_ik(
	shoulder_idx: int,
	forearm_idx: int,
	hand_idx: int,
	target_global_pos: Vector3,
	target_global_basis: Basis,
	is_left: bool
) -> void:
	if shoulder_idx == -1 or forearm_idx == -1 or hand_idx == -1 or not skeleton:
		return

	# Transformar objetivo desde coordenadas mundiales al espacio local del Skeleton3D
	var skel_inv = skeleton.global_transform.affine_inverse()
	var target_skel = skel_inv * target_global_pos

	var s_rest = skeleton.get_bone_global_rest(shoulder_idx).origin
	var e_rest = skeleton.get_bone_global_rest(forearm_idx).origin
	var w_rest = skeleton.get_bone_global_rest(hand_idx).origin

	var L1 = (e_rest - s_rest).length()
	var L2 = (w_rest - e_rest).length()

	var v = target_skel - s_rest
	var d = clampf(v.length(), 0.08, (L1 + L2) * 0.98)
	var v_dir = v.normalized()

	# Ley de cosenos para los ángulos del triángulo del brazo
	var cos_alpha = clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var alpha = acos(cos_alpha)

	# Pole vector para flexión anatómica: codos hacia afuera (+X izq, -X der), abajo (-Y) y atrás (-Z en local)
	var pole_dir = Vector3(0.6, -0.6, -0.5).normalized() if is_left else Vector3(-0.6, -0.6, -0.5).normalized()
	var plane_norm = v_dir.cross(pole_dir).normalized()
	if plane_norm.length_squared() < 0.001:
		plane_norm = Vector3.UP

	var bend_dir = plane_norm.cross(v_dir).normalized()
	var elbow_target = s_rest + v_dir * (L1 * cos(alpha)) + bend_dir * (L1 * sin(alpha))

	# 1. Rotación del hombro / brazo superior
	var rest_upper_dir = (e_rest - s_rest).normalized()
	var des_upper_dir = (elbow_target - s_rest).normalized()
	var q_shoulder = Quaternion(rest_upper_dir, des_upper_dir)

	# 2. Rotación del antebrazo / codo
	var rest_lower_dir = (w_rest - e_rest).normalized()
	var des_lower_dir = (target_skel - elbow_target).normalized()
	var q_forearm_world = Quaternion(rest_lower_dir, des_lower_dir)
	var q_forearm_local = q_shoulder.inverse() * q_forearm_world

	skeleton.set_bone_pose_rotation(shoulder_idx, q_shoulder)
	skeleton.set_bone_pose_rotation(forearm_idx, q_forearm_local)

	# 3. Orientación matemática canónica de la muñeca según la cinemática del modelo y mandos OpenXR
	var target_basis_skel = skel_inv.basis * target_global_basis

	# Matriz ortonormal canónica que alinea el espacio de reposo de la mano en A-pose con el mando OpenXR:
	# En el mando: -Z es hacia adelante (dedos), +Y es hacia arriba (pulgar), +X/-X es hacia la palma/dorso.
	# En el modelo: el brazo y mano caen a -37.23° (A-pose) con dedos en +X/-X, pulgar en +Z, palma en -Y.
	var align_basis: Basis
	if is_left:
		align_basis = Basis(
			Vector3(-0.605083, 0.0, -0.796162),
			Vector3(-0.796162, 0.0, 0.605083),
			Vector3(0.0, 1.0, 0.0)
		)
	else:
		align_basis = Basis(
			Vector3(-0.605083, 0.0, 0.796162),
			Vector3(0.796162, 0.0, 0.605083),
			Vector3(0.0, 1.0, 0.0)
		)

	var desired_hand_basis = target_basis_skel * align_basis

	# Usamos la orientación mundial exacta del antebrazo calculada analíticamente en este frame
	# para evitar la caché desactualizada de 1 frame de get_bone_global_pose() en Godot 4
	var forearm_world_basis = Basis(q_forearm_world)
	var rest_hand_basis = skeleton.get_bone_rest(hand_idx).basis
	var local_hand_basis = rest_hand_basis.inverse() * forearm_world_basis.inverse() * desired_hand_basis
	skeleton.set_bone_pose_rotation(hand_idx, local_hand_basis.get_rotation_quaternion())


## Aplica flexión reactiva de dedos en el esqueleto del cuerpo con distribución anatómica natural
func _apply_finger_curls_to_skeleton(skel: Skeleton3D, prefix: String, trigger: float, grip: float) -> void:
	if not skel:
		return
	var is_left = (prefix == "Left")
	var curl_axis = Vector3(0.0, 0.0, -1.0) if is_left else Vector3(0.0, 0.0, 1.0)

	# Zona muerta de descanso natural en empuñadura de mandos Quest (calibrado empíricamente a 0.12)
	var eff_grip = clampf((grip - 0.12) / 0.88, 0.0, 1.0)
	var eff_trig = clampf((trigger - 0.08) / 0.92, 0.0, 1.0)

	# Distribución jerárquica anatómica para evitar sobre-flexión de dedos en espiral
	var rot_j1 = Quaternion(curl_axis, eff_grip * 0.70)
	var rot_j2 = Quaternion(curl_axis, eff_grip * 0.85)
	var rot_j3 = Quaternion(curl_axis, eff_grip * 0.65)

	# Índice controlado por Trigger
	var idx_rot_j1 = Quaternion(curl_axis, eff_trig * 0.70)
	var idx_rot_j2 = Quaternion(curl_axis, eff_trig * 0.85)
	var idx_rot_j3 = Quaternion(curl_axis, eff_trig * 0.65)

	# Pulgar: rota desde +Z envolviendo hacia -Z a través de la palma y sobre los dedos
	var thumb_axis = Vector3(0.58, 0.78, -0.22).normalized() if is_left else Vector3(0.58, -0.78, 0.22).normalized()
	var thumb_val = (eff_trig * 0.4 + eff_grip * 0.6)
	var thumb_rot_1 = Quaternion(thumb_axis, thumb_val * 0.45)
	var thumb_rot_2 = Quaternion(thumb_axis, thumb_val * 0.60)
	var thumb_rot_3 = Quaternion(thumb_axis, thumb_val * 0.50)

	# Aplicar a cada nivel jerárquico (Middle, Ring, Pinky)
	var bones_level_1 = [prefix + "Middle1", prefix + "Ring1", prefix + "Pinky1", prefix + "MiddleProximal", prefix + "RingProximal", prefix + "PinkyProximal"]
	var bones_level_2 = [prefix + "Middle2", prefix + "Ring2", prefix + "Pinky2", prefix + "MiddleIntermediate", prefix + "RingIntermediate", prefix + "PinkyIntermediate"]
	var bones_level_3 = [prefix + "Middle3", prefix + "Ring3", prefix + "Pinky3", prefix + "MiddleDistal", prefix + "RingDistal", prefix + "PinkyDistal"]

	for b_name in bones_level_1:
		var idx = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j1)
	for b_name in bones_level_2:
		var idx = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j2)
	for b_name in bones_level_3:
		var idx = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j3)

	# Índice
	var idx_b1 = skel.find_bone(prefix + "Index1")
	if idx_b1 == -1: idx_b1 = skel.find_bone(prefix + "IndexProximal")
	if idx_b1 != -1: skel.set_bone_pose_rotation(idx_b1, idx_rot_j1)

	var idx_b2 = skel.find_bone(prefix + "Index2")
	if idx_b2 == -1: idx_b2 = skel.find_bone(prefix + "IndexIntermediate")
	if idx_b2 != -1: skel.set_bone_pose_rotation(idx_b2, idx_rot_j2)

	var idx_b3 = skel.find_bone(prefix + "Index3")
	if idx_b3 == -1: idx_b3 = skel.find_bone(prefix + "IndexDistal")
	if idx_b3 != -1: skel.set_bone_pose_rotation(idx_b3, idx_rot_j3)

	# Pulgar
	var th_b1 = skel.find_bone(prefix + "Thumb1")
	if th_b1 == -1: th_b1 = skel.find_bone(prefix + "ThumbProximal")
	if th_b1 != -1: skel.set_bone_pose_rotation(th_b1, thumb_rot_1)

	var th_b2 = skel.find_bone(prefix + "Thumb2")
	if th_b2 == -1: th_b2 = skel.find_bone(prefix + "ThumbIntermediate")
	if th_b2 != -1: skel.set_bone_pose_rotation(th_b2, thumb_rot_2)

	var th_b3 = skel.find_bone(prefix + "Thumb3")
	if th_b3 == -1: th_b3 = skel.find_bone(prefix + "ThumbDistal")
	if th_b3 != -1: skel.set_bone_pose_rotation(th_b3, thumb_rot_3)

func _get_wrist_transform_in_glb(skel: Skeleton3D, wrist_bone_name: String, hand_instance: Node3D) -> Transform3D:
	var bone_idx = skel.find_bone(wrist_bone_name)
	if bone_idx == -1:
		return Transform3D.IDENTITY
		
	# 1. Acumular transformaciones locales de los huesos en el esqueleto
	var t = Transform3D.IDENTITY
	var curr_bone = bone_idx
	while curr_bone != -1:
		t = skel.get_bone_rest(curr_bone) * t
		curr_bone = skel.get_bone_parent(curr_bone)
		
	# 2. Acumular transformaciones locales de los nodos de la escena desde el Skeleton3D hasta el root de la mano (hand_instance)
	var node = skel
	var path_nodes = []
	while node != null and node != hand_instance:
		path_nodes.append(node)
		node = node.get_parent()
	if node == hand_instance:
		path_nodes.append(hand_instance)
		
	path_nodes.reverse() # De padres a hijos
	
	var node_transform = Transform3D.IDENTITY
	for p_node in path_nodes:
		node_transform = node_transform * p_node.transform
		
	return node_transform * t


func _reset_node_scales(node: Node) -> void:
	if node is Node3D:
		node.scale = Vector3.ONE
	for child in node.get_children():
		_reset_node_scales(child)

func _scale_skins_in_children(node: Node, scale_factor: float, bone_filter: Array = []) -> void:
	if node is MeshInstance3D and node.skin:
		node.skin = node.skin.duplicate()
		for i in range(node.skin.get_bind_count()):
			var bind_name = node.skin.get_bind_name(i)
			if bone_filter.is_empty() or bone_filter.has(bind_name):
				var pose = node.skin.get_bind_pose(i)
				pose.basis = pose.basis.scaled(Vector3.ONE * scale_factor)
				pose.origin *= scale_factor
				node.skin.set_bind_pose(i, pose)
	for child in node.get_children():
		_scale_skins_in_children(child, scale_factor, bone_filter)


# --- Físicas 3D de Personajes Z (Colisiones, Knockback y Melee) ---

func _setup_character_physics() -> void:
	for child_name in ["CharacterHitbox", "CharacterPhysicalBody", "EnemyFistCollider"]:
		var old = get_node_or_null(child_name)
		if old:
			old.queue_free()

	var char_height: float = 1.75 if (character_data and character_data.character_name == "Goku") else 1.64
	var char_radius: float = 0.38

	# 1. Cuerpo Físico para colisiones directas y raycasts de proyectiles
	var physical_body = StaticBody3D.new()
	physical_body.name = "CharacterPhysicalBody"
	physical_body.collision_layer = 2 # Capa 2: Personajes Z
	physical_body.collision_mask = 1 | 2 | 4 # Capa 1: Escenario, 2: Personajes, 4: Proyectiles

	var body_col = CollisionShape3D.new()
	body_col.name = "PhysicalCapsule"
	var body_capsule = CapsuleShape3D.new()
	body_capsule.radius = char_radius
	body_capsule.height = char_height
	body_col.shape = body_capsule
	body_col.position = Vector3(0.0, char_height / 2.0, 0.0)
	physical_body.add_child(body_col)
	add_child(physical_body)

	# 2. Area3D para detección de proximidad y golpes Melee
	var hitbox = Area3D.new()
	hitbox.name = "CharacterHitbox"
	hitbox.collision_layer = 2
	hitbox.collision_mask = 1 | 2 | 4

	var hit_col = CollisionShape3D.new()
	hit_col.name = "HitboxCapsule"
	var hit_capsule = CapsuleShape3D.new()
	hit_capsule.radius = char_radius + 0.05
	hit_capsule.height = char_height
	hit_col.shape = hit_capsule
	hit_col.position = Vector3(0.0, char_height / 2.0, 0.0)
	hitbox.add_child(hit_col)
	add_child(hitbox)

	print("[Physics] Cuerpo físico y Hitbox de cápsula (%.2fm alt, %.2fm rad) configurados para %s." % [char_height, char_radius, character_data.character_name if character_data else name])


func apply_knockback(dir: Vector3, force: float) -> void:
	var horiz_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	if horiz_dir.length_squared() < 0.01:
		horiz_dir = -global_transform.basis.z
	# Masa corporal realista sin saltos artificiales en impactos horizontales
	var vert_comp = clampf(dir.y, -1.0, 1.0) if abs(dir.y) > 0.35 else 0.0
	var controlled_force = clampf(force, 1.5, 7.5)
	var impulse = (horiz_dir + Vector3.UP * vert_comp).normalized() * controlled_force
	velocity = impulse
	is_knocked_back = true
	print("[Physics] %s empujado con fuerza controlada %.1f m/s en dirección %s." % [character_data.character_name if character_data else name, controlled_force, horiz_dir])


## Determina la cota del suelo según si el personaje está sobre el ring de piedra o en la llanura exterior
func get_ground_elevation(world_pos: Vector3) -> float:
	var on_stone_ring = abs(world_pos.x) <= RING_HALF_SIZE and abs(world_pos.z) <= RING_HALF_SIZE
	return 0.5 if on_stone_ring else 0.0


func _clamp_to_arena(node: Node3D) -> void:
	var pos = node.global_position
	var limit = arena_half_limit
	var hit_mountain = false
	var horiz_speed = Vector2(velocity.x, velocity.z).length()

	# 1. Colisión física tridimensional continua contra mesetas, riscos y cañones interiores (Puntos 8 y 9)
	if is_inside_tree() and get_world_3d() and velocity.length_squared() > 0.01:
		var space = get_world_3d().direct_space_state
		if space:
			var char_center = pos + Vector3(0.0, 0.9, 0.0)
			var query_dir = velocity.normalized()
			var query_dist = maxf(horiz_speed * 0.05, 0.65)
			var ray_params = PhysicsRayQueryParameters3D.create(char_center, char_center + query_dir * query_dist)
			ray_params.collision_mask = 1 # Capa 1: Terreno, montañas y mesetas
			var col = space.intersect_ray(ray_params)
			if col and col.collider:
				var collider = col.collider
				if collider.is_in_group("mountains") or collider.has_meta("is_mountain") or "Mountain" in collider.name or "Canyon" in collider.name:
					hit_mountain = true
					pos = col.position + col.normal * 0.50
					_on_boundary_crash_impact(horiz_speed)
					velocity.x = 0.0
					velocity.z = 0.0
					if horiz_speed > 3.2:
						wall_stick_timer = 1.25
						is_knocked_back = false
						_spawn_ground_crash_vfx(col.position, false)
						_log_combat_event("💥 ¡Estrellamiento contra el risco! Incrustado en la roca (Wall-Stick).", "warning")
						print("[Physics] %s se incrustó en el risco de la montaña por 1.25s (Wall-Stick anime)." % (character_data.character_name if character_data else name))

	# 2. Bounding box perimetral exterior
	if pos.x > limit:
		pos.x = limit
		hit_mountain = true
	elif pos.x < -limit:
		pos.x = -limit
		hit_mountain = true

	if pos.z > limit:
		pos.z = limit
		hit_mountain = true
	elif pos.z < -limit:
		pos.z = -limit
		hit_mountain = true

	if hit_mountain and wall_stick_timer <= 0.0:
		_on_boundary_crash_impact(horiz_speed)
		# Cero rebote de goma: detener velocidad de inmediato
		velocity.x = 0.0
		velocity.z = 0.0
		# Si el impacto fue contundente (>3.2 m/s), el personaje queda incrustado en la roca (wall-stick)
		if horiz_speed > 3.2:
			wall_stick_timer = 1.25
			is_knocked_back = false
			_spawn_ground_crash_vfx(pos + Vector3(0.0, 1.2, 0.0), false)
			print("[Physics] %s se incrustó en el límite exterior por 1.25s (Wall-Stick anime)." % (character_data.character_name if character_data else name))

	var ground_h = get_ground_elevation(pos)
	if pos.y < ground_h:
		pos.y = ground_h
		velocity.y = 0.0

	# Comprobar colisión contra los 4 pilares angulares del Ring de Cell Games (X, Z = ±16.65)
	_check_pillar_collisions(pos)

	node.global_position = pos


func _get_gesture_tree() -> Node:
	if not is_inside_tree() or not get_tree() or not get_tree().root:
		return null
	return get_tree().root.find_child("GesturePhaseTree", true, false)

func _log_combat_event(msg: String, type: String = "info") -> void:
	var gss = _get_gesture_tree()
	if gss and gss.has_signal("gesture_logged"):
		gss.emit_signal("gesture_logged", msg, type)


## Daño de impacto secundario por estrellamiento contra el suelo (Ring o Llanura)
func _on_ground_crash_impact(fall_speed: float, crash_pos: Vector3, ground_h: float) -> void:
	var crash_damage = fall_speed * 28.0
	print("[Physics] %s se estrelló contra el suelo a %.1f m/s. Daño de impacto: %.0f NP." % [
		character_data.character_name if character_data else name, fall_speed, crash_damage
	])
	take_hit(crash_damage, Vector3.DOWN)

	# VFX de cráter / escombros de choque terrestre
	_spawn_ground_crash_vfx(Vector3(crash_pos.x, ground_h + 0.05, crash_pos.z), ground_h > 0.2)

	# Activar simulación Ragdoll si el impacto es contundente (caída violenta por martillazo o retroceso)
	if not is_player and fall_speed > 7.5 and not is_ragdoll_active:
		start_ragdoll(Vector3.DOWN * fall_speed * 12.0)
		ragdoll_recovery_timer = 2.8 # Recuperación tras estrellamiento

	# Notificación al HUD
	var loc = "en las losas del cuadrilátero" if ground_h > 0.2 else "en la llanura exterior"
	_log_combat_event("💥 ¡Estrellamiento %s! Daño de impacto: %.0f NP" % [loc, crash_damage], "warning")


## Daño secundario por choque contra los límites rocosos / montañas de la arena
func _on_boundary_crash_impact(speed: float) -> void:
	if speed > 10.0 and is_knocked_back:
		var wall_damage = speed * 32.0
		take_hit(wall_damage, Vector3.ZERO)
		_log_combat_event("💥 ¡Impacto contra la cordillera! Daño adicional: %.0f NP" % wall_damage, "warning")


## Comprueba colisión física contra los 4 pilares angulares de mampostería del ring
func _check_pillar_collisions(pos: Vector3) -> void:
	if velocity.length() < 7.5:
		return
	var pillar_coords = [
		Vector3(-16.65, 0.5, -16.65),
		Vector3(16.65, 0.5, -16.65),
		Vector3(-16.65, 0.5, 16.65),
		Vector3(16.65, 0.5, 16.65)
	]
	for p_pos in pillar_coords:
		if Vector2(pos.x - p_pos.x, pos.z - p_pos.z).length() < 1.6 and pos.y < 4.0:
			var pillar_damage = 350.0
			take_hit(pillar_damage, Vector3.ZERO)
			velocity *= 0.4
			_spawn_flurry_spark(p_pos + Vector3(0.0, 1.2, 0.0))
			_log_combat_event("💥 ¡Impacto demoledor contra pilar de Cell Games! Daño: 350 NP", "warning")
			break


## Inicia la simulación física ragdoll en el esqueleto
func start_ragdoll(impulse: Vector3 = Vector3.ZERO) -> void:
	if not ragdoll_simulator or is_ragdoll_active:
		return
	is_ragdoll_active = true
	if combat_anim_player and combat_anim_player.is_playing():
		combat_anim_player.pause()
	if procedural_animator:
		procedural_animator.enabled = false

	ragdoll_simulator.physical_bones_start_simulation()

	if impulse.length_squared() > 0.01:
		for child in ragdoll_simulator.get_children():
			if child is PhysicalBone3D:
				var bn = child.bone_name.to_lower()
				if "hip" in bn or "pelvis" in bn or "root" in bn or "spine" in bn:
					child.apply_central_impulse(impulse)
					break
	print("[Ragdoll] Simulación física activada para %s." % (character_data.character_name if character_data else name))

## Detiene la simulación física ragdoll y restaura la pose de combate
func stop_ragdoll() -> void:
	if not ragdoll_simulator or not is_ragdoll_active:
		return
	is_ragdoll_active = false
	ragdoll_simulator.physical_bones_stop_simulation()
	if procedural_animator:
		procedural_animator.enabled = true
	print("[Ragdoll] Simulación física detenida. Reanudando postura de combate.")


func _process_mutual_body_collision() -> void:
	if not is_player:
		return
	var opponent = _get_opponent()
	if not opponent or not is_instance_valid(opponent):
		return

	var my_origin = get_parent()
	var player_pos = my_origin.global_position if my_origin else global_position
	var opponent_pos = opponent.global_position

	var diff = player_pos - opponent_pos
	diff.y = 0.0
	var dist = diff.length()

	# Prevención de penetración física mutua entre combatientes (distancia mínima de cuerpos 0.65m)
	var min_body_dist = 0.65
	if dist < min_body_dist and dist > 0.001:
		var push_dir = diff.normalized()
		var overlap = (min_body_dist - dist) * 0.5
		if my_origin:
			my_origin.global_position += push_dir * overlap
			_clamp_to_arena(my_origin)
		opponent.global_position -= push_dir * overlap
		_clamp_to_arena(opponent)


## Gatilla una separación táctica suave hacia la distancia inicial (atacante inmóvil, defensor retrocede poco)
func _trigger_tactical_separation(opponent: Node3D, _separation_speed: float = 4.0) -> void:
	if not opponent or not is_instance_valid(opponent):
		return
	# Solo procesar cuando ambos jugadores NO están en una fase de secuencia
	if is_in_bullet_time or is_flying_to_opponent:
		return
	if opponent.get("is_in_bullet_time") or opponent.get("is_flying_to_opponent"):
		return

	var my_origin = get_parent() if is_player else null
	var my_pos = my_origin.global_position if my_origin else global_position
	var opp_pos = opponent.global_position
	var diff = opp_pos - my_pos
	diff.y = 0.0
	var fwd_dir = diff.normalized() if diff.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)

	# El atacante NO se mueve
	velocity = Vector3.ZERO
	is_knocked_back = false

	# El defensor retrocede suavemente hasta la distancia inicial canónica (~5.5m)
	var current_dist = diff.length()
	var desired_dist = 5.5
	if current_dist < desired_dist:
		var gentle_speed = clampf((desired_dist - current_dist) * 2.5, 2.0, 4.5)
		opponent.set("velocity", fwd_dir * gentle_speed)
		opponent.set("is_knocked_back", false)

	print("[Combat] Separación suave hacia distancia inicial (~2.8m). Atacante inmóvil.")


func _execute_melee_impact(opponent: Node3D) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	var my_origin = get_parent() if is_player else null
	var my_pos = my_origin.global_position if my_origin else global_position
	var fwd = (opponent.global_position - my_pos).normalized()
	if fwd.length_squared() < 0.01:
		fwd = -global_transform.basis.z

	var damage = 450.0
	if is_in_zenkai_state:
		damage *= 2.0

	# Aplicar daño y retroceso físico de impacto directo
	if opponent.has_method("take_hit"):
		opponent.take_hit(damage, fwd)
		increase_np(damage * 0.40)
	elif opponent.has_method("apply_knockback"):
		opponent.apply_knockback(fwd, 14.0)

	# Pulso háptico si es el jugador
	if is_player and my_origin:
		for hand_name in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(hand_name)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 200.0, 1.0, 0.25, 0.0)
		_log_combat_event("[Melee] ¡Impacto directo cuerpo a cuerpo! Daño: %.0f NP" % damage, "success")


## Calcula la duración dinámica del Bullet-Time (Punto 8: 6.0s en modo test para evaluar golpes y finisher)
func calculate_bullet_time_duration(attacker: Node3D, defender: Node3D) -> float:
	if not attacker or not defender:
		return 6.0
	var bp_atk: float = attacker.get("current_np") if attacker.get("current_np") != null else 10000.0
	var bp_def: float = maxf(defender.get("current_np") if defender.get("current_np") != null else 10000.0, 1000.0)
	var bp_diff: float = bp_atk - bp_def
	var ratio: float = bp_diff / bp_def
	# Modo prueba extendido: Duración base 6.0s (rango 4.5s - 7.5s)
	return clampf(6.0 + ratio * 1.5, 4.5, 7.5)


## Activa el modo Bullet-Time táctico al conectar el Melee Dash con el oponente
func _start_melee_bullet_time(opponent: Node3D) -> void:
	if not opponent or not is_instance_valid(opponent):
		return
	if is_in_bullet_time:
		return

	is_in_bullet_time = true
	var duration: float = calculate_bullet_time_duration(self, opponent)
	print("[CharacterInstance] ¡Iniciando Melee Bullet-Time! Duración calculada: %.2fs" % duration)

	# 0. Alinear milimétricamente la cabeza del jugador a 0.65m horizontal del rival
	if is_player:
		var my_origin = get_parent()
		var cam = my_origin.get_node_or_null("XRCamera3D") if my_origin else null
		if my_origin and cam:
			var opp_pos = opponent.global_position
			var cam_h = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
			var opp_h = Vector3(opp_pos.x, 0.0, opp_pos.z)
			var to_player_dir = (cam_h - opp_h).normalized()
			if to_player_dir.length_squared() < 0.01:
				to_player_dir = Vector3.BACK
			var desired_cam_pos = opp_pos + to_player_dir * 0.65
			var cam_offset_from_origin = cam.global_position - my_origin.global_position
			my_origin.global_position.x = desired_cam_pos.x - cam_offset_from_origin.x
			my_origin.global_position.z = desired_cam_pos.z - cam_offset_from_origin.z
			_clamp_to_arena(my_origin)

	# Instanciar la cúpula holográfica anime con las cajas de impacto
	active_target_dome = MeleeTargetDomeClass.new()
	get_tree().current_scene.add_child(active_target_dome)
	active_target_dome.setup(self, opponent, duration)
	active_target_dome.bullet_time_completed.connect(_on_bullet_time_completed.bind(opponent))
	active_target_dome.finisher_triggered.connect(_on_bullet_time_finisher.bind(opponent))

	# Pulso háptico inicial y log en HUD
	var my_origin = get_parent() if is_player else null
	if is_player and my_origin:
		for hand_name in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(hand_name)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 180.0, 0.7, 0.15, 0.0)

	_log_combat_event("⚡ ¡BULLET TIME ACTIVADO! Golpea los puntos vitales (%.1fs)" % duration, "success")
	var gss = _get_gesture_tree()
	if gss and gss.has_signal("phase_changed"):
		gss.emit_signal("phase_changed", "¡BULLET TIME ACTIVADO!")


## Callback al finalizar la ventana de Bullet-Time: desactiva la cúpula e inicia la ráfaga
func _on_bullet_time_completed(recorded_hits: Array, launch_vector: Vector3, opponent: Node3D) -> void:
	is_in_bullet_time = false
	active_target_dome = null
	_execute_melee_flurry_barrage(opponent, recorded_hits, launch_vector)


## Callback al activarse un Finisher (ej. Martillazo bimanual) durante el Bullet-Time
func _on_bullet_time_finisher(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3, opponent: Node3D) -> void:
	is_in_bullet_time = false
	active_target_dome = null
	if finisher_name == "hammer_strike":
		_execute_hammer_strike_finisher(opponent, swing_velocity, recorded_hits, launch_vector)
	else:
		_execute_melee_flurry_barrage(opponent, recorded_hits, launch_vector)


## Ejecuta cinematográficamente la ráfaga de puñetazos (flurry) acumulada durante el Bullet-Time
func _execute_melee_flurry_barrage(opponent: Node3D, recorded_hits: Array, launch_vector: Vector3 = Vector3.ZERO) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	var hit_count: int = recorded_hits.size()
	var my_origin = get_parent() if is_player else null
	var my_pos = my_origin.global_position if my_origin else global_position
	var fwd = (opponent.global_position - my_pos).normalized()
	if fwd.length_squared() < 0.01:
		fwd = -global_transform.basis.z

	if hit_count == 0:
		print("[BulletTime] 0 golpes conectados. El oponente esquivó la embestida.")
		_log_combat_event("¡El oponente esquivó tu embestida!", "warning")
		_separate_fighters_to_canonical_distance(opponent, 5.5)
		return

	# Daño escalado: potencia por golpe sumada con bonus de combo (+15% por cada golpe adicional)
	var total_damage: float = 0.0
	var has_charged_hit: bool = false
	for h in recorded_hits:
		var p_power = float(h.get("power", 1.0))
		var is_c = bool(h.get("is_charged", false))
		if is_c:
			has_charged_hit = true
			total_damage += 280.0 * p_power
		else:
			total_damage += 140.0 * p_power

	var combo_bonus: float = 1.0 + float(hit_count) * 0.15
	total_damage *= combo_bonus
	if is_in_zenkai_state:
		total_damage *= 2.0

	# Secuencia de impactos de alta velocidad anime (tatatatata)
	for i in range(hit_count):
		var hit_info = recorded_hits[i]

		# Flinch reactivo en el modelo del oponente
		if opponent.get("procedural_animator"):
			opponent.procedural_animator.trigger_hit_flinch(0.35, -fwd)

		# Pulso háptico en mandos durante la ráfaga
		if is_player and my_origin:
			var h_name: String = hit_info.get("hand", "RightHand")
			var ctrl = my_origin.get_node_or_null(h_name)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 160.0, 0.75, 0.05, 0.0)

		# Intervalo rítmico de 0.04s entre golpes
		await get_tree().create_timer(0.04).timeout
		if not is_instance_valid(opponent):
			return

	# Impacto final: El atacante NO se mueve
	velocity = Vector3.ZERO
	is_knocked_back = false

	if opponent.has_method("take_hit"):
		opponent.take_hit(total_damage, Vector3.ZERO)
		increase_np(total_damage * 0.40)

	# Pulso háptico máximo final
	if is_player and my_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 220.0, 1.0, 0.25, 0.0)

	_log_combat_event("💥 ¡RÁFAGA DE COMBATE! %d golpes conectados. Daño total: %.0f NP" % [hit_count, total_damage], "success")

	# REQUISITO CANÓNICO 5: Si la secuencia terminó con un golpe cargado, el contrincante sale despedido por los aires
	# y tras 1 segundo se activa una nueva ventana de Follow-Up Bullet-Time
	if has_charged_hit and launch_vector.length_squared() > 0.1:
		print("[BulletTime] Ráfaga concluida con golpe cargado. Lanzando al oponente por los aires hacia: %s" % str(launch_vector))
		_start_followup_airborne_sequence(opponent, launch_vector)
	else:
		# Si no hubo golpe cargado, separación garantizada a la distancia inicial canónica (5.5m)
		print("[BulletTime] Ráfaga concluida. Separando combatientes a distancia canónica (5.5m).")
		_separate_fighters_to_canonical_distance(opponent, 5.5)


## Ejecuta el demoledor Martillazo de Dragon Ball Z como Finisher de corte en Bullet-Time
func _execute_hammer_strike_finisher(opponent: Node3D, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3 = Vector3.ZERO) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	var my_origin = get_parent() if is_player else null
	var my_pos = my_origin.global_position if my_origin else global_position
	var fwd = (opponent.global_position - my_pos).normalized()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else -global_transform.basis.z

	# 1. Consumo de Ki para golpe pesado (25 Ki base, con Último Aliento si Ki < 25)
	var ki_cost: float = 25.0
	var ki_spent: float = 0.0
	if current_ki >= ki_cost:
		current_ki -= ki_cost
		ki_spent = ki_cost
	else:
		ki_spent = current_ki
		var ki_debt = ki_cost - current_ki
		current_ki = 0.0
		current_np = maxf(current_np - ki_debt * 35.0, 100.0)
	_notify_stats()

	# 2. Factores cinéticos y ratio diferencial de BP
	var v_clean: float = clampf(swing_velocity, 2.0, 5.5)
	var factor_cinetico: float = pow(v_clean / 2.5, 1.2) * (1.0 + (ki_spent / 40.0))

	var bp_atk: float = maxf(current_np, 1000.0)
	var bp_def: float = maxf(opponent.get("current_np") if opponent.get("current_np") != null else 10000.0, 1000.0)
	var ratio_bp: float = clampf(sqrt(bp_atk / bp_def), 0.35, 3.0)

	# El atacante NO se mueve jamás tras el martillazo
	velocity = Vector3.ZERO
	is_knocked_back = false

	# 3. Daño primario directo escalado por Ki y BP
	var base_dmg = 550.0 + ki_spent * 8.0
	var bp_dmg_mult = pow(bp_atk / bp_def, 0.6)
	var combo_bonus = 1.0 + float(recorded_hits.size()) * 0.20
	var direct_damage = base_dmg * bp_dmg_mult * combo_bonus
	if is_in_zenkai_state:
		direct_damage *= 2.0

	var hit_pos = opponent.global_position + Vector3(0.0, 1.1, 0.0)

	# 4. Efectos audiovisuales y hápticos
	_spawn_melee_shockwave(hit_pos)

	if is_player and my_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 220.0, 1.0, 0.30, 0.0)

	# Flinch con espina y cabeza arqueadas hacia atrás
	if opponent.get("procedural_animator"):
		opponent.procedural_animator.trigger_hit_flinch(1.4, -Vector3.UP)

	# 5. Aplicar daño primario
	if opponent.has_method("take_hit"):
		opponent.take_hit(direct_damage, Vector3.ZERO)
		increase_np(direct_damage * 0.45)

	var final_launch = launch_vector if launch_vector.length_squared() > 0.1 else (fwd * 4.2 + Vector3.UP * 2.2).normalized() * 11.5

	_log_combat_event("💥 ¡FINISHER MARTILLAZO CONECTADO! Rival derribado. Daño: %.0f NP" % direct_damage, "success")
	print("[HammerFinisher] Martillazo conectado: daño=%.0f NP. Atacante inmóvil. Impulsando hacia los aires." % direct_damage)

	# Iniciar secuencia de seguimiento aéreo tras el impacto del martillazo
	_start_followup_airborne_sequence(opponent, final_launch)


## Separa simétricamente a ambos combatientes hacia la distancia canónica de combate (5.5m)
func _separate_fighters_to_canonical_distance(opponent: Node3D, target_distance: float = 5.5) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	var my_origin = get_parent() if is_player else null
	var cam: Camera3D = my_origin.get_node_or_null("XRCamera3D") if my_origin else null

	var p_pos = cam.global_position if cam else (my_origin.global_position if my_origin else global_position)
	var p_h = Vector3(p_pos.x, 0.0, p_pos.z)
	var opp_h = Vector3(opponent.global_position.x, 0.0, opponent.global_position.z)

	var current_dist = p_h.distance_to(opp_h)
	# ¡REQUISITO CANÓNICO! Solo reajustar si la distancia entre los combatientes es menor a la distancia canónica (están pegados / muy juntos).
	# Si ya cumplen la distancia mínima (por ejemplo porque salieron volando por un golpe cargado o martillo a 8-12m), ¡NO reajustar ni traerlos de vuelta!
	if current_dist >= (target_distance - 0.3):
		print("[Combat] Combatientes ya a distancia adecuada (%.1fm >= %.1fm). Sin reajuste necesario." % [current_dist, target_distance])
		return

	var fwd_dir = (opp_h - p_h).normalized()
	if fwd_dir.length_squared() < 0.01:
		fwd_dir = -cam.global_transform.basis.z if cam else -global_transform.basis.z
		fwd_dir.y = 0.0
		fwd_dir = fwd_dir.normalized() if fwd_dir.length_squared() > 0.01 else Vector3.FORWARD

	# Punto medio horizontal entre los combatientes
	var mid = (p_h + opp_h) * 0.5
	var half_dist = target_distance * 0.5

	# Destino canónico del oponente (alejándose hacia adelante)
	var target_opp_pos = mid + fwd_dir * half_dist
	target_opp_pos.y = get_ground_elevation(target_opp_pos)

	# Destino canónico del jugador (alejándose hacia atrás)
	var target_head_pos = mid - fwd_dir * half_dist
	var cam_offset = (cam.global_position - my_origin.global_position) if (cam and my_origin) else Vector3.ZERO
	var target_origin_pos = Vector3(target_head_pos.x - cam_offset.x, my_origin.global_position.y if my_origin else 0.0, target_head_pos.z - cam_offset.z)

	# Frenar velocidades físicas
	velocity = Vector3.ZERO
	is_knocked_back = false
	opponent.set("velocity", Vector3.ZERO)
	opponent.set("is_knocked_back", false)

	# Desplazamiento simétrico suave simultáneo (0.45s)
	var tw_opp = opponent.create_tween()
	tw_opp.tween_property(opponent, "global_position", target_opp_pos, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if is_player and my_origin:
		var tw_p = my_origin.create_tween()
		tw_p.tween_property(my_origin, "global_position", target_origin_pos, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_p.tween_callback(func(): _clamp_to_arena(my_origin))

	tw_opp.tween_callback(func(): _clamp_to_arena(opponent))
	print("[Combat] Separación simétrica canónica ejecutada: Distancia final=%.1fm." % target_distance)


## Inicia la secuencia de lanzamiento aéreo y activa el Follow-Up Bullet-Time tras 1 segundo
func _start_followup_airborne_sequence(opponent: Node3D, launch_vector: Vector3) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	# Asegurar componente de elevación aérea y propulsión horizontal enérgica
	var h_comp = Vector3(launch_vector.x, 0.0, launch_vector.z)
	var h_dir = h_comp.normalized() if h_comp.length_squared() > 0.01 else -global_transform.basis.z
	h_dir.y = 0.0
	h_dir = h_dir.normalized()

	var vert_speed = maxf(launch_vector.y, 3.8)
	var horiz_speed = maxf(h_comp.length(), 9.5)
	var final_impulse = h_dir * horiz_speed + Vector3.UP * vert_speed

	# Elevar ligeramente al contrincante sobre el suelo para iniciar vuelo libre por los aires
	var ground_h = get_ground_elevation(opponent.global_position)
	opponent.global_position.y = maxf(opponent.global_position.y, ground_h + 0.85)

	# Reducir fricción durante el lanzamiento aéreo (drag=4.0 en vez de 24.0) para que vuele varios metros
	opponent.set("knockback_drag", 4.0)
	opponent.set("velocity", final_impulse)
	opponent.set("is_knocked_back", true)

	# Esperar 1.0 segundo mientras el contrincante vuela por los aires
	await get_tree().create_timer(1.0).timeout
	if not opponent or not is_instance_valid(opponent):
		return

	# Restaurar fricción canónica
	opponent.set("knockback_drag", 24.0)

	# Si el combate sigue activo, encender el Follow-Up Bullet-Time
	is_in_followup_bullet_time = true
	followup_bullet_time_timer = 4.0
	opponent_airborne_target = opponent

	# Suspender al oponente en el aire en cámara lenta
	opponent.set("velocity", Vector3.ZERO)
	opponent.set("is_knocked_back", false)

	_log_combat_event("⚡ ¡CADENA DE SEGUIMIENTO EN EL AIRE! (4.0s) Dispara Ki Blasts, Melee Dash o Super Poder", "success")
	var gss = _get_gesture_tree()
	if gss and gss.has_signal("phase_changed"):
		gss.emit_signal("phase_changed", "¡CADENA EN EL AIRE! (FOLLOW-UP BULLET TIME)")


## Finaliza el Follow-Up Bullet-Time
func _end_followup_bullet_time(timed_out: bool = false) -> void:
	if not is_in_followup_bullet_time:
		return
	is_in_followup_bullet_time = false

	var target_opp = opponent_airborne_target
	opponent_airborne_target = null

	if target_opp and is_instance_valid(target_opp):
		# En cualquier finalización donde los combatientes queden cerca o tras expirar el tiempo, separarlos a 5.5m
		var my_origin = get_parent() if is_player else null
		var cam: Camera3D = my_origin.get_node_or_null("XRCamera3D") if my_origin else null
		var p_pos = cam.global_position if cam else (my_origin.global_position if my_origin else global_position)
		var current_dist = p_pos.distance_to(target_opp.global_position)

		if timed_out or current_dist < 4.5:
			_separate_fighters_to_canonical_distance(target_opp, 5.5)
			_log_combat_event("Secuencia aérea concluida. Separación táctica restablecida (5.5m).", "info")
		else:
			target_opp.set("velocity", Vector3.ZERO)
			target_opp.set("is_knocked_back", false)


## Genera la onda de choque expansiva del impacto físico masivo (Melee Shockwave)
func _spawn_melee_shockwave(pos: Vector3) -> void:
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.50
	flash.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.4, 0.95)
	flash.material_override = mat

	var scene_root = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(flash)
	else:
		add_child(flash)
	flash.global_position = pos

	var tw = flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 5.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(flash.queue_free)


## Genera el cráter visual y polvo tras estrellarse contra el suelo (Ring o Llanura)
func _spawn_ground_crash_vfx(pos: Vector3, is_stone_ring: bool) -> void:
	var crater = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 1.4
	cylinder.bottom_radius = 1.8
	cylinder.height = 0.08
	cylinder.radial_segments = 16
	crater.mesh = cylinder

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.7, 0.5, 0.8) if not is_stone_ring else Color(0.95, 0.9, 0.7, 0.9)
	crater.material_override = mat

	var scene_root = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(crater)
	else:
		add_child(crater)
	crater.global_position = pos

	var tw = crater.create_tween().set_parallel(true)
	tw.tween_property(crater, "scale", Vector3.ONE * 2.2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.50)
	tw.chain().tween_callback(crater.queue_free)


## Genera un destello visual en el punto del impacto de la ráfaga
func _spawn_flurry_spark(pos: Vector3) -> void:
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	spark.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
	spark.material_override = mat

	var scene_root = get_tree().current_scene if (is_inside_tree() and get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(spark)
	else:
		add_child(spark)
	spark.global_position = pos

	var tw = spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 0.35, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.chain().tween_callback(spark.queue_free)
