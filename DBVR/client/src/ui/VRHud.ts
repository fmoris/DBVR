import {
  Scene,
  Mesh,
  MeshBuilder,
  Vector3,
} from "@babylonjs/core";
import { CombatSystem, GameStats } from "../systems/combat/CombatSystem";
import { InputManager } from "../systems/input/InputManager";
import gokuBaseImg from "../assets/images/rosters/goku_base.png";
import vegetaBaseImg from "../assets/images/rosters/vegeta_base.png";
import powersConfig from "../models/powers.json";
import gokuConfig from "../models/goku.json";

// Importar nuevos paneles modulares
import { StatsPanel } from "./components/StatsPanel";
import { ActionPanel } from "./components/ActionPanel";
import { StatusPanel } from "./components/StatusPanel";
import { DebugPanel } from "./components/DebugPanel";
import { PowersGuidePanel } from "./components/PowersGuidePanel";
import { GestureSimulator } from "../systems/gestures/GestureSimulator";
import { VRCalibrationSystem } from "../systems/gestures/VRCalibrationSystem";
import { PoseManager } from "../systems/gestures/PoseReferences";

const STATE_LABELS: Record<string, string> = {
  neutral: "Neutral",
  charging: "Cargando...",
  charging_special: "Carga Especial",
  attacking: "Atacando",
  defending: "Defendiendo",
  slowMotion: "Camara Lenta",
  hit: "Impacto",
  melee: "Combate Cercano",
  recharging: "Recargando KI...",
};

const STATE_COLORS: Record<string, string> = {
  neutral: "#00ff88",
  charging: "#ffcc00",
  charging_special: "#ff8800",
  attacking: "#ff6600",
  defending: "#00aaff",
  slowMotion: "#cc44ff",
  hit: "#ff2222",
  melee: "#ff0066",
  recharging: "#cc44ff",
};

function getNPColor(np: number): string {
  if (np >= 150000) return "#ffffff";
  if (np >= 70000) return "#ff8800";
  if (np >= 30000) return "#ffcc00";
  if (np >= 10000) return "#00ecff";
  if (np >= 3000) return "#00ff88";
  return "#aabbcc";
}

export class VRHud {
  private playerPanel: StatsPanel;
  private enemyPanel: StatsPanel;
  private attackPanel: ActionPanel;
  private defensePanel: ActionPanel;
  private statusPanel: StatusPanel;
  private debugPanel: DebugPanel;
  private powersGuidePanel: PowersGuidePanel;
  private gestureSimulator: GestureSimulator;
  private calibrationSystem: VRCalibrationSystem;
  private hudRoot: Mesh | null = null;


  private currentHudType: "normal" | "defense" | "melee" | "recharging" | null = null;
  private visible = false;

  constructor(private scene: Scene, private combat: CombatSystem, private inputManager: InputManager) {
    this.playerPanel = new StatsPanel(scene, true);
    this.enemyPanel = new StatsPanel(scene, false);
    this.attackPanel = new ActionPanel(scene, true);
    this.defensePanel = new ActionPanel(scene, false);
    this.statusPanel = new StatusPanel(scene);
    this.debugPanel = new DebugPanel(scene);
    this.powersGuidePanel = new PowersGuidePanel(scene, combat, inputManager);
    this.powersGuidePanel.onModelRepaired = () => {
        this.showToast("🧱 MODELO REPARADO", "#00ff88", 3000);
    };

    this.playerPanel.updateAvatar(gokuBaseImg);
    this.enemyPanel.updateAvatar(vegetaBaseImg);
    
    this.gestureSimulator = new GestureSimulator(scene);
    this.calibrationSystem = new VRCalibrationSystem(scene, this.inputManager.getGSS());
    this.calibrationSystem.onStatusChange = (status) => this.statusPanel.setStatusText(status);

    this.hide();
    this.combat.onStatsChange((stats) => this.update(stats));
    
    // Bucle de actualización para sistemas que requieren alta frecuencia (Calibración)
    scene.onBeforeRenderObservable.add(() => {
        const ctx = this.inputManager.getLastContext();
        if (ctx && this.calibrationSystem.isActive()) {
            this.calibrationSystem.update(ctx);
        }
    });

    this.powersGuidePanel.renderPowersList(
        undefined, 
        (id: string, ph: "PREP" | "FIRE") => this.startCalibration(id, ph), 
        (id: string) => this.resetCalibration(id), 
        (id: string) => this.simulateGesture(id),
        () => this.resetVRPositions()
    );

    this.setupEventListeners();
  }

