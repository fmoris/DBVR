class_name CharacterInstance
extends Node3D

signal stats_changed(ki: float, np: float, is_zenkai: bool)
signal transformed(transformation: Resource)
signal transformation_unlocked(form_name: String)
signal power_unlocked(power_name: String)
signal game_finished(winner_name: String)
signal match_finished(winner: Node3D, loser: Node3D, tech_name: String)
signal zenkai_activated(source: String) # "brecha", "comeback"

@export var character_data: Resource

# Estadísticas activas en runtime
var current_ki: float = 50.0
var current_np: float = 9000.0

var current_transformation: Resource = null
var current_transformation_index: int = -1
var _active_np_multiplier: float = 1.0
var _bp_popup_cooldown: float = 0.0
var _pending_bp_popup_accum: float = 0.0
var _passive_regen_cooldown: float = 0.0
var _passive_notify_accum: float = 0.0
var unlocked_powers: Array[String] = []
var unlocked_transformations: Array[String] = []

# Estado de Zenkai y Comebacks
var is_in_zenkai_state: bool = false
var is_comeback_zenkai: bool = false # Si es true, el Zenkai se activó por remontada y dura solo un ataque
var is_match_over: bool = false
var is_penalized: bool = false
var penalty_timer: float = 0.0
# Umbrales irreversibles de NP (Canon GDD: 25%, 50%, 75%, 100%)
var secured_np_threshold_ratio: float = 0.0

# --- Físicas 3D, Colisiones y Knockback ---
var velocity: Vector3 = Vector3.ZERO
var knockback_drag: float = 24.0 # Fricción alta para frenado realista de cuerpos (cero rebote excesivo)
var gravity: float = 9.8
var is_knocked_back: bool = false
var _proximity_repulsion_cooldown: float = 0.0
var arena_half_limit: float = 92.0 # Límite en las faldas del cañón de Akira Toriyama
const RING_HALF_SIZE: float = 16.0 # Límite del cuadrilátero de piedra de Cell (32x32m)
var wall_stick_timer: float = 0.0 # Efecto de quedar incrustado en la roca de la montaña (Toriyama canon)
var last_wall_crash_normal: Vector3 = Vector3.FORWARD

# --- Estado de Guardia y Bloqueo Defensivo ---
var is_blocking: bool = false
var is_guard_broken: bool = false
var guard_break_timer: float = 0.0

# --- Estado de Resistencia de Carga (Super Armor / Poise Canónico) ---
var is_charging_super: bool = false
var is_firing_beam: bool = false
var beam_tech_name: String = ""
var current_charge_poise: float = 500.0
var max_charge_poise: float = 500.0
var is_staggered: bool = false
var stagger_timer: float = 0.0

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
var char_voice_player: AudioStreamPlayer3D = null
var char_sfx_player: AudioStreamPlayer3D = null
var _hurt_voice_cooldown: float = 0.0
var head_bone_idx: int = -1
var hidden_head_bone_indices: Array[int] = []
var neck_bone_idx: int = -1
var torso_yaw: float = 0.0

## Retorna el nodo espacial raíz responsable del posicionamiento en el mundo (XROrigin3D para el jugador, o self para la IA)
func get_spatial_root() -> Node3D:
	if is_player:
		var p = get_parent()
		if p is Node3D and p is XROrigin3D:
			return p
	return self

# Índices óseos para Cinemática Inversa (IK) de brazos en 1ra persona y NPCs
var left_arm_idx: int = -1
var left_forearm_idx: int = -1
var left_hand_idx: int = -1
var right_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1

# Calibración automática de rig agnóstica de personaje (Goku/Vegeta) y cachés O(1)
var _rig_calibrated: bool = false
var _skel_char_basis: Basis = Basis.IDENTITY
var _left_hand_align_basis: Basis = Basis.IDENTITY
var _right_hand_align_basis: Basis = Basis.IDENTITY
var _arm_reach_left_skel: float = 0.56
var _arm_reach_right_skel: float = 0.56
var _finger_curl_cache: Dictionary = {}
var cached_exclude_rids: Array[RID] = []
var cached_ai_controller: Node = null

const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const MeleeTargetDomeClass = preload("res://scripts/MeleeTargetDome.gd")
const SuperBeamSequenceClass = preload("res://scripts/SuperBeamSequenceController.gd")
var is_charging_ki: bool = false
var aura_node: Node3D = null

# Estado y control de Bullet-Time (Dilatación temporal en combate cuerpo a cuerpo)
var is_in_bullet_time: bool = false
var active_target_dome: Node3D = null
var is_target_locked: bool = false # Requisito canónico de fijación visual para Melee Dash
var is_in_followup_bullet_time: bool = false
var followup_bullet_time_timer: float = 0.0
var opponent_airborne_target: Node3D = null

# Estado y control de Secuencia de Super Haz (Bullet-Time para técnicas supremas)
var is_in_beam_sequence: bool = false
var active_beam_sequence: Node3D = null

# Variables de vuelo hacia el contrincante
var is_flying_to_opponent: bool = false
var flight_speed: float = 18.0
var _dash_speed_mult: float = 1.0
var _dash_vfx_ring: MeshInstance3D = null

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
	current_transformation = null
	current_transformation_index = -1
	_active_np_multiplier = 1.0
	_bp_popup_cooldown = 0.0
	_pending_bp_popup_accum = 0.0
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
	is_match_over = false
	_hurt_voice_cooldown = 0.0
	_ensure_character_audio_players()
	if not is_player:
		play_character_action_audio("intro_taunt", true, "goku.intro_taunt")
	unlocked_powers.clear()
	unlocked_transformations.clear()
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
				neck_bone_idx = skeleton.find_bone("Neck")
				if neck_bone_idx == -1:
					neck_bone_idx = skeleton.find_bone("neck")

				left_arm_idx = skeleton.find_bone("LeftArm")
				left_forearm_idx = skeleton.find_bone("LeftForeArm")
				left_hand_idx = skeleton.find_bone("LeftHand")

				right_arm_idx = skeleton.find_bone("RightArm")
				right_forearm_idx = skeleton.find_bone("RightForeArm")
				right_hand_idx = skeleton.find_bone("RightHand")

				_calibrate_skeleton_rig()

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
					
					# Recolectar recursivamente todos los huesos asociados a cabeza, cabello y rostro
					hidden_head_bone_indices.clear()
					for i in range(skeleton.get_bone_count()):
						var b_name = skeleton.get_bone_name(i).to_lower()
						var is_head_descendant = false
						var p_idx = skeleton.get_bone_parent(i)
						while p_idx != -1:
							if p_idx == head_bone_idx:
								is_head_descendant = true
								break
							p_idx = skeleton.get_bone_parent(p_idx)
						if i == head_bone_idx or is_head_descendant or "hair" in b_name or "eye" in b_name or "face" in b_name or "jaw" in b_name or "brow" in b_name or "mouth" in b_name:
							hidden_head_bone_indices.append(i)
							skeleton.set_bone_pose_scale(i, Vector3.ZERO)

					var cam = get_parent().get_node_or_null("XRCamera3D") if get_parent() else null
					if cam:
						var cam_fwd_local: Vector3 = -cam.transform.basis.z
						var cam_fwd_xz: Vector3 = Vector3(cam_fwd_local.x, 0.0, cam_fwd_local.z)
						torso_yaw = atan2(-cam_fwd_xz.x, -cam_fwd_xz.z) if cam_fwd_xz.length_squared() > 0.0001 else cam.rotation.y
					else:
						torso_yaw = 0.0
							
					print("[CharacterInstance] Cuerpo 1ra persona configurado. Head: %d, Neck: %d, ArmIK: [L:%d, R:%d]" % [head_bone_idx, neck_bone_idx, left_arm_idx, right_arm_idx])
				else:
					# 1. Configurar animador procedural para dar vida orgánica al oponente en VR
					procedural_animator = ProceduralCombatAnimatorClass.new()
					procedural_animator.setup(skeleton, self)

					# 2. Generar PhysicalBoneSimulator3D para la simulación física de impactos (Ragdoll)
					ragdoll_simulator = RuntimeRagdollGenerator.generate_ragdoll(skeleton, {"total_mass": 75.0})
					if ragdoll_simulator:
						ragdoll_simulator.physical_bones_stop_simulation()

					# 3. Inicializar Inteligencia Artificial de Combate (CombatAIController)
					var ai_ctrl = get_node_or_null("CombatAIController")
					if not ai_ctrl:
						var ai_script = load("res://scripts/CombatAIController.gd")
						if ai_script:
							ai_ctrl = Node.new()
							ai_ctrl.name = "CombatAIController"
							ai_ctrl.set_script(ai_script)
							add_child(ai_ctrl)
					cached_ai_controller = ai_ctrl
					if cached_ai_controller and is_instance_valid(cached_ai_controller):
						cached_ai_controller.set("enabled", true)
			_disable_frustum_culling_in_children(body_mesh_instance)
			
	# Instanciar el modelo de las manos en runtime (solo si ES el jugador, para ver nuestras manos en primera persona)
	if is_player and character_data.hands_model_path != "":
		_setup_player_hands.call_deferred()

	# Configurar colisiones físicas y hitbox para ambos personajes
	_setup_character_physics()

	_notify_stats()


func swap_character_data(new_data: CharacterData) -> void:
	if not new_data:
		return
	current_transformation = null
	current_transformation_index = -1
	_active_np_multiplier = 1.0
	_bp_popup_cooldown = 0.0
	_pending_bp_popup_accum = 0.0
	secured_np_threshold_ratio = 0.0
	is_in_zenkai_state = false
	is_comeback_zenkai = false
	is_match_over = false
	is_charging_ki = false
	is_charging_super = false
	is_firing_beam = false
	is_blocking = false
	is_guard_broken = false
	is_staggered = false
	is_ragdoll_active = false
	ragdoll_recovery_timer = 0.0
	velocity = Vector3.ZERO

	if aura_node and is_instance_valid(aura_node):
		aura_node.visible = false
	if aura_particles and is_instance_valid(aura_particles):
		aura_particles.queue_free()
		aura_particles = null
	if body_mesh_instance and is_instance_valid(body_mesh_instance):
		remove_child(body_mesh_instance)
		body_mesh_instance.queue_free()
		body_mesh_instance = null

	skeleton = null
	procedural_animator = null
	ragdoll_simulator = null
	_rig_calibrated = false
	_finger_curl_cache.clear()
	cached_exclude_rids.clear()

	character_data = new_data
	setup_character()
	if not is_player and cached_ai_controller and is_instance_valid(cached_ai_controller):
		cached_ai_controller.set("enabled", true)
		if cached_ai_controller.has_method("reset_ai_for_character"):
			cached_ai_controller.reset_ai_for_character()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Asegurar bloqueo rígido permanente del Transform del jugador al XROrigin3D (Cero desfase 1ra persona)
	if is_player:
		transform = Transform3D.IDENTITY

	# Control de simulación y recuperación Ragdoll
	if is_ragdoll_active:
		if not is_match_over and ragdoll_recovery_timer > 0.0:
			ragdoll_recovery_timer -= delta
			if ragdoll_recovery_timer <= 0.0:
				stop_ragdoll()
		return

	if is_match_over:
		velocity = velocity.lerp(Vector3.ZERO, clampf(delta * 4.0, 0.0, 1.0))
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
				# Punto 5: Choque Dash vs Dash en pleno vuelo (gana ofensiva el de mayor BP)
				if bool(opponent.get("is_flying_to_opponent")) and dist <= target_dist + 0.45:
					_stop_flight()
					if opponent.has_method("_stop_flight"):
						opponent._stop_flight()
					var mid_clash: Vector3 = (my_pos + opponent_pos) * 0.5
					_spawn_melee_shockwave(mid_clash)
					KiSmokeFX.spawn_smoke(get_tree(), mid_clash, 1.1)
					var opp_np: float = float(opponent.get("current_np")) if opponent.get("current_np") != null else 10000.0
					if current_np >= opp_np:
						_start_melee_bullet_time(opponent)
					elif opponent.has_method("_start_melee_bullet_time"):
						opponent._start_melee_bullet_time(self)
					return

				var dir = diff.normalized() if dist > 0.01 else Vector3.FORWARD
				var move_amount = min(flight_speed * _dash_speed_mult * delta, dist - target_dist)
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
					_start_melee_bullet_time(opponent)
			else:
				_stop_flight()
				_start_melee_bullet_time(opponent)
		else:
			_stop_flight()

	# 2. Físicas de Velocidad y Knockback
	if wall_stick_timer > 0.0:
		wall_stick_timer -= delta
		velocity = Vector3.ZERO
		if wall_stick_timer <= 0.35 and not is_player and not is_ragdoll_active and ragdoll_simulator != null:
			wall_stick_timer = 0.0
			start_ragdoll(last_wall_crash_normal * 2.5 + Vector3.DOWN * 4.5)
			ragdoll_recovery_timer = 1.65
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

		# En Dragon Ball los peleadores levitan en el aire (Bukujutsu).
		# La gravedad SOLO se aplica si el personaje fue arrojado expresamente hacia el suelo (Remate/Martillazo, velocity.y < -4.0)
		# o si se encuentra en ragdoll / inconsciente. Un Ki blast o golpe normal NUNCA hace caer al suelo.
		var current_pos = (get_parent().global_position if is_player else global_position)
		var ground_h = get_ground_elevation(current_pos)
		if velocity.y < -4.0 or is_ragdoll_active:
			if current_pos.y > ground_h + 0.005:
				velocity.y -= gravity * delta
			else:
				# Si caía a gran velocidad hacia el suelo (impacto sísmico / crash damage)
				if velocity.y < -7.0 and is_knocked_back:
					_on_ground_crash_impact(abs(velocity.y), current_pos, ground_h)
				velocity.y = 0.0
				is_knocked_back = false
		else:
			# Si el golpe no era un remate hacia abajo, disipamos la velocidad vertical suavemente sin caer al suelo
			velocity.y = move_toward(velocity.y, 0.0, knockback_drag * delta)
			if current_pos.y <= ground_h + 0.005:
				velocity.y = 0.0
				is_knocked_back = false
		if is_knocked_back and velocity.length_squared() < 1.2:
			is_knocked_back = false
	elif is_knocked_back:
		is_knocked_back = false

	# 3. Colisión mutua de cuerpos anti-clipping (No atravesar al rival) y rebote de Ki por cercanía
	if _proximity_repulsion_cooldown > 0.0:
		_proximity_repulsion_cooldown -= delta
	_process_mutual_body_collision()

	# 4. Temporizador de rotura de guardia
	if is_guard_broken:
		guard_break_timer -= delta
		if guard_break_timer <= 0.0:
			is_guard_broken = false
			print("[Combat] %s recuperó la estabilidad de guardia." % (character_data.character_name if character_data else name))

	# 5. Temporizador de aturdimiento (Stagger por concentración rota)
	if is_staggered:
		stagger_timer -= delta
		if stagger_timer <= 0.0:
			is_staggered = false


