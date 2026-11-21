class_name HybridCombatController
extends Node

## HybridCombatController: Sistema híbrido de combate con mandos Meta Quest 3.
## Combina las poses corporales y cinemáticas del anime con la fiabilidad de los mandos físicos (6DoF + Grip + Trigger).
## Si los mandos están inactivos, cede automáticamente el control a GesturePhaseTree (Hand Tracking puro).

signal controller_mode_changed(is_active: bool)

@export var gesture_tree: Node = null
@export var haptics_enabled: bool = true

# Nodos de seguimiento
var xr_origin: XROrigin3D = null
var camera: XRCamera3D = null
var left_controller: XRController3D = null
var right_controller: XRController3D = null
var desktop_sim: Node = null

# Estado de conectividad
var controllers_active: bool = false
var last_reported_mode: bool = false

# --- Estados de Combate Híbrido ---

# 1. Recarga de Ki (2 Fases)
var is_charging_ki: bool = false
var ki_prep_phase: bool = false
var ki_haptic_timer: float = 0.0
var was_in_melee_minigame: bool = false

# 2. Ki Blasts (Izquierda y Derecha)
var left_trigger_held: bool = false
var right_trigger_held: bool = false
var left_charge_time: float = 0.0
var right_charge_time: float = 0.0
var left_is_charging: bool = false
var right_is_charging: bool = false
var left_blast_locked_haptic: bool = false
var right_blast_locked_haptic: bool = false
var left_blast_cooldown: float = 0.0
var right_blast_cooldown: float = 0.0

# 3. Super Poderes (Kamehameha / Galick Ho / Final Flash)
enum SuperPowerState { IDLE, CHARGING, READY_TO_FIRE }
var current_super_state: SuperPowerState = SuperPowerState.IDLE
var super_power_type: String = "" # "kamehameha", "galick_ho", "final_flash", "genkidama"
var super_charge_timer: float = 0.0
var super_locked_haptic: bool = false
var super_phase2_latched: bool = false
var super_phase2_grace_timer: float = 0.0
var super_phase2_ready_notified: bool = false
const SUPER_MIN_CHARGE_TIME: float = 1.0
var candidate_super_tech: String = ""
var candidate_hold_timer: float = 0.0
const SUPER_POSE_HOLD_TIME: float = 0.18

# 3a. Espacio corporal normalizado (Torso-Space, sin allocs por frame)
var body_scale: float = 1.0
var inv_body_scale: float = 1.0
var torso_fwd: Vector3 = Vector3.FORWARD
var torso_right: Vector3 = Vector3.RIGHT
var cam_fwd_flat: Vector3 = Vector3.FORWARD
var cam_pos_cached: Vector3 = Vector3.ZERO
var chest_pos_cached: Vector3 = Vector3.ZERO
var l_torso_pos: Vector3 = Vector3.ZERO
var r_torso_pos: Vector3 = Vector3.ZERO
var avg_torso_pos: Vector3 = Vector3.ZERO
var l_cam_rel_y: float = 0.0
var r_cam_rel_y: float = 0.0
var l_cam_fwd_proj: float = 0.0
var r_cam_fwd_proj: float = 0.0
var hands_dist_norm: float = 0.0
var l_torso_vel: Vector3 = Vector3.ZERO
var r_torso_vel: Vector3 = Vector3.ZERO
var super_phase1_anchor_z: float = 0.0
var super_unusable_warn_cooldown: float = 0.0
# Punto 3: Ventana "¡HAAA!" de 0.5s, láser guía y suavizado de dirección (cero allocs)
var super_aim_lock_window: float = -1.0
var _aim_dir_history: PackedVector3Array = PackedVector3Array()
var _aim_dir_cursor: int = 0
var _aim_dir_filled: int = 0
var _guide_laser_mesh: MeshInstance3D = null
var _guide_laser_mat: StandardMaterial3D = null
# Punto 11: Señales en controles para Fase 2 lista (anillo + flecha + háptico latido)
var _phase2_heartbeat_timer: float = 0.0
var _ctrl_cue_l: Node3D = null
var _ctrl_cue_r: Node3D = null
var pose_chest_ki_p1: bool = false
var pose_waist_ki_p2: bool = false
var pose_chest_guard: bool = false
var pose_wide_cross: bool = false
var pose_side_hip_galick: bool = false
var pose_hip_kame: bool = false
var pose_overhead_both: bool = false

# 3b. Bio-Hápticos de Ki y Transformación (Heartbeat continuo no invasivo)
var bio_haptic_timer: float = 0.0

# 4. Melee / Velocidades anteriores para aceleración (en espacio local del XROrigin3D)
var prev_left_pos: Vector3 = Vector3.ZERO
var prev_right_pos: Vector3 = Vector3.ZERO
var prev_left_local_pos: Vector3 = Vector3.ZERO
var prev_right_local_pos: Vector3 = Vector3.ZERO
var _has_prev_local_pos: bool = false
var left_velocity: Vector3 = Vector3.ZERO
var right_velocity: Vector3 = Vector3.ZERO
var melee_cooldown: float = 0.0
var left_punch_cocked: bool = false
var right_punch_cocked: bool = false
var super_cooldown: float = 0.0
var super_fatigue_timer: float = 0.0
var must_release_super_buttons: bool = false
var hud_toggle_cooldown: float = 0.0
var transform_cooldown: float = 0.0
var gesture_transform_timer: float = 0.0
var was_ax_pressed: bool = false
var was_by_pressed: bool = false
var startup_cooldown: float = 1.5
var recharge_exit_cooldown: float = 0.0 # Compuerta de gracia para evitar Ki Blasts indeseados al soltar gatillos de recarga
var is_charging_determination: bool = false
var determination_timer: float = 0.0
var determination_hit_cooldown: float = 0.0

# --- Movimiento por Casillas / Pasos (Yu Yu Hakusho / DB Legends / Ajedrez) ---
const STEP_DISTANCE: float = 3.0 # Metros por paso/casilla
const VERTICAL_STEP: float = 2.0 # Metros por salto o descenso en el aire
const MIN_ALLOWED_DISTANCE: float = 11.5 # Distancia mínima táctica en Modo Libre ("turnos en tiempo real")
const MAX_VERTICAL_HEIGHT: float = 9.0 # Límite superior de vuelo en metros
const MELEE_APPROACH_RANGE: float = 15.5
const MELEE_DECAY_RANGE: float = 16.5
var melee_approach_progress: float = 0.0
var step_cooldown: float = 0.0
var vertical_step_cooldown: float = 0.0
var right_stick_flicked: bool = false
var is_step_moving: bool = false
var step_audio_player: AudioStreamPlayer = null
var snd_step: AudioStream = null

# --- Frenado Aéreo (Air Brake agitando ambos controles físicos tras ser lanzado) ---
var _prev_air_l_vel: Vector3 = Vector3.ZERO
var _prev_air_r_vel: Vector3 = Vector3.ZERO
var _air_l_active_timer: float = 0.0
var _air_r_active_timer: float = 0.0
var _air_haptic_cd: float = 0.0
var _transform_progress_cd: float = 0.0
var _air_brake_root: Node3D = null
var _air_brake_fill_mesh: MeshInstance3D = null
var _air_brake_fill_mat: StandardMaterial3D = null
var _air_brake_label: Label3D = null

# Temporizador para comprobación periódica de estado en HUD
var status_pulse_timer: float = 0.0

const VRInGameMenuClass = preload("res://scripts/vr_in_game_menu.gd")
var in_game_menu: VRInGameMenu = null
var menu_toggle_cooldown: float = 0.0

const KiSenseAndLockOnClass = preload("res://scripts/ki_sense_and_lockon.gd")
var ki_lockon_system: KiSenseAndLockOn = null


func _ready() -> void:
	if not gesture_tree:
		gesture_tree = get_parent()
	_find_xr_nodes()

	step_audio_player = AudioStreamPlayer.new()
	step_audio_player.name = "StepAudioPlayer"
	add_child(step_audio_player)


func _exit_tree() -> void:
	if _air_brake_root and is_instance_valid(_air_brake_root):
		_air_brake_root.queue_free()
		_air_brake_root = null


func _find_xr_nodes() -> void:
	var scene_root: Node = get_tree().current_scene
	if not scene_root and get_tree():
		scene_root = get_tree().root
	if scene_root:
		xr_origin = scene_root.find_child("Player_XROrigin3D", true, false)
		if not xr_origin:
			xr_origin = scene_root.find_child("XROrigin3D", true, false)
			
	if xr_origin:
		camera = xr_origin.get_node_or_null("XRCamera3D")
		left_controller = xr_origin.get_node_or_null("LeftHand")
		right_controller = xr_origin.get_node_or_null("RightHand")

		if in_game_menu == null:
			var existing = xr_origin.find_child("VRInGameMenu", true, false)
			if not existing and get_tree() and get_tree().current_scene:
				existing = get_tree().current_scene.find_child("VRInGameMenu", true, false)
			if existing and existing is VRInGameMenu:
				in_game_menu = existing
			else:
				in_game_menu = VRInGameMenuClass.new()
				in_game_menu.name = "VRInGameMenu"
				xr_origin.add_child(in_game_menu)
			in_game_menu.setup_references(xr_origin, camera, left_controller, right_controller)

		if ki_lockon_system == null and get_tree() and get_tree().current_scene:
			ki_lockon_system = KiSenseAndLockOnClass.new()
			ki_lockon_system.name = "KiSenseAndLockOn"
			get_tree().current_scene.add_child.call_deferred(ki_lockon_system)
			var opp = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
			var ply = gesture_tree._get_player_instance() if gesture_tree else null
			ki_lockon_system.setup(camera, ply, opp, left_controller, right_controller)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
		
	if not xr_origin or not left_controller or not right_controller:
		_find_xr_nodes()
		if not left_controller or not right_controller:
			return

	# 1. Modo mandos de control Touch 100% activo (Hand Tracking óptico desactivado por estabilidad)
	controllers_active = true

	# Sincronizar el flag y los mandos con GesturePhaseTree para auto-switching y orígenes de proyectil
	if gesture_tree:
		gesture_tree.set("is_controller_override", true)
		gesture_tree.set("left_controller_node", left_controller)
		gesture_tree.set("right_controller_node", right_controller)

	# Notificar cambio de modo al HUD
	if controllers_active != last_reported_mode:
		last_reported_mode = controllers_active
		controller_mode_changed.emit(controllers_active)
		var mode_name = "MANDOS QUEST 3 (CONTROL TOTAL)"
		if gesture_tree and gesture_tree.has_signal("gesture_logged"):
			gesture_tree.emit_signal("gesture_logged", "[INPUT] Modo activo: " + mode_name, "info")

	# 2. Calcular velocidades lineales de los mandos en espacio local del XROrigin3D (inmune a knocksbacks/pasos)
	if delta > 0.0:
		var orig_basis: Basis = xr_origin.global_transform.basis.orthonormalized() if (xr_origin and is_instance_valid(xr_origin)) else Basis.IDENTITY
		var l_loc: Vector3 = left_controller.position
		var r_loc: Vector3 = right_controller.position
		if _has_prev_local_pos:
			left_velocity = orig_basis * ((l_loc - prev_left_local_pos) / delta)
			right_velocity = orig_basis * ((r_loc - prev_right_local_pos) / delta)
		prev_left_local_pos = l_loc
		prev_right_local_pos = r_loc
		_has_prev_local_pos = true
	prev_left_pos = left_controller.global_position
	prev_right_pos = right_controller.global_position

	# Calentamiento inicial de 1.5s: asienta tracking de OpenXR y descarta picos de aceleración
	if startup_cooldown > 0.0:
		startup_cooldown -= delta
		left_velocity = Vector3.ZERO
		right_velocity = Vector3.ZERO
		_process_hud_toggle(delta)
		return

	if determination_hit_cooldown > 0.0:
		determination_hit_cooldown = maxf(determination_hit_cooldown - delta, 0.0)

	if DramaticDirector.is_dramatic_pause_active:
		var dd_pause: DramaticDirector = DramaticDirector.get_active(get_tree())
		if dd_pause and dd_pause.is_in_intro:
			var skip_pressed: bool = (
				_ctrl_pressed(left_controller, &"ax_button")
				or _ctrl_pressed(left_controller, &"by_button")
				or _ctrl_pressed(right_controller, &"ax_button")
				or _ctrl_pressed(right_controller, &"by_button")
				or _ctrl_pressed(left_controller, &"trigger_click")
				or _ctrl_pressed(right_controller, &"trigger_click")
			)
			if skip_pressed:
				dd_pause.skip_dramatic_intro()
		left_velocity = Vector3.ZERO
		right_velocity = Vector3.ZERO
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		is_charging_determination = false
		determination_timer = 0.0
		if _air_brake_root and is_instance_valid(_air_brake_root):
			_air_brake_root.visible = false
		_process_hud_toggle(delta)
		return

	if melee_cooldown > 0.0:
		melee_cooldown -= delta
	if super_cooldown > 0.0:
		super_cooldown -= delta
	if super_fatigue_timer > 0.0:
		super_fatigue_timer -= delta
	if hud_toggle_cooldown > 0.0:
		hud_toggle_cooldown -= delta
	if transform_cooldown > 0.0:
		transform_cooldown -= delta
	if recharge_exit_cooldown > 0.0:
		recharge_exit_cooldown -= delta
	if super_unusable_warn_cooldown > 0.0:
		super_unusable_warn_cooldown -= delta
	if _transform_progress_cd > 0.0:
		_transform_progress_cd = maxf(_transform_progress_cd - delta, 0.0)
	if left_blast_cooldown > 0.0:
		left_blast_cooldown = maxf(left_blast_cooldown - delta, 0.0)
	if right_blast_cooldown > 0.0:
		right_blast_cooldown = maxf(right_blast_cooldown - delta, 0.0)

	# 3. Comprobación de estado Melee / Bullet-Time (Minijuego de cajas)
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	_update_body_space_metrics(player)
	var in_melee_minigame = player and (player.get("is_in_bullet_time") or player.get("is_flying_to_opponent") or player.get("is_flying_to_melee"))
	if in_melee_minigame:
		was_in_melee_minigame = true
		if _air_brake_root and is_instance_valid(_air_brake_root):
			_air_brake_root.visible = false
		# Durante el combate melee o minijuego de cajas se bloquean poderes y recarga de Ki,
		# pero SÍ se permite la Guardia (cruzar brazos) y el Desplazamiento evasivo (step back).
		_reset_super_state()
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
		if is_charging_ki:
			is_charging_ki = false
			if gesture_tree:
				gesture_tree._cancel_action("En combate cuerpo a cuerpo")
				gesture_tree._reset_to_idle()
		_process_guard()
		_process_hud_toggle(delta)
		return

	# Si acabamos de salir de una fase de melee, resetear estados y activar protecciones limpias
	if was_in_melee_minigame:
		was_in_melee_minigame = false
		melee_cooldown = 0.5
		left_punch_cocked = false
		right_punch_cocked = false
		must_release_super_buttons = true
		_reset_super_state()
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		is_charging_ki = false
		ki_prep_phase = false
		if gesture_tree:
			gesture_tree._reset_to_idle()

	# Fix 2: Procesar Frenado Aéreo mientras el jugador vuela lanzado por impacto
	_process_air_brake(delta, player)

	# Bloqueo mutuo estricto: durante Choque de Poderes o Secuencia de Super Haz se bloquean otras acciones
	if _is_exclusive_combat_sequence_active(player):
		_reset_super_state()
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
		if is_charging_ki or ki_prep_phase:
			is_charging_ki = false
			ki_prep_phase = false
			if gesture_tree:
				gesture_tree._cancel_action("Secuencia exclusiva en curso")
				gesture_tree._reset_to_idle()
		left_punch_cocked = false
		right_punch_cocked = false
		_process_hud_toggle(delta)
		return

	# Mientras el jugador sale volando / ragdoll / incrustado, no puede realizar acciones de combate
	if player and player.has_method("is_airborne_incapacitated") and player.is_airborne_incapacitated():
		_reset_super_state()
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
		if is_charging_ki:
			is_charging_ki = false
			ki_prep_phase = false
		_process_hud_toggle(delta)
		return

	# 4. Procesar las acciones híbridas en combate libre
	_process_melee_approach_bar(delta, player)
	_process_determination(delta)
	_process_ki_recharge(delta)
	_process_melee_punches()
	_process_ki_blasts(delta)
	if not is_charging_determination:
		_process_super_powers(delta)
	_process_transformations()
	_process_grid_step_movement(delta)
	_process_hud_toggle(delta)
	if not is_charging_determination:
		_process_guard()
	_process_bio_haptics(delta)


