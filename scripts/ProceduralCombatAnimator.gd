class_name ProceduralCombatAnimator
extends RefCounted

## ProceduralCombatAnimator (Godot 4.3+ VR)
## Controla las 18 animaciones procedurales canónicas de cuerpo completo para DBVR:
## 1. Guardia marcial diferenciada (Goku vs Vegeta) con stance de cadera y piernas
## 2. Levitación aérea y Dash de vuelo inclinado
## 3. Recarga de Ki en 2 fases (hombros -> cintura con postura de caballo y tensión)
## 4. Transformación (contracción y estallido/grito SSJ/Kaioken)
## 5. Guardia Cruzada en "X" y estado de Guardia Rota
## 6. Hit Flinch direccional multi-eje y jadeo por Ki bajo
## 7. Ráfaga de Ki Blasts alternados izq/der
## 8. Combo Melee completo (Jab, Cross, Gancho, Patada Circular, Martillazo 2 manos)
## 9-13. Poses Fase 1 y Fase 2 para Kamehameha, Galick Ho, Final Flash, Big Bang y Genkidama
## 14. Salir volando por los aires en "C" con giro en espiral
## 15. Suspendido aturdido en Follow-Up Bullet-Time
## 16. Estampado contra muralla/risco (Wall-Stick previo al desplome Ragdoll)
## 18. Reincorporación (Kip-Up) tras Ragdoll en suelo/pilares

var skeleton: Skeleton3D = null
var character_instance: Node3D = null
var enabled: bool = true
var is_vegeta_char: bool = false
var zenkai_anim_loader: ZenkaiAnimationLoader = null
var zenkai_overlay_weight: float = 0.45
var use_pure_zenkai_spa: bool = false
var spa_compose_mode: int = 4
var spa_axis_signs: Vector3 = Vector3(1.0, 1.0, 1.0)
var spa_swap_lr: bool = false
var spa_enable_torso: bool = true
var spa_enable_arms: bool = true
var spa_enable_legs: bool = true
var spa_enable_head: bool = false
var spa_forced_clip: String = ""
var spa_forced_u: float = -1.0
var _zenkai_bone_quats: Dictionary = {}

# Diccionario de huesos cacheados con sus transformaciones originales de reposo
var bone_indices: Dictionary = {}
var bone_rest_rotations: Dictionary = {}

# Tiempos acumulados para armónicos senoidales
var anim_time: float = 0.0
var breath_time: float = 0.0

# Estado de reacción a impactos (Hit Flinch)
var hit_flinch_timer: float = 0.0
var hit_flinch_intensity: float = 0.0
var hit_flinch_direction: Vector3 = Vector3.BACK

# Estados de acción y combate (cero alocaciones por frame)
var active_super_tech: String = ""
var active_super_phase: int = 0
var super_fire_hold_timer: float = 0.0
var ki_recharge_phase: int = 0
var transform_roar_timer: float = 0.0
var ki_blast_anim_timer: float = 0.0
var ki_blast_hand: int = 0
var melee_anim_timer: float = 0.0
var melee_anim_duration: float = 0.24
var melee_anim_type: int = 0
var melee_combo_counter: int = 0
var getup_recovery_timer: float = 0.0
var getup_recovery_duration: float = 0.45
var airborne_roll_angle: float = 0.0

# Memoria de rotación de mirada y poses para suavizado (Slerp / Lerp sin allocs)
var current_head_euler: Vector3 = Vector3.ZERO
var current_neck_euler: Vector3 = Vector3.ZERO
var current_hips_euler: Vector3 = Vector3.ZERO
var current_spine_euler: Vector3 = Vector3.ZERO
var current_chest_euler: Vector3 = Vector3.ZERO
var current_upper_chest_euler: Vector3 = Vector3.ZERO
var current_l_upleg_euler: Vector3 = Vector3.ZERO
var current_l_leg_euler: Vector3 = Vector3.ZERO
var current_r_upleg_euler: Vector3 = Vector3.ZERO
var current_r_leg_euler: Vector3 = Vector3.ZERO
var _cur_left_hand_pos: Vector3 = Vector3(-0.02, -0.02, 0.36)
var _cur_right_hand_pos: Vector3 = Vector3(0.04, -0.12, 0.24)
var _cur_left_hand_basis: Basis = Basis.IDENTITY
var _cur_right_hand_basis: Basis = Basis.IDENTITY
var _arm_bases_initialized: bool = false

# Estados cacheados de frame
var _st_is_wall_stuck: bool = false
var _st_wall_stick_ratio: float = 0.0
var _st_is_launching_air: bool = false
var _st_air_speed: float = 0.0
var _st_is_airborne_stunned: bool = false
var _st_is_transforming: bool = false
var _st_transform_u: float = 0.0
var _st_is_guard_broken: bool = false
var _st_is_melee_active: bool = false
var _st_melee_u: float = 0.0
var _st_super_tech: String = ""
var _st_super_phase: int = 0
var _st_is_blocking: bool = false
var _st_ki_phase: int = 0
var _st_is_ki_blast: bool = false
var _st_ki_blast_u: float = 0.0
var _st_is_flying: bool = false
var _st_is_getup: bool = false
var _st_getup_u: float = 0.0
var _st_is_exhausted: bool = false
var _st_flinch_factor: float = 0.0
var _st_flinch_local_dir: Vector3 = Vector3.BACK

const TARGET_BONES: Array[String] = [
	"Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg", "Hips"
]

const BONE_ALIASES: Dictionary = {
	"Hips": ["Hips", "WAIST"],
	"Spine": ["Spine", "SPINE1"],
	"Chest": ["Chest", "SPINE2"],
	"UpperChest": ["UpperChest", "SPINE3"],
	"Neck": ["Neck", "NECK"],
	"Head": ["Head", "HEAD"],
	"LeftShoulder": ["LeftShoulder", "CLAVICLE_R"],
	"LeftArm": ["LeftArm", "SHOULDER_R"],
	"LeftForeArm": ["LeftForeArm", "ELBOW_R"],
	"LeftHand": ["LeftHand", "WRIST_R"],
	"RightShoulder": ["RightShoulder", "CLAVICLE_L"],
	"RightArm": ["RightArm", "SHOULDER_L"],
	"RightForeArm": ["RightForeArm", "ELBOW_L"],
	"RightHand": ["RightHand", "WRIST_L"],
	"LeftUpLeg": ["LeftUpLeg", "THIGH_R"],
	"LeftLeg": ["LeftLeg", "CLANK_R"],
	"RightUpLeg": ["RightUpLeg", "THIGH_L"],
	"RightLeg": ["RightLeg", "CLANK_L"],
}


func setup(p_skeleton: Skeleton3D, p_character: Node3D) -> void:
	skeleton = p_skeleton
	character_instance = p_character
	bone_indices.clear()
	bone_rest_rotations.clear()
	is_vegeta_char = false

	if character_instance and character_instance.get("character_data") != null:
		var cdata: Resource = character_instance.get("character_data")
		if cdata and "character_name" in cdata:
			is_vegeta_char = "VEGETA" in String(cdata.character_name).to_upper()

	if not skeleton:
		return

	for target in TARGET_BONES:
		var idx: int = _find_bone_with_aliases(target)
		if idx != -1:
			bone_indices[target] = idx
			bone_rest_rotations[target] = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()

	zenkai_anim_loader = ZenkaiAnimationLoader.new()
	var active_form: String = ""
	var custom_lib: String = ""
	if character_instance and character_instance.get("current_transformation") != null:
		var tr_res: Resource = character_instance.get("current_transformation")
		if tr_res and "form_name" in tr_res:
			active_form = String(tr_res.get("form_name"))
		if tr_res and "anim_library_path" in tr_res:
			custom_lib = String(tr_res.get("anim_library_path"))
	if not custom_lib.is_empty():
		zenkai_anim_loader.load_library(custom_lib)
	else:
		zenkai_anim_loader.load_default_for_character(is_vegeta_char, active_form)

	print("[ProceduralCombatAnimator] Configurado para %s. Huesos mapeados: %d/%d" % [
		character_instance.name, bone_indices.size(), TARGET_BONES.size()
	])


func set_transformation_form(form_name: String, custom_library_path: String = "") -> void:
	if zenkai_anim_loader == null:
		zenkai_anim_loader = ZenkaiAnimationLoader.new()
	if not custom_library_path.is_empty():
		zenkai_anim_loader.load_library(custom_library_path)
	else:
		zenkai_anim_loader.load_default_for_character(is_vegeta_char, form_name)


func _find_bone_with_aliases(target: String) -> int:
	var candidates: Array = BONE_ALIASES.get(target, [target])
	for cand in candidates:
		var cand_str: String = String(cand)
		var idx: int = skeleton.find_bone(cand_str)
		if idx != -1:
			return idx
		idx = skeleton.find_bone(cand_str.to_lower())
		if idx != -1:
			return idx
		for b in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(b).nocasecmp_to(cand_str) == 0:
				return b
	return -1