func _process(delta: float) -> void:
	# Asegurar bloqueo rígido permanente del Transform del jugador al XROrigin3D
	if is_player:
		transform = Transform3D.IDENTITY

	if _bp_popup_cooldown > 0.0:
		_bp_popup_cooldown -= delta
	if _hurt_voice_cooldown > 0.0:
		_hurt_voice_cooldown -= delta

	# Manejar temporizador de penalización por fallo de remate
	if is_penalized:
		penalty_timer -= delta
		if penalty_timer <= 0.0:
			is_penalized = false
			print("[CharacterInstance] %s: Penalización finalizada." % character_data.character_name)

	# Consumo de Ki por segundo si está transformado (no revertir a mitad de un Super / Beam / estado Zenkai)
	var busy_with_super_or_zenkai: bool = is_charging_super or is_firing_beam or is_in_beam_sequence or is_in_zenkai_state
	if current_transformation:
		var drain = current_transformation.ki_drain_per_sec * delta
		if current_ki > drain:
			current_ki -= drain
			_notify_stats()
		else:
			current_ki = 0.0
			if not busy_with_super_or_zenkai:
				revert_to_base()

	# Reversión canónica a estado base si el Ki se agota por cualquier causa (Punto 13)
	if current_transformation and current_ki <= 0.0 and not busy_with_super_or_zenkai:
		revert_to_base()

	# Alinear el aura con la cámara para el jugador en primera persona
	if is_player and aura_node and is_instance_valid(aura_node):
		var camera = get_parent().get_node_or_null("XRCamera3D")
		if camera:
			var cam_w = camera.global_position
			var p_orig: Node3D = get_parent() as Node3D
			var floor_y = p_orig.global_position.y if p_orig else global_position.y
			aura_node.global_position = Vector3(cam_w.x, floor_y, cam_w.z)

	# Alinear el cuerpo con la cámara y mover cuello según la dirección de mirada con deadzone
	if is_player and is_instance_valid(body_mesh_instance):
		var camera = get_parent().get_node_or_null("XRCamera3D")
		if camera:
			# 1. Torso Deadzone: El torso no gira bruscamente; solo cuando la cabeza gira más de 35 grados (proyección XZ sin gimbal lock)
			var cam_fwd_local: Vector3 = -camera.transform.basis.z
			var cam_fwd_xz: Vector3 = Vector3(cam_fwd_local.x, 0.0, cam_fwd_local.z)
			var cam_yaw: float = torso_yaw
			if cam_fwd_xz.length_squared() > 0.0001:
				cam_yaw = atan2(-cam_fwd_xz.x, -cam_fwd_xz.z)
			var yaw_diff: float = wrapf(cam_yaw - torso_yaw, -PI, PI)
			var max_neck_angle: float = deg_to_rad(35.0)
			if abs(yaw_diff) > max_neck_angle:
				var target_yaw: float = cam_yaw - sign(yaw_diff) * max_neck_angle
				torso_yaw = lerp_angle(torso_yaw, target_yaw, 8.0 * delta)
				
			# Offset hacia atrás del torso respecto a los ojos (10cm) usando rotación mundial real
			var origin_node: Node3D = get_parent() as Node3D
			var origin_rot_y: float = origin_node.global_rotation.y if origin_node else 0.0
			var world_torso_yaw: float = origin_rot_y + torso_yaw
			var torso_back: Vector3 = Vector3(sin(world_torso_yaw), 0.0, cos(world_torso_yaw)) * 0.10
			var cam_world: Vector3 = camera.global_position
			var floor_y: float = origin_node.global_position.y if origin_node else global_position.y
			
			# Anclaje mundial absoluto: El cuerpo siempre está exactamente debajo de la cabeza en el mundo real
			body_mesh_instance.global_position = Vector3(cam_world.x + torso_back.x, floor_y, cam_world.z + torso_back.z)
			body_mesh_instance.global_rotation = Vector3(0.0, world_torso_yaw + PI, 0.0)
			
			if skeleton:
				# Ocultar todos los huesos de cabeza, cabello y rostro a escala cero para evitar cualquier visión en 3ra persona
				for b_idx in hidden_head_bone_indices:
					if skeleton.get_bone_pose_scale(b_idx) != Vector3.ZERO:
						skeleton.set_bone_pose_scale(b_idx, Vector3.ZERO)
				
				# Mover el cuello en espacio de personaje (compatible con Goku y Vegeta)
				if neck_bone_idx != -1:
					var neck_yaw: float = wrapf(cam_yaw - torso_yaw, -PI, PI)
					var neck_pitch: float = camera.rotation.x
					var neck_rot: Quaternion = get_bone_rotation_char_space(neck_bone_idx, Vector3(neck_pitch * 0.65, neck_yaw * 0.65, 0.0))
					skeleton.set_bone_pose_rotation(neck_bone_idx, neck_rot)

	# Cinemática Inversa (IK) de brazos y animación de dedos en primera persona
	if is_player:
		_process_player_arms_ik()

	# Rotar al oponente para mirar directamente al jugador cara a cara y actualizar animación procedural
	if not is_player:
		var opp = _get_opponent()
		if opp and is_instance_valid(opp):
			var opp_pos: Vector3 = opp.global_position
			if bool(opp.get("is_player")):
				var o_orig: Node = opp.get_parent()
				var o_cam: Camera3D = o_orig.get_node_or_null("XRCamera3D") as Camera3D if o_orig else null
				if o_cam and is_instance_valid(o_cam):
					opp_pos = o_cam.global_position
			var diff = opp_pos - global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				# Alinear frontalmente al oponente cara a cara hacia el jugador (el modelo tiene su frente canónico en +Z)
				rotation.y = atan2(diff.x, diff.z)

			if procedural_animator:
				# Altura de los ojos del jugador estimada a 1.45m o posición del visor
				var eye_target = opp_pos + Vector3(0.0, 1.45, 0.0)
				procedural_animator.update(delta, eye_target, is_charging_ki, is_blocking, is_flying_to_opponent)


	# Regeneración pasiva de Ki en Fase Libre y actualización visual del aura
	_process_passive_ki_regen(delta)
	_update_aura_visuals(delta)

func start_charging_super() -> void:
	is_charging_super = true
	var opp = _get_opponent()
	var opp_np = opp.current_np if opp and is_instance_valid(opp) else 10000.0
	var bp_ratio = clampf(current_np / maxf(opp_np, 100.0), 0.35, 3.5)
	max_charge_poise = 500.0 * bp_ratio
	current_charge_poise = max_charge_poise


func stop_charging_super() -> void:
	is_charging_super = false


func interrupt_charging_super() -> void:
	is_charging_super = false
	is_staggered = true
	stagger_timer = 0.4
	
	_spawn_fizzle_vfx()
	
	if is_player:
		var ctrl = get_tree().current_scene.find_child("HybridCombatController", true, false)
		if ctrl and ctrl.has_method("cancel_super_from_poise_break"):
			ctrl.cancel_super_from_poise_break()
		_log_combat_event("[CONCENTRACIÓN ROTA] ¡La lluvia de ataques interrumpió tu técnica!", "warning")
	else:
		var ai_ctrl = get_node_or_null("CombatAIController")
		if ai_ctrl and ai_ctrl.has_method("interrupt_kamehameha"):
			ai_ctrl.interrupt_kamehameha()
		_log_combat_event("[CONCENTRACIÓN ROTA] ¡Concentración rota! Técnica interrumpida.", "warning")


func _spawn_fizzle_vfx() -> void:
	var fizzle = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.50
	fizzle.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.85)
	fizzle.material_override = mat

	add_child(fizzle)
	fizzle.position = Vector3(0.0, 1.15, -0.32)

	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(fizzle, "scale", Vector3.ONE * 2.2, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(1.0, 0.1, 0.0, 0.0), 0.25)
	tween.chain().tween_callback(fizzle.queue_free)


func _trigger_poise_resisted_feedback(hit_direction: Vector3) -> void:
	var dir = hit_direction
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z

	# Pequeño retroceso firme de aguante
	apply_knockback(dir, 1.8)

	if procedural_animator:
		procedural_animator.trigger_hit_flinch(0.35, dir)

	if is_player:
		var origin = get_parent()
		if origin:
			for hand in ["LeftHand", "RightHand"]:
				var ctrl = origin.get_node_or_null(hand)
				if ctrl and ctrl.has_method("trigger_haptic_pulse"):
					ctrl.trigger_haptic_pulse("haptic", 110.0, 0.45, 0.09, 0.0)
		_log_combat_event("[SUPER ARMOR] ¡Aguantando la lluvia de ataques! Poise: %.0f/%.0f" % [current_charge_poise, max_charge_poise], "info")
	else:
		_log_combat_event("[SUPER ARMOR] ¡Goku aguanta los ataques mientras carga energía!", "info")


func take_hit(amount_np: float, hit_direction: Vector3 = Vector3.ZERO) -> void:
	# Punto 5: Si el luchador va volando en Melee Dash y recibe un ataque, evaluar interrupción por tipo y BP
	if is_flying_to_opponent and amount_np >= 10.0:
		var opp_d: Node3D = _get_opponent()
		var bp_shooter: float = maxf(float(opp_d.get("current_np")) if (opp_d and is_instance_valid(opp_d) and opp_d.get("current_np") != null) else 10000.0, 100.0)
		var bp_dasher: float = maxf(current_np, 100.0)
		var r_shoot_vs_dash: float = bp_shooter / bp_dasher
		if is_in_beam_sequence:
			_stop_flight()
		elif amount_np >= 350.0:
			# Ki Blast Cargado
			if bp_dasher >= bp_shooter * 1.5:
				amount_np *= 0.40 # Super Armor: sigue el dash
			else:
				_stop_flight()
				is_staggered = true
				stagger_timer = 0.35
		else:
			# Ki Blast Rápido
			if r_shoot_vs_dash >= 1.5:
				_stop_flight() # Corta el dash
			elif bp_dasher < bp_shooter * 1.5:
				_dash_speed_mult = 0.75
				amount_np *= 0.50
			else:
				amount_np *= 0.25

	# 1. Si está en postura de Guardia y no tiene la guardia rota, absorber con Bloqueo
	if is_blocking and not is_guard_broken and amount_np >= 10.0:
		block_hit(amount_np, hit_direction)
		return

	var old_np: float = current_np
	var active_max: float = get_active_max_np()

	# 2. Si está cargando un Super Poder, aplicar sistema canónico de Poise / Super Armor
	if is_charging_super and not is_staggered and amount_np >= 10.0:
		var poise_damage: float = amount_np * 0.75
		current_charge_poise -= poise_damage

		# Daño al BP mitigado al 50% mientras resiste la concentración
		var mitigated_damage: float = amount_np * 0.50
		var floor_limit_poise: float = maxf(active_max * secured_np_threshold_ratio, 100.0)
		current_np = maxf(current_np - mitigated_damage, floor_limit_poise)
		_regen_ki_from_damage(old_np - current_np)
		_notify_stats()
		_check_transformation_unlocks()
		if old_np - current_np >= 80.0:
			_spawn_bp_delta_popup(-(old_np - current_np), "")
		var opp_p: Node3D = _get_opponent()
		if opp_p and is_instance_valid(opp_p):
			check_zenkai_conditions(opp_p.current_np)
			if opp_p.has_method("check_zenkai_conditions"):
				opp_p.check_zenkai_conditions(current_np)

		if current_charge_poise <= 0.0:
			interrupt_charging_super()
			return
		else:
			_trigger_poise_resisted_feedback(hit_direction)
			return

	# 3. Recibir golpes disminuye nuestro BP/NP, pero nunca por debajo de los umbrales irreversibles asegurados (25%, 50%, 75%, 100%)
	var floor_limit: float = maxf(active_max * secured_np_threshold_ratio, 100.0)
	current_np = maxf(current_np - amount_np, floor_limit)
	_regen_ki_from_damage(old_np - current_np)
	_notify_stats()
	_check_transformation_unlocks()
	if old_np - current_np >= 80.0:
		_spawn_bp_delta_popup(-(old_np - current_np), "")
		if _hurt_voice_cooldown <= 0.0:
			_hurt_voice_cooldown = 0.60
			var hurt_suffix: String = "hurt_heavy" if amount_np >= 600.0 else "hurt_light"
			play_character_action_audio(hurt_suffix, true, "goku." + hurt_suffix)
	var opp_hit: Node3D = _get_opponent()
	if opp_hit and is_instance_valid(opp_hit):
		check_zenkai_conditions(opp_hit.current_np)
		if opp_hit.has_method("check_zenkai_conditions"):
			opp_hit.check_zenkai_conditions(current_np)

	# Solo aplicar retroceso físico a impactos reales (si sigue en dash por Super Armor no lo frenamos)
	if amount_np >= 10.0 and not is_flying_to_opponent:
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