# --- 1. RECARGA DE KI (2 FASES: Gatillos a Hombros -> Descenso a Cintura/Cadera) ---
func _is_exclusive_combat_sequence_active(player: Node) -> bool:
	if DramaticDirector.is_dramatic_pause_active:
		return true
	if player and is_instance_valid(player):
		if bool(player.get("is_in_beam_clash")) or bool(player.get("is_in_beam_sequence")):
			return true
		if bool(player.get("is_in_bullet_time")) or bool(player.get("is_flying_to_melee")) or bool(player.get("is_flying_to_opponent")):
			return true
	return false


func _process_melee_approach_bar(delta: float, player: Node) -> void:
	if not player or not is_instance_valid(player) or bool(player.get("is_match_over")):
		melee_approach_progress = maxf(melee_approach_progress - delta * 0.35, 0.0)
		if player and is_instance_valid(player):
			player.set("melee_approach_progress", melee_approach_progress)
		return

	var opp: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
	if not opp or not is_instance_valid(opp) or bool(opp.get("is_in_bullet_time")) or (opp.has_method("is_airborne_incapacitated") and opp.is_airborne_incapacitated()):
		melee_approach_progress = maxf(melee_approach_progress - delta * 0.25, 0.0)
		player.set("melee_approach_progress", melee_approach_progress)
		return

	var p_xz := Vector2(player.global_position.x, player.global_position.z)
	var o_xz := Vector2(opp.global_position.x, opp.global_position.z)
	var dist_xz: float = p_xz.distance_to(o_xz)

	if dist_xz <= MELEE_APPROACH_RANGE:
		var closeness: float = clampf((MELEE_APPROACH_RANGE - dist_xz) / 4.0, 0.0, 1.0)
		var fill_rate: float = lerpf(0.14, 0.34, closeness)
		melee_approach_progress = minf(melee_approach_progress + fill_rate * delta, 1.0)
	elif dist_xz > MELEE_DECAY_RANGE:
		melee_approach_progress = maxf(melee_approach_progress - delta * 0.18, 0.0)

	player.set("melee_approach_progress", melee_approach_progress)
	if melee_approach_progress >= 1.0 and melee_cooldown <= 0.0:
		melee_approach_progress = 0.0
		player.set("melee_approach_progress", 0.0)
		var bp_p: float = maxf(float(player.get("current_np")) if player.get("current_np") != null else 10000.0, 100.0)
		var bp_e: float = maxf(float(opp.get("current_np")) if opp.get("current_np") != null else 10000.0, 100.0)
		var p_atk_prob: float = clampf(bp_p / (bp_p + bp_e), 0.30, 0.70)
		var player_attacks: bool = randf() < p_atk_prob
		if player_attacks and player.has_method("_start_melee_bullet_time"):
			player._start_melee_bullet_time(opp)
		elif not player_attacks and opp.has_method("_start_melee_bullet_time"):
			opp._start_melee_bullet_time(player)


func _update_body_space_metrics(player: Node) -> void:
	if not left_controller or not right_controller or (not xr_origin and not camera):
		return
	body_scale = clampf(xr_origin.scale.y, 0.70, 1.40) if (xr_origin and is_instance_valid(xr_origin)) else 1.0
	inv_body_scale = 1.0 / body_scale

	cam_pos_cached = camera.global_position if (camera and is_instance_valid(camera)) else (xr_origin.global_position + Vector3(0.0, 1.6 * body_scale, 0.0))
	var raw_cam_fwd: Vector3 = -camera.global_transform.basis.z if (camera and is_instance_valid(camera)) else -xr_origin.global_transform.basis.z
	raw_cam_fwd.y = 0.0
	cam_fwd_flat = raw_cam_fwd.normalized() if raw_cam_fwd.length_squared() > 0.001 else Vector3.FORWARD

	var yaw: float = _get_torso_yaw(player)
	var t_basis: Basis = Basis(Vector3.UP, yaw)
	var tf: Vector3 = -t_basis.z
	tf.y = 0.0
	torso_fwd = tf.normalized() if tf.length_squared() > 0.001 else cam_fwd_flat
	var tr: Vector3 = t_basis.x
	tr.y = 0.0
	torso_right = tr.normalized() if tr.length_squared() > 0.001 else Vector3.RIGHT

	chest_pos_cached = cam_pos_cached - Vector3(0.0, 0.28 * body_scale, 0.0)

	var l_pos: Vector3 = left_controller.global_position
	var r_pos: Vector3 = right_controller.global_position
	var l_rel: Vector3 = (l_pos - chest_pos_cached) * inv_body_scale
	var r_rel: Vector3 = (r_pos - chest_pos_cached) * inv_body_scale
	l_torso_pos = Vector3(l_rel.dot(torso_right), l_rel.y, l_rel.dot(torso_fwd))
	r_torso_pos = Vector3(r_rel.dot(torso_right), r_rel.y, r_rel.dot(torso_fwd))
	avg_torso_pos = (l_torso_pos + r_torso_pos) * 0.5

	l_cam_rel_y = (l_pos.y - cam_pos_cached.y) * inv_body_scale
	r_cam_rel_y = (r_pos.y - cam_pos_cached.y) * inv_body_scale
	l_cam_fwd_proj = (l_pos - cam_pos_cached).dot(cam_fwd_flat) * inv_body_scale
	r_cam_fwd_proj = (r_pos - cam_pos_cached).dot(cam_fwd_flat) * inv_body_scale
	hands_dist_norm = l_pos.distance_to(r_pos) * inv_body_scale

	var l_vn: Vector3 = left_velocity * inv_body_scale
	var r_vn: Vector3 = right_velocity * inv_body_scale
	l_torso_vel = Vector3(l_vn.dot(torso_right), l_vn.y, l_vn.dot(torso_fwd))
	r_torso_vel = Vector3(r_vn.dot(torso_right), r_vn.y, r_vn.dot(torso_fwd))

	var avg_cam_rel_y: float = (l_cam_rel_y + r_cam_rel_y) * 0.5
	var in_front_shoulders: bool = (l_cam_fwd_proj >= 0.14 and r_cam_fwd_proj >= 0.14) and (absf(l_torso_pos.x) < 0.45 and absf(r_torso_pos.x) < 0.45) and hands_dist_norm <= 0.48
	var at_shoulder_height: bool = (l_cam_rel_y > -0.38 and r_cam_rel_y > -0.38 and l_cam_rel_y < 0.18 and r_cam_rel_y < 0.18)
	pose_chest_ki_p1 = in_front_shoulders and at_shoulder_height
	pose_waist_ki_p2 = (avg_cam_rel_y <= -0.28) and (hands_dist_norm >= 0.16)
	pose_chest_guard = (avg_cam_rel_y > -0.35 and avg_cam_rel_y < 0.22 and hands_dist_norm < 0.38 and absf(avg_torso_pos.x) < 0.22 and l_cam_fwd_proj >= 0.10 and r_cam_fwd_proj >= 0.10)
	pose_wide_cross = (hands_dist_norm >= 0.52 and l_torso_pos.x <= -0.22 and r_torso_pos.x >= 0.22 and avg_torso_pos.y >= -0.24 and avg_torso_pos.y <= 0.38 and l_torso_pos.z >= -0.18 and r_torso_pos.z >= -0.18)
	pose_side_hip_galick = (hands_dist_norm <= 0.38 and absf(avg_torso_pos.x) >= 0.14 and avg_torso_pos.y >= -0.28 and avg_torso_pos.y <= 0.34 and (l_torso_pos.z >= -0.18 or r_torso_pos.z >= -0.18))
	pose_hip_kame = (hands_dist_norm <= 0.36 and avg_torso_pos.y <= -0.04 and (absf(avg_torso_pos.x) >= 0.10 or avg_torso_pos.z <= 0.28))
	pose_overhead_both = (l_cam_rel_y >= 0.20 and r_cam_rel_y >= 0.20 and hands_dist_norm >= 0.24)


func _process_ki_recharge(delta: float) -> void:
	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.45 or _ctrl_pressed(left_controller, &"trigger_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.45 or _ctrl_pressed(right_controller, &"trigger_click")
	var triggers_held: bool = l_trig and r_trig

	# Si ambos gatillos están sostenidos y no hay super poder en curso
	if triggers_held and current_super_state == SuperPowerState.IDLE:
		var avg_rel_y: float = (l_cam_rel_y + r_cam_rel_y) * 0.5

		# Solo cancelar si las manos están claramente detrás de la espalda
		if l_cam_fwd_proj < -0.22 and r_cam_fwd_proj < -0.22:
			if (is_charging_ki or ki_prep_phase) and gesture_tree:
				gesture_tree._cancel_action("Recarga de Ki cancelada (manos detrás de la espalda)")
				gesture_tree._reset_to_idle()
				gesture_tree.sync_controller_gesture_state("IDLE")
			ki_prep_phase = false
			is_charging_ki = false
			return

		# FASE 1: Concentración a la altura de los hombros o pecho (manos recogidas, nunca extendidas disparando Ki Blasts)
		var l_palm_fwd_rec: bool = _is_arm_extended_palm_forward(left_controller, true, 0.35, 0.36, 0.30)
		var r_palm_fwd_rec: bool = _is_arm_extended_palm_forward(right_controller, false, 0.35, 0.36, 0.30)
		if not is_charging_ki:
			if not ki_prep_phase and not left_is_charging and not right_is_charging:
				if pose_chest_ki_p1 and not l_palm_fwd_rec and not r_palm_fwd_rec:
					ki_prep_phase = true
					if gesture_tree:
						gesture_tree.sync_controller_gesture_state("RECHARGE_PREP")
						if gesture_tree.has_signal("phase_changed"):
							gesture_tree.emit_signal("phase_changed", "RECARGA KI: FASE 1 (HOMBROS)")
						if gesture_tree.has_signal("gesture_logged"):
							gesture_tree.emit_signal("gesture_logged", "[KI] Fase 1: Concentración delante de los hombros. ¡Baja los puños a la cintura!", "info")
					_pulse_haptic(left_controller, 70.0, 0.40, 0.12)
					_pulse_haptic(right_controller, 70.0, 0.40, 0.12)
			else:
				# Si durante la Fase 1 extiende las palmas hacia adelante o rompe la pose sin descender a la cintura, cancelar
				if (not pose_chest_ki_p1 and avg_rel_y > -0.26) or (l_palm_fwd_rec and r_palm_fwd_rec):
					ki_prep_phase = false
					if gesture_tree:
						gesture_tree._cancel_action("Recarga cancelada (manos fuera de posición)")
						gesture_tree._reset_to_idle()
						gesture_tree.sync_controller_gesture_state("IDLE")
					return

				# Pulso háptico rítmico indicando concentración en Fase 1
				ki_haptic_timer += delta
				if ki_haptic_timer >= 0.08:
					ki_haptic_timer = 0.0
					_pulse_haptic(left_controller, 65.0, 0.40, 0.10)
					_pulse_haptic(right_controller, 65.0, 0.40, 0.10)

				# FASE 2: Detonación de Ki al descender las manos/muñecas a la cintura o caderas
				if pose_waist_ki_p2 or avg_rel_y <= -0.28:
					is_charging_ki = true
					ki_prep_phase = false
					ki_haptic_timer = 0.0
					# ¡PUNTO 8: EFECTO HÁPTICO DE IMPACTO AL PASAR DE FASE 1 A FASE 2!
					_pulse_haptic(left_controller, 180.0, 1.0, 0.35)
					_pulse_haptic(right_controller, 180.0, 1.0, 0.35)
					if gesture_tree:
						gesture_tree._trigger_action("recarga_ki")
						gesture_tree.sync_controller_gesture_state("IDLE")
						if gesture_tree.has_signal("phase_changed"):
							gesture_tree.emit_signal("phase_changed", "¡RECARGA DE KI ACTIVA! (CINTURA)")

		# Mantenimiento activo de la Fase 2 (Carga Máxima de Ki y BP con techo del 60%)
		if is_charging_ki:
			var player = gesture_tree._get_player_instance() if gesture_tree else null
			if player and is_instance_valid(player):
				var cfg: KiEconomyConfig = KiEconomyConfig.get_default()
				player.recharge_ki(cfg.charge_ki_per_sec_heavy * delta)
				if player.has_method("increase_np_from_charge"):
					player.increase_np_from_charge(cfg.charge_bp_per_sec_heavy * delta)
				else:
					player.increase_np(cfg.charge_bp_per_sec_heavy * delta)
			# ¡PUNTO 9: RUMBLE HÁPTICO PROFUNDO Y CONTINUO DE KI!
			ki_haptic_timer += delta
			if ki_haptic_timer >= 0.08:
				ki_haptic_timer = 0.0
				_pulse_haptic(left_controller, 130.0, 0.85, 0.12)
				_pulse_haptic(right_controller, 130.0, 0.85, 0.12)
	else:
		# Soltar los gatillos cancela o finaliza la recarga
		if is_charging_ki or ki_prep_phase:
			if gesture_tree:
				if is_charging_ki:
					gesture_tree._cancel_action("Recarga de Ki finalizada (Gatillos soltados)")
					gesture_tree._reset_to_idle()
				gesture_tree.sync_controller_gesture_state("IDLE")
			ki_prep_phase = false
			is_charging_ki = false
			left_charge_time = 0.0
			right_charge_time = 0.0
			left_is_charging = false
			right_is_charging = false
			recharge_exit_cooldown = 0.25 # Ventana debounce de 250ms para evitar Ki Blast accidental al soltar gatillos asincrónicamente
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)


