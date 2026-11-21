extends Node3D
class_name MatchResultScreen
## Pantalla diegética 3D de Victoria / Derrota tras un K.O. Zenkai o Agotamiento Vital.
## Punto 1 del playtest: permite ver el resultado y pulsar A / Trigger para volver a jugar.

var viewport: SubViewport = null
var panel_mesh: MeshInstance3D = null

var _btn_rematch_panel: Panel = null
var _btn_menu_panel: Panel = null
var _selected_index: int = 0 # 0 = Revancha, 1 = Menú
var _prev_confirm: bool = true # Arranca true para exigir soltar botón antes de confirmar
var _prev_stick_dir: int = 0
var _input_grace_timer: float = 0.65

var _left_ctrl: XRController3D = null
var _right_ctrl: XRController3D = null
var _camera: Camera3D = null


static func spawn_result_screen(tree: SceneTree, winner: Node3D, loser: Node3D, tech_name: String, player_char: Node3D) -> MatchResultScreen:
	if not tree:
		return null
	var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
	if not parent_node:
		return null
	# Evitar duplicados si ambos combatientes emiten match_finished
	var existing: Node = parent_node.get_node_or_null("MatchResultScreen")
	if existing and is_instance_valid(existing):
		return existing as MatchResultScreen

	var screen := MatchResultScreen.new()
	screen.name = "MatchResultScreen"
	parent_node.add_child(screen)
	screen.setup(winner, loser, tech_name, player_char)
	return screen


func setup(winner: Node3D, loser: Node3D, tech_name: String, player_char: Node3D) -> void:
	var scene: Node = get_tree().current_scene
	if scene:
		_left_ctrl = scene.find_child("LeftHand", true, false) as XRController3D
		_right_ctrl = scene.find_child("RightHand", true, false) as XRController3D
	_camera = get_viewport().get_camera_3d() if get_viewport() else null

	var winner_is_player: bool = (winner != null and is_instance_valid(winner) and bool(winner.get("is_player")))
	var w_name: String = "GUERRERO"
	if winner and is_instance_valid(winner):
		var wd: Variant = winner.get("character_data")
		w_name = wd.character_name if (wd and "character_name" in wd) else winner.name

	var p_bp: int = 0
	var e_bp: int = 0
	if player_char and is_instance_valid(player_char) and player_char.get("current_np") != null:
		p_bp = int(roundf(float(player_char.get("current_np"))))
	var opp_node: Node3D = loser if winner_is_player else winner
	if opp_node and is_instance_valid(opp_node) and opp_node.get("current_np") != null:
		e_bp = int(roundf(float(opp_node.get("current_np"))))

	_build_ui(winner_is_player, w_name, tech_name, p_bp, e_bp)
	_position_in_front_of_camera()


func _build_ui(is_victory: bool, winner_name: String, tech_name: String, p_bp: int, e_bp: int) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(760, 520)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root_ctrl)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.11, 0.94)
	style.border_width_left = 6
	style.border_width_top = 6
	style.border_width_right = 6
	style.border_width_bottom = 6
	style.border_color = Color(1.0, 0.82, 0.15, 1.0) if is_victory else Color(1.0, 0.22, 0.25, 1.0)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	bg.add_theme_stylebox_override("panel", style)
	root_ctrl.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 18)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	bg.add_child(margin)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.text = "🏆 ¡VICTORIA! 🏆" if is_victory else "💀 DERROTA 💀"
	title_lbl.add_theme_font_size_override("font_size", 54)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.18) if is_victory else Color(1.0, 0.26, 0.28))
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.text = "GANADOR: %s\nTécnica Final: %s" % [winner_name.to_upper(), tech_name.to_upper()]
	sub_lbl.add_theme_font_size_override("font_size", 26)
	sub_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	vbox.add_child(sub_lbl)

	var stats_lbl := Label.new()
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.text = "Tu BP Final: %s   |   Rival BP Final: %s" % [_fmt_num(p_bp), _fmt_num(e_bp)]
	stats_lbl.add_theme_font_size_override("font_size", 22)
	stats_lbl.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	vbox.add_child(stats_lbl)

	_btn_rematch_panel = _make_button_panel("▶ VOLVER A JUGAR (REVANCHA)")
	vbox.add_child(_btn_rematch_panel)

	_btn_menu_panel = _make_button_panel("☰ ABRIR MENÚ (CAMBIAR PERSONAJE)")
	vbox.add_child(_btn_menu_panel)

	var hint_lbl := Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.text = "Usa Joystick ↑/↓ para elegir · Pulsa [A] o [Trigger] para confirmar"
	hint_lbl.add_theme_font_size_override("font_size", 18)
	hint_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	vbox.add_child(hint_lbl)

	_refresh_button_styles()

	panel_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.22, 0.84)
	panel_mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 125
	mat.albedo_texture = viewport.get_texture()
	panel_mesh.material_override = mat
	add_child(panel_mesh)


