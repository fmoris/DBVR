extends Node

# --- Señales Públicas (Acción-Reacción) ---
signal phase_changed(new_phase_name: String)
signal ki_recharge_started(is_heavy: bool)
signal ki_recharge_stopped()
signal ki_blast_fired(hand_side: int) # 0: Izquierda, 1: Derecha

# NUEVA SEÑAL PARA EL DEBUGGER HUD EN VIVO
signal gesture_logged(message: String, log_type: String) # type: "success", "info", "warning", "error"

# --- Diccionario del Trie de Gestos (Base de Datos) ---
var gesture_tree: Dictionary = {
	"CROSS_ARMS_MOUTH": {
		"HANDS_CLOSED_HIP": {
			"action_trigger": "recarga_ki"
		}
	},
	"ARM_STRETCHED_OPEN_LEFT": {
		"FAST_THRUST_LEFT": {
			"action_trigger": "ki_blast_left"
		}
	},
	"ARM_STRETCHED_OPEN_RIGHT": {
		"FAST_THRUST_RIGHT": {
			"action_trigger": "ki_blast_right"
		}
	}
}

# --- Control del Trie-State-Machine ---
var current_node: Dictionary
var gesture_timer: float = 0.0
const GESTURE_TIMEOUT: float = 1.8  # Segundos máximos para pasar del Paso 1 al Paso 2
var is_charging_ki: bool = false

# --- Trackers Internos y Biometría ---
var left_tracker: XRHandTracker
var right_tracker: XRHandTracker

# Memoria de posiciones anteriores para velocidad lineal instantánea
var last_pos_left: Vector3 = Vector3.ZERO
var last_pos_right: Vector3 = Vector3.ZERO

# Umbrales Biométricos
const KIBLAST_VELOCITY_THRESHOLD: float = 2.2 # m/s
const HAND_OPEN_DISTANCE: float = 0.09        # Distancia muñeca a index_tip para mano abierta
const HAND_CLOSED_DISTANCE: float = 0.08      # Distancia muñeca a index_tip para puño cerrado

# Buffer de frames de gracia para evitar parpadeos del sensor óptico
var tracking_loss_frames: int = 0
const MAX_GRACE_FRAMES: int = 4

