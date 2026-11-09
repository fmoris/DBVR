@tool
extends Node3D

# --- Parámetros de Posicionamiento Fijo (Simulador/Fallback) ---
@export var distance_from_camera: float = 1.15
@export var horizontal_offset: float = 0.0
@export var vertical_offset: float = -0.34
@export var tilt_angle_degrees: float = 14.0

@onready var sub_viewport: SubViewport = $SubViewport
@onready var hud_mesh: MeshInstance3D = $HUDMesh

# --- Elementos de la Interfaz Canónica de Dragon Ball (Scouter & HUD) ---
var scouter_panel: Panel = null
var player_badge_label: Label = null
var rival_scouter_label: Label = null
var bp_title_label: Label = null
var bp_value_label: Label = null
var threshold_labels: Array[Label] = []
var ki_text_label: Label = null
var ki_cost_label: Label = null
var ki_progress_bar: ProgressBar = null
var guard_badge_label: Label = null
var zenkai_badge_label: Label = null
var action_status_label: Label = null

var gesture_tree_ref: Node = null
var player_instance: Node = null
var enemy_instance: Node = null

# --- Estado del Combate Dinámico ---
var ki_max: float = 100.0
var ki_current: float = 50.0 
var np_max: float = 20000.0
var np_current: float = 9000.0

var is_recharging: bool = false
var is_heavy_recharge: bool = false
var zenkai_pulse_timer: float = 0.0

# --- Historial de Depuración VR ---
var debug_history: Array[String] = []

# --- Nodos Procedimentales del Debug Tooltip (Cámara flotante superior) ---
var tooltip_viewport: SubViewport = null
var tooltip_mesh: MeshInstance3D = null
var tooltip_debug_logs: RichTextLabel = null
var tooltip_live_joints: Label = null

# --- Nodos Procedimentales de la Guía de Movimientos (Cámara flotante abajo a la derecha) ---
var moves_guide_viewport: SubViewport = null
var moves_guide_mesh: MeshInstance3D = null
var moves_guide_label: RichTextLabel = null
var moves_guide_mode_label: Label = null
var current_controller_mode: bool = true


var left_wrist_node: Node3D = null
var is_wrist_mode: bool = false
var wrist_hud_scale: float = 0.0

func _ready() -> void:
	if not sub_viewport or not hud_mesh:
		return
		
	# Configurar material sin prueba de profundidad y transparente para el HUD
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Glow directo sin sombras
	mat.albedo_texture = sub_viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 110
	hud_mesh.material_override = mat

	# Redimensionar la malla del HUD para estética Scouter cinematográfica (26cm x 13cm - ratio 2:1)
	if hud_mesh.mesh is QuadMesh:
		hud_mesh.mesh.size = Vector2(0.26, 0.13)

	# Construir la interfaz Dragon Ball Sci-Fi / Scouter procedimentalmente
	_build_dragon_ball_hud()

	if not Engine.is_editor_hint():
		call_deferred("_setup_wrist_hud")
		call_deferred("_setup_debug_tooltip")
		call_deferred("_setup_moves_guide_hud")


func _exit_tree() -> void:
	if tooltip_mesh and is_instance_valid(tooltip_mesh):
		tooltip_mesh.queue_free()
	tooltip_mesh = null
	if moves_guide_mesh and is_instance_valid(moves_guide_mesh):
		moves_guide_mesh.queue_free()
	moves_guide_mesh = null


func _setup_wrist_hud() -> void:
	if hud_mesh and is_instance_valid(hud_mesh):
		hud_mesh.top_level = true
		hud_mesh.scale = Vector3.ZERO
		hud_mesh.visible = false
		wrist_hud_scale = 0.0

	is_wrist_mode = true
	set_process(true)
	_connect_gesture_signals()
	print("[VRHUD] HUD holográfico montado exitosamente en muñeca/palma izquierda.")


