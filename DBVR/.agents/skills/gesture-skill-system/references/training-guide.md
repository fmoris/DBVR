# Guía de Entrenamiento — Protocolo en Headset

Cuando el usuario pida una sesión de entrenamiento, entregar esta guía
adaptada al personaje y ataques que tenga configurados.

---

## Cómo funciona el modo entrenamiento

```javascript
// 1. Iniciar captura para un label
gestureSystem.startTraining('goku_kame_phase1', 'wristOnly');

// 2. Hacer el gesto repetidamente mientras se captura
//    (el sistema captura frames automáticamente en cada update())

// 3. Detener y guardar los ejemplos al KNN
gestureSystem.stopTraining();

// 4. Repetir para el siguiente label
// 5. Al terminar todos los labels, guardar el modelo
gestureSystem.saveModel();
```

---

## UI de entrenamiento recomendada (para tu headset)

Agregar botones en la escena Babylon.js con `AdvancedDynamicTexture`:

```javascript
import { AdvancedDynamicTexture, Button, TextBlock, StackPanel } from '@babylonjs/gui';

function createTrainingUI(gestureSystem, scene) {
  const ui = AdvancedDynamicTexture.CreateFullscreenUI('TrainingUI');

  // Textos de estado
  const statusText = new TextBlock('status');
  statusText.color     = 'yellow';
  statusText.fontSize  = 22;
  statusText.top       = '-40%';
  statusText.text      = 'Modo Entrenamiento';
  ui.addControl(statusText);

  const countText = new TextBlock('count');
  countText.color    = 'white';
  countText.fontSize = 18;
  countText.top      = '-34%';
  ui.addControl(countText);

  // Actualizar contador cada frame
  scene.registerAfterRender(() => {
    if (gestureSystem.trainingMode) {
      countText.text = `Capturando "${gestureSystem.trainingLabel}": ${gestureSystem.trainingFrames} frames`;
    } else {
      const status = gestureSystem.getTrainingStatus();
      countText.text = status
        ? `Clases: ${status.classes} | Estado: ${status.state}`
        : 'Sistema no iniciado';
    }
  });

  // Botones de entrenamiento (generar uno por label)
  function makeTrainButton(label, extractor, text) {
    const btn = Button.CreateSimpleButton(`btn_${label}`, text);
    btn.width  = '200px';
    btn.height = '50px';
    btn.color  = 'white';
    btn.background = '#333';
    btn.onPointerClickObservable.add(() => {
      if (gestureSystem.trainingMode) {
        gestureSystem.stopTraining();
        btn.background = '#333';
        statusText.text = `✅ "${label}" guardado`;
      } else {
        gestureSystem.startTraining(label, extractor);
        btn.background = '#c00';
        statusText.text = `🔴 Capturando: ${label}`;
      }
    });
    return btn;
  }

  const panel = new StackPanel();
  panel.verticalAlignment = BABYLON.GUI.Control.VERTICAL_ALIGNMENT_CENTER;
  panel.left = '35%';
  ui.addControl(panel);

  // Añadir botones para Goku (adaptar según el personaje)
  panel.addControl(makeTrainButton('goku_stance',          'wristOnly',          '🥋 Stance'));
  panel.addControl(makeTrainButton('goku_kiblast_ready',   'wristOnly',          '⚡ Ki Blast Ready'));
  panel.addControl(makeTrainButton('goku_kiblast_forward', 'wristOnly',          '⚡ Ki Blast Forward'));
  panel.addControl(makeTrainButton('goku_kame_phase1',     'wristOnly',          '🔵 Kame Phase 1'));
  panel.addControl(makeTrainButton('goku_kame_charge',     'wristOnly',          '🔵 Kame Charge'));
  panel.addControl(makeTrainButton('goku_kame_release',    'wristOnly',          '🔵 Kame Release'));
  panel.addControl(makeTrainButton('goku_genki_gather',    'wristAndFingertips', '🌐 Genki Gather'));
  panel.addControl(makeTrainButton('goku_kaioken',         'wristAndFingertips', '🔴 Kaioken'));

  // Botón guardar
  const saveBtn = Button.CreateSimpleButton('save', '💾 Guardar Modelo');
  saveBtn.width  = '200px';
  saveBtn.height = '50px';
  saveBtn.color  = 'white';
  saveBtn.background = '#060';
  saveBtn.onPointerClickObservable.add(() => {
    gestureSystem.saveModel();
    gestureSystem.exportModel(); // también descarga el JSON
    statusText.text = '💾 Modelo guardado';
  });
  panel.addControl(saveBtn);

  return ui;
}
```

