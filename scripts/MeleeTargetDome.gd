class_name MeleeTargetDome
extends Node3D

## MeleeTargetDome (Godot 4.3+ VR)
## Cúpula esférica holográfica de fijación de objetivos tácticos en Bullet-Time.
## Durante el Bullet-Time (dilatación temporal por diferencial de BP), proyecta una matriz
## tridimensional de 6 cajas de impacto anime en puntos anatómicos clave del oponente.
## Registra los puñetazos físicos de los mandos VR en tiempo real.

signal target_hit(hit_count: int, zone_name: String, hit_pos: Vector3, is_charged: bool, power: float)
signal bullet_time_completed(recorded_hits: Array, launch_vector: Vector3)
signal finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3)

var attacker: Node3D = null
var defender: Node3D = null
var duration: float = 2.5
var time_left: float = 2.5
var is_active: bool = false
var hits: Array = []

# Seguimiento de velocidad para velocímetro y Martillazo
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO

# Seguimiento de puño cerrado y carga para puñetazos (0: Izquierda, 1: Derecha)
var fist_charge_times: Array[float] = [0.0, 0.0]
var fist_locked_haptic: Array[bool] = [false, false]
var fist_buffer_timers: Array[float] = [0.0, 0.0]

# Seguimiento de carga para Martillazo bimanual (mínimo 2.0s de carga con manos juntas)
var hammer_charge_time: float = 0.0
var hammer_locked_haptic: bool = false

# Vector de lanzamiento del último golpe cargado o martillo
var last_impact_vector: Vector3 = Vector3.ZERO
var was_last_hit_charged: bool = false

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

	# Actualizar seguimiento de puño cerrado y acumulación de carga por mando
	_update_fist_states(delta)

	# 1. Actualizar cálculo de velocidad cinemática de los mandos
	_update_controller_velocities(delta)

	# 2. Comprobar carga y ejecución de Martillazo Finisher bimanual
	# Si se está cargando el martillazo con ambas manos juntas, ralentizar el tiempo del domo (delta * 0.25)
	var is_charging_hammer = _process_hammer_charge(delta)
	var effective_delta = delta * 0.25 if is_charging_hammer else delta
	time_left -= effective_delta

	# Actualizar cooldown de impactos repetidos por zona
	for zone in target_zones:
		if zone.get("cooldown", 0.0) > 0.0:
			zone["cooldown"] -= delta

	if _check_hammer_finisher():
		return

	# Actualizar HUD flotante superior
	if header_label and is_instance_valid(header_label):
		var pct = clampf(time_left / maxf(duration, 0.1), 0.0, 1.0)
		var bar_len = int(pct * 12.0)
		var bar_str = "█".repeat(bar_len) + "░".repeat(12 - bar_len)
		if hammer_charge_time >= 2.0:
			header_label.text = "⚡ ¡MARTILLAZO LISTO! ⚡\n¡DESCARGA AMBOS PUÑOS HACIA ABAJO!\n🥊 COMBOS: %d GOLPES" % hits.size()
		elif is_charging_hammer:
			header_label.text = "⚡ CARGANDO MARTILLAZO: %.1fs / 2.0s ⚡\n[ %s ] %.1fs\n🥊 COMBOS: %d GOLPES" % [
				hammer_charge_time,
				bar_str,
				maxf(time_left, 0.0),
				hits.size()
			]
		else:
			var max_charge = maxf(fist_charge_times[0], fist_charge_times[1])
			if max_charge >= 0.5:
				header_label.text = "⚡ BULLET TIME ⚡ [GOLPE CARGADO: %.1fs]\n[ %s ] %.1fs\n🥊 COMBOS: %d GOLPES" % [
					max_charge,
					bar_str,
					maxf(time_left, 0.0),
					hits.size()
				]
			else:
				header_label.text = "⚡ BULLET TIME ⚡\n[ %s ] %.1fs\n🥊 COMBOS: %d GOLPES" % [
					bar_str,
					maxf(time_left, 0.0),
					hits.size()
				]

	# Detectar colisiones físicas de los mandos del jugador contra las cajas activas
	_check_controller_punches()

	# El tiempo dura su duración completa y SOLO se corta anticipadamente si se ejecuta el Martillazo
	if time_left <= 0.0:
		finish()


## Localiza de forma robusta los mandos XRController3D en la escena
func _get_controller(hand_name: String) -> XRController3D:
	if attacker and is_instance_valid(attacker):
		var p = attacker.get_parent()
		if p:
			var c = p.get_node_or_null(hand_name) as XRController3D
			if c:
				return c
	var scene = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	if scene:
		var xr = scene.find_child("Player_XROrigin3D", true, false)
		if not xr:
			xr = scene.find_child("XROrigin3D", true, false)
		if xr:
			var c = xr.get_node_or_null(hand_name) as XRController3D
			if c:
				return c
	return null


