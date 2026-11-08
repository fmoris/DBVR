class_name HybridCombatController
extends Node

## HybridCombatController: Sistema híbrido de combate con mandos Meta Quest 3.
## Combina las poses corporales y cinemáticas del anime con la fiabilidad de los mandos físicos (6DoF + Grip + Trigger).
## Si los mandos están inactivos, cede automáticamente el control a GesturePhaseTree (Hand Tracking puro).

signal controller_mode_changed(is_active: bool)

@export var gesture_tree: Node = null
@export var haptics_enabled: bool = true

# Nodos de seguimiento
var xr_origin: XROrigin3D = null
var camera: XRCamera3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null

# Estado de conectividad
var controllers_active: bool = false
var last_reported_mode: bool = false

# --- Estados de Combate Híbrido ---

# 1. Recarga de Ki (2 Fases)
var is_charging_ki: bool = false
var ki_prep_phase: bool = false

# 2. Ki Blasts (Izquierda y Derecha)
var left_trigger_held: bool = false
var right_trigger_held: bool = false
var left_charge_time: float = 0.0
var right_charge_time: float = 0.0
var left_is_charging: bool = false
var right_is_charging: bool = false
var left_blast_locked_haptic: bool = false
var right_blast_locked_haptic: bool = false

# 3. Super Poderes (Kamehameha / Galick Ho / Final Flash)
enum SuperPowerState { IDLE, CHARGING, READY_TO_FIRE }
var current_super_state: SuperPowerState = SuperPowerState.IDLE
var super_power_type: String = "" # "kamehameha", "galick_ho", "final_flash", "genkidama"
var super_charge_timer: float = 0.0
var super_locked_haptic: bool = false
const SUPER_MIN_CHARGE_TIME: float = 1.0

# 3b. Bio-Hápticos de Ki y Transformación (Heartbeat continuo no invasivo)
var bio_haptic_timer: float = 0.0

# 4. Melee / Velocidades anteriores para aceleración
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO
var melee_cooldown: float = 0.0
var super_cooldown: float = 0.0
var super_fatigue_timer: float = 0.0
var must_release_super_buttons: bool = false
var hud_toggle_cooldown: float = 0.0
var transform_cooldown: float = 0.0
var was_ax_pressed: bool = false
var was_by_pressed: bool = false
var startup_cooldown: float = 1.5
var recharge_exit_cooldown: float = 0.0 # Compuerta de gracia para evitar Ki Blasts indeseados al soltar gatillos de recarga

# Temporizador para comprobación periódica de estado en HUD
var status_pulse_timer: float = 0.0

const VRInGameMenuClass = preload("res://scripts/vr_in_game_menu.gd")
var in_game_menu: VRInGameMenu = null
var menu_toggle_cooldown: float = 0.0

const VRHandCalibrationMenuClass = preload("res://scripts/VRHandCalibrationMenu.gd")
var hand_calibration_menu: VRHandCalibrationMenu = null
var calibration_toggle_cooldown: float = 0.0

const KiSenseAndLockOnClass = preload("res://scripts/ki_sense_and_lockon.gd")
var ki_lockon_system: KiSenseAndLockOn = null


func _ready() -> void:
	if not gesture_tree:
		gesture_tree = get_parent()
	_find_xr_nodes()


func _find_xr_nodes() -> void:
	var scene_root = get_tree().current_scene
	if scene_root:
		xr_origin = scene_root.find_child("Player_XROrigin3D", true, false)
		if not xr_origin:
			xr_origin = scene_root.find_child("XROrigin3D", true, false)
			
	if xr_origin:
		camera = xr_origin.get_node_or_null("XRCamera3D")
		left_controller = xr_origin.get_node_or_null("LeftHand")
		right_controller = xr_origin.get_node_or_null("RightHand")

		if in_game_menu == null:
			var existing = xr_origin.find_child("VRInGameMenu", true, false)
			if not existing and get_tree() and get_tree().current_scene:
				existing = get_tree().current_scene.find_child("VRInGameMenu", true, false)
			if existing and existing is VRInGameMenu:
				in_game_menu = existing
			else:
				in_game_menu = VRInGameMenuClass.new()
				in_game_menu.name = "VRInGameMenu"
				xr_origin.add_child(in_game_menu)
			in_game_menu.setup_references(xr_origin, camera, left_controller, right_controller)

		if hand_calibration_menu == null:
			var existing_calib = xr_origin.find_child("VRHandCalibrationMenu", true, false)
			if not existing_calib and get_tree() and get_tree().current_scene:
				existing_calib = get_tree().current_scene.find_child("VRHandCalibrationMenu", true, false)
			if existing_calib and existing_calib is VRHandCalibrationMenu:
				hand_calibration_menu = existing_calib
			else:
				hand_calibration_menu = VRHandCalibrationMenuClass.new()
				hand_calibration_menu.name = "VRHandCalibrationMenu"
				xr_origin.add_child(hand_calibration_menu)
			hand_calibration_menu.setup_references(xr_origin, camera, left_controller, right_controller)

		if ki_lockon_system == null and get_tree() and get_tree().current_scene:
			ki_lockon_system = KiSenseAndLockOnClass.new()
			ki_lockon_system.name = "KiSenseAndLockOn"
			get_tree().current_scene.add_child.call_deferred(ki_lockon_system)
			var opp = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
			var ply = gesture_tree._get_player_instance() if gesture_tree else null
			ki_lockon_system.setup(camera, ply, opp, left_controller, right_controller)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	if not xr_origin or not left_controller or not right_controller:
		_find_xr_nodes()
		if not left_controller or not right_controller:
			return

	# 1. Modo mandos de control Touch 100% activo (Hand Tracking óptico desactivado por estabilidad)
	controllers_active = true

	# Sincronizar el flag y los mandos con GesturePhaseTree para auto-switching y orígenes de proyectil
	if gesture_tree:
		gesture_tree.set("is_controller_override", true)
		gesture_tree.set("left_controller_node", left_controller)
		gesture_tree.set("right_controller_node", right_controller)

	# Notificar cambio de modo al HUD
	if controllers_active != last_reported_mode:
		last_reported_mode = controllers_active
		controller_mode_changed.emit(controllers_active)
		var mode_name = "MANDOS QUEST 3 (CONTROL TOTAL)"
		if gesture_tree and gesture_tree.has_signal("gesture_logged"):
			gesture_tree.emit_signal("gesture_logged", "[INPUT] Modo activo: " + mode_name, "info")

	# 2. Calcular velocidades lineales de los mandos
	if delta > 0.0:
		if prev_left_pos != Vector3.ZERO:
			left_velocity = (left_controller.global_position - prev_left_pos) / delta
		if prev_right_pos != Vector3.ZERO:
			right_velocity = (right_controller.global_position - prev_right_pos) / delta
	prev_left_pos = left_controller.global_position
	prev_right_pos = right_controller.global_position

	# Calentamiento inicial de 1.5s: asienta tracking de OpenXR y descarta picos de aceleración
	if startup_cooldown > 0.0:
		startup_cooldown -= delta
		left_velocity = Vector3.ZERO
		right_velocity = Vector3.ZERO
		_process_hud_toggle(delta)
		return

	if melee_cooldown > 0.0:
		melee_cooldown -= delta
	if super_cooldown > 0.0:
		super_cooldown -= delta
	if super_fatigue_timer > 0.0:
		super_fatigue_timer -= delta
	if hud_toggle_cooldown > 0.0:
		hud_toggle_cooldown -= delta
	if transform_cooldown > 0.0:
		transform_cooldown -= delta
	if recharge_exit_cooldown > 0.0:
		recharge_exit_cooldown -= delta

	# 3. Comprobación de estado Melee / Bullet-Time (Minijuego de cajas)
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	var in_melee_minigame = player and (player.get("is_in_bullet_time") or player.get("is_flying_to_melee"))
	if in_melee_minigame:
		# Durante el combate melee o minijuego de cajas, SOLO se permite golpear las cajas físicamente.
		# Se bloquea totalmente el lanzamiento de poderes especiales, Ki Blasts, recarga de Ki, guardia y transformaciones.
		_reset_super_state()
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
		if is_charging_ki:
			is_charging_ki = false
			if gesture_tree:
				gesture_tree._cancel_action("En combate cuerpo a cuerpo")
				gesture_tree._reset_to_idle()
		_process_hud_toggle(delta)
		return

	# 4. Procesar las acciones híbridas en combate libre
	_process_ki_recharge(delta)
	_process_melee_punches()
	_process_ki_blasts(delta)
	_process_super_powers(delta)
	_process_transformations()
	_process_hud_toggle(delta)
	_process_guard()
	_process_bio_haptics(delta)


