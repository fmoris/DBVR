import { Scene, Vector3 } from "@babylonjs/core";
import { GestureSkillSystem, XRHandsContext } from "./GestureSkillSystem";
import { CalibrationGhost } from "./CalibrationGhost";
import { PoseManager, PoseReference } from "./PoseReferences";

export enum CalibrationState {
    IDLE,
    WAITING_FOR_HANDS,
    COUNTDOWN,
    RECORDING,
    DONE
}

export class VRCalibrationSystem {
    private ghost: CalibrationGhost;
    private state: CalibrationState = CalibrationState.IDLE;
    private targetLabel: string = "";
    private currentPose: PoseReference | null = null;
    
    private countdownValue: number = 3;
    private timer: number = 0;
    private inPosStartTime: number = 0;

    // Manipulation state (Direct)
    private isDraggingLeft: boolean = false;
    private isDraggingRight: boolean = false;
    private leftPinchTime: number = 0;
    private rightPinchTime: number = 0;

    // Remote dragging state (Pointer)
    private activeRemoteDrags: Map<number, { 
        side: 'left' | 'right', 
        initialGhostDist: number, 
        initialHandDist: number,
        offsetVector: Vector3 // Offset para evitar el "snap" inicial
    }> = new Map();

    private readonly PROXIMITY_THRESHOLD = 0.20; 
    private readonly PINCH_THRESHOLD = 0.05;      // 5cm for a pinch
    private readonly QUICK_TAP_MAX_MS = 250;     // Time for a toggle instead of a drag
    private readonly IN_POS_DURATION = 800;    
    private readonly MIN_DISTANCE = 0.2;
    private readonly MAX_DISTANCE = 5.0;

    public onStatusChange?: (status: string) => void;

    constructor(private scene: Scene, private gss: GestureSkillSystem) {
        this.ghost = new CalibrationGhost(this.scene);
        this.setupPointerInteraction();
    }

