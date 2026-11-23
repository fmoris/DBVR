class_name DramaticDirector
extends Node3D

## DramaticDirector (Godot 4.8 VR - 90 FPS, Cero Cinetosis)
## Orquestador central de escenas dramáticas y escala destructiva:
## - Dramatic Intro (2.2s, saltable)
## - Transformación Dramática (luz, columna Ki, rocas levitando, repulsión, cabello NPC)
## - Momento de Determinación (comeback en Furia)
## - Atmósfera reactiva de Beam Clash + Cadena Crítica
## - Dramatic Finish (hit-stop, columna al cielo, cráter gigante, banner)
## - Pool fijo de 6 cráteres persistentes y 1 MultiMesh de 12 rocas levitando (1 draw call)

const DramaticMiniSceneClass = preload("res://scripts/DramaticMiniSceneController.gd")
const KiBeamShader = preload("res://shaders/ki_beam.gdshader")
const ShockwaveShader = preload("res://shaders/shockwave.gdshader")

static var active_instance: DramaticDirector = null
static var is_dramatic_pause_active: bool = false

# Cachés de escena y cámara (sin búsquedas repetidas en hot path)
var _dir_light: DirectionalLight3D = null
var _world_env: WorldEnvironment = null
var _player_char: Node3D = null
var _enemy_char: Node3D = null
var _cam: Camera3D = null
var _l_ctrl: XRController3D = null
var _r_ctrl: XRController3D = null

var _base_light_energy: float = 1.15
var _base_light_color: Color = Color(1.0, 0.96, 0.88)
var _base_ambient_energy: float = 1.0
var _base_bg_energy: float = 1.0
var _env_saved: bool = false

# Audio dedicado para eventos dramáticos
var _sfx_player: AudioStreamPlayer = null
var _voice_player: AudioStreamPlayer = null

# Subsistema de mini-escenas
var mini_scene_controller: Node3D = null

# Pools prealocados (Zero Allocations en combate VR 90 FPS)
const MAX_CRATERS: int = 6
var _crater_pool: Array[MeshInstance3D] = []
var _crater_cursor: int = 0

const ROCK_COUNT: int = 12
var _rock_multimesh: MultiMeshInstance3D = null
var _rock_angles: PackedFloat32Array = PackedFloat32Array()
var _rock_radii: PackedFloat32Array = PackedFloat32Array()
var _rock_heights: PackedFloat32Array = PackedFloat32Array()
var _rock_speeds: PackedFloat32Array = PackedFloat32Array()
var _levitation_active: bool = false
var _levitate_center: Vector3 = Vector3.ZERO
var _levitate_timer: float = 0.0

var _pillar_mesh: MeshInstance3D = null
var _pillar_mat: ShaderMaterial = null
var _cam_banner_anchor: Node3D = null
var _banner_label: Label3D = null
var _speed_lines_mesh: MeshInstance3D = null

# Estado de secuencias activas
var is_in_intro: bool = false
var _intro_timer: float = 0.0
var _atmos_restore_timer: float = 0.0
var _timescale_restore_timer: float = 0.0
var _banner_timer: float = 0.0
var _hitstop_active: bool = false
var _hitstop_timer: float = 0.0
var _is_finish_playing: bool = false
var _finish_elapsed: float = 0.0

# Caché de materiales originales de cabello por personaje NPC para restaurar en revert_to_base()
var _saved_hair_materials: Dictionary = {}


static func get_active(tree: SceneTree = null) -> DramaticDirector:
	if active_instance and is_instance_valid(active_instance) and active_instance.is_inside_tree():
		return active_instance
	if tree and tree.current_scene:
		var found: Node = tree.current_scene.find_child("DramaticDirector", true, false)
		if found is DramaticDirector:
			active_instance = found as DramaticDirector
			return active_instance
	return null


func set_dramatic_pause(active: bool) -> void:
	is_dramatic_pause_active = active