# --- 1. RECARGA DE KI (2 FASES: Gatillos a Hombros -> Descenso a Cintura/Cadera) ---
func _process_ki_recharge(delta: float) -> void:
	var l_trig: bool = left_controller.get_float("trigger") > 0.45 or left_controller.is_button_pressed("trigger_click")
	var r_trig: bool = right_controller.get_float("trigger") > 0.45 or right_controller.is_button_pressed("trigger_click")
	var triggers_held: bool = l_trig and r_trig

	# Si ambos gatillos están sostenidos y no hay super poder en curso
	if triggers_held and current_super_state == SuperPowerState.IDLE:
		var cam_pos = camera.global_position if camera else xr_origin.global_position + Vector3(0, 1.6, 0)
		var cam_fwd = -camera.global_transform.basis.z if camera else Vector3.FORWARD
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.01 else Vector3.FORWARD

		var l_pos = left_controller.global_position
		var r_pos = right_controller.global_position
		var l_rel_y = l_pos.y - cam_pos.y
		var r_rel_y = r_pos.y - cam_pos.y
		var avg_rel_y = (l_rel_y + r_rel_y) * 0.5

		# Solo cancelar si las manos están claramente detrás de la espalda
		var l_fwd_proj = (l_pos - cam_pos).dot(cam_fwd)
		var r_fwd_proj = (r_pos - cam_pos).dot(cam_fwd)
		if l_fwd_proj < -0.22 and r_fwd_proj < -0.22:
			if (is_charging_ki or ki_prep_phase) and gesture_tree:
				gesture_tree._cancel_action("Recarga de Ki cancelada (manos detrás de la espalda)")
				gesture_tree._reset_to_idle()
			ki_prep_phase = false
			is_charging_ki = false
			return

		# FASE 1: Concentración a la altura de los hombros o pecho (OBLIGATORIAMENTE DELANTE DE LOS HOMBROS)
		var cam_right = camera.global_transform.basis.x if camera else Vector3.RIGHT
		var l_local_x = (l_pos - cam_pos).dot(cam_right)
		var r_local_x = (r_pos - cam_pos).dot(cam_right)
		var hands_dist = l_pos.distance_to(r_pos)

		var in_front_of_shoulders = (l_fwd_proj >= 0.16 and r_fwd_proj >= 0.16) and (abs(l_local_x) < 0.45 and abs(r_local_x) < 0.45) and hands_dist <= 0.48
		var at_shoulder_height = (l_rel_y > -0.38 and r_rel_y > -0.38 and l_rel_y < 0.18 and r_rel_y < 0.18)

		if not is_charging_ki:
			if not ki_prep_phase:
				if at_shoulder_height and in_front_of_shoulders:
					ki_prep_phase = true
					if gesture_tree and gesture_tree.has_signal("phase_changed"):
						gesture_tree.emit_signal("phase_changed", "RECARGA KI: FASE 1 (HOMBROS)")
					if gesture_tree and gesture_tree.has_signal("gesture_logged"):
						gesture_tree.emit_signal("gesture_logged", "[KI] Fase 1: Concentración delante de los hombros. ¡Baja los puños a la cintura!", "info")
					_pulse_haptic(left_controller, 70.0, 0.40, 0.12)
					_pulse_haptic(right_controller, 70.0, 0.40, 0.12)
			else:
				# Si durante la Fase 1 aleja las manos hacia los lados o rompe la pose sin descender a la cintura, cancelar
				if not in_front_of_shoulders and avg_rel_y > -0.28:
					ki_prep_phase = false
					if gesture_tree:
						gesture_tree._cancel_action("Recarga cancelada (manos fuera de posición)")
						gesture_tree._reset_to_idle()
					return

				# Pulso háptico suave continuo indicando concentración en Fase 1
				_pulse_haptic(left_controller, 50.0, 0.22, delta)
				_pulse_haptic(right_controller, 50.0, 0.22, delta)

				# FASE 2: Detonación de Ki al descender las manos/muñecas a la cintura o caderas
				if avg_rel_y <= -0.28:
					is_charging_ki = true
					ki_prep_phase = false
					if gesture_tree:
						gesture_tree._trigger_action("recarga_ki")
						if gesture_tree.has_signal("phase_changed"):
							gesture_tree.emit_signal("phase_changed", "¡RECARGA DE KI ACTIVA! (CINTURA)")

		# Mantenimiento activo de la Fase 2 (Carga Máxima de Ki y NP)
		if is_charging_ki:
			var player = gesture_tree._get_player_instance() if gesture_tree else null
			if player and is_instance_valid(player):
				player.recharge_ki(25.0 * delta)
				player.increase_np(3000.0 * delta)
			_pulse_haptic(left_controller, 95.0, 0.50, delta)
			_pulse_haptic(right_controller, 95.0, 0.50, delta)
	else:
		# Soltar los gatillos cancela o finaliza la recarga
		if is_charging_ki or ki_prep_phase:
			if is_charging_ki and gesture_tree:
				gesture_tree._cancel_action("Recarga de Ki finalizada (Gatillos soltados)")
				gesture_tree._reset_to_idle()
			ki_prep_phase = false
			is_charging_ki = false
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
			recharge_exit_cooldown = 0.25 # Ventana debounce de 250ms para evitar Ki Blast accidental al soltar gatillos asincrónicamente
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)


