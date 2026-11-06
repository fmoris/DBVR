@tool
extends Node3D

# --- Parámetros de la Mano de Ki ---
@export_enum("Left", "Right") var hand_side: String = "Left"
@export var joint_radius: float = 0.006  # 6mm por esfera de articulación para Quest 3
@export var energy_color: Color = Color(0.0, 0.7, 1.0, 0.9) # Celeste brillante de energía Ki
@export var show_debug_spheres: bool = true

const KiSphereShader = preload("res://ki_sphere.gdshader")
const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")

# --- Parámetros Físicos de Combate (Quest VR) ---
@export var enable_physics_fist: bool = true
@export var fist_radius: float = 0.08  # 8cm de radio físico para el puño de colisión
@export var force_multiplier: float = 35.0  # Coeficiente de fuerza para seguimiento reactivo

var material_ki: StandardMaterial3D
var tracker: XRHandTracker = null
var joint_instances: Array[MeshInstance3D] = []
var static_finger_meshes: Array[MeshInstance3D] = []
var frames_since_log: int = 0

# --- Referencias de Nodos y Física ---
var parent_node: Node = null
var physics_fist: RigidBody3D = null
var physics_collision: CollisionShape3D = null
var xr_origin: XROrigin3D = null

# --- Referencias de Esferas y Luces de Carga de Ki Blast (Espejo) ---
var charging_ki_sphere: MeshInstance3D = null
var charging_ki_corona: MeshInstance3D = null
var charging_ki_light: OmniLight3D = null
var gesture_tree_ref: Node = null

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
	# 0. Cachar referencias a nodos principales
	parent_node = get_parent()
	xr_origin = get_node_or_null("../../")
	gesture_tree_ref = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
	if not gesture_tree_ref and get_tree() and get_tree().root:
		var arena = get_tree().root.get_child(0)
		if arena:
			gesture_tree_ref = arena.find_child("GesturePhaseTree", true, false)

	# 1. Determinar color temático dinámico de Ki según el nombre del nodo padre
	if parent_node:
		if parent_node.name == "LeftHand":
			energy_color = Color(0.0, 0.7, 1.0, 0.9) # Celeste Ki cian
		elif parent_node.name == "RightHand":
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
		print("[VRHandVisualizer] %s: Inicializado. Encontradas %d mallas estáticas de fallback." % [parent_node.name if parent_node else name, static_count])

	# 4. Crear los mesh de articulaciones dinámicamente
	var sphere = SphereMesh.new()
	sphere.radius = joint_radius
	sphere.height = joint_radius * 2.0
	
	# Instanciar representaciones 3D para cada uno de los 26 joints
	# Para evadir el ocultamiento nativo de los controladores (XRController3D) cuando no hay mandos enlazados,
	# añadimos las esferas de articulaciones dinámicamente como hijas del origen de XR (XROrigin3D) el cual siempre está visible.
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
		
	# 5. Crear el puño físico y la esfera de Ki Blast procedimentales en runtime
	if enable_physics_fist and not Engine.is_editor_hint():
		_setup_physics_fist()
		_inject_enemy_collider()
		_setup_charging_ki_sphere()

func _process(_delta: float) -> void:
	# No procesar lógica de tracking real en el editor
	if Engine.is_editor_hint():
		return

	# SEGURIDAD ABSOLUTA: Forzar que el nodo padre (LeftHand/RightHand) permanezca visible
	# Esto anula cualquier lógica nativa del motor que intente ocultar el controlador cuando no detecta tracking.
	if parent_node and not parent_node.visible:
		parent_node.visible = true
 
	# 1. Obtener la referencia al tracker dinámico del script xr_setup.gd
	if not tracker:
		if xr_origin:
			if parent_node and parent_node.name == "LeftHand" and "left_hand_tracker" in xr_origin:
				tracker = xr_origin.left_hand_tracker
			elif parent_node and parent_node.name == "RightHand" and "right_hand_tracker" in xr_origin:
				tracker = xr_origin.right_hand_tracker

	# Intentar obtener la referencia al GesturePhaseTree si no se cargó en _ready
	if not gesture_tree_ref:
		gesture_tree_ref = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
		if not gesture_tree_ref and get_tree() and get_tree().root:
			var arena = get_tree().root.get_child(0)
			if arena:
				gesture_tree_ref = arena.find_child("GesturePhaseTree", true, false)

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
			parent_node.name if parent_node else name,
			"SÍ (26 Joints)" if hand_tracking_active else "NO (Fallback Controles)",
			"SÍ" if tracker != null else "NO",
			"SÍ" if parent_node and parent_node.visible else "NO"
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
				
				# Micro-animación: sutil pulsación sinusoidal de energía Ki en los joints (solo si está cargando/recarcando Ki)
				var is_active_charging: bool = false
				if gesture_tree_ref:
					if hand_side == "Left":
						is_active_charging = gesture_tree_ref.get("is_charging_ki_blast_left") or gesture_tree_ref.get("is_charging_ki")
					else:
						is_active_charging = gesture_tree_ref.get("is_charging_ki_blast_right") or gesture_tree_ref.get("is_charging_ki")
						
				if is_active_charging:
					var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.15
					mi.scale *= pulse
				
				mi.visible = show_debug_spheres
			else:
				mi.visible = false
	else:
		# --- MODO CONTROLADORES ACTIVO (FALLBACK SEGURO) ---
		# Ocultar los 26 joints dinámicos ya que no hay tracking de dedos
		_hide_all_joints()
		
		# Mostrar las mallas de manos estáticas alineadas al control con el material brillante de Ki (solo si no hay modelo GLB)
		var has_visual_hand = false
		if parent_node:
			var visual_hand_name = "PlayerVisualHandLeft" if hand_side == "Left" else "PlayerVisualHandRight"
			if parent_node.has_node(visual_hand_name):
				has_visual_hand = true
				
		for sm in static_finger_meshes:
			sm.visible = not has_visual_hand
			
	# Actualizar la esfera de Ki Blast de carga
	_update_charging_ki_sphere(_delta)

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
	if xr_origin:
		if xr_origin.get_parent():
			xr_origin.get_parent().call_deferred("add_child", physics_fist)
		else:
			xr_origin.call_deferred("add_child", physics_fist)
		print("[VRHandVisualizer] %s: Puño físico procedimental instanciado con éxito en la raíz global." % (parent_node.name if parent_node else name))
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

