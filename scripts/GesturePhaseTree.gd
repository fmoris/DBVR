extends Node

# --- Señales Públicas (Acción-Reacción) ---
signal phase_changed(new_phase_name: String)
signal ki_recharge_started(is_heavy: bool)
signal ki_recharge_stopped()
signal ki_blast_fired(hand_side: int, is_charged: bool) # 0: Izquierda, 1: Derecha, con modificador de cargado
signal ki_blast_charging(hand_side: int, charge_time: float, delta: float) # Carga progresiva en vivo

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
const KIBLAST_VELOCITY_THRESHOLD: float = 2.2 # m/s
const HAND_OPEN_DISTANCE: float = 0.115       # Distancia muñeca a index_tip para mano completamente abierta (dedos estirados)
const HAND_CLOSED_DISTANCE: float = 0.08      # Distancia muñeca a index_tip para puño cerrado

# Buffer de frames de gracia para evitar parpadeos del sensor óptico
var tracking_loss_frames: int = 0
const MAX_GRACE_FRAMES: int = 4

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
	
	# Filtro de gracia por pérdida temporal de tracking (parpadeos) específico de la mano activa
	var active_gesture_needs_left = false
	var active_gesture_needs_right = false
	
	if is_charging_ki or current_node == gesture_tree.get("CROSS_ARMS_MOUTH", {}):
		active_gesture_needs_left = true
		active_gesture_needs_right = true
	elif is_charging_ki_blast_left or current_node == gesture_tree.get("ARM_STRETCHED_OPEN_LEFT", {}):
		active_gesture_needs_left = true
	elif is_charging_ki_blast_right or current_node == gesture_tree.get("ARM_STRETCHED_OPEN_RIGHT", {}):
		active_gesture_needs_right = true
		
	var tracking_failed = false
	if active_gesture_needs_left and not left_valid:
		tracking_failed = true
	if active_gesture_needs_right and not right_valid:
		tracking_failed = true
		
	if tracking_failed:
		tracking_loss_frames += 1
		if tracking_loss_frames > MAX_GRACE_FRAMES:
			_cancel_action("Señal de tracking perdida en mano activa")
		return # RETORNAR INMEDIATAMENTE: Conserva el estado e impide cancelaciones en cero
	else:
		tracking_loss_frames = 0
		
	# Obtener el ancestro XROrigin3D de la cámara de forma robusta para transformar coordenadas locales a globales reales
	var xr_origin = camera.get_parent() if camera.get_parent() else self
	
	var pos_l = xr_origin.global_transform * left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if (left_valid and xr_origin) else Vector3.ZERO
	var pos_r = xr_origin.global_transform * right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if (right_valid and xr_origin) else Vector3.ZERO
	
	# Evitar procesar biometría si las posiciones se reportan en cero (micro-segundo de reconexión)
	if left_valid and pos_l == Vector3.ZERO:
		return
	if right_valid and pos_r == Vector3.ZERO:
		return
		
	# Calcular velocidades lineales instantáneas
	var vel_l = pos_l.distance_to(last_pos_left) / delta if left_valid and last_pos_left != Vector3.ZERO else 0.0
	var vel_r = pos_r.distance_to(last_pos_right) / delta if right_valid and last_pos_right != Vector3.ZERO else 0.0
	
	# Guardar memoria de posiciones previas
	if left_valid: last_pos_left = pos_l
	if right_valid: last_pos_right = pos_r

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
			# Se mantiene la pose lateral. La carga de Ki sigue activa.
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
		if is_charging_ki_blast_left:
			# Ya estamos en el estado intermedio de carga del Ki Blast Izquierdo.
			# Aquí las reglas de pose se flexibilizan para permitir el empuje balístico:
			# Ignoramos la pose de mano abierta e inclinación vertical momentánea.
			
			# 1. Carga continua de Ki Blast Izquierdo
			ki_blast_charge_time_left = min(ki_blast_charge_time_left + delta, 2.5)
			if ki_blast_charge_time_left < 2.5:
				emit_signal("ki_blast_charging", 0, ki_blast_charge_time_left, delta)
				
			# 2. Comprobar empuje explosivo (Fase 2)
			var forward_thrust = false
			if left_valid and last_pos_left != Vector3.ZERO:
				var move_vector = pos_l - last_pos_left
				var global_vel_vector = move_vector / delta
				var current_vel = global_vel_vector.length()
				
				# Obtener la dirección en la que mira el jugador (eje -Z de la cámara)
				var look_direction = -camera.global_transform.basis.z.normalized()
				var movement_direction = move_vector.normalized()
				
				# Dot product: debe moverse rápidamente hacia adelante (alineado con la mirada)
				var alignment = movement_direction.dot(look_direction)
				
				if current_vel >= KIBLAST_VELOCITY_THRESHOLD and alignment > 0.52:
					forward_thrust = true
			
			if forward_thrust:
				_feed_trie("FAST_THRUST_LEFT")
			else:
				# 3. Comprobar si se cancela por retracción extrema del brazo o caída
				# Permitimos flexionar el codo (tomar impulso) pero cancelamos si está extremadamente cerca o muy abajo
				if left_valid and pos_l != Vector3.ZERO:
					var cam_loc = camera.global_transform.affine_inverse() * pos_l
					var distance = pos_l.distance_to(head_pos)
					
					var is_too_close = distance < 0.25
					var is_dropped = cam_loc.y < -0.50 or cam_loc.z > -0.15
					var is_extreme_out = abs(cam_loc.x) > 0.65
					
					if is_too_close or is_dropped or is_extreme_out:
						_cancel_action("Ki Blast izquierdo cancelado: postura de brazo rota")
						_reset_ki_blast_charge(0)
		else:
			# No estamos cargando aún. Evaluar los requisitos estrictos de entrada para el Paso 1:
			# El brazo debe estar 100% estirado hacia adelante y a la altura de los hombros/pecho.
			if left_valid and pos_l != Vector3.ZERO:
				var cam_loc_l = camera.global_transform.affine_inverse() * pos_l
				var distance_l = pos_l.distance_to(head_pos)
				var is_open_l = _is_hand_open(left_tracker)
				
				# Dirección del vector muñeca-cabeza y vector de mirada frontal
				var hand_dir_l = (pos_l - head_pos).normalized()
				var look_dir = -camera.global_transform.basis.z.normalized()
				var alignment_l = hand_dir_l.dot(look_dir)
				
				# Criterios locales y globales de rigidez total:
				# 1. Estirado global: distancia > 0.60 metros (brazo extendido)
				# 2. Estirado frontal local: local z < -0.50 e integralmente alineado a mirada con alignment > 0.74 (cono frontal cerrado)
				# 3. Altura de hombros estricta: pos.y global estable respecto a head_height (pecho a hombros, máximo 40cm por debajo)
				# 4. Carril izquierdo natural del cuerpo: local x entre -0.45 y -0.05
				var is_stretched_l = distance_l > 0.60
				var is_forward_l = cam_loc_l.z < -0.50 and alignment_l > 0.74
				var is_shoulder_height_l = pos_l.y > (head_height - 0.40) and pos_l.y < (head_height + 0.12)
				var is_natural_side_l = cam_loc_l.x > -0.45 and cam_loc_l.x < -0.05
				
				if is_stretched_l and is_forward_l and is_shoulder_height_l and is_natural_side_l and is_open_l:
					_feed_trie("ARM_STRETCHED_OPEN_LEFT")
					is_charging_ki_blast_left = true
				
		# --- MANO DERECHA ---
		if is_charging_ki_blast_right:
			# Ya estamos en el estado intermedio de carga del Ki Blast Derecho.
			# Aquí las reglas de pose se flexibilizan para permitir el empuje balístico:
			# Ignoramos la pose de mano abierta e inclinación vertical momentánea.
			
			# 1. Carga continua de Ki Blast Derecho
			ki_blast_charge_time_right = min(ki_blast_charge_time_right + delta, 2.5)
			if ki_blast_charge_time_right < 2.5:
				emit_signal("ki_blast_charging", 1, ki_blast_charge_time_right, delta)
				
			# 2. Comprobar empuje explosivo (Fase 2)
			var forward_thrust = false
			if right_valid and last_pos_right != Vector3.ZERO:
				var move_vector = pos_r - last_pos_right
				var global_vel_vector = move_vector / delta
				var current_vel = global_vel_vector.length()
				
				# Obtener la dirección en la que mira el jugador (eje -Z de la cámara)
				var look_direction = -camera.global_transform.basis.z.normalized()
				var movement_direction = move_vector.normalized()
				
				# Dot product: debe moverse rápidamente hacia adelante (alineado con la mirada)
				var alignment = movement_direction.dot(look_direction)
				
				if current_vel >= KIBLAST_VELOCITY_THRESHOLD and alignment > 0.52:
					forward_thrust = true
			
			if forward_thrust:
				_feed_trie("FAST_THRUST_RIGHT")
			else:
				# 3. Comprobar si se cancela por retracción extrema del brazo o caída
				# Permitimos flexionar el codo (tomar impulso) pero cancelamos si está extremadamente cerca o muy abajo
				if right_valid and pos_r != Vector3.ZERO:
					var cam_loc = camera.global_transform.affine_inverse() * pos_r
					var distance = pos_r.distance_to(head_pos)
					
					var is_too_close = distance < 0.25
					var is_dropped = cam_loc.y < -0.50 or cam_loc.z > -0.15
					var is_extreme_out = abs(cam_loc.x) > 0.65
					
					if is_too_close or is_dropped or is_extreme_out:
						_cancel_action("Ki Blast derecho cancelado: postura de brazo rota")
						_reset_ki_blast_charge(1)
		else:
			# No estamos cargando aún. Evaluar los requisitos estrictos de entrada para el Paso 1:
			# El brazo debe estar 100% estirado hacia adelante y a la altura de los hombros/pecho.
			if right_valid and pos_r != Vector3.ZERO:
				var cam_loc_r = camera.global_transform.affine_inverse() * pos_r
				var distance_r = pos_r.distance_to(head_pos)
				var is_open_r = _is_hand_open(right_tracker)
				
				# Dirección del vector muñeca-cabeza y vector de mirada frontal
				var hand_dir_r = (pos_r - head_pos).normalized()
				var look_dir = -camera.global_transform.basis.z.normalized()
				var alignment_r = hand_dir_r.dot(look_dir)
				
				# Criterios locales y globales de rigidez total:
				# 1. Estirado global: distancia > 0.60 metros (brazo extendido)
				# 2. Estirado frontal local: local z < -0.50 e integralmente alineado a mirada con alignment > 0.74 (cono frontal cerrado)
				# 3. Altura de hombros estricta: pos.y global estable respecto a head_height (pecho a hombros, máximo 40cm por debajo)
				# 4. Carril derecho natural del cuerpo: local x entre 0.05 y 0.45
				var is_stretched_r = distance_r > 0.60
				var is_forward_r = cam_loc_r.z < -0.50 and alignment_r > 0.74
				var is_shoulder_height_r = pos_r.y > (head_height - 0.40) and pos_r.y < (head_height + 0.12)
				var is_natural_side_r = cam_loc_r.x > 0.05 and cam_loc_r.x < 0.45
				
				if is_forward_r and is_shoulder_height_r and is_natural_side_r and is_open_r and is_stretched_r:
					_feed_trie("ARM_STRETCHED_OPEN_RIGHT")
					is_charging_ki_blast_right = true

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
			if ki_blast_charge_time_left <= 0.01:
				emit_signal("phase_changed", "KI BLAST IZQ: CARGANDO")
				emit_signal("gesture_logged", "Mano Izquierda abierta al frente. ¡Cargando Ki Blast!", "info")
				if ki_blast_charge_player:
					ki_blast_charge_player.play()
		elif gesture_name == "ARM_STRETCHED_OPEN_RIGHT":
			if ki_blast_charge_time_right <= 0.01:
				emit_signal("phase_changed", "KI BLAST DER: CARGANDO")
				emit_signal("gesture_logged", "Mano Derecha abierta al frente. ¡Cargando Ki Blast!", "info")
				if ki_blast_charge_player:
					ki_blast_charge_player.play()
			
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
		
		# Reproducir sonidos de recarga de Ki
		if aura_start_player:
			aura_start_player.play()
		if aura_loop_player:
			aura_loop_player.play()
		
	elif action_name == "ki_blast_left":
		var is_charged = ki_blast_charge_time_left >= 1.0
		emit_signal("ki_blast_fired", 0, is_charged) # Lanzamiento Izquierdo con modificador
		_spawn_ki_blast_projectile(0, is_charged) # NUEVO: Spawneo del proyectil real en la escena
		if is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Izquierda! (Lento/Gigante)", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast Normal lanzado con Mano Izquierda! (Rápido)", "success")
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
		_reset_ki_blast_charge(0)
		_reset_to_idle()
		
	elif action_name == "ki_blast_right":
		var is_charged = ki_blast_charge_time_right >= 1.0
		emit_signal("ki_blast_fired", 1, is_charged) # Lanzamiento Derecho con modificador
		_spawn_ki_blast_projectile(1, is_charged) # NUEVO: Spawneo del proyectil real en la escena
		if is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Derecha! (Lento/Gigante)", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast Normal lanzado con Mano Derecha! (Rápido)", "success")
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
	
	# Malla visual de la esfera de Ki
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = projectile_radius
	sphere.height = projectile_radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh_inst.mesh = sphere
	
	# Material luminoso unshaded
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = energy_color
	mesh_inst.material_override = mat
	projectile.add_child(mesh_inst)
	
	# Luz dinámica omnidireccional asociada
	var light = OmniLight3D.new()
	light.light_color = energy_color
	light.light_energy = 5.0 if is_charged else 2.5
	light.omni_range = 3.0 if is_charged else 1.5
	projectile.add_child(light)
	
	# Añadir el proyectil a la raíz del árbol
	get_tree().root.add_child(projectile)
	
	# Definir e inyectar el comportamiento físico de viaje y colisión en el proyectil procedimental
	var script = GDScript.new()
	script.source_code = """
extends Node3D

var speed_velocity: Vector3
var lifetime_left: float = 4.0
var p_radius: float
var p_color: Color
var is_dead: bool = false
var ray_query_exclude: Array[RID] = []

func _physics_process(delta: float) -> void:
	if is_dead: return
	
	# Mover en línea recta
	var step = speed_velocity * delta
	var prev_pos = global_position
	global_position += step
	
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		queue_free()
		return
		
	# Raycast continuo para detección estable de colisiones
	var space = get_world_3d().direct_space_state
	if space:
		var parameters = PhysicsRayQueryParameters3D.create(prev_pos, global_position)
		parameters.exclude = ray_query_exclude
		var collision = space.intersect_ray(parameters)
		if collision:
			is_dead = true
			_trigger_explosion(collision.position, collision.collider)

func _trigger_explosion(pos: Vector3, collider: Node) -> void:
	# Fallback de partículas local
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = p_radius * 0.5
	sphere_mesh.height = p_radius
	flash.mesh = sphere_mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = p_color
	flash.material_override = mat
	flash.global_position = pos
	get_tree().root.add_child(flash)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, \"scale\", Vector3.ONE * 5.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, \"albedo_color\", Color(p_color.r, p_color.g, p_color.b, 0.0), 0.2).set_trans(Tween.TRANS_LINEAR)
	
	# Imprimir log del combate de Ki
	print(\"[COMBATE DE KI] ¡EXPLOSIÓN DE KI BLAST! Impacto contra: \" + collider.name)
	
	# Buscar e intentar reproducir VFX de partículas de chispas en el visualizador de manos
	var hand_visualizer = get_tree().root.find_child(\"vr_hand_visualizer*\", true, false)
	if hand_visualizer and hand_visualizer.has_method(\"_spawn_ki_impact_vfx\"):
		hand_visualizer.call_deferred(\"_spawn_ki_impact_vfx\", pos, p_color)
	
	# Limpiar
	tween.chain().tween_callback(flash.queue_free)
	queue_free()
"""
	script.reload()
	projectile.set_script(script)
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
			
		# Detener sonidos de carga de Ki Blast si se cancela el gesto
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

