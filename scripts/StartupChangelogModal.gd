extends Node3D
class_name StartupChangelogModal

## Ventana modal diegética 3D al inicio del juego con los últimos cambios aplicados.
## Pausa el árbol de escena hasta que el jugador la cierra con Trigger / A / B, iniciando el combate.

var viewport: SubViewport = null
var panel_mesh: MeshInstance3D = null

var _left_ctrl: XRController3D = null
var _right_ctrl: XRController3D = null
var _camera: Camera3D = null

var _input_grace_timer: float = 0.55
var _prev_pressed: bool = true
var _is_closing: bool = false


static func spawn_if_needed(tree: SceneTree, cam: Camera3D, l_ctrl: XRController3D, r_ctrl: XRController3D) -> Node3D:
	if not tree:
		return null
	var root_scene: Node = tree.current_scene if tree.current_scene else tree.root
	if not root_scene:
		return null
	if root_scene.has_meta("startup_changelog_shown"):
		return null
	root_scene.set_meta("startup_changelog_shown", true)

	var modal_script: Script = load("res://scripts/StartupChangelogModal.gd") as Script
	var modal: Node3D = modal_script.new() as Node3D
	modal.name = "StartupChangelogModal"
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	root_scene.add_child.call_deferred(modal)
	modal.call_deferred("setup", cam, l_ctrl, r_ctrl)
	return modal


func setup(cam: Camera3D, l_ctrl: XRController3D, r_ctrl: XRController3D) -> void:
	_camera = cam
	_left_ctrl = l_ctrl
	_right_ctrl = r_ctrl
	if not _camera and get_viewport():
		_camera = get_viewport().get_camera_3d()

	_build_ui()
	_position_in_front_of_camera()
	if get_tree():
		get_tree().paused = true


func _build_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 660)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root_ctrl)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.12, 0.95)
	style.border_width_left = 5
	style.border_width_top = 5
	style.border_width_right = 5
	style.border_width_bottom = 5
	style.border_color = Color(1.0, 0.84, 0.2, 0.98)
	style.set_corner_radius_all(22)
	style.set_content_margin_all(28)
	bg.add_theme_stylebox_override("panel", style)
	root_ctrl.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	bg.add_child(vbox)

	var title := Label.new()
	title.text = "⚡ DBZVR · ÚLTIMOS CAMBIOS APLICADOS ⚡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t_set := LabelSettings.new()
	t_set.font_size = 32
	t_set.font_color = Color(1.0, 0.86, 0.2)
	t_set.outline_size = 4
	t_set.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	title.label_settings = t_set
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Rama: feature/chain-sequences-and-beam-clash · Fase 1 (Secuencias Ki & Beam Clash)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s_set := LabelSettings.new()
	s_set.font_size = 18
	s_set.font_color = Color(0.25, 0.92, 1.0)
	subtitle.label_settings = s_set
	vbox.add_child(subtitle)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_font_size_override("bold_font_size", 21)
	body.text = (
		"[color=#eaf4ff]"
		+ "• [b][color=#ffd43b]Cadenas por Ki (chain_depth):[/color][/b] cada eslabón suma +35% costo de Ki (x1.0 → x1.35 → x1.70).\n\n"
		+ "• [b][color=#ffd43b]Meteor Chase Aéreo (12 Ki × escala):[/color][/b] tras lanzar al rival en Melee, lanza un puñetazo al frente durante los 4.0 s de Follow-Up para abrir otra Cúpula Melee aérea.\n\n"
		+ "• [b][color=#00e5ff]Persecución Post-Super (3.0 s · mín. 15 Ki):[/color][/b] al impactar un Súper sin K.O., puedes encadenar Ki Blasts sobre el humo o un Meteor Chase.\n\n"
		+ "• [b][color=#ff6b6b]Onda Expansiva (22 Ki · Botón B / Y):[/color][/b] corta la cadena aérea/post-super del rival.\n\n"
		+ "• [b][color=#c75bff]Beam Clash Anime:[/color][/b] la IA ya NO lanza Ki Blasts durante el choque; el haz avanza hasta 0.0 / 1.0 e impacta al instante si alguien llega a 0 Ki o desiste (0.40 s)."
		+ "[/color]"
	)
	vbox.add_child(body)

	var btn_panel := PanelContainer.new()
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.35, 0.55, 0.95)
	btn_style.border_width_left = 3
	btn_style.border_width_top = 3
	btn_style.border_width_right = 3
	btn_style.border_width_bottom = 3
	btn_style.border_color = Color(0.2, 0.95, 1.0, 1.0)
	btn_style.set_corner_radius_all(12)
	btn_style.set_content_margin_all(14)
	btn_panel.add_theme_stylebox_override("panel", btn_style)
	vbox.add_child(btn_panel)

	var btn_lbl := Label.new()
	btn_lbl.text = "▶ PULSA TRIGGER / A / B PARA CERRAR E INICIAR COMBATE"
	btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b_set := LabelSettings.new()
	b_set.font_size = 24
	b_set.font_color = Color(1.0, 1.0, 1.0)
	btn_lbl.label_settings = b_set
	btn_panel.add_child(btn_lbl)

	panel_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.42, 0.98)
	panel_mesh.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 120
	mat.albedo_texture = viewport.get_texture()
	panel_mesh.material_override = mat
	add_child(panel_mesh)


func _position_in_front_of_camera() -> void:
	if not _camera or not is_instance_valid(_camera):
		global_position = Vector3(0.0, 1.45, -1.35)
		return
	var fwd: Vector3 = -_camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	global_position = _camera.global_position + fwd * 1.38 + Vector3(0.0, -0.04, 0.0)
	look_at(_camera.global_position, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)


func _process(delta: float) -> void:
	if _is_closing:
		return
	_position_in_front_of_camera()

	if _input_grace_timer > 0.0:
		_input_grace_timer -= delta
		_prev_pressed = _is_any_confirm_pressed()
		return

	var pressed: bool = _is_any_confirm_pressed()
	if pressed and not _prev_pressed:
		_close_and_start()
	_prev_pressed = pressed


func _is_any_confirm_pressed() -> bool:
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER):
		return true
	for ctrl in [_left_ctrl, _right_ctrl]:
		if ctrl and is_instance_valid(ctrl):
			if ctrl.is_button_pressed("trigger_click") or ctrl.is_button_pressed("ax_button") or ctrl.is_button_pressed("by_button"):
				return true
			if ctrl.get_float("trigger") > 0.72:
				return true
	return false


func _close_and_start() -> void:
	_is_closing = true
	if get_tree():
		get_tree().paused = false
	queue_free()
