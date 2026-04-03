---
name: dragon-ball-game
description: >
  Crea videojuegos completos y fieles al universo Dragon Ball usando datos canónicos reales de personajes, poderes, niveles, transformaciones y frases. Usa este skill cuando el usuario quiera: crear un juego de Dragon Ball, implementar personajes con sus poderes reales, diseñar sistemas de combate con mecánicas canon, construir escenarios fieles a las sagas, generar IA de enemigos con comportamientos auténticos, o cualquier proyecto interactivo relacionado con la franquicia de Akira Toriyama. SIEMPRE usa este skill cuando el usuario mencione Dragon Ball junto a conceptos de juego, personaje, poder, saga, combate o videojuego.
---

# Dragon Ball Game Skill
> Datos verificados de fuentes canon: Daizenshuu oficial, Dragon Ball Wiki, Dragon Ball Super manga/anime, escritos aprobados por Akira Toriyama.

## Archivos de Referencia

Antes de generar cualquier juego o componente, lee los archivos necesarios:

- **`references/personajes.md`** — Personajes completos: stats, técnicas, transformaciones, frases, historia
- **`references/niveles-poder.md`** — Tabla de poderes canon, multiplicadores de transformación, mecánicas de sistema de combate
- **`references/game-design.md`** — Escenarios, arcos de historia, fusiones, villanos IA, sistema de progresión

**Regla de oro:** Si el dato no está en los archivos, usar conocimiento propio de Dragon Ball verificable, nunca inventar.

---

## Workflow de Creación

### Paso 1 — Identificar el tipo de juego solicitado

Determina primero qué tipo de juego quiere el usuario:

| Tipo | Descripción | Framework sugerido |
|------|-------------|-------------------|
| **Juego de combate 2D** | Estilo Budokai, luchadores 1v1 | HTML Canvas + JS |
| **RPG de texto** | Aventura narrativa por sagas | React / HTML |
| **Simulador de poder** | Calculadora de ki/fusiones | React |
| **Arena de torneos** | Torneo de las Artes Marciales | HTML Canvas |
| **Trivia/Quiz** | Preguntas del universo DB | React |
| **Roguelike** | Exploración con combate por turnos | React |

### Paso 2 — Seleccionar saga y personajes

Preguntar (o decidir según contexto) qué saga cubre el juego:
- DB Clásico (Torneo → Piccolo Daimao → 23° Torneo)
- DBZ Saiyans/Namek/Cell/Buu
- DBS (Beerus → Golden Frieza → Future Trunks → Torneo de Poder → DBS Super Hero)
- DBGT (Baby → Super 17 → Shadow Dragons)
- Crossover (mezcla de sagas)

### Paso 3 — Implementar con datos canon

**Para cada personaje jugable, incluir:**
```
{
  nombre: string,
  raza: string,
  kiBase: number,
  formas: [{ nombre, multiplicador, imagenDescripcion }],
  tecnicas: [{
    nombre: string,
    tipo: "ofensiva" | "defensiva" | "especial",
    dano: number,     // en % del ki base
    coste: number,    // ki consumido
    descripcion: string,  // descripción exacta del anime
    fraseCarga: string   // frase al ejecutar
  }],
  mecanicaEspecial: string,  // mecánica única del personaje
  frases: { victoria, derrota, tecnica }
}
```

### Paso 4 — Sistema de Combate

Implementar siguiendo las mecánicas del universo Dragon Ball:

#### Sistema de Ki
- Ki se recarga con el tiempo o al recibir daño (Zenkai)
- Saiyans: +15% poder tras recuperarse de daño crítico
- Namekianos: Regeneran HP gradualmente en combate
- Android 17/18: Ki infinito, no se agotan

#### Transformaciones en Batalla
- Las transformaciones son progresivas, no instantáneas
- Costo de mantener forma transformada (excepto SSGod y SSBlue que fluyen naturalmente)
- Diálogo/animación al transformarse con la frase canónica

#### Técnicas Especiales (HAX)
Implementar las mecánicas únicas documentadas:
```javascript
const mecanicasEspeciales = {
  goku: {
    instantTransmission: "teletransportación al enemigo, ignora distancia",
    zenkai: "al llegar a <20% HP, +15% ataque permanente en sesión"
  },
  vegeta: {
    ultraEgo: "recibe daño → +5% ataque por golpe recibido",
    finalExplosion: "KO mutual, solo usable en desesperación"
  },
  piccolo: {
    regeneracion: "recupera 2% HP por segundo",
    fusion: "puede absorber aliado Namekiano en arena para +50% poder"
  },
  cell: {
    herencia: "aprende la última técnica del oponente al verla 3 veces",
    absorcion: "ataque especial que drena HP del oponente"
  },
  majinBuu: {
    absorcion: "al ganar, copia 1 técnica del oponente derrotado",
    chocolateBeam: "transforma obstáculos del escenario en plataformas/items"
  },
  hit: {
    timeSkip: "primer ataque de cada round siempre evadido",
    evolucion: "si pelea continúa >3 rounds, Time-Skip se vuelve 2 ataques"
  }
}
```