## Detecta posición y orientación biométrica de la muñeca y palma izquierda (Mandos o Hand Tracking)
func _get_left_wrist_and_palm_info() -> Dictionary:
	var xr_origin = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D") as XROrigin3D
	if not xr_origin:
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.current_scene:
			xr_origin = tree.current_scene.find_child("Player_XROrigin3D", true, false) as XROrigin3D
			if not xr_origin:
				xr_origin = tree.current_scene.find_child("XROrigin3D", true, false) as XROrigin3D
	if not xr_origin:
		return { "valid": false }

	# 1. Prioridad: Controlador izquierdo Quest Touch (Modo activo preferente)
	var left_ctrl = xr_origin.get_node_or_null("LeftHand") as XRController3D
	if not left_ctrl:
		left_ctrl = xr_origin.find_child("LeftHand", true, false) as XRController3D
	if left_ctrl and left_ctrl.get_is_active():
		var l_basis = left_ctrl.global_transform.basis
		var w_pos = left_ctrl.global_position + l_basis * Vector3(0.0, 0.05, 0.04)
		var p_pos = left_ctrl.global_position + l_basis * Vector3(0.0, 0.08, 0.0)
		return {
			"valid": true,
			"wrist_pos": w_pos,
			"palm_pos": p_pos,
			"is_hand_tracking": false
		}
	elif left_ctrl:
		return {
			"valid": true,
			"wrist_pos": left_ctrl.global_position + Vector3.UP * 0.05,
			"palm_pos": left_ctrl.global_position + Vector3.UP * 0.08,
			"is_hand_tracking": false
		}

	# 2. Fallback: OpenXR Hand Tracking nativo si no hay mandos físicos
	var left_tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if left_tracker:
		var flags_wrist = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST)
		var flags_palm = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags_wrist & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) or (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var w_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if (flags_wrist & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) else left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			var p_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin if (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) else w_local
			return {
				"valid": true,
				"wrist_pos": xr_origin.global_transform * w_local,
				"palm_pos": xr_origin.global_transform * p_local,
				"is_hand_tracking": true
			}

	return { "valid": false }


func _reparent_to_camera_fallback() -> void:
	var camera = get_viewport().get_camera_3d()
	if camera:
		if get_parent() != camera:
			var old_parent = get_parent()
			if old_parent:
				old_parent.remove_child(self)
			camera.add_child(self)
		
		# Posicionar flotando al centro-abajo en la periferia de la visión
		position = Vector3(horizontal_offset, vertical_offset, -distance_from_camera)
		rotation = Vector3(deg_to_rad(tilt_angle_degrees), 0, 0)
		set_process(true)
		_connect_gesture_signals()
		print("[VRHUD] Fallback: HUD Dragon Ball Scouter asignado frente a la Cámara.")


# -----------------------------------------------------------------
# CONSTRUCCIÓN DEL HUD ESTILO DRAGON BALL (SCOUTER & GUANTELETE)
# -----------------------------------------------------------------
func _build_dragon_ball_hud() -> void:
	var hud_layout = sub_viewport.get_node_or_null("HUDLayout")
	if not hud_layout:
		return
		
	# Limpiar elementos anteriores
	for child in hud_layout.get_children():
		child.queue_free()

	# 1. Panel Principal de Cristal Scouter (Verde Esmeralda Oscuro con Bisel Neón)
	scouter_panel = Panel.new()
	scouter_panel.name = "ScouterGlassPanel"
	scouter_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	scouter_panel.offset_left = 20
	scouter_panel.offset_top = 20
	scouter_panel.offset_right = -20
	scouter_panel.offset_bottom = -20
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.045, 0.04, 0.82) # Cristal verde Scouter profundo
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.0, 0.95, 0.65, 0.90) # Verde Scouter Neón
	panel_style.corner_radius_top_left = 22
	panel_style.corner_radius_top_right = 22
	panel_style.corner_radius_bottom_left = 22
	panel_style.corner_radius_bottom_right = 22
	panel_style.set_content_margin_all(20)
	scouter_panel.add_theme_stylebox_override("panel", panel_style)
	hud_layout.add_child(scouter_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	scouter_panel.add_child(main_vbox)

	# 2. Fila Superior: Badge del Jugador + Scouter del Rival
	var header_hbox = HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header_hbox)

	player_badge_label = Label.new()
	player_badge_label.text = "[ 🥋 VEGETA // BASE ]"
	var p_settings = LabelSettings.new()
	p_settings.font_size = 32
	p_settings.font_color = Color(0.0, 0.9, 1.0) # Cian neón
	p_settings.shadow_size = 5
	p_settings.shadow_color = Color(0, 0, 0, 0.95)
	player_badge_label.label_settings = p_settings
	header_hbox.add_child(player_badge_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	rival_scouter_label = Label.new()
	rival_scouter_label.text = "[ 🎯 RIVAL: GOKU // BP 2,800,000,000 ]"
	var r_settings = LabelSettings.new()
	r_settings.font_size = 28
	r_settings.font_color = Color(0.2, 1.0, 0.4) # Verde Scouter
	r_settings.shadow_size = 5
	r_settings.shadow_color = Color(0, 0, 0, 0.95)
	rival_scouter_label.label_settings = r_settings
	header_hbox.add_child(rival_scouter_label)

	# 3. Sección de Nivel de Poder (Battle Power - Scouter)
	var bp_box = VBoxContainer.new()
	bp_box.add_theme_constant_override("separation", 2)
	main_vbox.add_child(bp_box)

	var bp_head_hbox = HBoxContainer.new()
	bp_box.add_child(bp_head_hbox)

	bp_title_label = Label.new()
	bp_title_label.text = "⚡ SCOUTER BATTLE POWER"
	var bp_t_settings = LabelSettings.new()
	bp_t_settings.font_size = 22
	bp_t_settings.font_color = Color(0.4, 0.95, 0.75, 0.95)
	bp_title_label.label_settings = bp_t_settings
	bp_head_hbox.add_child(bp_title_label)

	var bp_spacer = Control.new()
	bp_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_head_hbox.add_child(bp_spacer)

	# Umbrales Irreversibles (25%, 50%, 75%, 100%)
	threshold_labels.clear()
	var thresh_names = ["25%", "50%", "75%", "100% MAX"]
	for t_name in thresh_names:
		var t_lbl = Label.new()
		t_lbl.text = "[" + t_name + "]"
		var t_set = LabelSettings.new()
		t_set.font_size = 20
		t_set.font_color = Color(0.4, 0.5, 0.5, 0.8)
		t_lbl.label_settings = t_set
		bp_head_hbox.add_child(t_lbl)
		threshold_labels.append(t_lbl)

	bp_value_label = Label.new()
	bp_value_label.text = "BP: 2,800,000,000"
	var bp_v_settings = LabelSettings.new()
	bp_v_settings.font_size = 72
	bp_v_settings.font_color = Color(0.15, 1.0, 0.45) # Verde Scouter fluorescente
	bp_v_settings.shadow_size = 8
	bp_v_settings.shadow_color = Color(0, 0, 0, 0.98)
	bp_value_label.label_settings = bp_v_settings
	bp_box.add_child(bp_value_label)

	# 4. Sección de Barra de Ki (Energía Viva)
	var ki_box = VBoxContainer.new()
	ki_box.add_theme_constant_override("separation", 6)
	main_vbox.add_child(ki_box)

	var ki_head_hbox = HBoxContainer.new()
	ki_box.add_child(ki_head_hbox)

	ki_text_label = Label.new()
	ki_text_label.text = "⚡ KI: 50 / 100 (50%)"
	var ki_t_settings = LabelSettings.new()
	ki_t_settings.font_size = 36
	ki_t_settings.font_color = Color(0.0, 0.95, 1.0) # Azul Ki brillante
	ki_t_settings.shadow_size = 6
	ki_t_settings.shadow_color = Color(0, 0, 0, 0.95)
	ki_text_label.label_settings = ki_t_settings
	ki_head_hbox.add_child(ki_text_label)

	var ki_spacer = Control.new()
	ki_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ki_head_hbox.add_child(ki_spacer)

	ki_cost_label = Label.new()
	ki_cost_label.text = "[BLAST: 6 | GALICK: 50 | BIG BANG: 65 | FINAL FLASH: 90]"
	var cost_settings = LabelSettings.new()
	cost_settings.font_size = 20
	cost_settings.font_color = Color(1.0, 0.88, 0.25, 0.95)
	ki_cost_label.label_settings = cost_settings
	ki_head_hbox.add_child(ki_cost_label)

	# Barra de Ki Estilizada
	ki_progress_bar = ProgressBar.new()
	ki_progress_bar.custom_minimum_size = Vector2(0, 32)
	ki_progress_bar.max_value = 100.0
	ki_progress_bar.value = 50.0
	ki_progress_bar.show_percentage = false
	
	var bg_bar = StyleBoxFlat.new()
	bg_bar.bg_color = Color(0.02, 0.05, 0.08, 0.85)
	bg_bar.border_width_left = 2
	bg_bar.border_width_top = 2
	bg_bar.border_width_right = 2
	bg_bar.border_width_bottom = 2
	bg_bar.border_color = Color(0.1, 0.4, 0.5, 0.8)
	bg_bar.corner_radius_top_left = 8
	bg_bar.corner_radius_top_right = 8
	bg_bar.corner_radius_bottom_left = 8
	bg_bar.corner_radius_bottom_right = 8
	ki_progress_bar.add_theme_stylebox_override("background", bg_bar)

	var fill_bar = StyleBoxFlat.new()
	fill_bar.bg_color = Color(0.0, 0.85, 1.0, 0.95) # Cian Ki brillante
	fill_bar.corner_radius_top_left = 8
	fill_bar.corner_radius_top_right = 8
	fill_bar.corner_radius_bottom_left = 8
	fill_bar.corner_radius_bottom_right = 8
	ki_progress_bar.add_theme_stylebox_override("fill", fill_bar)
	ki_box.add_child(ki_progress_bar)

	# 5. Fila de Badges de Combate: Guardia + Estado Zenkai / Furia
	var status_hbox = HBoxContainer.new()
	status_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(status_hbox)

	guard_badge_label = Label.new()
	guard_badge_label.text = "[ 🛡️ GUARDIA: LISTA ]"
	var g_settings = LabelSettings.new()
	g_settings.font_size = 24
	g_settings.font_color = Color(0.2, 0.9, 0.4) # Verde listo
	guard_badge_label.label_settings = g_settings
	status_hbox.add_child(guard_badge_label)

	zenkai_badge_label = Label.new()
	zenkai_badge_label.text = "[ ⚡ ESTADO: NORMAL ]"
	var z_settings = LabelSettings.new()
	z_settings.font_size = 24
	z_settings.font_color = Color(0.7, 0.8, 0.9)
	zenkai_badge_label.label_settings = z_settings
	status_hbox.add_child(zenkai_badge_label)

	# 6. Pie de Acción: Técnica o Postura Activa
	action_status_label = Label.new()
	action_status_label.text = "▶ POSTURA: IDLE (NEUTRAL)"
	var a_settings = LabelSettings.new()
	a_settings.font_size = 26
	a_settings.font_color = Color(1.0, 0.92, 0.6) # Dorado suave
	action_status_label.label_settings = a_settings
	main_vbox.add_child(action_status_label)


func _connect_gesture_signals() -> void:
	update_ki(ki_current, ki_max)
	update_power_level(np_current, np_max)
	
	var gesture_tree = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
	if not gesture_tree:
		gesture_tree = get_tree().root.find_child("GesturePhaseTree", true, false)
		
	if gesture_tree:
		gesture_tree_ref = gesture_tree
		if gesture_tree.ki_recharge_started.is_connected(_on_recharge_started):
			gesture_tree.ki_recharge_started.disconnect(_on_recharge_started)
		if gesture_tree.ki_recharge_stopped.is_connected(_on_recharge_stopped):
			gesture_tree.ki_recharge_stopped.disconnect(_on_recharge_stopped)
		if gesture_tree.ki_blast_fired.is_connected(_on_ki_blast_fired):
			gesture_tree.ki_blast_fired.disconnect(_on_ki_blast_fired)
		if gesture_tree.has_signal("ki_blast_charging") and gesture_tree.ki_blast_charging.is_connected(_on_ki_blast_charging):
			gesture_tree.ki_blast_charging.disconnect(_on_ki_blast_charging)
		if gesture_tree.has_signal("gesture_logged") and gesture_tree.gesture_logged.is_connected(log_gesture_event):
			gesture_tree.gesture_logged.disconnect(log_gesture_event)
		if gesture_tree.has_signal("hand_states_updated") and gesture_tree.hand_states_updated.is_connected(_on_hand_states_updated):
			gesture_tree.hand_states_updated.disconnect(_on_hand_states_updated)
		if gesture_tree.has_signal("phase_changed") and gesture_tree.phase_changed.is_connected(_on_phase_changed):
			gesture_tree.phase_changed.disconnect(_on_phase_changed)

		gesture_tree.ki_recharge_started.connect(_on_recharge_started)
		gesture_tree.ki_recharge_stopped.connect(_on_recharge_stopped)
		gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)
		if gesture_tree.has_signal("ki_blast_charging"):
			gesture_tree.ki_blast_charging.connect(_on_ki_blast_charging)
		if gesture_tree.has_signal("gesture_logged"):
			gesture_tree.gesture_logged.connect(log_gesture_event)
		if gesture_tree.has_signal("hand_states_updated"):
			gesture_tree.hand_states_updated.connect(_on_hand_states_updated)
		if gesture_tree.has_signal("phase_changed"):
			gesture_tree.phase_changed.connect(_on_phase_changed)

		var hybrid_ctrl = gesture_tree.get_node_or_null("HybridCombatController")
		if hybrid_ctrl:
			if hybrid_ctrl.controller_mode_changed.is_connected(_on_controller_mode_changed):
				hybrid_ctrl.controller_mode_changed.disconnect(_on_controller_mode_changed)
			hybrid_ctrl.controller_mode_changed.connect(_on_controller_mode_changed)
			_update_moves_guide_text(hybrid_ctrl.controllers_active)
		else:
			_update_moves_guide_text(true)

		print("[VRHUD] Señales de GesturePhaseTree vinculadas con éxito.")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if moves_guide_mesh == null:
		_setup_moves_guide_hud()
		
	# Control Diegético del HUD en la Muñeca / Palma (KI, BP y Scouter Status)
	if is_wrist_mode and is_instance_valid(hud_mesh):
		var camera = get_viewport().get_camera_3d()
		var should_display: bool = false

		var hand_info = _get_left_wrist_and_palm_info()
		if hand_info.get("valid", false) and camera and is_instance_valid(camera):
			var cam_pos = camera.global_position
			var wrist_pos = hand_info["wrist_pos"] as Vector3
			var palm_pos = hand_info["palm_pos"] as Vector3
			var display_anchor = (wrist_pos + palm_pos) * 0.5

			# Distancia euclídea del visor a la mano izquierda
			var dist = display_anchor.distance_to(cam_pos)

			# Vector hacia donde apunta la mirada del jugador
			var cam_forward = -camera.global_transform.basis.z.normalized()
			var dir_from_cam = (display_anchor - cam_pos).normalized()
			var in_view = cam_forward.dot(dir_from_cam)

			# Activación natural e intuitiva:
			# El jugador mira su mano/muñeca izquierda en su campo de visión
			# a distancia ergonómica de lectura (8cm a 1.15m)
			if in_view > 0.15 and dist >= 0.08 and dist <= 1.15 and display_anchor.y > (cam_pos.y - 1.15):
				should_display = true

			if should_display or wrist_hud_scale > 0.01:
				# Flotar holográficamente 10 cm sobre el mando/muñeca
				var float_offset = Vector3.UP * 0.10 + (cam_pos - display_anchor).normalized() * 0.05
				hud_mesh.global_position = display_anchor + float_offset
				# Orientar siempre la pantalla holográfica frente a los ojos del jugador para máxima nitidez
				hud_mesh.look_at(cam_pos, Vector3.UP, true)

		var target_scale = 1.0 if should_display else 0.0
		wrist_hud_scale = move_toward(wrist_hud_scale, target_scale, delta * 6.5)
		hud_mesh.scale = Vector3.ONE * wrist_hud_scale
		hud_mesh.visible = (wrist_hud_scale > 0.02)
		
	# Búsqueda dinámica de la instancia del jugador
	if player_instance == null or not is_instance_valid(player_instance):
		var player = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D/PlayerCharacterInstance")
		if player:
			player_instance = player
			player_instance.stats_changed.connect(_on_player_stats_changed)
			if player_instance.has_signal("transformation_unlocked"):
				player_instance.transformation_unlocked.connect(_on_transformation_unlocked)
			_on_player_stats_changed(player_instance.current_ki, player_instance.current_np, player_instance.is_in_zenkai_state)
			_update_moves_guide_text(current_controller_mode)
			if ki_cost_label and player_instance.character_data:
				var cname = player_instance.character_data.character_name.to_upper()
				if "VEGETA" in cname:
					ki_cost_label.text = "[BLAST: 6 | GALICK: 50 | BIG BANG: 65 | FINAL FLASH: 90]"
				else:
					ki_cost_label.text = "[BLAST: 6 | KAMEHAMEHA: 50 | GENKIDAMA: 90]"
			print("[VRHUD] Enlazado exitosamente al CharacterInstance del jugador.")

	# Búsqueda dinámica del contrincante (Rival Scouter)
	if enemy_instance == null or not is_instance_valid(enemy_instance):
		var enemy = get_node_or_null("/root/cell_games_arena/EnemyCharacterInstance")
		if enemy:
			enemy_instance = enemy

	_update_combat_stats(delta)
	_update_dbz_hud_elements(delta)