## Absorbe el impacto reduciendo 85% del daño a cambio de Ki (Mecánica de Bloqueo / Guardia Cruzada)
func block_hit(amount_np: float, hit_direction: Vector3 = Vector3.ZERO) -> void:
	var ki_cost = clamp(amount_np * 0.03, 3.5, 18.0)
	var dir = hit_direction
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z

	if current_ki >= ki_cost:
		current_ki -= ki_cost
		_mark_ki_spent()

		# Daño al BP fuertemente mitigado (-85%)
		var old_np: float = current_np
		var mitigated_damage: float = amount_np * 0.15
		var active_max: float = get_active_max_np()
		var floor_limit: float = maxf(active_max * secured_np_threshold_ratio, 100.0)
		current_np = maxf(current_np - mitigated_damage, floor_limit)
		if old_np - current_np >= 80.0:
			_spawn_bp_delta_popup(-(old_np - current_np), "BLOQUEADO")
		
		# Recompensa mínima de BP (+20 BP), CERO Ki de ganancia (postura de contención pura)
		increase_np(20.0)
		_notify_stats()

		# Retroceso firme amortiguado
		apply_knockback(dir, 3.2)

		# Destello de escudo de choque de Ki
		_spawn_block_shield_vfx()

		if is_player:
			var origin = get_parent()
			if origin:
				for hand in ["LeftHand", "RightHand"]:
					var ctrl = origin.get_node_or_null(hand)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 140.0, 0.55, 0.12, 0.0)
			_log_combat_event("[GUARDIA] ¡Ataque bloqueado! Daño mitigado al BP (-85%%)", "info")
	else:
		# ¡GUARD BREAK! El Ki se agotó bloqueando
		current_ki = 0.0
		_notify_stats()
		is_blocking = false
		is_guard_broken = true
		guard_break_timer = 1.2

		# Daño parcial penetra la guardia (55% de daño al BP)
		var old_np_gb: float = current_np
		var break_damage: float = amount_np * 0.55
		current_np = maxf(current_np - break_damage, 100.0)
		_notify_stats()
		if old_np_gb - current_np >= 80.0:
			_spawn_bp_delta_popup(-(old_np_gb - current_np), "GUARDIA ROTA")

		apply_knockback(dir, 10.0)

		if is_player:
			var origin = get_parent()
			if origin:
				for hand in ["LeftHand", "RightHand"]:
					var ctrl = origin.get_node_or_null(hand)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 200.0, 1.0, 0.40, 0.0)
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
		_mark_ki_spent()
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
		_mark_ki_spent()
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
		if opp and is_instance_valid(opp):
			trigger_zenkai_match_finish(opp, self, "Agotamiento Vital")
		else:
			var winner_name = opp.character_data.character_name if (opp and opp.character_data) else "Rival"
			emit_signal("game_finished", winner_name)
		
	return { "success": true, "sacrificed_np": np_cost, "is_life_sacrifice": true }

func get_transformation_multiplier() -> float:
	if current_transformation and current_transformation.get("np_multiplier") != null:
		var m: float = float(current_transformation.np_multiplier)
		if m > 0.0:
			return m
	if current_transformation_index >= 0 and character_data and current_transformation_index < character_data.transformations.size():
		var trans: TransformationData = character_data.transformations[current_transformation_index]
		if trans and trans.np_multiplier > 0.0:
			return trans.np_multiplier
	return 1.0


func get_active_max_np() -> float:
	var base_max: float = character_data.max_np if character_data else 20000.0
	return base_max * get_transformation_multiplier()


func _format_bp_number(n: int) -> String:
	var neg: bool = n < 0
	var s: String = str(abs(n))
	var res: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count == 3 and i > 0:
			res = "," + res
			count = 0
	return ("-" + res) if neg else res


func _spawn_bp_delta_popup(delta_bp: float, custom_tag: String = "") -> void:
	if absf(delta_bp) < 80.0 and custom_tag == "":
		return
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam or not is_instance_valid(cam):
		return

	var lbl := Label3D.new()
	lbl.name = "BPDeltaPopup_" + str(Time.get_ticks_msec())
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.0020
	lbl.font_size = 28
	lbl.outline_size = 10
	lbl.render_priority = 115

	var int_delta: int = int(roundf(delta_bp))
	var sign_str: String = "+" if int_delta >= 0 else "-"
	var abs_str: String = _format_bp_number(abs(int_delta))
	var prefix_who: String = "TU BP" if is_player else "RIVAL BP"
	var tag_suffix: String = ("  %s" % custom_tag) if custom_tag != "" else ""
	if int_delta == 0 and custom_tag != "":
		lbl.text = "%s: %s" % [prefix_who, custom_tag]
	else:
		lbl.text = "%s: %s%s BP%s" % [prefix_who, sign_str, abs_str, tag_suffix]

	var col: Color = Color(0.25, 1.0, 0.45) if int_delta >= 0 else Color(1.0, 0.30, 0.28)
	if "TRANSFORMACI" in custom_tag:
		col = Color(1.0, 0.88, 0.18)
	lbl.modulate = col
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)

	get_tree().current_scene.add_child(lbl)
	var cam_basis: Basis = cam.global_transform.basis
	var cam_fwd: Vector3 = -cam_basis.z.normalized()
	var cam_right: Vector3 = cam_basis.x.normalized()
	var cam_up: Vector3 = cam_basis.y.normalized()
	var side_off: float = -0.30 if is_player else 0.30
	var jitter_y: float = randf_range(-0.04, 0.06)
	var start_pos: Vector3 = cam.global_position + cam_fwd * 1.65 + cam_right * side_off + cam_up * (0.20 + jitter_y)
	lbl.global_position = start_pos

	var tw: Tween = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position", start_pos + cam_up * 0.22, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.15).set_delay(0.30)
	tw.tween_property(lbl, "outline_modulate:a", 0.0, 1.15).set_delay(0.30)
	tw.chain().tween_callback(lbl.queue_free)


func increase_np(amount: float) -> void:
	var scaled_amount: float = amount * get_transformation_multiplier()
	if is_penalized:
		scaled_amount *= 0.25 # Penalización reduce drásticamente la ganancia de NP
	var active_max: float = get_active_max_np()
	var old_np: float = current_np
	current_np = minf(current_np + scaled_amount, active_max)
	_update_secured_threshold(active_max)
	_notify_stats()

	var delta_gained: float = current_np - old_np
	if delta_gained >= 80.0:
		_spawn_bp_delta_popup(delta_gained, "")
	elif delta_gained > 0.0:
		_pending_bp_popup_accum += delta_gained
		if _pending_bp_popup_accum >= 250.0 and _bp_popup_cooldown <= 0.0:
			_spawn_bp_delta_popup(_pending_bp_popup_accum, "")
			_pending_bp_popup_accum = 0.0
			_bp_popup_cooldown = 0.45

	var opp: Node3D = _get_opponent()
	if opp and is_instance_valid(opp):
		check_zenkai_conditions(opp.current_np)
		if opp.has_method("check_zenkai_conditions"):
			opp.check_zenkai_conditions(current_np)

## Ganancia de BP por recarga de Ki: solo sube hasta el techo de carga (60% del máximo activo).
## El resto del BP se gana peleando (golpes, desvíos, choques). Punto 8 del playtest.
func increase_np_from_charge(amount: float) -> void:
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var ceiling: float = get_active_max_np() * cfg.charge_bp_ceiling_ratio
	if current_np >= ceiling:
		return
	var effective_mult: float = maxf(get_transformation_multiplier() * (0.25 if is_penalized else 1.0), 0.001)
	var raw_allowed: float = minf(amount, (ceiling - current_np) / effective_mult)
	if raw_allowed <= 0.0:
		return
	increase_np(raw_allowed)


func _mark_ki_spent() -> void:
	_passive_regen_cooldown = KiEconomyConfig.get_default().passive_regen_delay_sec


func _process_passive_ki_regen(delta: float) -> void:
	if is_match_over or not character_data:
		return
	if _passive_regen_cooldown > 0.0:
		_passive_regen_cooldown -= delta
		return
	# Solo en Fase Libre: no cargando Super, no en melee/bullet-time, no recargando (esa ya tiene su tasa)
	if is_charging_super or is_firing_beam or is_in_beam_sequence or is_in_bullet_time or is_charging_ki:
		return
	if current_ki >= character_data.base_ki:
		return
	var regen: float = KiEconomyConfig.get_default().passive_ki_regen_per_sec * delta
	if is_penalized:
		regen *= 0.5
	current_ki = minf(current_ki + regen, character_data.base_ki)
	_passive_notify_accum += regen
	if _passive_notify_accum >= 1.0:
		_passive_notify_accum = 0.0
		_notify_stats()


func _regen_ki_from_damage(bp_lost: float) -> void:
	if bp_lost <= 0.0 or not character_data:
		return
	current_ki = minf(current_ki + bp_lost * KiEconomyConfig.get_default().ki_regen_per_bp_lost, character_data.base_ki)


func _update_secured_threshold(active_max: float) -> void:
	if active_max <= 0.0:
		return
	var ratio: float = current_np / active_max
	if ratio >= 1.0:
		# Al 100% el piso queda en 90% (configurable) para que el BP siga oscilando en combate
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, KiEconomyConfig.get_default().secured_floor_at_full)
	elif ratio >= 0.75:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.75)
	elif ratio >= 0.50:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.50)
	elif ratio >= 0.25:
		secured_np_threshold_ratio = max(secured_np_threshold_ratio, 0.25)

func check_zenkai_conditions(opponent_np: float) -> void:
	if is_match_over:
		return
	# Evitar recalcular si el Zenkai se activó por Comeback (ya que dura exactamente 1 ataque)
	if is_comeback_zenkai:
		return
	# No revocar Zenkai en medio de la carga o disparo de un Super Poder (ej: sacrificio de NP)
	if is_charging_super or is_firing_beam or is_in_beam_sequence:
		return
		
	var active_max: float = get_active_max_np()
		
	# Trigger 1: Brecha notable de NP a nuestro favor (+35% o >=85% del máximo activo superando al rival por +15%)
	var ratio_diff: float = (current_np - opponent_np) / maxf(active_max, 1.0)
	if ratio_diff >= 0.35 or (current_np >= active_max * 0.85 and current_np > opponent_np * 1.15):
		if not is_in_zenkai_state:
			is_in_zenkai_state = true
			emit_signal("zenkai_activated", "brecha")
			play_character_action_audio("common.zenkai_activate", false)
			_notify_stats()
	else:
		if is_in_zenkai_state:
			is_in_zenkai_state = false
			_notify_stats()

	_check_transformation_unlocks()

func trigger_comeback_zenkai() -> void:
	if not is_in_zenkai_state:
		is_in_zenkai_state = true
		is_comeback_zenkai = true
		emit_signal("zenkai_activated", "comeback")
		play_character_action_audio("common.furia_activate", false, "common.zenkai_activate")
		_notify_stats()
		_check_transformation_unlocks()
		print("[CharacterInstance] %s: ¡ZENKAI COMEBACK ACTIVADO! Tienes un ataque para liquidar o serás penalizado." % character_data.character_name)

func notify_attack_launched(p_power: Resource) -> void:
	# REQUISITO CANÓNICO: Si se lanza un Super Ataque de Ki durante el Follow-Up Bullet-Time, corta el tiempo
	if is_in_followup_bullet_time:
		var p_name = p_power.power_name.to_lower() if (p_power and "power_name" in p_power) else ""
		if not ("ki blast" in p_name):
			_end_followup_bullet_time(false)

	# Conservar is_in_zenkai_state activo mientras el Super Poder viaja para que el impacto ejecute el K.O. Zenkai.
	# Si era Comeback Zenkai y falla/es bloqueado o esquivado, notify_attack_failed() limpiará el estado.

func notify_attack_failed() -> void:
	is_in_zenkai_state = false
	is_comeback_zenkai = false
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

func unlock_transformation(form_name: String) -> void:
	if not unlocked_transformations.has(form_name):
		unlocked_transformations.append(form_name)
		emit_signal("transformation_unlocked", form_name)
		var char_name = character_data.character_name if character_data else name
		_log_combat_event("[TRANSFORMACIÓN] ¡%s ha despertado la transformación %s!" % [char_name, form_name], "success")
		print("[Transformation] %s desbloqueó: %s" % [char_name, form_name])

func is_transformation_unlocked(form_name: String) -> bool:
	return unlocked_transformations.has(form_name)

func _check_transformation_unlocks() -> void:
	if not character_data or character_data.transformations.is_empty():
		return
	
	var mult: float = get_transformation_multiplier()
	var active_max: float = character_data.max_np * mult
	var active_base: float = character_data.base_np * mult
	var climb_ratio: float = current_np / maxf(1.0, active_max)
	var damage_ratio: float = current_np / maxf(1.0, active_base)
	
	var opp = _get_opponent()
	var opp_np: float = opp.get("current_np") if (opp and is_instance_valid(opp) and opp.get("current_np") != null) else current_np
	var is_lagging_behind: bool = (opp_np - current_np) / maxf(1.0, current_np) >= 0.25
	
	# Desbloqueo Fase 1 (SSJ):
	# Se activa al escalar NP (>= 75% del máx), sufrir daño real (<= 78% del base) o estar en Furia (>= 25% atrás)
	var form_1: String = character_data.transformations[0].form_name
	if not is_transformation_unlocked(form_1):
		if climb_ratio >= 0.75 or damage_ratio <= 0.78 or is_lagging_behind:
			unlock_transformation(form_1)
	
	# Desbloqueo Fase 2 (Super Vegeta / SSJ2):
	# Se activa estando ya transformado en Fase 1+ al escalar NP (>= 85%), sufrir daño (<= 68%) o en Furia
	if character_data.transformations.size() > 1:
		var form_2: String = character_data.transformations[1].form_name
		if not is_transformation_unlocked(form_2):
			if current_transformation != null and (climb_ratio >= 0.85 or damage_ratio <= 0.68 or is_lagging_behind):
				unlock_transformation(form_2)
				
	# Desbloqueo Fase 3 (SSB / Forma Divina):
	# Se activa exclusivamente al alcanzar el Estado Zenkai
	if character_data.transformations.size() > 2:
		var form_3: String = character_data.transformations[2].form_name
		if not is_transformation_unlocked(form_3):
			if is_in_zenkai_state:
				unlock_transformation(form_3)

	# Desbloqueo Fase 4 (Cúspide x8.0: Ultra Instinto / Ultra Ego):
	# Se activa tras transformar en Fase 3+ con Estado Zenkai o umbral irreversible >= 75%
	if character_data.transformations.size() > 3:
		var form_4: String = character_data.transformations[3].form_name
		if not is_transformation_unlocked(form_4):
			if current_transformation_index >= 2 and (is_in_zenkai_state or secured_np_threshold_ratio >= 0.75):
				unlock_transformation(form_4)

