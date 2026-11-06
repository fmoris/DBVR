# RuntimeRagdollGenerator
# Generador autónomo de Ragdolls en tiempo de ejecución (Runtime) para Godot 4.3+
# Basado en la lógica cinemática y de masas del addon Auto-Ragdoll (Manik Sharma),
# adaptado para ejecutarse en standalone APK (Quest VR) sin dependencias del EditorPlugin.

class_name RuntimeRagdollGenerator
extends RefCounted

const CHAIN_NEXT: Dictionary = {
	"hips": "spine",
	"spine": "spine1",
	"spine1": "spine2",
	"spine2": "head",
	"head": "",
	"left_shoulder": "left_upper_arm",
	"left_upper_arm": "left_forearm",
	"left_forearm": "left_hand",
	"left_hand": "",
	"right_shoulder": "right_upper_arm",
	"right_upper_arm": "right_forearm",
	"right_forearm": "right_hand",
	"right_hand": "",
	"left_upper_leg": "left_lower_leg",
	"left_lower_leg": "left_foot",
	"left_foot": "",
	"right_upper_leg": "right_lower_leg",
	"right_lower_leg": "right_foot",
	"right_foot": "",
}

const MIRROR_PART: Dictionary = {
	"right_shoulder": "left_shoulder",
	"right_upper_arm": "left_upper_arm",
	"right_forearm": "left_forearm",
	"right_hand": "left_hand",
	"right_upper_leg": "left_upper_leg",
	"right_lower_leg": "left_lower_leg",
	"right_foot": "left_foot",
}

const RAGDOLL_PARTS: Array[String] = [
	"hips", "spine", "spine1", "spine2", "head",
	"left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
	"right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
	"left_upper_leg", "left_lower_leg", "left_foot",
	"right_upper_leg", "right_lower_leg", "right_foot",
]

const SHAPE_CONFIG: Dictionary = {
	"hips": {"shape": "box"},
	"spine": {"shape": "box"},
	"spine1": {"shape": "box"},
	"spine2": {"shape": "box"},
	"head": {"shape": "capsule", "radius_factor": 0.5},
	"left_shoulder": {"shape": "capsule", "radius_factor": 0.3},
	"right_shoulder": {"shape": "capsule", "radius_factor": 0.3},
	"left_upper_arm": {"shape": "capsule", "radius_factor": 0.22},
	"right_upper_arm": {"shape": "capsule", "radius_factor": 0.22},
	"left_forearm": {"shape": "capsule", "radius_factor": 0.2},
	"right_forearm": {"shape": "capsule", "radius_factor": 0.2},
	"left_hand": {"shape": "box"},
	"right_hand": {"shape": "box"},
	"left_upper_leg": {"shape": "capsule", "radius_factor": 0.22},
	"right_upper_leg": {"shape": "capsule", "radius_factor": 0.22},
	"left_lower_leg": {"shape": "capsule", "radius_factor": 0.18},
	"right_lower_leg": {"shape": "capsule", "radius_factor": 0.18},
	"left_foot": {"shape": "box"},
	"right_foot": {"shape": "box"},
}

const TORSO_SHAPE_XZ_SCALE: float = 1.6
const TOTAL_BODY_MASS: float = 75.0

const MASS_FRACTION: Dictionary = {
	"hips": 0.1420,
	"spine": 0.1306,
	"spine1": 0.0979,
	"spine2": 0.0979,
	"head": 0.0826,
	"left_shoulder": 0.0155,
	"right_shoulder": 0.0155,
	"left_upper_arm": 0.0270,
	"right_upper_arm": 0.0270,
	"left_forearm": 0.0187,
	"right_forearm": 0.0187,
	"left_hand": 0.0065,
	"right_hand": 0.0065,
	"left_upper_leg": 0.1050,
	"right_upper_leg": 0.1050,
	"left_lower_leg": 0.0475,
	"right_lower_leg": 0.0475,
	"left_foot": 0.0143,
	"right_foot": 0.0143,
}

