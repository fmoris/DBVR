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

# Memoria de rotación de mirada para suavizado (Slerp)
var current_head_look_quat: Quaternion = Quaternion.IDENTITY
var current_neck_look_quat: Quaternion = Quaternion.IDENTITY

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

	var spine_rot_offset = Quaternion.from_euler(Vector3(breath_angle + flinch_angle + charge_tilt, 0.0, 0.0))
	_set_bone_rot_relative("Spine", spine_rot_offset)

	var chest_rot_offset = Quaternion.from_euler(Vector3(breath_angle * 0.8 + flinch_angle * 0.5, 0.0, 0.0))
	_set_bone_rot_relative("Chest", chest_rot_offset)


func _apply_look_at(delta: float, target_pos: Vector3, is_charging_ki: bool, flinch_factor: float) -> void:
	if not bone_indices.has("Head") or not bone_indices.has("Neck"):
		return

	if flinch_factor > 0.4:
		# Durante impacto violento, la cabeza reacciona hacia atrás
		var head_flinch = Quaternion.from_euler(Vector3(-0.4 * flinch_factor, 0.0, 0.0))
		_set_bone_rot_relative("Head", head_flinch)
		_set_bone_rot_relative("Neck", head_flinch * 0.5)
		return

	# Calcular vector relativo desde el personaje hacia el objetivo (visor VR del jugador)
	var char_pos = character_instance.global_position
	var char_basis = character_instance.global_transform.basis

	# Posición del jugador en el espacio local del rival
	var local_target = char_basis.inverse() * (target_pos - char_pos)
	
	# En el modelo, mirar al frente es +Z
	var yaw = atan2(local_target.x, local_target.z)
	var horizontal_dist = Vector2(local_target.x, local_target.z).length()
	var pitch = -atan2(local_target.y, max(horizontal_dist, 0.1))

	# Limitar rangos anatómicos realistas (máximo 50 grados horizontal, 35 grados vertical)
	yaw = clampf(yaw, deg_to_rad(-50.0), deg_to_rad(50.0))
	pitch = clampf(pitch, deg_to_rad(-35.0), deg_to_rad(35.0))

	# Si está cargando Ki con furia, la cabeza se inclina un poco hacia abajo con mirada desafiante
	if is_charging_ki:
		pitch += deg_to_rad(12.0)

	var target_neck_quat = Quaternion.from_euler(Vector3(pitch * 0.45, yaw * 0.45, 0.0))
	var target_head_quat = Quaternion.from_euler(Vector3(pitch * 0.55, yaw * 0.55, 0.0))

	# Interpolación esférica suave (Slerp)
	current_neck_look_quat = current_neck_look_quat.slerp(target_neck_quat, clampf(9.0 * delta, 0.0, 1.0))
	current_head_look_quat = current_head_look_quat.slerp(target_head_quat, clampf(11.0 * delta, 0.0, 1.0))

	_set_bone_rot_relative("Neck", current_neck_look_quat)
	_set_bone_rot_relative("Head", current_head_look_quat)


func _apply_arms_guard(delta: float, is_charging_ki: bool, is_blocking: bool, flinch_factor: float) -> void:
	# Micro-temblor de Ki de alta frecuencia (Jitter) durante la carga de poder
	var ki_jitter_l = Vector3.ZERO
	var ki_jitter_r = Vector3.ZERO
	if is_charging_ki:
		var j_scale = 0.04
		ki_jitter_l = Vector3((randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale)
		ki_jitter_r = Vector3((randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale, (randf() - 0.5) * j_scale)

	if is_blocking:
		# Postura de bloqueo: Ambos antebrazos se cruzan frente al pecho protegiendo rostro
		var block_arm_l = Quaternion.from_euler(Vector3(deg_to_rad(45.0), deg_to_rad(20.0), deg_to_rad(30.0)))
		var block_forearm_l = Quaternion.from_euler(Vector3(deg_to_rad(85.0), deg_to_rad(-25.0), deg_to_rad(10.0)))
		var block_arm_r = Quaternion.from_euler(Vector3(deg_to_rad(45.0), deg_to_rad(-20.0), deg_to_rad(-30.0)))
		var block_forearm_r = Quaternion.from_euler(Vector3(deg_to_rad(85.0), deg_to_rad(25.0), deg_to_rad(-10.0)))

		_set_bone_rot_relative("LeftArm", block_arm_l)
		_set_bone_rot_relative("LeftForeArm", block_forearm_l)
		_set_bone_rot_relative("RightArm", block_arm_r)
		_set_bone_rot_relative("RightForeArm", block_forearm_r)

	elif is_charging_ki:
		# Postura Fase 2: Puños apretados a la cintura, codos hacia atrás y cuerpo tenso
		var charge_arm_l = Quaternion.from_euler(Vector3(deg_to_rad(-25.0), deg_to_rad(-10.0), deg_to_rad(20.0)) + ki_jitter_l)
		var charge_forearm_l = Quaternion.from_euler(Vector3(deg_to_rad(105.0), deg_to_rad(-15.0), 0.0) + ki_jitter_l)
		var charge_arm_r = Quaternion.from_euler(Vector3(deg_to_rad(-25.0), deg_to_rad(10.0), deg_to_rad(-20.0)) + ki_jitter_r)
		var charge_forearm_r = Quaternion.from_euler(Vector3(deg_to_rad(105.0), deg_to_rad(15.0), 0.0) + ki_jitter_r)

		_set_bone_rot_relative("LeftArm", charge_arm_l)
		_set_bone_rot_relative("LeftForeArm", charge_forearm_l)
		_set_bone_rot_relative("RightArm", charge_arm_r)
		_set_bone_rot_relative("RightForeArm", charge_forearm_r)

	else:
		# Guardia de Combate Marcial DBZ canónica (Idle vivo orgánico y fluido):
		var idle_pulse = sin(anim_time * 1.5) * 0.025

		var guard_arm_l = Quaternion.from_euler(Vector3(deg_to_rad(35.0) + idle_pulse, deg_to_rad(12.0), deg_to_rad(15.0)))
		var guard_forearm_l = Quaternion.from_euler(Vector3(deg_to_rad(75.0), deg_to_rad(-10.0), deg_to_rad(10.0)))

		var guard_arm_r = Quaternion.from_euler(Vector3(deg_to_rad(25.0) - idle_pulse, deg_to_rad(-15.0), deg_to_rad(-15.0)))
		var guard_forearm_r = Quaternion.from_euler(Vector3(deg_to_rad(80.0), deg_to_rad(10.0), deg_to_rad(-10.0)))

		_set_bone_rot_relative("LeftArm", guard_arm_l)
		_set_bone_rot_relative("LeftForeArm", guard_forearm_l)
		_set_bone_rot_relative("RightArm", guard_arm_r)
		_set_bone_rot_relative("RightForeArm", guard_forearm_r)


func _set_bone_rot_relative(bone_name: String, offset_quat: Quaternion) -> void:
	if not bone_indices.has(bone_name) or not bone_rest_rotations.has(bone_name):
		return

	var idx: int = bone_indices[bone_name]
	var rest_quat: Quaternion = bone_rest_rotations[bone_name]
	var final_rot: Quaternion = (offset_quat * rest_quat).normalized()
	skeleton.set_bone_pose_rotation(idx, final_rot)