# --- MÉTODOS AUXILIARES BIOMÉTRICOS ---
func _is_arm_extended(controller: XRController3D) -> bool:
	if not controller or not camera:
		return false
	var cam_pos = camera.global_position
	var ctrl_pos = controller.global_position
	var dist = cam_pos.distance_to(ctrl_pos)
	var cam_fwd = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() > 0.001:
		cam_fwd = cam_fwd.normalized()
	else:
		cam_fwd = Vector3.FORWARD
	var to_ctrl = (ctrl_pos - cam_pos)
	var forward_proj = to_ctrl.dot(cam_fwd)
	
	# El brazo está extendido al frente si proyecta al menos 0.35m adelante y dist 3D >= 0.38m
	return forward_proj >= 0.35 and dist >= 0.38


# --- 2. KI BLASTS (Izquierda y Derecha) ---
func _process_ki_blasts(delta: float) -> void:
	# Bloqueo total si se está recargando Ki, en preparación, en debounce de salida (250ms) o cargando super poder
	if is_charging_ki or ki_prep_phase or recharge_exit_cooldown > 0.0 or current_super_state != SuperPowerState.IDLE:
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		return

	var l_trig: bool = left_controller.get_float("trigger") > 0.35 or left_controller.is_button_pressed("trigger_click")
	var r_trig: bool = right_controller.get_float("trigger") > 0.35 or right_controller.is_button_pressed("trigger_click")

	# Si ambos gatillos están presionados simultáneamente, se reserva para Recarga de Ki, NO para Ki Blasts
	if l_trig and r_trig:
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		return

	# Si ambos mandos tienen Grip presionado, es Super Poder o Guardia
	var l_grip: bool = left_controller.get_float("grip") > 0.50 or left_controller.is_button_pressed("grip_click")
	var r_grip: bool = right_controller.get_float("grip") > 0.50 or right_controller.is_button_pressed("grip_click")
	if l_grip and r_grip:
		return

	# Mano Izquierda (solo gatillo izquierdo)
	_process_single_ki_blast(left_controller, 0, delta)
	# Mano Derecha (solo gatillo derecho)
	_process_single_ki_blast(right_controller, 1, delta)

	# Si ninguna mano está cargando Ki Blast y no hay Super Poder cargando, ocultar la mira
	if not left_is_charging and not right_is_charging and current_super_state == SuperPowerState.IDLE:
		if gesture_tree:
			gesture_tree._hide_aim_reticle()


func _process_single_ki_blast(controller: XRController3D, hand_side: int, delta: float) -> void:
	var trig_val = controller.get_float("trigger")
	var trig_pressed = trig_val > 0.35 or controller.is_button_pressed("trigger_click")
	var is_left = (hand_side == 0)

	if trig_pressed:
		var cam_p = camera.global_position if camera else xr_origin.global_position + Vector3(0, 1.6, 0)
		var aim_origin = controller.global_position
		var aim_fwd = -controller.global_transform.basis.z.normalized()

		# Consumir Ki mientras carga. Si no queda Ki, quema vital (BP)
		var player = gesture_tree._get_player_instance() if gesture_tree else null
		if player and is_instance_valid(player):
			if player.current_ki > 0.0:
				var ki_drain = 6.0 * delta
				player.consume_ki(ki_drain)
			else:
				var vital_drain = 80.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
				_pulse_haptic(controller, 130.0, 0.70, delta)

		if is_left:
			left_charge_time += delta
			left_is_charging = true
			if left_charge_time >= 0.50 and not left_blast_locked_haptic:
				left_blast_locked_haptic = true
				_pulse_haptic(controller, 140.0, 0.85, 0.12)
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡KI BLAST IZQ CARGADO LISTO!")

			if gesture_tree:
				gesture_tree._update_ki_blast_charge_sphere(0, left_charge_time, delta)
				gesture_tree.emit_signal("ki_blast_charging", 0, left_charge_time, delta)
				gesture_tree._update_aim_reticle(aim_origin, aim_fwd, Color(0.1, 0.8, 1.0))
			_pulse_haptic(controller, 100.0, clamp(0.15 + left_charge_time * 0.4, 0.15, 0.95), delta)
		else:
			right_charge_time += delta
			right_is_charging = true
			if right_charge_time >= 0.50 and not right_blast_locked_haptic:
				right_blast_locked_haptic = true
				_pulse_haptic(controller, 140.0, 0.85, 0.12)
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡KI BLAST DER CARGADO LISTO!")

			if gesture_tree:
				gesture_tree._update_ki_blast_charge_sphere(1, right_charge_time, delta)
				gesture_tree.emit_signal("ki_blast_charging", 1, right_charge_time, delta)
				gesture_tree._update_aim_reticle(aim_origin, aim_fwd, Color(1.0, 0.7, 0.1))
			_pulse_haptic(controller, 100.0, clamp(0.15 + right_charge_time * 0.4, 0.15, 0.95), delta)
	else:
		# Gatillo soltado: Evaluar disparo (tap rápido o disparo cargado)
		var held_time = left_charge_time if is_left else right_charge_time

		if held_time >= 0.04:
			var is_charged = held_time >= 0.50
			var action_name = "ki_blast_left" if is_left else "ki_blast_right"

			if gesture_tree:
				gesture_tree.set("last_firing_controller", controller)
				gesture_tree.set("last_firing_hand_side", hand_side)
				if is_left:
					gesture_tree.set("ki_blast_charge_time_left", held_time)
				else:
					gesture_tree.set("ki_blast_charge_time_right", held_time)
				gesture_tree._trigger_action(action_name)

			var recoil_amp = 0.95 if is_charged else 0.60
			var recoil_time = 0.18 if is_charged else 0.08
			_pulse_haptic(controller, 160.0, recoil_amp, recoil_time)

		# Limpiar esfera visual de carga en la palma
		if gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(hand_side)

		# Reset de variables de carga de esa mano
		if is_left:
			left_charge_time = 0.0
			left_is_charging = false
			left_blast_locked_haptic = false
		else:
			right_charge_time = 0.0
			right_is_charging = false
			right_blast_locked_haptic = false


