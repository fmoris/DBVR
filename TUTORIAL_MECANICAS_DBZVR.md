# 🐉 Tutorial Completo de Mecánicas — Dragon Ball VR (DBZVR)

> Guía práctica organizada **por fase y secuencia de combate** para saber exactamente qué hacer, qué gesto o botón ejecutar y cuánto Ki/BP cuesta o devuelve cada acción en **Meta Quest VR**.

---

## 0. Reglas Fundamentales del Combate (Sin barra de vida)

En DBZVR **no existe barra de HP tradicional**: ganas por **Battle Power (BP / NP)**, dominio de **Ki** y remate cinematográfico.

* **Ki (0–100):** Tu combustible táctico para atacar, esquivar, defender y transformar.
  * Regeneración pasiva: **+1.0 Ki/s** (tras **2.0 s** sin gastar Ki).
  * **Resistencia al daño:** Al perder BP por un golpe, recuperas Ki proporcionalmente (`0.0055 Ki` por BP perdido).
  * **⚠️ Último Aliento:** Si intentas lanzar Ki Blasts, Súpere o empujar un Choque con `0 Ki`, **quemas tu propio BP (Fuerza Vital)**. Si tu BP cae a **0**, pierdes el combate por **Agotamiento Vital**.
* **Battle Power (BP / NP):**
  * **Vegeta:** Base `10.000` · Máximo Base `20.000`.
  * **Goku:** Base `9.000` · Máximo Base `18.000`.
  * **Pisos Irreversibles de BP:** Conforme subes tu BP en una forma, aseguras mínimos de los que no puedes bajar al recibir golpes:
    * Al inicio: piso base `25%` (`>= 25%` máx. activo).
    * Al llegar al `>= 60%` ➔ piso `50%`.
    * Al llegar al `>= 80%` ➔ piso `75%`.
    * Al llegar al `>= 98%` ➔ piso `85%`.
    * *(Al transformarte o revertir, el piso se ajusta para que el BP pueda seguir oscilando en combate).*
* **¿Cómo se gana el combate?**
  1. **Finisher en Estado Zenkai:** Alcanzar **Estado Zenkai** (por Dominio o Comeback) y conectar un Súper Ataque / Finisher sin que el rival lo esquive ni lo desvíe.
  2. **K.O. por Agotamiento Vital:** Reducir el BP del rival a `0` (o que se agote quemando fuerza vital sin Ki).

---

## 1. Fase 0 — Combate Libre y Posicionamiento (Modo Neutro)

| Acción | Cómo hacerlo (Mandos Quest) | Costo / Efecto | Cuándo usarlo |
| :--- | :--- | :--- | :--- |
| **Moverse horizontal** | Mueve **Stick Derecho o Izquierdo** (4 direcciones) | Paso rápido de **3.0 m** (`cooldown 0.16 s`) | Reacomodar distancia, esquivar líneas de tiro |
| **Subir / Bajar altura** | **Click Stick Derecho** = Subir · **Click Stick Izquierdo** = Bajar | Salto vertical **2.0 m** (máx. **+9.0 m** sobre suelo) | Ganar altura o bajar al suelo |
| **Recarga de Ki (2 Fases)** | **Fase 1:** Mantén ambos **Gatillos** a la altura de hombros/pecho.<br>**Fase 2:** Baja ambas manos cerradas hacia la **cintura**. | **+24.0 Ki/s** y **+250 BP/s** *(hasta techo `60%` BP máx.)* | Cuando el rival esté lejos, cegado o en humo |
| **Guardia Cruzada en X** | **Grip + Gatillo en ambas manos** y cruza los puños frente al pecho | Mitiga **85%** del daño BP (consume Ki al bloquear) | Cuando veas venir ráfagas o ataques y no puedas esquivar |
| **Scouter / Retícula** | Se fija automáticamente al apuntar / mirar al rival | • **Amarillo:** Fijado normal<br>• **Naranja:** Guardia rival abierta / humo<br>• **Violeta pulsante:** Rival estrellado en Cráter | Para leer ventanas gratuitas de ataque |

> **Nota Hand Tracking Puro:** Recarga Ki cruzando puños al pecho ➔ puños a la cadera; Guardia cruzando puños al pecho.

---

## 2. Fase 1 — Combate a Distancia (`Ki Blasts`, Presión y Cortina de Humo)

