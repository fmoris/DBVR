import * as tf from '@tensorflow/tfjs';
import * as knnClassifier from '@tensorflow-models/knn-classifier';
import { WebXRHandJoint, AbstractMesh, Vector3, WebXRHand } from '@babylonjs/core';

// =====================================================================
// GESTURE SKILL SYSTEM - Dragon Ball VR Edition (TypeScript)
// =====================================================================

export interface XRHandsContext {
    leftWrist: AbstractMesh | undefined;
    rightWrist: AbstractMesh | undefined;
    leftHand?: WebXRHand;
    rightHand?: WebXRHand;
    headPos: Vector3;
    deltaTimeMs: number;
}

export type ExtractorType = 'wristOnly' | 'wristAndFingertips';

export interface CharacterConfig {
    id: string;
    modelFile?: string;
    extractors: Record<string, ExtractorType>;
    thresholds: Record<string, number>;
    fsmHandler: (this: GestureSkillSystem, gesture: string, confidence: number, ctx: XRHandsContext, now: number) => void;
    // Tiempos y parámetros específicos de ataques
    timing?: any;
    defaultData?: Record<string, number[][]>; // Datos de entrenamiento pre-cargados
}

export class GestureSkillSystem {
    private classifier: knnClassifier.KNNClassifier | null = null;
    public activeCharacter: CharacterConfig | null = null;

    public currentState: string = 'idle';
    public chargeStartTime: number = 0;
    public lastBlastHand: 'left' | 'right' | 'both' | null = null;
    private _prevLeftPos: Vector3 | null = null;
    private _prevRightPos: Vector3 | null = null;

    public trainingMode: boolean = false;
    private trainingLabel: string | null = null;
    private trainingBuffer: number[][] = [];
    public trainingFrames: number = 0;
    private _trainingExtractor: ExtractorType = 'wristOnly';

    private _sessionHistory: Record<string, number[][][]> = {}; // Historia 3D (sesiones)

    private _classifying: boolean = false;
    private _frameCount: number = 0;
    private readonly CLASSIFY_EVERY: number = 2; // Más frecuente (2 frames en lugar de 4) para mayor fluidez
 
    public lastValidGestureTime: number = 0;
    public gracePeriodMs: number = 300; // Más responsivo (300ms en lugar de 800ms)
 
    private _stateDebounce: { state: string; until: number } | null = null;
    private readonly STATE_DEBOUNCE_MS: number = 150;

    private _characters: Map<string, CharacterConfig> = new Map();

    // Estadísticas de normalización Z-score por dimensión (16 o 46)
    private _normalizationStats: Record<number, { mean: number[]; std: number[] }> = {};

    // Callbacks
    public onAttack: (name: string, power: number, hand: 'left' | 'right' | 'both', character: string) => void = () => { };
    public onPhaseChange: (from: string, to: string) => void = () => { };
    public onChargeUpdate: (attackName: string, chargeRatio: number) => void = () => { };
    public onCancel: () => void = () => { };


    constructor(_xrExperience: any) {
        this.classifier = knnClassifier.create();
    }

    public setXRExperience(_xr: any) {
    }

    async init(characterId: string) {
        await tf.setBackend('webgl');
        await tf.ready();

        if (!this._characters.has(characterId)) {
            throw new Error(`[GSS] Personaje "${characterId}" no registrado.`);
        }

        await this.switchCharacter(characterId);
        console.log(`[GSS] ✅ Iniciado con personaje: ${characterId}`);
    }

    registerCharacter(config: CharacterConfig) {
        this._characters.set(config.id, config);
        console.log(`[GSS] Personaje registrado: ${config.id}`);
    }

    async switchCharacter(characterId: string) {
        if (this.classifier) this.classifier.dispose();
        this.classifier = knnClassifier.create();
        
        const config = this._characters.get(characterId);
        if (!config) return;

        this.activeCharacter = config;
        this.currentState = 'idle';
        this._prevLeftPos = null;
        this._prevRightPos = null;
        this._sessionHistory = {};

        // 1. Intentar cargar desde el Servidor (Prioridad)
        let loadedFromRemote = false;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000);