# --- 3. SUPER PODERES (Galick Ho / Final Flash / Big Bang Attack / Kamehameha / Genkidama) ---
# Sistema canónico de 2 fases: Fase 1 (Carga con postura específica) + Fase 2 (Disparo hacia adelante)
func _process_super_powers(delta: float) -> void:
	# REQUISITO 4: Prevenir efecto metralleta con cooldown estricto y suelta obligatoria de botones
	if super_cooldown > 0.0:
		return

	if must_release_super_buttons:
		var l_g = left_controller.get_float("grip") > 0.55 or left_controller.is_button_pressed("grip_click")
		var r_g = right_controller.get_float("grip") > 0.55 or right_controller.is_button_pressed("grip_click")
		var l_t = left_controller.get_float("trigger") > 0.50 or left_controller.is_button_pressed("trigger_click")
		var r_t = right_controller.get_float("trigger") > 0.50 or right_controller.is_button_pressed("trigger_click")
		if not l_g and not r_g and not l_t and not r_t:
			must_release_super_buttons = false
		else:
			return

	var l_trig: bool = left_controller.get_float("trigger") > 0.45 or left_controller.is_button_pressed("trigger_click")
	var r_trig: bool = right_controller.get_float("trigger") > 0.45 or right_controller.is_button_pressed("trigger_click")

	# Si se está recargando Ki o se sostienen ambos gatillos, cancelar o no entrar a Super Poder
	if is_charging_ki or ki_prep_phase or (l_trig and r_trig):
		if current_super_state != SuperPowerState.IDLE:
			_reset_super_state()
		return

	var l_grip: bool = left_controller.get_float("grip") > 0.45 or left_controller.is_button_pressed("grip_click")
	var r_grip: bool = right_controller.get_float("grip") > 0.45 or right_controller.is_button_pressed("grip_click")

	var l_pos = left_controller.global_position
	var r_pos = right_controller.global_position
	var hands_dist = l_pos.distance_to(r_pos)
	var cam_pos = camera.global_position if camera else xr_origin.global_position + Vector3(0, 1.6, 0)
	var cam_fwd = -camera.global_transform.basis.z if camera else Vector3.FORWARD
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.01 else Vector3.FORWARD

	# Proyecciones hacia adelante respecto a la orientación de la cabeza
	var l_fwd_proj = (l_pos - cam_pos).dot(cam_fwd)
	var r_fwd_proj = (r_pos - cam_pos).dot(cam_fwd)

	# REQUISITO 8: Prohibir activación de super poderes detrás del cuerpo (solo cancelar si están claramente detrás de la espalda)
	if l_fwd_proj < -0.15 and r_fwd_proj < -0.15:
		if current_super_state != SuperPowerState.IDLE:
			_reset_super_state()
		return

	var avg_y = (l_pos.y + r_pos.y) / 2.0
	var rel_y = avg_y - cam_pos.y
	var avg_pos = (l_pos + r_pos) * 0.5
	var cam_right = camera.global_transform.basis.x if camera else Vector3.RIGHT
	var avg_local_x = (avg_pos - cam_pos).dot(cam_right)

	# Excluir la postura de guardia ÚNICAMENTE si está en reposo (IDLE), manos centradas al pecho (abs(x) < 0.12)
	var is_guard_pose = (current_super_state == SuperPowerState.IDLE) and (rel_y > -0.28 and rel_y < 0.22 and hands_dist < 0.30 and abs(avg_local_x) < 0.12)
	if is_guard_pose:
		return

	# Identificar personaje activo
	var char_name = "Goku"
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and player.character_data:
		char_name = player.character_data.character_name
	var is_vegeta = "VEGETA" in char_name.to_upper()

	# --- FASE 1: DETECCIÓN E INICIO DE CARGA ---
	if current_super_state == SuperPowerState.IDLE:
		var target_tech = ""
		var target_display = ""

		if is_vegeta:
			# VEGETA:
			# 1. Final Flash: REQUISITO 3 - Brazos estirados hacia afuera en cruz (T-pose > 0.48m) sosteniendo ambos grips
			if l_grip and r_grip and hands_dist >= 0.48 and rel_y > -0.35 and rel_y < 0.35 and l_fwd_proj >= -0.12 and r_fwd_proj >= -0.12:
				target_tech = "final_flash"
				target_display = "Final Flash"
			# 2. Galick Ho: Ambas manos juntas al hombro o cuello (hands_dist < 0.45m, rel_y > -0.32m, cerca del hombro)
			elif l_grip and r_grip and hands_dist < 0.45 and rel_y > -0.32 and (l_fwd_proj >= -0.10 or r_fwd_proj >= -0.10):
				target_tech = "galick_ho"
				target_display = "Galick Ho"
			# 3. Big Bang Attack: Un solo brazo extendido al frente con grip presionado EXCLUSIVAMENTE (SIN gatillo para no confundir con Melee)
			elif (l_grip != r_grip) and melee_cooldown <= 0.0:
				var is_l = l_grip
				var active_ctrl = left_controller if is_l else right_controller
				var active_trig = l_trig if is_l else r_trig
				if not active_trig and _is_arm_extended(active_ctrl):
					target_tech = "big_bang"
					target_display = "Big Bang Attack"
		else:
			# GOKU:
			# 1. Genkidama: Brazos elevados por encima de la cabeza (rel_y >= 0.25m, hands_dist >= 0.28m)
			if l_grip and r_grip and rel_y >= 0.25 and hands_dist >= 0.28:
				target_tech = "genkidama"
				target_display = "Genkidama"
			# 2. Kamehameha: Manos juntas a la cadera/costado (rel_y <= -0.20m, hands_dist < 0.32m)
			elif l_grip and r_grip and rel_y <= -0.20 and hands_dist < 0.32:
				target_tech = "kamehameha"
				target_display = "Kamehameha"

		if target_tech != "":
			current_super_state = SuperPowerState.CHARGING
			super_power_type = target_tech
			super_charge_timer = 0.0
			if target_tech == "big_bang":
				var bb_side = 0 if l_grip else 1
				if gesture_tree:
					gesture_tree.set("big_bang_hand", bb_side)
			_set_gesture_tree_charging_flag(super_power_type, true)
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", "%s: CARGANDO (FASE 1)" % target_display.to_upper())
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "¡Cargando %s! Mantén los grips y concentra tu Ki." % target_display, "info")

	# --- MANTENIMIENTO DE CARGA Y CONSUMO DE KI (O QUEMA DE FUERZA VITAL) ---
	if current_super_state == SuperPowerState.CHARGING:
		# Si se está cargando Big Bang y el usuario aprieta el gatillo de esa mano, formó puño para Melee -> Cancelar Big Bang
		if super_power_type == "big_bang":
			var bb_side = gesture_tree.get("big_bang_hand") if gesture_tree else (0 if l_grip else 1)
			var active_trig = l_trig if bb_side == 0 else r_trig
			if active_trig:
				_reset_super_state()
				return
		# Consumo continuo de Ki durante la carga
		if player and is_instance_valid(player):
			var drain_rate = 16.0
			if super_power_type == "final_flash":
				drain_rate = 25.0
			elif super_power_type == "kamehameha":
				drain_rate = 22.0
			elif super_power_type == "galick_ho":
				drain_rate = 18.0
			elif super_power_type == "big_bang":
				drain_rate = 18.0
			elif super_power_type == "genkidama":
				drain_rate = 15.0

			if player.current_ki > 0.0:
				player.consume_ki(drain_rate * delta)
			else:
				# ¡SOBRE-ESFUERZO VITAL DURANTE LA CARGA!
				# Si el jugador sostiene la carga sin Ki, quema su propia vitalidad (NP)
				var vital_drain = 350.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
				_pulse_haptic(left_controller, 160.0, 0.85, delta)
				_pulse_haptic(right_controller, 160.0, 0.85, delta)
				if int(super_charge_timer * 10) % 4 == 0:
					if gesture_tree and gesture_tree.has_signal("phase_changed"):
						gesture_tree.emit_signal("phase_changed", "¡SOBRE-ESFUERZO VITAL! (QUEMANDO FUERZA VITAL)")

		super_charge_timer += delta
		_pulse_haptic(left_controller, 110.0, clamp(0.25 + super_charge_timer * 0.35, 0.25, 0.95), delta)
		_pulse_haptic(right_controller, 110.0, clamp(0.25 + super_charge_timer * 0.35, 0.25, 0.95), delta)

		# Actualizar esfera visual concentrada en tiempo real
		if gesture_tree:
			_set_gesture_tree_charge_time(super_power_type, super_charge_timer)
			gesture_tree._update_special_charge_sphere(delta)

			# Retícula de apuntado anime durante la Fase 1
			var aim_color = Color(1.0, 0.9, 0.1) # Por defecto amarillo / Ki
			var aim_origin = (left_controller.global_position + right_controller.global_position) * 0.5
			var aim_dir = -camera.global_transform.basis.z if camera else Vector3.FORWARD
			if super_power_type == "big_bang":
				aim_color = Color(0.2, 0.7, 1.0) # Azul Big Bang
				var bb_side = gesture_tree.get("big_bang_hand") if gesture_tree else 1
				var bb_ctrl = left_controller if bb_side == 0 else right_controller
				if bb_ctrl:
					aim_origin = bb_ctrl.global_position
					aim_dir = (bb_ctrl.global_position - cam_pos).normalized()
			elif super_power_type == "galick_ho":
				aim_color = Color(0.85, 0.2, 1.0) # Púrpura Galick Ho
				aim_dir = -camera.global_transform.basis.z if camera else Vector3.FORWARD
			elif super_power_type == "final_flash":
				aim_color = Color(1.0, 0.95, 0.3) # Dorado Final Flash
				aim_dir = -camera.global_transform.basis.z if camera else Vector3.FORWARD
			elif super_power_type == "kamehameha":
				aim_color = Color(0.2, 0.6, 1.0) # Azul Kamehameha
				aim_dir = -camera.global_transform.basis.z if camera else Vector3.FORWARD
			elif super_power_type == "genkidama":
				aim_color = Color(0.3, 0.8, 1.0) # Celeste Genkidama
				aim_dir = -camera.global_transform.basis.z if camera else Vector3.FORWARD

			gesture_tree._update_aim_reticle(aim_origin, aim_dir, aim_color)

		# --- FASE 1 EN CURSO: MANTENIMIENTO DE CARGA Y EVALUACIÓN DE SALIDA ---
		# REGLA CANÓNICA DEL JUGADOR:
		# "cuando se esta en una fase 1 de algun gesto, solo existen 2 posibilidades:
		#  1. Ir a la fase 2 (disparar al soltar los botones con carga lista)
		#  2. Cancelar la acción soltando los botones (si se suelta antes de tiempo)
		# MIENTRAS SE MANTENGAN APRETADOS LOS BOTONES, NINGÚN OTRO GESTO PUEDE ACTIVARSE NI INTERRUMPIR."

		var bb_side = gesture_tree.get("big_bang_hand") if gesture_tree else (0 if l_grip else 1)
		var active_grip = l_grip if bb_side == 0 else r_grip

		var buttons_held: bool = false
		if super_power_type == "big_bang":
			buttons_held = active_grip
		else:
			# Para técnicas de dos manos (Final Flash, Galick Ho, Kamehameha, Genkidama):
			# Mientras mantenga al menos uno o ambos grips apretados, la carga se sostiene inamoviblemente
			buttons_held = l_grip or r_grip

		# Tiempo mínimo de carga requerida para que la Fase 1 quede LISTA y permita el disparo
		var min_fire_time = 0.7
		match super_power_type:
			"final_flash": min_fire_time = 1.0
			"galick_ho": min_fire_time = 0.7
			"big_bang": min_fire_time = 0.6
			"kamehameha": min_fire_time = 0.8
			"genkidama": min_fire_time = 1.2

		# Pulso háptico e indicación de "FASE 1 LISTA" en el instante exacto en que alcanza la carga mínima
		if super_charge_timer >= min_fire_time:
			if not super_locked_haptic:
				super_locked_haptic = true
				_pulse_haptic(left_controller, 180.0, 1.0, 0.20)
				_pulse_haptic(right_controller, 180.0, 1.0, 0.20)
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡%s LISTO! (SUELTA PARA DISPARAR)" % super_power_type.to_upper())
				if gesture_tree and gesture_tree.has_signal("gesture_logged"):
					gesture_tree.emit_signal("gesture_logged", "¡%s listo para lanzar! Suelta los botones o sigue concentrando." % super_power_type.capitalize(), "success")
			elif int(super_charge_timer * 10) % 5 == 0:
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡%s MÁXIMA ENERGÍA! (SUELTA PARA DISPARAR)" % super_power_type.to_upper())

		# POSIBILIDAD A: Mientras los botones sigan apretados, permanecer en Fase 1 concentrando energía
		if buttons_held:
			return

		# POSIBILIDAD B: Se soltaron los botones -> Evaluar si dispara (Fase 2) o cancela
		if super_charge_timer >= min_fire_time:
			# ¡FASE 2: DISPARO DE TÉCNICA!
			_execute_super_fire(super_power_type)
		else:
			# Cancelación por soltar botones antes de tiempo
			if gesture_tree:
				gesture_tree._cancel_action("%s cancelado (botones soltados antes de completar carga)" % super_power_type.capitalize())
				gesture_tree._reset_to_idle()
			super_cooldown = 0.20
			_reset_super_state()