const JOINT_CONFIG: Dictionary = {
	"hips": {"type": 0},
	"spine": {
		"type": 5,
		"x": {"lower": -20.0, "upper": 20.0},
		"y": {"lower": -20.0, "upper": 20.0},
		"z": {"lower": -20.0, "upper": 20.0},
	},
	"spine1": {
		"type": 5,
		"x": {"lower": -15.0, "upper": 15.0},
		"y": {"lower": -10.0, "upper": 10.0},
		"z": {"lower": -15.0, "upper": 15.0},
	},
	"spine2": {
		"type": 5,
		"x": {"lower": -15.0, "upper": 15.0},
		"y": {"lower": -10.0, "upper": 10.0},
		"z": {"lower": -15.0, "upper": 15.0},
	},
	"head": {
		"type": 5,
		"x": {"lower": -40.0, "upper": 40.0},
		"y": {"lower": -50.0, "upper": 50.0},
		"z": {"lower": -30.0, "upper": 30.0},
	},
	"left_shoulder": {
		"type": 5,
		"x": {"lower": -10.0, "upper": 10.0},
		"y": {"lower": -10.0, "upper": 10.0},
		"z": {"lower": -10.0, "upper": 10.0},
	},
	"right_shoulder": {
		"type": 5,
		"x": {"lower": -10.0, "upper": 10.0},
		"y": {"lower": -10.0, "upper": 10.0},
		"z": {"lower": -10.0, "upper": 10.0},
	},
	"left_upper_arm": {
		"type": 5,
		"x": {"lower": -70.0, "upper": 70.0},
		"y": {"lower": -45.0, "upper": 45.0},
		"z": {"lower": -70.0, "upper": 70.0},
	},
	"right_upper_arm": {
		"type": 5,
		"x": {"lower": -70.0, "upper": 70.0},
		"y": {"lower": -45.0, "upper": 45.0},
		"z": {"lower": -70.0, "upper": 70.0},
	},
	"left_forearm": {
		"type": 3,
		"lower": -5.0, "upper": 140.0,
		"hinge_body_axis": "z",
	},
	"right_forearm": {
		"type": 3,
		"lower": -5.0, "upper": 140.0,
		"hinge_body_axis": "z",
	},
	"left_hand": {
		"type": 5,
		"x": {"lower": -25.0, "upper": 25.0},
		"y": {"lower": -15.0, "upper": 15.0},
		"z": {"lower": -25.0, "upper": 25.0},
	},
	"right_hand": {
		"type": 5,
		"x": {"lower": -25.0, "upper": 25.0},
		"y": {"lower": -15.0, "upper": 15.0},
		"z": {"lower": -25.0, "upper": 25.0},
	},
	"left_upper_leg": {
		"type": 5,
		"x": {"lower": -50.0, "upper": 50.0},
		"y": {"lower": -30.0, "upper": 30.0},
		"z": {"lower": -50.0, "upper": 50.0},
	},
	"right_upper_leg": {
		"type": 5,
		"x": {"lower": -50.0, "upper": 50.0},
		"y": {"lower": -30.0, "upper": 30.0},
		"z": {"lower": -50.0, "upper": 50.0},
	},
	"left_lower_leg": {
		"type": 3,
		"lower": -5.0, "upper": 140.0,
		"hinge_body_axis": "x",
	},
	"right_lower_leg": {
		"type": 3,
		"lower": -5.0, "upper": 140.0,
		"hinge_body_axis": "x",
	},
	"left_foot": {
		"type": 5,
		"x": {"lower": -25.0, "upper": 25.0},
		"y": {"lower": -15.0, "upper": 15.0},
		"z": {"lower": -25.0, "upper": 25.0},
	},
	"right_foot": {
		"type": 5,
		"x": {"lower": -25.0, "upper": 25.0},
		"y": {"lower": -15.0, "upper": 15.0},
		"z": {"lower": -25.0, "upper": 25.0},
	},
}

const KNOWN_PREFIXES: Array[String] = [
	"mixamorig8:", "mixamorig:", "mixamorig8_", "mixamorig_",
	"bip01_", "bip001_", "bip01 ", "bip001 ",
	"cc_base_",
	"def_", "deform_", "def.", "deform.",
	"j_", "jnt_", "bone_",
	"character1:", "character1_",
	"metarig_",
]

