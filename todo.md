# VR KI Combat — TODO

---

## Infraestructura base (completado)
- [x] Inicializar proyecto con Vite + TypeScript
- [x] Convertir a full-stack (Express + tRPC + DB)
- [x] Esquema de base de datos (users, player_stats, match_replays, player_configs)
- [x] Routers tRPC (auth, stats, replays, config)
- [x] Almacenamiento S3 para replays de partidas
- [x] Escena 3D con BabylonJS (camara primera persona, entorno, enemigo)
- [x] Sistema de camara lenta base
- [x] HUD con barras de KI y salud
- [x] Pantalla de inicio

---

## PARTE 1 — Combate a distancia (KI)

### 1.1 Ataque basico de KI (proyectil rapido)
- [x] Gesto: mano extendida hacia adelante, palma abierta (GestureType.ATTACKING)
- [x] No relentiza el tiempo
- [x] Consume KI bajo (10 pts)
- [x] Causa dano leve al enemigo
- [ ] Puede encadenarse rapidamente (rafaga)
- [x] VFX: proyectil de KI con trail de particulas (VFXManager)

### 1.2 Ataque de KI cargado
- [x] Gesto: puno cerrado (GestureType.CHARGING) → abrir para lanzar
- [x] Durante la carga: VFX de energia concentrandose (VFXManager)
- [x] Gesto de lanzamiento: abrir el puno (soltar)
- [x] Relentiza el tiempo levemente al impactar (bullet time 800ms 0.4x)
- [ ] Interrumpe ataques especiales del rival si impacta durante la carga
- [x] Consume KI medio (20-30 pts segun tiempo de carga)
- [x] Dano proporcional al tiempo de carga (minimo 1s, maximo 3s)
- [x] VFX: esfera compacta con electricidad, escala segun carga

### 1.3 Ataque especial — Kamehameha
- [x] Secuencia de movimientos requerida (gestos VR o tecla 1):
  - [x] Paso 1: ambas manos juntas al costado (GestureType.CHARGING)
  - [x] Paso 2: mantener posicion minimo 2 segundos (carga minima)
  - [x] Paso 3: empujar ambas manos hacia adelante (lanzamiento)
- [x] Tiempo de carga minimo: 2s | maximo: 8s (3 niveles)
- [x] Dano escala con tiempo de carga (base 40, medio 70, maximo 100)
- [x] Relentiza el tiempo 3500ms a 0.18x al lanzar
- [x] Consume KI alto (40/60/80 pts segun nivel)
- [x] VFX: rayo de energia azul/blanco (VFXManager)
- [ ] Audio: sonido de carga creciente + disparo

### 1.4 Ataque especial — Final Flash
- [x] Secuencia de movimientos requerida (gestos VR o tecla 2):
  - [x] Paso 1: brazos extendidos a los lados (posicion en cruz)
  - [x] Paso 2: juntar las manos frente al pecho (concentracion)
  - [x] Paso 3: mantener posicion minimo 3 segundos (carga minima)
  - [x] Paso 4: empujar ambas manos hacia adelante (lanzamiento)
- [x] Tiempo de carga minimo: 3s | maximo: 10s (3 niveles)
- [x] Dano escala con tiempo de carga (base 60, medio 110, maximo 150)
- [x] Relentiza el tiempo 4500ms a 0.12x (mas que Kamehameha)
- [x] Consume KI muy alto (60/90/120 pts segun nivel)
- [x] VFX: explosion de energia amarilla/dorada (VFXManager)
- [ ] Audio: sonido de carga mas grave e intenso que Kamehameha

### 1.5 Defensas contra ataques especiales
- [x] **Bloqueo**: gesto GestureType.BLOCKING (brazos cruzados)
  - [x] Reduce dano en 70% (isDefending = true)
  - [x] Consume KI medio (15 pts)
  - [ ] VFX: escudo de energia frente al personaje
- [ ] **Desvio**: mano abierta en angulo (como redirigir)
  - [ ] Redirige el ataque en una direccion (no causa dano)
  - [ ] Consume KI bajo (10 pts)
  - [ ] Requiere timing preciso (ventana de 0.5s)
  - [ ] VFX: el rayo cambia de trayectoria
