class_name MeleeTargetDome
extends Node3D

## MeleeTargetDome (Godot 4.3+ VR)
## Cúpula esférica holográfica anime con combate rítmico secuencial de 2 fases:
## Fase 1 (Ataque / Beat Maker): El atacante golpea las 6 cajas holográficas y compone su combo (o martillazo).
## Fase 2 (Defensa Rítmica / Beat Matching): Al defensor le llegan las notas concéntricas en orden rítmico.
## Permite Manos Cruzadas (-85% daño), Bloqueo con Mano (+Ki, +BP) y Bloqueo Perfecto (Grip+Trigger = Parry + Inversión de Roles).

enum DomePhase {
	ATTACK_RECORDING,
	DEFENSE_RHYTHM,
	COMPLETED
}

signal target_hit(hit_count: int, zone_name: String, hit_pos: Vector3, is_charged: bool, power: float)
signal bullet_time_completed(recorded_hits: Array, launch_vector: Vector3)
signal finisher_triggered(finisher_name: String, swing_velocity: float, recorded_hits: Array, launch_vector: Vector3)
signal perfect_parry_triggered(new_attacker: Node3D, new_defender: Node3D)
signal defense_action_resolved(action_type: String, zone_id: int, was_successful: bool, reward_ki: float, reward_bp: float)

var phase: DomePhase = DomePhase.ATTACK_RECORDING

var attacker: Node3D = null
var defender: Node3D = null
var duration: float = 2.2
var time_left: float = 2.2
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
var hand_must_retract: Array[bool] = [false, false]

# Seguimiento de carga para Martillazo bimanual (mínimo 2.0s de carga con manos juntas)
var hammer_charge_time: float = 0.0
var hammer_locked_haptic: bool = false
var hammer_primed: bool = false
var hammer_primed_window: float = 0.0
var hammer_interruption_timer: float = 0.0

# Vector de lanzamiento del último golpe cargado o martillo
var last_impact_vector: Vector3 = Vector3.ZERO
var was_last_hit_charged: bool = false

# Cajas de objetivo tácticas
var target_zones: Array = []
var dome_mesh: MeshInstance3D = null
var header_label: Label3D = null

# Parámetros de la Fase 2 (Defensa Rítmica)
var defense_timer: float = 0.0
var defense_total_duration: float = 0.0
var consecutive_guard_hits: int = 0
var buffer_grip_timer_l: float = 0.0
var buffer_grip_timer_r: float = 0.0
var buffer_trig_timer_l: float = 0.0
var buffer_trig_timer_r: float = 0.0
var prev_grip_l: bool = false
var prev_grip_r: bool = false
var prev_trig_l: bool = false
var prev_trig_r: bool = false

# Reproductor de audio espacial para impactos dentro del Bullet-Time
var audio_player: AudioStreamPlayer3D = null
var sfx_hit_light: AudioStream = null
var sfx_hit_heavy: AudioStream = null
var sfx_parry: AudioStream = null

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
	phase = DomePhase.ATTACK_RECORDING
	is_active = true

	# Cargar efectos de sonido de combate
	sfx_hit_light = load("res://assets/audio/gekishin_test/003073_s1.wav")
	sfx_hit_heavy = load("res://assets/audio/gekishin_test/003073_s3.wav")
	if ResourceLoader.exists("res://assets/audio/gekishin_test/003074_s4.wav"):
		sfx_parry = load("res://assets/audio/gekishin_test/003074_s4.wav")
	else:
		sfx_parry = sfx_hit_light

	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "BulletTimeAudio"
	audio_player.unit_size = 5.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

	# Posicionar la cúpula sobre el centro del pecho del oponente
	_update_dome_transform()

	# Construir la cúpula exterior, las cajas holográficas y los anillos de timing
	_build_visual_dome()
	_build_target_boxes()
	_build_header_hud()

	# Si el atacante es la IA, genera una secuencia procedural ofensiva y pasa a Fase de Defensa
	if attacker and not attacker.get("is_player"):
		generate_ai_attack_sequence()
		start_defense_phase()

	print("[BulletTimeDome] Cúpula táctica inicializada. Duración ataque: %.2fs para %d objetivos." % [duration, target_zones.size()])


func _process(delta: float) -> void:
	if not is_active:
		return

	# Comprobar si los combatientes se separaron fuera del rango de combate cuerpo a cuerpo
	if attacker and defender and is_instance_valid(attacker) and is_instance_valid(defender):
		var p_atk = attacker.global_position
		var p_def = defender.global_position
		if attacker.get("is_player"):
			var orig = attacker.get_parent()
			var c = orig.get_node_or_null("XRCamera3D") if orig else null
			if c: p_atk = c.global_position
		if defender.get("is_player"):
			var orig = defender.get_parent()
			var c = orig.get_node_or_null("XRCamera3D") if orig else null
			if c: p_def = c.global_position
		p_atk.y = 0.0
		p_def.y = 0.0
		if p_atk.distance_to(p_def) > 3.5:
			print("[BulletTimeDome] Fin del enfrentamiento melee: Separación fuera de rango (%.2fm)." % p_atk.distance_to(p_def))
			finish_without_hits()
			return

	if phase == DomePhase.ATTACK_RECORDING:
		_process_attack_recording(delta)
	elif phase == DomePhase.DEFENSE_RHYTHM:
		_process_defense_rhythm(delta)


