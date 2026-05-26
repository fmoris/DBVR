extends Node

# --- Señales Públicas (Acción-Reacción) ---
signal phase_changed(new_phase_name: String)
signal ki_recharge_started(is_heavy: bool)
signal ki_recharge_stopped()
signal ki_blast_fired(hand_side: int) # 0: Izquierda, 1: Derecha

# --- Estados del Árbol de Fases ---
enum Phase {
	IDLE,
	RECHARGE_PREP,    # Inicio de pose en cadera (Recarga Rápida)
	RECHARGE_HEAVY,   # Recarga sostenida máxima
	KIBLAST_READY     # Mano al frente lista para empujar
}

var current_phase: Phase = Phase.IDLE
var phase_name_map: Dictionary = {
	Phase.IDLE: "IDLE (POSTURA NEUTRAL)",
	Phase.RECHARGE_PREP: "RECARGA KI: RÁPIDA",
	Phase.RECHARGE_HEAVY: "RECARGA KI: CARGA MÁXIMA",
	Phase.KIBLAST_READY: "KI BLAST: LISTO"
}

# --- Trackers Internos y Biometría ---
var left_tracker: XRHandTracker
var right_tracker: XRHandTracker

# Memoria de posiciones anteriores para cálculo de velocidad lineal instantánea
var last_pos_left: Vector3 = Vector3.ZERO
var last_pos_right: Vector3 = Vector3.ZERO

# Temporizadores de persistencia
var recharge_hold_time: float = 0.0
var last_recharge_heavy_emitted: bool = false

# Umbrales Biométricos y Espaciales
const KIBLAST_VELOCITY_THRESHOLD: float = 2.2 # m/s requeridos para el empuje súbito
const RECHARGE_HEAVY_TIME: float = 0.6        # Segundos sosteniendo para activar aura pesada
const HAND_OPEN_DISTANCE: float = 0.09        # Distancia WRIST a INDEX_TIP para considerar palma abierta

func _ready() -> void:
	# Enlazar la señal de cambio de fase automáticamente al HUD si existe en la escena
	var hud = get_tree().root.find_child("VRHUD", true, false)
	if hud and hud.has_method("update_status_text"):
		phase_changed.connect(func(phase_text): hud.update_status_text(phase_text, Color(0.0, 0.95, 1.0) if "RECARGA" in phase_text else Color(0.9, 0.9, 0.9)))

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	# 1. Enlace continuo y autónomo de Hand Trackers
	_ensure_trackers()
	
	# 2. Obtener altura de referencia corporal (Invariancia de Escala)
	var camera = get_viewport().get_camera_3d()
	var head_height: float = camera.global_position.y if camera else 1.65
	var head_pos: Vector3 = camera.global_position if camera else Vector3(0, 1.65, 0)

	# 3. Extraer biometría actual de ambas manos
	var left_valid = left_tracker and _is_joint_valid(left_tracker, XRHandTracker.HAND_JOINT_WRIST)
	var right_valid = right_tracker and _is_joint_valid(right_tracker, XRHandTracker.HAND_JOINT_WRIST)

	var pos_l = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if left_valid else Vector3.ZERO
	var pos_r = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if right_valid else Vector3.ZERO

	# Calcular velocidades lineales instantáneas
	var vel_l: float = pos_l.distance_to(last_pos_left) / delta if left_valid and last_pos_left != Vector3.ZERO else 0.0
	var vel_r: float = pos_r.distance_to(last_pos_right) / delta if right_valid and last_pos_right != Vector3.ZERO else 0.0

	# Actualizar memoria de posiciones para el próximo frame
	if left_valid: last_pos_left = pos_l
	if right_valid: last_pos_right = pos_r

	# 4. Evaluación del Árbol de Fases Jerárquico
	
	# --- EVALUACIÓN A: RECARGA DE KI (Ambas manos en cadera, estables) ---
	var is_left_hip = left_valid and pos_l.y < (head_height * 0.65) and pos_l.distance_to(head_pos) > 0.15
	var is_right_hip = right_valid and pos_r.y < (head_height * 0.65) and pos_r.distance_to(head_pos) > 0.15
	var are_hands_stable = vel_l < 0.8 and vel_r < 0.8 # Baja velocidad requerida para concentración
	
	if is_left_hip and is_right_hip and are_hands_stable:
		recharge_hold_time += delta
		
		if recharge_hold_time >= RECHARGE_HEAVY_TIME:
			_set_phase(Phase.RECHARGE_HEAVY)
			if not last_recharge_heavy_emitted:
				ki_recharge_started.emit(true) # Carga Pesada (Aura Máxima)
				last_recharge_heavy_emitted = true
		else:
			_set_phase(Phase.RECHARGE_PREP)
			if recharge_hold_time <= delta * 2: # Recién entrado
				ki_recharge_started.emit(false) # Carga Rápida Ligera
	else:
		# Si salimos de la pose de recarga, reiniciamos temporizadores
		if current_phase == Phase.RECHARGE_PREP or current_phase == Phase.RECHARGE_HEAVY:
			ki_recharge_stopped.emit()
			recharge_hold_time = 0.0
			last_recharge_heavy_emitted = false
			_set_phase(Phase.IDLE)

	# --- EVALUACIÓN B: KI BLAST (Ráfaga rápida ambidiestra independiente) ---
	# Permite disparar de forma alternada o simultánea si la mano está abierta y se empuja velozmente
	if left_valid and _is_hand_open(left_tracker):
		var is_chest_height = pos_l.y > (head_height * 0.5) and pos_l.y < (head_height * 1.1)
		if is_chest_height and vel_l >= KIBLAST_VELOCITY_THRESHOLD:
			# Verificar si el movimiento fue hacia adelante alejándose del pecho
			var forward_movement = pos_l.distance_to(head_pos) - last_pos_left.distance_to(head_pos)
			if forward_movement > 0.02: # Empuje neto positivo
				ki_blast_fired.emit(0) # Fuego Izquierdo
				print("[GesturePhaseTree] ¡KI BLAST Disparado! (Mano Izquierda) | Vel: %.2f m/s" % vel_l)

	if right_valid and _is_hand_open(right_tracker):
		var is_chest_height = pos_r.y > (head_height * 0.5) and pos_r.y < (head_height * 1.1)
		if is_chest_height and vel_r >= KIBLAST_VELOCITY_THRESHOLD:
			# Verificar empuje frontal
			var forward_movement = pos_r.distance_to(head_pos) - last_pos_right.distance_to(head_pos)
			if forward_movement > 0.02:
				ki_blast_fired.emit(1) # Fuego Derecho
				print("[GesturePhaseTree] ¡KI BLAST Disparado! (Mano Derecha) | Vel: %.2f m/s" % vel_r)

# --- Funciones Auxiliares Internas ---

func _set_phase(new_phase: Phase) -> void:
	if current_phase != new_phase:
		current_phase = new_phase
		phase_changed.emit(phase_name_map[current_phase])

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

func _is_hand_open(tracker: XRHandTracker) -> bool:
	# Soporte híbrido: evalúa tracking de dedos si está presente
	if _is_joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		var wrist_pos = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
		var index_pos = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
		return wrist_pos.distance_to(index_pos) >= HAND_OPEN_DISTANCE
	# Fallback si no hay tracking de dedos: asume mano lista para ráfaga en altura de pecho
	return true
