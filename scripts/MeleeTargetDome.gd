class_name MeleeTargetDome
extends Node3D

## MeleeTargetDome (Godot 4.3+ VR)
## Cúpula esférica holográfica de fijación de objetivos tácticos en Bullet-Time.
## Durante el Bullet-Time (dilatación temporal por diferencial de BP), proyecta una matriz
## tridimensional de 6 cajas de impacto anime en puntos anatómicos clave del oponente.
## Registra los puñetazos físicos de los mandos VR en tiempo real.

signal target_hit(hit_count: int, zone_name: String, hit_pos: Vector3)
signal bullet_time_completed(recorded_hits: Array)
signal finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array)

var attacker: Node3D = null
var defender: Node3D = null
var duration: float = 2.5
var time_left: float = 2.5
var is_active: bool = false
var hits: Array = []

# Seguimiento de velocidad para el Martillazo (Finisher bimanual)
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO

# Cajas de objetivo tácticas
var target_zones: Array = []
var dome_mesh: MeshInstance3D = null
var header_label: Label3D = null

# Reproductor de audio espacial para impactos dentro del Bullet-Time
var audio_player: AudioStreamPlayer3D = null
var sfx_hit_light: AudioStream = null
var sfx_hit_heavy: AudioStream = null

# Definición canónica de zonas anatómicas de impacto DBZ (matriz frontal plana fija frente al jugador)
const ZONE_DEFINITIONS = [
	{ "id": 0, "name": "Rostro / Cabeza", "offset": Vector3(0.0, 0.22, 0.0), "color": Color(1.0, 0.3, 0.2, 0.85) },
	{ "id": 1, "name": "Plexo Solar", "offset": Vector3(0.0, 0.0, 0.0), "color": Color(0.2, 0.85, 1.0, 0.85) },
	{ "id": 2, "name": "Costilla Izquierda", "offset": Vector3(-0.22, 0.10, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 3, "name": "Costilla Derecha", "offset": Vector3(0.22, 0.10, 0.0), "color": Color(0.2, 1.0, 0.4, 0.85) },
	{ "id": 4, "name": "Flanco Izquierdo", "offset": Vector3(-0.18, -0.16, 0.0), "color": Color(1.0, 0.8, 0.2, 0.85) },
	{ "id": 5, "name": "Flanco Derecho", "offset": Vector3(0.18, -0.16, 0.0), "color": Color(1.0, 0.8, 0.2, 0.85) }
]

func setup(p_attacker: Node3D, p_defender: Node3D, p_duration: float) -> void:
	attacker = p_attacker
	defender = p_defender
	duration = p_duration
	time_left = p_duration
	hits.clear()
	is_active = true

	# Cargar efectos de sonido de combate
	sfx_hit_light = load("res://assets/audio/gekishin_test/003073_s1.wav")
	sfx_hit_heavy = load("res://assets/audio/gekishin_test/003073_s3.wav")

	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BulletTimeAudio"
	audio_player.unit_size = 5.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

	# Posicionar la cúpula sobre el centro del pecho del oponente
	_update_dome_transform()

	# Construir la cúpula exterior y las cajas holográficas
	_build_visual_dome()
	_build_target_boxes()
	_build_header_hud()

	print("[BulletTimeDome] Cúpula táctica inicializada. Duración: %.2fs para %d objetivos." % [duration, target_zones.size()])


func _process(delta: float) -> void:
	if not is_active:
		return

	time_left -= delta

	# 1. Actualizar cálculo de velocidad cinemática de los mandos
	_update_controller_velocities(delta)

	# 2. Comprobar si el jugador ejecuta el Martillazo Finisher bimanual (Time-Cut inmediato)
	if _check_hammer_finisher():
		return

	# Actualizar HUD flotante superior
	if header_label and is_instance_valid(header_label):
		var pct = clampf(time_left / maxf(duration, 0.1), 0.0, 1.0)
		var bar_len = int(pct * 12.0)
		var bar_str = "█".repeat(bar_len) + "░".repeat(12 - bar_len)
		header_label.text = "⚡ BULLET TIME ⚡\n[ %s ] %.1fs\n🎯 IMPACTOS: %d / %d" % [
			bar_str,
			maxf(time_left, 0.0),
			hits.size(),
			target_zones.size()
		]

	# Detectar colisiones físicas de los mandos del jugador contra las cajas activas
	_check_controller_punches()

	# Si se agota el tiempo o se conectaron todos los objetivos, finalizar Bullet-Time
	if time_left <= 0.0 or hits.size() >= target_zones.size():
		finish()


## Muestreo frame a frame de la velocidad física de ambos mandos
func _update_controller_velocities(delta: float) -> void:
	if delta <= 0.0001 or not attacker or not is_instance_valid(attacker):
		return

	var origin = attacker.get_parent()
	if not origin:
		return

	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand")
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand")

	if left_ctrl and left_ctrl.get_is_active():
		var cur_pos = left_ctrl.global_position
		if prev_left_pos != Vector3.ZERO:
			left_velocity = (cur_pos - prev_left_pos) / delta
		prev_left_pos = cur_pos

	if right_ctrl and right_ctrl.get_is_active():
		var cur_pos = right_ctrl.global_position
		if prev_right_pos != Vector3.ZERO:
			right_velocity = (cur_pos - prev_right_pos) / delta
		prev_right_pos = cur_pos


## Comprueba si el jugador junta ambos puños y descarga el Martillazo como Finisher
func _check_hammer_finisher() -> bool:
	if not attacker or not is_instance_valid(attacker) or not defender or not is_instance_valid(defender):
		return false

	var origin = attacker.get_parent()
	if not origin:
		return false

	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand")
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand")

	if not left_ctrl or not right_ctrl or not left_ctrl.get_is_active() or not right_ctrl.get_is_active():
		return false

	# 1. Ambos mandos deben tener puño cerrado (Grip + Trigger presionados)
	var l_grip = left_ctrl.get_float("grip") > 0.45 or left_ctrl.is_button_pressed("grip_click")
	var l_trig = left_ctrl.get_float("trigger") > 0.45 or left_ctrl.is_button_pressed("trigger_click")
	var r_grip = right_ctrl.get_float("grip") > 0.45 or right_ctrl.is_button_pressed("grip_click")
	var r_trig = right_ctrl.get_float("trigger") > 0.45 or right_ctrl.is_button_pressed("trigger_click")

	if not (l_grip and l_trig and r_grip and r_trig):
		return false

	# 2. Ambas manos juntas en mazo (distancia < 25 cm)
	var hand_dist = left_ctrl.global_position.distance_to(right_ctrl.global_position)
	if hand_dist > 0.25:
		return false

	# 3. Cinemática del swing coordinado
	var avg_v = (left_velocity + right_velocity) * 0.5
	var peak_speed = maxf(left_velocity.length(), right_velocity.length())

	var to_def = (defender.global_position - attacker.global_position).normalized()
	to_def.y = 0.0
	to_def = to_def.normalized() if to_def.length_squared() > 0.01 else Vector3.FORWARD

	var fwd_speed = avg_v.dot(to_def)
	var vert_speed = abs(avg_v.y)

	# Umbral cinemático: velocidad del swing > 1.8 m/s hacia el rival o en trayectoria vertical
	if peak_speed >= 1.8 and (fwd_speed > 0.8 or vert_speed > 1.0):
		print("[BulletTimeDome] ⚡ ¡FINISHER MARTILLAZO DETECTADO! Velocidad física de impacto: %.2f m/s (Corte inmediato de tiempo)." % peak_speed)
		is_active = false
		emit_signal("finisher_triggered", "hammer_strike", peak_speed, hits)

		# Desvanecer rápidamente la cúpula y autoeliminarse
		if dome_mesh and is_instance_valid(dome_mesh):
			var tw = create_tween()
			tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(queue_free)
		else:
			queue_free()
		return true

	return false


func _update_dome_transform() -> void:
	# Localizar la posición de la cabeza / cámara del jugador atacante
	var cam: Camera3D = null
	if attacker and is_instance_valid(attacker):
		var my_origin = attacker.get_parent()
		if my_origin:
			cam = my_origin.get_node_or_null("XRCamera3D")
	if not cam:
		var vp = get_viewport()
		if vp:
			cam = vp.get_camera_3d()

	var cam_pos = cam.global_position if cam else (attacker.global_position + Vector3(0.0, 1.45, 0.0) if attacker else global_position)
	var fwd = -cam.global_transform.basis.z if cam else ((-attacker.global_transform.basis.z) if attacker else Vector3.FORWARD)
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		if defender and is_instance_valid(defender):
			fwd = (defender.global_position - cam_pos)
			fwd.y = 0.0
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	# Posicionar la matriz de recuadros exactamente a 0.52m al frente de los ojos del jugador
	# a la altura de su pecho, completamente desacoplada de giros del contrincante
	global_position = cam_pos + fwd * 0.52 + Vector3(0.0, -0.16, 0.0)

	# Orientar frontalmente hacia el jugador (+Z local de las cajas mira hacia los ojos del atacante)
	rotation.y = atan2(-fwd.x, -fwd.z)
	rotation.x = 0.0
	rotation.z = 0.0


## Crea la esfera de energía anime translúcida (Matrix Dome)
func _build_visual_dome() -> void:
	dome_mesh = MeshInstance3D.new()
	dome_mesh.name = "EnergyDomeMesh"

	var sphere = SphereMesh.new()
	sphere.radius = 0.50
	sphere.height = 1.00
	sphere.radial_segments = 24
	sphere.rings = 14
	dome_mesh.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.12, 0.65, 1.0, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.75, 1.0)
	mat.emission_energy_multiplier = 0.5
	dome_mesh.material_override = mat

	add_child(dome_mesh)

	# Animación de respiración/pulso del domo
	var tween = create_tween().set_loops()
	tween.tween_property(dome_mesh, "scale", Vector3.ONE * 1.04, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(dome_mesh, "scale", Vector3.ONE * 0.98, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Construye las 6 cajas holográficas de impacto anime
func _build_target_boxes() -> void:
	target_zones.clear()

	for def in ZONE_DEFINITIONS:
		var zone_node = Node3D.new()
		zone_node.name = "Zone_" + str(def.id)
		zone_node.position = def.offset
		add_child(zone_node)

		# 1. Caja externa de impacto
		var box_mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.16, 0.16, 0.05)
		box_mesh_inst.mesh = box

		var mat_box = StandardMaterial3D.new()
		mat_box.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_box.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
		mat_box.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_box.albedo_color = def.color
		mat_box.emission_enabled = true
		mat_box.emission = Color(def.color.r, def.color.g, def.color.b)
		mat_box.emission_energy_multiplier = 1.2
		box_mesh_inst.material_override = mat_box
		zone_node.add_child(box_mesh_inst)

		# 2. Marco reticular interior brillante (Target Ring)
		var inner_quad = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(0.12, 0.12)
		inner_quad.mesh = quad
		inner_quad.position = Vector3(0.0, 0.0, 0.028)

		var mat_quad = StandardMaterial3D.new()
		mat_quad.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_quad.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_quad.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		inner_quad.material_override = mat_quad
		zone_node.add_child(inner_quad)

		# 3. Vista limpia sin textos de partes corporales (Punto 2: solo los cuadrados holográficos)
		var lbl: Label3D = null

		# Datos cacheados de la zona
		target_zones.append({
			"id": def.id,
			"name": def.name,
			"node": zone_node,
			"box_mesh": box_mesh_inst,
			"inner_mesh": inner_quad,
			"label": lbl,
			"hit": false,
			"color": def.color
		})


## Cabecera superior con contador de tiempo y ráfaga
func _build_header_hud() -> void:
	header_label = Label3D.new()
	header_label.name = "HeaderLabel"
	header_label.text = "⚡ BULLET TIME ⚡\n%.1fs" % duration
	header_label.font_size = 32
	header_label.outline_size = 10
	header_label.modulate = Color(1.0, 0.95, 0.3)
	header_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	header_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	header_label.position = Vector3(0.0, 0.72, 0.0)
	add_child(header_label)


## Detecta los puñetazos de los mandos físicos o manos OpenXR contra las zonas de impacto
func _check_controller_punches() -> void:
	if not attacker or not is_instance_valid(attacker):
		return

	var origin: XROrigin3D = attacker.get_parent() as XROrigin3D if attacker.get("is_player") else null
	if not origin:
		return

	var left_ctrl: XRController3D = origin.get_node_or_null("LeftHand")
	var right_ctrl: XRController3D = origin.get_node_or_null("RightHand")

	var hand_sources: Array = []
	if left_ctrl and left_ctrl.get_is_active():
		hand_sources.append({ "pos": left_ctrl.global_position, "name": "LeftHand", "ctrl": left_ctrl })
	if right_ctrl and right_ctrl.get_is_active():
		hand_sources.append({ "pos": right_ctrl.global_position, "name": "RightHand", "ctrl": right_ctrl })

	# Soporte biométrico OpenXR Hand Tracking (yemas y palmas de ambas manos)
	var left_tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	var right_tracker = XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker

	if left_tracker:
		var flags_tip = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		if (flags_tip & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var tip_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
			hand_sources.append({ "pos": origin.global_transform * tip_local, "name": "LeftHand", "ctrl": left_ctrl })
		var flags_palm = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			hand_sources.append({ "pos": origin.global_transform * palm_local, "name": "LeftHand", "ctrl": left_ctrl })

	if right_tracker:
		var flags_tip = right_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		if (flags_tip & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var tip_local = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
			hand_sources.append({ "pos": origin.global_transform * tip_local, "name": "RightHand", "ctrl": right_ctrl })
		var flags_palm = right_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			hand_sources.append({ "pos": origin.global_transform * palm_local, "name": "RightHand", "ctrl": right_ctrl })

	for hand_data in hand_sources:
		var hand_pos: Vector3 = hand_data["pos"]
		var ctrl_node: XRController3D = hand_data["ctrl"]
		var hand_name: String = hand_data["name"]

		for zone in target_zones:
			if zone["hit"]:
				continue

			var target_pos: Vector3 = zone["node"].global_position
			var dist: float = hand_pos.distance_to(target_pos)

			# Radio de detección de golpe físico: 0.24 metros (sensible y natural en VR)
			if dist <= 0.24:
				_register_hit(zone, ctrl_node, hand_name)


## Registra el impacto exitoso en una zona
func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String) -> void:
	zone["hit"] = true
	var hit_pos: Vector3 = zone["node"].global_position

	hits.append({
		"zone_id": zone["id"],
		"name": zone["name"],
		"pos": hit_pos,
		"hand": hand_name,
		"time_left": time_left
	})

	# 1. Efecto visual: flash dorado brillante, expansión y disipación
	var box_inst: MeshInstance3D = zone["box_mesh"]
	var lbl: Label3D = zone["label"]
	if lbl and is_instance_valid(lbl):
		lbl.text = "¡HIT!"
		lbl.modulate = Color(1.0, 0.9, 0.1)

	_spawn_hit_spark(hit_pos)

	if box_inst and is_instance_valid(box_inst):
		var mat = box_inst.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.9, 0.2, 1.0)
			mat.emission = Color(1.0, 0.9, 0.3)
			mat.emission_energy_multiplier = 4.0

		var tw = create_tween().set_parallel(true)
		tw.tween_property(zone["node"], "scale", Vector3.ONE * 1.5, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if mat:
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		tw.chain().tween_callback(func():
			if is_instance_valid(zone["node"]):
				zone["node"].visible = false
		)

	# 2. Audio de impacto físico inmediato
	if audio_player:
		audio_player.global_position = hit_pos
		audio_player.stream = sfx_hit_heavy if hits.size() == target_zones.size() else sfx_hit_light
		audio_player.pitch_scale = randf_range(0.95, 1.15)
		audio_player.play()

	# 3. Pulso háptico en el mando que conectó el puñetazo
	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		ctrl_node.trigger_haptic_pulse("haptic", 200.0, 0.95, 0.12, 0.0)

	emit_signal("target_hit", hits.size(), zone["name"], hit_pos)
	print("[BulletTimeDome] ¡Impacto #%d conectado en '%s'! (Mando: %s)" % [hits.size(), zone["name"], hand_name])


## Genera un destello radial anime (sparks) en el punto de contacto
func _spawn_hit_spark(pos: Vector3) -> void:
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	spark.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5, 0.95)
	spark.material_override = mat

	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(spark)
	else:
		add_child(spark)
	spark.global_position = pos

	var tw = spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 2.8, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.chain().tween_callback(spark.queue_free)


## Finaliza el Bullet-Time y emite los resultados para la ráfaga de golpes
func finish() -> void:
	if not is_active:
		return
	is_active = false

	print("[BulletTimeDome] Bullet-Time finalizado. Total de golpes registrados: %d" % hits.size())
	emit_signal("bullet_time_completed", hits)

	# Desvanecer la cúpula exterior y destruirse limpiamente
	if dome_mesh and is_instance_valid(dome_mesh):
		var tw = create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()
