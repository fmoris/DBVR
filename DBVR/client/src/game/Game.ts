import { Vector3, Color4, ParticleSystem } from "@babylonjs/core";
import "@babylonjs/loaders/glTF";
import { HUD } from "./HUD";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";
import { InputManager } from "./InputManager";
import { GameEngine } from "./GameEngine";
import { EnvironmentManager } from "./EnvironmentManager";
import { ResultScreen } from "./ResultScreen";
import { VRHud } from "./VRHud";
import { GestureDebugOverlay } from "./GestureDebugOverlay";
import { PlayerController } from "./PlayerController";
import { XRManager } from "./XRManager";
import gokuConfig from "../models/goku.json";
import vegetaConfig from "../models/vegeta.json";

// @ts-ignore
import gokuBaseUrl from "../models/goku/goku_base.glb?url";
// @ts-ignore
import vegetaBaseUrl from "../models/vegeta/vegeta_base.glb?url";

const MODEL_URLS: Record<string, string> = {
  "goku/goku_base.glb": gokuBaseUrl,
  "vegeta/vegeta_base.glb": vegetaBaseUrl,
};

export class Game {
  private engineManager: GameEngine;
  private envManager: EnvironmentManager;
  private inputManager!: InputManager;
  private xrManager!: XRManager;
  private playerController!: PlayerController;
  private hud!: HUD;
  private combat!: CombatSystem;
  private vfx!: VFXManager;
  private resultScreen!: ResultScreen;
  private vrHud!: VRHud;
  private debugOverlay!: GestureDebugOverlay;
  
  private combatStartTime = 0;
  private enemyAura: ParticleSystem | null = null;
  private started = false;
  private menuCallback: (() => void) | null = null;

  constructor(private canvas: HTMLCanvasElement, private xrOverlay: HTMLElement = canvas.parentElement!) {
    this.engineManager = new GameEngine(canvas);
    this.envManager = new EnvironmentManager(this.engineManager.getScene());
  }

  setMenuCallback(cb: () => void): void { this.menuCallback = cb; }

  start(): void {
    const scene = this.engineManager.getScene();
    this.vfx = new VFXManager(scene);
    this.combat = new CombatSystem(scene, this.vfx, gokuConfig, vegetaConfig);
    this.inputManager = new InputManager();
    this.vrHud = new VRHud(scene, this.combat, this.inputManager);
    this.hud = new HUD(this.xrOverlay, this.combat);
    this.resultScreen = new ResultScreen(this.xrOverlay);
    this.debugOverlay = new GestureDebugOverlay(this.xrOverlay, scene);

    this.playerController = new PlayerController({
        scene, vfx: this.vfx, combat: this.combat, inputManager: this.inputManager, vrHud: this.vrHud
    });

    this.xrManager = new XRManager({
        scene, xrOverlay: this.xrOverlay, inputManager: this.inputManager, 
        playerController: this.playerController, vrHud: this.vrHud, 
        hud: this.hud, debugOverlay: this.debugOverlay,
        envManager: this.envManager
    });

    this.inputManager.setup(gokuConfig.transformations?.[0]?.powers || []);
    this.envManager.setup(MODEL_URLS, vegetaConfig.transformations?.[0]?.url, (vegetaConfig as any).height_m || 1.64);

    this.hud.onMenu(() => this.menuCallback?.());
    this.hud.onDebugToggle(() => this.debugOverlay.toggle());

    this.setupKeyboard();
    this.setupVoiceRecognition();
    this.setupGameOverHandler();
    
    this.xrManager.init();

    this.started = true;
    this.combatStartTime = Date.now();
    this.playerController.setup();
    this.enemyAura = this.vfx.createAura("enemy_aura", Vector3.Zero());
    
    this.hud.show();
    this.canvas.focus();
    this.inputManager.start().then(() => {
        this.vrHud.renderPowersList();
    });
    this.setupGSSListeners(); // Nueva vinculación
    this.engineManager.runRenderLoop();

    scene.registerBeforeRender(() => this.updateFrame());
  }

  private updateFrame(): void {
    const camera = this.engineManager.getCamera();
    this.playerController.update(camera.position);

    const stats = this.combat.getStats();
    if (this.enemyAura) {
      const colorHex = vegetaConfig.transformations?.[0]?.props?.color_palette || "#1e1b4b";
      const eColor = Color4.FromHexString(colorHex.length === 7 ? colorHex + "cc" : colorHex);
      this.vfx.updateAura(this.enemyAura, (stats.enemyKi / 100) * 100, stats.combatState === "slowMotion", stats.enemyNP, eColor);
    }

  }

  private setupGameOverHandler(): void {
    this.resultScreen.onAction((action) => {
      if (action === "restart") window.location.reload();
      else if (action === "menu" && this.menuCallback) { this.resultScreen.hide(); this.menuCallback(); }
      else window.location.reload();
    });

    this.combat.onGameOver((winner) => {
      const stats = this.combat.getStats();
      this.resultScreen.show({
        playerNP: stats.playerNP, enemyNP: stats.enemyNP, playerKi: stats.playerKi,
        winner, combatDurationSeconds: (Date.now() - this.combatStartTime) / 1000,
      });
    });
  }

