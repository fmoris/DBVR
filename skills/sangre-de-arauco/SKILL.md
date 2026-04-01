---
metadata.clawdbot:
  name: sangre-de-arauco
  description: Experto en el proyecto Sangre de Arauco - juego de mesa educativo sobre la Guerra de Arauco. Usa para preguntas sobre: reglas del juego, mecánicas, contexto histórico, diseño, desarrollo del prototipo, testeo, y cualquier aspecto del proyecto Sangre de Arauco.
  version: 0.2.0
  author: Bites
  requires:
    env: ["PYTHONIOENCODING=utf-8"]
---

# Sangre de Arauco - Experto

Skill especializada en el proyecto "Sangre de Arauco", un juego de mesa educativo sobre la Guerra de Arauco entre la Corona Española y el pueblo Mapuche.

## Uso

Cuando el usuario pregunte sobre el proyecto Sangre de Arauco, usar esta skill.

## Cómo funciona el aprendizaje

**Carpeta de conocimiento:**
```
D:\openclaw\workspace\Documentos\Sangre de Arauco\
```

**Archivos actuales:**
- `texto.txt` - Documento principal del proyecto (12,988 caracteres)
- `sangre-de-arauco-completo.txt` - Versión combinada

**Para agregar nuevo conocimiento:**
1. Agregar archivos .txt a la carpeta
2. La próxima pregunta incluirá automáticamente el nuevo contenido

## Cómo responder preguntas

1. Leer todos los archivos .txt en la carpeta de conocimiento
2. Buscar la información relevante
3. Responder basado en el contenido

**No usar aura.compiler** - tiene bugs con Python 3.14. Leer archivos directamente.

## Scripts

- `compile.py` - Compila archivos a formato compatible (o texto combinado)

## Notas

- Esta skill SOLO debe usarse para Sangre de Arauco
- No mezclar con otros proyectos
- El contenido se lee directamente de archivos .txt - no necesita .aura