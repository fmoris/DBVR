class_name DesktopXRSimulator
extends Node

## Simulador de entrada XR (manos + cámara + botones) para pruebas manuales con teclado/mouse
## y pruebas automáticas por secuencias en PC/Editor cuando no hay visor OpenXR conectado.
## Se desactiva automáticamente en Android/Meta Quest o cuando OpenXR está inicializado.

enum SimMode {
	MANUAL,
	SCRIPTED
}

var sim_active: bool = false
var mode: SimMode = SimMode.MANUAL

# Referencias a nodos XR de la escena
var xr_origin: XROrigin3D = null
var camera: XRCamera3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null
var hybrid_controller: Node = null
var gesture_tree: Node = null

# Estado virtual de botones/ejes (preasignado, zero-alloc en hot path)
var v_left_trigger: float = 0.0
var v_right_trigger: float = 0.0
var v_left_grip: float = 0.0
var v_right_grip: float = 0.0
var v_left_ax: bool = false
var v_right_ax: bool = false
var v_left_by: bool = false
var v_right_by: bool = false
var v_left_primary_click: bool = false
var v_right_primary_click: bool = false
var v_left_stick: Vector2 = Vector2.ZERO
var v_right_stick: Vector2 = Vector2.ZERO

# Poses objetivo en torso-space normalizado (relativo al pecho y yaw de cámara)
var _target_l_torso: Vector3 = Vector3(-0.22, -0.18, 0.22)
var _target_r_torso: Vector3 = Vector3(0.22, -0.18, 0.22)
var _current_l_torso: Vector3 = Vector3(-0.22, -0.18, 0.22)
var _current_r_torso: Vector3 = Vector3(0.22, -0.18, 0.22)
var _l_palm_forward: bool = false
var _r_palm_forward: bool = false
var _pose_lerp_speed: float = 18.0

# Control de cámara desktop
var _mouse_captured: bool = false
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
const MOUSE_SENSITIVITY: float = 0.0028

# Secuencia melee manual con tecla V
var _manual_melee_timer: float = 0.0
var _manual_melee_left: bool = false

# Mini-HUD de debug en pantalla
var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _hud_label: Label = null
var _hud_visible: bool = true
var _hud_refresh_timer: float = 0.0
var _active_pose_label: String = "IDLE"


func setup(origin: XROrigin3D, cam: XRCamera3D, is_scripted: bool = false) -> void:
	if OS.has_feature("android"):
		sim_active = false
		queue_free()
		return

	xr_origin = origin
	camera = cam
	var has_test_suite: bool = false
	for u_a: String in OS.get_cmdline_user_args():
		if u_a.begins_with("--test-suite="):
			has_test_suite = true
			break
	mode = SimMode.SCRIPTED if (is_scripted or has_test_suite) else SimMode.MANUAL
	sim_active = true

	if xr_origin:
		left_controller = xr_origin.get_node_or_null("LeftHand")
		right_controller = xr_origin.get_node_or_null("RightHand")

	if camera:
		_cam_yaw = camera.rotation.y
		_cam_pitch = camera.rotation.x

	_bind_controllers_to_hybrid()

	if mode == SimMode.MANUAL and not DisplayServer.get_name().to_lower().contains("headless"):
		_create_debug_hud()
		print("[DesktopXRSimulator] Modo MANUAL activo. Pulsa F1 para ocultar/mostrar guía, Tab para capturar mouse.")
	else:
		print("[DesktopXRSimulator] Modo SCRIPTED activo para pruebas automáticas.")


func _bind_controllers_to_hybrid() -> void:
	var scene_root: Node = get_tree().current_scene if get_tree() else null
	if not scene_root:
		return
	gesture_tree = scene_root.find_child("GesturePhaseTree", true, false)
	if gesture_tree:
		hybrid_controller = gesture_tree.find_child("HybridCombatController", true, false)
		if not hybrid_controller:
			for child: Node in gesture_tree.get_children():
				if child.get_script() and child.has_method("cancel_super_from_poise_break"):
					hybrid_controller = child
					break
	if hybrid_controller:
		hybrid_controller.set("desktop_sim", self)


