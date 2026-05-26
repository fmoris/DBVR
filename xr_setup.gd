extends XROrigin3D

# --- Interfaces y Trackers OpenXR ---
var xr_interface: XRInterface
var left_hand_tracker: XRHandTracker
var right_hand_tracker: XRHandTracker

# --- Estados Previos para Logs Limpios ---
var last_state_left: String = ""
var last_state_right: String = ""

# --- Referencias de Nodos Dinámicos ---
@onready var camera: XRCamera3D = $XRCamera3D
@onready var ki_sphere: MeshInstance3D = get_node_or_null("RightHand/KiSphere")

func _ready() -> void:
	# Inicialización robusta de OpenXR según tutorial oficial
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR inicializado exitosamente en Godot Engine.")
		
		# IMPORTANTE: Para evitar el parpadeo (Judder), activamos VSync 
		# sincronizado con el visor.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		
		# Habilitar renderizado XR en el Viewport principal
		get_viewport().use_xr = true
		
		# Habilitar sombreado de tasa variable (VRS) dinámico para XR en el viewport si está disponible
		if "vrs_mode" in get_viewport():
			get_viewport().vrs_mode = Viewport.VRS_XR
			print("[OpenXR] VRS_XR dinámico activado con éxito en el Viewport.")
	else:
		print("Advertencia: OpenXR no detectado o no inicializado. Verifique la conexión del visor/simulador.")

func _process(_delta: float) -> void:
	# Descubrimiento dinámico de Hand Trackers en caso de conexión tardía o reconexión
	if left_hand_tracker == null or right_hand_tracker == null:
		var trackers = XRServer.get_trackers(XRServer.TRACKER_HAND)
		for tracker_name in trackers:
			var t = trackers[tracker_name]
			if t is XRHandTracker:
				if t.hand == XRHandTracker.TRACKER_HAND_LEFT:
					left_hand_tracker = t
				elif t.hand == XRHandTracker.TRACKER_HAND_RIGHT:
					right_hand_tracker = t

	# Análisis continuo de posturas para feedback local
	if left_hand_tracker:
		analyze_hand_pose(left_hand_tracker, "Izquierda")
	if right_hand_tracker:
		analyze_hand_pose(right_hand_tracker, "Derecha")

func analyze_hand_pose(tracker: XRHandTracker, hand_name: String) -> void:
	var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST)
	
	# Verificar si la posición de la muñeca es válida y está siendo rastreada
	if !(flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
		if ki_sphere and hand_name == "Derecha":
			ki_sphere.visible = false
		return

	var wrist_pose = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
	var hand_pos = wrist_pose.origin
	var head_pos = camera.position if camera else Vector3.ZERO
	
	# 1. Gesto de Dedos (Apertura de la mano)
	var index_tip = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var dist_fist = hand_pos.distance_to(index_tip)
	var finger_state = "ABIERTA" if dist_fist > 0.1 else "CERRADA"

	# 2. Posición Espacial Relativa a la Cabeza/Cámara
	var spatial_state = ""
	var dist_to_head = hand_pos.distance_to(head_pos)
	
	if dist_to_head > 0.55:
		spatial_state = "BRAZO ESTIRADO"
	elif hand_pos.y > head_pos.y:
		spatial_state = "MANO ARRIBA"
	elif hand_pos.y < (head_pos.y * 0.6):
		spatial_state = "CERCA DE CADERA"
	else:
		spatial_state = "POSICIÓN NEUTRAL"

	# 3. Lógica de Efectos Visuales Segura (Esfera de Ki)
	if hand_name == "Derecha" and ki_sphere != null:
		if finger_state == "ABIERTA" and (spatial_state == "CERCA DE CADERA" or spatial_state == "BRAZO ESTIRADO"):
			ki_sphere.visible = true
			# Micro-animación premium: vibración orgánica de la energía
			ki_sphere.scale = Vector3.ONE * (1.0 + randf_range(-0.06, 0.06))
		else:
			ki_sphere.visible = false

	# 4. Logs de Cambio de Estado (Evita saturar consola)
	var current_state = finger_state + "|" + spatial_state
	if hand_name == "Izquierda":
		if current_state != last_state_left:
			print("[OpenXR HandTracking] [%s] %s" % [hand_name, current_state])
			last_state_left = current_state
	else:
		if current_state != last_state_right:
			print("[OpenXR HandTracking] [%s] %s" % [hand_name, current_state])
			last_state_right = current_state

# --- APIs de Consulta Espacial Nativas para la Fase 3 (GesturePhaseTree) ---

## Retorna el tracker asociado a la mano solicitada (0: Izquierda, 1: Derecha)
func get_hand_tracker(hand_side: int) -> XRHandTracker:
	return left_hand_tracker if hand_side == 0 else right_hand_tracker

## Verifica si un joint específico tiene posición válida en el espacio
func is_joint_valid(hand_side: int, joint: int) -> bool:
	var tracker = get_hand_tracker(hand_side)
	if not tracker:
		return false
	var flags = tracker.get_hand_joint_flags(joint)
	return (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0

## Retorna la posición global/espacial de un joint específico
func get_joint_position(hand_side: int, joint: int) -> Vector3:
	var tracker = get_hand_tracker(hand_side)
	if tracker and is_joint_valid(hand_side, joint):
		return tracker.get_hand_joint_transform(joint).origin
	return Vector3.ZERO

## Retorna la transformación completa del joint (posición y rotación)
func get_joint_transform(hand_side: int, joint: int) -> Transform3D:
	var tracker = get_hand_tracker(hand_side)
	if tracker and is_joint_valid(hand_side, joint):
		return tracker.get_hand_joint_transform(joint)
	return Transform3D()