func _enter_tree() -> void:
	active_instance = self
	is_dramatic_pause_active = false


func _ready() -> void:
	active_instance = self
	_cache_scene_references()
	_build_audio_players()
	_build_pools()
	_build_camera_overlays()

	mini_scene_controller = DramaticMiniSceneClass.new()
	mini_scene_controller.name = "DramaticMiniSceneController"
	mini_scene_controller.director = self
	add_child(mini_scene_controller)

	# Iniciar Dramatic Intro en el primer arranque tras 0.25s para asegurar cámara XR asentada
	call_deferred("_start_deferred_intro")


func _exit_tree() -> void:
	is_dramatic_pause_active = false
	if Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	restore_atmosphere()
	if _cam_banner_anchor and is_instance_valid(_cam_banner_anchor):
		_cam_banner_anchor.queue_free()
	if _speed_lines_mesh and is_instance_valid(_speed_lines_mesh):
		_speed_lines_mesh.queue_free()
	if active_instance == self:
		active_instance = null


func _cache_scene_references() -> void:
	var scene: Node = get_tree().current_scene if get_tree() else null
	if not scene:
		return
	_dir_light = scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if _dir_light:
		_base_light_energy = _dir_light.light_energy
		_base_light_color = _dir_light.light_color
	_world_env = scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env and _world_env.environment:
		_base_ambient_energy = _world_env.environment.ambient_light_energy
		_base_bg_energy = _world_env.environment.background_energy_multiplier
		_env_saved = true

	var xr_orig: Node = scene.get_node_or_null("Player_XROrigin3D")
	if xr_orig:
		_cam = xr_orig.get_node_or_null("XRCamera3D") as Camera3D
		_l_ctrl = xr_orig.get_node_or_null("LeftHand") as XRController3D
		_r_ctrl = xr_orig.get_node_or_null("RightHand") as XRController3D
		_player_char = xr_orig.get_node_or_null("PlayerCharacterInstance") as Node3D
	_enemy_char = scene.get_node_or_null("EnemyCharacterInstance") as Node3D


func _build_audio_players() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "DramaticSFXPlayer"
	_sfx_player.volume_db = -1.5
	add_child(_sfx_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "DramaticVoicePlayer"
	_voice_player.volume_db = 0.0
	add_child(_voice_player)


func _build_pools() -> void:
	# 1. Pool de 6 cráteres persistentes (anillo oscuro con relieve limpio para Quest 3)
	var shared_crater_mesh := QuadMesh.new()
	shared_crater_mesh.size = Vector2(5.2, 5.2)

	var shared_crater_mat := StandardMaterial3D.new()
	shared_crater_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shared_crater_mat.albedo_color = Color(0.92, 0.84, 0.72, 0.92)
	shared_crater_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shared_crater_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var z_crater_tex: Texture2D = ZenkaiVFXManager.get_tex("crater_cracks")
	if z_crater_tex != null:
		shared_crater_mat.albedo_texture = z_crater_tex

	_crater_pool.clear()
	for i in range(MAX_CRATERS):
		var cr := MeshInstance3D.new()
		cr.name = "DramaticCrater_%d" % i
		cr.mesh = shared_crater_mesh
		cr.rotation_degrees.x = -90.0
		cr.material_override = shared_crater_mat
		cr.visible = false
		add_child(cr)
		_crater_pool.append(cr)

	# 2. MultiMesh único para 12 rocas levitando (1 draw call)
	_rock_multimesh = MultiMeshInstance3D.new()
	_rock_multimesh.name = "DramaticFloatingRocks"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = ROCK_COUNT
	var rock_box := BoxMesh.new()
	rock_box.size = Vector3(0.22, 0.16, 0.19)
	mm.mesh = rock_box
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.36, 0.28, 0.22)
	rock_mat.roughness = 0.95
	mm.mesh.surface_set_material(0, rock_mat)
	_rock_multimesh.multimesh = mm
	_rock_multimesh.visible = false
	add_child(_rock_multimesh)

	_rock_angles.resize(ROCK_COUNT)
	_rock_radii.resize(ROCK_COUNT)
	_rock_heights.resize(ROCK_COUNT)
	_rock_speeds.resize(ROCK_COUNT)
	for i in range(ROCK_COUNT):
		_rock_angles[i] = float(i) * (TAU / float(ROCK_COUNT))
		_rock_radii[i] = randf_range(1.3, 3.4)
		_rock_heights[i] = randf_range(0.15, 2.2)
		_rock_speeds[i] = randf_range(0.8, 2.1)

	# 3. Pilar vertical de luz reutilizable (Transformación / Dramatic Finish)
	_pillar_mesh = MeshInstance3D.new()
	_pillar_mesh.name = "DramaticEnergyPillar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.9
	cyl.height = 42.0
	cyl.radial_segments = 16
	_pillar_mesh.mesh = cyl
	_pillar_mat = ShaderMaterial.new()
	_pillar_mat.shader = KiBeamShader
	_pillar_mat.set_shader_parameter("beam_color", Color(1.0, 0.85, 0.15, 0.9))
	_pillar_mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 0.95))
	_pillar_mat.set_shader_parameter("flow_speed", 12.0)
	_pillar_mat.set_shader_parameter("core_intensity", 3.2)
	_pillar_mesh.material_override = _pillar_mat
	_pillar_mesh.visible = false
	add_child(_pillar_mesh)


