class_name ProceduralCombatAnimator
extends RefCounted

## ProceduralCombatAnimator (Godot 4.3+ VR)
## Controla la animación procedural orgánica de los luchadores en DBVR:
## - Guardia marcial viva (Idle de combate)
## - Respiración rítmica del tórax y columna
## - Mirada fija interactiva hacia el visor VR del jugador (Head & Neck Look-At)
## - Levitación flotante armónica en el aire
## - Tensión muscular y temblor de Ki durante la recarga de energía
## - Flinch reactivo elástico al recibir golpes e impactos
## - Postura de bloqueo defensivo

var skeleton: Skeleton3D = null
var character_instance: Node3D = null
var enabled: bool = true

# Diccionario de huesos cacheados con sus transformaciones originales de reposo
var bone_indices: Dictionary = {}
var bone_rest_rotations: Dictionary = {}

# Tiempos acumulados para armónicos senoidales
var anim_time: float = 0.0
var breath_time: float = 0.0

# Estado de reacción a impactos (Hit Flinch)
var hit_flinch_timer: float = 0.0
var hit_flinch_intensity: float = 0.0
var hit_flinch_direction: Vector3 = Vector3.BACK

# Memoria de rotación de mirada y poses de brazos para suavizado (Slerp / Lerp sin allocs)
var current_head_euler: Vector3 = Vector3.ZERO
var current_neck_euler: Vector3 = Vector3.ZERO
var _cur_left_hand_pos: Vector3 = Vector3(0.08, -0.06, 0.36)
var _cur_right_hand_pos: Vector3 = Vector3(-0.08, -0.14, 0.24)
var _cur_left_hand_basis: Basis = Basis.IDENTITY
var _cur_right_hand_basis: Basis = Basis.IDENTITY
var _arm_bases_initialized: bool = false

# Lista de nombres de huesos canónicos a buscar
const TARGET_BONES: Array[String] = [
	"Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg", "Hips"
]

func setup(p_skeleton: Skeleton3D, p_character: Node3D) -> void:
	skeleton = p_skeleton
	character_instance = p_character
	bone_indices.clear()
	bone_rest_rotations.clear()

	if not skeleton:
		return

	# Identificar índices de cada hueso en el esqueleto
	for target in TARGET_BONES:
		var idx = skeleton.find_bone(target)
		if idx == -1:
			idx = skeleton.find_bone(target.to_lower())
		if idx == -1:
			# Búsqueda aproximada en caso de prefijos
			for b in range(skeleton.get_bone_count()):
				var b_name = skeleton.get_bone_name(b)
				if b_name.nocasecmp_to(target) == 0:
					idx = b
					break
		if idx != -1:
			bone_indices[target] = idx
			bone_rest_rotations[target] = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()

	print("[ProceduralCombatAnimator] Configurado para %s. Huesos mapeados: %d/%d" % [
		character_instance.name, bone_indices.size(), TARGET_BONES.size()
	])


func trigger_hit_flinch(intensity: float, hit_dir: Vector3) -> void:
	hit_flinch_intensity = clampf(intensity, 0.2, 1.2)
	hit_flinch_direction = hit_dir.normalized() if hit_dir.length_squared() > 0.01 else Vector3.BACK
	hit_flinch_timer = 0.35 # Duración del retroceso visual en segundos


func update(delta: float, target_look_pos: Vector3, is_charging_ki: bool, is_blocking: bool, is_flying: bool) -> void:
	if not enabled or not skeleton or not is_instance_valid(skeleton):
		return

	anim_time += delta
	breath_time += delta * (2.8 if is_charging_ki else 1.4)

	# 1. Recuperación elástica de impacto
	if hit_flinch_timer > 0.0:
		hit_flinch_timer -= delta
		if hit_flinch_timer < 0.0:
			hit_flinch_timer = 0.0

	var flinch_factor: float = 0.0
	if hit_flinch_timer > 0.0:
		# Curva elástica de impacto: retroceso rápido y retorno suave
		var progress: float = 1.0 - (hit_flinch_timer / 0.35)
		flinch_factor = sin(progress * PI) * hit_flinch_intensity

	# 2. Levitación e inclinación corporal si está en el aire
	_apply_body_hover(delta, is_flying, flinch_factor)

	# 3. Respiración y flexión del tórax
	_apply_breathing_and_spine(is_charging_ki, flinch_factor)

	# 4. Mirada interactiva (Head & Neck Look-At al jugador)
	_apply_look_at(delta, target_look_pos, is_charging_ki, flinch_factor)

	# 5. Brazos en Guardia de Combate o Bloqueo
	_apply_arms_guard(delta, is_charging_ki, is_blocking, flinch_factor)


