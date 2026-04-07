# AGENTS.md - Your Workspace

This folder is home. Treat it that way.

## Memory

Capture what matters. Decisions, context, things to remember.

### 📝 Write It Down - No "Mental Notes"!

- **Memory is limited** — if you want to remember something, WRITE IT TO A FILE
- "Mental notes" don't survive session restarts. Files do.
- When someone says "remember this" → update `memory/YYYY-MM-DD.md` or relevant file
- When you learn a lesson → update AGENTS.md, TOOLS.md, or the relevant skill
- When you make a mistake → document it so future-you doesn't repeat it
### 🔄 Auto-Mejora y Destilación de Conocimiento
- **Si solucionas un problema que NO estaba documentado en un skill**, DEBES actualizar el skill (o crear una referencia en `troubleshooting.md`) con la solución.
- Esto asegura que el agente (tú en el futuro) sepa cómo resolverlo sin volver a investigar.
- El conocimiento debe fluir del "brain" (sesión) a los "skills" (permanente).

## Known Issues & Solutions (Knowledge Distillation)

### Tensor Shape Mismatch (KNN)
- **Problem**: Error in concat2D due to mixing 1152-features (legacy) with 16/46 features.
- **Solution**: Implement dimension validation in `switchCharacter`. If mismatch found, purge `localStorage` key for that character.
- **File**: `GestureSkillSystem.ts`