func transform_to(index: int) -> void:
	if index >= 0 and index < character_data.transformations.size():
		var trans = character_data.transformations[index]
		if not is_transformation_unlocked(trans.form_name):
			var char_name = character_data.character_name if character_data else name
			print("[Transformation] %s intentó transformarse en %s pero AÚN NO ESTÁ DESBLOQUEADA." % [char_name, trans.form_name])
			_log_combat_event("[TRANSFORMACIÓN] %s bloqueada. ¡Aumenta tu furia en combate para despertarla!" % trans.form_name, "warning")
			return

		var prev_mult: float = _active_np_multiplier if _active_np_multiplier > 0.0 else 1.0
		current_transformation = trans
		current_transformation_index = index
		var new_mult: float = trans.np_multiplier if trans.np_multiplier > 0.0 else 1.0
		_active_np_multiplier = new_mult
		var old_np: float = current_np
		var ratio_mult: float = new_mult / prev_mult
		current_np = clampf(current_np * ratio_mult, 1000.0, get_active_max_np())

		# Desbloquear técnicas de esta fase
		for power in character_data.powers:
			if power.unlock_requirement_transformation == trans.form_name:
				if not unlocked_powers.has(power.power_name):
					unlocked_powers.append(power.power_name)
					emit_signal("power_unlocked", power.power_name)

		emit_signal("transformed", trans)
		_notify_stats()
		_update_aura_visuals()
		_spawn_bp_delta_popup(current_np - old_np, "¡%s x%.1f!" % [trans.form_name.to_upper(), new_mult])

		var opp: Node3D = _get_opponent()
		if opp and is_instance_valid(opp):
			check_zenkai_conditions(opp.current_np)
			if opp.has_method("check_zenkai_conditions"):
				opp.check_zenkai_conditions(current_np)

		# Feedback cinemático y onda expansiva de transformación
		if procedural_animator and procedural_animator.has_method("trigger_transformation_roar"):
			procedural_animator.trigger_transformation_roar()
		_spawn_melee_shockwave(global_position + Vector3(0, 1.0, 0))
		var trans_suffix: String = "kaioken" if "kaioken" in trans.form_name.to_lower() else "transform_ssj"
		play_character_action_audio(trans_suffix, true, "goku." + trans_suffix)
		play_character_action_audio("common.aura_burst", false)
		var char_name = character_data.character_name if character_data else name
		_log_combat_event("[TRANSFORMACIÓN] ¡%s se ha transformado en %s! (NP x%.1f -> BP %s)" % [char_name, trans.form_name, new_mult, _format_bp_number(int(current_np))], "success")

func revert_to_base() -> void:
	if current_transformation == null:
		return
	var char_name = character_data.character_name if character_data else ""
	# Excepción canónica: personajes como Freezer no se destransforman por agotamiento de Ki
	if char_name == "Freezer" or char_name == "Frieza":
		return
	print("[CharacterInstance] %s: ¡Ki agotado! Destransformación forzada al estado base." % char_name)
	var prev_mult: float = _active_np_multiplier if _active_np_multiplier > 0.0 else 1.0
	current_transformation = null
	current_transformation_index = -1
	_active_np_multiplier = 1.0
	var old_np: float = current_np
	if prev_mult > 1.0:
		current_np = clampf(current_np / prev_mult, 1000.0, get_active_max_np())
	emit_signal("transformed", null)
	_notify_stats()
	_update_aura_visuals()
	if absf(current_np - old_np) >= 50.0:
		_spawn_bp_delta_popup(current_np - old_np, "FORMA BASE")
	var opp: Node3D = _get_opponent()
	if opp and is_instance_valid(opp):
		check_zenkai_conditions(opp.current_np)
		if opp.has_method("check_zenkai_conditions"):
			opp.check_zenkai_conditions(current_np)

func is_power_usable(power: Resource) -> bool:
	if is_penalized and not is_in_zenkai_state:
		return false
	# En Estado Zenkai se exime todo bloqueo de transformación para permitir lanzar cualquier Super Poder
	if is_in_zenkai_state:
		return true
	# 1. ¿Está desbloqueado o es técnica base?
	var is_unlocked = unlocked_powers.has(power.power_name) or power.unlock_requirement_transformation == ""
	if not is_unlocked:
		return false
	# 2. ¿Prohibido en esta forma?
	if current_transformation and power.forbidden_transformations.has(current_transformation.form_name):
		return false
	# 3. Super Poderes y Finishers ejecutables con Ki o mediante Último Aliento (Fuerza Vital)
	return true

func execute_finisher_hit(power: Resource) -> void:
	if power and power.is_finisher:
		var opp: Node3D = _get_opponent()
		var p_name: String = power.power_name if "power_name" in power else "Finisher"
		trigger_zenkai_match_finish(self, opp, p_name)


func trigger_zenkai_match_finish(winner: Node3D, loser: Node3D, tech_name: String) -> void:
	if is_match_over:
		return
	Engine.time_scale = 1.0
	is_match_over = true
	is_charging_super = false
	is_firing_beam = false
	if cached_ai_controller and is_instance_valid(cached_ai_controller):
		cached_ai_controller.set("enabled", false)

	if loser and is_instance_valid(loser):
		loser.set("is_match_over", true)
		loser.set("is_charging_super", false)
		loser.set("is_firing_beam", false)
		loser.set("current_ki", 0.0)
		if loser.has_method("stop_charging_super"):
			loser.stop_charging_super()
		var loser_ai: Node = loser.get("cached_ai_controller")
		if loser_ai and is_instance_valid(loser_ai):
			loser_ai.set("enabled", false)
		var knock_dir: Vector3 = (loser.global_position - global_position).normalized()
		if knock_dir.length_squared() < 0.01:
			knock_dir = Vector3.BACK
		if loser.has_method("start_ragdoll"):
			loser.start_ragdoll(knock_dir * 16.0)
		loser.set("ragdoll_recovery_timer", -1.0)
		if loser.has_method("_notify_stats"):
			loser._notify_stats()

	var w_name: String = character_data.character_name if character_data else name
	if winner and is_instance_valid(winner) and winner.get("character_data"):
		var w_data: Resource = winner.get("character_data")
		if w_data and "character_name" in w_data:
			w_name = w_data.character_name
	emit_signal("game_finished", w_name)
	emit_signal("match_finished", winner, loser, tech_name)
	play_character_action_audio("common.ko_finisher", false)
	if winner and is_instance_valid(winner) and winner.has_method("play_character_action_audio"):
		winner.play_character_action_audio("victory", true, "goku.victory")

	# Limpiar domos melee activos y proyectiles en vuelo al concluir el combate
	is_in_bullet_time = false
	is_in_followup_bullet_time = false
	if active_target_dome and is_instance_valid(active_target_dome):
		active_target_dome.queue_free()
		active_target_dome = null
	var tree_fin: SceneTree = get_tree()
	if tree_fin:
		for proj in tree_fin.get_nodes_in_group("ki_projectiles"):
			if is_instance_valid(proj):
				proj.queue_free()
		var player_node: Node3D = self if is_player else (loser if (loser and bool(loser.get("is_player"))) else winner)
		var res_timer: SceneTreeTimer = tree_fin.create_timer(2.4)
		res_timer.timeout.connect(func() -> void:
			if is_instance_valid(self) and get_tree():
				MatchResultScreen.spawn_result_screen(get_tree(), winner, loser, tech_name, player_node)
		)
	_spawn_zenkai_finish_banner(winner, loser, tech_name)


func _spawn_zenkai_finish_banner(winner: Node3D, _loser: Node3D, tech_name: String) -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if not cam or not is_instance_valid(cam):
		return

	var w_name: String = character_data.character_name if character_data else name
	if winner and is_instance_valid(winner) and winner.get("character_data"):
		var w_data: Resource = winner.get("character_data")
		if w_data and "character_name" in w_data:
			w_name = w_data.character_name

	var banner := Label3D.new()
	banner.name = "ZenkaiMatchFinishBanner"
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.no_depth_test = true
	banner.render_priority = 120
	banner.pixel_size = 0.0022
	banner.font_size = 34
	banner.outline_size = 10
	banner.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	var winner_is_player: bool = (winner == self and is_player) or (winner != null and is_instance_valid(winner) and bool(winner.get("is_player")))
	banner.modulate = Color(1.0, 0.88, 0.15) if winner_is_player else Color(1.0, 0.22, 0.25)
	banner.text = "🏆 ¡K.O. ZENKAI DEFINITIVO! 🏆\nGANADOR: %s\nTécnica Final: %s\n[Usa el Menú (☰) para Reiniciar Combate]" % [w_name.to_upper(), tech_name.to_upper()]

	var parent_node: Node = tree.current_scene if tree.current_scene else self
	parent_node.add_child(banner)

	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	banner.global_position = cam.global_position + fwd * 1.70 + Vector3(0.0, 0.08, 0.0)

	var finish_timer: SceneTreeTimer = tree.create_timer(8.0)
	finish_timer.timeout.connect(func() -> void:
		if is_instance_valid(banner):
			banner.queue_free()
	)

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
		var opp = _get_opponent()
		if opp:
			is_target_locked = true
		else:
			_log_combat_event("⚠️ ¡Debes fijar al rival con la mirada antes de embestir!", "warning")
			var my_origin = get_parent()
			if my_origin:
				for hand in ["LeftHand", "RightHand"]:
					var ctrl = my_origin.get_node_or_null(hand)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 120.0, 0.65, 0.22, 0.0)
			return
	var opp_f: Node3D = _get_opponent()
	var bp_atk_f: float = maxf(current_np, 100.0)
	var bp_def_f: float = maxf(float(opp_f.get("current_np")) if (opp_f and is_instance_valid(opp_f) and opp_f.get("current_np") != null) else 10000.0, 100.0)
	flight_speed = clampf(18.0 * sqrt(bp_atk_f / bp_def_f), 13.0, 26.0)
	_dash_speed_mult = 1.0
	is_flying_to_opponent = true
	_set_dash_vfx_visible(true)
	_update_aura_visuals()
	play_character_action_audio("common.dash_fly", false, "common.dodge_vanish")
	print("[CharacterInstance] %s: Iniciando vuelo rápido (%.1f m/s)." % [character_data.character_name, flight_speed])

func _stop_flight() -> void:
	is_flying_to_opponent = false
	_dash_speed_mult = 1.0
	_set_dash_vfx_visible(false)
	_update_aura_visuals()
	print("[CharacterInstance] %s: Vuelo finalizado a distancia de melee." % character_data.character_name)
	
	# Si somos el jugador, loguear la llegada en el GSS
	if is_player:
		var gss = get_tree().root.find_child("GesturePhaseTree", true, false)
		if gss:
			gss.emit_signal("gesture_logged", "[Melee] ¡Llegada al oponente a distancia de Melee!", "success")
			gss.emit_signal("phase_changed", "DISTANCIA DE MELEE")


func _set_dash_vfx_visible(show_vfx: bool) -> void:
	if not is_player:
		return
	if show_vfx:
		if _dash_vfx_ring == null or not is_instance_valid(_dash_vfx_ring):
			var orig: Node = get_parent()
			var cam: Camera3D = orig.get_node_or_null("XRCamera3D") as Camera3D if orig else null
			if cam:
				_dash_vfx_ring = MeshInstance3D.new()
				_dash_vfx_ring.name = "MeleeDashSpeedLines"
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.65
				cyl.bottom_radius = 1.15
				cyl.height = 1.8
				cyl.radial_segments = 24
				cyl.cap_top = false
				cyl.cap_bottom = false
				_dash_vfx_ring.mesh = cyl
				var mat := StandardMaterial3D.new()
				mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
				mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
				mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.albedo_color = Color(0.75, 0.92, 1.0, 0.16)
				_dash_vfx_ring.material_override = mat
				_dash_vfx_ring.rotation.x = PI * 0.5
				_dash_vfx_ring.position = Vector3(0.0, 0.0, -0.95)
				cam.add_child(_dash_vfx_ring)
		if _dash_vfx_ring and is_instance_valid(_dash_vfx_ring):
			_dash_vfx_ring.visible = true
	else:
		if _dash_vfx_ring and is_instance_valid(_dash_vfx_ring):
			_dash_vfx_ring.visible = false

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


## Auto-calibración universal del rig en reposo (agnóstico a Goku -90° X y Vegeta +Y up)
func _calibrate_skeleton_rig() -> void:
	_rig_calibrated = false
	_finger_curl_cache.clear()
	if not skeleton:
		return

	var spine_idx: int = skeleton.find_bone("Spine")
	if spine_idx == -1:
		spine_idx = skeleton.find_bone("Hips")
	var neck_idx: int = neck_bone_idx if neck_bone_idx != -1 else skeleton.find_bone("Head")

	if spine_idx != -1 and neck_idx != -1 and left_arm_idx != -1 and right_arm_idx != -1:
		var spine_p: Vector3 = skeleton.get_bone_global_rest(spine_idx).origin
		var neck_p: Vector3 = skeleton.get_bone_global_rest(neck_idx).origin
		var skel_up: Vector3 = (neck_p - spine_p).normalized()
		if skel_up.length_squared() < 0.001:
			skel_up = Vector3.UP

		var l_arm_p: Vector3 = skeleton.get_bone_global_rest(left_arm_idx).origin
		var r_arm_p: Vector3 = skeleton.get_bone_global_rest(right_arm_idx).origin
		var span: Vector3 = l_arm_p - r_arm_p
		var skel_left: Vector3 = (span - skel_up * span.dot(skel_up)).normalized()
		if skel_left.length_squared() < 0.001:
			skel_left = Vector3.RIGHT
		var skel_fwd: Vector3 = skel_left.cross(skel_up).normalized()
		_skel_char_basis = Basis(skel_left, skel_up, skel_fwd).orthonormalized()
	else:
		_skel_char_basis = Basis.IDENTITY

	if left_arm_idx != -1 and left_forearm_idx != -1 and left_hand_idx != -1:
		var l1: float = (skeleton.get_bone_global_rest(left_forearm_idx).origin - skeleton.get_bone_global_rest(left_arm_idx).origin).length()
		var l2: float = (skeleton.get_bone_global_rest(left_hand_idx).origin - skeleton.get_bone_global_rest(left_forearm_idx).origin).length()
		_arm_reach_left_skel = maxf(l1 + l2, 0.05)

	if right_arm_idx != -1 and right_forearm_idx != -1 and right_hand_idx != -1:
		var r1: float = (skeleton.get_bone_global_rest(right_forearm_idx).origin - skeleton.get_bone_global_rest(right_arm_idx).origin).length()
		var r2: float = (skeleton.get_bone_global_rest(right_hand_idx).origin - skeleton.get_bone_global_rest(right_forearm_idx).origin).length()
		_arm_reach_right_skel = maxf(r1 + r2, 0.05)

	_left_hand_align_basis = _compute_hand_align_basis("Left", left_hand_idx)
	_right_hand_align_basis = _compute_hand_align_basis("Right", right_hand_idx)
	_build_finger_curl_cache("Left")
	_build_finger_curl_cache("Right")
	_rig_calibrated = true


