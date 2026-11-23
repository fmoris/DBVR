@tool
extends Node3D

# --- Parámetros de Posicionamiento Fijo (Simulador/Fallback) ---
@export var distance_from_camera: float = 1.55
@export var horizontal_offset: float = 0.0
@export var vertical_offset: float = -0.34
@export var tilt_angle_degrees: float = 14.0
@export var enable_debug_tooltip: bool = false

@onready var sub_viewport: SubViewport = $SubViewport
@onready var hud_mesh: MeshInstance3D = $HUDMesh

# --- Elementos de la Interfaz Canónica de Dragon Ball (Micro-HUD Scouter) ---
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
var status_pill_panel: PanelContainer = null
var status_pill_label: Label = null
var status_pill_style: StyleBoxFlat = null
var dramatic_bonus_panel: PanelContainer = null
var dramatic_bonus_label: Label = null
var super_cooldowns_label: Label = null
var transform_hint_label: Label = null
var _scouter_panel_style: StyleBoxFlat = null

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
var _pulse_redraw_accum: float = 0.0
var _status_override_timer: float = 0.0
var _status_override_text: String = ""
var _status_override_color: Color = Color(1.0, 0.92, 0.45)
var _was_low_ki: bool = false
var _vignette_mesh: MeshInstance3D = null
var _vignette_mat: ShaderMaterial = null
var _hit_vignette_timer: float = 0.0
var _vignette_pulse_t: float = 0.0
var _last_np_for_vignette: float = -1.0
var _last_approach_pct: int = -1
const VRVignetteShader = preload("res://shaders/vr_vignette.gdshader")

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

# Cachés de nodos/posiciones para Zero Allocations en hot paths (90 FPS VR)
var _cached_xr_origin: XROrigin3D = null
var _cached_left_ctrl: XRController3D = null
var _cached_camera: Camera3D = null
var _wrist_pos_cache: Vector3 = Vector3.ZERO
var _palm_pos_cache: Vector3 = Vector3.ZERO

# Caché dirty-flag para eliminar asignaciones de texto y redraws redundantes del SubViewport (90 FPS VR)
var _hud_dirty: bool = true
var _last_ki_int: int = -1
var _last_max_ki_int: int = -1
var _last_np_int: int = -1
var _last_np_pct_tier: int = -1
var _last_bp_mult: float = -1.0
var _last_recharging: bool = false
var _last_enemy_np_int: int = -1
var _last_player_np_comp: int = -1
var _last_enemy_mult: float = -1.0
var _last_guard_state: int = -1
var _last_zenkai_state: bool = false
var _last_zenkai_comeback: bool = false
var _last_furia_state: bool = false
var _last_buff_text: String = ""
var _last_dramatic_hud_text: String = ""
var _last_cooldowns_hud_text: String = ""
var _cd_hud_timer: float = 0.0
var _last_transform_hint_text: String = ""
var _last_status_override_active: bool = false

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

	# Redimensionar la malla del HUD a formato Micro-HUD Scouter compacto (con cooldowns y guía de transformación)
	if sub_viewport:
		sub_viewport.size = Vector2i(720, 480)
	if hud_mesh.mesh is QuadMesh:
		hud_mesh.mesh.size = Vector2(0.15, 0.092)

	# Construir la interfaz Dragon Ball Sci-Fi / Scouter procedimentalmente
	_build_dragon_ball_hud()

	if not Engine.is_editor_hint():
		call_deferred("_setup_wrist_hud")
		if enable_debug_tooltip:
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
	if sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	is_wrist_mode = true
	set_process(true)
	_connect_gesture_signals()
	print("[VRHUD] HUD holográfico montado exitosamente en muñeca/palma izquierda.")