  private setupEventListeners(): void {
    window.addEventListener('gss-saved-local', (e: any) => {
        this.showToast(`💾 GESTO GUARDADO: ${e.detail.id.toUpperCase()}`, "#00ff88", 4000);
        this.updatePowersGuide(this.combat.getStats());
    });

    window.addEventListener('gss-sync-start', () => {
        this.showToast(`☁️ SINCRONIZANDO CON SERVIDOR...`, "#ffcc00", 0);
    });

    window.addEventListener('gss-sync-success', (e: any) => {
        this.showToast(`✅ SINCRONIZACIÓN EXITOSA`, "#00ff88", 5000);
        this.showToast(`📄 ARCHIVO: ${e.detail.filename}`, "#aaaaaa", 5000);
    });

    window.addEventListener('gss-sync-error', () => {
        this.showToast(`❌ ERROR DE SINCRONIZACIÓN`, "#ff4444", 6000);
    });

    window.addEventListener('gss-remote-load-start', (e: any) => {
        this.showToast(`📥 CARGANDO MODELO REMOTO: ${e.detail.id.toUpperCase()}...`, "#00ccff", 0);
    });

    window.addEventListener('gss-remote-load-success', (e: any) => {
        this.showToast(`✅ MODELO REMOTO CARGADO`, "#00ff88", 5000);
        this.showToast(`📄 ARCHIVO: ${e.detail.filename}`, "#aaaaaa", 5000);
        this.updatePowersGuide(this.combat.getStats());
    });

    window.addEventListener('gss-remote-load-error', () => {
        this.showToast(`⚠️ NO SE PUDO CARGAR MODELO REMOTO`, "#ffff00", 5000);
        this.showToast(`💾 USANDO RESPALDO LOCAL`, "#aaaaaa", 5000);
        this.updatePowersGuide(this.combat.getStats());
    });
  }

  public attachToXRCamera(xrCamera: any): void {
    const forward = xrCamera.getForwardRay().direction;
    const pos = xrCamera.globalPosition.clone();
    
    if (this.hudRoot) this.hudRoot.dispose();

    this.hudRoot = MeshBuilder.CreateBox("hudRoot", { size: 0.01 }, this.scene);
    this.hudRoot.isVisible = false;
    this.hudRoot.position = pos;
    this.hudRoot.lookAt(pos.add(new Vector3(forward.x, 0, forward.z)));

    const panels = [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ];

    panels.forEach(p => p.parent = this.hudRoot);

    // Posiciones locales
    this.playerPanel.position = new Vector3(-1.1, 0.4, 1.4);
    this.playerPanel.rotation = new Vector3(0, -0.4, 0);

    this.enemyPanel.position = new Vector3(1.1, 0.4, 1.4);
    this.enemyPanel.rotation = new Vector3(0, 0.4, 0);

    this.attackPanel.position = new Vector3(0.00, 0.95, 1.4);
    this.defensePanel.position = new Vector3(0.00, -0.72, 1.4);
    
    // StatusPanel un poco más alto para acomodar el log
    this.statusPanel.position = new Vector3(0.00, 0.75, 1.3);
    this.powersGuidePanel.position = new Vector3(1.15, 0.22, 1.3);
    this.powersGuidePanel.rotation = new Vector3(0, 0.45, 0);

    this.debugPanel.position = new Vector3(1.15, -0.38, 1.3);
    this.debugPanel.rotation = new Vector3(0, 0.45, 0);

    this.show();
  }

  public detachFromCamera(): void {
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(p => p.parent = null);

    if (this.hudRoot) {
        this.hudRoot.dispose();
        this.hudRoot = null;
    }
    this.hide();
  }

  public show(): void {
    this.visible = true;
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(p => p.setEnabled(true));
    this.update(this.combat.getStats());
  }

  public hide(): void {
    this.visible = false;
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(p => p.setEnabled(false));
  }

  public isVisible(): boolean { return this.visible; }

  public update(stats: GameStats): void {
    if (!this.visible) return;

    let targetType: "normal" | "defense" | "melee" | "recharging" = "normal";
    if (stats.enemyAttacking) targetType = "defense";
    else if (stats.combatState === "melee") targetType = "melee";
    else if (stats.combatState === "recharging") targetType = "recharging";

    if (this.currentHudType !== targetType) {
      this.refreshActions(targetType, stats);
      this.currentHudType = targetType;
    }

    this.updateStatsPanels(stats);
    this.updateStatusAndActions(stats);
    this.updatePowersGuide(stats);
  }