- [ ] **Choque** (solo contra ataques especiales): lanzar propio ataque especial al mismo tiempo
  - [ ] Ambos ataques se anulan o el mas cargado gana
  - [ ] Si son iguales: explosion en el centro, ambos reciben dano reducido
  - [ ] VFX: explosion epica en el punto de choque
- [x] **Esquive**: gesto GestureType.PARRYING o tecla D
  - [x] Reduce dano al esquivar
  - [x] Consume KI muy bajo (5 pts)
  - [ ] Ventana de tiempo muy corta (0.3s)
  - [ ] Gesto: inclinacion rapida de cabeza (head tracking)

---

## PARTE 2 — Combate cuerpo a cuerpo (Melee)

### 2.1 Activacion del modo melee
- [ ] Gesto de activacion: ambos punos cerrados empujados hacia adelante simultaneamente
- [ ] Al activar: el tiempo se relentiza para el ATACANTE (elige tipo de ataque)
- [ ] Tipos de ataque a elegir:
  - [ ] Ataque rapido (bajo dano, bajo KI, dificulta defensa perfecta)
  - [ ] Ataque cargado (alto dano, alto KI, mas facil de defender pero mas impacto)
- [ ] Tras elegir: el personaje vuela a toda velocidad hacia el rival (animacion de vuelo)
- [ ] El tiempo se relentiza para el ATACANTE al llegar (elige punto de impacto)
- [ ] Para el DEFENSOR: aparecen sombras de golpes en multiples lugares
  - [ ] Las sombras falsas desaparecen gradualmente
  - [ ] El golpe real se revela con tiempo suficiente para reaccionar
  - [ ] Cuanto mas cargado el ataque, menos tiempo tiene el defensor para leer el golpe

### 2.2 Acciones del atacante en melee
- [ ] Seleccion de punto de impacto (cabeza, torso, costado)
- [ ] Ataque rapido: gesto de puno hacia adelante (un brazo)
- [ ] Ataque cargado: gesto de puno con ambos brazos o carga previa
- [ ] Cadena de golpes: si el primer golpe conecta, puede encadenar siguiente accion
  - [ ] Maximo 3 golpes por cadena antes de que el defensor pueda expulsar
  - [ ] Cada golpe en cadena consume KI adicional

### 2.3 Acciones del defensor en melee
- [ ] **Defensa normal**: bloquear el golpe real (reduce dano 50%)
  - [ ] Gesto: cruzar brazo hacia el punto del golpe
  - [ ] Consume KI bajo
- [ ] **Defensa perfecta**: bloquear en el momento exacto de impacto (ventana 0.2s)
  - [ ] Anula completamente el dano
  - [ ] Abre ventana para CONTRA-ATAQUE o EXPULSION
  - [ ] VFX especial al lograr defensa perfecta (flash de luz)
- [ ] **Contra-ataque** (solo tras defensa perfecta):
  - [ ] El defensor pasa a ser atacante en melee
  - [ ] El atacante original pasa a ser defensor
  - [ ] Consume KI medio
- [ ] **Expulsion** (solo tras defensa perfecta o al final de cadena):
  - [ ] Empujar con ambas manos al rival
  - [ ] Ambos personajes vuelven a la posicion inicial de combate a distancia
  - [ ] Genera KI para el que expulsa (10-15 pts)
  - [ ] VFX: onda de choque que separa a los personajes

### 2.4 Generacion y consumo de KI en melee
- [ ] Ataques rapidos: consumen 10 KI por golpe
- [ ] Ataques cargados: consumen 25 KI por golpe
- [ ] Defensa normal: consume 8 KI
- [ ] Defensa perfecta: no consume KI (recompensa al jugador)
- [ ] Contra-ataque: consume 15 KI
- [ ] Expulsion: genera 12 KI
- [ ] Recibir golpe sin defensa: genera 5 KI (el dolor genera energia)