func _execute_super_fire(tech_name: String) -> void:
	var ki_req: float = 50.0
	var tech_display_name = tech_name.capitalize()
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and is_instance_valid(player):
		var power_lookup = ""
		match tech_name:
			"galick_ho": power_lookup = "Galick Ho"
			"big_bang": power_lookup = "Big Bang Attack"
			"final_flash": power_lookup = "Final Flash"
			"kamehameha": power_lookup = "Super Kamehameha" if player.is_in_zenkai_state else "Kamehameha"
			"genkidama": power_lookup = "Genkidama"

		var power = null
		if player.character_data and player.character_data.powers:
			for p in player.character_data.powers:
				if p and p.power_name.to_lower() == power_lookup.to_lower():
					power = p
					break
		if power:
			ki_req = power.ki_cost
			tech_display_name = power.power_name

		# Si el jugador dispara dentro de la ventana de fatiga (< 4.0s de otro super), penalizar con 25% más de costo
		if super_fatigue_timer > 0.0:
			ki_req *= 1.25

		var res: Dictionary = player.consume_ki_or_life_force(ki_req)
		if res.get("is_life_sacrifice", false):
			var lost_np = int(res.get("sacrificed_np", 0.0))
			print("[HybridCombatController] [ÚLTIMO ALIENTO] ¡Quemaste %d BP para forzar la técnica %s!" % [lost_np, tech_display_name])
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para desatar %s." % [lost_np, tech_display_name], "warning")
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", "%s: ¡ÚLTIMO ALIENTO! (-%d BP)" % [tech_display_name.to_upper(), lost_np])
			# Pulso háptico dramático de latido cardíaco forzado
			_pulse_haptic(left_controller, 220.0, 1.0, 0.85)
			_pulse_haptic(right_controller, 220.0, 1.0, 0.85)
		else:
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", "¡FUEGO! %s DESATADO" % tech_display_name.to_upper())
			_pulse_haptic(left_controller, 200.0, 1.0, 0.55)
			_pulse_haptic(right_controller, 200.0, 1.0, 0.55)

	if gesture_tree:
		gesture_tree._hide_aim_reticle()
		gesture_tree._trigger_action(tech_name)
		gesture_tree._reset_to_idle()

	# Ventana de enfriamiento ágil para super poderes y retorno limpio a IDLE
	super_fatigue_timer = 1.0
	super_cooldown = 0.30
	must_release_super_buttons = false
	_reset_super_state()