func _unhandled_input(event: InputEvent) -> void:
	if not sim_active or mode != SimMode.MANUAL:
		return

	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.keycode == KEY_TAB:
				_toggle_mouse_capture()
			elif key_ev.keycode == KEY_F1:
				_hud_visible = not _hud_visible
				if _hud_panel:
					_hud_panel.visible = _hud_visible
			elif key_ev.keycode == KEY_V:
				var ply_v: Node = gesture_tree._get_player_instance() if (gesture_tree and gesture_tree.has_method("_get_player_instance")) else null
				var dome_v: Variant = ply_v.get("active_target_dome") if ply_v else null
				var lore_v: Variant = dome_v.get("_lore_ctrl") if (dome_v and is_instance_valid(dome_v)) else null
				if lore_v and is_instance_valid(lore_v) and bool(lore_v.get("is_event_active")) and int(lore_v.get("active_event_type")) == 1:
					lore_v.call("inject_virtual_clash_punch")
					_manual_melee_timer = 0.10
					_manual_melee_left = not _manual_melee_left
				elif _manual_melee_timer <= 0.0:
					_manual_melee_timer = 0.28
					_manual_melee_left = not _manual_melee_left
	elif event is InputEventMouseMotion and _mouse_captured and camera:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_cam_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_cam_pitch = clampf(_cam_pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.2, 1.2)
		camera.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _toggle_mouse_capture() -> void:
	_mouse_captured = not _mouse_captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if not sim_active:
		return
	if not hybrid_controller or not is_instance_valid(hybrid_controller):
		_bind_controllers_to_hybrid()
	if not xr_origin or not camera or not left_controller or not right_controller:
		return

	if mode == SimMode.MANUAL:
		_update_manual_inputs(delta)

	_apply_hand_transforms(delta)

	if mode == SimMode.MANUAL and _hud_label and _hud_visible:
		_hud_refresh_timer += delta
		if _hud_refresh_timer >= 0.1:
			_hud_refresh_timer = 0.0
			_update_debug_hud_text()