func _update_dbz_hud_elements(delta: float) -> void:
	# 1. Actualizar datos del Rival en el Scouter
	if enemy_instance and is_instance_valid(enemy_instance) and rival_scouter_label:
		var e_name = enemy_instance.character_data.character_name.to_upper() if enemy_instance.character_data else "RIVAL"
		var e_np = int(enemy_instance.current_np)
		rival_scouter_label.text = "[ 🎯 RIVAL: %s // BP %s ]" % [e_name, format_number_with_commas(e_np)]

	# 2. Actualizar estado de guardia y bloqueo
	if player_instance and is_instance_valid(player_instance) and guard_badge_label:
		if player_instance.get("is_guard_broken"):
			guard_badge_label.text = "[ ⚠️ ¡GUARDIA ROTA! (STAGGER) ]"
			guard_badge_label.label_settings.font_color = Color(1.0, 0.2, 0.2) # Rojo parpadeante
		elif player_instance.get("is_blocking"):
			guard_badge_label.text = "[ 🛡️ BLOQUEANDO [-75%] ]"
			guard_badge_label.label_settings.font_color = Color(1.0, 0.9, 0.2) # Amarillo defensivo
		else:
			guard_badge_label.text = "[ 🛡️ GUARDIA: LISTA ]"
			guard_badge_label.label_settings.font_color = Color(0.2, 0.9, 0.4) # Verde listo

	# 3. Animar pulso de Zenkai / Furia
	if player_instance and is_instance_valid(player_instance) and zenkai_badge_label:
		if player_instance.get("is_in_zenkai_state"):
			zenkai_pulse_timer += delta * 6.0
			var pulse_val = (sin(zenkai_pulse_timer) + 1.0) * 0.5
			var z_col = Color(1.0, 0.2 + pulse_val * 0.6, 0.1)
			zenkai_badge_label.text = "[ 🔥 ¡ESTADO ZENKAI ACTIVO! - FINISHER K.O. DISPONIBLE 🔥 ]"
			zenkai_badge_label.label_settings.font_color = z_col
		else:
			zenkai_badge_label.text = "[ ⚡ ESTADO: NORMAL ]"
			zenkai_badge_label.label_settings.font_color = Color(0.7, 0.8, 0.9)