const SLOT_TO_INTERNAL: Dictionary = {
	"pelvis": "hips",
	"left_hips": "left_upper_leg",
	"left_knee": "left_lower_leg",
	"left_foot": "left_foot",
	"right_hips": "right_upper_leg",
	"right_knee": "right_lower_leg",
	"right_foot": "right_foot",
	"left_arm": "left_upper_arm",
	"left_elbow": "left_forearm",
	"left_hand": "left_hand",
	"right_arm": "right_upper_arm",
	"right_elbow": "right_forearm",
	"right_hand": "right_hand",
	"middle_spine": "spine",
	"head": "head",
}

static func generate_ragdoll(skeleton: Skeleton3D, config: Dictionary = {}) -> PhysicalBoneSimulator3D:
	if not skeleton or not is_instance_valid(skeleton):
		push_error("[RuntimeRagdollGenerator] Skeleton3D nulo o inválido.")
		return null

	print("[RuntimeRagdollGenerator] Generando esqueleto físico para: ", skeleton.name)

	var total_mass: float = config.get("total_mass", TOTAL_BODY_MASS)
	var strength: float = config.get("strength", 0.0)
	var flip_forward: bool = config.get("flip_forward", false)

	var bone_map: Dictionary = {}
	var slots = config.get("slots", {})
	if slots.size() > 0:
		for slot_key in slots:
			var bone_name: String = slots[slot_key]
			if bone_name.is_empty():
				continue
			var b_idx = skeleton.find_bone(bone_name)
			if b_idx != -1:
				var internal_part = SLOT_TO_INTERNAL.get(slot_key, slot_key)
				bone_map[internal_part] = b_idx
	else:
		bone_map = _identify_ragdoll_bones(skeleton)

	if bone_map.is_empty():
		push_warning("[RuntimeRagdollGenerator] No se pudieron clasificar huesos para el ragdoll.")
		return null

	print("[RuntimeRagdollGenerator] %d huesos identificados para la simulación ragdoll." % bone_map.size())

	# Eliminar simuladores previos si existieran
	var old_sims: Array[Node] = []
	for child in skeleton.get_children():
		if child is PhysicalBoneSimulator3D:
			old_sims.append(child)
	for old in old_sims:
		skeleton.remove_child(old)
		old.queue_free()

	var measurements = _compute_measurements(skeleton, bone_map)

	var simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)

	var total_fraction: float = 0.0
	for part in bone_map:
		total_fraction += MASS_FRACTION.get(part, 0.05)
	if total_fraction <= 0.001:
		total_fraction = 1.0

	var shape_cache: Dictionary = {}
	var created_count = 0
	for part in RAGDOLL_PARTS:
		if part not in bone_map:
			continue
		if part not in measurements:
			continue

		var bone_idx: int = bone_map[part]
		var bone_name: String = skeleton.get_bone_name(bone_idx)
		var m: Dictionary = measurements[part]
		var mass_share: float = MASS_FRACTION.get(part, 0.05) / total_fraction

		var pb = _create_physical_bone(skeleton, bone_name, part, m, shape_cache, total_mass, mass_share, strength, flip_forward)
		simulator.add_child(pb)
		created_count += 1

	print("[RuntimeRagdollGenerator] Ragdoll generado con éxito (%d huesos físicos creados)." % created_count)
	return simulator

static func _identify_ragdoll_bones(skeleton: Skeleton3D) -> Dictionary:
	var bone_map: Dictionary = {}
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		var part = _classify_bone(bone_name)
		if not part.is_empty() and part not in bone_map:
			bone_map[part] = i
	return bone_map