---

## SISTEMA DE NIVEL DE PODER (reemplaza HP)

### Concepto central
- [ ] Eliminar completamente el concepto de HP/vida
- [ ] Cada luchador tiene un **Nivel de Poder** (NP) que fluctua durante toda la batalla
- [ ] El NP determina la fuerza, resistencia e inmunidad a ciertos ataques
- [ ] La condicion de victoria NO es reducir el NP a 0, sino lograr una diferencia de NP suficiente para que el rival no pueda continuar (rendicion narrativa, como en el anime)

### Escala y rangos del Nivel de Poder
- [x] Rango 1 — Debilitado (NP 0-20%): sin reduccion de dano (0%)
- [x] Rango 2 — Normal (NP 21-50%): reduccion de dano 20%
- [x] Rango 3 — Elevado (NP 51-75%): reduccion de dano 40%
- [x] Rango 4 — Dominante (NP 76-90%): reduccion de dano 70%
- [x] Rango 5 — Trascendente (NP 91-100%): reduccion de dano 90%

### Como sube el Nivel de Poder
- [x] Ataques conectados exitosamente: +NP segun tipo de ataque (launchBasicAttack, etc.)
- [ ] Defensas perfectas: +10 NP (recompensa la habilidad)
- [x] Recibir un golpe fuerte: +NP al recibir dano (presion aumenta el poder)
- [ ] Tiempo en combate activo: +1 NP cada 3 segundos (escalada natural)
- [x] Gritar el nombre del ataque especial: +5 NP bonus al lanzar (Web Speech API)
- [ ] Encadenar acciones sin recibir dano: +3 NP por accion encadenada

### Como baja el Nivel de Poder
- [x] Recibir un ataque especial a maxima carga: -NP segun dano y factor de poder
- [ ] Ser expulsado en melee: -10 NP
- [ ] Fallar un ataque especial (rival lo esquiva o desvía): -8 NP (frustracion)
- [ ] Inactividad prolongada (mas de 5s sin accion): -2 NP por segundo
- [ ] Ser bloqueado repetidamente sin variar ataques: -3 NP por bloqueo consecutivo

### Fluctuacion natural del NP
- [x] El NP nunca es completamente estable: oscila +/- 3 pts de forma organica
- [x] Durante momentos de alta intensidad (atacando/defendiendo): oscilacion aumenta a +/- 8 pts
- [x] Simula la tension dramatica del anime (startNPFluctuation en CombatSystem)
- [ ] Visualmente: el aura del personaje pulsa al ritmo de la fluctuacion

### Condicion de victoria
- [x] Victoria cuando la diferencia de NP entre ambos luchadores supera 50 puntos
- [ ] El luchador con NP mas bajo entra en estado de "rendicion inminente"
- [ ] El luchador dominante tiene una ventana de 5s para ejecutar el golpe final
- [ ] Si no ejecuta el golpe final en ese tiempo, el rival puede iniciar un COMEBACK

### Sistema de Comeback (luchador en desventaja)
- [ ] Se activa cuando el NP del jugador cae por debajo del 25% Y el rival supera el 75%
- [ ] El jugador en desventaja recibe una notificacion visual/haptica de "momento critico"
- [ ] Opciones de comeback disponibles (cada una con requisito de gesto + grito):
  - [ ] **Transformacion**: gesto de explosion de energia (brazos al cielo) + grito
    - [ ] Multiplica el NP actual por 2.5 instantaneamente
    - [ ] Cambia el aura visual del personaje (color diferente)
    - [ ] Consume todo el KI disponible
    - [ ] Solo disponible una vez por combate
  - [ ] **Ataque Desesperado**: lanzar un ataque especial sin tener el KI suficiente
    - [ ] Se activa con NP por debajo de 20%
    - [ ] El personaje usa su propia energia vital (NP) como combustible
    - [ ] Si conecta: +40 NP instantaneo y el rival pierde -30 NP
    - [ ] Si falla: el luchador queda en NP 5% (al borde de la derrota)
  - [ ] **Momento de Determinacion**: gesto de meditacion rapida (5 segundos completamente quieto)
    - [ ] Requiere que el rival no ataque durante esos 5 segundos (lectura psicologica)
    - [ ] Si se completa: NP sube a 40% instantaneamente
    - [ ] VFX: aura explosiva que empuja al rival hacia atras

