import {
  Vector3,
  Color4,
  ParticleSystem,
  Mesh,
  Scene
} from "@babylonjs/core";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";
import { InputManager } from "./InputManager";
import { VRHud } from "./VRHud";
import gokuConfig from "../models/goku.json";

export interface PlayerControllerConfig {
    scene: Scene;
    vfx: VFXManager;
    combat: CombatSystem;
    inputManager: InputManager;
    vrHud: VRHud;
}

export class PlayerController {
  private scene: Scene;
  private vfx: VFXManager;
  private combat: CombatSystem;
  private inputManager: InputManager;
  private vrHud: VRHud;

  private playerAura: ParticleSystem | null = null;
  private leftPalmMesh?: Mesh;
  private rightPalmMesh?: Mesh;
  
  private lastKiBlastTime: number = 0;
  private lastBasicAttackTime: number = 0;
  private leftChargePower: number = 1.0;
  private rightChargePower: number = 1.0; 
  private leftChargeStartKi: number = 0;
  private rightChargeStartKi: number = 0;
  private lastChargeUpdateTime: number = 0;
  private lastChargedFireTime: number = 0; 
  private lastReportedGesture: string = "IDLE";
  private handTrackingActive = false;

  constructor(config: PlayerControllerConfig) {
    this.scene = config.scene;
    this.vfx = config.vfx;
    this.combat = config.combat;
    this.inputManager = config.inputManager;
    this.vrHud = config.vrHud;
  }

  public setup(): void {
    // Inicializar aura aquí si es necesario, o pasarla desde fuera
    this.playerAura = this.vfx.createAura("player_aura", Vector3.Zero());
    
    this.leftPalmMesh = this.scene.getMeshByName("leftHand") as Mesh;
    this.rightPalmMesh = this.scene.getMeshByName("rightHand") as Mesh;

    // Suscribirse a mensajes del sistema de combate para mostrarlos en el HUD
    this.combat.onMessage((msg, color) => {
        this.vrHud?.showToast(msg, color, 3000);
    });
  }

  public update(cameraPosition: Vector3): void {
    const G = this.inputManager.getGestureRecognizer();
    const lJoints = G.getLeftHandJoints();
    const rJoints = G.getRightHandJoints();
    const wasActive = this.handTrackingActive;
    this.handTrackingActive = !!(lJoints || rJoints);

    // Sync hand meshes (Desktop/Simulator)
    if (this.handTrackingActive) {
      if (!wasActive && this.leftPalmMesh) {
         this.scene.stopAnimation(this.leftPalmMesh);
         this.scene.stopAnimation(this.rightPalmMesh!);
      }
      if (this.leftPalmMesh && lJoints) this.leftPalmMesh.position.copyFromFloats(lJoints.wrist.x, lJoints.wrist.y, lJoints.wrist.z);
      if (this.rightPalmMesh && rJoints) this.rightPalmMesh.position.copyFromFloats(rJoints.wrist.x, rJoints.wrist.y, rJoints.wrist.z);
    }

    // Process charging logic
    this.updateChargingLogic();

    // Aura Update
    this.updateAura(cameraPosition);

    // If not in XR but hand tracking active, process gestures
    // This part normally depends on XR state, but we can pass it or check it if we have access to XRManager later
    // For now, let's assume Game.ts calls processGestures if needed or we check a simplified condition
  }

  private updateChargingLogic(): void {
    const G = this.inputManager.getGestureRecognizer();
    const activeCombo = G.getActiveCombo();
    const comboStep = G.getComboStep();
    const gesture = G.getCurrentGesture();
    const now = Date.now();

    if (now - this.lastChargeUpdateTime > 100) {
      this.lastChargeUpdateTime = now;
      const stats = this.combat.getStats();
      
      if (activeCombo?.startsWith("CHARGED") && comboStep === 1) {
        let chargePower = activeCombo === "CHARGED_KI_BLAST_L" ? this.leftChargePower : this.rightChargePower;
        let startKi = activeCombo === "CHARGED_KI_BLAST_L" ? this.leftChargeStartKi : this.rightChargeStartKi;
        
        if (startKi === 0) {
            if (activeCombo === "CHARGED_KI_BLAST_L") this.leftChargeStartKi = stats.playerKi;
            else this.rightChargeStartKi = stats.playerKi;
            startKi = stats.playerKi;
        }

        if (stats.playerKi > startKi * 0.8 && chargePower < 3.5 && this.combat.consumeKi(4)) {
            if (activeCombo === "CHARGED_KI_BLAST_L") this.leftChargePower += 0.2;
            else this.rightChargePower += 0.2;
            this.vrHud?.showToast(`CARGANDO: x${(chargePower+0.2).toFixed(1)}`, "#ff8800", 0);
        }
      } else {
        if (gesture !== "CHARGED_KI_BLAST_L") { this.leftChargePower = 1.0; this.leftChargeStartKi = 0; }
        if (gesture !== "CHARGED_KI_BLAST_R") { this.rightChargePower = 1.0; this.rightChargeStartKi = 0; }
      }
    }
  }

