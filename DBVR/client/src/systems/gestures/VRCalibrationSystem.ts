import { Scene, Vector3, WebXRHandJoint } from "@babylonjs/core";
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

    private readonly PROXIMITY_THRESHOLD = 0.25; // Aumentado a 25cm para facilitar el agarre físico
    private readonly PINCH_THRESHOLD = 0.05;     // 5cm for a pinch
    private readonly QUICK_TAP_MAX_MS = 250;     // Time for a toggle instead of a drag
    private readonly IN_POS_DURATION = 800;    

    public onStatusChange?: (status: string) => void;

    constructor(private scene: Scene, private gss: GestureSkillSystem) {
        this.ghost = new CalibrationGhost(this.scene);
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

        const now = performance.now();
        // Usar la cabeza del usuario como referencia de pecho (aprox 25cm abajo)
        const head = ctx.headPos || new Vector3(0, 1.6, 0);
        const chest = head.clone();
        chest.y -= 0.25; 

        // Generar las posiciones de mundo dinámicas basadas en el cuerpo real del jugador
        const dynamicWorldPose: PoseReference = {
            left: chest.add(this.currentPose.left),
            right: chest.add(this.currentPose.right),
            leftRot: this.currentPose.leftRot,
            rightRot: this.currentPose.rightRot,
            leftClosed: this.currentPose.leftClosed,
            rightClosed: this.currentPose.rightClosed
        };

        // Detectar pinzas verdaderas de WebXR (Index Tip vs Thumb Tip)
        const leftPinchDist = this._getPinchDist(ctx.leftHand);
        const rightPinchDist = this._getPinchDist(ctx.rightHand);
        const leftPinch = leftPinchDist < this.PINCH_THRESHOLD;
        const rightPinch = rightPinchDist < this.PINCH_THRESHOLD;

        // --- MANIPULACIÓN DIRECTA IZQUIERDA ---
        this._handleHandInteraction(
            'left', leftPinch, leftPos, ctx.leftWrist?.rotationQuaternion, 
            dynamicWorldPose.left, now, chest
        );

        // --- MANIPULACIÓN DIRECTA DERECHA ---
        this._handleHandInteraction(
            'right', rightPinch, rightPos, ctx.rightWrist?.rotationQuaternion, 
            dynamicWorldPose.right, now, chest
        );

        // --- LÓGICA DE CALIBRACIÓN (POSICIONAMIENTO) ---
        // Vuelve a calcular después de la posible manipulación
        const updatedDynamicWorldPose: PoseReference = {
            left: chest.add(this.currentPose.left),
            right: chest.add(this.currentPose.right),
            leftRot: this.currentPose.leftRot,
            rightRot: this.currentPose.rightRot,
            leftClosed: this.currentPose.leftClosed,
            rightClosed: this.currentPose.rightClosed
        };

        const lDist = Vector3.Distance(leftPos, updatedDynamicWorldPose.left);
        const rDist = Vector3.Distance(rightPos, updatedDynamicWorldPose.right);
        const lInPos = lDist < this.PROXIMITY_THRESHOLD;
        const rInPos = rDist < this.PROXIMITY_THRESHOLD;

        this.ghost.updateVisuals(lInPos, rInPos);
        this.ghost.show(updatedDynamicWorldPose, this._getLabelText());

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
        const iTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)?.absolutePosition; 
        const tTip = hand.getJointMesh(WebXRHandJoint.THUMB_TIP)?.absolutePosition; 
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
                
                // Mostrar de forma visual rápida (opcional, dejamos limpio sin línea)
                this.ghost.setDragLink(side, null, null);

                // Actualizar gestos en PoseManager
                PoseManager.setOverride(this.targetLabel, this.currentPose!);
            }
        } else {
            // Soltar
            if (isDragging) {
                // Quitar línea si existiera
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
        if (this.isDraggingLeft || this.isDraggingRight) return "[ AGARRADO ]";
        return "PELLIZCA PARA MOVER";
    }

    public isActive() {
        return this.state !== CalibrationState.IDLE;
    }
}
