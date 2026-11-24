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
| **Instancia de Personaje (Jugador / IA)** | [character_instance.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/character_instance.gd) | Gestión de Ki, Nivel de Poder (NP) con umbrales irreversibles (25/50/75/100%), Furia, Zenkai, transformaciones, bloqueo/cola diferida de eventos dramáticos durante cadenas activas (`is_in_active_combat_sequence`), físicas balísticas (`18–28m` con desaceleración exponencial y caída) y IK de brazos en 1ra persona. |
| **Animador de Combate 100% Zenkai SPA** | [ProceduralCombatAnimator.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ProceduralCombatAnimator.gd) | Ejecuta animaciones Zenkai `.spa` al 100% sobre los 18 huesos en la IA (`_apply_pure_zenkai_full_body`, 41 clips mapeados) con fallback procedural seguro para el jugador VR. |
| **Cargador de Animaciones Zenkai (`.spa` ➔ `.json`)** | [ZenkaiAnimationLoader.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ZenkaiAnimationLoader.gd) | Caché estático zero-allocation de pistas de cuaterniones extraídas de `[0]mList.par` (`res://assets/animations/zenkai/*.json`). |
| **Recurso de Personaje** | [character_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/character_data.gd) | Definición base de personaje, modelos GLB, poderes y transformaciones. |
| **Recurso de Transformación** | [transformation_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/transformation_data.gd) | Multiplicadores NP, drenaje de Ki, color de aura, `aura_vfx_path`, `has_bio_lightning`, `light_energy`, `light_range`, `aura_loop_action_id` y `anim_library_path`. |
| **Recurso de Poder / Técnica** | [power_data.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/power_data.gd) | Costo de Ki, daño NP, `explosion_tier` (1..5), `charge_action_id`, `fire_action_id`, `impact_action_id` y `anim_clip_prefix`. |
| **Economía de Ki y Balance Canon** | [ki_economy_config.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/resources/ki_economy_config.gd), [ki_economy.tres](file:///d:/Mis%20Documentos/dbzvr/resources/ki_economy.tres) | Fuente única de verdad para recarga de Ki, drenaje por guardias, reembolsos diferidos por impacto limpio, Z-Vanish, Kiai, Choques (`melee_clash_even_ki_reward`, `melee_clash_win_reward`, `melee_sim_clashes_to_flurry`) e Intercambio Simultáneo. |
| **Perfiles de Goku y Vegeta** | [goku.tres](file:///d:/Mis%20Documentos/dbzvr/resources/goku.tres), [goku_zenkai.tres](file:///d:/Mis%20Documentos/dbzvr/resources/goku_zenkai.tres), [vegeta.tres](file:///d:/Mis%20Documentos/dbzvr/resources/vegeta.tres) | Perfiles completos de Goku (Base, SSJ, SSJ2, SSJ3, SSB, Ultra Instinto) y Vegeta (Base, SSJ, Super Vegeta, SSB, Ultra Ego) con sus técnicas y referencias Zenkai. |

---

## 3. Combate, Gestos VR, Proyectiles, Melee y Secuencias de Super Haz

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Motor Gestual Biométrico (GSS v3)** | [GesturePhaseTree.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/GesturePhaseTree.gd) | Reconocimiento de poses en 2 fases (Recarga de Ki, Kamehameha, Galick Ho, Final Flash, Big Bang, Genkidama). |
| **Controlador Híbrido de Combate VR** | [HybridCombatController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/HybridCombatController.gd) | Disparo de Ki Blasts, desvío físico con manos, guardia cruzada, frenado aéreo, Approach Bar y Melee Dash. |
| **Cúpula Melee Rítmico (VR + Simulador)** | [MeleeTargetDome.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/MeleeTargetDome.gd) | Declaración táctica (golpe frontal real tipo jab/directo/gancho + retracción en profundidad + tiers por velocidad), defensa 1 mano con `Trigger` (fallo `early_lockout` estricto si pulsas en Rojo antes de Ámbar sin penalizar preparar puño de Choque, preservando Ámbar como bloqueo parcial), Parry `Trigger+Grip` desambiguado de `CLASH`, Choque en nodos `⬜ DEFEND` y shape híbrido `CLASH` en Intercambio Simultáneo con escalada configurable, audio real de golpes, lanzamientos en diagonal (`<=32°`), recompensas de Ki diferidas y soporte `DesktopXRSimulator`. |
| **Eventos Dinámicos Lore Melee** | [MeleeLoreEventController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/MeleeLoreEventController.gd) | Orquesta `FIST_FLURRY_CLASH` (puño frontal cerrado `G+T`, orbe dinámico, barra de Ki visible, temporizador, crescendo de audio, pasivas Goku `-30% Ki` / Vegeta `+15% empuje` y Comeback Zenkai en Furia), `METEOR_SMASH` (proyección diagonal apuntable hacia cráter), `Z_VANISH_WAR` (Shunkan Idō/Zanzoken), `GUARD_PRESSURE_BREAK`, `EXPLOSIVE_WAVE` y `SONIC_Z_BURST`. |
| **Proyectiles de Ki (Rápidos / Cargados)** | [ProceduralKiProjectile.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ProceduralKiProjectile.gd) | Física de vuelo, homing, desvío con manos, choques en aire y detonación AoE conectada a `ZenkaiVFXManager` (Tiers 1 y 2). |
| **Secuencia Bullet-Time de Super Haz** | [SuperBeamSequenceController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/SuperBeamSequenceController.gd) | Bullet-Time adaptativo por diferencial de NP, Z-Vanish, desvío, contención, choque de haces y explosión Zenkai (Tiers 4 y 5). |
| **Choque de Poderes (Beam Clash)** | [BeamClashController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/BeamClashController.gd) | Duelo de haces de energía entre atacante y defensor. |
| **Inteligencia Artificial 1v1** | [CombatAIController.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/CombatAIController.gd) | Toma de decisiones reactiva del rival en Fase Libre, Melee Rush y Follow-Up Bullet-Time. |

---

## 4. Efectos Visuales (Zenkai VFX), Shaders, Iluminación y Audio

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Gestor y Pool de VFX Zenkai Puros** | [ZenkaiVFXManager.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ZenkaiVFXManager.gd) | Registro cacheado de 47 texturas reales `pebs_*` de Zenkai, fábrica de orbes/blasts (`build_zenkai_orb_visual`), impactos (`spawn_zenkai_impact_flash`), cráteres (`spawn_zenkai_crater_decal`), flipbooks 4×4 de explosión/rocas y pool de 5 cúpulas + 4 `OmniLight3D`. |
| **Humo Anime 4×4 Zenkai** | [KiSmokeFX.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/KiSmokeFX.gd) | Pool de emisores `CPUParticles3D` usando spritesheet 4×4 real de humo anime (`smoke_anime_white_4x4.png`, `kka_1_000`) en lugar de gradientes procedurales. |
| **Shader de Cúpula de Explosión y Bio-Rayos** | [ki_explosion_dome.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/ki_explosion_dome.gdshader) | Shader espacial `unshaded` + `blend_add` con flujo de plasma dual, máscara de disolución y arcos bioeléctricos. |
| **Shaders de Aura, Haz y Onda de Choque** | [zenkai_aura.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/zenkai_aura.gdshader), [ki_beam.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/ki_beam.gdshader), [shockwave.gdshader](file:///d:/Mis%20Documentos/dbzvr/shaders/shockwave.gdshader) | Shaders alimentados con texturas reales de Zenkai (`aura_vertical_streaks.png`, `aura_flame_band.png`, `beam_core_strip.png`). Eliminado uso de `ki_sphere.gdshader` y `ki_corona.gdshader`. |
| **Catálogo de Partículas y Mallas Zenkai** | `res://assets/vfx_zenkai/{common,particles}/` | 47 texturas reales extraídas de `common_ioram/vram` y los 8 paquetes `effect/*_{goku,vegeta}_*` (descompresor `HLCS`/`0HCS`) organizadas en `aura/`, `lightning/`, `blast/`, `beam/`, `explosion/` e `impact/`. |
| **Diccionario y Mapa de Audio Zenkai** | [audio_actions.json](file:///d:/Mis%20Documentos/dbzvr/assets/audio/audio_actions.json), [sound_dictionary.json](file:///d:/Mis%20Documentos/dbzvr/assets/audio/sfx_zenkai/sound_dictionary.json) | 62 acciones de audio pobladas al 100% con efectos `snd_dbgstr` y bancos `.nub` de Goku y Vegeta (`goku_zenkai/`, `vegeta_zenkai/`, `sfx_zenkai/`). |

---

## 5. Dirección Dramática, Arena Destructible y Pruebas en Escritorio

| Componente | Ruta | Responsabilidad |
|---|---|---|
| **Director Dramático Cinematográfico** | [DramaticDirector.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/DramaticDirector.gd) | Intros, Finishers K.O., eventos Zenkai, banners 3D, reset de estado estático entre combates y control de atmósfera/cámara lenta. |
| **Destrucción de Arena e Impactos** | [ArenaDestructionManager.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/ArenaDestructionManager.gd) | Física de destrucción de rocas/pilares (`PillarSpire_*`), cráteres sísmicos (`METEOR_SMASH` y Martillazo), escombros y daño ambiental AoE. |
| **Simulador XR en Escritorio** | [DesktopXRSimulator.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/debug/DesktopXRSimulator.gd) | Simulación de manos, cámara, gatillos y sticks para probar combate libre y Melee Rítmico sin visor OpenXR conectado. |
| **Runner Automatizado de Combate** | [CombatSequenceRunner.gd](file:///d:/Mis%20Documentos/dbzvr/scripts/tests/CombatSequenceRunner.gd) | Ejecuta secuencias automatizadas `--test-suite=all` sobre `DesktopXRSimulator` para validación en escritorio. |