# ==============================================================================
# FASE 1: ATAQUE (BEAT MAKER / GRABACIÓN DE GOLPES)
# ==============================================================================

func _process_attack_recording(delta: float) -> void:
	# Mantener la posición de la cúpula sincronizada con la cámara del atacante
	_update_dome_transform()

	# Actualizar seguimiento de puño cerrado y acumulación de carga por mando
	_update_fist_states(delta)

	# 1. Actualizar cálculo de velocidad cinemática de los mandos
	_update_controller_velocities(delta)

	# 2. Comprobar carga y ejecución de Martillazo Finisher bimanual
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
				header_label.text = "🥊 FASE DE ATAQUE 🥊 [GOLPE CARGADO: %.1fs]\n[ %s ] %.1fs\n🥊 COMBOS: %d GOLPES" % [
					max_charge,
					bar_str,
					maxf(time_left, 0.0),
					hits.size()
				]
			else:
				header_label.text = "🥊 FASE DE ATAQUE 🥊\n[ %s ] %.1fs\n🥊 COMBOS: %d GOLPES" % [
					bar_str,
					maxf(time_left, 0.0),
					hits.size()
				]

	# Detectar colisiones físicas de los mandos del atacante contra las cajas activas
	_check_controller_punches()

	# Al expirar el tiempo de ataque:
	if time_left <= 0.0:
		if hits.is_empty():
			print("[BulletTimeDome] Tiempo de ataque expirado sin golpes conectados.")
			finish_without_hits()
		else:
			# Si el atacante es la IA, pasar a la defensa rítmica del jugador
			# Si el atacante es el jugador, terminar para descargar la ráfaga (flurry) sobre el oponente
			if attacker and not attacker.get("is_player"):
				start_defense_phase()
			else:
				finish_defense_phase()


# ==============================================================================
# FASE 2: DEFENSA RÍTMICA (RHYTHM DEFENSE / BEAT MATCHING)
# ==============================================================================

func start_defense_phase() -> void:
	phase = DomePhase.DEFENSE_RHYTHM
	defense_timer = -0.40 # Pre-roll de 400ms para que el defensor se prepare
	consecutive_guard_hits = 0

	# Calcular la duración total de la defensa basada en los tiempos grabados
	var max_offset = 0.0
	for h in hits:
		var off = float(h.get("time_offset", 0.0))
		if off > max_offset:
			max_offset = off
	defense_total_duration = max_offset + 0.65

	# Ajustar HUD defensivo
	if header_label and is_instance_valid(header_label):
		header_label.text = "🛡️ ¡DEFENSA RÍTMICA! 🛡️\n⚡ MANO = DESVÍO (+Ki/+BP)\n⚡ GRIP+GATILLO = BLOQUEO PERFECTO"
		header_label.modulate = Color(0.2, 0.85, 1.0)

	# Cambiar visuales de la cúpula a tonalidad protectora cian/violeta
	if dome_mesh and is_instance_valid(dome_mesh):
		var mat = dome_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.5, 0.9, 0.08)

	# Reorientar la cúpula frente al defensor
	_update_dome_transform_for_defender()

	print("[BulletTimeDome] ¡Iniciada Fase de Defensa Rítmica! %d notas a defender en %.2fs." % [hits.size(), defense_total_duration])


func _process_defense_rhythm(delta: float) -> void:
	defense_timer += delta

	# Reorientar la cúpula frente al defensor
	_update_dome_transform_for_defender()

	# Actualizar buffer biomecánico de 90ms de los mandos del defensor
	_update_defender_input_buffers(delta)

	# Actualizar HUD defensivo con cuenta regresiva
	if header_label and is_instance_valid(header_label):
		var remaining = maxf(defense_total_duration - defense_timer, 0.0)
		header_label.text = "🛡️ ¡DEFENSA RÍTMICA! (%.1fs) 🛡️\n⚡ MANO = DESVÍO (+Ki/+BP)\n⚡ GRIP+GATILLO = BLOQUEO PERFECTO" % remaining

	# Evaluar las notas grabadas de la secuencia
	var all_resolved = true
	var defender_is_player = defender.get("is_player") if defender else false

	for i in range(hits.size()):
		var note = hits[i]
		if note.get("resolved", false):
			continue

		all_resolved = false
		var time_offset = float(note.get("time_offset", 0.0))
		var t_diff = time_offset - defense_timer
		var zone_id = int(note.get("zone_id", 0))
		var zone = target_zones[zone_id] if zone_id < target_zones.size() else target_zones[0]
		var ring = zone.get("timing_ring") as MeshInstance3D

		# 1. Visual del Anillo Concéntrico de Timing (aparece 0.8s antes del impacto)
		if t_diff > 0.0 and t_diff <= 0.8:
			if ring and is_instance_valid(ring):
				ring.visible = true
				var t_factor = clampf(t_diff / 0.8, 0.0, 1.0)
				ring.scale = Vector3.ONE * (1.0 + t_factor * 1.6)

				# Color de la nota según el tipo de ataque
				var r_mat = ring.material_override as StandardMaterial3D
				if r_mat:
					if note.get("is_hammer", false):
						r_mat.albedo_color = Color(0.9, 0.2, 1.0, 0.95) # Púrpura eléctrico Martillo
					elif note.get("is_charged", false):
						r_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.95) # Naranja flamígero Cargado
					else:
						r_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.95) # Celeste Ki Normal
		elif t_diff > 0.8:
			if ring and is_instance_valid(ring):
				ring.visible = false

		# 2. Ventana de Impacto / Timing Activo (Timing = 0, margen ±0.12s)
		if abs(t_diff) <= 0.12:
			var zone_pos = zone["node"].global_position

			# CASO A: DEFENSOR ES JUGADOR HUMANO (VR)
			if defender_is_player:
				var hand_near_idx = _get_defender_hand_near_zone(zone_pos, 0.20)
				var is_just_guard = _is_defender_just_guard_active(hand_near_idx)

				# A1. BLOQUEO PERFECTO (Mano en la zona + Grip y Trigger en buffer de 90ms)
				if hand_near_idx != -1 and is_just_guard:
					_resolve_perfect_parry(note, zone)
					return # Corta inmediatamente y pasa al contraataque

				# A2. BLOQUEO CON LA MANO (Desvío de arte marcial)
				elif hand_near_idx != -1:
					_resolve_hand_block(note, zone, hand_near_idx)
					continue

				# A3. MANOS CRUZADAS EN EL PECHO (Guardia pasiva)
				elif _is_defender_crossing_arms():
					_resolve_cross_arm_guard(note, zone)
					continue

			# CASO B: DEFENSOR ES LA IA (GOKU)
			else:
				_resolve_ai_defense(note, zone)
				continue

		# 3. IMPACTO RECIBIDO (La nota superó la ventana de timing sin ser defendida)
		elif t_diff < -0.12:
			_resolve_unblocked_hit(note, zone)
			continue

	# Si todas las notas concluyeron, finalizar la cúpula
	if all_resolved or defense_timer >= defense_total_duration:
		finish_defense_phase()


