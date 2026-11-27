extends Node3D
class_name KiAuraPreview

const TRANSPARENCY_PRESETS: Array[Dictionary] = [
	{"label": "1. Actual 100% (Bloquea)", "opacity": 1.00, "flames": 1.00, "lightning": 1.00, "fp_clear": 0.00},
	{"label": "2. Suave 60%", "opacity": 0.60, "flames": 0.55, "lightning": 0.70, "fp_clear": 0.00},
	{"label": "3. Media 38%", "opacity": 0.38, "flames": 0.32, "lightning": 0.55, "fp_clear": 0.00},
	{"label": "4. Calibrado VR (24%)", "opacity": 0.24, "flames": 0.11, "lightning": 0.43, "fp_clear": 1.00},
	{"label": "5. Ultra Sutil 12%", "opacity": 0.12, "flames": 0.10, "lightning": 0.28, "fp_clear": 0.00},
	{"label": "6. Ventana VR Frontal (Rec.)", "opacity": 0.45, "flames": 0.24, "lightning": 0.50, "fp_clear": 0.85}
]

const FORM_PRESETS: Array[Dictionary] = [
	{"label": "Base (Celeste)", "char_res": "res://resources/goku_zenkai.tres", "form": ""},
	{"label": "SSJ (Dorado)", "char_res": "res://resources/goku_zenkai.tres", "form": "SSJ"},
	{"label": "SSJ3 (Bio-Rayos)", "char_res": "res://resources/goku_zenkai.tres", "form": "SSJ3"},
	{"label": "SSB (Divino)", "char_res": "res://resources/goku_zenkai.tres", "form": "SSB"},
	{"label": "Vegeta (Violeta)", "char_res": "res://resources/vegeta_zenkai.tres", "form": ""}
]

const STATE_PRESETS: Array[Dictionary] = [
	{"label": "Recargando Ki (Máx)", "charging": true, "flying": false, "furia": false, "zenkai": false},
	{"label": "Transformado (Idle)", "charging": false, "flying": false, "furia": false, "zenkai": false},
	{"label": "Dash / Vuelo", "charging": false, "flying": true, "furia": false, "zenkai": false},
	{"label": "Furia / Zenkai", "charging": false, "flying": false, "furia": true, "zenkai": true}
]

const DIST_PRESETS: Array[Dictionary] = [
	{"label": "Cerca 2.2m", "dist": 2.2},
	{"label": "Media 6.0m", "dist": 6.0},
	{"label": "Lejos 14.0m", "dist": 14.0}
]

var _player_fighter: CharacterInstance = null
var _opponent: CharacterInstance = null
var _cam_pivot: Node3D = null
var _camera: Camera3D = null

var _is_first_person: bool = true
var _opponent_aura_on: bool = true
var _fp_yaw: float = 0.0
var _fp_pitch: float = -0.03
var _orbit_yaw: float = 0.35
var _orbit_pitch: float = -0.14
var _orbit_dist: float = 3.8
var _dragging: bool = false

var _active_preset_idx: int = 0
var _active_form_idx: int = 0
var _active_state_idx: int = 0
var _active_dist_idx: int = 1

var _opacity_val: float = 1.0
var _flames_val: float = 1.0
var _lightning_val: float = 1.0
var _fp_clear_val: float = 0.0

var _preset_buttons: Array[Button] = []
var _form_buttons: Array[Button] = []
var _state_buttons: Array[Button] = []
var _dist_buttons: Array[Button] = []
var _view_btn: Button = null
var _opp_aura_btn: Button = null

var _slider_opacity: HSlider = null
var _slider_flames: HSlider = null
var _slider_fp_clear: HSlider = null
var _lbl_opacity: Label = null
var _lbl_flames: Label = null
var _lbl_fp_clear: Label = null
var _summary_label: Label = null
var _status_label: Label = null
var _updating_sliders: bool = false