func _compute_hand_align_basis(prefix: String, hand_idx: int) -> Basis:
	if not skeleton or hand_idx == -1:
		return Basis.IDENTITY
	var is_left: bool = (prefix == "Left")
	var hand_grest: Transform3D = skeleton.get_bone_global_rest(hand_idx)
	var hand_pos: Vector3 = hand_grest.origin
	var hand_rot_inv: Basis = hand_grest.basis.orthonormalized().inverse()
	var skel_up: Vector3 = _skel_char_basis.y

	var idx1: int = skeleton.find_bone(prefix + "Index1")
	if idx1 == -1: idx1 = skeleton.find_bone(prefix + "IndexProximal")
	var mid1: int = skeleton.find_bone(prefix + "Middle1")
	if mid1 == -1: mid1 = skeleton.find_bone(prefix + "MiddleProximal")
	var pnk1: int = skeleton.find_bone(prefix + "Pinky1")
	if pnk1 == -1: pnk1 = skeleton.find_bone(prefix + "PinkyProximal")

	if idx1 == -1 or mid1 == -1 or pnk1 == -1:
		if is_left:
			return Basis(Vector3(-0.605083, 0.0, -0.796162), Vector3(-0.796162, 0.0, 0.605083), Vector3(0.0, 1.0, 0.0))
		return Basis(Vector3(-0.605083, 0.0, 0.796162), Vector3(0.796162, 0.0, 0.605083), Vector3(0.0, 1.0, 0.0))

	var finger_dir_skel: Vector3 = (skeleton.get_bone_global_rest(mid1).origin - hand_pos).normalized()
	var raw_thumb_skel: Vector3 = skeleton.get_bone_global_rest(idx1).origin - skeleton.get_bone_global_rest(pnk1).origin
	var thumb_skel: Vector3 = (raw_thumb_skel - finger_dir_skel * raw_thumb_skel.dot(finger_dir_skel)).normalized()
	var palm_in_skel: Vector3 = finger_dir_skel.cross(thumb_skel).normalized()
	if palm_in_skel.dot(-skel_up) < 0.0:
		palm_in_skel = -palm_in_skel

	var f_loc: Vector3 = (hand_rot_inv * finger_dir_skel).normalized()
	var t_loc: Vector3 = (hand_rot_inv * thumb_skel).normalized()
	var p_loc: Vector3 = (hand_rot_inv * palm_in_skel).normalized()
	var x_loc: Vector3 = p_loc if is_left else -p_loc
	return Basis(x_loc, t_loc, -f_loc).orthonormalized().inverse()


func _build_finger_curl_cache(prefix: String) -> void:
	if not skeleton:
		return
	var hand_idx: int = skeleton.find_bone(prefix + "Hand")
	var idx1: int = skeleton.find_bone(prefix + "Index1")
	var pnk1: int = skeleton.find_bone(prefix + "Pinky1")
	var skel_up: Vector3 = _skel_char_basis.y
	var n_palm_skel: Vector3 = -skel_up
	if hand_idx != -1 and idx1 != -1 and pnk1 != -1:
		var v_idx: Vector3 = skeleton.get_bone_global_rest(idx1).origin - skeleton.get_bone_global_rest(hand_idx).origin
		var v_pnk: Vector3 = skeleton.get_bone_global_rest(pnk1).origin - skeleton.get_bone_global_rest(hand_idx).origin
		var cross_p: Vector3 = v_idx.cross(v_pnk)
		if cross_p.length_squared() > 0.000001:
			n_palm_skel = cross_p.normalized()
			if n_palm_skel.dot(-skel_up) < 0.0:
				n_palm_skel = -n_palm_skel

	var finger_data: Dictionary = {}
	var finger_names: Array[String] = ["Index", "Middle", "Ring", "Pinky", "Thumb"]
	for fname in finger_names:
		var b1: int = skeleton.find_bone(prefix + fname + "1")
		var b2: int = skeleton.find_bone(prefix + fname + "2")
		var b3: int = skeleton.find_bone(prefix + fname + "3")
		if b1 == -1: b1 = skeleton.find_bone(prefix + fname + "Proximal")
		if b2 == -1: b2 = skeleton.find_bone(prefix + fname + "Intermediate")
		if b3 == -1: b3 = skeleton.find_bone(prefix + fname + "Distal")

		var curl_local: Vector3 = Vector3(0.0, 0.0, -1.0 if prefix == "Left" else 1.0)
		var opp_local: Vector3 = Vector3(0.0, 1.0 if prefix == "Left" else -1.0, 0.0)
		var rest_1: Quaternion = Quaternion.IDENTITY
		var rest_2: Quaternion = Quaternion.IDENTITY
		var rest_3: Quaternion = Quaternion.IDENTITY

		if b1 != -1:
			rest_1 = skeleton.get_bone_rest(b1).basis.orthonormalized().get_rotation_quaternion()
		if b2 != -1:
			rest_2 = skeleton.get_bone_rest(b2).basis.orthonormalized().get_rotation_quaternion()
		if b3 != -1:
			rest_3 = skeleton.get_bone_rest(b3).basis.orthonormalized().get_rotation_quaternion()

		if b1 != -1 and b2 != -1:
			var f_dir_skel: Vector3 = (skeleton.get_bone_global_rest(b2).origin - skeleton.get_bone_global_rest(b1).origin).normalized()
			var r_b1_inv: Basis = skeleton.get_bone_global_rest(b1).basis.orthonormalized().inverse()
			if fname == "Thumb" and idx1 != -1 and pnk1 != -1:
				var across: Vector3 = (skeleton.get_bone_global_rest(pnk1).origin - skeleton.get_bone_global_rest(idx1).origin).normalized()
				var thumb_target: Vector3 = (across * 0.7 + n_palm_skel * 0.7).normalized()
				var c_skel: Vector3 = f_dir_skel.cross(thumb_target)
				if c_skel.length_squared() > 0.0001:
					curl_local = (r_b1_inv * c_skel.normalized()).normalized()
				var opp_skel: Vector3 = f_dir_skel.cross(across)
				if opp_skel.length_squared() > 0.0001:
					opp_local = (r_b1_inv * opp_skel.normalized()).normalized()
			else:
				var c_skel: Vector3 = f_dir_skel.cross(n_palm_skel)
				if c_skel.length_squared() > 0.0001:
					curl_local = (r_b1_inv * c_skel.normalized()).normalized()

		finger_data[fname] = {
			"b1": b1, "b2": b2, "b3": b3,
			"rest_1": rest_1, "rest_2": rest_2, "rest_3": rest_3,
			"curl_axis": curl_local,
			"opp_axis": opp_local
		}
	_finger_curl_cache[prefix] = finger_data


func get_skel_char_basis() -> Basis:
	return _skel_char_basis


## Convierte una rotación de Euler en espacio canónico de personaje (+X=Izq, +Y=Arriba, +Z=Frente) al espacio local del hueso
func get_bone_rotation_char_space(bone_idx: int, euler_char: Vector3) -> Quaternion:
	if not skeleton or bone_idx == -1:
		return Quaternion.IDENTITY
	var bone_grest_basis: Basis = skeleton.get_bone_global_rest(bone_idx).basis.orthonormalized()
	var bone_rest_quat: Quaternion = skeleton.get_bone_rest(bone_idx).basis.orthonormalized().get_rotation_quaternion()
	var offset_char_basis: Basis = Basis.from_euler(euler_char)
	var skel_delta: Basis = _skel_char_basis * offset_char_basis * _skel_char_basis.inverse()
	var local_delta: Quaternion = (bone_grest_basis.inverse() * skel_delta * bone_grest_basis).get_rotation_quaternion()
	return (bone_rest_quat * local_delta).normalized()


## Resuelve IK del brazo desde posiciones y rotaciones expresadas en espacio canónico de personaje (en metros respecto al hombro)
func solve_character_arm_ik_local(is_left: bool, hand_offset_from_shoulder_m: Vector3, hand_euler_char: Vector3) -> void:
	solve_character_arm_ik_basis(is_left, hand_offset_from_shoulder_m, Basis.from_euler(hand_euler_char))


## Sobrecarga directa con Basis en espacio canónico de personaje (+X=Izq, +Y=Arriba, +Z=Frente)
func solve_character_arm_ik_basis(is_left: bool, hand_offset_from_shoulder_m: Vector3, hand_basis_char: Basis) -> void:
	if not skeleton or not _rig_calibrated:
		return
	var s_idx: int = left_arm_idx if is_left else right_arm_idx
	var f_idx: int = left_forearm_idx if is_left else right_forearm_idx
	var h_idx: int = left_hand_idx if is_left else right_hand_idx
	if s_idx == -1 or f_idx == -1 or h_idx == -1:
		return
	var reach_skel: float = _arm_reach_left_skel if is_left else _arm_reach_right_skel
	var scale_to_skel: float = reach_skel / 0.56
	var s_origin_skel: Vector3 = skeleton.get_bone_global_rest(s_idx).origin
	var target_skel_pos: Vector3 = s_origin_skel + (_skel_char_basis * hand_offset_from_shoulder_m) * scale_to_skel
	var target_basis_skel: Basis = (_skel_char_basis * hand_basis_char).orthonormalized()
	_solve_arm_ik_skel(s_idx, f_idx, h_idx, target_skel_pos, target_basis_skel, is_left)


func _safe_from_to_quat(from_dir: Vector3, to_dir: Vector3, fallback_axis: Vector3) -> Quaternion:
	var a: Vector3 = from_dir.normalized()
	var b: Vector3 = to_dir.normalized()
	var d: float = a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var ax: Vector3 = fallback_axis
		if ax.length_squared() < 0.0001 or absf(ax.normalized().dot(a)) > 0.98:
			ax = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a, b)


## Algoritmo analítico de 2 huesos (Hombro -> Codo -> Mano) en coordenadas globales para VR
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
	var skel_inv: Transform3D = skeleton.global_transform.affine_inverse()
	var target_skel: Vector3 = skel_inv * target_global_pos
	var target_basis_skel: Basis = (skel_inv.basis * target_global_basis).orthonormalized()
	_solve_arm_ik_skel(shoulder_idx, forearm_idx, hand_idx, target_skel, target_basis_skel, is_left)


