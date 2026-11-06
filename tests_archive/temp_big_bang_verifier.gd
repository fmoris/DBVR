@tool
extends Node

# Verificador de animación del Big Bang Attack de Vegeta
var skeleton: Skeleton3D
var time: float = 0.0
var active: bool = false

var original_poses: Dictionary = {}
var target_poses: Dictionary = {}

var right_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1
var right_shoulder_idx: int = -1
var head_idx: int = -1
var spine_idx: int = -1

# Esfera de energía de Ki para la carga
var ki_sphere: MeshInstance3D
var ki_material: StandardMaterial3D

func _ready():
	var p = get_parent()
	while p and not (p is Skeleton3D):
		p = p.get_parent()
		
	if p is Skeleton3D:
		skeleton = p
		resolve_bones()
		
		# Validar huesos críticos para evitar errores de índice -1 en esqueletos no optimizados
		if right_arm_idx == -1 or right_hand_idx == -1:
			print("Advertencia: Huesos críticos no encontrados en el esqueleto '" + skeleton.name + "'. No se animará (ignorado de forma segura).")
			active = false
			set_process(false)
			queue_free()
			return
			
		store_original_poses()
		setup_ki_sphere()
		define_target_poses()
		active = true
		print("Big Bang Attack Animator inicializado en: " + skeleton.name)
	else:
		print("Error: No se encontró Skeleton3D.")
		queue_free()

func resolve_bones():
	right_shoulder_idx = skeleton.find_bone("RightShoulder")
	right_arm_idx = skeleton.find_bone("RightArm")
	right_forearm_idx = skeleton.find_bone("RightForeArm")
	right_hand_idx = skeleton.find_bone("RightHand")
	head_idx = skeleton.find_bone("Head")
	spine_idx = skeleton.find_bone("Spine")

func store_original_poses():
	var bones = [right_shoulder_idx, right_arm_idx, right_forearm_idx, right_hand_idx, head_idx, spine_idx]
	for idx in bones:
		if idx != -1:
			original_poses[idx] = {
				"rot": skeleton.get_bone_pose_rotation(idx),
				"pos": skeleton.get_bone_pose_position(idx),
				"scale": skeleton.get_bone_pose_scale(idx)
			}

func setup_ki_sphere():
	# Crear una esfera 3D para representar la energía del Big Bang Attack
	ki_sphere = MeshInstance3D.new()
	ki_sphere.name = "BigBangKiSphere"
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.01 # Comenzará muy pequeña
	sphere_mesh.height = 0.02
	ki_sphere.mesh = sphere_mesh
	
	# Crear material de Ki brillante (Glow)
	ki_material = StandardMaterial3D.new()
	ki_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Emisión pura
	ki_material.albedo_color = Color(0.2, 0.6, 1.0, 1.0) # Azul eléctrico brillante (Big Bang Attack clásico)
	ki_material.use_point_size = true
	
	ki_sphere.material_override = ki_material
	add_child(ki_sphere)

func define_target_poses():
	# Definir las rotaciones del esqueleto para la pose de disparo del Big Bang Attack:
	# El brazo derecho debe levantarse completamente horizontal hacia adelante con la palma abierta
	
	# 1. RightArm (Brazo): Rotación para levantarlo hacia adelante y arriba (apuntando al frente)
	if right_arm_idx != -1:
		target_poses[right_arm_idx] = Quaternion(Vector3(0, 1, 0), 1.45) * Quaternion(Vector3(0, 0, 1), 1.35) * Quaternion(Vector3(1, 0, 0), 0.1)
	
	# 2. RightForeArm (Antebrazo): Estirado completamente alineado con el brazo
	if right_forearm_idx != -1:
		target_poses[right_forearm_idx] = Quaternion.IDENTITY
	
	# 3. RightHand (Mano): Palma abierta mirando hacia adelante (al oponente)
	if right_hand_idx != -1:
		target_poses[right_hand_idx] = Quaternion(Vector3(0, 1, 0), -1.2) * Quaternion(Vector3(1, 0, 0), 0.6)
	
	# 4. Spine (Columna): Ligeramente inclinada hacia atrás por el esfuerzo
	if spine_idx != -1:
		target_poses[spine_idx] = Quaternion(Vector3(1, 0, 0), -0.15)
	
	# 5. Head (Cabeza): Mirando al frente hacia el objetivo
	if head_idx != -1:
		target_poses[head_idx] = Quaternion(Vector3(1, 0, 0), 0.15) * Quaternion(Vector3(0, 1, 0), 0.2)