func _update_manual_inputs(delta: float) -> void:
	clear_virtual_buttons()
	_l_palm_forward = false
	_r_palm_forward = false
	_pose_lerp_speed = 18.0

	# Rotación opcional de cámara con flechas si no se captura el mouse
	var yaw_in: float = 0.0
	if Input.is_key_pressed(KEY_LEFT):
		yaw_in += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		yaw_in -= 1.0
	if absf(yaw_in) > 0.01:
		_cam_yaw += yaw_in * 1.8 * delta
		camera.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)

	# Movimiento horizontal WASD -> primary_2d_axis
	var stick_x: float = 0.0
	var stick_y: float = 0.0
	if Input.is_key_pressed(KEY_D):
		stick_x += 1.0
	if Input.is_key_pressed(KEY_A):
		stick_x -= 1.0
	if Input.is_key_pressed(KEY_W):
		stick_y += 1.0
	if Input.is_key_pressed(KEY_S):
		stick_y -= 1.0
	v_right_stick = Vector2(stick_x, stick_y)

	# Movimiento vertical E / Q -> primary_click
	if Input.is_key_pressed(KEY_E):
		v_right_primary_click = true
	if Input.is_key_pressed(KEY_Q):
		v_left_primary_click = true

	# Transformación T (ax_button) / Revertir Y (by_button)
	if Input.is_key_pressed(KEY_T):
		v_right_ax = true
	if Input.is_key_pressed(KEY_Y):
		v_right_by = true

	# Secuencia de puñetazo Melee (V)
	if _manual_melee_timer > 0.0:
		_manual_melee_timer -= delta
		_pose_lerp_speed = 45.0
		_active_pose_label = "MELEE_PUNCH"
		if _manual_melee_left:
			v_left_grip = 1.0
			v_left_trigger = 1.0
			if _manual_melee_timer > 0.16:
				_target_l_torso = Vector3(-0.22, -0.05, 0.15)
			else:
				_target_l_torso = Vector3(-0.15, 0.0, 0.58)
			_target_r_torso = Vector3(0.24, -0.18, 0.22)
		else:
			v_right_grip = 1.0
			v_right_trigger = 1.0
			if _manual_melee_timer > 0.16:
				_target_r_torso = Vector3(0.22, -0.05, 0.15)
			else:
				_target_r_torso = Vector3(0.15, 0.0, 0.58)
			_target_l_torso = Vector3(-0.24, -0.18, 0.22)
		return

	# Poses prioritarias de teclado
	if Input.is_key_pressed(KEY_R):
		# Recarga de Ki: Fase 1 (pecho) -> tras 0.35s o manteniendo Shift, Fase 2 (cintura)
		v_left_trigger = 1.0
		v_right_trigger = 1.0
		if Input.is_key_pressed(KEY_SHIFT):
			_active_pose_label = "KI_RECHARGE_P1 (Hombros)"
			_target_l_torso = Vector3(-0.18, 0.08, 0.26)
			_target_r_torso = Vector3(0.18, 0.08, 0.26)
		else:
			# Si ya estaba en prep o manteniendo R sin Shift, pasar a Fase 2 si ya entró en prep
			var in_prep: bool = bool(hybrid_controller.get("ki_prep_phase")) or bool(hybrid_controller.get("is_charging_ki")) if hybrid_controller else false
			if in_prep:
				_active_pose_label = "KI_RECHARGE_P2 (Cintura)"
				_target_l_torso = Vector3(-0.24, -0.30, 0.14)
				_target_r_torso = Vector3(0.24, -0.30, 0.14)
			else:
				_active_pose_label = "KI_RECHARGE_P1 (Auto->P2)"
				_target_l_torso = Vector3(-0.18, 0.08, 0.26)
				_target_r_torso = Vector3(0.18, 0.08, 0.26)
		return

	if Input.is_key_pressed(KEY_G):
		_active_pose_label = "GUARDIA_CRUZADA"
		v_left_grip = 1.0
		v_right_grip = 1.0
		v_left_trigger = 1.0
		v_right_trigger = 1.0
		_target_l_torso = Vector3(-0.08, 0.02, 0.24)
		_target_r_torso = Vector3(0.08, 0.02, 0.24)
		return

	if Input.is_key_pressed(KEY_1):
		v_left_grip = 1.0
		v_right_grip = 1.0
		if Input.is_key_pressed(KEY_SPACE):
			_active_pose_label = "KAMEHAMEHA_FIRE (F2)"
			_target_l_torso = Vector3(-0.10, -0.05, 0.56)
			_target_r_torso = Vector3(0.10, -0.05, 0.56)
		else:
			_active_pose_label = "KAMEHAMEHA_CHARGE (F1 - Space para lanzar)"
			_target_l_torso = Vector3(-0.28, -0.16, 0.10)
			_target_r_torso = Vector3(-0.16, -0.16, 0.14)
		return

	if Input.is_key_pressed(KEY_2):
		v_left_grip = 1.0
		v_right_grip = 1.0
		if Input.is_key_pressed(KEY_SPACE):
			_active_pose_label = "GALICK_HO_FIRE (F2)"
			_target_l_torso = Vector3(-0.10, 0.0, 0.56)
			_target_r_torso = Vector3(0.10, 0.0, 0.56)
		else:
			_active_pose_label = "GALICK_HO_CHARGE (F1 - Space para lanzar)"
			_target_l_torso = Vector3(0.24, 0.05, 0.08)
			_target_r_torso = Vector3(0.32, 0.05, 0.12)
		return

	if Input.is_key_pressed(KEY_3):
		v_left_grip = 1.0
		v_right_grip = 1.0
		if Input.is_key_pressed(KEY_SPACE):
			_active_pose_label = "FINAL_FLASH_FIRE (F2)"
			_target_l_torso = Vector3(-0.10, 0.0, 0.56)
			_target_r_torso = Vector3(0.10, 0.0, 0.56)
		else:
			_active_pose_label = "FINAL_FLASH_CHARGE (F1 - Space para lanzar)"
			_target_l_torso = Vector3(-0.42, 0.04, 0.14)
			_target_r_torso = Vector3(0.42, 0.04, 0.14)
		return

	if Input.is_key_pressed(KEY_4):
		v_left_grip = 1.0
		v_right_grip = 1.0
		if Input.is_key_pressed(KEY_SPACE):
			_active_pose_label = "GENKIDAMA_FIRE (F2)"
			_target_l_torso = Vector3(-0.12, -0.02, 0.54)
			_target_r_torso = Vector3(0.12, -0.02, 0.54)
		else:
			_active_pose_label = "GENKIDAMA_CHARGE (F1 - Space para lanzar)"
			_target_l_torso = Vector3(-0.22, 0.58, 0.10)
			_target_r_torso = Vector3(0.22, 0.58, 0.10)
		return

	if Input.is_key_pressed(KEY_5):
		_active_pose_label = "BIG_BANG_ATTACK"
		v_right_grip = 1.0
		_r_palm_forward = true
		_target_l_torso = Vector3(-0.24, -0.18, 0.20)
		_target_r_torso = Vector3(0.16, 0.02, 0.54)
		return

	# Ki Blasts con Click Izquierdo / Click Derecho (sin interferir si mouse no está sobre UI o presionado)
	var l_click: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var r_click: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if l_click or r_click:
		_active_pose_label = "KI_BLAST"
		if l_click:
			v_left_trigger = 1.0
			_l_palm_forward = true
			_target_l_torso = Vector3(-0.18, 0.02, 0.52)
		else:
			_target_l_torso = Vector3(-0.22, -0.18, 0.22)
		if r_click:
			v_right_trigger = 1.0
			_r_palm_forward = true
			_target_r_torso = Vector3(0.18, 0.02, 0.52)
		else:
			_target_r_torso = Vector3(0.22, -0.18, 0.22)
		return

	_active_pose_label = "IDLE"
	_target_l_torso = Vector3(-0.22, -0.18, 0.22)
	_target_r_torso = Vector3(0.22, -0.18, 0.22)


