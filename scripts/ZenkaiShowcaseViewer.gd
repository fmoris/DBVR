extends Node3D
class_name ZenkaiShowcaseViewer

const ZenkaiAuraShader = preload("res://shaders/zenkai_aura.gdshader")
const KiBeamShader = preload("res://shaders/ki_beam.gdshader")

const FORM_PRESETS: Array[Dictionary] = [
	{"label": "Goku Base", "char_res": "res://resources/goku_zenkai.tres", "form": "", "color": Color(0.75, 0.92, 1.0, 0.85), "lightning": false},
	{"label": "Goku SSJ", "char_res": "res://resources/goku_zenkai.tres", "form": "SSJ", "color": Color(1.0, 0.85, 0.1, 0.90), "lightning": false},
	{"label": "Goku SSJ3", "char_res": "res://resources/goku_zenkai.tres", "form": "SSJ3", "color": Color(1.0, 0.92, 0.25, 0.95), "lightning": true},
	{"label": "Goku SSB", "char_res": "res://resources/goku_zenkai.tres", "form": "SSB", "color": Color(0.1, 0.7, 1.0, 0.92), "lightning": true},
	{"label": "Vegeta Base", "char_res": "res://resources/vegeta.tres", "form": "", "color": Color(0.85, 0.35, 1.0, 0.85), "lightning": false},
	{"label": "Vegeta Super", "char_res": "res://resources/vegeta.tres", "form": "Super Vegeta", "color": Color(1.0, 0.9, 0.0, 0.95), "lightning": true},
	{"label": "Vegeta SSB", "char_res": "res://resources/vegeta.tres", "form": "SSB", "color": Color(0.1, 0.7, 1.0, 0.92), "lightning": true},
]

const MANUAL_BONES: Array[String] = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"
]

var _fighter: CharacterInstance = null
var _cam_pivot: Node3D = null
var _camera: Camera3D = null
var _vfx_root: Node3D = null
var _active_beam_node: Node3D = null
var _active_orb_node: Node3D = null

var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.15
var _cam_dist: float = 3.6
var _dragging: bool = false

var _state_charging_ki: bool = false
var _state_blocking: bool = false
var _state_flying: bool = false
var _state_aura_on: bool = false
var _state_lightning: bool = false
var _current_color: Color = Color(0.75, 0.92, 1.0, 0.90)

var _status_label: Label = null
var _debug_hud_label: Label = null
var _mode_btn: Button = null
# 0 = Calibrado, 1 = SPA Puro, 2 = Manual / Poses Prueba
var _anim_mode: int = 0
var _frame_paused: bool = false
var _frame_slider: HSlider = null

# Editor manual de huesos (grados Euler por alias de hueso)
var _manual_eulers: Dictionary = {}
var _selected_bone: String = "LeftArm"
var _bone_selector: OptionButton = null
var _slider_x: HSlider = null
var _slider_y: HSlider = null
var _slider_z: HSlider = null
var _lbl_x: Label = null
var _lbl_y: Label = null
var _lbl_z: Label = null
var _updating_sliders: bool = false


func _ready() -> void:
	for b in MANUAL_BONES:
		_manual_eulers[b] = Vector3.ZERO
	_build_environment()
	_build_camera()
	_vfx_root = Node3D.new()
	_vfx_root.name = "ShowcaseVFXRoot"
	add_child(_vfx_root)
	_build_ui()
	_load_preset(0)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.11, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.92)
	env.ambient_light_energy = 0.80
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.35
	add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(28.0, 28.0)
	floor_mi.mesh = floor_plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.24, 0.28)
	fmat.roughness = 0.88
	floor_mi.material_override = fmat
	add_child(floor_mi)


func _build_camera() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0.0, 1.05, 0.0)
	add_child(_cam_pivot)
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.current = true
	_cam_pivot.add_child(_camera)
	_update_camera_transform()


func _update_camera_transform() -> void:
	_cam_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _cam_dist)
	_camera.look_at(_cam_pivot.global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 0.35, 1.4, 12.0)
			_update_camera_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 0.35, 1.4, 12.0)
			_update_camera_transform()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.008, -1.1, 0.65)
		_update_camera_transform()


