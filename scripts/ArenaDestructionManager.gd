class_name ArenaDestructionManager
extends Node3D

## Gestor canónico de destrucción del entorno (Recuadros café y 1er círculo de montañas),
## impactos sísmicos contra el piso (indestructible), pool de escombros físicos y humo denso DBZ.

const BOULDER_MAX_HP: float = 350.0
const BOULDER_BP_BONUS: float = 220.0
const CANYON_MAX_HP: float = 1800.0
const CANYON_BP_BONUS: float = 550.0
const DEBRIS_POOL_SIZE: int = 24

var _boulder_mm: MultiMeshInstance3D = null
var _boulder_body: StaticBody3D = null
var _boulder_hp: PackedFloat32Array = PackedFloat32Array()
var _boulder_pos: Array[Vector3] = []
var _boulder_cols: Array[CollisionShape3D] = []

var _canyon_mm: MultiMeshInstance3D = null
var _canyon_body: StaticBody3D = null
var _canyon_hp: PackedFloat32Array = PackedFloat32Array()
var _canyon_pos: Array[Vector3] = []
var _canyon_cols: Array[CollisionShape3D] = []

# Pool fijo de escombros físicos (cero allocs en runtime)
var _debris_nodes: Array[MeshInstance3D] = []
var _debris_vel: Array[Vector3] = []
var _debris_rot_vel: Array[Vector3] = []
var _debris_timers: PackedFloat32Array = PackedFloat32Array()
var _debris_cursor: int = 0


static func get_active(tree: SceneTree) -> ArenaDestructionManager:
	if not tree:
		return null
	var search_root: Node = tree.current_scene if tree.current_scene else tree.root
	if not search_root:
		return null
	var node: Node = search_root.get_node_or_null("ArenaDestructionManager")
	if node is ArenaDestructionManager:
		return node as ArenaDestructionManager
	return search_root.find_child("ArenaDestructionManager", true, false) as ArenaDestructionManager


func _ready() -> void:
	_init_debris_pool()


func register_arena_destructibles(arena_root: Node) -> void:
	if not arena_root:
		return

	_boulder_mm = arena_root.get_node_or_null("ToriyamaBoulders_MultiMesh") as MultiMeshInstance3D
	_boulder_body = arena_root.get_node_or_null("ToriyamaBoulders_Mountain_StaticBody") as StaticBody3D
	_boulder_hp.clear()
	_boulder_pos.clear()
	_boulder_cols.clear()
	if _boulder_mm and _boulder_mm.multimesh:
		var b_count: int = _boulder_mm.multimesh.instance_count
		_boulder_hp.resize(b_count)
		for i in range(b_count):
			_boulder_hp[i] = BOULDER_MAX_HP
			_boulder_pos.append(_boulder_mm.multimesh.get_instance_transform(i).origin)
		if _boulder_body:
			for c in _boulder_body.get_children():
				if c is CollisionShape3D:
					_boulder_cols.append(c as CollisionShape3D)

	_canyon_mm = arena_root.get_node_or_null("ToriyamaCanyon_MultiMesh") as MultiMeshInstance3D
	_canyon_body = arena_root.get_node_or_null("ToriyamaCanyon_StaticBody") as StaticBody3D
	_canyon_hp.clear()
	_canyon_pos.clear()
	_canyon_cols.clear()
	if _canyon_mm and _canyon_mm.multimesh:
		var c_count: int = _canyon_mm.multimesh.instance_count
		_canyon_hp.resize(c_count)
		for i in range(c_count):
			_canyon_hp[i] = CANYON_MAX_HP
			_canyon_pos.append(_canyon_mm.multimesh.get_instance_transform(i).origin)
		if _canyon_body:
			for c in _canyon_body.get_children():
				if c is CollisionShape3D:
					_canyon_cols.append(c as CollisionShape3D)


func _init_debris_pool() -> void:
	if not _debris_nodes.is_empty():
		return
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.85, 0.65, 0.78)
	var deb_mat := StandardMaterial3D.new()
	deb_mat.albedo_color = Color(0.62, 0.44, 0.28)
	deb_mat.roughness = 0.92

	_debris_timers.resize(DEBRIS_POOL_SIZE)
	for i in range(DEBRIS_POOL_SIZE):
		var m := MeshInstance3D.new()
		m.name = "DebrisChunk_%d" % i
		m.mesh = box_mesh
		m.material_override = deb_mat
		m.visible = false
		add_child(m)
		_debris_nodes.append(m)
		_debris_vel.append(Vector3.ZERO)
		_debris_rot_vel.append(Vector3.ZERO)
		_debris_timers[i] = 0.0