static func _classify_bone(bone_name: String) -> String:
	var n = _strip_known_prefix(bone_name).to_lower()

	var side = ""
	var stripped = n

	if "left" in n:
		side = "left"
		stripped = n.replace("left", "")
	elif "right" in n:
		side = "right"
		stripped = n.replace("right", "")
	elif n.begins_with("l_") or n.begins_with("l.") or n.begins_with("l ") or n.begins_with("l-"):
		side = "left"
		stripped = n.substr(2)
	elif n.begins_with("r_") or n.begins_with("r.") or n.begins_with("r ") or n.begins_with("r-"):
		side = "right"
		stripped = n.substr(2)
	elif n.ends_with("_l") or n.ends_with(".l") or n.ends_with(" l") or n.ends_with("-l"):
		side = "left"
		stripped = n.substr(0, n.length() - 2)
	elif n.ends_with("_r") or n.ends_with(".r") or n.ends_with(" r") or n.ends_with("-r"):
		side = "right"
		stripped = n.substr(0, n.length() - 2)

	var clean = stripped.replace("_", "").replace(".", "").replace(" ", "").replace("-", "").replace(":", "")

	if clean in ["hips", "hip", "pelvis", "root"]:
		return "hips"
	if clean in ["spine2", "spine02", "chest"]:
		return "spine2"
	if clean in ["spine1", "spine01"]:
		return "spine1"
	if clean in ["spine", "spine0", "spine00", "abdomen"]:
		return "spine"
	if clean in ["head", "skull", "cranium"]:
		return "head"

	if side.is_empty():
		return ""

	if clean in ["shoulder", "clavicle"]:
		return side + "_shoulder"
	if clean in ["forearm", "lowerarm", "elbow", "radius", "ulna"]:
		return side + "_forearm"
	if clean in ["arm", "upperarm", "uparm", "bicep", "humerus"]:
		return side + "_upper_arm"
	if clean in ["hand", "wrist", "palm"]:
		return side + "_hand"
	if clean in ["upleg", "upperleg", "thigh", "femur"]:
		return side + "_upper_leg"
	if clean in ["leg", "lowerleg", "calf", "shin", "knee", "tibia"]:
		return side + "_lower_leg"
	if clean in ["foot", "ankle", "heel"]:
		return side + "_foot"

	return ""

static func _strip_known_prefix(bone_name: String) -> String:
	return strip_bone_prefix(bone_name)

static func strip_bone_prefix(bone_name: String) -> String:
	if bone_name.is_empty():
		return ""

	var s: String = bone_name

	for sep in [":", "|", "/"]:
		var last_idx: int = s.rfind(sep)
		if last_idx != -1 and last_idx < s.length() - 1:
			s = s.substr(last_idx + 1)

	var mixamo_regex = RegEx.create_from_string("^(?i)mixamo(?:rig)?\\d*[_.:\\s-]*")
	if mixamo_regex:
		var m = mixamo_regex.search(s)
		if m and m.get_end() > 0 and m.get_end() < s.length():
			return s.substr(m.get_end())

	var biped_regex = RegEx.create_from_string("^(?i)(?:valvebiped\\.)?(?:bip|biped)\\d*[_.:\\s-]*")
	if biped_regex:
		var m = biped_regex.search(s)
		if m and m.get_end() > 0 and m.get_end() < s.length():
			return s.substr(m.get_end())

	var tech_regex = RegEx.create_from_string("^(?i)(?:cc_base|def|deform|mch|org|vrm|metarig|rig\\d*|j|jnt|bone|character\\d*|char\\d*|actor\\d*|player\\d*|bot\\d*|npc\\d*|model\\d*)[_.:\\s-]+")
	if tech_regex:
		var m = tech_regex.search(s)
		if m and m.get_end() > 0 and m.get_end() < s.length():
			return s.substr(m.get_end())

	var lower_s = s.to_lower()
	for p in KNOWN_PREFIXES:
		if lower_s.begins_with(p):
			s = s.substr(p.length())
			lower_s = s.to_lower()
			break

	for delim in ["_", "-"]:
		if delim in s:
			var parts = s.split(delim)
			if parts.size() > 1:
				for i in range(parts.size()):
					var seg = parts[i].to_lower()
					if _is_bone_keyword(seg):
						if i > 0:
							var remaining: PackedStringArray = []
							for j in range(i, parts.size()):
								remaining.append(parts[j])
							return delim.join(remaining)
						break

	return s

