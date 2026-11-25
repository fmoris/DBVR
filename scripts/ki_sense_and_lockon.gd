class_name KiSenseAndLockOn
extends Node3D

## KiSenseAndLockOn (Dragon Ball VR)
## Gestiona:
## 1. Rastro y brújula de Ki (Ki Sense Pointer): Si el oponente sale del campo de visión (arriba, atrás, etc.),
##    muestra una flecha periférica animada indicando su posición 3D exacta y distancia en metros.
## 2. Fijación de objetivo por mirada (Gaze Lock-On): Al mirar de frente al oponente durante 1.3 segundos,
##    fija al rival (is_target_locked = true), desplegando una retícula anime y habilitando el Melee Dash.

signal target_locked_state_changed(is_locked: bool)

var camera: XRCamera3D = null
var player_instance: Node3D = null
var opponent_instance: Node3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null

var is_target_locked: bool = false
var gaze_charge_timer: float = 0.0
const REQUIRED_GAZE_TIME: float = 1.3
var lock_loss_timer: float = 0.0
const LOCK_LOSS_TIMEOUT: float = 3.5

# Componentes visuales
var lockon_reticle_root: Node3D = null
var reticle_ring: MeshInstance3D = null
var reticle_icon: MeshInstance3D = null
var _reticle_icon_mat: StandardMaterial3D = null
var reticle_label: Label3D = null
var _tex_target_normal: Texture2D = null
var _tex_target_fight: Texture2D = null

var ki_pointer_root: Node3D = null
var pointer_label: Label3D = null
var pointer_arrow_mesh: MeshInstance3D = null

var alert_banner_root: Node3D = null
var alert_title_label: Label3D = null
var alert_sub_label: Label3D = null
var alert_bg_mat: StandardMaterial3D = null
var _alert_timer: float = 0.0
var _alert_duration: float = 2.4
var _alert_tween: Tween = null
var _alert_color: Color = Color(1.0, 0.85, 0.15)
var _prev_player_zenkai: bool = false
var _prev_opp_charging_super: bool = false
var _prev_opp_zenkai_attack: bool = false
var _prev_opp_opened: bool = false
var _prev_opp_crater: bool = false
var _zenkai_reminder_timer: float = 0.0
var _connected_player_id: int = 0
var _connected_opp_id: int = 0

var audio_player: AudioStreamPlayer3D = null
var sfx_locked: AudioStream = null

func _ready() -> void:
	_build_lockon_reticle()
	_build_ki_pointer()
	_build_scouter_alert_banner()
	_setup_audio()


func setup(p_cam: XRCamera3D, p_player: Node3D, p_opp: Node3D, p_left: XRController3D, p_right: XRController3D) -> void:
	camera = p_cam
	player_instance = p_player
	opponent_instance = p_opp
	left_controller = p_left
	right_controller = p_right
	_bind_combat_alerts()


func _setup_audio() -> void:
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "LockOnAudio"
	audio_player.unit_size = 3.0
	audio_player.max_distance = 15.0
	add_child(audio_player)
	sfx_locked = null