func _build_camera_overlays() -> void:
	if not _cam and get_viewport():
		_cam = get_viewport().get_camera_3d()
	if not _cam or not is_instance_valid(_cam):
		return

	if not _cam_banner_anchor or not is_instance_valid(_cam_banner_anchor):
		_cam_banner_anchor = Node3D.new()
		_cam_banner_anchor.name = "DramaticBannerAnchor"
		_cam_banner_anchor.position = Vector3(0.0, 0.25, -1.25)
		_cam.add_child(_cam_banner_anchor)

		_banner_label = Label3D.new()
		_banner_label.font_size = 26
		_banner_label.pixel_size = 0.0014
		_banner_label.no_depth_test = true
		_banner_label.render_priority = 124
		_banner_label.outline_size = 10
		_banner_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
		_banner_label.visible = false
		_cam_banner_anchor.add_child(_banner_label)

	if not _speed_lines_mesh or not is_instance_valid(_speed_lines_mesh):
		_speed_lines_mesh = MeshInstance3D.new()
		_speed_lines_mesh.name = "DramaticSpeedLinesCone"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.6
		cyl.bottom_radius = 1.6
		cyl.height = 1.8
		cyl.radial_segments = 18
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		_speed_lines_mesh.mesh = cyl
		_speed_lines_mesh.rotation.x = PI * 0.5
		_speed_lines_mesh.position = Vector3(0.0, 0.0, -0.70)
		var mat := ShaderMaterial.new()
		mat.shader = KiBeamShader
		mat.set_shader_parameter("beam_color", Color(0.85, 0.95, 1.0, 0.22))
		mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 0.10))
		mat.set_shader_parameter("flow_speed", 24.0)
		mat.set_shader_parameter("core_intensity", 1.2)
		mat.set_shader_parameter("beam_frequency", 20.0)
		_speed_lines_mesh.material_override = mat
		_speed_lines_mesh.visible = false
		_cam.add_child(_speed_lines_mesh)


func _start_deferred_intro() -> void:
	_cache_scene_references()
	_build_camera_overlays()
	if not is_inside_tree():
		return
	play_dramatic_intro()