        try {
            console.log(`[GSS] 📥 Buscando modelo remoto para "${characterId}"...`);
            window.dispatchEvent(new CustomEvent('gss-remote-load-start', { detail: { id: characterId } }));
            
            const response = await fetch(`/api/gestures/latest/${characterId}`, { signal: controller.signal });
            clearTimeout(timeoutId);

            if (response.ok) {
                const result = await response.json();
                if (result.model) {
                    this._sessionHistory = result.model;
                    loadedFromRemote = true;
                    console.log(`[GSS] ✅ Modelo remoto cargado exitosamente: ${result.filename}`);
                    window.dispatchEvent(new CustomEvent('gss-remote-load-success', { detail: { filename: result.filename } }));
                    
                    // Sincronizar localStorage con la versión del servidor
                    localStorage.setItem(`gss_model_${characterId}`, JSON.stringify(this._sessionHistory));
                }
            } else {
                console.warn(`[GSS] Sin modelo remoto para ${characterId} (Status: ${response.status}).`);
            }
        } catch (e: any) {
            clearTimeout(timeoutId);
            if (e.name === 'AbortError') {
                console.warn(`[GSS] ⏱️ Timeout en carga remota para ${characterId}. Usando datos locales.`);
            } else {
                console.error(`[GSS] Error en carga remota para ${characterId}:`, e);
            }
            window.dispatchEvent(new CustomEvent('gss-remote-load-error', { detail: { error: e } }));
        }

        // 2. Fallback a LocalStorage si no hubo carga remota
        if (!loadedFromRemote) {
            const saved = localStorage.getItem(`gss_model_${characterId}`);
            if (saved) {
                try {
                    const data = JSON.parse(saved);
                    for (const [label, entry] of Object.entries(data)) {
                        this._sessionHistory[label] = (Array.isArray((entry as any)[0]) && !Array.isArray((entry as any)[0][0]))
                            ? [entry as number[][]]
                            : entry as number[][][];
                    }
                    console.log(`[GSS] 💾 Modelo cargado desde LocalStorage.`);
                } catch (e) {
                    console.warn(`[GSS] Error parseando localStorage para ${characterId}:`, e);
                }
            }
        }