func _build_lockon_reticle() -> void:
	lockon_reticle_root = Node3D.new()
	lockon_reticle_root.name = "LockOnReticle"
	add_child(lockon_reticle_root)
	lockon_reticle_root.visible = false

	# 1. Anillo exterior holográfico
	reticle_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.25
	torus.rings = 24
	torus.ring_segments = 16
	reticle_ring.mesh = torus
	reticle_ring.rotation_degrees.x = 90.0

	var mat_ring = StandardMaterial3D.new()
	mat_ring.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat_ring.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat_ring.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_ring.albedo_color = Color(0.2, 0.85, 1.0, 0.85)
	mat_ring.no_depth_test = true # Visible a través de proyectiles de Ki y efectos
	reticle_ring.material_override = mat_ring
	lockon_reticle_root.add_child(reticle_ring)

	# 2. Retícula oficial Zenkai Target (target_normal -> target_fight, sin texto flotante)
	if ResourceLoader.exists("res://assets/ui_zenkai/target_normal.png"):
		_tex_target_normal = ResourceLoader.load("res://assets/ui_zenkai/target_normal.png") as Texture2D
	if ResourceLoader.exists("res://assets/ui_zenkai/target_fight.png"):
		_tex_target_fight = ResourceLoader.load("res://assets/ui_zenkai/target_fight.png") as Texture2D
	if _tex_target_normal != null and _tex_target_fight != null:
		reticle_ring.visible = false

	reticle_icon = MeshInstance3D.new()
	reticle_icon.name = "ScouterLockOnIcon"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.56, 0.56)
	reticle_icon.mesh = quad
	_reticle_icon_mat = StandardMaterial3D.new()
	_reticle_icon_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	_reticle_icon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if _tex_target_fight != null else BaseMaterial3D.BLEND_MODE_ADD
	_reticle_icon_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_reticle_icon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_reticle_icon_mat.no_depth_test = true
	_reticle_icon_mat.render_priority = 115
	_reticle_icon_mat.albedo_texture = _tex_target_fight if _tex_target_fight != null else _create_scouter_lock_icon_texture()
	_reticle_icon_mat.albedo_color = Color(1.0, 0.95, 0.95, 0.96) if _tex_target_fight != null else Color(1.0, 0.90, 0.22, 0.95)
	reticle_icon.material_override = _reticle_icon_mat
	reticle_icon.visible = false
	lockon_reticle_root.add_child(reticle_icon)


func _create_scouter_lock_icon_texture() -> ImageTexture:
	var sz: int = 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(1.0, 1.0, 1.0, 1.0)
	var m: int = 6
	var arm: int = 14
	var t: int = 3
	# 4 esquinas Scouter
	for i in range(arm):
		for w in range(t):
			img.set_pixel(m + i, m + w, col)
			img.set_pixel(m + w, m + i, col)
			img.set_pixel(sz - 1 - m - i, m + w, col)
			img.set_pixel(sz - 1 - m - w, m + i, col)
			img.set_pixel(m + i, sz - 1 - m - w, col)
			img.set_pixel(m + w, sz - 1 - m - i, col)
			img.set_pixel(sz - 1 - m - i, sz - 1 - m - w, col)
			img.set_pixel(sz - 1 - m - w, sz - 1 - m - i, col)
	# Rombo central
	var c: int = sz / 2
	var r: int = 10
	for d in range(-r, r + 1):
		var y_off: int = r - abs(d)
		for k in range(-1, 2):
			img.set_pixel(c + d, c + y_off + k, col)
			img.set_pixel(c + d, c - y_off + k, col)
	return ImageTexture.create_from_image(img)


func _build_ki_pointer() -> void:
	ki_pointer_root = Node3D.new()
	ki_pointer_root.name = "KiSensePointer"
	add_child(ki_pointer_root)
	ki_pointer_root.visible = false

	# Flecha anime 3D de Ki
	pointer_arrow_mesh = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.08, 0.12, 0.04)
	pointer_arrow_mesh.mesh = prism
	pointer_arrow_mesh.rotation_degrees.z = -90.0

	var mat_arrow = StandardMaterial3D.new()
	mat_arrow.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat_arrow.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat_arrow.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_arrow.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
	mat_arrow.no_depth_test = true
	pointer_arrow_mesh.material_override = mat_arrow
	ki_pointer_root.add_child(pointer_arrow_mesh)

	# Etiqueta de distancia y rastreo de Ki
	pointer_label = Label3D.new()
	pointer_label.text = "⚡ KI: 15.0m ⚡"
	pointer_label.font_size = 20
	pointer_label.pixel_size = 0.0016
	pointer_label.outline_size = 6
	pointer_label.modulate = Color(1.0, 0.9, 0.2)
	pointer_label.outline_modulate = Color.BLACK
	pointer_label.no_depth_test = true
	pointer_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pointer_label.position = Vector3(0.0, -0.09, 0.0)
	ki_pointer_root.add_child(pointer_label)


