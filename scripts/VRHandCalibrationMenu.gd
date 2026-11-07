class_name VRHandCalibrationMenu
extends Node3D

## VRHandCalibrationMenu (Dragon Ball VR)
## Menú de calibración biométrica y diagnóstico de manos/muñecas en tiempo real.
## Accionado al presionar el stick analógico izquierdo (primary_click).

signal calibration_menu_toggled(is_open: bool)

var is_open: bool = false
var selected_index: int = 0
var input_cooldown: float = 0.0
var stream_telemetry_active: bool = false
var stream_timer: float = 0.0

var xr_origin_ref: Node3D = null
var camera_ref: Camera3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null

var sub_viewport: SubViewport = null
var menu_mesh: MeshInstance3D = null
var button_panels: Array[Panel] = []
var button_labels: Array[Label] = []
var live_feedback_label: Label = null
var instruction_label: Label = null

const CALIBRATION_OPTIONS = [
	{
		"id": 0,
		"title": "📏 1. MEDIR MUÑECA (ORIENTACIÓN FRONTAL)",
		"desc": "Extiende el brazo al frente y pulsa gatillo para capturar rotación neutra",
		"mode": "wrist"
	},
	{
		"id": 1,
		"title": "✊ 2. MEDIR APERTURA & PUÑO CERRADO",
		"desc": "Cierra el puño apretando Grip + Trigger o abre la mano para registrar umbrales",
		"mode": "fist"
	},
	{
		"id": 2,
		"title": "🔄 3. MEDIR GIRO DE PALMA (SUPINACIÓN/PRONACIÓN)",
		"desc": "Gira la muñeca con la palma mirando hacia arriba para capturar el ángulo del Scouter",
		"mode": "palm"
	},
	{
		"id": 3,
		"title": "📡 4. ACTIVAR STREAM TELEMETRÍA EN CONSOLA",
		"desc": "Envía lecturas continuas a la consola de Godot cada 0.5s para inspección activa",
		"mode": "stream"
	}
]


func _ready() -> void:
	visible = false
	_build_calibration_ui()


func setup_references(xr_origin: Node3D, camera: Camera3D, left_ctrl: XRController3D, right_ctrl: XRController3D) -> void:
	xr_origin_ref = xr_origin
	camera_ref = camera
	left_controller = left_ctrl
	right_controller = right_ctrl
	if not is_inside_tree() and xr_origin_ref and is_instance_valid(xr_origin_ref) and xr_origin_ref.is_inside_tree():
		xr_origin_ref.add_child(self)


