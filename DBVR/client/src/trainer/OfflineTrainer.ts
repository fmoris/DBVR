import * as tf from '@tensorflow/tfjs';
import * as poseDetection from '@tensorflow-models/pose-detection';
import * as knnClassifier from '@tensorflow-models/knn-classifier';

import powersConfig from '../models/powers.json';

const imagesGlob = import.meta.glob('../models/imagesTraining/**/*.{png,jpg,jpeg}', { eager: true, query: '?url', import: 'default' });

class OfflineTrainer {
    private logEl: HTMLElement;
    private canvas: HTMLCanvasElement;
    private ctx: CanvasRenderingContext2D;
    private startBtn: HTMLButtonElement;
    private downloadBtn: HTMLButtonElement;
    private classifier: knnClassifier.KNNClassifier;
    private datasetRecord: Record<string, number[][]> = {};

    constructor() {
        this.logEl = document.getElementById('log-container')!;
        this.canvas = document.getElementById('offscreen-canvas') as HTMLCanvasElement;
        this.ctx = this.canvas.getContext('2d')!;
        this.startBtn = document.getElementById('start-btn') as HTMLButtonElement;
        this.downloadBtn = document.getElementById('download-btn') as HTMLButtonElement;

        this.classifier = knnClassifier.create();

        this.startBtn.addEventListener('click', () => this.startTraining());
        this.downloadBtn.addEventListener('click', () => this.downloadModel());
    }

    private log(msg: string) {
        console.log(msg);
        this.logEl.innerHTML += `<div>${msg}</div>`;
        this.logEl.scrollTop = this.logEl.scrollHeight;
    }

    private getLabelForImage(powerId: string, phaseName: string): string | null {
        const pId = powerId.toLowerCase();
        const cfg = (powersConfig as any)[pId];
        if (!cfg) return null;

        // mapping 'charge' -> 'preparation', 'firing' -> 'firing'
        const internalPhase = phaseName.toLowerCase() === 'charge' ? 'preparation' : 'firing';

        if (pId === "kamehameha") {
            return internalPhase === "preparation" ? "kamehameha_preparation" : "kamehameha_firing";
        } else if (pId === "genkidama") {
            return internalPhase === "preparation" ? "genkidama_preparation" : "genkidama_firing";
        } else {
            return cfg.vr_gestures ? cfg.vr_gestures[internalPhase] : `${pId}_${internalPhase}`;
        }
    }

    private extractVRFeaturesFromPose(pose: poseDetection.Pose): Float32Array | null {
        // Find wrists and nose (head)
        const leftWrist = pose.keypoints.find(k => k.name === 'left_wrist');
        const rightWrist = pose.keypoints.find(k => k.name === 'right_wrist');
        const nose = pose.keypoints.find(k => k.name === 'nose');

        if (!leftWrist || !rightWrist || !nose) return null;
        if (leftWrist.score && leftWrist.score < 0.5) return null;
        if (rightWrist.score && rightWrist.score < 0.5) return null;

        // Use 3D coordinates if available (BlazePose returns x, y, z)
        // Note: Pose detection keypoints 3D z is scaled relative to the image size and hips distance
        // We will just use the available x,y,z relative mathematics:
        
        let lx = leftWrist.x; let ly = leftWrist.y; let lz = leftWrist.z || 0.0;
        let rx = rightWrist.x; let ry = rightWrist.y; let rz = rightWrist.z || 0.0;
        let hy = (nose as any).y;

        // The math expects coordinates roughly in meters (like in BabylonJS).
        // For images, we can normalize using the shoulder width or just let KNN handle the scale invariant feature representation.
        // Actually, GestureSkillSystem normalized lH and rH relative to head.
        // We calculate midpoint of both wrists.
        const midX = (lx + rx) / 2;
        const midY = (ly + ry) / 2;
        const midZ = (lz + rz) / 2;

        const lRelX = lx - midX; const lRelY = ly - midY; const lRelZ = lz - midZ;
        const rRelX = rx - midX; const rRelY = ry - midY; const rRelZ = rz - midZ;

        const dist = Math.sqrt(Math.pow(lx - rx, 2) + Math.pow(ly - ry, 2) + Math.pow(lz - rz, 2));
        
        // Babylon Y is UP, image Y is DOWN. 
        const lH = -(ly - hy); 
        const rH = -(ry - hy);

        // Velocities and directions are 0 because it's a still image
        const lV = 0, rV = 0;
        const lDirX = lRelX / (dist/2 || 1), lDirY = -lRelY / (dist/2 || 1), lDirZ = lRelZ / (dist/2 || 1);
        const rDirX = rRelX / (dist/2 || 1), rDirY = -rRelY / (dist/2 || 1);

        // Final 16 features: [lRel.x, lRel.y, lRel.z, rRel.x, rRel.y, rRel.z, dist, lH, rH, lV, rV, lDir.x, lDir.y, lDir.z, rDir.x, rDir.y]
        // Normalize distances for the image context 
        const maxScale = Math.max(Math.abs(dist), Math.abs(lH), Math.abs(rH), 1);

        return new Float32Array([
            lRelX / maxScale, -lRelY / maxScale, lRelZ / maxScale,
            rRelX / maxScale, -rRelY / maxScale, rRelZ / maxScale,
            dist / maxScale,
            lH / maxScale, 
            rH / maxScale,
            lV, rV,
            lDirX, lDirY, lDirZ,
            rDirX, rDirY
        ]);
    }