func _on_player_stats_changed(ki: float, np: float, _is_zenkai: bool) -> void:
	var max_ki = 100.0
	var max_np = 20000.0
	if player_instance and player_instance.character_data:
		max_ki = player_instance.character_data.base_ki
		max_np = player_instance.character_data.max_np
		if player_instance.current_transformation:
			max_np *= player_instance.current_transformation.np_multiplier

	update_ki(ki, max_ki)
	update_power_level(np, max_np)
	
	ki_current = ki
	np_current = np
	ki_max = max_ki
	np_max = max_np

	# Actualizar nombre y transformación del jugador
	if player_badge_label and player_instance and player_instance.character_data:
		var c_name = player_instance.character_data.character_name.to_upper()
		var form = "BASE"
		var form_col = Color(0.0, 0.85, 1.0)
		if player_instance.current_transformation:
			form = player_instance.current_transformation.form_name.to_upper()
			form_col = player_instance.current_transformation.aura_color
		player_badge_label.text = "[ 🥋 %s // %s ]" % [c_name, form]
		player_badge_label.label_settings.font_color = form_col


func _on_transformation_unlocked(form_name: String) -> void:
	if action_status_label:
		action_status_label.text = "⚡ ¡PODER SAIYAN DESPERTADO: %s! ⚡" % form_name.to_upper()
		action_status_label.label_settings.font_color = Color(1.0, 0.9, 0.1)