func _resolve_perfect_parry(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	var ring = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	# Recompensas masivas: +40 Ki y +400 BP
	if defender and is_instance_valid(defender):
		if defender.has_method("recharge_ki"):
			defender.recharge_ki(40.0)
		if defender.has_method("increase_np"):
			defender.increase_np(400.0)

	# Audio icónico Dragon Ball PING y destello
	if audio_player:
		audio_player.global_position = zone["node"].global_position
		audio_player.stream = sfx_parry
		audio_player.pitch_scale = 1.30
		audio_player.play()

	_spawn_parry_shockwave(zone["node"].global_position)

	# Pulso háptico máximo en ambos mandos
	var def_origin = defender.get_parent() if defender.get("is_player") else null
	if def_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = def_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 250.0, 1.0, 0.25, 0.0)

	emit_signal("defense_action_resolved", "perfect_parry", zone["id"], true, 40.0, 400.0)
	print("[BulletTimeDome] ⚡ ¡BLOQUEO PERFECTO CONECTADO! Hit-Stop 80ms e Inversión de Roles inmediata.")

	# Hit-Stop anime de 80ms
	_trigger_hit_stop(0.08)

	# Descartar todas las notas restantes del combo del atacante
	for h in hits:
		h["resolved"] = true

	# ¡INVERSIÓN DE ROLES INMEDIATA!
	restart_as_attacker()


func _resolve_hand_block(note: Dictionary, zone: Dictionary, hand_idx: int) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0 # Resetea presión de guardia
	var ring = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var is_hammer = note.get("is_hammer", false)
	var is_charged = note.get("is_charged", false)
	var base_power = float(note.get("power", 1.0))
	var zone_pos = zone["node"].global_position

	# El Martillazo NO se puede frenar con una sola mano: Rompe guardia
	if is_hammer:
		var dmg = 650.0 * base_power
		if defender.has_method("take_hit"):
			defender.take_hit(dmg, Vector3.DOWN)
		_spawn_hit_spark(zone_pos)
		emit_signal("defense_action_resolved", "guard_break", zone["id"], false, 0.0, 0.0)
		print("[BulletTimeDome] 💥 ¡El Martillazo rompió el bloqueo de mano! Daño completo.")
		return

	# Golpe cargado: Bloqueo parcial (mitiga 50% daño a cambio de 8 Ki)
	if is_charged:
		var mitigated_dmg = 140.0 * base_power
		if defender.has_method("consume_ki"):
			defender.consume_ki(8.0)
		if defender.has_method("take_hit"):
			defender.take_hit(mitigated_dmg, Vector3.ZERO)
		if defender.has_method("increase_np"):
			defender.increase_np(75.0)

		if audio_player:
			audio_player.global_position = zone_pos
			audio_player.stream = sfx_hit_heavy
			audio_player.play()
		_spawn_hit_spark(zone_pos)
		emit_signal("defense_action_resolved", "partial_block", zone["id"], true, 8.0, 75.0)
		return

	# Golpe normal: Bloqueo 100% perfecto de mano (+15 Ki, +150 BP)
	if defender.has_method("recharge_ki"):
		defender.recharge_ki(15.0)
	if defender.has_method("increase_np"):
		defender.increase_np(150.0)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.stream = sfx_hit_light
		audio_player.pitch_scale = 1.25
		audio_player.play()

	_spawn_block_spark(zone_pos, Color(1.0, 0.9, 0.2))

	# Pulso háptico ágil en el mando que bloqueó
	var def_origin = defender.get_parent() if defender.get("is_player") else null
	if def_origin:
		var h_name = "LeftHand" if hand_idx == 0 else "RightHand"
		var ctrl = def_origin.get_node_or_null(h_name)
		if ctrl and ctrl.has_method("trigger_haptic_pulse"):
			ctrl.trigger_haptic_pulse("haptic", 180.0, 0.85, 0.10, 0.0)

	emit_signal("defense_action_resolved", "hand_block", zone["id"], true, 15.0, 150.0)