func trigger_hit_flinch(intensity: float, hit_dir: Vector3) -> void:
	hit_flinch_intensity = clampf(intensity, 0.2, 1.4)
	hit_flinch_direction = hit_dir.normalized() if hit_dir.length_squared() > 0.01 else Vector3.BACK
	hit_flinch_timer = 0.35


func set_super_pose(tech_name: String, phase: int) -> void:
	var t_low: String = tech_name.to_lower()
	if phase <= 0 or t_low.is_empty():
		active_super_tech = ""
		active_super_phase = 0
		super_fire_hold_timer = 0.0
		return

	if "kamehameha" in t_low:
		active_super_tech = "kamehameha"
	elif "galick" in t_low:
		active_super_tech = "galick_ho"
	elif "final" in t_low:
		active_super_tech = "final_flash"
	elif "big" in t_low:
		active_super_tech = "big_bang"
	elif "genki" in t_low:
		active_super_tech = "genkidama"
	else:
		active_super_tech = "kamehameha"

	active_super_phase = phase
	if phase == 2:
		super_fire_hold_timer = 1.35


func set_ki_recharge_phase(phase: int) -> void:
	ki_recharge_phase = clampi(phase, 0, 2)


func trigger_transformation_roar() -> void:
	transform_roar_timer = 0.85


func trigger_ki_blast_shot(hand_side: int) -> void:
	ki_blast_hand = hand_side % 2
	ki_blast_anim_timer = 0.22


func trigger_melee_strike(strike_type: int = -1) -> void:
	if strike_type < 0:
		melee_anim_type = melee_combo_counter % 4
		melee_combo_counter += 1
	else:
		melee_anim_type = clampi(strike_type, 0, 5)
	if melee_anim_type == 5:
		melee_anim_duration = 0.42
	elif melee_anim_type == 4:
		melee_anim_duration = 0.38
	else:
		melee_anim_duration = 0.24
	melee_anim_timer = melee_anim_duration


var melee_block_timer: float = 0.0
var melee_block_type: int = 0

func trigger_melee_block(block_type: int = 0, duration: float = 0.28) -> void:
	melee_block_type = clampi(block_type, 0, 3)
	melee_block_timer = maxf(duration, 0.1)


func trigger_getup_recovery(duration: float = 0.45) -> void:
	getup_recovery_duration = maxf(duration, 0.15)
	getup_recovery_timer = getup_recovery_duration


func update(delta: float, target_look_pos: Vector3, is_charging_ki: bool, is_blocking: bool, is_flying: bool) -> void:
	if not enabled or not skeleton or not is_instance_valid(skeleton):
		return

	anim_time += delta
	breath_time += delta * (2.8 if is_charging_ki else 1.4)

	# 1. Actualizar temporizadores de acciones discretas
	if hit_flinch_timer > 0.0:
		hit_flinch_timer = maxf(hit_flinch_timer - delta, 0.0)
	if transform_roar_timer > 0.0:
		transform_roar_timer = maxf(transform_roar_timer - delta, 0.0)
	if ki_blast_anim_timer > 0.0:
		ki_blast_anim_timer = maxf(ki_blast_anim_timer - delta, 0.0)
	if melee_anim_timer > 0.0:
		melee_anim_timer = maxf(melee_anim_timer - delta, 0.0)
	if melee_block_timer > 0.0:
		melee_block_timer = maxf(melee_block_timer - delta, 0.0)
	if getup_recovery_timer > 0.0:
		getup_recovery_timer = maxf(getup_recovery_timer - delta, 0.0)
	if active_super_phase == 2 and super_fire_hold_timer > 0.0:
		super_fire_hold_timer = maxf(super_fire_hold_timer - delta, 0.0)
		if super_fire_hold_timer <= 0.0 and not bool(character_instance.get("is_firing_beam")):
			active_super_phase = 0
			active_super_tech = ""

	# 2. Resolver estado físico en tiempo real sin alocar memoria
	_resolve_frame_states(delta, is_charging_ki, is_blocking, is_flying)

	# 3. Aplicar animación corporal completa sobre los 18 huesos
	_apply_body_hover_and_trajectory(delta)
	if use_pure_zenkai_spa and zenkai_anim_loader != null:
		var z_clip: String = spa_forced_clip if not spa_forced_clip.is_empty() else _get_active_zenkai_clip_name()
		if not z_clip.is_empty() and zenkai_anim_loader.has_clip(z_clip):
			var z_u: float = spa_forced_u if spa_forced_u >= 0.0 else _get_active_zenkai_clip_u()
			_apply_pure_zenkai_full_body(delta, z_clip, z_u)
			return
	_apply_hips_spine_and_chest(delta)
	_apply_legs_pose(delta)
	_apply_look_at(delta, target_look_pos)
	_apply_arms_pose(delta)


func _resolve_frame_states(delta: float, is_charging_ki: bool, is_blocking: bool, is_flying: bool) -> void:
	_st_flinch_factor = 0.0
	if hit_flinch_timer > 0.0:
		var progress: float = 1.0 - (hit_flinch_timer / 0.35)
		_st_flinch_factor = sin(progress * PI) * hit_flinch_intensity
		if character_instance and is_instance_valid(character_instance):
			_st_flinch_local_dir = (character_instance.global_transform.basis.inverse() * hit_flinch_direction).normalized()
		else:
			_st_flinch_local_dir = Vector3.BACK

	var wall_stick: float = 0.0
	var vel: Vector3 = Vector3.ZERO
	var is_knocked_back: bool = false
	var is_guard_broken: bool = false
	var is_firing_beam_prop: bool = false
	var cur_ki: float = 100.0
	var is_flying_prop: bool = is_flying
	var is_airborne_stunned: bool = false

	if character_instance and is_instance_valid(character_instance):
		var ws_val: Variant = character_instance.get("wall_stick_timer")
		if ws_val != null:
			wall_stick = float(ws_val)
		var vel_val: Variant = character_instance.get("velocity")
		if vel_val != null:
			vel = vel_val
		is_knocked_back = bool(character_instance.get("is_knocked_back"))
		is_guard_broken = bool(character_instance.get("is_guard_broken")) or bool(character_instance.get("is_staggered"))
		is_firing_beam_prop = bool(character_instance.get("is_firing_beam"))
		var ki_val: Variant = character_instance.get("current_ki")
		if ki_val != null:
			cur_ki = float(ki_val)
		if bool(character_instance.get("is_flying_to_opponent")):
			is_flying_prop = true
		if character_instance.has_method("_get_opponent"):
			var opp: Node3D = character_instance._get_opponent() as Node3D
			if opp and is_instance_valid(opp):
				is_airborne_stunned = bool(opp.get("is_in_followup_bullet_time")) and opp.get("opponent_airborne_target") == character_instance

	_st_air_speed = vel.length()
	_st_is_wall_stuck = wall_stick > 0.0
	_st_wall_stick_ratio = clampf(1.0 - (wall_stick / 1.25), 0.0, 1.0) if _st_is_wall_stuck else 0.0
	_st_is_launching_air = (not _st_is_wall_stuck) and is_knocked_back and _st_air_speed > 6.5
	airborne_roll_angle = sin(anim_time * 10.0) * deg_to_rad(6.0) if _st_is_launching_air else 0.0

	_st_is_airborne_stunned = (not _st_is_wall_stuck) and (not _st_is_launching_air) and is_airborne_stunned
	_st_is_transforming = transform_roar_timer > 0.0
	_st_transform_u = clampf(1.0 - (transform_roar_timer / 0.85), 0.0, 1.0) if _st_is_transforming else 0.0
	_st_is_guard_broken = is_guard_broken
	_st_is_melee_active = melee_anim_timer > 0.0
	_st_melee_u = clampf(1.0 - (melee_anim_timer / maxf(melee_anim_duration, 0.01)), 0.0, 1.0) if _st_is_melee_active else 0.0

	_st_super_tech = active_super_tech
	_st_super_phase = active_super_phase
	if is_firing_beam_prop:
		_st_super_phase = 2
		if _st_super_tech.is_empty():
			var bname: Variant = character_instance.get("beam_tech_name")
			if bname != null and not String(bname).is_empty():
				set_super_pose(String(bname), 2)
				_st_super_tech = active_super_tech
			else:
				_st_super_tech = "kamehameha"

	_st_is_blocking = is_blocking and not is_guard_broken
	_st_ki_phase = ki_recharge_phase if ki_recharge_phase > 0 else (2 if is_charging_ki else 0)
	_st_is_ki_blast = ki_blast_anim_timer > 0.0
	_st_ki_blast_u = clampf(1.0 - (ki_blast_anim_timer / 0.22), 0.0, 1.0) if _st_is_ki_blast else 0.0
	_st_is_flying = is_flying_prop
	_st_is_getup = getup_recovery_timer > 0.0
	_st_getup_u = clampf(1.0 - (getup_recovery_timer / maxf(getup_recovery_duration, 0.01)), 0.0, 1.0) if _st_is_getup else 1.0
	_st_is_exhausted = cur_ki < 20.0 and _st_ki_phase == 0 and _st_super_phase == 0


