extends XROrigin3D

# --- Interfaces y Trackers OpenXR ---
var xr_interface: XRInterface
var left_hand_tracker: XRHandTracker
var right_hand_tracker: XRHandTracker

# --- Referencias de Nodos Dinámicos ---
@onready var camera: XRCamera3D = $XRCamera3D

func _ready() -> void:
	# Inicialización robusta de OpenXR según tutorial oficial
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		if not xr_interface.is_initialized():
			xr_interface.initialize()
			
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
		call_deferred("_align_player_to_opponent")
	else:
		print("Advertencia: OpenXR no detectado o no inicializado. Verifique la conexión del visor/simulador.")
		_adjust_camera_height_non_vr()
		call_deferred("_align_player_to_opponent")


## Alinea automáticamente la vista del jugador exactamente de frente hacia el oponente al iniciar
func _align_player_to_opponent() -> void:
	# Esperar a que el tracking de OpenXR y la escena estén completamente sincronizados
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame

	# Centrar orientación física del HMD en el punto de mira actual
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	await get_tree().process_frame
	await get_tree().process_frame

	var opp = get_parent().find_child("EnemyCharacterInstance", true, false) if get_parent() else null
	if opp and camera:
		var cam_pos = camera.global_position
		var opp_pos = opp.global_position
		var dir_to_opp = opp_pos - cam_pos
		dir_to_opp.y = 0.0

		if dir_to_opp.length_squared() > 0.01:
			var target_yaw = atan2(-dir_to_opp.x, -dir_to_opp.z)
			rotation.y = target_yaw - camera.rotation.y
			print("[XRSetup] 🎯 Jugador alineado frontalmente hacia el oponente (Yaw: %.2f rad)." % rotation.y)

func _process(_delta: float) -> void:
	# Descubrimiento dinámico de Hand Trackers en caso de conexión tardía o reconexión
	# Solo realizamos la búsqueda si OpenXR está inicializado para evitar overhead de CPU innecesario en PC
	if xr_interface and xr_interface.is_initialized():
		if left_hand_tracker == null or right_hand_tracker == null:
			var trackers = XRServer.get_trackers(XRServer.TRACKER_HAND)
			for tracker_name in trackers:
				var t = trackers[tracker_name]
				if t is XRHandTracker:
					if t.hand == XRHandTracker.TRACKER_HAND_LEFT:
						left_hand_tracker = t
					elif t.hand == XRHandTracker.TRACKER_HAND_RIGHT:
						right_hand_tracker = t

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

## Ajusta la altura local de la cámara para simular la vista del personaje en modo no-VR/editor
func _adjust_camera_height_non_vr() -> void:
	# Esperar a que la escena esté completamente instanciada
	await get_tree().process_frame
	var player_char = get_node_or_null("PlayerCharacterInstance")
	if player_char and player_char.character_data:
		var scale_factor = player_char.character_data.scale_factor
		if scale_factor <= 0.01:
			scale_factor = 1.0
		# Goku base eye level is 1.65m relative to origin floor.
		camera.position.y = 1.65 * scale_factor
		print("[XRSetup] Altura de cámara No-VR/Simulación ajustada a %.2fm para %s (escala %.2f)" % [camera.position.y, player_char.character_data.character_name, scale_factor])