func _ready() -> void:
	current_node = gesture_tree
	# Enlace automático al HUD para mostrar estados generales si existe
	var hud = get_tree().root.find_child("VRHUD", true, false)
	if hud:
		if hud.has_method("update_status_text"):
			phase_changed.connect(func(text): hud.update_status_text(text))
		if hud.has_method("log_gesture_event"):
			gesture_logged.connect(func(msg, type): hud.log_gesture_event(msg, type))
			
	print("[GesturePhaseTree] Motor gestual Trie-State-Machine inicializado con éxito.")
	emit_signal("gesture_logged", "Trie-State-Machine Activo. Esperando gesto inicial...", "info")

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	# 1. Asegurar enlace continuo de trackers
	_ensure_trackers()
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	var head_height = camera.global_position.y
	var head_pos = camera.global_position
	
	# 2. Extraer validez y posiciones de los trackers de mano
	var left_valid = left_tracker and _is_joint_valid(left_tracker, XRHandTracker.HAND_JOINT_WRIST)
	var right_valid = right_tracker and _is_joint_valid(right_tracker, XRHandTracker.HAND_JOINT_WRIST)
	
	# Filtro de gracia por pérdida temporal de tracking (parpadeos)
	if not left_valid or not right_valid:
		tracking_loss_frames += 1
		if tracking_loss_frames > MAX_GRACE_FRAMES:
			if current_node != gesture_tree:
				_cancel_action("Señal de tracking perdida")
			return
	else:
		tracking_loss_frames = 0
		
	var pos_l = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if left_valid else Vector3.ZERO
	var pos_r = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if right_valid else Vector3.ZERO
	
	# Calcular velocidades lineales instantáneas
	var vel_l = pos_l.distance_to(last_pos_left) / delta if left_valid and last_pos_left != Vector3.ZERO else 0.0
	var vel_r = pos_r.distance_to(last_pos_right) / delta if right_valid and last_pos_right != Vector3.ZERO else 0.0
	
	# Guardar memoria de posiciones previas
	if left_valid: last_pos_left = pos_l
	if right_valid: last_pos_right = pos_r
	
	# 3. Lógica del Temporizador de Tolerancia del Trie
	if current_node != gesture_tree and not is_charging_ki:
		gesture_timer += delta
		if gesture_timer >= GESTURE_TIMEOUT:
			_cancel_action("Timeout de pose: tardó demasiado en completar la técnica")
			return

	# =========================================================================
	# --- EVALUACIÓN DE FIRMAS BIOMÉTRICAS (ALIMENTACIÓN AL TRIE) ---
	# =========================================================================

	# -------------------------------------------------------------------------
	# CASO 1: CARGA DE KI (2 PASOS)
	# -------------------------------------------------------------------------
	if not is_charging_ki:
		# --- PASO 1: MANOS CERRADAS CRUZADAS EN BOCA/PECHO (Inicializador) ---
		var l_closed = left_valid and _is_hand_closed(left_tracker)
		var r_closed = right_valid and _is_hand_closed(right_tracker)
		var hands_crossed = left_valid and right_valid and pos_l.distance_to(pos_r) < 0.18
		
		# Altura a nivel de boca/pecho (eje Y local de la cámara)
		var cam_local_pos_l = camera.global_transform.affine_inverse() * pos_l
		var cam_local_pos_r = camera.global_transform.affine_inverse() * pos_r
		var height_valid = cam_local_pos_l.y > -0.35 and cam_local_pos_l.y < -0.05 and cam_local_pos_r.y > -0.35 and cam_local_pos_r.y < -0.05
		
		if l_closed and r_closed and hands_crossed and height_valid:
			_feed_trie("CROSS_ARMS_MOUTH")
			
	else:
		# --- PASO 2: MANTENIMIENTO Y CARGA CONTINUA (Costados laterales de la cadera) ---
		# La carga de Ki ya está activa. Evaluamos en cada frame si sigue cumpliéndose la pose
		var l_closed = left_valid and _is_hand_closed(left_tracker)
		var r_closed = right_valid and _is_hand_closed(right_tracker)
		var height_valid = pos_l.y < (head_height * 0.65) and pos_r.y < (head_height * 0.65)
		
		# Validación Lateral (Mano Izquierda a la izquierda, Mano Derecha a la derecha)
		var cam_local_pos_l = camera.global_transform.affine_inverse() * pos_l
		var cam_local_pos_r = camera.global_transform.affine_inverse() * pos_r
		var sides_valid = cam_local_pos_l.x < -0.15 and cam_local_pos_r.x > 0.15
		
		if l_closed and r_closed and height_valid and sides_valid:
			# Se mantiene la pose. Emitimos la carga continua
			# Aumentará Ki en vr_hud
			pass
		else:
			# ¡Se rompió la pose de carga lateral! Cancelación reactiva inmediata
			_cancel_action("Pose de carga rota: manos separadas de la cadera o abiertas")
			return

	# -------------------------------------------------------------------------
	# CASO 2: KI BLAST AMBIDIESTRO (2 PASOS)
	# -------------------------------------------------------------------------
	# Evaluar de forma independiente cada mano si no se está cargando Ki general
	if not is_charging_ki:
		# --- MANO IZQUIERDA ---
		var is_stretched_l = left_valid and pos_l.distance_to(head_pos) > 0.55
		var is_open_l = left_valid and _is_hand_open(left_tracker)
		var is_chest_height_l = left_valid and pos_l.y > (head_height * 0.5) and pos_l.y < (head_height * 1.1)
		
		if is_stretched_l and is_open_l and is_chest_height_l:
			_feed_trie("ARM_STRETCHED_OPEN_LEFT")
			
			# Comprobar si en este estado intermedio se realiza el empuje explosivo (Paso 2)
			if current_node.has("FAST_THRUST_LEFT") or (current_node == gesture_tree.get("ARM_STRETCHED_OPEN_LEFT", {})):
				if vel_l >= KIBLAST_VELOCITY_THRESHOLD:
					var forward_movement = pos_l.distance_to(head_pos) - last_pos_left.distance_to(head_pos)
					if forward_movement > 0.02:
						_feed_trie("FAST_THRUST_LEFT")
		else:
			# Si el puntero está en la carga de la mano izquierda pero se retrae el brazo, cancelar
			if current_node == gesture_tree.get("ARM_STRETCHED_OPEN_LEFT", {}):
				_cancel_action("Ki Blast izquierdo cancelado: brazo retraído o mano cerrada")
				
		# --- MANO DERECHA ---
		var is_stretched_r = right_valid and pos_r.distance_to(head_pos) > 0.55
		var is_open_r = right_valid and _is_hand_open(right_tracker)
		var is_chest_height_r = right_valid and pos_r.y > (head_height * 0.5) and pos_r.y < (head_height * 1.1)
		
		if is_stretched_r and is_open_r and is_chest_height_r:
			_feed_trie("ARM_STRETCHED_OPEN_RIGHT")
			
			# Comprobar empuje explosivo (Paso 2)
			if current_node.has("FAST_THRUST_RIGHT") or (current_node == gesture_tree.get("ARM_STRETCHED_OPEN_RIGHT", {})):
				if vel_r >= KIBLAST_VELOCITY_THRESHOLD:
					var forward_movement = pos_r.distance_to(head_pos) - last_pos_right.distance_to(head_pos)
					if forward_movement > 0.02:
						_feed_trie("FAST_THRUST_RIGHT")
		else:
			# Cancelar si se retrae el brazo de carga derecho
			if current_node == gesture_tree.get("ARM_STRETCHED_OPEN_RIGHT", {}):
				_cancel_action("Ki Blast derecho cancelado: brazo retraído o mano cerrada")