func _apply_body_hover_and_trajectory(delta: float) -> void:
	if not character_instance or not is_instance_valid(character_instance):
		return
	var mesh_node: Node3D = character_instance.get("body_mesh_instance") as Node3D
	if not mesh_node or not is_instance_valid(mesh_node):
		return

	var target_pos_y: float = 0.0
	var target_rot_x: float = 0.0
	var target_rot_z: float = 0.0

	if _st_is_wall_stuck:
		target_pos_y = -0.12 * _st_wall_stick_ratio
	elif _st_is_launching_air:
		target_rot_x = deg_to_rad(-48.0)
		target_rot_z = airborne_roll_angle
	elif _st_is_getup:
		target_pos_y = lerpf(-0.36, 0.0, _st_getup_u)
		target_rot_x = lerpf(deg_to_rad(18.0), 0.0, _st_getup_u)
	elif _st_is_flying:
		target_rot_x = deg_to_rad(28.0)
	else:
		var cur_pos: Vector3 = character_instance.position
		if cur_pos.y > 0.6:
			target_pos_y = sin(anim_time * 2.5) * 0.06
			target_rot_x = sin(anim_time * 1.8) * 0.03
		else:
			target_pos_y = sin(anim_time * 1.8) * 0.008

	var blend: float = clampf(16.0 * delta, 0.0, 1.0)
	mesh_node.position.y = lerpf(mesh_node.position.y, target_pos_y, blend)
	mesh_node.rotation.x = lerp_angle(mesh_node.rotation.x, target_rot_x, blend)
	mesh_node.rotation.z = lerp_angle(mesh_node.rotation.z, target_rot_z, blend)


func _apply_hips_spine_and_chest(delta: float) -> void:
	var hips_target: Vector3 = Vector3.ZERO
	var spine_target: Vector3 = Vector3.ZERO
	var chest_target: Vector3 = Vector3.ZERO
	var upper_target: Vector3 = Vector3.ZERO

	var breath_x: float = sin(breath_time) * (0.045 if _st_ki_phase > 0 else 0.02)

	if _st_is_wall_stuck:
		hips_target = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
		spine_target = Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(4.0))
		chest_target = Vector3(deg_to_rad(16.0), 0.0, 0.0)
	elif _st_is_launching_air:
		hips_target = Vector3(deg_to_rad(-25.0), 0.0, 0.0)
		spine_target = Vector3(deg_to_rad(20.0), 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(25.0), 0.0, 0.0)
	elif _st_is_airborne_stunned:
		var sway_z: float = sin(anim_time * 2.2) * deg_to_rad(6.0)
		spine_target = Vector3(deg_to_rad(-10.0), 0.0, sway_z)
		chest_target = Vector3(deg_to_rad(-14.0), 0.0, -sway_z * 0.5)
	elif _st_is_transforming:
		if _st_transform_u < 0.35:
			spine_target = Vector3(deg_to_rad(14.0), 0.0, 0.0)
			chest_target = Vector3(deg_to_rad(16.0), 0.0, 0.0)
		else:
			var roar_jit: float = sin(anim_time * 55.0) * 0.03
			spine_target = Vector3(deg_to_rad(-14.0) + roar_jit, 0.0, 0.0)
			chest_target = Vector3(deg_to_rad(-18.0) - roar_jit, 0.0, 0.0)
	elif _st_is_guard_broken:
		spine_target = Vector3(deg_to_rad(-14.0), 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(-18.0), 0.0, 0.0)
	elif _st_is_melee_active:
		var punch_snap: float = sin(minf(_st_melee_u * 1.35, 1.0) * PI)
		match melee_anim_type:
			0:
				hips_target = Vector3(0.0, deg_to_rad(-18.0 * punch_snap), 0.0)
				chest_target = Vector3(deg_to_rad(10.0 * punch_snap), deg_to_rad(-26.0 * punch_snap), 0.0)
			1:
				hips_target = Vector3(0.0, deg_to_rad(22.0 * punch_snap), 0.0)
				chest_target = Vector3(deg_to_rad(12.0 * punch_snap), deg_to_rad(32.0 * punch_snap), 0.0)
			2:
				hips_target = Vector3(0.0, deg_to_rad(-20.0 * punch_snap), 0.0)
				chest_target = Vector3(deg_to_rad(-8.0 * punch_snap), deg_to_rad(-30.0 * punch_snap), deg_to_rad(12.0 * punch_snap))
			3:
				hips_target = Vector3(deg_to_rad(-12.0 * punch_snap), deg_to_rad(38.0 * punch_snap), deg_to_rad(-18.0 * punch_snap))
				chest_target = Vector3(deg_to_rad(10.0 * punch_snap), deg_to_rad(-14.0 * punch_snap), deg_to_rad(16.0 * punch_snap))
			4:
				if _st_melee_u < 0.35:
					var w: float = _st_melee_u / 0.35
					spine_target = Vector3(deg_to_rad(-20.0 * w), 0.0, 0.0)
					chest_target = Vector3(deg_to_rad(-14.0 * w), 0.0, 0.0)
				else:
					var s: float = minf((_st_melee_u - 0.35) / 0.35, 1.0)
					spine_target = Vector3(deg_to_rad(24.0 * s), 0.0, 0.0)
					chest_target = Vector3(deg_to_rad(18.0 * s), 0.0, 0.0)
			5: # Golpe Cargado (windup atrás -> estallido frontal)
				if _st_melee_u < 0.42:
					var w: float = _st_melee_u / 0.42
					hips_target = Vector3(0.0, deg_to_rad(-24.0 * w), 0.0)
					spine_target = Vector3(deg_to_rad(-8.0 * w), 0.0, 0.0)
					chest_target = Vector3(deg_to_rad(-6.0 * w), deg_to_rad(-32.0 * w), 0.0)
				else:
					var s: float = minf((_st_melee_u - 0.42) / 0.28, 1.0)
					hips_target = Vector3(0.0, deg_to_rad(lerpf(-24.0, 28.0, s)), 0.0)
					spine_target = Vector3(deg_to_rad(lerpf(-8.0, 14.0, s)), 0.0, 0.0)
					chest_target = Vector3(deg_to_rad(lerpf(-6.0, 16.0, s)), deg_to_rad(lerpf(-32.0, 38.0, s)), 0.0)
	elif _st_super_phase == 2:
		var beam_vib: float = sin(anim_time * 58.0) * 0.02
		match _st_super_tech:
			"final_flash":
				spine_target = Vector3(deg_to_rad(8.0) + beam_vib, 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(10.0) - beam_vib, 0.0, 0.0)
			"big_bang":
				chest_target = Vector3(deg_to_rad(4.0), deg_to_rad(20.0), 0.0)
			"genkidama":
				spine_target = Vector3(deg_to_rad(16.0), 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(14.0), 0.0, 0.0)
			_:
				spine_target = Vector3(deg_to_rad(8.0) + beam_vib, 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(10.0) - beam_vib, 0.0, 0.0)
	elif _st_super_phase == 1:
		var sup_vib: float = sin(anim_time * 48.0) * 0.015
		match _st_super_tech:
			"kamehameha":
				hips_target = Vector3(deg_to_rad(8.0), deg_to_rad(-28.0), 0.0)
				spine_target = Vector3(deg_to_rad(8.0) + sup_vib, deg_to_rad(-18.0), 0.0)
				chest_target = Vector3(deg_to_rad(6.0), deg_to_rad(-22.0), 0.0)
			"galick_ho":
				hips_target = Vector3(deg_to_rad(8.0), deg_to_rad(-26.0), 0.0)
				spine_target = Vector3(deg_to_rad(8.0) + sup_vib, deg_to_rad(-20.0), 0.0)
				chest_target = Vector3(deg_to_rad(8.0), deg_to_rad(-24.0), 0.0)
			"final_flash":
				spine_target = Vector3(deg_to_rad(-6.0) + sup_vib, 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
			"big_bang":
				chest_target = Vector3(deg_to_rad(4.0), deg_to_rad(18.0), 0.0)
			"genkidama":
				spine_target = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
	elif melee_block_timer > 0.0:
		match melee_block_type:
			0:
				spine_target = Vector3(deg_to_rad(-6.0), deg_to_rad(-10.0), 0.0)
				chest_target = Vector3(deg_to_rad(4.0), deg_to_rad(-12.0), 0.0)
			1:
				spine_target = Vector3(deg_to_rad(10.0), 0.0, 0.0)
				chest_target = Vector3(deg_to_rad(8.0), 0.0, 0.0)
			2:
				hips_target = Vector3(0.0, deg_to_rad(14.0), 0.0)
				spine_target = Vector3(deg_to_rad(10.0), deg_to_rad(10.0), 0.0)
			3:
				hips_target = Vector3(0.0, deg_to_rad(-16.0), 0.0)
				chest_target = Vector3(0.0, deg_to_rad(-16.0), 0.0)
	elif _st_is_blocking:
		spine_target = Vector3(deg_to_rad(8.0) + breath_x, 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(6.0), 0.0, 0.0)
	elif _st_ki_phase > 0:
		var ki_vib: float = sin(anim_time * 52.0) * (0.025 if _st_ki_phase == 2 else 0.01)
		spine_target = Vector3(deg_to_rad(12.0) + breath_x + ki_vib, 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(6.0) - ki_vib, 0.0, 0.0)
	elif _st_is_ki_blast:
		var blast_snap: float = sin(_st_ki_blast_u * PI)
		var yaw_sign: float = -1.0 if ki_blast_hand == 0 else 1.0
		chest_target = Vector3(deg_to_rad(6.0 * blast_snap), deg_to_rad(24.0 * yaw_sign * blast_snap), 0.0)
	elif _st_is_flying:
		spine_target = Vector3(deg_to_rad(16.0), 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(10.0), 0.0, 0.0)
	elif _st_is_getup:
		var crouch: float = 1.0 - _st_getup_u
		spine_target = Vector3(deg_to_rad(36.0 * crouch), 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(14.0 * crouch), 0.0, 0.0)
	elif _st_is_exhausted:
		var pant_x: float = sin(anim_time * 5.2) * deg_to_rad(4.0)
		spine_target = Vector3(deg_to_rad(14.0) + pant_x, 0.0, 0.0)
		chest_target = Vector3(deg_to_rad(10.0) + pant_x, 0.0, 0.0)
	else:
		# Guardia marcial DBZ frontal (ligerísimo ángulo -4° para no verse de costado)
		var martial_yaw: float = deg_to_rad(-4.0)
		hips_target = Vector3(0.0, martial_yaw * 0.4, 0.0)
		spine_target = Vector3(breath_x + deg_to_rad(4.0), martial_yaw * 0.3, 0.0)
		chest_target = Vector3(breath_x * 0.8 + deg_to_rad(3.0), martial_yaw * 0.3, 0.0)

	# Superposición elástica direccional por impacto físico recibido (Hit Flinch)
	if _st_flinch_factor > 0.001:
		var flinch_pitch: float = -0.32 * _st_flinch_factor * clampf(-_st_flinch_local_dir.z, -1.0, 1.0)
		if absf(flinch_pitch) < 0.08:
			flinch_pitch = -0.28 * _st_flinch_factor
		var flinch_yaw: float = 0.28 * _st_flinch_factor * _st_flinch_local_dir.x
		var flinch_roll: float = -0.18 * _st_flinch_factor * _st_flinch_local_dir.x
		spine_target += Vector3(flinch_pitch, flinch_yaw * 0.4, flinch_roll * 0.5)
		chest_target += Vector3(flinch_pitch * 0.6, flinch_yaw * 0.6, flinch_roll * 0.5)

	if zenkai_anim_loader != null and zenkai_overlay_weight > 0.001:
		var z_clip: String = _get_active_zenkai_clip_name()
		if not z_clip.is_empty() and zenkai_anim_loader.has_clip(z_clip):
			var z_u: float = _get_active_zenkai_clip_u()
			var d_hips: Vector3 = zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip, "Hips", z_u)
			var d_spine: Vector3 = zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip, "Spine", z_u)
			var d_chest: Vector3 = zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip, "Chest", z_u)
			var d_upper: Vector3 = zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip, "UpperChest", z_u)
			hips_target += d_hips * (zenkai_overlay_weight * 0.65)
			spine_target += d_spine * zenkai_overlay_weight
			chest_target += d_chest * zenkai_overlay_weight
			upper_target += d_upper * (zenkai_overlay_weight * 0.75)

	var blend: float = clampf(16.0 * delta, 0.0, 1.0)
	current_hips_euler = current_hips_euler.lerp(hips_target, blend)
	current_spine_euler = current_spine_euler.lerp(spine_target, blend)
	current_chest_euler = current_chest_euler.lerp(chest_target, blend)
	current_upper_chest_euler = current_upper_chest_euler.lerp(upper_target, blend)

	_set_bone_rot_relative("Hips", current_hips_euler)
	_set_bone_rot_relative("Spine", current_spine_euler)
	_set_bone_rot_relative("Chest", current_chest_euler)
	_set_bone_rot_relative("UpperChest", current_upper_chest_euler)


