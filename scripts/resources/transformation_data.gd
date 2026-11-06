class_name TransformationData
extends Resource

@export var form_name: String = "" # Nombre de la transformación (ej: Kaioken, SSJ, SSB)
@export var np_multiplier: float = 2.0 # Multiplica el NP máximo y aumenta el daño
@export var ki_drain_per_sec: float = 1.0 # Costo por segundo para mantener la transformación
@export var aura_color: Color = Color(1, 0.8, 0, 1) # Color del aura de energía del personaje
