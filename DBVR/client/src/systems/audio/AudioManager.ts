import { Scene, Sound, Engine } from "@babylonjs/core";
// @ts-ignore
import auraUrl from "../../assets/sfx/aura_loop.mp3?url";

export class AudioManager {
    private auraSound: Sound | null = null;
    private targetVolume: number = 0;
    private currentVolume: number = 0;
    private lerpSpeed: number = 0.05; // Más suave aún para evitar clics de audio
    private isUnlocked: boolean = false;

    constructor(private scene: Scene) {
        this.init();
        this.setupUnlockListeners();
    }

    private init(): void {
        console.log("[AudioManager] 🔊 Cargando Aura loop:", auraUrl);
        this.auraSound = new Sound(
            "aura_loop",
            auraUrl,
            this.scene,
            () => {
                console.log("[AudioManager] ✅ Aura loop decodificado y listo.");
                // Intentar reproducir de inmediato si ya hubo interacción
                if (this.auraSound && Engine.audioEngine && Engine.audioEngine.unlocked) {
                    this.auraSound.play();
                }
            },
            {
                loop: true,
                autoplay: false,
                volume: 0,
                streaming: false // Cargamos en memoria (33KB) para evitar cortes de red
            }
        );

        this.scene.onBeforeRenderObservable.add(() => {
            this.updateVolumes();
        });
    }

    private setupUnlockListeners(): void {
        const unlock = () => {
            if (this.isUnlocked) return;
            this.unlock();
            window.removeEventListener("click", unlock);
            window.removeEventListener("touchstart", unlock);
        };
        window.addEventListener("click", unlock);
        window.addEventListener("touchstart", unlock);
    }

    /**
     * Fuerza el desbloqueo del motor de audio (necesario tras clic de usuario)
     */
    public unlock(): void {
        if (this.isUnlocked) return;
        
        console.log("[AudioManager] 🔓 Intentando desbloquear AudioEngine...");
        if (Engine.audioEngine) {
            Engine.audioEngine.unlock();
            this.isUnlocked = true;
            this.playAura();
        }
    }

    public setPlayerAuraVolume(ratio: number): void {
        // Mapeamos el ratio a un volumen audible. 
        this.targetVolume = Math.max(0, Math.min(0.7, ratio));
    }

    private updateVolumes(): void {
        if (!this.auraSound || !this.auraSound.isReady()) return;

        if (Math.abs(this.currentVolume - this.targetVolume) > 0.001) {
            this.currentVolume += (this.targetVolume - this.currentVolume) * this.lerpSpeed;
            this.auraSound.setVolume(this.currentVolume);
        }
    }

    public playAura(): void {
        if (this.auraSound && !this.auraSound.isPlaying && this.auraSound.isReady()) {
            this.auraSound.play();
        }
    }

    public stopAura(): void {
        if (this.auraSound && this.auraSound.isPlaying) {
            this.auraSound.stop();
        }
    }

    public dispose(): void {
        if (this.auraSound) {
            this.auraSound.dispose();
            this.auraSound = null;
        }
    }
}