func _apply_legs_pose(delta: float) -> void:
	# En espacio de personaje (+X=Izq, +Y=Arriba, +Z=Frente):
	# Muslo adelante = -X, Muslo atrás = +X, Rodilla doblada atrás = +X
	# Separar pierna Izq (+X) = +Z, Separar pierna Der (-X) = -Z
	var l_up: Vector3 = Vector3.ZERO
	var l_knee: Vector3 = Vector3.ZERO
	var r_up: Vector3 = Vector3.ZERO
	var r_knee: Vector3 = Vector3.ZERO

	if _st_is_wall_stuck:
		l_up = Vector3(deg_to_rad(-20.0), 0.0, deg_to_rad(20.0))
		l_knee = Vector3(deg_to_rad(40.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(-16.0), 0.0, deg_to_rad(-20.0))
		r_knee = Vector3(deg_to_rad(36.0), 0.0, 0.0)
	elif _st_is_launching_air:
		l_up = Vector3(deg_to_rad(-42.0), 0.0, deg_to_rad(12.0))
		l_knee = Vector3(deg_to_rad(36.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(-36.0), 0.0, deg_to_rad(-12.0))
		r_knee = Vector3(deg_to_rad(32.0), 0.0, 0.0)
	elif _st_is_airborne_stunned:
		l_up = Vector3(deg_to_rad(-26.0), 0.0, deg_to_rad(10.0))
		l_knee = Vector3(deg_to_rad(42.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(8.0), 0.0, deg_to_rad(-10.0))
		r_knee = Vector3(deg_to_rad(22.0), 0.0, 0.0)
	elif _st_is_transforming:
		if _st_transform_u < 0.35:
			l_up = Vector3(deg_to_rad(-32.0), 0.0, deg_to_rad(15.0))
			l_knee = Vector3(deg_to_rad(52.0), 0.0, 0.0)
			r_up = Vector3(deg_to_rad(-32.0), 0.0, deg_to_rad(-15.0))
			r_knee = Vector3(deg_to_rad(52.0), 0.0, 0.0)
		else:
			l_up = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(18.0))
			l_knee = Vector3(deg_to_rad(18.0), 0.0, 0.0)
			r_up = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-18.0))
			r_knee = Vector3(deg_to_rad(18.0), 0.0, 0.0)
	elif _st_is_guard_broken:
		l_up = Vector3(deg_to_rad(-26.0), 0.0, deg_to_rad(14.0))
		l_knee = Vector3(deg_to_rad(42.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(-14.0))
		r_knee = Vector3(deg_to_rad(38.0), 0.0, 0.0)
	elif _st_is_melee_active and melee_anim_type == 3:
		var kick_snap: float = sin(minf(_st_melee_u * 1.25, 1.0) * PI)
		l_up = Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(8.0))
		l_knee = Vector3(deg_to_rad(20.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(-76.0 * kick_snap), deg_to_rad(-20.0 * kick_snap), deg_to_rad(-28.0 * kick_snap))
		r_knee = Vector3(deg_to_rad(12.0 * kick_snap), 0.0, 0.0)
	elif _st_super_phase == 2:
		match _st_super_tech:
			"final_flash", "genkidama":
				l_up = Vector3(deg_to_rad(-24.0), 0.0, deg_to_rad(16.0))
				l_knee = Vector3(deg_to_rad(36.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(-24.0), 0.0, deg_to_rad(-16.0))
				r_knee = Vector3(deg_to_rad(36.0), 0.0, 0.0)
			"big_bang":
				l_up = Vector3(deg_to_rad(-10.0), 0.0, deg_to_rad(10.0))
				l_knee = Vector3(deg_to_rad(14.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(10.0), 0.0, deg_to_rad(-10.0))
				r_knee = Vector3(deg_to_rad(14.0), 0.0, 0.0)
			_:
				l_up = Vector3(deg_to_rad(-36.0), 0.0, deg_to_rad(12.0))
				l_knee = Vector3(deg_to_rad(46.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(-12.0))
				r_knee = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	elif _st_super_phase == 1:
		match _st_super_tech:
			"kamehameha", "galick_ho":
				l_up = Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(12.0))
				l_knee = Vector3(deg_to_rad(28.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(-32.0), 0.0, deg_to_rad(-14.0))
				r_knee = Vector3(deg_to_rad(46.0), 0.0, 0.0)
			"big_bang":
				l_up = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(10.0))
				l_knee = Vector3(deg_to_rad(16.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(10.0), 0.0, deg_to_rad(-10.0))
				r_knee = Vector3(deg_to_rad(14.0), 0.0, 0.0)
			_:
				l_up = Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(16.0))
				l_knee = Vector3(deg_to_rad(42.0), 0.0, 0.0)
				r_up = Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(-16.0))
				r_knee = Vector3(deg_to_rad(42.0), 0.0, 0.0)
	elif _st_ki_phase > 0:
		l_up = Vector3(deg_to_rad(-32.0), 0.0, deg_to_rad(15.0))
		l_knee = Vector3(deg_to_rad(48.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(-32.0), 0.0, deg_to_rad(-15.0))
		r_knee = Vector3(deg_to_rad(48.0), 0.0, 0.0)
	elif _st_is_flying:
		l_up = Vector3(deg_to_rad(-44.0), 0.0, deg_to_rad(6.0))
		l_knee = Vector3(deg_to_rad(66.0), 0.0, 0.0)
		r_up = Vector3(deg_to_rad(22.0), 0.0, deg_to_rad(-6.0))
		r_knee = Vector3(deg_to_rad(18.0), 0.0, 0.0)
	elif _st_is_getup:
		var k: float = 1.0 - _st_getup_u
		l_up = Vector3(lerpf(deg_to_rad(-55.0), deg_to_rad(-18.0), _st_getup_u), 0.0, deg_to_rad(10.0))
		l_knee = Vector3(lerpf(deg_to_rad(72.0), deg_to_rad(24.0), _st_getup_u), 0.0, 0.0)
		r_up = Vector3(lerpf(deg_to_rad(-72.0), deg_to_rad(14.0), _st_getup_u), 0.0, deg_to_rad(-10.0 * k - 8.0))
		r_knee = Vector3(lerpf(deg_to_rad(94.0), deg_to_rad(18.0), _st_getup_u), 0.0, 0.0)
	else:
		# Guardia marcial viva (pierna izquierda adelante, derecha atrás en apoyo)
		var sway: float = sin(anim_time * 1.8) * 0.03
		l_up = Vector3(deg_to_rad(-18.0) + sway, 0.0, deg_to_rad(10.0))
		l_knee = Vector3(deg_to_rad(24.0) - sway * 0.6, 0.0, 0.0)
		r_up = Vector3(deg_to_rad(14.0) - sway, 0.0, deg_to_rad(-10.0))
		r_knee = Vector3(deg_to_rad(18.0) + sway * 0.6, 0.0, 0.0)

	if zenkai_anim_loader != null and zenkai_overlay_weight > 0.001:
		var z_clip_legs: String = _get_active_zenkai_clip_name()
		if not z_clip_legs.is_empty() and zenkai_anim_loader.has_clip(z_clip_legs):
			var z_u_legs: float = _get_active_zenkai_clip_u()
			var leg_w: float = zenkai_overlay_weight * 0.60
			l_up += zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip_legs, "LeftUpLeg", z_u_legs) * leg_w
			l_knee += zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip_legs, "LeftLeg", z_u_legs) * leg_w
			r_up += zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip_legs, "RightUpLeg", z_u_legs) * leg_w
			r_knee += zenkai_anim_loader.sample_clip_bone_delta_euler(z_clip_legs, "RightLeg", z_u_legs) * leg_w

	var blend: float = clampf(14.0 * delta, 0.0, 1.0)
	current_l_upleg_euler = current_l_upleg_euler.lerp(l_up, blend)
	current_l_leg_euler = current_l_leg_euler.lerp(l_knee, blend)
	current_r_upleg_euler = current_r_upleg_euler.lerp(r_up, blend)
	current_r_leg_euler = current_r_leg_euler.lerp(r_knee, blend)

	_set_bone_rot_relative("LeftUpLeg", current_l_upleg_euler)
	_set_bone_rot_relative("LeftLeg", current_l_leg_euler)
	_set_bone_rot_relative("RightUpLeg", current_r_upleg_euler)
	_set_bone_rot_relative("RightLeg", current_r_leg_euler)