func reset_for_new_match() -> void:
	_is_finish_playing = false
	_finish_elapsed = 0.0
	is_in_intro = false
	is_dramatic_pause_active = false
	_hitstop_active = false
	_hitstop_timer = 0.0
	_atmos_restore_timer = 0.0
	_timescale_restore_timer = 0.0
	_levitation_active = false
	_saved_hair_materials.clear()
	Engine.time_scale = 1.0
	restore_atmosphere()
	if _rock_multimesh:
		_rock_multimesh.visible = false
	if _pillar_mesh:
		_pillar_mesh.visible = false
	if _speed_lines_mesh:
		_speed_lines_mesh.visible = false
	for cr in _crater_pool:
		if cr and is_instance_valid(cr):
			cr.visible = false
	if mini_scene_controller:
		mini_scene_controller.reset_match_state()


func _process(delta: float) -> void:
	var real_delta: float = minf(delta / maxf(Engine.time_scale, 0.01), 0.05)

	if is_in_intro:
		_intro_timer -= real_delta
		if _intro_timer <= 0.0:
			skip_dramatic_intro()
		return

	if _hitstop_active:
		_hitstop_timer -= real_delta
		if _hitstop_timer <= 0.0:
			_hitstop_active = false
			if _is_finish_playing:
				Engine.time_scale = 0.45
			elif not is_dramatic_pause_active:
				Engine.time_scale = 1.0

	if _is_finish_playing:
		_finish_elapsed += real_delta
		if _finish_elapsed >= 1.35 and Engine.time_scale < 1.0 and not _hitstop_active:
			Engine.time_scale = 1.0
		if _finish_elapsed >= 3.20:
			_is_finish_playing = false
			Engine.time_scale = 1.0
			restore_atmosphere()

	if _timescale_restore_timer > 0.0:
		_timescale_restore_timer -= real_delta
		if _timescale_restore_timer <= 0.0 and not _hitstop_active and not is_dramatic_pause_active and not _is_finish_playing:
			Engine.time_scale = 1.0

	if _atmos_restore_timer > 0.0:
		_atmos_restore_timer -= real_delta
		if _atmos_restore_timer <= 0.0:
			restore_atmosphere()

	if _banner_timer > 0.0:
		_banner_timer -= real_delta
		if _banner_timer <= 0.0 and _banner_label and is_instance_valid(_banner_label):
			_banner_label.visible = false

	if _levitation_active and _rock_multimesh and _rock_multimesh.visible:
		_levitate_timer += real_delta
		_update_levitating_rocks(real_delta)

	if not _is_finish_playing and mini_scene_controller:
		mini_scene_controller.tick_controller(delta, _player_char, _enemy_char)


func _update_levitating_rocks(_real_delta: float) -> void:
	var mm: MultiMesh = _rock_multimesh.multimesh
	if not mm:
		return
	for i in range(ROCK_COUNT):
		var ang: float = _rock_angles[i] + _levitate_timer * _rock_speeds[i] * 0.7
		var r: float = _rock_radii[i]
		var bob_y: float = _rock_heights[i] + sin(_levitate_timer * _rock_speeds[i] + float(i)) * 0.45
		var pos := Vector3(_levitate_center.x + cos(ang) * r, maxf(0.25, _levitate_center.y + bob_y), _levitate_center.z + sin(ang) * r)
		var rot_b := Basis.from_euler(Vector3(_levitate_timer * 1.4 + float(i), ang, _levitate_timer * 0.9))
		mm.set_instance_transform(i, Transform3D(rot_b, pos))


## Muestra un banner diegético anclado a la cámara sin mover el visor
func show_camera_banner(text_val: String, color: Color, duration_sec: float) -> void:
	if not _banner_label or not is_instance_valid(_banner_label):
		_build_camera_overlays()
	if _banner_label and is_instance_valid(_banner_label):
		_banner_label.text = text_val
		_banner_label.modulate = color
		_banner_label.visible = true
		_banner_timer = duration_sec


