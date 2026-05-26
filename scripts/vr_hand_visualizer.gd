@tool
extends Node3D

# --- Parámetros de la Mano de Ki ---
@export_enum("Left", "Right") var hand_side: String = "Left"
@export var joint_radius: float = 0.006  # 6mm por esfera de articulación para Quest 3
@export var energy_color: Color = Color(0.0, 0.7, 1.0, 0.9) # Celeste brillante de energía Ki

# --- Parámetros Físicos de Combate (Quest VR) ---
@export var enable_physics_fist: bool = true
@export var fist_radius: float = 0.08  # 8cm de radio físico para el puño de colisión
@export var force_multiplier: float = 35.0  # Coeficiente de fuerza para seguimiento reactivo

var material_ki: StandardMaterial3D
var tracker: XRHandTracker = null
var joint_instances: Array[MeshInstance3D] = []
var static_finger_meshes: Array[MeshInstance3D] = []
var frames_since_log: int = 0

# --- Referencias de Física ---
var physics_fist: RigidBody3D = null
var physics_collision: CollisionShape3D = null

# Definición de las 26 articulaciones canónicas de OpenXR corregidas para Godot 4
const JOINTS = [
	XRHandTracker.HAND_JOINT_WRIST,
	XRHandTracker.HAND_JOINT_PALM,
	
	# Pulgar
	XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
	XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL,
	XRHandTracker.HAND_JOINT_THUMB_TIP,
	
	# Índice
	XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
	
	# Medio
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	
	# Anular
	XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL,
	XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE,
	XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL,
	XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
	
	# Meñique
	XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP
]

func _ready() -> void:
	# 1. Determinar color temático dinámico de Ki según el nombre del nodo padre
	if get_parent():
		if get_parent().name == "LeftHand":
			energy_color = Color(0.0, 0.7, 1.0, 0.9) # Celeste Ki cian
		elif get_parent().name == "RightHand":
			energy_color = Color(1.0, 0.6, 0.1, 0.9) # Dorado/Naranja Ki

	# 2. Configurar el material de energía Ki (brillante y traslúcido)
	material_ki = StandardMaterial3D.new()
	material_ki.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	material_ki.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Glow sin sombras
	material_ki.albedo_color = energy_color
	
	# 3. Guardar las mallas estáticas cilíndricas del controlador (para usarlas como fallback si no hay hand tracking)
	if not Engine.is_editor_hint():
		var static_count = 0
		for child in get_children():
			if child is MeshInstance3D:
				static_finger_meshes.append(child)
				child.material_override = material_ki
				child.visible = true # Visibles por defecto
				static_count += 1
		print("[VRHandVisualizer] %s: Inicializado. Encontradas %d mallas estáticas de fallback." % [get_parent().name, static_count])

	# 4. Crear los mesh de articulaciones dinámicamente
	var sphere = SphereMesh.new()
	sphere.radius = joint_radius
	sphere.height = joint_radius * 2.0
	
	# Instanciar representaciones 3D para cada uno de los 26 joints
	for j in JOINTS:
		var mi = MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = material_ki
		mi.visible = false
		add_child(mi)
		joint_instances.append(mi)
		
	# 5. Crear el puño físico procedimental en runtime
	if enable_physics_fist and not Engine.is_editor_hint():
		_setup_physics_fist()