## Actualiza posiciones en caché de muñeca/palma izquierda (Zero Allocations por frame)
func _update_left_wrist_and_palm_cache() -> bool:
	if _cached_xr_origin == null or not is_instance_valid(_cached_xr_origin) or not _cached_xr_origin.is_inside_tree():
		_cached_xr_origin = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D") as XROrigin3D
		if not _cached_xr_origin:
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree and tree.current_scene:
				_cached_xr_origin = tree.current_scene.find_child("Player_XROrigin3D", true, false) as XROrigin3D
				if not _cached_xr_origin:
					_cached_xr_origin = tree.current_scene.find_child("XROrigin3D", true, false) as XROrigin3D
		_cached_left_ctrl = null
	if not _cached_xr_origin:
		return false

	# 1. Prioridad: Controlador izquierdo Quest Touch activo
	if _cached_left_ctrl == null or not is_instance_valid(_cached_left_ctrl) or not _cached_left_ctrl.is_inside_tree():
		_cached_left_ctrl = _cached_xr_origin.get_node_or_null("LeftHand") as XRController3D
		if not _cached_left_ctrl:
			_cached_left_ctrl = _cached_xr_origin.find_child("LeftHand", true, false) as XRController3D

	if _cached_left_ctrl and _cached_left_ctrl.get_is_active():
		var l_basis: Basis = _cached_left_ctrl.global_transform.basis
		var l_pos: Vector3 = _cached_left_ctrl.global_position
		_wrist_pos_cache = l_pos + l_basis * Vector3(0.0, 0.05, 0.04)
		_palm_pos_cache = l_pos + l_basis * Vector3(0.0, 0.08, 0.0)
		return true

	# 2. Fallback: OpenXR Hand Tracking nativo si el mando físico no está activo
	var left_tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if left_tracker:
		var flags_wrist: int = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST)
		var flags_palm: int = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		var has_w: bool = (flags_wrist & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0
		var has_p: bool = (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0
		if has_w or has_p:
			var w_local: Vector3 = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin if has_w else left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			var p_local: Vector3 = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin if has_p else w_local
			var orig_xf: Transform3D = _cached_xr_origin.global_transform
			_wrist_pos_cache = orig_xf * w_local
			_palm_pos_cache = orig_xf * p_local
			return true

	# 3. Fallback final si existe nodo LeftHand pero aún sin tracking activo
	if _cached_left_ctrl:
		var fallback_pos: Vector3 = _cached_left_ctrl.global_position
		_wrist_pos_cache = fallback_pos + Vector3.UP * 0.05
		_palm_pos_cache = fallback_pos + Vector3.UP * 0.08
		return true

	return false


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
# CONSTRUCCIÓN DEL MICRO-HUD MINIMALISTA DRAGON BALL (3 BLOQUES)
# -----------------------------------------------------------------
func _build_dragon_ball_hud() -> void:
	var hud_layout = sub_viewport.get_node_or_null("HUDLayout")
	if not hud_layout:
		return

	# Limpiar elementos anteriores
	for child in hud_layout.get_children():
		child.queue_free()

	bp_title_label = null
	ki_cost_label = null
	guard_badge_label = null
	zenkai_badge_label = null
	action_status_label = null

	# 1. Panel Principal de Cristal Scouter Compacto (720x326)
	scouter_panel = Panel.new()
	scouter_panel.name = "ScouterGlassPanel"
	scouter_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	scouter_panel.offset_left = 10
	scouter_panel.offset_top = 10
	scouter_panel.offset_right = -10
	scouter_panel.offset_bottom = -10

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.045, 0.045, 0.84)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.0, 0.92, 0.68, 0.90)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.set_content_margin_all(18)
	_scouter_panel_style = panel_style
	scouter_panel.add_theme_stylebox_override("panel", panel_style)
	hud_layout.add_child(scouter_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 10)
	scouter_panel.add_child(main_vbox)

	# BLOQUE 1: Cabecera compacta -> Jugador/Forma + BP compacto + Diff rival
	var header_hbox := HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	header_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header_hbox)

	player_badge_label = Label.new()
	player_badge_label.text = "VEGETA · BASE"
	var p_settings := LabelSettings.new()
	p_settings.font_size = 28
	p_settings.font_color = Color(0.0, 0.92, 1.0)
	p_settings.shadow_size = 4
	p_settings.shadow_color = Color(0, 0, 0, 0.95)
	player_badge_label.label_settings = p_settings
	player_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(player_badge_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	bp_value_label = Label.new()
	bp_value_label.text = "BP 10.0K"
	var bp_v_settings := LabelSettings.new()
	bp_v_settings.font_size = 44
	bp_v_settings.font_color = Color(0.18, 1.0, 0.48)
	bp_v_settings.shadow_size = 6
	bp_v_settings.shadow_color = Color(0, 0, 0, 0.98)
	bp_value_label.label_settings = bp_v_settings
	bp_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(bp_value_label)

	rival_scouter_label = Label.new()
	rival_scouter_label.text = "+1.0K"
	var r_settings := LabelSettings.new()
	r_settings.font_size = 28
	r_settings.font_color = Color(0.25, 1.0, 0.45)
	r_settings.shadow_size = 4
	r_settings.shadow_color = Color(0, 0, 0, 0.95)
	rival_scouter_label.label_settings = r_settings
	rival_scouter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(rival_scouter_label)

	# BLOQUE 2: Barra de Ki limpia con marcas de corte táctica (15% Z-Vanish / 30% Super)
	var ki_overlay := Control.new()
	ki_overlay.custom_minimum_size = Vector2(0, 64)
	main_vbox.add_child(ki_overlay)

	ki_progress_bar = ProgressBar.new()
	ki_progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	ki_progress_bar.max_value = 100.0
	ki_progress_bar.value = 50.0
	ki_progress_bar.show_percentage = false

	var bg_bar := StyleBoxFlat.new()
	bg_bar.bg_color = Color(0.02, 0.05, 0.08, 0.90)
	bg_bar.border_width_left = 2
	bg_bar.border_width_top = 2
	bg_bar.border_width_right = 2
	bg_bar.border_width_bottom = 2
	bg_bar.border_color = Color(0.12, 0.45, 0.55, 0.85)
	bg_bar.corner_radius_top_left = 10
	bg_bar.corner_radius_top_right = 10
	bg_bar.corner_radius_bottom_left = 10
	bg_bar.corner_radius_bottom_right = 10
	ki_progress_bar.add_theme_stylebox_override("background", bg_bar)

	var fill_bar := StyleBoxFlat.new()
	fill_bar.bg_color = Color(0.0, 0.86, 1.0, 0.95)
	fill_bar.corner_radius_top_left = 10
	fill_bar.corner_radius_top_right = 10
	fill_bar.corner_radius_bottom_left = 10
	fill_bar.corner_radius_bottom_right = 10
	ki_progress_bar.add_theme_stylebox_override("fill", fill_bar)
	ki_overlay.add_child(ki_progress_bar)

	# Marca de corte 15 Ki (Z-Vanish)
	var tick_vanish := ColorRect.new()
	tick_vanish.anchor_left = 0.15
	tick_vanish.anchor_right = 0.15
	tick_vanish.anchor_top = 0.0
	tick_vanish.anchor_bottom = 1.0
	tick_vanish.offset_left = -2.0
	tick_vanish.offset_right = 2.0
	tick_vanish.offset_top = 4.0
	tick_vanish.offset_bottom = -4.0
	tick_vanish.color = Color(1.0, 0.85, 0.20, 0.92)
	ki_overlay.add_child(tick_vanish)

	# Marca de corte 30 Ki (Super Poder)
	var tick_super := ColorRect.new()
	tick_super.anchor_left = 0.30
	tick_super.anchor_right = 0.30
	tick_super.anchor_top = 0.0
	tick_super.anchor_bottom = 1.0
	tick_super.offset_left = -2.0
	tick_super.offset_right = 2.0
	tick_super.offset_top = 4.0
	tick_super.offset_bottom = -4.0
	tick_super.color = Color(0.90, 0.98, 1.0, 0.88)
	ki_overlay.add_child(tick_super)

	ki_text_label = Label.new()
	ki_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	ki_text_label.text = "KI 50%"
	ki_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ki_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ki_t_settings := LabelSettings.new()
	ki_t_settings.font_size = 30
	ki_t_settings.font_color = Color(1.0, 1.0, 1.0)
	ki_t_settings.outline_size = 4
	ki_t_settings.outline_color = Color(0.0, 0.0, 0.0, 0.92)
	ki_t_settings.shadow_size = 4
	ki_t_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	ki_text_label.label_settings = ki_t_settings
	ki_overlay.add_child(ki_text_label)

	# BLOQUE 3: Fila inferior -> 4 pips de umbral (25/50/75/100%) + 1 solo pill dinámico
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 10)
	bottom_hbox.custom_minimum_size = Vector2(0, 48)
	main_vbox.add_child(bottom_hbox)

	threshold_labels.clear()
	for i in range(4):
		var t_lbl := Label.new()
		t_lbl.text = "○"
		var t_set := LabelSettings.new()
		t_set.font_size = 30
		t_set.font_color = Color(0.45, 0.60, 0.60, 0.55)
		t_lbl.label_settings = t_set
		t_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bottom_hbox.add_child(t_lbl)
		threshold_labels.append(t_lbl)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(bottom_spacer)

	status_pill_panel = PanelContainer.new()
	status_pill_panel.name = "StatusPillPanel"
	status_pill_style = StyleBoxFlat.new()
	status_pill_style.bg_color = Color(0.12, 0.04, 0.04, 0.88)
	status_pill_style.border_width_left = 2
	status_pill_style.border_width_top = 2
	status_pill_style.border_width_right = 2
	status_pill_style.border_width_bottom = 2
	status_pill_style.border_color = Color(1.0, 0.85, 0.2, 0.9)
	status_pill_style.corner_radius_top_left = 12
	status_pill_style.corner_radius_top_right = 12
	status_pill_style.corner_radius_bottom_left = 12
	status_pill_style.corner_radius_bottom_right = 12
	status_pill_style.content_margin_left = 14
	status_pill_style.content_margin_right = 14
	status_pill_style.content_margin_top = 4
	status_pill_style.content_margin_bottom = 4
	status_pill_panel.add_theme_stylebox_override("panel", status_pill_style)
	status_pill_panel.visible = false
	bottom_hbox.add_child(status_pill_panel)

	status_pill_label = Label.new()
	status_pill_label.text = ""
	var pill_set := LabelSettings.new()
	pill_set.font_size = 24
	pill_set.font_color = Color(1.0, 0.90, 0.25)
	pill_set.shadow_size = 3
	pill_set.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	status_pill_label.label_settings = pill_set
	status_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_pill_panel.add_child(status_pill_label)

	# BLOQUE 4: Franja dedicada de Bonos Dramáticos Activos / Permanentes (nunca tapada por Furia/Zenkai/Guardia)
	dramatic_bonus_panel = PanelContainer.new()
	dramatic_bonus_panel.name = "DramaticBonusPanel"
	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.04, 0.09, 0.14, 0.88)
	d_style.border_width_left = 2
	d_style.border_width_top = 2
	d_style.border_width_right = 2
	d_style.border_width_bottom = 2
	d_style.border_color = Color(1.0, 0.85, 0.25, 0.92)
	d_style.corner_radius_top_left = 10
	d_style.corner_radius_top_right = 10
	d_style.corner_radius_bottom_left = 10
	d_style.corner_radius_bottom_right = 10
	d_style.content_margin_left = 12
	d_style.content_margin_right = 12
	d_style.content_margin_top = 4
	d_style.content_margin_bottom = 4
	dramatic_bonus_panel.add_theme_stylebox_override("panel", d_style)
	dramatic_bonus_panel.visible = false
	main_vbox.add_child(dramatic_bonus_panel)

	dramatic_bonus_label = Label.new()
	dramatic_bonus_label.name = "DramaticBonusLabel"
	dramatic_bonus_label.text = ""
	dramatic_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var db_set := LabelSettings.new()
	db_set.font_size = 20
	db_set.font_color = Color(1.0, 0.93, 0.45)
	db_set.shadow_size = 3
	db_set.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	dramatic_bonus_label.label_settings = db_set
	dramatic_bonus_panel.add_child(dramatic_bonus_label)

	# BLOQUE 4.5: Indicador compacto de Cooldowns de Súper Poderes
	super_cooldowns_label = Label.new()
	super_cooldowns_label.name = "SuperCooldownsLabel"
	super_cooldowns_label.text = ""
	var scd_set := LabelSettings.new()
	scd_set.font_size = 19
	scd_set.font_color = Color(0.42, 0.92, 1.0)
	scd_set.shadow_size = 3
	scd_set.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	super_cooldowns_label.label_settings = scd_set
	main_vbox.add_child(super_cooldowns_label)

	# BLOQUE 5: Pista persistente de Transformación (bloqueo / requisito o cómo activarla al instante)
	transform_hint_label = Label.new()
	transform_hint_label.name = "TransformHintLabel"
	transform_hint_label.text = ""
	transform_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var th_set := LabelSettings.new()
	th_set.font_size = 20
	th_set.font_color = Color(0.72, 0.80, 0.92)
	th_set.shadow_size = 3
	th_set.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	transform_hint_label.label_settings = th_set
	main_vbox.add_child(transform_hint_label)