# --- MÉTODOS AUXILIARES BIOMÉTRICOS ---
func _is_arm_extended(controller: XRController3D) -> bool:
	if not controller or not camera:
		return false
	var cam_pos = camera.global_position
	var ctrl_pos = controller.global_position
	var dist = cam_pos.distance_to(ctrl_pos)
	var cam_fwd = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() > 0.001:
		cam_fwd = cam_fwd.normalized()
	else:
		cam_fwd = Vector3.FORWARD
	var to_ctrl = (ctrl_pos - cam_pos)
	var forward_proj = to_ctrl.dot(cam_fwd)
	
	# El brazo está extendido al frente si proyecta al menos 0.35m adelante y dist 3D >= 0.38m
	return forward_proj >= 0.35 and dist >= 0.38


func _get_controller_palm_world_dir(controller: XRController3D, is_left: bool) -> Vector3:
	if not controller:
		return Vector3.FORWARD
	# Alineado con _compute_hand_align_basis en character_instance.gd: palma hacia +X (izq) o -X (der)
	var b: Basis = controller.global_transform.basis
	return (b.x if is_left else -b.x).normalized()


func _is_arm_extended_palm_forward(
	controller: XRController3D,
	is_left: bool,
	min_palm_dot: float = 0.45,
	min_reach: float = 0.40,
	min_fwd: float = 0.34
) -> bool:
	if not controller or not is_instance_valid(controller):
		return false
	var hand_from_chest: float = controller.global_position.distance_to(chest_pos_cached) * inv_body_scale
	var hand_torso: Vector3 = l_torso_pos if is_left else r_torso_pos
	var hand_cam_z: float = l_cam_fwd_proj if is_left else r_cam_fwd_proj
	var cam_fwd_3d: Vector3 = (-camera.global_transform.basis.z).normalized() if (camera and is_instance_valid(camera)) else cam_fwd_flat
	var palm_dir: Vector3 = _get_controller_palm_world_dir(controller, is_left)
	return (
		hand_from_chest >= min_reach
		and maxf(hand_torso.z, hand_cam_z) >= min_fwd
		and absf(hand_torso.x) <= 0.62
		and hand_torso.y >= -0.35
		and hand_torso.y <= 0.55
		and palm_dir.dot(cam_fwd_3d) >= min_palm_dot
	)


# --- 2. KI BLASTS (Izquierda y Derecha) ---
func _process_ki_blasts(delta: float) -> void:
	# Bloqueo total si se está recargando Ki, en preparación, en debounce de salida (250ms) o cargando super poder
	if is_charging_ki or ki_prep_phase or recharge_exit_cooldown > 0.0 or current_super_state != SuperPowerState.IDLE:
		if left_is_charging or right_is_charging:
			if gesture_tree:
				gesture_tree._cleanup_ki_blast_charge_sphere(0)
				gesture_tree._cleanup_ki_blast_charge_sphere(1)
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		return

	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.35 or _ctrl_pressed(left_controller, &"trigger_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.35 or _ctrl_pressed(right_controller, &"trigger_click")

	# Si ambos gatillos están presionados en pose de recarga (pecho/cintura sin palmas extendidas), ceder a Recarga de Ki;
	# si las palmas están extendidas adelante, permitir fuego bimanual alternado/simultáneo fluido
	var l_palm_fwd_kb: bool = _is_arm_extended_palm_forward(left_controller, true, 0.35, 0.36, 0.30)
	var r_palm_fwd_kb: bool = _is_arm_extended_palm_forward(right_controller, false, 0.35, 0.36, 0.30)
	if l_trig and r_trig and (pose_chest_ki_p1 or pose_waist_ki_p2) and not l_palm_fwd_kb and not r_palm_fwd_kb and not left_is_charging and not right_is_charging:
		return

	# Si ambos mandos tienen Grip presionado y no hay Ki Blast cargando, es Super Poder o Guardia
	var l_grip: bool = _ctrl_float(left_controller, &"grip") > 0.50 or _ctrl_pressed(left_controller, &"grip_click")
	var r_grip: bool = _ctrl_float(right_controller, &"grip") > 0.50 or _ctrl_pressed(right_controller, &"grip_click")
	if l_grip and r_grip and not left_is_charging and not right_is_charging:
		return

	# Mano Izquierda (solo gatillo izquierdo)
	_process_single_ki_blast(left_controller, 0, delta)
	# Mano Derecha (solo gatillo derecho)
	_process_single_ki_blast(right_controller, 1, delta)

	# Si ninguna mano está cargando Ki Blast y no hay Super Poder cargando, ocultar la mira
	if not left_is_charging and not right_is_charging and current_super_state == SuperPowerState.IDLE:
		if gesture_tree:
			gesture_tree._hide_aim_reticle()


func _process_single_ki_blast(controller: XRController3D, hand_side: int, delta: float) -> void:
	var trig_val = _ctrl_float(controller, &"trigger")
	var trig_pressed = trig_val > 0.65 or _ctrl_pressed(controller, &"trigger_click")
	var grip_pressed: bool = _ctrl_float(controller, &"grip") > 0.40 or _ctrl_pressed(controller, &"grip_click")
	var is_left = (hand_side == 0)

	# Si la mano cierra Grip (puño para Melee o Big Bang), NUNCA iniciar ni disparar Ki Blast accidentalmente
	if grip_pressed:
		var had_charge: bool = left_is_charging if is_left else right_is_charging
		if had_charge and gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(hand_side)
		if is_left:
			left_charge_time = 0.0
			left_is_charging = false
			left_blast_locked_haptic = false
		else:
			right_charge_time = 0.0
			right_is_charging = false
			right_blast_locked_haptic = false
		return

	var ctrl_p: Vector3 = controller.global_position
	var palm_dir: Vector3 = _get_controller_palm_world_dir(controller, is_left)

	# REQUISITO CANÓNICO: Brazo extendido al frente y palma orientada hacia adelante (solo Trigger, sin Grip)
	var was_charging: bool = left_is_charging if is_left else right_is_charging
	var hand_cd: float = left_blast_cooldown if is_left else right_blast_cooldown
	var is_arm_extended: bool = _is_arm_extended_palm_forward(controller, is_left, 0.45, 0.40, 0.34)
	var can_continue_charge: bool = was_charging and _is_arm_extended_palm_forward(controller, is_left, 0.25, 0.34, 0.24)
	var can_start_or_charge: bool = can_continue_charge or (is_arm_extended and (was_charging or hand_cd <= 0.0))

	if trig_pressed and can_start_or_charge:
		var aim_origin: Vector3 = ctrl_p
		var cam_dir_3d: Vector3 = (-camera.global_transform.basis.z).normalized() if (camera and is_instance_valid(camera)) else cam_fwd_flat
		var shoulder_pos: Vector3 = cam_pos_cached - Vector3(0.0, 0.16 * body_scale, 0.0)
		var arm_v: Vector3 = aim_origin - shoulder_pos
		var arm_dir: Vector3 = arm_v.normalized() if arm_v.length_squared() > 0.001 else cam_dir_3d
		var safe_palm_dir: Vector3 = palm_dir if palm_dir.dot(cam_dir_3d) >= 0.0 else cam_dir_3d
		var raw_hand_dir: Vector3 = (cam_dir_3d * 0.45 + safe_palm_dir * 0.35 + arm_dir * 0.20).normalized()

		# Consumir Ki mientras carga. Si no queda Ki, quema vital (BP)
		var player = gesture_tree._get_player_instance() if gesture_tree else null
		if player and is_instance_valid(player):
			if player.current_ki > 0.0:
				var ki_drain = KiEconomyConfig.get_default().ki_blast_charge_drain_per_sec * delta
				player.consume_ki(ki_drain)
			else:
				var vital_drain = 80.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
				_pulse_haptic(controller, 130.0, 0.70, delta)

		var blast_spd_mult: float = player.get_dramatic_modifier("blast_charge_speed_mult", 1.0) if (player and is_instance_valid(player) and player.has_method("get_dramatic_modifier")) else 1.0
		if is_left:
			var was_left_charging: bool = left_is_charging
			left_charge_time += delta * blast_spd_mult
			left_is_charging = true
			if not was_left_charging and gesture_tree:
				gesture_tree.sync_controller_gesture_state("ARM_STRETCHED_OPEN_LEFT")
			if left_charge_time >= 0.45 and not left_blast_locked_haptic:
				left_blast_locked_haptic = true
				_pulse_haptic(controller, 140.0, 0.85, 0.12)
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡KI BLAST IZQ CARGADO LISTO!")

			if gesture_tree:
				gesture_tree._update_ki_blast_charge_sphere(0, left_charge_time, delta)
				gesture_tree.emit_signal("ki_blast_charging", 0, left_charge_time, delta)
				gesture_tree._update_aim_reticle(aim_origin, raw_hand_dir, Color(0.1, 0.8, 1.0), false)
			_pulse_haptic(controller, 100.0, clamp(0.15 + left_charge_time * 0.4, 0.15, 0.95), delta)
		else:
			var was_right_charging: bool = right_is_charging
			right_charge_time += delta * blast_spd_mult
			right_is_charging = true
			if not was_right_charging and gesture_tree:
				gesture_tree.sync_controller_gesture_state("ARM_STRETCHED_OPEN_RIGHT")
			if right_charge_time >= 0.45 and not right_blast_locked_haptic:
				right_blast_locked_haptic = true
				_pulse_haptic(controller, 140.0, 0.85, 0.12)
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "¡KI BLAST DER CARGADO LISTO!")

			if gesture_tree:
				gesture_tree._update_ki_blast_charge_sphere(1, right_charge_time, delta)
				gesture_tree.emit_signal("ki_blast_charging", 1, right_charge_time, delta)
				gesture_tree._update_aim_reticle(aim_origin, raw_hand_dir, Color(1.0, 0.7, 0.1), false)
			_pulse_haptic(controller, 100.0, clamp(0.15 + right_charge_time * 0.4, 0.15, 0.95), delta)
	else:
		# Gatillo soltado o brazo retirado: Evaluar disparo (tap rápido o disparo cargado)
		var held_time = left_charge_time if is_left else right_charge_time

		# Solo dispara si se mantuvo cargando al menos 0.025s (acepta taps rápidos de gatillo)
		if held_time >= 0.025:
			var is_charged = held_time >= 0.45
			var action_name = "ki_blast_left" if is_left else "ki_blast_right"
			var player_cd: Node = gesture_tree._get_player_instance() if gesture_tree else null
			var c_data_cd = player_cd.get("character_data") if (player_cd and is_instance_valid(player_cd)) else null
			var is_veg_cd: bool = c_data_cd != null and "VEGETA" in String(c_data_cd.character_name).to_upper()
			var shot_cd: float = 0.25 if is_charged else (0.125 if is_veg_cd else 0.15)
			if is_left:
				left_blast_cooldown = shot_cd
			else:
				right_blast_cooldown = shot_cd

			if gesture_tree:
				gesture_tree.set("last_firing_controller", controller)
				gesture_tree.set("last_firing_hand_side", hand_side)
				if is_left:
					gesture_tree.set("ki_blast_charge_time_left", held_time)
				else:
					gesture_tree.set("ki_blast_charge_time_right", held_time)
				gesture_tree._trigger_action(action_name)

			var recoil_amp = 0.95 if is_charged else 0.60
			var recoil_time = 0.18 if is_charged else 0.08
			_pulse_haptic(controller, 160.0, recoil_amp, recoil_time)

		# Limpiar esfera visual de carga en la palma
		if gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(hand_side)

		# Reset de variables de carga de esa mano
		var was_hand_charging: bool = left_is_charging if is_left else right_is_charging
		if is_left:
			left_charge_time = 0.0
			left_is_charging = false
			left_blast_locked_haptic = false
		else:
			right_charge_time = 0.0
			right_is_charging = false
			right_blast_locked_haptic = false
		if was_hand_charging and gesture_tree and not left_is_charging and not right_is_charging:
			gesture_tree.sync_controller_gesture_state("IDLE")


# --- 3. SUPER PODERES (Galick Ho / Final Flash / Big Bang Attack / Kamehameha / Genkidama) ---
# Sistema canónico de 2 fases: Fase 1 (Carga en torso-space) + Fase 2 (Auto-disparo "¡HAAA!" al proyectar postura)
func _get_torso_yaw(player: Node) -> float:
	var origin_yaw: float = xr_origin.global_rotation.y if (xr_origin and is_instance_valid(xr_origin)) else 0.0
	if player and is_instance_valid(player) and player.get("torso_yaw") != null:
		return origin_yaw + float(player.get("torso_yaw"))
	if camera and is_instance_valid(camera):
		return camera.global_rotation.y
	return origin_yaw


func _is_super_tech_usable(player: Node, tech_name: String) -> bool:
	if not player or not is_instance_valid(player):
		return true
	if not player.has_method("is_power_usable"):
		return true
	var cdata = player.get("character_data")
	if not cdata or cdata.get("powers") == null:
		return true
	var found_any: bool = false
	for p in cdata.powers:
		if p == null:
			continue
		if String(p.gesture_trigger) == tech_name:
			found_any = true
			if player.is_power_usable(p):
				return true
	return not found_any


func _record_and_smooth_aim_dir(raw_dir: Vector3) -> Vector3:
	if _aim_dir_history.size() != 15:
		_aim_dir_history.resize(15)
		_aim_dir_cursor = 0
		_aim_dir_filled = 0
	var n_dir: Vector3 = raw_dir.normalized() if raw_dir.length_squared() > 0.0001 else Vector3.FORWARD
	_aim_dir_history[_aim_dir_cursor] = n_dir
	_aim_dir_cursor = (_aim_dir_cursor + 1) % 15
	_aim_dir_filled = mini(_aim_dir_filled + 1, 15)
	var acc := Vector3.ZERO
	for i in range(_aim_dir_filled):
		acc += _aim_dir_history[i]
	return acc.normalized() if acc.length_squared() > 0.0001 else n_dir