func _set_atmosphere(tint_color: Color, light_mult: float, env_mult: float, duration_sec: float = -1.0) -> void:
	if _dir_light and is_instance_valid(_dir_light):
		_dir_light.light_energy = _base_light_energy * light_mult
		_dir_light.light_color = _base_light_color.lerp(tint_color, 0.65)
	if _world_env and is_instance_valid(_world_env) and _world_env.environment and _env_saved:
		_world_env.environment.ambient_light_energy = _base_ambient_energy * env_mult
		_world_env.environment.background_energy_multiplier = _base_bg_energy * env_mult
	if duration_sec > 0.0:
		_atmos_restore_timer = duration_sec


func restore_atmosphere() -> void:
	if _dir_light and is_instance_valid(_dir_light):
		_dir_light.light_energy = _base_light_energy
		_dir_light.light_color = _base_light_color
	if _world_env and is_instance_valid(_world_env) and _world_env.environment and _env_saved:
		_world_env.environment.ambient_light_energy = _base_ambient_energy
		_world_env.environment.background_energy_multiplier = _base_bg_energy
	_levitation_active = false
	if _rock_multimesh and is_instance_valid(_rock_multimesh):
		_rock_multimesh.visible = false
	if _pillar_mesh and is_instance_valid(_pillar_mesh):
		_pillar_mesh.visible = false
	if _speed_lines_mesh and is_instance_valid(_speed_lines_mesh):
		_speed_lines_mesh.visible = false


func begin_miniscene_atmosphere(target: Node3D, col: Color) -> void:
	_set_atmosphere(col, 0.45, 0.62, -1.0)
	if target and is_instance_valid(target):
		_levitate_center = target.global_position
		_levitation_active = true
		if _rock_multimesh:
			_rock_multimesh.visible = true
	if _speed_lines_mesh:
		_speed_lines_mesh.visible = true


# ==============================================================================
# 1. DRAMATIC INTRO (Careo Saiyan, 2.2s, saltable)
# ==============================================================================
func play_dramatic_intro() -> void:
	if is_in_intro:
		return
	is_in_intro = true
	is_dramatic_pause_active = true
	_intro_timer = 2.2

	var p_name: String = "VEGETA"
	var e_name: String = "GOKU"
	if _player_char and _player_char.get("character_data"):
		p_name = String(_player_char.character_data.character_name).to_upper()
	if _enemy_char and _enemy_char.get("character_data"):
		e_name = String(_enemy_char.character_data.character_name).to_upper()

	show_camera_banner("⚡ CELL GAMES — %s vs %s ⚡\n¡ELEVA TU KI!" % [p_name, e_name], Color(1.0, 0.88, 0.25), 2.0)
	play_dramatic_sfx("dramatic.intro_fanfare", "common.aura_burst")
	if _enemy_char and is_instance_valid(_enemy_char):
		play_character_dramatic_voice(_enemy_char, "dramatic_intro", "intro_taunt")


func skip_dramatic_intro() -> void:
	if not is_in_intro:
		return
	is_in_intro = false
	is_dramatic_pause_active = false
	show_camera_banner("⚔️ ¡COMBATE! ⚔️", Color(1.0, 0.95, 0.3), 0.85)


