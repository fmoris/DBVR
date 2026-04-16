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
    headForward?: Vector3; // NEW: Dirección de la cabeza (Z local)
    headRight?: Vector3;   // NEW: Dirección lateral (X local)
    deltaTimeMs: number;
}

export type ExtractorType = 'wristOnly' | 'wristAndFingertips';

export interface CharacterConfig {
    id: string;
    modelFile?: string;
    gestureIds?: string[]; // IDs de movimientos a cargar (kamehameha, ki_blast, etc)
    extractors: Record<string, ExtractorType>;
    thresholds: Record<string, number>;
    fsmHandler: (this: GestureSkillSystem, gesture: string, confidence: number, ctx: XRHandsContext, now: number) => void;
    // Tiempos y parámetros específicos de ataques
    timing?: any;
    defaultData?: Record<string, number[][]>; // Datos de entrenamiento pre-cargados (Legacy/Fallback)
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

    /** Coordenadas locales respecto al cuerpo (Body-centric) del último frame procesado */
    public lastLocalL: Vector3 = Vector3.Zero();
    public lastLocalR: Vector3 = Vector3.Zero();
 
    private _stateDebounce: { state: string; until: number } | null = null;
    private readonly STATE_DEBOUNCE_MS: number = 150;

    private _characters: Map<string, CharacterConfig> = new Map();

    // Estadísticas de normalización Z-score por dimensión (16 o 46)
    private _normalizationStats: Record<number, { mean: number[]; std: number[] }> = {};

    // Callbacks
    public onAttack: (name: string, power: number, hand: 'left' | 'right' | 'both', character: string) => void = () => { };
    public onPhaseChange: (from: string, to: string) => void = () => { };
    public onChargeUpdate: (attackName: string, chargeRatio: number, ctx: XRHandsContext) => void = () => { };
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
        // GUARD: Evitar recargas si ya estamos en este personaje y tenemos datos
        if (this.activeCharacter && this.activeCharacter.id === characterId && Object.keys(this._sessionHistory).length > 0) {
            return;
        }

        if (this.classifier) this.classifier.dispose();
        this.classifier = knnClassifier.create();
        
        const config = this._characters.get(characterId);
        if (!config) return;

        this.activeCharacter = config;
        this.currentState = 'idle';
        this._prevLeftPos = null;
        this._prevRightPos = null;
        this._sessionHistory = {}; 

        // 1. CARGA MODULAR (Prioridad: Archivos individuales por movimiento)
        if (config.gestureIds && config.gestureIds.length > 0) {
            console.log(`[GSS] 🧩 Cargando ${config.gestureIds.length} movimientos para "${characterId}"...`);
            
            const loadPromises = config.gestureIds.map(async (id) => {
                try {
                    const response = await fetch(`/api/gestures/movement/${id}`);
                    if (response.ok) {
                        const data = await response.json();
                        if (data.model) {
                            // Merge modular data into session history
                            for (const [label, sessions] of Object.entries(data.model)) {
                                this._sessionHistory[label] = sessions as number[][][];
                            }
                            console.log(`[GSS] ✅ Movimiento "${id}" cargado.`);
                        }
                    } else {
                        console.warn(`[GSS] ❌ Movimiento "${id}" no encontrado en el servidor.`);
                    }
                } catch (e) {
                    console.error(`[GSS] Error cargando movimiento "${id}":`, e);
                }
            });

            await Promise.all(loadPromises);
        }

        // 2. Fallback a DefaultData (Solo si no hay datos modulares)
        if (Object.keys(this._sessionHistory).length === 0 && this.activeCharacter?.defaultData) {
            console.log(`[GSS] 📦 Cargando datos por defecto (CharacterConfig.defaultData) para "${characterId}"...`);
            for (const [label, entry] of Object.entries(this.activeCharacter.defaultData)) {
                this._sessionHistory[label] = [entry as number[][]];
            }
        }

        // 4. Fallback final: Si sigue vacío, inicializar objeto vacío para evitar crashes
        if (Object.keys(this._sessionHistory).length === 0) {
            console.warn(`[GSS] ⚠️ No se detectaron modelos para "${characterId}" (remotos, locales o default). Iniciando sistema vacío.`);
            this._sessionHistory = {};
        }

