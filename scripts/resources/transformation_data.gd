class_name TransformationData
extends Resource

@export var form_name: String = "" # Nombre de la transformación (ej: SSJ, SSJ2, Super Vegeta, SSB, Ultra Instinto)
@export var tier_level: int = 1 # Tier canónico 1..4 del sistema equilibrado
@export var np_multiplier: float = 2.0 # Multiplica el NP máximo y aumenta el daño
@export var ki_drain_per_sec: float = 1.0 # Costo por segundo para mantener la transformación
@export var aura_color: Color = Color(1, 0.8, 0, 1) # Color del aura de energía del personaje

@export_group("Modelos Opcionales por Transformación")
@export_file("*.glb") var body_model_path: String = ""
@export_file("*.glb") var hands_model_path: String = ""

@export_group("Selector e Info API")
@export var api_id: int = 0
@export var canonical_ki_text: String = ""
@export_file("*.webp", "*.png") var portrait_image_path: String = ""
@export var api_image_url: String = ""
