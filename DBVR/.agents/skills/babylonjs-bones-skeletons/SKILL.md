---
name: babylonjs-bones-skeletons
description: >
  Experto en Babylon.js bones y skeletons. Usa este skill SIEMPRE que el usuario
  mencione bones, skeletons, animaciones de esqueleto, IK (Inverse Kinematics),
  BoneLookController, BoneIKController, SkeletonViewer, skinning, vertex weights,
  attachToBone, animación de personajes, rigging, o cualquier consulta sobre
  BABYLON.Skeleton o BABYLON.Bone. Trigger inmediato si el usuario pregunta cómo
  cargar modelos animados, clonar esqueletos, crear rangos de animación, depurar
  huesos, o manejar transformaciones de bones en Babylon.js. Proporciona código
  JavaScript listo para Babylon.js Playground con ejemplos mínimos y optimizaciones.
---

# Babylon.js Bones & Skeletons — Skill

Eres un experto en el sistema de huesos y esqueletos de Babylon.js. Responde con
código JS listo para el Playground, cita la documentación oficial, e incluye siempre
ejemplos mínimos funcionales. Ignora queries no relacionadas con bones/skeletons.

**Fuentes oficiales:**
- Guía principal: https://doc.babylonjs.com/features/featuresDeepDive/mesh/bonesSkeletons
- API Skeleton: https://doc.babylonjs.com/typedoc/classes/BABYLON.Skeleton
- API Bone: https://doc.babylonjs.com/typedoc/classes/BABYLON.Bone

---

## 1. Conceptos Fundamentales

| Concepto | Descripción |
|---|---|
| `BABYLON.Skeleton` | Contenedor de la jerarquía de bones |
| `BABYLON.Bone` | Nodo individual con nombre, padre y matriz de transformación |
| `mesh.skeleton` | Referencia al skeleton asignado al mesh |
| Vertex Weights | Hasta 4 influencias de bone por vértice |
| `MatricesWeightsKind` | Buffer de pesos por vértice |
| `MatricesIndicesKind` | Buffer de índices de bone por vértice |

**Fórmula de transformación por vértice:**
```
worldMatrix * Σ(bonesMatrices[index] * weight)
```

---

## 2. Creación Manual de Skeleton

```javascript
// Crear skeleton
const skeleton = new BABYLON.Skeleton("humanoid", "humanoid0", scene);

// Bone raíz (sin padre)
const rootBone = new BABYLON.Bone("root", skeleton, null, BABYLON.Matrix.Identity());

// Bone hijo
const spineBone = new BABYLON.Bone(
  "spine",
  skeleton,
  rootBone,
  BABYLON.Matrix.Translation(0, 1, 0)
);

// Asignar al mesh
mesh.skeleton = skeleton;

// Configurar vertex data
const weights = [1, 0, 0, 0,  /* vértice 0 */  0.5, 0.5, 0, 0  /* vértice 1 */];
const indices = [0, 0, 0, 0,  /* vértice 0 */  0,   1,   0, 0  /* vértice 1 */];

mesh.setVerticesData(BABYLON.VertexBuffer.MatricesWeightsKind, weights, false);
mesh.setVerticesData(BABYLON.VertexBuffer.MatricesIndicesKind, indices, false);

// Preparar matrices inversas
skeleton.returnToRest();
```

---

## 3. Carga desde Archivo

```javascript
BABYLON.SceneLoader.ImportMesh(
  "",
  "https://assets.babylonjs.com/meshes/",
  "HVGirl.glb",
  scene,
  (meshes, particleSystems, skeletons) => {
    const skeleton = skeletons[0];
    const mesh = meshes[0];

    // Iniciar animación
    scene.beginAnimation(skeleton, 0, 100, true, 1.0);
  }
);
```

---

## 4. Animación y Rangos

```javascript
// Crear rango
skeleton.createAnimationRange("walk", 0, 30);
skeleton.createAnimationRange("run",  31, 60);
skeleton.createAnimationRange("idle", 61, 90);

// Recuperar rango
const walkRange = skeleton.getAnimationRange("walk");

// Reproducir rango por nombre
const animatable = skeleton.beginAnimation("walk", true, 1.0);

// Control de velocidad en tiempo real
animatable.speedRatio = 2.0;

// Blending entre animaciones
skeleton.beginAnimation("run", true, 1.0, null, 0.05 /* blending speed */);
```

---

## 5. Manipulación de Bones

```javascript
const bone = skeleton.bones[2];

// Rotación
bone.rotate(BABYLON.Axis.Y, Math.PI / 4, BABYLON.Space.WORLD, mesh);
bone.setYawPitchRoll(yaw, pitch, roll, BABYLON.Space.LOCAL, mesh);

// Posición
bone.setPosition(new BABYLON.Vector3(0, 2, 0), BABYLON.Space.WORLD, mesh);

// Escala (con hijos opcionales)
bone.scale(1.5, 1.5, 1.5, true);
bone.setScale(new BABYLON.Vector3(2, 1, 1));

// Adjuntar mesh a bone (ej: espada a mano)
sword.attachToBone(skeleton.bones[handIndex], characterMesh);
```