func _apply_body_hover(delta: float, is_flying: bool, flinch_factor: float) -> void:
	if not character_instance or not is_instance_valid(character_instance):
		return

	# Si está en el cuadrilátero pero no suspendido, aplicar una ligera vibración rítmica
	var cur_pos = character_instance.position
	# La altura base normal de suelo es ~0.501
	if cur_pos.y > 0.6:
		# Suspendido en el aire (vuelo): vaivén senoidal antigravedad de 6cm
		var hover_offset = sin(anim_time * 2.5) * 0.06
		var pitch_tilt = sin(anim_time * 1.8) * 0.03
		character_instance.body_mesh_instance.position.y = hover_offset if character_instance.body_mesh_instance else 0.0
		if character_instance.body_mesh_instance:
			character_instance.body_mesh_instance.rotation.x = pitch_tilt
	else:
		if character_instance.body_mesh_instance:
			# En el suelo: micro-ondulación de peso entre pies
			character_instance.body_mesh_instance.position.y = sin(anim_time * 1.8) * 0.008
			character_instance.body_mesh_instance.rotation.x = 0.0


func _apply_breathing_and_spine(is_charging_ki: bool, flinch_factor: float) -> void:
	var breath_angle = sin(breath_time) * (0.045 if is_charging_ki else 0.02)
	
	# Arqueo por impacto hacia atrás
	var flinch_angle = -0.35 * flinch_factor

	# Inclinación hacia adelante por carga de Ki
	var charge_tilt = 0.12 if is_charging_ki else 0.0

	var spine_euler: Vector3 = Vector3(breath_angle + flinch_angle + charge_tilt, 0.0, 0.0)
	_set_bone_rot_relative("Spine", spine_euler)

	var chest_euler: Vector3 = Vector3(breath_angle * 0.8 + flinch_angle * 0.5, 0.0, 0.0)
	_set_bone_rot_relative("Chest", chest_euler)


func _apply_look_at(delta: float, target_pos: Vector3, is_charging_ki: bool, flinch_factor: float) -> void:
	if not bone_indices.has("Head") or not bone_indices.has("Neck"):
		return

	if flinch_factor > 0.4:
		var head_flinch: Vector3 = Vector3(-0.4 * flinch_factor, 0.0, 0.0)
		_set_bone_rot_relative("Head", head_flinch)
		_set_bone_rot_relative("Neck", head_flinch * 0.5)
		return

	var char_pos: Vector3 = character_instance.global_position
	var char_basis: Basis = character_instance.global_transform.basis
	var local_target: Vector3 = char_basis.inverse() * (target_pos - char_pos)

	# Frente canónico del personaje es +Z
	var yaw: float = clampf(atan2(local_target.x, local_target.z), deg_to_rad(-50.0), deg_to_rad(50.0))
	var horizontal_dist: float = Vector2(local_target.x, local_target.z).length()
	var pitch: float = clampf(-atan2(local_target.y, maxf(horizontal_dist, 0.1)), deg_to_rad(-35.0), deg_to_rad(35.0))
	if is_charging_ki:
		pitch += deg_to_rad(12.0)

	var target_neck_euler: Vector3 = Vector3(pitch * 0.45, yaw * 0.45, 0.0)
	var target_head_euler: Vector3 = Vector3(pitch * 0.55, yaw * 0.55, 0.0)
	current_neck_euler = current_neck_euler.lerp(target_neck_euler, clampf(9.0 * delta, 0.0, 1.0))
	current_head_euler = current_head_euler.lerp(target_head_euler, clampf(11.0 * delta, 0.0, 1.0))

	_set_bone_rot_relative("Neck", current_neck_euler)
	_set_bone_rot_relative("Head", current_head_euler)