Los `Ki Blasts` son una herramienta táctica para **romper recargas**, **drenar Ki enemigo**, **acumular presión** y **abrir humo + emboscada**.

### Cómo disparar y defender Ki Blasts
| Tipo | Cómo hacerlo | Costo / Ventaja |
| :--- | :--- | :--- |
| **Ki Blast Rápido** | **Brazo extendido al frente + palma hacia adelante + Gatillo** *(sin Grip)* | **3.0 Ki** (**2.5 Ki** Vegeta). Corta la **Recarga de Ki** del rival (en tramo parejo/superior) y acumula `+1` stack de presión. |
| **Ki Blast Cargado** | Mantén **Gatillo** presionado **`>= 0.45 s`** con palma extendida *(hasta sentir pulso háptico)* y suelta | **9.0 Ki** (+`2.0 Ki/s` mientras cargas). Proyectil **Homing** que suma **`+3` stacks de golpe**, rompe **Poise** de Carga Súper y puede activar **Frenado Aéreo**. |
| **Desvío de Ki Blast** | Manotazo rápido dentro de distancia de captura sin ser golpeado pasivamente | **+12 Ki** y **+150 BP** por desvío limpio. |
| **Devolución Perfecta** | Manotazo **frontal rápido (`>= 2.2 m/s`)** contra un **Ki Blast Cargado** o el último proyectil de una ráfaga | Devuelve el tiro **teledirigido (Homing)** hacia el tirador original con máxima penetración. |

### Escalado por Ratio de BP (`BP_Atacante / BP_Defensor`)
* **Muy Inferior (`ratio <= 0.55`, No-Sell Saiyan):** Los tiros rápidos causan **0 daño / 0 drenaje / 0 stacks** (sin regalos de Ki). El **Cargado** sí hace `25%` de daño y `+1 stack`. *(En **Furia**, recibes `+0.35` al ratio efectivo Anti-Snowball).*
* **Parejo (`0.75 <= ratio < 1.35`):** Drena **3 Ki** (rápido) / **9 Ki** (cargado); requiere **3 stacks** en ventana de `2.8 s` para abrir guardia.
* **Superior (`1.35 <= ratio < 1.80`):** Solo **2 stacks** abren guardia; drena **4.5 / 13 Ki**; corta cargas Súper; `+1` golpe en emboscada.
* **Abrumador (`>= 1.80`):** **2 stacks** abren guardia; Cargado rompe guardia y activa **Frenado Aéreo**; **`+2` golpes** en emboscada.

### ¿Qué hacer cuando saturas los stacks de presión del rival?
Se despliega una **Cortina de Humo** y el Scouter avisa **`💥 ¡GUARDIA RIVAL ABIERTA!`** (`~1.6–2.2 s`). Tienes **2 opciones inmediatas**:
1. **Melee Dash Gratuito (0 Ki):** Lanza un puño al frente ➔ entras al Melee con **`+1` o `+2` golpes extra** y sin gastar los `10 Ki` del Dash.
2. **Súper Ataque Acelerado (`+25%` Velocidad de Carga):** Aprovecha que el rival está cegado en humo (sus reacciones de defensa AI bajan y tardan más) para disparar tu Súper.

---

## 3. Fase 2 — Acercamiento (`Melee Dash`)

* **Cómo activarlo:** Cierra **1 puño (`Grip + Gatillo`)** cerca del pecho/hombro (etapa de armado) y **lánzalo hacia adelante** con el rival fijado en tu Scouter. *(No cierres los dos puños a la vez o el juego priorizará recarga/transformación).*
* **Costo:** **10.0 Ki** (o **0 Ki** si entras durante una apertura de Cortina de Humo).
* **Peligro durante el vuelo:**
  * Si recibes un **Ki Blast Rápido** de un rival muy superior (`ratio >= 1.5`) o un **Ki Blast Cargado** (salvo que tú tengas Super Armor por `>= 1.5x BP`), tu Dash se corta y quedas brevemente aturdido (`0.35 s`).
  * Al llegar a distancia de combate cuerpo a cuerpo se abre la **Cúpula Holográfica de Melee**.

---

## 4. Fase 3 — Minijuego de Melee (Cúpula Holográfica · Administrador de Ki)

