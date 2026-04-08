import {
  Vector3,
  Color4,
  ParticleSystem,
  Mesh,
  Scene
} from "@babylonjs/core";
import { CombatSystem } from "../combat/CombatSystem";
import { VFXManager } from "../vfx/VFXManager";
import { InputManager } from "./InputManager";
import { VRHud } from "../../ui/VRHud";
import gokuConfig from "../../models/goku.json";

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
  
  private handTrackingActive = false;

  constructor(config: PlayerControllerConfig) {
    this.scene = config.scene;
    this.vfx = config.vfx;
    this.combat = config.combat;
    this.inputManager = config.inputManager;
    this.vrHud = config.vrHud;
  }

  public setup(): void {
    this.playerAura = this.vfx.createAura("player_aura", Vector3.Zero());
    
    this.leftPalmMesh = this.scene.getMeshByName("leftHand") as Mesh;
    this.rightPalmMesh = this.scene.getMeshByName("rightHand") as Mesh;

    this.combat.onMessage((msg, color) => {
        this.vrHud?.showToast(msg, color, 3000);
    });
  }

  public update(cameraPosition: Vector3): void {
    const ctx = this.inputManager.getLastContext();
    const wasActive = this.handTrackingActive;
    this.handTrackingActive = !!(ctx && (ctx.leftWrist || ctx.rightWrist));

    if (this.handTrackingActive && ctx) {
      if (!wasActive && this.leftPalmMesh) {
         this.scene.stopAnimation(this.leftPalmMesh);
         this.scene.stopAnimation(this.rightPalmMesh!);
      }
      if (this.leftPalmMesh && ctx.leftWrist) {
        this.leftPalmMesh.position.copyFrom(ctx.leftWrist.absolutePosition);
      }
      if (this.rightPalmMesh && ctx.rightWrist) {
        this.rightPalmMesh.position.copyFrom(ctx.rightWrist.absolutePosition);
      }
    }

    this.updateAura(cameraPosition);
  }

  private updateAura(cameraPosition: Vector3): void {
    if (!this.playerAura) return;
    
    const stats = this.combat.getStats();
    const isPlayerCharging = stats.combatState === "slowMotion" || 
                           stats.combatState === "charging" || 
                           stats.combatState === "charging_special" ||
                           stats.combatState === "recharging";

    this.playerAura.emitter = new Vector3(cameraPosition.x, cameraPosition.y - 0.5, cameraPosition.z);
    
    const colorHex = gokuConfig.transformations?.[0]?.props?.color_palette || "#3b82f6";
    const pColor = Color4.FromHexString(colorHex.length === 7 ? colorHex + "cc" : colorHex);
    
    this.vfx.updateAura(this.playerAura, (stats.playerKi / 100) * 100, isPlayerCharging, stats.playerNP, pColor);
  }

  public processGestures(_cameraForward: Vector3): void {
    // La detección ahora la maneja el GestureSkillSystem (GSS) a través del InputManager.
    // Los eventos de combate se emiten desde el GSS y se capturan en Game.ts.
  }

  public dispose(): void {
    this.playerAura?.dispose();
  }
}