# ==============================================================================
# 2. TRANSFORMACIÓN DRAMÁTICA
# ==============================================================================
func play_dramatic_transformation(fighter: Node3D, trans: Resource) -> void:
	if not fighter or not is_instance_valid(fighter) or not trans:
		return

	var aura_col: Color = trans.aura_color if "aura_color" in trans else Color(1.0, 0.85, 0.15)
	var f_name: String = String(trans.form_name).to_upper() if "form_name" in trans else "SUPER SAIYAN"
	var pos: Vector3 = fighter.get_parent().global_position if (bool(fighter.get("is_player")) and fighter.get_parent() is Node3D) else fighter.global_position

	_set_atmosphere(aura_col, 0.48, 0.65, 1.35)
	_levitate_center = pos
	_levitation_active = true
	if _rock_multimesh:
		_rock_multimesh.visible = true

	if _pillar_mesh and _pillar_mat:
		_pillar_mat.set_shader_parameter("beam_color", Color(aura_col.r, aura_col.g, aura_col.b, 0.9))
		_pillar_mesh.global_position = Vector3(pos.x, pos.y + 18.0, pos.z)
		_pillar_mesh.scale = Vector3(0.85, 1.0, 0.85)
		_pillar_mesh.visible = true

	_spawn_shockwave_ring(pos + Vector3(0.0, 0.25, 0.0), aura_col, 4.5, 0.55)
	_spawn_shockwave_ring(pos + Vector3(0.0, 0.90, 0.0), aura_col.lightened(0.25), 3.4, 0.45)

	# Repulsión por presión de aura si el rival está a < 5.0m (sin daño directo)
	var opp: Node3D = _enemy_char if fighter == _player_char else _player_char
	if opp and is_instance_valid(opp):
		var opp_pos: Vector3 = opp.get_parent().global_position if (bool(opp.get("is_player")) and opp.get_parent() is Node3D) else opp.global_position
		if pos.distance_to(opp_pos) < 5.0 and opp.has_method("apply_knockback"):
			var push_dir: Vector3 = (opp_pos - pos).normalized()
			if push_dir.length_squared() < 0.01:
				push_dir = Vector3.BACK
			opp.apply_knockback(push_dir, 8.5)

	# Tintar cabello del rival NPC acorde a la transformación
	if not bool(fighter.get("is_player")):
		_apply_npc_hair_tint(fighter, aura_col)

	# Micro slow-mo cinematográfico seguro (0.45s reales)
	if not is_dramatic_pause_active and not _is_finish_playing:
		Engine.time_scale = 0.40
		_timescale_restore_timer = 0.45

	play_dramatic_sfx("dramatic.transform_buildup", "common.aura_burst")
	var c_data: Variant = fighter.get("character_data")
	var char_lbl: String = String(c_data.character_name).to_upper() if (c_data and "character_name" in c_data) else "SAIYAN"
	show_camera_banner("⚡ ¡%s DESPIERTA %s! ⚡" % [char_lbl, f_name], aura_col.lightened(0.2), 1.45)


func _apply_npc_hair_tint(fighter: Node3D, col: Color) -> void:
	var id_key: int = fighter.get_instance_id()
	if not _saved_hair_materials.has(id_key):
		_saved_hair_materials[id_key] = {}
	var store: Dictionary = _saved_hair_materials[id_key]
	_tint_hair_recursive(fighter, col, store)