## Inicializa e inyecta en el árbol de nodos los reproductores de audio para los efectos de sonido de Ki
func _setup_sound_players() -> void:
	# 1. Reproductor para el estallido inicial del aura
	aura_start_player = AudioStreamPlayer.new()
	aura_start_player.name = "AuraStartPlayer"
	var start_stream = load("res://assets/sfx/AURA.mp3")
	if start_stream:
		start_stream.loop = false # Un solo disparo
		aura_start_player.stream = start_stream
	aura_start_player.volume_db = -5.0 # Volumen óptimo para alta fidelidad
	add_child(aura_start_player)
	
	# 2. Reproductor para el zumbido/bucle continuo de la energía
	aura_loop_player = AudioStreamPlayer.new()
	aura_loop_player.name = "AuraLoopPlayer"
	var loop_stream = load("res://assets/sfx/aura_loop.mp3")
	if loop_stream:
		loop_stream.loop = true # Ciclado continuo
		aura_loop_player.stream = loop_stream
	aura_loop_player.volume_db = -9.0 # Ligeramente más suave
	add_child(aura_loop_player)
	
	# 3. Reproductor para el efecto de carga del Ki Blast
	ki_blast_charge_player = AudioStreamPlayer.new()
	ki_blast_charge_player.name = "KiBlastChargePlayer"
	var charge_stream = load("res://assets/sfx/Charged_KI_Blast_1.mp3")
	if charge_stream:
		charge_stream.loop = false # Tono ascendente una sola vez
		ki_blast_charge_player.stream = charge_stream
	ki_blast_charge_player.volume_db = -6.0 # Nivel de potencia premium
	add_child(ki_blast_charge_player)
	
	print("[GesturePhaseTree] Reproductores de audio para recarga de Ki y Ki Blast inicializados con éxito.")