## Núcleo IK jerárquico de 2 pasos: sin flips antipodales + pole vector continuo + reparto de pronación 50/50
func _solve_arm_ik_skel(
	shoulder_idx: int,
	forearm_idx: int,
	hand_idx: int,
	target_skel: Vector3,
	target_basis_skel: Basis,
	is_left: bool
) -> void:
	var s_rest: Vector3 = skeleton.get_bone_global_rest(shoulder_idx).origin
	var e_rest: Vector3 = skeleton.get_bone_global_rest(forearm_idx).origin
	var w_rest: Vector3 = skeleton.get_bone_global_rest(hand_idx).origin

	var upper_rest_vec: Vector3 = e_rest - s_rest
	var lower_rest_vec: Vector3 = w_rest - e_rest
	var L1: float = upper_rest_vec.length()
	var L2: float = lower_rest_vec.length()
	if L1 < 0.0001 or L2 < 0.0001:
		return

	var v: Vector3 = target_skel - s_rest
	var min_d: float = maxf(0.10 * (L1 + L2), absf(L1 - L2) + 0.005 * (L1 + L2))
	var d: float = clampf(v.length(), min_d, (L1 + L2) * 0.992)
	var v_dir: Vector3 = v.normalized() if v.length_squared() > 0.000001 else _skel_char_basis.z

	# Ley de cosenos para ángulo de apertura del triángulo Hombro-Codo-Muñeca
	var cos_alpha: float = clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var alpha: float = acos(cos_alpha)

	# Pole vector continuo en espacio de personaje -> Skeleton3D (codos afuera/abajo/atrás, sin saltos)
	var v_char: Vector3 = _skel_char_basis.inverse() * v_dir
	var side_sign: float = 1.0 if is_left else -1.0
	var pole_char: Vector3 = Vector3(
		side_sign * 0.65,
		-0.60 - clampf(v_char.y, -0.4, 0.6) * 0.15,
		-0.45 - clampf(v_char.z, -0.3, 0.5) * 0.20
	).normalized()
	var pole_skel: Vector3 = (_skel_char_basis * pole_char).normalized()

	var bend_proj: Vector3 = pole_skel - v_dir * pole_skel.dot(v_dir)
	if bend_proj.length_squared() < 0.0001:
		bend_proj = v_dir.cross(_skel_char_basis.x)
		if bend_proj.length_squared() < 0.0001:
			bend_proj = v_dir.cross(_skel_char_basis.y)
	var bend_dir: Vector3 = bend_proj.normalized()
	var elbow_target: Vector3 = s_rest + v_dir * (L1 * cos_alpha) + bend_dir * (L1 * sin(alpha))

	# Paso 1: Rotación jerárquica del hombro (soporta huesos rest no-identidad como Goku)
	var rest_upper_dir: Vector3 = upper_rest_vec.normalized()
	var des_upper_dir: Vector3 = (elbow_target - s_rest).normalized()
	var hinge_fallback: Vector3 = _skel_char_basis.z
	var q_shoulder_delta: Quaternion = _safe_from_to_quat(rest_upper_dir, des_upper_dir, hinge_fallback)

	var R_arm_grest: Basis = skeleton.get_bone_global_rest(shoulder_idx).basis.orthonormalized()
	var R_arm_desired: Basis = (Basis(q_shoulder_delta) * R_arm_grest).orthonormalized()
	var arm_parent: int = skeleton.get_bone_parent(shoulder_idx)
	var R_arm_parent_cur: Basis = skeleton.get_bone_global_pose(arm_parent).basis.orthonormalized() if arm_parent != -1 else Basis.IDENTITY
	var q_shoulder_local: Quaternion = (R_arm_parent_cur.inverse() * R_arm_desired).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(shoulder_idx, q_shoulder_local)

	# Paso 2: Flexión jerárquica de bisagra en el codo (desde el antebrazo ya rotado por el hombro -> cero flip 180°)
	var rest_lower_dir: Vector3 = lower_rest_vec.normalized()
	var current_lower_dir: Vector3 = (q_shoulder_delta * rest_lower_dir).normalized()
	var des_lower_dir: Vector3 = (target_skel - elbow_target).normalized()
	var elbow_axis_hint: Vector3 = des_upper_dir.cross(bend_dir).normalized()
	var q_elbow_hinge: Quaternion = _safe_from_to_quat(current_lower_dir, des_lower_dir, elbow_axis_hint)
	var q_forearm_delta_base: Quaternion = (q_elbow_hinge * q_shoulder_delta).normalized()

	var R_forearm_grest: Basis = skeleton.get_bone_global_rest(forearm_idx).basis.orthonormalized()
	var R_forearm_base: Basis = (Basis(q_forearm_delta_base) * R_forearm_grest).orthonormalized()

	# Paso 3: Descomposición Swing-Twist de la muñeca y reparto anatómico 50% ForeArm / 50% Hand
	var align_basis: Basis = _left_hand_align_basis if is_left else _right_hand_align_basis
	var R_hand_desired: Basis = (target_basis_skel * align_basis).orthonormalized()
	var R_hand_grest: Basis = skeleton.get_bone_global_rest(hand_idx).basis.orthonormalized()
	var R_hand_rel_rest: Basis = R_forearm_grest.inverse() * R_hand_grest
	var R_hand_base: Basis = R_forearm_base * R_hand_rel_rest

	var q_wrist_total: Quaternion = (R_hand_desired * R_hand_base.inverse()).get_rotation_quaternion()
	var q_vec: Vector3 = Vector3(q_wrist_total.x, q_wrist_total.y, q_wrist_total.z)
	var proj_twist: Vector3 = des_lower_dir * q_vec.dot(des_lower_dir)
	var q_twist: Quaternion = Quaternion(proj_twist.x, proj_twist.y, proj_twist.z, q_wrist_total.w)
	var twist_angle: float = 0.0
	if q_twist.length_squared() > 0.00001:
		q_twist = q_twist.normalized()
		if q_twist.w < 0.0:
			q_twist = -q_twist
		var sin_half: float = Vector3(q_twist.x, q_twist.y, q_twist.z).dot(des_lower_dir)
		twist_angle = clampf(2.0 * atan2(sin_half, q_twist.w), -deg_to_rad(135.0), deg_to_rad(135.0))

	var q_forearm_twist: Quaternion = Quaternion(des_lower_dir, twist_angle * 0.5)
	var R_forearm_final: Basis = (Basis(q_forearm_twist) * R_forearm_base).orthonormalized()
	var q_forearm_local: Quaternion = (R_arm_desired.inverse() * R_forearm_final).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(forearm_idx, q_forearm_local)

	var q_hand_local: Quaternion = (R_forearm_final.inverse() * R_hand_desired).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(hand_idx, q_hand_local)


## Aplica flexión reactiva de dedos con ejes calibrados y caché sin allocs por frame
func _apply_finger_curls_to_skeleton(skel: Skeleton3D, prefix: String, trigger: float, grip: float) -> void:
	if not skel:
		return

	var eff_grip: float = clampf(grip, 0.0, 1.0)
	var eff_trig: float = clampf(trigger, 0.0, 1.0)

	var bend_mid_j1: float = 0.28 + eff_grip * 0.45
	var bend_mid_j2: float = 0.32 + eff_grip * 0.55
	var bend_mid_j3: float = 0.22 + eff_grip * 0.40
	var bend_idx_j1: float = 0.16 + eff_trig * 0.52
	var bend_idx_j2: float = 0.20 + eff_trig * 0.62
	var bend_idx_j3: float = 0.14 + eff_trig * 0.48
	var thumb_val: float = clampf(eff_trig * 0.45 + eff_grip * 0.55, 0.0, 1.0)
	var th_bend_1: float = 0.12 + thumb_val * 0.35
	var th_bend_2: float = 0.16 + thumb_val * 0.42
	var th_bend_3: float = 0.14 + thumb_val * 0.38

	if skel == skeleton and _finger_curl_cache.has(prefix):
		var side_cache: Dictionary = _finger_curl_cache[prefix]
		for fname in ["Middle", "Ring", "Pinky"]:
			var d_f: Dictionary = side_cache[fname]
			var ax: Vector3 = d_f["curl_axis"]
			if d_f["b1"] != -1: skel.set_bone_pose_rotation(d_f["b1"], d_f["rest_1"] * Quaternion(ax, bend_mid_j1))
			if d_f["b2"] != -1: skel.set_bone_pose_rotation(d_f["b2"], d_f["rest_2"] * Quaternion(ax, bend_mid_j2))
			if d_f["b3"] != -1: skel.set_bone_pose_rotation(d_f["b3"], d_f["rest_3"] * Quaternion(ax, bend_mid_j3))

		var d_i: Dictionary = side_cache["Index"]
		var ax_i: Vector3 = d_i["curl_axis"]
		if d_i["b1"] != -1: skel.set_bone_pose_rotation(d_i["b1"], d_i["rest_1"] * Quaternion(ax_i, bend_idx_j1))
		if d_i["b2"] != -1: skel.set_bone_pose_rotation(d_i["b2"], d_i["rest_2"] * Quaternion(ax_i, bend_idx_j2))
		if d_i["b3"] != -1: skel.set_bone_pose_rotation(d_i["b3"], d_i["rest_3"] * Quaternion(ax_i, bend_idx_j3))

		var d_t: Dictionary = side_cache["Thumb"]
		var ax_tc: Vector3 = d_t["curl_axis"]
		var ax_to: Vector3 = d_t["opp_axis"]
		if d_t["b1"] != -1: skel.set_bone_pose_rotation(d_t["b1"], d_t["rest_1"] * Quaternion(ax_tc, th_bend_1) * Quaternion(ax_to, 0.20 + thumb_val * 0.30))
		if d_t["b2"] != -1: skel.set_bone_pose_rotation(d_t["b2"], d_t["rest_2"] * Quaternion(ax_tc, th_bend_2))
		if d_t["b3"] != -1: skel.set_bone_pose_rotation(d_t["b3"], d_t["rest_3"] * Quaternion(ax_tc, th_bend_3))
		return

	# Fallback por si se llama en esqueleto de mano independiente
	var is_left: bool = (prefix == "Left")
	var curl_axis: Vector3 = Vector3(0.0, 0.0, -1.0 if is_left else 1.0)
	var thumb_opp_axis: Vector3 = Vector3(0.0, 1.0 if is_left else -1.0, 0.0)
	var rot_j1: Quaternion = Quaternion(curl_axis, bend_mid_j1)
	var rot_j2: Quaternion = Quaternion(curl_axis, bend_mid_j2)
	var rot_j3: Quaternion = Quaternion(curl_axis, bend_mid_j3)
	for b_name in [prefix + "Middle1", prefix + "Ring1", prefix + "Pinky1", prefix + "MiddleProximal", prefix + "RingProximal", prefix + "PinkyProximal"]:
		var idx: int = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j1)
	for b_name in [prefix + "Middle2", prefix + "Ring2", prefix + "Pinky2", prefix + "MiddleIntermediate", prefix + "RingIntermediate", prefix + "PinkyIntermediate"]:
		var idx: int = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j2)
	for b_name in [prefix + "Middle3", prefix + "Ring3", prefix + "Pinky3", prefix + "MiddleDistal", prefix + "RingDistal", prefix + "PinkyDistal"]:
		var idx: int = skel.find_bone(b_name)
		if idx != -1: skel.set_bone_pose_rotation(idx, rot_j3)
	var idx_b1: int = skel.find_bone(prefix + "Index1")
	if idx_b1 == -1: idx_b1 = skel.find_bone(prefix + "IndexProximal")
	if idx_b1 != -1: skel.set_bone_pose_rotation(idx_b1, Quaternion(curl_axis, bend_idx_j1))
	var idx_b2: int = skel.find_bone(prefix + "Index2")
	if idx_b2 == -1: idx_b2 = skel.find_bone(prefix + "IndexIntermediate")
	if idx_b2 != -1: skel.set_bone_pose_rotation(idx_b2, Quaternion(curl_axis, bend_idx_j2))
	var idx_b3: int = skel.find_bone(prefix + "Index3")
	if idx_b3 == -1: idx_b3 = skel.find_bone(prefix + "IndexDistal")
	if idx_b3 != -1: skel.set_bone_pose_rotation(idx_b3, Quaternion(curl_axis, bend_idx_j3))
	var th_b1: int = skel.find_bone(prefix + "Thumb1")
	if th_b1 == -1: th_b1 = skel.find_bone(prefix + "ThumbProximal")
	if th_b1 != -1: skel.set_bone_pose_rotation(th_b1, Quaternion(curl_axis, th_bend_1) * Quaternion(thumb_opp_axis, 0.20 + thumb_val * 0.30))
	var th_b2: int = skel.find_bone(prefix + "Thumb2")
	if th_b2 == -1: th_b2 = skel.find_bone(prefix + "ThumbIntermediate")
	if th_b2 != -1: skel.set_bone_pose_rotation(th_b2, Quaternion(curl_axis, th_bend_2))
	var th_b3: int = skel.find_bone(prefix + "Thumb3")
	if th_b3 == -1: th_b3 = skel.find_bone(prefix + "ThumbDistal")
	if th_b3 != -1: skel.set_bone_pose_rotation(th_b3, Quaternion(curl_axis, th_bend_3))

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

	cached_exclude_rids.clear()
	cached_exclude_rids.append(physical_body.get_rid())
	cached_exclude_rids.append(hitbox.get_rid())

	print("[Physics] Cuerpo físico y Hitbox de cápsula (%.2fm alt, %.2fm rad) configurados para %s." % [char_height, char_radius, character_data.character_name if character_data else name])


## Retorna RIDs cacheados en O(1) para excluir del raycast/colisión de proyectiles propios
func get_projectile_exclude_rids() -> Array[RID]:
	return cached_exclude_rids


func apply_knockback(dir: Vector3, force: float) -> void:
	var horiz_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	if horiz_dir.length_squared() < 0.01:
		horiz_dir = -global_transform.basis.z
	# Masa corporal realista sin saltos artificiales en impactos horizontales
	var vert_comp = clampf(dir.y, -1.0, 1.0) if abs(dir.y) > 0.35 else 0.0
	var controlled_force = clampf(force, 1.5, 28.0)
	var impulse = (horiz_dir + Vector3.UP * vert_comp).normalized() * controlled_force
	velocity = impulse
	is_knocked_back = true
	print("[Physics] %s empujado con fuerza controlada %.1f m/s en dirección %s." % [character_data.character_name if character_data else name, controlled_force, horiz_dir])


## Determina la cota del suelo según si el personaje está sobre el ring de piedra o en la llanura exterior
func get_ground_elevation(world_pos: Vector3) -> float:
	var on_stone_ring = abs(world_pos.x) <= RING_HALF_SIZE and abs(world_pos.z) <= RING_HALF_SIZE
	return 0.5 if on_stone_ring else 0.0


func _clamp_to_arena(node: Node3D) -> void:
	if not node or not is_instance_valid(node):
		return
	# Si el nodo es el avatar del jugador, clamplear el XROrigin3D y asegurar transform local cero
	if node.get("is_player") and node.get_parent() is XROrigin3D:
		var origin: XROrigin3D = node.get_parent()
		node.transform = Transform3D.IDENTITY
		node = origin

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
				if collider.is_in_group("mountains") or collider.has_meta("is_mountain") or "Mountain" in collider.name or "Canyon" in collider.name or "Boulder" in collider.name:
					hit_mountain = true
					last_wall_crash_normal = col.normal
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
		var perimeter_normal: Vector3 = Vector3(
			-signf(pos.x) if absf(pos.x) >= limit else 0.0,
			0.0,
			-signf(pos.z) if absf(pos.z) >= limit else 0.0
		)
		if perimeter_normal.length_squared() > 0.01:
			last_wall_crash_normal = perimeter_normal.normalized()
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
	# Punto 2: Silenciar logs flotantes de texto durante el minijuego melee para no saturar al jugador
	if is_in_bullet_time or (active_target_dome != null and is_instance_valid(active_target_dome)):
		return
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
			var impact_speed: float = velocity.length()
			var rebound_dir: Vector3 = -velocity.normalized() if impact_speed > 0.01 else Vector3.BACK
			velocity *= 0.4
			_spawn_flurry_spark(p_pos + Vector3(0.0, 1.2, 0.0))
			_log_combat_event("💥 ¡Impacto demoledor contra pilar de Cell Games! Daño: 350 NP", "warning")
			if not is_player and not is_ragdoll_active and ragdoll_simulator != null and impact_speed >= 11.0:
				start_ragdoll(rebound_dir * 6.0 + Vector3.DOWN * 4.0)
				ragdoll_recovery_timer = 1.8
			break


