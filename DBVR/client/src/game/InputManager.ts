import { VoiceRecognizer, VoiceCommand } from "./VoiceRecognizer";
import { GestureSkillSystem, XRHandsContext } from "./GestureSkillSystem";
import { GOKU_CONFIG } from "./CharacterConfigs";

export class InputManager {
  private voiceRecognizer: VoiceRecognizer;
  private gestureSkillSystem: GestureSkillSystem;
  private started = false;
  private _lastContext: XRHandsContext | null = null;

  constructor() {
    this.voiceRecognizer = new VoiceRecognizer();
    this.gestureSkillSystem = new GestureSkillSystem(null); // XR se asigna luego
    this.gestureSkillSystem.registerCharacter(GOKU_CONFIG);
  }

  public setup(allowedPowers: string[]): void {
    this.voiceRecognizer.setAllowedPowers(allowedPowers);
  }

  public async start(): Promise<void> {
    this.started = true;
    this.voiceRecognizer.start();
    await this.gestureSkillSystem.init("goku").catch(e => console.error("[InputManager] Error init GSS:", e));
    console.log("[InputManager] Voice recognition & GSS active.");
  }

  public stop(): void {
    this.voiceRecognizer.stop();
  }


  public getVoiceRecognizer(): VoiceRecognizer {
    return this.voiceRecognizer;
  }

  public getGSS(): GestureSkillSystem {
    return this.gestureSkillSystem;
  }

  public getLastContext(): XRHandsContext | null {
    return this._lastContext;
  }

  public onVoiceCommand(callback: (command: string, transcript: string) => void): void {
    this.voiceRecognizer.onCommand((command: VoiceCommand, transcript: string) => {
        if (command) {
            callback(command as string, transcript);
        }
    });
  }

  public onVoiceStatus(callback: (active: boolean, transcript: string) => void): void {
    this.voiceRecognizer.onStatus(callback);
  }

  public onSpeech(callback: (transcript: string) => void): void {
    this.voiceRecognizer.onSpeech(callback);
  }

  /**
   * Encapsulates keyboard event logic previously in Game.ts
   */
  public setupKeyboardControls(actions: {
    onBasicAttack: () => void;
    onChargeStart: () => void;
    onChargeRelease: () => void;
    onBlock: () => void;
    onDodge: () => void;
    onSpecial: (powerId: string) => void;
    onEnterVR: () => void;
    isInChargingState: () => boolean;
  }): void {
    window.addEventListener("keydown", (e) => {
      if (!this.started) return;
      
      switch (e.key.toLowerCase()) {
        case "s": actions.onBlock(); break;
        case "d": actions.onDodge(); break;
        case "v": actions.onEnterVR(); break;
      }
    });
  }

  public update(ctx: XRHandsContext): void {
    if (!this.started) return;
    this._lastContext = ctx;
    this.gestureSkillSystem.update(ctx);
  }

  public dispose(): void {
    this.voiceRecognizer.stop();
  }
}