func _process(delta: float) -> void:
	if not camera or not opponent_instance or not is_instance_valid(camera) or not is_instance_valid(opponent_instance):
		_ensure_references()
		if not camera or not opponent_instance:
			return

	if player_instance and is_instance_valid(player_instance):
		if bool(player_instance.get("is_in_bullet_time")) or bool(player_instance.get("is_in_beam_sequence")) or bool(player_instance.get("is_in_beam_clash")):
			if lockon_reticle_root:
				lockon_reticle_root.visible = false
			if ki_pointer_root:
				ki_pointer_root.visible = false
			return

	var cam_pos = camera.global_position
	var opp_chest = opponent_instance.global_position + Vector3(0.0, 1.15, 0.0)
	var to_opp = opp_chest - cam_pos
	var dist_to_opp = to_opp.length()
	var dir_to_opp = to_opp.normalized() if dist_to_opp > 0.01 else Vector3.FORWARD

	var cam_fwd = -camera.global_transform.basis.z.normalized()
	var dot_gaze = clampf(cam_fwd.dot(dir_to_opp), -1.0, 1.0)
	var angle_deg = rad_to_deg(acos(dot_gaze))

	# 1. ACTUALIZAR FIJACIÓN POR MIRADA (Gaze Lock-On)
	var is_looking_at_rival = (angle_deg <= 22.0)

	if is_looking_at_rival:
		lock_loss_timer = 0.0
		if not is_target_locked:
			gaze_charge_timer += delta
			var progress = clampf(gaze_charge_timer / REQUIRED_GAZE_TIME, 0.0, 1.0)
			_show_reticle_charging(opp_chest, progress)

			if gaze_charge_timer >= REQUIRED_GAZE_TIME:
				_lock_target()
		else:
			_show_reticle_locked(opp_chest)
	else:
		if is_target_locked:
			lock_loss_timer += delta
			_show_reticle_locked(opp_chest)
			if lock_loss_timer >= LOCK_LOSS_TIMEOUT:
				_unlock_target("Pérdida de fijación por desviación de mirada")
		else:
			gaze_charge_timer = maxf(0.0, gaze_charge_timer - delta * 2.0)
			if gaze_charge_timer <= 0.0:
				lockon_reticle_root.visible = false

	# 2. ACTUALIZAR BRÚJULA DE KI PERIFÉRICA (Ki Sense Pointer)
	# Si el oponente está fuera del cono central (> 32 grados o detrás), proyectar puntero periférico
	if angle_deg > 28.0 or dot_gaze < 0.2:
		_update_peripheral_ki_pointer(cam_pos, opp_chest, dist_to_opp)
	else:
		ki_pointer_root.visible = false

	# 3. ALERTAS TÁCTICAS DE COMBATE Y BANNER PERIFÉRICO
	_poll_combat_alerts(delta)


func _fmt_bp(n: int) -> String:
	var s: String = str(abs(n))
	var res: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count == 3 and i > 0:
			res = "," + res
			count = 0
	return ("-" + res) if n < 0 else res


func _get_comparative_bp_line() -> String:
	var p_bp: int = int(player_instance.current_np) if (player_instance and is_instance_valid(player_instance) and player_instance.get("current_np") != null) else 0
	var e_bp: int = int(opponent_instance.current_np) if (opponent_instance and is_instance_valid(opponent_instance) and opponent_instance.get("current_np") != null) else 0
	var p_mult: float = player_instance.get_transformation_multiplier() if (player_instance and is_instance_valid(player_instance) and player_instance.has_method("get_transformation_multiplier")) else 1.0
	var e_mult: float = opponent_instance.get_transformation_multiplier() if (opponent_instance and is_instance_valid(opponent_instance) and opponent_instance.has_method("get_transformation_multiplier")) else 1.0
	var p_tag: String = (" (x%.1f)" % p_mult) if p_mult > 1.01 else ""
	var e_tag: String = (" (x%.1f)" % e_mult) if e_mult > 1.01 else ""
	var diff: int = p_bp - e_bp
	var status_tag: String = "VENTAJA" if diff >= 0 else "DESVENTAJA"
	var sign_d: String = "+" if diff >= 0 else ""
	return "TU BP: %s%s vs RIVAL: %s%s [%s %s%s]" % [_fmt_bp(p_bp), p_tag, _fmt_bp(e_bp), e_tag, status_tag, sign_d, _fmt_bp(diff)]