func _tint_hair_recursive(node: Node, col: Color, store: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var low_name: String = mi.name.to_lower()
		if "hair" in low_name or "pelo" in low_name or "cabello" in low_name:
			var mi_id: int = mi.get_instance_id()
			if not store.has(mi_id):
				store[mi_id] = [mi, mi.material_override]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col.lightened(0.25)
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 0.55
			mi.material_override = mat
	for ch in node.get_children():
		_tint_hair_recursive(ch, col, store)


func restore_npc_hair_tint(fighter: Node3D) -> void:
	if not fighter or not is_instance_valid(fighter):
		return
	var id_key: int = fighter.get_instance_id()
	if not _saved_hair_materials.has(id_key):
		return
	var store: Dictionary = _saved_hair_materials[id_key]
	for entry in store.values():
		if entry is Array and entry.size() >= 2:
			var mi: MeshInstance3D = entry[0] as MeshInstance3D
			if mi and is_instance_valid(mi):
				mi.material_override = entry[1]
	_saved_hair_materials.erase(id_key)


# ==============================================================================
# 3. MOMENTO DE DETERMINACIÓN
# ==============================================================================
func update_determination_vfx(fighter: Node3D, progress_ratio: float, active: bool) -> void:
	if not active:
		restore_atmosphere()
		if _banner_label and _banner_label.visible and "DETERMINACI" in _banner_label.text:
			_banner_label.visible = false
		return

	var pos: Vector3 = fighter.get_parent().global_position if (bool(fighter.get("is_player")) and fighter.get_parent() is Node3D) else fighter.global_position
	_set_atmosphere(Color(1.0, 0.22, 0.12), 0.55, 0.68, -1.0)
	_levitate_center = pos
	_levitation_active = true
	if _rock_multimesh:
		_rock_multimesh.visible = true

	var pct: int = int(clampf(progress_ratio, 0.0, 1.0) * 100.0)
	show_camera_banner("🔥 DETERMINACIÓN: %d%% — ¡RESISTE! 🔥" % pct, Color(1.0, 0.42, 0.15), 0.25)
	if progress_ratio <= 0.08:
		play_dramatic_sfx("dramatic.determination_charge", "common.ki_charge_phase2")


func play_determination_burst(fighter: Node3D) -> void:
	var pos: Vector3 = fighter.get_parent().global_position if (bool(fighter.get("is_player")) and fighter.get_parent() is Node3D) else fighter.global_position
	_spawn_shockwave_ring(pos + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.32, 0.10, 0.95), 6.0, 0.55)
	restore_atmosphere()
	play_dramatic_sfx("dramatic.determination_burst", "common.furia_activate")
	show_camera_banner("🔥 ¡DETERMINACIÓN COMPLETA! +45 KI & ZENKAI 🔥", Color(1.0, 0.85, 0.2), 1.8)


# ==============================================================================
# 4. CLÍMAX BEAM CLASH + CRÁTERES + DRAMATIC FINISH
# ==============================================================================
func update_beam_clash_atmosphere(clash_ratio: float, color_atk: Color, color_def: Color, clash_pos: Vector3, active: bool) -> void:
	if not active:
		restore_atmosphere()
		return
	var dom_col: Color = color_atk.lerp(color_def, clampf(clash_ratio, 0.0, 1.0))
	_set_atmosphere(dom_col, 0.42, 0.58, -1.0)
	_levitate_center = clash_pos
	_levitation_active = true
	if _rock_multimesh:
		_rock_multimesh.visible = true
	if _speed_lines_mesh:
		_speed_lines_mesh.visible = true


func on_beam_clash_resolved(clash_pos: Vector3) -> void:
	restore_atmosphere()
	spawn_persistent_crater(clash_pos, 1.35, true)


func play_dramatic_finish(winner: Node3D, loser: Node3D, tech_name: String) -> float:
	_is_finish_playing = true
	_finish_elapsed = 0.0
	Engine.time_scale = 0.06
	_hitstop_active = true
	_hitstop_timer = 0.18

	var col: Color = Color(1.0, 0.85, 0.2)
	var w_data: Variant = winner.get("character_data") if (winner and is_instance_valid(winner)) else null
	if w_data and "character_name" in w_data and "VEGETA" in String(w_data.character_name).to_upper():
		col = Color(0.92, 0.72, 0.18)

	var impact_pos: Vector3 = loser.global_position if (loser and is_instance_valid(loser)) else Vector3.ZERO
	_set_atmosphere(col, 0.30, 0.45, -1.0)

	if _pillar_mesh and _pillar_mat:
		_pillar_mat.set_shader_parameter("beam_color", Color(col.r, col.g, col.b, 0.98))
		_pillar_mesh.global_position = Vector3(impact_pos.x, impact_pos.y + 20.0, impact_pos.z)
		_pillar_mesh.scale = Vector3(2.2, 1.2, 2.2)
		_pillar_mesh.visible = true

	if _speed_lines_mesh:
		_speed_lines_mesh.visible = true

	_spawn_shockwave_ring(impact_pos + Vector3(0.0, 0.4, 0.0), col, 8.5, 0.85)
	_spawn_shockwave_ring(impact_pos + Vector3(0.0, 1.5, 0.0), Color(1.0, 1.0, 1.0, 0.95), 7.0, 0.70)
	spawn_persistent_crater(impact_pos, 1.80, false)

	play_dramatic_sfx("dramatic.finish_impact", "common.ko_finisher")
	if winner and is_instance_valid(winner):
		play_character_dramatic_voice(winner, "dramatic_finish", "victory")

	var w_name: String = String(w_data.character_name).to_upper() if (w_data and "character_name" in w_data) else "GANADOR"
	show_camera_banner("★ DRAMATIC FINISH ★\n%s — %s" % [w_name, tech_name.to_upper()], Color(1.0, 0.90, 0.22), 3.1)
	return 3.2