func _make_button_panel(label_text: String) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 62)
	var st := StyleBoxFlat.new()
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.border_width_left = 3
	st.border_width_top = 3
	st.border_width_right = 3
	st.border_width_bottom = 3
	p.add_theme_stylebox_override("panel", st)

	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 26)
	p.add_child(lbl)
	return p


func _refresh_button_styles() -> void:
	var panels: Array[Panel] = [_btn_rematch_panel, _btn_menu_panel]
	for i in range(panels.size()):
		var p: Panel = panels[i]
		if not p:
			continue
		var st: StyleBoxFlat = p.get_theme_stylebox("panel") as StyleBoxFlat
		var selected: bool = (i == _selected_index)
		if st:
			st.bg_color = Color(0.18, 0.55, 0.88, 0.95) if selected else Color(0.08, 0.12, 0.20, 0.85)
			st.border_color = Color(1.0, 0.88, 0.2, 1.0) if selected else Color(0.30, 0.40, 0.55, 0.7)
	if viewport and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _position_in_front_of_camera() -> void:
	if not _camera or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() if get_viewport() else null
	if _camera and is_instance_valid(_camera):
		var fwd: Vector3 = -_camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
		global_position = _camera.global_position + fwd * 1.65 + Vector3(0.0, 0.05, 0.0)
		look_at(_camera.global_position, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)


func _process(delta: float) -> void:
	if _input_grace_timer > 0.0:
		_input_grace_timer -= delta
		return

	var stick_y: float = 0.0
	var confirm_pressed: bool = Input.is_action_just_pressed("ui_accept")

	for ctrl in [_left_ctrl, _right_ctrl]:
		if ctrl and is_instance_valid(ctrl):
			var stick: Vector2 = ctrl.get_vector2("primary")
			if absf(stick.y) > absf(stick_y):
				stick_y = stick.y
			if ctrl.is_button_pressed("ax_button") or ctrl.get_float("trigger") > 0.75:
				confirm_pressed = true

	var stick_dir: int = 1 if stick_y > 0.55 else (-1 if stick_y < -0.55 else 0)
	if stick_dir != 0 and stick_dir != _prev_stick_dir:
		_selected_index = 1 - _selected_index
		_refresh_button_styles()
	_prev_stick_dir = stick_dir

	if confirm_pressed and not _prev_confirm:
		_execute_selected()
	_prev_confirm = confirm_pressed


func _execute_selected() -> void:
	if _selected_index == 0:
		get_tree().reload_current_scene()
	else:
		var menu: Node = get_tree().current_scene.find_child("VRInGameMenu", true, false) if get_tree().current_scene else null
		queue_free()
		if menu and menu.has_method("toggle_menu"):
			menu.toggle_menu()


func _fmt_num(n: int) -> String:
	var s: String = str(abs(n))
	var res: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		c += 1
		if c == 3 and i > 0:
			res = "," + res
			c = 0
	return ("-" + res) if n < 0 else res
