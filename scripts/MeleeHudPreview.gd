extends Node3D
class_name MeleeHudPreview

## Vista interactiva de escritorio para comparar 3 alternativas de HUD Melee VR
## usando texturas oficiales de DBZ Zenkai (res://assets/ui_zenkai/), mezclando
## elementos [FIJO] al combate y seguimiento suave de [CABEZA].

enum HudAlt {
	TACTICAL_FLANKS = 0,
	SCOUTER_DUAL_ARC = 1,
	ANIME_CINEMA = 2
}

enum Scenario {
	ATTACK = 0,
	DEFENSE = 1,
	SIMULTANEOUS = 2,
	LORE_EVENT = 3
}

const ZONE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.20, 0.0),
	Vector3(0.0, -0.01, 0.0),
	Vector3(-0.19, 0.17, 0.0),
	Vector3(0.19, 0.17, 0.0),
	Vector3(-0.19, -0.15, 0.0),
	Vector3(0.19, -0.15, 0.0)
]

const UI_PATH: String = "res://assets/ui_zenkai/"

var _active_alt: int = HudAlt.TACTICAL_FLANKS
var _active_scenario: int = Scenario.DEFENSE
var _auto_sweep: bool = false
var _show_anchor_tags: bool = true

var _head_pivot: Node3D = null
var _camera: Camera3D = null
var _head_yaw: float = 0.0
var _head_pitch: float = -0.03
var _sweep_phase: float = 0.0
var _dragging: bool = false

var _world_hud_root: Node3D = null
var _head_hud_root: Node3D = null
var _opponent: Node3D = null

var _zones: Array[Dictionary] = []
var _lore_orb: MeshInstance3D = null
var _lore_orb_mat: StandardMaterial3D = null

var _alt_world_roots: Array[Node3D] = []
var _alt_head_roots: Array[Node3D] = []
var _tag_labels: Array[Label3D] = []
var _tex_cache: Dictionary = {}

# Referencias animables compartidas (cero alocaciones en _process)
var _alt1_p_ki_fill: MeshInstance3D = null
var _alt1_e_ki_fill: MeshInstance3D = null
var _alt1_timer_fill: MeshInstance3D = null
var _alt1_role_lbl: Label3D = null
var _alt1_p_ki_lbl: Label3D = null
var _alt1_e_ki_lbl: Label3D = null
var _alt1_pips_lbl: Label3D = null
var _alt1_round_lbl: Label3D = null
var _alt1_threat_mat: StandardMaterial3D = null
var _alt1_threat_name: Label3D = null
var _alt1_counter_lbl: Label3D = null
var _alt1_flash_lbl: Label3D = null
var _alt1_border_r: StandardMaterial3D = null

var _alt2_p_ki_fill: MeshInstance3D = null
var _alt2_e_ki_fill: MeshInstance3D = null
var _alt2_timer_fill: MeshInstance3D = null
var _alt2_p_ki_val: Label3D = null
var _alt2_e_ki_val: Label3D = null
var _alt2_pips_lbl: Label3D = null
var _alt2_threat_mat: StandardMaterial3D = null
var _alt2_threat_sub: Label3D = null
var _alt2_scouter_role: Label3D = null
var _alt2_scouter_bp: Label3D = null
var _alt2_scouter_flash: Label3D = null

var _alt3_p_ki_fill: MeshInstance3D = null
var _alt3_e_ki_fill: MeshInstance3D = null
var _alt3_timer_fill: MeshInstance3D = null
var _alt3_pips_lbl: Label3D = null
var _alt3_ki_num_l: Label3D = null
var _alt3_ki_num_r: Label3D = null
var _alt3_stamp_lbl: Label3D = null
var _alt3_stamp_mat: StandardMaterial3D = null
var _alt3_callout_root: Node3D = null
var _alt3_flash_lbl: Label3D = null

var _alt_buttons: Array[Button] = []
var _scen_buttons: Array[Button] = []
var _sweep_btn: Button = null
var _tags_btn: Button = null
var _desc_label: Label = null

var _ring_phase: float = 0.0
var _flash_timer: float = 0.0
var _flash_cycle_idx: int = 0
var _player_ki_sim: float = 74.0
var _enemy_ki_sim: float = 42.0


func _ready() -> void:
	_preload_zenkai_ui_textures()
	_build_environment()
	_build_head_rig()
	_spawn_opponent_backdrop()
	_build_spatial_anchors_and_zones()
	_build_alt1_tactical_flanks()
	_build_alt2_scouter_dual_arc()
	_build_alt3_anime_cinema()
	_build_desktop_ui()
	_select_alternative(HudAlt.TACTICAL_FLANKS)
	_select_scenario(Scenario.DEFENSE)


func _preload_zenkai_ui_textures() -> void:
	var names: Array[String] = [
		"target_fight.png", "target_normal.png",
		"scouter_radar.png", "radar_map.png",
		"indicator_base.png", "indicator_active.png",
		"icon_fist.png", "icon_burst.png", "icon_up.png", "icon_down.png",
		"finisher_lv0.png", "finisher_lv1.png", "finisher_lv2.png",
		"alert_base_y.png", "alert_base_b.png", "alert_base_g.png", "alert_base_r.png",
		"alert_arrow_y.png", "alert_arrow_b.png", "alert_arrow_g.png", "alert_arrow_r.png",
		"info_obi.png", "alert_chara_goku.png",
		"chara_chip_goku.png", "chara_chip_vegeta.png"
	]
	for fn in names:
		var path: String = UI_PATH + fn
		if ResourceLoader.exists(path):
			_tex_cache[fn] = ResourceLoader.load(path) as Texture2D


func _get_ui_tex(fn: String) -> Texture2D:
	return _tex_cache.get(fn, null) as Texture2D


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.09, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.92)
	env.ambient_light_energy = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.18
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 28.0, 0.0)
	sun.light_energy = 1.35
	add_child(sun)

	var arena := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(24.0, 0.4, 24.0)
	arena.mesh = box
	arena.position = Vector3(0.0, -0.2, -3.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.28, 0.25)
	mat.roughness = 0.88
	arena.material_override = mat
	add_child(arena)