## Inicia la simulación física ragdoll en el esqueleto
func start_ragdoll(impulse: Vector3 = Vector3.ZERO) -> void:
	if is_ragdoll_active:
		return
	# Punto 5: Si el esqueleto tiene escala no unitaria (ej. Vegeta 0.078) o no hay simulador,
	# Jolt deforma la malla; usar caída procedural segura en su lugar.
	var has_non_unit_scale: bool = skeleton != null and is_instance_valid(skeleton) and (skeleton.global_transform.basis.get_scale() - Vector3.ONE).length() > 0.05
	if not ragdoll_simulator or has_non_unit_scale:
		is_ragdoll_active = true
		var dir: Vector3 = impulse.normalized() if impulse.length_squared() > 0.01 else Vector3.BACK
		if procedural_animator:
			procedural_animator.trigger_hit_flinch(1.5, -dir)
		if body_mesh_instance and is_instance_valid(body_mesh_instance):
			var tw: Tween = create_tween()
			tw.tween_property(body_mesh_instance, "rotation:x", deg_to_rad(-65.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return
	is_ragdoll_active = true
	if procedural_animator:
		procedural_animator.enabled = false

	ragdoll_simulator.physical_bones_start_simulation()

	if impulse.length_squared() > 0.01:
		var applied_core: bool = false
		var applied_spin: bool = false
		for child in ragdoll_simulator.get_children():
			if child is PhysicalBone3D:
				var bn: String = child.bone_name.to_lower()
				if not applied_core and ("hip" in bn or "pelvis" in bn or "root" in bn or bn == "spine"):
					child.apply_central_impulse(impulse)
					applied_core = true
				elif not applied_spin and ("spine2" in bn or "chest" in bn or "head" in bn):
					child.apply_central_impulse(impulse * 0.35 + Vector3(0.0, 1.5, 0.0))
					applied_spin = true
				if applied_core and applied_spin:
					break
	print("[Ragdoll] Simulación física activada para %s." % (character_data.character_name if character_data else name))

## Detiene la simulación física ragdoll y restaura la pose de combate
func stop_ragdoll() -> void:
	if not is_ragdoll_active:
		return
	is_ragdoll_active = false
	if ragdoll_simulator and is_instance_valid(ragdoll_simulator):
		ragdoll_simulator.physical_bones_stop_simulation()
	if skeleton and is_instance_valid(skeleton):
		skeleton.reset_bone_poses()
	if body_mesh_instance and is_instance_valid(body_mesh_instance):
		body_mesh_instance.position = Vector3.ZERO
		body_mesh_instance.rotation = Vector3.ZERO
	if procedural_animator:
		procedural_animator.enabled = true
		if procedural_animator.has_method("trigger_getup_recovery"):
			procedural_animator.trigger_getup_recovery(0.45)
	print("[Ragdoll] Simulación física detenida. Reanudando postura de combate.")


func is_airborne_incapacitated() -> bool:
	return is_ragdoll_active or wall_stick_timer > 0.0 or (is_knocked_back and velocity.length_squared() > 1.2)


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

	# Punto 4: Rebote de Ki por cercanía extrema fuera del melee (< 1.4m)
	var in_melee_seq: bool = is_in_bullet_time or is_flying_to_opponent or bool(opponent.get("is_in_bullet_time")) or bool(opponent.get("is_flying_to_opponent"))
	if not in_melee_seq and not is_match_over and dist < 1.40:
		var push_dir: Vector3 = diff.normalized() if dist > 0.001 else Vector3.BACK
		if _proximity_repulsion_cooldown <= 0.0:
			_proximity_repulsion_cooldown = 0.60
			var mid_pos: Vector3 = (player_pos + opponent_pos) * 0.5 + Vector3(0.0, 1.0, 0.0)
			_spawn_melee_shockwave(mid_pos)
			_spawn_block_shield_vfx()
			if my_origin:
				for h in ["LeftHand", "RightHand"]:
					var ctrl = my_origin.get_node_or_null(h)
					if ctrl and ctrl.has_method("trigger_haptic_pulse"):
						ctrl.trigger_haptic_pulse("haptic", 175.0, 0.85, 0.14, 0.0)
			velocity = push_dir * 9.0
			knockback_drag = 8.0
			is_knocked_back = true
			opponent.set("velocity", -push_dir * 9.0)
			opponent.set("knockback_drag", 8.0)
			opponent.set("is_knocked_back", true)

	# Prevención de penetración física mutua entre combatientes (distancia mínima dura 0.90m)
	var min_body_dist: float = 0.90
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


## Calcula la duración dinámica del Bullet-Time canónico (micro-turno de acción rápida)
func calculate_bullet_time_duration(p_attacker: Node3D, p_defender: Node3D) -> float:
	var n_hits: int = calculate_melee_attack_count(p_attacker, p_defender)
	return float(n_hits) * 1.35 + 0.80


## Calcula la cantidad estratégica de golpes permitidos según Transformación y Ratio de BP (1..5 golpes)
func calculate_melee_attack_count(p_attacker: Node3D, p_defender: Node3D) -> int:
	var count: int = 2
	if p_attacker and is_instance_valid(p_attacker):
		var t_idx_val: Variant = p_attacker.get("current_transformation_index")
		var t_idx: int = int(t_idx_val) if t_idx_val != null else -1
		if t_idx == 0:
			count += 1
		elif t_idx == 1:
			count += 2
		elif t_idx >= 2:
			count += 3
	var atk_bp: float = float(p_attacker.get("current_np")) if (p_attacker and is_instance_valid(p_attacker) and p_attacker.get("current_np") != null) else 9000.0
	var def_bp: float = float(p_defender.get("current_np")) if (p_defender and is_instance_valid(p_defender) and p_defender.get("current_np") != null) else 9000.0
	var ratio: float = atk_bp / maxf(def_bp, 100.0)
	if ratio >= 1.35:
		count += 1
	elif ratio < 0.75:
		count -= 1
	return clampi(count, 1, 5)


## Activa la secuencia cinemática y Bullet-Time de Super Ataque de Ki
func start_super_beam_sequence(tech_name: String, col: Color, dmg: float, tier_level: int = 3, aim_dir: Vector3 = Vector3.ZERO) -> void:
	var opp = _get_opponent()
	if not opp or not is_instance_valid(opp):
		return
	if is_in_beam_sequence and not is_instance_valid(active_beam_sequence):
		is_in_beam_sequence = false
	if is_in_bullet_time and not is_instance_valid(active_target_dome):
		is_in_bullet_time = false
	if is_in_beam_sequence or is_in_bullet_time:
		return

	is_in_beam_sequence = true
	is_firing_beam = true
	beam_tech_name = tech_name
	if procedural_animator and procedural_animator.has_method("set_super_pose"):
		procedural_animator.set_super_pose(tech_name, 2)
	if opp.has_method("set"):
		opp.set("is_in_beam_sequence", true)

	var seq = SuperBeamSequenceClass.new()
	seq.name = "SuperBeamSequenceController"
	active_beam_sequence = seq
	get_tree().current_scene.add_child(seq)
	seq.setup(self, opp, tech_name, col, dmg, tier_level, aim_dir)
	seq.sequence_completed.connect(func(res: String, final_dmg: float):
		is_in_beam_sequence = false
		is_firing_beam = false
		beam_tech_name = ""
		active_beam_sequence = null
		if procedural_animator and procedural_animator.has_method("set_super_pose"):
			procedural_animator.set_super_pose("", 0)
		if is_instance_valid(opp) and opp.has_method("set"):
			opp.set("is_in_beam_sequence", false)
			opp.set("is_firing_beam", false)
	)


## Activa el modo Bullet-Time táctico al conectar el Melee Dash con el oponente
func _start_melee_bullet_time(opponent: Node3D) -> void:
	if not opponent or not is_instance_valid(opponent):
		return
	if is_in_bullet_time:
		return

	is_in_bullet_time = true
	if opponent.has_method("set"):
		opponent.set("is_in_bullet_time", true)
	var allowed_hits: int = calculate_melee_attack_count(self, opponent)
	var duration: float = float(allowed_hits) * 1.35 + 0.80
	print("[CharacterInstance] ¡Iniciando Melee Secuencial! Golpes permitidos: %d | Duración: %.2fs" % [allowed_hits, duration])

	# 0. Alinear milimétricamente a distancia cuerpo a cuerpo y frenar inercia
	velocity = Vector3.ZERO
	is_knocked_back = false
	if opponent.has_method("set"):
		opponent.set("velocity", Vector3.ZERO)
		opponent.set("is_knocked_back", false)

	# Alinear frente a frente: colocar siempre a la IA directamente delante de la mirada del jugador (0.85m) y misma altura Y
	var p_node: Node3D = self if is_player else opponent
	var ai_node: Node3D = opponent if is_player else self
	var p_origin: Node3D = p_node.get_parent() as Node3D if (p_node and p_node.get_parent() is Node3D) else null
	var p_cam: Camera3D = p_origin.get_node_or_null("XRCamera3D") as Camera3D if p_origin else null
	if p_cam and is_instance_valid(p_cam) and ai_node and is_instance_valid(ai_node):
		var cam_fwd_xz: Vector3 = -p_cam.global_transform.basis.z
		cam_fwd_xz.y = 0.0
		cam_fwd_xz = cam_fwd_xz.normalized() if cam_fwd_xz.length_squared() > 0.001 else Vector3.FORWARD
		var p_floor_y: float = p_origin.global_position.y if p_origin else p_node.global_position.y
		ai_node.global_position = Vector3(p_cam.global_position.x, p_floor_y, p_cam.global_position.z) + cam_fwd_xz * 0.85
		_clamp_to_arena(ai_node)
		# Punto 7: Girar instantáneamente a la IA para mirar cara a cara al jugador desde el frame 0
		var face_dx: float = p_cam.global_position.x - ai_node.global_position.x
		var face_dz: float = p_cam.global_position.z - ai_node.global_position.z
		if face_dx * face_dx + face_dz * face_dz > 0.0001:
			ai_node.rotation.y = atan2(face_dx, face_dz)
		# Punto 8: Onda expansiva de choque al iniciar el melee (+ humo si está cerca del suelo)
		var clash_pt: Vector3 = (p_cam.global_position - Vector3(0.0, 0.20, 0.0) + ai_node.global_position + Vector3(0.0, 1.1, 0.0)) * 0.5
		_spawn_melee_shockwave(clash_pt)
		if p_floor_y <= 2.0:
			KiSmokeFX.spawn_smoke(get_tree(), Vector3(clash_pt.x, p_floor_y + 0.15, clash_pt.z), 0.85)

	# Instanciar la cúpula holográfica anime con las cajas de impacto secuenciales
	active_target_dome = MeleeTargetDomeClass.new()
	get_tree().current_scene.add_child(active_target_dome)
	active_target_dome.setup(self, opponent, duration, allowed_hits)
	active_target_dome.bullet_time_completed.connect(_on_bullet_time_completed.bind(opponent))
	active_target_dome.finisher_triggered.connect(_on_bullet_time_finisher.bind(opponent))
	active_target_dome.perfect_parry_triggered.connect(_on_perfect_parry_turnover)

	# Pulso háptico inicial y log en HUD
	var my_origin = get_parent() if is_player else null
	if is_player and my_origin:
		for hand_name in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(hand_name)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 180.0, 0.7, 0.15, 0.0)

	_log_combat_event("⚡ ¡COMBATE MELEE SECUENCIAL! (%d golpes disponibles en %.1fs)" % [allowed_hits, duration], "success")
	var gss = _get_gesture_tree()
	if gss and gss.has_signal("phase_changed"):
		gss.emit_signal("phase_changed", "¡FASE DE ATAQUE MELEE!")


## Callback al completarse el Bloqueo Perfecto: Inversión de Roles instantánea
func _on_perfect_parry_turnover(new_attacker: Node3D, new_defender: Node3D) -> void:
	if new_attacker == self:
		_log_combat_event("⚡ ¡BLOQUEO PERFECTO! ¡CONTRAATAQUE INICIADO!", "success")
		var gss = _get_gesture_tree()
		if gss and gss.has_signal("phase_changed"):
			gss.emit_signal("phase_changed", "¡BLOQUEO PERFECTO! ¡CONTRAATACA!")
	else:
		_log_combat_event("⚠️ ¡EL RIVAL EJECUTÓ BLOQUEO PERFECTO! ¡DEFENSA OBLIGATORIA!", "warning")
		var gss = _get_gesture_tree()
		if gss and gss.has_signal("phase_changed"):
			gss.emit_signal("phase_changed", "¡EL RIVAL HIZO PARRY! ¡DEFIENDE!")


## Callback al finalizar la secuencia completa de Melee Rítmico (sin repetir cobro de daño ya aplicado en la cúpula)
func _on_bullet_time_completed(recorded_hits: Array, _launch_vector: Vector3, opponent: Node3D) -> void:
	is_in_bullet_time = false
	if opponent and is_instance_valid(opponent) and opponent.has_method("set"):
		opponent.set("is_in_bullet_time", false)
	active_target_dome = null

	velocity = Vector3.ZERO
	is_knocked_back = false
	if opponent and is_instance_valid(opponent) and opponent.has_method("set"):
		opponent.set("velocity", Vector3.ZERO)
		opponent.set("is_knocked_back", false)

	if recorded_hits.is_empty():
		_log_combat_event("↩️ Secuencia melee cancelada o sin impactos. Retornando a distancia táctica.", "info")
	else:
		_log_combat_event("⚔️ Intercambio melee concluido (%d acciones resueltas). Separación táctica." % recorded_hits.size(), "info")

	_separate_fighters_to_canonical_distance(opponent, 5.5)


## Callback al activarse un Finisher (Martillazo al suelo, Ataque Cargado v3 Atrás/Arriba, o Ki Break)
func _on_bullet_time_finisher(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3, opponent: Node3D) -> void:
	var strike_atk: Node3D = self
	var strike_def: Node3D = opponent
	if active_target_dome and is_instance_valid(active_target_dome):
		var d_atk: Variant = active_target_dome.get("last_finisher_attacker")
		var d_def: Variant = active_target_dome.get("last_finisher_victim")
		if d_atk is Node3D and is_instance_valid(d_atk) and d_def is Node3D and is_instance_valid(d_def):
			strike_atk = d_atk
			strike_def = d_def

	is_in_bullet_time = false
	if opponent and is_instance_valid(opponent) and opponent.has_method("set"):
		opponent.set("is_in_bullet_time", false)
	active_target_dome = null

	if finisher_name == "hammer_strike":
		strike_atk._execute_hammer_strike_finisher(strike_def, swing_velocity, recorded_hits, launch_vector)
	elif finisher_name in ["charged_v3_up", "charged_v3_back", "ki_break_launch"]:
		strike_atk._execute_charged_v3_or_ki_break_finisher(strike_def, finisher_name, swing_velocity, launch_vector)
	else:
		_separate_fighters_to_canonical_distance(opponent, 5.5)


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

		# Animación ofensiva cíclica (Jab, Cross, Gancho, Patada) y Flinch reactivo en el oponente
		if procedural_animator and procedural_animator.has_method("trigger_melee_strike"):
			procedural_animator.trigger_melee_strike(i % 4)
		if opponent.get("procedural_animator"):
			opponent.procedural_animator.trigger_hit_flinch(0.45, -fwd)

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

	# Expulsión y separación canónica garantizada al concluir la ráfaga
	if has_charged_hit and launch_vector.length_squared() > 0.1:
		print("[BulletTime] Ráfaga concluida con golpe cargado. Expulsando al rival por los aires.")
		var h_dir = (opponent.global_position - my_pos).normalized()
		h_dir.y = 0.0
		var final_impulse = (h_dir * 22.0 + Vector3.UP * 5.0)
		opponent.set("knockback_drag", 1.8)
		opponent.set("velocity", final_impulse)
		opponent.set("is_knocked_back", true)
	else:
		print("[BulletTime] Ráfaga concluida. Separando combatientes a distancia canónica (6.0m).")
		_separate_fighters_to_canonical_distance(opponent, 6.0)


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
		_mark_ki_spent()
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
	if procedural_animator and procedural_animator.has_method("trigger_melee_strike"):
		procedural_animator.trigger_melee_strike(4)
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

	# 6. Cálculo cinético de aplastamiento exclusivo CONTRA EL SUELO (Martillazo DBZ)
	var ki_mult: float = 1.0 + (ki_spent / 25.0) * 0.85
	var swing_mult: float = clampf(v_clean / 2.2, 0.85, 2.0)
	var launch_base_speed: float = 42.0
	var final_speed: float = launch_base_speed * ratio_bp * ki_mult * swing_mult

	var launch_dir: Vector3 = (fwd * 1.4 + Vector3.DOWN * 3.8).normalized()
	var final_impulse: Vector3 = launch_dir * final_speed

	var opp_pos_cur: Vector3 = opponent.get_parent().global_position if (opponent.get("is_player") and opponent.get_parent() is Node3D) else opponent.global_position
	var ground_h: float = get_ground_elevation(opp_pos_cur)
	opponent.set("knockback_drag", 2.2)
	opponent.set("velocity", final_impulse)
	opponent.set("is_knocked_back", true)

	# Si ya está cerca del piso (<= ground_h + 1.5m), estrellar de inmediato con cráter sísmico y Ragdoll en el suelo
	if opp_pos_cur.y <= ground_h + 1.5:
		if opponent.get("is_player"):
			var p_orig = opponent.get_parent()
			if p_orig is Node3D:
				p_orig.global_position.y = ground_h
		else:
			opponent.global_position.y = ground_h
		if opponent.has_method("_on_ground_crash_impact"):
			opponent._on_ground_crash_impact(maxf(final_speed * 0.45, 12.0), opp_pos_cur, ground_h)
		opponent.set("velocity", fwd * clampf(final_speed * 0.22, 3.0, 9.0))

	# REQUISITO CANÓNICO: El martillazo CORTA Y TERMINA el minijuego por completo (sin Follow-Up Bullet Time)
	is_in_bullet_time = false
	is_in_followup_bullet_time = false
	if opponent.has_method("set"):
		opponent.set("is_in_bullet_time", false)
	active_target_dome = null

	_log_combat_event("🔨 ¡MARTILLAZO DBZ CONTRA EL SUELO! Impacto a %.1f m/s (BP Ratio: %.2f)." % [final_speed, ratio_bp], "success")
	print("[HammerFinisher] Martillazo al suelo conectado: daño=%.0f NP, vel=%.1f m/s." % [direct_damage, final_speed])
	_check_transformation_unlocks()

	var gss = _get_gesture_tree()
	if gss and gss.has_signal("phase_changed"):
		gss.emit_signal("phase_changed", "¡FASE LIBRE! (RIVAL ESTRELLADO AL SUELO)")

	# Punto 1: Si el atacante estaba en Estado Zenkai, el Martillazo conectado cierra el combate
	if is_in_zenkai_state and not is_match_over:
		trigger_zenkai_match_finish(self, opponent, "Martillazo Zenkai")


## Ejecuta lanzamiento direccional moderado (Ataque Cargado v3 Atrás/Arriba o Golpe Fuerte por Ki == 0)
func _execute_charged_v3_or_ki_break_finisher(opponent: Node3D, mode: String, swing_velocity: float, _launch_vector: Vector3 = Vector3.ZERO) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	var my_origin = get_parent() if is_player else null
	var my_pos = my_origin.global_position if my_origin else global_position
	var fwd = (opponent.global_position - my_pos).normalized()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else -global_transform.basis.z

	var bp_atk: float = maxf(current_np, 1000.0)
	var bp_def: float = maxf(opponent.get("current_np") if opponent.get("current_np") != null else 10000.0, 1000.0)
	var ratio_bp: float = clampf(sqrt(bp_atk / bp_def), 0.50, 2.5)
	var v_mult: float = clampf(swing_velocity / 2.5, 0.85, 1.45)

	velocity = Vector3.ZERO
	is_knocked_back = false

	var base_speed: float = 32.0
	var final_speed: float = base_speed * ratio_bp * v_mult
	var launch_dir: Vector3 = (fwd * 3.8 + Vector3.UP * 0.55).normalized()
	var mode_tag: String = "HACIA ATRÁS"
	if mode == "charged_v3_up":
		launch_dir = (fwd * 1.8 + Vector3.UP * 2.4).normalized()
		mode_tag = "POR LOS AIRES"
	elif mode == "ki_break_launch":
		launch_dir = (fwd * 3.8 + Vector3.UP * 0.90).normalized()
		final_speed *= 1.15
		mode_tag = "IMBLOQUEABLE (SIN KI)"

	var hit_pos: Vector3 = opponent.global_position + Vector3(0.0, 1.1, 0.0)
	if procedural_animator and procedural_animator.has_method("trigger_melee_strike"):
		procedural_animator.trigger_melee_strike(2 if mode == "charged_v3_up" else 1)
	_spawn_melee_shockwave(hit_pos)

	if opponent.get("procedural_animator"):
		opponent.procedural_animator.trigger_hit_flinch(1.1, -fwd)

	if is_player and my_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = my_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 200.0, 1.0, 0.22, 0.0)

	opponent.set("knockback_drag", 1.2)
	opponent.set("velocity", launch_dir * final_speed)
	opponent.set("is_knocked_back", true)

	is_in_bullet_time = false
	is_in_followup_bullet_time = false
	if opponent.has_method("set"):
		opponent.set("is_in_bullet_time", false)
	active_target_dome = null

	_log_combat_event("💥 ¡GOLPE LANZADOR (%s)! Rival expulsado a %.1f m/s." % [mode_tag, final_speed], "success")
	var gss = _get_gesture_tree()
	if gss and gss.has_signal("phase_changed"):
		gss.emit_signal("phase_changed", "¡FASE LIBRE! (%s)" % mode_tag)

	# Punto 1: Si el atacante estaba en Estado Zenkai, el remate conectado cierra el combate
	if is_in_zenkai_state and not is_match_over:
		trigger_zenkai_match_finish(self, opponent, "Remate Zenkai (%s)" % mode_tag)


