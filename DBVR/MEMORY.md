# Long-Term Memory (MEMORY.md)

This file contains curated long-term memories, decisions, context, and structural knowledge about the workspace and projects.

## Skills & Capabilities
- **babylonjs-bones-skeletons**: A specialized skill documenting rules and best practices for creating, loading, and animating bones/skeletons in Babylon.js. Used automatically whenever the user mentions anything related to bones, rigging, inverse kinematics (`BoneIKController`), look controllers (`BoneLookController`), or Babylon's `Skeleton`/`Bone` APIs. 

## Project: DBVR (Dragon Ball VR)
- **WebXR Combat System**: Developed a robust FSM-based VR combat system, including physical guardrails, gesture synchronization, and an immersive user interface.
- **IK Mirror Avatar**: Implemented a procedural mirror avatar to copy user hand movements. Initially attempted with several models, but standardized on **Mixamo Rigs** (using `passive_marker_man.glb`) with specific configuration: `bendAxis: (0,1,0)`, `poleAngle: PI/2`.
- **Modular Gesture System**: Migración completada a una arquitectura basada en movimientos individuales (`server/data/gestures/`). 
    - **SSOT (Source of Truth)**: El servidor es el único origen de datos. `localStorage` ha sido descartado y deshabilitado para evitar corrupción por datos obsoletos.
- **FSM & Extractor Optimization**: 
    - Estándar de 2 fases obligatorio (`prep` + `active/fire`).
    - **Regla de Extractores**: Usar `wristOnly` en estados de preparación (ahorro de CPU) y `wristAndFingertips` en estados activos/disparo (máxima precisión de seguimiento de dedos).
- **VFX Charge Sync**: Sincronización en tiempo real de los efectos de carga (`chargePosition`) usando el `XRHandsContext`. Los orbes deben seguir dinámicamente el punto medio entre manos (Kamehameha) o la mano disparadora (Ki Blast).
- **Consistencia de Etiquetas**: El mapeo de IDs de poder a etiquetas de gestos debe estar sincronizado en `CharacterConfigs.ts`, `PowersGuidePanel.ts` y `VRHud.ts`.
