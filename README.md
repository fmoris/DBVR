# 🐉 DBZVR — Dragon Ball VR (Godot 4.8 · Meta Quest OpenXR)

Experiencia de combate **1v1 en Realidad Virtual en tiempo real** inspirada en *Dragon Ball Z*, *Dragon Ball Legends* y *Yu Yu Hakusho: Tokubetsu Hen*, diseñada para **Meta Quest (OpenXR)** a **90 FPS** con soporte híbrido para **mandos Quest** y **Hand Tracking biométrico (26 huesos)**.

🌐 **GitHub Pages (Web + Manual Interactivo):** <https://fmoris.github.io/DBVR/>  
📘 **Manual completo en Markdown:** [TUTORIAL_MECANICAS_DBZVR.md](TUTORIAL_MECANICAS_DBZVR.md)

---

## ✨ Características Principales

### 1. Combate sin barra de HP (Battle Power + Administrador de Ki)
* **Ki (`0–100`):** Combustible táctico para ataques, desvíos, teletransportes y transformaciones (`+1.0 Ki/s` pasivo, recarga en 2 fases `+24.0 Ki/s` y ganancia por resistencia al daño).
* **Último Aliento:** Si lanzas Ki Blasts, Súper Ataques o empujas un Choque con `0 Ki`, quemas tu **Battle Power (BP)** como Fuerza Vital; llegar a `0 BP` provoca derrota por **Agotamiento Vital**.
* **Pisos Irreversibles de BP:** Conforme escalas tu BP en una forma aseguras pisos de `25%`, `50%`, `75%` y `85%`.
* **Furia, Determinación y Zenkai:**
  * **Furia (`>= 30%` déficit de BP):** Duplica la recarga de Ki (`+100%`) y ganancia de BP (`x2`).
  * **Momento de Determinación (1× por combate):** Brazos cruzados al pecho (`Grips`, `2.8 s`) ➔ `+45 Ki`, `+25%` del déficit de BP y **Zenkai Comeback**.
  * **Estado Zenkai:** Por **Dominio** (`>= 40%` ventaja y `>= 75%` máx.) o **Comeback** (1 intento heroico de K.O. tras Parry Perfecto, Desvío de Súper o Determinación).

### 2. Personajes y Transformaciones
| Luchador | Base / Máx BP | Transformaciones (Multiplicador · Drenaje Ki/s) | Técnicas Características |
| :--- | :---: | :--- | :--- |
| **Vegeta** | `10.000 / 20.000` | `SSJ (x2.0 · 2.1/s)` ➔ `Super Vegeta (x3.5 · 3.2/s)` ➔ `SSB (x5.0 · 4.4/s)` ➔ `Ultra Ego (x8.0 · 5.5/s)` | *Galick Ho* (`28 Ki`), *Big Bang Attack* (`35 Ki`), *Final Flash* (`45 Ki`, `SSJ+` Finisher) |
| **Goku** *(+ variante `Goku Zenkai`)* | `9.000 / 18.000` | `SSJ (x2.0 · 1.8/s)` ➔ `SSJ2 (x3.5 · 2.8/s)` ➔ `SSB (x5.0 · 4.0/s)` ➔ `Ultra Instinto (x8.0 · 5.5/s)` | *Kamehameha* (`28 Ki`), *Genkidama* (`45 Ki`, solo Base), *Super Kamehameha* (`45 Ki`, `SSJ+` Finisher) |

