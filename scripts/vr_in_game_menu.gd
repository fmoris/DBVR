class_name VRInGameMenu
extends Node3D

## VRInGameMenu (Dragon Ball VR)
## Menú táctico 3D con estética canónica Scouter / Dragon Ball Z.
## Accionado por el botón Option (☰) del mando izquierdo.

signal menu_toggled(is_open: bool)

var is_open: bool = false
var selected_index: int = 0
var input_cooldown: float = 0.0

var xr_origin_ref: Node3D = null
var camera_ref: Camera3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null

var sub_viewport: SubViewport = null
var menu_mesh: MeshInstance3D = null
var button_panels: Array[Panel] = []
var button_labels: Array[Label] = []

const BUTTON_DEFS = [
	{ "id": 0, "title": "🥋 CAMBIAR LUCHADOR (VEGETA ⇄ GOKU)", "desc": "Alternar entre Vegeta y Goku en tiempo real", "action": "swap_character" },
	{ "id": 1, "title": "⚔️ DIFICULTAD IA: NORMAL", "desc": "Alternar nivel táctico del rival (Entrenamiento / Normal / Z-Hard)", "action": "cycle_difficulty" },
	{ "id": 2, "title": "📖 MOSTRAR / OCULTAR GUÍA", "desc": "Alternar panel holográfico de técnicas y gestos", "action": "toggle_guide" },
	{ "id": 3, "title": "🔄 RESETEAR COMBATE", "desc": "Reiniciar el combate actual desde el inicio", "action": "reset" },
	{ "id": 4, "title": "🎯 CALIBRAR VISTA VR", "desc": "Centrar posición y orientación física del visor", "action": "calibrate" }
]


func _ready() -> void:
	visible = false
	_build_scouter_menu_ui()


func setup_references(xr_origin: Node3D, camera: Camera3D, left_ctrl: XRController3D, right_ctrl: XRController3D) -> void:
	xr_origin_ref = xr_origin
	camera_ref = camera
	left_controller = left_ctrl
	right_controller = right_ctrl
	if not is_inside_tree() and xr_origin_ref and is_instance_valid(xr_origin_ref) and xr_origin_ref.is_inside_tree():
		xr_origin_ref.add_child(self)