### Representacion visual del NP
- [x] Barra de NP con color dinamico en el HUD (cyan → verde → amarillo → naranja segun valor)
- [x] Aura del personaje (manos) con particulas de KI azul
- [ ] Aura escala en tamano e intensidad con el NP
- [ ] Particulas de energia aumentan en cantidad y velocidad con el NP alto
- [ ] Efecto de distorsion de calor alrededor del personaje en rangos 4 y 5
- [x] Numero flotante de NP visible en el HUD cuando cambia

---

## Sistemas transversales

### Regeneracion de KI
- [x] Regeneracion pasiva lenta en estado neutral (2 pts/0.5s = 4 pts/s)
- [x] Gesto de recarga activa: GestureType.RECHARGING (tecla R) — recarga rapida
- [x] Recibir dano genera KI (5 pts por impacto)

### IA del enemigo
- [x] Ataques basicos automaticos con intervalos aleatorios (3-6s)
- [x] Logica de decision para ataques especiales (segun KI disponible y NP)
- [ ] Respuesta a ataques del jugador (defensa, esquive)
- [ ] Activacion de melee cuando el jugador tiene KI bajo

### WebXR Hand Tracking (Meta Quest)
- [x] Mapear gestos de manos a acciones del juego (GestureRecognizer v2, joints W3C)
- [ ] Calibracion inicial de posicion del jugador
- [ ] Feedback haptico en acciones clave

---

## Post-MVP
- [ ] Mas personajes con ataques especiales propios
- [ ] Multiples escenarios
- [ ] Sistema de sonido y musica
- [ ] Sistema de progresion y niveles
- [ ] Modo multijugador en red

## UI / Pantalla de Inicio

- [x] Redisenar pantalla de inicio con layout de tres secciones navegables
- [x] Seccion principal: titulo, logo, boton de inicio y accesos a Tutorial/Changelog
- [x] Seccion Tutorial: guia paso a paso con controles de teclado y gestos VR
- [x] Seccion Changelog: historial de versiones del juego
- [x] Animacion de fondo con particulas de KI en la pantalla de inicio
- [x] Navegacion con botones entre secciones

## Ataques Especiales — Niveles de Carga

- [x] Kamehameha nivel minimo (2s, 40 KI, daño base 40)
- [x] Kamehameha nivel medio (5s, 60 KI, daño base 70)
- [x] Kamehameha nivel maximo (8s, 80 KI, daño base 100)
- [x] Final Flash nivel minimo (3s, 60 KI, daño base 60)
- [x] Final Flash nivel medio (6s, 90 KI, daño base 110)
- [x] Final Flash nivel maximo (10s, 120 KI, daño base 150)
- [x] Calculo de daño final: daño base * factor NP del jugador
- [x] HUD muestra nivel de carga actual (MINIMO / MEDIO / MAXIMO) durante la carga
- [x] HUD muestra daño estimado en tiempo real segun carga acumulada

---

## Sesion 26/03/2026 — Completado

- [x] Fuente Saiyan Sans aplicada en StartScreen.ts (todos los botones y titulos)
- [x] Fuente Saiyan Sans aplicada en HUD.ts (todos los botones de control)
- [x] Fuente Saiyan Sans como fuente global en index.html (body)
- [x] IA del enemigo: ataques automaticos cada 3-6s (basico, Kamehameha, Final Flash)
- [x] IA del enemigo: regeneracion de KI propia
- [x] IA del enemigo: logica de decision segun NP y KI disponible
- [x] Indicador visual de ataque del enemigo en el HUD
- [x] VoiceRecognizer.ts: reconocimiento de voz con Web Speech API
- [x] Comandos de voz: "Kamehameha" y "Final Flash" activan ataques especiales
- [x] Bonus de +5 NP al gritar el nombre del ataque
- [x] Indicador de transcripcion de voz en el HUD
- [x] ResultScreen.ts: pantalla de victoria/derrota con estadisticas
- [x] Pantalla de resultado: rango de combate (Novato/Luchador/Guerrero/Elite/Legendario)
- [x] Pantalla de resultado: duracion del combate, NP final, KI restante
- [x] Pantalla de resultado: botones Reiniciar y Menu
- [x] CombatSystem: gameOver y winner en GameStats
- [x] CombatSystem: onGameOver callback para notificar fin del combate
- [x] CombatSystem: enemyAttacking y enemyAttackName en GameStats
- [x] Correccion de errores TypeScript criticos en archivos del juego