func _on_phase_changed(new_phase_name: String) -> void:
	if action_status_label:
		action_status_label.text = "▶ %s" % new_phase_name.to_upper()
		if "KAMEHAMEHA" in new_phase_name:
			action_status_label.label_settings.font_color = Color(0.2, 0.8, 1.0)
		elif "RECARGA" in new_phase_name:
			action_status_label.label_settings.font_color = Color(1.0, 0.85, 0.2)
		elif "MELEE" in new_phase_name:
			action_status_label.label_settings.font_color = Color(1.0, 0.4, 0.3)
		else:
			action_status_label.label_settings.font_color = Color(1.0, 0.92, 0.6)


func _on_recharge_started(is_heavy: bool) -> void:
	is_recharging = true
	is_heavy_recharge = is_heavy

func _on_recharge_stopped() -> void:
	is_recharging = false
	is_heavy_recharge = false

func _on_ki_blast_fired(_hand_side: int, _is_charged: bool) -> void:
	pass

func _on_ki_blast_charging(_hand_side: int, _charge_time: float, _delta: float) -> void:
	pass

func _update_combat_stats(delta: float) -> void:
	if player_instance and is_instance_valid(player_instance):
		if is_recharging:
			var recharge_speed = 35.0 if is_heavy_recharge else 12.0
			player_instance.recharge_ki(recharge_speed * delta)
			
			var np_gain = 1800.0 if is_heavy_recharge else 400.0
			player_instance.increase_np(np_gain * delta)
		
		ki_current = player_instance.current_ki
		np_current = player_instance.current_np
		
		var max_ki = player_instance.character_data.base_ki
		var max_np = player_instance.character_data.max_np
		if player_instance.current_transformation:
			max_np *= player_instance.current_transformation.np_multiplier
			
		update_ki(ki_current, max_ki)
		update_power_level(np_current, max_np)