func _compute_super_raw_aim_dir(tech_name: String, is_launch_moment: bool) -> Vector3:
	var cam_dir: Vector3 = (-camera.global_transform.basis.z).normalized() if (camera and is_instance_valid(camera)) else torso_fwd
	var shoulder_pos: Vector3 = cam_pos_cached - Vector3(0.0, 0.16 * body_scale, 0.0)
	var raw: Vector3 = cam_dir
	if tech_name == "big_bang":
		var bb_side: int = int(gesture_tree.get("big_bang_hand")) if gesture_tree else 1
		var bb_ctrl: XRController3D = left_controller if bb_side == 0 else right_controller
		if bb_ctrl and is_instance_valid(bb_ctrl):
			var arm_v: Vector3 = bb_ctrl.global_position - shoulder_pos
			var arm_dir: Vector3 = arm_v.normalized() if arm_v.length_squared() > 0.001 else cam_dir
			var palm_dir: Vector3 = _get_controller_palm_world_dir(bb_ctrl, bb_side == 0)
			if palm_dir.dot(cam_dir) < 0.0:
				palm_dir = cam_dir
			raw = (cam_dir * 0.45 + palm_dir * 0.35 + arm_dir * 0.20).normalized()
	elif tech_name == "genkidama":
		if is_launch_moment and left_controller and right_controller and avg_torso_pos.z >= 0.16:
			var mid_h: Vector3 = (left_controller.global_position + right_controller.global_position) * 0.5
			var c2h: Vector3 = mid_h - shoulder_pos
			var hand_dir: Vector3 = c2h.normalized() if c2h.length_squared() > 0.001 else cam_dir
			raw = (cam_dir * 0.65 + hand_dir * 0.35).normalized()
	elif is_launch_moment or (avg_torso_pos.z >= 0.25 and hands_dist_norm <= 0.50):
		if left_controller and right_controller:
			var mid_hands: Vector3 = (left_controller.global_position + right_controller.global_position) * 0.5
			var arm_v_2: Vector3 = mid_hands - shoulder_pos
			var shoulder_dir_2: Vector3 = arm_v_2.normalized() if arm_v_2.length_squared() > 0.001 else cam_dir
			var palms_sum: Vector3 = _get_controller_palm_world_dir(left_controller, true) + _get_controller_palm_world_dir(right_controller, false)
			var palms_dir: Vector3 = palms_sum.normalized() if (palms_sum.length_squared() > 0.01 and palms_sum.dot(cam_dir) > 0.0) else cam_dir
			raw = (cam_dir * 0.50 + palms_dir * 0.30 + shoulder_dir_2 * 0.20).normalized()
	return _record_and_smooth_aim_dir(raw)


func _update_guide_laser(start_pos: Vector3, end_pos: Vector3, col: Color) -> void:
	if _guide_laser_mesh == null or not is_instance_valid(_guide_laser_mesh):
		_guide_laser_mesh = MeshInstance3D.new()
		_guide_laser_mesh.name = "SuperGuideLaser"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.012
		cyl.height = 1.0
		cyl.radial_segments = 8
		_guide_laser_mesh.mesh = cyl
		_guide_laser_mat = StandardMaterial3D.new()
		_guide_laser_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_guide_laser_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		_guide_laser_mat.no_depth_test = true
		_guide_laser_mesh.material_override = _guide_laser_mat
		var scene_r: Node = get_tree().current_scene if get_tree() else null
		if scene_r:
			scene_r.add_child(_guide_laser_mesh)
	if not _guide_laser_mesh.is_inside_tree():
		return
	var diff: Vector3 = end_pos - start_pos
	var dist: float = diff.length()
	if dist < 0.05:
		_guide_laser_mesh.visible = false
		return
	_guide_laser_mesh.visible = true
	_guide_laser_mesh.global_position = (start_pos + end_pos) * 0.5
	_guide_laser_mesh.look_at(end_pos, Vector3.UP)
	_guide_laser_mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_guide_laser_mesh.scale = Vector3(1.0, dist, 1.0)
	if _guide_laser_mat:
		_guide_laser_mat.albedo_color = Color(col.r, col.g, col.b, 0.75)


func _hide_guide_laser() -> void:
	if _guide_laser_mesh and is_instance_valid(_guide_laser_mesh):
		_guide_laser_mesh.visible = false


func _ensure_ctrl_cue(ctrl: XRController3D, is_left: bool) -> Node3D:
	var cached: Node3D = _ctrl_cue_l if is_left else _ctrl_cue_r
	if cached and is_instance_valid(cached):
		return cached
	if not ctrl or not is_instance_valid(ctrl):
		return null
	var root := Node3D.new()
	root.name = "Phase2CueRoot"
	root.visible = false
	ctrl.add_child(root)

	var ring := MeshInstance3D.new()
	ring.name = "ChargeRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.052
	torus.outer_radius = 0.068
	torus.rings = 16
	torus.ring_segments = 8
	ring.mesh = torus
	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	r_mat.no_depth_test = true
	ring.material_override = r_mat
	root.add_child(ring)

	var arrow := MeshInstance3D.new()
	arrow.name = "Phase2Arrow"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.022
	cone.height = 0.055
	cone.radial_segments = 8
	arrow.mesh = cone
	arrow.position = Vector3(0.0, 0.05, -0.09)
	arrow.rotation.x = -PI * 0.5
	var a_mat := StandardMaterial3D.new()
	a_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	a_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	a_mat.no_depth_test = true
	a_mat.albedo_color = Color(1.0, 0.92, 0.2, 0.95)
	arrow.material_override = a_mat
	arrow.visible = false
	root.add_child(arrow)

	var lbl := Label3D.new()
	lbl.name = "Phase2Label"
	lbl.text = "▶ EMPUJA"
	lbl.font_size = 24
	lbl.pixel_size = 0.0014
	lbl.outline_size = 8
	lbl.no_depth_test = true
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0.0, 0.11, -0.04)
	lbl.modulate = Color(1.0, 0.92, 0.25)
	lbl.visible = false
	root.add_child(lbl)

	if is_left:
		_ctrl_cue_l = root
	else:
		_ctrl_cue_r = root
	return root


func _update_controller_phase2_cues(tech_name: String, ratio: float, is_ready: bool, bb_side: int) -> void:
	var use_l: bool = (tech_name != "big_bang") or (bb_side == 0)
	var use_r: bool = (tech_name != "big_bang") or (bb_side == 1)
	var col: Color = Color(0.2, 0.8, 1.0)
	if tech_name == "galick_ho":
		col = Color(0.85, 0.25, 1.0)
	elif tech_name == "final_flash" or tech_name == "big_bang":
		col = Color(1.0, 0.88, 0.18)

	var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.025) * 0.16
	for idx in range(2):
		var ctrl: XRController3D = left_controller if idx == 0 else right_controller
		var active: bool = use_l if idx == 0 else use_r
		var cue: Node3D = _ensure_ctrl_cue(ctrl, idx == 0)
		if not cue:
			continue
		cue.visible = active
		if not active:
			continue
		var ring: MeshInstance3D = cue.get_node_or_null("ChargeRing") as MeshInstance3D
		var arrow: MeshInstance3D = cue.get_node_or_null("Phase2Arrow") as MeshInstance3D
		var lbl: Label3D = cue.get_node_or_null("Phase2Label") as Label3D
		if ring:
			var sc: float = lerpf(0.45, 1.0, ratio) * (pulse if is_ready else 1.0)
			ring.scale = Vector3(sc, sc, sc)
			var r_mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
			if r_mat:
				r_mat.albedo_color = Color(1.0, 0.92, 0.25, 0.95) if is_ready else Color(col.r, col.g, col.b, 0.45 + ratio * 0.4)
		if arrow:
			arrow.visible = is_ready
			if is_ready:
				if tech_name == "genkidama":
					arrow.rotation.x = PI
					arrow.position = Vector3(0.0, -0.06, -0.06)
				else:
					arrow.rotation.x = -PI * 0.5
					arrow.position = Vector3(0.0, 0.05, -0.09)
		if lbl:
			lbl.visible = is_ready
			if is_ready:
				lbl.text = "▼ BAJA" if tech_name == "genkidama" else "▶ EMPUJA"


func _hide_controller_phase2_cues() -> void:
	for cue in [_ctrl_cue_l, _ctrl_cue_r]:
		if cue and is_instance_valid(cue):
			cue.visible = false


func _is_phase2_autofire_pose(tech_name: String, eff_l_z: float, eff_r_z: float, bb_side: int) -> bool:
	match tech_name:
		"final_flash":
			return eff_l_z >= 0.22 and eff_r_z >= 0.22 and hands_dist_norm <= 0.42
		"galick_ho":
			return eff_l_z >= 0.24 and eff_r_z >= 0.24 and hands_dist_norm <= 0.52 and absf(avg_torso_pos.x) <= 0.38 and (avg_torso_pos.z >= super_phase1_anchor_z + 0.18 or (eff_l_z >= 0.34 and eff_r_z >= 0.34))
		"kamehameha":
			return eff_l_z >= 0.24 and eff_r_z >= 0.24 and hands_dist_norm <= 0.52 and (avg_torso_pos.z >= super_phase1_anchor_z + 0.18 or (eff_l_z >= 0.34 and eff_r_z >= 0.34))
		"genkidama":
			var avg_rel_y: float = (l_cam_rel_y + r_cam_rel_y) * 0.5
			return avg_rel_y <= 0.08 and (eff_l_z >= 0.16 or eff_r_z >= 0.16)
		"big_bang":
			var bb_ctrl: XRController3D = left_controller if bb_side == 0 else right_controller
			if not _is_arm_extended_palm_forward(bb_ctrl, bb_side == 0, 0.30, 0.34, 0.24):
				return false
			var active_z: float = maxf(l_torso_pos.z, l_cam_fwd_proj) if bb_side == 0 else maxf(r_torso_pos.z, r_cam_fwd_proj)
			var active_vel_z: float = l_torso_vel.z if bb_side == 0 else r_torso_vel.z
			return active_z >= 0.34 and (active_vel_z >= 0.55 or active_z >= super_phase1_anchor_z + 0.08)
	return false


func _is_valid_super_release_pose(tech_name: String, l_local_z: float, r_local_z: float, _avg_local_y: float, _avg_local_z: float, hands_dist: float, bb_side: int, l_cam_z: float = -999.0, r_cam_z: float = -999.0) -> bool:
	var eff_l_z: float = maxf(l_local_z, l_cam_z)
	var eff_r_z: float = maxf(r_local_z, r_cam_z)
	match tech_name:
		"final_flash":
			return eff_l_z >= 0.16 and eff_r_z >= 0.16 and hands_dist <= 0.72
		"galick_ho", "kamehameha":
			return eff_l_z >= 0.16 and eff_r_z >= 0.16 and hands_dist <= 0.58
		"big_bang":
			var bb_ctrl_rel: XRController3D = left_controller if bb_side == 0 else right_controller
			if super_phase2_latched:
				return true
			return _is_arm_extended_palm_forward(bb_ctrl_rel, bb_side == 0, 0.15, 0.30, 0.22)
		"genkidama":
			var avg_rel_y: float = (l_cam_rel_y + r_cam_rel_y) * 0.5
			return avg_rel_y <= 0.22 or eff_l_z >= 0.15 or eff_r_z >= 0.15
	return true


