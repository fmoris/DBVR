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