# --- Lógica de Control del Trie-State-Machine ---

func _feed_trie(gesture_name: String) -> void:
	if gesture_name in current_node:
		current_node = current_node[gesture_name]
		gesture_timer = 0.0
		
		# Emitir logs intermedios de progreso
		if gesture_name == "CROSS_ARMS_MOUTH":
			emit_signal("phase_changed", "RECARGA: CONCENTRACIÓN")
			emit_signal("gesture_logged", "Paso 1: Puños cruzados en boca. ¡Concentrando energía!", "info")
		elif gesture_name == "ARM_STRETCHED_OPEN_LEFT":
			emit_signal("phase_changed", "KI BLAST IZQ: CARGANDO")
			emit_signal("gesture_logged", "Mano Izquierda abierta al frente. ¡Cargando Ki Blast!", "info")
		elif gesture_name == "ARM_STRETCHED_OPEN_RIGHT":
			emit_signal("phase_changed", "KI BLAST DER: CARGANDO")
			emit_signal("gesture_logged", "Mano Derecha abierta al frente. ¡Cargando Ki Blast!", "info")
			
		# Comprobar si se ha alcanzado una acción final
		if current_node.has("action_trigger"):
			var trigger = current_node["action_trigger"]
			_trigger_action(trigger)

func _trigger_action(action_name: String) -> void:
	if action_name == "recarga_ki":
		is_charging_ki = true
		emit_signal("phase_changed", "¡CARGA DE KI ACTIVA!")
		emit_signal("ki_recharge_started", true) # Carga Máxima activada
		emit_signal("gesture_logged", "Paso 2: ¡Carga de Ki activa a los costados de la cadera!", "success")
		
	elif action_name == "ki_blast_left":
		emit_signal("ki_blast_fired", 0) # Lanzamiento Izquierdo
		emit_signal("gesture_logged", "Paso 2: ¡Ki Blast lanzado con Mano Izquierda!", "success")
		_reset_to_idle()
		
	elif action_name == "ki_blast_right":
		emit_signal("ki_blast_fired", 1) # Lanzamiento Derecho
		emit_signal("gesture_logged", "Paso 2: ¡Ki Blast lanzado con Mano Derecha!", "success")
		_reset_to_idle()

func _cancel_action(reason: String) -> void:
	if current_node != gesture_tree or is_charging_ki:
		if is_charging_ki:
			is_charging_ki = false
			emit_signal("ki_recharge_stopped")
			
		emit_signal("phase_changed", "IDLE (POSTURA NEUTRAL)")
		emit_signal("gesture_logged", "Técnica interrumpida: " + reason, "error")
		_reset_to_idle()

func _reset_to_idle() -> void:
	current_node = gesture_tree
	gesture_timer = 0.0

# --- Métodos de Consulta Biométrica Auxiliares ---

func _ensure_trackers() -> void:
	if left_tracker == null or right_tracker == null:
		var trackers = XRServer.get_trackers(XRServer.TRACKER_HAND)
		for t_name in trackers:
			var t = trackers[t_name]
			if t is XRHandTracker:
				if t.hand == XRHandTracker.TRACKER_HAND_LEFT:
					left_tracker = t
				elif t.hand == XRHandTracker.TRACKER_HAND_RIGHT:
					right_tracker = t

func _is_joint_valid(tracker: XRHandTracker, joint: int) -> bool:
	var flags = tracker.get_hand_joint_flags(joint)
	return (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0

func _is_hand_closed(tracker: XRHandTracker) -> bool:
	if _is_joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		var wrist = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
		var index = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
		return wrist.distance_to(index) < HAND_CLOSED_DISTANCE
	return false

func _is_hand_open(tracker: XRHandTracker) -> bool:
	if _is_joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		var wrist = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
		var index = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
		return wrist.distance_to(index) >= HAND_OPEN_DISTANCE
	return true