# --- API para CombatSequenceRunner (Modo SCRIPTED) ---

func clear_virtual_buttons() -> void:
	v_left_trigger = 0.0
	v_right_trigger = 0.0
	v_left_grip = 0.0
	v_right_grip = 0.0
	v_left_ax = false
	v_right_ax = false
	v_left_by = false
	v_right_by = false
	v_left_primary_click = false
	v_right_primary_click = false
	v_left_stick = Vector2.ZERO
	v_right_stick = Vector2.ZERO


func set_scripted_hands(
	l_torso: Vector3,
	r_torso: Vector3,
	l_palm_fwd: bool = false,
	r_palm_fwd: bool = false,
	instant: bool = false
) -> void:
	_target_l_torso = l_torso
	_target_r_torso = r_torso
	_l_palm_forward = l_palm_fwd
	_r_palm_forward = r_palm_fwd
	if instant:
		_current_l_torso = l_torso
		_current_r_torso = r_torso
		if camera and is_instance_valid(camera):
			_apply_hand_transforms(0.016)


func _apply_hand_transforms(delta: float) -> void:
	var alpha: float = clampf(delta * _pose_lerp_speed, 0.0, 1.0)
	_current_l_torso = _current_l_torso.lerp(_target_l_torso, alpha)
	_current_r_torso = _current_r_torso.lerp(_target_r_torso, alpha)

	var body_scale: float = clampf(xr_origin.scale.y, 0.70, 1.40) if xr_origin else 1.0
	var cam_pos: Vector3 = camera.global_position
	var chest_pos: Vector3 = cam_pos - Vector3(0.0, 0.28 * body_scale, 0.0)

	var raw_fwd: Vector3 = -camera.global_transform.basis.z
	raw_fwd.y = 0.0
	var fwd: Vector3 = raw_fwd.normalized() if raw_fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()

	var l_world: Vector3 = chest_pos + (right * _current_l_torso.x + Vector3.UP * _current_l_torso.y + fwd * _current_l_torso.z) * body_scale
	var r_world: Vector3 = chest_pos + (right * _current_r_torso.x + Vector3.UP * _current_r_torso.y + fwd * _current_r_torso.z) * body_scale

	left_controller.global_position = l_world
	right_controller.global_position = r_world

	# Orientación de palma alineada con HybridCombatController._get_controller_palm_world_dir (b.x izq / -b.x der)
	var cam_fwd_3d: Vector3 = (-camera.global_transform.basis.z).normalized()
	if _l_palm_forward:
		var z_axis: Vector3 = cam_fwd_3d.cross(Vector3.UP).normalized()
		var y_axis: Vector3 = z_axis.cross(cam_fwd_3d).normalized()
		left_controller.global_transform = Transform3D(Basis(cam_fwd_3d, y_axis, z_axis).orthonormalized(), l_world)
	else:
		left_controller.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd).orthonormalized(), l_world)

	if _r_palm_forward:
		var neg_fwd: Vector3 = -cam_fwd_3d
		var z_axis_r: Vector3 = neg_fwd.cross(Vector3.UP).normalized()
		var y_axis_r: Vector3 = z_axis_r.cross(neg_fwd).normalized()
		right_controller.global_transform = Transform3D(Basis(neg_fwd, y_axis_r, z_axis_r).orthonormalized(), r_world)
	else:
		right_controller.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd).orthonormalized(), r_world)