---

## Rediseno visual (referencia ejemplo_ui.jpeg)

- [x] HUD: mover paneles a esquinas inferiores (izquierda: barras HP/KI, derecha: minimapa/KI)
- [x] HUD: paneles con forma de escudo/tech redondeado estilo azul metalico
- [x] HUD: barras de vida (verde/rojo) y KI (cyan) integradas en el panel
- [x] HUD: botones de control compactos en fila inferior central
- [x] Entorno: cielo dramatico naranja-dorado al atardecer (clearColor)
- [x] Entorno: suelo de tierra rojiza de canon
- [x] Entorno: formaciones rocosas de canon a los lados y fondo
- [x] Entorno: nubes semitransparentes en el horizonte
- [x] Entorno: iluminacion calida direccional (sol bajo, dorado-naranja)
- [x] Manos: mas grandes y prominentes (palma + 4 dedos + pulgar)
- [x] Manos: aura de KI azul alrededor de las manos (particulas)
- [x] Manos: posicion mas baja y separada (como en la imagen)

---

## Bug: carga infinita al entrar VR en Meta Quest 3

- [x] Reemplazar initWebXR() en Game.ts con patron correcto (xrInput, optionalFeatures array)
- [x] Corregir mismatch local-floor (init) vs local (enterXRAsync) — ahora consistente
- [x] Agregar timeout de 12s con fallback si WebXR no responde
- [x] Agregar verificacion previa navigator.xr.isSessionSupported antes de init
- [x] Ocultar manos estaticas 3D cuando hand tracking esta activo en VR (onStateChangedObservable)
- [x] GestureRecognizer.ts ya existe — error de Vite era stale cache
- [x] Corregir error TS2554 en routers.ts (storageGet con argumento extra)

---

## Bug: gestos no funcionan en VR + botón menú

- [x] Diagnosticado: joints accedidos por índice numérico (incorrecto), umbrales invertidos en Z
- [x] Reescrito GestureRecognizer v2 con acceso por nombre de joint (W3C), umbrales calibrados Quest 3
- [x] Cooldown por gesto para evitar spam de acciones (600ms ataque, 200ms carga)
- [x] extractHandJoints() exportada con fallback numérico para compatibilidad
- [x] Botón Menú [M] agregado en la barra de controles del HUD (rojo diferenciado)
- [x] disposeAndExit() en Game.ts: sale de XR, detiene voz, libera motor
- [x] main.ts refactorizado: goToMenu() recrea StartScreen sin window.location.reload()

---

## Debug gestos + bullet time mejorado

- [x] Changelog en juego (StartScreen) actualizado a v0.9.0 con historial completo (8 versiones)
- [x] Badge de version en pantalla principal actualizado de v0.3.0 a v0.9.0
- [x] CHANGELOG.md creado en raiz del proyecto con formato Keep a Changelog
- [x] Overlay de debug (GestureDebugOverlay.ts): joints L/R, gesto, historial de cambios
- [x] Overlay muestra gesto detectado con color segun tipo
- [x] Overlay muestra si hand tracking esta activo (verde) o sin datos (rojo)
- [x] Toggle con tecla G (desktop) y boton [DBG] en HUD
- [x] Bullet time Kamehameha: 3500ms a 0.18x (antes 1500ms a 0.25x)
- [x] Bullet time Final Flash: 4500ms a 0.12x (antes 2000ms a 0.2x)
- [x] Transicion suave de entrada (300ms ramp-in) y salida (500ms ramp-out)
- [x] Efecto visual: viñeta purpura mas intensa, aberracion cromatica, etiqueta BULLET TIME