func _show_reticle_charging(pos: Vector3, progress: float) -> void:
	lockon_reticle_root.visible = true
	lockon_reticle_root.global_position = pos

	var scale_factor = lerpf(1.45, 1.0, progress)
	lockon_reticle_root.scale = Vector3.ONE * scale_factor

	if _tex_target_normal != null and reticle_icon and _reticle_icon_mat:
		reticle_ring.visible = false
		reticle_icon.visible = true
		_reticle_icon_mat.albedo_texture = _tex_target_normal
		_reticle_icon_mat.albedo_color = Color(0.85, 1.0, 0.90, 0.50 + progress * 0.48)
		reticle_icon.scale = Vector3.ONE
		reticle_icon.rotation.z = progress * 1.2
		return

	var mat = reticle_ring.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.2, 0.85, 1.0, 0.5 + progress * 0.45)

	if reticle_icon:
		reticle_icon.visible = false


func _show_reticle_locked(pos: Vector3) -> void:
	lockon_reticle_root.visible = true
	lockon_reticle_root.global_position = pos
	lockon_reticle_root.scale = Vector3.ONE

	var opp_crater_v: Variant = opponent_instance.get("ground_crater_stun_timer") if (opponent_instance != null and is_instance_valid(opponent_instance)) else null
	var is_opp_crater: bool = opp_crater_v != null and float(opp_crater_v) > 0.0
	var opp_open_v: Variant = opponent_instance.get("blast_opened_timer") if (opponent_instance != null and is_instance_valid(opponent_instance)) else null
	var is_opp_opened: bool = opp_open_v != null and float(opp_open_v) > 0.0

	if _tex_target_fight != null and reticle_icon and _reticle_icon_mat:
		reticle_ring.visible = false
		reticle_icon.visible = true
		_reticle_icon_mat.albedo_texture = _tex_target_fight
		if is_opp_crater:
			var cpulse_tex: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.018)
			_reticle_icon_mat.albedo_color = Color(1.0, 0.35 * cpulse_tex + 0.20, 1.0, 0.98)
		elif is_opp_opened:
			_reticle_icon_mat.albedo_color = Color(1.0, 0.80, 0.25, 0.98)
		else:
			_reticle_icon_mat.albedo_color = Color(1.0, 0.95, 0.95, 0.98)
		var pulse_t: float = 1.0 + sin(Time.get_ticks_msec() * 0.010) * 0.07
		reticle_icon.scale = Vector3(pulse_t, pulse_t, pulse_t)
		return

	var mat = reticle_ring.material_override as StandardMaterial3D
	if mat:
		if is_opp_crater:
			var cpulse: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.018)
			mat.albedo_color = Color(0.95, 0.25 * cpulse + 0.15, 1.0, 0.98)
		else:
			mat.albedo_color = Color(1.0, 0.38, 0.10, 0.98) if is_opp_opened else Color(1.0, 0.88, 0.15, 0.95)

	if reticle_icon:
		reticle_icon.visible = true
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.08
		reticle_icon.scale = Vector3(pulse, pulse, pulse)


func _lock_target() -> void:
	is_target_locked = true
	if player_instance:
		player_instance.set("is_target_locked", true)

	# Audio y hápticos
	if audio_player and sfx_locked:
		audio_player.global_position = lockon_reticle_root.global_position
		audio_player.stream = sfx_locked
		audio_player.pitch_scale = 1.35
		audio_player.play()

	if right_controller and right_controller.has_method("trigger_haptic_pulse"):
		right_controller.trigger_haptic_pulse("haptic", 180.0, 0.75, 0.18, 0.0)
	if left_controller and left_controller.has_method("trigger_haptic_pulse"):
		left_controller.trigger_haptic_pulse("haptic", 180.0, 0.75, 0.18, 0.0)

	emit_signal("target_locked_state_changed", true)
	print("[KiSenseAndLockOn] 🎯 ¡Objetivo fijado con éxito! Melee Dash habilitado.")


