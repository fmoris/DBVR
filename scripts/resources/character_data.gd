class_name CharacterData
extends Resource

## Multiplicadores universales por Tier equilibrados para combate VR (Fase 1..4)
const STANDARD_TIER_MULTIPLIERS: Array[float] = [2.0, 3.5, 5.0, 8.0]

@export var character_name: String = ""
@export var base_np: float = 9000.0
@export var max_np: float = 20000.0
@export var base_ki: float = 100.0
@export var scale_factor: float = 1.0 # Para definir estatura (Goku: 1.0, Vegeta: 0.94)
@export var model_asset_scale: float = 1.0 # Para compensar la escala de importación de la malla (ej. Vegeta: 8.291948)

@export_file("*.glb") var body_model_path: String = ""
@export_file("*.glb") var hands_model_path: String = ""

@export_group("Selector e Info API")
@export var api_id: int = 0
@export var race: String = "Saiyan"
@export var gender: String = "Male"
@export var affiliation: String = "Z Fighter"
@export var canonical_ki_text: String = ""
@export var canonical_max_ki_text: String = ""
@export_multiline var description: String = ""
@export var origin_planet_name: String = ""
@export_multiline var origin_planet_description: String = ""
@export_file("*.webp", "*.png") var portrait_image_path: String = ""
@export_file("*.webp", "*.png") var origin_planet_image_path: String = ""
@export var api_image_url: String = ""

@export var powers: Array[Resource] = []
@export var transformations: Array[Resource] = []


static func get_standard_tier_multiplier(tier_index: int) -> float:
	if tier_index >= 0 and tier_index < STANDARD_TIER_MULTIPLIERS.size():
		return STANDARD_TIER_MULTIPLIERS[tier_index]
	return 1.0