  private updateStatsPanels(stats: GameStats): void {
    const pNP = stats.playerNP || 10000;
    const pKI = (stats.playerKi / stats.maxKi) * 100;
    this.playerPanel.updateStats(
        pNP, pNP / 100000, getNPColor(pNP),
        stats.playerKi, pKI,
        STATE_LABELS[stats.combatState] || "NEUTRAL",
        STATE_COLORS[stats.combatState] || "#00ff88"
    );

    const eNP = stats.enemyNP || 10000;
    const eKI = (stats.enemyKi / stats.enemyMaxKi) * 100;
    this.enemyPanel.updateStats(
        eNP, eNP / 100000, getNPColor(eNP),
        stats.enemyKi, eKI,
        STATE_LABELS[stats.combatState] || "NEUTRAL",
        STATE_COLORS[stats.combatState] || "#ff4444"
    );
  }

  private updateStatusAndActions(stats: GameStats): void {
    if (stats.isSlowMotion) {
      this.statusPanel.updateStatus("⚡ BULLET TIME", "#cc44ff", "rgba(80,0,120,0.75)", "#cc44ff", 2);
    } else if (stats.enemyAttackName) {
      const isAttacking = stats.enemyAttacking;
      this.statusPanel.updateStatus((isAttacking ? "⚠ " : "ℹ ") + stats.enemyAttackName, 
        isAttacking ? "#ff2222" : "#00ff88", 
        isAttacking ? "rgba(80,0,0,0.75)" : "rgba(0,60,20,0.75)",
        isAttacking ? "#ff2222" : "#00ff88", 2);
    } else if (stats.combatState === "charging" || stats.combatState === "charging_special") {
      const pct = Math.min(100, (stats.chargeTime / 8) * 100);
      this.statusPanel.updateStatus(`⚡ CARGANDO ${pct.toFixed(0)}%`, "#ffcc00", "rgba(60,40,0,0.75)", "#ffcc00", 2);
    } else {
       this.statusPanel.setStatusText("");
    }

    this.attackPanel.filterByKi(stats.playerKi);
    this.defensePanel.filterByKi(stats.playerKi);

    const kiText = `KI: ${stats.playerKi.toFixed(0)}`;
    const kiColor = stats.playerKi > 20 ? "#00ccff" : "#ff4444";
    if (this.currentHudType === "normal") this.attackPanel.setTitle(`⚔ ATAQUES [${kiText}]`, kiColor);
  }

  private updatePowersGuide(stats: GameStats): void {
    const targetAttack = (stats.combatState === "charging_special") ? (stats.specialType ?? undefined) : undefined;
    
    // Solo renderizar si el ataque cambió o la lista fue forzada a actualizar

    this.powersGuidePanel.renderPowersList(
        targetAttack, 
        (id: string, ph: "PREP" | "FIRE") => this.startCalibration(id, ph), 
        (id: string) => this.resetCalibration(id), 
        (id: string) => this.simulateGesture(id),
        () => this.resetVRPositions()
    );
  }

  public renderPowersList(
      attackId?: string, 
      onCalib?: (id: string, ph: "PREP" | "FIRE") => void, 
      onReset?: (id: string) => void, 
      onSimulate?: (id: string) => void,
      onResetPos?: () => void
  ): void {
    this.powersGuidePanel.renderPowersList(attackId, onCalib, onReset, onSimulate, onResetPos);
  }