func _connect_gesture_signals() -> void:
	update_ki(ki_current, ki_max)
	update_power_level(np_current, np_max)
	
	var gesture_tree = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
	if not gesture_tree:
		gesture_tree = get_tree().root.find_child("GesturePhaseTree", true, false)
		
	if gesture_tree:
		gesture_tree_ref = gesture_tree
		if gesture_tree.has_signal("ki_recharge_started"):
			if gesture_tree.ki_recharge_started.is_connected(_on_recharge_started):
				gesture_tree.ki_recharge_started.disconnect(_on_recharge_started)
			gesture_tree.ki_recharge_started.connect(_on_recharge_started)

		if gesture_tree.has_signal("ki_recharge_stopped"):
			if gesture_tree.ki_recharge_stopped.is_connected(_on_recharge_stopped):
				gesture_tree.ki_recharge_stopped.disconnect(_on_recharge_stopped)
			gesture_tree.ki_recharge_stopped.connect(_on_recharge_stopped)

		if gesture_tree.has_signal("ki_blast_fired"):
			if gesture_tree.ki_blast_fired.is_connected(_on_ki_blast_fired):
				gesture_tree.ki_blast_fired.disconnect(_on_ki_blast_fired)
			gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)

		if gesture_tree.has_signal("ki_blast_charging"):
			if gesture_tree.ki_blast_charging.is_connected(_on_ki_blast_charging):
				gesture_tree.ki_blast_charging.disconnect(_on_ki_blast_charging)
			gesture_tree.ki_blast_charging.connect(_on_ki_blast_charging)

		if gesture_tree.has_signal("gesture_logged"):
			if gesture_tree.gesture_logged.is_connected(log_gesture_event):
				gesture_tree.gesture_logged.disconnect(log_gesture_event)
			gesture_tree.gesture_logged.connect(log_gesture_event)

		if gesture_tree.has_signal("hand_states_updated"):
			if gesture_tree.hand_states_updated.is_connected(_on_hand_states_updated):
				gesture_tree.hand_states_updated.disconnect(_on_hand_states_updated)
			gesture_tree.hand_states_updated.connect(_on_hand_states_updated)

		if gesture_tree.has_signal("phase_changed"):
			if gesture_tree.phase_changed.is_connected(_on_phase_changed):
				gesture_tree.phase_changed.disconnect(_on_phase_changed)
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

	# Resolver cámara activa en caché sin búsquedas repetidas
	if _cached_camera == null or not is_instance_valid(_cached_camera) or not _cached_camera.is_inside_tree():
		_cached_camera = get_viewport().get_camera_3d()

	# Control Diegético del Micro-HUD en la Muñeca / Palma (KI, BP y Scouter Status)
	if is_wrist_mode and is_instance_valid(hud_mesh):
		var should_display: bool = false

		if _update_left_wrist_and_palm_cache() and _cached_camera and is_instance_valid(_cached_camera):
			var cam_pos: Vector3 = _cached_camera.global_position
			var display_anchor: Vector3 = (_wrist_pos_cache + _palm_pos_cache) * 0.5

			# Distancia euclídea del visor a la mano izquierda
			var dist: float = display_anchor.distance_to(cam_pos)

			# Vector hacia donde apunta la mirada del jugador
			var cam_forward: Vector3 = -_cached_camera.global_transform.basis.z.normalized()
			var dir_from_cam: Vector3 = (display_anchor - cam_pos).normalized()
			var in_view: float = cam_forward.dot(dir_from_cam)

			# Activación natural al mirar la mano/muñeca izquierda (8cm a 1.15m)
			if in_view > 0.15 and dist >= 0.08 and dist <= 1.15 and display_anchor.y > (cam_pos.y - 1.15):
				should_display = true

			if should_display or wrist_hud_scale > 0.01:
				var float_offset: Vector3 = Vector3.UP * 0.09 + (cam_pos - display_anchor).normalized() * 0.05
				hud_mesh.global_position = display_anchor + float_offset
				hud_mesh.look_at(cam_pos, Vector3.UP, true)

		var target_scale: float = 1.0 if should_display else 0.0
		wrist_hud_scale = move_toward(wrist_hud_scale, target_scale, delta * 6.5)
		hud_mesh.scale = Vector3.ONE * wrist_hud_scale
		hud_mesh.visible = (wrist_hud_scale > 0.02)
		if sub_viewport and is_instance_valid(sub_viewport):
			if not hud_mesh.visible:
				sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			elif _hud_dirty:
				sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				_hud_dirty = false

	# Búsqueda dinámica única de la instancia del jugador
	if player_instance == null or not is_instance_valid(player_instance):
		var player = get_node_or_null("/root/cell_games_arena/Player_XROrigin3D/PlayerCharacterInstance")
		if player:
			player_instance = player
			player_instance.stats_changed.connect(_on_player_stats_changed)
			if player_instance.has_signal("transformation_unlocked"):
				player_instance.transformation_unlocked.connect(_on_transformation_unlocked)
			if player_instance.has_signal("furia_changed"):
				player_instance.furia_changed.connect(_on_player_furia_changed)
			if player_instance.has_signal("dramatic_buffs_changed"):
				player_instance.dramatic_buffs_changed.connect(_on_player_dramatic_buffs_changed)
			_on_player_stats_changed(player_instance.current_ki, player_instance.current_np, player_instance.is_in_zenkai_state)
			_update_moves_guide_text(current_controller_mode)
			_refresh_ki_cost_label()
			print("[VRHUD] Enlazado exitosamente al CharacterInstance del jugador.")

	# Búsqueda dinámica única del contrincante (Rival Scouter)
	if enemy_instance == null or not is_instance_valid(enemy_instance):
		var enemy = get_node_or_null("/root/cell_games_arena/EnemyCharacterInstance")
		if enemy:
			enemy_instance = enemy

	_update_combat_stats(delta)
	_update_dbz_hud_elements(delta)
	_update_vignette_overlay(delta)