func _build_head_rig() -> void:
	_head_pivot = Node3D.new()
	_head_pivot.name = "SimulatedVRHead"
	_head_pivot.position = Vector3(0.0, 1.54, 0.0)
	add_child(_head_pivot)

	_camera = Camera3D.new()
	_camera.fov = 92.0
	_camera.near = 0.05
	_camera.current = true
	_head_pivot.add_child(_camera)
	_apply_head_rotation()


func _apply_head_rotation() -> void:
	if _head_pivot:
		_head_pivot.rotation = Vector3(_head_pitch, _head_yaw, 0.0)


func _spawn_opponent_backdrop() -> void:
	var goku_res: Resource = ResourceLoader.load("res://resources/goku_zenkai.tres")
	if goku_res != null:
		var opp := CharacterInstance.new()
		opp.name = "PreviewOpponent"
		opp.is_player = false
		opp.character_data = goku_res as CharacterData
		add_child(opp)
		opp.global_position = Vector3(0.0, 0.0, -1.32)
		opp.rotation_degrees = Vector3.ZERO
		opp.set_physics_process(false)
		opp.set_process(false)
		for ch in opp.get_children():
			if ch.name.contains("AI") or ch is CombatAIController:
				ch.set_process(false)
				ch.set_physics_process(false)
				ch.queue_free()
		_opponent = opp
		return

	var fallback := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.26
	cap.height = 1.68
	fallback.mesh = cap
	fallback.position = Vector3(0.0, 0.84, -1.32)
	add_child(fallback)
	_opponent = fallback


func _build_spatial_anchors_and_zones() -> void:
	_world_hud_root = Node3D.new()
	_world_hud_root.name = "WorldFixedMeleeAnchor"
	_world_hud_root.position = Vector3(0.0, 1.38, -0.56)
	add_child(_world_hud_root)

	_head_hud_root = Node3D.new()
	_head_hud_root.name = "HeadLazyFollowAnchor"
	_head_hud_root.global_transform = _head_pivot.global_transform
	add_child(_head_hud_root)

	# 6 zonas con retículas oficiales target_fight / target_normal de DBZ Zenkai
	for i in range(ZONE_OFFSETS.size()):
		var z_node := Node3D.new()
		z_node.position = ZONE_OFFSETS[i]
		_world_hud_root.add_child(z_node)

		var reticle_res: Dictionary = _make_tex_quad(z_node, Vector2(0.15, 0.15), "target_fight.png" if i == 1 else "target_normal.png", Color.WHITE, Vector3(0.0, 0.0, 0.002), 112)
		var ring_m: MeshInstance3D = reticle_res["mesh"] as MeshInstance3D
		var r_mat: StandardMaterial3D = reticle_res["mat"] as StandardMaterial3D

		var box_m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, 0.10, 0.010)
		box_m.mesh = bm
		var b_mat := StandardMaterial3D.new()
		b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		b_mat.albedo_color = Color(0.18, 0.78, 1.0, 0.16)
		box_m.material_override = b_mat
		z_node.add_child(box_m)

		var z_lbl := Label3D.new()
		z_lbl.text = "🔥" if i == 1 else "·"
		z_lbl.font_size = 30
		z_lbl.pixel_size = 0.0014
		z_lbl.no_depth_test = true
		z_lbl.render_priority = 115
		z_lbl.outline_size = 6
		z_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		z_lbl.position = Vector3(0.0, 0.0, 0.015)
		z_node.add_child(z_lbl)

		_zones.append({
			"node": z_node,
			"ring": ring_m,
			"ring_mat": r_mat,
			"box": box_m,
			"box_mat": b_mat,
			"icon": z_lbl
		})

	_lore_orb = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	_lore_orb.mesh = sph
	_lore_orb.position = Vector3(0.0, 0.02, 0.0)
	_lore_orb_mat = StandardMaterial3D.new()
	_lore_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lore_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lore_orb_mat.albedo_color = Color(0.35, 0.94, 1.0, 0.72)
	_lore_orb.material_override = _lore_orb_mat
	_lore_orb.visible = false
	_world_hud_root.add_child(_lore_orb)


func _make_tex_quad(parent: Node3D, size: Vector2, tex_name: String, tint: Color, pos: Vector3, prio: int = 114) -> Dictionary:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = prio
	mat.albedo_color = tint
	var tex: Texture2D = _get_ui_tex(tex_name)
	if tex:
		mat.albedo_texture = tex
	mi.material_override = mat
	parent.add_child(mi)
	return { "mesh": mi, "mat": mat }


func _make_panel(parent: Node3D, size: Vector2, bg_col: Color, border_col: Color, prio: int = 110) -> Dictionary:
	var holder := Node3D.new()
	parent.add_child(holder)

	var border := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = size + Vector2(0.014, 0.014)
	border.mesh = bq
	var b_mat := StandardMaterial3D.new()
	b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.no_depth_test = true
	b_mat.render_priority = prio
	b_mat.albedo_color = border_col
	border.material_override = b_mat
	holder.add_child(border)

	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	bg.mesh = q
	bg.position = Vector3(0.0, 0.0, 0.001)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = prio + 1
	bg_mat.albedo_color = bg_col
	bg.material_override = bg_mat
	holder.add_child(bg)

	return { "root": holder, "border_mat": b_mat, "bg_mat": bg_mat }


func _make_bar_fill(parent: Node3D, size: Vector3, col: Color, prio: int = 114) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = prio
	mat.albedo_color = col
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	return mesh_inst


func _make_label(parent: Node3D, txt: String, font_sz: int, col: Color, pos: Vector3, align: int = HORIZONTAL_ALIGNMENT_CENTER, prio: int = 118) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = font_sz
	lbl.pixel_size = 0.0012
	lbl.modulate = col
	lbl.outline_size = 7
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	lbl.no_depth_test = true
	lbl.render_priority = prio
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos
	parent.add_child(lbl)
	return lbl