func _process(delta: float) -> void:
	if _fighter == null or not is_instance_valid(_fighter):
		return
	_fighter.is_charging_ki = _state_charging_ki
	_fighter.is_blocking = _state_blocking
	_fighter.is_flying_to_opponent = _state_flying
	_fighter.is_in_zenkai_state = _state_lightning
	_fighter.current_ki = 100.0 if _state_aura_on else 5.0
	if _fighter.aura_node and is_instance_valid(_fighter.aura_node):
		_fighter.aura_node.visible = _state_aura_on

	if _fighter.procedural_animator == null:
		return

	var anim: ProceduralCombatAnimator = _fighter.procedural_animator
	if _anim_mode == 2:
		_apply_manual_pose(anim)
		if _debug_hud_label != null:
			_debug_hud_label.text = _get_manual_debug_summary()
	else:
		var look_target: Vector3 = _fighter.global_position + Vector3(0.0, 1.45, 4.0)
		anim.use_pure_zenkai_spa = (_anim_mode == 1)
		if _frame_paused and _frame_slider != null:
			anim.spa_forced_u = float(_frame_slider.value)
		else:
			anim.spa_forced_u = -1.0
		anim.update(delta, look_target, _state_charging_ki, _state_blocking, _state_flying)
		if _debug_hud_label != null:
			_debug_hud_label.text = anim.get_spa_debug_summary()


func _apply_manual_pose(anim: ProceduralCombatAnimator) -> void:
	if anim.skeleton == null or not is_instance_valid(anim.skeleton):
		return
	for b_alias in MANUAL_BONES:
		var idx: int = int(anim.bone_indices.get(b_alias, -1))
		if idx == -1:
			continue
		var rest_q: Quaternion = anim.bone_rest_rotations.get(b_alias, Quaternion.IDENTITY)
		var deg: Vector3 = _manual_eulers.get(b_alias, Vector3.ZERO)
		var offset_q: Quaternion = Quaternion.from_euler(deg * (PI / 180.0))
		anim.skeleton.set_bone_pose_rotation(idx, (rest_q * offset_q).normalized())


func _get_manual_debug_summary() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("MODO MANUAL | Hueso: %s" % _selected_bone)
	var cur: Vector3 = _manual_eulers.get(_selected_bone, Vector3.ZERO)
	lines.append("Actual: X=%+.0f  Y=%+.0f  Z=%+.0f" % [cur.x, cur.y, cur.z])
	var moved: int = 0
	for b in MANUAL_BONES:
		var v: Vector3 = _manual_eulers.get(b, Vector3.ZERO)
		if v.length_squared() > 0.1:
			lines.append("%-13s: (%+4.0f, %+4.0f, %+4.0f)" % [b, v.x, v.y, v.z])
			moved += 1
			if moved >= 6:
				break
	if moved == 0:
		lines.append("(T-Pose reposo — mueve sliders o usa Pose Prueba)")
	return "\n".join(lines)


func _copy_coordinates_to_clipboard() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if _anim_mode == 2:
		lines.append("=== COORDENADAS MANUALES ===")
		for b in MANUAL_BONES:
			var v: Vector3 = _manual_eulers.get(b, Vector3.ZERO)
			if v.length_squared() > 0.1:
				lines.append("%s: Vector3(%.1f, %.1f, %.1f)" % [b, v.x, v.y, v.z])
	elif _fighter and _fighter.procedural_animator:
		lines.append("=== DIAGNOSTICO SPA ===")
		lines.append(_fighter.procedural_animator.get_spa_debug_summary())
	var txt: String = "\n".join(lines)
	DisplayServer.clipboard_set(txt)
	_set_status("¡Coordenadas copiadas al portapapeles! Pega con Ctrl+V en el chat.")


func _load_preset(idx: int) -> void:
	var preset: Dictionary = FORM_PRESETS[clampi(idx, 0, FORM_PRESETS.size() - 1)]
	_clear_vfx()
	if _fighter and is_instance_valid(_fighter):
		_fighter.queue_free()
		_fighter = null

	_fighter = CharacterInstance.new()
	_fighter.name = "ShowcaseFighter"
	_fighter.is_player = false
	_fighter.character_data = load(String(preset["char_res"])) as CharacterData
	add_child(_fighter)
	_fighter.global_position = Vector3.ZERO
	_fighter.rotation_degrees = Vector3.ZERO
	for ch in _fighter.get_children():
		if ch.name.contains("AI") or ch is CombatAIController:
			ch.set_process(false)
			ch.set_physics_process(false)
			ch.queue_free()

	_current_color = preset["color"]
	_state_lightning = bool(preset["lightning"])
	var form_name: String = String(preset["form"])
	if not form_name.is_empty() and _fighter.character_data:
		for tr in _fighter.character_data.transformations:
			if String(tr.form_name).nocasecmp_to(form_name) == 0:
				_fighter.current_transformation = tr
				if not String(tr.body_model_path).is_empty():
					_fighter._swap_body_mesh_for_path(String(tr.body_model_path))
				if _fighter.procedural_animator:
					_fighter.procedural_animator.reload_zenkai_animations(tr.form_name, String(tr.anim_library_path))
				break

	_set_status("Personaje: %s | Arrastra mouse para rotar, rueda para zoom" % String(preset["label"]))


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _sync_sliders_from_selected_bone() -> void:
	_updating_sliders = true
	var v: Vector3 = _manual_eulers.get(_selected_bone, Vector3.ZERO)
	if _slider_x:
		_slider_x.value = v.x
		_lbl_x.text = "X: %+4.0f°" % v.x
	if _slider_y:
		_slider_y.value = v.y
		_lbl_y.text = "Y: %+4.0f°" % v.y
	if _slider_z:
		_slider_z.value = v.z
		_lbl_z.text = "Z: %+4.0f°" % v.z
	_updating_sliders = false


