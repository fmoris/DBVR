import { Scene, Sound } from "@babylonjs/core";
// @ts-ignore
import auraUrl from "../../assets/sfx/Aura loop.mp3?url";

export class AudioManager {
    private auraSound: Sound | null = null;
    private targetVolume: number = 0;
    private currentVolume: number = 0;
    private lerpSpeed: number = 0.1; // Suavizado para el volumen

    constructor(private scene: Scene) {
        this.init();
    }

    private init(): void {
        console.log("[AudioManager] Cargando Aura loop:", auraUrl);
        this.auraSound = new Sound(
            "aura_loop",
            auraUrl,
            this.scene,
            () => {
                console.log("[AudioManager] Aura loop cargado y listo.");
                if (this.auraSound) {
                    this.auraSound.play();
                }
            },
            {
                loop: true,
                autoplay: false,
                volume: 0,
                streaming: true
            }
        );

        // Actualizar volumen suavemente en cada frame
        this.scene.onBeforeRenderObservable.add(() => {
            this.updateVolumes();
        });
    }

    /**
     * Actualiza el volumen objetivo basado en el ratio de Ki (0.0 a 1.0)
     */
    public setPlayerAuraVolume(ratio: number): void {
        // Mapeamos el ratio a un volumen audible. 
        // 0% Ki = 0 vol, 100% Ki = 0.8 vol (para no saturar)
        this.targetVolume = Math.max(0, Math.min(0.8, ratio));
    }

    private updateVolumes(): void {
        if (!this.auraSound) return;

        // Interpolación lineal simple para que el cambio de volumen no sea brusco
        if (Math.abs(this.currentVolume - this.targetVolume) > 0.001) {
            this.currentVolume += (this.targetVolume - this.currentVolume) * this.lerpSpeed;
            this.auraSound.setVolume(this.currentVolume);
        }
    }

    public playAura(): void {
        if (this.auraSound && !this.auraSound.isPlaying) {
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