func _process(delta: float):
	if not active or not skeleton or not is_instance_valid(ki_sphere):
		return
		
	time += delta
	var cycle_duration = 5.0 # Duración de cada ciclo de ataque
	var cycle_time = fmod(time, cycle_duration)
	
	# FASES DE LA ANIMACIÓN
	# Fase 1: Cargar Energía (0.0s a 2.0s)
	if cycle_time < 2.0:
		var t = cycle_time / 2.0 # Progreso de 0 a 1
		
		# Interpolar pose de reposo a pose de tiro
		interpolate_skeleton(t)
		
		# Actualizar posición y tamaño de la esfera de Ki en la mano
		var hand_transform = skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_idx)
		ki_sphere.global_transform.origin = hand_transform.origin + hand_transform.basis.y * 0.15 # Un poco por delante de la mano
		
		# La esfera crece hasta tamaño máximo y brilla cada vez más (azul)
		var size = lerp(0.01, 0.35, t)
		ki_sphere.scale = Vector3(size, size, size)
		ki_material.albedo_color = Color(0.2, 0.6, 1.0, 1.0) * (1.0 + t * 4.0) # Aumenta la intensidad del brillo
		ki_sphere.visible = true
		
		# Pequeña vibración en el brazo por la acumulación de poder
		if right_arm_idx != -1 and target_poses.has(right_arm_idx):
			var shake = sin(time * 50.0) * 0.02
			skeleton.set_bone_pose_rotation(right_arm_idx, target_poses[right_arm_idx] * Quaternion(Vector3(0, 1, 0), shake))

	# Fase 2: Disparo del Big Bang Attack (2.0s a 2.3s)
	elif cycle_time < 2.3:
		var t = (cycle_time - 2.0) / 0.3
		
		# Retroceso del brazo en el momento del disparo
		if right_arm_idx != -1 and target_poses.has(right_arm_idx):
			var recoil_rot = target_poses[right_arm_idx] * Quaternion(Vector3(1, 0, 0), 0.25) # Retroceso hacia atrás
			skeleton.set_bone_pose_rotation(right_arm_idx, recoil_rot)
			
		# Lanzar la esfera de Ki hacia adelante
		var hand_transform = skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_idx)
		# Dirección hacia adelante (calculada desde la orientación de la mano o el esqueleto)
		var forward_dir = -skeleton.global_transform.basis.z # Hacia donde apunta el esqueleto
		
		ki_sphere.global_transform.origin += forward_dir * t * 15.0 # Sale disparada a alta velocidad
		ki_sphere.scale = Vector3(0.35, 0.35, 0.35) * (1.0 - t * 0.5) # Se reduce ligeramente en su trayecto
		ki_material.albedo_color = Color(0.5, 0.8, 1.0, 1.0) * 5.0 # Brillo máximo blanco-azul

	# Fase 3: Explosión e impacto (2.3s a 3.0s)
	elif cycle_time < 3.0:
		var t = (cycle_time - 2.3) / 0.7
		# Ocultar la esfera principal (ya impactó)
		ki_sphere.visible = false
		
		# Volver de la pose de retroceso a la pose de tiro estirada
		if right_arm_idx != -1 and target_poses.has(right_arm_idx):
			var cur_rot = target_poses[right_arm_idx].slerp(original_poses[right_arm_idx]["rot"], t * 0.5)
			skeleton.set_bone_pose_rotation(right_arm_idx, cur_rot)

	# Fase 4: Retorno a la calma (3.0s a 5.0s)
	else:
		var t = (cycle_time - 3.0) / 2.0
		interpolate_skeleton(1.0 - t)
		ki_sphere.visible = false

	skeleton.force_update_all_bone_transforms()

func interpolate_skeleton(weight: float):
	# Interpolación suave entre poses originales y de ataque
	for idx in original_poses.keys():
		if target_poses.has(idx):
			var orig = original_poses[idx]["rot"]
			var targ = target_poses[idx]
			skeleton.set_bone_pose_rotation(idx, orig.slerp(targ, weight))
		
	# Mover levemente el torso
	if spine_idx != -1 and target_poses.has(spine_idx):
		skeleton.set_bone_pose_rotation(spine_idx, original_poses[spine_idx]["rot"].slerp(target_poses[spine_idx], weight))

func _exit_tree():
	# Limpiar la esfera de Ki al eliminar el nodo
	if is_instance_valid(ki_sphere):
		ki_sphere.queue_free()
	restore_original_poses()

func restore_original_poses():
	if not skeleton:
		return
	for idx in original_poses.keys():
		var pose = original_poses[idx]
		skeleton.set_bone_pose_rotation(idx, pose["rot"])
		skeleton.set_bone_pose_position(idx, pose["pos"])
		skeleton.set_bone_pose_scale(idx, pose["scale"])
	skeleton.force_update_all_bone_transforms()