func _add_anchor_tag(parent: Node3D, is_head: bool, pos: Vector3) -> void:
	var lbl := _make_label(
		parent,
		"[CABEZA]" if is_head else "[FIJO]",
		13,
		Color(1.0, 0.86, 0.25, 0.95) if is_head else Color(0.35, 1.0, 0.65, 0.95),
		pos,
		HORIZONTAL_ALIGNMENT_CENTER,
		124
	)
	lbl.visible = _show_anchor_tags
	_tag_labels.append(lbl)


# ==============================================================================
# ALTERNATIVA 1: FLANCOS TÁCTICOS (ZENKAI HÍBRIDO)
# Izq FIJO: Alertas triangulares oficiales + Lv.2 | Der FIJO: Target/Icono Zenkai
# Arriba CABEZA: Retratos CharaChip + Barras Ki + Cinta info_obi en Flash
# ==============================================================================
func _build_alt1_tactical_flanks() -> void:
	var w_root := Node3D.new()
	_world_hud_root.add_child(w_root)
	var h_root := Node3D.new()
	_head_hud_root.add_child(h_root)
	_alt_world_roots.append(w_root)
	_alt_head_roots.append(h_root)

	# FIJO IZQUIERDA: Triángulos oficiales Zenkai + Pips + badge Lv.2
	var p_left: Dictionary = _make_panel(w_root, Vector2(0.15, 0.36), Color(0.03, 0.06, 0.11, 0.84), Color(0.22, 0.88, 1.0, 0.88))
	var left_r: Node3D = p_left["root"] as Node3D
	left_r.position = Vector3(-0.44, 0.02, 0.03)
	left_r.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	_make_tex_quad(left_r, Vector2(0.075, 0.038), "finisher_lv2.png", Color.WHITE, Vector3(0.0, 0.145, 0.003), 115)
	var alert_texs: Array[String] = ["alert_base_g.png", "alert_base_r.png", "alert_base_y.png", "alert_base_b.png"]
	for i in range(4):
		_make_tex_quad(left_r, Vector2(0.040, 0.065), alert_texs[i], Color(1.0, 1.0, 1.0, 0.85 if i < 3 else 0.30), Vector3(-0.032, 0.078 - float(i) * 0.060, 0.003), 114)
	_alt1_pips_lbl = _make_label(left_r, "🛡\n💥\n⚡\n○", 28, Color.WHITE, Vector3(0.025, -0.012, 0.004))
	_alt1_round_lbl = _make_label(left_r, "3/4", 17, Color(0.95, 0.96, 1.0), Vector3(0.0, -0.152, 0.004))
	_add_anchor_tag(left_r, false, Vector3(0.0, 0.205, 0.005))

	# FIJO DERECHA: Retícula oficial target_fight + icono puño/burst + chips cortos
	var p_right: Dictionary = _make_panel(w_root, Vector2(0.25, 0.28), Color(0.04, 0.06, 0.11, 0.84), Color(1.0, 0.35, 0.16, 0.92))
	var right_r: Node3D = p_right["root"] as Node3D
	right_r.position = Vector3(0.46, 0.02, 0.03)
	right_r.rotation_degrees = Vector3(0.0, -18.0, 0.0)
	_alt1_border_r = p_right["border_mat"] as StandardMaterial3D
	_make_tex_quad(right_r, Vector2(0.11, 0.11), "target_fight.png", Color(1.0, 0.92, 0.88, 0.95), Vector3(0.0, 0.068, 0.003), 114)
	var thr_icon: Dictionary = _make_tex_quad(right_r, Vector2(0.055, 0.055), "icon_burst.png", Color(1.0, 0.82, 0.25, 1.0), Vector3(0.0, 0.068, 0.004), 116)
	_alt1_threat_mat = thr_icon["mat"] as StandardMaterial3D
	_alt1_threat_name = _make_label(right_r, "V3 ENTRANTE", 19, Color(1.0, 0.85, 0.35), Vector3(0.0, -0.015, 0.004))
	_alt1_counter_lbl = _make_label(right_r, "[🕹️ VANISH]\n[G+T PARRY]  [🐢 X]", 15, Color(0.85, 0.96, 1.0), Vector3(0.0, -0.088, 0.004))
	_add_anchor_tag(right_r, false, Vector3(0.0, 0.165, 0.005))

	# CABEZA ARRIBA: Retratos oficiales Goku vs Vegeta + Barras indicator_base + cinta info_obi
	var p_top: Dictionary = _make_panel(h_root, Vector2(0.64, 0.13), Color(0.02, 0.05, 0.10, 0.82), Color(0.25, 0.88, 1.0, 0.85))
	var top_r: Node3D = p_top["root"] as Node3D
	top_r.position = Vector3(0.0, 0.27, -0.96)
	top_r.rotation_degrees = Vector3(6.0, 0.0, 0.0)
	_make_tex_quad(top_r, Vector2(0.11, 0.11), "chara_chip_vegeta.png", Color.WHITE, Vector3(-0.26, 0.0, 0.003), 115)
	_make_tex_quad(top_r, Vector2(0.11, 0.11), "chara_chip_goku.png", Color.WHITE, Vector3(0.26, 0.0, 0.003), 115)
	_alt1_role_lbl = _make_label(top_r, "🛡️ DEFENSA", 17, Color(0.30, 0.92, 1.0), Vector3(0.0, 0.038, 0.004))
	_alt1_p_ki_lbl = _make_label(top_r, "TÚ 74", 15, Color(0.35, 0.95, 1.0), Vector3(-0.185, 0.012, 0.004), HORIZONTAL_ALIGNMENT_LEFT)
	_alt1_e_ki_lbl = _make_label(top_r, "42 RIVAL", 15, Color(1.0, 0.45, 0.28), Vector3(0.185, 0.012, 0.004), HORIZONTAL_ALIGNMENT_RIGHT)
	_make_tex_quad(top_r, Vector2(0.18, 0.026), "indicator_base.png", Color(0.25, 0.35, 0.45, 0.85), Vector3(-0.10, -0.016, 0.003), 113)
	_make_tex_quad(top_r, Vector2(0.18, 0.026), "indicator_base.png", Color(0.35, 0.20, 0.20, 0.85), Vector3(0.10, -0.016, 0.003), 113)
	_alt1_p_ki_fill = _make_bar_fill(top_r, Vector3(0.165, 0.014, 0.005), Color(0.18, 0.90, 1.0, 0.98), 115)
	_alt1_p_ki_fill.position = Vector3(-0.10, -0.016, 0.004)
	_alt1_e_ki_fill = _make_bar_fill(top_r, Vector3(0.165, 0.014, 0.005), Color(1.0, 0.34, 0.16, 0.98), 115)
	_alt1_e_ki_fill.position = Vector3(0.10, -0.016, 0.004)
	_alt1_timer_fill = _make_bar_fill(top_r, Vector3(0.38, 0.007, 0.005), Color(1.0, 0.88, 0.22, 0.95), 115)
	_alt1_timer_fill.position = Vector3(0.0, -0.044, 0.004)
	_make_tex_quad(top_r, Vector2(0.42, 0.075), "info_obi.png", Color(1.0, 1.0, 1.0, 0.85), Vector3(0.0, -0.105, 0.003), 114)
	_alt1_flash_lbl = _make_label(top_r, "✨ ¡PARRY PERFECTO! +20 KI", 18, Color(1.0, 0.94, 0.25), Vector3(0.0, -0.105, 0.005))
	_add_anchor_tag(top_r, true, Vector3(0.0, 0.090, 0.005))