func _set_gesture_tree_charging_flag(tech_name: String, active: bool) -> void:
	if not gesture_tree:
		return
	var flag_name = "is_charging_" + tech_name
	gesture_tree.set(flag_name, active)


func _set_gesture_tree_charge_time(tech_name: String, time_val: float) -> void:
	if not gesture_tree:
		return
	var time_name = tech_name + "_charge_time"
	gesture_tree.set(time_name, time_val)


func _reset_super_state() -> void:
	current_super_state = SuperPowerState.IDLE
	super_power_type = ""
	super_charge_timer = 0.0
	super_locked_haptic = false
	if gesture_tree:
		gesture_tree._hide_aim_reticle()
		gesture_tree.set("is_charging_kamehameha", false)
		gesture_tree.set("is_charging_genkidama", false)
		gesture_tree.set("is_charging_galick_ho", false)
		gesture_tree.set("is_charging_final_flash", false)
		gesture_tree.set("is_charging_big_bang", false)
		if gesture_tree.has_method("_update_special_charge_sphere"):
			gesture_tree._update_special_charge_sphere(0.0)


# --- 4. TRANSFORMACIONES (Botones A / X y B / Y con Edge-Trigger y Progresión Estricta) ---
func _process_transformations() -> void:
	var right_ax = right_controller.is_button_pressed("ax_button") if right_controller else false
	var left_ax = left_controller.is_button_pressed("ax_button") if left_controller else false
	var ax_pressed = right_ax or left_ax

	var right_by = right_controller.is_button_pressed("by_button") if right_controller else false
	var left_by = left_controller.is_button_pressed("by_button") if left_controller else false
	var by_pressed = right_by or left_by

	# Edge detection: solo disparar en el instante en que el botón pasa de NO presionado a PRESIONADO
	var just_pressed_ax = ax_pressed and not was_ax_pressed
	var just_pressed_by = by_pressed and not was_by_pressed

	was_ax_pressed = ax_pressed
	was_by_pressed = by_pressed

	if transform_cooldown > 0.0:
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or not is_instance_valid(player) or not player.character_data:
		return

	# Botón A (mando derecho) o X (mando izquierdo): Avanzar transformación SECUENCIALMENTE
	if just_pressed_ax:
		var current_trans = player.get("current_transformation")
		var total_forms = player.character_data.transformations.size()
		if total_forms > 0:
			var target_idx = 0
			if current_trans == null:
				# De Estado Base a la Primera Fase (ej: SSJ)
				target_idx = 0
			else:
				# Buscar la fase actual
				var curr_idx = -1
				for i in range(total_forms):
					if player.character_data.transformations[i] == current_trans:
						curr_idx = i
						break
				if curr_idx != -1 and curr_idx < total_forms - 1:
					# Avanzar estrictamente a la siguiente forma secuencial (ej: SSJ -> Super Vegeta -> SSB)
					target_idx = curr_idx + 1
				else:
					# Ya estamos en la máxima transformación disponible
					print("[Transformation] %s ya se encuentra en su máxima transformación." % player.character_data.character_name)
					_pulse_haptic(right_controller, 80.0, 0.3, 0.1)
					transform_cooldown = 0.30
					return

			player.transform_to(target_idx)
			transform_cooldown = 0.35 # Previene rebotes y pulsaciones múltiples por frame
			_pulse_haptic(left_controller, 180.0, 0.9, 0.35)
			_pulse_haptic(right_controller, 180.0, 0.9, 0.35)
			return

	# Botón B (mando derecho) o Y (mando izquierdo): Revertir a Base
	if just_pressed_by:
		var current_trans = player.get("current_transformation")
		if current_trans != null:
			player.revert_to_base()
			transform_cooldown = 0.35
			_pulse_haptic(left_controller, 120.0, 0.6, 0.25)
			_pulse_haptic(right_controller, 120.0, 0.6, 0.25)


