---
name: board-game-manual
description: "Generación de manuales de juegos de mesa en formato .md y .docx. Usar cuando el usuario pida crear, redactar o generar un manual/rulebook para un juego de mesa, dado: nombre del juego, público objetivo, rango etario y tipo de juego. Si falta información, ofrecer dos opciones: generar el manual con títulos en blanco o hacer preguntas para completarlo."
---

# Board Game Manual

Genera manuales profesionales de juegos de mesa en Markdown y Word (.docx), siguiendo las mejores prácticas de la industria.

## Flujo de Trabajo

El flujo depende de cuánta información provee el usuario:

**¿El usuario proveyó toda la información necesaria?**
→ Generar el manual directamente (Flujo A)

**¿Falta información?**
→ Ofrecer dos opciones al usuario (Flujo B)

---

## Flujo A: Generación Directa

Cuando el usuario provee: nombre del juego, público objetivo, rango etario y tipo de juego.

1. Construir el `game_data.json` con la información disponible (ver esquema en `references/game_data_schema.md`)
2. Guardar el JSON en el directorio de trabajo
3. Ejecutar el generador:
   ```bash
   python scripts\generate_manual.py game_data.json --output-dir output --format both
   ```
   
   O en Mac/Linux:
   ```bash
   python scripts/generate_manual.py game_data.json --output-dir ./output --format both
   ```
4. Entregar ambos archivos al usuario (.md y .docx)

---

## Flujo B: Información Incompleta

Cuando falte información para completar el manual, ofrecer estas dos opciones al usuario:

**Opción 1 — Generar con campos pendientes:**
Generar el manual inmediatamente. Los campos faltantes aparecerán como texto en cursiva gris con la etiqueta `[pendiente de completar]`. El usuario puede editar el .docx para completarlos.

**Opción 2 — Completar mediante preguntas:**
Hacer preguntas una sección a la vez para recopilar la información. Seguir el orden de secciones del manual (ver estructura abajo). No hacer más de 3 preguntas por mensaje.

---

## Campos Mínimos Requeridos

| Campo | Descripción |
|---|---|
| `NOMBRE_DEL_JUEGO` | Nombre completo del juego |
| `MIN_JUGADORES` / `MAX_JUGADORES` | Rango de jugadores |
| `OBJETIVO_DEL_JUEGO` | Condición de victoria en una oración |

Todos los demás campos son opcionales: si no se proveen, el manual los marca como pendientes.

---

## Estructura del Manual

El template sigue esta estructura estándar de la industria:

1. **Introducción temática** — Contexto narrativo + objetivo del juego (siempre visible)
2. **Componentes** — Tabla completa de elementos de la caja
3. **Preparación** — Pasos numerados de setup + selección del primer jugador
4. **Cómo leer los componentes** — Iconos, símbolos, estructura de cartas
5. **Turno de juego** — Resumen de acciones + detalle de cada una (H3)
6. **Acciones especiales** — Condiciones fuera del turno normal
7. **Fin de ronda** — Pasos de limpieza (omitir si no hay rondas)
8. **Fin del juego** — Condición disparadora + pasos de cierre
9. **Puntuación** — Cálculo + desempate
10. **Apéndice** — Casos especiales, glosario, FAQ

---

## Adaptación por Tipo de Juego y Rango Etario

Ajustar el tono y la extensión según el contexto:

| Tipo | Introducción | Apéndice | Tono |
|---|---|---|---|
| Temático / narrativo | Narrativa inmersiva | Moderado | Puede incluir sabor |
| Abstracto / estratégico | Breve y funcional | Mínimo | Neutro y preciso |
| Familiar / infantil | Simple y visual | Muy reducido | Amigable |
| Experto / heavy | Detallada | Extenso | Técnico y completo |

| Edad | Vocabulario | Longitud |
|---|---|---|
| 4–7 años | Muy simple | 1–2 páginas, principalmente imágenes |
| 8–12 años | Simple | 2–4 páginas, mezcla texto/imágenes |
| 13–17 años | Moderado | 4–8 páginas |
| 18+ años | Sin restricciones | Según complejidad |

---

## Esquema JSON del Juego

Ver `references/game_data_schema.md` para el esquema completo con todos los campos disponibles y un ejemplo funcional.

## Mejores Prácticas de Escritura

Ver `references/best_practices.md` para guía completa sobre estructura, formato, proceso iterativo y señales de alerta.

---

## Notas de Implementación

- El script `generate_manual.py` procesa automáticamente arrays de objetos (componentes, acciones, glosario, FAQ) y los convierte en tablas y secciones Markdown.
- Los campos no provistos aparecen en cursiva gris con `[pendiente de completar]` tanto en .md como en .docx.
- El .docx generado es editable directamente en Word, LibreOffice o Google Docs.
- Instalar dependencia si no está disponible: `sudo pip3 install python-docx`