func _resolve_cross_arm_guard(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits += 1
	var ring = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var base_power = float(note.get("power", 1.0))
	var is_charged = note.get("is_charged", false)
	var is_hammer = note.get("is_hammer", false)
	var zone_pos = zone["node"].global_position

	# Daño mitigado al 85% (solo entra el 15%)
	var raw_dmg = 550.0 if is_hammer else (280.0 if is_charged else 140.0)
	raw_dmg *= base_power
	var final_dmg = raw_dmg * 0.15

	# Costo de Ki con presión progresiva (+2 Ki por impacto consecutivo en guardia)
	var ki_cost = 4.0 + (consecutive_guard_hits * 2.0)
	if defender.has_method("consume_ki"):
		defender.consume_ki(ki_cost)
	if defender.has_method("take_hit"):
		defender.take_hit(final_dmg, Vector3.ZERO)
	if defender.has_method("increase_np"):
		defender.increase_np(20.0)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.stream = sfx_hit_heavy if is_hammer else sfx_hit_light
		audio_player.pitch_scale = 0.85
		audio_player.play()

	_spawn_block_spark(zone_pos, Color(0.2, 0.7, 1.0))

	# Pulso háptico de impacto contenido en ambos mandos
	var def_origin = defender.get_parent() if defender.get("is_player") else null
	if def_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = def_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 140.0, 0.60, 0.10, 0.0)

	emit_signal("defense_action_resolved", "cross_arm_guard", zone["id"], true, 0.0, 20.0)


func _resolve_unblocked_hit(note: Dictionary, zone: Dictionary) -> void:
	note["resolved"] = true
	consecutive_guard_hits = 0
	var ring = zone.get("timing_ring") as MeshInstance3D
	if ring and is_instance_valid(ring):
		ring.visible = false

	var base_power = float(note.get("power", 1.0))
	var is_charged = note.get("is_charged", false)
	var is_hammer = note.get("is_hammer", false)
	var zone_pos = zone["node"].global_position

	var raw_dmg = 600.0 if is_hammer else (280.0 if is_charged else 140.0)
	raw_dmg *= base_power

	if defender and is_instance_valid(defender):
		if defender.has_method("take_hit"):
			defender.take_hit(raw_dmg, -global_transform.basis.z)
		if defender.get("procedural_animator"):
			defender.procedural_animator.trigger_hit_flinch(0.40, -global_transform.basis.z)

	if attacker and is_instance_valid(attacker) and attacker.has_method("increase_np"):
		attacker.increase_np(raw_dmg * 0.40)

	if audio_player:
		audio_player.global_position = zone_pos
		audio_player.stream = sfx_hit_heavy if is_charged or is_hammer else sfx_hit_light
		audio_player.play()

	# Pulso háptico de daño no bloqueado
	var def_origin = defender.get_parent() if defender.get("is_player") else null
	if def_origin:
		for h in ["LeftHand", "RightHand"]:
			var ctrl = def_origin.get_node_or_null(h)
			if ctrl and ctrl.has_method("trigger_haptic_pulse"):
				ctrl.trigger_haptic_pulse("haptic", 200.0, 0.75, 0.12, 0.0)

	_spawn_hit_spark(zone_pos)
	emit_signal("defense_action_resolved", "hit_taken", zone["id"], false, 0.0, 0.0)


func _resolve_ai_defense(note: Dictionary, zone: Dictionary) -> void:
	var is_hammer = note.get("is_hammer", false)
	var is_charged = note.get("is_charged", false)
	var in_zenkai = defender.get("is_in_zenkai_state") if defender else false

	# Ante ataques pesados, la IA prioriza Guardia en Cruz o Bloqueo Perfecto si tiene Zenkai
	if is_hammer or is_charged:
		if in_zenkai and randf() < 0.25:
			_resolve_perfect_parry(note, zone)
		else:
			_resolve_cross_arm_guard(note, zone)
	else:
		# Ataques normales: 75% bloqueo con mano, 15% Bloqueo Perfecto, 10% impacto
		var roll = randf()
		if roll < 0.15 and in_zenkai:
			_resolve_perfect_parry(note, zone)
		elif roll < 0.85:
			_resolve_hand_block(note, zone, 0)
		else:
			_resolve_unblocked_hit(note, zone)