    private setupPointerInteraction() {
        this.scene.onPointerObservable.add((pointerInfo) => {
            if (this.state === CalibrationState.IDLE || this.state === CalibrationState.DONE) return;
            if (!this.currentPose) return;

            const type = pointerInfo.type;
            const event = pointerInfo.event;
            const pointerId = (event as any).pointerId;

            // Detectar inicio de arrastre remoto
            if (type === 1) { // POINTERDOWN
                const pickInfo = pointerInfo.pickInfo;
                if (pickInfo?.hit && pickInfo.pickedMesh && pickInfo.pickedMesh.metadata?.side) {
                    const side = pickInfo.pickedMesh.metadata.side as 'left' | 'right';
                    
                    // Solo una mano por lado simultáneamente para evitar "peleas"
                    for (const drag of this.activeRemoteDrags.values()) {
                        if (drag.side === side) return;
                    }

                    const ray = pickInfo.ray!;
                    const headPos = this.scene.activeCamera?.globalPosition || Vector3.Zero();
                    const handPos = ray.origin;
                    
                    // Punto de impacto real vs centro del objeto
                    const hitPoint = pickInfo.pickedPoint || pickInfo.pickedMesh.absolutePosition;
                    const initialGhostDist = Vector3.Distance(ray.origin, hitPoint);
                    
                    // Calculamos el offset vectorial para evitar el "snap"
                    // Es la diferencia entre la dirección del rayo y la posición del centro del objeto
                    const offsetVector = pickInfo.pickedMesh.absolutePosition.subtract(hitPoint);

                    this.activeRemoteDrags.set(pointerId, {
                        side,
                        initialGhostDist,
                        initialHandDist: Vector3.Distance(handPos, headPos),
                        offsetVector
                    });

                    if (side === 'left') {
                        this.isDraggingLeft = true;
                        this.leftPinchTime = performance.now();
                    } else {
                        this.isDraggingRight = true;
                        this.rightPinchTime = performance.now();
                    }
                }
            }

            // Actualizar posición y profundidad
            if (type === 4 && this.activeRemoteDrags.has(pointerId)) { // POINTERMOVE
                const drag = this.activeRemoteDrags.get(pointerId)!;
                const ray = pointerInfo.pickInfo?.ray;
                if (!ray) return;

                const headPos = this.scene.activeCamera?.globalPosition || Vector3.Zero();
                const currentHandPos = ray.origin;

                // Validación de seguridad para evitar saltos por datos XR corruptos
                if (!this._isValid(currentHandPos) || !this._isValid(ray.direction)) return;

                const currentHandDist = Vector3.Distance(currentHandPos, headPos);
                
                // Calcular nueva distancia con multiplicador y clamping
                const deltaHandDist = currentHandDist - drag.initialHandDist;
                const newGhostDist = Math.max(this.MIN_DISTANCE, Math.min(this.MAX_DISTANCE, drag.initialGhostDist + (deltaHandDist * 4.0)));

                // Posición proyectada + Offset
                const targetPoint = ray.origin.add(ray.direction.scale(newGhostDist));
                const finalPos = targetPoint.add(drag.offsetVector);

                // Auto-rescate si se vuelve inválido
                if (!this._isValid(finalPos)) {
                    this.resetPositions();
                    return;
                }

                // Convertir a posición relativa (Chest)
                const chest = headPos.clone();
                chest.y -= 0.25;
                const relativePos = finalPos.subtract(chest);

                if (drag.side === 'left') {
                    this.currentPose!.left = relativePos;
                    const controller = (event as any).inputSource;
                    if (controller?.grip?.rotationQuaternion) {
                        this.currentPose!.leftRot = controller.grip.rotationQuaternion.clone();
                    }
                } else {
                    this.currentPose!.right = relativePos;
                    const controller = (event as any).inputSource;
                    if (controller?.grip?.rotationQuaternion) {
                        this.currentPose!.rightRot = controller.grip.rotationQuaternion.clone();
                    }
                }

                // Visualización
                this.ghost.setDragLink(drag.side, currentHandPos, finalPos);
                PoseManager.setOverride(this.targetLabel, this.currentPose!);
            }

            // Finalizar arrastre
            if (type === 2 && this.activeRemoteDrags.has(pointerId)) { // POINTERUP
                const drag = this.activeRemoteDrags.get(pointerId)!;
                const side = drag.side;
                this.ghost.setDragLink(side, null, null);

                const now = performance.now();
                const pinchTime = side === 'left' ? this.leftPinchTime : this.rightPinchTime;
                const duration = now - pinchTime;

                if (duration < this.QUICK_TAP_MAX_MS) {
                    if (side === 'left') this.currentPose!.leftClosed = !this.currentPose!.leftClosed;
                    else this.currentPose!.rightClosed = !this.currentPose!.rightClosed;
                    PoseManager.setOverride(this.targetLabel, this.currentPose!);
                }

                if (side === 'left') { this.isDraggingLeft = false; this.leftPinchTime = 0; }
                else { this.isDraggingRight = false; this.rightPinchTime = 0; }
                
                this.activeRemoteDrags.delete(pointerId);
            }
        });
    }

    private _isValid(vec: Vector3): boolean {
        return isFinite(vec.x) && isFinite(vec.y) && isFinite(vec.z);
    }

    public resetPositions() {
        if (!this.currentPose) return;
        console.log("[VRCalibration] 🧹 Reseteando posiciones de fantasmas a valores por defecto");
        this.currentPose.left = new Vector3(-0.3, 0.1, 0.4);
        this.currentPose.right = new Vector3(0.3, 0.1, 0.4);
        this.currentPose.leftRot = undefined;
        this.currentPose.rightRot = undefined;
        PoseManager.setOverride(this.targetLabel, this.currentPose);
        this.onStatusChange?.("POSICIONES RESETEADAS");
    }