  private setupVoiceRecognition(): void {
    console.log("[Game] Setting up voice recognition...");
    if (!this.inputManager.getVoiceRecognizer().isAvailable()) {
        console.warn("[Game] Voice recognition NOT available.");
        return;
    }
    this.inputManager.onVoiceCommand((command, transcript) => {
       // console.log(`[Game] Voice Command detected: ${command} ("${transcript}")`);
       if (this.started && command) { 
           this.combat.triggerSpecial(command); 
           this.combat.applyVoiceBonus(command); 
           this.vrHud?.showToast(`Voz: "${transcript}" -> ¡ÉXITO!`, "#00ff88", 2000);
       }
    });

    this.inputManager.onVoiceStatus((_active, transcript) => {
        // if (transcript) console.log(`[Game] Voice Status: ${_active}, Transcript: "${transcript}"`);
        this.hud.showVoiceTranscript(transcript);
    });

    this.inputManager.onSpeech((transcript) => {
        // console.log(`[Game] Raw Speech detected: "${transcript}"`);
        if (!this.started) return;
        
        // Notificar actividad para recarga
        this.combat.registerVoiceActivity();
        
        const lower = transcript.toLowerCase();
        const isBonus = lower.includes("ha") || lower.includes("ja") || lower.includes("pum");
        
        if (isBonus) {
            this.combat.registerVoiceTrigger("blast_bonus");
            this.vrHud?.showToast(`Voz: "${transcript}" -> ¡POTENCIADO!`, "#ffcc00", 1500);
        } else {
            // Mostrar transcripción simple si no es un comando para dar feedback de que el micro funciona
            // Solo si no estamos en medio de un ataque especial para no saturar
            const stats = this.combat.getStats();
            if (stats.combatState !== "attacking") {
                this.vrHud?.showToast(`Voz: "${transcript}"`, "#aaaaaa", 1000);
            }
        }
    });
  }

  private setupKeyboard(): void {
    this.inputManager.setupKeyboardControls({
        onBasicAttack: () => this.combat.launchBasicAttack(),
        onChargeStart: () => this.combat.startChargedAttack(),
        onChargeRelease: () => this.combat.releaseChargedAttack(),
        onBlock: () => this.combat.activateBlock(),
        onDodge: () => this.combat.activateDodge(),
        onSpecial: (p) => this.combat.triggerSpecial(p),
        onEnterVR: () => this.enterVR(),
        isInChargingState: () => this.combat.isInChargingState()
    });
  }

  private setupGSSListeners(): void {
    const gss = this.inputManager.getGSS();
    
    gss.onAttack = (name, power, hand, character) => {
        if (!this.started) return;

        // Mapeo de ataques GSS -> CombatSystem
        if (name === "kamehameha" || name === "galick_gun" || name === "final_flash" || name === "genkidama") {
            // Ya cargado por FSM, procedemos a disparar
            this.combat.triggerSpecial(name); 
        } 
        else if (name === "ki_blast_quick" || name === "ki_blast_charged") {
            const h = (hand === "both" || hand === "right") ? "right" : "left";
            const ctx = this.inputManager.getLastContext();
            const wrist = h === "left" ? ctx?.leftWrist : ctx?.rightWrist;
            if (wrist) {
                const multiplier = name === "ki_blast_quick" ? 1.0 : (1.0 + power);
                this.combat.launchKiBlast(wrist.absolutePosition, this.engineManager.getCamera().getForwardRay().direction, multiplier);
            }
        }

        this.vrHud?.showToast(`ATAQUE GSS: ${name.toUpperCase()} (${character})`, "#00ff88", 1500);
    };

    gss.onPhaseChange = (from, to) => {
        if (to === "kame_charge" || to.includes("charge")) {
             // Sincronizar inicio de carga en CombatSystem si no ha empezado
             const attack = to === "kame_charge" ? "kamehameha" : "charged_ki_blast";
             if (this.combat.getStats().combatState === "neutral") {
                 this.combat.triggerSpecial(attack);
             }
        } else if (to === "idle" && from.includes("charge")) {
            // Cancelado en GSS -> Cancelar en Combat
            this.combat.cancelSpecial();
        }
    };

    gss.onChargeUpdate = (_name, _ratio) => {
        // Opcional: Actualizar VFX de carga en tiempo real con el ratio del GSS
        // this.combat.updateChargeRatio(_ratio);
    };
  }

  async enterVR(): Promise<void> { await this.xrManager.enterVR(); }

  async disposeAndExit(): Promise<void> {
    await this.xrManager.exitXR();
    this.playerController.dispose();
    this.inputManager.dispose();
    this.engineManager.dispose();
  }

  dispose(): void { this.engineManager.dispose(); }
}