### 3. Fases y Secuencias de Combate
* **Fase Libre y Scouter:** Desplazamiento discreto por casillas (`3.0 m` horizontal, `2.0 m` vertical hasta `+9.0 m`), Recarga Ki en 2 fases, Guardia Cruzada `X` (`-85%` daño BP) y retícula diegética (Amarilla fijado, Naranja guardia abierta, Violeta pulsante cráter).
* **Combate a Distancia (`Ki Blasts`):** Rápidos (`3.0` / `2.5 Ki` Vegeta) y Cargados (`>= 0.45 s`, `9.0 Ki`, homing), escalado por ratio de BP (incluyendo *No-Sell* Saiyan), Desvío (`+12 Ki`, `+150 BP`), **Devolución Perfecta** teledirigida y **Cortina de Humo** (habilita **Melee Dash `0 Ki`** o **Súper `+25%` velocidad**).
* **Minijuego de Melee (`MeleeTargetDome` + `MeleeLoreEventController`):**
  * **Barra Doble de Ki** en HUD con alertas (`⚠️ KI CRÍTICO < 22 Ki`).
  * Combos de **4 a 7 golpes** (hasta **8** con emboscada), validación física (`>= 22 cm`, retracción `>= 20 cm`, `>= 1.55 / 1.35 m/s`) y 3 niveles de potencia (`~ Suave 0.60×`, `💥 ¡SÓLIDO! 1.00×`, `⚡ ¡SÓNICO! 1.35×` con reembolso `+1.5 Ki`).
  * **Semáforo Defensivo:** Aro Cian/Violeta (`Espera`) ➔ Verde (`¡YA!`) ➔ Dorado (`¡PARRY! +14 Ki`), Desvío con palma abierta o Trigger (`+5 Ki`), `Z-Vanish` defensivo (`-14 Ki`), Choque de Puños, Guardia Cruzada `X` y Onda Explosiva Kiai (`-22 Ki`).
  * **6 Eventos Dinámicos de Lore DBZ:** *Choque Frenético de Puños*, *Caída del Meteoro* (cráter `3.5 s` + `+35%` vel. Súper), *Guerra de Z-Vanish*, *Desgarre de Guardia*, *Onda Explosiva (Kiai)* e *Intercambio Sónico Z-Burst*.
* **Súper Ataques, `Bullet-Time`, `Beam Clash` y `Air Brake`:** 5 respuestas defensivas en `Bullet-Time`, Choque de Poderes interactivo (agitación + gatillos, IA bloqueada de lanzar Ki Blasts durante el choque, avance físico del haz hasta `0.0 / 1.0` e impacto inmediato si un luchador se queda sin `Ki` o desiste) y Frenado Aéreo antes de chocar con la muralla (`Wall-Stick 0.65 s`).
* **Bucle de Secuencias Encadenadas por Ki (`Manga Chain Loop`):**
  * **El Ki es la llave de toda cadena:** Cada eslabón consecutivo (`chain_depth`) escala su costo en `+35%` (`chain_ki_cost_step = 0.35`, ej. `x1.0 → x1.35 → x1.70`), obligando a gestionar cuándo extender la ofensiva o volver a Fase Libre.
  * **Follow-Up Aéreo & `Meteor Chase` (`12 Ki × escala`):** Tras lanzar al rival por los aires en Melee, puedes encadenar ráfagas de Ki Blasts o ejecutar *Meteor Chase* para abrir una nueva `MeleeTargetDome` aérea.
  * **Ventana `Post-Super Follow-Up` (`3.0 s` · mín. `15 Ki`):** Si un Súper Ataque impacta sin K.O., el atacante con Ki suficiente puede perseguir entre el humo con Ki Blasts o *Meteor Chase*.
  * **Corte Defensivo (`Explosive Wave`, `22 Ki` con `B/Y`):** El defensor puede detonar una Onda Expansiva para cortar la cadena aérea/post-super del rival y reiniciar `chain_depth = 0`.
* **7 Mini-Escenas Dramáticas Contextuales:** *Corazón Sereno*, *Pulso Kaioken*, *Orgullo del Príncipe*, *Precisión Real*, *Reflejos Z*, *Ruptura de Límites* y *Sobrecarga de Aura*.