static func _is_bone_keyword(seg: String) -> bool:
	if seg.is_empty():
		return false
	if seg == "l" or seg == "r":
		return true
	if seg.begins_with("left") or seg.begins_with("right"):
		return true
	if seg.begins_with("upper") or seg.begins_with("up") or seg.begins_with("lower") or seg.begins_with("low") or seg.begins_with("mid") or seg.begins_with("middle"):
		return true
	if seg.begins_with("hip") or seg.begins_with("pelvis") or seg.begins_with("root"):
		return true
	if seg.begins_with("spine") or seg.begins_with("chest") or seg.begins_with("torso") or seg.begins_with("abdomen"):
		return true
	if seg.begins_with("neck") or seg.begins_with("head") or seg.begins_with("skull") or seg.begins_with("cranium"):
		return true
	if seg.begins_with("shoulder") or seg.begins_with("clavicle"):
		return true
	if seg.begins_with("arm") or seg.begins_with("forearm") or seg.begins_with("elbow") or seg.begins_with("hand") or seg.begins_with("wrist") or seg.begins_with("palm"):
		return true
	if seg.begins_with("leg") or seg.begins_with("thigh") or seg.begins_with("calf") or seg.begins_with("shin") or seg.begins_with("knee") or seg.begins_with("foot") or seg.begins_with("ankle") or seg.begins_with("heel") or seg.begins_with("toe"):
		return true
	if seg.begins_with("femur") or seg.begins_with("tibia") or seg.begins_with("radius") or seg.begins_with("ulna") or seg.begins_with("humerus"):
		return true
	return false

static func _compute_measurements(skeleton: Skeleton3D, bone_map: Dictionary) -> Dictionary:
	var results: Dictionary = {}

	var hip_width: float = 0.0
	var shoulder_width: float = 0.0

	if "left_upper_leg" in bone_map and "right_upper_leg" in bone_map:
		var ll_pos = skeleton.get_bone_global_rest(bone_map["left_upper_leg"]).origin
		var rl_pos = skeleton.get_bone_global_rest(bone_map["right_upper_leg"]).origin
		hip_width = ll_pos.distance_to(rl_pos)

	if "left_shoulder" in bone_map and "right_shoulder" in bone_map:
		var ls_pos = skeleton.get_bone_global_rest(bone_map["left_shoulder"]).origin
		var rs_pos = skeleton.get_bone_global_rest(bone_map["right_shoulder"]).origin
		shoulder_width = ls_pos.distance_to(rs_pos)
	elif "left_upper_arm" in bone_map and "right_upper_arm" in bone_map:
		var la_pos = skeleton.get_bone_global_rest(bone_map["left_upper_arm"]).origin
		var ra_pos = skeleton.get_bone_global_rest(bone_map["right_upper_arm"]).origin
		shoulder_width = la_pos.distance_to(ra_pos)

	for part in RAGDOLL_PARTS:
		if part not in bone_map:
			continue

		var bone_idx: int = bone_map[part]
		var target = _get_bone_target(skeleton, bone_idx, part, bone_map)

		results[part] = {
			"bone_idx": bone_idx,
			"length": target["length"],
			"target_global": target["target_global"],
			"hip_width": hip_width,
			"shoulder_width": shoulder_width,
		}

	return results

static func _resolve_chain_target(part: String, bone_map: Dictionary) -> String:
	if part == "hips":
		for candidate in ["spine", "spine1", "spine2", "head"]:
			if candidate in bone_map:
				return candidate
	elif part == "spine":
		for candidate in ["spine1", "spine2", "head"]:
			if candidate in bone_map:
				return candidate
	elif part == "spine1":
		for candidate in ["spine2", "head"]:
			if candidate in bone_map:
				return candidate
	elif part == "spine2":
		if "head" in bone_map:
			return "head"
	elif part == "left_upper_arm":
		if "left_forearm" in bone_map:
			return "left_forearm"
	elif part == "left_forearm":
		if "left_hand" in bone_map:
			return "left_hand"
	elif part == "right_upper_arm":
		if "right_forearm" in bone_map:
			return "right_forearm"
	elif part == "right_forearm":
		if "right_hand" in bone_map:
			return "right_hand"
	elif part == "left_upper_leg":
		if "left_lower_leg" in bone_map:
			return "left_lower_leg"
	elif part == "left_lower_leg":
		if "left_foot" in bone_map:
			return "left_foot"
	elif part == "right_upper_leg":
		if "right_lower_leg" in bone_map:
			return "right_lower_leg"
	elif part == "right_lower_leg":
		if "right_foot" in bone_map:
			return "right_foot"
	return CHAIN_NEXT.get(part, "")

