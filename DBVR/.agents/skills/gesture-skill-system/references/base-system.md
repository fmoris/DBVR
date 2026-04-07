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
    constructor(_xrExperience) {
        this.classifier = knnClassifier.create();
        this.activeCharacter = null;
        this.currentState = 'idle';
        this.chargeStartTime = 0;
        this.lastBlastHand = null;
        this._prevLeftPos = null;
        this._prevRightPos = null;
        this.trainingMode = false;
        this.trainingLabel = null;
        this.trainingBuffer = [];
        this.trainingFrames = 0;
        this._trainingExtractor = 'wristOnly';
        this._sessionHistory = {}; 
        this._classifying = false;
        this._frameCount = 0;
        this.CLASSIFY_EVERY = 4;
        this._characters = new Map();

        // Callbacks
        this.onAttack = () => { };
        this.onPhaseChange = () => { };
        this.onChargeUpdate = () => { };
        this.onCancel = () => { };
    }

    async init(characterId) {
        await tf.setBackend('webgl');
        await tf.ready();
        if (!this._characters.has(characterId)) throw new Error(`[GSS] Personaje "${characterId}" no registrado.`);
        await this.switchCharacter(characterId);
    }

    registerCharacter(config) {
        this._characters.set(config.id, config);
    }

    async switchCharacter(characterId) {
        if (this.classifier) this.classifier.dispose();
        this.classifier = knnClassifier.create();
        const config = this._characters.get(characterId);
        if (!config) return;

        this.activeCharacter = config;
        this.currentState = 'idle';
        this._sessionHistory = {};

        const saved = localStorage.getItem(`gss_model_${characterId}`);
        if (saved) {
            try {
                const data = JSON.parse(saved);
                for (const [label, entry] of Object.entries(data)) {
                    // Soporte para ambos formatos: array de muestras (legacy) y array de sesiones (nuevo)
                    const sessions = (Array.isArray(entry[0]) && !Array.isArray(entry[0][0])) ? [entry] : entry;
                    this._sessionHistory[label] = sessions;
                    const flattened = sessions.flat(1);
                    if (flattened.length === 0) continue;

                    // VALIDACIÓN DE DIMENSIONES (Crucial para evitar Error in concat2D)
                    const features = flattened[0].length;
                    if (features === 1152) {
                        console.error(`[GSS] 🚨 Datos LEGACY detectados. Purgando...`);
                        localStorage.removeItem(`gss_model_${characterId}`);
                        break;
                    }
                    if (features !== 16 && features !== 46) continue;

                    const augmented = this._augmentData(flattened);
                    const allSamples = [...flattened, ...augmented];
                    const tensor = tf.tensor2d(allSamples);
                    this.classifier.addExample(tensor, label);
                    tensor.dispose();
                }
            } catch (e) {
                console.warn(`[GSS] Error cargando modelo:`, e);
            }
        }

        if (this.activeCharacter.defaultData) {
            this.loadDefaultData(this.activeCharacter.defaultData);
        }
    }

    loadDefaultData(data) {
        if (!this.classifier) return;
        const currentDataset = this.classifier.getClassifierDataset();
        for (const [label, examples] of Object.entries(data)) {
            if (!examples || examples.length === 0) continue;
            const tensor = tf.tensor2d(examples);
            if (currentDataset[label]) {
                const oldTensor = currentDataset[label];
                if (oldTensor.shape[1] === tensor.shape[1]) {
                    const newTensor = tf.concat([oldTensor, tensor], 0);
                    currentDataset[label] = newTensor;
                    oldTensor.dispose();
                }
                tensor.dispose();
            } else {
                currentDataset[label] = tensor;
            }
        }
        this.classifier.setClassifierDataset(currentDataset);
    }

    _extractWristOnly(ctx) {
        if (!ctx.leftWrist || !ctx.rightWrist || !ctx.headPos) return new Float32Array(16).fill(0);
        const lp = ctx.leftWrist.absolutePosition, rp = ctx.rightWrist.absolutePosition;
        const mid = lp.add(rp).scale(0.5);
        const lRel = lp.subtract(mid), rRel = rp.subtract(mid);
        const dt = Math.max(ctx.deltaTimeMs, 1) / 1000;
        return new Float32Array([
            lRel.x, lRel.y, lRel.z, rRel.x, rRel.y, rRel.z,
            lp.subtract(rp).length(), lp.y - ctx.headPos.y, rp.y - ctx.headPos.y,
            lRel.length() / dt, rRel.length() / dt,
            lRel.normalizeToNew().x, lRel.normalizeToNew().y, lRel.normalizeToNew().z,
            rRel.normalizeToNew().x, rRel.normalizeToNew().y
        ]);
    }

    _extractWristAndFingertips(ctx) {
        if (!ctx.leftHand || !ctx.rightHand) return new Float32Array(46).fill(0);
        const base = this._extractWristOnly(ctx);
        const tips = [WebXRHandJoint.THUMB_TIP, WebXRHandJoint.INDEX_FINGER_TIP, WebXRHandJoint.MIDDLE_FINGER_TIP, WebXRHandJoint.RING_FINGER_TIP, WebXRHandJoint.PINKY_FINGER_TIP];
        const extras = [];
        for (const hand of [ctx.leftHand, ctx.rightHand]) {
            const wristPos = hand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition;
            for (const tip of tips) {
                const mesh = hand.getJointMesh(tip);
                if (!mesh || !wristPos) { extras.push(0, 0, 0); continue; }
                const rel = mesh.absolutePosition.subtract(wristPos);
                const s = Math.max(rel.length(), 0.001);
                extras.push(rel.x / s, rel.y / s, rel.z / s);
            }
        }
        const out = new Float32Array(base.length + extras.length);
        out.set(base); out.set(extras, base.length);
        return out;
    }

    _extract(ctx, extractorType = 'wristOnly') {
        return extractorType === 'wristAndFingertips' ? this._extractWristAndFingertips(ctx) : this._extractWristOnly(ctx);
    }

    async update(ctx) {
        if (!ctx.leftWrist || !ctx.rightWrist || !this.activeCharacter || !this.classifier) return;
        const now = performance.now();
        if (this.trainingMode) {
            const f = this._extract(ctx, this._trainingExtractor);
            if (f) { this.trainingBuffer.push(Array.from(f)); this.trainingFrames++; }
            return;
        }
        this._frameCount++;
        if (this._frameCount % this.CLASSIFY_EVERY !== 0) { this._tickFSM('none', 0, ctx, now); return; }
        if (this._classifying || this.classifier.getNumClasses() === 0) return;
        const features = this._extract(ctx, this.activeCharacter.extractors[this.currentState] || 'wristOnly');
        if (!features) return;
        this._classifying = true;
        const tensor = tf.tensor1d(features);
        try {
            const result = await this.classifier.predictClass(tensor, 3);
            const label = result.label, confidence = result.confidences[label] ?? 0;
            const threshold = this.activeCharacter.thresholds[this.currentState] || 0.75;
            this._tickFSM(confidence >= threshold ? label : 'none', confidence, ctx, now);
        } finally { tensor.dispose(); this._classifying = false; }
    }

    _tickFSM(gesture, confidence, ctx, now) {
        if (this.activeCharacter?.fsmHandler) this.activeCharacter.fsmHandler.call(this, gesture, confidence, ctx, now);
    }

    _augmentData(samples) {
        const augmented = [];
        for (const s of samples) {
            const jittered = s.map(v => v + (Math.random() * 0.01 - 0.005));
            augmented.push(jittered);
            if (s.length === 16) {
                const mirrored = [...jittered];
                mirrored[0] = -jittered[3]; mirrored[1] = jittered[4]; mirrored[2] = jittered[5];
                mirrored[3] = -jittered[0]; mirrored[4] = jittered[1]; mirrored[5] = jittered[2];
                mirrored[7] = jittered[8]; mirrored[8] = jittered[7];
                mirrored[9] = jittered[10]; mirrored[10] = jittered[9];
                mirrored[11] = -jittered[14]; mirrored[12] = jittered[15];
                augmented.push(mirrored);
            }
        }
        return augmented;
    }

    saveModel() {
        if (!this.activeCharacter) return;
        localStorage.setItem(`gss_model_${this.activeCharacter.id}`, JSON.stringify(this._sessionHistory));
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