## Genera una secuencia rítmica procedural cuando el atacante es la IA (Goku)
func generate_ai_attack_sequence() -> void:
	hits.clear()
	var ai_in_zenkai: bool = attacker.get("is_in_zenkai_state") if attacker else false
	var num_hits: int = randi_range(3, 5) if ai_in_zenkai else randi_range(3, 4)
	var curr_time: float = 0.35
	var last_zone: int = -1

	for i in range(num_hits):
		var zone_id: int = randi() % ZONE_DEFINITIONS.size()
		if zone_id == last_zone:
			zone_id = (zone_id + 1) % ZONE_DEFINITIONS.size()
		last_zone = zone_id

		var is_last: bool = (i == num_hits - 1)
		var is_hammer: bool = false
		var is_charged: bool = false
		var power: float = 1.0

		if is_last and (ai_in_zenkai or (attacker and attacker.get("current_ki") > 35.0)):
			var r = randf()
			if r < 0.30:
				is_hammer = true
				power = 2.0
				zone_id = 1 # Golpe al centro
			elif r < 0.65:
				is_charged = true
				power = 1.5

		var target_pos: Vector3 = target_zones[zone_id]["node"].global_position if zone_id < target_zones.size() else global_position
		hits.append({
			"zone_id": zone_id,
			"name": ZONE_DEFINITIONS[zone_id]["name"] if not is_hammer else "Martillazo Finisher",
			"pos": target_pos,
			"hand": "Right" if (i % 2 == 0) else "Left",
			"time_offset": curr_time,
			"power": power,
			"is_charged": is_charged,
			"is_hammer": is_hammer,
			"velocity": 4.5,
			"swing_dir": Vector3.DOWN if is_hammer else (Vector3.FORWARD + Vector3.RIGHT * (0.2 if i % 2 == 0 else -0.2)),
			"resolved": false
		})

		curr_time += randf_range(0.38, 0.52)


# ==============================================================================
# INVERSIÓN DE ROLES (TURNOVER) Y REINICIO
# ==============================================================================

func restart_as_attacker() -> void:
	# Intercambiar referencias de atacante y defensor
	var temp = attacker
	attacker = defender
	defender = temp

	# Reiniciar variables de la Fase 1
	phase = DomePhase.ATTACK_RECORDING
	hits.clear()
	duration = 2.2
	time_left = 2.2
	hammer_charge_time = 0.0
	hammer_primed = false
	fist_charge_times = [0.0, 0.0]
	last_impact_vector = Vector3.ZERO
	was_last_hit_charged = false

	# Reorientar cúpula frente al nuevo atacante
	_update_dome_transform()

	# Reconfigurar HUD superior
	if header_label and is_instance_valid(header_label):
		header_label.text = "⚡ ¡INVERSIÓN DE ROLES! ¡TU TURNO DE ATAQUE! ⚡\n%.1fs" % duration
		header_label.modulate = Color(1.0, 0.95, 0.3)

	# Restaurar color de cúpula exterior ofensiva
	if dome_mesh and is_instance_valid(dome_mesh):
		var mat = dome_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.85, 0.2, 0.08)

	# Emitir señal de cambio de turno
	emit_signal("perfect_parry_triggered", attacker, defender)
	print("[BulletTimeDome] 🔄 Inversión de roles completada. Nuevo atacante: %s, Nuevo defensor: %s" % [
		attacker.name if attacker else "None", defender.name if defender else "None"
	])

	# Si el nuevo atacante es la IA, genera su combo y transiciona a la defensa del jugador
	if attacker and not attacker.get("is_player"):
		generate_ai_attack_sequence()
		start_defense_phase()


func finish_defense_phase() -> void:
	if not is_active:
		return
	is_active = false
	phase = DomePhase.COMPLETED

	var final_launch = last_impact_vector
	if final_launch == Vector3.ZERO:
		var fwd = Vector3.BACK
		if defender and is_instance_valid(defender) and attacker and is_instance_valid(attacker):
			var diff = defender.global_position - attacker.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				fwd = diff.normalized()
		final_launch = fwd * 4.0

	print("[BulletTimeDome] Secuencia rítmica concluida. Total notas procesadas: %d" % hits.size())
	emit_signal("bullet_time_completed", hits, final_launch)

	if dome_mesh and is_instance_valid(dome_mesh):
		var tw = create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()