func _process_super_powers(delta: float) -> void:
	var player: Node = gesture_tree._get_player_instance() if gesture_tree else null
	if player and is_instance_valid(player) and bool(player.get("is_match_over")):
		if current_super_state != SuperPowerState.IDLE:
			_reset_super_state()
		return

	# REQUISITO 4: Prevenir efecto metralleta con cooldown estricto y suelta obligatoria de Grips tras disparo automático
	if super_cooldown > 0.0:
		candidate_super_tech = ""
		candidate_hold_timer = 0.0
		return

	if must_release_super_buttons:
		var l_g: bool = _ctrl_float(left_controller, &"grip") > 0.65 or _ctrl_pressed(left_controller, &"grip_click")
		var r_g: bool = _ctrl_float(right_controller, &"grip") > 0.65 or _ctrl_pressed(right_controller, &"grip_click")
		if not l_g and not r_g:
			must_release_super_buttons = false
		else:
			return

	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.65 or _ctrl_pressed(left_controller, &"trigger_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.65 or _ctrl_pressed(right_controller, &"trigger_click")

	# Si se está recargando Ki, cancelar o bloquear entrada; no cancelar CHARGING activo por rozar ambos gatillos
	var block_super_entry: bool = is_charging_ki or (current_super_state == SuperPowerState.IDLE and (ki_prep_phase or (l_trig and r_trig)))
	if block_super_entry:
		if current_super_state != SuperPowerState.IDLE:
			_reset_super_state()
		candidate_super_tech = ""
		candidate_hold_timer = 0.0
		return

	var l_grip: bool = _ctrl_float(left_controller, &"grip") > 0.65 or _ctrl_pressed(left_controller, &"grip_click")
	var r_grip: bool = _ctrl_float(right_controller, &"grip") > 0.65 or _ctrl_pressed(right_controller, &"grip_click")

	var l_local_x: float = l_torso_pos.x
	var r_local_x: float = r_torso_pos.x
	var l_local_y: float = l_torso_pos.y
	var r_local_y: float = r_torso_pos.y
	var l_local_z: float = l_torso_pos.z
	var r_local_z: float = r_torso_pos.z
	var l_cam_z: float = l_cam_fwd_proj
	var r_cam_z: float = r_cam_fwd_proj
	var avg_local_y: float = avg_torso_pos.y
	var avg_local_z: float = avg_torso_pos.z

	# Prohibir activación de super poderes claramente detrás de la espalda respecto al torso
	if l_local_z < -0.25 and r_local_z < -0.25:
		if current_super_state != SuperPowerState.IDLE:
			_reset_super_state()
		candidate_super_tech = ""
		candidate_hold_timer = 0.0
		return

	# Excluir la postura de guardia ÚNICAMENTE si está en reposo (IDLE), manos centradas al pecho
	var is_guard_pose: bool = (current_super_state == SuperPowerState.IDLE) and pose_chest_guard and hands_dist_norm < 0.30 and absf(avg_torso_pos.x) < 0.14
	if is_guard_pose:
		candidate_super_tech = ""
		candidate_hold_timer = 0.0
		return

	# Identificar personaje activo
	var char_name: String = "Goku"
	if player and player.character_data:
		char_name = player.character_data.character_name
	var is_vegeta: bool = "VEGETA" in char_name.to_upper()

	# Condiciones geométricas estrictas por zona normalizada del torso
	var vegeta_final_flash_pose: bool = is_vegeta and l_grip and r_grip and pose_wide_cross
	var vegeta_galick_ho_pose: bool = is_vegeta and l_grip and r_grip and pose_side_hip_galick

	# --- FASE 1: DETECCIÓN E INICIO DE CARGA (CON ESTABILIZACIÓN DE 0.18s) ---
	if current_super_state == SuperPowerState.IDLE:
		var target_tech: String = ""
		var target_display: String = ""

		if is_vegeta:
			if vegeta_final_flash_pose:
				target_tech = "final_flash"
				target_display = "Final Flash"
			elif vegeta_galick_ho_pose:
				target_tech = "galick_ho"
				target_display = "Galick Ho"
			elif (l_grip != r_grip) and melee_cooldown <= 0.0:
				var is_l: bool = l_grip
				var active_ctrl: XRController3D = left_controller if is_l else right_controller
				var active_trig: bool = l_trig if is_l else r_trig
				if not active_trig and _is_arm_extended_palm_forward(active_ctrl, is_l, 0.45, 0.40, 0.34):
					target_tech = "big_bang"
					target_display = "Big Bang Attack"
		else:
			if l_grip and r_grip and pose_overhead_both:
				target_tech = "genkidama"
				target_display = "Genkidama"
			elif l_grip and r_grip and pose_hip_kame:
				target_tech = "kamehameha"
				target_display = "Kamehameha"

		if target_tech != "":
			if not _is_super_tech_usable(player, target_tech):
				candidate_super_tech = ""
				candidate_hold_timer = 0.0
				if super_unusable_warn_cooldown <= 0.0:
					super_unusable_warn_cooldown = 1.6
					var req_msg: String = "requiere SSJ o Zenkai" if target_tech == "final_flash" else "requiere Base o Zenkai"
					if gesture_tree and gesture_tree.has_signal("gesture_logged"):
						gesture_tree.emit_signal("gesture_logged", "[BLOQUEADO] %s no disponible en esta forma (%s)." % [target_display, req_msg], "warning")
				return

			if target_tech == candidate_super_tech:
				candidate_hold_timer += delta
			else:
				candidate_super_tech = target_tech
				candidate_hold_timer = delta

			if candidate_hold_timer >= SUPER_POSE_HOLD_TIME:
				candidate_super_tech = ""
				candidate_hold_timer = 0.0
				current_super_state = SuperPowerState.CHARGING
				super_power_type = target_tech
				super_charge_timer = 0.0
				super_phase1_anchor_z = (l_local_z if l_grip else r_local_z) if target_tech == "big_bang" else avg_local_z
				if player and player.has_method("start_charging_super"):
					player.start_charging_super()
				if target_tech == "big_bang":
					var bb_side_init: int = 0 if l_grip else 1
					if gesture_tree:
						gesture_tree.set("big_bang_hand", bb_side_init)
				_set_gesture_tree_charging_flag(super_power_type, true)
				if gesture_tree:
					gesture_tree.sync_controller_gesture_state(super_power_type.to_upper() + "_CHARGE")
					if gesture_tree.has_signal("phase_changed"):
						gesture_tree.emit_signal("phase_changed", "%s: CARGANDO (FASE 1)" % target_display.to_upper())
					if gesture_tree.has_signal("gesture_logged"):
						gesture_tree.emit_signal("gesture_logged", "¡Cargando %s! Al completar la carga, proyecta el gesto al frente para auto-disparar." % target_display, "info")
		else:
			candidate_super_tech = ""
			candidate_hold_timer = 0.0

	# --- MANTENIMIENTO DE CARGA, AUTO-UPGRADE Y CONSUMO DE KI ---
	if current_super_state == SuperPowerState.CHARGING:
		# Ventana de auto-upgrade (<= 0.40s): si inició Big Bang antes de cerrar el segundo grip para Final Flash / Galick Ho
		if super_power_type == "big_bang" and super_charge_timer <= 0.40 and l_grip and r_grip and is_vegeta:
			if vegeta_final_flash_pose or vegeta_galick_ho_pose:
				var upgraded_tech: String = "final_flash" if vegeta_final_flash_pose else "galick_ho"
				var upgraded_display: String = "Final Flash" if vegeta_final_flash_pose else "Galick Ho"
				if _is_super_tech_usable(player, upgraded_tech):
					_set_gesture_tree_charging_flag("big_bang", false)
					_set_gesture_tree_charge_time("big_bang", 0.0)
					super_power_type = upgraded_tech
					super_phase1_anchor_z = avg_local_z
					_set_gesture_tree_charging_flag(super_power_type, true)
					_set_gesture_tree_charge_time(super_power_type, super_charge_timer)
					if gesture_tree:
						gesture_tree.sync_controller_gesture_state(super_power_type.to_upper() + "_CHARGE")
						if gesture_tree.has_signal("phase_changed"):
							gesture_tree.emit_signal("phase_changed", "%s: CARGANDO (FASE 1)" % upgraded_display.to_upper())
						if gesture_tree.has_signal("gesture_logged"):
							gesture_tree.emit_signal("gesture_logged", "¡Técnica actualizada a %s! Mantén los grips y concentra tu Ki." % upgraded_display, "info")

		# Si se está cargando Big Bang al inicio (< 0.45s) y el usuario aprieta el gatillo de esa mano, formó puño para Melee
		if super_power_type == "big_bang" and super_charge_timer < 0.45:
			var bb_side_trig: int = int(gesture_tree.get("big_bang_hand")) if gesture_tree else (0 if l_grip else 1)
			var active_trig: bool = l_trig if bb_side_trig == 0 else r_trig
			if active_trig:
				_reset_super_state()
				return

		# Consumo continuo de Ki durante la carga
		if player and is_instance_valid(player):
			var drain_rate: float = KiEconomyConfig.get_default().super_charge_drain_per_sec

			if player.current_ki > 0.0:
				player.consume_ki(drain_rate * delta)
			else:
				# ¡SOBRE-ESFUERZO VITAL DURANTE LA CARGA!
				var vital_drain: float = 350.0 * delta
				player.current_np = max(1.0, player.current_np - vital_drain)
				player._notify_stats()
				_pulse_haptic(left_controller, 160.0, 0.85, delta)
				_pulse_haptic(right_controller, 160.0, 0.85, delta)
				if int(super_charge_timer * 10) % 4 == 0:
					if gesture_tree and gesture_tree.has_signal("phase_changed"):
						gesture_tree.emit_signal("phase_changed", "¡SOBRE-ESFUERZO VITAL! (QUEMANDO FUERZA VITAL)")

		var super_spd_mult: float = player.get_dramatic_modifier("super_charge_speed_mult", 1.0) if (player and is_instance_valid(player) and player.has_method("get_dramatic_modifier")) else 1.0
		var opp_sup: Node = player._get_opponent() if (player and is_instance_valid(player) and player.has_method("_get_opponent")) else null
		if opp_sup and is_instance_valid(opp_sup):
			var cfg_sup: KiEconomyConfig = KiEconomyConfig.get_default()
			var sup_window_mult: float = 1.0
			var smoke_t_val: Variant = opp_sup.get("smoke_obscured_timer")
			if bool(opp_sup.get("smoke_obscures_active")) and smoke_t_val != null and float(smoke_t_val) > 0.0:
				sup_window_mult = maxf(sup_window_mult, cfg_sup.ki_blast_smoke_super_charge_mult)
			var crater_t_val: Variant = opp_sup.get("ground_crater_stun_timer")
			if crater_t_val != null and float(crater_t_val) > 0.0:
				sup_window_mult = maxf(sup_window_mult, cfg_sup.melee_crater_super_charge_mult)
			super_spd_mult *= sup_window_mult
		super_charge_timer += delta * super_spd_mult
		_pulse_haptic(left_controller, 110.0, clamp(0.25 + super_charge_timer * 0.35, 0.25, 0.95), delta)
		_pulse_haptic(right_controller, 110.0, clamp(0.25 + super_charge_timer * 0.35, 0.25, 0.95), delta)

		# Actualizar esfera visual concentrada y mira suave en tiempo real
		if gesture_tree:
			_set_gesture_tree_charge_time(super_power_type, super_charge_timer)
			gesture_tree._update_special_charge_sphere(delta)

			var aim_color: Color = Color(1.0, 0.9, 0.1)
			var aim_origin: Vector3 = (left_controller.global_position + right_controller.global_position) * 0.5
			if super_power_type == "big_bang":
				aim_color = Color(1.0, 0.90, 0.15)
				var bb_side_aim: int = int(gesture_tree.get("big_bang_hand")) if gesture_tree else 1
				var bb_ctrl: XRController3D = left_controller if bb_side_aim == 0 else right_controller
				if bb_ctrl:
					aim_origin = bb_ctrl.global_position
			elif super_power_type == "galick_ho":
				aim_color = Color(0.85, 0.2, 1.0)
			elif super_power_type == "final_flash":
				aim_color = Color(1.0, 0.95, 0.3)
			elif super_power_type == "kamehameha":
				aim_color = Color(0.2, 0.6, 1.0)
			elif super_power_type == "genkidama":
				aim_color = Color(0.3, 0.8, 1.0)

			var aim_dir: Vector3 = _compute_super_raw_aim_dir(super_power_type, false)
			gesture_tree._update_aim_reticle(aim_origin, aim_dir, aim_color, true)

		# --- FASE 1 EN CURSO: MANTENIMIENTO Y AUTO-DISPARO EN FASE 2 ---
		var bb_side: int = int(gesture_tree.get("big_bang_hand")) if gesture_tree else (0 if l_grip else 1)
		var active_grip: bool = l_grip if bb_side == 0 else r_grip

		var buttons_held: bool = false
		if super_power_type == "big_bang":
			buttons_held = active_grip
		else:
			buttons_held = l_grip or r_grip

		# Tiempo mínimo de carga ágil antes de habilitar disparo en Fase 2
		var min_fire_time: float = 0.45
		match super_power_type:
			"galick_ho": min_fire_time = 0.45
			"kamehameha": min_fire_time = 0.45
			"big_bang": min_fire_time = 0.55
			"final_flash": min_fire_time = 0.55
			"genkidama": min_fire_time = 0.65

		if super_charge_timer < min_fire_time:
			if super_power_type == "kamehameha" or super_power_type == "galick_ho":
				super_phase1_anchor_z = minf(super_phase1_anchor_z, avg_local_z)
			elif super_power_type == "big_bang":
				var active_z_bb: float = l_local_z if bb_side == 0 else r_local_z
				var active_vz_bb: float = l_torso_vel.z if bb_side == 0 else r_torso_vel.z
				if absf(active_vz_bb) < 0.30:
					super_phase1_anchor_z = active_z_bb

		var eff_l_z: float = maxf(l_local_z, l_cam_z)
		var eff_r_z: float = maxf(r_local_z, r_cam_z)

		# Pulso háptico e indicación de "FASE 1 LISTA" al completar carga mínima
		if super_charge_timer >= min_fire_time and not super_locked_haptic:
			super_locked_haptic = true
			_pulse_haptic(left_controller, 180.0, 1.0, 0.20)
			_pulse_haptic(right_controller, 180.0, 1.0, 0.20)
			var ready_cue: String = "¡%s LISTO! ¡EMPUJA LAS MANOS AL FRENTE PARA LANZAR!" % super_power_type.to_upper()
			if super_power_type == "final_flash":
				ready_cue = "¡FINAL FLASH LISTO! ¡JUNTA LAS MANOS AL FRENTE PARA DISPARAR!"
			elif super_power_type == "genkidama":
				ready_cue = "¡GENKIDAMA LISTA! ¡BAJA LOS BRAZOS AL FRENTE PARA LANZAR!"
			elif super_power_type == "big_bang":
				ready_cue = "¡BIG BANG LISTO! ¡EMPUJA LA PALMA AL FRENTE O SUELTA EL GRIP!"
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", ready_cue)
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", ready_cue, "success")

		# Punto 11: Señales visuales en los controles (anillo de progreso + flecha/etiqueta Fase 2) y latido háptico
		var p2_ready: bool = super_charge_timer >= min_fire_time
		var p2_ratio: float = clampf(super_charge_timer / maxf(min_fire_time, 0.01), 0.0, 1.0)
		_update_controller_phase2_cues(super_power_type, p2_ratio, p2_ready, bb_side)
		if p2_ready:
			_phase2_heartbeat_timer += delta
			if _phase2_heartbeat_timer >= 0.35:
				_phase2_heartbeat_timer = 0.0
				if super_power_type == "big_bang":
					_pulse_haptic(left_controller if bb_side == 0 else right_controller, 115.0, 0.48, 0.08)
				else:
					_pulse_haptic(left_controller, 115.0, 0.48, 0.08)
					_pulse_haptic(right_controller, 115.0, 0.48, 0.08)

		# FASE 2 CANÓNICA ("¡HAAA!"): Disparo inmediato al proyectar la postura de lanzamiento tras completar carga mínima
		if p2_ready and _is_phase2_autofire_pose(super_power_type, eff_l_z, eff_r_z, bb_side):
			_hide_guide_laser()
			_execute_super_fire(super_power_type)
			return

		# Evaluar ventana tolerante si el jugador extiende parcialmente y suelta los Grips
		var in_phase2_now: bool = _is_valid_super_release_pose(super_power_type, l_local_z, r_local_z, avg_local_y, avg_local_z, hands_dist_norm, bb_side, l_cam_z, r_cam_z)
		if super_power_type == "big_bang" and super_charge_timer >= min_fire_time:
			var eff_bb_z: float = eff_l_z if bb_side == 0 else eff_r_z
			if eff_bb_z >= 0.26:
				super_phase2_latched = true
				super_phase2_grace_timer = 0.85
		if super_charge_timer >= min_fire_time:
			if in_phase2_now:
				super_phase2_latched = true
				super_phase2_grace_timer = 0.75
			elif super_phase2_grace_timer > 0.0:
				super_phase2_grace_timer = maxf(super_phase2_grace_timer - delta, 0.0)
				if super_phase2_grace_timer <= 0.0:
					super_phase2_latched = false
					super_phase2_ready_notified = false

		var in_phase2_window: bool = in_phase2_now or super_phase2_latched or super_phase2_grace_timer > 0.0

		if super_charge_timer >= min_fire_time and in_phase2_window:
			var grip_released: bool = (not active_grip) if super_power_type == "big_bang" else (not (l_grip and r_grip))
			if grip_released:
				_execute_super_fire(super_power_type)
				return

		# POSIBILIDAD A: Mientras los botones sigan apretados, permanecer en Fase 1 concentrando energía
		if buttons_held:
			return

		# POSIBILIDAD B: Se soltaron los botones -> Validar Fase 2 o cancelar
		if super_charge_timer >= min_fire_time:
			if in_phase2_window:
				_execute_super_fire(super_power_type)
			else:
				if gesture_tree:
					gesture_tree._cancel_action("%s cancelado: extiende las manos al frente al lanzar" % super_power_type.capitalize())
					gesture_tree._reset_to_idle()
				super_cooldown = 0.20
				_reset_super_state()
		else:
			if gesture_tree:
				gesture_tree._cancel_action("%s cancelado (grips soltados antes de completar carga)" % super_power_type.capitalize())
				gesture_tree._reset_to_idle()
			super_cooldown = 0.20
			_reset_super_state()


func _execute_super_fire(tech_name: String) -> void:
	var ki_req: float = 50.0
	var tech_display_name = tech_name.capitalize()
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and is_instance_valid(player):
		# Evitar gastar Ki si ya existe una secuencia de super ataque activa (salvo Beam Clash contra rayo/esfera entrante)
		if tech_name in ["kamehameha", "galick_ho", "final_flash", "big_bang", "genkidama"]:
			var blocked_by_active_seq: bool = false
			if bool(player.get("is_in_bullet_time")):
				var active_dome: Variant = player.get("active_target_dome")
				if active_dome != null and is_instance_valid(active_dome):
					blocked_by_active_seq = true
				else:
					player.set("is_in_bullet_time", false)
			if not blocked_by_active_seq and bool(player.get("is_in_beam_sequence")):
				var own_seq: Variant = player.get("active_beam_sequence")
				var opp_node: Node3D = player._get_opponent() if player.has_method("_get_opponent") else null
				var opp_seq: Variant = opp_node.get("active_beam_sequence") if (opp_node and is_instance_valid(opp_node)) else null
				if own_seq != null and is_instance_valid(own_seq) and int(own_seq.get("state")) < 2:
					blocked_by_active_seq = true
				elif opp_seq != null and is_instance_valid(opp_seq):
					var opp_state: int = int(opp_seq.get("state"))
					if opp_state == 0:
						blocked_by_active_seq = false # Beam Clash permitido
					elif opp_state == 1:
						blocked_by_active_seq = true
					else:
						player.set("is_in_beam_sequence", false)
				else:
					player.set("is_in_beam_sequence", false)
			if blocked_by_active_seq:
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "ESPERA A QUE TERMINE EL RAYO")
				_hide_guide_laser()
				_reset_super_state()
				super_cooldown = 0.25
				return

		player.set("last_super_charge_time", super_charge_timer)
		var power_lookup = ""
		match tech_name:
			"galick_ho": power_lookup = "Galick Ho"
			"big_bang": power_lookup = "Big Bang Attack"
			"final_flash": power_lookup = "Final Flash"
			"kamehameha": power_lookup = "Super Kamehameha" if player.is_in_zenkai_state else "Kamehameha"
			"genkidama": power_lookup = "Genkidama"

		var power = null
		if player.character_data and player.character_data.powers:
			for p in player.character_data.powers:
				if p and p.power_name.to_lower() == power_lookup.to_lower():
					power = p
					break
		if power:
			ki_req = power.ki_cost
			tech_display_name = power.power_name

		# Si el jugador dispara dentro de la ventana de fatiga (< 4.0s de otro super), penalizar con 25% más de costo
		if super_fatigue_timer > 0.0:
			ki_req *= 1.25

		# En estado Zenkai, limitar el costo para drenar el Ki disponible sin sacrificar mitad del BP justo antes del impacto
		if player.is_in_zenkai_state:
			ki_req = minf(ki_req, maxf(player.current_ki, 30.0))

		var res: Dictionary = player.consume_ki_or_life_force(ki_req)
		if res.get("is_life_sacrifice", false):
			var lost_np = int(res.get("sacrificed_np", 0.0))
			print("[HybridCombatController] [ÚLTIMO ALIENTO] ¡Quemaste %d BP para forzar la técnica %s!" % [lost_np, tech_display_name])
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "¡ÚLTIMO ALIENTO! Sin Ki suficiente, sacrificaste %d BP para desatar %s." % [lost_np, tech_display_name], "warning")
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", "%s: ¡ÚLTIMO ALIENTO! (-%d BP)" % [tech_display_name.to_upper(), lost_np])
			_pulse_haptic(left_controller, 220.0, 1.0, 0.85)
			_pulse_haptic(right_controller, 220.0, 1.0, 0.85)
		else:
			if gesture_tree and gesture_tree.has_signal("phase_changed"):
				gesture_tree.emit_signal("phase_changed", "¡FUEGO! %s DESATADO" % tech_display_name.to_upper())
			_pulse_haptic(left_controller, 200.0, 1.0, 0.55)
			_pulse_haptic(right_controller, 200.0, 1.0, 0.55)

	var raw_launch_dir: Vector3 = _compute_super_raw_aim_dir(tech_name, true)
	if gesture_tree:
		var chg_pl: Node = gesture_tree.get("ki_blast_charge_player")
		if chg_pl and is_instance_valid(chg_pl) and chg_pl.has_method("stop"):
			chg_pl.stop()
		gesture_tree._hide_aim_reticle()
		gesture_tree.set("last_super_launch_dir", raw_launch_dir)
		gesture_tree.set("_ki_already_consumed_by_hybrid", true)
		gesture_tree._trigger_action(tech_name)
		gesture_tree._reset_to_idle()
		gesture_tree.sync_controller_gesture_state("IDLE")

	# Bloquear reentrada hasta soltar Grips tras auto-disparo en Fase 2
	_reset_super_state()
	super_fatigue_timer = 1.0
	super_cooldown = 0.45
	must_release_super_buttons = true