func spawn_persistent_crater(world_pos: Vector3, scale_mult: float = 1.0, play_sfx: bool = true) -> void:
	if _crater_pool.is_empty():
		return
	var ground_y: float = 0.05
	if _player_char and is_instance_valid(_player_char) and _player_char.has_method("get_ground_elevation"):
		ground_y = _player_char.get_ground_elevation(world_pos) + 0.04

	var cr: MeshInstance3D = _crater_pool[_crater_cursor]
	_crater_cursor = (_crater_cursor + 1) % MAX_CRATERS
	if cr and is_instance_valid(cr):
		cr.global_position = Vector3(world_pos.x, ground_y, world_pos.z)
		cr.rotation.y = randf() * TAU
		cr.scale = Vector3(scale_mult, 1.0, scale_mult)
		cr.visible = true

	if play_sfx:
		play_dramatic_sfx("dramatic.crater_impact", "common.melee_hit_heavy")


func play_environment_impact_hitstop(world_pos: Vector3) -> void:
	if not is_dramatic_pause_active and not _is_finish_playing:
		Engine.time_scale = 0.25
		_hitstop_active = true
		_hitstop_timer = 0.08
	_spawn_shockwave_ring(world_pos, Color(1.0, 0.72, 0.25, 0.9), 2.8, 0.35)
	play_dramatic_sfx("dramatic.crater_impact", "common.melee_hit_heavy")


func _spawn_shockwave_ring(world_pos: Vector3, col: Color, end_scale: float, dur: float) -> void:
	var sw := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	sw.mesh = quad
	sw.rotation.x = -PI * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = ShockwaveShader
	mat.set_shader_parameter("ring_color", col)
	sw.material_override = mat
	add_child(sw)
	sw.global_position = world_pos
	var tw: Tween = sw.create_tween()
	tw.tween_property(sw, "scale", Vector3.ONE * end_scale, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/ring_color:a", 0.0, dur)
	tw.tween_callback(sw.queue_free)


func play_dramatic_sfx(primary_id: String, fallback_id: String = "") -> void:
	if not _sfx_player or not is_instance_valid(_sfx_player):
		return
	var act: String = primary_id
	if not AudioActionManager.has_action_sounds(act) and fallback_id != "":
		act = fallback_id
	if AudioActionManager.has_action_sounds(act):
		AudioActionManager.play_action(act, _sfx_player)


func play_character_dramatic_voice(fighter: Node3D, suffix: String, fallback_suffix: String = "") -> void:
	if not _voice_player or not is_instance_valid(_voice_player) or not fighter or not is_instance_valid(fighter):
		return
	var c_data: Variant = fighter.get("character_data")
	var c_name: String = String(c_data.character_name) if (c_data and "character_name" in c_data) else "Goku"
	var act: String = AudioActionManager.get_character_action_id(c_name, suffix)
	if not AudioActionManager.has_action_sounds(act) and fallback_suffix != "":
		act = AudioActionManager.get_character_action_id(c_name, fallback_suffix)
	if AudioActionManager.has_action_sounds(act):
		AudioActionManager.play_action(act, _voice_player)