func finish_without_hits() -> void:
	if not is_active:
		return
	is_active = false
	phase = DomePhase.COMPLETED
	emit_signal("bullet_time_completed", [], Vector3.ZERO)
	if dome_mesh and is_instance_valid(dome_mesh):
		var tw = create_tween()
		tw.tween_property(dome_mesh, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()


# ==============================================================================
# SEGUIMIENTO BIOMECÁNICO Y BUFFERS DE ENTRADA
# ==============================================================================

func _update_defender_input_buffers(delta: float) -> void:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return

	var left_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	if left_ctrl:
		var g_l = left_ctrl.get_float("grip") > 0.65 or left_ctrl.is_button_pressed("grip_click")
		var t_l = left_ctrl.get_float("trigger") > 0.65 or left_ctrl.is_button_pressed("trigger_click")
		if g_l and not prev_grip_l:
			buffer_grip_timer_l = 0.09 # 90ms buffer
		if t_l and not prev_trig_l:
			buffer_trig_timer_l = 0.09
		prev_grip_l = g_l
		prev_trig_l = t_l

	if right_ctrl:
		var g_r = right_ctrl.get_float("grip") > 0.65 or right_ctrl.is_button_pressed("grip_click")
		var t_r = right_ctrl.get_float("trigger") > 0.65 or right_ctrl.is_button_pressed("trigger_click")
		if g_r and not prev_grip_r:
			buffer_grip_timer_r = 0.09
		if t_r and not prev_trig_r:
			buffer_trig_timer_r = 0.09
		prev_grip_r = g_r
		prev_trig_r = t_r

	buffer_grip_timer_l = maxf(buffer_grip_timer_l - delta, 0.0)
	buffer_grip_timer_r = maxf(buffer_grip_timer_r - delta, 0.0)
	buffer_trig_timer_l = maxf(buffer_trig_timer_l - delta, 0.0)
	buffer_trig_timer_r = maxf(buffer_trig_timer_r - delta, 0.0)


func _is_defender_just_guard_active(hand_idx: int) -> bool:
	if hand_idx == 0:
		return (prev_grip_l and prev_trig_l) or (buffer_grip_timer_l > 0.0 and prev_trig_l) or (buffer_trig_timer_l > 0.0 and prev_grip_l)
	elif hand_idx == 1:
		return (prev_grip_r and prev_trig_r) or (buffer_grip_timer_r > 0.0 and prev_trig_r) or (buffer_trig_timer_r > 0.0 and prev_grip_r)
	return false


func _get_defender_hand_near_zone(zone_pos: Vector3, threshold: float) -> int:
	if not defender or not is_instance_valid(defender) or not defender.get("is_player"):
		return -1

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return -1

	var left_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	if left_ctrl and left_ctrl.global_position.distance_to(zone_pos) <= threshold:
		return 0
	if right_ctrl and right_ctrl.global_position.distance_to(zone_pos) <= threshold:
		return 1
	return -1


func _is_defender_crossing_arms() -> bool:
	if not defender or not is_instance_valid(defender):
		return false
	if defender.get("is_blocking"):
		return true

	var origin: XROrigin3D = defender.get_parent() as XROrigin3D if defender.get("is_player") else null
	if not origin:
		return false

	var cam = origin.get_node_or_null("XRCamera3D") as Camera3D
	var left_ctrl = origin.get_node_or_null("LeftHand") as XRController3D
	var right_ctrl = origin.get_node_or_null("RightHand") as XRController3D

	if cam and left_ctrl and right_ctrl:
		var hands_dist = left_ctrl.global_position.distance_to(right_ctrl.global_position)
		var avg_pos = (left_ctrl.global_position + right_ctrl.global_position) * 0.5
		var rel_y = avg_pos.y - cam.global_position.y
		if hands_dist < 0.28 and rel_y > -0.30 and rel_y < 0.20:
			return true
	return false


func _trigger_hit_stop(freeze_time: float = 0.08) -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(freeze_time, true, false, true).timeout
	Engine.time_scale = 1.0


# ==============================================================================
# CONSTRUCCIÓN DE MALLAS Y RETÍCULAS HOLOGRÁFICAS
# ==============================================================================

func _build_visual_dome() -> void:
	dome_mesh = MeshInstance3D.new()
	dome_mesh.name = "MeleeDomeSphere"
	var sphere = SphereMesh.new()
	sphere.radius = 1.25
	sphere.height = 2.50
	sphere.radial_segments = 32
	sphere.rings = 16
	dome_mesh.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.08)
	dome_mesh.material_override = mat
	add_child(dome_mesh)


func _build_target_boxes() -> void:
	target_zones.clear()

	for def in ZONE_DEFINITIONS:
		var zone_node = Node3D.new()
		zone_node.name = "Zone_%d_%s" % [def.id, def.name.replace(" / ", "_").replace(" ", "_")]
		zone_node.position = def.offset
		add_child(zone_node)

		# 1. Caja holográfica exterior
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

		# 2. Marco reticular interior brillante
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

		# 3. Anillo concéntrico de timing (Fase 2: Defensa Rítmica)
		var timing_ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.08
		torus.outer_radius = 0.095
		torus.rings = 16
		torus.ring_segments = 16
		timing_ring.mesh = torus
		timing_ring.rotation.x = PI * 0.5
		timing_ring.position = Vector3(0.0, 0.0, 0.035)
		timing_ring.visible = false

		var mat_ring = StandardMaterial3D.new()
		mat_ring.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat_ring.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat_ring.albedo_color = Color(1.0, 0.9, 0.2, 0.95)
		timing_ring.material_override = mat_ring
		zone_node.add_child(timing_ring)

		target_zones.append({
			"id": def.id,
			"name": def.name,
			"node": zone_node,
			"box_mesh": box_mesh_inst,
			"inner_mesh": inner_quad,
			"timing_ring": timing_ring,
			"hit": false,
			"color": def.color
		})


func _build_header_hud() -> void:
	header_label = Label3D.new()
	header_label.name = "HeaderLabel"
	header_label.text = "🥊 FASE DE ATAQUE 🥊\n%.1fs" % duration
	header_label.font_size = 32
	header_label.outline_size = 10
	header_label.modulate = Color(1.0, 0.95, 0.3)
	header_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	header_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	header_label.position = Vector3(0.0, 0.72, 0.0)
	add_child(header_label)


func _update_dome_transform() -> void:
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

	global_position = cam_pos + fwd * 0.52 + Vector3(0.0, -0.16, 0.0)
	rotation.y = atan2(-fwd.x, -fwd.z)
	rotation.x = 0.0