Al cerrarse el Melee comienza un duelo rítmico por turnos de **Ataque ➔ Defensa**. En todo momento verás:
1. **HUD Superior + Barra Doble de Ki:** Muestra **TU KI** (barra izquierda cian; se vuelve **roja `⚠️ KI CRÍTICO`** por debajo de **22 Ki**) vs. **RIVAL KI** (barra derecha naranja), con popups instantáneos (`-11 KI`, `+14 KI`).
2. **Tarjeta Fija (esquina inferior izquierda):** Cambia sola según te toque Atacar (**⭕ CÍRCULOS**) o Defender (**⬜ CUADRADOS**).

---

### A) Turno de Ataque (**⭕ CÍRCULOS**)

Dispones de **4 a 7 golpes** por secuencia según transformación y ventaja de BP *(hasta **8 golpes** con Emboscada por Ki Blast)*.

#### Requisitos físicos para que cuente cada golpe (anti-toque falso):
1. Puño cerrado (**Grip + Gatillo**).
2. Recorrido real del brazo **`>= 22 cm`** en cono frontal hacia el objetivo.
3. Velocidad **`>= 1.55 m/s`** en golpe rápido (o **`>= 1.35 m/s`** si está cargado).
4. **Retraer el puño `>= 20 cm`** tras cada impacto antes de volver a golpear.

#### Niveles de Potencia Física y Costos de Ki:
| Tipo de Golpe | Cómo ejecutarlo | Costo de Ki | Efecto |
| :--- | :--- | :---: | :--- |
| **~ Suave** | Golpe corto/lento que apenas pasa el mínimo | Costo según carga | **0.60×** daño BP. Evítalo para no desperdiciar Ki. |
| **💥 ¡SÓLIDO!** | Puñetazo firme (`>= 1.95 m/s` y `>= 24 cm`, o cargado `>= 1.60 m/s`) | Costo según carga | **1.00×** daño BP normal + impacto visual en el rival. |
| **⚡ ¡SÓNICO!** | Puñetazo explosivo (`>= 2.85 m/s` y `>= 30 cm`, o cargado `>= 2.40 m/s` y `>= 28 cm`) | Costo **− 1.5 Ki reembolsados** | **1.35×** daño BP, onda expansiva, micro hit-stop, **desplazamiento largo por la arena** y abre eventos Lore. |
| **Golpe Rápido** | Impacto sin sostener carga previa (`< 0.50 s`) | **−5.0 Ki** *(−3.5 si Sónico)* | Base para acumular combo ahorrando Ki. |
| **Golpe Cargado (Nv.2)** | Mantén puño cerrado **`0.50 s .. 1.09 s`** (esfera crece) y golpea | **−11.0 Ki** *(−9.5 si Sónico)* | Mayor daño, onda de choque y fuerza bloqueo pesado. |
| **Cargado V3 (Nv.3)** | Mantén puño **`>= 1.10 s`** y golpea (arriba o al frente) | **−16.0 Ki** | Gran daño; **NO cancela el resto del combo** — programa lanzamiento al final si conecta sin bloqueo. |
| **🔨 Martillazo DBZ** | **Ambos puños arriba `>= 0.85 s`** y bájalos fuerte juntos | **−22.0 Ki** | Rompe bloqueos de 1 mano; si pasa limpio estrella al rival contra el suelo al cerrar secuencia. |
| **Cancelar y Ahorrar Ki** | Mueve **Stick Derecho hacia atrás (`↓`)** sin haber pegado | **0 Ki** | Cancela la ofensiva antes de gastar Ki si necesitas recargar o escapar. |

> **Regla clave de Ki:** Conectar golpes sin bloqueo **NO te regala Ki gratis**; en cambio sí drena **−6 / −12 / −16 Ki** al defensor por aturdimiento. ¡Piensa cuántos golpes cargar para no quedarte sin Ki cuando te toque defender!

---

### B) Turno de Defensa (**⬜ CUADRADOS**)

Cuando el rival te ataca aparece un **Aro de Timing** encogiéndose alrededor del cuadrado activo. **Lee el Semáforo:**

* 🔵/🟣 **Aro Cian (o Violeta = Martillazo) (`> 0.24 s`):** **ESPERA.** *No spamees el Gatillo demasiado pronto (`> 0.32 s`)* porque bloqueará tu Parry/Desvío de esa nota (aunque **la Guardia Cruzada X y el Z-Vanish siguen funcionando**).
* 🟢 **Aro Verde (`0.14 s .. 0.24 s` + pulso háptico guía):** **¡YA! Momento óptimo de Desvío o Guardia.**
* 🟡 **Aro Dorado (`<= 0.14 s`):** **¡PARRY PERFECTO!**