# ==============================================================================
# ALTERNATIVA 2: SCOUTER DUAL-ARC (ZENKAI PERIFÉRICO)
# Izq/Der FIJO: Columnas Ki + badges alerta/MAX | Ojo Der CABEZA: scouter_radar oficial
# ==============================================================================
func _build_alt2_scouter_dual_arc() -> void:
	var w_root := Node3D.new()
	_world_hud_root.add_child(w_root)
	var h_root := Node3D.new()
	_head_hud_root.add_child(h_root)
	_alt_world_roots.append(w_root)
	_alt_head_roots.append(h_root)

	# FIJO IZQUIERDA: Ki Jugador vertical + Pips
	var p_l: Dictionary = _make_panel(w_root, Vector2(0.17, 0.42), Color(0.02, 0.06, 0.10, 0.82), Color(0.20, 0.95, 0.72, 0.88))
	var lr: Node3D = p_l["root"] as Node3D
	lr.position = Vector3(-0.40, 0.0, 0.03)
	lr.rotation_degrees = Vector3(0.0, 22.0, 0.0)
	_make_tex_quad(lr, Vector2(0.09, 0.09), "chara_chip_vegeta.png", Color.WHITE, Vector3(-0.032, 0.155, 0.003), 115)
	_make_bar_fill(lr, Vector3(0.026, 0.21, 0.004), Color(0.06, 0.12, 0.18, 0.92), 113).position = Vector3(-0.032, -0.005, 0.002)
	_alt2_p_ki_fill = _make_bar_fill(lr, Vector3(0.026, 0.21, 0.006), Color(0.18, 0.92, 1.0, 0.98), 115)
	_alt2_p_ki_fill.position = Vector3(-0.032, -0.005, 0.003)
	_alt2_p_ki_val = _make_label(lr, "74", 18, Color(0.45, 0.98, 1.0), Vector3(-0.032, -0.155, 0.004))
	_alt2_pips_lbl = _make_label(lr, "🛡\n💥\n⚡\n○", 28, Color.WHITE, Vector3(0.035, -0.005, 0.004))
	_add_anchor_tag(lr, false, Vector3(0.0, 0.235, 0.005))

	# FIJO DERECHA: Ki Rival vertical + Timer + Finisher/Threat badge oficial
	var p_r: Dictionary = _make_panel(w_root, Vector2(0.19, 0.42), Color(0.05, 0.04, 0.09, 0.82), Color(1.0, 0.36, 0.18, 0.88))
	var rr: Node3D = p_r["root"] as Node3D
	rr.position = Vector3(0.41, 0.0, 0.03)
	rr.rotation_degrees = Vector3(0.0, -22.0, 0.0)
	_make_tex_quad(rr, Vector2(0.09, 0.09), "chara_chip_goku.png", Color.WHITE, Vector3(0.038, 0.155, 0.003), 115)
	_make_bar_fill(rr, Vector3(0.026, 0.21, 0.004), Color(0.14, 0.07, 0.08, 0.92), 113).position = Vector3(0.038, -0.005, 0.002)
	_alt2_e_ki_fill = _make_bar_fill(rr, Vector3(0.026, 0.21, 0.006), Color(1.0, 0.32, 0.15, 0.98), 115)
	_alt2_e_ki_fill.position = Vector3(0.038, -0.005, 0.003)
	_alt2_e_ki_val = _make_label(rr, "42", 18, Color(1.0, 0.52, 0.30), Vector3(0.038, -0.155, 0.004))
	_alt2_timer_fill = _make_bar_fill(rr, Vector3(0.010, 0.21, 0.006), Color(1.0, 0.88, 0.20, 0.95), 115)
	_alt2_timer_fill.position = Vector3(0.008, -0.005, 0.003)
	_make_tex_quad(rr, Vector2(0.075, 0.075), "target_fight.png", Color.WHITE, Vector3(-0.042, 0.045, 0.003), 114)
	var t2_m: Dictionary = _make_tex_quad(rr, Vector2(0.045, 0.045), "icon_burst.png", Color(1.0, 0.85, 0.25), Vector3(-0.042, 0.045, 0.004), 116)
	_alt2_threat_mat = t2_m["mat"] as StandardMaterial3D
	_make_tex_quad(rr, Vector2(0.075, 0.038), "finisher_lv2.png", Color.WHITE, Vector3(-0.042, -0.025, 0.004), 115)
	_alt2_threat_sub = _make_label(rr, "🕹️/G+T", 14, Color(0.95, 0.95, 1.0), Vector3(-0.042, -0.075, 0.004))
	_add_anchor_tag(rr, false, Vector3(0.0, 0.235, 0.005))

	# CABEZA OJO DERECHO: Visor Scouter real con radar oficial 20_scouter_radar.png
	var p_sc: Dictionary = _make_panel(h_root, Vector2(0.36, 0.18), Color(0.02, 0.14, 0.09, 0.62), Color(0.20, 1.0, 0.58, 0.92))
	var sr: Node3D = p_sc["root"] as Node3D
	sr.position = Vector3(0.33, 0.20, -0.92)
	sr.rotation_degrees = Vector3(4.0, -16.0, 0.0)
	_make_tex_quad(sr, Vector2(0.28, 0.14), "scouter_radar.png", Color(0.55, 1.0, 0.72, 0.95), Vector3(-0.04, 0.0, 0.003), 115)
	_make_tex_quad(sr, Vector2(0.085, 0.085), "alert_chara_goku.png", Color.WHITE, Vector3(0.115, 0.025, 0.004), 116)
	_alt2_scouter_role = _make_label(sr, "[ 🛡️ DEFENSA ]", 17, Color(0.45, 1.0, 0.72), Vector3(-0.03, 0.052, 0.005))
	_alt2_scouter_bp = _make_label(sr, "BP 1.18x  |  3/4", 15, Color(0.82, 1.0, 0.88), Vector3(-0.03, 0.002, 0.005))
	_alt2_scouter_flash = _make_label(sr, "▶ ¡PARRY!", 17, Color(1.0, 0.92, 0.25), Vector3(0.0, -0.052, 0.005))
	_add_anchor_tag(sr, true, Vector3(0.0, 0.115, 0.005))