# --- 5. GOLPES MELEE CINEMÁTICOS (LANZAMIENTO HACIA EL RIVAL) ---
func _process_melee_punches() -> void:
	if melee_cooldown > 0.0 or is_charging_ki or startup_cooldown > 0.0:
		return

	var l_grip = left_controller.get_float("grip") > 0.40 or left_controller.is_button_pressed("grip_click")
	var l_trig = left_controller.get_float("trigger") > 0.40 or left_controller.is_button_pressed("trigger_click")
	# REQUISITO CANÓNICO: Puño cerrado simulado con Grab + Gatillo (ambos botones presionados)
	var l_fist = l_grip and l_trig

	var r_grip = right_controller.get_float("grip") > 0.40 or right_controller.is_button_pressed("grip_click")
	var r_trig = right_controller.get_float("trigger") > 0.40 or right_controller.is_button_pressed("trigger_click")
	# REQUISITO CANÓNICO: Puño cerrado simulado con Grab + Gatillo (ambos botones presionados)
	var r_fist = r_grip and r_trig

	# Si se estaba cargando Big Bang y el usuario cierra el puño completo (grab + gatillo), priorizar Melee
	if current_super_state == SuperPowerState.CHARGING and super_power_type == "big_bang":
		if l_fist or r_fist:
			_reset_super_state()
	elif current_super_state != SuperPowerState.IDLE:
		return

	var cam_pos = camera.global_position if camera else xr_origin.global_position + Vector3(0, 1.6, 0)
	var cam_fwd = -camera.global_transform.basis.z if camera else Vector3.FORWARD
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.01 else Vector3.FORWARD

	var l_fwd_proj = (left_controller.global_position - cam_pos).dot(cam_fwd)
	var r_fwd_proj = (right_controller.global_position - cam_pos).dot(cam_fwd)

	# Puño izquierdo lanzado hacia adelante: Grab + Gatillo con velocidad frontal > 1.2 m/s
	if l_fist and left_velocity.dot(cam_fwd) > 1.2 and l_fwd_proj > 0.10:
		_execute_melee_punch(left_controller)
	# Puño derecho lanzado hacia adelante: Grab + Gatillo con velocidad frontal > 1.2 m/s
	elif r_fist and right_velocity.dot(cam_fwd) > 1.2 and r_fwd_proj > 0.10:
		_execute_melee_punch(right_controller)


func _execute_melee_punch(controller: XRController3D) -> void:
	melee_cooldown = 0.45
	_reset_super_state()
	left_charge_time = 0.0
	right_charge_time = 0.0
	left_is_charging = false
	right_is_charging = false

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	# Si ya estamos en Bullet-Time cuerpo a cuerpo, el golpe impacta la cúpula táctica
	if player and player.get("is_in_bullet_time"):
		_pulse_haptic(controller, 200.0, 0.95, 0.12)
		return

	# Auto-fijar al rival si no está bloqueado para garantizar embestida instantánea
	if player and is_instance_valid(player):
		if not player.get("is_target_locked"):
			var opp = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
			if opp:
				player.set("is_target_locked", true)
				player.set("target_opponent", opp)

	if gesture_tree:
		gesture_tree._cleanup_ki_blast_charge_sphere(0)
		gesture_tree._cleanup_ki_blast_charge_sphere(1)
		gesture_tree._hide_aim_reticle()
		gesture_tree._trigger_action("melee_attack")
	_pulse_haptic(controller, 180.0, 0.90, 0.18)