static func _get_bone_target(skeleton: Skeleton3D, bone_idx: int, part: String, bone_map: Dictionary) -> Dictionary:
	var bone_pos = skeleton.get_bone_global_rest(bone_idx).origin
	var children = skeleton.get_bone_children(bone_idx)

	if part.ends_with("_hand"):
		var hand_result = _get_hand_bone_target(skeleton, bone_idx)
		if hand_result["length"] > 0.001:
			return hand_result

	var chain_child_part: String = _resolve_chain_target(part, bone_map)
	if not chain_child_part.is_empty() and chain_child_part in bone_map:
		var chain_bone_idx: int = bone_map[chain_child_part]

		if children.has(chain_bone_idx):
			var cp = skeleton.get_bone_global_rest(chain_bone_idx).origin
			return {"length": bone_pos.distance_to(cp), "target_global": cp}

		for child_idx in children:
			if _is_ancestor_of(skeleton, child_idx, chain_bone_idx):
				var cp = skeleton.get_bone_global_rest(child_idx).origin
				var dist = bone_pos.distance_to(cp)
				if dist > 0.001:
					return {"length": dist, "target_global": cp}

	if children.size() > 0:
		var cp = skeleton.get_bone_global_rest(children[0]).origin
		var dist = bone_pos.distance_to(cp)
		if dist > 0.001:
			return {"length": dist, "target_global": cp}

	var parent_idx = skeleton.get_bone_parent(bone_idx)
	if parent_idx >= 0:
		var pp = skeleton.get_bone_global_rest(parent_idx).origin
		var dir = bone_pos - pp
		var pl = dir.length()
		if pl > 0.001:
			var est_len = pl * 0.5
			return {"length": est_len, "target_global": bone_pos + dir.normalized() * est_len}

	return {"length": 0.1, "target_global": bone_pos + Vector3.UP * 0.1}

static func _get_hand_bone_target(skeleton: Skeleton3D, hand_bone_idx: int) -> Dictionary:
	var hand_pos = skeleton.get_bone_global_rest(hand_bone_idx).origin
	var best_dist: float = 0.0
	var best_tip: Vector3 = hand_pos

	var tip_bones: Array = []
	_collect_leaf_bones(skeleton, hand_bone_idx, tip_bones)

	for tip_idx in tip_bones:
		var tip_pos = skeleton.get_bone_global_rest(tip_idx).origin
		var dist = hand_pos.distance_to(tip_pos)
		if dist > best_dist:
			best_dist = dist
			best_tip = tip_pos

	if best_dist > 0.001:
		for tip_idx in tip_bones:
			var tip_pos = skeleton.get_bone_global_rest(tip_idx).origin
			if hand_pos.distance_to(tip_pos) >= best_dist - 0.0001:
				var tip_parent = skeleton.get_bone_parent(tip_idx)
				if tip_parent >= 0:
					var parent_pos = skeleton.get_bone_global_rest(tip_parent).origin
					var last_bone_dir = tip_pos - parent_pos
					var last_bone_len = last_bone_dir.length()
					if last_bone_len > 0.001:
						var extended_tip = tip_pos + last_bone_dir.normalized() * last_bone_len
						best_dist = hand_pos.distance_to(extended_tip)
						best_tip = extended_tip
				break

	return {"length": best_dist, "target_global": best_tip}

static func _collect_leaf_bones(skeleton: Skeleton3D, bone_idx: int, result: Array) -> void:
	var children = skeleton.get_bone_children(bone_idx)
	if children.size() == 0:
		result.append(bone_idx)
		return
	for child_idx in children:
		_collect_leaf_bones(skeleton, child_idx, result)

static func _is_ancestor_of(skeleton: Skeleton3D, ancestor_idx: int, descendant_idx: int) -> bool:
	var current = descendant_idx
	while current >= 0:
		current = skeleton.get_bone_parent(current)
		if current == ancestor_idx:
			return true
	return false