func _build_calibration_ui() -> void:
	sub_viewport = SubViewport.new()
	sub_viewport.name = "CalibrationSubViewport"
	sub_viewport.size = Vector2i(1080, 840)
	sub_viewport.transparent_bg = true
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_viewport)

	var root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_viewport.add_child(root_control)

	var main_panel = Panel.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.offset_left = 24
	main_panel.offset_top = 24
	main_panel.offset_right = -24
	main_panel.offset_bottom = -24

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.04, 0.08, 0.92) # Azul cápsula espacial Saiyan
	panel_style.border_width_left = 4
	panel_style.border_width_top = 4
	panel_style.border_width_right = 4
	panel_style.border_width_bottom = 4
	panel_style.border_color = Color(0.18, 0.65, 1.0, 0.95) # Azul Neón
	panel_style.corner_radius_top_left = 22
	panel_style.corner_radius_top_right = 22
	panel_style.corner_radius_bottom_left = 22
	panel_style.corner_radius_bottom_right = 22
	panel_style.set_content_margin_all(24)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	root_control.add_child(main_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	main_panel.add_child(vbox)

	# Título principal
	var title = Label.new()
	title.text = "🔧 CALIBRADOR BIOMÉTRICO DE MANOS (VR DIAGNOSTIC)"
	var t_set = LabelSettings.new()
	t_set.font_size = 32
	t_set.font_color = Color(0.2, 0.85, 1.0)
	t_set.shadow_size = 4
	t_set.shadow_color = Color(0, 0, 0, 0.8)
	title.label_settings = t_set
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	instruction_label = Label.new()
	instruction_label.text = "Selecciona una opción con Stick Izquierdo y pulsa Gatillo para medir"
	var inst_set = LabelSettings.new()
	inst_set.font_size = 18
	inst_set.font_color = Color(0.8, 0.9, 1.0, 0.85)
	instruction_label.label_settings = inst_set
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(instruction_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Botones de selección
	button_panels.clear()
	button_labels.clear()

	for i in range(CALIBRATION_OPTIONS.size()):
		var def = CALIBRATION_OPTIONS[i]
		var btn_panel = Panel.new()
		btn_panel.custom_minimum_size = Vector2(0, 85)

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.04, 0.08, 0.14, 0.85)
		btn_style.border_width_left = 3
		btn_style.border_width_top = 3
		btn_style.border_width_right = 3
		btn_style.border_width_bottom = 3
		btn_style.border_color = Color(0.2, 0.5, 0.8, 0.6)
		btn_style.corner_radius_top_left = 12
		btn_style.corner_radius_top_right = 12
		btn_style.corner_radius_bottom_left = 12
		btn_style.corner_radius_bottom_right = 12
		btn_panel.add_theme_stylebox_override("panel", btn_style)
		vbox.add_child(btn_panel)

		var btn_vbox = VBoxContainer.new()
		btn_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_panel.add_child(btn_vbox)

		var lbl_title = Label.new()
		lbl_title.text = def["title"]
		var l_set = LabelSettings.new()
		l_set.font_size = 22
		l_set.font_color = Color.WHITE
		lbl_title.label_settings = l_set
		lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(lbl_title)

		var lbl_desc = Label.new()
		lbl_desc.text = def["desc"]
		var d_set = LabelSettings.new()
		d_set.font_size = 15
		d_set.font_color = Color(0.65, 0.82, 0.95)
		lbl_desc.label_settings = d_set
		lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(lbl_desc)

		button_panels.append(btn_panel)
		button_labels.append(lbl_title)

	# Panel de telemetría y lecturas en vivo en la parte inferior
	var feedback_panel = Panel.new()
	feedback_panel.custom_minimum_size = Vector2(0, 160)
	var fb_style = StyleBoxFlat.new()
	fb_style.bg_color = Color(0.01, 0.02, 0.04, 0.95)
	fb_style.border_width_left = 2
	fb_style.border_width_top = 2
	fb_style.border_width_right = 2
	fb_style.border_width_bottom = 2
	fb_style.border_color = Color(0.0, 1.0, 0.6, 0.8)
	fb_style.corner_radius_top_left = 10
	fb_style.corner_radius_top_right = 10
	fb_style.corner_radius_bottom_left = 10
	fb_style.corner_radius_bottom_right = 10
	fb_style.set_content_margin_all(12)
	feedback_panel.add_theme_stylebox_override("panel", fb_style)
	vbox.add_child(feedback_panel)

	live_feedback_label = Label.new()
	live_feedback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	live_feedback_label.text = "[TELEMETRÍA EN VIVO]\nEsperando selección del usuario..."
	var fb_set = LabelSettings.new()
	fb_set.font_size = 17
	fb_set.font_color = Color(0.3, 1.0, 0.7)
	live_feedback_label.label_settings = fb_set
	live_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_panel.add_child(live_feedback_label)

	# Malla Quad 3D espacial
	menu_mesh = MeshInstance3D.new()
	menu_mesh.name = "CalibrationQuadMesh"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.92, 0.72)
	menu_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = sub_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 115
	menu_mesh.material_override = mat
	add_child(menu_mesh)

	_update_selection_visuals()