func _update_dome_transform_for_defender() -> void:
	var cam: Camera3D = null
	if defender and is_instance_valid(defender):
		var my_origin = defender.get_parent()
		if my_origin:
			cam = my_origin.get_node_or_null("XRCamera3D")
	if not cam:
		var vp = get_viewport()
		if vp:
			cam = vp.get_camera_3d()

	var cam_pos = cam.global_position if cam else (defender.global_position + Vector3(0.0, 1.45, 0.0) if defender else global_position)
	var fwd = -cam.global_transform.basis.z if cam else ((-defender.global_transform.basis.z) if defender else Vector3.FORWARD)
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		if attacker and is_instance_valid(attacker):
			fwd = (attacker.global_position - cam_pos)
			fwd.y = 0.0
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	global_position = cam_pos + fwd * 0.52 + Vector3(0.0, -0.16, 0.0)
	rotation.y = atan2(-fwd.x, -fwd.z)
	rotation.x = 0.0


# ==============================================================================
# REGISTRO DE GOLPES DEL ATACANTE (FASE 1)
# ==============================================================================

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

	for zone in target_zones:
		if zone.get("cooldown", 0.0) > 0.0:
			continue

		var target_pos: Vector3 = zone["node"].global_position

		for hand_data in hand_sources:
			var hand_idx = hand_data["idx"]
			var hand_pos: Vector3 = hand_data["pos"]
			var dist: float = hand_pos.distance_to(target_pos)

			# Resetear retracción si la mano se aleja de la caja
			if hand_must_retract[hand_idx] and dist > 0.22:
				hand_must_retract[hand_idx] = false

			if hand_must_retract[hand_idx]:
				continue

			if dist <= 0.28:
				var cur_vel = left_velocity if hand_idx == 0 else right_velocity
				var v_mag = cur_vel.length()
				if v_mag < 0.35:
					v_mag = 0.50

				_register_hit(zone, hand_data["ctrl"], hand_data["name"], hand_idx, cur_vel, v_mag)
				hand_must_retract[hand_idx] = true
				break


func _register_hit(zone: Dictionary, ctrl_node: XRController3D, hand_name: String, hand_idx: int, cur_vel: Vector3, v_mag: float) -> void:
	zone["cooldown"] = 0.14
	var hit_pos: Vector3 = zone["node"].global_position

	var charge_t = fist_charge_times[hand_idx]
	var is_charged = charge_t >= 0.50
	var punch_power = v_mag * (1.0 + charge_t * 1.25)

	var swing_dir = cur_vel.normalized() if cur_vel.length_squared() > 0.01 else -global_transform.basis.z
	var fwd = -global_transform.basis.z

	if is_charged:
		was_last_hit_charged = true
		last_impact_vector = (swing_dir + Vector3.UP * 0.25).normalized() * (8.5 + punch_power * 0.45)
	else:
		was_last_hit_charged = false
		last_impact_vector = (fwd + Vector3.UP * 0.15).normalized() * 4.0

	# Consumo de Ki / BP por golpe físico
	if attacker and is_instance_valid(attacker) and attacker.has_method("consume_ki_or_life_force"):
		var res = attacker.consume_ki_or_life_force(3.5)
		if res.get("is_life_sacrifice", false):
			var bp_lost = int(res.get("sacrificed_np", 0.0))
			print("[BulletTimeDome] Golpe físico ejecutado con sacrificio vital: -%d BP" % bp_lost)

	var relative_time = duration - time_left
	hits.append({
		"zone_id": zone["id"],
		"name": zone["name"],
		"pos": hit_pos,
		"hand": hand_name,
		"time_offset": relative_time,
		"power": punch_power,
		"is_charged": is_charged,
		"is_hammer": false,
		"velocity": v_mag,
		"swing_dir": swing_dir,
		"resolved": false
	})

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

	if audio_player:
		audio_player.global_position = hit_pos
		audio_player.stream = sfx_hit_heavy if (is_charged or hits.size() % 4 == 0) else sfx_hit_light
		audio_player.pitch_scale = randf_range(0.90, 1.10) if is_charged else randf_range(0.95, 1.15)
		audio_player.play()

	if ctrl_node and ctrl_node.has_method("trigger_haptic_pulse"):
		var h_freq = 220.0 if is_charged else 180.0
		var h_amp = 1.0 if is_charged else clampf(0.55 + v_mag * 0.15, 0.55, 0.95)
		var h_dur = 0.20 if is_charged else 0.08
		ctrl_node.trigger_haptic_pulse("haptic", h_freq, h_amp, h_dur, 0.0)

	fist_charge_times[hand_idx] = 0.0
	fist_locked_haptic[hand_idx] = false

	emit_signal("target_hit", hits.size(), zone["name"], hit_pos, is_charged, punch_power)