    private drawPose(pose: poseDetection.Pose) {
        this.ctx.fillStyle = '#00ff88';
        this.ctx.strokeStyle = '#00ccff';
        this.ctx.lineWidth = 4;

        // Helper to find and draw connections
        const findKP = (name: string) => pose.keypoints.find(k => k.name === name && k.score && k.score > 0.3);
        const lWrist = findKP('left_wrist'); const lElbow = findKP('left_elbow'); const lShoulder = findKP('left_shoulder');
        const rWrist = findKP('right_wrist'); const rElbow = findKP('right_elbow'); const rShoulder = findKP('right_shoulder');
        const nose = findKP('nose');
        
        const drawLine = (p1: any, p2: any) => {
            if (p1 && p2) {
                this.ctx.beginPath(); this.ctx.moveTo(p1.x, p1.y); this.ctx.lineTo(p2.x, p2.y); this.ctx.stroke();
            }
        };

        drawLine(lWrist, lElbow); drawLine(lElbow, lShoulder);
        drawLine(rWrist, rElbow); drawLine(rElbow, rShoulder);
        drawLine(lShoulder, nose); drawLine(rShoulder, nose);

        // Draw points
        for (const kp of pose.keypoints) {
            if (kp.score && kp.score > 0.3) {
                this.ctx.beginPath();
                this.ctx.arc(kp.x, kp.y, 6, 0, 2 * Math.PI);
                this.ctx.fill();
            }
        }
    }

    private async loadImage(src: string): Promise<HTMLImageElement> {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.crossOrigin = "anonymous";
            img.onload = () => resolve(img);
            img.onerror = reject;
            img.src = src;
        });
    }

    private async startTraining() {
        this.startBtn.disabled = true;
        this.log("Iniciando motor TensorFlow...");

        await tf.setBackend('webgl');
        await tf.ready();

        this.log("Cargando modelo corporales BlazePose 3D...");
        const detectorConfig = {
            runtime: 'tfjs',
            modelType: 'full'
        };
        const detector = await poseDetection.createDetector(poseDetection.SupportedModels.BlazePose, detectorConfig as any);

        this.log("Modelo cargado. Procesando imágenes...");

        let totalProcessed = 0;
        let successCount = 0;

        for (const [path, url] of Object.entries(imagesGlob)) {
            // Path format expected: ../models/imagesTraining/Kamehameha/charge/image.jpg
            const parts = path.split('/');
            const powerName = parts[parts.length - 3];
            const phaseName = parts[parts.length - 2];

            const label = this.getLabelForImage(powerName, phaseName);
            if (!label) {
                this.log(`⚠️ Ignorando imagen: ruta no coincide con poderes - ${path}`);
                continue;
            }

            try {
                const img = await this.loadImage(url as string);
                
                // Set canvas size and draw
                this.canvas.width = img.width;
                this.canvas.height = img.height;
                this.ctx.drawImage(img, 0, 0);

                const poses = await detector.estimatePoses(this.canvas, { maxPoses: 1, flipHorizontal: false });
                
                if (poses.length > 0) {
                    this.drawPose(poses[0]);
                    
                    // Esperar 400ms para mostrar la imagen con el esqueleto dibujado en pantalla
                    await new Promise(resolve => setTimeout(resolve, 400));

                    const features = this.extractVRFeaturesFromPose(poses[0]);
                    if (features) {
                        const tensor = tf.tensor1d(features);
                        this.classifier.addExample(tensor, label);
                        
                        if (!this.datasetRecord[label]) this.datasetRecord[label] = [];
                        this.datasetRecord[label].push(Array.from(features));

                        tensor.dispose();
                        successCount++;
                        this.log(`✅ Procesado: ${powerName}/${phaseName} -> Etiqueta [${label}]`);
                    } else {
                        this.log(`❌ Skippeado: Manos o cabeza no visibles claramente en ${path}`);
                    }
                } else {
                    this.log(`❌ No se detectaron cuerpos en ${path}`);
                }

            } catch (err) {
                this.log(`🔥 Error procesando ${path}: ${err}`);
            }
            totalProcessed++;
        }

        this.log(`🎉 Finalizado. ${successCount}/${totalProcessed} procesadas exitosamente.`);
        if (successCount > 0) {
            this.downloadBtn.disabled = false;
        }
    }

    private downloadModel() {
        // Envolver los arrays 2D para cumplir con la sintaxis de "Sesiones 3D" esperada por GSS
        const gameFormat: Record<string, number[][][]> = {};
        for(const [label, data] of Object.entries(this.datasetRecord)) {
            gameFormat[label] = [data]; // Una sola mega-sesión con todos los frames/imágenes
        }

        const blob = new Blob([JSON.stringify(gameFormat)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'goku_pretrained.json';
        a.click();
        URL.revokeObjectURL(url);
        this.log("📥 Archivo goku_pretrained.json descargado.");
        this.log("Mueve este archivo a client/src/models/goku_pretrained.json y añádelo en goku.json en 'defaultData' o inyéctalo en el LocalStorage.");
    }
}

// Iniciar
window.addEventListener('DOMContentLoaded', () => {
    new OfflineTrainer();
});