static func _create_physical_bone(skeleton: Skeleton3D, bone_name: String, part: String, m: Dictionary, shape_cache: Dictionary, total_mass: float = 75.0, mass_share: float = 0.1, strength: float = 0.0, flip_forward: bool = false) -> PhysicalBone3D:
	var pb = PhysicalBone3D.new()
	pb.bone_name = bone_name
	pb.name = "PhysicalBone_" + bone_name

	var bone_idx: int = m["bone_idx"]
	var bone_length: float = m["length"]
	var target_global: Vector3 = m["target_global"]

	pb.body_offset = _compute_body_offset(skeleton, bone_idx, target_global, flip_forward)
	pb.mass = maxf(total_mass * mass_share, 0.05)
	pb.linear_damp = 0.5
	pb.angular_damp = 3.0

	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var mirror: String = MIRROR_PART.get(part, "")
	if not mirror.is_empty() and mirror in shape_cache:
		col.shape = shape_cache[mirror]
	else:
		var shape = _create_shape(part, bone_length, m)
		col.shape = shape
		shape_cache[part] = shape
	pb.add_child(col)

	_configure_joint(pb, part, skeleton, bone_idx, strength, flip_forward)
	return pb

static func _compute_body_offset(skeleton: Skeleton3D, bone_idx: int, target_global: Vector3, flip_forward: bool = false) -> Transform3D:
	var bone_global = skeleton.get_bone_global_rest(bone_idx)
	var bone_pos = bone_global.origin
	var dir_global = target_global - bone_pos
	var length = dir_global.length()

	if length < 0.001:
		return Transform3D.IDENTITY

	var dir_norm = dir_global.normalized()
	var bone_basis_inv = bone_global.basis.inverse()
	var dir_local = (bone_basis_inv * dir_norm).normalized()
	var center_local = dir_local * (length * 0.5)

	var y_axis = dir_local
	var z_axis: Vector3
	if abs(y_axis.dot(Vector3.UP)) < 0.95:
		z_axis = y_axis.cross(Vector3.UP).normalized()
	elif abs(y_axis.dot(Vector3.RIGHT)) < 0.95:
		z_axis = y_axis.cross(Vector3.RIGHT).normalized()
	else:
		z_axis = y_axis.cross(Vector3.FORWARD).normalized()
	var x_axis = y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()

	if flip_forward:
		x_axis = -x_axis
		z_axis = -z_axis

	return Transform3D(Basis(x_axis, y_axis, z_axis), center_local)

static func _create_shape(part: String, bone_length: float, m: Dictionary) -> Shape3D:
	var cfg: Dictionary = SHAPE_CONFIG.get(part, {"shape": "capsule", "radius_factor": 0.2})

	match cfg.get("shape", "capsule"):
		"box":
			return _create_box_shape(part, bone_length, m)
		_:
			return _create_capsule_shape(bone_length, cfg.get("radius_factor", 0.2))

static func _create_capsule_shape(bone_length: float, radius_factor: float) -> CapsuleShape3D:
	var capsule = CapsuleShape3D.new()
	var effective_length = maxf(bone_length, 0.02)
	capsule.radius = maxf(effective_length * radius_factor, 0.005)
	capsule.height = maxf(effective_length, capsule.radius * 2.0 + 0.01)
	return capsule

static func _create_box_shape(part: String, bone_length: float, m: Dictionary) -> BoxShape3D:
	var box = BoxShape3D.new()
	var hw: float = m.get("hip_width", 0.0)
	var sw: float = m.get("shoulder_width", 0.0)
	var bl = maxf(bone_length, 0.02)

	if part == "hips":
		var w = hw if hw > 0.01 else bl * 1.0
		box.size = Vector3(w * TORSO_SHAPE_XZ_SCALE, bl, w * 0.5 * TORSO_SHAPE_XZ_SCALE)
	elif part == "spine":
		var w = hw * 0.9 if hw > 0.01 else bl * 1.0
		box.size = Vector3(w * TORSO_SHAPE_XZ_SCALE, bl, w * 0.55 * TORSO_SHAPE_XZ_SCALE)
	elif part == "spine1":
		var w: float
		if sw > 0.01 and hw > 0.01:
			w = lerpf(hw, sw, 0.5)
		elif sw > 0.01:
			w = sw * 0.7
		elif hw > 0.01:
			w = hw
		else:
			w = bl * 1.0
		box.size = Vector3(w * TORSO_SHAPE_XZ_SCALE, bl, w * 0.55 * TORSO_SHAPE_XZ_SCALE)
	elif part == "spine2":
		var w: float
		if sw > 0.01:
			w = sw * 0.85
		elif hw > 0.01:
			w = hw * 1.1
		else:
			w = bl * 1.0
		box.size = Vector3(w * TORSO_SHAPE_XZ_SCALE, bl, w * 0.55 * TORSO_SHAPE_XZ_SCALE)
	elif part.ends_with("_hand"):
		box.size = Vector3(bl * 0.6, bl, bl * 0.3)
	elif part.ends_with("_foot"):
		box.size = Vector3(bl * 0.45, bl * 0.8, bl * 0.25)
	else:
		box.size = Vector3(bl * 0.5, bl, bl * 0.3)

	return box