# ==============================================================================
# ALTERNATIVA 3: CINE ANIME MINIMALISTA (ZENKAI INFERIOR)
# Mitad superior libre; pips triangulares izq, sello Zenkai der,
# Barra Ki clash con CharaChips abajo y cinta info_obi solo en callout
# ==============================================================================
func _build_alt3_anime_cinema() -> void:
	var w_root := Node3D.new()
	_world_hud_root.add_child(w_root)
	var h_root := Node3D.new()
	_head_hud_root.add_child(h_root)
	_alt_world_roots.append(w_root)
	_alt_head_roots.append(h_root)

	# FIJO IZQUIERDA: Triángulos de alerta flotantes sin recuadro
	var p_left_anchor := Node3D.new()
	p_left_anchor.position = Vector3(-0.39, -0.01, 0.03)
	p_left_anchor.rotation_degrees = Vector3(0.0, 14.0, 0.0)
	w_root.add_child(p_left_anchor)
	var a_texs3: Array[String] = ["alert_base_g.png", "alert_base_r.png", "alert_base_y.png", "alert_base_b.png"]
	for i in range(4):
		_make_tex_quad(p_left_anchor, Vector2(0.038, 0.062), a_texs3[i], Color(1.0, 1.0, 1.0, 0.85 if i < 3 else 0.30), Vector3(-0.028, 0.090 - float(i) * 0.060, 0.002), 114)
	_alt3_pips_lbl = _make_label(p_left_anchor, "🛡\n💥\n⚡\n○", 28, Color.WHITE, Vector3(0.022, 0.0, 0.003))
	_add_anchor_tag(p_left_anchor, false, Vector3(0.0, 0.165, 0.004))

	# FIJO DERECHA: Retícula target_fight + icono Zenkai flotante
	var stamp_anchor := Node3D.new()
	stamp_anchor.position = Vector3(0.40, -0.01, 0.03)
	stamp_anchor.rotation_degrees = Vector3(0.0, -14.0, 0.0)
	w_root.add_child(stamp_anchor)
	_make_tex_quad(stamp_anchor, Vector2(0.115, 0.115), "target_fight.png", Color(1.0, 0.90, 0.82, 0.95), Vector3(0.0, 0.035, 0.002), 114)
	var s3_m: Dictionary = _make_tex_quad(stamp_anchor, Vector2(0.052, 0.052), "icon_burst.png", Color(1.0, 0.88, 0.25), Vector3(0.0, 0.035, 0.003), 116)
	_alt3_stamp_mat = s3_m["mat"] as StandardMaterial3D
	_alt3_stamp_lbl = _make_label(stamp_anchor, "V3 · 🕹️/G+T", 18, Color(1.0, 0.90, 0.35), Vector3(0.0, -0.055, 0.004))
	_add_anchor_tag(stamp_anchor, false, Vector3(0.0, 0.120, 0.004))

	# FIJO INFERIOR: CharaChips + Barra Ki anime frente a frente debajo del domo
	var p_bot: Dictionary = _make_panel(w_root, Vector2(0.62, 0.095), Color(0.02, 0.04, 0.08, 0.78), Color(0.35, 0.88, 1.0, 0.78))
	var br: Node3D = p_bot["root"] as Node3D
	br.position = Vector3(0.0, -0.33, 0.04)
	br.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	_make_tex_quad(br, Vector2(0.095, 0.095), "chara_chip_vegeta.png", Color.WHITE, Vector3(-0.265, 0.004, 0.003), 115)
	_make_tex_quad(br, Vector2(0.095, 0.095), "chara_chip_goku.png", Color.WHITE, Vector3(0.265, 0.004, 0.003), 115)
	_alt3_ki_num_l = _make_label(br, "74", 17, Color(0.35, 0.96, 1.0), Vector3(-0.20, 0.010, 0.004))
	_alt3_ki_num_r = _make_label(br, "42", 17, Color(1.0, 0.44, 0.24), Vector3(0.20, 0.010, 0.004))
	_make_tex_quad(br, Vector2(0.17, 0.026), "indicator_base.png", Color(0.25, 0.35, 0.45, 0.85), Vector3(-0.092, 0.010, 0.002), 113)
	_make_tex_quad(br, Vector2(0.17, 0.026), "indicator_base.png", Color(0.35, 0.20, 0.20, 0.85), Vector3(0.092, 0.010, 0.002), 113)
	_alt3_p_ki_fill = _make_bar_fill(br, Vector3(0.155, 0.014, 0.005), Color(0.20, 0.92, 1.0, 0.98), 115)
	_alt3_p_ki_fill.position = Vector3(-0.092, 0.010, 0.003)
	_alt3_e_ki_fill = _make_bar_fill(br, Vector3(0.155, 0.014, 0.005), Color(1.0, 0.34, 0.16, 0.98), 115)
	_alt3_e_ki_fill.position = Vector3(0.092, 0.010, 0.003)
	_alt3_timer_fill = _make_bar_fill(br, Vector3(0.38, 0.007, 0.005), Color(1.0, 0.90, 0.24, 0.95), 115)
	_alt3_timer_fill.position = Vector3(0.0, -0.026, 0.003)
	_add_anchor_tag(br, false, Vector3(0.0, -0.072, 0.004))

	# CABEZA SOLO EN CALLOUT: Cinta oficial info_obi + texto grande
	_alt3_callout_root = Node3D.new()
	_alt3_callout_root.position = Vector3(0.0, 0.23, -0.96)
	h_root.add_child(_alt3_callout_root)
	_make_tex_quad(_alt3_callout_root, Vector2(0.46, 0.095), "info_obi.png", Color(1.0, 1.0, 1.0, 0.92), Vector3(0.0, 0.0, 0.001), 114)
	_alt3_flash_lbl = _make_label(_alt3_callout_root, "⚡ ¡PARRY!", 26, Color(1.0, 0.94, 0.25), Vector3(0.0, 0.0, 0.003))
	_add_anchor_tag(_alt3_callout_root, true, Vector3(0.0, 0.065, 0.004))