func _set_gesture_tree_charging_flag(tech_name: String, active: bool) -> void:
	if not gesture_tree:
		return
	var flag_name = "is_charging_" + tech_name
	gesture_tree.set(flag_name, active)


func _set_gesture_tree_charge_time(tech_name: String, time_val: float) -> void:
	if not gesture_tree:
		return
	var time_name = tech_name + "_charge_time"
	gesture_tree.set(time_name, time_val)


func _reset_super_state() -> void:
	current_super_state = SuperPowerState.IDLE
	super_power_type = ""
	super_charge_timer = 0.0
	super_locked_haptic = false
	super_phase2_latched = false
	super_phase2_grace_timer = 0.0
	super_phase2_ready_notified = false
	candidate_super_tech = ""
	candidate_hold_timer = 0.0
	super_aim_lock_window = -1.0
	_phase2_heartbeat_timer = 0.0
	_aim_dir_filled = 0
	_hide_guide_laser()
	_hide_controller_phase2_cues()
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and player.has_method("stop_charging_super"):
		player.stop_charging_super()
	if gesture_tree:
		var chg_pl: Node = gesture_tree.get("ki_blast_charge_player")
		if chg_pl and is_instance_valid(chg_pl) and chg_pl.has_method("stop"):
			chg_pl.stop()
		gesture_tree._hide_aim_reticle()
		gesture_tree.sync_controller_gesture_state("IDLE")
		gesture_tree.set("is_charging_kamehameha", false)
		gesture_tree.set("is_charging_genkidama", false)
		gesture_tree.set("is_charging_galick_ho", false)
		gesture_tree.set("is_charging_final_flash", false)
		gesture_tree.set("is_charging_big_bang", false)
		if gesture_tree.has_method("_update_special_charge_sphere"):
			gesture_tree._update_special_charge_sphere(0.0)


## Cancela la técnica actual por rotura de concentración (Poise roto por lluvia de Ki Blasts)
func cancel_super_from_poise_break() -> void:
	if current_super_state != SuperPowerState.IDLE:
		_reset_super_state()
		super_cooldown = 0.8
		must_release_super_buttons = true
		_pulse_haptic(left_controller, 200.0, 1.0, 0.35)
		_pulse_haptic(right_controller, 200.0, 1.0, 0.35)
		if gesture_tree and gesture_tree.has_signal("gesture_logged"):
			gesture_tree.emit_signal("gesture_logged", "[CONCENTRACIÓN ROTA] ¡Ataques enemigos interrumpieron tu técnica!", "warning")


## Cancela la recarga de Ki cuando el jugador recibe una interrupción táctica (Counter-Interrupt)
func cancel_ki_recharge_from_hit() -> void:
	if is_charging_ki or ki_prep_phase:
		is_charging_ki = false
		ki_prep_phase = false
		left_charge_time = 0.0
		right_charge_time = 0.0
		left_is_charging = false
		right_is_charging = false
		recharge_exit_cooldown = 0.45
		_pulse_haptic(left_controller, 200.0, 1.0, 0.35)
		_pulse_haptic(right_controller, 200.0, 1.0, 0.35)
		if gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(0)
			gesture_tree._cleanup_ki_blast_charge_sphere(1)
			gesture_tree._cancel_action("¡Intercepción de Ki! Recarga cancelada por impacto")
			gesture_tree._reset_to_idle()
			gesture_tree.sync_controller_gesture_state("IDLE")


# --- 4. TRANSFORMACIONES (Botones A / X y B / Y con Edge-Trigger y Progresión Estricta) ---
func _process_transformations() -> void:
	var right_ax = _ctrl_pressed(right_controller, &"ax_button") if right_controller else false
	var left_ax = _ctrl_pressed(left_controller, &"ax_button") if left_controller else false
	var ax_pressed = right_ax or left_ax

	var right_by = _ctrl_pressed(right_controller, &"by_button") if right_controller else false
	var left_by = _ctrl_pressed(left_controller, &"by_button") if left_controller else false
	var by_pressed = right_by or left_by

	# Edge detection: solo disparar en el instante en que el botón pasa de NO presionado a PRESIONADO
	var just_pressed_ax = ax_pressed and not was_ax_pressed
	var just_pressed_by = by_pressed and not was_by_pressed

	was_ax_pressed = ax_pressed
	was_by_pressed = by_pressed

	if transform_cooldown > 0.0:
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or not is_instance_valid(player) or not player.character_data:
		return

	# Botón A (mando derecho) o X (mando izquierdo): Avanzar transformación SECUENCIALMENTE
	if just_pressed_ax:
		var current_trans = player.get("current_transformation")
		var total_forms = player.character_data.transformations.size()
		if total_forms > 0:
			var target_idx = 0
			if current_trans == null:
				# De Estado Base a la Primera Fase (ej: SSJ)
				target_idx = 0
			else:
				# Buscar la fase actual
				var curr_idx = -1
				for i in range(total_forms):
					if player.character_data.transformations[i] == current_trans:
						curr_idx = i
						break
				if curr_idx != -1 and curr_idx < total_forms - 1:
					# Avanzar estrictamente a la siguiente forma secuencial (ej: SSJ -> Super Vegeta -> SSB)
					target_idx = curr_idx + 1
				else:
					# Ya estamos en la máxima transformación disponible
					print("[Transformation] %s ya se encuentra en su máxima transformación." % player.character_data.character_name)
					_pulse_haptic(right_controller, 80.0, 0.3, 0.1)
					transform_cooldown = 0.30
					return

			var target_trans = player.character_data.transformations[target_idx]
			if not player.is_transformation_unlocked(target_trans.form_name):
				var status_info: Dictionary = player.get_next_transformation_status() if player.has_method("get_next_transformation_status") else {}
				var req_txt: String = String(status_info.get("requirement_text", "¡Lucha para desbloquearla!"))
				print("[Transformation] %s intentó activar %s pero aún no está desbloqueada (%s)." % [player.character_data.character_name, target_trans.form_name, req_txt])
				_pulse_haptic(right_controller, 90.0, 0.45, 0.15)
				_pulse_haptic(left_controller, 90.0, 0.45, 0.15)
				if gesture_tree and gesture_tree.has_signal("gesture_logged"):
					gesture_tree.emit_signal("gesture_logged", "[BLOQUEADO] %s: %s" % [target_trans.form_name, req_txt], "warning")
				if gesture_tree and gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "🔒 %s: %s" % [target_trans.form_name.to_upper(), req_txt])
				if ki_lockon_system and is_instance_valid(ki_lockon_system) and ki_lockon_system.has_method("show_scouter_alert"):
					ki_lockon_system.show_scouter_alert("🔒 %s BLOQUEADO" % target_trans.form_name.to_upper(), req_txt, Color(1.0, 0.65, 0.2), 2.4)
				transform_cooldown = 0.35
				return

			player.transform_to(target_idx)
			transform_cooldown = 0.35 # Previene rebotes y pulsaciones múltiples por frame
			_pulse_haptic(left_controller, 180.0, 0.9, 0.35)
			_pulse_haptic(right_controller, 180.0, 0.9, 0.35)
			return

	# Botón B (mando derecho) o Y (mando izquierdo): Revertir a Base
	if just_pressed_by:
		var current_trans = player.get("current_transformation")
		if current_trans != null:
			player.revert_to_base()
			transform_cooldown = 0.35
			_pulse_haptic(left_controller, 120.0, 0.6, 0.25)
			_pulse_haptic(right_controller, 120.0, 0.6, 0.25)
			return
		else:
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "[FORMA BASE] Ya te encuentras en tu estado normal.", "info")
			_pulse_haptic(right_controller, 60.0, 0.25, 0.08)
			transform_cooldown = 0.35
			return

	# Gesto Canónico de Transformación en VR (Puños a la cintura durante 1.2s)
	var l_trig = _ctrl_float(left_controller, &"trigger") > 0.45 or _ctrl_pressed(left_controller, &"trigger_click") if left_controller else false
	var r_trig = _ctrl_float(right_controller, &"trigger") > 0.45 or _ctrl_pressed(right_controller, &"trigger_click") if right_controller else false
	var l_grip = _ctrl_float(left_controller, &"grip") > 0.45 or _ctrl_pressed(left_controller, &"grip_click") if left_controller else false
	var r_grip = _ctrl_float(right_controller, &"grip") > 0.45 or _ctrl_pressed(right_controller, &"grip_click") if right_controller else false

	if l_trig and r_trig and l_grip and r_grip and camera and left_controller and right_controller:
		var is_at_waist = (l_cam_rel_y < -0.22) and (r_cam_rel_y < -0.22)
		var is_waist_dist = hands_dist_norm >= 0.20 and hands_dist_norm <= 0.65

		if is_at_waist and is_waist_dist:
			gesture_transform_timer += get_process_delta_time()
			var current_trans = player.get("current_transformation")
			var total_forms = player.character_data.transformations.size()
			var next_idx = 0
			if current_trans != null:
				for i in range(total_forms):
					if player.character_data.transformations[i] == current_trans:
						next_idx = i + 1
						break
			var next_trans = player.character_data.transformations[next_idx] if next_idx < total_forms else null
			var next_unlocked: bool = (next_trans != null) and player.is_transformation_unlocked(next_trans.form_name)

			if gesture_transform_timer > 0.2 and next_unlocked:
				var pct: int = int(clampf(gesture_transform_timer / 1.2, 0.0, 1.0) * 100.0)
				var pulse_freq = lerp(70.0, 200.0, clampf(gesture_transform_timer / 1.2, 0.0, 1.0))
				_pulse_haptic(left_controller, pulse_freq, 0.45, 0.05)
				_pulse_haptic(right_controller, pulse_freq, 0.45, 0.05)
				if _transform_progress_cd <= 0.0 and gesture_tree and gesture_tree.has_signal("phase_changed"):
					_transform_progress_cd = 0.14
					gesture_tree.emit_signal("phase_changed", "⚡ TRANSFORMANDO A %s... %d%%" % [next_trans.form_name.to_upper(), pct])

			if gesture_transform_timer >= 1.2:
				gesture_transform_timer = 0.0
				if next_trans != null:
					if next_unlocked:
						player.transform_to(next_idx)
						transform_cooldown = 0.60
						_pulse_haptic(left_controller, 220.0, 1.0, 0.50)
						_pulse_haptic(right_controller, 220.0, 1.0, 0.50)
					else:
						var status_g: Dictionary = player.get_next_transformation_status() if player.has_method("get_next_transformation_status") else {}
						var req_g: String = String(status_g.get("requirement_text", "¡Lucha para desbloquearla!"))
						if gesture_tree and gesture_tree.has_signal("phase_changed"):
							gesture_tree.emit_signal("phase_changed", "🔒 %s: %s" % [next_trans.form_name.to_upper(), req_g])
						_pulse_haptic(left_controller, 80.0, 0.35, 0.15)
						_pulse_haptic(right_controller, 80.0, 0.35, 0.15)
						transform_cooldown = 0.40
		else:
			gesture_transform_timer = 0.0
	else:
		gesture_transform_timer = 0.0