static func _configure_joint(pb: PhysicalBone3D, part: String, skeleton: Skeleton3D, bone_idx: int, strength: float = 0.0, flip_forward: bool = false) -> void:
	var cfg: Dictionary = JOINT_CONFIG.get(part, {"type": 5, "x": {"lower": 0.0, "upper": 0.0}, "y": {"lower": 0.0, "upper": 0.0}, "z": {"lower": 0.0, "upper": 0.0}})
	var jtype: int = cfg.get("type", 5)
	pb.joint_type = jtype

	match jtype:
		0:
			pass
		3:
			var hinge_body_axis: String = cfg.get("hinge_body_axis", "z")
			pb.joint_offset = _compute_hinge_joint_offset(pb.body_offset, hinge_body_axis, flip_forward)
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_lower", cfg.get("lower", -5.0))
			pb.set("joint_constraints/angular_limit_upper", cfg.get("upper", 140.0))
			pb.set("joint_constraints/angular_limit_bias", 0.3)
			pb.set("joint_constraints/angular_limit_softness", 0.9)
			pb.set("joint_constraints/angular_limit_relaxation", 1.0)
		5:
			for axis in ["x", "y", "z"]:
				var limits: Dictionary = cfg.get(axis, {"lower": 0.0, "upper": 0.0})
				_configure_6dof_axis(pb, axis, limits.get("lower", 0.0), limits.get("upper", 0.0), strength)

static func _compute_hinge_joint_offset(body_off: Transform3D, hinge_body_axis: String, flip_forward: bool = false) -> Transform3D:
	var rotation: Basis
	match hinge_body_axis:
		"x":
			rotation = Basis(Vector3(0, 1, 0), PI / 2.0)
		"y":
			rotation = Basis(Vector3(1, 0, 0), -PI / 2.0)
		_:
			rotation = Basis.IDENTITY
	if flip_forward:
		rotation = rotation.rotated(Vector3(0, 1, 0), PI)
	return Transform3D(body_off.basis * rotation, Vector3.ZERO)

static func _configure_6dof_axis(pb: PhysicalBone3D, axis: String, lower_deg: float, upper_deg: float, strength: float = 0.0) -> void:
	var p = "joint_constraints/" + axis + "/"

	pb.set(p + "linear_limit_enabled", true)
	pb.set(p + "linear_limit_upper", 0.0)
	pb.set(p + "linear_limit_lower", 0.0)
	pb.set(p + "linear_limit_softness", 0.7)
	pb.set(p + "linear_restitution", 0.5)
	pb.set(p + "linear_damping", 1.0)
	pb.set(p + "linear_spring_enabled", false)
	pb.set(p + "linear_spring_stiffness", 0.0)
	pb.set(p + "linear_spring_damping", 0.0)
	pb.set(p + "linear_equilibrium_point", 0.0)

	pb.set(p + "angular_limit_enabled", true)
	pb.set(p + "angular_limit_upper", upper_deg)
	pb.set(p + "angular_limit_lower", lower_deg)
	pb.set(p + "angular_limit_softness", 0.5)
	pb.set(p + "angular_restitution", 0.0)
	pb.set(p + "angular_damping", 1.0)
	pb.set(p + "erp", 0.5)
	if strength > 0.0:
		pb.set(p + "angular_spring_enabled", true)
		pb.set(p + "angular_spring_stiffness", strength * 100.0)
		pb.set(p + "angular_spring_damping", strength * 10.0)
		pb.set(p + "angular_equilibrium_point", 0.0)
	else:
		pb.set(p + "angular_spring_enabled", false)
		pb.set(p + "angular_spring_stiffness", 0.0)
		pb.set(p + "angular_spring_damping", 0.0)
		pb.set(p + "angular_equilibrium_point", 0.0)