func _ready() -> void:
	_build_environment()
	_build_camera_rig()
	_spawn_player_subject(0)
	_spawn_forward_opponent(0)
	_build_ui()
	_select_preset(3)
	_select_state(0)
	_select_distance(1)
	_apply_camera_mode()
	_refresh_opponent_aura_button()


func _build_environment() -> void:
	var env := Environment.new()
	var sky_path: String = "res://assets/images/background.png"
	if ResourceLoader.exists(sky_path):
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = load(sky_path) as Texture2D
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.6
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.45, 0.72, 0.94)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = 0.85

	env.ambient_light_color = Color(0.65, 0.75, 0.88)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.70
	env.glow_bloom = 0.22

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(32.0, 0.2, 32.0)
	floor_mi.mesh = floor_box
	floor_mi.position = Vector3(0.0, -0.1, 0.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.50, 0.55, 0.59)
	fmat.roughness = 0.88
	floor_mi.material_override = fmat
	add_child(floor_mi)

	var grass_mi := MeshInstance3D.new()
	var grass_plane := PlaneMesh.new()
	grass_plane.size = Vector2(140.0, 140.0)
	grass_mi.mesh = grass_plane
	grass_mi.position = Vector3(0.0, -0.25, 0.0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.70, 0.24)
	gmat.roughness = 0.94
	grass_mi.material_override = gmat
	add_child(grass_mi)

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.38, 0.42, 0.46)
	pillar_mat.roughness = 0.85
	var corners: Array[Vector3] = [
		Vector3(-16.0, 4.5, -16.0),
		Vector3(16.0, 4.5, -16.0),
		Vector3(-16.0, 4.5, 16.0),
		Vector3(16.0, 4.5, 16.0)
	]
	for corner in corners:
		var p_mi := MeshInstance3D.new()
		var p_cyl := CylinderMesh.new()
		p_cyl.top_radius = 0.55
		p_cyl.bottom_radius = 0.85
		p_cyl.height = 9.0
		p_mi.mesh = p_cyl
		p_mi.position = corner
		p_mi.material_override = pillar_mat
		add_child(p_mi)


func _build_camera_rig() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "PreviewCameraPivot"
	add_child(_cam_pivot)

	_camera = Camera3D.new()
	_camera.fov = 92.0
	_camera.near = 0.05
	_camera.current = true
	_cam_pivot.add_child(_camera)


func _apply_camera_mode() -> void:
	if _is_first_person:
		_cam_pivot.position = Vector3(0.0, 1.54, 0.0)
		_cam_pivot.rotation = Vector3(_fp_pitch, _fp_yaw, 0.0)
		_camera.position = Vector3.ZERO
		_camera.rotation = Vector3.ZERO
		_camera.fov = 92.0
		if _player_fighter and is_instance_valid(_player_fighter) and _player_fighter.body_mesh_instance:
			_player_fighter.body_mesh_instance.visible = false
	else:
		_cam_pivot.position = Vector3(0.0, 1.05, 0.0)
		_cam_pivot.rotation = Vector3(_orbit_pitch, _orbit_yaw, 0.0)
		_camera.position = Vector3(0.0, 0.0, _orbit_dist)
		_camera.look_at(_cam_pivot.global_position, Vector3.UP)
		_camera.fov = 60.0
		if _player_fighter and is_instance_valid(_player_fighter) and _player_fighter.body_mesh_instance:
			_player_fighter.body_mesh_instance.visible = true

	if _view_btn:
		_view_btn.text = "Vista: 1ra Persona VR (V)" if _is_first_person else "Vista: 3ra Persona Órbita (V)"