func _unlock_target(reason: String) -> void:
	is_target_locked = false
	gaze_charge_timer = 0.0
	lock_loss_timer = 0.0
	lockon_reticle_root.visible = false

	if player_instance:
		player_instance.set("is_target_locked", false)

	emit_signal("target_locked_state_changed", false)
	print("[KiSenseAndLockOn] ⚠️ Fijación cancelada: %s" % reason)


func _update_peripheral_ki_pointer(cam_pos: Vector3, opp_pos: Vector3, dist_m: float) -> void:
	ki_pointer_root.visible = true

	# Transformar posición del rival al espacio local de la cámara
	var cam_basis = camera.global_transform.basis
	var local_dir = cam_basis.inverse() * (opp_pos - cam_pos).normalized()

	# Dirección 2D en el plano de la pantalla (X horizontal, Y vertical)
	var screen_dir = Vector2(local_dir.x, local_dir.y)
	if screen_dir.length_squared() < 0.001:
		screen_dir = Vector2.UP if local_dir.z > 0.0 else Vector2.DOWN
	else:
		screen_dir = screen_dir.normalized()

	# Si el rival está detrás de la cabeza (local_dir.z > 0), invertir o resaltar
	if local_dir.z > 0.0:
		screen_dir = -screen_dir

	# Posicionar el puntero en la periferia de visión cerca del jugador para lectura nítida
	var pointer_offset_local = Vector3(screen_dir.x * 0.54, screen_dir.y * 0.36, -1.20)
	ki_pointer_root.global_position = camera.global_position + (cam_basis * pointer_offset_local)

	# Orientar la flecha para que apunte en la dirección screen_dir
	var arrow_angle = atan2(screen_dir.y, screen_dir.x)
	pointer_arrow_mesh.rotation = Vector3(0.0, 0.0, arrow_angle - PI * 0.5)

	# Actualizar texto con la distancia de Ki y comparativa de BP
	var opp_name = opponent_instance.get("character_data").character_name if opponent_instance.get("character_data") else "RIVAL"
	pointer_label.text = "⚡ KI DE %s: %.1fm ⚡\n%s" % [opp_name.to_upper(), dist_m, _get_comparative_bp_line()]


func _ensure_references() -> void:
	if not camera and get_viewport():
		camera = get_viewport().get_camera_3d()
	if not opponent_instance and get_tree() and get_tree().current_scene:
		opponent_instance = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
	if not player_instance and get_tree() and get_tree().current_scene:
		player_instance = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
	_bind_combat_alerts()


func _build_scouter_alert_banner() -> void:
	alert_banner_root = Node3D.new()
	alert_banner_root.name = "ScouterAlertBanner"
	alert_banner_root.visible = false
	add_child(alert_banner_root)

	var bg_mesh := MeshInstance3D.new()
	bg_mesh.name = "AlertBackdrop"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.82, 0.16)
	bg_mesh.mesh = quad
	alert_bg_mat = StandardMaterial3D.new()
	alert_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	alert_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	alert_bg_mat.albedo_color = Color(0.03, 0.07, 0.08, 0.78)
	alert_bg_mat.no_depth_test = true
	alert_bg_mat.render_priority = 95
	bg_mesh.material_override = alert_bg_mat
	bg_mesh.position = Vector3(0.0, 0.0, -0.01)
	alert_banner_root.add_child(bg_mesh)

	alert_title_label = Label3D.new()
	alert_title_label.name = "AlertTitleLabel"
	alert_title_label.text = "⚡ ALERTA SCOUTER"
	alert_title_label.font_size = 34
	alert_title_label.pixel_size = 0.0015
	alert_title_label.outline_size = 8
	alert_title_label.modulate = _alert_color
	alert_title_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	alert_title_label.no_depth_test = true
	alert_title_label.render_priority = 96
	alert_title_label.position = Vector3(0.0, 0.028, 0.0)
	alert_banner_root.add_child(alert_title_label)

	alert_sub_label = Label3D.new()
	alert_sub_label.name = "AlertSubLabel"
	alert_sub_label.text = ""
	alert_sub_label.font_size = 20
	alert_sub_label.pixel_size = 0.0012
	alert_sub_label.outline_size = 5
	alert_sub_label.modulate = Color(0.88, 0.95, 1.0, 1.0)
	alert_sub_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	alert_sub_label.no_depth_test = true
	alert_sub_label.render_priority = 96
	alert_sub_label.position = Vector3(0.0, -0.036, 0.0)
	alert_banner_root.add_child(alert_sub_label)