# --- 5. GOLPES MELEE CINEMÁTICOS (LANZAMIENTO HACIA EL RIVAL EN 2 ETAPAS REALES) ---
func _process_melee_punches() -> void:
	var player: Node = gesture_tree._get_player_instance() if gesture_tree else null
	if player and is_instance_valid(player) and bool(player.get("is_match_over")):
		left_punch_cocked = false
		right_punch_cocked = false
		return

	if melee_cooldown > 0.0 or is_charging_ki or startup_cooldown > 0.0:
		left_punch_cocked = false
		right_punch_cocked = false
		return

	var l_grip: bool = _ctrl_float(left_controller, &"grip") > 0.40 or _ctrl_pressed(left_controller, &"grip_click")
	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.40 or _ctrl_pressed(left_controller, &"trigger_click")
	# REQUISITO CANÓNICO: Puño cerrado simulado con Grab + Gatillo (ambos botones presionados)
	var l_fist: bool = l_grip and l_trig

	var r_grip: bool = _ctrl_float(right_controller, &"grip") > 0.40 or _ctrl_pressed(right_controller, &"grip_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.40 or _ctrl_pressed(right_controller, &"trigger_click")
	# REQUISITO CANÓNICO: Puño cerrado simulado con Grab + Gatillo (ambos botones presionados)
	var r_fist: bool = r_grip and r_trig

	# Si ambos puños están cerrados a la vez, se reserva para Recarga de Ki o Transformación (nunca Melee)
	if l_fist and r_fist:
		left_punch_cocked = false
		right_punch_cocked = false
		return

	# Garantizar que formar puño (Grip+Trigger) limpia cualquier carga residual de Ki Blast en esa mano
	if l_fist and left_is_charging:
		left_charge_time = 0.0
		left_is_charging = false
		left_blast_locked_haptic = false
		if gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(0)
	if r_fist and right_is_charging:
		right_charge_time = 0.0
		right_is_charging = false
		right_blast_locked_haptic = false
		if gesture_tree:
			gesture_tree._cleanup_ki_blast_charge_sphere(1)

	if (left_is_charging and not l_fist) or (right_is_charging and not r_fist) or current_super_state != SuperPowerState.IDLE:
		if not (current_super_state == SuperPowerState.CHARGING and super_power_type == "big_bang" and super_charge_timer < 0.45):
			left_punch_cocked = false
			right_punch_cocked = false
			return

	# Si se estaba cargando Big Bang al inicio (< 0.45s) y el usuario cierra el puño completo (grab + gatillo), priorizar Melee
	if current_super_state == SuperPowerState.CHARGING and super_power_type == "big_bang" and super_charge_timer < 0.45:
		if l_fist or r_fist:
			_reset_super_state()
	elif current_super_state != SuperPowerState.IDLE:
		left_punch_cocked = false
		right_punch_cocked = false
		return

	# ETAPA 1: Armado del puño cerca del pecho / hombro (en torso-space normalizado)
	if l_fist:
		if l_torso_pos.z <= 0.36 and absf(l_torso_pos.x) <= 0.48 and l_torso_pos.y >= -0.40 and l_torso_pos.y <= 0.35:
			left_punch_cocked = true
	else:
		left_punch_cocked = false

	if r_fist:
		if r_torso_pos.z <= 0.36 and absf(r_torso_pos.x) <= 0.48 and r_torso_pos.y >= -0.40 and r_torso_pos.y <= 0.35:
			right_punch_cocked = true
	else:
		right_punch_cocked = false

	# ETAPA 2: Extensión explosiva hacia adelante tras armado o golpe directo veloz al frente
	var l_fwd_vel: float = maxf(l_torso_vel.z, left_velocity.dot(cam_fwd_flat) * inv_body_scale)
	var r_fwd_vel: float = maxf(r_torso_vel.z, right_velocity.dot(cam_fwd_flat) * inv_body_scale)
	var l_fwd_pos: float = maxf(l_torso_pos.z, l_cam_fwd_proj)
	var r_fwd_pos: float = maxf(r_torso_pos.z, r_cam_fwd_proj)
	var l_punch_fire: bool = l_fist and ((left_punch_cocked and l_fwd_pos >= 0.34 and l_fwd_vel >= 1.35) or (l_fwd_pos >= 0.36 and l_fwd_vel >= 1.85))
	var r_punch_fire: bool = r_fist and ((right_punch_cocked and r_fwd_pos >= 0.34 and r_fwd_vel >= 1.35) or (r_fwd_pos >= 0.36 and r_fwd_vel >= 1.85))
	if l_punch_fire:
		left_punch_cocked = false
		_execute_melee_punch(left_controller)
	elif r_punch_fire:
		right_punch_cocked = false
		_execute_melee_punch(right_controller)


func _execute_melee_punch(controller: XRController3D) -> void:
	var player: Node = gesture_tree._get_player_instance() if gesture_tree else null
	# Si ya estamos en Bullet-Time cuerpo a cuerpo, el golpe impacta la cúpula táctica
	if player and player.get("is_in_bullet_time"):
		melee_cooldown = 0.45
		_pulse_haptic(controller, 200.0, 0.95, 0.12)
		return

	if player and is_instance_valid(player):
		var curr_ki: float = float(player.get("current_ki")) if player.get("current_ki") != null else 0.0
		var dash_cost: float = KiEconomyConfig.get_default().melee_dash_cost
		var opp_m: Node = player._get_opponent() if player.has_method("_get_opponent") else null
		if not opp_m and get_tree() and get_tree().current_scene:
			opp_m = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
		var free_opening: bool = opp_m != null and is_instance_valid(opp_m) and player.has_method("has_free_melee_opening_against") and player.has_free_melee_opening_against(opp_m)
		if free_opening:
			dash_cost = 0.0
		if curr_ki < dash_cost:
			melee_cooldown = 0.6
			_pulse_haptic(controller, 90.0, 0.35, 0.12)
			if gesture_tree:
				if gesture_tree.has_signal("phase_changed"):
					gesture_tree.emit_signal("phase_changed", "SIN KI PARA MELEE (%d KI)" % int(dash_cost))
				if gesture_tree.has_signal("gesture_logged"):
					gesture_tree.emit_signal("gesture_logged", "¡Ki insuficiente para embestida Melee (%d Ki)!" % int(dash_cost), "warning")
			return
		if dash_cost > 0.0 and player.has_method("consume_ki"):
			player.consume_ki(dash_cost)

	_reset_super_state()
	left_charge_time = 0.0
	right_charge_time = 0.0
	left_is_charging = false
	right_is_charging = false

	melee_cooldown = 2.5

	# Auto-fijar al rival si no está bloqueado para garantizar embestida instantánea
	if player and is_instance_valid(player):
		if not player.get("is_target_locked"):
			var opp = get_tree().current_scene.find_child("EnemyCharacterInstance", true, false)
			if opp:
				player.set("is_target_locked", true)
				player.set("target_opponent", opp)

	if gesture_tree:
		gesture_tree._cleanup_ki_blast_charge_sphere(0)
		gesture_tree._cleanup_ki_blast_charge_sphere(1)
		gesture_tree._hide_aim_reticle()
		gesture_tree._trigger_action("melee_attack")
	_pulse_haptic(controller, 180.0, 0.90, 0.18)


# --- 6. CONTROL DEL HUD Y MENÚ IN-GAME ---
func _process_hud_toggle(delta: float) -> void:
	if not left_controller or not right_controller:
		return

	# Botón de menú (tres barras / Option) del mando izquierdo: Menú In-Game
	if menu_toggle_cooldown > 0.0:
		menu_toggle_cooldown -= delta
	elif _ctrl_pressed(left_controller, &"menu_button"):
		menu_toggle_cooldown = 0.45
		if not in_game_menu or not is_instance_valid(in_game_menu):
			_find_xr_nodes()
		if in_game_menu and is_instance_valid(in_game_menu):
			if not in_game_menu.is_inside_tree():
				if xr_origin and is_instance_valid(xr_origin) and xr_origin.is_inside_tree():
					xr_origin.add_child(in_game_menu)
				elif get_tree() and get_tree().current_scene:
					get_tree().current_scene.add_child(in_game_menu)
			in_game_menu.toggle_menu()


# --- 6. MOVIMIENTO POR CASILLAS / PASOS DISCRETOS (Yu Yu Hakusho / DB Legends / Ajedrez) ---
func _process_grid_step_movement(delta: float) -> void:
	if not left_controller or not right_controller or not xr_origin:
		return

	if step_cooldown > 0.0:
		step_cooldown -= delta
	if vertical_step_cooldown > 0.0:
		vertical_step_cooldown -= delta

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player:
		return

	# Si estamos volando en dash hacia el rival, no se permite movimiento manual
	if player.get("is_flying_to_melee") or player.get("is_flying_to_opponent"):
		return

	# A. ELEVACIÓN VERTICAL POR CLIC DE STICK
	var r_click: bool = right_controller and (_ctrl_pressed(right_controller, &"primary_click") or _ctrl_pressed(right_controller, &"secondary_click"))
	var l_click: bool = left_controller and (_ctrl_pressed(left_controller, &"primary_click") or _ctrl_pressed(left_controller, &"secondary_click"))

	# Clic stick derecho: SUBIR un espacio vertical
	if r_click and vertical_step_cooldown <= 0.0 and not is_step_moving:
		vertical_step_cooldown = 0.20
		var ground_h = player.get_ground_elevation(xr_origin.global_position)
		var max_h = ground_h + MAX_VERTICAL_HEIGHT
		if xr_origin.global_position.y + VERTICAL_STEP <= max_h:
			var target_pos = xr_origin.global_position + Vector3(0.0, VERTICAL_STEP, 0.0)
			_execute_vertical_step(target_pos, true)
		else:
			_pulse_haptic(right_controller, 90.0, 0.4, 0.12) # Límite superior alcanzado

	# Clic stick izquierdo: BAJAR un espacio vertical
	elif l_click and vertical_step_cooldown <= 0.0 and not is_step_moving:
		vertical_step_cooldown = 0.20
		var ground_h = player.get_ground_elevation(xr_origin.global_position)
		var min_h = ground_h + 0.05
		if xr_origin.global_position.y - VERTICAL_STEP >= min_h:
			var target_pos = xr_origin.global_position - Vector3(0.0, VERTICAL_STEP, 0.0)
			_execute_vertical_step(target_pos, false)
		elif xr_origin.global_position.y > min_h + 0.02:
			var target_pos = Vector3(xr_origin.global_position.x, min_h, xr_origin.global_position.z)
			_execute_vertical_step(target_pos, false)
		else:
			_pulse_haptic(left_controller, 90.0, 0.4, 0.12) # Límite inferior (suelo) alcanzado

	# B. DESPLAZAMIENTO HORIZONTAL POR CASILLAS (STICK DERECHO O IZQUIERDO)
	var stick: Vector2 = _ctrl_vec2(right_controller, &"primary") if right_controller else Vector2.ZERO
	if stick.length() < 0.25 and left_controller:
		stick = _ctrl_vec2(left_controller, &"primary")
	var stick_len: float = stick.length()

	if stick_len < 0.25:
		right_stick_flicked = false
	elif stick_len >= 0.55 and not right_stick_flicked and step_cooldown <= 0.0 and not is_step_moving:
		right_stick_flicked = true
		step_cooldown = 0.16

		var cam_basis = camera.global_transform.basis if camera else xr_origin.global_transform.basis
		var cam_fwd = -cam_basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()

		var cam_right = cam_basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()

		var move_dir = Vector3.ZERO
		# Seleccionar dirección dominante (4 direcciones discretas como ajedrez)
		# En OpenXR Godot, stick.y positivo es hacia adelante
		if abs(stick.y) >= abs(stick.x):
			if stick.y > 0.0:
				move_dir = cam_fwd  # Adelante
			else:
				move_dir = -cam_fwd # Atrás
		else:
			if stick.x > 0.0:
				move_dir = cam_right  # Derecha
			else:
				move_dir = -cam_right # Izquierda

		_execute_horizontal_step(move_dir)


func _execute_horizontal_step(move_dir: Vector3) -> void:
	if not xr_origin or is_step_moving:
		return
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player:
		return

	var target_pos = xr_origin.global_position + move_dir * STEP_DISTANCE

	# 1. Comprobación estricta de distancia mínima frontal con el oponente (2.4m)
	var opponent = player._get_opponent()
	if opponent and is_instance_valid(opponent):
		var opp_pos = opponent.global_position
		var current_diff = opp_pos - xr_origin.global_position
		current_diff.y = 0.0
		var current_dist = current_diff.length()

		var future_diff = opp_pos - target_pos
		future_diff.y = 0.0
		var future_dist = future_diff.length()

		# Si el paso nos acerca al rival y nos dejaría a una distancia no permitida (< 6.0m)
		if future_dist < current_dist and future_dist < MIN_ALLOWED_DISTANCE:
			print("[Movement] Paso frontal bloqueado: distancia mínima con el rival (%.1fm). Distancia futura: %.2fm" % [MIN_ALLOWED_DISTANCE, future_dist])
			_pulse_haptic(right_controller, 90.0, 0.5, 0.15)
			player._log_combat_event("[MOVIMIENTO] ¡Distancia mínima alcanzada (%.1fm)! No puedes acercarte más." % MIN_ALLOWED_DISTANCE, "warning")
			return

	# 2. Comprobación de colisión física con obstáculos del entorno (rocas café, pilares, mesetas)
	if xr_origin and xr_origin.is_inside_tree() and xr_origin.get_world_3d():
		var space = xr_origin.get_world_3d().direct_space_state
		if space:
			var char_y = xr_origin.global_position.y + 0.8
			var p_from = Vector3(xr_origin.global_position.x, char_y, xr_origin.global_position.z)
			var p_to = Vector3(target_pos.x, char_y, target_pos.z)
			var ray = PhysicsRayQueryParameters3D.create(p_from, p_to)
			ray.collision_mask = 1 # Capa 1: Entorno sólido, rocas y montañas
			var col = space.intersect_ray(ray)
			if col and col.collider:
				print("[Movement] Paso bloqueado por colisión con obstáculo sólido (%s)." % col.collider.name)
				_pulse_haptic(right_controller, 110.0, 0.45, 0.12)
				player._log_combat_event("[MOVIMIENTO] Bloqueado por obstáculo del entorno.", "warning")
				return

	# 3. Comprobación de límites de la arena
	var dist_center = Vector2(target_pos.x, target_pos.z).length()
	if dist_center > player.arena_half_limit:
		_pulse_haptic(right_controller, 90.0, 0.4, 0.15)
		return

	# 4. Desplazamiento ágil estilo anime (0.12s Tween)
	is_step_moving = true
	_play_step_audio(1.25)
	_pulse_haptic(right_controller, 140.0, 0.45, 0.08)

	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(xr_origin, "global_position", target_pos, 0.12)
	tween.tween_callback(func(): is_step_moving = false)


func _execute_vertical_step(target_pos: Vector3, is_up: bool) -> void:
	if not xr_origin or is_step_moving:
		return

	is_step_moving = true
	_play_step_audio(1.40 if is_up else 1.10)
	var ctrl = right_controller if is_up else left_controller
	_pulse_haptic(ctrl, 160.0, 0.6, 0.10)

	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(xr_origin, "global_position", target_pos, 0.12)
	tween.tween_callback(func(): is_step_moving = false)


func _play_step_audio(pitch: float = 1.25) -> void:
	if step_audio_player:
		step_audio_player.pitch_scale = pitch * randf_range(0.92, 1.08)
		step_audio_player.volume_db = -5.0
		AudioActionManager.play_action("common.dodge_vanish", step_audio_player, snd_step)


func _ensure_air_brake_bar() -> void:
	if _air_brake_root and is_instance_valid(_air_brake_root):
		return
	if not camera or not is_instance_valid(camera):
		return

	_air_brake_root = Node3D.new()
	_air_brake_root.name = "AirBrakeDiegeticBar"
	_air_brake_root.position = Vector3(0.0, -0.10, -1.05)
	_air_brake_root.visible = false
	camera.add_child(_air_brake_root)

	var bg_mesh := MeshInstance3D.new()
	bg_mesh.name = "AirBrakeBg"
	var bg_q := QuadMesh.new()
	bg_q.size = Vector2(0.42, 0.042)
	bg_mesh.mesh = bg_q
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 122
	bg_mat.albedo_color = Color(0.05, 0.08, 0.12, 0.85)
	bg_mesh.material_override = bg_mat
	_air_brake_root.add_child(bg_mesh)

	_air_brake_fill_mesh = MeshInstance3D.new()
	_air_brake_fill_mesh.name = "AirBrakeFill"
	var fill_q := QuadMesh.new()
	fill_q.size = Vector2(0.40, 0.028)
	_air_brake_fill_mesh.mesh = fill_q
	_air_brake_fill_mesh.position = Vector3(-0.20, 0.0, 0.002)
	_air_brake_fill_mat = StandardMaterial3D.new()
	_air_brake_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_air_brake_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_air_brake_fill_mat.no_depth_test = true
	_air_brake_fill_mat.render_priority = 123
	_air_brake_fill_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.95)
	_air_brake_fill_mesh.material_override = _air_brake_fill_mat
	_air_brake_root.add_child(_air_brake_fill_mesh)

	_air_brake_label = Label3D.new()
	_air_brake_label.name = "AirBrakeLabel"
	_air_brake_label.font_size = 22
	_air_brake_label.pixel_size = 0.0013
	_air_brake_label.no_depth_test = true
	_air_brake_label.render_priority = 124
	_air_brake_label.outline_size = 8
	_air_brake_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_air_brake_label.position = Vector3(0.0, 0.055, 0.002)
	_air_brake_label.text = "⚡ ¡AGITA LOS CONTROLES! 0%"
	_air_brake_root.add_child(_air_brake_label)