---

## Tipografia body
- [x] Fuente Rajdhani (Google Fonts, 400/500/600/700) agregada en index.html
- [x] Variable CSS --font-body definida en :root de index.html
- [x] HUD: contenedor principal cambiado a --font-body (labels, barras, botones secundarios)
- [x] StartScreen: contenedor cambiado a --font-body; botones de navegacion y textos descriptivos
- [x] StartScreen: --font-saiyan mantenido en boton Iniciar Combate (titulo principal)
- [x] ResultScreen: contenedor cambiado a --font-body; botones Reiniciar y Menu
- [x] ResultScreen: --font-saiyan mantenido solo en el titulo VICTORIA/DERROTA
- [x] GestureDebugOverlay: cambiado de Courier New a --font-body

---

## Bug: HUD y debug overlay invisibles en VR + gestos sin funcionar
- [x] HUD invisible en VR — corregido con div #xr-overlay + feature dom-overlay en WebXR
- [x] Debug overlay invisible en VR — montado en xrOverlay, se activa automáticamente al entrar en XR
- [x] Gestos: bug raíz identificado — handTracking.hands.get() siempre retornaba undefined
- [x] Corregido: loop detecta automáticamente la API correcta (leftHand, Map, controllers)
- [x] Debug overlay muestra qué API se usó para acceder a las manos
- [x] Debug overlay se actualiza siempre (no solo cuando está visible)
- [x] main.ts: xrOverlay creado antes del Game y pasado como parámetro al constructor

---

## Rediseño botones HUD
- [x] Panel ATAQUE (Atacar, Cargar, Kamehameha, Final Flash) al centro-derecho
- [x] Panel DEFENSA (Bloquear, Esquivar, Recargar) al centro-izquierdo
- [x] Botones de sistema (Menu, DBG) en esquina inferior central

---

## Bug: botones ResultScreen no funcionan
- [x] Bug 1: onAction se registraba dentro de onGameOver (después de render) — movido antes de show()
- [x] Bug 2: pointer-events:none heredado bloqueaba los clics — agregado pointer-events:auto en overlay
- [x] Bug 3: z-index del overlay subido de 30 a 50 para estar sobre el HUD
- [x] Botón Menú ahora usa menuCallback limpio en lugar de window.location.reload()

---

## Bug persistente VR (sesión 26/03 tarde)
- [x] xrOverlay movido a document.body (hijo directo) con position:fixed — requerido por spec dom-overlay
- [x] domOverlay pasado correctamente como propiedad del objeto config (no con spread)
- [x] Loop hand tracking reescrito con onHandAddedObservable + fallback cache cada 120 frames
- [x] extractHandJoints mejorado: 4 métodos de acceso (getJointMesh, _jointMeshes Map, jointMeshes array, joints objeto)
- [x] Debug overlay muestra estado en tiempo real: L/R detectadas, API usada, joints, gesto

---

## Bug: HUD invisible en VR (gestos funcionan, HUD no)
- [x] HUD container: cambiado a position:fixed con width/height 100% explícitos
- [x] GestureDebugOverlay: cambiado a position:fixed
- [x] ResultScreen: cambiado a position:fixed
- [x] xrOverlay: pointer-events:auto + background:transparent (requerido por spec dom-overlay)
- [x] Debug overlay: activación automática via onStateChangedObservable (no sessiongranted)
- [x] Debug overlay: show() llamado desde Game.ts al entrar en VR (state === 2)

---

## Bug: botones StartScreen no funcionan
- [x] Causa raíz: xrOverlay (z-index:9999, pointer-events:auto) cubría toda la pantalla e interceptaba los clics
- [x] Solución: pointer-events:none por defecto en xrOverlay; se activa solo en startGame() y se desactiva en goToMenu()