func _build_scouter_menu_ui() -> void:
	# 1. Crear SubViewport 2D de alta resolución (1024x768)
	sub_viewport = SubViewport.new()
	sub_viewport.name = "MenuSubViewport"
	sub_viewport.size = Vector2i(1024, 768)
	sub_viewport.transparent_bg = true
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sub_viewport)

	# 2. Contenedor base de Control
	var root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_viewport.add_child(root_control)

	# 3. Panel de Cristal Scouter (Verde Esmeralda Profundo con Bisel Neón)
	var main_panel = Panel.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.offset_left = 32
	main_panel.offset_top = 32
	main_panel.offset_right = -32
	main_panel.offset_bottom = -32

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.045, 0.04, 0.88) # Cristal Scouter
	panel_style.border_width_left = 4
	panel_style.border_width_top = 4
	panel_style.border_width_right = 4
	panel_style.border_width_bottom = 4
	panel_style.border_color = Color(0.0, 0.95, 0.65, 0.95) # Verde Neón fluorescente
	panel_style.corner_radius_top_left = 26
	panel_style.corner_radius_top_right = 26
	panel_style.corner_radius_bottom_left = 26
	panel_style.corner_radius_bottom_right = 26
	panel_style.set_content_margin_all(28)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	root_control.add_child(main_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(vbox)

	# 4. Título Estilo Dragon Ball Scouter
	var title = Label.new()
	title.text = "⚡ DRAGON BALL VR // MENÚ TÁCTICO ⚡"
	var t_set = LabelSettings.new()
	t_set.font_size = 32
	t_set.font_color = Color(1.0, 0.88, 0.15) # Oro Saiyan
	t_set.shadow_size = 6
	t_set.shadow_color = Color(0.0, 0.0, 0.0, 0.9)
	title.label_settings = t_set
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub_title = Label.new()
	sub_title.text = "PAUSA DE COMBATE — SELECCIONA CON STICK / GATILLO"
	var st_set = LabelSettings.new()
	st_set.font_size = 17
	st_set.font_color = Color(0.3, 0.9, 0.75, 0.85)
	sub_title.label_settings = st_set
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_title)

	# Separador
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 5. Botones interactivos
	button_panels.clear()
	button_labels.clear()

	for i in range(BUTTON_DEFS.size()):
		var def = BUTTON_DEFS[i]
		var btn_panel = Panel.new()
		btn_panel.custom_minimum_size = Vector2(0, 82)

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.02, 0.08, 0.06, 0.85)
		btn_style.border_width_left = 3
		btn_style.border_width_top = 3
		btn_style.border_width_right = 3
		btn_style.border_width_bottom = 3
		btn_style.border_color = Color(0.15, 0.65, 0.50, 0.6)
		btn_style.corner_radius_top_left = 14
		btn_style.corner_radius_top_right = 14
		btn_style.corner_radius_bottom_left = 14
		btn_style.corner_radius_bottom_right = 14
		btn_panel.add_theme_stylebox_override("panel", btn_style)
		vbox.add_child(btn_panel)

		var btn_vbox = VBoxContainer.new()
		btn_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_panel.add_child(btn_vbox)

		var lbl_title = Label.new()
		lbl_title.text = def["title"]
		var l_set = LabelSettings.new()
		l_set.font_size = 25
		l_set.font_color = Color.WHITE
		lbl_title.label_settings = l_set
		lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(lbl_title)

		var lbl_desc = Label.new()
		lbl_desc.text = def["desc"]
		var d_set = LabelSettings.new()
		d_set.font_size = 15
		d_set.font_color = Color(0.65, 0.80, 0.80)
		lbl_desc.label_settings = d_set
		lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(lbl_desc)

		button_panels.append(btn_panel)
		button_labels.append(lbl_title)

	# 6. Malla Quad 3D espacial para proyectar el menú
	menu_mesh = MeshInstance3D.new()
	menu_mesh.name = "MenuQuadMesh"
	var quad = QuadMesh.new()
	quad.size = Vector2(1.05, 0.78)
	menu_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = sub_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 110
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
				push_warning("[VRInGameMenu] Advertencia: No se puede alternar el menú fuera de un nodo 3D del árbol.")
				return

	if not is_inside_tree():
		return

	is_open = not is_open
	visible = is_open

	if is_open:
		_reposition_in_front_of_player()
		_refresh_dynamic_labels()
		_update_selection_visuals()
		if sub_viewport and is_instance_valid(sub_viewport):
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if menu_mesh and is_instance_valid(menu_mesh):
			menu_mesh.scale = Vector3.ZERO
			if is_inside_tree():
				var tw = create_tween()
				if tw:
					tw.tween_property(menu_mesh, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Pulso háptico suave de apertura
		if left_controller and is_instance_valid(left_controller) and left_controller.has_method("trigger_haptic_pulse"):
			left_controller.trigger_haptic_pulse("haptic", 120.0, 0.5, 0.1, 0.0)
	else:
		if sub_viewport and is_instance_valid(sub_viewport):
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if left_controller and is_instance_valid(left_controller) and left_controller.has_method("trigger_haptic_pulse"):
			left_controller.trigger_haptic_pulse("haptic", 80.0, 0.3, 0.05, 0.0)

	emit_signal("menu_toggled", is_open)


func _reposition_in_front_of_player() -> void:
	if not is_inside_tree():
		return

	var cam: Camera3D = camera_ref
	if not cam or not is_instance_valid(cam) or not cam.is_inside_tree():
		if is_inside_tree() and get_viewport():
			cam = get_viewport().get_camera_3d()
	if not cam or not is_instance_valid(cam) or not cam.is_inside_tree():
		return

	# Proyectar flotando a 1.65m exactamente frente a la mirada del jugador
	var cam_pos = cam.global_position
	var fwd = -cam.global_transform.basis.z.normalized()
	fwd.y = 0.0 # Mantener nivelado con el horizonte para evitar cabeceo incómodo
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	global_position = cam_pos + fwd * 1.65 + Vector3(0.0, -0.05, 0.0)
	if global_position.distance_squared_to(cam_pos) > 0.01:
		look_at(cam_pos, Vector3.UP)
		rotate_y(PI) # Alinear la normal frontal del Quad hacia los ojos


func _process(delta: float) -> void:
	if not is_open:
		return

	if input_cooldown > 0.0:
		input_cooldown -= delta

	# 1. Navegación con Stick Analógico
	_process_analog_navigation()

	# 2. Selección con Gatillo o Botón A/X
	_process_interactions()


func _process_analog_navigation() -> void:
	if input_cooldown > 0.0:
		return

	var joy_y: float = 0.0
	if right_controller and right_controller.get_is_active():
		joy_y = right_controller.get_vector2("primary").y
	if abs(joy_y) < 0.3 and left_controller and left_controller.get_is_active():
		joy_y = left_controller.get_vector2("primary").y

	if abs(joy_y) > 0.5:
		if joy_y < -0.5: # Stick hacia abajo
			selected_index = (selected_index + 1) % BUTTON_DEFS.size()
			_on_selection_changed()
		elif joy_y > 0.5: # Stick hacia arriba
			selected_index = (selected_index - 1 + BUTTON_DEFS.size()) % BUTTON_DEFS.size()
			_on_selection_changed()
		input_cooldown = 0.22


func _on_selection_changed() -> void:
	_update_selection_visuals()
	if right_controller and right_controller.has_method("trigger_haptic_pulse"):
		right_controller.trigger_haptic_pulse("haptic", 120.0, 0.35, 0.05, 0.0)
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
			style.bg_color = Color(0.9, 0.70, 0.12, 0.95) # Oro brillante al seleccionar
			style.border_color = Color(1.0, 1.0, 0.4, 1.0)
			style.border_width_left = 5
			style.border_width_top = 5
			style.border_width_right = 5
			style.border_width_bottom = 5
			l.label_settings.font_color = Color(0.02, 0.04, 0.04, 1.0) # Texto oscuro sobre oro
		else:
			style.bg_color = Color(0.02, 0.08, 0.06, 0.85)
			style.border_color = Color(0.15, 0.65, 0.50, 0.6)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			l.label_settings.font_color = Color(0.85, 0.98, 0.92, 1.0)
	if sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_open else SubViewport.UPDATE_DISABLED


func _process_interactions() -> void:
	var trigger_pressed = false
	if right_controller and right_controller.get_is_active():
		trigger_pressed = right_controller.get_float("trigger") > 0.6 or right_controller.is_button_pressed("trigger_click") or right_controller.is_button_pressed("ax_button")
	if not trigger_pressed and left_controller and left_controller.get_is_active():
		trigger_pressed = left_controller.get_float("trigger") > 0.6 or left_controller.is_button_pressed("trigger_click") or left_controller.is_button_pressed("ax_button")

	if trigger_pressed and input_cooldown <= 0.0:
		input_cooldown = 0.4
		_activate_action(BUTTON_DEFS[selected_index]["action"])


func _activate_action(action_name: String) -> void:
	print("[VRInGameMenu] Acción seleccionada: ", action_name)

	# Pulso háptico de confirmación
	if right_controller and right_controller.has_method("trigger_haptic_pulse"):
		right_controller.trigger_haptic_pulse("haptic", 200.0, 0.9, 0.2, 0.0)
	if left_controller and left_controller.has_method("trigger_haptic_pulse"):
		left_controller.trigger_haptic_pulse("haptic", 200.0, 0.9, 0.2, 0.0)

	match action_name:
		"swap_character":
			_execute_character_swap()
			_refresh_dynamic_labels()

		"cycle_difficulty":
			_cycle_ai_difficulty()
			_refresh_dynamic_labels()

		"toggle_guide":
			if is_inside_tree() and get_tree() and get_tree().root:
				var hud = get_tree().root.find_child("VRHUD", true, false)
				if hud and hud.has_method("toggle_moves_guide"):
					hud.toggle_moves_guide()
			toggle_menu()

		"reset":
			print("[VRInGameMenu] 🔄 Reiniciando combate...")
			toggle_menu()
			if is_inside_tree() and get_tree():
				get_tree().reload_current_scene()

		"calibrate":
			print("[VRInGameMenu] 🎯 Calibrando vista VR...")
			XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
			if is_inside_tree() and get_tree():
				var tw = create_tween()
				if tw:
					tw.tween_interval(0.35)
					tw.tween_callback(func(): _reposition_in_front_of_player())
			else:
				_reposition_in_front_of_player()


func _refresh_dynamic_labels() -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
		return
	var scene: Node = get_tree().current_scene
	var player: Node = scene.find_child("PlayerCharacterInstance", true, false)
	var enemy: Node = scene.find_child("EnemyCharacterInstance", true, false)

	if button_labels.size() > 0 and player and player.get("character_data"):
		var p_name: String = str(player.character_data.character_name).to_upper()
		var opp_name: String = "GOKU" if "VEGETA" in p_name else "VEGETA"
		button_labels[0].text = "🥋 CAMBIAR LUCHADOR (%s ➔ %s)" % [p_name, opp_name]

	if button_labels.size() > 1 and enemy:
		var ai_ctrl: Node = enemy.get_node_or_null("CombatAIController")
		if ai_ctrl and ai_ctrl.has_method("get_difficulty_label"):
			button_labels[1].text = "⚔️ DIFICULTAD IA: %s" % ai_ctrl.get_difficulty_label()

	if sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_open else SubViewport.UPDATE_DISABLED


func _execute_character_swap() -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
		return
	var scene: Node = get_tree().current_scene
	var player: Node = scene.find_child("PlayerCharacterInstance", true, false)
	var enemy: Node = scene.find_child("EnemyCharacterInstance", true, false)
	if not player or not enemy:
		return

	var goku_res: CharacterData = load("res://resources/goku.tres")
	var goku_zenkai_res: CharacterData = load("res://resources/goku_zenkai.tres")
	var vegeta_res: CharacterData = load("res://resources/vegeta.tres")
	if not goku_res or not vegeta_res:
		push_warning("[VRInGameMenu] No se pudieron cargar goku.tres o vegeta.tres para intercambio.")
		return

	var p_name_upper: String = ""
	if player.get("character_data"):
		p_name_upper = str(player.character_data.character_name).to_upper()

	var new_player_data: CharacterData = vegeta_res
	var new_enemy_data: CharacterData = goku_res
	if "ZENKAI" in p_name_upper:
		new_player_data = goku_res
		new_enemy_data = vegeta_res
	elif "VEGETA" in p_name_upper:
		new_player_data = goku_zenkai_res if goku_zenkai_res else goku_res
		new_enemy_data = vegeta_res
	else:
		new_player_data = vegeta_res
		new_enemy_data = goku_zenkai_res if goku_zenkai_res else goku_res

	if player.has_method("swap_character_data"):
		player.swap_character_data(new_player_data)
	if enemy.has_method("swap_character_data"):
		enemy.swap_character_data(new_enemy_data)

	var hud: Node = get_tree().root.find_child("VRHUD", true, false)
	if hud and hud.has_method("refresh_for_character_swap"):
		hud.refresh_for_character_swap()

	var lockon: Node = scene.find_child("KiSenseAndLockOn", true, false)
	if lockon and lockon.has_method("show_scouter_alert"):
		lockon.show_scouter_alert("🥋 LUCHADOR: %s" % new_player_data.character_name.to_upper(), "Combate renovado vs %s" % new_enemy_data.character_name.to_upper(), Color(0.25, 0.9, 1.0), 2.2)

	print("[VRInGameMenu] 🥋 Intercambio completado: Jugador=%s | Rival=%s" % [new_player_data.character_name, new_enemy_data.character_name])


func _cycle_ai_difficulty() -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene:
		return
	var enemy: Node = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
	if not enemy:
		return
	var ai_ctrl: Node = enemy.get_node_or_null("CombatAIController")
	if not ai_ctrl or not ai_ctrl.has_method("set_difficulty"):
		return
	var current_diff: int = int(ai_ctrl.get("difficulty"))
	var next_diff: int = (current_diff + 1) % 3
	ai_ctrl.set_difficulty(next_diff)
	var label_str: String = ai_ctrl.get_difficulty_label() if ai_ctrl.has_method("get_difficulty_label") else str(next_diff)
	print("[VRInGameMenu] ⚔️ Dificultad IA cambiada a: %s" % label_str)
