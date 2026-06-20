extends Node

# --- Precarga Estática de Recursos (Ch 9 - Optimización Quest 3) ---
const ProceduralKiProjectileScript = preload("res://scripts/ProceduralKiProjectile.gd")
const KiSphereShader = preload("res://ki_sphere.gdshader")
const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")

# --- Señales Públicas (Acción-Reacción) ---
signal phase_changed(new_phase_name: String)
signal ki_recharge_started(is_heavy: bool)
signal ki_recharge_stopped()
signal ki_blast_fired(hand_side: int, is_charged: bool) # 0: Izquierda, 1: Derecha, con modificador de cargado
signal ki_blast_charging(hand_side: int, charge_time: float, delta: float) # Carga progresiva en vivo

# NUEVA SEÑAL PARA EL DEBUGGER HUD EN VIVO
signal gesture_logged(message: String, log_type: String) # type: "success", "info", "warning", "error"
signal hand_states_updated(left_desc: String, right_desc: String)

# --- Diccionario del Trie de Gestos (Base de Datos) ---
var gesture_tree: Dictionary = {
	"RECHARGE_PREP": {
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
var is_charging_ki: bool = false

# --- Control de Carga de Ki Blast (Espejo y Simétrico) ---
var ki_blast_charge_time_left: float = 0.0
var ki_blast_charge_time_right: float = 0.0
var is_charging_ki_blast_left: bool = false
var is_charging_ki_blast_right: bool = false

# --- Reproductores de Audio de Carga de Ki y Ki Blast ---
var aura_start_player: AudioStreamPlayer = null
var aura_loop_player: AudioStreamPlayer = null
var ki_blast_charge_player: AudioStreamPlayer = null

# --- Trackers Internos y Biometría ---
var left_tracker: XRHandTracker
var right_tracker: XRHandTracker

# Memoria de posiciones anteriores para velocidad lineal instantánea
var last_pos_left: Vector3 = Vector3.ZERO
var last_pos_right: Vector3 = Vector3.ZERO

# Umbrales Biométricos
const HAND_OPEN_DISTANCE: float = 0.095       # Distancia muñeca a index_tip para mano completamente abierta (dedos estirados)
const HAND_CLOSED_DISTANCE: float = 0.08      # Distancia muñeca a index_tip para puño cerrado

# Buffer de frames de gracia para evitar parpadeos del sensor óptico
var tracking_loss_frames: int = 0
const MAX_GRACE_FRAMES: int = 4

# Timer para limitar la frecuencia de debug de zonas en consola
var debug_log_timer: float = 0.0

func _ready() -> void:
	current_node = gesture_tree
	_setup_sound_players()
	# Enlace automático al HUD para mostrar estados generales si existe
	var hud = get_tree().root.find_child("VRHUD", true, false)
	if hud:
		if hud.has_method("update_status_text"):
			phase_changed.connect(func(text): hud.update_status_text(text))
		if hud.has_method("log_gesture_event"):
			gesture_logged.connect(func(msg, type): hud.log_gesture_event(msg, type))
			
	print("[GesturePhaseTree] Motor gestual Trie-State-Machine v3 (GSS v3) inicializado con éxito.")
	emit_signal("gesture_logged", "GSS v3 Activo. Esperando gesto inicial...", "info")

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	# 1. Asegurar enlace continuo de trackers
	_ensure_trackers()
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	# 2. Calcular el torso de referencia (up vector absoluto, rotación Y horizontal)
	var torso_pos = camera.global_position - Vector3(0, 0.40, 0)
	var forward_xz = -camera.global_transform.basis.z
	forward_xz.y = 0.0
	forward_xz = forward_xz.normalized()
	
	if forward_xz.length_squared() < 0.001:
		forward_xz = Vector3.FORWARD
		
	var torso_z = -forward_xz
	var torso_x = Vector3.UP.cross(torso_z).normalized()
	var torso_y = Vector3.UP
	var torso_transform = Transform3D(Basis(torso_x, torso_y, torso_z), torso_pos)
	
	# 3. Clasificar los estados discretizados de las manos
	var left_state = _classify_hand_state(left_tracker, 0, torso_transform, delta)
	var right_state = _classify_hand_state(right_tracker, 1, torso_transform, delta)
	
	# Emitir señal de actualización de estados de manos para el HUD
	var left_desc = "%s-%s-%s-%s-%s" % [left_state.height, left_state.lateral, left_state.depth, left_state.shape, left_state.speed] if left_state.valid else "DESCONECTADA"
	var right_desc = "%s-%s-%s-%s-%s" % [right_state.height, right_state.lateral, right_state.depth, right_state.shape, right_state.speed] if right_state.valid else "DESCONECTADA"
	emit_signal("hand_states_updated", left_desc, right_desc)
	
	# Debug periódico de zonas en consola
	debug_log_timer += delta
	if debug_log_timer >= 0.5:
		debug_log_timer = 0.0
		if left_state.valid or right_state.valid:
			var left_log = "%s-%s-%s-%s-%s" % [left_state.height, left_state.lateral, left_state.depth, left_state.shape, left_state.speed] if left_state.valid else "OFF"
			var right_log = "%s-%s-%s-%s-%s" % [right_state.height, right_state.lateral, right_state.depth, right_state.shape, right_state.speed] if right_state.valid else "OFF"
			print("[GSS-Debug] L: %s | R: %s" % [left_log, right_log])
	
	# 4. Control de gracia para pérdida temporal de señal
	var active_gesture_needs_left = false
	var active_gesture_needs_right = false
	
	if is_charging_ki or current_node == gesture_tree.get("RECHARGE_PREP", {}):
		active_gesture_needs_left = true
		active_gesture_needs_right = true
	elif is_charging_ki_blast_left or current_node == gesture_tree.get("ARM_STRETCHED_OPEN_LEFT", {}):
		active_gesture_needs_left = true
	elif is_charging_ki_blast_right or current_node == gesture_tree.get("ARM_STRETCHED_OPEN_RIGHT", {}):
		active_gesture_needs_right = true
		
	var tracking_failed = false
	if active_gesture_needs_left and not left_state.valid:
		tracking_failed = true
	if active_gesture_needs_right and not right_state.valid:
		tracking_failed = true
		
	if tracking_failed:
		tracking_loss_frames += 1
		if tracking_loss_frames > MAX_GRACE_FRAMES:
			_cancel_action("Señal de tracking perdida en mano activa")
		return
	else:
		tracking_loss_frames = 0
		
	# 5. Si estamos en modo de recarga activa, evaluar condiciones de mantenimiento/ruptura
	if is_charging_ki:
		var ki_charge_valid = left_state.valid and right_state.valid and \
							left_state.shape == "CLOSED" and right_state.shape == "CLOSED" and \
							left_state.height == "HIP" and right_state.height == "HIP" and \
							left_state.depth == "CLOSE" and right_state.depth == "CLOSE"
		if not ki_charge_valid:
			_cancel_action("Pose de recarga rota (manos abiertas o fuera de la cadera)")
			return
		return # Durante la recarga de Ki, no procesamos transiciones de otros gestos
		
	# 6. Procesar carga y cancelaciones de Ki Blasts
	if is_charging_ki_blast_left:
		ki_blast_charge_time_left = min(ki_blast_charge_time_left + delta, 2.5)
		if ki_blast_charge_time_left < 2.5:
			emit_signal("ki_blast_charging", 0, ki_blast_charge_time_left, delta)
			
		var left_dropped = left_state.valid and (left_state.depth == "CLOSE" or left_state.height == "LOW")
		if left_dropped:
			_cancel_action("Carga de Ki Blast izquierdo cancelada: postura rota")
			_reset_ki_blast_charge(0)
			return
			
	if is_charging_ki_blast_right:
		ki_blast_charge_time_right = min(ki_blast_charge_time_right + delta, 2.5)
		if ki_blast_charge_time_right < 2.5:
			emit_signal("ki_blast_charging", 1, ki_blast_charge_time_right, delta)
			
		var right_dropped = right_state.valid and (right_state.depth == "CLOSE" or right_state.height == "LOW")
		if right_dropped:
			_cancel_action("Carga de Ki Blast derecho cancelada: postura rota")
			_reset_ki_blast_charge(1)
			return
			
	# 7. Evaluar reglas gestuales para avanzar en el Trie
	var detected_gesture = _match_gesture(left_state, right_state)
	if not detected_gesture.is_empty():
		_feed_trie(detected_gesture)

# --- Métodos de Clasificación y Reglas de GSS v3 ---

func _classify_hand_state(tracker: XRHandTracker, hand_side: int, torso_transform: Transform3D, delta: float) -> Dictionary:
	var state = {
		"valid": false,
		"height": "LOW",
		"lateral": "CENTER",
		"depth": "CLOSE",
		"shape": "NEUTRAL",
		"speed": "STABLE",
		"speed_val": 0.0,
		"pos_local": Vector3.ZERO
	}
	
	if not tracker:
		return state
		
	var wrist_valid = _is_joint_valid(tracker, XRHandTracker.HAND_JOINT_WRIST)
	if not wrist_valid:
		return state
		
	var camera = get_viewport().get_camera_3d()
	var xr_origin = camera.get_parent() if camera.get_parent() else self
	
	var wrist_global = xr_origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
	if wrist_global == Vector3.ZERO:
		return state
		
	state["valid"] = true
	
	# Transformar a espacio local del Torso
	var pos_local = torso_transform.affine_inverse() * wrist_global
	state["pos_local"] = pos_local
	
	# 1. Clasificación Vertical (Y)
	if pos_local.y >= 0.20:
		state["height"] = "HEAD"
	elif pos_local.y > -0.15 and pos_local.y < 0.20:
		state["height"] = "CHEST"
	elif pos_local.y > -0.50 and pos_local.y <= -0.15:
		state["height"] = "HIP"
	else:
		state["height"] = "LOW"
		
	# 2. Clasificación Horizontal (X)
	if pos_local.x < -0.15:
		state["lateral"] = "LEFT"
	elif pos_local.x > 0.15:
		state["lateral"] = "RIGHT"
	else:
		state["lateral"] = "CENTER"
		
	# 3. Clasificación de Profundidad (Z)
	# Nota: -Z es hacia adelante, así que valores más negativos significan más lejos del cuerpo.
	if pos_local.z <= -0.38:
		state["depth"] = "FAR"
	elif pos_local.z > -0.38 and pos_local.z < -0.20:
		state["depth"] = "MEDIUM"
	else:
		state["depth"] = "CLOSE"
		
	# 4. Clasificación de Apertura de Mano
	if _is_hand_closed(tracker):
		state["shape"] = "CLOSED"
	elif _is_hand_open(tracker):
		state["shape"] = "OPEN"
	else:
		state["shape"] = "NEUTRAL"
		
	# 5. Cálculo y Clasificación de Velocidad
	var last_pos = last_pos_left if hand_side == 0 else last_pos_right
	var speed_val = 0.0
	if last_pos != Vector3.ZERO:
		speed_val = wrist_global.distance_to(last_pos) / delta
	
	state["speed_val"] = speed_val
	
	if speed_val >= 2.0:
		state["speed"] = "FAST"
	elif speed_val < 0.8:
		state["speed"] = "STABLE"
	else:
		state["speed"] = "SLOW"
		
	# Guardar posición en memoria
	if hand_side == 0:
		last_pos_left = wrist_global
	else:
		last_pos_right = wrist_global
		
	return state

func _match_gesture(left_state: Dictionary, right_state: Dictionary) -> String:
	# 1. Recarga KI - Paso 1: Puños cerrados frente al pecho (no cruzados)
	if left_state.valid and right_state.valid:
		var l_closed = left_state.shape == "CLOSED"
		var r_closed = right_state.shape == "CLOSED"
		var l_chest = left_state.height == "CHEST"
		var r_chest = right_state.height == "CHEST"
		var l_side = left_state.lateral == "LEFT" or left_state.lateral == "CENTER"
		var r_side = right_state.lateral == "RIGHT" or right_state.lateral == "CENTER"
		var hands_not_crossed = left_state.pos_local.x < right_state.pos_local.x
		var l_close = left_state.depth == "CLOSE" or left_state.depth == "MEDIUM"
		var r_close = right_state.depth == "CLOSE" or right_state.depth == "MEDIUM"
		var l_stable = left_state.speed == "STABLE"
		var r_stable = right_state.speed == "STABLE"
		
		if l_closed and r_closed and l_chest and r_chest and l_side and r_side and hands_not_crossed and l_close and r_close and l_stable and r_stable:
			return "RECHARGE_PREP"
			
	# 2. Recarga KI - Paso 2: Ambos puños cerrados a los costados de la cadera (cerca)
	if left_state.valid and right_state.valid:
		var l_closed = left_state.shape == "CLOSED"
		var r_closed = right_state.shape == "CLOSED"
		var l_hip = left_state.height == "HIP"
		var r_hip = right_state.height == "HIP"
		var l_left = left_state.lateral == "LEFT"
		var r_right = right_state.lateral == "RIGHT"
		var l_close = left_state.depth == "CLOSE"
		var r_close = right_state.depth == "CLOSE"
		var l_stable = left_state.speed == "STABLE"
		var r_stable = right_state.speed == "STABLE"
		
		if l_closed and r_closed and l_hip and r_hip and l_left and r_right and l_close and r_close and l_stable and r_stable:
			return "HANDS_CLOSED_HIP"
			
	# 3. Ki Blast Izquierdo - Preparar (Mano izquierda abierta, brazo estirado, estable)
	if left_state.valid:
		var l_open = left_state.shape == "OPEN"
		var l_chest = left_state.height == "CHEST" or left_state.height == "HEAD"
		var l_left = left_state.lateral == "LEFT" or left_state.lateral == "CENTER"
		var l_far = left_state.depth == "FAR"
		var l_stable = left_state.speed == "STABLE"
		
		if l_open and l_chest and l_left and l_far and l_stable:
			return "ARM_STRETCHED_OPEN_LEFT"
			
	# 4. Ki Blast Izquierdo - Disparar (Mano izquierda abierta, brazo estirado, empuje rápido)
	if left_state.valid:
		var l_open = left_state.shape == "OPEN"
		var l_height_valid = left_state.height != "LOW"
		var l_far = left_state.depth == "FAR" or left_state.depth == "MEDIUM"
		var l_fast = left_state.speed == "FAST"
		
		if l_open and l_height_valid and l_far and l_fast:
			return "FAST_THRUST_LEFT"
			
	# 5. Ki Blast Derecho - Preparar (Mano derecha abierta, brazo estirado, estable)
	if right_state.valid:
		var r_open = right_state.shape == "OPEN"
		var r_chest = right_state.height == "CHEST" or right_state.height == "HEAD"
		var r_right = right_state.lateral == "RIGHT" or right_state.lateral == "CENTER"
		var r_far = right_state.depth == "FAR"
		var r_stable = right_state.speed == "STABLE"
		
		if r_open and r_chest and r_right and r_far and r_stable:
			return "ARM_STRETCHED_OPEN_RIGHT"
			
	# 6. Ki Blast Derecho - Disparar (Mano derecha abierta, brazo estirado, empuje rápido)
	if right_state.valid:
		var r_open = right_state.shape == "OPEN"
		var r_height_valid = right_state.height != "LOW"
		var r_far = right_state.depth == "FAR" or right_state.depth == "MEDIUM"
		var r_fast = right_state.speed == "FAST"
		
		if r_open and r_height_valid and r_far and r_fast:
			return "FAST_THRUST_RIGHT"
			
	return ""

# --- Lógica de Control del Trie-State-Machine ---

func _feed_trie(gesture_name: String) -> void:
	if gesture_name in current_node:
		current_node = current_node[gesture_name]
		gesture_timer = 0.0
		
		# Emitir logs intermedios de progreso
		if gesture_name == "RECHARGE_PREP":
			emit_signal("phase_changed", "RECARGA: PREPARANDO")
			emit_signal("gesture_logged", "Paso 1: Puños cerrados frente al pecho. Preparando recarga...", "info")
		elif gesture_name == "ARM_STRETCHED_OPEN_LEFT":
			if ki_blast_charge_time_left <= 0.01:
				is_charging_ki_blast_left = true
				emit_signal("phase_changed", "KI BLAST IZQ: CARGANDO")
				emit_signal("gesture_logged", "Brazo Izquierdo estirado al frente. ¡Cargando Ki Blast!", "info")
				if ki_blast_charge_player:
					ki_blast_charge_player.play()
		elif gesture_name == "ARM_STRETCHED_OPEN_RIGHT":
			if ki_blast_charge_time_right <= 0.01:
				is_charging_ki_blast_right = true
				emit_signal("phase_changed", "KI BLAST DER: CARGANDO")
				emit_signal("gesture_logged", "Brazo Derecho estirado al frente. ¡Cargando Ki Blast!", "info")
				if ki_blast_charge_player:
					ki_blast_charge_player.play()
			
		# Comprobar si se ha alcanzado una acción final
		if current_node.has("action_trigger"):
			var trigger = current_node["action_trigger"]
			_trigger_action(trigger)

func _trigger_action(action_name: String) -> void:
	if action_name == "recarga_ki":
		is_charging_ki = true
		emit_signal("phase_changed", "¡RECARGA DE KI ACTIVA!")
		emit_signal("ki_recharge_started", true) # Carga Máxima activada
		emit_signal("gesture_logged", "Paso 2: ¡Carga de Ki activa a los costados de la cadera!", "success")
		
		# Reproducir sonidos de recarga de Ki
		if aura_start_player:
			aura_start_player.play()
		if aura_loop_player:
			aura_loop_player.play()
		
	elif action_name == "ki_blast_left":
		var is_charged = ki_blast_charge_time_left >= 1.0
		emit_signal("ki_blast_fired", 0, is_charged) # Lanzamiento Izquierdo con modificador
		_spawn_ki_blast_projectile(0, is_charged) # Spawneo del proyectil real en la escena
		if is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Izquierda!", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast rápido lanzado con Mano Izquierda!", "success")
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
		_reset_ki_blast_charge(0)
		_reset_to_idle()
		
	elif action_name == "ki_blast_right":
		var is_charged = ki_blast_charge_time_right >= 1.0
		emit_signal("ki_blast_fired", 1, is_charged) # Lanzamiento Derecho con modificador
		_spawn_ki_blast_projectile(1, is_charged) # Spawneo del proyectil real en la escena
		if is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Derecha!", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast rápido lanzado con Mano Derecha!", "success")
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
		_reset_ki_blast_charge(1)
		_reset_to_idle()