  private updateAura(cameraPosition: Vector3): void {
    if (!this.playerAura) return;
    
    const G = this.inputManager.getGestureRecognizer();
    const stats = this.combat.getStats();
    const activeCombo = G.getActiveCombo();
    const isPlayerCharging = stats.combatState === "slowMotion" || 
                           activeCombo?.startsWith("CHARGED") || 
                           G.getCurrentGesture() === "RECHARGING";

    this.playerAura.emitter = new Vector3(cameraPosition.x, cameraPosition.y - 0.5, cameraPosition.z);
    
    const colorHex = gokuConfig.transformations?.[0]?.props?.color_palette || "#3b82f6";
    const pColor = Color4.FromHexString(colorHex.length === 7 ? colorHex + "cc" : colorHex);
    
    this.vfx.updateAura(this.playerAura, (stats.playerKi / 100) * 100, isPlayerCharging, stats.playerNP, pColor);
  }

  public processGestures(cameraForward: Vector3): void {
    const G = this.inputManager.getGestureRecognizer();
    const gesture = G.getCurrentGesture();
    const gestureChanged = gesture !== this.lastReportedGesture;
    
    if (gestureChanged && gesture !== "IDLE") {
        const gestureLabels: Record<string, { label: string, color: string }> = {
            "ATTACKING": { label: "¡ATAQUE BÁSICO!", color: "#00ccff" },
            "CHARGING": { label: "¡CARGANDO ENERGÍA!", color: "#ffcc00" },
            "BLOCKING": { label: "🛡️ BLOQUEO ACTIVO", color: "#00ff88" },
            "RECHARGING": { label: "⚡ RECARGANDO KI...", color: "#cc44ff" },
            "KAMEHAMEHA": { label: "¡KAMEHAMEHA!", color: "#00ccff" },
            "KI_BLAST_L": { label: "¡KI BLAST (IZQ)!", color: "#00ccff" },
            "KI_BLAST_R": { label: "¡KI BLAST (DER)!", color: "#00ccff" },
            "CHARGED_KI_BLAST_L": { label: "¡CARGA KI BLAST (IZQ)!", color: "#ff8800" },
            "CHARGED_KI_BLAST_R": { label: "¡CARGA KI BLAST (DER)!", color: "#ff8800" },
            "RECHARGE_PREP": { label: "Preparando Recarga...", color: "#aa44ff" }
        };
        const info = gestureLabels[gesture];
        if (info) {
            this.vrHud?.showToast(info.label, info.color, 1500);
        }
    }
    
    if (gestureChanged && this.lastReportedGesture === "RECHARGE_PREP" && gesture === "IDLE") {
        this.vrHud?.showToast("Secuencia Cancelada", "#ff4444", 2000);
    }
    if (gestureChanged && this.lastReportedGesture === "RECHARGING") {
        this.combat.stopRecharge();
        this.vrHud?.showToast("Fin de Recarga", "#aaaaaa", 1500);
    }
    
    this.lastReportedGesture = gesture;

    switch (gesture) {
      case "ATTACKING": {
        const time = performance.now();
        if (time - this.lastBasicAttackTime > 600) {
          this.lastBasicAttackTime = time;
          this.combat.launchBasicAttack();
          G.reset("both");
        }
        break;
      }
      case "CHARGING": this.combat.startChargedAttack(); break;
      case "BLOCKING": this.combat.activateBlock(); break;
      case "RECHARGING": this.combat.rechargeKi(); break;
      case "KAMEHAMEHA": this.vfx.spawnImpact({x:0,y:1.5,z:2}, "heavy"); break;
      case "KI_BLAST_L":
      case "KI_BLAST_R": {
        const time = performance.now();
        if (time - this.lastChargedFireTime < 500 || time - this.lastKiBlastTime < 400) break;
        this.lastKiBlastTime = time;
        const hand = gesture === "KI_BLAST_L" ? G.getLeftHandJoints() : G.getRightHandJoints();
        if (hand) {
          this.combat.launchKiBlast(hand.wrist, cameraForward, 1.0);
          this.combat.applyVoiceBonus("ki_blast");
          this.inputManager.getGestureRecognizer().reset(gesture === "KI_BLAST_L" ? "left" : "right");
        }
        break;
      }
      case "CHARGED_KI_BLAST_L":
      case "CHARGED_KI_BLAST_R": {
        const hand = gesture === "CHARGED_KI_BLAST_L" ? G.getLeftHandJoints() : G.getRightHandJoints();
        const power = gesture === "CHARGED_KI_BLAST_L" ? this.leftChargePower : this.rightChargePower;
        if (hand) {
          this.combat.launchKiBlast(hand.wrist, cameraForward, power);
          this.combat.applyVoiceBonus("ki_blast");
          this.lastChargedFireTime = performance.now();
          this.inputManager.getGestureRecognizer().reset(gesture === "CHARGED_KI_BLAST_L" ? "left" : "right");
        }
        break;
      }
    }
    
    // Notify debug overlay through some means or let Game.ts handle it
  }

  public dispose(): void {
    this.playerAura?.dispose();
  }
}