func toggle_menu() -> void:
	if not is_inside_tree():
		if xr_origin_ref and is_instance_valid(xr_origin_ref) and xr_origin_ref.is_inside_tree():
			xr_origin_ref.add_child(self)
		else:
			var tree = Engine.get_main_loop() as SceneTree
			if tree and tree.current_scene and tree.current_scene is Node3D:
				tree.current_scene.add_child(self)
			else:
				return

	if not is_inside_tree():
		return

	is_open = not is_open
	visible = is_open

	if is_open:
		_reposition_in_front_of_player()
		if menu_mesh and is_instance_valid(menu_mesh):
			menu_mesh.scale = Vector3.ZERO
			if is_inside_tree():
				var tw = create_tween()
				if tw:
					tw.tween_property(menu_mesh, "scale", Vector3.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if left_controller and is_instance_valid(left_controller) and left_controller.has_method("trigger_haptic_pulse"):
			left_controller.trigger_haptic_pulse("haptic", 140.0, 0.6, 0.12, 0.0)
	else:
		stream_telemetry_active = false
		if left_controller and is_instance_valid(left_controller) and left_controller.has_method("trigger_haptic_pulse"):
			left_controller.trigger_haptic_pulse("haptic", 80.0, 0.3, 0.05, 0.0)

	emit_signal("calibration_menu_toggled", is_open)


func _reposition_in_front_of_player() -> void:
	if not is_inside_tree():
		return

	var cam: Camera3D = camera_ref
	if not cam or not is_instance_valid(cam) or not cam.is_inside_tree():
		if get_viewport():
			cam = get_viewport().get_camera_3d()
	if not cam or not is_instance_valid(cam) or not cam.is_inside_tree():
		return

	var cam_pos = cam.global_position
	var fwd = -cam.global_transform.basis.z.normalized()
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	global_position = cam_pos + fwd * 1.15 + Vector3(0.0, -0.04, 0.0)
	if global_position.distance_squared_to(cam_pos) > 0.01:
		look_at(cam_pos, Vector3.UP)
		rotate_y(PI)


func _process(delta: float) -> void:
	if not is_open:
		return

	if input_cooldown > 0.0:
		input_cooldown -= delta

	_process_analog_navigation()
	_process_interactions()
	_update_live_telemetry(delta)


func _process_analog_navigation() -> void:
	if input_cooldown > 0.0:
		return

	var joy_y: float = 0.0
	if left_controller and left_controller.get_is_active():
		joy_y = left_controller.get_vector2("primary").y
	if abs(joy_y) < 0.3 and right_controller and right_controller.get_is_active():
		joy_y = right_controller.get_vector2("primary").y

	if abs(joy_y) > 0.5:
		if joy_y < -0.5:
			selected_index = (selected_index + 1) % CALIBRATION_OPTIONS.size()
			_on_selection_changed()
		elif joy_y > 0.5:
			selected_index = (selected_index - 1 + CALIBRATION_OPTIONS.size()) % CALIBRATION_OPTIONS.size()
			_on_selection_changed()
		input_cooldown = 0.22


func _on_selection_changed() -> void:
	_update_selection_visuals()
	if left_controller and left_controller.has_method("trigger_haptic_pulse"):
		left_controller.trigger_haptic_pulse("haptic", 120.0, 0.35, 0.05, 0.0)


func _update_selection_visuals() -> void:
	for i in range(button_panels.size()):
		var p = button_panels[i]
		var l = button_labels[i]
		var style = p.get_theme_stylebox("panel") as StyleBoxFlat
		if not style:
			continue

		if i == selected_index:
			style.bg_color = Color(0.12, 0.55, 0.95, 0.95) # Azul brillante selección
			style.border_color = Color(0.6, 0.9, 1.0, 1.0)
			style.border_width_left = 5
			style.border_width_top = 5
			style.border_width_right = 5
			style.border_width_bottom = 5
			l.label_settings.font_color = Color(0.02, 0.04, 0.08, 1.0)
		else:
			style.bg_color = Color(0.04, 0.08, 0.14, 0.85)
			style.border_color = Color(0.2, 0.5, 0.8, 0.6)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			l.label_settings.font_color = Color(0.9, 0.95, 1.0, 1.0)


func _process_interactions() -> void:
	var trigger_pressed = false
	if left_controller and left_controller.get_is_active():
		trigger_pressed = left_controller.get_float("trigger") > 0.6 or left_controller.is_button_pressed("trigger_click") or left_controller.is_button_pressed("ax_button")
	if not trigger_pressed and right_controller and right_controller.get_is_active():
		trigger_pressed = right_controller.get_float("trigger") > 0.6 or right_controller.is_button_pressed("trigger_click") or right_controller.is_button_pressed("ax_button")

	if trigger_pressed and input_cooldown <= 0.0:
		input_cooldown = 0.4
		_execute_calibration_action(CALIBRATION_OPTIONS[selected_index]["mode"])


func _execute_calibration_action(mode: String) -> void:
	if left_controller and left_controller.has_method("trigger_haptic_pulse"):
		left_controller.trigger_haptic_pulse("haptic", 200.0, 0.9, 0.18, 0.0)

	match mode:
		"wrist":
			_capture_wrist_data()
		"fist":
			_capture_fist_data()
		"palm":
			_capture_palm_rotation_data()
		"stream":
			stream_telemetry_active = not stream_telemetry_active
			var status = "ACTIVADO (cada 0.5s)" if stream_telemetry_active else "DESACTIVADO"
			print("[CALIBRACION_MANOS] 📡 Stream continuo de telemetría a consola: %s" % status)
			if live_feedback_label:
				live_feedback_label.text = "[CALIBRACION] Stream a consola: %s" % status


func _capture_wrist_data() -> void:
	if not left_controller:
		return
	var pos = left_controller.global_position
	var rot_euler = left_controller.global_transform.basis.get_euler()
	var pitch_deg = rad_to_deg(rot_euler.x)
	var yaw_deg = rad_to_deg(rot_euler.y)
	var roll_deg = rad_to_deg(rot_euler.z)

	var log_msg = "[CALIBRACION_MANOS] 📏 MUÑECA IZQ: Pos=(%.3f, %.3f, %.3f) | Euler=(Pitch: %.1f°, Yaw: %.1f°, Roll: %.1f°)" % [
		pos.x, pos.y, pos.z, pitch_deg, yaw_deg, roll_deg
	]
	print(log_msg)

	if live_feedback_label:
		live_feedback_label.text = "✅ [MUÑECA CAPTURADA]\n" + log_msg


func _capture_fist_data() -> void:
	if not left_controller:
		return
	var trig = left_controller.get_float("trigger")
	var grip = left_controller.get_float("grip")
	var is_ax = left_controller.is_button_pressed("ax_button")
	var stick = left_controller.get_vector2("primary")

	var is_closed = (trig > 0.6 and grip > 0.6)
	var fist_str = "PUÑO CERRADO (100%)" if is_closed else ("PUÑO SEMI-ABIERTO" if (trig > 0.3 or grip > 0.3) else "MANO EXTENDIDA / REPOSO")

	var log_msg = "[CALIBRACION_MANOS] ✊ APERTURA/DEDOS: Trigger=%.2f | Grip=%.2f | BotonAX=%s | Stick=(%.2f, %.2f) => Estado: %s" % [
		trig, grip, str(is_ax), stick.x, stick.y, fist_str
	]
	print(log_msg)

	if live_feedback_label:
		live_feedback_label.text = "✅ [DEDOS CAPTURADOS]\n" + log_msg


func _capture_palm_rotation_data() -> void:
	if not left_controller:
		return
	var basis = left_controller.global_transform.basis
	var palm_normal = -basis.y # Vector perpendicular a la cara interna de la mano
	var up_dot = palm_normal.dot(Vector3.UP)
	var forward_dot = palm_normal.dot(-basis.z)

	var posture = "PALMA AL CIELO (SUPINACIÓN)" if up_dot > 0.5 else ("PALMA AL SUELO (PRONACIÓN)" if up_dot < -0.5 else "PALMA DE PERFIL / LATERAL")

	var log_msg = "[CALIBRACION_MANOS] 🔄 GIRO PALMA: UpDot=%.2f | ForwardDot=%.2f => Orientación: %s" % [
		up_dot, forward_dot, posture
	]
	print(log_msg)

	if live_feedback_label:
		live_feedback_label.text = "✅ [GIRO PALMA CAPTURADO]\n" + log_msg


func _update_live_telemetry(delta: float) -> void:
	if not left_controller:
		return

	# Actualizar visualización en tiempo real en la pantalla del menú
	var trig = left_controller.get_float("trigger")
	var grip = left_controller.get_float("grip")
	var rot_euler = left_controller.global_transform.basis.get_euler()
	var palm_normal = -left_controller.global_transform.basis.y
	var up_dot = palm_normal.dot(Vector3.UP)

	if not stream_telemetry_active and live_feedback_label and not live_feedback_label.text.begins_with("✅"):
		live_feedback_label.text = "📊 [EN VIVO] Trigger: %.2f | Grip: %.2f | PalmaUp: %.2f\nMuñeca Euler: (%.0f°, %.0f°, %.0f°)" % [
			trig, grip, up_dot,
			rad_to_deg(rot_euler.x), rad_to_deg(rot_euler.y), rad_to_deg(rot_euler.z)
		]

	# Stream continuo a consola si está activo
	if stream_telemetry_active:
		stream_timer += delta
		if stream_timer >= 0.5:
			stream_timer = 0.0
			var pos = left_controller.global_position
			print("[CALIBRACION_MANOS_STREAM] Pos=(%.2f, %.2f, %.2f) Euler=(%.0f°, %.0f°, %.0f°) Trig=%.2f Grip=%.2f PalmaUp=%.2f" % [
				pos.x, pos.y, pos.z,
				rad_to_deg(rot_euler.x), rad_to_deg(rot_euler.y), rad_to_deg(rot_euler.z),
				trig, grip, up_dot
			])
			if live_feedback_label:
				live_feedback_label.text = "📡 [STREAM CONSOLA ACTIVO]\nTrig: %.2f | Grip: %.2f | PalmaUp: %.2f | Euler: (%.0f°, %.0f°, %.0f°)" % [
					trig, grip, up_dot,
					rad_to_deg(rot_euler.x), rad_to_deg(rot_euler.y), rad_to_deg(rot_euler.z)
				]