func _check_hammer_finisher() -> bool:
	if not hammer_primed and hammer_charge_time < 2.0:
		return false

	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var down_l = -left_velocity.y
	var down_r = -right_velocity.y
	var avg_down = (down_l + down_r) * 0.5
	var peak_speed = maxf(left_velocity.length(), right_velocity.length())

	if avg_down > 0.55 or down_l > 0.65 or down_r > 0.65 or (avg_down > 0.40 and peak_speed > 0.95):
		var to_def = -global_transform.basis.z
		if defender and is_instance_valid(defender) and attacker and is_instance_valid(attacker):
			var diff = (defender.global_position - attacker.global_position)
			diff.y = 0.0
			if diff.length_squared() > 0.01:
				to_def = diff.normalized()

		var launch_vec = (to_def * 4.2 + Vector3.UP * 2.2).normalized() * 11.5
		last_impact_vector = launch_vec
		was_last_hit_charged = true

		print("[BulletTimeDome] ⚡ ¡FINISHER MARTILLAZO REGISTRADO! Transicionando a Fase 2 de Defensa Rítmica.")
		hits.append({
			"zone_id": 1,
			"name": "Martillazo Finisher",
			"pos": target_zones[1]["node"].global_position,
			"hand": "BothHands",
			"time_offset": duration - time_left,
			"power": 4.5,
			"is_charged": true,
			"is_hammer": true,
			"velocity": peak_speed,
			"swing_dir": Vector3.DOWN,
			"resolved": false
		})

		start_defense_phase()
		return true

	return false


# ==============================================================================
# FUNCIONES AUXILIARES DE ENTRADA Y EFECTOS
# ==============================================================================

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


func _update_fist_states(delta: float) -> void:
	for i in [0, 1]:
		var hand_name = "LeftHand" if i == 0 else "RightHand"
		var c = _get_controller(hand_name)
		if not c:
			continue

		var cam = attacker.get_parent().get_node_or_null("XRCamera3D") if (attacker and attacker.get_parent()) else null
		var cam_pos = cam.global_position if cam else global_position
		var dist_to_body = c.global_position.distance_to(cam_pos)

		if hand_must_retract[i] and dist_to_body < 0.50:
			hand_must_retract[i] = false

		var trig_val = c.get_float("trigger")
		var grip_val = c.get_float("grip")
		var is_closed = trig_val > 0.45 or grip_val > 0.45 or c.is_button_pressed("trigger_click") or c.is_button_pressed("grip_click")

		if is_closed:
			fist_buffer_timers[i] = 0.12
		else:
			if fist_buffer_timers[i] > 0.0:
				fist_buffer_timers[i] -= delta

		var effectively_closed = is_closed or fist_buffer_timers[i] > 0.0
		if effectively_closed and not hand_must_retract[i]:
			fist_charge_times[i] += delta
			if fist_charge_times[i] >= 0.50 and not fist_locked_haptic[i]:
				fist_locked_haptic[i] = true
				if c.has_method("trigger_haptic_pulse"):
					c.trigger_haptic_pulse("haptic", 160.0, 0.85, 0.12, 0.0)
		else:
			fist_charge_times[i] = 0.0
			fist_locked_haptic[i] = false


func _process_hammer_charge(delta: float) -> bool:
	var left_ctrl = _get_controller("LeftHand")
	var right_ctrl = _get_controller("RightHand")
	if not left_ctrl or not right_ctrl:
		return false

	var hands_dist = left_ctrl.global_position.distance_to(right_ctrl.global_position)
	var cam = attacker.get_parent().get_node_or_null("XRCamera3D") if (attacker and attacker.get_parent()) else null
	var cam_pos = cam.global_position if cam else global_position
	var avg_pos = (left_ctrl.global_position + right_ctrl.global_position) * 0.5
	var rel_y = avg_pos.y - cam_pos.y

	var l_closed = left_ctrl.get_float("trigger") > 0.60 or left_ctrl.is_button_pressed("trigger_click")
	var r_closed = right_ctrl.get_float("trigger") > 0.60 or right_ctrl.is_button_pressed("trigger_click")

	var is_hammer_pose = (hands_dist <= 0.28) and (rel_y >= 0.05) and l_closed and r_closed

	if is_hammer_pose:
		hammer_interruption_timer = 0.0
		hammer_charge_time += delta
		if hammer_charge_time >= 2.0:
			if not hammer_locked_haptic:
				hammer_locked_haptic = true
				hammer_primed = true
				hammer_primed_window = 1.4
				for c in [left_ctrl, right_ctrl]:
					if c and c.has_method("trigger_haptic_pulse"):
						c.trigger_haptic_pulse("haptic", 200.0, 1.0, 0.25, 0.0)
		return true
	else:
		if hammer_primed:
			hammer_primed_window -= delta
			if hammer_primed_window <= 0.0:
				hammer_primed = false
				hammer_charge_time = 0.0
				hammer_locked_haptic = false
		else:
			hammer_interruption_timer += delta
			if hammer_interruption_timer > 0.20:
				hammer_charge_time = 0.0
				hammer_locked_haptic = false
		return false


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


func _spawn_block_spark(pos: Vector3, col: Color) -> void:
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.10
	sphere.height = 0.20
	spark.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	spark.material_override = mat

	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(spark)
	else:
		add_child(spark)
	spark.global_position = pos

	var tw = spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 0.40, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.chain().tween_callback(spark.queue_free)


func _spawn_parry_shockwave(pos: Vector3) -> void:
	var wave = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.25
	wave.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.3, 0.95)
	wave.material_override = mat

	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(wave)
	else:
		add_child(wave)
	wave.global_position = pos

	var tw = wave.create_tween().set_parallel(true)
	tw.tween_property(wave, "scale", Vector3.ONE * 2.2, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.20)
	tw.chain().tween_callback(wave.queue_free)