### 4. Relato breve de una partida real (Vegeta vs. Goku)
1. **Fase Libre (Arena 32×32 m):** Vegeta (`10.000 BP`) presiona con *Ki Blasts* mientras Goku (`9.000 BP`) recarga en 2 fases hasta el techo del `60% BP` y desvía ráfagas (`+12 Ki`, `+150 BP`).
2. **Cadena Melee → Follow-Up → Meteor Chase:** Vegeta conecta un Dash (`10 Ki`), remata con *Martillazo DBZ* (`-22 Ki`) lanzando a Goku por los aires y activa *Meteor Chase* (`12 Ki × 1.35`) para abrir una segunda `MeleeTargetDome` aérea. Goku responde con *Parry Perfecto* (`+14 Ki`), invierte el turno y activa *Corazón Sereno* (permanente: `+20% Recarga Ki`, `+18% Vel. Súper`).
3. **Beam Clash y Post-Super Follow-Up:** Ambos alcanzan `SSJ (x2.0)`. Vegeta lanza *Galick Ho* (`28 Ki`) y Goku responde con *Kamehameha* (`28 Ki`) en *Bullet-Time*: en el *Beam Clash*, la IA no puede lanzar *Ki Blasts* externos y el haz de Goku avanza físicamente hasta `0.0` al quedarse Vegeta sin Ki, impactándolo de lleno y abriendo `3.0 s` de *Post-Super Follow-Up* (`>= 15 Ki`).
4. **Furia, Zenkai y Desenlace:** En Furia, Vegeta desbloquea *Orgullo del Príncipe* (Furia permanente al `22%` y `+15%` daño Súpers) y sube a `Super Vegeta` → `SSB` → `Ultra Ego (x8.0)`. Goku responde con *Momento de Determinación* (`+45 Ki`, *Zenkai Comeback*), alcanza `Ultra Instinto (x8.0)` y sella el **K.O. Zenkai** con *Super Kamehameha* (`45 Ki`). *(El relato completo paso a paso y el selector interactivo de personajes están disponibles en [GitHub Pages](https://fmoris.github.io/DBVR/)).*

---

## 🗂️ Estructura del Proyecto

```text
dbzvr/
├── cell_games_arena.tscn           # Escena principal de combate (Arena de los Juegos de Cell)
├── vr_hud.tscn                     # HUD holográfico en muñeca / palma
├── project.godot                   # Configuración Godot 4.8 (Mobile / gl_compatibility)
├── export_presets.cfg              # Preset de exportación Android / Meta Quest OpenXR
├── TUTORIAL_MECANICAS_DBZVR.md     # Manual completo de mecánicas por fase y secuencia
├── docs/                           # Sitio estático GitHub Pages (info + manual interactivo)
├── resources/
│   ├── ki_economy.tres             # Parámetros de economía Ki/BP
│   ├── vegeta.tres / goku.tres     # Definición de personajes, poderes y transformaciones
│   ├── goku_zenkai.tres            # Variante Goku Zenkai con intercambio de mallas por forma
│   └── dramatic_events/            # 7 recursos DramaticMiniEventData (.tres)
├── scripts/
│   ├── character_instance.gd       # Estado de luchador, BP, Ki, Zenkai, Air Brake, físicas
│   ├── HybridCombatController.gd   # Gestos VR híbridos (mandos + pose en espacio de torso)
│   ├── GesturePhaseTree.gd         # Motor gestual Trie-State-Machine (GSS v3)
│   ├── MeleeTargetDome.gd          # Cúpula holográfica de combate Melee y Semáforo defensivo
│   ├── MeleeLoreEventController.gd # Orquestador de los 6 eventos dinámicos de Lore DBZ
│   ├── SuperBeamSequenceController.gd # Secuencia Bullet-Time, AoE y 5 defensas de Súper
│   ├── BeamClashController.gd      # Choque de Poderes (tira y afloja en tiempo real)
│   ├── DramaticDirector.gd         # Atmósfera cinematográfica, cráteres y K.O. Zenkai
│   ├── DramaticMiniSceneController.gd # 7 minijuegos dramáticos en cámara lenta
│   ├── ProceduralKiProjectile.gd   # Proyectiles Ki, desvíos, Devolución Perfecta y choques
│   ├── CombatAIController.gd       # IA táctica de combate y transformaciones
│   ├── ki_sense_and_lockon.gd      # Scouter, retícula dinámica y alertas de combate
│   └── vr_hud.gd / vr_in_game_menu.gd # HUD diegético y menú in-game VR
└── shaders/                        # Shaders de Ki, auras, haces y ondas de choque
```

---

## 🛠️ Requisitos, Pruebas y Compilación APK

* **Motor:** Godot Engine `4.8-beta2` (o `4.3+` compatible con el proyecto).
* **Target VR:** Meta Quest (Android ARM64, OpenXR, `gl_compatibility`).

### Verificación headless (consola)
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 20
```

### Compilar APK Debug para Meta Quest
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --export-debug "Android" "d:\Mis Documentos\dbzvr\builds\dbzvr.apk"
```

---

## 🌿 Flujo Git-Flow del Repositorio
* `main`: Solo código consolidado y validado para visor VR.
* `develop`: Rama de integración continua.
* `feature/*` y `fix/*`: Ramas de desarrollo obligatorio previo a cada cambio, con PR hacia `develop`.