func _process_air_brake(delta: float, player: Node) -> void:
	_update_air_brake_with_motion(delta, player, left_velocity, right_velocity)


func _update_air_brake_with_motion(delta: float, player: Node, l_vel: Vector3, r_vel: Vector3) -> void:
	if not player or not is_instance_valid(player) or not bool(player.get("is_air_brake_active")) or DramaticDirector.is_dramatic_pause_active:
		_prev_air_l_vel = l_vel
		_prev_air_r_vel = r_vel
		_air_l_active_timer = 0.0
		_air_r_active_timer = 0.0
		_air_haptic_cd = 0.0
		if _air_brake_root and is_instance_valid(_air_brake_root):
			_air_brake_root.visible = false
		return

	_ensure_air_brake_bar()
	if _air_brake_root and is_instance_valid(_air_brake_root):
		_air_brake_root.visible = true

	var safe_dt: float = maxf(delta, 0.001)
	var l_accel: float = (l_vel - _prev_air_l_vel).length() / safe_dt
	var r_accel: float = (r_vel - _prev_air_r_vel).length() / safe_dt
	_prev_air_l_vel = l_vel
	_prev_air_r_vel = r_vel

	# Combinar velocidad lineal y sacudida por cambio de dirección (espacio local XR, inmune al knockback)
	var l_shake: float = l_vel.length() + l_accel * 0.045
	var r_shake: float = r_vel.length() + r_accel * 0.045

	# Ventana deslizante de 0.24s para tolerar inversiones de sentido a 90 FPS
	if l_shake >= 1.35:
		_air_l_active_timer = 0.24
	else:
		_air_l_active_timer = maxf(_air_l_active_timer - delta, 0.0)

	if r_shake >= 1.35:
		_air_r_active_timer = 0.24
	else:
		_air_r_active_timer = maxf(_air_r_active_timer - delta, 0.0)

	var l_moving: bool = _air_l_active_timer > 0.0
	var r_moving: bool = _air_r_active_timer > 0.0
	var both_shaking: bool = l_moving and r_moving
	var sync_mult: float = 1.0 if both_shaking else 0.38

	var active_shake: float = (l_shake if l_moving else 0.0) + (r_shake if r_moving else 0.0)
	var effort_rate: float = clampf(active_shake * 0.52, 0.0, 7.8) * sync_mult
	var effort_gain: float = effort_rate * delta
	var completed_now: bool = false
	if effort_gain > 0.0 and player.has_method("add_air_brake_effort"):
		completed_now = bool(player.add_air_brake_effort(effort_gain, delta))
	elif player.has_method("add_air_brake_effort"):
		completed_now = bool(player.add_air_brake_effort(0.0, delta))

	var prog: float = 1.0 if completed_now else (float(player.get("air_brake_progress")) if player.get("air_brake_progress") != null else 0.0)
	var diff_lbl: String = String(player.get("air_brake_difficulty_label")) if player.get("air_brake_difficulty_label") != null else "NORMAL"
	if _air_brake_fill_mesh and is_instance_valid(_air_brake_fill_mesh):
		var fill_scale: float = clampf(prog, 0.02, 1.0)
		_air_brake_fill_mesh.scale = Vector3(fill_scale, 1.0, 1.0)
		_air_brake_fill_mesh.position.x = -0.20 + 0.20 * fill_scale
	if _air_brake_fill_mat:
		_air_brake_fill_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.95).lerp(Color(1.0, 0.88, 0.2, 0.98), prog)
	if _air_brake_label and is_instance_valid(_air_brake_label):
		var l_ind: String = "◀L▶" if l_moving else " L "
		var r_ind: String = "◀R▶" if r_moving else " R "
		_air_brake_label.text = "⚡ [%s] ¡AGITA LOS CONTROLES! [%s] %d%% (%s)" % [l_ind, r_ind, int(roundf(prog * 100.0)), diff_lbl]
		_air_brake_label.modulate = Color(1.0, 0.92, 0.28) if both_shaking else Color(0.75, 0.92, 1.0)
	if completed_now and _air_brake_root and is_instance_valid(_air_brake_root):
		_air_brake_root.visible = false

	_air_haptic_cd = maxf(_air_haptic_cd - delta, 0.0)
	if (l_moving or r_moving) and _air_haptic_cd <= 0.0:
		_air_haptic_cd = 0.06
		var pulse_amp: float = clampf(0.28 + effort_rate * 0.08, 0.28, 0.78)
		if l_moving:
			_pulse_haptic(left_controller, 130.0, pulse_amp, 0.05)
		if r_moving:
			_pulse_haptic(right_controller, 130.0, pulse_amp, 0.05)


func cancel_determination_from_hit() -> void:
	if not is_charging_determination:
		return
	is_charging_determination = false
	determination_timer = 0.0
	determination_hit_cooldown = 0.8
	var player: Node3D = gesture_tree._get_player_instance() if gesture_tree else null
	var dd: DramaticDirector = DramaticDirector.get_active(get_tree())
	if dd:
		dd.update_determination_vfx(player, 0.0, false)
	if gesture_tree and gesture_tree.has_signal("gesture_logged"):
		gesture_tree.emit_signal("gesture_logged", "[DETERMINACIÓN] ¡Concentración interrumpida por impacto fuerte!", "warning")


func _process_determination(delta: float) -> void:
	if not left_controller or not right_controller:
		return
	var player: Node3D = gesture_tree._get_player_instance() if gesture_tree else null
	var eligible: bool = (
		player != null
		and is_instance_valid(player)
		and not bool(player.get("is_match_over"))
		and bool(player.get("is_in_furia"))
		and not bool(player.get("has_used_determination"))
		and not is_charging_ki
		and current_super_state == SuperPowerState.IDLE
		and determination_hit_cooldown <= 0.0
	)
	var dd: DramaticDirector = DramaticDirector.get_active(get_tree())
	if not eligible:
		if is_charging_determination:
			is_charging_determination = false
			determination_timer = 0.0
			if dd:
				dd.update_determination_vfx(player, 0.0, false)
		return

	var l_grip: bool = _ctrl_float(left_controller, &"grip") > 0.45 or _ctrl_pressed(left_controller, &"grip_click")
	var r_grip: bool = _ctrl_float(right_controller, &"grip") > 0.45 or _ctrl_pressed(right_controller, &"grip_click")
	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.45 or _ctrl_pressed(left_controller, &"trigger_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.45 or _ctrl_pressed(right_controller, &"trigger_click")
	var pose_ok: bool = pose_chest_guard and l_grip and r_grip and not l_trig and not r_trig

	if pose_ok:
		is_charging_determination = true
		determination_timer += delta
		var ratio: float = clampf(determination_timer / 2.8, 0.0, 1.0)
		if dd:
			dd.update_determination_vfx(player, ratio, true)
		_pulse_haptic(left_controller, 110.0, lerpf(0.25, 0.85, ratio), delta)
		_pulse_haptic(right_controller, 110.0, lerpf(0.25, 0.85, ratio), delta)
		if determination_timer >= 2.8:
			is_charging_determination = false
			determination_timer = 0.0
			if player.has_method("complete_moment_of_determination"):
				player.complete_moment_of_determination()
	elif is_charging_determination:
		is_charging_determination = false
		determination_timer = 0.0
		if dd:
			dd.update_determination_vfx(player, 0.0, false)


# --- 7. GUARDIA DEFENSIVA (BLOQUEO) ---
func _process_guard() -> void:
	if not left_controller or not right_controller or is_charging_ki or current_super_state != SuperPowerState.IDLE:
		_set_player_blocking(false)
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or player.get("is_guard_broken"):
		_set_player_blocking(false)
		return

	var l_grip: bool = _ctrl_float(left_controller, &"grip") > 0.45 or _ctrl_pressed(left_controller, &"grip_click")
	var r_grip: bool = _ctrl_float(right_controller, &"grip") > 0.45 or _ctrl_pressed(right_controller, &"grip_click")
	var l_trig: bool = _ctrl_float(left_controller, &"trigger") > 0.45 or _ctrl_pressed(left_controller, &"trigger_click")
	var r_trig: bool = _ctrl_float(right_controller, &"trigger") > 0.45 or _ctrl_pressed(right_controller, &"trigger_click")

	# Guardia Cruzada en 'X': Ambos puños cerrados (Grip + Gatillo en ambas manos) frente al pecho
	if l_grip and l_trig and r_grip and r_trig and pose_chest_guard:
		_set_player_blocking(true)
		_pulse_haptic(left_controller, 80.0, 0.45, 0.08)
		_pulse_haptic(right_controller, 80.0, 0.45, 0.08)
		return

	_set_player_blocking(false)


func _set_player_blocking(blocking: bool) -> void:
	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if player and player.get("is_blocking") != blocking:
		player.set("is_blocking", blocking)
		if blocking:
			if gesture_tree and gesture_tree.has_signal("gesture_logged"):
				gesture_tree.emit_signal("gesture_logged", "[GUARDIA CRUZADA] Postura defensiva activa (-85% daño a BP).", "info")


# --- UTILIDADES HÁPTICAS Y COMUNICACIÓN ---
## Bio-Hápticos sutiles: vibración rítmica en latido ("heartbeat") proporcional al % de Ki y multiplicada por la transformación
func _process_bio_haptics(delta: float) -> void:
	if not haptics_enabled or not left_controller or not right_controller:
		return

	# Silenciar durante la carga o ejecución activa de cualquier ataque para no contaminar el feedback cinético
	if left_is_charging or right_is_charging or is_charging_ki or ki_prep_phase or current_super_state != SuperPowerState.IDLE:
		bio_haptic_timer = 0.0
		return

	var player = gesture_tree._get_player_instance() if gesture_tree else null
	if not player or not is_instance_valid(player):
		return

	if player.get("is_in_bullet_time") or player.get("is_flying_to_melee"):
		bio_haptic_timer = 0.0
		return

	var cdata = player.get("character_data")
	var current_ki: float = float(player.get("current_ki") if player.get("current_ki") != null else 0.0)
	var max_ki: float = float(cdata.base_ki) if (cdata and cdata.get("base_ki") != null) else 100.0
	var ki_ratio: float = clampf(current_ki / maxf(max_ki, 1.0), 0.0, 1.0)

	# Multiplicador según la transformación actual (form_name canónico en TransformationData)
	var trans_mult: float = 1.0
	var trans = player.get("current_transformation")
	if trans != null and trans.get("form_name") != null:
		var t_name: String = String(trans.get("form_name")).to_lower()
		if "ultra" in t_name or "ego" in t_name or "instinto" in t_name:
			trans_mult = 2.5
		elif "kaioken" in t_name:
			trans_mult = 1.35
		elif "ssj2" in t_name or "super saiyan 2" in t_name:
			trans_mult = 2.0
		elif "ssj3" in t_name or "blue" in t_name or "ssb" in t_name or "god" in t_name:
			trans_mult = 2.25
		elif "ssj" in t_name or "super" in t_name:
			trans_mult = 1.75

	# Intervalo del latido: a mayor Ki, latido más enérgico (entre 1.25s y 0.70s)
	var target_interval = lerpf(1.25, 0.70, ki_ratio)
	bio_haptic_timer += delta

	if bio_haptic_timer >= target_interval:
		bio_haptic_timer = 0.0
		# Amplitud base sutil entre 0.06 y 0.14 modulada por la transformación
		var base_amp = lerpf(0.06, 0.14, ki_ratio)
		var final_amp = clampf(base_amp * trans_mult, 0.06, 0.60)
		var freq = lerpf(55.0, 90.0, ki_ratio)
		_pulse_haptic(left_controller, freq, final_amp, 0.05)
		_pulse_haptic(right_controller, freq, final_amp, 0.05)


func _pulse_haptic(controller: XRController3D, freq: float, amp: float, duration: float) -> void:
	if not haptics_enabled or not controller or (desktop_sim and desktop_sim.get("sim_active")):
		return
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", freq, amp, duration, 0.0)


func _ctrl_pressed(ctrl: XRController3D, action: StringName) -> bool:
	if not ctrl:
		return false
	if desktop_sim and desktop_sim.get("sim_active"):
		return desktop_sim.call("get_button_pressed", ctrl == left_controller, action)
	return ctrl.is_button_pressed(action)


func _ctrl_float(ctrl: XRController3D, action: StringName) -> float:
	if not ctrl:
		return 0.0
	if desktop_sim and desktop_sim.get("sim_active"):
		return desktop_sim.call("get_float", ctrl == left_controller, action)
	return ctrl.get_float(action)


func _ctrl_vec2(ctrl: XRController3D, action: StringName) -> Vector2:
	if not ctrl:
		return Vector2.ZERO
	if desktop_sim and desktop_sim.get("sim_active"):
		return desktop_sim.call("get_vector2", ctrl == left_controller, action)
	return ctrl.get_vector2(action)
