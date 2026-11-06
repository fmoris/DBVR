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
var reticle_label: Label3D = null

var ki_pointer_root: Node3D = null
var pointer_label: Label3D = null
var pointer_arrow_mesh: MeshInstance3D = null

var audio_player: AudioStreamPlayer3D = null
var sfx_locked: AudioStream = null

func _ready() -> void:
	_build_lockon_reticle()
	_build_ki_pointer()
	_setup_audio()


func setup(p_cam: XRCamera3D, p_player: Node3D, p_opp: Node3D, p_left: XRController3D, p_right: XRController3D) -> void:
	camera = p_cam
	player_instance = p_player
	opponent_instance = p_opp
	left_controller = p_left
	right_controller = p_right


func _setup_audio() -> void:
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "LockOnAudio"
	audio_player.unit_size = 3.0
	audio_player.max_distance = 15.0
	add_child(audio_player)
	sfx_locked = load("res://assets/audio/gekishin_test/003073_s1.wav")


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

	# 2. Etiqueta central de estado
	reticle_label = Label3D.new()
	reticle_label.text = "[ FIJANDO KI ]"
	reticle_label.font_size = 22
	reticle_label.outline_size = 6
	reticle_label.modulate = Color(0.2, 0.85, 1.0)
	reticle_label.outline_modulate = Color.BLACK
	reticle_label.no_depth_test = true
	reticle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reticle_label.position = Vector3(0.0, 0.30, 0.0)
	lockon_reticle_root.add_child(reticle_label)


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


func _show_reticle_charging(pos: Vector3, progress: float) -> void:
	lockon_reticle_root.visible = true
	lockon_reticle_root.global_position = pos

	var scale_factor = lerpf(1.4, 1.0, progress)
	lockon_reticle_root.scale = Vector3.ONE * scale_factor

	var mat = reticle_ring.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.2, 0.85, 1.0, 0.5 + progress * 0.45)

	var pct_str = int(progress * 100.0)
	reticle_label.text = "[ FIJANDO KI: %d%% ]" % pct_str
	reticle_label.modulate = Color(0.2, 0.85, 1.0)


func _show_reticle_locked(pos: Vector3) -> void:
	lockon_reticle_root.visible = true
	lockon_reticle_root.global_position = pos
	lockon_reticle_root.scale = Vector3.ONE

	var mat = reticle_ring.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0, 0.88, 0.15, 0.95)

	reticle_label.text = "🎯 [ OBJETIVO FIJADO ] 🎯"
	reticle_label.modulate = Color(1.0, 0.95, 0.2)


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

	# Posicionar el puntero en la periferia de visión (0.42m del centro a 0.85m de profundidad)
	var pointer_offset_local = Vector3(screen_dir.x * 0.40, screen_dir.y * 0.28, -0.80)
	ki_pointer_root.global_position = camera.global_position + (cam_basis * pointer_offset_local)

	# Orientar la flecha para que apunte en la dirección screen_dir
	var arrow_angle = atan2(screen_dir.y, screen_dir.x)
	pointer_arrow_mesh.rotation = Vector3(0.0, 0.0, arrow_angle - PI * 0.5)

	# Actualizar texto con la distancia de Ki
	var opp_name = opponent_instance.get("character_data").character_name if opponent_instance.get("character_data") else "RIVAL"
	pointer_label.text = "⚡ KI DE %s: %.1fm ⚡" % [opp_name.to_upper(), dist_m]


func _ensure_references() -> void:
	if not camera and get_viewport():
		camera = get_viewport().get_camera_3d()
	if not opponent_instance and get_tree() and get_tree().current_scene:
		opponent_instance = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
	if not player_instance and get_tree() and get_tree().current_scene:
		player_instance = get_tree().current_scene.find_child("PlayerCharacterInstance", true, false)
