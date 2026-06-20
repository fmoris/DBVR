@tool
extends Node

# Este script se auto-agrega como hijo de cada Skeleton3D para animar sus extremidades en el editor
var skeleton: Skeleton3D
var time: float = 0.0
var duration: float = 120.0 # Duración de la animación en segundos
var active: bool = false

# Diccionario para almacenar las poses originales y restaurarlas al finalizar
# Clave: bone_idx (int) -> Valor: Transform3D original
var original_poses: Dictionary = {}

# Mapeo de huesos a animar
# Nombre estándar -> [Sufijos alternativos para rig japonés/MMD o no optimizado]
var BONE_TARGETS = {
	"LeftArm": ["LeftArm", "_0142", "ARM_L_024", "LeftUpperArm"],
	"RightArm": ["RightArm", "_0157", "ARM_R_042", "RightUpperArm"],
	"LeftUpLeg": ["LeftUpLeg", "_0127", "THIGH_L_05", "LeftUpperLeg"],
	"RightUpLeg": ["RightUpLeg", "_0131", "THIGH_R_019", "RightUpperLeg"],
	"Head": ["Head", "_0139", "HEAD_026"]
}

# Índices reales de los huesos en este esqueleto
var resolved_bones: Dictionary = {}

func _ready():
	# Encontrar el Skeleton3D
	var p = get_parent()
	while p and not (p is Skeleton3D):
		p = p.get_parent()
		
	if p is Skeleton3D:
		skeleton = p
		resolve_bones()
		store_original_poses()
		active = true
		log_message("Inicializado correctamente en: " + str(skeleton.get_path()) + ". Huesos detectados: " + str(resolved_bones.keys()))
	else:
		log_message("Error: No se encontró un Skeleton3D como ancestro.")
		queue_free()

func resolve_bones():
	for standard_name in BONE_TARGETS.keys():
		var found = false
		# 1. Buscar coincidencia exacta
		var idx = skeleton.find_bone(standard_name)
		if idx != -1:
			resolved_bones[standard_name] = idx
			continue
			
		# 2. Buscar por coincidencia de sufijo o nombres alternativos
		var alternatives = BONE_TARGETS[standard_name]
		for alt in alternatives:
			for i in range(skeleton.get_bone_count()):
				var bone_name = skeleton.get_bone_name(i)
				if bone_name == alt or bone_name.ends_with(alt):
					resolved_bones[standard_name] = i
					found = true
					break
			if found:
				break

func store_original_poses():
	for standard_name in resolved_bones.keys():
		var idx = resolved_bones[standard_name]
		original_poses[idx] = {
			"rot": skeleton.get_bone_pose_rotation(idx),
			"pos": skeleton.get_bone_pose_position(idx),
			"scale": skeleton.get_bone_pose_scale(idx)
		}

func _process(delta: float):
	if not active or not skeleton:
		return
		
	time += delta
	
	if time >= duration:
		restore_poses()
		log_message("Animación finalizada en " + skeleton.name + ". Poses originales restauradas.")
		queue_free()
		return
		
	# Calcular rotaciones usando ondas senoidales suaves (frecuencia y desfase)
	# 1. Brazos: Abducción/aducción (rotación en eje Z)
	var arm_angle = sin(time * 3.0) * 0.8
	var arm_rot_left = Quaternion(Vector3(0, 0, 1), arm_angle)
	var arm_rot_right = Quaternion(Vector3(0, 0, 1), -arm_angle)
	
	# 2. Piernas: Flexión/extensión (rotación en eje X)
	var leg_angle = sin(time * 3.0) * 0.5
	var leg_rot_left = Quaternion(Vector3(1, 0, 0), leg_angle)
	var leg_rot_right = Quaternion(Vector3(1, 0, 0), -leg_angle)
	
	# 3. Cabeza: Rotación lateral (Y) y pequeña flexión (X)
	var head_rot_y = sin(time * 2.0) * 0.5
	var head_rot_x = cos(time * 2.0) * 0.2
	var head_rot = Quaternion(Vector3(0, 1, 0), head_rot_y) * Quaternion(Vector3(1, 0, 0), head_rot_x)
	
	# Aplicar rotaciones
	if resolved_bones.has("LeftArm"):
		skeleton.set_bone_pose_rotation(resolved_bones["LeftArm"], arm_rot_left)
	if resolved_bones.has("RightArm"):
		skeleton.set_bone_pose_rotation(resolved_bones["RightArm"], arm_rot_right)
	if resolved_bones.has("LeftUpLeg"):
		skeleton.set_bone_pose_rotation(resolved_bones["LeftUpLeg"], leg_rot_left)
	if resolved_bones.has("RightUpLeg"):
		skeleton.set_bone_pose_rotation(resolved_bones["RightUpLeg"], leg_rot_right)
	if resolved_bones.has("Head"):
		skeleton.set_bone_pose_rotation(resolved_bones["Head"], head_rot)
		
	# Forzar actualización de deformación
	skeleton.force_update_all_bone_transforms()

func restore_poses():
	if not skeleton:
		return
	for idx in original_poses.keys():
		var pose = original_poses[idx]
		skeleton.set_bone_pose_rotation(idx, pose["rot"])
		skeleton.set_bone_pose_position(idx, pose["pos"])
		skeleton.set_bone_pose_scale(idx, pose["scale"])
	skeleton.force_update_all_bone_transforms()

func log_message(msg: String):
	# Escribir en un log acumulativo para que el usuario pueda ver el estado
	var existing = ""
	if FileAccess.file_exists("res://temp_output.txt"):
		var read_file = FileAccess.open("res://temp_output.txt", FileAccess.READ)
		if read_file:
			existing = read_file.get_as_text()
			read_file.close()
			
	var write_file = FileAccess.open("res://temp_output.txt", FileAccess.WRITE)
	if write_file:
		# Dividir líneas de manera segura y aplicar slice sin índices negativos fuera de rango
		var lines = existing.split("\n")
		var start_idx = max(0, lines.size() - 50)
		var sliced_lines = lines.slice(start_idx)
		existing = "\n".join(sliced_lines)
		if existing.length() > 0 and not existing.ends_with("\n"):
			existing += "\n"
		write_file.store_string(existing + "[" + str(Time.get_ticks_msec()) + "] " + msg + "\n")
		write_file.close()