# --- APIs Públicas para Actualización de la Interfaz ---

func update_ki(current: float, max_val: float) -> void:
	var percent = (current / max_val) * 100.0 if max_val > 0 else 0.0
	if ki_text_label:
		ki_text_label.text = "⚡ KI: %d / %d  [%d%%]" % [int(current), int(max_val), int(percent)]
	if ki_progress_bar:
		ki_progress_bar.max_value = max_val
		ki_progress_bar.value = current
		
		# Cambiar color de la barra según estado de recarga
		var fill = ki_progress_bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat:
			if is_recharging:
				fill.bg_color = Color(1.0, 0.85, 0.2, 0.95) # Oro eléctrico al recargar
			else:
				fill.bg_color = Color(0.0, 0.85, 1.0, 0.95) # Cian estándar

func update_power_level(current: float, max_val: float) -> void:
	var percent = (current / max_val) * 100.0 if max_val > 0 else 0.0
	if bp_value_label:
		bp_value_label.text = "BP: %s" % format_number_with_commas(int(current))

	# Actualizar hitos de umbrales irreversibles (25%, 50%, 75%, 100%)
	var thresh_pcts = [25.0, 50.0, 75.0, 100.0]
	for i in range(threshold_labels.size()):
		var lbl = threshold_labels[i]
		var target_pct = thresh_pcts[i]
		if percent >= target_pct:
			lbl.label_settings.font_color = Color(1.0, 0.85, 0.1, 1.0) # Oro iluminado (alcanzado)
		else:
			lbl.label_settings.font_color = Color(0.35, 0.45, 0.45, 0.6) # Apagado

func update_status_text(text: String, color: Color = Color(0.9, 0.9, 0.9)) -> void:
	if action_status_label:
		action_status_label.text = "▶ %s" % text
		action_status_label.label_settings.font_color = color

func format_number_with_commas(n: int) -> String:
	var s = str(n)
	var res = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count == 3 and i > 0:
			res = "," + res
			count = 0
	return res


# --- Consola Debugger Tooltip Superior Flotante (Procedimental) ---
func _setup_debug_tooltip() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	tooltip_viewport = SubViewport.new()
	tooltip_viewport.name = "VRDebugTooltipViewport"
	tooltip_viewport.size = Vector2i(900, 450)
	tooltip_viewport.transparent_bg = true
	tooltip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(tooltip_viewport)
	
	var tooltip_layout = Control.new()
	tooltip_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip_viewport.add_child(tooltip_layout)
	
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.01, 0.03, 0.65)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 1.0, 1.0, 0.2)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	tooltip_layout.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	var debug_title = Label.new()
	debug_title.text = "GSS V3 - LIVE GESTURE DEBUGGER"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 26
	title_settings.font_color = Color(1.0, 0.85, 0.0)
	debug_title.label_settings = title_settings
	vbox.add_child(debug_title)
	
	tooltip_debug_logs = RichTextLabel.new()
	tooltip_debug_logs.bbcode_enabled = true
	tooltip_debug_logs.fit_content = true
	tooltip_debug_logs.custom_minimum_size = Vector2(0, 220)
	tooltip_debug_logs.add_theme_font_size_override("normal_font_size", 20)
	vbox.add_child(tooltip_debug_logs)
	
	tooltip_live_joints = Label.new()
	tooltip_live_joints.text = "L: CONECTANDO...\nR: CONECTANDO..."
	var joints_settings = LabelSettings.new()
	joints_settings.font_size = 18
	joints_settings.font_color = Color(0.65, 0.75, 0.85, 0.85)
	tooltip_live_joints.label_settings = joints_settings
	vbox.add_child(tooltip_live_joints)
	
	tooltip_mesh = MeshInstance3D.new()
	tooltip_mesh.name = "VRDebugTooltipMesh"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.9, 0.45)
	tooltip_mesh.mesh = quad
	
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tooltip_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 101
	tooltip_mesh.material_override = mat
	
	camera.add_child(tooltip_mesh)
	tooltip_mesh.position = Vector3(0.0, 0.38, -1.15)
	tooltip_mesh.rotation = Vector3.ZERO
	tooltip_mesh.visible = false # Oculto por defecto para no saturar la vista
	
	_update_tooltip_logs()


func _on_hand_states_updated(left_desc: String, right_desc: String) -> void:
	if tooltip_live_joints:
		tooltip_live_joints.text = "L: %s\nR: %s" % [left_desc, right_desc]


func log_gesture_event(msg: String, type: String = "info") -> void:
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
	
	var color_hex = "00ccff"
	match type:
		"success": color_hex = "00ff88"
		"info": color_hex = "00ccff"
		"warning": color_hex = "ffcc00"
		"error": color_hex = "ff3344"
		
	var log_line = "[color=#666677][%s][/color] [color=#%s]%s[/color]" % [time_str, color_hex, msg]
	debug_history.append(log_line)
	if debug_history.size() > 6:
		debug_history.pop_front()
	_update_tooltip_logs()