func _set_manual_pose_dict(pose: Dictionary, title: String) -> void:
	_anim_mode = 2
	if _mode_btn:
		_mode_btn.text = "Modo: 2 Manual / Poses Prueba"
	for b in MANUAL_BONES:
		_manual_eulers[b] = pose.get(b, Vector3.ZERO)
	_sync_sliders_from_selected_bone()
	_set_status("Pose Prueba: " + title)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Barra superior: Personajes / Transformaciones
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 10.0
	top_panel.offset_right = -10.0
	top_panel.offset_top = 8.0
	top_panel.offset_bottom = 44.0
	var top_hbox := HBoxContainer.new()
	top_panel.add_child(top_hbox)
	for i in range(FORM_PRESETS.size()):
		var b := Button.new()
		b.text = String(FORM_PRESETS[i]["label"])
		var cap_i: int = i
		b.pressed.connect(func() -> void: _load_preset(cap_i))
		top_hbox.add_child(b)
	var copy_btn := Button.new()
	copy_btn.text = "📋 Copiar Coordenadas"
	copy_btn.pressed.connect(_copy_coordinates_to_clipboard)
	top_hbox.add_child(copy_btn)
	canvas.add_child(top_panel)

	# Barra de estado inferior anclada
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_left = 12.0
	_status_label.offset_right = -12.0
	_status_label.offset_top = -28.0
	_status_label.offset_bottom = -4.0
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	canvas.add_child(_status_label)

	# COLUMNA IZQUIERDA COMPLETA (anclada de arriba a abajo, con scroll limpio, sin solapamientos)
	var left_panel := PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_left = 10.0
	left_panel.offset_right = 340.0
	left_panel.offset_top = 50.0
	left_panel.offset_bottom = -32.0
	canvas.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	var left_vb := VBoxContainer.new()
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vb.add_theme_constant_override("separation", 5)
	left_scroll.add_child(left_vb)

	# 1. HUD de diagnóstico (siempre visible, sin recortes)
	_debug_hud_label = Label.new()
	_debug_hud_label.add_theme_font_size_override("font_size", 12)
	_debug_hud_label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.82))
	_debug_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vb.add_child(_debug_hud_label)

	left_vb.add_child(HSeparator.new())

	# 2. Selector de Modo + Calibración SPA
	_mode_btn = Button.new()
	_mode_btn.text = "Modo: 0 Calibrado (Seguro)"
	_mode_btn.pressed.connect(func() -> void:
		_anim_mode = (_anim_mode + 1) % 3
		var names: Array[String] = ["0 Calibrado (Seguro)", "1 SPA Puro (Debug)", "2 Manual / Poses Prueba"]
		_mode_btn.text = "Modo: " + names[_anim_mode]
		_set_status("Cambiado a " + _mode_btn.text)
	)
	left_vb.add_child(_mode_btn)

	var comp_btn := Button.new()
	comp_btn.text = "SPA Comp: 4 (calibrado)"
	comp_btn.pressed.connect(func() -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_compose_mode = (_fighter.procedural_animator.spa_compose_mode + 1) % 5
			var labels: Array[String] = ["0 (rest * spa)", "1 (spa * rest)", "2 (rest * inv)", "3 (spa directo)", "4 (calibrado)"]
			comp_btn.text = "SPA Comp: " + labels[_fighter.procedural_animator.spa_compose_mode]
	)
	left_vb.add_child(comp_btn)

	var row1 := HBoxContainer.new()
	left_vb.add_child(row1)
	_add_cal_toggle(row1, "X:+1", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_axis_signs.x *= -1.0
			btn.text = "X:%+.0f" % _fighter.procedural_animator.spa_axis_signs.x
	)
	_add_cal_toggle(row1, "Y:+1", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_axis_signs.y *= -1.0
			btn.text = "Y:%+.0f" % _fighter.procedural_animator.spa_axis_signs.y
	)
	_add_cal_toggle(row1, "Z:+1", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_axis_signs.z *= -1.0
			btn.text = "Z:%+.0f" % _fighter.procedural_animator.spa_axis_signs.z
	)
	_add_cal_toggle(row1, "L/R:OFF", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_swap_lr = not _fighter.procedural_animator.spa_swap_lr
			btn.text = "L/R:" + ("ON" if _fighter.procedural_animator.spa_swap_lr else "OFF")
	)

	var row2 := HBoxContainer.new()
	left_vb.add_child(row2)
	_add_cal_toggle(row2, "Torso:ON", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_enable_torso = not _fighter.procedural_animator.spa_enable_torso
			btn.text = "Torso:" + ("ON" if _fighter.procedural_animator.spa_enable_torso else "OFF")
	)
	_add_cal_toggle(row2, "Braz:ON", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_enable_arms = not _fighter.procedural_animator.spa_enable_arms
			btn.text = "Braz:" + ("ON" if _fighter.procedural_animator.spa_enable_arms else "OFF")
	)
	_add_cal_toggle(row2, "Pier:ON", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_enable_legs = not _fighter.procedural_animator.spa_enable_legs
			btn.text = "Pier:" + ("ON" if _fighter.procedural_animator.spa_enable_legs else "OFF")
	)
	_add_cal_toggle(row2, "Cab:OFF", func(btn: Button) -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.spa_enable_head = not _fighter.procedural_animator.spa_enable_head
			btn.text = "Cab:" + ("ON" if _fighter.procedural_animator.spa_enable_head else "OFF")
	)

	var row3 := HBoxContainer.new()
	left_vb.add_child(row3)
	_add_cal_toggle(row3, "Pausa", func(btn: Button) -> void:
		_frame_paused = not _frame_paused
		btn.text = "Play" if _frame_paused else "Pausa"
	)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0.0
	_frame_slider.max_value = 1.0
	_frame_slider.step = 0.02
	_frame_slider.value = 0.0
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_frame_slider)

	left_vb.add_child(HSeparator.new())

	# 3. POSES DE PRUEBA + EDITOR MANUAL DE HUESOS
	var man_hdr := Label.new()
	man_hdr.text = "=== POSES DE PRUEBA / HUESOS ==="
	left_vb.add_child(man_hdr)

	var pose_grid := GridContainer.new()
	pose_grid.columns = 2
	left_vb.add_child(pose_grid)

	_add_grid_btn(pose_grid, "T-Pose (Reset)", func() -> void:
		_set_manual_pose_dict({}, "T-Pose (Reposo)")
	)
	_add_grid_btn(pose_grid, "Brazos Adelante", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(0.0, -90.0, 0.0),
			"RightArm": Vector3(0.0, -90.0, 0.0),
		}, "Brazos Adelante (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Brazos Arriba", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(-180.0, 0.0, -75.0),
			"RightArm": Vector3(-180.0, 0.0, -75.0),
		}, "Brazos Arriba (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Brazos Abajo", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(0.0, -10.0, -75.0),
			"RightArm": Vector3(5.0, -15.0, -75.0),
		}, "Brazos Abajo (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Flexionar Codos", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(0.0, -90.0, 0.0),
			"LeftForeArm": Vector3(0.0, -180.0, 85.0),
			"RightArm": Vector3(0.0, -90.0, 0.0),
			"RightForeArm": Vector3(-180.0, 0.0, -90.0),
		}, "Flexionar Codos (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Flexionar Muñecas", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(0.0, -10.0, -75.0),
			"LeftHand": Vector3(-100.0, 0.0, 0.0),
			"RightArm": Vector3(5.0, -15.0, -75.0),
			"RightHand": Vector3(-100.0, 0.0, 0.0),
		}, "Flexionar Muñecas (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Flexionar Rodillas", func() -> void:
		_set_manual_pose_dict({
			"LeftUpLeg": Vector3(0.0, -100.0, 5.0),
			"LeftLeg": Vector3(0.0, 90.0, 0.0),
			"RightUpLeg": Vector3(0.0, -100.0, 5.0),
			"RightLeg": Vector3(-15.0, 100.0, 0.0),
		}, "Flexionar Rodillas (Calibrado)")
	)
	_add_grid_btn(pose_grid, "Guardia Manual", func() -> void:
		_set_manual_pose_dict({
			"LeftArm": Vector3(0.0, -45.0, -40.0),
			"LeftForeArm": Vector3(0.0, -180.0, 85.0),
			"RightArm": Vector3(0.0, -65.0, -35.0),
			"RightForeArm": Vector3(-180.0, 0.0, -90.0),
			"LeftUpLeg": Vector3(0.0, -25.0, 12.0),
			"LeftLeg": Vector3(0.0, 35.0, 0.0),
			"RightUpLeg": Vector3(0.0, -30.0, -8.0),
			"RightLeg": Vector3(0.0, 38.0, 0.0),
		}, "Guardia Marcial (Calibrado)")
	)

	# Selector de hueso + Sliders X/Y/Z
	var bone_row := HBoxContainer.new()
	left_vb.add_child(bone_row)
	_bone_selector = OptionButton.new()
	_bone_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in MANUAL_BONES:
		_bone_selector.add_item(b)
	_bone_selector.selected = MANUAL_BONES.find("LeftArm")
	_bone_selector.item_selected.connect(func(idx: int) -> void:
		_selected_bone = MANUAL_BONES[idx]
		_sync_sliders_from_selected_bone()
	)
	bone_row.add_child(_bone_selector)
	var rst_bone := Button.new()
	rst_bone.text = "0°"
	rst_bone.pressed.connect(func() -> void:
		_manual_eulers[_selected_bone] = Vector3.ZERO
		_sync_sliders_from_selected_bone()
	)
	bone_row.add_child(rst_bone)

	var sx_pair: Array = _add_axis_slider(left_vb, "X", func(val: float) -> void:
		if _updating_sliders: return
		_anim_mode = 2
		_mode_btn.text = "Modo: 2 Manual / Poses Prueba"
		var cur: Vector3 = _manual_eulers.get(_selected_bone, Vector3.ZERO)
		cur.x = val
		_manual_eulers[_selected_bone] = cur
		_lbl_x.text = "X: %+4.0f°" % val
	)
	_lbl_x = sx_pair[0] as Label
	_slider_x = sx_pair[1] as HSlider

	var sy_pair: Array = _add_axis_slider(left_vb, "Y", func(val: float) -> void:
		if _updating_sliders: return
		_anim_mode = 2
		_mode_btn.text = "Modo: 2 Manual / Poses Prueba"
		var cur: Vector3 = _manual_eulers.get(_selected_bone, Vector3.ZERO)
		cur.y = val
		_manual_eulers[_selected_bone] = cur
		_lbl_y.text = "Y: %+4.0f°" % val
	)
	_lbl_y = sy_pair[0] as Label
	_slider_y = sy_pair[1] as HSlider

	var sz_pair: Array = _add_axis_slider(left_vb, "Z", func(val: float) -> void:
		if _updating_sliders: return
		_anim_mode = 2
		_mode_btn.text = "Modo: 2 Manual / Poses Prueba"
		var cur: Vector3 = _manual_eulers.get(_selected_bone, Vector3.ZERO)
		cur.z = val
		_manual_eulers[_selected_bone] = cur
		_lbl_z.text = "Z: %+4.0f°" % val
	)
	_lbl_z = sz_pair[0] as Label
	_slider_z = sz_pair[1] as HSlider

	left_vb.add_child(HSeparator.new())

	# 4. Animaciones de Combate
	var anim_hdr := Label.new()
	anim_hdr.text = "=== ANIMACIONES COMBATE ==="
	left_vb.add_child(anim_hdr)

	_add_anim_btn(left_vb, "Idle Guardia", func() -> void:
		_reset_anim_flags()
		_set_status("Anim: Idle Guardia")
	)
	_add_anim_btn(left_vb, "Vuelo / Dash", func() -> void:
		_reset_anim_flags()
		_state_flying = true
		_set_status("Anim: Vuelo / Dash")
	)
	_add_anim_btn(left_vb, "Recarga Ki (F1)", func() -> void:
		_reset_anim_flags()
		_state_charging_ki = true
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_ki_recharge_phase(1)
		_set_status("Anim: Recarga Ki Fase 1")
	)
	_add_anim_btn(left_vb, "Recarga Ki (F2)", func() -> void:
		_reset_anim_flags()
		_state_charging_ki = true
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_ki_recharge_phase(2)
		_set_status("Anim: Recarga Ki Fase 2")
	)
	_add_anim_btn(left_vb, "Transformación / Roar", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.trigger_transformation_roar()
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), Vector3(0.0, 1.0, 0.0), 3, _current_color, true)
		_set_status("Anim: Transformación + Estallido Aura")
	)
	_add_anim_btn(left_vb, "Guardia / Bloqueo", func() -> void:
		_reset_anim_flags()
		_state_blocking = true
		_set_status("Anim: Guardia")
	)
	_add_anim_btn(left_vb, "Hit Flinch (Golpeado)", func() -> void:
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.trigger_hit_flinch(1.1, Vector3(0.0, 0.0, -1.0))
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), Vector3(0.0, 1.25, 0.25), Color(1.0, 0.85, 0.3), 1.0)
		_set_status("Anim: Hit Flinch + Impacto")
	)
	_add_anim_btn(left_vb, "Ki Blast Izq", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.trigger_ki_blast_shot(0)
		_spawn_orb_vfx(Vector3(-0.35, 1.25, 0.55), 0.16, Color(1.0, 0.65, 0.1, 0.95), false, false)
		_set_status("Anim: Ki Blast Izquierdo")
	)
	_add_anim_btn(left_vb, "Ki Blast Der", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.trigger_ki_blast_shot(1)
		_spawn_orb_vfx(Vector3(0.35, 1.25, 0.55), 0.16, Color(1.0, 0.65, 0.1, 0.95), false, false)
		_set_status("Anim: Ki Blast Derecho")
	)
	for m in range(6):
		var m_idx: int = m
		var m_lbl: String = "Melee Heavy Smash" if m == 5 else ("Melee Rush %d" % (m + 1))
		_add_anim_btn(left_vb, m_lbl, func() -> void:
			_reset_anim_flags()
			if _fighter and _fighter.procedural_animator:
				_fighter.procedural_animator.trigger_melee_strike(m_idx)
			_set_status("Anim: " + m_lbl)
		)
	_add_anim_btn(left_vb, "Kamehameha Carga", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Kamehameha", 1)
		_spawn_orb_vfx(Vector3(-0.22, 1.12, 0.35), 0.28, Color(0.15, 0.68, 1.0, 0.95), true, true)
		_set_status("Anim: Kamehameha Carga + Orbe Zenkai")
	)
	_add_anim_btn(left_vb, "Kamehameha Disparo", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Kamehameha", 2)
		_spawn_beam_vfx(Color(0.15, 0.68, 1.0, 0.95), 0.38)
		_set_status("Anim: Kamehameha Disparo + Haz Zenkai")
	)
	_add_anim_btn(left_vb, "Galick Ho Disparo", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Galick Ho", 2)
		_spawn_beam_vfx(Color(0.75, 0.18, 1.0, 0.95), 0.38)
		_set_status("Anim: Galick Ho + Haz Púrpura Zenkai")
	)
	_add_anim_btn(left_vb, "Final Flash Disparo", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Final Flash", 2)
		_spawn_beam_vfx(Color(1.0, 0.88, 0.15, 0.95), 0.45)
		_set_status("Anim: Final Flash + Haz Dorado Zenkai")
	)
	_add_anim_btn(left_vb, "Big Bang Attack", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Big Bang Attack", 2)
		_spawn_orb_vfx(Vector3(0.0, 1.25, 0.95), 0.55, Color(0.25, 0.78, 1.0, 0.95), true, true)
		_set_status("Anim: Big Bang + Super Orbe Zenkai")
	)
	_add_anim_btn(left_vb, "Genkidama", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.set_super_pose("Genkidama", 1)
		_spawn_orb_vfx(Vector3(0.0, 2.75, 0.0), 0.95, Color(0.20, 0.75, 1.0, 0.95), true, true)
		_set_status("Anim: Genkidama + Super Orbe Zenkai")
	)
	_add_anim_btn(left_vb, "Kip-Up Recuperación", func() -> void:
		_reset_anim_flags()
		if _fighter and _fighter.procedural_animator:
			_fighter.procedural_animator.trigger_getup_recovery(0.55)
		_set_status("Anim: Kip-Up")
	)

	# PANEL DERECHO: Efectos Especiales Zenkai (anclado de arriba a abajo al borde derecho)
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -260.0
	right_panel.offset_right = -10.0
	right_panel.offset_top = 50.0
	right_panel.offset_bottom = -32.0
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_scroll)
	var right_vb := VBoxContainer.new()
	right_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_vb)

	var vfx_hdr := Label.new()
	vfx_hdr.text = "=== VFX ZENKAI REALES ==="
	right_vb.add_child(vfx_hdr)

	_add_anim_btn(right_vb, "Toggle Aura ON/OFF", func() -> void:
		_state_aura_on = not _state_aura_on
		_set_status("Aura Zenkai: " + ("ON" if _state_aura_on else "OFF"))
	)
	_add_anim_btn(right_vb, "Toggle Bio-Rayos 4x4", func() -> void:
		_state_lightning = not _state_lightning
		_set_status("Bio-Rayos 4x4: " + ("ON" if _state_lightning else "OFF"))
	)
	_add_anim_btn(right_vb, "Orbe Ki Blast (Dorado)", func() -> void:
		_spawn_orb_vfx(Vector3(0.0, 1.25, 0.85), 0.22, Color(1.0, 0.65, 0.1, 0.95), false, false)
		_set_status("VFX: Ki Blast Zenkai")
	)
	_add_anim_btn(right_vb, "Orbe Cargado + Rayos", func() -> void:
		_spawn_orb_vfx(Vector3(0.0, 1.25, 0.95), 0.42, _current_color, true, true)
		_set_status("VFX: Orbe Super Zenkai + Rayos")
	)
	_add_anim_btn(right_vb, "Super Beam Azul", func() -> void:
		_spawn_beam_vfx(Color(0.15, 0.68, 1.0, 0.95), 0.40)
		_set_status("VFX: Super Beam Kamehameha")
	)
	_add_anim_btn(right_vb, "Super Beam Púrpura", func() -> void:
		_spawn_beam_vfx(Color(0.75, 0.18, 1.0, 0.95), 0.40)
		_set_status("VFX: Super Beam Galick Gun")
	)
	_add_anim_btn(right_vb, "Super Beam Dorado", func() -> void:
		_spawn_beam_vfx(Color(1.0, 0.88, 0.15, 0.95), 0.46)
		_set_status("VFX: Super Beam Final Flash")
	)
	_add_anim_btn(right_vb, "Impacto / Flash Zenkai", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_impact_flash(get_tree(), Vector3(0.0, 1.25, 1.4), _current_color, 1.6)
		_set_status("VFX: Impacto Flash + Chispas + Anillo")
	)
	_add_anim_btn(right_vb, "Explosión T2 (Fuego 4x4)", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), Vector3(0.0, 1.1, 2.2), 2, Color(1.0, 0.55, 0.12, 1.0), false)
		_set_status("VFX: Explosión Tier 2 (Fuego 4x4)")
	)
	_add_anim_btn(right_vb, "Explosión T4 (Azul 4x4)", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), Vector3(0.0, 1.2, 3.2), 4, Color(0.15, 0.68, 1.0, 1.0), true)
		_set_status("VFX: Explosión Tier 4 Azul + Rocas 4x4")
	)
	_add_anim_btn(right_vb, "Explosión T4 (Púrpura 4x4)", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), Vector3(0.0, 1.2, 3.2), 4, Color(0.75, 0.18, 1.0, 1.0), true)
		_set_status("VFX: Explosión Tier 4 Púrpura + Rocas 4x4")
	)
	_add_anim_btn(right_vb, "Explosión T5 (Zenkai Pilar)", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_explosion(get_tree(), Vector3(0.0, 0.6, 4.5), 5, _current_color, true)
		_set_status("VFX: Explosión Tier 5 Definitiva")
	)
	_add_anim_btn(right_vb, "Humo Anime 4x4", func() -> void:
		KiSmokeFX.spawn_smoke(get_tree(), Vector3(0.0, 0.6, 1.8), 1.45)
		_set_status("VFX: Humo Anime 4x4 Zenkai")
	)
	_add_anim_btn(right_vb, "Cráter Grietas Zenkai", func() -> void:
		ZenkaiVFXManager.spawn_zenkai_crater_decal(get_tree(), Vector3(0.0, 0.04, 1.8), 1.8, _current_color)
		_set_status("VFX: Cráter Grietas Zenkai")
	)
	_add_anim_btn(right_vb, "Limpiar VFX Activos", func() -> void:
		_clear_vfx()
		_set_status("VFX limpiados")
	)
	canvas.add_child(right_panel)