func _ensure_vignette_overlay() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	if _vignette_mesh and is_instance_valid(_vignette_mesh):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam or not is_instance_valid(cam):
		return
	_vignette_mesh = MeshInstance3D.new()
	_vignette_mesh.name = "VRVignetteOverlay"
	var q := QuadMesh.new()
	q.size = Vector2(1.55, 1.15)
	_vignette_mesh.mesh = q
	_vignette_mesh.position = Vector3(0.0, 0.0, -0.35)
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = VRVignetteShader
	_vignette_mat.set_shader_parameter("intensity", 0.0)
	_vignette_mesh.material_override = _vignette_mat
	_vignette_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(_vignette_mesh)


func trigger_hit_vignette(duration_sec: float = 0.28) -> void:
	_hit_vignette_timer = maxf(_hit_vignette_timer, duration_sec)


func _update_vignette_overlay(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_vignette_overlay()
	if not _vignette_mat:
		return

	if _hit_vignette_timer > 0.0:
		_hit_vignette_timer = maxf(_hit_vignette_timer - delta, 0.0)

	var target_col := Color(0.0, 0.0, 0.0, 1.0)
	var target_intensity: float = 0.0
	var target_inner: float = 0.46

	if player_instance and is_instance_valid(player_instance):
		var cur_np_val: float = float(player_instance.current_np)
		if _last_np_for_vignette >= 0.0 and (_last_np_for_vignette - cur_np_val) >= 50.0:
			_hit_vignette_timer = 0.28
		_last_np_for_vignette = cur_np_val

		var e_np_val: float = float(enemy_instance.current_np) if (enemy_instance and is_instance_valid(enemy_instance)) else cur_np_val
		var cur_ki_val: float = float(player_instance.current_ki)
		var in_furia: bool = bool(player_instance.get("is_in_furia"))
		var in_zenkai: bool = bool(player_instance.get("is_in_zenkai_state"))
		var form_idx: int = int(player_instance.get("current_transformation_index")) if player_instance.get("current_transformation_index") != null else -1

		_vignette_pulse_t += delta * 5.0
		var pulse_01: float = (sin(_vignette_pulse_t) + 1.0) * 0.5

		if _hit_vignette_timer > 0.0:
			target_col = Color(1.0, 0.10, 0.08, 1.0)
			target_intensity = 0.92 * clampf(_hit_vignette_timer / 0.32, 0.35, 1.0)
			target_inner = 0.22
		elif in_furia or (e_np_val > 100.0 and cur_np_val < e_np_val * 0.70):
			target_col = Color(0.92, 0.06, 0.06, 1.0)
			target_intensity = 0.60 + pulse_01 * 0.28
			target_inner = 0.24 - pulse_01 * 0.04
		elif cur_ki_val < 15.0:
			target_col = Color(0.20, 0.35, 0.98, 1.0)
			target_intensity = 0.52 + pulse_01 * 0.24
			target_inner = 0.28
		elif in_zenkai or (e_np_val > 100.0 and cur_np_val > e_np_val * 1.35):
			target_col = Color(1.0, 0.85, 0.18, 1.0)
			target_intensity = 0.48 + pulse_01 * 0.22
			target_inner = 0.30
		elif form_idx >= 0:
			target_col = Color(1.0, 0.78, 0.15, 1.0)
			target_intensity = 0.38
			target_inner = 0.32

	_vignette_mat.set_shader_parameter("vignette_color", target_col)
	_vignette_mat.set_shader_parameter("intensity", target_intensity)
	_vignette_mat.set_shader_parameter("inner_radius", target_inner)


func _apply_pill_appearance(text_val: String, col: Color, border_col: Color) -> void:
	if not status_pill_panel or not status_pill_label:
		return
	if text_val == "":
		if status_pill_panel.visible:
			status_pill_panel.visible = false
			_hud_dirty = true
		return
	if not status_pill_panel.visible:
		status_pill_panel.visible = true
		_hud_dirty = true
	if status_pill_label.text != text_val:
		status_pill_label.text = text_val
		_hud_dirty = true
	if status_pill_label.label_settings and status_pill_label.label_settings.font_color != col:
		status_pill_label.label_settings.font_color = col
		_hud_dirty = true
	if status_pill_style and status_pill_style.border_color != border_col:
		status_pill_style.border_color = border_col
		_hud_dirty = true


func _update_dbz_hud_elements(delta: float) -> void:
	# 1. Actualizar diferencia compacta del Rival en el Scouter (dirty check)
	if enemy_instance and is_instance_valid(enemy_instance) and rival_scouter_label:
		var e_np: int = int(enemy_instance.current_np)
		var p_np_comp: int = int(player_instance.current_np) if (player_instance and is_instance_valid(player_instance)) else e_np
		var e_mult: float = enemy_instance.get_transformation_multiplier() if enemy_instance.has_method("get_transformation_multiplier") else 1.0
		if e_np != _last_enemy_np_int or p_np_comp != _last_player_np_comp or absf(e_mult - _last_enemy_mult) > 0.05:
			_last_enemy_np_int = e_np
			_last_player_np_comp = p_np_comp
			_last_enemy_mult = e_mult
			var diff_bp: int = p_np_comp - e_np
			var sign_d: String = "+" if diff_bp >= 0 else ""
			rival_scouter_label.text = "%s%s" % [sign_d, _format_compact_bp(diff_bp)]
			if rival_scouter_label.label_settings:
				rival_scouter_label.label_settings.font_color = Color(0.25, 1.0, 0.45) if diff_bp >= 0 else Color(1.0, 0.35, 0.35)
			_hud_dirty = true

	# 2. Expiración del pill transitorio de acción
	if _status_override_timer > 0.0:
		_status_override_timer = maxf(_status_override_timer - delta, 0.0)
		if _status_override_timer <= 0.0:
			_status_override_text = ""

	# 3. Actualizar único pill dinámico prioritario (Guardia Rota > Zenkai > Furia > Guardia > Buff Dramático > Acción transitoria)
	if player_instance and is_instance_valid(player_instance):
		var g_state: int = 2 if player_instance.get("is_guard_broken") else (1 if player_instance.get("is_blocking") else 0)
		var z_active: bool = bool(player_instance.get("is_in_zenkai_state"))
		var z_comeback: bool = bool(player_instance.get("is_comeback_zenkai")) or String(player_instance.get("zenkai_source")) == "comeback"
		var f_active: bool = bool(player_instance.get("is_in_furia"))
		var buff_text: String = player_instance.get_active_buff_summary() if player_instance.has_method("get_active_buff_summary") else ""
		var has_override: bool = _status_override_timer > 0.0 and _status_override_text != ""
		var app_val: Variant = player_instance.get("melee_approach_progress")
		var app_pct: int = int(roundf(clampf(float(app_val) if app_val != null else 0.0, 0.0, 1.0) * 100.0))
		var show_approach: bool = app_pct >= 5

		var state_changed: bool = (
			g_state != _last_guard_state
			or z_active != _last_zenkai_state
			or z_comeback != _last_zenkai_comeback
			or f_active != _last_furia_state
			or buff_text != _last_buff_text
			or has_override != _last_status_override_active
			or (show_approach and app_pct != _last_approach_pct)
			or (not show_approach and _last_approach_pct >= 5)
		)
		_last_guard_state = g_state
		_last_zenkai_state = z_active
		_last_zenkai_comeback = z_comeback
		_last_furia_state = f_active
		_last_buff_text = buff_text
		_last_status_override_active = has_override
		_last_approach_pct = app_pct if show_approach else -1

		if g_state == 2:
			_apply_pill_appearance("⚠ GUARDIA ROTA", Color(1.0, 0.25, 0.25), Color(1.0, 0.22, 0.22, 0.95))
		elif z_active:
			var z_pill_txt: String = "⚡ ZENKAI COMEBACK" if z_comeback else "🔥 ZENKAI DOMINIO"
			var col_z := Color(1.0, 0.65, 0.15) if z_comeback else Color(1.0, 0.45, 0.15)
			if hud_mesh and hud_mesh.visible:
				_pulse_redraw_accum += delta
				if _pulse_redraw_accum >= 0.08 or state_changed:
					zenkai_pulse_timer += _pulse_redraw_accum * 7.5
					_pulse_redraw_accum = 0.0
					var pulse_z: float = (sin(zenkai_pulse_timer) + 1.0) * 0.5
					col_z = Color(1.0, 0.35 + pulse_z * 0.60, 0.12)
					_apply_pill_appearance(z_pill_txt, col_z, col_z)
			elif state_changed:
				_apply_pill_appearance(z_pill_txt, col_z, col_z)
		elif f_active:
			var col_f := Color(1.0, 0.55, 0.15)
			if hud_mesh and hud_mesh.visible:
				_pulse_redraw_accum += delta
				if _pulse_redraw_accum >= 0.08 or state_changed:
					zenkai_pulse_timer += _pulse_redraw_accum * 6.5
					_pulse_redraw_accum = 0.0
					var pulse_f: float = (sin(zenkai_pulse_timer) + 1.0) * 0.5
					col_f = Color(1.0, 0.35 + pulse_f * 0.45, 0.10)
					_apply_pill_appearance("⚡ FURIA x2", col_f, col_f)
			elif state_changed:
				_apply_pill_appearance("⚡ FURIA x2", col_f, col_f)
		elif g_state == 1:
			_apply_pill_appearance("🛡 GUARDIA", Color(1.0, 0.92, 0.25), Color(1.0, 0.88, 0.20, 0.90))
		elif buff_text != "":
			var buff_col: Color = player_instance.get_active_buff_color() if player_instance.has_method("get_active_buff_color") else Color(0.2, 0.9, 1.0)
			_apply_pill_appearance("★ " + buff_text, buff_col, buff_col)
		elif has_override:
			_apply_pill_appearance(_status_override_text, _status_override_color, _status_override_color)
		elif show_approach:
			_apply_pill_appearance("⚔️ ACERCAMIENTO MELEE: %d%%" % app_pct, Color(1.0, 0.72, 0.22), Color(1.0, 0.65, 0.15, 0.92))
		elif state_changed:
			_apply_pill_appearance("", Color.WHITE, Color.WHITE)

		# 4. Franja dedicada de Bonos Dramáticos concretos (siempre visible al ganar un bono)
		var dram_text: String = player_instance.get_dramatic_hud_text() if player_instance.has_method("get_dramatic_hud_text") else ""
		if dram_text != _last_dramatic_hud_text:
			_last_dramatic_hud_text = dram_text
			if dramatic_bonus_panel and dramatic_bonus_label:
				dramatic_bonus_panel.visible = (dram_text != "")
				dramatic_bonus_label.text = dram_text
			_hud_dirty = true

		# Borde dorado pulsante del panel completo al activar Zenkai
		if _scouter_panel_style:
			var target_border := Color(1.0, 0.85, 0.15, 0.96) if z_active else Color(0.0, 0.92, 0.68, 0.90)
			if z_active and hud_mesh and hud_mesh.visible:
				var p_z: float = (sin(zenkai_pulse_timer) + 1.0) * 0.5
				target_border = Color(1.0, 0.65 + p_z * 0.30, 0.10, 0.98)
			if _scouter_panel_style.border_color != target_border:
				_scouter_panel_style.border_color = target_border
				_hud_dirty = true

		# 4.5 Indicador compacto de Cooldowns de Súper Poderes (actualizado cada 0.20s)
		_cd_hud_timer += delta
		if super_cooldowns_label and player_instance.has_method("get_super_cooldowns_hud_text") and (_cd_hud_timer >= 0.20 or _last_cooldowns_hud_text == ""):
			_cd_hud_timer = 0.0
			var cd_txt: String = player_instance.get_super_cooldowns_hud_text()
			if cd_txt != _last_cooldowns_hud_text:
				_last_cooldowns_hud_text = cd_txt
				super_cooldowns_label.text = cd_txt
				if super_cooldowns_label.label_settings:
					super_cooldowns_label.label_settings.font_color = Color(1.0, 0.72, 0.22) if ("⏳" in cd_txt or "⌛" in cd_txt) else Color(0.42, 0.92, 1.0)
				_hud_dirty = true

		# 5. Pista persistente de Transformación (desbloqueada / requisito / máxima)
		if transform_hint_label and player_instance.has_method("get_next_transformation_status"):
			var st: Dictionary = player_instance.get_next_transformation_status()
			var hint_str: String = ""
			var hint_col: Color = Color(0.72, 0.80, 0.92)
			if bool(st.get("has_next", false)):
				var f_name: String = String(st.get("form_name", ""))
				if bool(st.get("is_unlocked", false)):
					hint_str = "⚡ [A/X] o Puños Cintura ➔ %s (x%.1f)" % [f_name, float(st.get("multiplier", 1.0))]
					hint_col = Color(1.0, 0.90, 0.25)
				else:
					hint_str = "🔒 %s: %s" % [f_name, String(st.get("requirement_text", ""))]
					hint_col = Color(0.72, 0.80, 0.92)
			else:
				hint_str = "👑 FORMA MÁXIMA ([B/Y] Revertir)"
				hint_col = Color(0.85, 0.92, 1.0)
			if hint_str != _last_transform_hint_text:
				_last_transform_hint_text = hint_str
				transform_hint_label.text = hint_str
				if transform_hint_label.label_settings:
					transform_hint_label.label_settings.font_color = hint_col
				_hud_dirty = true


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

	# Actualizar etiqueta compacta: PERSONAJE · FORMA
	if player_badge_label and player_instance and player_instance.character_data:
		var c_name: String = player_instance.character_data.character_name.to_upper()
		var form: String = "BASE"
		var form_col: Color = Color(0.0, 0.90, 1.0)
		if player_instance.current_transformation:
			form = player_instance.current_transformation.form_name.to_upper()
			form_col = player_instance.current_transformation.aura_color
		var next_badge: String = "%s · %s" % [c_name, form]
		if player_badge_label.text != next_badge:
			player_badge_label.text = next_badge
			_hud_dirty = true
		if player_badge_label.label_settings and player_badge_label.label_settings.font_color != form_col:
			player_badge_label.label_settings.font_color = form_col
			_hud_dirty = true


func _on_player_furia_changed(active: bool) -> void:
	if active:
		update_status_text("⚡ ¡FURIA DESATADA!", Color(1.0, 0.45, 0.12))


func _on_player_dramatic_buffs_changed() -> void:
	_hud_dirty = true


func _on_transformation_unlocked(form_name: String) -> void:
	update_status_text("⚡ DESPERTAR: %s" % form_name.to_upper(), Color(1.0, 0.9, 0.15))


func _on_phase_changed(new_phase_name: String) -> void:
	var upper_p: String = new_phase_name.to_upper()
	if "IDLE" in upper_p or "NEUTRAL" in upper_p:
		_status_override_timer = 0.0
		_status_override_text = ""
		return
	var col := Color(1.0, 0.92, 0.55)
	if "KAMEHAMEHA" in upper_p or "GALICK" in upper_p or "FINAL" in upper_p or "BIG BANG" in upper_p:
		col = Color(0.25, 0.85, 1.0)
	elif "RECARGA" in upper_p:
		col = Color(1.0, 0.85, 0.2)
	elif "MELEE" in upper_p:
		col = Color(1.0, 0.4, 0.3)
	update_status_text(upper_p, col)


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

func _update_combat_stats(_delta: float) -> void:
	if player_instance and is_instance_valid(player_instance):
		# La recarga de Ki y BP ahora vive exclusivamente en HybridCombatController / GesturePhaseTree
		# para evitar doble ganancia y respetar el techo de carga del 60% (Punto 8 y 9).
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
	var cur_int: int = int(current)
	var max_int: int = int(max_val)
	if cur_int == _last_ki_int and max_int == _last_max_ki_int and is_recharging == _last_recharging:
		return

	# Alerta háptica periférica sutil cuando el Ki cae por debajo de 15 (umbral de Z-Vanish)
	if _last_ki_int >= 0 and current < 15.0 and not _was_low_ki and not is_recharging:
		_was_low_ki = true
		if _cached_left_ctrl and is_instance_valid(_cached_left_ctrl) and _cached_left_ctrl.has_method("trigger_haptic_pulse"):
			_cached_left_ctrl.trigger_haptic_pulse("haptic", 85.0, 0.35, 0.10, 0.0)
	elif current >= 20.0:
		_was_low_ki = false

	_last_ki_int = cur_int
	_last_max_ki_int = max_int
	_last_recharging = is_recharging
	_hud_dirty = true
	var percent: float = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if ki_text_label:
		ki_text_label.text = ("KI %d%% ⚡" % int(percent)) if is_recharging else ("KI %d%%" % int(percent))
	if ki_progress_bar:
		ki_progress_bar.max_value = max_val
		ki_progress_bar.value = current

		var fill = ki_progress_bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat:
			if is_recharging:
				fill.bg_color = Color(1.0, 0.85, 0.2, 0.95) # Oro eléctrico al recargar
			elif current < 15.0:
				fill.bg_color = Color(1.0, 0.22, 0.22, 0.95) # Rojo crítico (< 15 Ki sin reserva Z-Vanish)
			else:
				fill.bg_color = Color(0.0, 0.86, 1.0, 0.95) # Cian estándar


func update_power_level(current: float, max_val: float) -> void:
	var cur_int: int = int(current)
	var mult: float = 1.0
	if player_instance and is_instance_valid(player_instance) and player_instance.has_method("get_transformation_multiplier"):
		mult = player_instance.get_transformation_multiplier()
	var percent: float = (current / max_val) * 100.0 if max_val > 0 else 0.0
	var tier_mask: int = (1 if percent >= 25.0 else 0) | (2 if percent >= 50.0 else 0) | (4 if percent >= 75.0 else 0) | (8 if percent >= 100.0 else 0)
	if cur_int == _last_np_int and tier_mask == _last_np_pct_tier and absf(mult - _last_bp_mult) <= 0.05:
		return
	var delta_dir: String = ""
	if _last_np_int >= 0:
		if cur_int > _last_np_int + 5:
			delta_dir = " ▲"
		elif cur_int < _last_np_int - 5:
			delta_dir = " ▼"
	_last_np_int = cur_int
	_last_np_pct_tier = tier_mask
	_last_bp_mult = mult
	_hud_dirty = true
	if bp_value_label:
		bp_value_label.text = "BP %s%s" % [_format_compact_bp(cur_int), delta_dir]

	# Actualizar pips luminosos de umbrales irreversibles (25%, 50%, 75%, 100%)
	var thresh_pcts: Array[float] = [25.0, 50.0, 75.0, 100.0]
	for i in range(threshold_labels.size()):
		var lbl: Label = threshold_labels[i]
		if percent >= thresh_pcts[i]:
			lbl.text = "●"
			lbl.label_settings.font_color = Color(1.0, 0.88, 0.18, 1.0)
		else:
			lbl.text = "○"
			lbl.label_settings.font_color = Color(0.45, 0.60, 0.60, 0.55)


func update_status_text(text: String, color: Color = Color(0.9, 0.9, 0.9)) -> void:
	var clean_text: String = text.strip_edges()
	var upper_c: String = clean_text.to_upper()
	if clean_text == "" or "IDLE" in upper_c or "NEUTRAL" in upper_c:
		_status_override_timer = 0.0
		_status_override_text = ""
		return
	_status_override_text = clean_text.left(24)
	_status_override_color = color
	_status_override_timer = 1.8
	_last_status_override_active = false
	if status_pill_panel and status_pill_label and _last_guard_state != 2 and not _last_zenkai_state and not _last_furia_state and _last_guard_state != 1:
		_apply_pill_appearance(_status_override_text, color, color)


func _format_compact_bp(val: int) -> String:
	var abs_v: int = abs(val)
	if abs_v >= 1000000:
		return "%.2fM" % (float(val) / 1000000.0)
	if abs_v >= 1000:
		return "%.1fK" % (float(val) / 1000.0)
	return str(val)


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
	tooltip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	quad.size = Vector2(0.95, 0.48)
	tooltip_mesh.mesh = quad
	
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tooltip_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 101
	tooltip_mesh.material_override = mat
	
	camera.add_child(tooltip_mesh)
	tooltip_mesh.position = Vector3(0.0, 0.42, -1.65)
	tooltip_mesh.rotation = Vector3.ZERO
	tooltip_mesh.visible = false # Oculto por defecto para no saturar la vista
	
	_update_tooltip_logs()


func _on_hand_states_updated(left_desc: String, right_desc: String) -> void:
	if tooltip_live_joints:
		tooltip_live_joints.text = "L: %s\nR: %s" % [left_desc, right_desc]
		if tooltip_viewport and is_instance_valid(tooltip_viewport) and tooltip_mesh and tooltip_mesh.visible:
			tooltip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func log_gesture_event(msg: String, type: String = "info") -> void:
	if not tooltip_debug_logs:
		return
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
	if tooltip_viewport and is_instance_valid(tooltip_viewport):
		tooltip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if (tooltip_mesh and tooltip_mesh.visible) else SubViewport.UPDATE_DISABLED


# --- Guía de Movimientos y Controles (Abajo a la derecha) ---
func _setup_moves_guide_hud() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	moves_guide_viewport = SubViewport.new()
	moves_guide_viewport.name = "VRMovesGuideViewport"
	moves_guide_viewport.size = Vector2i(900, 950)
	moves_guide_viewport.transparent_bg = true
	moves_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	quad.size = Vector2(0.70, 0.62)
	moves_guide_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = moves_guide_viewport.get_texture()
	mat.no_depth_test = true
	mat.render_priority = 100
	moves_guide_mesh.material_override = mat

	camera.add_child(moves_guide_mesh)
	moves_guide_mesh.position = Vector3(0.62, -0.15, -1.55)
	moves_guide_mesh.rotation = Vector3(deg_to_rad(10), deg_to_rad(-14), 0)
	moves_guide_mesh.visible = false # Oculto en combate para vista limpia e inmersiva

	_update_moves_guide_text(current_controller_mode)


func _on_controller_mode_changed(is_controller: bool) -> void:
	current_controller_mode = is_controller
	if moves_guide_mesh and is_instance_valid(moves_guide_mesh):
		moves_guide_mesh.visible = false
	_update_moves_guide_text(is_controller)


func _get_power_cost_for_guide(tech_name: String, fallback_cost: int) -> int:
	if player_instance and is_instance_valid(player_instance) and player_instance.character_data:
		for p in player_instance.character_data.powers:
			if p and (String(p.power_name).to_lower() == tech_name.to_lower() or String(p.gesture_trigger).to_lower() == tech_name.to_lower()):
				return int(p.ki_cost)
	return fallback_cost


func _update_moves_guide_text(is_controller: bool) -> void:
	current_controller_mode = is_controller
	if not moves_guide_label:
		return

	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var char_name_check: String = player_instance.character_data.character_name if (player_instance and is_instance_valid(player_instance) and player_instance.character_data) else "Vegeta"
	var is_vegeta_cost: bool = "VEGETA" in char_name_check.to_upper()
	var cost_blast: float = cfg.ki_blast_rapid_vegeta_cost if is_vegeta_cost else cfg.ki_blast_cost
	var cost_blast_chg: int = int(cfg.ki_blast_charged_cost)
	var cost_galick: int = _get_power_cost_for_guide("Galick Ho", 28)
	var cost_bigbang: int = _get_power_cost_for_guide("Big Bang Attack", 35)
	var cost_final: int = _get_power_cost_for_guide("Final Flash", 45)
	var cost_kame: int = _get_power_cost_for_guide("Kamehameha", 28)
	var cost_genki: int = _get_power_cost_for_guide("Genkidama", 45)

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
			text += "• [color=#00e5ff]Ki Blast Bimanual [%.1f Ki]:[/color] Palmas extendidas + Gatillos L/R (Corta recargas y satura guardia)\n" % cost_blast
			text += "• [color=#00e5ff]Ki Blast Cargado [%d Ki]:[/color] Mantener Gatillo 0.45s -> Homing, quiebra Poise y abre Cortina de Humo\n" % cost_blast_chg
			text += "• [color=#ffcc00]Saturación & Humo:[/color] Satura al rival ➔ Melee Dash 0 Ki (+1/+2 golpes) o Super +25% vel.\n"
			text += "• [color=#00e5ff]Galick Ho [%d Ki]:[/color] Grips al hombro/costado (Carga) -> Empuja al frente\n" % cost_galick
			text += "• [color=#00e5ff]Big Bang Attack [%d Ki]:[/color] Brazo extendido + palma al frente + Grip (sin Gatillo)\n" % cost_bigbang
			text += "• [color=#00e5ff]Final Flash (SSJ) [%d Ki]:[/color] Brazos en cruz T-Pose con Grips -> Junta al frente\n" % cost_final
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Gatillos a hombros y descender a cintura\n"
			text += "• [color=#00e5ff]Guardia Cruzada (-85%% BP | -7~20 Ki):[/color] Ambos Puños (Grip+Gatillo) al pecho en 'X'\n"
			text += "• [color=#00e5ff]Semáforo / Desvío / Parry:[/color] Aro Verde = Desvío (+5 Ki) | Aro Dorado = Parry (+14 Ki)\n"
			text += "• [color=#00e5ff]Melee Táctico (4-7 Golpes):[/color] Rápido -5 | Cargado -11 | V3 -16 | Sónico +1.5 Ki\n"
			text += "• [color=#ffcc00]Z-Vanish / Onda Kiai (Melee):[/color] Stick [-14 Ki] | Abre brazos + 2 Grips [-22 Ki]\n"
			text += "• [color=#ffcc00]Eventos DBZ (Choque/Meteoro):[/color] Estrellar en Cráter = ¡Super +35%% Vel. Carga!\n"
			text += "• [color=#00e5ff]Melee Dash [%d Ki]:[/color] Puño cerrado (Grip+Gatillo) al frente | Stick Atrás = Cancelar\n" % int(cfg.melee_dash_cost)
			text += "• [color=#00e5ff]Frenado Aéreo:[/color] Agita ambos controles físicos rápido al salir lanzado\n"
			text += "• [color=#ffcc00]Finisher Martillazo DBZ [-%d Ki]:[/color] Ambos puños arriba 0.85s y bajar (Estrella contra el suelo)\n" % int(cfg.melee_hammer_cost)
			text += "• [color=#00e5ff]Movimiento / Altura:[/color] Stick Derecho (Pasos 3m) | Click Der = Subir / Izq = Bajar\n"
			text += "• [color=#00e5ff]Transformar / Base:[/color] Pulsa [A/X] o Puños a la Cintura (Grip+Trigger 1.2s) | [B/Y] Revertir\n"
			text += "• [color=#ff8833]Determinación (Furia, 1x):[/color] Brazos cruzados al pecho + Grips (sin Gatillos) 2.8s\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
			text += "• [color=#aaaaaa]Ocultar/Ver Guía:[/color] Click Joystick / Botón Menú\n"
		else:
			text += "[color=#ffe066][b]TÉCNICAS DE GOKU (MANDOS QUEST):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast Bimanual [%.1f Ki]:[/color] Palmas extendidas + Gatillos L/R (Corta recargas y satura guardia)\n" % cost_blast
			text += "• [color=#00e5ff]Ki Blast Cargado [%d Ki]:[/color] Mantener Gatillo 0.45s -> Homing curvo, quiebra Poise y abre Humo\n" % cost_blast_chg
			text += "• [color=#ffcc00]Saturación & Humo:[/color] Satura al rival ➔ Melee Dash 0 Ki (+1/+2 golpes) o Super +25% vel.\n"
			text += "• [color=#00e5ff]Kamehameha [%d Ki]:[/color] Grips en la cadera (Carga) -> Empuja ambas manos al frente\n" % cost_kame
			text += "• [color=#00e5ff]Genkidama (Base) [%d Ki]:[/color] Brazos al cielo con Grips -> Baja al frente\n" % cost_genki
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Gatillos a hombros y descender a cintura\n"
			text += "• [color=#00e5ff]Guardia Cruzada (-85%% BP | -7~20 Ki):[/color] Ambos Puños (Grip+Gatillo) al pecho en 'X'\n"
			text += "• [color=#00e5ff]Semáforo / Desvío / Parry:[/color] Aro Verde = Desvío (+5 Ki) | Aro Dorado = Parry (+14 Ki)\n"
			text += "• [color=#00e5ff]Melee Táctico (4-7 Golpes):[/color] Rápido -5 | Cargado -11 | V3 -16 | Sónico +1.5 Ki\n"
			text += "• [color=#ffcc00]Z-Vanish / Onda Kiai (Melee):[/color] Stick [-14 Ki] | Abre brazos + 2 Grips [-22 Ki]\n"
			text += "• [color=#ffcc00]Eventos DBZ (Choque/Meteoro):[/color] Estrellar en Cráter = ¡Super +35%% Vel. Carga!\n"
			text += "• [color=#00e5ff]Melee Dash [%d Ki]:[/color] Puño cerrado (Grip+Gatillo) al frente | Stick Atrás = Cancelar\n" % int(cfg.melee_dash_cost)
			text += "• [color=#00e5ff]Frenado Aéreo:[/color] Agita ambos controles físicos rápido al salir lanzado\n"
			text += "• [color=#ffcc00]Finisher Martillazo DBZ [-%d Ki]:[/color] Ambos puños arriba 0.85s y bajar (Estrella contra el suelo)\n" % int(cfg.melee_hammer_cost)
			text += "• [color=#00e5ff]Movimiento / Altura:[/color] Stick Derecho (Pasos 3m) | Click Der = Subir / Izq = Bajar\n"
			text += "• [color=#00e5ff]Transformar / Base:[/color] Pulsa [A/X] o Puños a la Cintura (Grip+Trigger 1.2s) | [B/Y] Revertir\n"
			text += "• [color=#ff8833]Determinación (Furia, 1x):[/color] Brazos cruzados al pecho + Grips (sin Gatillos) 2.8s\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
			text += "• [color=#aaaaaa]Ocultar/Ver Guía:[/color] Click Joystick / Botón Menú\n"
	else:
		if is_vegeta:
			text += "[color=#ffe066][b]GESTOS BIOMÉTRICOS DE VEGETA (HAND TRACKING):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast [%.1f Ki]:[/color] Brazo extendido al frente con palma abierta\n" % cost_blast
			text += "• [color=#00e5ff]Ki Blast Cargado [%d Ki]:[/color] Mantener brazo extendido al frente (crece esfera)\n" % cost_blast_chg
			text += "• [color=#00e5ff]Galick Ho [%d Ki]:[/color] Manos juntas al hombro -> Empuje con palmas al frente\n" % cost_galick
			text += "• [color=#00e5ff]Big Bang Attack [%d Ki]:[/color] Un brazo extendido palma abierta -> Empuje frontal\n" % cost_bigbang
			text += "• [color=#00e5ff]Final Flash (SSJ) [%d Ki]:[/color] Brazos en cruz abiertos -> Juntar palmas al frente\n" % cost_final
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Puños cruzados al pecho -> Puños a la cadera\n"
			text += "• [color=#00e5ff]Guardia / Desvío / Melee:[/color] Puños al pecho | Manotazo veloz | Puño al frente\n"
			text += "• [color=#00e5ff]Transformar:[/color] Manos a la cadera con Ki 100% y extender dedos\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
		else:
			text += "[color=#ffe066][b]GESTOS BIOMÉTRICOS DE GOKU (HAND TRACKING):[/b][/color]\n"
			text += "• [color=#00e5ff]Ki Blast [%.1f Ki]:[/color] Brazo extendido al frente con palma abierta\n" % cost_blast
			text += "• [color=#00e5ff]Ki Blast Cargado [%d Ki]:[/color] Mantener brazo extendido al frente (crece esfera)\n" % cost_blast_chg
			text += "• [color=#00e5ff]Kamehameha [%d Ki]:[/color] Manos juntas en cadera -> Empujar al frente\n" % cost_kame
			text += "• [color=#00e5ff]Genkidama (Base) [%d Ki]:[/color] Brazos elevados al cielo -> Bajar al frente\n" % cost_genki
			text += "• [color=#00e5ff]Recarga Ki (2 Fases):[/color] Puños cruzados al pecho -> Puños a la cadera\n"
			text += "• [color=#00e5ff]Guardia / Desvío / Melee:[/color] Puños cruzados | Manotazo veloz | Puñetazo\n"
			text += "• [color=#00e5ff]Transformar:[/color] Manos a la cadera con Ki 100% y extender dedos\n"
			text += "• [color=#ff5555]Último Aliento:[/color] Si lanzas sin Ki, quemarás Fuerza Vital (BP)\n"
	moves_guide_label.text = text
	if moves_guide_viewport and is_instance_valid(moves_guide_viewport):
		moves_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if (moves_guide_mesh and moves_guide_mesh.visible) else SubViewport.UPDATE_DISABLED


func toggle_moves_guide() -> void:
	if moves_guide_mesh and is_instance_valid(moves_guide_mesh):
		moves_guide_mesh.visible = not moves_guide_mesh.visible
		if moves_guide_viewport and is_instance_valid(moves_guide_viewport):
			moves_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if moves_guide_mesh.visible else SubViewport.UPDATE_DISABLED


func _refresh_ki_cost_label() -> void:
	if not ki_cost_label or not player_instance or not is_instance_valid(player_instance) or not player_instance.character_data:
		return
	var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
	var parts: Array[String] = ["BLAST: %d/%d" % [int(cfg.ki_blast_cost), int(cfg.ki_blast_charged_cost)]]
	for p in player_instance.character_data.powers:
		if not p or String(p.gesture_trigger) == "ki_blast":
			continue
		if String(p.power_name) == "Super Kamehameha":
			continue
		parts.append("%s: %d" % [String(p.power_name).to_upper(), int(p.ki_cost)])
	ki_cost_label.text = "[" + " | ".join(parts) + "]"
	_hud_dirty = true


func refresh_for_character_swap() -> void:
	_last_ki_int = -1
	_last_max_ki_int = -1
	_last_np_int = -1
	_last_np_pct_tier = -1
	_last_bp_mult = -1.0
	_last_enemy_np_int = -1
	_last_player_np_comp = -1
	_last_enemy_mult = -1.0
	_last_guard_state = -1
	_last_zenkai_state = false
	_last_furia_state = false
	_last_status_override_active = false
	_was_low_ki = false
	_status_override_timer = 0.0
	_status_override_text = ""
	_hud_dirty = true
	if player_instance and is_instance_valid(player_instance):
		_refresh_ki_cost_label()
		_on_player_stats_changed(player_instance.current_ki, player_instance.current_np, player_instance.is_in_zenkai_state)
	_update_moves_guide_text(current_controller_mode)
	if sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