## Instancia procedimentalmente un proyectil de energía Ki 3D brillante que vuela e impacta dinámicamente
func _spawn_ki_blast_projectile(hand_side: int, is_charged: bool) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	# Determinar color de la energía
	var energy_color = Color(0.0, 0.7, 1.0, 0.9) # Cian por defecto para Izquierda
	if hand_side == 1:
		energy_color = Color(1.0, 0.6, 0.1, 0.9) # Dorada para Derecha
		
	# Punto inicial de lanzamiento: Hacia adelante en frente de la mirada
	var spawn_pos = camera.global_position - camera.global_transform.basis.z * 0.4
	
	# Intentar obtener la posición exacta de la palma de la mano en global
	var tracker = left_tracker if hand_side == 0 else right_tracker
	if tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			var xr_origin = camera.get_parent()
			if xr_origin:
				spawn_pos = xr_origin.global_transform * palm_local
				
	# Dirección del proyectil: Eje frontal de la cámara (hacia donde mira el jugador)
	var velocity_dir = -camera.global_transform.basis.z.normalized()
	
	# Atributos de escala y velocidad según carga
	var projectile_radius = 0.05
	var speed = 28.0
	if is_charged:
		projectile_radius = 0.18
		speed = 14.0
		
	# Crear el nodo principal del proyectil
	var projectile = Node3D.new()
	projectile.name = "ProceduralKiProjectile_" + str(hand_side) + "_" + str(Time.get_ticks_msec())
	projectile.global_position = spawn_pos
	
	# 1. Malla visual del Núcleo (Core)
	var mesh_core = MeshInstance3D.new()
	mesh_core.name = "CoreMesh"
	var sphere_core = SphereMesh.new()
	sphere_core.radius = projectile_radius
	sphere_core.height = projectile_radius * 2.0
	sphere_core.radial_segments = 16
	sphere_core.rings = 8
	mesh_core.mesh = sphere_core
	
	var mat_core = ShaderMaterial.new()
	mat_core.shader = KiSphereShader
	mat_core.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.95))
	mat_core.set_shader_parameter("core_glow", 4.5)
	mesh_core.material_override = mat_core
	projectile.add_child(mesh_core)
	
	# 2. Malla visual de la Corona de Rayos
	var mesh_corona = MeshInstance3D.new()
	mesh_corona.name = "CoronaMesh"
	var sphere_corona = SphereMesh.new()
	sphere_corona.radius = projectile_radius * 1.15
	sphere_corona.height = projectile_radius * 2.30
	sphere_corona.radial_segments = 16
	sphere_corona.rings = 8
	mesh_corona.mesh = sphere_corona
	
	var mat_corona = ShaderMaterial.new()
	mat_corona.shader = KiCoronaShader
	mat_corona.set_shader_parameter("base_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.85))
	mat_corona.set_shader_parameter("vertex_displacement", 0.04)
	mesh_corona.material_override = mat_corona
	projectile.add_child(mesh_corona)
	
	# Luz dinámica omnidireccional asociada
	var light = OmniLight3D.new()
	light.light_color = energy_color
	light.light_energy = 5.0 if is_charged else 2.5
	light.omni_range = 3.0 if is_charged else 1.5
	projectile.add_child(light)
	
	# Añadir el proyectil a la raíz del árbol
	get_tree().root.add_child(projectile)
	
	# Asignar el script físico estático precompilado
	projectile.set_script(ProceduralKiProjectileScript)
	projectile.set("speed_velocity", velocity_dir * speed)
	projectile.set("p_radius", projectile_radius)
	projectile.set("p_color", energy_color)
	
	# Configurar el ciclo de física del proyectil
	projectile.set_physics_process(true)

func _cancel_action(reason: String) -> void:
	if current_node != gesture_tree or is_charging_ki or is_charging_ki_blast_left or is_charging_ki_blast_right:
		if is_charging_ki:
			is_charging_ki = false
			emit_signal("ki_recharge_stopped")
			
			# Detener sonidos de recarga de Ki
			if aura_start_player:
				aura_start_player.stop()
			if aura_loop_player:
				aura_loop_player.stop()
			
		# Detener sonidos de carga de Ki Blast
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
			
		_reset_ki_blast_charge(0)
		_reset_ki_blast_charge(1)
		emit_signal("phase_changed", "IDLE (POSTURA NEUTRAL)")
		emit_signal("gesture_logged", "Técnica interrumpida: " + reason, "error")
		_reset_to_idle()

func _reset_to_idle() -> void:
	current_node = gesture_tree
	gesture_timer = 0.0

func _reset_ki_blast_charge(hand_side: int) -> void:
	if hand_side == 0:
		ki_blast_charge_time_left = 0.0
		is_charging_ki_blast_left = false
	else:
		ki_blast_charge_time_right = 0.0
		is_charging_ki_blast_right = false

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

# --- Configuración Procedimental de Reproductores de Audio ---

func _setup_sound_players() -> void:
	# 1. Reproductor para el estallido inicial del aura
	aura_start_player = AudioStreamPlayer.new()
	aura_start_player.name = "AuraStartPlayer"
	var start_stream = load("res://assets/sfx/AURA.mp3")
	if start_stream:
		start_stream.loop = false
		aura_start_player.stream = start_stream
	aura_start_player.volume_db = -5.0
	add_child(aura_start_player)
	
	# 2. Reproductor para el zumbido/bucle continuo de la energía
	aura_loop_player = AudioStreamPlayer.new()
	aura_loop_player.name = "AuraLoopPlayer"
	var loop_stream = load("res://assets/sfx/aura_loop.mp3")
	if loop_stream:
		loop_stream.loop = true
		aura_loop_player.stream = loop_stream
	aura_loop_player.volume_db = -9.0
	add_child(aura_loop_player)
	
	# 3. Reproductor para el efecto de carga del Ki Blast
	ki_blast_charge_player = AudioStreamPlayer.new()
	ki_blast_charge_player.name = "KiBlastChargePlayer"
	var charge_stream = load("res://assets/sfx/Charged_KI_Blast_1.mp3")
	if charge_stream:
		charge_stream.loop = false
		ki_blast_charge_player.stream = charge_stream
	ki_blast_charge_player.volume_db = -6.0
	add_child(ki_blast_charge_player)
	
	print("[GesturePhaseTree] Reproductores de audio inicializados con éxito.")
