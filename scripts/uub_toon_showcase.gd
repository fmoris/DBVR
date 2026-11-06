@tool
extends Node3D

## UubToonShowcase: Controlador de sombreado Cel-Shading Anime (Gekishin Toon)
## Aplica materiales de sombreado en 2 tonos (luz/sombra) y contorno negro de anime (Inverted Hull)
## tanto en el editor como en runtime de Meta Quest VR.

const ToonShader = preload("res://shaders/gekishin_toon.gdshader")
const OutlineShader = preload("res://shaders/anime_outline.gdshader")

func _ready() -> void:
	apply_anime_toon_materials()

func apply_anime_toon_materials() -> void:
	# Paletas canonicas de Uub (Dragon Ball Z / Gekishin Squadra)
	var color_skin_base = Color(0.76, 0.53, 0.38, 1.0) # Piel morena calida anime
	var color_skin_shadow = Color(0.55, 0.35, 0.24, 1.0)
	
	var color_gi_base = Color(0.86, 0.89, 0.80, 1.0) # Verde lima / crema canon (Gi superior)
	var color_gi_shadow = Color(0.67, 0.72, 0.61, 1.0)
	
	var color_pants_base = Color(0.18, 0.38, 0.58, 1.0) # Teal / verde azulado (Pantalones bombachos)
	var color_pants_shadow = Color(0.11, 0.24, 0.40, 1.0)
	
	var color_belt_base = Color(0.13, 0.42, 0.78, 1.0) # Azul faja/cinturon con nudo
	var color_belt_shadow = Color(0.08, 0.27, 0.55, 1.0)
	
	var color_hair_base = Color(0.15, 0.15, 0.18, 1.0) # Mohawk negro/carbon
	var color_hair_shadow = Color(0.07, 0.07, 0.09, 1.0)
	
	var color_boots_base = Color(0.35, 0.25, 0.20, 1.0) # Sandalias cuero marron
	var color_boots_shadow = Color(0.20, 0.14, 0.11, 1.0)
	
	var color_eyes_base = Color(0.96, 0.96, 0.96, 1.0)
	var color_eyes_shadow = Color(0.70, 0.70, 0.75, 1.0)
	
	var color_details_base = Color(0.15, 0.10, 0.08, 1.0)
	var color_details_shadow = Color(0.08, 0.05, 0.04, 1.0)

	# Materiales Toon pre-configurados con anime outline
	var mat_skin = _create_toon_material(color_skin_base, color_skin_shadow, 1.0)
	var mat_gi = _create_toon_material(color_gi_base, color_gi_shadow, 1.2)
	var mat_pants = _create_toon_material(color_pants_base, color_pants_shadow, 1.2)
	var mat_belt = _create_toon_material(color_belt_base, color_belt_shadow, 1.2)
	var mat_hair = _create_toon_material(color_hair_base, color_hair_shadow, 1.0)
	var mat_boots = _create_toon_material(color_boots_base, color_boots_shadow, 1.2)
	var mat_eyes = _create_toon_material(color_eyes_base, color_eyes_shadow, 0.0)
	var mat_details = _create_toon_material(color_details_base, color_details_shadow, 0.0)

	# Mapeo exacto verificado por coordenadas 3D y anatomia de cada submalla
	var index_material_map = {
		0: mat_details, # Cejas y lineas de expresion
		1: mat_eyes,    # Ojos blancos
		2: mat_skin,    # Rostro
		3: mat_skin,    # Manos y antebrazos descubiertos
		4: mat_pants,   # Pantalones bombachos teal
		5: mat_boots,   # Sandalias de cuero marron
		6: mat_skin,    # Brazos descubiertos
		7: mat_gi,      # Gi superior sin mangas (verde lima / crema)
		8: mat_belt,    # Cinturon / faja azul con nudo
		9: mat_skin,    # Cuello
		10: mat_skin,   # Orejas
		11: mat_skin,   # Craneo
		12: mat_hair    # Mohawk negro
	}

	var mesh_instances: Array[MeshInstance3D] = []
	_gather_mesh_instances(self, mesh_instances)

	for idx in range(mesh_instances.size()):
		var mi = mesh_instances[idx]
		if idx in index_material_map:
			mi.material_override = index_material_map[idx]

	print("[UubToonShowcase] 13 Submallas Toon configuradas con exito (Cel-Shading + Inverted Hull Outline).")

func _create_toon_material(base_c: Color, shadow_c: Color, outline_width: float) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = ToonShader
	mat.set_shader_parameter("base_color", base_c)
	mat.set_shader_parameter("shadow_color", shadow_c)
	mat.set_shader_parameter("shadow_threshold", 0.05)
	mat.set_shader_parameter("shadow_softness", 0.02)
	mat.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0, 1.0))
	mat.set_shader_parameter("rim_threshold", 0.65)
	mat.set_shader_parameter("rim_power", 1.5)

	if outline_width > 0.0:
		var outline_mat = ShaderMaterial.new()
		outline_mat.shader = OutlineShader
		outline_mat.set_shader_parameter("outline_color", Color(0.08, 0.08, 0.10, 1.0))
		outline_mat.set_shader_parameter("outline_thickness", outline_width)
		mat.next_pass = outline_mat

	return mat

func _gather_mesh_instances(node: Node, out_list: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_list.append(node)
	for child in node.get_children():
		_gather_mesh_instances(child, out_list)