| Defensa | Cómo hacerla en ventana | Costo / Recompensa de Ki | Puntos de Dominio & Efecto |
| :--- | :--- | :---: | :--- |
| **✨ Parry Perfecto** | En **Aro Dorado (`<= 0.14 s`)**, coloca tu mano en el `⬜` y pulsa **Gatillo** *(sin mover brazo rápido)* | **+14.0 Ki** *(rival −10 Ki)* | **¡Roba el turno al instante!**, teletransporta (Z-Blink) y si estás en **Furia** activa **Zenkai Comeback**. |
| **✋ Desvío con 1 Mano** | En **Aro Verde/Dorado (`<= 0.24 s`)**, mete la mano en el `⬜` con **Palma Abierta** en movimiento (`>= 0.45 m/s`, sin botones) **O** pulsa solo **Gatillo** *(sin Grip)* | **+5.0 Ki** *(Rápido)*<br>**−6.0 Ki** *(Cargado)*<br>**−10.0 Ki** *(V3)* | **+1.00** (Rápido) / **+0.50** (Cargado) / **+0.75** (V3). Mitiga o anula daño. *Nota: No frena el Martillazo.* |
| **💨 Z-Vanish Defensivo** | Flick rápido con **Stick Izq o Der** dentro de la ventana (`<= 0.28 s`) | **−14.0 Ki** | **+1.00** y **0 daño**. Teletransporta a otra zona de la arena; si el rival tiene Ki puede desatar **Guerra de Z-Vanish**. |
| **⚡ Choque de Puños** | En `⬜` *(salvo Martillazo)*, lanza tu **puño cerrado (`Grip+Trigger`, `>= 0.85 m/s`)** | **+4.0 Ki** *(parejo)* o **+8.0 Ki** *(si BP `> 1.4x`)* | Si BP defensor `>= 70%`: **0 daño**, quita **−1 golpe** al siguiente turno rival (`+0.65 / +1.00`), y puede abrir **Choque Frenético**. |
| **🛡️ Guardia Cruzada X** | Mantén **Grip + Gatillo en ambos mandos** cruzados frente al pecho *(siempre disponible)* | **−7 / −12 / −16 / −20 Ki** + **+2 Ki** extra por cada bloqueo seguido en X | **+0.25**, solo entra **15% daño**. Si bloqueas un Martillazo con BP `< 1.25x`, cortas el melee. *Abusar en X puede causar Desgarre de Guardia.* |
| **💥 Onda Explosiva (Kiai)** | Tras recibir **`>= 2` golpes sin bloquear** en la ronda, **abre ambos brazos (`>= 75 cm`) + 2 Grips** | **−22.0 Ki** | Corta el combo enemigo al instante con explosión de Ki (`160 BP`) y los separa `10 m`. |

* **Inversión de Roles al final de la ronda:** Si tu puntuación defensiva total **`S_def > N / 2`** (más del 50% de los golpes), **robas la ofensiva**; si no, el atacante continúa.
* **⚡ Ruptura de Ki (`Ki == 0`):** Si uno de los dos llega a **0 Ki**, el otro gana **1 Golpe Imbloqueable** en una caja central gigante (`500 BP` y lanzamiento lejos).

---

### C) Los 6 Eventos Dinámicos de Lore DBZ (Dentro del Melee)

