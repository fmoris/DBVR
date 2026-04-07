# Troubleshooting — Gestos que no funcionan bien

Cuando el usuario reporte que un gesto no se detecta correctamente,
diagnosticar con estas preguntas y soluciones antes de proponer cambios de código.

---

## Diagrama de diagnóstico

```
¿El gesto no se detecta nunca?
   ├─ ¿Tiene suficientes ejemplos? (< 15 frames) → Re-entrenar con más frames
   ├─ ¿El extractor del nodo coincide con el de entrenamiento? → Verificar config
   └─ ¿El umbral es muy alto? → Bajar threshold a 0.60

¿El gesto se detecta pero dispara el ataque equivocado?
   ├─ ¿Hay otro label muy similar? → Añadir más ejemplos NEGATIVOS del label confundido
   └─ ¿El árbol de fases tiene el nodo correcto? → Verificar phaseTree mapping

¿El gesto se detecta pero tarda mucho?
   ├─ ¿minHoldMs es muy alto? → Reducir
   └─ ¿CLASSIFY_EVERY es muy alto? → Reducir (costo de rendimiento)

¿Ki Blast siempre sale en modo cargado, nunca rápido?
   └─ quickVelocity demasiado alto o quickThresholdMs demasiado bajo → Ajustar

¿Ki Blast siempre sale rápido, nunca cargado?
   └─ quickThresholdMs demasiado alto o chargeStartMs demasiado bajo → Ajustar
```

---

## Problemas comunes y soluciones

### 1. "El gesto se confunde con stance/idle"

**Causa**: El KNN no tiene suficientes ejemplos de `stance` para establecer una frontera clara.

**Solución**:
```javascript
// Re-entrenar stance con más variedad (posiciones ligeramente distintas)
gestureSystem.classifier.clearClass('goku_stance');
gestureSystem.startTraining('goku_stance', 'wristOnly');
// hacer la pose desde 5-6 posiciones distintas → stopTraining()
```

---

### 2. "Kamehameha y Galick Gun se confunden en fase 1"

**Causa**: Ambos empiezan con "manos juntas" y el KNN de ese nodo no puede distinguirlos
porque son el mismo gesto — es correcto, deben compartir la fase 1.

**Solución**: Verificar que el árbol de fases está bien configurado:
- Fase 1 clasifica `hands_together` → avanza al nodo de tipo de empuje
- El nodo de tipo de empuje clasifica `push_forward` vs `push_shoulder`

```javascript
// Verificar que phase2A tiene ambos labels entrenados:
const examples = gestureSystem.classifier.getClassExampleCount();
console.log(examples); // debe mostrar 'push_forward' y 'push_shoulder'
```

---

### 3. "El Ki Blast cargado nunca se libera"

**Causa A**: `chargedVelocity` muy alto — el jugador no puede hacer el movimiento tan rápido.

```javascript
// Bajar de 1.2 a 0.9
gokuConfig.timing.kiBlast.chargedVelocity = 0.9;
```

**Causa B**: El `maxChargeMs` es demasiado largo antes del auto-disparo.

```javascript
// Reducir de 4000ms a 2500ms
gokuConfig.timing.kiBlast.maxChargeMs = 2500;
```

---

### 4. "El gesto de dedos (Genkidama, Kaioken) no funciona"

**Causa**: El nodo usa `wristAndFingertips` pero el hand tracking no está activo.

**Diagnóstico**:
```javascript
// Verificar que hand tracking está disponible
scene.registerAfterRender(() => {
  const hasHandTracking = !!handTracking.left?.hand && !!handTracking.right?.hand;
  console.log('Hand tracking activo:', hasHandTracking);
});
```

**Solución A**: Asegurarse de que WebXRFeatureName.HAND_TRACKING está habilitado.

**Solución B**: Si el dispositivo no soporta hand tracking, cambiar el extractor a `wristOnly`
y re-entrenar ese label. Los gestos de dedos serán menos precisos pero funcionarán.

```javascript
gokuConfig.extractors['kaioken_charging'] = 'wristOnly'; // fallback sin dedos
```

---

### 5. "El sistema funciona en desktop pero no en el headset"

**Causa**: Backend WebGL compite con Babylon.js en dispositivos móviles.

**Solución**:
```javascript
// Cambiar a WASM (más estable en headsets de baja potencia)
await tf.setBackend('wasm');

// Y aumentar el throttle de clasificación
gestureSystem.CLASSIFY_EVERY = 8; // clasificar cada 8 frames en vez de 4
```

---

### 6. "El modelo no carga al reiniciar"

**Causa**: El modelo se guardó en localStorage pero con clave distinta.

**Diagnóstico**:
```javascript
// Listar todas las claves en localStorage
for (let i = 0; i < localStorage.length; i++) {
  const key = localStorage.key(i);
  if (key.startsWith('gss_model_')) {
    console.log(key, '→', localStorage.getItem(key).length, 'chars');
  }
}
```

**Solución**: La clave es `gss_model_${characterId}`. Verificar que `characterId` coincide.

---

### 7. "Error in concat2D: Shape of tensors[1] (N, 16) does not match (M, 1152)"

**Causa**: Mezcla de datos con distintas dimensiones. Generalmente ocurre al intentar cargar datos **LEGACY** de `localStorage` que usaban 1152 features (formato windowed antiguo) junto a los nuevos (16 o 46 features).

**Diagnóstico**: Verificar las dimensiones de los datos guardados.

**Solución**: Implementar una validación de dimensiones antes de añadir ejemplos al clasificador y purgar la clave si se detecta un mismatch crítico.

```javascript
// En el loop de carga de localStorage
const features = flattened[0].length;
if (features === 1152) {
    console.error("Detectados datos legacy de 1152 features. Purgando...");
    localStorage.removeItem(`gss_model_${characterId}`);
    return;
}
```

---

## Verificación rápida del estado del sistema

```javascript
// Ejecutar en consola para diagnóstico completo
function diagnoseGSS(gestureSystem) {
  const status = gestureSystem.getTrainingStatus();
  console.group('[GSS Diagnóstico]');
  console.log('Personaje activo:', status?.character ?? 'ninguno');
  console.log('Estado FSM:', status?.state);
  console.log('Clases entrenadas:', status?.classes);
  console.log('Ejemplos por clase:', status?.examples);
  console.log('Backend TF.js:', tf.getBackend());
  console.log('Tensores en memoria:', tf.memory().numTensors);
  console.groupEnd();
}
diagnoseGSS(gestureSystem);
```

---

## Tabla de ajuste fino de parámetros

| Síntoma | Parámetro | Cambio |
|---|---|---|
| Gesto no detectado | `confidenceThreshold` | Bajar 0.05 |
| Falsos positivos | `confidenceThreshold` | Subir 0.05 |
| Fase avanza muy rápido | `minHoldMs` | Subir 100ms |
| Fase tarda demasiado | `minHoldMs` | Bajar 100ms |
| Timeout prematuro | `maxWaitMs` | Subir 1000ms |
| Ki Blast siempre cargado | `quickThresholdMs` | Subir 50ms |
| Ki Blast nunca cargado | `chargeStartMs` | Bajar 100ms |
| Carga libera sola | `chargedVelocity` | Subir 0.2 |
| Carga nunca libera | `chargedVelocity` | Bajar 0.2 |
