# GestureSkillSystem — Código Base Completo

Este es el sistema base. Cuando el usuario pida el sistema completo, entregar este
código adaptado a los personajes que haya mencionado en la conversación.

## Dependencias

```html
<!-- TensorFlow.js (requerido) -->
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs"></script>
<!-- KNN Classifier (requerido) -->
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/knn-classifier"></script>
```

O con npm:
```bash
npm install @tensorflow/tfjs @tensorflow-models/knn-classifier
```

> **Nota sobre ml5.js**: El código original usaba ml5.js sobre TF.js. Este sistema
> usa TF.js directamente con `@tensorflow-models/knn-classifier`, que es más estable
> en entornos WebXR y no tiene dependencia extra. La API es equivalente.

---

## GestureSkillSystem.js — Código completo

```javascript
// =====================================================================
// GESTURE SKILL SYSTEM - Dragon Ball VR Edition
// Compatible con Babylon.js + WebXR
// Dependencias: @tensorflow/tfjs, @tensorflow-models/knn-classifier
// =====================================================================

import * as tf from '@tensorflow/tfjs';
import * as knnClassifier from '@tensorflow-models/knn-classifier';
import { WebXRHandJoint } from '@babylonjs/core';

class GestureSkillSystem {

  // ─────────────────────────────────────────────────────────────────
  // CONSTRUCTOR Y CONFIGURACIÓN
  // ─────────────────────────────────────────────────────────────────

  constructor(scene, xrExperience) {
    this.scene          = scene;
    this.xr             = xrExperience;

    // KNN — uno por personaje activo (se intercambia al cambiar personaje)
    this.classifier     = null;
    this.activeCharacter = null;

    // Estado de la FSM
    this.currentState   = 'idle';
    this.chargeStartTime = 0;
    this.lastBlastHand  = null;

    // Velocidad (delta de posición entre frames)
    this._prevLeftPos   = null;
    this._prevRightPos  = null;
    this._prevTime      = performance.now();

    // Modo entrenamiento
    this.trainingMode   = false;
    this.trainingLabel  = null;
    this.trainingBuffer = [];
    this.trainingFrames = 0;

    // Clasificación — mutex para evitar llamadas simultáneas
    this._classifying   = false;
    this._frameCount    = 0;
    this.CLASSIFY_EVERY = 4; // clasificar cada 4 frames (~15/seg a 60fps)

    // Personajes registrados: id → config
    this._characters    = new Map();

    // Callbacks públicos — el juego los sobreescribe
    this.onAttack       = (name, power, hand, character) => {};
    this.onPhaseChange  = (from, to) => {};
    this.onChargeUpdate = (attackName, chargeRatio) => {};  // 0.0 → 1.0
    this.onCancel       = () => {};
  }

  // ─────────────────────────────────────────────────────────────────
  // INICIALIZACIÓN
  // ─────────────────────────────────────────────────────────────────

  async init(characterId) {
    await tf.setBackend('webgl');
    await tf.ready();

    if (!this._characters.has(characterId)) {
      throw new Error(`[GSS] Personaje "${characterId}" no registrado. Llama registerCharacter() primero.`);
    }

    await this.switchCharacter(characterId);
    console.log(`[GSS] ✅ Iniciado con personaje: ${characterId}`);
  }

  /**
   * Registra un personaje con su configuración.
   * Debe llamarse ANTES de init().
   */
  registerCharacter(config) {
    this._characters.set(config.id, config);
    console.log(`[GSS] Personaje registrado: ${config.id}`);
  }

  /**
   * Cambia el personaje activo en tiempo de ejecución.
   * Carga el modelo KNN del nuevo personaje si existe.
   */
  async switchCharacter(characterId) {
    if (this.classifier) {
      this.classifier.dispose();
    }

    this.classifier     = knnClassifier.create();
    this.activeCharacter = this._characters.get(characterId);
    this.currentState   = 'idle';
    this._prevLeftPos   = null;
    this._prevRightPos  = null;

    // Intentar cargar modelo guardado
    const saved = localStorage.getItem(`gss_model_${characterId}`);
    if (saved) {
      try {
        const dataset = JSON.parse(saved);
        const restored = {};
        for (const [label, data] of Object.entries(dataset)) {
          restored[label] = tf.tensor2d(data);
        }
        this.classifier.setClassifierDataset(restored);
        console.log(`[GSS] Modelo cargado para ${characterId}`);
      } catch (e) {
        console.warn(`[GSS] No se pudo cargar modelo para ${characterId}:`, e);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // EXTRACCIÓN DE FEATURES
  // ─────────────────────────────────────────────────────────────────

  /**
   * Extractor ligero — solo muñecas.
   * Usar en: idle, carga inicial, poses de posición amplia.
   * Vector: 17 valores.
   */
  _extractWristOnly(ctx) {
    const lp  = ctx.leftWrist.absolutePosition;
    const rp  = ctx.rightWrist.absolutePosition;
    const mid = lp.add(rp).scale(0.5);
    const lR  = lp.subtract(mid);
    const rR  = rp.subtract(mid);
    const dist = lp.subtract(rp).length();
    const lH  = lp.y - ctx.headPos.y;
    const rH  = rp.y - ctx.headPos.y;
    const dt  = Math.max(ctx.deltaTimeMs, 1) / 1000;
    const lV  = lR.length() / dt;
    const rV  = rR.length() / dt;
    const lD  = lR.normalizeToNew();
    const rD  = rR.normalizeToNew();

    return new Float32Array([
      lR.x, lR.y, lR.z,
      rR.x, rR.y, rR.z,
      dist, lH, rH, lV, rV,
      lD.x, lD.y, lD.z,
      rD.x, rD.y, rD.z,
    ]);
  }

  /**
   * Extractor con dedos — muñecas + 5 tips por mano.
   * Usar en: nodos que distinguen mano abierta vs puño vs apuntar.
   * Vector: 47 valores.
   * REQUIERE: hand tracking activo (ctx.leftHand y ctx.rightHand no null)
   */
  _extractWristAndFingertips(ctx) {
    const base = this._extractWristOnly(ctx);
    if (!ctx.leftHand || !ctx.rightHand) return null;

    const tips = [
      WebXRHandJoint.THUMB_TIP,
      WebXRHandJoint.INDEX_FINGER_TIP,
      WebXRHandJoint.MIDDLE_FINGER_TIP,
      WebXRHandJoint.RING_FINGER_TIP,
      WebXRHandJoint.PINKY_FINGER_TIP,
    ];

    const extras = [];
    for (const hand of [ctx.leftHand, ctx.rightHand]) {
      const wristPos = hand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition;
      if (!wristPos) return null;
      for (const tip of tips) {
        const mesh = hand.getJointMesh(tip);
        if (!mesh) { extras.push(0, 0, 0); continue; }
        const rel = mesh.absolutePosition.subtract(wristPos);
        const s   = Math.max(rel.length(), 0.001);
        extras.push(rel.x / s, rel.y / s, rel.z / s);
      }
    }

    const out = new Float32Array(base.length + extras.length);
    out.set(base);
    out.set(extras, base.length);
    return out;
  }

  /**
   * Selecciona el extractor correcto según lo que pida el nodo activo.
   * El nodo se pasa como string: 'wristOnly' | 'wristAndFingertips'
   */
  _extract(ctx, extractorType = 'wristOnly') {
    if (extractorType === 'wristAndFingertips') return this._extractWristAndFingertips(ctx);
    return this._extractWristOnly(ctx);
  }

  // ─────────────────────────────────────────────────────────────────
  // VELOCIDAD DE MUÑECA (para Ki Blast rápido vs cargado)
  // ─────────────────────────────────────────────────────────────────

  _getWristVelocity(hand, ctx) {
    const wristMesh = hand === 'left' ? ctx.leftWrist : ctx.rightWrist;
    const prev      = hand === 'left' ? this._prevLeftPos : this._prevRightPos;
    if (!prev) return 0;
    const delta = wristMesh.absolutePosition.subtract(prev);
    return delta.length() / Math.max(ctx.deltaTimeMs / 1000, 0.001);
  }

  // ─────────────────────────────────────────────────────────────────
  // UPDATE — llamar cada frame
  // ─────────────────────────────────────────────────────────────────

  async update(ctx) {
    // ctx = XRHandsContext: { leftWrist, rightWrist, leftHand, rightHand, headPos, deltaTimeMs }
    if (!ctx.leftWrist || !ctx.rightWrist || !this.activeCharacter) return;

    const now = performance.now();

    // Guardar posiciones para velocidad del próximo frame
    const lPos = ctx.leftWrist.absolutePosition.clone();
    const rPos = ctx.rightWrist.absolutePosition.clone();

    // ── MODO ENTRENAMIENTO ──
    if (this.trainingMode) {
      const features = this._extract(ctx, this._trainingExtractor);
      if (features) {
        this.trainingBuffer.push(Array.from(features));
        this.trainingFrames++;
      }
      this._prevLeftPos  = lPos;
      this._prevRightPos = rPos;
      return;
    }

    // ── THROTTLE: clasificar cada N frames ──
    this._frameCount++;
    if (this._frameCount % this.CLASSIFY_EVERY !== 0) {
      // Aún así actualizar la FSM para tiempos de carga
      this._tickFSM(null, 0, ctx, now);
      this._prevLeftPos  = lPos;
      this._prevRightPos = rPos;
      return;
    }

    // ── CLASIFICACIÓN ──
    if (this._classifying || this.classifier.getNumClasses() === 0) return;

    // Obtener extractor del nodo actual del árbol
    const nodeExtractor = this._getExtractorForCurrentState();
    const features      = this._extract(ctx, nodeExtractor);
    if (!features) return;

    this._classifying = true;
    const tensor = tf.tensor1d(features);
    let gesture = 'none', confidence = 0;

    try {
      const result = await this.classifier.predictClass(tensor, 3);
      gesture    = result.label;
      confidence = result.confidences[gesture] ?? 0;
    } finally {
      tensor.dispose();
      this._classifying = false;
    }

    if (confidence >= this._getThresholdForCurrentState()) {
      this._tickFSM(gesture, confidence, ctx, now);
    }

    this._prevLeftPos  = lPos;
    this._prevRightPos = rPos;
  }

  /**
   * Retorna el tipo de extractor que debe usar el nodo FSM actual.
   * Los personajes definen en su config qué extractor usa cada estado.
   */
  _getExtractorForCurrentState() {
    return this.activeCharacter?.extractors?.[this.currentState] ?? 'wristOnly';
  }

  _getThresholdForCurrentState() {
    return this.activeCharacter?.thresholds?.[this.currentState] ?? 0.72;
  }

  // ─────────────────────────────────────────────────────────────────
  // FSM — Finite State Machine principal
  // ─────────────────────────────────────────────────────────────────

  _tickFSM(gesture, confidence, ctx, now) {
    // Delegar al manejador del personaje activo
    const handler = this.activeCharacter?.fsmHandler;
    if (handler) {
      handler.call(this, gesture, confidence, ctx, now);
    }
  }

  /**
   * Cambia de estado FSM y dispara el callback onPhaseChange.
   */
  _setState(next) {
    const prev = this.currentState;
    this.currentState = next;
    if (prev !== next) {
      console.log(`[GSS] Estado: ${prev} → ${next}`);
      this.onPhaseChange(prev, next);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // SISTEMA DE CARGA (común a todos los personajes)
  // ─────────────────────────────────────────────────────────────────

  _startCharge(attackName, hand, now) {
    this.chargeStartTime = now;
    this.lastBlastHand   = hand;
    this._chargeAttack   = attackName;
    console.log(`[GSS] ⚡ Carga iniciada: ${attackName}`);
  }

  _getChargeRatio(timing, now) {
    const elapsed = now - this.chargeStartTime;
    return Math.min(elapsed / timing.maxChargeMs, 1.0);
  }

  _cancelAttack() {
    console.log('[GSS] ❌ Ataque cancelado');
    this.chargeStartTime = 0;
    this.lastBlastHand   = null;
    this._chargeAttack   = null;
    this.onCancel();
    this._setState('idle');
  }

  _fireAttack(name, power, hand) {
    console.log(`[GSS] 🚀 ${name.toUpperCase()} (power: ${power.toFixed(2)}, mano: ${hand})`);
    this.onAttack(name, power, hand, this.activeCharacter.id);
    this.chargeStartTime = performance.now(); // reset para cooldown
  }

  _getActiveHand(ctx) {
    // La mano que se mueve más rápido en Z es la activa
    const lV = this._getWristVelocity('left', ctx);
    const rV = this._getWristVelocity('right', ctx);
    return lV > rV ? 'left' : 'right';
  }

  // ─────────────────────────────────────────────────────────────────
  // MODO ENTRENAMIENTO
  // ─────────────────────────────────────────────────────────────────

  /**
   * Inicia la captura de ejemplos para el label indicado.
   * extractorType: 'wristOnly' | 'wristAndFingertips'
   */
  startTraining(label, extractorType = 'wristOnly') {
    this.trainingMode      = true;
    this.trainingLabel     = label;
    this.trainingBuffer    = [];
    this.trainingFrames    = 0;
    this._trainingExtractor = extractorType;
    console.log(`[GSS] 🎥 Entrenando: "${label}" [${extractorType}] — haz el gesto...`);
  }

  /**
   * Detiene la captura y añade los ejemplos al clasificador.
   */
  stopTraining() {
    this.trainingMode = false;
    if (this.trainingBuffer.length === 0) {
      console.warn('[GSS] No se capturaron ejemplos');
      return;
    }
    for (const features of this.trainingBuffer) {
      const tensor = tf.tensor1d(new Float32Array(features));
      this.classifier.addExample(tensor, this.trainingLabel);
      tensor.dispose();
    }
    console.log(`[GSS] ✅ ${this.trainingBuffer.length} ejemplos añadidos para "${this.trainingLabel}"`);
    this.trainingBuffer = [];
  }

  /**
   * Guarda el modelo del personaje activo en localStorage.
   */
  saveModel() {
    if (!this.activeCharacter) return;
    const dataset    = this.classifier.getClassifierDataset();
    const serialized = {};
    for (const [label, tensor] of Object.entries(dataset)) {
      serialized[label] = Array.from(tensor.arraySync());
    }
    localStorage.setItem(`gss_model_${this.activeCharacter.id}`, JSON.stringify(serialized));
    console.log(`[GSS] 💾 Modelo guardado: ${this.activeCharacter.id}`);
  }

  /**
   * Descarga el modelo como archivo JSON (para compartir o respaldar).
   */
  exportModel() {
    if (!this.activeCharacter) return;
    const dataset    = this.classifier.getClassifierDataset();
    const serialized = {};
    for (const [label, tensor] of Object.entries(dataset)) {
      serialized[label] = Array.from(tensor.arraySync());
    }
    const blob = new Blob([JSON.stringify(serialized)], { type: 'application/json' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = `gestures-${this.activeCharacter.id}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  /**
   * Importa un modelo desde un archivo JSON descargado con exportModel().
   */
  async importModel(jsonString) {
    const dataset    = JSON.parse(jsonString);
    const restored   = {};
    for (const [label, data] of Object.entries(dataset)) {
      restored[label] = tf.tensor2d(data);
    }
    this.classifier.setClassifierDataset(restored);
    console.log('[GSS] 📂 Modelo importado correctamente');
  }

  // ─────────────────────────────────────────────────────────────────
  // UTILIDADES
  // ─────────────────────────────────────────────────────────────────

  getTrainingStatus() {
    if (!this.activeCharacter) return null;
    return {
      character:  this.activeCharacter.id,
      classes:    this.classifier.getNumClasses(),
      examples:   this.classifier.getClassExampleCount(),
      state:      this.currentState,
    };
  }

  dispose() {
    if (this.classifier) this.classifier.dispose();
  }
}

export { GestureSkillSystem };
```

---

## Cómo construir el XRHandsContext cada frame

```javascript
// En tu scene.registerAfterRender o game loop:
let prevTime = performance.now();

scene.registerAfterRender(async () => {
  const now   = performance.now();
  const delta = now - prevTime;
  prevTime    = now;

  const leftWrist  = handTracking.left?.hand?.getJointMesh(WebXRHandJoint.WRIST);
  const rightWrist = handTracking.right?.hand?.getJointMesh(WebXRHandJoint.WRIST);

  if (!leftWrist || !rightWrist) return;

  const ctx = {
    leftWrist,
    rightWrist,
    leftHand:   handTracking.left?.hand,   // null si no hay hand tracking
    rightHand:  handTracking.right?.hand,
    headPos:    xr.baseExperience.camera.position,
    deltaTimeMs: delta,
  };

  await gestureSystem.update(ctx);
});
```