## Separa a los combatientes garantizando la distancia canónica de combate (6.0m)
func _separate_fighters_to_canonical_distance(opponent: Node3D, target_distance: float = 6.0) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	# Si la IA es quien ejecutó la acción, la IA retrocede respecto al jugador para mantener el espacio de combate
	if not is_player:
		var opp_origin = opponent.get_parent() if opponent.get("is_player") else null
		var opp_cam = opp_origin.get_node_or_null("XRCamera3D") if opp_origin else null
		var p_head = opp_cam.global_position if opp_cam else (opp_origin.global_position if opp_origin else opponent.global_position)
		var p_h = Vector3(p_head.x, 0.0, p_head.z)
		var ai_h = Vector3(global_position.x, 0.0, global_position.z)
		var current_d = ai_h.distance_to(p_h)
		if current_d >= target_distance:
			return
		var away_dir = (ai_h - p_h).normalized()
		if away_dir.length_squared() < 0.01:
			away_dir = global_transform.basis.z
			away_dir.y = 0.0
			away_dir = away_dir.normalized() if away_dir.length_squared() > 0.01 else Vector3.FORWARD
		var target_ai_pos = p_h + away_dir * target_distance
		target_ai_pos.y = get_ground_elevation(target_ai_pos)
		
		velocity = Vector3.ZERO
		is_knocked_back = false
		is_flying_to_opponent = false
		var tw_self = create_tween()
		tw_self.tween_property(self, "global_position", target_ai_pos, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_self.tween_callback(func(): _clamp_to_arena(self))
		print("[Combat] Separación canónica: IA retrocedió suavemente a %.1fm del jugador." % target_distance)
		return

	# Si el jugador ejecutó la acción (atacante), el oponente IA es quien se aleja
	var my_origin = get_parent() if is_player else null
	var cam: Camera3D = my_origin.get_node_or_null("XRCamera3D") if my_origin else null

	var p_pos = cam.global_position if cam else (my_origin.global_position if my_origin else global_position)
	var p_h = Vector3(p_pos.x, 0.0, p_pos.z)
	var opp_h = Vector3(opponent.global_position.x, 0.0, opponent.global_position.z)

	var current_dist = p_h.distance_to(opp_h)
	if current_dist >= target_distance:
		print("[Combat] Combatientes ya a distancia adecuada (%.1fm >= %.1fm). Sin reajuste necesario." % [current_dist, target_distance])
		return

	var fwd_dir = (opp_h - p_h).normalized()
	if fwd_dir.length_squared() < 0.01:
		fwd_dir = -cam.global_transform.basis.z if cam else -global_transform.basis.z
		fwd_dir.y = 0.0
		fwd_dir = fwd_dir.normalized() if fwd_dir.length_squared() > 0.01 else Vector3.FORWARD

	# Destino canónico del oponente IA: exactamente a target_distance frente a la cabeza del jugador
	var target_opp_pos = p_h + fwd_dir * target_distance
	target_opp_pos.y = get_ground_elevation(target_opp_pos)

	# Frenar velocidades físicas
	velocity = Vector3.ZERO
	is_knocked_back = false
	is_flying_to_opponent = false
	opponent.set("velocity", Vector3.ZERO)
	opponent.set("is_knocked_back", false)
	opponent.set("is_flying_to_opponent", false)

	# Desplazamiento limpio y suave del oponente IA hacia la distancia canónica (0.35s)
	var tw_opp = opponent.create_tween()
	tw_opp.tween_property(opponent, "global_position", target_opp_pos, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_opp.tween_callback(func(): _clamp_to_arena(opponent))
	print("[Combat] Separación canónica garantizada: Oponente reubicado a %.1fm." % target_distance)


## Inicia la secuencia de lanzamiento aéreo y activa el Follow-Up Bullet-Time tras 1 segundo
func _start_followup_airborne_sequence(opponent: Node3D, launch_vector: Vector3) -> void:
	if not opponent or not is_instance_valid(opponent):
		return

	# Asegurar componente de elevación aérea y propulsión horizontal enérgica
	var h_comp = Vector3(launch_vector.x, 0.0, launch_vector.z)
	var h_dir = h_comp.normalized() if h_comp.length_squared() > 0.01 else -global_transform.basis.z
	h_dir.y = 0.0
	h_dir = h_dir.normalized()

	# Cálculo de expulsión aérea escalado por ratio BP y Ki
	var bp_atk: float = maxf(current_np, 1000.0)
	var bp_def: float = maxf(opponent.get("current_np") if opponent.get("current_np") != null else 10000.0, 1000.0)
	var ratio_bp: float = clampf(sqrt(bp_atk / bp_def), 0.50, 3.5)
	var ki_mult: float = 1.0 + (current_ki / 100.0) * 0.60

	var vert_speed = maxf(launch_vector.y, 4.5) * ratio_bp * 0.9
	var horiz_speed = maxf(h_comp.length(), 16.0) * ratio_bp * ki_mult
	var final_impulse = h_dir * horiz_speed + Vector3.UP * vert_speed

	# Elevar ligeramente al contrincante sobre el suelo para iniciar vuelo libre por los aires
	var ground_h = get_ground_elevation(opponent.global_position)
	if opponent.get("is_player"):
		var p_orig = opponent.get_parent()
		if p_orig is Node3D:
			p_orig.global_position.y = maxf(p_orig.global_position.y, ground_h)
	else:
		opponent.global_position.y = maxf(opponent.global_position.y, ground_h + 0.85)

	# Fricción reducida durante el lanzamiento aéreo (drag=1.8 en vez de 24.0) para que vuele varios metros
	opponent.set("knockback_drag", 1.8)
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


func _ensure_character_audio_players() -> void:
	if char_voice_player == null or not is_instance_valid(char_voice_player):
		char_voice_player = AudioStreamPlayer3D.new()
		char_voice_player.name = "CharVoicePlayer3D"
		char_voice_player.unit_size = 7.0
		char_voice_player.max_distance = 40.0
		char_voice_player.position = Vector3(0.0, 1.4, 0.0)
		add_child(char_voice_player)
	if char_sfx_player == null or not is_instance_valid(char_sfx_player):
		char_sfx_player = AudioStreamPlayer3D.new()
		char_sfx_player.name = "CharSfxPlayer3D"
		char_sfx_player.unit_size = 7.0
		char_sfx_player.max_distance = 40.0
		char_sfx_player.position = Vector3(0.0, 1.1, 0.0)
		add_child(char_sfx_player)


func play_character_action_audio(action_or_suffix: String, is_voice: bool = true, fallback_action: String = "") -> void:
	_ensure_character_audio_players()
	var target_player: AudioStreamPlayer3D = char_voice_player if is_voice else char_sfx_player
	if not target_player or not is_instance_valid(target_player):
		return
	var act_id: String = action_or_suffix
	if not ("." in act_id):
		var c_name: String = character_data.character_name if character_data else "Goku"
		act_id = AudioActionManager.get_character_action_id(c_name, action_or_suffix)
	if not AudioActionManager.has_action_sounds(act_id) and not fallback_action.is_empty():
		act_id = fallback_action
	if not AudioActionManager.has_action_sounds(act_id):
		return
	target_player.pitch_scale = randf_range(0.95, 1.05)
	AudioActionManager.play_action(act_id, target_player)