  private refreshActions(type: "normal" | "defense" | "melee" | "recharging", stats: GameStats): void {
    if (this.currentHudType === type) return;
    this.currentHudType = type;
    
    this.attackPanel.clearActions();
    this.defensePanel.clearActions();

    const c = this.combat;

    if (type === "normal") {
      this.attackPanel.setEnabled(true);
      this.defensePanel.setEnabled(true);
      this.attackPanel.setTitle("⚔ ATAQUES");
      this.defensePanel.setTitle("🛡 COMPLEMENTO");

      this.attackPanel.addAction("A", "Atacar", "#00ff88", "#003322", () => {
          c.launchBasicAttack();
          this.simulateGesture("ki_blast", true);
      }, 8);
      this.attackPanel.addAction("W", "Cargar", "#ffcc00", "#332200", () => {
          c.startChargedAttack();
          this.simulateGesture("charged_ki_blast", true);
      }, 20);

      const allowedPowers = gokuConfig.transformations[0].powers || [];
      const powersDict = powersConfig as Record<string, any>;
      let kIdx = 1;
      for (const k of allowedPowers) {
        const d = powersDict[k];
        if (d && (d.type === "ofensiva" || d.type === "especial")) {
          const color = k === "kamehameha" ? "#00ccff" : "#ff4400";
          this.attackPanel.addAction(`${kIdx}`, d.name || k, color, "#331100", () => {
              c.triggerSpecial(k);
              this.simulateGesture(k, true);
          }, 40);
          kIdx++;
        }
      }
      this.defensePanel.addAction("R", "Recargar KI", "#cc44ff", "#220033", () => {
          c.rechargeKi();
          this.simulateGesture("recharge", true);
      }, 0);
    }
    else if (type === "defense") {
      this.attackPanel.setEnabled(false);
      this.defensePanel.setEnabled(true);
      this.defensePanel.setTitle(`⚠️ ¡CUIDADO! VIENE: ${stats.enemyAttackName}`);

      const attType = stats.enemyAttackType || "basic";
      if (attType === "basic") {
        this.defensePanel.addAction("S", "Bloqueo Seguro", "#00ff88", "#002211", () => c.activateBlock(), 15);
        this.defensePanel.addAction("D", "Esquiva", "#66ccff", "#001122", () => c.activateDodge(), 5);
      } else {
        this.defensePanel.addAction("S", "Desvío Preciso", "#ff8800", "#331100", () => c.activateDeflect(), 10);
        this.defensePanel.addAction("K", "Choque de Poder", "#ffcc00", "#332200", () => c.triggerPowerClash(), 50);
        this.defensePanel.addAction("D", "Esquiva Crucial", "#ffffff", "#333333", () => c.activateDodge(), 5);
      }
    }
    else if (type === "melee") {
      this.attackPanel.setEnabled(true);
      this.defensePanel.setEnabled(false);
      this.attackPanel.setTitle("👊 PUÑO DE HIERRO (MELEE)");

      this.attackPanel.addAction("A", "Rápido", "#00ff88", "#002211", () => c.meleeAttack("light"), 0);
      this.attackPanel.addAction("S", "Múltiple", "#66ccff", "#001122", () => c.meleeAttack("heavy"), 0);
      this.attackPanel.addAction("D", "Cargado", "#ffcc00", "#332200", () => c.meleeAttack("charged"), 0);
      this.attackPanel.addAction("W", "Vanish", "#cc44ff", "#220033", () => c.meleeAttack("vanish"), 10);
    }
  }

  public updateHandTrackingDebug(leftHandActive: boolean, rightHandActive: boolean, leftJoints: any, rightJoints: any, gesture: string, apiSource: string): void {
    if (!this.visible) return;

    let status = leftHandActive || rightHandActive ? `✅ Manos detectadas (${apiSource})` : `⏳ Esperando manos... (${apiSource})`;
    let statusColor = leftHandActive || rightHandActive ? "#00ff00" : "#ffff00";

    const formatJoints = (active: boolean, joints: any) => {
        if (!active || !joints) return "No detectada";
        const w = joints.wrist;
        const i = joints.indexTip;
        return `Muñeca: ${w ? `X:${w.x.toFixed(2)} Y:${w.y.toFixed(2)} Z:${w.z.toFixed(2)}` : "N/A"}\nÍndice: ${i ? `X:${i.x.toFixed(2)} Y:${i.y.toFixed(2)} Z:${i.z.toFixed(2)}` : "N/A"}`;
    }

    let gestureInfo = gesture || "NINGUNO";
    const gss = this.inputManager.getGSS();
    if (gss) {
        gestureInfo = `PERSONAJE: ${(gss.activeCharacter?.id || "unknown").toUpperCase()}\nESTADO: ${gss.currentState.toUpperCase()}`;
    }

    this.debugPanel.updateDebug(status, statusColor, formatJoints(leftHandActive, leftJoints), formatJoints(rightHandActive, rightJoints), gestureInfo);
  }

  public showToast(msg: string, col: string = "white", dur: number = 4000): void { this.statusPanel.showToast(msg, col, dur); }
  public hideToast(): void { this.statusPanel.hideToast(); }

  private startCalibration(powerId: string, phase: "PREP" | "FIRE"): void {
      const label = this.getLabelForPower(powerId, phase);
      
      this.statusPanel.setStatusBgVisible(true);
      
      // Intentar calibración guiada inmersiva
      const started = this.calibrationSystem.startSession(powerId, phase, label);
      
      if (!started) {
          // Fallback a modo manual con delay de 1.5s
          this.statusPanel.setStatusText(`PREPARA: ${powerId} (${phase})\nGRABANDO EN 1.5s...`);
          
          setTimeout(() => {
              this.statusPanel.setStatusText(`¡GRABANDO YA!\n(MANTÉN 2 SEGUNDOS)`);
              this.inputManager.getGSS().startTraining(label);
              
              setTimeout(() => {
                  this.inputManager.getGSS().stopTraining();
                  this.statusPanel.setStatusText(`CALIBRACIÓN OK:\n${label}`);
                  setTimeout(() => this.statusPanel.setStatusBgVisible(false), 2000);
                  this.powersGuidePanel.renderPowersList(
                      undefined, 
                      (id: string, ph: "PREP" | "FIRE") => this.startCalibration(id, ph), 
                      (id: string) => this.resetCalibration(id), 
                      (id: string) => this.simulateGesture(id),
                      () => this.resetVRPositions()
                  );
              }, 2000);
          }, 1500);
      }
  }