func _build_desktop_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_panel.offset_left = 12.0
	top_panel.offset_top = 10.0
	top_panel.offset_right = 760.0
	top_panel.offset_bottom = 120.0
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = Color(0.05, 0.08, 0.14, 0.86)
	top_sb.border_color = Color(0.24, 0.78, 1.0, 0.65)
	top_sb.set_border_width_all(1)
	top_sb.set_corner_radius_all(8)
	top_sb.set_content_margin_all(10)
	top_panel.add_theme_stylebox_override("panel", top_sb)
	canvas.add_child(top_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	top_panel.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vbox.add_child(row1)

	var scen_names: Array[String] = ["⚔️ Ataque", "🛡️ Defensa", "⚡ Simultáneo", "💨 Evento Lore"]
	for i in range(scen_names.size()):
		var sb := Button.new()
		sb.text = scen_names[i]
		var cap_s: int = i
		sb.pressed.connect(func() -> void: _select_scenario(cap_s))
		row1.add_child(sb)
		_scen_buttons.append(sb)

	_sweep_btn = Button.new()
	_sweep_btn.text = "👁️ Auto-Giro: OFF"
	_sweep_btn.pressed.connect(_toggle_auto_sweep)
	row1.add_child(_sweep_btn)

	_tags_btn = Button.new()
	_tags_btn.text = "🏷️ Tags: ON"
	_tags_btn.pressed.connect(_toggle_tags)
	row1.add_child(_tags_btn)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Reset Vista"
	reset_btn.pressed.connect(_reset_head_view)
	row1.add_child(reset_btn)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	_desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_desc_label)

	var bot_panel := PanelContainer.new()
	bot_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_panel.offset_left = 18.0
	bot_panel.offset_right = -18.0
	bot_panel.offset_top = -76.0
	bot_panel.offset_bottom = -12.0
	var bot_sb := StyleBoxFlat.new()
	bot_sb.bg_color = Color(0.04, 0.07, 0.12, 0.90)
	bot_sb.border_color = Color(1.0, 0.78, 0.22, 0.80)
	bot_sb.set_border_width_all(2)
	bot_sb.set_corner_radius_all(10)
	bot_sb.set_content_margin_all(10)
	bot_panel.add_theme_stylebox_override("panel", bot_sb)
	canvas.add_child(bot_panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	bot_panel.add_child(hbox)

	var alt_titles: Array[String] = [
		"1. Flancos Tácticos (Zenkai Híbrido)",
		"2. Scouter Dual-Arc (Zenkai Periférico)",
		"3. Cine Anime Minimalista (Zenkai Inferior)"
	]
	for i in range(alt_titles.size()):
		var ab := Button.new()
		ab.text = alt_titles[i]
		ab.custom_minimum_size = Vector2(280.0, 42.0)
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_a: int = i
		ab.pressed.connect(func() -> void: _select_alternative(cap_a))
		hbox.add_child(ab)
		_alt_buttons.append(ab)


func _style_button_active(btn: Button, is_on: bool, active_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = active_col if is_on else Color(0.11, 0.15, 0.22, 0.95)
	sb.border_color = active_col.lightened(0.35) if is_on else Color(0.30, 0.38, 0.50, 0.75)
	sb.set_border_width_all(2 if is_on else 1)
	sb.set_corner_radius_all(7)
	sb.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_color_override("font_color", Color(0.05, 0.07, 0.10) if is_on else Color(0.90, 0.94, 1.0))


func _select_alternative(idx: int) -> void:
	_active_alt = clampi(idx, 0, _alt_world_roots.size() - 1)
	for i in range(_alt_world_roots.size()):
		_alt_world_roots[i].visible = (i == _active_alt)
		_alt_head_roots[i].visible = (i == _active_alt)
	for i in range(_alt_buttons.size()):
		_style_button_active(_alt_buttons[i], i == _active_alt, Color(1.0, 0.80, 0.22))
	_update_description_text()


func _select_scenario(idx: int) -> void:
	_active_scenario = clampi(idx, 0, 3)
	for i in range(_scen_buttons.size()):
		_style_button_active(_scen_buttons[i], i == _active_scenario, Color(0.28, 0.90, 1.0))
	_refresh_scenario_visuals()


func _update_description_text() -> void:
	if not _desc_label:
		return
	var detail: String = ""
	match _active_alt:
		HudAlt.TACTICAL_FLANKS:
			detail = "ALT 1 (Zenkai) — [FIJO Izq] Alertas + Lv.2 | [FIJO Der] Retícula target_fight + Chips | [CABEZA] CharaChips + Ki + cinta info_obi."
		HudAlt.SCOUTER_DUAL_ARC:
			detail = "ALT 2 (Zenkai) — [FIJO Izq/Der] Arcos verticales de Ki + Retratos | [CABEZA Ojo Der] Lente oficial 20_scouter_radar."
		HudAlt.ANIME_CINEMA:
			detail = "ALT 3 (Zenkai) — [FIJO Izq/Der/Abajo] Alertas + Sello + Barra Ki con CharaChips | [CABEZA] Cinta info_obi solo en evento."
	_desc_label.text = "%s\nArrastra el mouse (o WASD/Flechas) para girar la cabeza VR y comparar FIJO vs CABEZA." % detail


func _refresh_scenario_visuals() -> void:
	var is_lore: bool = (_active_scenario == Scenario.LORE_EVENT)
	if _lore_orb:
		_lore_orb.visible = is_lore
	var fight_tex: Texture2D = _get_ui_tex("target_fight.png")
	var normal_tex: Texture2D = _get_ui_tex("target_normal.png")
	for i in range(_zones.size()):
		var zd: Dictionary = _zones[i]
		var z_node: Node3D = zd["node"] as Node3D
		var box_m: MeshInstance3D = zd["box"] as MeshInstance3D
		var b_mat: StandardMaterial3D = zd["box_mat"] as StandardMaterial3D
		var r_mat: StandardMaterial3D = zd["ring_mat"] as StandardMaterial3D
		var ic: Label3D = zd["icon"] as Label3D
		z_node.visible = not is_lore
		if _active_scenario == Scenario.ATTACK:
			box_m.visible = false
			if fight_tex:
				r_mat.albedo_texture = fight_tex
			r_mat.albedo_color = Color(1.0, 0.72, 0.25, 0.95)
			ic.text = "⭕"
			ic.modulate = Color(1.0, 0.85, 0.35)
		elif _active_scenario == Scenario.DEFENSE:
			box_m.visible = true
			var hot: bool = (i == 1)
			if fight_tex and normal_tex:
				r_mat.albedo_texture = fight_tex if hot else normal_tex
			b_mat.albedo_color = Color(1.0, 0.25, 0.10, 0.28) if hot else Color(0.18, 0.78, 1.0, 0.12)
			r_mat.albedo_color = Color(1.0, 0.92, 0.88, 1.0) if hot else Color(0.55, 1.0, 0.75, 0.65)
			ic.text = "🔥" if hot else "·"
			ic.modulate = Color(1.0, 0.78, 0.25) if hot else Color(0.70, 0.90, 1.0)
		elif _active_scenario == Scenario.SIMULTANEOUS:
			box_m.visible = (i % 2 == 1)
			var is_atk_slot: bool = (i % 2 == 0)
			if fight_tex and normal_tex:
				r_mat.albedo_texture = fight_tex if (i == 2 or is_atk_slot) else normal_tex
			b_mat.albedo_color = Color(0.20, 0.88, 1.0, 0.22)
			r_mat.albedo_color = Color(1.0, 0.78, 0.25, 0.95) if is_atk_slot else Color(0.35, 1.0, 0.65, 0.95)
			ic.text = "💥" if i == 2 else ("⭕" if is_atk_slot else "⬜")
			ic.modulate = Color(1.0, 0.90, 0.30)

	var role_str: String = "🛡️ DEFENSA"
	var role_col: Color = Color(0.30, 0.92, 1.0)
	var icon_tex: String = "icon_burst.png"
	var name_str: String = "V3 ENTRANTE"
	var chips_str: String = "[🕹️ VANISH]\n[G+T PARRY]  [🐢 X]"
	var stamp_str: String = "V3 · 🕹️/G+T"
	var pips_str: String = "🛡\n💥\n⚡\n○"
	var round_str: String = "3/4"
	if _active_scenario == Scenario.ATTACK:
		role_str = "⚔️ ATAQUE"
		role_col = Color(1.0, 0.56, 0.16)
		icon_tex = "icon_fist.png"
		name_str = "TU TURNO"
		chips_str = "[G+T PUÑO]\n[0.5s⚡] [1.1s🔥]"
		stamp_str = "⚔️ 3/4 · [A/X]"
		pips_str = "⚡\n👊\n○\n○"
	elif _active_scenario == Scenario.SIMULTANEOUS:
		role_str = "⚡ SIMULTÁNEO"
		role_col = Color(1.0, 0.88, 0.22)
		icon_tex = "icon_burst.png"
		name_str = "CHOQUE 2/4"
		chips_str = "[⭕ G+T GOLPE]\n[⬜ TRIG / PARRY]"
		stamp_str = "💥 2/4 CHOQUE"
	elif _active_scenario == Scenario.LORE_EVENT:
		role_str = "💨 DESENGANCHE Z"
		role_col = Color(0.42, 0.96, 1.0)
		icon_tex = "icon_up.png"
		name_str = "RESPIRO +10 KI"
		chips_str = "[SALTO ATRÁS]\n[SIN VUELO]"
		stamp_str = "💨 +10 KI"

	var i_tex: Texture2D = _get_ui_tex(icon_tex)
	if _alt1_threat_mat and i_tex:
		_alt1_threat_mat.albedo_texture = i_tex
	if _alt2_threat_mat and i_tex:
		_alt2_threat_mat.albedo_texture = i_tex
	if _alt3_stamp_mat and i_tex:
		_alt3_stamp_mat.albedo_texture = i_tex

	if _alt1_role_lbl:
		_alt1_role_lbl.text = role_str
		_alt1_role_lbl.modulate = role_col
		_alt1_threat_name.text = name_str
		_alt1_counter_lbl.text = chips_str
		_alt1_pips_lbl.text = pips_str
		_alt1_round_lbl.text = round_str
	if _alt1_border_r:
		_alt1_border_r.albedo_color = role_col
	if _alt2_pips_lbl:
		_alt2_pips_lbl.text = pips_str
		_alt2_threat_sub.text = stamp_str
		_alt2_scouter_role.text = "[ %s ]" % role_str
		_alt2_scouter_role.modulate = role_col
	if _alt3_pips_lbl:
		_alt3_pips_lbl.text = pips_str
		_alt3_stamp_lbl.text = stamp_str


func _toggle_auto_sweep() -> void:
	_auto_sweep = not _auto_sweep
	if _sweep_btn:
		_sweep_btn.text = "👁️ Auto-Giro: ON" if _auto_sweep else "👁️ Auto-Giro: OFF"


func _toggle_tags() -> void:
	_show_anchor_tags = not _show_anchor_tags
	for lbl in _tag_labels:
		if lbl and is_instance_valid(lbl):
			lbl.visible = _show_anchor_tags
	if _tags_btn:
		_tags_btn.text = "🏷️ Tags: ON" if _show_anchor_tags else "🏷️ Tags: OFF"


func _reset_head_view() -> void:
	_auto_sweep = false
	if _sweep_btn:
		_sweep_btn.text = "👁️ Auto-Giro: OFF"
	_head_yaw = 0.0
	_head_pitch = -0.03
	_apply_head_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_head_yaw = clampf(_head_yaw - mm.relative.x * 0.0055, -0.78, 0.78)
		_head_pitch = clampf(_head_pitch - mm.relative.y * 0.0045, -0.45, 0.45)
		_apply_head_rotation()


func _process(delta: float) -> void:
	var yaw_in: float = Input.get_axis("ui_right", "ui_left")
	var pitch_in: float = Input.get_axis("ui_down", "ui_up")
	if absf(yaw_in) > 0.01 or absf(pitch_in) > 0.01:
		_head_yaw = clampf(_head_yaw + yaw_in * delta * 1.15, -0.78, 0.78)
		_head_pitch = clampf(_head_pitch + pitch_in * delta * 0.85, -0.45, 0.45)
		_apply_head_rotation()
	elif _auto_sweep:
		_sweep_phase += delta * 1.45
		_head_yaw = sin(_sweep_phase) * 0.36
		_head_pitch = -0.03 + sin(_sweep_phase * 0.7) * 0.06
		_apply_head_rotation()

	if _head_hud_root and _head_pivot:
		var lerp_w: float = 1.0 - exp(-9.0 * delta)
		_head_hud_root.global_position = _head_pivot.global_position
		var cur_q: Quaternion = _head_hud_root.global_transform.basis.get_rotation_quaternion()
		var dst_q: Quaternion = _head_pivot.global_transform.basis.get_rotation_quaternion()
		_head_hud_root.global_transform.basis = Basis(cur_q.slerp(dst_q, lerp_w))

	_ring_phase = fposmod(_ring_phase + delta * 0.75, 1.0)
	var ring_s: float = 0.85 + (1.0 - _ring_phase) * 0.65
	if _active_scenario != Scenario.LORE_EVENT and _zones.size() > 1:
		var hot_ring: MeshInstance3D = _zones[1]["ring"] as MeshInstance3D
		if hot_ring:
			hot_ring.scale = Vector3.ONE * ring_s
			hot_ring.rotation.z += delta * 1.4
	elif _lore_orb and _lore_orb.visible:
		_lore_orb.scale = Vector3.ONE * (0.95 + sin(_ring_phase * TAU) * 0.14)

	_flash_timer += delta
	if _flash_timer >= 2.2:
		_flash_timer = 0.0
		_flash_cycle_idx = (_flash_cycle_idx + 1) % 3
		_player_ki_sim = 74.0 if _flash_cycle_idx == 0 else (90.0 if _flash_cycle_idx == 1 else 64.0)
		_enemy_ki_sim = 42.0 if _flash_cycle_idx == 0 else (32.0 if _flash_cycle_idx == 1 else 26.0)
		var f_txt: String = "✨ ¡PARRY! +20 KI" if _flash_cycle_idx == 0 else ("💨 ¡Z-VANISH! -8 KI" if _flash_cycle_idx == 1 else "✋ ¡DESVÍO! +16 KI")
		if _alt1_flash_lbl:
			_alt1_flash_lbl.text = f_txt
		if _alt2_scouter_flash:
			_alt2_scouter_flash.text = "▶ " + f_txt
		if _alt3_flash_lbl:
			_alt3_flash_lbl.text = f_txt

	var p_ratio: float = clampf(_player_ki_sim / 100.0, 0.05, 1.0)
	var e_ratio: float = clampf(_enemy_ki_sim / 100.0, 0.05, 1.0)
	var t_ratio: float = clampf(1.0 - _ring_phase, 0.05, 1.0)
	var p_i_str: String = "%d" % int(_player_ki_sim)
	var e_i_str: String = "%d" % int(_enemy_ki_sim)

	if _alt1_p_ki_fill:
		_alt1_p_ki_fill.scale.x = p_ratio
		_alt1_e_ki_fill.scale.x = e_ratio
		_alt1_timer_fill.scale.x = t_ratio
		_alt1_p_ki_lbl.text = "TÚ " + p_i_str
		_alt1_e_ki_lbl.text = e_i_str + " RIVAL"
	if _alt2_p_ki_fill:
		_alt2_p_ki_fill.scale.y = p_ratio
		_alt2_e_ki_fill.scale.y = e_ratio
		_alt2_timer_fill.scale.y = t_ratio
		_alt2_p_ki_val.text = p_i_str
		_alt2_e_ki_val.text = e_i_str
	if _alt3_p_ki_fill:
		_alt3_p_ki_fill.scale.x = p_ratio
		_alt3_e_ki_fill.scale.x = e_ratio
		_alt3_timer_fill.scale.x = t_ratio
		_alt3_ki_num_l.text = p_i_str
		_alt3_ki_num_r.text = e_i_str
		if _alt3_callout_root:
			_alt3_callout_root.visible = (_flash_timer <= 1.25)