    public startSession(powerId: string, phase: "PREP" | "FIRE", label: string) {
        this.currentPose = PoseManager.getPose(label);
        const worldPose = PoseManager.getWorldPose(label);

        this.targetLabel = label;
        this.state = CalibrationState.WAITING_FOR_HANDS;
        this.ghost.show(worldPose, "MUEVE O POSA");
        this.onStatusChange?.(`AJUSTE: ${powerId} (${phase})`);
        return true;
    }

    public update(ctx: XRHandsContext) {
        if (this.state === CalibrationState.IDLE || this.state === CalibrationState.DONE) return;

        const leftPos = ctx.leftWrist?.absolutePosition;
        const rightPos = ctx.rightWrist?.absolutePosition;
        if (!leftPos || !rightPos || !this.currentPose) return;

        const worldPose = PoseManager.getWorldPose(this.targetLabel);
        
        // Detectar pinzas (Index Tip vs Thumb Tip)
        const leftPinchDist = this._getPinchDist(ctx.leftHand);
        const rightPinchDist = this._getPinchDist(ctx.rightHand);
        const leftPinch = leftPinchDist < this.PINCH_THRESHOLD;
        const rightPinch = rightPinchDist < this.PINCH_THRESHOLD;

        const now = performance.now();
        // Usar la cabeza del usuario como referencia de pecho (aprox 20cm abajo)
        const head = ctx.headPos || new Vector3(0, 1.6, 0);
        const chest = head.clone();
        chest.y -= 0.25; 

        // --- MANIPULACIÓN IZQUIERDA ---
        let leftOccupied = false;
        for (const drag of this.activeRemoteDrags.values()) {
            if (drag.side === 'left') { leftOccupied = true; break; }
        }

        if (!leftOccupied) {
            this._handleHandInteraction(
                'left', leftPinch, leftPos, ctx.leftWrist?.rotationQuaternion, 
                worldPose.left, now, chest
            );
        }

        // --- MANIPULACIÓN DERECHA ---
        let rightOccupied = false;
        for (const drag of this.activeRemoteDrags.values()) {
            if (drag.side === 'right') { rightOccupied = true; break; }
        }

        if (!rightOccupied) {
            this._handleHandInteraction(
                'right', rightPinch, rightPos, ctx.rightWrist?.rotationQuaternion, 
                worldPose.right, now, chest
            );
        }

        // --- LÓGICA DE CALIBRACIÓN (POSICIONAMIENTO) ---
        const updatedWorldPose = PoseManager.getWorldPose(this.targetLabel);
        const lDist = Vector3.Distance(leftPos, updatedWorldPose.left);
        const rDist = Vector3.Distance(rightPos, updatedWorldPose.right);
        const lInPos = lDist < this.PROXIMITY_THRESHOLD;
        const rInPos = rDist < this.PROXIMITY_THRESHOLD;

        this.ghost.updateVisuals(lInPos, rInPos);
        this.ghost.show(updatedWorldPose, this._getLabelText());

        switch (this.state) {
            case CalibrationState.WAITING_FOR_HANDS:
                if (lInPos && rInPos) {
                    if (this.inPosStartTime === 0) this.inPosStartTime = now;
                    if (now - this.inPosStartTime > this.IN_POS_DURATION) {
                        this.state = CalibrationState.COUNTDOWN;
                        this.countdownValue = 3;
                        this.timer = now;
                        this.ghost.updateText(`3...`);
                    }
                } else {
                    this.inPosStartTime = 0;
                }
                break;

            case CalibrationState.COUNTDOWN:
                if (!lInPos || !rInPos) {
                    this.state = CalibrationState.WAITING_FOR_HANDS;
                    this.ghost.updateText("¡MANTÉN LA POSICIÓN!");
                    return;
                }
                const elapsed = now - this.timer;
                if (elapsed > 1000) {
                    this.countdownValue--;
                    this.timer = now;
                    if (this.countdownValue > 0) {
                        this.ghost.updateText(`${this.countdownValue}...`);
                    } else {
                        this._startCapture();
                    }
                }
                break;

            case CalibrationState.RECORDING:
                // El GSS captura frames de entrenamiento
                break;
        }
    }