func _bind_combat_alerts() -> void:
	if player_instance and is_instance_valid(player_instance):
		var pid: int = player_instance.get_instance_id()
		if pid != _connected_player_id:
			_connected_player_id = pid
			if player_instance.has_signal("transformation_unlocked") and not player_instance.transformation_unlocked.is_connected(_on_player_transformation_alert):
				player_instance.transformation_unlocked.connect(_on_player_transformation_alert)
			_prev_player_zenkai = (player_instance.get("is_in_zenkai_state") == true)

	if opponent_instance and is_instance_valid(opponent_instance):
		var oid: int = opponent_instance.get_instance_id()
		if oid != _connected_opp_id:
			_connected_opp_id = oid
			if opponent_instance.has_signal("transformation_unlocked") and not opponent_instance.transformation_unlocked.is_connected(_on_enemy_transformation_alert):
				opponent_instance.transformation_unlocked.connect(_on_enemy_transformation_alert)
			_prev_opp_charging_super = (opponent_instance.get("is_charging_super") == true)


func _on_player_transformation_alert(form_name: String) -> void:
	show_scouter_alert("⚡ ¡%s LISTO PARA ACTIVAR! ⚡" % form_name.to_upper(), "Pulsa [A / X] o mantén Puños a la Cintura (Grip+Trigger 1.2s)", Color(1.0, 0.88, 0.18), 3.8)


func _on_enemy_transformation_alert(form_name: String) -> void:
	show_scouter_alert("⚠️ ¡RIVAL TRANSFORMADO: %s!" % form_name.to_upper(), "El nivel de poder enemigo ha aumentado", Color(1.0, 0.38, 0.15), 2.6)