| Evento | Cuándo se dispara | Qué debes hacer | Resultado |
| :--- | :--- | :--- | :--- |
| **1. ⚡ Choque Frenético de Puños** | Tras un **Choque de Puños** con BP competitivo (`0.65–1.50`) y ambos con `>= 20 Ki` | Golpea **IZQ–DER sin parar** (`>= 1.40 m/s`). *Drena `6 Ki/s` a ambos.* | Quien gane la barra tira y afloja inflige `650–950 BP`, gana `+10 Ki` y toma la ofensiva. |
| **2. 🌌 Caída del Meteoro** | Al terminar un combo tras conectar `>= 2` golpes *(con al menos 1 Sónico o V3 Arriba)* y `>= 12 Ki` | **Paso 1:** Sube manos o Stick `↑` (**−12 Ki**) para aparecer sobre él.<br>**Paso 2:** Baja ambos puños fuerte sobre el orbe violeta. | Inflige `480 BP`, deja al rival **aturdido en un Cráter (`3.5 s`)** y te posiciona en altura (`11 m`) con **+35% velocidad de carga de Súper** y el rival **sin Z-Vanish**. |
| **3. 💨 Guerra de Z-Vanish** | Tras un **Z-Vanish Defensivo** si el atacante tiene `>= 18 Ki` y BP `>= 0.70x` | Quien persigue pulsa **Stick (12 Ki/salto)** hasta 3 saltos; **Guardia X** para plantarse (o recibe patada a la espalda si fallas). | Quien gane el último contra-blink conecta patada (`360 BP`) o ambos se separan agotados. |
| **4. 💥 Desgarre de Guardia** | Si el defensor abusa de **Guardia Cruzada X (`>= 2` seguidos)** o queda con `<= 22 Ki` | **Atacante:** Golpea fuerte (`>= 1.65 m/s`) el orbe naranja para romper guardia.<br>**Defensor:** Abre ambos brazos + 2 Grips (**−15 Ki**) para repelerlo. | Rompe la guardia (`1.6 s` vendida, `+320 BP`) y roba iniciativa, o repele a `9 m`. |
| **5. 🛡️ Onda Explosiva (Kiai)** | En Defensa, tras recibir **`>= 2` golpes seguidos** y tener `>= 22 Ki` | Abre ambos brazos (`>= 75 cm`) apretando **ambos Grips**. | Gasta **22 Ki**, golpea al atacante (`160 BP`) y termina el melee separándolos a `10 m`. |
| **6. 🔥 Intercambio Sónico Z-Burst** | A mitad de combo largo (`>= 3` golpes, `>= 2` Sónicos o Furia/Transf.) con `>= 15 Ki` | Golpea el **Orbe Dorado** hasta **3 teletransportes seguidos** (`−6 Ki` por salto). **Stick Der `↓`** si quieres guardar Ki y salir. | Hasta 3 impactos extra (`240 BP c/u` y `+140 NP`) recorriendo toda la arena y lanzamiento final. |

---

## 5. Fase 4 — Súper Ataques de Ki y Secuencia `Bullet-Time`

### A) Técnicas de Súper Ataque (Modo Mandos · Hold `0.18 s` en pose ➔ Carga ➔ Empuje al frente)
* **Vegeta:**
  * **Galick Ho (`28 Ki`, Base+, `1800 BP` · carga min `0.45 s`):** Ambos **Grips** juntos al costado/cadera ➔ empuja al frente.
  * **Big Bang Attack (`35 Ki`, Base+, `3200 BP` · carga min `0.55 s`):** **1 brazo** extendido al frente con palma abierta y **Grip** *(sin Gatillo)* ➔ mantén al frente al cargar.
  * **Final Flash (`45 Ki`, requiere `SSJ` o `Zenkai`, `FINISHER`, `0.55 s`):** Ambos brazos abiertos en **cruz T-Pose con Grips** ➔ junta ambos al frente.
* **Goku:**
  * **Kamehameha (`28 Ki` / Super Kamehameha `45 Ki` en `SSJ`, `0.45 s`):** Ambos **Grips** recogidos en la **cadera** ➔ empuja ambas manos al frente.
  * **Genkidama (`45 Ki`, **prohibido si estás transformado**, `6000 BP`, `0.65 s`):** Ambos brazos al **cielo con Grips** ➔ baja hacia el frente.

> **Poise y Explosión en Área (AoE):** Mientras cargas un Súper absorbes parte del golpe hasta romper tu Poise. Si un Súper explota cerca aunque falle el tiro directo, la **onda expansiva** daña BP y empuja según la diferencia de BP (o **0 BP / 0 empuje** si el defensor es abrumadoramente superior).

### B) Estás en `Bullet-Time` recibiendo un Súper (5 Respuestas en orden)

Cuando te disparan un Súper el tiempo se ralentiza (ventana **más larga si tienes mayor BP, Furia o Zenkai**, y muy corta si estás en **Cráter** o con menos BP):

