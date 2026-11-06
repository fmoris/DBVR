class_name CharacterData
extends Resource

@export var character_name: String = ""
@export var base_np: float = 9000.0
@export var max_np: float = 20000.0
@export var base_ki: float = 100.0
@export var scale_factor: float = 1.0 # Para definir estatura (Goku: 1.0, Vegeta: 0.94)
@export var model_asset_scale: float = 1.0 # Para compensar la escala de importación de la malla (ej. Vegeta: 8.291948)

@export_file("*.glb") var body_model_path: String = ""
@export_file("*.glb") var hands_model_path: String = ""

@export var powers: Array[Resource] = []
@export var transformations: Array[Resource] = []