  private resetVRPositions(): void {
      this.calibrationSystem.resetPositions();
      PoseManager.reset();
      this.statusPanel.showToast("POSICIONES REINICIADAS", "#00ff88", 2000);
      // Refrescar para asegurar que los fantasmas se actualicen si están visibles
      this.powersGuidePanel.renderPowersList(
          undefined, 
          (id: string, ph: "PREP" | "FIRE") => this.startCalibration(id, ph), 
          (id: string) => this.resetCalibration(id), 
          (id: string) => this.simulateGesture(id),
          () => this.resetVRPositions()
      );
  }

  private resetCalibration(powerId: string): void {
      const gss = this.inputManager.getGSS();
      const labelPrep = this.getLabelForPower(powerId, "PREP");
      const labelFire = this.getLabelForPower(powerId, "FIRE");

      gss.removeLabel(labelPrep);
      gss.removeLabel(labelFire);

      this.statusPanel.setStatusText(`¡GESTOS DE ${powerId.toUpperCase()} LIMPIOS!\nReset instantáneo completado.`);
      this.statusPanel.setStatusBgVisible(true);
      this.statusPanel.setStatusBgBackground("rgba(100, 100, 100, 0.7)");
      
      this.powersGuidePanel.renderPowersList(
          undefined, 
          (id: string, ph: "PREP" | "FIRE") => this.startCalibration(id, ph), 
          (id: string) => this.resetCalibration(id), 
          (id: string) => this.simulateGesture(id),
          () => this.resetVRPositions()
      );
      setTimeout(() => this.statusPanel.setStatusBgVisible(false), 2000);
  }

  private getLabelForPower(powerId: string, phase: "PREP" | "FIRE"): string {
      const pId = powerId.toLowerCase();
      if (pId === "kamehameha") return (phase === "PREP") ? "kamehameha_preparation" : "kamehameha_firing";
      if (pId === "genkidama") return (phase === "PREP") ? "genkidama_preparation" : "genkidama_firing";
      if (pId === "ki_blast") return (phase === "PREP") ? "ki_prep" : "ki_fire";
      if (pId === "charged_ki_blast") return (phase === "PREP") ? "ki_charge_prep" : "ki_charge_fire";
      if (pId === "recharge") return (phase === "PREP") ? "recharge_p1" : "recharge_p2";
      
      const power = (powersConfig as any)[pId];
      return (power && power.vr_gestures) 
        ? ((phase === "PREP") ? power.vr_gestures.preparation : power.vr_gestures.firing)
        : `${pId}_${phase.toLowerCase()}`;
  }

  private simulateGesture(powerId: string, instant: boolean = false): void {
      console.log(`[VRHud] simulateGesture called for: ${powerId}`);
      const labelPrep = this.getLabelForPower(powerId, "PREP");
      const labelFire = this.getLabelForPower(powerId, "FIRE");

      const origin = this.hudRoot ? this.hudRoot.position.clone() : new Vector3(0, 1.4, 0);
      
      // Extraer rotación Y real del Quaternion (lookAt lo usa internamente)
      let rotY = 0;
      if (this.hudRoot) {
          if (this.hudRoot.rotationQuaternion) {
              rotY = this.hudRoot.rotationQuaternion.toEulerAngles().y;
          } else {
              rotY = this.hudRoot.rotation.y;
          }
      }
      const rot = { y: rotY };
      
      if (!instant) {
          this.statusPanel.setStatusText(`SIMULANDO DENTRO DE 1s:\n${powerId.toUpperCase()}`);
          this.statusPanel.setStatusBgVisible(true);
          this.statusPanel.setStatusBgBackground("rgba(0, 100, 255, 0.7)");
          
          setTimeout(() => {
              this.statusPanel.setStatusBgVisible(false);
              this.gestureSimulator.playGestureSequence(labelPrep, labelFire, origin, rot);
          }, 1000);
      } else {
          this.gestureSimulator.playGestureSequence(labelPrep, labelFire, origin, rot);
      }
  }

  public dispose(): void {
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(p => p.dispose());
    
    if (this.gestureSimulator) this.gestureSimulator.dispose();
  }
}
