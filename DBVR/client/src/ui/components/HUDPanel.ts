import {
    Scene,
    Mesh,
    MeshBuilder,
    StandardMaterial,
    Vector3,
} from "@babylonjs/core";
import {
    AdvancedDynamicTexture,
    Rectangle,
    Control,
} from "@babylonjs/gui";

export interface PanelConfig {
    name: string;
    width: number;
    height: number;
    resolution: number;
}

export abstract class HUDPanel {
    protected mesh: Mesh;
    protected adt: AdvancedDynamicTexture;
    protected rootRect: Rectangle;

    constructor(protected scene: Scene, config: PanelConfig) {
        this.mesh = MeshBuilder.CreatePlane(config.name, {
            width: config.width,
            height: config.height,
            sideOrientation: Mesh.DOUBLESIDE,
        }, this.scene);
        this.mesh.isPickable = true;

        const mat = new StandardMaterial(config.name + "-mat", this.scene);
        mat.backFaceCulling = false;
        mat.disableLighting = true;
        this.mesh.material = mat;

        const texW = Math.round(config.width * config.resolution);
        const texH = Math.round(config.height * config.resolution);
        this.adt = AdvancedDynamicTexture.CreateForMesh(this.mesh, texW, texH);
        this.adt.background = "transparent";

        this.rootRect = new Rectangle(config.name + "-root");
        this.rootRect.width = "100%";
        this.rootRect.height = "100%";
        this.rootRect.thickness = 0;
        this.adt.addControl(this.rootRect);
    }

    public set parent(parent: Mesh | null) {
        this.mesh.parent = parent;
    }

    public get position(): Vector3 {
        return this.mesh.position;
    }

    public set position(value: Vector3) {
        this.mesh.position = value;
    }

    public get rotation(): Vector3 {
        return this.mesh.rotation;
    }

    public set rotation(value: Vector3) {
        this.mesh.rotation = value;
    }

    public setEnabled(enabled: boolean): void {
        this.mesh.setEnabled(enabled);
    }

    public dispose(): void {
        this.adt.dispose();
        this.mesh.dispose();
    }

    protected makePanelBg(bg: string, borderColor: string, cornerRadius: number = 16): Rectangle {
        const rect = new Rectangle("panel-bg");
        rect.width = "100%";
        rect.height = "100%";
        rect.cornerRadius = cornerRadius;
        rect.background = bg;
        rect.color = borderColor;
        rect.thickness = 2;
        
        // Efecto de borde brillante (Glassmorphism)
        rect.shadowBlur = 10;
        rect.shadowColor = borderColor;
        rect.shadowOffsetX = 0;
        rect.shadowOffsetY = 0;

        this.rootRect.addControl(rect);
        return rect;
    }

    protected addScanlines(parent: Rectangle): void {
        // En ADT no hay blur real de fondo, pero podemos simular scanlines con una imagen repetida
        // o un patrón de rectángulos muy finos.
        for (let i = 0; i < 100; i += 2) {
            const line = new Rectangle(`scanline-${i}`);
            line.width = "100%";
            line.heightInPixels = 1;
            line.top = `${i}%`;
            line.background = "rgba(255, 255, 255, 0.03)";
            line.thickness = 0;
            line.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
            parent.addControl(line);
        }
    }
}