---

## Tabla de Poderes para Mecánicas de Juego

### Niveles de Daño Relativos (normalizado para gameplay)

| Tier | Personaje/Forma | HP base | ATK base | DEF base |
|------|----------------|---------|---------|---------|
| 1 | Humano entrenado (Krillin, Yamcha) | 500 | 80 | 60 |
| 2 | Guerreros Z (Piccolo, Tien) | 800 | 120 | 100 |
| 3 | SSJ Goku/Vegeta | 1500 | 250 | 180 |
| 4 | SSJ2/Cell Perfecto | 2200 | 380 | 270 |
| 5 | SSJ3/Gotenks | 3000 | 500 | 350 |
| 6 | Beerus, SSGod | 5000 | 750 | 500 |
| 7 | SSBlue/Ultra Ego | 7500 | 1100 | 750 |
| 8 | Ultra Instinct | 12000 | 1800 | 1500 |
| S | Black Frieza, Beast Gohan | 20000 | 3000 | 2000 |

### Multiplicadores de Transformación en Juego
```javascript
const multiplicadores = {
  kaiokenX2: 2.0,
  kaiokenX4: 4.0,
  kaiokenX10: 10.0,
  kaiokenX20: 20.0,
  superSaiyan: 2.5,      // en juego (escalado desde x50)
  superSaiyan2: 3.5,
  superSaiyan3: 5.0,
  superSaiyanGod: 8.0,
  superSaiyanBlue: 10.0,
  ssbKaiokenX10: 15.0,
  ultraInstinctOmen: 18.0,
  ultraInstinct: 25.0,
  ultraEgo: 12.0,        // escala con daño recibido
  orangePiccolo: 8.0,
  beastGohan: 22.0,
  goldenFrieza: 12.0,
  blackFrieza: 30.0
}
```

---

## Plantillas de Código Reutilizables

### Template: Personaje Base
```javascript
const crearPersonaje = (nombre) => {
  const datos = PERSONAJES_DB[nombre]; // cargar desde references/personajes.md
  return {
    nombre: datos.nombre,
    hp: datos.hpBase,
    maxHp: datos.hpBase,
    ki: 0,
    maxKi: 100,
    ataque: datos.ataqueBase,
    defensa: datos.defensaBase,
    formaActual: "base",
    multiplicadorActual: 1,
    tecnicas: datos.tecnicas,
    mecanicaEspecial: datos.mecanicaEspecial,
    // Estado especial
    zenkai: 0,          // contador Saiyan
    stacksUltraEgo: 0,  // contador Vegeta
    timeSkipUsado: false // Hit
  }
}
```

### Template: Sistema de Batalla por Turnos
```javascript
const ejecutarTurno = (atacante, defensor, tecnica) => {
  // 1. Calcular daño base
  let dano = atacante.ataque * tecnica.multiplicadorDano * atacante.multiplicadorActual;
  
  // 2. Aplicar defensa
  dano -= defensor.defensa * defensor.multiplicadorActual * 0.3;
  
  // 3. Mecánicas especiales
  if (defensor.nombre === "Vegeta" && defensor.formaActual === "ultraEgo") {
    defensor.stacksUltraEgo++;
    defensor.ataque *= 1.05; // +5% ataque por golpe recibido
  }
  
  if (atacante.nombre === "Hit" && !atacante.timeSkipUsado) {
    atacante.timeSkipUsado = true;
    return { dano: dano * 1.5, mensaje: "¡Time-Skip! El golpe es inevitable." }
  }
  
  // 4. Zenkai Saiyan
  if (defensor.raza === "Saiyan" && defensor.hp - dano < defensor.maxHp * 0.2) {
    defensor.zenkai += 0.15;
  }
  
  return { dano, efectoEspecial: null }
}
```