## Busca e inyecta dinámicamente un colisionador de cápsula de combate en los rivales de tipo CharacterInstance
func _inject_enemy_collider() -> void:
	var arena = get_node_or_null("/root/cell_games_arena")
	if not arena:
		return
		
	# Buscar todos los CharacterInstance que no sean el jugador
	for child in arena.get_children():
		if child.has_method("take_hit") and not child.name.contains("Player"):
			var existing_body = child.find_child("EnemyFistCollider", true, false)
			if not existing_body:
				var static_body = StaticBody3D.new()
				static_body.name = "EnemyFistCollider"
				
				# Crear CollisionShape3D en forma de cápsula humana
				var collision_shape = CollisionShape3D.new()
				var capsule = CapsuleShape3D.new()
				capsule.height = 1.8
				capsule.radius = 0.45
				collision_shape.shape = capsule
				static_body.add_child(collision_shape)
				collision_shape.position = Vector3(0, 0.9, 0)
				
				child.add_child(static_body)
				print("[VRHandVisualizer] %s: ¡Inyección de colisión física en el rival %s!" % [get_parent().name, child.name])

## Captura y reacciona a los contactos físicos del puño contra el rival o el entorno
func _on_fist_collision(body: Node) -> void:
	if body.name.begins_with("KiCombatFist") or body == physics_fist:
		return
		
	var impact_speed = physics_fist.linear_velocity.length()
	
	if impact_speed > 0.6:
		var target_char = null
		if body.name in ["EnemyFistCollider", "CharacterPhysicalBody", "CharacterHitbox"]:
			target_char = body.get_parent()
		elif body.has_method("take_hit"):
			target_char = body
		elif body.get_parent() and body.get_parent().has_method("take_hit"):
			target_char = body.get_parent()
			
		var contact_point = physics_fist.global_position + physics_fist.linear_velocity.normalized() * fist_radius
		
		if target_char and target_char.has_method("take_hit"):
			var damage_np = 450.0
			var punch_dir = physics_fist.linear_velocity.normalized()
			target_char.take_hit(damage_np, punch_dir)
			
			# Incrementar NP del jugador Goku
			var player = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D/PlayerCharacterInstance")
			if player:
				player.increase_np(300.0)
				player.check_zenkai_conditions(target_char.current_np)
				target_char.check_zenkai_conditions(player.current_np)
				
			print("[COMBATE DE KI] ¡GOLPE FÍSICO DIRECTO A %s! Daño NP: %.1f | Velocidad: %.2f m/s" % [target_char.name, damage_np, impact_speed])
			_spawn_ki_impact_vfx(contact_point, energy_color)
		else:
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

# --- Esferas y Luces de Carga de Ki Blast Procedimentales ---

