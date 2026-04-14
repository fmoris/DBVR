import { Scene, Mesh, MeshBuilder, Vector3, StandardMaterial, Color3, DynamicTexture } from "@babylonjs/core";
import { PoseReference } from "./PoseReferences";

export class CalibrationGhost {
    private leftHand: Mesh;
    private rightHand: Mesh;
    private label: Mesh;
    private texture: DynamicTexture;
    
    private leftMat: StandardMaterial;
    private rightMat: StandardMaterial;

    private readonly COLOR_WAITING = new Color3(0.1, 0.4, 1.0);
    private readonly COLOR_READY = new Color3(0.2, 1.0, 0.4);
    
    private leftLink: Mesh | null = null;
    private rightLink: Mesh | null = null;

    constructor(private scene: Scene) {
        // Left silhouette
        this.leftHand = MeshBuilder.CreateBox("ghost-left", { size: 0.08, height: 0.12, depth: 0.04 }, this.scene);
        this.leftMat = new StandardMaterial("ghost-left-mat", this.scene);
        this.leftMat.emissiveColor = this.COLOR_WAITING;
        this.leftMat.alpha = 0.4;
        this.leftHand.material = this.leftMat;
        this.leftHand.isVisible = false;
        this.leftHand.isPickable = true;
        this.leftHand.metadata = { side: 'left' };

        // Right silhouette
        this.rightHand = MeshBuilder.CreateBox("ghost-right", { size: 0.08, height: 0.12, depth: 0.04 }, this.scene);
        this.rightMat = new StandardMaterial("ghost-right-mat", this.scene);
        this.rightMat.emissiveColor = this.COLOR_WAITING;
        this.rightMat.alpha = 0.4;
        this.rightHand.material = this.rightMat;
        this.rightHand.isVisible = false;
        this.rightHand.isPickable = true;
        this.rightHand.metadata = { side: 'right' };

        // Label for status/countdown
        this.label = MeshBuilder.CreatePlane("ghost-label", { width: 0.5, height: 0.2 }, this.scene);
        this.texture = new DynamicTexture("ghost-label-tex", { width: 512, height: 256 }, this.scene);
        const mat = new StandardMaterial("ghost-label-mat", this.scene);
        mat.diffuseTexture = this.texture;
        mat.emissiveColor = Color3.White();
        mat.opacityTexture = this.texture;
        this.label.material = mat;
        this.label.isVisible = false;
        this.label.billboardMode = Mesh.BILLBOARDMODE_ALL;
    }

    public show(ref: PoseReference, text: string) {
        this.leftHand.position.copyFrom(ref.left);
        this.rightHand.position.copyFrom(ref.right);
        
        if (ref.leftRot) this.leftHand.rotationQuaternion = ref.leftRot;
        else this.leftHand.rotationQuaternion = null;

        if (ref.rightRot) this.rightHand.rotationQuaternion = ref.rightRot;
        else this.rightHand.rotationQuaternion = null;

        // Visuals for closed hands (Scaling down the box to look like a fist)
        this.leftHand.scaling.setAll(ref.leftClosed ? 0.7 : 1.0);
        this.rightHand.scaling.setAll(ref.rightClosed ? 0.7 : 1.0);

        this.leftHand.isVisible = true;
        this.rightHand.isVisible = true;

        const labelPos = ref.left.add(ref.right).scale(0.5);
        labelPos.y += 0.25;
        this.label.position.copyFrom(labelPos);
        this.label.isVisible = true;

        this.updateText(text);
    }

    public hide() {
        this.leftHand.isVisible = false;
        this.rightHand.isVisible = false;
        this.label.isVisible = false;
    }

    public updateVisuals(leftInPos: boolean, rightInPos: boolean) {
        this.leftMat.emissiveColor = leftInPos ? this.COLOR_READY : this.COLOR_WAITING;
        this.leftMat.alpha = leftInPos ? 0.7 : 0.4;
        this.rightMat.emissiveColor = rightInPos ? this.COLOR_READY : this.COLOR_WAITING;
        this.rightMat.alpha = rightInPos ? 0.7 : 0.4;
    }

    public setDragLink(side: 'left' | 'right', start: Vector3 | null, end: Vector3 | null) {
        // Limpiar linea anterior
        if (side === 'left' && this.leftLink) { this.leftLink.dispose(); this.leftLink = null; }
        if (side === 'right' && this.rightLink) { this.rightLink.dispose(); this.rightLink = null; }

        if (start && end) {
            const line = MeshBuilder.CreateLines(`drag-link-${side}`, {
                points: [start, end],
                updatable: false
            }, this.scene);
            line.color = Color3.White();
            
            if (side === 'left') this.leftLink = line;
            else this.rightLink = line;
        }
    }

    public updateText(text: string) {
        const ctx = this.texture.getContext() as CanvasRenderingContext2D;
        ctx.clearRect(0, 0, 512, 256);
        
        // Background with some transparency for readability
        ctx.fillStyle = "rgba(0,0,0,0.5)";
        ctx.fillRect(0, 0, 512, 256);

        ctx.font = "bold 60px Arial";
        ctx.fillStyle = "white";
        ctx.textAlign = "center" as CanvasTextAlign;
        ctx.textBaseline = "middle" as CanvasTextBaseline;
        ctx.fillText(text, 256, 128);
        
        this.texture.update();
    }

    public dispose() {
        this.leftHand.dispose();
        this.rightHand.dispose();
        this.label.dispose();
    }
}
