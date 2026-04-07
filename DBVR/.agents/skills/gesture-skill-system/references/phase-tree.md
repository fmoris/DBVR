# Árbol de Fases — Referencia para GestureSkillSystem

---

## Cuándo usar árbol de fases vs clasificación directa

**Clasificación directa** (un solo KNN): funciona cuando todos los ataques son
gestualmente distintos desde el inicio. No hay ambigüedad en fase 1.

**Árbol de fases**: necesario cuando 2+ ataques comparten el gesto inicial.
En Dragon Ball esto pasa siempre: Kamehameha y Galick Gun empiezan con manos juntas.

---

## Patrón de nodo intermedio (desambiguación)

Cuando dos ataques comparten fase 1, insertar un nodo intermedio:

```
[FASE 1: manos juntas]
   ├── push_forward  → KAMEHAMEHA
   └── push_shoulder → GALICK GUN
```

El KNN de "fase 1" solo clasifica la dirección del empuje, no el ataque completo.
Los labels que entrenas en ese nodo son `push_forward` y `push_shoulder`, no los nombres de los ataques.

---

## Cómo mapear el árbol al FSM

Cada rama del árbol se convierte en un `case` del switch en `fsmHandler`:

```javascript
// Árbol:
// idle → [goku_kame_phase1] → kame_phase1
//                           → [goku_kame_charge] → kame_charging
//                                                → [goku_kame_release] → DISPARO

// FSM equivalente:
case 'idle':
  if (gesture === 'goku_kame_phase1') this._setState('kame_phase1');
  break;

case 'kame_phase1':
  if (gesture === 'goku_kame_charge') {
    this._setState('kame_charging');
    this._startCharge('kamehameha', 'both', now);
  }
  break;

case 'kame_charging':
  if (gesture === 'goku_kame_release') this._setState('kame_releasing');
  break;

case 'kame_releasing':
  // después de releaseHoldMs → fireAttack
  break;
```

---

## Extractores por tipo de nodo

| Tipo de nodo | Extractor | Razón |
|---|---|---|
| Idle | wristOnly | Solo detectar si hay movimiento |
| Carga inicial (posición amplia) | wristOnly | Manos juntas/separadas = posición |
| Dirección de empuje | wristOnly | Velocidad y dirección de muñecas |
| Forma de mano (abierta/cerrada) | wristAndFingertips | Dedos importan |
| Transformación / pose única | wristAndFingertips | Máxima precisión |

---

## Template para agregar un nuevo ataque a un personaje existente

Cuando el usuario pida agregar un ataque, generar exactamente estos bloques:

### Bloque 1: Labels en la config del personaje
```javascript
// Dentro de gokuConfig.gestures (o el personaje que sea):
nuevoAtaque: {
  phase1:  '[personaje]_[ataque]_phase1',
  charge:  '[personaje]_[ataque]_charge',
  release: '[personaje]_[ataque]_release',
},
```

### Bloque 2: Extractores en la config
```javascript
// Dentro de gokuConfig.extractors:
'[ataque]_phase1':   'wristOnly',          // ajustar según el gesto
'[ataque]_charging': 'wristOnly',
'[ataque]_releasing':'wristOnly',
```

### Bloque 3: Timing en la config
```javascript
// Dentro de gokuConfig.timing:
[ataque]: {
  minChargeMs:   1000,
  maxChargeMs:   6000,
  releaseHoldMs: 300,
  maxWaitMs:     4000,
},
```

### Bloque 4: Casos FSM
```javascript
// Dentro de fsmHandler, en el case 'idle'/'base':
if (gesture === g.[nuevoAtaque].phase1) this._setState('[ataque]_phase1');

// Nuevos cases:
case '[ataque]_phase1':
  if (gesture === g.[nuevoAtaque].charge) {
    this._setState('[ataque]_charging');
    this._startCharge('[ataque]', 'both', now);
  } else if (gesture !== g.[nuevoAtaque].phase1) {
    if (now - this.chargeStartTime > t.[ataque].maxWaitMs) this._cancelAttack();
  }
  break;

case '[ataque]_charging': {
  if (gesture !== g.[nuevoAtaque].charge) { this._cancelAttack(); break; }
  const elapsed = now - this.chargeStartTime;
  const ratio   = Math.min(elapsed / t.[ataque].maxChargeMs, 1.0);
  this.onChargeUpdate('[ataque]', ratio);
  if (gesture === g.[nuevoAtaque].release && elapsed >= t.[ataque].minChargeMs) {
    this._setState('[ataque]_releasing');
    this._releaseTime = now;
  }
  break;
}

case '[ataque]_releasing':
  if (now - this._releaseTime > t.[ataque].releaseHoldMs) {
    const elapsed = now - this.chargeStartTime;
    const ratio   = Math.min(elapsed / t.[ataque].maxChargeMs, 1.0);
    this._fireAttack('[ataque]', 1.0 + ratio * 2.0, 'both');
    this._setState('idle');
  }
  break;
```

### Bloque 5: Labels de entrenamiento a capturar
```
| Label | Gesto | Extractor | Frames |
|---|---|---|---|
| [personaje]_[ataque]_phase1  | [descripción del gesto] | wristOnly | 25 |
| [personaje]_[ataque]_charge  | [descripción del gesto] | wristOnly | 25 |
| [personaje]_[ataque]_release | [descripción del gesto] | wristOnly | 20 |
```

---

## Regla de colisión entre ataques

Antes de agregar un ataque, verificar si su gesto inicial colisiona con uno existente:

1. Listar todos los gestos de `phase1` del personaje
2. Si el nuevo gesto de `phase1` es igual a uno existente → agregar nodo desambiguador
3. Si es diferente → se puede registrar directamente en `idle`

**Ejemplo**: Si Vegeta ya tiene `galick_phase1` = manos juntas, y queremos agregar
`big_bang_phase1` que también empieza con manos juntas, necesitamos un nodo intermedio
que clasifique `galick_direction` vs `big_bang_direction` en fase 2.