### Template: Transformación Canónica
```javascript
const transformar = (personaje, formaObjetivo) => {
  const forma = FORMAS[personaje.nombre][formaObjetivo];
  if (!forma) return false;
  
  // Verificar condiciones (ki mínimo, HP mínimo, etc.)
  if (personaje.ki < forma.kiRequerido) return false;
  
  personaje.formaActual = formaObjetivo;
  personaje.multiplicadorActual = multiplicadores[formaObjetivo];
  personaje.ki -= forma.kosTransformacion;
  
  // Mostrar animación/frase
  mostrarTransformacion({
    nombre: forma.nombre,
    frase: forma.fraseCanonica,
    descripcion: forma.descripcionVisual
  });
  
  return true;
}
```

---

## Directrices Visuales y de Audio

### Paleta de Colores por Personaje
```css
/* Paletas canon de cada personaje */
--goku-base: #f97316;        /* naranja Goku dojo */
--goku-ssj: #fbbf24;         /* dorado SSJ */
--goku-ssjblue: #3b82f6;     /* azul SSB */
--goku-ui: #e2e8f0;          /* plateado UI */

--vegeta-base: #1e1b4b;      /* azul oscuro traje */
--vegeta-ssj: #fbbf24;       /* dorado SSJ */
--vegeta-ultraego: #7c3aed;  /* violeta Ultra Ego */

--piccolo-base: #16a34a;     /* verde Namekiano */
--piccolo-orange: #ea580c;   /* naranja Orange Piccolo */

--freezer-base: #f1f5f9;     /* blanco perla */
--freezer-golden: #fcd34d;   /* dorado Golden */
--freezer-black: #1c1917;    /* negro Black */

--cell-base: #4ade80;        /* verde celular */
--buu-base: #f9a8d4;         /* rosa Buu */

--ki-beam: #fef08a;          /* amarillo ki genérico */
--ki-divine: #60a5fa;        /* azul ki divino */
--ki-destruction: #a855f7;   /* violeta destrucción */
--ki-evil: #dc2626;          /* rojo ki maligno */
```

### Descripciones de Efectos Visuales Canon
```
Kamehameha: Ola de energía azul, cargada con ambas manos unidas, "¡Ka-me-ha-me-HA!"
Final Flash: Palmas hacia afuera, carga lenta, destello blanco masivo, "¡Final... Flash!"
Special Beam Cannon: Dedo apuntado, rayo espiral amarillo/verde, demora 5 minutos en cargarse en canon
Death Beam: Dedo extendido, rayo violeta/fucsia instantáneo, sin carga visible
Destructo Disk: Disco rosa brillante, corta cualquier material, puede ser guiado
Spirit Bomb: Brazos al cielo, esfera de luz blanca, crece lentamente absorbiendo ki del entorno
Hakai: Partículas moradas, desintegración desde afuera hacia adentro del objetivo
```

---

## Sagas y Misiones — Estructura Narrativa

### Orden Canon de Sagas para Modo Historia
1. **DB Clásico** → Piccolo Daimao Final Boss
2. **Saiyan** → Vegeta Final Boss (superviviente)
3. **Namek** → Freezer Final Boss (Goku SSJ por primera vez)
4. **Androides** → Cell Perfect Final Boss
5. **Majin Buu** → Kid Buu Final Boss (Spirit Bomb colectiva)
6. **Super: Beerus** → Dios de la Destrucción (tutorial divino)
7. **Super: Golden Frieza** → Frieza vengativo
8. **Super: Future Trunks** → Zamasu Fusión Final Boss
9. **Super: Torneo de Poder** → 80 luchadores, ring-out, Jiren Final Boss
10. **Super Hero** → Cell Max + Gamma 1/2 → Orange Piccolo + Beast Gohan

### Condiciones de Victoria Canónicas
- **Raditz:** Solo puede ser derrotado si Piccolo usa Special Beam Cannon a través de Goku
- **Freezer:** Goku debe haber visto morir a Krillin para activar SSJ
- **Cell:** Gohan activa SSJ2 al ver a Android 16 destruido
- **Beerus:** Goku necesita ki de 5 saiyans puros para SSGod
- **Jiren:** Solo Ultra Instinct puede seguirle el ritmo

---

## Fuentes y Créditos
- Dragon Ball Wiki (Fandom ES) — datos de personajes
- Daizenshuu oficial — niveles de poder Raditz→Namek era
- cultture.com — poderes elementales de personajes
- estadisticasdepoder.blogspot.com — habilidades especiales/HAX canónicas
- Dragon Ball Super manga — transformaciones recientes
- Creador original: Akira Toriyama (Toei Animation / Shueisha)

**IMPORTANTE:** Todo el contenido de Dragon Ball pertenece a Akira Toriyama, Toei Animation y Shueisha. Este skill es para crear proyectos de fans, no proyectos comerciales.