    private _startCapture() {
        this.state = CalibrationState.RECORDING;
        this.ghost.updateText("¡GRABANDO!");
        this.onStatusChange?.("GRABANDO GESTO...");
        
        this.gss.startTraining(this.targetLabel);
        
        setTimeout(() => {
            this.gss.stopTraining();
            this._finish();
        }, 2000);
    }

    private _finish() {
        this.state = CalibrationState.DONE;
        this.ghost.updateText("COMPLETADO");
        this.onStatusChange?.("CALIBRACIÓN FINALIZADA");
        
        setTimeout(() => {
            this.ghost.hide();
            this.state = CalibrationState.IDLE;
        }, 1500);
    }

    public cancel() {
        this.state = CalibrationState.IDLE;
        this.ghost.hide();
        this.onStatusChange?.("CALIBRACIÓN CANCELADA");
    }

    private _getPinchDist(hand: any): number {
        if (!hand) return 999;
        const iTip = hand.getJointMesh(9)?.absolutePosition; // INDEX_FINGER_TIP (9 en Babylon)
        const tTip = hand.getJointMesh(4)?.absolutePosition; // THUMB_TIP (4 en Babylon)
        if (!iTip || !tTip) return 999;
        return Vector3.Distance(iTip, tTip);
    }

    private _handleHandInteraction(side: 'left' | 'right', isPinching: boolean, handPos: Vector3, handRot: any, ghostPos: Vector3, now: number, chest: Vector3) {
        const isDragging = side === 'left' ? this.isDraggingLeft : this.isDraggingRight;
        const pinchTime = side === 'left' ? this.leftPinchTime : this.rightPinchTime;

        if (isPinching) {
            const distToGhost = Vector3.Distance(handPos, ghostPos);
            
            // Iniciar arrastre si está cerca o ya estaba arrastrando
            if (isDragging || distToGhost < this.PROXIMITY_THRESHOLD) {
                if (side === 'left') {
                    this.isDraggingLeft = true;
                    if (this.leftPinchTime === 0) this.leftPinchTime = now;
                    this.currentPose!.left = handPos.subtract(chest);
                    if (handRot) this.currentPose!.leftRot = handRot.clone();
                } else {
                    this.isDraggingRight = true;
                    if (this.rightPinchTime === 0) this.rightPinchTime = now;
                    this.currentPose!.right = handPos.subtract(chest);
                    if (handRot) this.currentPose!.rightRot = handRot.clone();
                }
                
                // Mostrar línea visual blanca
                this.ghost.setDragLink(side, handPos, ghostPos);

                // Actualizar gestos en PoseManager
                PoseManager.setOverride(this.targetLabel, this.currentPose!);
            }
        } else {
            // Soltar
            if (isDragging) {
                // Quitar línea
                this.ghost.setDragLink(side, null, null);

                const duration = now - pinchTime;
                if (duration > 0 && duration < this.QUICK_TAP_MAX_MS) {
                    // Quick tap -> Toggle closed state (mano abierta/cerrada)
                    if (side === 'left') this.currentPose!.leftClosed = !this.currentPose!.leftClosed;
                    else this.currentPose!.rightClosed = !this.currentPose!.rightClosed;
                    PoseManager.setOverride(this.targetLabel, this.currentPose!);
                }
                
                if (side === 'left') { this.isDraggingLeft = false; this.leftPinchTime = 0; }
                else { this.isDraggingRight = false; this.rightPinchTime = 0; }
            }
        }
    }

    private _getLabelText(): string {
        if (this.state === CalibrationState.COUNTDOWN) return `${this.countdownValue}...`;
        if (this.state === CalibrationState.RECORDING) return "¡GRABANDO!";
        if (this.state === CalibrationState.DONE) return "COMPLETADO";
        if (this.isDraggingLeft || this.isDraggingRight) return "AJUSTANDO...";
        return "MANTÉN O ARRASTRA";
    }

    public isActive() {
        return this.state !== CalibrationState.IDLE;
    }
}