func _process(_delta: float) -> void:
	# No procesar lógica de tracking real en el editor
	if Engine.is_editor_hint():
		return

	# SEGURIDAD ABSOLUTA: Forzar que el nodo padre (LeftHand/RightHand) permanezca visible
	# Esto anula cualquier lógica nativa del motor que intente ocultar el controlador cuando no detecta tracking.
	if get_parent() and not get_parent().visible:
		get_parent().visible = true

	# 1. Obtener la referencia al tracker dinámico del script xr_setup.gd
	if not tracker:
		var origin = get_node_or_null("../../")
		if origin and "left_hand_tracker" in origin:
			if get_parent().name == "LeftHand":
				tracker = origin.left_hand_tracker
			elif get_parent().name == "RightHand":
				tracker = origin.right_hand_tracker

	# 2. Evaluar si el tracking de articulaciones OpenXR está activo y es válido
	var hand_tracking_active = false
	if tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			hand_tracking_active = true

	# LOG PERIÓDICO DE DIAGNÓSTICO (Cada 180 frames / ~3 segundos en Quest para evitar inundar consola)
	frames_since_log += 1
	if frames_since_log >= 180:
		frames_since_log = 0
		print("[VRHandVisualizer] %s: Rastro Dedos = %s | Tracker Enlazado = %s | Padre Visible = %s" % [
			get_parent().name,
			"SÍ (26 Joints)" if hand_tracking_active else "NO (Fallback Controles)",
			"SÍ" if tracker != null else "NO",
			"SÍ" if get_parent().visible else "NO"
		])

	# 3. Renderizado Inteligente Híbrido (Hand Tracking vs Controladores)
	if hand_tracking_active:
		# --- MODO DE RASTREO DE MANOS ACTIVO (26 articulaciones físicas) ---
		# Ocultar la malla cilíndrica estática de controladores
		for sm in static_finger_meshes:
			sm.visible = false
			
		# Actualizar y posicionar cada una de las 26 articulaciones individuales
		for i in range(JOINTS.size()):
			var joint = JOINTS[i]
			var joint_flags = tracker.get_hand_joint_flags(joint)
			var mi = joint_instances[i]
			
			if (joint_flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
				var joint_transform = tracker.get_hand_joint_transform(joint)
				
				# Modulación de tamaño premium
				var scale_factor = 1.0
				if joint in [
					XRHandTracker.HAND_JOINT_THUMB_TIP,
					XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
					XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
					XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
					XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP
				]:
					scale_factor = 1.25 # Puntas más visibles
				elif joint == XRHandTracker.HAND_JOINT_PALM:
					scale_factor = 2.0  # Palma central prominente
					
				# Asignar transformaciones globales (cero latencia física)
				mi.global_transform = joint_transform
				mi.scale = Vector3.ONE * scale_factor
				
				# Micro-animación: sutil pulsación sinusoidal de energía Ki en los joints
				var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.15
				mi.scale *= pulse
				
				mi.visible = true
			else:
				mi.visible = false
	else:
		# --- MODO CONTROLADORES ACTIVO (FALLBACK SEGURO) ---
		# Ocultar los 26 joints dinámicos ya que no hay tracking de dedos
		_hide_all_joints()
		
		# Mostrar las mallas de manos estáticas alineadas al control con el material brillante de Ki
		for sm in static_finger_meshes:
			sm.visible = true

func _hide_all_joints() -> void:
	for mi in joint_instances:
		mi.visible = false

# --- Métodos Físicos de Combate Reactivo (Procedimentales) ---

## Configura e instancia un cuerpo rígido físico en runtime para las colisiones de combate
func _setup_physics_fist() -> void:
	physics_fist = RigidBody3D.new()
	physics_fist.name = "KiCombatFist_" + hand_side
	
	# Configurar parámetros del cuerpo rígido para simular un puño físico estable
	physics_fist.gravity_scale = 0.0   # Sin gravedad para evitar que se caiga
	physics_fist.can_sleep = false      # Mantener activo para tracking ininterrumpido
	physics_fist.linear_damp = 10.0    # Evitar oscilaciones/rebotes exagerados
	physics_fist.angular_damp = 10.0
	
	# Colisiones físicas: Capas de colisión estándar para interactuar con el entorno y enemigos
	physics_fist.collision_layer = 1
	physics_fist.collision_mask = 1
	
	# Crear la forma esférica de colisión
	physics_collision = CollisionShape3D.new()
	physics_collision.name = "FistCollision"
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = fist_radius
	physics_collision.shape = sphere_shape
	physics_fist.add_child(physics_collision)
	
	# Instanciar en la raíz de forma segura para conservar coordenadas globales sin heredar transform del tracker
	var origin = get_node_or_null("../../")
	if origin:
		if origin.get_parent():
			origin.get_parent().call_deferred("add_child", physics_fist)
		else:
			origin.call_deferred("add_child", physics_fist)
		print("[VRHandVisualizer] %s: Puño físico procedimental instanciado con éxito en la raíz global." % get_parent().name)
	else:
		call_deferred("add_child", physics_fist)

## Lógica física de acoplamiento por fuerzas reactivas ejecutada en el hilo de física del motor
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	# Mover el cuerpo físico acoplado a la palma si el tracker está disponible
	if physics_fist and tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_transform = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
			var target_pos = palm_transform.origin
			
			# Vector de desplazamiento y distancia hasta la mano física real
			var direction = target_pos - physics_fist.global_position
			var distance = direction.length()
			
			# Teletransporte de seguridad si el tracking parpadea o reaparece muy lejos
			if distance > 1.0:
				physics_fist.global_position = target_pos
				physics_fist.linear_velocity = Vector3.ZERO
			else:
				# Aplicar velocidad física reactiva (Nudge force).
				# Si colisiona con un muro o rival, se detiene físicamente en el punto de contacto.
				physics_fist.linear_velocity = direction * force_multiplier
				
			# Slerp suave para la rotación (orientación física del puño)
			physics_fist.global_transform.basis = physics_fist.global_transform.basis.slerp(palm_transform.basis, 15.0 * delta)