        // 3. Calcular estadísticas y reconstruir clasificador (esto reemplaza la inyección directa)
        this._recalculateNormalizationStats();
    }

    private loadDefaultData() {
        // Este método queda depreciado por la carga unificada en switchCharacter
        // pero lo mantenemos vacío por si hay referencias externas legacy.
    }

    private _isValidDimension(dim: number): boolean {
        return dim === 16 || dim === 46;
    }

    // ─────────────────────────────────────────────────────────────────
    // NORMALIZACIÓN Z-SCORE
    // ─────────────────────────────────────────────────────────────────

    private _recalculateNormalizationStats() {
        console.log("[GSS] 📊 Recalculando estadísticas de normalización Z-score...");
        const dimensions = [16, 46];
        const newStats: Record<number, { mean: number[]; std: number[] }> = {};

        for (const dim of dimensions) {
            const allSamples: number[][] = [];
            // Recolectar todas las muestras de todas las etiquetas para esta dimensión
            for (const sessions of Object.values(this._sessionHistory)) {
                for (const session of sessions) {
                    if (session.length > 0 && session[0].length === dim) {
                        allSamples.push(...session);
                    }
                }
            }

            if (allSamples.length === 0) continue;

            const n = allSamples.length;
            const mean = new Array(dim).fill(0);
            const std = new Array(dim).fill(0);

            // Calcular media
            for (const sample of allSamples) {
                for (let i = 0; i < dim; i++) {
                    mean[i] += sample[i];
                }
            }
            for (let i = 0; i < dim; i++) mean[i] /= n;

            // Calcular desviación estándar
            for (const sample of allSamples) {
                for (let i = 0; i < dim; i++) {
                    const diff = sample[i] - mean[i];
                    std[i] += diff * diff;
                }
            }
            for (let i = 0; i < dim; i++) {
                std[i] = Math.sqrt(std[i] / n);
                if (std[i] < 0.0001) std[i] = 1.0; // Evitar división por cero si la feature es constante
            }

            newStats[dim] = { mean, std };
        }

        this._normalizationStats = newStats;
        
        // Re-inyectar datos al clasificador usando la nueva normalización
        this._rebuildClassifier();
    }

    private _applyNormalization(features: Float32Array): Float32Array {
        const dim = features.length;
        const stats = this._normalizationStats[dim];
        if (!stats) return features; // Si no hay stats, pasamos raw (fallback)

        const normalized = new Float32Array(dim);
        for (let i = 0; i < dim; i++) {
            normalized[i] = (features[i] - stats.mean[i]) / stats.std[i];
        }
        return normalized;
    }

    private _rebuildClassifier() {
        if (!this.classifier) return;
        console.log("[GSS] 🚀 Re-construyendo clasificador con datos normalizados...");
        
        // Limpiamos el clasificador pero mantenemos la instancia
        this.classifier.dispose();
        this.classifier = knnClassifier.create();

        for (const [label, sessions] of Object.entries(this._sessionHistory)) {
            const flattened = sessions.flat(1);
            if (flattened.length === 0) continue;

            const augmented = this._augmentData(flattened);
            const allSamples = [...flattened, ...augmented];

            tf.tidy(() => {
                for (const example of allSamples) {
                    const normExample = this._applyNormalization(new Float32Array(example));
                    this.classifier!.addExample(tf.tensor1d(normExample), label);
                }
            });
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // EXTRACCIÓN DE FEATURES
    // ─────────────────────────────────────────────────────────────────

    private _extractWristOnly(ctx: XRHandsContext): Float32Array {
        if (!ctx.leftWrist || !ctx.rightWrist || !ctx.headPos) {
            return new Float32Array(16).fill(0);
        }

        const lp = ctx.leftWrist.absolutePosition;
        const rp = ctx.rightWrist.absolutePosition;
        const mid = lp.add(rp).scale(0.5);
        const lRel = lp.subtract(mid);
        const rRel = rp.subtract(mid);
        const dist = lp.subtract(rp).length();
        const lH = lp.y - ctx.headPos.y;
        const rH = rp.y - ctx.headPos.y;
        const dt = Math.max(ctx.deltaTimeMs, 1) / 1000;

        // Velocidad relativa al centro
        const lV = lRel.length() / dt;
        const rV = rRel.length() / dt;

        const lDir = lRel.normalizeToNew();
        const rDir = rRel.normalizeToNew();

        return new Float32Array([
            lRel.x, lRel.y, lRel.z,
            rRel.x, rRel.y, rRel.z,
            dist, lH, rH, lV, rV,
            lDir.x, lDir.y, lDir.z,
            rDir.x, rDir.y,
        ]);
    }

    private _extractWristAndFingertips(ctx: XRHandsContext): Float32Array {
        if (!ctx.leftWrist || !ctx.rightWrist || !ctx.headPos || !ctx.leftHand || !ctx.rightHand) {
            return new Float32Array(46).fill(0);
        }

        const base = this._extractWristOnly(ctx);
        const tips = [
            WebXRHandJoint.THUMB_TIP,
            WebXRHandJoint.INDEX_FINGER_TIP,
            WebXRHandJoint.MIDDLE_FINGER_TIP,
            WebXRHandJoint.RING_FINGER_TIP,
            WebXRHandJoint.PINKY_FINGER_TIP,
        ];

        const extras: number[] = [];
        for (const hand of [ctx.leftHand, ctx.rightHand]) {
            const wristPos = hand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition;
            for (const tip of tips) {
                const mesh = hand.getJointMesh(tip);
                if (!mesh || !wristPos) {
                    extras.push(0, 0, 0);
                    continue;
                }
                const rel = mesh.absolutePosition.subtract(wristPos);
                const s = Math.max(rel.length(), 0.001);
                extras.push(rel.x / s, rel.y / s, rel.z / s);
            }
        }

        const out = new Float32Array(base.length + extras.length);
        out.set(base);
        out.set(extras, base.length);
        return out;
    }

    private _extract(ctx: XRHandsContext, extractorType: ExtractorType = 'wristOnly'): Float32Array | null {
        let features: Float32Array;
        if (extractorType === 'wristAndFingertips') {
            features = this._extractWristAndFingertips(ctx);
        } else {
            features = this._extractWristOnly(ctx);
        }

        // Si estamos entrenando, devolvemos RAW para guardar en _sessionHistory
        if (this.trainingMode) return features;

        // Si estamos infiriendo, aplicamos normalización Z-score
        return this._applyNormalization(features);
    }

    // ─────────────────────────────────────────────────────────────────
    // UPDATE
    // ─────────────────────────────────────────────────────────────────

    public async update(ctx: XRHandsContext) {
        if (!this.activeCharacter || !this.classifier) return;

        const now = performance.now();
        // Wrist positions can be null if not tracked
        const lPos = ctx.leftWrist?.absolutePosition.clone() || null;
        const rPos = ctx.rightWrist?.absolutePosition.clone() || null;

        if (this.trainingMode) {
            const features = this._extract(ctx, this._trainingExtractor);
            if (features) {
                this.trainingBuffer.push(Array.from(features));
                this.trainingFrames++;
            }
            this._prevLeftPos = lPos;
            this._prevRightPos = rPos;
            return;
        }

        this._frameCount++;
        if (this._frameCount % this.CLASSIFY_EVERY !== 0) {
            // No enviamos 'none' en frames de salto para no romper la FSM.
            // La FSM solo debe reaccionar a cambios reales de clasificación.
            this._prevLeftPos = lPos;
            this._prevRightPos = rPos;
            return;
        }

        const classifier = this.classifier;
        if (this._classifying || !classifier || classifier.getNumClasses() === 0) return;

        const nodeExtractor = this.activeCharacter.extractors[this.currentState] || 'wristOnly';
        const features = this._extract(ctx, nodeExtractor);
        if (!features) return;

        this._classifying = true;
        const tensor = tf.tensor1d(features);
        let gesture = 'none';
        let confidence = 0;

        try {
            const result = await classifier.predictClass(tensor, 3);
            gesture = result.label;
            confidence = (result.confidences as any)[gesture] ?? 0;
            
            // Actualizar tiempo de último gesto válido
            const threshold = this.activeCharacter.thresholds[this.currentState] || 0.75;
            if (confidence >= threshold && gesture !== 'none') {
                this.lastValidGestureTime = now;
            }
        } finally {
            tensor.dispose();
            this._classifying = false;
        }

        const threshold = this.activeCharacter.thresholds[this.currentState] || 0.75;
        
        // Lógica de Gracia: si el gesto es inválido pero estamos en periodo de gracia,
        // nos quedamos en el último gesto válido para que la FSM no se rompa.
        if (confidence < threshold || gesture === 'none') {
            const timeSinceValid = now - this.lastValidGestureTime;
            if (this.currentState !== 'idle' && timeSinceValid < this.gracePeriodMs) {
                // Mantenemos el estado actual "artificialmente" enviando un placeholder
                // que la FSM trate como "continuar" o simplemente no enviamos 'none'
                // Enviamos 'none' pero con una bandera o simplemente ignoramos el tick
                return; 
            }
            this._tickFSM('none', 0, ctx, now);
        } else {
            this._tickFSM(gesture, confidence, ctx, now);
        }

        this._prevLeftPos = lPos;
        this._prevRightPos = rPos;
    }

    private _tickFSM(gesture: string, confidence: number, ctx: XRHandsContext, now: number) {
        if (this.activeCharacter?.fsmHandler) {
            this.activeCharacter.fsmHandler.call(this, gesture, confidence, ctx, now);
        }
    }

    public setState(next: string) {
        const prev = this.currentState;
        if (prev !== next) {
            const now = performance.now();

            // Prevenir flickering: si es la misma transición reversa en <150ms, ignorar
            if (this._stateDebounce &&
                this._stateDebounce.state === next &&
                now < this._stateDebounce.until) {
                console.log(`[GSS] ⏸ Estado: ${prev} → ${next} ignorado (debounce)`);
                return;
            }

            this.currentState = next;
            this._stateDebounce = { state: prev, until: now + this.STATE_DEBOUNCE_MS };
            console.log(`[GSS] Estado: ${prev} → ${next}`);
            this.onPhaseChange(prev, next);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // SISTEMA DE CARGA
    // ─────────────────────────────────────────────────────────────────

    public startCharge(attackName: string, hand: 'left' | 'right' | 'both', now: number) {
        this.chargeStartTime = now;
        this.lastBlastHand = hand;
        console.log(`[GSS] ⚡ Carga iniciada: ${attackName}`);
    }

    public getChargeRatio(maxChargeMs: number, now: number): number {
        if (this.chargeStartTime === 0) return 0;
        const elapsed = now - this.chargeStartTime;
        return Math.min(elapsed / maxChargeMs, 1.0);
    }

    public cancelAttack() {
        console.log('[GSS] ❌ Ataque cancelado');
        this.chargeStartTime = 0;
        this.lastBlastHand = null;
        this.onCancel();
        this.setState('idle');
    }

    public fireAttack(name: string, power: number, hand: 'left' | 'right' | 'both') {
        this.onAttack(name, power, hand, this.activeCharacter?.id || 'unknown');
        this.chargeStartTime = performance.now(); // reset para cooldown/etc
    }

    public getActiveHand(ctx: XRHandsContext): 'left' | 'right' {
        const lV = this._getWristVelocity('left', ctx);
        const rV = this._getWristVelocity('right', ctx);
        return lV > rV ? 'left' : 'right';
    }

    private _getWristVelocity(hand: 'left' | 'right', ctx: XRHandsContext): number {
        const pos = hand === 'left' ? ctx.leftWrist?.absolutePosition : ctx.rightWrist?.absolutePosition;
        if (!pos) return 0;
        const prev = hand === 'left' ? this._prevLeftPos : this._prevRightPos;
        if (!prev) return 0;
        const delta = pos.subtract(prev);
        return delta.length() / Math.max(ctx.deltaTimeMs / 1000, 0.001);
    }

    // ─────────────────────────────────────────────────────────────────
    // MODO ENTRENAMIENTO
    // ─────────────────────────────────────────────────────────────────

    public startTraining(label: string, extractorType: ExtractorType = 'wristOnly') {
        if (!this.classifier) {
            console.error('[GSS] No se puede iniciar el entrenamiento: el clasificador no está inicializado.');
            return;
        }

        this.trainingMode = true;
        this.trainingLabel = label;
        this.trainingBuffer = [];
        this.trainingFrames = 0;
        this._trainingExtractor = extractorType;
        console.log(`[GSS] 🎥 Entrenando: "${label}" [${extractorType}]`);
    }

    public stopTraining() {
        this.trainingMode = false;
        const classifier = this.classifier;
        if (this.trainingBuffer.length === 0 || !this.trainingLabel || !classifier) {
            console.warn('[GSS] No se capturaron ejemplos');
            this.trainingBuffer = [];
            return;
        }

        const label = this.trainingLabel;
        const newSession = [...this.trainingBuffer];

        // VALIDACIÓN DE SEGURIDAD: Evitar que entren datos vacíos o con dimensiones corruptas
        const sampleCount = newSession.length;
        const featureCount = newSession[0].length;

        if (!this._isValidDimension(featureCount)) {
            console.error(`[GSS] 🚨 Error crítico de dimensión al guardar "${label}". frames: ${sampleCount}, features: ${featureCount}. Se esperaba 16 o 46.`);
            this.trainingBuffer = [];
            return;
        }

        // 1. Guardar en historia (3D RAW)
        if (!this._sessionHistory[label]) this._sessionHistory[label] = [];
        this._sessionHistory[label].push(newSession);

        // 2. RECALCULAR estadísticas y RECONSTRUIR clasificador
        // Esto integrará la nueva sesión y re-normalizará TODO el dataset
        this._recalculateNormalizationStats();

        console.log(`[GSS] ✅ Sesión guardada para "${label}" (${sampleCount} frames). Estadísticas actualizadas.`);
        
        this.trainingBuffer = [];
        this.saveModel(); // Guardado automático incremental
    }

    private _augmentData(samples: number[][]): number[][] {
        const augmented: number[][] = [];
        for (const s of samples) {
            // Jittering: clonar con ruido mínimo
            const jittered = s.map(v => v + (Math.random() * 0.01 - 0.005));
            augmented.push(jittered);

            // Mirroring: si el vector tiene 16 features (wristOnly)
            if (s.length === 16) {
                const mirrored = [...jittered];
                // Swap L/R rel pos and negate X
                // lRel: 0,1,2 | rRel: 3,4,5
                mirrored[0] = -jittered[3];
                mirrored[1] =  jittered[4];
                mirrored[2] =  jittered[5];
                mirrored[3] = -jittered[0];
                mirrored[4] =  jittered[1];
                mirrored[5] =  jittered[2];
                // Swap Heights
                mirrored[7] = jittered[8];
                mirrored[8] = jittered[7];
                // Swap Velocities
                mirrored[9] = jittered[10];
                mirrored[10] = jittered[9];
                // Swap Dirs (aprox)
                mirrored[11] = -jittered[14]; // lDir.x <- -rDir.x
                mirrored[12] =  jittered[15]; // lDir.y <-  rDir.y
                // ...
                augmented.push(mirrored);
            }
        }
        return augmented;
    }

    public getGestureCount(label: string): number {
        return this._sessionHistory[label]?.length || 0;
    }

    /**
     * Retorna todas las sesiones grabadas para un movimiento específico
     */
    public getSessions(label: string): number[][][] {
        return this._sessionHistory[label] || [];
    }

    /**
     * Retorna una única sesión específica grabada para un movimiento
     */
    public getSession(label: string, index: number): number[][] | null {
        const sessions = this.getSessions(label);
        return sessions[index] || null;
    }

    public async saveModel() {
        if (!this.activeCharacter || !this.classifier) return;
        
        // 1. Guardado local
        localStorage.setItem(`gss_model_${this.activeCharacter.id}`, JSON.stringify(this._sessionHistory));
        console.log(`[GSS] 💾 Modelo (historia 3D) guardado localmente: ${this.activeCharacter.id}`);
        
        // Dispatch event for HUD notification
        window.dispatchEvent(new CustomEvent('gss-saved-local', { detail: { id: this.activeCharacter.id } }));

        // 2. Sincronización automática con servidor
        if (this.validateModel()) {
            await this.syncWithServer();
        } else {
            console.warn("[GSS] ⚠️ Modelo no válido para sincronización (pocos datos)");
        }
    }

    private validateModel(): boolean {
        // Al menos una etiqueta con al menos un par de sesiones
        const labels = Object.keys(this._sessionHistory);
        if (labels.length === 0) return false;

        let totalFrames = 0;
        for (const label of labels) {
            const sessions = this._sessionHistory[label];
            for (const session of sessions) {
                totalFrames += session.length;
            }
        }

        return totalFrames >= 10; // Mínimo 10 frames totales en toda la historia
    }

    private async syncWithServer() {
        if (!this.activeCharacter) return;
        
        const characterId = this.activeCharacter.id;
        window.dispatchEvent(new CustomEvent('gss-sync-start', { detail: { id: characterId } }));

        try {
            console.log(`[GSS] ☁️ Sincronizando modelo "${characterId}" con el servidor...`);
            const response = await fetch('/api/gestures/sync', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    characterId,
                    model: this._sessionHistory
                })
            });

            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const result = await response.json();
            
            console.log(`[GSS] ✅ Sincronización exitosa: ${result.filename}`);
            window.dispatchEvent(new CustomEvent('gss-sync-success', { detail: { filename: result.filename } }));
        } catch (error) {
            console.error("[GSS] ❌ Error en sincronización:", error);
            window.dispatchEvent(new CustomEvent('gss-sync-error', { detail: { error } }));
        }
    }

    public exportModel() {
        if (!this.activeCharacter || !this.classifier) return;
        const blob = new Blob([JSON.stringify(this._sessionHistory)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `gestures-${this.activeCharacter.id}.json`;
        a.click();
        URL.revokeObjectURL(url);
        console.log(`[GSS] 📥 Modelo exportado: gestures-${this.activeCharacter.id}.json`);
    }

    public removeLabel(label: string) {
        if (!this.classifier || !this.activeCharacter) return;
        
        // 1. Eliminar de la historia 3D
        if (this._sessionHistory[label]) {
            delete this._sessionHistory[label];
        }

        // 2. Eliminar de la memoria física del clasificador (Instantáneo)
        try {
            const classifier = this.classifier;
            const dataset = classifier.getClassifierDataset();
            if (dataset[label]) {
                classifier.clearClass(label);
                console.log(`[GSS] 🗑️ Etiqueta "${label}" eliminada del clasificador.`);
            }
        } catch (e) {
            console.warn(`[GSS] No se pudo limpiar la clase "${label}":`, e);
        }

        // 3. Persistir cambios en LocalStorage
        this.saveModel();
    }

    public getMetrics() {
        const dataset = this.classifier?.getClassifierDataset();
        return {
            classCount: dataset ? Object.keys(dataset).length : 0,
            totalSamples: Object.values(this._sessionHistory).reduce((sum, arr) => sum + arr.length, 0),
            sessionCounts: Object.fromEntries(
                Object.entries(this._sessionHistory).map(([label, sessions]) => [label, sessions.length])
            ),
        };
    }

    /**
     * Limpia TODO el modelo (Classifier + Historia + LocalStorage) para el personaje activo.
     * Úsalo si detectas corrupción masiva.
     */
    public fullReset() {
        if (!this.activeCharacter) return;
        const id = this.activeCharacter.id;
        
        console.warn(`[GSS] ❗ REALIZANDO RESET TOTAL para "${id}"...`);
        
        // 1. Limpiar Clasificador
        if (this.classifier) {
            this.classifier.dispose();
            this.classifier = knnClassifier.create();
        }

        // 2. Limpiar Historia en memoria
        this._sessionHistory = {};

        // 3. Limpiar LocalStorage
        localStorage.removeItem(`gss_model_${id}`);
        
        // 4. Recargar datos por defecto
        if (this.activeCharacter.defaultData) {
            this.loadDefaultData();
            // Refrescar via switchCharacter para que se aplique la carga unificada
            this.switchCharacter(this.activeCharacter.id);
        }
        
        console.log(`[GSS] ✅ Reset total completado. El Clasificador ahora está limpio (solo con defaultData).`);
    }

    public dispose() {
        if (this.classifier) this.classifier.dispose();
    }
}
