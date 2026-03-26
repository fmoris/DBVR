# CHANGELOG — VR KI Combat

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).
Las versiones corresponden a los checkpoints del proyecto.

---

## [9ec4cd13] — 2026-03-26 · Debug overlay de gestos + Bullet time mejorado

### Agregado
- **`GestureDebugOverlay.ts`**: nuevo componente que muestra en pantalla en tiempo real las coordenadas de muñecas e índices de ambas manos, el gesto detectado con color por tipo, el estado del hand tracking (activo / sin datos) y un historial de los últimos 5 cambios de gesto.
- Botón `[DBG]` (tecla `G` en desktop) en la barra de controles del HUD para activar/desactivar el overlay sin salir del juego.

### Modificado
- **Bullet time Kamehameha**: duración aumentada de 1500ms a 3500ms, velocidad reducida de 0.25x a 0.18x.
- **Bullet time Final Flash**: duración aumentada de 2000ms a 4500ms, velocidad reducida de 0.20x a 0.12x.
- **`activateSlowMotion()`**: transición de entrada suavizada con ramp-in de 300ms (de 1x a timeScale) y ramp-out de 500ms (de timeScale a 1x), eliminando el corte abrupto anterior.
- **Efectos visuales de bullet time**: viñeta púrpura más intensa con doble box-shadow, overlay de aberración cromática (radial-gradient en modo screen) y etiqueta "BULLET TIME" con fade-in/out.
- El estado `"attacking"` ahora dura hasta que expira el bullet time (fallback a 4500ms/5500ms en lugar de 1200ms/1500ms).

### Archivos modificados
`CombatSystem.ts` · `HUD.ts` · `Game.ts` · `GestureDebugOverlay.ts` (nuevo)

---

## [91e72d35] — 2026-03-26 · Corrección de gestos VR + botón Menú

### Corregido
- **Bug crítico en `GestureRecognizer.ts`**: los joints se accedían por índice numérico (`hand.joints[8]`) cuando Babylon 6 los expone por nombre de string (`"index-finger-tip"`), lo que hacía que todos los joints llegaran como `{x:0, y:0, z:0}`.
- **Umbrales de gestos invertidos**: en el espacio de referencia `local-floor`, "adelante" es `-Z`, no `+Z`. Los umbrales de `isAttackingPosture` estaban invertidos.
- **Spam de acciones**: `processGestures()` se llamaba cada frame sin cooldown, disparando `launchBasicAttack()` cientos de veces por segundo.

### Agregado
- **`GestureRecognizer` v2**: acceso a joints por nombre W3C estándar (`wrist`, `thumb-tip`, `index-finger-tip`, etc.) con fallback numérico para versiones antiguas de Babylon. Función `extractHandJoints()` exportada.
- Cooldown por tipo de gesto: 600ms para ataque, 200ms para carga, 150ms para bloqueo, 400ms para parry, 200ms para recarga.
- Detección de velocidad de empuje (delta Z entre frames) para el gesto de ataque.
- Botón `[M]` (tecla `M`) en el HUD para volver al menú principal.
- `disposeAndExit()` en `Game.ts`: sale de la sesión XR limpiamente, detiene el reconocimiento de voz y libera el motor de Babylon.
- **`main.ts` refactorizado**: `goToMenu()` recrea `StartScreen` sin `window.location.reload()`, permitiendo múltiples partidas en la misma sesión.

### Archivos modificados
`GestureRecognizer.ts` · `Game.ts` · `HUD.ts` · `main.ts` · `routers.ts`

---

## [6741c28c] — 2026-03-26 · Fix carga infinita VR en Meta Quest 3

### Corregido
- **`optionalFeatures: true`** era inválido en Oculus Browser; reemplazado por el array correcto `["hand-tracking"]`.
- **`enableFeature(HAND_TRACKING)`** sin pasar `xrInput` fallaba silenciosamente en Quest, dejando la sesión en espera indefinida.
- **Mismatch de referenceSpace**: `local-floor` en init vs `local` en `enterXRAsync`, causando error interno en el runtime XR.
- Error TypeScript `TS2554` en `routers.ts` (argumento extra en `storageGet`).