        // 5. Asegurar consistencia de dimensiones (Clean & Pad to 46)
        this._sanitizeHistory();

        // 6. Calcular estadísticas y reconstruir clasificador
        this._recalculateNormalizationStats();
    }

    private _sanitizeHistory() {
        console.log("[GSS] 🧼 Sanitizando historia de gestos (Padding a 46)...");
        for (const [label, sessions] of Object.entries(this._sessionHistory)) {
            for (let s = 0; s < sessions.length; s++) {
                const session = sessions[s];
                for (let f = 0; f < session.length; f++) {
                    if (session[f].length === 16) {
                        const padded = new Array(46).fill(0);
                        for (let i = 0; i < 16; i++) padded[i] = session[f][i];
                        session[f] = padded;
                    } else if (session[f].length !== 46) {
                        console.warn(`[GSS] Frame con dimensión inválida (${session[f].length}) en ${label}. session ${s}, frame ${f}.`);
                    }
                }
            }
        }
    }

    private loadDefaultData() {
        // Este método queda depreciado por la carga unificada en switchCharacter
        // pero lo mantenemos vacío por si hay referencias externas legacy.
    }

    private _isValidDimension(dim: number): boolean {
        return dim === 46; // Forzamos consistencia a 46 (16 base + 30 tips)
    }

    // ─────────────────────────────────────────────────────────────────
    // NORMALIZACIÓN Z-SCORE
    // ─────────────────────────────────────────────────────────────────

    private _recalculateNormalizationStats() {
        console.log("[GSS] 📊 Recalculando estadísticas de normalización Z-score...");
        const dimensions = [46]; // Solo usamos 46 para consistencia KNN
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
        const out = new Float32Array(46).fill(0); // Forzamos 46 para consistencia

        if (!ctx.leftWrist || !ctx.rightWrist || !ctx.headPos) {
            return out;
        }

        const lp = ctx.leftWrist.absolutePosition;
        const rp = ctx.rightWrist.absolutePosition;
        
        // --- 1. Definir origen y base local (BODY-CENTRIC) ---
        const chest = ctx.headPos.clone();
        chest.y -= 0.25;

        const forward = ctx.headForward || new Vector3(0, 0, 1);
        const right = ctx.headRight || new Vector3(1, 0, 0);
        const up = Vector3.Up();

        const lRelWorld = lp.subtract(chest);
        const rRelWorld = rp.subtract(chest);

        const lLocal = new Vector3(
            Vector3.Dot(lRelWorld, right),
            Vector3.Dot(lRelWorld, up),
            Vector3.Dot(lRelWorld, forward)
        );

        const rLocal = new Vector3(
            Vector3.Dot(rRelWorld, right),
            Vector3.Dot(rRelWorld, up),
            Vector3.Dot(rRelWorld, forward)
        );

        this.lastLocalL.copyFrom(lLocal);
        this.lastLocalR.copyFrom(rLocal);

        const dist = lp.subtract(rp).length();
        const dt = Math.max(ctx.deltaTimeMs, 1) / 1000;

        if (!this._prevLeftPos) this._prevLeftPos = lp.clone();
        if (!this._prevRightPos) this._prevRightPos = rp.clone();
        
        const lV = (lp.subtract(this._prevLeftPos).length()) / dt;
        const rV = (rp.subtract(this._prevRightPos).length()) / dt;

        const features = [
            lLocal.x, lLocal.y, lLocal.z,
            rLocal.x, rLocal.y, rLocal.z,
            dist,
            lLocal.y,
            rLocal.y,
            lV, rV,
            lLocal.x / (lLocal.length() || 1),
            lLocal.y / (lLocal.length() || 1),
            lLocal.z / (lLocal.length() || 1),
            rLocal.x / (rLocal.length() || 1),
            rLocal.y / (rLocal.length() || 1)
        ];

        out.set(features);
        return out;
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

        // GUARD: Si no hay manos trackeadas, no procesar nada para evitar falsos positivos (Phantom Charge)
        if (!ctx.leftWrist && !ctx.rightWrist) return;

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
        } catch (err: any) {
            // DETECTAMOS INCOMPATIBILIDAD DE MODELO (Shape mismatch o datos viejos)
            if (err.message && (err.message.includes("shape") || err.message.includes("size"))) {
                console.warn("[GSS] 🚨 Incompatibilidad de modelo detectada. Aplicando RESET de emergencia...");
                this.fullReset();
            } else {
                console.error("[GSS] Error en clasificación predictiva:", err);
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

    public fireAttack(name: string, power: number, hand: 'left' | 'right' | 'both', autoIdle: boolean = true) {
        this.onAttack(name, power, hand, this.activeCharacter?.id || 'unknown');
        this.chargeStartTime = performance.now(); // reset para cooldown/etc
        
        if (autoIdle) {
            this.setState('idle');
        }
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
        this.currentState = 'idle'; // Resetear estado FSM para evitar interferencias
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

        // 2. SANITIZAR historia para asegurar que todo sea 46-dim (importante si se mezclan tipos)
        this._sanitizeHistory();

        // 3. RECALCULAR estadísticas y RECONSTRUIR clasificador
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
                // En el nuevo espacio Body-Centric: 
                // index 0 = Left_Right_Offset, 1 = Up_Offset, 2 = Forward_Offset
                // Para espejar: Invertimos el signo de Right_Offset (eje 0 y eje 3)
                // y Swappeamos L con R.
                
                mirrored[0] = -jittered[3];  // L_Right = -R_Right
                mirrored[1] =  jittered[4];  // L_Up = R_Up
                mirrored[2] =  jittered[5];  // L_Forward = R_Forward
                
                mirrored[3] = -jittered[0];  // R_Right = -L_Right
                mirrored[4] =  jittered[1];  // R_Up = L_Up
                mirrored[5] =  jittered[2];  // R_Forward = L_Forward
                
                // Heights (índices 7 y 8) se swappean
                mirrored[7] = jittered[8];
                mirrored[8] = jittered[7];
                
                // Velocities (9 y 10) se swappean
                mirrored[9] = jittered[10];
                mirrored[10] = jittered[9];
                
                // Dirs (en el nuevo espacio local, swappear y negar Right)
                mirrored[11] = -jittered[14]; // L_dir_Right = -R_dir_Right
                mirrored[12] =  jittered[15]; // L_dir_Up = R_dir_Up
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
        
        // Sincronizar solo la última etiqueta entrenada de forma modular
        if (this.trainingLabel && this._sessionHistory[this.trainingLabel]) {
            await this.syncMovement(this.trainingLabel);
        } else {
            console.warn("[GSS] ⚠️ No hay etiqueta de entrenamiento activa para sincronizar.");
        }
    }

    private async syncMovement(movementId: string) {
        if (!this.activeCharacter) return;
        
        // Creamos un mini-modelo que contiene solo este movimiento para el servidor
        const modelToSync = {
            [movementId]: this._sessionHistory[movementId]
        };

        window.dispatchEvent(new CustomEvent('gss-sync-start', { detail: { id: movementId } }));

        try {
            console.log(`[GSS] ☁️ Sincronizando movimiento "${movementId}"...`);
            const response = await fetch(`/api/gestures/movement/${movementId}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ model: modelToSync })
            });

            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            
            console.log(`[GSS] ✅ Sincronización modular exitosa: ${movementId}.json`);
            window.dispatchEvent(new CustomEvent('gss-sync-success', { detail: { movementId } }));
        } catch (error) {
            console.error("[GSS] ❌ Error en sincronización modular:", error);
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

        if (this.classifier) {
            this.classifier.dispose();
            this.classifier = knnClassifier.create();
        }

        // 1. Limpiar Historia
        this._sessionHistory = {};
        
        // 2. Recargar (esto disparará la carga de defaultData y sanitización de 46-dim)
        this.switchCharacter(id);
        
        console.log(`[GSS] ✅ Reset total completado. El Clasificador ahora está limpio.`);
    }

    public dispose() {
        if (this.classifier) this.classifier.dispose();
    }
}
