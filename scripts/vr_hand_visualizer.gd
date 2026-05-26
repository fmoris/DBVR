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
	# Para evadir el ocultamiento nativo de los controladores (XRController3D) cuando no hay mandos enlazados,
	# añadimos las esferas de articulaciones dinámicamente como hijas del origen de XR (XROrigin3D) el cual siempre está visible.
	var xr_origin = get_node_or_null("../../")
	for j in JOINTS:
		var mi = MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = material_ki
		mi.visible = false
		if xr_origin and not Engine.is_editor_hint():
			xr_origin.call_deferred("add_child", mi)
		else:
			add_child(mi)
		joint_instances.append(mi)
		
	# 5. Crear el puño físico procedimental en runtime
	if enable_physics_fist and not Engine.is_editor_hint():
		_setup_physics_fist()
		_inject_enemy_collider()

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
					
				# Asignar transformaciones globales reales multiplicando por el origen de XR (cero latencia física)
				if xr_origin:
					mi.global_transform = xr_origin.global_transform * joint_transform
				else:
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
	
	# Activar el monitoreo de contactos físicos para la detección de golpes y VFX
	physics_fist.contact_monitor = true
	physics_fist.max_contacts_reported = 4
	physics_fist.body_entered.connect(_on_fist_collision)
	
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
			var palm_local_transform = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
			
			# Convertir posición local de palma a coordenadas globales reales
			var target_pos = palm_local_transform.origin
			var target_basis = palm_local_transform.basis
			if xr_origin:
				target_pos = xr_origin.global_transform * target_pos
				target_basis = xr_origin.global_transform.basis * target_basis
			
			# Vector de desplazamiento y distancia hasta la mano física real en el espacio global
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
				
			# Slerp suave para la rotación (orientación física del puño en base global)
			physics_fist.global_transform.basis = physics_fist.global_transform.basis.slerp(target_basis, 15.0 * delta)

# --- Métodos Avanzados de Combate y Efectos de Ki (Acción Posterior) ---

## Busca e inyecta dinámicamente un colisionador de cápsula de combate en Vegeta si se encuentra en la escena
func _inject_enemy_collider() -> void:
	var arena = get_node_or_null("/root/cell_games_arena")
	if not arena:
		return
		
	var vegeta = arena.find_child("Vegeta", true, false)
	if vegeta and is_instance_valid(vegeta):
		# Verificar si ya inyectamos el colisionador anteriormente
		var existing_body = vegeta.find_child("VegetaFistCollider", true, false)
		if not existing_body:
			var static_body = StaticBody3D.new()
			static_body.name = "VegetaFistCollider"
			
			# Crear CollisionShape3D en forma de cápsula humana
			var collision_shape = CollisionShape3D.new()
			var capsule = CapsuleShape3D.new()
			capsule.height = 1.8
			capsule.radius = 0.45
			collision_shape.shape = capsule
			static_body.add_child(collision_shape)
			
			# Alinear la cápsula físicamente en la posición local del rival
			collision_shape.position = Vector3(0, 0.9, 0)
			
			# Añadir el cuerpo físico al rival
			vegeta.add_child(static_body)
			print("[VRHandVisualizer] %s: ¡Inyección exitosa de colisiones físicas de combate en el rival Vegeta!" % get_parent().name)

## Captura y reacciona a los contactos físicos del puño contra el rival o el entorno
func _on_fist_collision(body: Node) -> void:
	# Evitar auto-colisiones absurdas o con el otro puño del jugador
	if body.name.begins_with("KiCombatFist") or body == physics_fist:
		return
		
	var impact_speed = physics_fist.linear_velocity.length()
	
	# Filtrar impactos leves o vibraciones normales del tracking
	if impact_speed > 0.6:
		var is_vegeta = false
		if body.name == "VegetaFistCollider" or body.get_parent().name == "Vegeta":
			is_vegeta = true
			
		# Estimar punto exacto de colisión en base al radio físico de colisión del puño
		var contact_point = physics_fist.global_position + physics_fist.linear_velocity.normalized() * fist_radius
		
		if is_vegeta:
			print("[COMBATE DE KI] ¡GOLPE FÍSICO DIRECTO A VEGETA! Daño: 450 unidades | Velocidad de Impacto: %.2f m/s" % impact_speed)
			_spawn_ki_impact_vfx(contact_point, energy_color)
		else:
			# Golpe contra el suelo, columnas o límites del escenario
			print("[COMBATE DE KI] Impacto contra el entorno: %s | Velocidad: %.2f m/s" % [body.name, impact_speed])
			_spawn_ki_impact_vfx(contact_point, energy_color)

## Instancia ráfagas y destellos tridimensionales brillantes procedimentales en el punto de contacto
func _spawn_ki_impact_vfx(contact_point: Vector3, color: Color) -> void:
	var root_scene = get_tree().root.get_child(0)
	if not root_scene:
		return
		
	# --- 1. DESTELLO ESFÉRICO DE EXPANSIÓN (Holograma de energía) ---
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04
	flash.mesh = sphere_mesh
	
	# Material holográfico unshaded dinámico
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	flash.material_override = mat
	
	flash.global_position = contact_point
	root_scene.add_child(flash)
	
	# Animación de expansión rápida del destello mediante Tweens en Godot 4
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_color = Color(color.r, color.g, color.b, 0.0)
	tween.tween_property(mat, "albedo_color", target_color, 0.15).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(flash.queue_free)
	
	# --- 2. EXPULSIÓN FÍSICA DE CHISPAS DE ENERGÍA KI ---
	# Instanciar procedimentalmente 5 micro-esferas con físicas dinámicas de Jolt
	for i in range(5):
		var spark = RigidBody3D.new()
		
		# Crear el mesh visual de la chispa
		var spark_visual = MeshInstance3D.new()
		var spark_mesh = SphereMesh.new()
		spark_mesh.radius = 0.012
		spark_mesh.height = 0.024
		spark_visual.mesh = spark_mesh
		
		# Material translúcido independiente para evitar mutar el original
		var spark_mat = StandardMaterial3D.new()
		spark_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		spark_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		spark_mat.albedo_color = color
		spark_visual.material_override = spark_mat
		spark.add_child(spark_visual)
		
		# Colisionador físico microscópico para que interactúe con el piso
		var spark_col = CollisionShape3D.new()
		var spark_col_shape = SphereShape3D.new()
		spark_col_shape.radius = 0.012
		spark_col.shape = spark_col_shape
		spark.add_child(spark_col)
		
		# Propiedades del cuerpo físico
		spark.gravity_scale = 0.4 # Gravedad ligera tipo anime
		spark.linear_damp = 1.0
		spark.global_position = contact_point
		
		root_scene.add_child(spark)
		
		# Proyección aleatoria hacia afuera/arriba del impacto
		var random_direction = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.2),
			randf_range(-1.0, 1.0)
		).normalized()
		var impulse_force = randf_range(1.5, 4.0)
		spark.apply_central_impulse(random_direction * impulse_force)
		
		# Animación de reducción progresiva a escala cero de la chispa
		var spark_tween = create_tween()
		spark_tween.tween_property(spark_visual, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		spark_tween.chain().tween_callback(spark.queue_free)