## Muestreo frame a frame de la velocidad física de ambos mandos
func _update_controller_velocities(delta: float) -> void:
	if delta <= 0.0001:
		return

	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")

	if left_ctrl:
		var cur_pos = left_ctrl.global_position
		if prev_left_pos != Vector3.ZERO:
			left_velocity = (cur_pos - prev_left_pos) / delta
		prev_left_pos = cur_pos

	if right_ctrl:
		var cur_pos = right_ctrl.global_position
		if prev_right_pos != Vector3.ZERO:
			right_velocity = (cur_pos - prev_right_pos) / delta
		prev_right_pos = cur_pos


## Actualiza el estado de puño cerrado y la carga de cada mano
func _update_fist_states(delta: float) -> void:
	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")
	var ctrls = [left_ctrl, right_ctrl]

	for i in range(2):
		var c = ctrls[i]
		if not c:
			continue
		var grip_v = c.get_float("grip")
		var trig_v = c.get_float("trigger")
		var grip_press = grip_v > 0.55 or c.is_button_pressed("grip_click")
		var trig_press = trig_v > 0.40 or c.is_button_pressed("trigger_click")
		var is_fist = grip_press and trig_press

		if is_fist:
			fist_buffer_timers[i] = 0.15 # Gracia de 150ms
			fist_charge_times[i] = minf(fist_charge_times[i] + delta, 2.5)

			# Pulso háptico distintivo de Fase 1 lista (0.5s)
			if fist_charge_times[i] >= 0.50 and not fist_locked_haptic[i]:
				fist_locked_haptic[i] = true
				if c.has_method("trigger_haptic_pulse"):
					c.trigger_haptic_pulse("haptic", 140.0, 0.75, 0.10, 0.0)
		else:
			if fist_buffer_timers[i] > 0.0:
				fist_buffer_timers[i] -= delta
			else:
				fist_charge_times[i] = 0.0
				fist_locked_haptic[i] = false


## Procesa la carga bimanual del Martillazo (requiere ambos puños juntos)
func _process_hammer_charge(delta: float) -> bool:
	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		hammer_charge_time = 0.0
		hammer_locked_haptic = false
		return false

	var l_fist = fist_buffer_timers[0] > 0.0
	var r_fist = fist_buffer_timers[1] > 0.0
	var hands_dist = left_ctrl.global_position.distance_to(right_ctrl.global_position)

	# Ambas manos en puño cerrado juntas (distancia <= 0.38m)
	if l_fist and r_fist and hands_dist <= 0.38:
		hammer_charge_time += delta
		# Pulso háptico rítmico mientras carga
		if left_ctrl.has_method("trigger_haptic_pulse"):
			left_ctrl.trigger_haptic_pulse("haptic", 85.0, clampf(0.20 + hammer_charge_time * 0.25, 0.20, 0.85), delta, 0.0)
		if right_ctrl.has_method("trigger_haptic_pulse"):
			right_ctrl.trigger_haptic_pulse("haptic", 85.0, clampf(0.20 + hammer_charge_time * 0.25, 0.20, 0.85), delta, 0.0)

		# Haptic Lock-in al completar 2.0s de carga mínima
		if hammer_charge_time >= 2.0 and not hammer_locked_haptic:
			hammer_locked_haptic = true
			if left_ctrl.has_method("trigger_haptic_pulse"):
				left_ctrl.trigger_haptic_pulse("haptic", 170.0, 1.0, 0.20, 0.0)
			if right_ctrl.has_method("trigger_haptic_pulse"):
				right_ctrl.trigger_haptic_pulse("haptic", 170.0, 1.0, 0.20, 0.0)
		return true
	else:
		# Si se separan las manos antes de 2.0s, resetea
		if hammer_charge_time < 2.0:
			hammer_charge_time = 0.0
			hammer_locked_haptic = false
		return false