func _update_tooltip_logs() -> void:
	if not tooltip_debug_logs:
		return
	var text_block = ""
	for entry in debug_history:
		text_block += entry + "\n"
	tooltip_debug_logs.text = text_block


# --- Guía de Movimientos y Controles (Abajo a la derecha) ---
func _setup_moves_guide_hud() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	moves_guide_viewport = SubViewport.new()
	moves_guide_viewport.name = "VRMovesGuideViewport"
	moves_guide_viewport.size = Vector2i(900, 950)
	moves_guide_viewport.transparent_bg = true
	moves_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(moves_guide_viewport)

	var layout = Control.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	moves_guide_viewport.add_child(layout)

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.08, 0.88)
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.2, 0.65, 1.0, 0.85)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	layout.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "📜 GUÍA DE MOVIMIENTOS Z"
	var t_set = LabelSettings.new()
	t_set.font_size = 32
	t_set.font_color = Color(1.0, 0.85, 0.2)
	title.label_settings = t_set
	vbox.add_child(title)

	moves_guide_mode_label = Label.new()
	moves_guide_mode_label.text = "MODO: MANDOS QUEST 3"
	var m_set = LabelSettings.new()
	m_set.font_size = 22
	m_set.font_color = Color(0.3, 0.95, 1.0)
	moves_guide_mode_label.label_settings = m_set
	vbox.add_child(moves_guide_mode_label)

	moves_guide_label = RichTextLabel.new()
	moves_guide_label.bbcode_enabled = true
	moves_guide_label.fit_content = true
	moves_guide_label.custom_minimum_size = Vector2(0, 750)
	moves_guide_label.add_theme_font_size_override("normal_font_size", 24)
	vbox.add_child(moves_guide_label)

	moves_guide_mesh = MeshInstance3D.new()
	moves_guide_mesh.name = "VRMovesGuideMesh"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.52, 0.56)
	moves_guide_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = moves_guide_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 100
	moves_guide_mesh.material_override = mat

	camera.add_child(moves_guide_mesh)
	moves_guide_mesh.position = Vector3(0.50, -0.15, -1.05)
	moves_guide_mesh.rotation = Vector3(deg_to_rad(10), deg_to_rad(-14), 0)
	moves_guide_mesh.visible = false # Oculto en combate para vista limpia e inmersiva

	_update_moves_guide_text(current_controller_mode)


func _on_controller_mode_changed(is_controller: bool) -> void:
	current_controller_mode = is_controller
	if moves_guide_mesh and is_instance_valid(moves_guide_mesh):
		moves_guide_mesh.visible = false
	_update_moves_guide_text(is_controller)