1. **🔥 Choque de Poderes (Beam Clash):** Prepara y dispara cualquier Súper tuyo utilizable (`>= 15 Ki`) apuntando al frente.
2. **💨 Z-Vanish Esquive:** Flick rápido con **Stick Izq o Der** (`15 Ki`). *No disponible si estás aturdido en Cráter.*
3. **✋ Aguantar el Rayo con las Manos:** Extiende ambas manos al frente apretando **ambos Grips (sin Gatillo)** y **agita rápido los controles** para disiparlo (`9 Ki/s`).
4. **🥋 Desvío al Cielo:** Si tu BP es **`>= 70%`** del atacante, golpea la cabeza del haz con una mano a **`> 2.0 m/s`** ➔ lo desvías a la estratósfera (**+25 Ki, +300 BP**; si estás en Furia activa **Zenkai Comeback**).
5. **🛡️ Contener en Guardia Cruzada X:** Puños cerrados (`Grip+Gatillo`) cruzados al pecho (recibes daño contenido en lugar de impacto directo).

---

## 6. Fase 5 — Secuencia de Choque de Poderes (`Beam Clash`)

Cuando chocan dos Súper haces, el tiempo corre al **`50%` (`~3.5–4.0 s`)**:
1. **Mantén ambos Grips sostenidos con manos al frente** *(si sueltas ambos Grips o bajas manos de la postura Fase 2, dejas de empujar)*.
2. **Agita ambos controles** con fuerza **Y pulsa repetidamente ambos Gatillos** para bombear empuje.
3. Si estás en **Estado Zenkai**, tu empuje se multiplica por **1.45×**.
4. Si llegas a **0 Ki**, entras en **Último Aliento** quemando tu propio **BP**. Quien llegue al extremo (`15% / 85%`) o domine al acabarse el tiempo gana el choque.

---

## 7. Fase 6 — Frenado Aéreo (`Air Brake`) y Choque con Muralla

Cuando un ataque pesado o Martillazo te manda volando a gran velocidad:
* Aparece el HUD **`⚡ [◀L▶] ¡AGITA LOS CONTROLES! [◀R▶] X%`**.
* **Qué hacer:** Agita **ambos controles físicos alternando direcciones rápidamente** (los dos mandos juntos rinden `100%` de eficiencia vs. `38%` con uno solo) hasta llegar al **`100%`** antes de impactar el suelo o la muralla exterior.
* Si no logras frenar y golpeas el límite del escenario, quedas incrustado **`0.65 s` (Wall-Stick)** antes de caer.

---

## 8. Fase 7 — Transformaciones, Furia, Determinación, Zenkai y Mini-Escenas

### A) Transformaciones
| Personaje | Fases (Multiplicador BP · Drenaje Ki/s) | Requisitos de Desbloqueo | Controles |
| :--- | :--- | :--- | :--- |
| **Vegeta** | **SSJ (`x2.0` · `2.1/s`)** ➔ **Super Vegeta (`x3.5` · `3.2/s`)** ➔ **SSB (`x5.0` · `4.4/s`)** ➔ **Ultra Ego (`x8.0` · `5.5/s`)** | • **Fase 1:** `>=75%` BP máx, bajar a `<=78%` BP base o entrar en Furia<br>• **Fase 2:** Ya en Fase 1+ y `>=85%` máx, `<=68%` base o Furia<br>• **Fase 3:** Entrar en **Estado Zenkai**<br>• **Fase 4:** En Fase 3+ con **Zenkai** o piso **`>=75%`** | • **Avanzar forma:** Botón **`A` / `X`** *o* mantener **Puños en la cintura (`Grip+Gatillo`) `1.2 s`**.<br>• **Revertir a Base:** Botón **`B` / `Y`**. |
| **Goku** | **SSJ (`x2.0` · `1.8/s`)** ➔ **SSJ2 (`x3.5` · `2.8/s`)** ➔ **SSB (`x5.0` · `4.0/s`)** ➔ **Ultra Instinto (`x8.0` · `5.5/s`)** | Mismos criterios de combate | *(Recuerda: Goku NO puede usar Genkidama transformado).* |

### B) Estados de Remontada (`Furia`, `Determinación` y `Zenkai`)
* **🔥 Furia (Comeback Pasivo):** Se activa si estás **`>= 30%` atrás en BP** *(o `22%` con el buff Orgullo Saiyan de Vegeta)*. Duplica velocidad de **Recarga Ki (`+100%`)**, **duplica ganancia de BP** y te da **`+0.35`** en ratio de `Ki Blasts`.
* **🌟 Momento de Determinación (1 vez por combate):** Mientras estés en **Furia**, cruza **ambos brazos al pecho apretando solo `Grips` (SIN Gatillos)** durante **`2.8 s`** sin recibir golpes pesados ➔ otorga **`+45 Ki`**, **`+25%` de tu déficit de BP** y despierta **Zenkai Comeback**.
* **⚡ Estado Zenkai:**
  * **Por Dominio:** Liderar en **`>= 40%` BP** y estar **`>= 75%`** de tu BP máximo activo.
  * **Por Comeback (1 intento heroico):** Al lograr **Parry Perfecto en Melee**, **Desvío de Súper con la mano** o **Determinación** estando en Furia. Tienes **1 oportunidad** de rematar con Súper/Finisher; si fallas, quedas penalizado con `0 Ki` y mitad de BP.