---

## Protocolo de captura por gesto

### Reglas generales
- **Frames por label**: 20–30 mínimo. Más es mejor hasta ~60.
- **Variedad**: hacer el gesto desde ángulos y posiciones ligeramente distintas.
- **Calidad > cantidad**: si el gesto no está bien formado, parar y rehacer.
- **Orden recomendado**: de lo más diferente a lo más parecido. Entrenar `stance`
  antes que `kame_phase1` para que el KNN tenga una buena referencia de "no es un ataque".

### Sesión de entrenamiento para Goku (orden óptimo)

```
1. goku_stance          (25 frames) — pose neutra, referencia de "idle"
2. goku_kame_phase1     (25 frames) — manos juntas lateral
3. goku_kame_charge     (25 frames) — manos juntas sostenidas
4. goku_kame_release    (20 frames) — empuje frontal
5. goku_kiblast_ready   (20 frames) — mano al frente
6. goku_kiblast_forward (20 frames) — misma mano empujando
7. goku_genki_gather    (20 frames) — manos al cielo
8. goku_genki_charge    (20 frames) — manos sobre la cabeza
9. goku_genki_release   (15 frames) — manos bajando
10. goku_kaioken        (20 frames) — brazos cruzados
```

---

## Generador de sesión personalizada

Cuando el usuario pida la sesión de entrenamiento para sus personajes/ataques,
generar una lista como esta adaptada a sus labels exactos:

```javascript
// Sesión de entrenamiento para [PERSONAJE]
// Ejecutar en este orden para mejores resultados:

const TRAINING_SESSION = [
  // { label, extractor, frames, instrucción }
  { label: '[personaje]_stance',    extractor: 'wristOnly', frames: 25,
    instrucción: 'Mantén la postura de combate neutral' },
  { label: '[personaje]_[ataque1]_phase1', extractor: 'wristOnly', frames: 25,
    instrucción: '[Descripción del gesto de fase 1]' },
  // ... etc
];

// Loop automático de entrenamiento (opcional, para UI guiada)
async function runAutomaticTraining(gestureSystem, session) {
  for (const step of session) {
    console.log(`\n📍 Siguiente: "${step.label}"`);
    console.log(`   → ${step.instrucción}`);
    console.log(`   → Presiona el botón cuando estés listo`);
    // Esperar input del usuario (botón, voz, etc.)
    await waitForUserReady(); // implementar según tu UI
    gestureSystem.startTraining(step.label, step.extractor);
    await wait(step.frames * 100); // ~100ms por frame
    gestureSystem.stopTraining();
    console.log(`   ✅ ${step.frames} frames capturados`);
  }
  gestureSystem.saveModel();
  console.log('\n🎉 ¡Entrenamiento completo!');
}
```

---

## Re-entrenamiento parcial

Si un gesto específico no funciona bien, solo re-entrenar ese label sin borrar los demás:

```javascript
// Borrar solo el label problemático
gestureSystem.classifier.clearClass('goku_kame_phase1');

// Re-entrenar ese label
gestureSystem.startTraining('goku_kame_phase1', 'wristOnly');
// ... hacer el gesto ...
gestureSystem.stopTraining();
gestureSystem.saveModel();
```