func _apply_look_at(delta: float, target_pos: Vector3) -> void:
	if not bone_indices.has("Head") or not bone_indices.has("Neck"):
		return

	var target_neck_euler: Vector3 = Vector3.ZERO
	var target_head_euler: Vector3 = Vector3.ZERO

	if _st_is_wall_stuck:
		target_neck_euler = Vector3(deg_to_rad(22.0), deg_to_rad(8.0), 0.0)
		target_head_euler = Vector3(deg_to_rad(40.0), deg_to_rad(14.0), 0.0)
	elif _st_is_launching_air:
		target_neck_euler = Vector3(deg_to_rad(12.0), 0.0, 0.0)
		target_head_euler = Vector3(deg_to_rad(24.0), 0.0, 0.0)
	elif _st_is_airborne_stunned:
		target_neck_euler = Vector3(deg_to_rad(-10.0), 0.0, deg_to_rad(8.0))
		target_head_euler = Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(16.0))
	elif _st_is_transforming and _st_transform_u >= 0.35:
		target_neck_euler = Vector3(deg_to_rad(-16.0), 0.0, 0.0)
		target_head_euler = Vector3(deg_to_rad(-28.0), 0.0, 0.0)
	elif _st_flinch_factor > 0.40:
		target_neck_euler = Vector3(-0.22 * _st_flinch_factor, 0.0, 0.0)
		target_head_euler = Vector3(-0.42 * _st_flinch_factor, 0.0, 0.0)
	else:
		var char_basis: Basis = character_instance.global_transform.basis.orthonormalized()
		var head_pos: Vector3 = character_instance.global_position + char_basis.y * 1.50
		if skeleton and is_instance_valid(skeleton) and skeleton.is_inside_tree():
			var head_idx: int = int(bone_indices.get("Head", -1))
			if head_idx != -1:
				var bone_world_pos: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(head_idx).origin)
				var rel_h: float = (bone_world_pos - character_instance.global_position).dot(char_basis.y)
				if rel_h > 0.8 and rel_h < 2.2:
					head_pos = bone_world_pos + char_basis.y * 0.08
		var local_target: Vector3 = char_basis.inverse() * (target_pos - head_pos)

		# Frente canónico del personaje es +Z; compensar giro y pitch acumulado del torso/malla para mantener vista al jugador
		var torso_yaw_offset: float = current_hips_euler.y + current_spine_euler.y + current_chest_euler.y + current_upper_chest_euler.y
		var torso_pitch_offset: float = current_hips_euler.x + current_spine_euler.x + current_chest_euler.x + current_upper_chest_euler.x
		var mesh_node: Node3D = character_instance.get("body_mesh_instance") as Node3D
		if mesh_node and is_instance_valid(mesh_node):
			torso_pitch_offset += mesh_node.rotation.x
		var yaw: float = clampf(atan2(local_target.x, local_target.z) - torso_yaw_offset * 0.75, deg_to_rad(-58.0), deg_to_rad(58.0))
		var horizontal_dist: float = Vector2(local_target.x, local_target.z).length()
		var desired_pitch: float = -atan2(local_target.y, maxf(horizontal_dist, 0.1))
		var pitch: float = clampf(desired_pitch - torso_pitch_offset * 0.85, deg_to_rad(-35.0), deg_to_rad(35.0))
		if _st_ki_phase > 0:
			pitch += deg_to_rad(12.0)

		target_neck_euler = Vector3(pitch * 0.45, yaw * 0.45, 0.0)
		target_head_euler = Vector3(pitch * 0.55, yaw * 0.55, 0.0)

	current_neck_euler = current_neck_euler.lerp(target_neck_euler, clampf(10.0 * delta, 0.0, 1.0))
	current_head_euler = current_head_euler.lerp(target_head_euler, clampf(12.0 * delta, 0.0, 1.0))

	_set_bone_rot_relative("Neck", current_neck_euler)
	_set_bone_rot_relative("Head", current_head_euler)