### Agregado
- Verificación previa con `navigator.xr.isSessionSupported()` antes de inicializar.
- `Promise.race` con timeout de 12 segundos como fallback si WebXR no responde.
- Las manos 3D estáticas se ocultan automáticamente al entrar en sesión XR (`onStateChangedObservable`).

### Archivos modificados
`Game.ts` · `routers.ts`

---

## [34d5006e] — 2026-03-26 · Rediseño visual (referencia ejemplo_ui)

### Modificado
- **HUD rediseñado**: paneles de barras movidos a esquinas inferiores con forma de escudo tech-azul (borde redondeado asimétrico). Panel izquierdo: jugador (NP, HP, KI). Panel derecho: enemigo (NP, HP, KI). Botones de control en fila compacta central inferior.
- **Entorno de cañón**: fondo naranja-dorado de atardecer (`clearColor`), suelo de tierra rojiza, 11 formaciones rocosas a los lados y fondo, nubes semitransparentes en el horizonte.
- **Iluminación**: sol bajo dorado-naranja (`DirectionalLight`) + relleno azulado de cielo (`HemisphericLight`).
- **Manos del jugador**: palma más grande con 4 dedos y pulgar modelados, posición más baja y separada, aura de partículas KI azul permanente.

### Archivos modificados
`Game.ts` · `HUD.ts`

---

## [337ed943] — 2026-03-26 · Fuente Saiyan Sans + IA enemigo + Voz + Pantalla resultado

### Agregado
- **Fuente Saiyan Sans**: aplicada globalmente en `body`, `StartScreen` y `HUD` via variable CSS `--font-saiyan`.
- **IA del enemigo** (`CombatSystem.ts`): ataques automáticos cada 3–6 segundos (ataque básico, Kamehameha, Final Flash) según NP y KI disponible. Indicador rojo en HUD al atacar.
- **`VoiceRecognizer.ts`**: reconocimiento de voz con Web Speech API. Detecta "Kamehameha" y "Final Flash" para otorgar +5 NP de bonus. Transcripción mostrada en HUD en tiempo real.
- **`ResultScreen.ts`**: pantalla de victoria/derrota al finalizar el combate con rango (Novato → Legendario), NP final de ambos, duración y KI restante. Botones Reiniciar y Menú.

### Archivos modificados / creados
`VoiceRecognizer.ts` (nuevo) · `ResultScreen.ts` (nuevo) · `CombatSystem.ts` · `Game.ts` · `HUD.ts` · `StartScreen.ts` · `client/index.html`

---

## [c6d8c1bd] — 2026-03-23 · MVP inicial

### Agregado
- Proyecto inicializado con stack React 19 + Tailwind 4 + Express 4 + tRPC 11 + BabylonJS 6.
- **`Game.ts`**: motor BabylonJS, cámara en primera persona, loop de render.
- **`CombatSystem.ts`**: sistema de combate con estados (neutral, charging, charging_special, attacking, defending, slowMotion, hit, melee), barras de NP/HP/KI, ataques básico, cargado, Kamehameha y Final Flash con niveles de carga.
- **`GestureRecognizer.ts`**: detección inicial de gestos de manos (v1, con bugs de índices).
- **`WebXRManager.ts`**: wrapper de sesión WebXR con hand tracking.
- **`VFXManager.ts`**: sistema de efectos visuales (proyectiles KI, Kamehameha, Final Flash, auras, partículas de impacto).
- **`HUD.ts`**: interfaz de combate con barras de estado, indicadores de carga y botones de control.
- **`StartScreen.ts`**: pantalla de inicio con selección de personaje y tutorial de gestos.
- **`BabylonScene.ts`**: escena alternativa de referencia (no usada en producción).
- Soporte WebXR con `immersive-vr`, hand tracking y `dom-overlay`.
- Controles de teclado: A (ataque), W (cargar/lanzar), S (bloquear), D (esquivar), R (recargar KI), 1 (Kamehameha), 2 (Final Flash).

---

## Convención de versiones

Cada versión corresponde al hash corto del checkpoint de Manus. El formato de cada entrada sigue:

| Sección | Descripción |
|---|---|
| **Agregado** | Funcionalidades nuevas que no existían antes |
| **Modificado** | Cambios en funcionalidades existentes |
| **Corregido** | Bugs resueltos |
| **Eliminado** | Código o funcionalidades removidas |
| **Archivos** | Lista de archivos afectados por el cambio |