func _process(delta: float) -> void:
	for i in range(_debris_nodes.size()):
		if _debris_timers[i] <= 0.0:
			continue
		_debris_timers[i] -= delta
		var m: MeshInstance3D = _debris_nodes[i]
		if not is_instance_valid(m):
			continue
		if _debris_timers[i] <= 0.0:
			m.visible = false
			continue
		var v: Vector3 = _debris_vel[i]
		v.y -= 18.0 * delta
		var np: Vector3 = m.global_position + v * delta
		if np.y < 0.30:
			np.y = 0.30
			v.y = absf(v.y) * 0.38
			v.x *= 0.72
			v.z *= 0.72
		_debris_vel[i] = v
		m.global_position = np
		var rv: Vector3 = _debris_rot_vel[i]
		m.rotation += rv * delta
		if _debris_timers[i] < 0.45:
			var sc: float = clampf(_debris_timers[i] / 0.45, 0.05, 1.0)
			m.scale = Vector3.ONE * sc


func spawn_debris_burst(origin_pos: Vector3, count: int = 6, scale_mult: float = 1.0) -> void:
	if _debris_nodes.is_empty():
		_init_debris_pool()
	var n: int = mini(count, DEBRIS_POOL_SIZE)
	for k in range(n):
		var idx: int = _debris_cursor
		_debris_cursor = (_debris_cursor + 1) % DEBRIS_POOL_SIZE
		var m: MeshInstance3D = _debris_nodes[idx]
		if not is_instance_valid(m):
			continue
		m.visible = true
		m.global_position = origin_pos + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.8), randf_range(-1.2, 1.2))
		m.scale = Vector3.ONE * randf_range(0.65, 1.45) * scale_mult
		m.rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
		var ang: float = randf_range(0.0, TAU)
		var spd: float = randf_range(6.0, 16.0) * scale_mult
		_debris_vel[idx] = Vector3(cos(ang) * spd, randf_range(5.0, 14.0) * scale_mult, sin(ang) * spd)
		_debris_rot_vel[idx] = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		_debris_timers[idx] = 1.75


func spawn_dense_dbz_smoke(pos: Vector3, victim: Node3D, radius_scale: float = 2.8, obscure_sec: float = 2.8) -> void:
	if get_tree():
		KiSmokeFX.spawn_smoke(get_tree(), pos + Vector3(0.0, 0.8, 0.0), radius_scale)
		KiSmokeFX.spawn_smoke(get_tree(), pos + Vector3(1.2, 1.4, -0.9), radius_scale * 0.90)
		KiSmokeFX.spawn_smoke(get_tree(), pos + Vector3(-1.2, 1.2, 1.0), radius_scale * 0.90)
		KiSmokeFX.spawn_smoke(get_tree(), pos + Vector3(0.0, 2.1, 0.4), radius_scale * 0.80)
	if victim and is_instance_valid(victim) and victim.has_method("set"):
		victim.set("smoke_obscures_active", true)
		var prev_t: float = float(victim.get("smoke_obscured_timer")) if victim.get("smoke_obscured_timer") != null else 0.0
		victim.set("smoke_obscured_timer", maxf(prev_t, obscure_sec))


func _collapse_instance(mm_inst: MultiMeshInstance3D, cols: Array[CollisionShape3D], idx: int) -> void:
	if mm_inst and mm_inst.multimesh and idx >= 0 and idx < mm_inst.multimesh.instance_count:
		var t: Transform3D = mm_inst.multimesh.get_instance_transform(idx)
		t.basis = Basis.from_scale(Vector3(0.001, 0.001, 0.001))
		t.origin.y = -60.0
		mm_inst.multimesh.set_instance_transform(idx, t)
	if idx >= 0 and idx < cols.size() and is_instance_valid(cols[idx]):
		cols[idx].set_deferred("disabled", true)