func _apply_arms_guard(delta: float, is_charging_ki: bool, is_blocking: bool, flinch_factor: float) -> void:
	if not character_instance or not character_instance.has_method("solve_character_arm_ik_basis"):
		return

	var ki_jitter_l: Vector3 = Vector3.ZERO
	var ki_jitter_r: Vector3 = Vector3.ZERO
	if is_charging_ki:
		var j_scale: float = 0.015
		ki_jitter_l = Vector3((randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale)
		ki_jitter_r = Vector3((randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale)

	var is_firing_beam: bool = bool(character_instance.get("is_firing_beam"))

	# Objetivos en espacio canónico de personaje (+X=Izq, +Y=Arriba, +Z=Frente, metros desde el hombro)
	var des_pos_l: Vector3
	var des_pos_r: Vector3
	var des_basis_l: Basis
	var des_basis_r: Basis
	var hand_grip: float = 0.72
	var hand_trig: float = 0.65

	if is_firing_beam:
		var beam_jitter_l: Vector3 = Vector3((randf() - 0.5) * 0.025, (randf() - 0.5) * 0.025, (randf() - 0.5) * 0.025)
		var beam_jitter_r: Vector3 = Vector3((randf() - 0.5) * 0.025, (randf() - 0.5) * 0.025, (randf() - 0.5) * 0.025)
		des_pos_l = Vector3(-0.06, -0.04, 0.48) + beam_jitter_l
		des_pos_r = Vector3(0.06, -0.04, 0.48) + beam_jitter_r
		des_basis_l = Basis.looking_at(Vector3(0.0, 0.85, 0.52).normalized(), Vector3(-1.0, 0.0, 0.0))
		des_basis_r = Basis.looking_at(Vector3(0.0, 0.85, 0.52).normalized(), Vector3(1.0, 0.0, 0.0))
		hand_grip = 0.10
		hand_trig = 0.10
	elif is_blocking:
		# Antebrazos cruzados/levantados frente al pecho y rostro
		des_pos_l = Vector3(-0.08, 0.10, 0.30)
		des_pos_r = Vector3(0.08, 0.06, 0.28)
		des_basis_l = Basis.looking_at(Vector3(-0.35, 0.85, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
		des_basis_r = Basis.looking_at(Vector3(0.35, 0.85, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
		hand_grip = 0.90
		hand_trig = 0.85
	elif is_charging_ki:
		# Puños apretados a la cintura con codos atrás y tensión de Ki
		des_pos_l = Vector3(0.06, -0.24, 0.12) + ki_jitter_l
		des_pos_r = Vector3(-0.06, -0.24, 0.12) + ki_jitter_r
		des_basis_l = Basis.looking_at(Vector3(-0.15, -0.15, 0.97).normalized(), Vector3(0.3, 0.95, 0.0).normalized())
		des_basis_r = Basis.looking_at(Vector3(0.15, -0.15, 0.97).normalized(), Vector3(-0.3, 0.95, 0.0).normalized())
		hand_grip = 1.0
		hand_trig = 1.0
	else:
		# Guardia marcial DBZ asimétrica (izq. adelantada, der. al plexo) + balanceo por impacto
		var idle_pulse: float = sin(anim_time * 1.6) * 0.018
		var flinch_pull: Vector3 = Vector3(0.0, 0.06, -0.12) * flinch_factor
		des_pos_l = Vector3(-0.02, -0.02 + idle_pulse, 0.36) + flinch_pull
		des_pos_r = Vector3(0.04, -0.12 - idle_pulse, 0.24) + flinch_pull
		des_basis_l = Basis.looking_at(Vector3(-0.20, 0.45, 0.87).normalized(), Vector3(0.25, 0.96, 0.0).normalized())
		des_basis_r = Basis.looking_at(Vector3(0.20, 0.40, 0.89).normalized(), Vector3(-0.25, 0.96, 0.0).normalized())

	if not _arm_bases_initialized:
		_cur_left_hand_pos = des_pos_l
		_cur_right_hand_pos = des_pos_r
		_cur_left_hand_basis = des_basis_l
		_cur_right_hand_basis = des_basis_r
		_arm_bases_initialized = true
	else:
		var blend: float = clampf(14.0 * delta, 0.0, 1.0)
		_cur_left_hand_pos = _cur_left_hand_pos.lerp(des_pos_l, blend)
		_cur_right_hand_pos = _cur_right_hand_pos.lerp(des_pos_r, blend)
		_cur_left_hand_basis = _cur_left_hand_basis.slerp(des_basis_l, blend).orthonormalized()
		_cur_right_hand_basis = _cur_right_hand_basis.slerp(des_basis_r, blend).orthonormalized()

	character_instance.solve_character_arm_ik_basis(true, _cur_left_hand_pos, _cur_left_hand_basis)
	character_instance.solve_character_arm_ik_basis(false, _cur_right_hand_pos, _cur_right_hand_basis)
	if character_instance.has_method("_apply_finger_curls_to_skeleton"):
		character_instance._apply_finger_curls_to_skeleton(skeleton, "Left", hand_trig, hand_grip)
		character_instance._apply_finger_curls_to_skeleton(skeleton, "Right", hand_trig, hand_grip)


func _set_bone_rot_relative(bone_name: String, offset_euler_char: Vector3) -> void:
	if not bone_indices.has(bone_name) or not bone_rest_rotations.has(bone_name):
		return

	var idx: int = bone_indices[bone_name]
	if character_instance and character_instance.has_method("get_bone_rotation_char_space"):
		skeleton.set_bone_pose_rotation(idx, character_instance.get_bone_rotation_char_space(idx, offset_euler_char))
		return

	var rest_quat: Quaternion = bone_rest_rotations[bone_name]
	var offset_quat: Quaternion = Quaternion.from_euler(offset_euler_char)
	skeleton.set_bone_pose_rotation(idx, (offset_quat * rest_quat).normalized())