func _spawn_player_subject(form_idx: int) -> void:
	if _player_fighter and is_instance_valid(_player_fighter):
		_player_fighter.queue_free()
		_player_fighter = null

	var preset: Dictionary = FORM_PRESETS[clampi(form_idx, 0, FORM_PRESETS.size() - 1)]
	_player_fighter = CharacterInstance.new()
	_player_fighter.name = "AuraSubjectPlayer"
	_player_fighter.character_data = load(String(preset["char_res"])) as CharacterData
	add_child(_player_fighter)
	_player_fighter.global_position = Vector3.ZERO
	_player_fighter.rotation_degrees = Vector3.ZERO
	_strip_ai_and_processes(_player_fighter)
	_player_fighter.is_player = true

	var form_name: String = String(preset["form"])
	if not form_name.is_empty() and _player_fighter.character_data:
		for tr in _player_fighter.character_data.transformations:
			if String(tr.form_name).nocasecmp_to(form_name) == 0:
				_player_fighter.current_transformation = tr
				break

	if _player_fighter.body_mesh_instance and is_instance_valid(_player_fighter.body_mesh_instance):
		_player_fighter.body_mesh_instance.visible = not _is_first_person


func _spawn_forward_opponent(form_idx: int = 0) -> void:
	if _opponent and is_instance_valid(_opponent):
		_opponent.queue_free()
		_opponent = null

	var preset: Dictionary = FORM_PRESETS[clampi(form_idx, 0, FORM_PRESETS.size() - 1)]
	var opp_res_path: String = String(preset["char_res"])
	if not ResourceLoader.exists(opp_res_path):
		opp_res_path = "res://resources/vegeta_zenkai.tres"
	if not ResourceLoader.exists(opp_res_path):
		opp_res_path = "res://resources/goku_zenkai.tres"
	if not ResourceLoader.exists(opp_res_path):
		return

	_opponent = CharacterInstance.new()
	_opponent.name = "ForwardReferenceOpponent"
	_opponent.character_data = load(opp_res_path) as CharacterData
	add_child(_opponent)
	_strip_ai_and_processes(_opponent)
	_opponent.is_player = false
	_opponent.rotation_degrees = Vector3.ZERO

	var form_name: String = String(preset["form"])
	if not form_name.is_empty() and _opponent.character_data:
		for tr in _opponent.character_data.transformations:
			if String(tr.form_name).nocasecmp_to(form_name) == 0:
				_opponent.current_transformation = tr
				if not String(tr.body_model_path).is_empty():
					_opponent._swap_body_mesh_for_path(String(tr.body_model_path))
				break

	_apply_opponent_distance()


func _strip_ai_and_processes(fighter: CharacterInstance) -> void:
	fighter.set_physics_process(false)
	fighter.set_process(false)
	for ch in fighter.get_children():
		if ch.name.contains("AI") or ch is CombatAIController:
			ch.set_process(false)
			ch.set_physics_process(false)
			ch.queue_free()


func _apply_opponent_distance() -> void:
	if _opponent and is_instance_valid(_opponent):
		var d: float = float(DIST_PRESETS[clampi(_active_dist_idx, 0, DIST_PRESETS.size() - 1)]["dist"])
		_opponent.global_position = Vector3(0.0, 0.0, -d)