---

## 6. Clonación de Skeleton

```javascript
// Para múltiples personajes con el mismo rig
const clone1 = originalMesh.clone("character2");
clone1.skeleton = originalSkeleton.clone("skeleton_clone1", "id_clone1");

// Copiar rangos de animación al clon
skeleton.copyAnimationRange(originalSkeleton, "walk", true /* rescaleAsRequired */);
```

---

## 7. Controladores (Look & IK)

### BoneLookController — bone mira hacia un target

```javascript
const target = new BABYLON.Mesh("target", scene);
const lookCtrl = new BABYLON.BoneLookController(mesh, headBone, target.position, {
  adjustYaw:   Math.PI / 2,
  adjustPitch: 0,
  adjustRoll:  0
});

scene.registerBeforeRender(() => {
  lookCtrl.update();
});
```

### BoneIKController — IK de 2 huesos (brazo/pierna)

```javascript
const targetMesh   = BABYLON.Mesh.CreateSphere("ikTarget",   4, 0.1, scene);
const poleMesh     = BABYLON.Mesh.CreateSphere("ikPole",     4, 0.1, scene);

const ikCtrl = new BABYLON.BoneIKController(mesh, tipBone, {
  targetMesh,
  poleTargetMesh: poleMesh,
  poleAngle:      Math.PI,
  maxAngle:       Math.PI * 0.9
});

scene.registerBeforeRender(() => {
  ikCtrl.update();
});
```

---

## 8. Rendimiento

| Opción | Descripción | Cuándo usar |
|---|---|---|
| `skeleton.useTextureToStoreBoneMatrices = true` | GPU (default) | Hardware moderno |
| `mesh.computeBonesUsingShaders = false` | CPU fallback | Dispositivos low-end |

```javascript
// GPU (recomendado, default)
skeleton.useTextureToStoreBoneMatrices = true;

// CPU (dispositivos débiles)
mesh.computeBonesUsingShaders = false;

// Número máximo de influencias (reduce si la geometría lo permite)
mesh.numBoneInfluencers = 2; // default 4; reducir mejora rendimiento
```

---

## 9. Debugging

```javascript
// Modo básico — muestra líneas de skeleton
const viewer = new BABYLON.Debug.SkeletonViewer(skeleton, mesh, scene, false, 3, {
  displayMode: BABYLON.Debug.SkeletonViewer.DISPLAY_LINES
});

// Modo esferas — más visual
viewer.changeDisplayMode(BABYLON.Debug.SkeletonViewer.DISPLAY_SPHERES);

// Shader de mapa de colores por bone
const shaderMaterial = BABYLON.Debug.SkeletonViewer.CreateSkeletonMapShader(
  { skeleton },
  scene
);
mesh.material = shaderMaterial;

// Deshabilitar viewer
viewer.isEnabled = false;
viewer.dispose();
```

También puedes usar el **Inspector** integrado:
```javascript
scene.debugLayer.show();
```

---

## 10. Referencia Rápida de Métodos

| Método | Descripción |
|---|---|
| `skeleton.returnToRest()` | Prepara la matriz inversa absoluta |
| `scene.beginAnimation(skeleton, from, to, loop, speed)` | Inicia animación en rango numérico |
| `skeleton.beginAnimation(name, loop, speed)` | Inicia animación por nombre de rango |
| `skeleton.clone(name, id)` | Clona el skeleton completo |
| `skeleton.copyAnimationRange(source, name, rescale)` | Copia rango desde otro skeleton |
| `skeleton.createAnimationRange(name, from, to)` | Define un rango nombrado |
| `skeleton.getAnimationRange(name)` | Recupera un rango definido |
| `bone.getWorldMatrix()` | Obtiene la matriz world del bone |
| `bone.getAbsolutePosition(mesh)` | Posición absoluta en world space |
| `bone.getRotation(space, mesh)` | Rotación actual del bone |

---

## 11. Fuentes Oficiales

| Tipo | Título | URL |
|---|---|---|
| Guía | Bones and Skeletons | https://doc.babylonjs.com/features/featuresDeepDive/mesh/bonesSkeletons |
| API | BABYLON.Skeleton Class | https://doc.babylonjs.com/typedoc/classes/BABYLON.Skeleton |
| API | BABYLON.Bone Class | https://doc.babylonjs.com/typedoc/classes/BABYLON.Bone |
| API | BoneLookController | https://doc.babylonjs.com/typedoc/classes/BABYLON.BoneLookController |
| API | BoneIKController | https://doc.babylonjs.com/typedoc/classes/BABYLON.BoneIKController |
| API | SkeletonViewer | https://doc.babylonjs.com/typedoc/classes/BABYLON.Debug.SkeletonViewer |

> Para detalles adicionales sobre animaciones avanzadas o blend trees, consulta:
> https://doc.babylonjs.com/features/featuresDeepDive/animation/animatedCharacter
