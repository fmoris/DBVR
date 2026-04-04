import { Scene } from "@babylonjs/core";
import { GestureRecognizer } from "./GestureRecognizer";
import { VoiceRecognizer, VoiceCommand } from "./VoiceRecognizer";
import { GestureSimulator } from "./GestureSimulator";

export class InputManager {
  private gestureRecognizer: GestureRecognizer;
  private voiceRecognizer: VoiceRecognizer;
  private simulator: GestureSimulator;
  private started = false;

  constructor(scene: Scene) {
    this.gestureRecognizer = new GestureRecognizer(scene);
    this.voiceRecognizer = new VoiceRecognizer();
    this.simulator = new GestureSimulator(this.gestureRecognizer);
  }

  public setup(allowedPowers: string[]): void {
    this.voiceRecognizer.setAllowedPowers(allowedPowers);
    this.gestureRecognizer.setAllowedPowers(allowedPowers);
  }

  public start(): void {
    this.started = true;
    this.voiceRecognizer.start();
    console.log("[InputManager] Voice recognition active.");
  }

  public stop(): void {
    this.voiceRecognizer.stop();
  }

  public getGestureRecognizer(): GestureRecognizer {
    return this.gestureRecognizer;
  }

  public getVoiceRecognizer(): VoiceRecognizer {
    return this.voiceRecognizer;
  }

  public getSimulator(): GestureSimulator {
    return this.simulator;
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
        case "a": actions.onBasicAttack(); break;
        case "w": 
          if (actions.isInChargingState()) {
            actions.onChargeRelease();
          } else {
            actions.onChargeStart();
          }
          break;
        case "s": actions.onBlock(); break;
        case "d": actions.onDodge(); break;
        case "1": actions.onSpecial("kamehameha"); break;
        case "2": actions.onSpecial("finalFlash"); break;
        case "v": actions.onEnterVR(); break;
        
        // Simulator shortcuts
        case "k": this.simulator.playRechargeSequence(); break;
        case "i": this.simulator.playKiBlastSequence("left"); break;
        case "o": this.simulator.playKiBlastSequence("right"); break;
      }
    });
  }

  public update(): void {
    // Logic that needs to run every frame for inputs
  }

  public dispose(): void {
    this.voiceRecognizer.stop();
  }
}