func _process(delta: float) -> void:
	if _player_fighter == null or not is_instance_valid(_player_fighter):
		return
	var st: Dictionary = STATE_PRESETS[clampi(_active_state_idx, 0, STATE_PRESETS.size() - 1)]
	var chg: bool = bool(st["charging"])
	var fly: bool = bool(st["flying"])
	var fur: bool = bool(st["furia"])
	var zen: bool = bool(st["zenkai"])

	_player_fighter.is_charging_ki = chg
	_player_fighter.is_flying_to_opponent = fly
	_player_fighter.is_in_furia = fur
	_player_fighter.is_in_zenkai_state = zen
	_player_fighter.current_ki = _player_fighter.get_max_ki()
	_player_fighter.aura_opacity_mult = _opacity_val
	_player_fighter.aura_flame_alpha_mult = _flames_val
	_player_fighter.aura_lightning_alpha_mult = _lightning_val
	_player_fighter.aura_fp_center_clear = _fp_clear_val
	_player_fighter._update_aura_visuals(delta)

	if _opponent and is_instance_valid(_opponent):
		if _opponent_aura_on:
			_opponent.is_charging_ki = chg
			_opponent.is_flying_to_opponent = fly
			_opponent.is_in_furia = fur
			_opponent.is_in_zenkai_state = zen
			_opponent.current_ki = _opponent.get_max_ki()
			_opponent.aura_opacity_mult = _opacity_val
			_opponent.aura_flame_alpha_mult = _flames_val
			_opponent.aura_lightning_alpha_mult = _lightning_val
			_opponent.aura_fp_center_clear = 0.0
			_opponent._update_aura_visuals(delta)
			if _opponent.aura_node and is_instance_valid(_opponent.aura_node):
				_opponent.aura_node.visible = true
		elif _opponent.aura_node and is_instance_valid(_opponent.aura_node):
			_opponent.aura_node.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_1:
					_select_preset(0)
				KEY_2:
					_select_preset(1)
				KEY_3:
					_select_preset(2)
				KEY_4:
					_select_preset(3)
				KEY_5:
					_select_preset(4)
				KEY_6:
					_select_preset(5)
				KEY_V:
					_toggle_camera_view()
				KEY_E:
					_toggle_opponent_aura()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif not _is_first_person and mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit_dist = clampf(_orbit_dist - 0.35, 1.6, 9.0)
			_apply_camera_mode()
		elif not _is_first_person and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit_dist = clampf(_orbit_dist + 0.35, 1.6, 9.0)
			_apply_camera_mode()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _is_first_person:
			_fp_yaw -= mm.relative.x * 0.006
			_fp_pitch = clampf(_fp_pitch - mm.relative.y * 0.006, -0.85, 0.85)
		else:
			_orbit_yaw -= mm.relative.x * 0.008
			_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.008, -1.0, 0.55)
		_apply_camera_mode()


func _toggle_camera_view() -> void:
	_is_first_person = not _is_first_person
	_apply_camera_mode()


func _toggle_opponent_aura() -> void:
	_opponent_aura_on = not _opponent_aura_on
	_refresh_opponent_aura_button()


func _refresh_opponent_aura_button() -> void:
	if _opp_aura_btn and is_instance_valid(_opp_aura_btn):
		_opp_aura_btn.button_pressed = _opponent_aura_on
		_opp_aura_btn.text = "Rival Aura: ON (E)" if _opponent_aura_on else "Rival Aura: OFF (E)"


func _select_preset(idx: int) -> void:
	_active_preset_idx = clampi(idx, 0, TRANSPARENCY_PRESETS.size() - 1)
	var p: Dictionary = TRANSPARENCY_PRESETS[_active_preset_idx]
	_opacity_val = float(p["opacity"])
	_flames_val = float(p["flames"])
	_lightning_val = float(p["lightning"])
	_fp_clear_val = float(p["fp_clear"])
	_sync_sliders_and_summary(String(p["label"]))
	_refresh_button_states(_preset_buttons, _active_preset_idx)


func _select_form(idx: int) -> void:
	_active_form_idx = clampi(idx, 0, FORM_PRESETS.size() - 1)
	_spawn_player_subject(_active_form_idx)
	_spawn_forward_opponent(_active_form_idx)
	_refresh_button_states(_form_buttons, _active_form_idx)
	_set_status("Forma activa: %s" % String(FORM_PRESETS[_active_form_idx]["label"]))


func _select_state(idx: int) -> void:
	_active_state_idx = clampi(idx, 0, STATE_PRESETS.size() - 1)
	_refresh_button_states(_state_buttons, _active_state_idx)
	_set_status("Estado: %s" % String(STATE_PRESETS[_active_state_idx]["label"]))


