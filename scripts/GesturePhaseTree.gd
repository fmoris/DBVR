extends Node

# --- Precarga Estática de Recursos (Ch 9 - Optimización Quest 3) ---
const ProceduralKiProjectileScript = preload("res://scripts/ProceduralKiProjectile.gd")
const KiSphereShader = preload("res://ki_sphere.gdshader")
const KiCoronaShader = preload("res://shaders/ki_corona.gdshader")
const HybridCombatControllerScript = preload("res://scripts/HybridCombatController.gd")

# Flag de modo híbrido (Auto-switching con mandos Meta Quest 3)
var is_controller_override: bool = false

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
	},
	"KAMEHAMEHA_CHARGE": {
		"KAMEHAMEHA_FIRE": {
			"action_trigger": "kamehameha"
		}
	},
	"GENKIDAMA_CHARGE": {
		"GENKIDAMA_FIRE": {
			"action_trigger": "genkidama"
		}
	},
	"GALICK_HO_CHARGE": {
		"GALICK_HO_FIRE": {
			"action_trigger": "galick_ho"
		}
	},
	"FINAL_FLASH_CHARGE": {
		"FINAL_FLASH_FIRE": {
			"action_trigger": "final_flash"
		}
	},
	"BIG_BANG_CHARGE": {
		"BIG_BANG_FIRE": {
			"action_trigger": "big_bang"
		}
	},
	"MELEE_PREP": {
		"MELEE_PUNCH": {
			"action_trigger": "melee_attack"
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

# --- Aura Visual del Jugador ---
var visual_aura: Node3D = null
var player_instance: Node3D = null

# --- Control de Carga de Habilidades Especiales ---
var is_charging_kamehameha: bool = false
var kamehameha_charge_time: float = 0.0
var is_charging_genkidama: bool = false
var genkidama_charge_time: float = 0.0
var is_charging_galick_ho: bool = false
var galick_ho_charge_time: float = 0.0
var is_charging_final_flash: bool = false
var final_flash_charge_time: float = 0.0
var is_charging_big_bang: bool = false
var big_bang_charge_time: float = 0.0
var big_bang_hand: int = 1

# Referencias a controladores VR activos provistos por HybridCombatController
var left_controller_node: XRController3D = null
var right_controller_node: XRController3D = null
var last_firing_controller: XRController3D = null
var last_firing_hand_side: int = -1

# --- Mira de Puntería Holográfica (Aim Reticle) durante Fase 1 de Carga ---
var aim_reticle_node: Node3D = null
var aim_reticle_mesh: MeshInstance3D = null
var aim_reticle_mat: StandardMaterial3D = null
var aim_reticle_texture: ImageTexture = null
var current_aim_target: Vector3 = Vector3.ZERO
var current_aim_locked: bool = false

# --- Esferas Visuales de Carga de Ki Blast en la Palma ---
var ki_blast_sphere_left: MeshInstance3D = null
var ki_blast_corona_left: MeshInstance3D = null
var ki_blast_light_left: OmniLight3D = null

var ki_blast_sphere_right: MeshInstance3D = null
var ki_blast_corona_right: MeshInstance3D = null
var ki_blast_light_right: OmniLight3D = null

# --- Articulación Melee Cheek Hand (0: Izquierda, 1: Derecha) ---
var melee_cheek_hand: int = -1

# --- Esferas Visuales de Carga Especial ---
var special_charge_sphere: MeshInstance3D = null
var special_charge_corona: MeshInstance3D = null
var special_charge_light: OmniLight3D = null

# --- Trackers Internos y Biometría ---
var left_tracker: XRHandTracker
var right_tracker: XRHandTracker

# Memoria de posiciones anteriores para velocidad lineal instantánea
var last_pos_left: Vector3 = Vector3.ZERO
var last_pos_right: Vector3 = Vector3.ZERO
var prev_camera_global_pos: Vector3 = Vector3.ZERO
var camera_forward_speed: float = 0.0
var last_hands_dist: float = 0.0
var hands_dist: float = 0.0
var hands_sep_speed: float = 0.0
var transformation_hold_timer: float = 0.0
var last_detected_fingers: int = -1

# Persistencia para modelo de Torso Yaw Deadzone
var torso_yaw: float = 0.0
var torso_yaw_initialized: bool = false

# Umbrales Biométricos
const HAND_OPEN_DISTANCE: float = 0.090       # Distancia muñeca a index_tip para mano completamente abierta (dedos estirados)
const HAND_CLOSED_DISTANCE: float = 0.082      # Distancia muñeca a index_tip para puño cerrado

# Buffer de frames de gracia para evitar parpadeos del sensor óptico
var tracking_loss_frames: int = 0
const MAX_GRACE_FRAMES: int = 4

# Timer para limitar la frecuencia de debug de zonas en consola
var debug_log_timer: float = 0.0

func _ready() -> void:
	current_node = gesture_tree
	_setup_sound_players()

	# Inicializar el controlador híbrido de mandos Quest 3 para auto-switching
	var hybrid_ctrl = HybridCombatControllerScript.new()
	hybrid_ctrl.name = "HybridCombatController"
	hybrid_ctrl.gesture_tree = self
	add_child(hybrid_ctrl)

	# Enlace automático al HUD para mostrar estados generales si existe
	var hud = get_tree().root.find_child("VRHUD", true, false)
	if hud:
		if hud.has_method("update_status_text"):
			phase_changed.connect(func(text): hud.update_status_text(text))
		if hud.has_method("log_gesture_event"):
			gesture_logged.connect(func(msg, type): hud.log_gesture_event(msg, type))
			
	print("[GesturePhaseTree] Motor gestual Trie-State-Machine v3 (GSS v3) inicializado con éxito.")
	emit_signal("gesture_logged", "GSS v3 Activo. Esperando gesto inicial...", "info")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			match event.keycode:
				KEY_0:
					player.revert_to_base()
					emit_signal("gesture_logged", "[DEBUG] Revertido a forma Base", "info")
				KEY_1:
					player.transform_to(0) # Kaioken
					emit_signal("gesture_logged", "[DEBUG] Transformado a Kaioken", "info")
				KEY_2:
					player.transform_to(1) # SSJ (Desbloquea Kamehameha)
					emit_signal("gesture_logged", "[DEBUG] Transformado a SSJ (Kamehameha desbloqueado)", "info")
				KEY_3:
					player.transform_to(2) # SSB
					emit_signal("gesture_logged", "[DEBUG] Transformado a SSB", "info")
				KEY_K:
					player.recharge_ki(100.0)
					emit_signal("gesture_logged", "[DEBUG] Ki recargado al máximo (100)", "info")

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	# 0. Si el controlador híbrido de mandos Quest 3 está activo, ceder el control
	if is_controller_override:
		return

	# 0.1 Si el jugador está volando hacia el oponente, no procesar gestos
	var player_check = _get_player_instance()
	if player_check and is_instance_valid(player_check) and player_check.get("is_flying_to_opponent"):
		return

	# 1. Asegurar enlace continuo de trackers
	_ensure_trackers()
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	# Calcular velocidad de la cabeza/cámara en su eje forward
	if prev_camera_global_pos != Vector3.ZERO:
		var camera_velocity = (camera.global_position - prev_camera_global_pos) / delta
		var cam_forward = -camera.global_transform.basis.z.normalized()
		camera_forward_speed = camera_velocity.dot(cam_forward)
	else:
		camera_forward_speed = 0.0
	prev_camera_global_pos = camera.global_position
		
	# Actualizar la posición y rotación del aura dorada si está activa
	if visual_aura and is_instance_valid(visual_aura):
		var feet_pos = Vector3(camera.global_position.x, 0.5, camera.global_position.z)
		visual_aura.global_position = feet_pos + Vector3(0, 1.2, 0)
		visual_aura.rotate_y(delta * 0.5)
		
	# 2. Calcular el torso de referencia con Yaw Deadzone (amortiguación de giro de cabeza) y offset dinámico de altura
	var xr_origin: Node3D = camera.get_parent() as Node3D if (camera and camera.get_parent() is Node3D) else null
	var origin_scale_y = xr_origin.global_transform.basis.get_scale().y if xr_origin else 1.0
	var camera_height_local = camera.position.y
	var torso_offset_y = clamp(camera_height_local * 0.24, 0.25, 0.42)
	var torso_pos = camera.global_position - Vector3(0, torso_offset_y * origin_scale_y, 0)
	
	# Obtener la dirección horizontal actual de la mirada de la cámara
	var cam_fwd = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	var cam_fwd_norm = Vector3.FORWARD
	if cam_fwd.length_squared() > 0.001:
		cam_fwd_norm = cam_fwd.normalized()
		
	# Calcular el ángulo Yaw actual de la cámara
	var current_cam_yaw = atan2(cam_fwd_norm.x, cam_fwd_norm.z)
	
	# Inicializar en el primer frame válido
	if not torso_yaw_initialized:
		torso_yaw = current_cam_yaw
		torso_yaw_initialized = true
	else:
		# Calcular la diferencia angular más corta entre el torso actual y la cabeza
		var angle_diff = angle_difference(torso_yaw, current_cam_yaw)
		# Si la cabeza gira más de 35 grados (0.61086 rad), el torso es arrastrado por ella
		var max_head_turn = deg_to_rad(35.0)
		if abs(angle_diff) > max_head_turn:
			if angle_diff > 0.0:
				torso_yaw = current_cam_yaw - max_head_turn
			else:
				torso_yaw = current_cam_yaw + max_head_turn
		else:
			# Centrado pasivo suave hacia la cabeza (lerp de 5.0 * delta)
			torso_yaw = torso_yaw + angle_diff * (5.0 * delta)
				
	# Reconstruir el vector forward del torso a partir del torso_yaw
	var forward_xz = Vector3(sin(torso_yaw), 0.0, cos(torso_yaw)).normalized()
		
	var torso_z = -forward_xz
	var torso_x = Vector3.UP.cross(torso_z).normalized()
	var torso_y = Vector3.UP
	var torso_transform = Transform3D(Basis(torso_x, torso_y, torso_z), torso_pos)
	
	# 3. Clasificar los estados discretizados de las manos
	var left_state = _classify_hand_state(left_tracker, 0, torso_transform, origin_scale_y, delta)
	var right_state = _classify_hand_state(right_tracker, 1, torso_transform, origin_scale_y, delta)
	
	# Calcular la distancia y velocidad de separación relativa de las manos
	if left_state.valid and right_state.valid:
		hands_dist = left_state.pos_local.distance_to(right_state.pos_local)
		if last_hands_dist > 0.0:
			hands_sep_speed = (hands_dist - last_hands_dist) / delta
		else:
			hands_sep_speed = 0.0
	else:
		hands_dist = 0.0
		hands_sep_speed = 0.0
	
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
	elif is_charging_kamehameha or is_charging_genkidama or is_charging_galick_ho or is_charging_final_flash:
		active_gesture_needs_left = true
		active_gesture_needs_right = true
	elif is_charging_big_bang:
		active_gesture_needs_right = true
		
	var tracking_failed = false
	if not is_controller_override:
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
		
	# 4.5 Carga activa de Super Poderes (Kamehameha, Genkidama, Galick Ho, Final Flash, Big Bang)
	var detected_gesture: String = ""
	if is_charging_kamehameha:
		if not is_controller_override:
			detected_gesture = _match_gesture(left_state, right_state, torso_transform)
			if detected_gesture == "KAMEHAMEHA_FIRE":
				_feed_trie(detected_gesture)
				return
				
			var pose_valid = _check_kamehameha_pose_maintained(left_state, right_state)
			if not pose_valid:
				_cancel_action("Pose de carga de Kamehameha rota")
				return
			
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki <= 0.0:
				if kamehameha_charge_time >= 0.8:
					_feed_trie("KAMEHAMEHA_FIRE")
				else:
					_cancel_action("Ki agotado: ¡No queda energía para continuar la carga!")
				return
			var ki_drain = 18.0 * delta
			player.consume_ki(ki_drain)
			kamehameha_charge_time += delta
		gesture_timer = 0.0
		_update_special_charge_sphere(delta)
		return

	if is_charging_genkidama:
		if not is_controller_override:
			detected_gesture = _match_gesture(left_state, right_state, torso_transform)
			if detected_gesture == "GENKIDAMA_FIRE":
				_feed_trie(detected_gesture)
				return
				
			var pose_valid = _check_genkidama_pose_maintained(left_state, right_state)
			if not pose_valid:
				_cancel_action("Pose de carga de Genkidama rota")
				return
			
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki <= 0.0:
				if genkidama_charge_time >= 1.0:
					_feed_trie("GENKIDAMA_FIRE")
				else:
					_cancel_action("Ki agotado: ¡No queda energía para reunir la Genkidama!")
				return
			var ki_drain = 20.0 * delta
			player.consume_ki(ki_drain)
			genkidama_charge_time += delta
		gesture_timer = 0.0
		_update_special_charge_sphere(delta)
		return

	if is_charging_galick_ho:
		if not is_controller_override:
			detected_gesture = _match_gesture(left_state, right_state, torso_transform)
			if detected_gesture == "GALICK_HO_FIRE":
				_feed_trie(detected_gesture)
				return
				
			var pose_valid = _check_galick_ho_pose_maintained(left_state, right_state)
			if not pose_valid:
				_cancel_action("Pose de carga de Galick Ho rota")
				return
			
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki <= 0.0:
				if galick_ho_charge_time >= 0.8:
					_feed_trie("GALICK_HO_FIRE")
				else:
					_cancel_action("Ki agotado: ¡No queda energía para continuar el Galick Ho!")
				return
			var ki_drain = 18.0 * delta
			player.consume_ki(ki_drain)
			galick_ho_charge_time += delta
		gesture_timer = 0.0
		_update_special_charge_sphere(delta)
		return

	if is_charging_final_flash:
		if not is_controller_override:
			detected_gesture = _match_gesture(left_state, right_state, torso_transform)
			if detected_gesture == "FINAL_FLASH_FIRE":
				_feed_trie(detected_gesture)
				return
				
			var pose_valid = _check_final_flash_pose_maintained(left_state, right_state)
			if not pose_valid:
				_cancel_action("Pose de carga de Final Flash rota")
				return
			
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki <= 0.0:
				if final_flash_charge_time >= 1.0:
					_feed_trie("FINAL_FLASH_FIRE")
				else:
					_cancel_action("Ki agotado: ¡No queda energía para el Final Flash!")
				return
			var ki_drain = 25.0 * delta
			player.consume_ki(ki_drain)
			final_flash_charge_time += delta
		gesture_timer = 0.0
		_update_special_charge_sphere(delta)
		return

	if is_charging_big_bang:
		if not is_controller_override:
			detected_gesture = _match_gesture(left_state, right_state, torso_transform)
			if detected_gesture == "BIG_BANG_FIRE":
				_feed_trie(detected_gesture)
				return
				
			var pose_valid = _check_big_bang_pose_maintained(right_state if right_state.valid else left_state)
			if not pose_valid:
				_cancel_action("Pose de carga de Big Bang Attack rota")
				return
			
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki <= 0.0:
				if big_bang_charge_time >= 0.7:
					_feed_trie("BIG_BANG_FIRE")
				else:
					_cancel_action("Ki agotado: ¡No queda energía para el Big Bang Attack!")
				return
			var ki_drain = 22.0 * delta
			player.consume_ki(ki_drain)
			big_bang_charge_time += delta
		gesture_timer = 0.0
		_update_special_charge_sphere(delta)
		return

	# 5. Si estamos en modo de recarga activa, evaluar condiciones de mantenimiento/ruptura y transformaciones
	if is_charging_ki:
		var player = _get_player_instance()
		var is_ki_full = false
		if player and is_instance_valid(player):
			var max_ki = player.character_data.base_ki if player.character_data else 100.0
			is_ki_full = player.current_ki >= max_ki - 0.5

		if not is_controller_override:
			var shapes_valid = true
			if not is_ki_full:
				shapes_valid = left_state.shape != "OPEN" and right_state.shape != "OPEN"
				
			var ki_charge_valid = left_state.valid and right_state.valid and \
								shapes_valid and \
								left_state.height in ["HIP", "LOW", "CHEST"] and right_state.height in ["HIP", "LOW", "CHEST"] and \
								left_state.depth in ["CLOSE", "MEDIUM"] and right_state.depth in ["CLOSE", "MEDIUM"]
			if not ki_charge_valid:
				_cancel_action("Pose de recarga rota (manos abiertas o fuera de la cadera)")
				return
			
		# Si el Ki está al 100%, evaluar gestos de los dedos para transformaciones (Simétrico de 2 manos con hold de 0.6s)
		if is_ki_full:
			var left_fingers = _get_extended_fingers_count(left_tracker)
			var right_fingers = _get_extended_fingers_count(right_tracker)
			
			if left_fingers == right_fingers and left_fingers > 0:
				var fingers = left_fingers
				if fingers == last_detected_fingers:
					transformation_hold_timer += delta
					if transformation_hold_timer >= 0.6: # Sostener por 0.6s
						transformation_hold_timer = 0.0
						last_detected_fingers = -1
						
						if fingers in [1, 2, 3]:
							var target_idx = fingers - 1
							if player and is_instance_valid(player):
								if target_idx >= 0 and target_idx < player.character_data.transformations.size():
									var target_trans = player.character_data.transformations[target_idx]
									if player.current_transformation != target_trans:
										player.transform_to(target_idx)
										emit_signal("gesture_logged", "¡Transformación a " + target_trans.form_name + "!", "success")
							else:
								emit_signal("gesture_logged", "¡Simulación de Transformación %d!" % fingers, "success")
						elif fingers == 4:
							# Revertir a base
							if player and is_instance_valid(player):
								if player.current_transformation != null:
									player.revert_to_base()
									emit_signal("gesture_logged", "¡Revertido al estado base!", "success")
				else:
					last_detected_fingers = fingers
					transformation_hold_timer = 0.0
			else:
				last_detected_fingers = -1
				transformation_hold_timer = 0.0
						
		return # Durante la recarga de Ki, no procesamos transiciones de otros gestos
		
	# 6. Procesar carga y cancelaciones de Ki Blasts (Requisitos: Brazo extendido, consumo de Ki y esfera en la palma)
	if is_charging_ki_blast_left:
		# REQUISITO 1: El brazo DEBE estar extendido (depth == "FAR") y no bajo
		if not is_controller_override:
			var left_arm_ok = left_state.valid and left_state.depth == "FAR" and left_state.height != "LOW"
			if not left_arm_ok:
				_cancel_action("Carga de Ki Blast cancelada: El brazo izquierdo no está extendido al frente")
				_reset_ki_blast_charge(0)
				return
				
		# REQUISITO 4: Consumir Ki mientras carga. Si llega a 0, quema fuerza vital (Último Aliento).
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki > 0.0:
				player.consume_ki(14.0 * delta)
			else:
				var vital_drain = 120.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
			
		ki_blast_charge_time_left = min(ki_blast_charge_time_left + delta, 2.5)
		emit_signal("ki_blast_charging", 0, ki_blast_charge_time_left, delta)
		# REQUISITO 2: Esfera de Ki creciendo en la palma de la mano y mira holográfica
		_update_ki_blast_charge_sphere(0, ki_blast_charge_time_left, delta)
		if not is_controller_override:
			var sp_info = _get_hand_projectile_origin(0)
			_update_aim_reticle(sp_info["pos"], sp_info["dir"], Color(0.0, 0.7, 1.0))
			
	if is_charging_ki_blast_right:
		# REQUISITO 1: El brazo DEBE estar extendido (depth == "FAR") y no bajo
		if not is_controller_override:
			var right_arm_ok = right_state.valid and right_state.depth == "FAR" and right_state.height != "LOW"
			if not right_arm_ok:
				_cancel_action("Carga de Ki Blast cancelada: El brazo derecho no está extendido al frente")
				_reset_ki_blast_charge(1)
				return
				
		# REQUISITO 4: Consumir Ki mientras carga. Si llega a 0, quema fuerza vital (Último Aliento).
		var player = _get_player_instance()
		if player and is_instance_valid(player):
			if player.current_ki > 0.0:
				player.consume_ki(14.0 * delta)
			else:
				var vital_drain = 120.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
			
		ki_blast_charge_time_right = min(ki_blast_charge_time_right + delta, 2.5)
		emit_signal("ki_blast_charging", 1, ki_blast_charge_time_right, delta)
		# REQUISITO 2: Esfera de Ki creciendo en la palma de la mano y mira holográfica
		_update_ki_blast_charge_sphere(1, ki_blast_charge_time_right, delta)
		if not is_controller_override:
			var sp_info = _get_hand_projectile_origin(1)
			_update_aim_reticle(sp_info["pos"], sp_info["dir"], Color(1.0, 0.6, 0.1))
			
	# 7. Evaluar reglas gestuales para avanzar en el Trie
	detected_gesture = _match_gesture(left_state, right_state, torso_transform)
	if not detected_gesture.is_empty():
		_feed_trie(detected_gesture)
	else:
		# Timeout de seguridad para estados intermedios cuando no hay gestos activos
		if current_node != gesture_tree and not is_charging_ki and not is_charging_ki_blast_left and not is_charging_ki_blast_right:
			gesture_timer += delta
			if gesture_timer >= 2.5:
				_cancel_action("Tiempo límite de gesto expirado (2.5s)")
				last_hands_dist = hands_dist
				return
				
	# Guardar distancia para el siguiente frame
	last_hands_dist = hands_dist

# --- Métodos de Clasificación y Reglas de GSS v3 ---

func _classify_hand_state(tracker: XRHandTracker, hand_side: int, torso_transform: Transform3D, origin_scale_y: float, delta: float) -> Dictionary:
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
	var xr_origin: Node3D = camera.get_parent() as Node3D if (camera and camera.get_parent() is Node3D) else null
	
	var wrist_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
	var wrist_global = xr_origin.global_transform * wrist_local if xr_origin else wrist_local
	if wrist_global == Vector3.ZERO:
		return state
		
	state["valid"] = true
	
	# Transformar a espacio local del Torso
	var pos_local = torso_transform.affine_inverse() * wrist_global
	
	# Normalización por Escala del Personaje (Scale-Invariance)
	if origin_scale_y > 0.001:
		pos_local = pos_local / origin_scale_y
		
	state["pos_local"] = pos_local
	
	# 1. Clasificación Vertical (Y)
	if pos_local.y >= 0.20:
		state["height"] = "HEAD"
	elif pos_local.y > -0.10 and pos_local.y < 0.20:
		state["height"] = "CHEST"
	elif pos_local.y > -0.55 and pos_local.y <= -0.10:
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
	if pos_local.z <= -0.40:
		state["depth"] = "FAR"
	elif pos_local.z > -0.40 and pos_local.z <= -0.24:
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
		# Dividir por la escala para obtener la velocidad física real del jugador
		var dist_global = wrist_global.distance_to(last_pos)
		var scale_adj = origin_scale_y if origin_scale_y > 0.001 else 1.0
		speed_val = (dist_global / scale_adj) / delta
	
	state["speed_val"] = speed_val
	
	if speed_val >= 1.5:
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

func _match_gesture(left_state: Dictionary, right_state: Dictionary, torso_transform: Transform3D) -> String:
	# Calcular si las manos están demasiado cerca (cruzadas o juntas)
	var hands_are_close = false
	if left_state.valid and right_state.valid:
		var dist = left_state.pos_local.distance_to(right_state.pos_local)
		if dist < 0.25:
			hands_are_close = true

	# Obtener direcciones de palmas en espacio de torso
	var palm_dir_left = Vector3.ZERO
	var palm_dir_right = Vector3.ZERO
	if left_state.valid:
		palm_dir_left = _get_palm_dir_in_torso(left_tracker, torso_transform)
	if right_state.valid:
		palm_dir_right = _get_palm_dir_in_torso(right_tracker, torso_transform)

	# I. Melee - Lanzamiento (Fase 2: Separar puños rápidamente)
	if left_state.valid and right_state.valid and current_node.has("MELEE_PUNCH"):
		var fists_separated = hands_dist > 0.30
		if fists_separated:
			return "MELEE_PUNCH"

	# II. Melee - Preparar (Fase 1: Juntar los puños frente al rostro)
	if not is_charging_kamehameha and not is_charging_genkidama and not current_node.has("MELEE_PUNCH"):
		if left_state.valid and right_state.valid:
			var both_not_open = left_state.shape != "OPEN" and right_state.shape != "OPEN"
			var both_near_face = left_state.height in ["HEAD", "CHEST"] and right_state.height in ["HEAD", "CHEST"]
			var close_to_each_other = hands_dist < 0.35
			var close_to_face = left_state.depth in ["CLOSE", "MEDIUM"] and right_state.depth in ["CLOSE", "MEDIUM"]
			var stable = left_state.speed_val < 3.0 and right_state.speed_val < 3.0
			
			if both_not_open and both_near_face and close_to_each_other and close_to_face and stable:
				return "MELEE_PREP"

	# A. Kamehameha - Lanzamiento (Fuego)
	if is_charging_kamehameha:
		if left_state.valid and right_state.valid:
			var pushed_forward = left_state.depth in ["FAR", "MEDIUM"] or right_state.depth in ["FAR", "MEDIUM"]
			var fast = left_state.speed == "FAST" or right_state.speed == "FAST"
			if pushed_forward and fast:
				return "KAMEHAMEHA_FIRE"

	# B. Genkidama - Lanzamiento (Fuego)
	if is_charging_genkidama:
		if left_state.valid and right_state.valid:
			var thrown_down = left_state.pos_local.y < 0.25 or right_state.pos_local.y < 0.25
			var fast = left_state.speed == "FAST" or right_state.speed == "FAST"
			if thrown_down and fast:
				return "GENKIDAMA_FIRE"

	# C. Kamehameha - Preparar (Carga)
	if not is_charging_kamehameha and not is_charging_genkidama:
		if left_state.valid and right_state.valid:
			var dist = left_state.pos_local.distance_to(right_state.pos_local)
			var close_to_body = left_state.depth in ["CLOSE", "MEDIUM"] and right_state.depth in ["CLOSE", "MEDIUM"]
			var stable = left_state.speed_val < 2.0 and right_state.speed_val < 2.0
			var avg_x = (left_state.pos_local.x + right_state.pos_local.x) / 2.0
			
			var on_side_and_hip = false
			if avg_x > 0.08: # Carga al costado derecho
				var r_on_hip = right_state.height in ["HIP", "LOW"] and right_state.lateral in ["RIGHT", "CENTER"]
				var l_on_hip_or_chest = left_state.height in ["CHEST", "HIP", "LOW"] and left_state.lateral in ["RIGHT", "CENTER"]
				if r_on_hip and l_on_hip_or_chest:
					on_side_and_hip = true
			elif avg_x < -0.08: # Carga al costado izquierdo
				var l_on_hip = left_state.height in ["HIP", "LOW"] and left_state.lateral in ["LEFT", "CENTER"]
				var r_on_hip_or_chest = right_state.height in ["CHEST", "HIP", "LOW"] and right_state.lateral in ["LEFT", "CENTER"]
				if l_on_hip and r_on_hip_or_chest:
					on_side_and_hip = true
			
			if dist < 0.28 and on_side_and_hip and close_to_body and stable:
				return "KAMEHAMEHA_CHARGE"

	# D. Genkidama - Preparar (Reunir energía)
	if not is_charging_kamehameha and not is_charging_genkidama and not is_charging_galick_ho and not is_charging_final_flash and not is_charging_big_bang:
		if left_state.valid and right_state.valid:
			var raised = left_state.pos_local.y >= 0.25 and right_state.pos_local.y >= 0.25
			var separated = left_state.pos_local.distance_to(right_state.pos_local) >= 0.25
			var shapes_valid = left_state.shape in ["OPEN", "NEUTRAL"] and right_state.shape in ["OPEN", "NEUTRAL"]
			var stable = left_state.speed_val < 2.0 and right_state.speed_val < 2.0
			if raised and separated and shapes_valid and stable:
				var player = _get_player_instance()
				if player and player.character_data and player.character_data.character_name == "Goku":
					return "GENKIDAMA_CHARGE"

	# E. Galick Ho - Lanzamiento (Fuego)
	if is_charging_galick_ho:
		if left_state.valid and right_state.valid:
			var pushed_forward = left_state.depth == "FAR" or right_state.depth == "FAR"
			var fast = left_state.speed == "FAST" or right_state.speed == "FAST" or (left_state.speed_val > 1.2 and right_state.speed_val > 1.2)
			if pushed_forward and fast:
				return "GALICK_HO_FIRE"

	# F. Final Flash - Lanzamiento (Fuego)
	if is_charging_final_flash:
		if left_state.valid and right_state.valid:
			var hands_together = hands_dist < 0.38
			var pushed_forward = left_state.depth == "FAR" or right_state.depth == "FAR"
			var fast = left_state.speed == "FAST" or right_state.speed == "FAST" or hands_sep_speed < -0.8
			if hands_together and (pushed_forward or fast):
				return "FINAL_FLASH_FIRE"

	# G. Big Bang Attack - Lanzamiento (Fuego)
	if is_charging_big_bang:
		if right_state.valid and right_state.depth == "FAR":
			var fast = right_state.speed == "FAST" or right_state.speed_val > 1.3
			if fast:
				return "BIG_BANG_FIRE"
		elif left_state.valid and left_state.depth == "FAR":
			var fast = left_state.speed == "FAST" or left_state.speed_val > 1.3
			if fast:
				return "BIG_BANG_FIRE"

	# H. Galick Ho - Preparar (Carga junto al hombro / codos flexionados atrás)
	if not is_charging_galick_ho and not is_charging_final_flash and not is_charging_big_bang and not is_charging_kamehameha and not is_charging_genkidama:
		if left_state.valid and right_state.valid:
			var dist = left_state.pos_local.distance_to(right_state.pos_local)
			var near_shoulder = (left_state.height in ["CHEST", "HEAD"] and right_state.height in ["CHEST", "HEAD"])
			var close_to_body = left_state.depth in ["CLOSE", "MEDIUM"] and right_state.depth in ["CLOSE", "MEDIUM"]
			var stable = left_state.speed_val < 2.2 and right_state.speed_val < 2.2
			var avg_x = (left_state.pos_local.x + right_state.pos_local.x) / 2.0
			var to_one_side = abs(avg_x) > 0.05
			if dist < 0.28 and near_shoulder and close_to_body and to_one_side and stable:
				var player = _get_player_instance()
				if player and player.character_data and player.character_data.character_name == "Vegeta":
					return "GALICK_HO_CHARGE"

	# I. Final Flash - Preparar (Brazos abiertos en cruz a los lados)
	if not is_charging_final_flash and not is_charging_galick_ho and not is_charging_big_bang:
		if left_state.valid and right_state.valid:
			var wide_open = hands_dist > 0.62
			var chest_level = left_state.height in ["CHEST", "HEAD"] and right_state.height in ["CHEST", "HEAD"]
			var opposite_sides = left_state.lateral == "LEFT" and right_state.lateral == "RIGHT"
			var stable = left_state.speed_val < 2.2 and right_state.speed_val < 2.2
			if wide_open and chest_level and opposite_sides and stable:
				var player = _get_player_instance()
				if player and player.character_data and player.character_data.character_name == "Vegeta":
					return "FINAL_FLASH_CHARGE"

	# J. Big Bang Attack - Preparar (Un solo brazo extendido al frente)
	if not is_charging_big_bang and not is_charging_galick_ho and not is_charging_final_flash:
		var player = _get_player_instance()
		if player and player.character_data and player.character_data.character_name == "Vegeta":
			if right_state.valid and right_state.depth == "FAR" and right_state.height in ["CHEST", "HEAD"]:
				var r_open = right_state.shape != "CLOSED"
				var r_stable = right_state.speed_val < 1.5
				var l_not_extended = not left_state.valid or left_state.depth != "FAR"
				if r_open and r_stable and l_not_extended and not hands_are_close:
					return "BIG_BANG_CHARGE"
			elif left_state.valid and left_state.depth == "FAR" and left_state.height in ["CHEST", "HEAD"]:
				var l_open = left_state.shape != "CLOSED"
				var l_stable = left_state.speed_val < 1.5
				var r_not_extended = not right_state.valid or right_state.depth != "FAR"
				if l_open and l_stable and r_not_extended and not hands_are_close:
					return "BIG_BANG_CHARGE"

	# 1. Recarga KI - Paso 1: Puños cerrados o relajados frente al pecho (no cruzados)
	if left_state.valid and right_state.valid:
		var l_not_open = left_state.shape != "OPEN"
		var r_not_open = right_state.shape != "OPEN"
		var l_chest = left_state.height == "CHEST"
		var r_chest = right_state.height == "CHEST"
		var l_side = left_state.lateral == "LEFT" or left_state.lateral == "CENTER"
		var r_side = right_state.lateral == "RIGHT" or right_state.lateral == "CENTER"
		var hands_not_crossed = left_state.pos_local.x < right_state.pos_local.x
		var l_close = left_state.depth == "CLOSE" or left_state.depth == "MEDIUM"
		var r_close = right_state.depth == "CLOSE" or right_state.depth == "MEDIUM"
		var l_stable = left_state.speed_val < 2.0
		var r_stable = right_state.speed_val < 2.0
		
		if l_not_open and r_not_open and l_chest and r_chest and l_side and r_side and hands_not_crossed and l_close and r_close and l_stable and r_stable:
			return "RECHARGE_PREP"
			
	# 2. Recarga KI - Paso 2: Ambos puños cerrados/relajados a los costados del cuerpo (no cruzados, abiertos hacia los laterales)
	if left_state.valid and right_state.valid:
		var l_not_open = left_state.shape != "OPEN"
		var r_not_open = right_state.shape != "OPEN"
		var l_height_ok = left_state.height in ["CHEST", "HIP", "LOW"]
		var r_height_ok = right_state.height in ["CHEST", "HIP", "LOW"]
		var l_side = left_state.lateral == "LEFT"
		var r_side = right_state.lateral == "RIGHT"
		var hands_not_crossed = left_state.pos_local.x < right_state.pos_local.x
		var l_close = left_state.depth in ["CLOSE", "MEDIUM"]
		var r_close = right_state.depth in ["CLOSE", "MEDIUM"]
		var l_stable = left_state.speed_val < 2.0
		var r_stable = right_state.speed_val < 2.0
		
		if l_not_open and r_not_open and l_height_ok and r_height_ok and l_side and r_side and hands_not_crossed and l_close and r_close and l_stable and r_stable:
			return "HANDS_CLOSED_HIP"
			
	# 3. Ki Blast Izquierdo - Preparar (REQUISITO 1: Solo con Brazo Estirado al Frente depth == "FAR")
	if left_state.valid:
		var l_open = left_state.shape != "CLOSED"
		var l_chest = left_state.height == "CHEST" or left_state.height == "HEAD"
		var l_left = left_state.lateral == "LEFT" or left_state.lateral == "CENTER"
		var l_far = left_state.depth == "FAR"
		var l_stable = left_state.speed_val <= 2.0
		var l_palm_fwd = palm_dir_left.z < 0.6
		
		if l_open and l_chest and l_left and l_far and l_stable and l_palm_fwd and not hands_are_close:
			return "ARM_STRETCHED_OPEN_LEFT"
			
	# 4. Ki Blast Izquierdo - Disparar (REQUISITO 1: Solo con Brazo Estirado al Frente depth == "FAR")
	if left_state.valid:
		var l_height_valid = left_state.height != "LOW"
		var l_far = left_state.depth == "FAR"
		var l_fast = left_state.speed == "FAST" or left_state.speed_val > 1.2
		
		if l_height_valid and l_far and l_fast:
			return "FAST_THRUST_LEFT"
			
	# 5. Ki Blast Derecho - Preparar (REQUISITO 1: Solo con Brazo Estirado al Frente depth == "FAR")
	if right_state.valid:
		var r_open = right_state.shape != "CLOSED"
		var r_chest = right_state.height == "CHEST" or right_state.height == "HEAD"
		var r_right = right_state.lateral == "RIGHT" or right_state.lateral == "CENTER"
		var r_far = right_state.depth == "FAR"
		var r_stable = right_state.speed_val <= 2.0
		var r_palm_fwd = palm_dir_right.z < 0.6
		
		if r_open and r_chest and r_right and r_far and r_stable and r_palm_fwd and not hands_are_close:
			return "ARM_STRETCHED_OPEN_RIGHT"
			
	# 6. Ki Blast Derecho - Disparar (REQUISITO 1: Solo con Brazo Estirado al Frente depth == "FAR")
	if right_state.valid:
		var r_height_valid = right_state.height != "LOW"
		var r_far = right_state.depth == "FAR"
		var r_fast = right_state.speed == "FAST" or right_state.speed_val > 1.2
		
		if r_height_valid and r_far and r_fast:
			return "FAST_THRUST_RIGHT"
			
	return ""

# --- Lógica de Control del Trie-State-Machine ---

func _get_player_instance() -> Node3D:
	if player_instance == null or not is_instance_valid(player_instance):
		player_instance = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D/PlayerCharacterInstance")
	return player_instance


func _feed_trie(gesture_name: String) -> void:
	if gesture_name in current_node:
		current_node = current_node[gesture_name]
		gesture_timer = 0.0
		
		# Emitir logs intermedios de progreso
		if gesture_name == "RECHARGE_PREP":
			emit_signal("phase_changed", "RECARGA: PREPARANDO")
			emit_signal("gesture_logged", "Paso 1: Puños cerrados frente al pecho. Preparando recarga...", "info")
		elif gesture_name == "MELEE_PREP":
			emit_signal("phase_changed", "MELEE: PREPARADO")
			emit_signal("gesture_logged", "Gesto Melee Fase 1. ¡Puños juntos frente al rostro!", "info")
		elif gesture_name == "KAMEHAMEHA_CHARGE":
			var player = _get_player_instance()
			var power = _get_power_by_name("Kamehameha")
			if not power and player and player.is_in_zenkai_state:
				power = _get_power_by_name("Super Kamehameha")
			
			if player and power and player.is_power_usable(power):
				var res = player.consume_ki_or_life_force(power.ki_cost)
				if res.get("success", false):
					is_charging_kamehameha = true
					kamehameha_charge_time = 0.0
					if res.get("is_life_sacrifice", false):
						emit_signal("phase_changed", "KAMEHAMEHA: ¡ÚLTIMO ALIENTO! (-%d BP)" % int(res.get("sacrificed_np", 0.0)))
						emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para cargar Kamehameha." % int(res.get("sacrificed_np", 0.0)), "warning")
					else:
						emit_signal("phase_changed", "KAMEHAMEHA: CARGANDO")
						emit_signal("gesture_logged", "Manos unidas en la cadera. ¡Cargando Kamehameha!", "info")
					if ki_blast_charge_player:
						ki_blast_charge_player.play()
				else:
					emit_signal("gesture_logged", "No se pudo cargar Kamehameha.", "warning")
					_cancel_action("Kamehameha cancelado")
					return
			else:
				emit_signal("gesture_logged", "Kamehameha bloqueado o no disponible en este estado.", "error")
				_cancel_action("Kamehameha no disponible")
				return
		elif gesture_name == "GENKIDAMA_CHARGE":
			var player = _get_player_instance()
			var power = _get_power_by_name("Genkidama")
			if player and power and player.is_power_usable(power):
				var res = player.consume_ki_or_life_force(power.ki_cost)
				if res.get("success", false):
					is_charging_genkidama = true
					genkidama_charge_time = 0.0
					if res.get("is_life_sacrifice", false):
						emit_signal("phase_changed", "GENKIDAMA: ¡ÚLTIMO ALIENTO! (-%d BP)" % int(res.get("sacrificed_np", 0.0)))
						emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para reunir la Genkidama." % int(res.get("sacrificed_np", 0.0)), "warning")
					else:
						emit_signal("phase_changed", "GENKIDAMA: REUNIENDO ENERGÍA")
						emit_signal("gesture_logged", "Brazos alzados al cielo. ¡Reuniendo energía para la Genkidama!", "info")
					if ki_blast_charge_player:
						ki_blast_charge_player.play()
				else:
					emit_signal("gesture_logged", "No se pudo reunir la Genkidama.", "warning")
					_cancel_action("Genkidama cancelada")
					return
			else:
				emit_signal("gesture_logged", "Genkidama bloqueada o no disponible en este estado.", "error")
				_cancel_action("Genkidama no disponible")
				return
		elif gesture_name == "GALICK_HO_CHARGE":
			var player = _get_player_instance()
			var power = _get_power_by_name("Galick Ho")
			if player and power and player.is_power_usable(power):
				var res = player.consume_ki_or_life_force(power.ki_cost)
				if res.get("success", false):
					is_charging_galick_ho = true
					galick_ho_charge_time = 0.0
					if res.get("is_life_sacrifice", false):
						emit_signal("phase_changed", "GALICK HO: ¡ÚLTIMO ALIENTO! (-%d BP)" % int(res.get("sacrificed_np", 0.0)))
						emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para forzar Galick Ho." % int(res.get("sacrificed_np", 0.0)), "warning")
					else:
						emit_signal("phase_changed", "GALICK HO: CARGANDO")
						emit_signal("gesture_logged", "Manos unidas al hombro. ¡Cargando Galick Ho!", "info")
					if ki_blast_charge_player:
						ki_blast_charge_player.play()
				else:
					emit_signal("gesture_logged", "No se pudo cargar Galick Ho.", "warning")
					_cancel_action("Galick Ho cancelado")
					return
			else:
				emit_signal("gesture_logged", "Galick Ho bloqueado o no disponible.", "error")
				_cancel_action("Galick Ho no disponible")
				return
		elif gesture_name == "FINAL_FLASH_CHARGE":
			var player = _get_player_instance()
			var power = _get_power_by_name("Final Flash")
			if player and power and player.is_power_usable(power):
				var res = player.consume_ki_or_life_force(power.ki_cost)
				if res.get("success", false):
					is_charging_final_flash = true
					final_flash_charge_time = 0.0
					if res.get("is_life_sacrifice", false):
						emit_signal("phase_changed", "FINAL FLASH: ¡ÚLTIMO ALIENTO! (-%d BP)" % int(res.get("sacrificed_np", 0.0)))
						emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para forzar Final Flash." % int(res.get("sacrificed_np", 0.0)), "warning")
					else:
						emit_signal("phase_changed", "FINAL FLASH: CARGANDO RELÁMPAGOS")
						emit_signal("gesture_logged", "Brazos en cruz acumulando relámpagos. ¡Cargando Final Flash!", "info")
					if ki_blast_charge_player:
						ki_blast_charge_player.play()
				else:
					emit_signal("gesture_logged", "No se pudo cargar Final Flash.", "warning")
					_cancel_action("Final Flash cancelado")
					return
			else:
				emit_signal("gesture_logged", "Final Flash requiere transformación SSJ o Zenkai.", "error")
				_cancel_action("Final Flash bloqueado")
				return
		elif gesture_name == "BIG_BANG_CHARGE":
			var player = _get_player_instance()
			var power = _get_power_by_name("Big Bang Attack")
			if player and power and player.is_power_usable(power):
				var res = player.consume_ki_or_life_force(power.ki_cost)
				if res.get("success", false):
					is_charging_big_bang = true
					big_bang_charge_time = 0.0
					if res.get("is_life_sacrifice", false):
						emit_signal("phase_changed", "BIG BANG: ¡ÚLTIMO ALIENTO! (-%d BP)" % int(res.get("sacrificed_np", 0.0)))
						emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para forzar Big Bang Attack." % int(res.get("sacrificed_np", 0.0)), "warning")
					else:
						emit_signal("phase_changed", "BIG BANG: CARGANDO ENERGÍA")
						emit_signal("gesture_logged", "Brazo extendido con palma abierta. ¡Cargando Big Bang Attack!", "info")
					if ki_blast_charge_player:
						ki_blast_charge_player.play()
				else:
					emit_signal("gesture_logged", "No se pudo cargar Big Bang Attack.", "warning")
					_cancel_action("Big Bang Attack cancelado")
					return
			else:
				emit_signal("gesture_logged", "Big Bang Attack requiere transformación SSJ.", "error")
				_cancel_action("Big Bang Attack bloqueado")
				return
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
	var player = _get_player_instance()
	
	if action_name == "recarga_ki":
		is_charging_ki = true
		emit_signal("phase_changed", "¡RECARGA DE KI ACTIVA!")
		emit_signal("ki_recharge_started", true) # Carga Máxima activada
		emit_signal("gesture_logged", "Paso 2: ¡Carga de Ki activa a los costados de la cadera!", "success")
		
		# Mostrar aura visual dorada y luz
		_show_visual_aura(true)
		
		# Reproducir sonidos de recarga de Ki
		if aura_start_player:
			aura_start_player.play()
		if aura_loop_player:
			aura_loop_player.play()
		
	elif action_name == "ki_blast_left":
		# REQUISITO 1: Solo al tener el brazo extendido
		if not is_controller_override and not _is_hand_arm_extended(0):
			emit_signal("gesture_logged", "¡Debes extender el brazo izquierdo al frente para disparar Ki Blast!", "warning")
			_reset_ki_blast_charge(0)
			_hide_aim_reticle()
			_reset_to_idle()
			return

		var is_charged = ki_blast_charge_time_left >= 0.70
		var ki_cost = 15.0 if is_charged else 5.0
		var is_life = false
		var sacrificed_bp = 0
		if player:
			var res = player.consume_ki_or_life_force(ki_cost)
			if not res.get("success", false):
				_reset_ki_blast_charge(0)
				_hide_aim_reticle()
				_reset_to_idle()
				return
			if res.get("is_life_sacrifice", false):
				is_life = true
				sacrificed_bp = int(res.get("sacrificed_np", 0.0))

		_hide_aim_reticle()
		emit_signal("ki_blast_fired", 0, is_charged)
		_spawn_ki_blast_projectile(0, is_charged)
		if is_life:
			emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Ki Blast disparado sacrificando %d BP." % sacrificed_bp, "warning")
		elif is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Izquierda!", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast rápido lanzado con Mano Izquierda!", "success")
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
		_reset_ki_blast_charge(0)
		_reset_to_idle()
		
	elif action_name == "ki_blast_right":
		# REQUISITO 1: Solo al tener el brazo extendido
		if not is_controller_override and not _is_hand_arm_extended(1):
			emit_signal("gesture_logged", "¡Debes extender el brazo derecho al frente para disparar Ki Blast!", "warning")
			_reset_ki_blast_charge(1)
			_hide_aim_reticle()
			_reset_to_idle()
			return

		var is_charged = ki_blast_charge_time_right >= 0.70
		var ki_cost = 15.0 if is_charged else 5.0
		var is_life = false
		var sacrificed_bp = 0
		if player:
			var res = player.consume_ki_or_life_force(ki_cost)
			if not res.get("success", false):
				_reset_ki_blast_charge(1)
				_hide_aim_reticle()
				_reset_to_idle()
				return
			if res.get("is_life_sacrifice", false):
				is_life = true
				sacrificed_bp = int(res.get("sacrificed_np", 0.0))

		_hide_aim_reticle()
		emit_signal("ki_blast_fired", 1, is_charged)
		_spawn_ki_blast_projectile(1, is_charged)
		if is_life:
			emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Ki Blast disparado sacrificando %d BP." % sacrificed_bp, "warning")
		elif is_charged:
			emit_signal("gesture_logged", "Paso 2: ¡KI BLAST CARGADO lanzado con Mano Derecha!", "success")
		else:
			emit_signal("gesture_logged", "Paso 2: ¡Ki Blast rápido lanzado con Mano Derecha!", "success")
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
		_reset_ki_blast_charge(1)
		_reset_to_idle()
		
	elif action_name in ["kamehameha", "genkidama", "galick_ho", "final_flash", "big_bang"]:
		if player and is_instance_valid(player):
			var power: Resource = null
			for p in player.character_data.powers:
				if p.gesture_trigger == action_name:
					power = p
					break
					
			# Mapeo inteligente si el usuario hace el gesto característico con otro personaje:
			# Vegeta haciendo gesto de beam -> Galick Ho; Goku -> Kamehameha
			if not power:
				for p in player.character_data.powers:
					if action_name in ["kamehameha", "galick_ho"] and p.gesture_trigger in ["galick_ho", "kamehameha"]:
						power = p
						break
					elif action_name in ["genkidama", "final_flash"] and p.gesture_trigger in ["final_flash", "genkidama"]:
						power = p
						break
					elif action_name == "big_bang" and p.gesture_trigger in ["big_bang", "galick_ho"]:
						power = p
						break
					
			# Si el jugador está en Zenkai, disparar la versión Finisher de su técnica (Super Kamehameha o Final Flash)
			if player.is_in_zenkai_state:
				for p in player.character_data.powers:
					if p.is_finisher:
						power = p
						break
			
			if power:
				if player.is_power_usable(power):
					emit_signal("phase_changed", "¡%s LANZADO!" % power.power_name.to_upper())
					emit_signal("gesture_logged", "¡Gesto completado! Lanzando %s" % power.power_name, "success")
					if ki_blast_charge_player:
						ki_blast_charge_player.stop()
					_spawn_special_projectile(power)
					player.notify_attack_launched(power)
					_reset_to_idle()
				else:
					emit_signal("gesture_logged", "¡%s bloqueado o no disponible en este estado!" % power.power_name, "error")
					_reset_to_idle()
			else:
				_reset_to_idle()
		else:
			emit_signal("gesture_logged", "Error: No se encontró instancia de personaje activa.", "error")
			_reset_to_idle()

	elif action_name == "melee_attack":
		_hide_aim_reticle()
		_cleanup_ki_blast_charge_sphere(0)
		_cleanup_ki_blast_charge_sphere(1)
		if player and is_instance_valid(player):
			emit_signal("phase_changed", "¡MELEE DISPARADO!")
			emit_signal("gesture_logged", "¡Puñetazo lanzado! Volando al contrincante...", "success")
			if player.has_method("start_flight_to_opponent"):
				player.start_flight_to_opponent()
			_reset_to_idle()
		else:
			_reset_to_idle()

## Obtiene el punto de origen 3D y dirección de disparo de un Ki Blast desde la mano real
func _get_hand_projectile_origin(hand_side: int) -> Dictionary:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	var default_pos = Vector3.ZERO
	var default_dir = Vector3.FORWARD
	if camera and camera.is_inside_tree():
		default_pos = camera.global_position - camera.global_transform.basis.z * 0.4
		default_dir = -camera.global_transform.basis.z.normalized()

	var xr_origin = camera.get_parent() if (camera and camera.is_inside_tree()) else null
	if not xr_origin or not xr_origin.is_inside_tree():
		var scene_root = get_tree().current_scene if get_tree() else null
		if scene_root and scene_root.is_inside_tree():
			xr_origin = scene_root.find_child("Player_XROrigin3D", true, false)

	# 1. Controlador directo provisto por HybridCombatController o fallback a búsqueda
	var ctrl: XRController3D = left_controller_node if hand_side == 0 else right_controller_node
	if not ctrl or not ctrl.is_inside_tree():
		var ctrl_name = "LeftHand" if hand_side == 0 else "RightHand"
		ctrl = xr_origin.get_node_or_null(ctrl_name) if (xr_origin and xr_origin.is_inside_tree()) else null

	# 1.1 Si los mandos físicos de Meta Quest están presentes y activos
	if ctrl and ctrl.is_inside_tree() and ctrl.get_is_active():
		var spawn_p = ctrl.global_position
		var final_dir = default_dir
		if current_aim_target != Vector3.ZERO and current_aim_target.distance_squared_to(spawn_p) > 0.1:
			final_dir = (current_aim_target - spawn_p).normalized()
		else:
			# Auto-apuntado dinámico automático si apunta hacia el oponente en un cono suave (~55°)
			var opp = _get_opponent_instance()
			if opp and is_instance_valid(opp):
				var opp_chest = opp.global_position + Vector3(0, 1.2, 0)
				var to_opp = (opp_chest - spawn_p).normalized()
				var hand_fwd = (spawn_p - camera.global_position).normalized() if camera else default_dir
				if hand_fwd.dot(to_opp) > 0.55:
					final_dir = to_opp
				elif camera:
					final_dir = hand_fwd
			elif camera:
				final_dir = (ctrl.global_position - camera.global_position).normalized()
		return { "pos": spawn_p + final_dir * 0.12, "dir": final_dir }

	# 2. Si hay Hand Tracking óptico (26 joints)
	var tracker = left_tracker if hand_side == 0 else right_tracker
	if tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			if xr_origin and xr_origin.is_inside_tree():
				var palm_global = xr_origin.global_transform * palm_local
				var final_dir = default_dir
				if current_aim_target != Vector3.ZERO and current_aim_target.distance_squared_to(palm_global) > 0.1:
					final_dir = (current_aim_target - palm_global).normalized()
				else:
					var opp = _get_opponent_instance()
					if opp and is_instance_valid(opp):
						var opp_chest = opp.global_position + Vector3(0, 1.2, 0)
						var to_opp = (opp_chest - palm_global).normalized()
						var hand_fwd = (palm_global - camera.global_position).normalized() if camera else default_dir
						if hand_fwd.dot(to_opp) > 0.55:
							final_dir = to_opp
						elif camera:
							final_dir = hand_fwd
					elif camera:
						final_dir = (palm_global - camera.global_position).normalized()
				return { "pos": palm_global + final_dir * 0.12, "dir": final_dir }

	# 3. Fallback: proyectar desde el lateral correspondiente al lado que dispara
	var side_offset = -0.25 if hand_side == 0 else 0.25
	var fallback_pos = camera.global_position + camera.global_transform.basis.x * side_offset - camera.global_transform.basis.z * 0.4 - camera.global_transform.basis.y * 0.15 if camera else default_pos
	return { "pos": fallback_pos, "dir": default_dir }

## Obtiene el punto de origen 3D y dirección de disparo para técnicas especiales (Kamehameha, etc.)
func _get_special_projectile_origin(power_name: String) -> Dictionary:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	var default_pos = Vector3.ZERO
	var default_dir = Vector3.FORWARD
	if camera and camera.is_inside_tree():
		default_pos = camera.global_position - camera.global_transform.basis.z * 0.5
		default_dir = -camera.global_transform.basis.z.normalized()

	var xr_origin = camera.get_parent() if (camera and camera.is_inside_tree()) else null
	if not xr_origin or not xr_origin.is_inside_tree():
		var scene_root = get_tree().current_scene if get_tree() else null
		if scene_root and scene_root.is_inside_tree():
			xr_origin = scene_root.find_child("Player_XROrigin3D", true, false)

	var l_ctrl: XRController3D = left_controller_node if (left_controller_node and left_controller_node.is_inside_tree()) else (xr_origin.get_node_or_null("LeftHand") if (xr_origin and xr_origin.is_inside_tree()) else null)
	var r_ctrl: XRController3D = right_controller_node if (right_controller_node and right_controller_node.is_inside_tree()) else (xr_origin.get_node_or_null("RightHand") if (xr_origin and xr_origin.is_inside_tree()) else null)

	# Caso Genkidama: Se lanza desde arriba de la cabeza / brazos alzados
	if power_name == "Genkidama":
		var genki_pos = default_pos + Vector3(0, 1.8, 0)
		if l_ctrl and r_ctrl and l_ctrl.is_inside_tree() and r_ctrl.is_inside_tree() and l_ctrl.get_is_active() and r_ctrl.get_is_active():
			genki_pos = (l_ctrl.global_position + r_ctrl.global_position) * 0.5 + Vector3(0, 0.6, 0)
		return { "pos": genki_pos, "dir": default_dir }

	# Caso Kamehameha / Galick Ho / Final Flash / Big Bang: Sale apuntado dinámicamente desde las manos
	if l_ctrl and r_ctrl and l_ctrl.is_inside_tree() and r_ctrl.is_inside_tree() and l_ctrl.get_is_active() and r_ctrl.get_is_active():
		var aim_pos = (l_ctrl.global_position + r_ctrl.global_position) * 0.5
		if power_name == "Big Bang Attack":
			var bb_ctrl = l_ctrl if big_bang_hand == 0 else r_ctrl
			aim_pos = bb_ctrl.global_position
		
		var final_dir = default_dir
		if current_aim_target != Vector3.ZERO and current_aim_target.distance_squared_to(aim_pos) > 0.1:
			final_dir = (current_aim_target - aim_pos).normalized()
		elif camera:
			final_dir = (aim_pos - camera.global_position).normalized()
		return { "pos": aim_pos + final_dir * 0.18, "dir": final_dir }

	if left_tracker and right_tracker:
		var l_flags = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		var r_flags = right_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (l_flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) and (r_flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var l_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			var r_local = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			if xr_origin:
				var center_global = xr_origin.global_transform * ((l_local + r_local) * 0.5)
				return { "pos": center_global + default_dir * 0.15, "dir": default_dir }

	return { "pos": default_pos, "dir": default_dir }

## Instancia procedimentalmente un proyectil de energía Ki 3D brillante que vuela e impacta dinámicamente
func _spawn_ki_blast_projectile(hand_side: int, is_charged: bool) -> void:
	# Ocultar la mira de apuntado al disparar
	_hide_aim_reticle()

	# Determinar color de la energía
	var energy_color = Color(0.0, 0.7, 1.0, 0.9) if hand_side == 0 else Color(1.0, 0.6, 0.1, 0.9)
	var player = _get_player_instance()
	if player and player.character_data:
		for p in player.character_data.powers:
			if p.gesture_trigger == "ki_blast":
				energy_color = p.energy_color
				break

	# Obtener punto de origen y dirección directa desde la mano que dispara (no desde la mirada)
	var spawn_info = _get_hand_projectile_origin(hand_side)
	var spawn_pos: Vector3 = spawn_info["pos"]
	var velocity_dir: Vector3 = spawn_info["dir"]
	
	# Atributos de escala y velocidad según carga
	var projectile_radius = 0.05
	var speed = 28.0
	if is_charged:
		projectile_radius = 0.18
		speed = 14.0
		
	# Crear el nodo principal del proyectil
	var projectile = Node3D.new()
	projectile.name = "ProceduralKiProjectile_" + str(hand_side) + "_" + str(Time.get_ticks_msec())
	
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
	
	# Luz dinámica omnidireccional asociada (calibrada para VR sin destello cegador)
	var light = OmniLight3D.new()
	light.light_color = energy_color
	light.light_energy = 2.2 if is_charged else 1.2
	light.omni_range = 2.0 if is_charged else 1.0
	projectile.add_child(light)
	
	# Asignar el script físico estático precompilado y sus variables ANTES de entrar al árbol
	projectile.set_script(ProceduralKiProjectileScript)
	projectile.set("speed_velocity", velocity_dir * speed)
	projectile.set("p_radius", projectile_radius)
	projectile.set("p_color", energy_color)
	projectile.set("tier", 2 if is_charged else 1)
	projectile.set("base_damage", 700.0 if is_charged else 200.0)
	projectile.set("explosion_radius", 2.6 if is_charged else 1.2)
	
	# Excluir colisionadores del propio jugador para que el proyectil no choque consigo mismo al salir
	var exclude_rids: Array[RID] = []
	if player:
		for child in player.get_children():
			if child is CollisionObject3D:
				exclude_rids.append(child.get_rid())
		var origin = player.get_parent()
		if origin:
			for child in origin.get_children():
				if child is CollisionObject3D:
					exclude_rids.append(child.get_rid())
	projectile.set("ray_query_exclude", exclude_rids)
	
	# Añadir el proyectil de forma segura a la escena 3D
	var target_parent: Node = get_parent() if (get_parent() and get_parent() is Node3D) else (get_tree().current_scene if get_tree() else null)
	if target_parent and target_parent.is_inside_tree():
		target_parent.add_child(projectile)
		projectile.global_position = spawn_pos
		projectile.set_physics_process(true)
	current_aim_target = Vector3.ZERO
	current_aim_locked = false


func _spawn_special_projectile(power: Resource) -> void:
	# Ocultar la mira de apuntado al disparar
	_hide_aim_reticle()

	# Obtener punto de origen y dirección directa desde las manos (no desde la mirada)
	var spawn_info = _get_special_projectile_origin(power.power_name)
	var spawn_pos: Vector3 = spawn_info["pos"]
	var velocity_dir: Vector3 = spawn_info["dir"]
	# Desplazar origen ligeramente hacia adelante y abajo (a nivel de manos/pecho) para que el proyectil no tape la línea de visión
	spawn_pos += velocity_dir * 0.40 + Vector3(0.0, -0.16, 0.0)
	
	# Capturar y limpiar tiempos de carga
	var charge_time = 0.0
	if power.power_name.contains("Kamehameha"):
		charge_time = kamehameha_charge_time
		kamehameha_charge_time = 0.0
		is_charging_kamehameha = false
	elif power.power_name == "Genkidama":
		charge_time = genkidama_charge_time
		genkidama_charge_time = 0.0
		is_charging_genkidama = false
	elif power.power_name == "Galick Ho":
		charge_time = galick_ho_charge_time
		galick_ho_charge_time = 0.0
		is_charging_galick_ho = false
	elif power.power_name == "Final Flash":
		charge_time = final_flash_charge_time
		final_flash_charge_time = 0.0
		is_charging_final_flash = false
	elif power.power_name == "Big Bang Attack":
		charge_time = big_bang_charge_time
		big_bang_charge_time = 0.0
		is_charging_big_bang = false
		
	# Limpiar esferas de previsualización
	_update_special_charge_sphere(0.0)
	
	# Parámetros visuales específicos según la técnica y la carga
	var projectile_radius = 0.25
	if power.power_name.contains("Kamehameha"):
		projectile_radius = 0.32 * (1.0 + charge_time * 0.40) # Crece un 40% por segundo de carga
	elif power.power_name == "Genkidama":
		projectile_radius = 1.2 * (1.0 + charge_time * 0.30) # Crece un 30% por segundo de carga
	elif power.power_name == "Galick Ho":
		projectile_radius = 0.35 * (1.0 + charge_time * 0.40)
	elif power.power_name == "Final Flash":
		projectile_radius = 0.55 * (1.0 + charge_time * 0.50)
	elif power.power_name == "Big Bang Attack":
		projectile_radius = 0.45 * (1.0 + charge_time * 0.35)
		
	var speed = power.projectile_speed
	var energy_color = power.energy_color
	
	var projectile = Node3D.new()
	projectile.name = "ProceduralKiProjectile_" + power.power_name.replace(" ", "") + "_" + str(Time.get_ticks_msec())
	
	# 1. Malla del núcleo (Core)
	var mesh_core = MeshInstance3D.new()
	mesh_core.name = "CoreMesh"
	var sphere_core = SphereMesh.new()
	sphere_core.radius = projectile_radius
	sphere_core.height = projectile_radius * 2.0
	mesh_core.mesh = sphere_core
	
	var mat_core = StandardMaterial3D.new()
	mat_core.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat_core.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat_core.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_core.albedo_color = Color(energy_color.r, energy_color.g, energy_color.b, 0.55)
	mesh_core.material_override = mat_core
	projectile.add_child(mesh_core)
	
	# 2. Luz dinámica interna (suave para no enceguecer el visor VR)
	var light = OmniLight3D.new()
	light.name = "ProjectileLight"
	light.light_color = energy_color
	light.light_energy = 2.8
	light.omni_range = projectile_radius * 4.5
	projectile.add_child(light)
	
	# 3. Vincular el script de proyectil de Ki
	projectile.set_script(ProceduralKiProjectileScript)
	projectile.set("speed_velocity", velocity_dir * speed)
	projectile.set("p_radius", projectile_radius)
	projectile.set("p_color", energy_color)
	var is_ult = power.is_finisher or power.power_name.contains("Super") or power.power_name == "Genkidama"
	projectile.set("tier", 4 if is_ult else 3)
	
	var player = _get_player_instance()
	var base_dmg = power.base_damage_np
	if power.is_finisher and not (player and player.is_in_zenkai_state):
		base_dmg = 4500.0
	projectile.set("base_damage", base_dmg)
	projectile.set("explosion_radius", 8.5 if is_ult else 4.8)
	
	# Almacenar referencia al recurso del poder y tiempo de carga
	projectile.set_meta("power_ref", power)
	projectile.set_meta("charge_time", charge_time)
	
	if player and is_instance_valid(player) and player.get("is_comeback_zenkai"):
		projectile.set_meta("is_comeback_shot", true)
		
	var exclude_rids: Array[RID] = []
	var current_scene = get_tree().current_scene
	if current_scene:
		var stack = [current_scene]
		while stack.size() > 0:
			var node = stack.pop_back()
			if node is CollisionObject3D:
				if node.name.begins_with("KiCombatFist"):
					exclude_rids.append(node.get_rid())
			for child in node.get_children():
				stack.push_back(child)
		if player:
			for child in player.get_children():
				if child is CollisionObject3D:
					exclude_rids.append(child.get_rid())
			var origin = player.get_parent()
			if origin:
				for child in origin.get_children():
					if child is CollisionObject3D:
						exclude_rids.append(child.get_rid())
	projectile.set("ray_query_exclude", exclude_rids)
	
	var special_target_parent: Node = get_parent() if (get_parent() and get_parent() is Node3D) else (get_tree().current_scene if get_tree() else null)
	if special_target_parent and special_target_parent.is_inside_tree():
		special_target_parent.add_child(projectile)
		projectile.global_position = spawn_pos
		projectile.set_physics_process(true)
	current_aim_target = Vector3.ZERO
	current_aim_locked = false

func _cancel_action(reason: String) -> void:
	if current_node != gesture_tree or is_charging_ki or is_charging_ki_blast_left or is_charging_ki_blast_right or is_charging_kamehameha or is_charging_genkidama or is_charging_galick_ho or is_charging_final_flash or is_charging_big_bang:
		if is_charging_ki:
			is_charging_ki = false
			emit_signal("ki_recharge_stopped")
			
			# Ocultar aura visual dorada
			_show_visual_aura(false)
			
			# Detener sonidos de recarga de Ki
			if aura_start_player:
				aura_start_player.stop()
			if aura_loop_player:
				aura_loop_player.stop()
			
		# Detener sonidos de carga de Ki Blast y especiales
		if ki_blast_charge_player:
			ki_blast_charge_player.stop()
			
		_reset_ki_blast_charge(0)
		_reset_ki_blast_charge(1)
		
		# Resetear estados de habilidades especiales
		is_charging_kamehameha = false
		kamehameha_charge_time = 0.0
		is_charging_genkidama = false
		genkidama_charge_time = 0.0
		is_charging_galick_ho = false
		galick_ho_charge_time = 0.0
		is_charging_final_flash = false
		final_flash_charge_time = 0.0
		is_charging_big_bang = false
		big_bang_charge_time = 0.0
		_update_special_charge_sphere(0.0)
		melee_cheek_hand = -1
		
		emit_signal("phase_changed", "IDLE (POSTURA NEUTRAL)")
		emit_signal("gesture_logged", "Técnica interrumpida: " + reason, "error")
		_reset_to_idle()

func _reset_to_idle() -> void:
	current_node = gesture_tree
	gesture_timer = 0.0
	melee_cheek_hand = -1
	current_aim_target = Vector3.ZERO
	current_aim_locked = false
	_hide_aim_reticle()

func _reset_ki_blast_charge(hand_side: int) -> void:
	current_aim_target = Vector3.ZERO
	current_aim_locked = false
	_hide_aim_reticle()
	if hand_side == 0:
		ki_blast_charge_time_left = 0.0
		is_charging_ki_blast_left = false
		_cleanup_ki_blast_charge_sphere(0)
	else:
		ki_blast_charge_time_right = 0.0
		is_charging_ki_blast_right = false
		_cleanup_ki_blast_charge_sphere(1)

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

func _is_finger_extended(tracker: XRHandTracker, tip_joint: int) -> bool:
	if _is_joint_valid(tracker, tip_joint):
		var wrist = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
		var tip = tracker.get_hand_joint_transform(tip_joint).origin
		return wrist.distance_to(tip) >= HAND_OPEN_DISTANCE
	return false

func _get_extended_fingers_count(tracker: XRHandTracker) -> int:
	var count = 0
	if _is_finger_extended(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		count += 1
	if _is_finger_extended(tracker, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP):
		count += 1
	if _is_finger_extended(tracker, XRHandTracker.HAND_JOINT_RING_FINGER_TIP):
		count += 1
	if _is_finger_extended(tracker, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP):
		count += 1
	return count

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

# --- Gestión del Aura Visual 3D del Jugador ---

func _show_visual_aura(show: bool) -> void:
	if show:
		if visual_aura != null and is_instance_valid(visual_aura):
			return
			
		var camera = get_viewport().get_camera_3d()
		if not camera:
			return
			
		# Contenedor del Aura
		visual_aura = Node3D.new()
		visual_aura.name = "PlayerKiAura"
		
		# 1. Crear cilindro procedural
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "AuraMesh"
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.85
		cylinder.bottom_radius = 0.95
		cylinder.height = 2.4
		cylinder.radial_segments = 24
		cylinder.rings = 4
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		mesh_inst.mesh = cylinder
		
		var mat = ShaderMaterial.new()
		mat.shader = KiCoronaShader
		mat.set_shader_parameter("base_color", Color(1.0, 0.85, 0.1, 0.85)) # Oro brillante
		mat.set_shader_parameter("vertex_displacement", 0.07)
		mat.set_shader_parameter("speed", 4.5)
		mat.set_shader_parameter("scale", 5.0)
		mesh_inst.material_override = mat
		visual_aura.add_child(mesh_inst)
		
		# 2. Luz dinámica omnidireccional
		var light = OmniLight3D.new()
		light.name = "AuraLight"
		light.light_color = Color(1.0, 0.8, 0.2)
		light.light_energy = 8.0
		light.omni_range = 4.0
		light.position = Vector3(0, 0.5, 0)
		visual_aura.add_child(light)
		
		var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		root_node.add_child(visual_aura)
		var feet_pos = Vector3(camera.global_position.x, 0.5, camera.global_position.z)
		visual_aura.global_position = feet_pos + Vector3(0, 1.2, 0)
	else:
		if visual_aura != null and is_instance_valid(visual_aura):
			visual_aura.queue_free()
		visual_aura = null


func _check_kamehameha_pose_maintained(left_state: Dictionary, right_state: Dictionary) -> bool:
	if not left_state.valid or not right_state.valid:
		return false
	var dist = left_state.pos_local.distance_to(right_state.pos_local)
	var on_hip = left_state.height in ["HIP", "LOW", "CHEST"]
	var close_to_body = left_state.depth in ["CLOSE", "MEDIUM"]
	var fast = left_state.speed == "FAST" or right_state.speed == "FAST"
	return (dist < 0.32 and on_hip and close_to_body) or fast


func _check_genkidama_pose_maintained(left_state: Dictionary, right_state: Dictionary) -> bool:
	if not left_state.valid or not right_state.valid:
		return false
	var raised = left_state.pos_local.y >= 0.20 and right_state.pos_local.y >= 0.20
	var separated = left_state.pos_local.distance_to(right_state.pos_local) >= 0.25
	var fast = left_state.speed == "FAST" or right_state.speed == "FAST"
	return (raised and separated) or fast


func _check_galick_ho_pose_maintained(left_state: Dictionary, right_state: Dictionary) -> bool:
	if not left_state.valid or not right_state.valid:
		return false
	var dist = left_state.pos_local.distance_to(right_state.pos_local)
	var near_shoulder = (left_state.height in ["CHEST", "HEAD"] and right_state.height in ["CHEST", "HEAD"])
	var close_to_body = left_state.depth in ["CLOSE", "MEDIUM"] and right_state.depth in ["CLOSE", "MEDIUM"]
	var fast = left_state.speed == "FAST" or right_state.speed == "FAST" or (left_state.speed_val > 1.2 and right_state.speed_val > 1.2)
	return (dist < 0.32 and near_shoulder and close_to_body) or fast


func _check_final_flash_pose_maintained(left_state: Dictionary, right_state: Dictionary) -> bool:
	if not left_state.valid or not right_state.valid:
		return false
	var wide = hands_dist > 0.55
	var chest_level = left_state.height in ["CHEST", "HEAD"] and right_state.height in ["CHEST", "HEAD"]
	var fast = left_state.speed == "FAST" or right_state.speed == "FAST" or hands_sep_speed < -0.8
	return (wide and chest_level) or fast


func _check_big_bang_pose_maintained(hand_state: Dictionary) -> bool:
	if not hand_state.valid:
		return false
	var arm_far = hand_state.depth == "FAR"
	var chest_level = hand_state.height in ["CHEST", "HEAD"]
	var fast = hand_state.speed == "FAST" or hand_state.speed_val > 1.3
	return (arm_far and chest_level) or fast


func _is_hand_arm_extended(hand_side: int) -> bool:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not camera:
		return true
	var tracker = left_tracker if hand_side == 0 else right_tracker
	if tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var wrist_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
			var xr_origin: Node3D = camera.get_parent() as Node3D if (camera.get_parent() is Node3D) else null
			var wrist_global = xr_origin.global_transform * wrist_local if xr_origin else wrist_local
			var cam_fwd = -camera.global_transform.basis.z
			cam_fwd.y = 0.0
			if cam_fwd.length_squared() > 0.01:
				cam_fwd = cam_fwd.normalized()
			else:
				cam_fwd = Vector3.FORWARD
			var to_wrist = wrist_global - camera.global_position
			var fwd_dist = to_wrist.dot(cam_fwd)
			var total_dist = to_wrist.length()
			return fwd_dist > 0.32 and total_dist > 0.38
	return true


func _update_ki_blast_charge_sphere(hand_side: int, charge_time: float, _delta: float = 0.0) -> void:
	if charge_time <= 0.0:
		_cleanup_ki_blast_charge_sphere(hand_side)
		return
		
	var player = _get_player_instance()
	var energy_color = Color(0.0, 0.7, 1.0, 0.9) if hand_side == 0 else Color(1.0, 0.6, 0.1, 0.9)
	if player and player.character_data:
		for p in player.character_data.powers:
			if p.gesture_trigger == "ki_blast":
				energy_color = p.energy_color
				break
				
	var target_pos = _get_hand_global_position(hand_side)
	var norm_charge = clamp(charge_time / 2.0, 0.0, 1.0)
	var current_radius = 0.04 + norm_charge * 0.16
	
	if hand_side == 0:
		if not ki_blast_sphere_left or not is_instance_valid(ki_blast_sphere_left):
			ki_blast_sphere_left = MeshInstance3D.new()
			ki_blast_sphere_left.name = "KiBlastChargeSphere_Left"
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radial_segments = 16
			sphere_mesh.rings = 8
			ki_blast_sphere_left.mesh = sphere_mesh
			var mat = ShaderMaterial.new()
			mat.shader = KiSphereShader
			mat.set_shader_parameter("base_color", energy_color)
			mat.set_shader_parameter("core_glow", 4.0)
			ki_blast_sphere_left.material_override = mat
			get_tree().current_scene.add_child(ki_blast_sphere_left)
			
		if not ki_blast_corona_left or not is_instance_valid(ki_blast_corona_left):
			ki_blast_corona_left = MeshInstance3D.new()
			ki_blast_corona_left.name = "KiBlastChargeCorona_Left"
			var corona_mesh = SphereMesh.new()
			corona_mesh.radial_segments = 16
			corona_mesh.rings = 8
			ki_blast_corona_left.mesh = corona_mesh
			var mat = ShaderMaterial.new()
			mat.shader = KiCoronaShader
			mat.set_shader_parameter("base_color", energy_color)
			mat.set_shader_parameter("speed", 5.0)
			mat.set_shader_parameter("scale", 6.0)
			ki_blast_corona_left.material_override = mat
			get_tree().current_scene.add_child(ki_blast_corona_left)
			
		if not ki_blast_light_left or not is_instance_valid(ki_blast_light_left):
			ki_blast_light_left = OmniLight3D.new()
			ki_blast_light_left.name = "KiBlastChargeLight_Left"
			ki_blast_light_left.light_color = energy_color
			get_tree().current_scene.add_child(ki_blast_light_left)
			
		ki_blast_sphere_left.global_position = target_pos
		ki_blast_corona_left.global_position = target_pos
		ki_blast_light_left.global_position = target_pos
		
		ki_blast_sphere_left.mesh.radius = current_radius
		ki_blast_sphere_left.mesh.height = current_radius * 2.0
		ki_blast_corona_left.mesh.radius = current_radius * 1.25
		ki_blast_corona_left.mesh.height = current_radius * 1.25 * 2.0
		ki_blast_light_left.light_energy = 3.0 + norm_charge * 5.0
		ki_blast_light_left.omni_range = current_radius * 8.0
	else:
		if not ki_blast_sphere_right or not is_instance_valid(ki_blast_sphere_right):
			ki_blast_sphere_right = MeshInstance3D.new()
			ki_blast_sphere_right.name = "KiBlastChargeSphere_Right"
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radial_segments = 16
			sphere_mesh.rings = 8
			ki_blast_sphere_right.mesh = sphere_mesh
			var mat = ShaderMaterial.new()
			mat.shader = KiSphereShader
			mat.set_shader_parameter("base_color", energy_color)
			mat.set_shader_parameter("core_glow", 4.0)
			ki_blast_sphere_right.material_override = mat
			get_tree().current_scene.add_child(ki_blast_sphere_right)
			
		if not ki_blast_corona_right or not is_instance_valid(ki_blast_corona_right):
			ki_blast_corona_right = MeshInstance3D.new()
			ki_blast_corona_right.name = "KiBlastChargeCorona_Right"
			var corona_mesh = SphereMesh.new()
			corona_mesh.radial_segments = 16
			corona_mesh.rings = 8
			ki_blast_corona_right.mesh = corona_mesh
			var mat = ShaderMaterial.new()
			mat.shader = KiCoronaShader
			mat.set_shader_parameter("base_color", energy_color)
			mat.set_shader_parameter("speed", 5.0)
			mat.set_shader_parameter("scale", 6.0)
			ki_blast_corona_right.material_override = mat
			get_tree().current_scene.add_child(ki_blast_corona_right)
			
		if not ki_blast_light_right or not is_instance_valid(ki_blast_light_right):
			ki_blast_light_right = OmniLight3D.new()
			ki_blast_light_right.name = "KiBlastChargeLight_Right"
			ki_blast_light_right.light_color = energy_color
			get_tree().current_scene.add_child(ki_blast_light_right)
			
		ki_blast_sphere_right.global_position = target_pos
		ki_blast_corona_right.global_position = target_pos
		ki_blast_light_right.global_position = target_pos
		
		ki_blast_sphere_right.mesh.radius = current_radius
		ki_blast_sphere_right.mesh.height = current_radius * 2.0
		ki_blast_corona_right.mesh.radius = current_radius * 1.25
		ki_blast_corona_right.mesh.height = current_radius * 1.25 * 2.0
		ki_blast_light_right.light_energy = 3.0 + norm_charge * 5.0
		ki_blast_light_right.omni_range = current_radius * 8.0


func _cleanup_ki_blast_charge_sphere(hand_side: int) -> void:
	if hand_side == 0:
		if ki_blast_sphere_left and is_instance_valid(ki_blast_sphere_left):
			ki_blast_sphere_left.queue_free()
		if ki_blast_corona_left and is_instance_valid(ki_blast_corona_left):
			ki_blast_corona_left.queue_free()
		if ki_blast_light_left and is_instance_valid(ki_blast_light_left):
			ki_blast_light_left.queue_free()
		ki_blast_sphere_left = null
		ki_blast_corona_left = null
		ki_blast_light_left = null
	else:
		if ki_blast_sphere_right and is_instance_valid(ki_blast_sphere_right):
			ki_blast_sphere_right.queue_free()
		if ki_blast_corona_right and is_instance_valid(ki_blast_corona_right):
			ki_blast_corona_right.queue_free()
		if ki_blast_light_right and is_instance_valid(ki_blast_light_right):
			ki_blast_light_right.queue_free()
		ki_blast_sphere_right = null
		ki_blast_corona_right = null
		ki_blast_light_right = null


func _get_hand_global_position(hand_side: int) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
		
	# 1. Si los mandos de Meta Quest están activos, usar su posición global real
	var xr_orig: Node3D = camera.get_parent() as Node3D if (camera.get_parent() is Node3D) else null
	if xr_orig:
		var ctrl_name = "LeftHand" if hand_side == 0 else "RightHand"
		var ctrl = xr_orig.get_node_or_null(ctrl_name) as XRController3D
		if ctrl and ctrl.get_is_active():
			return ctrl.global_position

	# 2. Hand Tracking óptico OpenXR
	var tracker = left_tracker if hand_side == 0 else right_tracker
	if tracker:
		var flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			var origin_node = xr_orig if xr_orig else camera.get_parent()
			if origin_node:
				return origin_node.global_transform * palm_local
				
	var side_offset = -0.2 if hand_side == 0 else 0.2
	return camera.global_position - camera.global_transform.basis.z * 0.4 + camera.global_transform.basis.x * side_offset - camera.global_transform.basis.y * 0.15


func _update_special_charge_sphere(delta: float) -> void:
	if delta == 0.0 or (not is_charging_kamehameha and not is_charging_genkidama and not is_charging_galick_ho and not is_charging_final_flash and not is_charging_big_bang):
		if special_charge_sphere and is_instance_valid(special_charge_sphere):
			special_charge_sphere.queue_free()
		if special_charge_corona and is_instance_valid(special_charge_corona):
			special_charge_corona.queue_free()
		if special_charge_light and is_instance_valid(special_charge_light):
			special_charge_light.queue_free()
		special_charge_sphere = null
		special_charge_corona = null
		special_charge_light = null
		return
		
	var player = _get_player_instance()
	if not player or not is_instance_valid(player):
		return
		
	var target_pos = Vector3.ZERO
	var charge_time = 0.0
	var energy_color = Color(0.0, 0.7, 1.0, 0.8)
	var base_radius = 0.1
	var scale_multiplier = 1.0
	
	if is_charging_kamehameha:
		var left_pos = _get_hand_global_position(0)
		var right_pos = _get_hand_global_position(1)
		target_pos = (left_pos + right_pos) * 0.5
		charge_time = kamehameha_charge_time
		scale_multiplier = 1.0 + charge_time * 0.40
		base_radius = 0.15
		
		var power = _get_power_by_name("Kamehameha")
		if not power and player.is_in_zenkai_state:
			power = _get_power_by_name("Super Kamehameha")
		if power:
			energy_color = power.energy_color
			
	elif is_charging_genkidama:
		var camera = get_viewport().get_camera_3d()
		if camera:
			target_pos = camera.global_position + Vector3(0.0, 1.4, 0.0) - camera.global_transform.basis.z * 0.2
		charge_time = genkidama_charge_time
		scale_multiplier = 1.0 + charge_time * 0.30
		base_radius = 0.35
		
		var power = _get_power_by_name("Genkidama")
		if power:
			energy_color = power.energy_color

	elif is_charging_galick_ho:
		var left_pos = _get_hand_global_position(0)
		var right_pos = _get_hand_global_position(1)
		target_pos = (left_pos + right_pos) * 0.5
		charge_time = galick_ho_charge_time
		scale_multiplier = 1.0 + charge_time * 0.40
		base_radius = 0.16
		var power = _get_power_by_name("Galick Ho")
		if power:
			energy_color = power.energy_color

	elif is_charging_final_flash:
		var left_pos = _get_hand_global_position(0)
		var right_pos = _get_hand_global_position(1)
		target_pos = (left_pos + right_pos) * 0.5
		charge_time = final_flash_charge_time
		scale_multiplier = 1.0 + charge_time * 0.50
		base_radius = 0.25
		var power = _get_power_by_name("Final Flash")
		if power:
			energy_color = power.energy_color

	elif is_charging_big_bang:
		var bb_pos = _get_hand_global_position(big_bang_hand)
		target_pos = bb_pos
		charge_time = big_bang_charge_time
		scale_multiplier = 1.0 + charge_time * 0.35
		base_radius = 0.18
		var power = _get_power_by_name("Big Bang Attack")
		if power:
			energy_color = power.energy_color
			
	if not special_charge_sphere or not is_instance_valid(special_charge_sphere):
		special_charge_sphere = MeshInstance3D.new()
		special_charge_sphere.name = "SpecialChargeSphere"
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radial_segments = 24
		sphere_mesh.rings = 12
		special_charge_sphere.mesh = sphere_mesh
		
		var mat = ShaderMaterial.new()
		mat.shader = KiSphereShader
		mat.set_shader_parameter("base_color", energy_color)
		mat.set_shader_parameter("core_glow", 4.0)
		special_charge_sphere.material_override = mat
		get_tree().current_scene.add_child(special_charge_sphere)
		
	if not special_charge_corona or not is_instance_valid(special_charge_corona):
		special_charge_corona = MeshInstance3D.new()
		special_charge_corona.name = "SpecialChargeCorona"
		var corona_mesh = SphereMesh.new()
		corona_mesh.radial_segments = 24
		corona_mesh.rings = 12
		special_charge_corona.mesh = corona_mesh
		
		var mat = ShaderMaterial.new()
		mat.shader = KiCoronaShader
		mat.set_shader_parameter("base_color", energy_color)
		mat.set_shader_parameter("speed", 5.0)
		mat.set_shader_parameter("scale", 6.0)
		special_charge_corona.material_override = mat
		get_tree().current_scene.add_child(special_charge_corona)
		
	if not special_charge_light or not is_instance_valid(special_charge_light):
		special_charge_light = OmniLight3D.new()
		special_charge_light.name = "SpecialChargeLight"
		special_charge_light.light_color = energy_color
		special_charge_light.light_energy = 5.0
		get_tree().current_scene.add_child(special_charge_light)
		
	special_charge_sphere.global_position = target_pos
	special_charge_corona.global_position = target_pos
	special_charge_light.global_position = target_pos
	
	var current_radius = base_radius * scale_multiplier
	special_charge_sphere.mesh.radius = current_radius
	special_charge_sphere.mesh.height = current_radius * 2.0
	
	special_charge_corona.mesh.radius = current_radius * 1.25
	special_charge_corona.mesh.height = current_radius * 1.25 * 2.0
	
	special_charge_light.light_energy = 5.0 + charge_time * 2.0
	special_charge_light.omni_range = current_radius * 10.0


func _get_power_by_name(power_name: String) -> Resource:
	var player = _get_player_instance()
	if player and is_instance_valid(player) and player.character_data:
		for power in player.character_data.powers:
			if power.power_name == power_name:
				return power
	return null

func _get_palm_dir_in_torso(tracker: XRHandTracker, torso_transform: Transform3D) -> Vector3:
	if not tracker:
		return Vector3.ZERO
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	var xr_origin = camera.get_parent()
	if not xr_origin:
		return Vector3.ZERO
		
	var palm_flags = tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
	if (palm_flags & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID) == 0:
		return Vector3.ZERO
		
	var palm_global_basis = xr_origin.global_transform.basis * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis
	# En OpenXR, la normal de la palma apunta en la dirección -Y (hacia afuera de la palma)
	var palm_normal_global = -palm_global_basis.y.normalized()
	
	# Transformar a la base local del torso
	return torso_transform.basis.inverse() * palm_normal_global


func _get_opponent_instance() -> Node3D:
	var player = _get_player_instance()
	if player and player.has_method("_get_opponent"):
		var opp = player._get_opponent()
		if opp and is_instance_valid(opp):
			return opp
	var scene = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	if scene:
		var opp = scene.find_child("EnemyCharacterInstance", true, false)
		if opp and is_instance_valid(opp) and opp is Node3D:
			return opp
	return null


# --- MIRA DE PUNTERÍA HOLOGRÁFICA (AIM RETICLE) EN FASE 1 DE ATAQUES ---
func _ensure_aim_reticle() -> void:
	if aim_reticle_node and is_instance_valid(aim_reticle_node):
		return
	
	aim_reticle_node = Node3D.new()
	aim_reticle_node.name = "DragonBallAimReticle"
	
	aim_reticle_mesh = MeshInstance3D.new()
	aim_reticle_mesh.name = "ReticleMesh"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	aim_reticle_mesh.mesh = quad
	
	if not aim_reticle_texture:
		var size = 128
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center = Vector2(64, 64)
		var radius = 48.0
		for y in range(size):
			for x in range(size):
				var pos = Vector2(x, y)
				var d = pos.distance_to(center)
				var alpha = 0.0
				# Anillo exterior
				if abs(d - radius) < 2.5:
					alpha = 1.0
				# Brackets tácticos de esquina estilo Scouter
				elif (abs(x - 64) > 34 or abs(y - 64) > 34) and abs(d - 54.0) < 2.5:
					alpha = 1.0
				# Punto central concentrado
				elif d < 4.0:
					alpha = 1.0
				# Anillo interior concéntrico
				elif abs(d - 26.0) < 2.0:
					alpha = 0.75
				# Cruceta / Ticks cardinales
				elif (abs(x - 64) < 2.0 or abs(y - 64) < 2.0) and d > 12.0 and d < 55.0:
					alpha = 0.90
				
				if alpha > 0.0:
					img.set_pixel(x, y, Color(1, 1, 1, alpha))
				else:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
		aim_reticle_texture = ImageTexture.create_from_image(img)
	
	aim_reticle_mat = StandardMaterial3D.new()
	aim_reticle_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	aim_reticle_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	aim_reticle_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	aim_reticle_mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
	aim_reticle_mat.no_depth_test = true
	aim_reticle_mat.render_priority = 100
	aim_reticle_mat.albedo_texture = aim_reticle_texture
	aim_reticle_mat.albedo_color = Color(0.2, 0.8, 1.0, 1.0)
	aim_reticle_mesh.material_override = aim_reticle_mat
	
	aim_reticle_node.add_child(aim_reticle_mesh)
	aim_reticle_node.visible = false
	
	var scene_root = null
	if is_inside_tree() and get_tree():
		scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(aim_reticle_node)
	elif is_inside_tree():
		add_child(aim_reticle_node)


func _update_aim_reticle(origin_pos: Vector3, aim_dir: Vector3, color: Color) -> void:
	_ensure_aim_reticle()
	if not aim_reticle_node or not is_instance_valid(aim_reticle_node):
		return
	
	aim_reticle_node.visible = true
	
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	var cam_pos = camera.global_position if camera else origin_pos
	
	var opp = _get_opponent_instance()
	var hit_pos = origin_pos + aim_dir * 12.0
	var is_locked = false
	
	if opp and is_instance_valid(opp):
		var opp_chest = opp.global_position + Vector3(0, 1.2, 0)
		var to_opp = (opp_chest - origin_pos).normalized()
		# Si la línea de tiro apunta dentro de un cono de ~35 grados hacia el oponente: Lock-On directo
		if aim_dir.dot(to_opp) > 0.80:
			hit_pos = opp_chest
			is_locked = true
			
	current_aim_target = hit_pos
	current_aim_locked = is_locked
	aim_reticle_node.global_position = hit_pos
	
	# Retícula roja brillante cuando está bloqueada sobre el enemigo; si no, color de la técnica
	if aim_reticle_mat:
		aim_reticle_mat.albedo_color = Color(1.0, 0.25, 0.2, 1.0) if is_locked else color
	
	# Escala dinámica adaptada a la distancia para que siempre se vea de tamaño ideal en el visor
	var dist = (hit_pos - cam_pos).length()
	var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.02) * (0.12 if is_locked else 0.05)
	var scale_val = clamp(dist * 0.085, 0.5, 2.5) * pulse
	aim_reticle_mesh.scale = Vector3(scale_val, scale_val, scale_val)


func _hide_aim_reticle() -> void:
	if aim_reticle_node and is_instance_valid(aim_reticle_node):
		aim_reticle_node.visible = false
