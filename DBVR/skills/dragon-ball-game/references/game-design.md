# Diseño de Juego Dragon Ball — Guía Canónica
> Referencia para implementar videojuegos con fidelidad a la fuente original

---

## DISEÑO DE ESCENARIOS (Arenas Canónicas)

### Escenarios por Saga
| Saga | Escenarios |
|------|-----------|
| DB Clásico | Dojo de Kame House, Torneo de las Artes Marciales (anfiteatro), Castillo del Rey Demon |
| Saiyan | Tierra (desierto), Espacio (cápsula) |
| Namek | Planeta Namek (cielo rosado, 3 soles), Nave de Freezer |
| Androide/Cell | Laboratorio del Dr. Gero, Sala del Tiempo y el Espacio, Cell Games Arena |
| Buu | Majin Buu's House, Otro Mundo, Interior de Buu |
| Super | Universo 7 (Tierra), Universo 6, Torneo del Poder (plataforma flotante en el vacío) |

---

## ARCOS NARRATIVOS PARA MISIONES

### Saga Saiyan
- **Objetivo:** Defender la Tierra de Raditz, Nappa y Vegeta
- **Gimmick narrativo:** Krillin, Piccolo, Yamcha mueren. Se activa buscar Dragon Balls en Namek.

### Saga Namek/Freezer
- **Objetivo:** Revivir a los muertos y enfrentar a Freezer
- **Progresión de poder:** Goku llega tarde, todos luchan sin él
- **Climax:** Primera transformación SSJ de Goku en Namek

### Saga Cell
- **Objetivo:** Detener a Cell antes de que alcance su forma perfecta
- **Mecánica de juego:** Cell puede absorber personajes si llega a ellos
- **Final:** Cell Games — torneo de 9 días

### Saga Buu
- **Objetivos en cascada:** Babidi → Dabura → Majin Vegeta → Super Buu → Kid Buu
- **Mecánica:** Genkidama final requiere energía de todos los habitantes de la Tierra

### Dragon Ball Super
- **Saga Beerus:** Tutorial de ki divino, Goku aprende SSGod
- **Saga Golden Freezer:** Freezer regresa entrenado
- **Torneo de Poder:** 8 universos, 10 guerreros cada uno, ring-out = eliminación

---

## SISTEMA DE FRASES/VOCES EN BATALLA

### Frases de Victoria por Personaje

**Goku:**
- "¡Eso estuvo genial! ¿Podemos pelear de nuevo?"
- "Tu poder fue increíble. ¡Gracias por el entrenamiento!"
- "¡Cada batalla me hace más fuerte!"

**Vegeta:**
- "Era predecible. Solo hay un príncipe de los Saiyans."
- "¿Eso fue todo? Decepcionante."
- "Mi orgullo... ¡jamás será doblegado!"

**Piccolo:**
- "Eso fue suficiente."
- "No tenías ninguna posibilidad."
- "Entrena más. Si es que puedes."

**Gohan:**
- "No me gusta pelear... pero no dejaré que lastimes a mis amigos."
- "Papá me enseñó esto."
- "¡¿ESO... FUE TODO TU PODER?!" (forma Beast)

**Freezer:**
- "Patético. Los débiles no merecen vivir."
- "¿Realmente pensaste que podías vencerme?"
- "Tendrás el honor de morir por mis manos."

**Cell:**
- "Soy la creación perfecta del Dr. Gero."
- "Tengo el ADN de los guerreros más fuertes del universo."
- "La perfección... ¡lo abarca todo!"

**Majin Buu:**
- "¡Buu quiere más pelea!"
- "Buu transformar en chocolate... ¡y comer!"

---

## SISTEMA DE PROGRESIÓN DE PODER

### Mecánica de "Zenkai" (Saiyan)
Los Saiyans se vuelven más fuertes tras recuperarse de heridas graves.
- **En juego:** Al ganar una batalla con menos del 20% de HP, el personaje recibe +15% de poder permanente en esa sesión.

### Mecánica de "Potencial Oculto"
Algunos personajes tienen un techo de poder bloqueado que se desbloquea bajo ciertas condiciones:
- Gohan: Al ver a un aliado en peligro, activa Beast
- Piccolo: Al fusionarse con otro Namekiano
- Krillin: Potencial liberado en Namek por Guru

### Entrenamiento entre Batallas
- Sala del Tiempo: 1 día exterior = 1 año interior
- Grado de Dios: Entrenamiento con Whis (x3 velocidad y poder)
- Kaioken: Solo entrenando en el Más Allá con Kaiosama

---

## MECÁNICAS DE FUSIÓN

### Potara (Permanente en Kai — temporal en mortales)
| Fusión | Personajes | Poder resultante |
|--------|-----------|-----------------|
| Vegetto | Goku + Vegeta | El más fuerte de la saga Buu |
| Kefura | Kefla (Kale + Caulifla) | Universo 6 fusionadas |

### Fusión de Baile (Metamoran) — 30 minutos
| Fusión | Personajes | Condición |
|--------|-----------|-----------|
| Gogeta | Goku + Vegeta | Baile sincronizado |
| Gotenks | Goten + Trunks | Baile sincronizado |

### Fusión Namekiana (Permanente)
- Piccolo + Nail = Piccolo x10 poder
- Piccolo + Kami = Piccolo Completo (ki aumenta x3 extra)

---

## VILLANOS SECUNDARIOS — DATOS PARA ENEMIGOS IA

### Nappa
- Nivel: 4,000
- Técnicas: Break Cannon (rayo de boca), Garden Bomber (pequeñas esferas)
- Comportamiento IA: Agresivo, baja defensa cuando ataca

### Raditz
- Nivel: 1,500
- Técnicas: Double Sunday (doble rayo de manos)
- Debilidad: Cola — agarrar la cola reduce su poder a 0

### Ginyu
- Nivel: 120,000
- Habilidad única: Intercambio de cuerpos (puede robar el personaje del jugador)
- Comportamiento IA: Espera momento de vulnerabilidad para intercambiar

### Babidi
- Nivel: Bajo, pero puede controlar mentes
- Habilidad: Majin — convierte guerreros en Majin (multiplica poder, pierden control)

### Zamasu (Fusión)
- Ki oscuro (rosa/magenta)
- Inmortal: No puede morir en su universo
- Debilidad: Trunks Sword of Hope (espada de ki colectivo)