func _select_distance(idx: int) -> void:
	_active_dist_idx = clampi(idx, 0, DIST_PRESETS.size() - 1)
	_apply_opponent_distance()
	_refresh_button_states(_dist_buttons, _active_dist_idx)
	_set_status("Distancia al rival: %s" % String(DIST_PRESETS[_active_dist_idx]["label"]))


func _refresh_button_states(buttons: Array[Button], active_idx: int) -> void:
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		if b and is_instance_valid(b):
			b.button_pressed = (i == active_idx)


func _sync_sliders_and_summary(preset_title: String) -> void:
	_updating_sliders = true
	if _slider_opacity:
		_slider_opacity.value = _opacity_val * 100.0
	if _slider_flames:
		_slider_flames.value = _flames_val * 100.0
	if _slider_fp_clear:
		_slider_fp_clear.value = _fp_clear_val * 100.0
	_updating_sliders = false
	_update_numeric_labels(preset_title)


func _update_numeric_labels(preset_title: String) -> void:
	if _lbl_opacity:
		_lbl_opacity.text = "Opacidad Aura (Mallas): %d%%" % int(round(_opacity_val * 100.0))
	if _lbl_flames:
		_lbl_flames.text = "Opacidad Llamas (Partículas): %d%%" % int(round(_flames_val * 100.0))
	if _lbl_fp_clear:
		_lbl_fp_clear.text = "Despeje Frontal VR (Cono): %d%%" % int(round(_fp_clear_val * 100.0))
	if _summary_label:
		_summary_label.text = "%s\nopacity=%.2f | flames=%.2f | fp_clear=%.2f" % [
			preset_title, _opacity_val, _flames_val, _fp_clear_val
		]


func _on_slider_changed(_val: float) -> void:
	if _updating_sliders:
		return
	_opacity_val = float(_slider_opacity.value) * 0.01
	_flames_val = float(_slider_flames.value) * 0.01
	_fp_clear_val = float(_slider_fp_clear.value) * 0.01
	_lightning_val = clampf(lerpf(0.25, 1.0, _opacity_val), 0.15, 1.0)
	_refresh_button_states(_preset_buttons, -1)
	_update_numeric_labels("Personalizado")