## Configura e instancia la esfera de Ki y la luz de energía en el origen de XR
func _setup_charging_ki_sphere() -> void:
	var sphere = SphereMesh.new()
	sphere.radius = 0.035 # Radio de la palma aprox (sin incluir dedos)
	sphere.height = 0.070
	sphere.radial_segments = 32
	sphere.rings = 16

	# 1. Crear procedimentalmente el Núcleo (Core) de Ki
	charging_ki_sphere = MeshInstance3D.new()
	charging_ki_sphere.name = "ProceduralKiSphere_" + hand_side
	charging_ki_sphere.mesh = sphere
	
	# Material de Shader para el plasma denso del Core
	var mat_core = ShaderMaterial.new()
	mat_core.shader = KiSphereShader
	mat_core.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.9))
	mat_core.set_shader_parameter("core_glow", 4.0)
	charging_ki_sphere.material_override = mat_core
	charging_ki_sphere.visible = false
	
	if xr_origin:
		xr_origin.call_deferred("add_child", charging_ki_sphere)
	else:
		call_deferred("add_child", charging_ki_sphere)
		
	# 2. Crear procedimentalmente la Corona de Rayos (Corona)
	charging_ki_corona = MeshInstance3D.new()
	charging_ki_corona.name = "ProceduralKiCorona_" + hand_side
	charging_ki_corona.mesh = sphere
	
	# Material de Shader para la corona eléctrica
	var mat_corona = ShaderMaterial.new()
	mat_corona.shader = KiCoronaShader
	mat_corona.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.85))
	mat_corona.set_shader_parameter("vertex_displacement", 0.05)
	charging_ki_corona.material_override = mat_corona
	charging_ki_corona.visible = false
	
	if xr_origin:
		xr_origin.call_deferred("add_child", charging_ki_corona)
	else:
		call_deferred("add_child", charging_ki_corona)
		
	# 3. Crear procedimentalmente la luz de Ki
	charging_ki_light = OmniLight3D.new()
	charging_ki_light.name = "ProceduralKiLight_" + hand_side
	charging_ki_light.light_color = energy_color
	charging_ki_light.light_energy = 0.0
	charging_ki_light.omni_range = 1.5
	charging_ki_light.visible = false
	
	if xr_origin:
		xr_origin.call_deferred("add_child", charging_ki_light)
	else:
		call_deferred("add_child", charging_ki_light)
		
	print("[VRHandVisualizer] %s: Esferas concéntricas (Core + Corona) y luz de Ki Blast inicializadas." % (parent_node.name if parent_node else name))

## Actualiza el tamaño, la posición y la pulsación sinusoidal del Ki Blast en base a la carga real
func _update_charging_ki_sphere(delta: float) -> void:
	if not charging_ki_sphere or not charging_ki_corona or not charging_ki_light or not gesture_tree_ref:
		return
		
	# Leer variables de carga de forma segura desde el Trie
	var is_charging: bool = false
	var charge_time: float = 0.0
	
	if hand_side == "Left":
		is_charging = gesture_tree_ref.get("is_charging_ki_blast_left") if "is_charging_ki_blast_left" in gesture_tree_ref else false
		charge_time = gesture_tree_ref.get("ki_blast_charge_time_left") if "ki_blast_charge_time_left" in gesture_tree_ref else 0.0
	else:
		is_charging = gesture_tree_ref.get("is_charging_ki_blast_right") if "is_charging_ki_blast_right" in gesture_tree_ref else false
		charge_time = gesture_tree_ref.get("ki_blast_charge_time_right") if "ki_blast_charge_time_right" in gesture_tree_ref else 0.0
		
	if is_charging and charge_time > 0.0:
		# Hacer visibles esferas y luz
		charging_ki_sphere.visible = true
		charging_ki_corona.visible = true
		charging_ki_light.visible = true
		
		# Determinar posición de la esfera (Palma o fallback del control)
		var palm_pos = global_position
		if tracker:
			var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
			if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
				var palm_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
				if xr_origin:
					palm_pos = xr_origin.global_transform * palm_local.origin
				else:
					palm_pos = palm_local.origin
					
		charging_ki_sphere.global_position = palm_pos
		charging_ki_corona.global_position = palm_pos
		charging_ki_light.global_position = palm_pos
		
		# Calcular factor de escala progresiva: de 0.2x inicial hasta 2.0x a los 2.5 segundos (crecimiento dinámico de Ki)
		var scale_factor = 0.2 + (charge_time / 2.5) * 1.8
		
		# Aplicar vibración sinusoidal orgánica tipo Dragon Ball
		var pulse = scale_factor * (1.0 + randf_range(-0.06, 0.06))
		
		# Escalar ambas esferas concéntricamente
		charging_ki_sphere.scale = Vector3.ONE * pulse
		charging_ki_corona.scale = Vector3.ONE * pulse * 1.15 # La corona envuelve al núcleo
		
		# Actualizar brillo y rango de la luz procedimental
		charging_ki_light.light_energy = (charge_time / 2.5) * 4.0 + 1.0
		charging_ki_light.omni_range = 1.0 + (charge_time / 2.5) * 2.0
	else:
		# Ocultar todo
		charging_ki_sphere.visible = false
		charging_ki_corona.visible = false
		charging_ki_light.visible = false