func _poll_combat_alerts(delta: float) -> void:
	if player_instance and is_instance_valid(player_instance):
		var z_now: bool = (player_instance.get("is_in_zenkai_state") == true)
		var z_comeback: bool = (player_instance.get("is_comeback_zenkai") == true) or String(player_instance.get("zenkai_source")) == "comeback"
		var match_over: bool = (player_instance.get("is_match_over") == true)
		var z_title: String = "⚡ ¡ZENKAI COMEBACK (1 INTENTO)! ⚡" if z_comeback else "🔥 ¡ZENKAI DOMINIO LISTO PARA K.O.! 🔥"
		var z_sub: String = "Acierta tu Super Poder ahora (fallarlo penaliza)" if z_comeback else "¡Superas al rival! Acierta un Super Poder para el K.O."
		var z_col: Color = Color(1.0, 0.65, 0.12) if z_comeback else Color(1.0, 0.85, 0.12)
		if z_now and not _prev_player_zenkai and not match_over:
			show_scouter_alert(z_title, z_sub, z_col, 3.4)
			_zenkai_reminder_timer = 0.0
		elif z_now and not match_over:
			_zenkai_reminder_timer += delta
			if _zenkai_reminder_timer >= 8.0:
				_zenkai_reminder_timer = 0.0
				show_scouter_alert(z_title, z_sub, z_col, 2.6)
		else:
			_zenkai_reminder_timer = 0.0
		_prev_player_zenkai = z_now

	if opponent_instance and is_instance_valid(opponent_instance):
		var opp_charging: bool = (opponent_instance.get("is_charging_super") == true)
		var opp_firing: bool = (opponent_instance.get("is_firing_beam") == true)
		var opp_zenkai: bool = (opponent_instance.get("is_in_zenkai_state") == true)
		var opp_super_active: bool = opp_charging or opp_firing
		if opp_zenkai and opp_super_active and not _prev_opp_zenkai_attack:
			show_scouter_alert("💀 ¡PELIGRO: ATAQUE ZENKAI DE K.O. ENTRANTE! 💀", "¡BLOQUEA, DESVÍA, ESQUIVA O CHOCA EL PODER!", Color(1.0, 0.15, 0.18), 3.2)
		elif opp_charging and not _prev_opp_charging_super:
			show_scouter_alert("🚨 ¡SUPER ENEMIGO INMINENTE!", "Prepárate para Bloqueo, Choque o Esquive", Color(1.0, 0.22, 0.25), 2.2)
		var opp_open_t: Variant = opponent_instance.get("blast_opened_timer")
		var opp_opened: bool = (opp_open_t != null and float(opp_open_t) > 0.0) and bool(opponent_instance.get("smoke_obscures_active"))
		if opp_opened and not _prev_opp_opened:
			show_scouter_alert("💥 ¡GUARDIA RIVAL ABIERTA!", "Melee Dash 0 KI (+1 Golpe) o Super (+25% Vel.)", Color(1.0, 0.72, 0.12), 2.2)
		var opp_crater_t: Variant = opponent_instance.get("ground_crater_stun_timer")
		var opp_crater: bool = opp_crater_t != null and float(opp_crater_t) > 0.0
		if opp_crater and not _prev_opp_crater:
			show_scouter_alert("🌌 ¡RIVAL ESTRELLADO EN CRÁTER!", "¡Lanza tu SUPER ahora! (+35% Vel. Carga)", Color(0.95, 0.35, 1.0), 2.8)
		_prev_opp_opened = opp_opened
		_prev_opp_crater = opp_crater
		_prev_opp_charging_super = opp_charging
		_prev_opp_zenkai_attack = (opp_zenkai and opp_super_active)

	if alert_banner_root and alert_banner_root.visible and camera and is_instance_valid(camera):
		var cam_basis: Basis = camera.global_transform.basis
		alert_banner_root.global_position = camera.global_position + (cam_basis * Vector3(0.0, 0.22, -1.22))
		alert_banner_root.global_transform.basis = cam_basis
		if _alert_timer > 0.0:
			_alert_timer -= delta
			var fade: float = clampf(_alert_timer / 0.45, 0.0, 1.0) if _alert_timer < 0.45 else 1.0
			if alert_title_label:
				alert_title_label.modulate = Color(_alert_color.r, _alert_color.g, _alert_color.b, fade)
			if alert_sub_label:
				alert_sub_label.modulate = Color(0.88, 0.95, 1.0, fade)
			if alert_bg_mat:
				alert_bg_mat.albedo_color = Color(0.03, 0.07, 0.08, 0.78 * fade)
			if _alert_timer <= 0.0:
				alert_banner_root.visible = false


func show_scouter_alert(title: String, subtitle: String = "", alert_color: Color = Color(1.0, 0.85, 0.15), duration: float = 2.4) -> void:
	if not alert_banner_root:
		return
	_alert_color = alert_color
	_alert_duration = maxf(0.8, duration)
	_alert_timer = _alert_duration
	if alert_title_label:
		alert_title_label.text = title
		alert_title_label.modulate = alert_color
	if alert_sub_label:
		alert_sub_label.text = subtitle
		alert_sub_label.modulate = Color(0.88, 0.95, 1.0, 1.0)
	if alert_bg_mat:
		alert_bg_mat.albedo_color = Color(0.03, 0.07, 0.08, 0.78)
	alert_banner_root.visible = true
	alert_banner_root.scale = Vector3.ONE * 0.72
	if _alert_tween and is_instance_valid(_alert_tween):
		_alert_tween.kill()
	if is_inside_tree():
		_alert_tween = create_tween()
		if _alert_tween:
			_alert_tween.tween_property(alert_banner_root, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
