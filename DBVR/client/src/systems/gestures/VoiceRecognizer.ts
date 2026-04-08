// VoiceRecognizer.ts
// Reconocimiento de voz usando Web Speech API para activar ataques especiales.
// Integrado dinámicamente con powers.json.

import powersConfig from "../../models/powers.json";
import gokuConfig from "../../models/goku.json";

export type VoiceCommand = string | null;
type VoiceCommandCallback = (command: VoiceCommand, transcript: string) => void;
type SpeechCallback = (transcript: string) => void;

function normalizeText(text: string): string {
  return text.toLowerCase().trim().replace(/[^a-z\s]/g, "");
}

// Declaraciones de tipos para Web Speech API
declare class SpeechRecognition extends EventTarget {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((event: SpeechRecognitionEvent) => void) | null;
  onerror: ((event: SpeechRecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
  onstart: (() => void) | null;
  onaudiostart: (() => void) | null;
  onsoundstart: (() => void) | null;
  onspeechstart: (() => void) | null;
  start(): void;
  stop(): void;
}

declare interface SpeechRecognitionEvent extends Event {
  resultIndex: number;
  results: SpeechRecognitionResultList;
}

declare interface SpeechRecognitionErrorEvent extends Event {
  error: string;
}

export class VoiceRecognizer {
  private recognition: SpeechRecognition | null = null;
  private isListening = false;
  private callbacks: VoiceCommandCallback[] = [];
  private speechCallbacks: SpeechCallback[] = [];
  private statusCallbacks: Array<(active: boolean, transcript: string) => void> = [];
  private available = false;
  private restartTimeout: ReturnType<typeof setTimeout> | null = null;
  private allowedPowers: string[] = [];

  constructor() {
    const SpeechRecognitionAPI =
      (window as any).SpeechRecognition ||
      (window as any).webkitSpeechRecognition;

    if (!SpeechRecognitionAPI) {
      console.warn("[VoiceRecognizer] Web Speech API no disponible en este navegador.");
      return;
    }

    this.available = true;
    const rec = new SpeechRecognitionAPI() as SpeechRecognition;
    this.recognition = rec;
    rec.continuous = true;
    rec.interimResults = true;
    rec.lang = "es-ES";
    
    rec.onstart = () => console.log("[VoiceRecognizer] Recognition started (onstart)");
    rec.onaudiostart = () => console.log("[VoiceRecognizer] Audio capture started");
    rec.onsoundstart = () => console.log("[VoiceRecognizer] Sound detected");
    rec.onspeechstart = () => console.log("[VoiceRecognizer] Speech detected (onspeechstart)");
    rec.onend = () => {
      console.log("[VoiceRecognizer] Recognition ended (onend)");
      if (this.isListening) {
        console.log("[VoiceRecognizer] Restarting recognition...");
        this.restartTimeout = setTimeout(() => {
          try {
            this.recognition?.start();
          } catch (_) {}
        }, 300);
      }
    };

    rec.onresult = (event: SpeechRecognitionEvent) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        const transcript = result[0].transcript;
        const normalizedTranscript = normalizeText(transcript);
        
        console.log(`[VoiceRecognizer] Result: "${transcript}" (isFinal: ${result.isFinal})`);
        
        let matchedCommand: string | null = null;

        // Búsqueda dinámica en powers.json filtrando por allowedPowers
        const powersDict = powersConfig as Record<string, any>;
        for (const key of this.allowedPowers) {
          const details = powersDict[key];
          if (!details) continue;
          
          const prompts = details.voice_prompts as string[];
          if (!prompts) continue;

          if (prompts.some(p => normalizedTranscript.includes(normalizeText(p)))) {
             matchedCommand = key;
             break;
          }
        }

        if (matchedCommand) {
          this.notifyCommand(matchedCommand, transcript);
        }

        this.notifySpeech(transcript);
        this.statusCallbacks.forEach((cb) => cb(true, transcript));
      }
    };

    // Inicializar con Goku base
    this.setAllowedPowers(gokuConfig.transformations?.[0]?.powers || []);

    rec.onerror = (event: SpeechRecognitionErrorEvent) => {
      if (event.error === "no-speech") return;
      console.error("[VoiceRecognizer] Speech Recognition Error:", event.error);
    };

    // rec.onend is now handled above for consistency
  }

  isAvailable(): boolean {
    return this.available;
  }

  /**
   * Actualiza los poderes permitidos para el reconocimiento de voz.
   */
  public setAllowedPowers(powers: string[]): void {
    this.allowedPowers = powers;
    console.log(`[VoiceRecognizer] Escuchando comandos para: ${powers.join(", ")}`);
  }

  start(): void {
    if (!this.available || this.isListening) return;
    this.isListening = true;
    console.log("[VoiceRecognizer] Starting recognition (continuous: true)...");
    try {
      this.recognition?.start();
    } catch (e) {
      console.error("[VoiceRecognizer] Error starting recognition:", e);
    }
  }

  stop(): void {
    this.isListening = false;
    if (this.restartTimeout) {
      clearTimeout(this.restartTimeout);
      this.restartTimeout = null;
    }
    try {
      this.recognition?.stop();
    } catch (_) {}
  }

  onCommand(callback: VoiceCommandCallback): void {
    this.callbacks.push(callback);
  }

  onStatus(callback: (active: boolean, transcript: string) => void): void {
    this.statusCallbacks.push(callback);
  }

  onSpeech(callback: SpeechCallback): void {
    this.speechCallbacks.push(callback);
  }

  private notifySpeech(transcript: string): void {
    this.speechCallbacks.forEach((cb) => cb(transcript));
  }

  private notifyCommand(command: VoiceCommand, transcript: string): void {
    this.callbacks.forEach((cb) => cb(command, transcript));
  }

  dispose(): void {
    this.stop();
    this.callbacks = [];
    this.statusCallbacks = [];
  }
}