func _update_moves_guide_text(is_controller: bool) -> void:
	current_controller_mode = is_controller
	if not moves_guide_label:
		return

	var char_name = "Vegeta"
	if player_instance and is_instance_valid(player_instance) and player_instance.character_data:
		char_name = player_instance.character_data.character_name
	var is_vegeta = "VEGETA" in char_name.to_upper()

	if moves_guide_mode_label:
		var mode_str = "MANDOS QUEST 3 (HÍBRIDO)" if is_controller else "HAND TRACKING PURO"
		moves_guide_mode_label.text = "GUÍA: %s | %s" % [char_name.to_upper(), mode_str]

	var text = ""
	if is_controller:
		if is_vegeta:
			text += "[color=#ffe066][b]TÉCNICAS DE VEGETA (MANDOS QUEST):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast:[/color] Gatillo con brazo extendido (Disparo veloz)\n"
			text += "• [color=#00e5ff]Ki Blast Cargado:[/color] Mantener Gatillo (Fase 1 Carga) -> Soltar Gatillo (Fase 2 Fuego)\n"
			text += "• [color=#00e5ff]Galick Ho (2 Fases):[/color] Grips al hombro (Carga) -> Brazos al frente y Soltar Grips (Fuego)\n"
			text += "• [color=#00e5ff]Big Bang Attack (2 Fases):[/color] 1 Brazo al frente con Grip (Carga) -> Soltar Grip (Fuego)\n"
			text += "• [color=#00e5ff]Final Flash (2 Fases):[/color] Brazos en cruz (T-Pose Grips) -> Manos juntas al frente y Soltar Grips (Fuego)\n"
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Gatillos a hombros y descender a cintura\n"
			text += "• [color=#00e5ff]Guardia (-75% daño):[/color] Ambos Grips juntos al pecho/rostro\n"
			text += "• [color=#00e5ff]Desvío de Ki:[/color] Manotazo veloz contra proyectil entrante\n"
			text += "• [color=#00e5ff]Melee Dash (Bullet-Time):[/color] Puñetazo veloz (Grip + Gatillo) -> Golpea las 6 cajas\n"
			text += "• [color=#ffcc00]Finisher Martillazo DBZ:[/color] En Bullet-Time, junta ambos puños y golpea (Eyección aérea masiva)\n"
			text += "• [color=#00e5ff]Combate Fuera de Ring:[/color] Libre en llanuras exteriores de Cell Games (85m)\n"
			text += "• [color=#00e5ff]Movimiento por Pasos (Ajedrez):[/color] Stick Derecho (Adelante, Atrás, Izq, Der)\n"
			text += "• [color=#00e5ff]Subir / Bajar en el Aire:[/color] Click Stick Der = Subir | Click Stick Izq = Bajar\n"
			text += "• [color=#00e5ff]Transformar (SSJ):[/color] Botón A (Der) o X (Izq) | Gesto puños a cintura\n"
			text += "• [color=#00e5ff]Revertir a Base:[/color] Botón B (Der) o Y (Izq)\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
			text += "• [color=#aaaaaa]Ocultar/Ver Guía:[/color] Click Joystick / Botón Menú\n"
		else:
			text += "[color=#ffe066][b]TÉCNICAS DE GOKU (MANDOS QUEST):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast:[/color] Gatillo con brazo extendido (Disparo veloz)\n"
			text += "• [color=#00e5ff]Ki Blast Cargado:[/color] Mantener Gatillo (Fase 1 Carga) -> Soltar Gatillo (Fase 2 Fuego)\n"
			text += "• [color=#00e5ff]Kamehameha (2 Fases):[/color] Grips en la cadera (Carga) -> Brazos al frente y Soltar Grips (Fuego)\n"
			text += "• [color=#00e5ff]Genkidama (2 Fases):[/color] Brazos al cielo con Grips (Carga) -> Bajar al frente y Soltar Grips (Fuego)\n"
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Gatillos a hombros y descender a cintura\n"
			text += "• [color=#00e5ff]Guardia (-75% daño):[/color] Ambos Grips juntos al pecho/rostro\n"
			text += "• [color=#00e5ff]Desvío de Ki:[/color] Manotazo veloz contra proyectil entrante\n"
			text += "• [color=#00e5ff]Melee Dash (Bullet-Time):[/color] Puñetazo veloz (Grip + Gatillo) -> Golpea las 6 cajas\n"
			text += "• [color=#ffcc00]Finisher Martillazo DBZ:[/color] En Bullet-Time, junta ambos puños y golpea (Eyección aérea masiva)\n"
			text += "• [color=#00e5ff]Combate Fuera de Ring:[/color] Libre en llanuras exteriores de Cell Games (85m)\n"
			text += "• [color=#00e5ff]Movimiento por Pasos (Ajedrez):[/color] Stick Derecho (Adelante, Atrás, Izq, Der)\n"
			text += "• [color=#00e5ff]Subir / Bajar en el Aire:[/color] Click Stick Der = Subir | Click Stick Izq = Bajar\n"
			text += "• [color=#00e5ff]Transformar (SSJ):[/color] Botón A (Der) o X (Izq) | Gesto puños a cintura\n"
			text += "• [color=#00e5ff]Revertir a Base:[/color] Botón B (Der) o Y (Izq)\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
			text += "• [color=#aaaaaa]Ocultar/Ver Guía:[/color] Click Joystick / Botón Menú\n"
	else:
		if is_vegeta:
			text += "[color=#ffe066][b]GESTOS BIOMÉTRICOS DE VEGETA (HAND TRACKING):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast:[/color] Brazo extendido al frente con palma abierta\n"
			text += "• [color=#00e5ff]Ki Blast Cargado:[/color] Mantener brazo extendido al frente (crece esfera en palma)\n"
			text += "• [color=#00e5ff]Galick Ho (2 Fases):[/color] Manos juntas al hombro (Carga) -> Empuje con palmas al frente\n"
			text += "• [color=#00e5ff]Big Bang Attack (2 Fases):[/color] Un brazo extendido palma abierta (Carga) -> Empuje frontal\n"
			text += "• [color=#00e5ff]Final Flash (2 Fases):[/color] Brazos en cruz abiertos (Carga) -> Juntar palmas al frente\n"
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Puños cruzados al pecho -> Puños a la cadera\n"
			text += "• [color=#00e5ff]Guardia:[/color] Ambos puños protegiendo el pecho/rostro\n"
			text += "• [color=#00e5ff]Desvío de Ki:[/color] Manotazo veloz contra proyectil\n"
			text += "• [color=#00e5ff]Golpe Melee:[/color] Puño al mentón -> Puñetazo al frente\n"
			text += "• [color=#00e5ff]Transformar:[/color] Manos a la cadera con Ki 100% y extender dedos\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
		else:
			text += "[color=#ffe066][b]GESTOS BIOMÉTRICOS DE GOKU (HAND TRACKING):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast:[/color] Brazo extendido al frente con palma abierta\n"
			text += "• [color=#00e5ff]Ki Blast Cargado:[/color] Mantener brazo extendido al frente (crece esfera en palma)\n"
			text += "• [color=#00e5ff]Kamehameha (2 Fases):[/color] Manos juntas en cadera (Carga) -> Empujar al frente\n"
			text += "• [color=#00e5ff]Genkidama (2 Fases):[/color] Brazos elevados al cielo (Carga) -> Bajar al frente\n"
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Puños cruzados al pecho -> Puños a la cadera\n"
			text += "• [color=#00e5ff]Guardia:[/color] Ambos puños cruzados frente al pecho\n"
			text += "• [color=#00e5ff]Desvío de Ki:[/color] Manotazo veloz contra el proyectil\n"
			text += "• [color=#00e5ff]Golpe Melee:[/color] Puños al rostro -> Lanzar puñetazo al frente\n"
			text += "• [color=#00e5ff]Transformar:[/color] Manos a la cadera con Ki 100% y extender dedos\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
	moves_guide_label.text = text


func toggle_moves_guide() -> void:
	if moves_guide_mesh and is_instance_valid(moves_guide_mesh):
		moves_guide_mesh.visible = not moves_guide_mesh.visible