func _copy_values_to_clipboard() -> void:
	var preset_name: String = "Personalizado"
	if _active_preset_idx >= 0 and _active_preset_idx < TRANSPARENCY_PRESETS.size():
		preset_name = String(TRANSPARENCY_PRESETS[_active_preset_idx]["label"])
	var txt: String = "Preset: %s | aura_opacity_mult=%.2f | aura_flame_alpha_mult=%.2f | aura_lightning_alpha_mult=%.2f | aura_fp_center_clear=%.2f" % [
		preset_name, _opacity_val, _flames_val, _lightning_val, _fp_clear_val
	]
	DisplayServer.clipboard_set(txt)
	_set_status("Valores copiados al portapapeles: " + txt)


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 8.0
	top_panel.offset_right = -8.0
	top_panel.offset_top = 8.0
	top_panel.offset_bottom = 46.0
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = Color(0.05, 0.07, 0.12, 0.78)
	top_sb.set_corner_radius_all(6)
	top_panel.add_theme_stylebox_override("panel", top_sb)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 4)
	top_panel.add_child(top_hbox)

	for i in range(TRANSPARENCY_PRESETS.size()):
		var b := Button.new()
		b.text = String(TRANSPARENCY_PRESETS[i]["label"])
		b.toggle_mode = true
		var cap_i: int = i
		b.pressed.connect(func() -> void: _select_preset(cap_i))
		top_hbox.add_child(b)
		_preset_buttons.append(b)

	_view_btn = Button.new()
	_view_btn.text = "Vista: 1ra Persona VR (V)"
	_view_btn.pressed.connect(_toggle_camera_view)
	top_hbox.add_child(_view_btn)

	_opp_aura_btn = Button.new()
	_opp_aura_btn.text = "Rival Aura: ON (E)"
	_opp_aura_btn.toggle_mode = true
	_opp_aura_btn.button_pressed = _opponent_aura_on
	_opp_aura_btn.pressed.connect(_toggle_opponent_aura)
	top_hbox.add_child(_opp_aura_btn)

	var copy_btn := Button.new()
	copy_btn.text = "📋 Copiar Valores"
	copy_btn.pressed.connect(_copy_values_to_clipboard)
	top_hbox.add_child(copy_btn)
	canvas.add_child(top_panel)

	var left_panel := PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_left = 8.0
	left_panel.offset_right = 290.0
	left_panel.offset_top = 54.0
	left_panel.offset_bottom = -34.0
	var left_sb := StyleBoxFlat.new()
	left_sb.bg_color = Color(0.05, 0.07, 0.12, 0.72)
	left_sb.set_corner_radius_all(6)
	left_panel.add_theme_stylebox_override("panel", left_sb)
	canvas.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 5)
	left_scroll.add_child(vb)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 12)
	_summary_label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.86))
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_summary_label)

	vb.add_child(HSeparator.new())
	_add_section_header(vb, "Ajuste Fino en Vivo")

	_lbl_opacity = Label.new()
	_lbl_opacity.add_theme_font_size_override("font_size", 12)
	vb.add_child(_lbl_opacity)
	_slider_opacity = _make_slider(vb)

	_lbl_flames = Label.new()
	_lbl_flames.add_theme_font_size_override("font_size", 12)
	vb.add_child(_lbl_flames)
	_slider_flames = _make_slider(vb)

	_lbl_fp_clear = Label.new()
	_lbl_fp_clear.add_theme_font_size_override("font_size", 12)
	vb.add_child(_lbl_fp_clear)
	_slider_fp_clear = _make_slider(vb)

	vb.add_child(HSeparator.new())
	_add_section_header(vb, "Forma / Aura")
	for i in range(FORM_PRESETS.size()):
		var fb := Button.new()
		fb.text = String(FORM_PRESETS[i]["label"])
		fb.toggle_mode = true
		var cap_f: int = i
		fb.pressed.connect(func() -> void: _select_form(cap_f))
		vb.add_child(fb)
		_form_buttons.append(fb)
	_refresh_button_states(_form_buttons, _active_form_idx)

	vb.add_child(HSeparator.new())
	_add_section_header(vb, "Estado de Combate")
	for i in range(STATE_PRESETS.size()):
		var sb_btn := Button.new()
		sb_btn.text = String(STATE_PRESETS[i]["label"])
		sb_btn.toggle_mode = true
		var cap_s: int = i
		sb_btn.pressed.connect(func() -> void: _select_state(cap_s))
		vb.add_child(sb_btn)
		_state_buttons.append(sb_btn)

	vb.add_child(HSeparator.new())
	_add_section_header(vb, "Distancia Rival")
	var dist_hb := HBoxContainer.new()
	vb.add_child(dist_hb)
	for i in range(DIST_PRESETS.size()):
		var db := Button.new()
		db.text = String(DIST_PRESETS[i]["label"])
		db.toggle_mode = true
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_d: int = i
		db.pressed.connect(func() -> void: _select_distance(cap_d))
		dist_hb.add_child(db)
		_dist_buttons.append(db)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_left = 10.0
	_status_label.offset_right = -10.0
	_status_label.offset_top = -28.0
	_status_label.offset_bottom = -4.0
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_status_label.text = "Teclas 1-6: Grados de transparencia | V: 1ra/3ra persona | E: Aura rival ON/OFF | Arrastra mouse: mirar"
	canvas.add_child(_status_label)


func _add_section_header(parent: VBoxContainer, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	parent.add_child(lbl)


func _make_slider(parent: VBoxContainer) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.value_changed.connect(_on_slider_changed)
	parent.add_child(s)
	return s