# --- 6. CONTROL DEL HUD Y MENÚ IN-GAME ---
func _process_hud_toggle(delta: float) -> void:
	if not left_controller or not right_controller:
		return

	# Botón de menú (tres barras / Option) del mando izquierdo: Menú In-Game
	if menu_toggle_cooldown > 0.0:
		menu_toggle_cooldown -= delta
	elif left_controller.is_button_pressed("menu_button"):
		menu_toggle_cooldown = 0.45
		if not in_game_menu or not is_instance_valid(in_game_menu):
			_find_xr_nodes()
		if in_game_menu and is_instance_valid(in_game_menu):
			if not in_game_menu.is_inside_tree():
				if xr_origin and is_instance_valid(xr_origin) and xr_origin.is_inside_tree():
					xr_origin.add_child(in_game_menu)
				elif get_tree() and get_tree().current_scene:
					get_tree().current_scene.add_child(in_game_menu)
			in_game_menu.toggle_menu()

	# Clic de stick izquierdo (primary_click): Menú de Calibración Biométrica de Manos
	if calibration_toggle_cooldown > 0.0:
		calibration_toggle_cooldown -= delta
	elif left_controller.is_button_pressed("primary_click"):
		calibration_toggle_cooldown = 0.45
		if not hand_calibration_menu or not is_instance_valid(hand_calibration_menu):
			_find_xr_nodes()
		if hand_calibration_menu and is_instance_valid(hand_calibration_menu):
			if not hand_calibration_menu.is_inside_tree():
				if xr_origin and is_instance_valid(xr_origin) and xr_origin.is_inside_tree():
					xr_origin.add_child(hand_calibration_menu)
				elif get_tree() and get_tree().current_scene:
					get_tree().current_scene.add_child(hand_calibration_menu)
			hand_calibration_menu.toggle_menu()

	# Clic de stick derecho (primary_click): alternar guía de movimientos del HUD
	if hud_toggle_cooldown > 0.0:
		hud_toggle_cooldown -= delta
	elif right_controller.is_button_pressed("primary_click"):
		hud_toggle_cooldown = 0.4
		var hud = get_tree().root.find_child("VRHUD", true, false)
		if hud and hud.has_method("toggle_moves_guide"):
			hud.toggle_moves_guide()
			_pulse_haptic(right_controller, 120.0, 0.4, 0.1)


# --- 7. GUARDIA DEFENSIVA (BLOQUEO) ---
func _process_guard() -> void:
	if not left_controller or not right_controller or is_charging_ki or current_super_state != SuperPowerState.IDLE:
		_set_player_blocking(false)
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or player.get("is_guard_broken"):
		_set_player_blocking(false)
		return

	var l_grip = left_controller.get_float("grip") > 0.45 or left_controller.is_button_pressed("grip_click")
	var r_grip = right_controller.get_float("grip") > 0.45 or right_controller.is_button_pressed("grip_click")
	var l_trig = left_controller.get_float("trigger") > 0.45 or left_controller.is_button_pressed("trigger_click")
	var r_trig = right_controller.get_float("trigger") > 0.45 or right_controller.is_button_pressed("trigger_click")

	# Si está dando puñetazos de melee (trig + grip), no es guardia
	if (l_grip and l_trig) or (r_grip and r_trig):
		_set_player_blocking(false)
		return

	# Ambos Grips sostenidos cubriendo pecho o cabeza
	if l_grip and r_grip:
		var cam_pos = camera.global_position if camera else xr_origin.global_position + Vector3(0, 1.6, 0)
		var cam_fwd = -camera.global_transform.basis.z if camera else Vector3.FORWARD
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.01 else Vector3.FORWARD

		var l_pos = left_controller.global_position
		var r_pos = right_controller.global_position
		var hands_dist = l_pos.distance_to(r_pos)
		var avg_y = (l_pos.y + r_pos.y) / 2.0
		var rel_y = avg_y - cam_pos.y

		# Verificar que las manos estén al frente (NUNCA detrás de la espalda)
		var l_fwd_proj = (l_pos - cam_pos).dot(cam_fwd)
		var r_fwd_proj = (r_pos - cam_pos).dot(cam_fwd)

		# Altura entre -0.32m y +0.25m respecto a la cabeza, manos juntas (< 0.40m) y al frente
		if rel_y > -0.32 and rel_y < 0.25 and hands_dist < 0.40 and l_fwd_proj >= 0.10 and r_fwd_proj >= 0.10:
			_set_player_blocking(true)
			_pulse_haptic(left_controller, 70.0, 0.12, 0.05)
			_pulse_haptic(right_controller, 70.0, 0.12, 0.05)
			return

	_set_player_blocking(false)


func _set_player_blocking(blocking: bool) -> void:
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and player.get("is_blocking") != blocking:
		player.set("is_blocking", blocking)
		if blocking:
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "[GUARDIA] Postura defensiva de bloqueo activa.", "info")


# --- UTILIDADES HÁPTICAS Y COMUNICACIÓN ---
## Bio-Hápticos sutiles: vibración rítmica en latido ("heartbeat") proporcional al % de Ki y multiplicada por la transformación
func _process_bio_haptics(delta: float) -> void:
	if not haptics_enabled or not left_controller or not right_controller:
		return

	# Silenciar durante la carga o ejecución activa de cualquier ataque para no contaminar el feedback cinético
	if left_is_charging or right_is_charging or is_charging_ki or ki_prep_phase or current_super_state != SuperPowerState.IDLE:
		bio_haptic_timer = 0.0
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or not is_instance_valid(player):
		return

	if player.get("is_in_bullet_time") or player.get("is_flying_to_melee"):
		bio_haptic_timer = 0.0
		return

	var current_ki = float(player.get("current_ki") if player.get("current_ki") != null else 0.0)
	var max_ki = float(player.get("max_ki") if player.get("max_ki") != null else 100.0)
	var ki_ratio = clampf(current_ki / maxf(max_ki, 1.0), 0.0, 1.0)

	# Multiplicador según la transformación actual
	var trans_mult: float = 1.0
	var trans = player.get("current_transformation")
	if trans != null and trans.get("transformation_name") != null:
		var t_name: String = String(trans.get("transformation_name")).to_lower()
		if "kaioken" in t_name:
			trans_mult = 1.35
		elif "ssj2" in t_name or "super saiyan 2" in t_name:
			trans_mult = 2.0
		elif "ssj3" in t_name or "blue" in t_name or "ssb" in t_name or "god" in t_name:
			trans_mult = 2.25
		elif "ssj" in t_name or "super" in t_name:
			trans_mult = 1.75

	# Intervalo del latido: a mayor Ki, latido más enérgico (entre 1.25s y 0.70s)
	var target_interval = lerpf(1.25, 0.70, ki_ratio)
	bio_haptic_timer += delta

	if bio_haptic_timer >= target_interval:
		bio_haptic_timer = 0.0
		# Amplitud base sutil entre 0.06 y 0.14 modulada por la transformación
		var base_amp = lerpf(0.06, 0.14, ki_ratio)
		var final_amp = clampf(base_amp * trans_mult, 0.06, 0.60)
		var freq = lerpf(55.0, 90.0, ki_ratio)
		_pulse_haptic(left_controller, freq, final_amp, 0.05)
		_pulse_haptic(right_controller, freq, final_amp, 0.05)


func _pulse_haptic(controller: XRController3D, freq: float, amp: float, duration: float) -> void:
	if not haptics_enabled or not controller:
		return
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", freq, amp, duration, 0.0)