## Comprueba si el jugador junta ambos puños y descarga el Martillazo como Finisher
func _check_hammer_finisher() -> bool:
	if not is_active:
		return false

	# REQUISITO CANÓNICO: Requiere al menos 2.0 segundos de carga con ambos puños juntos
	if hammer_charge_time < 2.0:
		return false

	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var l_pos = left_ctrl.global_position
	var r_pos = right_ctrl.global_position
	var hand_dist = l_pos.distance_to(r_pos)
	if hand_dist > 0.45:
		return false

	var avg_v = (left_velocity + right_velocity) * 0.5
	var peak_speed = maxf(left_velocity.length(), right_velocity.length())
	var downward_speed = -avg_v.y

	# Umbral cinemático estricto tras la carga: swing descendente hacia abajo
	if downward_speed > 0.80 or (downward_speed > 0.50 and peak_speed > 1.10):
		var to_def = Vector3.FORWARD
		if defender and is_instance_valid(defender) and attacker and is_instance_valid(attacker):
			var diff = (defender.global_position - attacker.global_position)
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				to_def = diff.normalized()

		# Vector de impacto hacia abajo y hacia el oponente/suelo
		var launch_vec = (to_def * 2.5 + Vector3.DOWN * 5.0).normalized() * 7.0
		last_impact_vector = launch_vec
		was_last_hit_charged = true

		print("[BulletTimeDome] ⚡ ¡FINISHER MARTILLAZO DETECTADO! (Carga: %.2fs, Vel: %.2f m/s, Corte inmediato de tiempo)." % [hammer_charge_time, peak_speed])
		is_active = false
		emit_signal("finisher_triggered", "hammer_strike", peak_speed, hits, launch_vec)

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

	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")

	var hand_sources: Array = []
	if left_ctrl:
		hand_sources.append({ "pos": left_ctrl.global_position, "name": "LeftHand", "ctrl": left_ctrl, "idx": 0 })
	if right_ctrl:
		hand_sources.append({ "pos": right_ctrl.global_position, "name": "RightHand", "ctrl": right_ctrl, "idx": 1 })

	# Soporte biométrico OpenXR Hand Tracking (yemas y palmas de ambas manos)
	var left_tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	var right_tracker = XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker

	if left_tracker:
		var flags_palm = left_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = left_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			hand_sources.append({ "pos": origin.global_transform * palm_local, "name": "LeftHand", "ctrl": left_ctrl, "idx": 0 })

	if right_tracker:
		var flags_palm = right_tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
		if (flags_palm & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			var palm_local = right_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
			hand_sources.append({ "pos": origin.global_transform * palm_local, "name": "RightHand", "ctrl": right_ctrl, "idx": 1 })

	for hand_data in hand_sources:
		var hand_pos: Vector3 = hand_data["pos"]
		var ctrl_node: XRController3D = hand_data["ctrl"]
		var hand_name: String = hand_data["name"]
		var hand_idx: int = hand_data["idx"]

		# REQUISITO CANÓNICO 1: Para dar un golpe se DEBEN apretar Gatillo y Grab al mismo tiempo (simulando puño cerrado).
		# Se utiliza un buffer de gracia de 150ms (fist_buffer_timers). Si no es un puño cerrado, ¡NO cuenta como golpe!
		var is_fist = fist_buffer_timers[hand_idx] > 0.0
		if not is_fist:
			continue

		# REQUISITO CANÓNICO 2: Velocímetro del golpe. Se requiere una velocidad física mínima de 0.55 m/s
		var cur_vel = left_velocity if hand_idx == 0 else right_velocity
		var v_mag = cur_vel.length()
		if v_mag < 0.55:
			continue

		for zone in target_zones:
			if zone.get("cooldown", 0.0) > 0.0:
				continue

			var target_pos: Vector3 = zone["node"].global_position
			var dist: float = hand_pos.distance_to(target_pos)

			# Radio de detección de golpe físico: 0.30 metros
			if dist <= 0.30:
				_register_hit(zone, ctrl_node, hand_name, hand_idx, cur_vel, v_mag)


## Registra el impacto exitoso en una zona calculando potencia y dirección del golpe
func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String, hand_idx: int, cur_vel: Vector3, v_mag: float) -> void:
	# Cooldown de 140ms por zona para permitir golpes repetidos rápidos al mismo lugar
	zone["cooldown"] = 0.14
	var hit_pos: Vector3 = zone["node"].global_position

	# REQUISITO CANÓNICO: Potencia del golpe = Velocidad del mando * (1.0 + tiempo_carga * 1.25)
	var charge_t = fist_charge_times[hand_idx]
	var is_charged = charge_t >= 0.50
	var punch_power = v_mag * (1.0 + charge_t * 1.25)

	# Dirección del impacto basada en la cinemática del puñetazo
	var swing_dir = cur_vel.normalized() if cur_vel.length_squared() > 0.01 else -global_transform.basis.z
	var fwd = -global_transform.basis.z

	# Determinar vector de lanzamiento según la dirección donde llegó el golpe (cielo, atrás, lado, suelo)
	if is_charged:
		was_last_hit_charged = true
		last_impact_vector = (swing_dir + Vector3.UP * 0.30).normalized() * (5.5 + punch_power * 0.35)
	else:
		was_last_hit_charged = false
		last_impact_vector = (fwd + Vector3.UP * 0.15).normalized() * 3.8

	# Consumo de Ki / BP por golpe físico
	if attacker and is_instance_valid(attacker) and attacker.has_method("consume_ki_or_life_force"):
		var res = attacker.consume_ki_or_life_force(3.5)
		if res.get("is_life_sacrifice", false):
			var bp_lost = int(res.get("sacrificed_np", 0.0))
			print("[BulletTimeDome] Golpe físico ejecutado con sacrificio vital: -%d BP" % bp_lost)

	hits.append({
		"zone_id": zone["id"],
		"name": zone["name"],
		"pos": hit_pos,
		"hand": hand_name,
		"time_left": time_left,
		"power": punch_power,
		"is_charged": is_charged,
		"velocity": v_mag,
		"swing_dir": swing_dir
	})

	# 1. Efecto visual: destello y pulso elástico
	_spawn_hit_spark(hit_pos)

	var box_inst: MeshInstance3D = zone["box_mesh"]
	var orig_col: Color = zone["color"]

	if box_inst and is_instance_valid(box_inst):
		var mat = box_inst.material_override as StandardMaterial3D
		if mat:
			var flash_col = Color(1.0, 1.0, 0.4) if not is_charged else Color(1.0, 0.3, 0.1)
			mat.albedo_color = flash_col
			mat.emission = flash_col
			mat.emission_energy_multiplier = 4.5 if is_charged else 3.0

		var scale_mult = 1.65 if is_charged else 1.35
		var tw = create_tween().set_parallel(true)
		tw.tween_property(zone["node"], "scale", Vector3.ONE * scale_mult, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(zone["node"], "scale", Vector3.ONE, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if mat:
			tw.parallel().tween_property(mat, "albedo_color", orig_col, 0.12)
			tw.parallel().tween_property(mat, "emission", Color(orig_col.r, orig_col.g, orig_col.b), 0.12)
			tw.parallel().tween_property(mat, "emission_energy_multiplier", 1.2, 0.12)

	# 2. Audio de impacto físico
	if audio_player:
		audio_player.global_position = hit_pos
		audio_player.stream = sfx_hit_heavy if (is_charged or hits.size() % 4 == 0) else sfx_hit_light
		audio_player.pitch_scale = randf_range(0.90, 1.10) if is_charged else randf_range(0.95, 1.15)
		audio_player.play()

	# 3. Pulso háptico de impacto (mayor intensidad en golpe cargado)
	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		var h_freq = 220.0 if is_charged else 180.0
		var h_amp = 1.0 if is_charged else clampf(0.55 + v_mag * 0.15, 0.55, 0.95)
		var h_dur = 0.20 if is_charged else 0.08
		ctrl_node.trigger_haptic_pulse("haptic", h_freq, h_amp, h_dur, 0.0)

	# Resetear carga de la mano tras impactar
	fist_charge_times[hand_idx] = 0.0
	fist_locked_haptic[hand_idx] = false

	emit_signal("target_hit", hits.size(), zone["name"], hit_pos, is_charged, punch_power)
	print("[BulletTimeDome] ¡Impacto #%d conectado en '%s'! (Potencia: %.1f, Cargado: %s, Mando: %s)" % [
		hits.size(), zone["name"], punch_power, str(is_charged), hand_name
	])


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
	tw.tween_property(spark, "scale", Vector3.ONE * 0.35, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.10)
	tw.chain().tween_callback(spark.queue_free)


## Finaliza el Bullet-Time y emite los resultados con el vector de lanzamiento para la ráfaga
func finish() -> void:
	if not is_active:
		return
	is_active = false

	var final_launch = last_impact_vector
	if final_launch == Vector3.ZERO:
		var fwd = Vector3.BACK
		if defender and is_instance_valid(defender) and attacker and is_instance_valid(attacker):
			var diff = defender.global_position - attacker.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				fwd = diff.normalized()
		final_launch = fwd * 4.0

	print("[BulletTimeDome] Bullet-Time finalizado. Total golpes: %d, Último golpe cargado: %s" % [hits.size(), str(was_last_hit_charged)])
	emit_signal("bullet_time_completed", hits, final_launch)

	# Desvanecer la cúpula exterior y destruirse limpiamente
	if dome_mesh and is_instance_valid(dome_mesh):
		var tw = create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()
