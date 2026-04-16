import { Scene, Mesh, MeshBuilder, Vector3, Animation, StandardMaterial, Color3, EasingFunction, SineEase, AbstractMesh } from "@babylonjs/core";
import { POSE_REFERENCES } from "./PoseReferences";

export class GestureSimulator {
    private leftHand: AbstractMesh;
    private rightHand: AbstractMesh;
    public isAnimating: boolean = false;
    public customTargets: boolean = false;
    private targetRootPos?: Vector3;
    private targetRootRotY?: number;

    constructor(private scene: Scene) {
        // Create fallback left hand (blueish)
        this.leftHand = MeshBuilder.CreateBox("sim-left-hand", { size: 0.08, height: 0.12, depth: 0.04 }, this.scene);
        const lm = new StandardMaterial("left-mat", this.scene);
        lm.emissiveColor = new Color3(0.0, 0.5, 1.0);
        lm.alpha = 0.7;
        this.leftHand.material = lm;
        this.leftHand.isVisible = false;

        // Create fallback right hand (reddish)
        this.rightHand = MeshBuilder.CreateBox("sim-right-hand", { size: 0.08, height: 0.12, depth: 0.04 }, this.scene);
        const rm = new StandardMaterial("right-mat", this.scene);
        rm.emissiveColor = new Color3(1.0, 0.2, 0.2);
        rm.alpha = 0.7;
        this.rightHand.material = rm;
        this.rightHand.isVisible = false;
    }

    public setExternalTargets(targets: { left: AbstractMesh, right: AbstractMesh }, rootPos?: Vector3, rotY?: number) {
        this.leftHand.dispose();
        this.rightHand.dispose();
        this.leftHand = targets.left;
        this.rightHand = targets.right;
        this.customTargets = true;
        this.targetRootPos = rootPos;
        this.targetRootRotY = rotY;
    }

    private getPosePositions(pose: string): { left: Vector3, right: Vector3 } {
        // Altura base (hombros aprox) en coords LOCALES
        const chest = new Vector3(0, 1.4, 0); 
        const ref = POSE_REFERENCES[pose];

        if (ref) {
            return {
                left: chest.add(new Vector3(ref.left.x, ref.left.y, -ref.left.z)),
                right: chest.add(new Vector3(ref.right.x, ref.right.y, -ref.right.z))
            };
        }

        // Default fallback
        return {
            left: chest.add(new Vector3(-0.2, -0.2, 0)),
            right: chest.add(new Vector3(0.2, -0.2, 0))
        };
    }

    private playAnimation(mesh: AbstractMesh, startPath: Vector3, endPath: Vector3, callback?: () => void) {
        const anim = new Animation("sim-anim", "position", 60, Animation.ANIMATIONTYPE_VECTOR3, Animation.ANIMATIONLOOPMODE_CONSTANT);
        const keys = [
            { frame: 0, value: startPath },
            { frame: 60, value: endPath },
            { frame: 120, value: endPath } // Hold
        ];
        anim.setKeys(keys);

        const easingFunc = new SineEase();
        easingFunc.setEasingMode(EasingFunction.EASINGMODE_EASEINOUT);
        anim.setEasingFunction(easingFunc);

        mesh.animations = [anim];
        this.scene.beginAnimation(mesh, 0, 120, false, 1.0, callback);
    }

    public playGestureSequence(prepLabel: string, fireLabel: string, basePosition: Vector3, baseRotationAngles?: { y: number }) {
        console.log(`[GestureSimulator] Starting sequence: ${prepLabel} -> ${fireLabel}`);
        if (this.isAnimating) {
            console.warn("[GestureSimulator] Already animating, ignoring request.");
            return;
        }
        this.isAnimating = true;

        if (!this.customTargets) {
            this.leftHand.isVisible = true;
            this.rightHand.isVisible = true;
        }

        const cleanPrep = prepLabel.replace("dbvr_", "").replace("canon_", "").toLowerCase();
        const cleanFire = fireLabel.replace("dbvr_", "").replace("canon_", "").toLowerCase();

        const prepPos = this.getPosePositions(cleanPrep);
        const firePos = this.getPosePositions(cleanFire);

        let globalPrepL = prepPos.left;
        let globalPrepR = prepPos.right;
        let globalFireL = firePos.left;
        let globalFireR = firePos.right;

        const useBasePos = this.customTargets && this.targetRootPos ? this.targetRootPos : basePosition;
        const rotY = this.customTargets && this.targetRootRotY !== undefined ? this.targetRootRotY : (baseRotationAngles ? baseRotationAngles.y : 0);
        
        const transformPos = (v: Vector3) => {
            const rotated = new Vector3(
                v.x * Math.cos(rotY) - v.z * Math.sin(rotY),
                v.y,
                v.x * Math.sin(rotY) + v.z * Math.cos(rotY)
            );
            return rotated.add(useBasePos);
        };

        globalPrepL = transformPos(prepPos.left);
        globalPrepR = transformPos(prepPos.right);
        globalFireL = transformPos(firePos.left);
        globalFireR = transformPos(firePos.right);

        this.leftHand.position = globalPrepL;
        this.rightHand.position = globalPrepR;

        setTimeout(() => {
            if (!this.isAnimating) return;
            
            let animationsFinished = 0;
            const onEnd = () => {
                animationsFinished++;
                if (animationsFinished >= 2) {
                    setTimeout(() => {
                        if (!this.customTargets) {
                            this.leftHand.isVisible = false;
                            this.rightHand.isVisible = false;
                        }
                        this.isAnimating = false;
                    }, 1000);
                }
            };

            this.playAnimation(this.leftHand, globalPrepL, globalFireL, onEnd);
            this.playAnimation(this.rightHand, globalPrepR, globalFireR, onEnd);

        }, 1000);
    }

    public stop() {
        this.isAnimating = false;
        if (!this.customTargets) {
            this.leftHand.isVisible = false;
            this.rightHand.isVisible = false;
        }
        this.scene.stopAnimation(this.leftHand);
        this.scene.stopAnimation(this.rightHand);
    }

    public dispose() {
        this.stop();
        if (!this.customTargets) {
            this.leftHand.dispose();
            this.rightHand.dispose();
        }
    }
}