func _add_cal_toggle(parent: HBoxContainer, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: cb.call(btn))
	parent.add_child(btn)


func _add_grid_btn(parent: GridContainer, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _add_axis_slider(parent: VBoxContainer, axis_name: String, cb: Callable) -> Array:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.text = "%s:   +0°" % axis_name
	lbl.custom_minimum_size = Vector2(72, 20)
	hb.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = -180.0
	sl.max_value = 180.0
	sl.step = 5.0
	sl.value = 0.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(cb)
	hb.add_child(sl)
	return [lbl, sl]


func _add_anim_btn(parent: VBoxContainer, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _reset_anim_flags() -> void:
	if _anim_mode == 2:
		_anim_mode = 1
		if _mode_btn:
			_mode_btn.text = "Modo: 1 SPA Puro (Debug)"
	_state_charging_ki = false
	_state_blocking = false
	_state_flying = false
	if _fighter and _fighter.procedural_animator:
		_fighter.procedural_animator.set_super_pose("", 0)
		_fighter.procedural_animator.set_ki_recharge_phase(0)


func _clear_vfx() -> void:
	if _active_beam_node and is_instance_valid(_active_beam_node):
		_active_beam_node.queue_free()
		_active_beam_node = null
	if _active_orb_node and is_instance_valid(_active_orb_node):
		_active_orb_node.queue_free()
		_active_orb_node = null


func _spawn_orb_vfx(pos: Vector3, radius: float, col: Color, is_super: bool, has_lightning: bool) -> void:
	if _active_orb_node and is_instance_valid(_active_orb_node):
		_active_orb_node.queue_free()
	_active_orb_node = ZenkaiVFXManager.build_zenkai_orb_visual(_vfx_root, radius, col, is_super, has_lightning)
	_active_orb_node.position = pos


func _spawn_beam_vfx(col: Color, radius: float) -> void:
	if _active_beam_node and is_instance_valid(_active_beam_node):
		_active_beam_node.queue_free()

	var root := Node3D.new()
	root.name = "ShowcaseSuperBeam"
	root.position = Vector3(0.0, 1.22, 0.55)
	_vfx_root.add_child(root)
	_active_beam_node = root

	var beam_len: float = 8.5
	var core_mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = beam_len
	cyl.radial_segments = 16
	core_mi.mesh = cyl
	core_mi.rotation_degrees.x = 90.0
	core_mi.position = Vector3(0.0, 0.0, beam_len * 0.5)

	var mat_beam := ShaderMaterial.new()
	mat_beam.shader = KiBeamShader
	var beam_tex: Texture2D = ZenkaiVFXManager.get_tex("beam_core")
	var flame_tex: Texture2D = ZenkaiVFXManager.get_tex("aura_streaks")
	if beam_tex:
		mat_beam.set_shader_parameter("streak_tex", beam_tex)
	if flame_tex:
		mat_beam.set_shader_parameter("flame_tex", flame_tex)
	mat_beam.set_shader_parameter("beam_color", col)
	mat_beam.set_shader_parameter("core_color", Color.WHITE)
	mat_beam.set_shader_parameter("flow_speed", 15.0)
	mat_beam.set_shader_parameter("core_intensity", 4.6)
	core_mi.material_override = mat_beam
	root.add_child(core_mi)

	var sheath_mi := MeshInstance3D.new()
	var cyl_s := CylinderMesh.new()
	cyl_s.top_radius = radius * 1.48
	cyl_s.bottom_radius = radius * 1.48
	cyl_s.height = beam_len
	cyl_s.radial_segments = 16
	cyl_s.cap_top = false
	cyl_s.cap_bottom = false
	sheath_mi.mesh = cyl_s
	sheath_mi.rotation_degrees.x = 90.0
	sheath_mi.position = Vector3(0.0, 0.0, beam_len * 0.5)
	var mat_s := ShaderMaterial.new()
	mat_s.shader = ZenkaiAuraShader
	if flame_tex:
		mat_s.set_shader_parameter("flame_tex", flame_tex)
	if ZenkaiVFXManager.get_band_tex():
		mat_s.set_shader_parameter("band_tex", ZenkaiVFXManager.get_band_tex())
	mat_s.set_shader_parameter("base_color", Color(col.r, col.g, col.b, 0.72))
	mat_s.set_shader_parameter("speed", 11.5)
	mat_s.set_shader_parameter("has_bio_lightning", 1.0)
	sheath_mi.material_override = mat_s
	root.add_child(sheath_mi)

	var nozzle := ZenkaiVFXManager.build_zenkai_orb_visual(root, radius * 1.35, col, true, true)
	nozzle.position = Vector3.ZERO
	var head := ZenkaiVFXManager.build_zenkai_orb_visual(root, radius * 1.5, col, true, true)
	head.position = Vector3(0.0, 0.0, beam_len)