func _find_nearest_active(pos: Vector3, positions: Array[Vector3], hps: PackedFloat32Array, max_dist: float) -> int:
	var best_idx: int = -1
	var best_d2: float = max_dist * max_dist
	for i in range(positions.size()):
		if i >= hps.size() or hps[i] <= 0.0:
			continue
		var d2: float = Vector2(positions[i].x - pos.x, positions[i].z - pos.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
	return best_idx


func apply_body_collision_impact(collider: Node, impact_pos: Vector3, victim: Node3D, attacker: Node3D, impact_speed: float) -> Dictionary:
	var res: Dictionary = {"destroyed": false, "kind": "none", "bonus_bp": 0.0}
	if not collider or impact_speed < 6.0:
		return res

	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and is_instance_valid(attacker) and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(victim.get("current_np")) if (victim and is_instance_valid(victim) and victim.get("current_np") != null) else 10000.0, 100.0)
	var bp_mult: float = clampf(sqrt(bp_atk / bp_def), 0.70, 2.20)
	var dmg: float = impact_speed * 28.0 * bp_mult

	if collider == _boulder_body or "Boulder" in collider.name:
		var b_idx: int = _find_nearest_active(impact_pos, _boulder_pos, _boulder_hp, 12.0)
		if b_idx != -1:
			_boulder_hp[b_idx] -= dmg
			if _boulder_hp[b_idx] <= 0.0:
				_collapse_instance(_boulder_mm, _boulder_cols, b_idx)
				spawn_debris_burst(impact_pos, 8, 1.15)
				spawn_dense_dbz_smoke(impact_pos, victim, 2.5, 2.2)
				if victim and is_instance_valid(victim) and victim.has_method("take_hit"):
					victim.take_hit(BOULDER_BP_BONUS, Vector3.ZERO, false)
				res["destroyed"] = true
				res["kind"] = "boulder"
				res["bonus_bp"] = BOULDER_BP_BONUS
			else:
				spawn_debris_burst(impact_pos, 3, 0.8)
				spawn_dense_dbz_smoke(impact_pos, victim, 1.5, 1.2)
	elif collider == _canyon_body or "Canyon" in collider.name:
		var c_idx: int = _find_nearest_active(impact_pos, _canyon_pos, _canyon_hp, 38.0)
		if c_idx != -1:
			_canyon_hp[c_idx] -= dmg
			if _canyon_hp[c_idx] <= 0.0:
				_collapse_instance(_canyon_mm, _canyon_cols, c_idx)
				spawn_debris_burst(impact_pos, 16, 1.85)
				spawn_dense_dbz_smoke(impact_pos, victim, 4.0, 3.2)
				var dd_m: DramaticDirector = DramaticDirector.get_active(get_tree())
				if dd_m:
					dd_m.spawn_persistent_crater(Vector3(impact_pos.x, 0.15, impact_pos.z), 2.4, true)
				if victim and is_instance_valid(victim) and victim.has_method("take_hit"):
					victim.take_hit(CANYON_BP_BONUS, Vector3.ZERO, false)
				res["destroyed"] = true
				res["kind"] = "mountain"
				res["bonus_bp"] = CANYON_BP_BONUS
			else:
				spawn_debris_burst(impact_pos, 4, 1.0)
				spawn_dense_dbz_smoke(impact_pos, victim, 2.0, 1.6)
	return res


func apply_power_aoe_destruction(center: Vector3, radius: float, power_damage: float, bp_atk: float = 10000.0) -> int:
	var destroyed_count: int = 0
	var bp_scale: float = clampf(bp_atk / 10000.0, 0.75, 2.6)
	var eff_dmg: float = maxf(power_damage, 400.0) * bp_scale

	for i in range(_boulder_pos.size()):
		if i >= _boulder_hp.size() or _boulder_hp[i] <= 0.0:
			continue
		if Vector2(_boulder_pos[i].x - center.x, _boulder_pos[i].z - center.z).length() <= radius:
			_boulder_hp[i] -= eff_dmg
			if _boulder_hp[i] <= 0.0:
				_collapse_instance(_boulder_mm, _boulder_cols, i)
				spawn_debris_burst(_boulder_pos[i], 6, 1.1)
				spawn_dense_dbz_smoke(_boulder_pos[i], null, 2.2, 0.0)
				destroyed_count += 1

	for j in range(_canyon_pos.size()):
		if j >= _canyon_hp.size() or _canyon_hp[j] <= 0.0:
			continue
		if Vector2(_canyon_pos[j].x - center.x, _canyon_pos[j].z - center.z).length() <= radius + 16.0:
			_canyon_hp[j] -= eff_dmg
			if _canyon_hp[j] <= 0.0:
				_collapse_instance(_canyon_mm, _canyon_cols, j)
				spawn_debris_burst(_canyon_pos[j], 10, 1.7)
				spawn_dense_dbz_smoke(_canyon_pos[j], null, 3.4, 0.0)
				destroyed_count += 1

	return destroyed_count


func apply_floor_seismic_impact(impact_pos: Vector3, victim: Node3D, attacker: Node3D, impact_speed: float) -> float:
	if impact_speed < 11.0:
		return 0.0
	var bp_atk: float = maxf(float(attacker.get("current_np")) if (attacker and is_instance_valid(attacker) and attacker.get("current_np") != null) else 10000.0, 100.0)
	var bp_def: float = maxf(float(victim.get("current_np")) if (victim and is_instance_valid(victim) and victim.get("current_np") != null) else 10000.0, 100.0)
	var bp_mult: float = clampf(sqrt(bp_atk / bp_def), 0.75, 2.0)
	var bonus_bp: float = clampf(impact_speed * 14.0 * bp_mult, 180.0, 380.0)
	spawn_debris_burst(impact_pos, 7, 1.0)
	spawn_dense_dbz_smoke(impact_pos, victim, 2.6, 2.0)
	if victim and is_instance_valid(victim) and victim.has_method("take_hit"):
		victim.take_hit(bonus_bp, Vector3.DOWN, false)
	return bonus_bp