# --- Lectura unificada para HybridCombatController ---

func get_button_pressed(is_left: bool, action: StringName) -> bool:
	match action:
		&"trigger_click":
			return (v_left_trigger > 0.5) if is_left else (v_right_trigger > 0.5)
		&"grip_click":
			return (v_left_grip > 0.5) if is_left else (v_right_grip > 0.5)
		&"ax_button":
			return v_left_ax if is_left else v_right_ax
		&"by_button":
			return v_left_by if is_left else v_right_by
		&"primary_click", &"secondary_click":
			return v_left_primary_click if is_left else v_right_primary_click
	return false


func get_float(is_left: bool, action: StringName) -> float:
	match action:
		&"trigger":
			return v_left_trigger if is_left else v_right_trigger
		&"grip":
			return v_left_grip if is_left else v_right_grip
	return 0.0


func get_vector2(is_left: bool, action: StringName) -> Vector2:
	if action == &"primary":
		return v_left_stick if is_left else v_right_stick
	return Vector2.ZERO


# --- Mini-HUD 2D de Debug ---

func _create_debug_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "DesktopSimDebugHUD"
	_hud_layer.layer = 100
	add_child(_hud_layer)

	_hud_panel = PanelContainer.new()
	_hud_panel.position = Vector2(14.0, 14.0)
	_hud_layer.add_child(_hud_panel)

	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_panel.add_child(_hud_label)
	_update_debug_hud_text()


func _update_debug_hud_text() -> void:
	if not _hud_label:
		return
	var ply: Node = gesture_tree._get_player_instance() if (gesture_tree and gesture_tree.has_method("_get_player_instance")) else null
	var ki_txt: String = "%.0f" % float(ply.get("current_ki")) if (ply and ply.get("current_ki") != null) else "N/A"
	var np_txt: String = "%.0f" % float(ply.get("current_bp")) if (ply and ply.get("current_bp") != null) else "N/A"
	var blk_txt: String = "SI" if (ply and bool(ply.get("is_blocking"))) else "NO"
	_hud_label.text = (
		"[DBVR DESKTOP SIMULATOR | F1: Ocultar | Tab: Mouse (%s)]\n" % ("CAPTURADO" if _mouse_captured else "LIBRE")
		+ "Pose: %s | Ki: %s | NP: %s | Guardia: %s\n" % [_active_pose_label, ki_txt, np_txt, blk_txt]
		+ "WASD: Paso | E/Q: Subir/Bajar | Click I/D: Ki Blast | V: Melee | G: Guardia\n"
		+ "R: Recarga Ki | 1: Kamehameha 2: Galick 3: FinalFlash 4: Genki (+Space=Lanzar) | 5: BigBang | T/Y: Transf."
	)