### C) Las 7 Mini-Escenas Dramáticas Contextuales
Durante la pelea pueden aparecer minijuegos breves que ralentizan el mundo (`0.04x`) para premiarte con buffs temporales o permanentes:

| Mini-Escena | Cómo se completa | Recompensa |
| :--- | :--- | :--- |
| **Corazón Sereno** *(Goku)* | Eleva palmas a **3 anillos dorados** en el cielo (`3.5 s`) | **Permanente:** `+20%` Recarga Ki · `+18%` Vel. Carga Súper |
| **Pulso Kaioken** *(Goku)* | Extiende manos al ritmo de **2 pulsos carmesí** (`3.0 s`) | **15 s:** `+30%` Daño Total · `+25%` Vel. Vuelo |
| **Orgullo del Príncipe** *(Vegeta)* | Destroza el núcleo con **5 golpes rápidos** (`3.5 s`) | **Permanente:** Furia al `22%` · `+15%` Daño Súper |
| **Precisión Real** *(Vegeta)* | Apunta y dispara **Gatillo a 3 blancos** (`3.2 s`) | **16 s:** `2x` Carga Ki Blast · `−50%` Coste Ki Blast |
| **Reflejos Z** *(Todos)* | Toca los **3 orbes de presión** en secuencia (`3.2 s`) | **20 s:** `+500 BP` · `+25%` Ventana Bullet-Time |
| **Ruptura de Límites** *(Todos)* | Abre los brazos con **Grips** rompiendo **3 anillos** (`3.5 s`) | **Permanente:** `+12%` Ganancia BP · `−15%` Drenaje Transf. |
| **Sobrecarga de Aura** *(Todos)* | Agita ambos puños **6 veces** para estabilizar Ki (`3.5 s`) | **18 s:** `+35 Ki` instantáneo · `2x` Ki Pasivo · `−25%` Coste Blast |

---

## 9. Guía Rápida de Decisión ("¿Qué hago si...?")

* **El rival está recargando Ki lejos:** Lánzale **Ki Blast Rápido o Cargado** para cortarle la carga y robar ventaja de Ki.
* **Saturaste al rival y salió Humo (`💥 ¡GUARDIA RIVAL ABIERTA!`):** Lanza **Melee Dash gratis (`0 Ki`, +1/+2 golpes)** o carga un **Súper un `25%` más rápido**.
* **Estás dentro del Melee en ataque:** Alterna **Golpes Rápidos Sónicos** (`−3.5 Ki` neto) para ahorrar Ki y reserva golpes **Cargados/V3** para activar **Caída del Meteoro**. Si estás en **`< 22 Ki`**, usa **Stick `↓`** antes de pegar para no llegar seco a defender.
* **Estás defendiendo en Melee y ves venir el golpe:** Espera a que el aro cambie de Azul a **Verde (`¡YA!`)** para Desvío con palma abierta (`+5 Ki`), o **Dorado** para Parry (`+14 Ki` y robas turno). Si te apuraste (`⚠️ ¡MUY PRONTO!`), **cierra Puños en X al pecho (`Grip+Gatillo`)** — la Guardia Cruzada siempre te protege.
* **Recibes varios golpes seguidos en Melee y tienes `>= 22 Ki`:** Abre ambos brazos con **ambos Grips** para lanzar **Onda Explosiva Kiai** y cortar su combo.
* **Acabas de estrellar al rival en el Cráter (`🌌 3.5 s`):** Carga **al instante** tu Súper (`Galick Ho` / `Final Flash` / `Kamehameha`) aprovechando el **`+35%` de velocidad** mientras no tiene `Z-Vanish`.
* **Vas `>= 30%` abajo en BP:** Activa **Determinación** (brazos al pecho solo **Grips** sin gatillos `2.8 s`), transfórmate y busca un **Parry** o **Desvío de Súper** para rematar con **Zenkai Comeback**.