func _apply_arms_pose(delta: float) -> void:
	if not character_instance or not character_instance.has_method("solve_character_arm_ik_basis"):
		return

	# Bases estándar verificadas en espacio canónico de personaje (+X=Izq, +Y=Arriba, +Z=Frente)
	var guard_basis_l: Basis = Basis.looking_at(Vector3(-0.20, 0.45, 0.87).normalized(), Vector3(0.25, 0.96, 0.0).normalized())
	var guard_basis_r: Basis = Basis.looking_at(Vector3(0.20, 0.40, 0.89).normalized(), Vector3(-0.25, 0.96, 0.0).normalized())
	var palm_fwd_l: Basis = Basis.looking_at(Vector3(0.0, 0.85, 0.52).normalized(), Vector3(-1.0, 0.0, 0.0))
	var palm_fwd_r: Basis = Basis.looking_at(Vector3(0.0, 0.85, 0.52).normalized(), Vector3(1.0, 0.0, 0.0))

	var des_pos_l: Vector3 = Vector3(-0.02, -0.02, 0.36)
	var des_pos_r: Vector3 = Vector3(0.04, -0.12, 0.24)
	var des_basis_l: Basis = guard_basis_l
	var des_basis_r: Basis = guard_basis_r
	var grip_l: float = 0.72
	var trig_l: float = 0.65
	var grip_r: float = 0.72
	var trig_r: float = 0.65

	if _st_is_wall_stuck:
		des_pos_l = Vector3(0.28, 0.18, -0.08)
		des_pos_r = Vector3(-0.28, 0.14, -0.08)
		des_basis_l = palm_fwd_l
		des_basis_r = palm_fwd_r
		grip_l = 0.10
		trig_l = 0.10
		grip_r = 0.10
		trig_r = 0.10
	elif _st_is_launching_air:
		var flutter: float = sin(anim_time * 32.0) * 0.03
		des_pos_l = Vector3(0.20, 0.10 + flutter, 0.40)
		des_pos_r = Vector3(-0.20, 0.08 - flutter, 0.40)
		des_basis_l = guard_basis_l
		des_basis_r = guard_basis_r
		grip_l = 0.35
		trig_l = 0.35
		grip_r = 0.35
		trig_r = 0.35
	elif _st_is_airborne_stunned:
		des_pos_l = Vector3(0.24, -0.10, 0.10)
		des_pos_r = Vector3(-0.24, -0.12, 0.12)
		grip_l = 0.20
		trig_l = 0.20
		grip_r = 0.20
		trig_r = 0.20
	elif _st_is_transforming:
		if _st_transform_u < 0.35:
			des_pos_l = Vector3(-0.04, -0.10, 0.22)
			des_pos_r = Vector3(0.04, -0.10, 0.22)
			grip_l = 1.0
			trig_l = 1.0
			grip_r = 1.0
			trig_r = 1.0
		else:
			var roar_j: float = sin(anim_time * 54.0) * 0.02
			des_pos_l = Vector3(0.24 + roar_j, -0.24, 0.05)
			des_pos_r = Vector3(-0.24 - roar_j, -0.24, 0.05)
			des_basis_l = Basis.looking_at(Vector3(0.35, -0.35, 0.87).normalized(), Vector3(0.3, 0.95, 0.0).normalized())
			des_basis_r = Basis.looking_at(Vector3(-0.35, -0.35, 0.87).normalized(), Vector3(-0.3, 0.95, 0.0).normalized())
			grip_l = 0.65
			trig_l = 0.65
			grip_r = 0.65
			trig_r = 0.65
	elif _st_is_guard_broken:
		des_pos_l = Vector3(0.34, 0.05, 0.06)
		des_pos_r = Vector3(-0.34, 0.05, 0.06)
		des_basis_l = palm_fwd_l
		des_basis_r = palm_fwd_r
		grip_l = 0.20
		trig_l = 0.20
		grip_r = 0.20
		trig_r = 0.20
	elif _st_is_melee_active:
		var punch_curve: float = sin(minf(_st_melee_u * 1.3, 1.0) * PI)
		match melee_anim_type:
			0: # Jab Izquierdo
				des_pos_l = Vector3(0.0, 0.04, lerpf(0.18, 0.54, punch_curve))
				des_pos_r = Vector3(0.02, 0.05, 0.22)
			1: # Cross Derecho
				des_pos_l = Vector3(-0.04, -0.10, 0.16)
				des_pos_r = Vector3(0.0, 0.03, lerpf(0.18, 0.56, punch_curve))
			2: # Gancho / Uppercut Izquierdo
				des_pos_l = Vector3(lerpf(0.12, -0.10, punch_curve), lerpf(-0.18, 0.16, punch_curve), lerpf(0.20, 0.44, punch_curve))
				des_pos_r = Vector3(0.02, 0.04, 0.22)
			3: # Patada Circular (manos arriba en guardia de equilibrio)
				des_pos_l = Vector3(0.04, 0.06, 0.26)
				des_pos_r = Vector3(-0.12, -0.02, 0.18)
			4: # Martillazo DBZ 2 Manos (arriba -> abajo)
				if _st_melee_u < 0.35:
					var w: float = _st_melee_u / 0.35
					des_pos_l = Vector3(0.06, lerpf(0.0, 0.48, w), 0.18)
					des_pos_r = Vector3(-0.06, lerpf(0.0, 0.48, w), 0.18)
				else:
					var s: float = minf((_st_melee_u - 0.35) / 0.35, 1.0)
					des_pos_l = Vector3(0.06, lerpf(0.48, -0.32, s), lerpf(0.18, 0.46, s))
					des_pos_r = Vector3(-0.06, lerpf(0.48, -0.32, s), lerpf(0.18, 0.46, s))
			5: # Golpe Cargado (windup atrás en cadera -> puñetazo explosivo a máxima extensión)
				if _st_melee_u < 0.42:
					var w: float = _st_melee_u / 0.42
					des_pos_l = Vector3(0.06, 0.04, lerpf(0.28, 0.36, w))
					des_pos_r = Vector3(lerpf(0.0, -0.18, w), lerpf(-0.08, -0.14, w), lerpf(0.20, -0.14, w))
				else:
					var s: float = minf((_st_melee_u - 0.42) / 0.25, 1.0)
					des_pos_l = Vector3(lerpf(0.06, 0.14, s), lerpf(0.04, -0.10, s), lerpf(0.36, 0.14, s))
					des_pos_r = Vector3(lerpf(-0.18, -0.02, s), lerpf(-0.14, 0.04, s), lerpf(-0.14, 0.56, s))
		grip_l = 1.0
		trig_l = 1.0
		grip_r = 1.0
		trig_r = 1.0
	elif _st_super_phase == 2:
		var bv_x: float = sin(anim_time * 59.0) * 0.014
		var bv_y: float = cos(anim_time * 53.0) * 0.014
		match _st_super_tech:
			"big_bang":
				des_pos_l = Vector3(0.02, -0.14, 0.18)
				des_pos_r = Vector3(0.06 + bv_x, 0.04 + bv_y, 0.54)
				des_basis_r = palm_fwd_r
				grip_l = 0.85
				trig_l = 0.85
				grip_r = 0.05
				trig_r = 0.05
			"genkidama":
				des_pos_l = Vector3(-0.06 + bv_x, -0.06 + bv_y, 0.48)
				des_pos_r = Vector3(0.06 - bv_x, -0.06 - bv_y, 0.48)
				des_basis_l = palm_fwd_l
				des_basis_r = palm_fwd_r
				grip_l = 0.10
				trig_l = 0.10
				grip_r = 0.10
				trig_r = 0.10
			_: # Kamehameha, Galick Ho, Final Flash Fase 2
				des_pos_l = Vector3(-0.06 + bv_x, -0.04 + bv_y, 0.50)
				des_pos_r = Vector3(0.06 - bv_x, -0.04 - bv_y, 0.50)
				des_basis_l = palm_fwd_l
				des_basis_r = palm_fwd_r
				grip_l = 0.10
				trig_l = 0.10
				grip_r = 0.10
				trig_r = 0.10
	elif _st_super_phase == 1:
		var sv: float = sin(anim_time * 47.0) * 0.010
		match _st_super_tech:
			"kamehameha":
				des_pos_l = Vector3(-0.42, -0.14 + sv, 0.22)
				des_pos_r = Vector3(0.02, -0.28 - sv, 0.22)
				des_basis_l = Basis.looking_at(Vector3(-0.35, -0.10, 0.93).normalized(), Vector3(-0.93, 0.0, -0.35).normalized())
				des_basis_r = Basis.looking_at(Vector3(-0.35, 0.10, 0.93).normalized(), Vector3(-0.93, 0.0, -0.35).normalized())
				grip_l = 0.35
				trig_l = 0.35
				grip_r = 0.35
				trig_r = 0.35
			"galick_ho":
				des_pos_l = Vector3(-0.30, -0.04 + sv, 0.10)
				des_pos_r = Vector3(-0.08, -0.02 - sv, 0.06)
				des_basis_l = palm_fwd_l
				des_basis_r = palm_fwd_r
				grip_l = 0.25
				trig_l = 0.25
				grip_r = 0.25
				trig_r = 0.25
			"final_flash":
				des_pos_l = Vector3(0.38, 0.02 + sv, 0.08)
				des_pos_r = Vector3(-0.38, 0.02 - sv, 0.08)
				des_basis_l = palm_fwd_l
				des_basis_r = palm_fwd_r
				grip_l = 0.20
				trig_l = 0.20
				grip_r = 0.20
				trig_r = 0.20
			"big_bang":
				des_pos_l = Vector3(0.02, -0.14, 0.18)
				des_pos_r = Vector3(0.06, 0.04 + sv, 0.54)
				des_basis_r = palm_fwd_r
				grip_l = 0.85
				trig_l = 0.85
				grip_r = 0.05
				trig_r = 0.05
			"genkidama":
				des_pos_l = Vector3(0.12, 0.46 + sv, 0.06)
				des_pos_r = Vector3(-0.12, 0.46 - sv, 0.06)
				des_basis_l = palm_fwd_l
				des_basis_r = palm_fwd_r
				grip_l = 0.05
				trig_l = 0.05
				grip_r = 0.05
				trig_r = 0.05
	elif melee_block_timer > 0.0:
		match melee_block_type:
			0: # Bloqueo con una mano (brazo derecho arriba cubriendo rostro, palma abierta)
				des_pos_l = Vector3(0.08, -0.04, 0.20)
				des_pos_r = Vector3(0.02, 0.16, 0.36)
				des_basis_r = palm_fwd_r
				grip_l = 0.85; trig_l = 0.85; grip_r = 0.05; trig_r = 0.15
			1: # Guardia Cruzada en X
				des_pos_l = Vector3(-0.14, 0.12, 0.30)
				des_pos_r = Vector3(0.14, 0.08, 0.26)
				des_basis_l = Basis.looking_at(Vector3(-0.42, 0.82, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
				des_basis_r = Basis.looking_at(Vector3(0.42, 0.82, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
				grip_l = 0.95; trig_l = 0.95; grip_r = 0.95; trig_r = 0.95
			2: # Choque de Puños (puño derecho extendido al impacto)
				des_pos_l = Vector3(-0.10, -0.06, 0.18)
				des_pos_r = Vector3(0.0, 0.04, 0.52)
				grip_l = 0.95; trig_l = 0.95; grip_r = 1.0; trig_r = 1.0
			3: # Bloqueo Perfecto (parada/desvío firme con una mano al frente y la otra en guardia baja)
				des_pos_l = Vector3(0.10, -0.10, 0.16)
				des_pos_r = Vector3(-0.02, 0.18, 0.44)
				des_basis_r = palm_fwd_r
				grip_l = 0.90; trig_l = 0.90; grip_r = 0.05; trig_r = 0.10
	elif _st_is_blocking:
		des_pos_l = Vector3(-0.14, 0.12, 0.30)
		des_pos_r = Vector3(0.14, 0.08, 0.26)
		des_basis_l = Basis.looking_at(Vector3(-0.42, 0.82, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
		des_basis_r = Basis.looking_at(Vector3(0.42, 0.82, 0.38).normalized(), Vector3(0.0, 0.35, -0.94).normalized())
		grip_l = 0.90
		trig_l = 0.85
		grip_r = 0.90
		trig_r = 0.85
	elif _st_ki_phase == 1:
		des_pos_l = Vector3(-0.06, -0.02, 0.26)
		des_pos_r = Vector3(0.06, -0.04, 0.24)
		grip_l = 0.92
		trig_l = 0.92
		grip_r = 0.92
		trig_r = 0.92
	elif _st_ki_phase == 2:
		var kj_x: float = sin(anim_time * 57.0) * 0.010
		var kj_y: float = cos(anim_time * 61.0) * 0.010
		des_pos_l = Vector3(0.06 + kj_x, -0.24 + kj_y, 0.12)
		des_pos_r = Vector3(-0.06 - kj_x, -0.24 - kj_y, 0.12)
		des_basis_l = Basis.looking_at(Vector3(-0.15, -0.15, 0.97).normalized(), Vector3(0.3, 0.95, 0.0).normalized())
		des_basis_r = Basis.looking_at(Vector3(0.15, -0.15, 0.97).normalized(), Vector3(-0.3, 0.95, 0.0).normalized())
		grip_l = 1.0
		trig_l = 1.0
		grip_r = 1.0
		trig_r = 1.0
	elif _st_is_ki_blast:
		var recoil: float = sin(_st_ki_blast_u * PI) * 0.06
		if ki_blast_hand == 0:
			des_pos_l = Vector3(-0.02, 0.02, 0.50 - recoil)
			des_basis_l = palm_fwd_l
			grip_l = 0.08
			trig_l = 0.08
			des_pos_r = Vector3(0.04, -0.12, 0.24)
		else:
			des_pos_l = Vector3(-0.02, -0.02, 0.34)
			des_pos_r = Vector3(0.02, 0.02, 0.50 - recoil)
			des_basis_r = palm_fwd_r
			grip_r = 0.08
			trig_r = 0.08
	elif _st_is_flying:
		des_pos_l = Vector3(0.14, -0.22, -0.18)
		des_pos_r = Vector3(-0.14, -0.22, -0.18)
		grip_l = 1.0
		trig_l = 1.0
		grip_r = 1.0
		trig_r = 1.0
	elif _st_is_getup:
		des_pos_l = Vector3(lerpf(0.08, -0.02, _st_getup_u), lerpf(-0.14, -0.02, _st_getup_u), lerpf(0.20, 0.36, _st_getup_u))
		des_pos_r = Vector3(lerpf(0.04, 0.04, _st_getup_u), lerpf(-0.32, -0.12, _st_getup_u), lerpf(0.28, 0.24, _st_getup_u))
		grip_l = 0.65
		trig_l = 0.65
		grip_r = lerpf(0.15, 0.85, _st_getup_u)
		trig_r = grip_r
	elif _st_is_exhausted:
		var breath_arm: float = sin(anim_time * 5.2) * 0.015
		des_pos_l = Vector3(0.04, -0.18 + breath_arm, 0.16)
		des_pos_r = Vector3(-0.04, -0.22 + breath_arm, 0.12)
		grip_l = 0.45
		trig_l = 0.45
		grip_r = 0.45
		trig_r = 0.45
	else:
		# Guardia Marcial DBZ diferenciada (Goku vs Vegeta) + retroceso elástico de impacto
		var idle_pulse: float = sin(anim_time * 1.6) * 0.018
		var flinch_pull: Vector3 = Vector3(0.0, 0.06, -0.12) * _st_flinch_factor
		if is_vegeta_char:
			des_pos_l = Vector3(-0.04, 0.02 + idle_pulse, 0.34) + flinch_pull
			des_pos_r = Vector3(0.04, -0.08 - idle_pulse, 0.26) + flinch_pull
			grip_l = 0.95
			trig_l = 0.95
			grip_r = 0.95
			trig_r = 0.95
		else:
			des_pos_l = Vector3(-0.02, -0.02 + idle_pulse, 0.36) + flinch_pull
			des_pos_r = Vector3(0.04, -0.12 - idle_pulse, 0.24) + flinch_pull
			grip_l = 0.42
			trig_l = 0.38
			grip_r = 0.92
			trig_r = 0.85

	if not _arm_bases_initialized:
		_cur_left_hand_pos = des_pos_l
		_cur_right_hand_pos = des_pos_r
		_cur_left_hand_basis = des_basis_l
		_cur_right_hand_basis = des_basis_r
		_arm_bases_initialized = true
	else:
		var snap_speed: float = 26.0 if (_st_is_melee_active or _st_is_ki_blast or _st_super_phase == 2) else 15.0
		var blend: float = clampf(snap_speed * delta, 0.0, 1.0)
		_cur_left_hand_pos = _cur_left_hand_pos.lerp(des_pos_l, blend)
		_cur_right_hand_pos = _cur_right_hand_pos.lerp(des_pos_r, blend)
		_cur_left_hand_basis = _cur_left_hand_basis.slerp(des_basis_l, blend).orthonormalized()
		_cur_right_hand_basis = _cur_right_hand_basis.slerp(des_basis_r, blend).orthonormalized()

	character_instance.solve_character_arm_ik_basis(true, _cur_left_hand_pos, _cur_left_hand_basis)
	character_instance.solve_character_arm_ik_basis(false, _cur_right_hand_pos, _cur_right_hand_basis)
	if character_instance.has_method("_apply_finger_curls_to_skeleton"):
		character_instance._apply_finger_curls_to_skeleton(skeleton, "Left", trig_l, grip_l)
		character_instance._apply_finger_curls_to_skeleton(skeleton, "Right", trig_r, grip_r)


func _set_bone_rot_relative(bone_name: String, offset_euler_char: Vector3) -> void:
	if not bone_indices.has(bone_name) or not bone_rest_rotations.has(bone_name):
		return

	var idx: int = bone_indices[bone_name]
	if character_instance and character_instance.has_method("get_bone_rotation_char_space"):
		skeleton.set_bone_pose_rotation(idx, character_instance.get_bone_rotation_char_space(idx, offset_euler_char))
		return

	var rest_quat: Quaternion = bone_rest_rotations[bone_name]
	var offset_quat: Quaternion = Quaternion.from_euler(offset_euler_char)
	skeleton.set_bone_pose_rotation(idx, (offset_quat * rest_quat).normalized())


func _is_bone_group_enabled(bone_alias: String) -> bool:
	if bone_alias in ["Hips", "Spine", "Chest", "UpperChest"]:
		return spa_enable_torso
	if bone_alias in ["Neck", "Head"]:
		return spa_enable_head
	if bone_alias in ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]:
		return spa_enable_arms
	if bone_alias in ["LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]:
		return spa_enable_legs
	return true


func _swap_lr_alias(bone_alias: String) -> String:
	if not spa_swap_lr:
		return bone_alias
	if bone_alias.begins_with("Left"):
		return "Right" + bone_alias.substr(4)
	if bone_alias.begins_with("Right"):
		return "Left" + bone_alias.substr(5)
	return bone_alias


func _apply_spa_axis_signs(q: Quaternion) -> Quaternion:
	return Quaternion(q.x * spa_axis_signs.x, q.y * spa_axis_signs.y, q.z * spa_axis_signs.z, q.w).normalized()


func _apply_pure_zenkai_full_body(delta: float, clip_name: String, u: float) -> void:
	var blend: float = clampf(18.0 * delta, 0.0, 1.0)
	for bone_alias in TARGET_BONES:
		var idx: int = int(bone_indices.get(bone_alias, -1))
		if idx == -1:
			continue
		var rest_q: Quaternion = bone_rest_rotations.get(bone_alias, Quaternion.IDENTITY)
		if not _is_bone_group_enabled(bone_alias):
			_zenkai_bone_quats[bone_alias] = rest_q
			skeleton.set_bone_pose_rotation(idx, rest_q)
			continue
		var sample_alias: String = _swap_lr_alias(bone_alias)
		var raw_q: Quaternion = zenkai_anim_loader.sample_clip_bone_rotation(clip_name, sample_alias, u, Quaternion.IDENTITY)
		var spa_q: Quaternion = _apply_spa_axis_signs(raw_q)
		var target_q: Quaternion = rest_q
		if bone_alias == "Hips" or bone_alias == "Neck" or bone_alias == "Head":
			var raw_q0: Quaternion = zenkai_anim_loader.sample_clip_bone_rotation(clip_name, sample_alias, 0.0, Quaternion.IDENTITY)
			var spa_q0: Quaternion = _apply_spa_axis_signs(raw_q0)
			var delta_q: Quaternion = (spa_q0.inverse() * spa_q).normalized()
			target_q = (delta_q * rest_q).normalized()
		else:
			match spa_compose_mode:
				0:
					target_q = (rest_q * spa_q).normalized()
				1:
					target_q = (spa_q * rest_q).normalized()
				2:
					target_q = (rest_q * spa_q.inverse()).normalized()
				3:
					target_q = spa_q
				_:
					target_q = _map_calibrated_spa_bone(bone_alias, rest_q, spa_q)
		var cur_q: Quaternion = _zenkai_bone_quats.get(bone_alias, rest_q)
		var next_q: Quaternion = cur_q.slerp(target_q, blend).normalized()
		_zenkai_bone_quats[bone_alias] = next_q
		skeleton.set_bone_pose_rotation(idx, next_q)


func _map_calibrated_spa_bone(bone_alias: String, rest_q: Quaternion, spa_q: Quaternion) -> Quaternion:
	# Base empírica de skeleton_axis_calibration.json (21_goku1_body.glb):
	# Hombros: -Y adelante, -Z abajo | Codos: -Y flexión sin pellizco | Muslos: -Y adelante | Rodillas: +Y flexión atrás
	if bone_alias == "LeftForeArm" or bone_alias == "RightForeArm":
		var flex_rad: float = clampf(2.0 * acos(clampf(absf(spa_q.w), 0.0, 1.0)), 0.0, deg_to_rad(120.0))
		var mapped_q: Quaternion = Quaternion.from_euler(Vector3(0.0, -flex_rad, 0.0))
		return (rest_q * mapped_q).normalized()
	if bone_alias == "LeftUpLeg" or bone_alias == "RightUpLeg":
		# Escala 0.45 en flexión -Y para evitar postura "sentado" (-60° -> -27°)
		var e: Vector3 = spa_q.get_euler()
		var mapped_leg: Quaternion = Quaternion.from_euler(Vector3(
			clampf(e.x * 0.40, deg_to_rad(-20.0), deg_to_rad(20.0)),
			clampf(e.y * 0.48, deg_to_rad(-55.0), deg_to_rad(25.0)),
			clampf(-e.z * 0.65, deg_to_rad(-22.0), deg_to_rad(22.0))
		))
		return (rest_q * mapped_leg).normalized()
	if bone_alias == "LeftLeg" or bone_alias == "RightLeg":
		var knee_y: float = clampf(spa_q.y * 0.48, 0.0, 0.52)
		var knee_w: float = sqrt(maxf(0.01, 1.0 - knee_y * knee_y))
		var knee_q: Quaternion = Quaternion(0.0, knee_y, 0.0, knee_w).normalized()
		return (rest_q * knee_q).normalized()
	if bone_alias == "LeftArm":
		# Base calibrada: brazos al frente (-Y) y altura de guardia en pecho (-Z acotado a -48°)
		var e_l: Vector3 = spa_q.get_euler()
		var arm_l: Quaternion = Quaternion.from_euler(Vector3(
			clampf(e_l.x * 0.35, deg_to_rad(-40.0), deg_to_rad(40.0)),
			clampf(-absf(e_l.y) - deg_to_rad(22.0), deg_to_rad(-95.0), deg_to_rad(15.0)),
			clampf(-absf(e_l.z) * 0.55 - deg_to_rad(12.0), deg_to_rad(-48.0), deg_to_rad(25.0))
		))
		return (rest_q * arm_l).normalized()
	if bone_alias == "RightArm":
		var e_r: Vector3 = spa_q.get_euler()
		var arm_r: Quaternion = Quaternion.from_euler(Vector3(
			clampf(e_r.x * 0.35, deg_to_rad(-40.0), deg_to_rad(40.0)),
			clampf(-absf(e_r.y) - deg_to_rad(25.0), deg_to_rad(-95.0), deg_to_rad(15.0)),
			clampf(-absf(e_r.z) * 0.55 - deg_to_rad(10.0), deg_to_rad(-48.0), deg_to_rad(25.0))
		))
		return (rest_q * arm_r).normalized()
	if bone_alias == "LeftHand" or bone_alias == "RightHand":
		var e_h: Vector3 = spa_q.get_euler()
		var hand_q: Quaternion = Quaternion.from_euler(Vector3(
			clampf(e_h.x, deg_to_rad(-140.0), deg_to_rad(40.0)),
			clampf(e_h.y * 0.4, deg_to_rad(-30.0), deg_to_rad(30.0)),
			clampf(e_h.z * 0.4, deg_to_rad(-30.0), deg_to_rad(30.0))
		))
		return (rest_q * hand_q).normalized()
	return (rest_q * spa_q).normalized()


func get_spa_debug_summary() -> String:
	var clip: String = spa_forced_clip if not spa_forced_clip.is_empty() else _get_active_zenkai_clip_name()
	var u: float = spa_forced_u if spa_forced_u >= 0.0 else _get_active_zenkai_clip_u()
	var comp_names: Array[String] = ["0:rest*spa", "1:spa*rest", "2:rest*inv", "3:direct", "4:calibrado"]
	var cname: String = comp_names[clampi(spa_compose_mode, 0, 4)]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SPA=%s | clip=%s | u=%.2f | comp=%s" % ["ON" if use_pure_zenkai_spa else "OFF", clip, u, cname])
	lines.append("signs=(%+.0f,%+.0f,%+.0f) | swapLR=%s | T:%d A:%d L:%d H:%d" % [
		spa_axis_signs.x, spa_axis_signs.y, spa_axis_signs.z,
		"ON" if spa_swap_lr else "OFF",
		1 if spa_enable_torso else 0,
		1 if spa_enable_arms else 0,
		1 if spa_enable_legs else 0,
		1 if spa_enable_head else 0
	])
	if skeleton != null and is_instance_valid(skeleton):
		for b_alias in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg"]:
			var idx: int = int(bone_indices.get(b_alias, -1))
			if idx == -1:
				continue
			var rest_q: Quaternion = bone_rest_rotations.get(b_alias, Quaternion.IDENTITY)
			var pose_q: Quaternion = skeleton.get_bone_pose_rotation(idx)
			var rel_q: Quaternion = (rest_q.inverse() * pose_q).normalized()
			var e: Vector3 = rel_q.get_euler() * (180.0 / PI)
			lines.append("%-11s: (%+5.0f, %+5.0f, %+5.0f)" % [b_alias, e.x, e.y, e.z])
	return "\n".join(lines)


func _get_active_zenkai_clip_name() -> String:
	if _st_is_transforming:
		return "aura_burst_loop"
	if _st_is_guard_broken:
		return "guard_break"
	if _st_flinch_factor > 0.25:
		return "damage_heavy" if hit_flinch_intensity >= 0.8 else "damage_light"
	if _st_super_phase == 2:
		if _st_super_tech == "big_bang" or _st_super_tech == "genkidama":
			return "hissatsu2_fire"
		return "hissatsu1_fire"
	if _st_super_phase == 1:
		if _st_super_tech == "big_bang" or _st_super_tech == "genkidama":
			return "hissatsu2_charge"
		return "hissatsu1_charge"
	if _st_is_melee_active:
		match melee_anim_type:
			0: return "rush_1"
			1: return "rush_2"
			2: return "rush_3"
			3: return "rush_4"
			4: return "rush_5"
			_: return "heavy_smash"
	if _st_is_ki_blast:
		return "ki_blast_left" if ki_blast_hand == 0 else "ki_blast_right"
	if _st_is_blocking:
		return "guard_active"
	if _st_ki_phase > 0:
		return "ki_charge_loop"
	if _st_is_flying:
		return "dash_loop"
	if _st_is_launching_air:
		return "blow_spiral"
	if _st_is_getup:
		return "recover_kipup"
	return "idle_ground"


func _get_active_zenkai_clip_u() -> float:
	if _st_is_transforming:
		return _st_transform_u
	if _st_is_melee_active:
		return _st_melee_u
	if _st_is_ki_blast:
		return _st_ki_blast_u
	if _st_is_getup:
		return _st_getup_u
	if _st_flinch_factor > 0.25:
		return clampf(1.0 - (hit_flinch_timer / 0.35), 0.0, 1.0)
	var clip: String = _get_active_zenkai_clip_name()
	var dur: float = zenkai_anim_loader.get_clip_duration(clip, 0.85) if zenkai_anim_loader != null else 0.85
	return fmod(anim_time / maxf(dur, 0.15), 1.0)
