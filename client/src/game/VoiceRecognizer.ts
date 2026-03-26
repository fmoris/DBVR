// VoiceRecognizer.ts
// Reconocimiento de voz usando Web Speech API para activar ataques especiales
// Comandos: "kamehameha" -> activa Kamehameha, "final flash" -> activa Final Flash

export type VoiceCommand = "kamehameha" | "finalFlash" | null;

type VoiceCommandCallback = (command: VoiceCommand, transcript: string) => void;

// Variantes de los comandos para mayor tolerancia
const KAMEHAMEHA_VARIANTS = [
  "kamehameha", "kame hame ha", "kame-hame-ha", "kamejameha",
  "camehameja", "camehamea", "kamejameja",
];

const FINAL_FLASH_VARIANTS = [
  "final flash", "final flas", "final flas", "final flasch",
  "final flas", "fainaru furashhu", "final flash",
];

function normalizeText(text: string): string {
  return text.toLowerCase().trim().replace(/[^a-z\s]/g, "");
}

function matchesKamehameha(text: string): boolean {
  const normalized = normalizeText(text);
  return KAMEHAMEHA_VARIANTS.some((v) => normalized.includes(v));
}

function matchesFinalFlash(text: string): boolean {
  const normalized = normalizeText(text);
  return FINAL_FLASH_VARIANTS.some((v) => normalized.includes(v));
}

// Declaraciones de tipos para Web Speech API (no siempre incluidas en lib.dom.d.ts)
declare class SpeechRecognition extends EventTarget {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((event: SpeechRecognitionEvent) => void) | null;
  onerror: ((event: SpeechRecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
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
  private statusCallbacks: Array<(active: boolean, transcript: string) => void> = [];
  private available = false;
  private restartTimeout: ReturnType<typeof setTimeout> | null = null;

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
    rec.lang = "es-ES"; // Espanol como idioma principal

    rec.onresult = (event: SpeechRecognitionEvent) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        const transcript = result[0].transcript;

        if (matchesKamehameha(transcript)) {
          this.notifyCommand("kamehameha", transcript);
        } else if (matchesFinalFlash(transcript)) {
          this.notifyCommand("finalFlash", transcript);
        }

        // Notificar el texto reconocido para el HUD
        this.statusCallbacks.forEach((cb) => cb(true, transcript));
      }
    };

    rec.onerror = (event: SpeechRecognitionErrorEvent) => {
      // Ignorar errores de no-speech (silencio normal)
      if (event.error === "no-speech") return;
      console.warn("[VoiceRecognizer] Error:", event.error);
    };

    rec.onend = () => {
      // Reiniciar automaticamente si sigue activo
      if (this.isListening) {
        this.restartTimeout = setTimeout(() => {
          try {
            this.recognition?.start();
          } catch (_) {
            // Ignorar si ya esta corriendo
          }
        }, 300);
      }
    };
  }

  isAvailable(): boolean {
    return this.available;
  }

  start(): void {
    if (!this.available || this.isListening) return;
    this.isListening = true;
    try {
      this.recognition?.start();
    } catch (_) {
      // Puede lanzar si ya esta activo
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

  private notifyCommand(command: VoiceCommand, transcript: string): void {
    this.callbacks.forEach((cb) => cb(command, transcript));
  }

  dispose(): void {
    this.stop();
    this.callbacks = [];
    this.statusCallbacks = [];
  }
}
