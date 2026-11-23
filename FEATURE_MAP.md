# FEATURE_MAP.md — DBZVR (Godot 4.3+ / 4.8 VR OpenXR)

Mapa vivo de funcionalidades, escenas, recursos, shaders y puntos de entrada de **Dragon Ball Z VR** para Meta Quest 3 (90 FPS estables).

---

## 1. Escena Principal y Configuración XR

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Arena Cell Games (Main Scene)** | [cell_games_arena.tscn](file:///d:/Mis%20Documentos/dbzvr/cell_games_arena.tscn) | Escena raíz del combate 1v1 con `XROrigin3D`, `PlayerCharacterInstance`, `EnemyCharacterInstance`, `HybridCombatController` y `GesturePhaseTree`. |
| **XR Setup & Test Bootstrapper** | [xr_setup.gd](file:///d:/Mis%20Documentos/dbzvr/xr_setup.gd) | Inicialización OpenXR, VRS_XR, centrado HMD y lanzamiento automático de `DesktopXRSimulator` + `CombatSequenceRunner` con `--test-suite=all`. |
| **Meta Platform Autoload** | [MetaManager.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/MetaManager.gd) | Singleton de plataforma Meta Quest SDK. |
| **Audio Action Autoload** | [AudioActionManager.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/AudioActionManager.gd) | Precarga y caché O(1) de los 62 eventos de audio mapeados en `assets/audio/audio_actions.json`. |

---

## 2. Personajes, Animaciones y Datos (`CharacterData`, `TransformationData`, `PowerData`)

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Instancia de Personaje (Jugador / IA)** | [character_instance.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/character_instance.gd) | Gestión de Ki, Nivel de Poder (NP) con umbrales irreversibles (25/50/75/100%), Furia, Zenkai, transformaciones, IK de brazos en 1ra persona, aura dinámica y físicas 3D. |
| **Animador de Combate + Zenkai Overlay** | [ProceduralCombatAnimator.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ProceduralCombatAnimator.gd) | 18 poses y animaciones canónicas sobre 18 huesos con soporte para librerías de keyframes extraídos de Zenkai (`ZenkaiAnimationLoader`). |
| **Cargador de Animaciones Zenkai (`.spa` ➔ `.json`)** | [ZenkaiAnimationLoader.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ZenkaiAnimationLoader.gd) | Caché estático zero-allocation de pistas de cuaterniones extraídas de `[0]mList.par` (`res://assets/animations/zenkai/*.json`). |
| **Recurso de Personaje** | [character_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/character_data.gd) | Definición base de personaje, modelos GLB, poderes y transformaciones. |
| **Recurso de Transformación** | [transformation_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/transformation_data.gd) | Multiplicadores NP, drenaje de Ki, color de aura, `aura_vfx_path`, `has_bio_lightning`, `light_energy`, `light_range`, `aura_loop_action_id` y `anim_library_path`. |
| **Recurso de Poder / Técnica** | [power_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/power_data.gd) | Costo de Ki, daño NP, `explosion_tier` (1..5), `charge_action_id`, `fire_action_id`, `impact_action_id` y `anim_clip_prefix`. |
| **Perfiles de Goku y Vegeta** | [goku.tres](file:///d:/Mis%20Documentos/dbzvr/resources/goku.tres), [goku_zenkai.tres](file:///d:/Mis%20Documentos/dbzvr/resources/goku_zenkai.tres), [vegeta.tres](file:///d:/Mis%20Documentos/dbzvr/resources/vegeta.tres) | Perfiles completos de Goku (Base, SSJ, SSJ2, SSJ3, SSB, Ultra Instinto) y Vegeta (Base, SSJ, Super Vegeta, SSB, Ultra Ego) con sus técnicas y referencias Zenkai. |

---

## 3. Combate, Gestos VR, Proyectiles y Secuencias de Super Haz

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Motor Gestual Biométrico (GSS v3)** | [GesturePhaseTree.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/GesturePhaseTree.gd) | Reconocimiento de poses en 2 fases (Recarga de Ki, Kamehameha, Galick Ho, Final Flash, Big Bang, Genkidama). |
| **Controlador Híbrido de Combate VR** | [HybridCombatController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/HybridCombatController.gd) | Disparo de Ki Blasts, desvío físico con manos, guardia cruzada, Melee Dash y Momento de Determinación. |
| **Proyectiles de Ki (Rápidos / Cargados)** | [ProceduralKiProjectile.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ProceduralKiProjectile.gd) | Física de vuelo, homing, desvío con manos, choques en aire y detonación AoE conectada a `ZenkaiVFXManager` (Tiers 1 y 2). |
| **Secuencia Bullet-Time de Super Haz** | [SuperBeamSequenceController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/SuperBeamSequenceController.gd) | Bullet-Time adaptativo por diferencial de NP, Z-Vanish, desvío, contención, choque de haces y explosión Zenkai (Tiers 4 y 5). |
| **Choque de Poderes (Beam Clash)** | [BeamClashController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/BeamClashController.gd) | Duelo de haces de energía entre atacante y defensor. |
| **Inteligencia Artificial 1v1** | [CombatAIController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/CombatAIController.gd) | Toma de decisiones reactiva del rival en Fase Libre y Fase de Cadena. |

---

## 4. Efectos Visuales (Zenkai VFX), Shaders, Iluminación y Audio

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Gestor y Pool de Explosiones Zenkai** | [ZenkaiVFXManager.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ZenkaiVFXManager.gd) | Pool estático zero-allocation de 5 cúpulas multi-capa (`DomeMesh`, `RingMesh`, `PillarMesh`) y 4 `OmniLight3D` sin sombras para los 5 Tiers de explosión. |
| **Shader de Cúpula de Explosión y Bio-Rayos** | [ki_explosion_dome.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/ki_explosion_dome.gdshader) | Shader espacial `unshaded` + `blend_add` con flujo de plasma dual, máscara de disolución y arcos bioeléctricos. |
| **Shaders de Aura, Haz y Onda de Choque** | [ki_corona.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/ki_corona.gdshader), [ki_beam.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/ki_beam.gdshader), [shockwave.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/shockwave.gdshader) | Shaders de corona de Ki, cilindro de haz energético y anillos refractivos. |
| **Mallas y Texturas VFX Zenkai** | `res://assets/vfx_zenkai/{common,goku,vegeta}/` | 32 mallas `.fbx` y texturas `.png` convertidas de los contenedores `*_battle_vram.pak` de Zenkai Battle Royale. |
| **Diccionario y Mapa de Audio Zenkai** | [audio_actions.json](file:///d:/Mis%20Documentos/dbzvr/assets/audio/audio_actions.json), [sound_dictionary.json](file:///d:/Mis%20Documentos/dbzvr/assets/audio/sfx_zenkai/sound_dictionary.json) | 62 acciones de audio pobladas al 100% con efectos `snd_dbgstr` y bancos `.nub` de Goku y Vegeta (`goku_zenkai/`, `vegeta_zenkai/`, `sfx_zenkai/`). |
