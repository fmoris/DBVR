# Esquema de Datos del Juego (game_data.json)

Este archivo define todos los campos que pueden usarse para generar un manual.
Los campos marcados con `*` son **obligatorios**. Los demás son opcionales pero recomendados.

## Ejemplo Completo

```json
{
  "NOMBRE_DEL_JUEGO": "El Nombre del Juego",
  "MIN_JUGADORES": "2",
  "MAX_JUGADORES": "4",
  "DURACION": "45–60",
  "EDAD_MINIMA": "10",
  "VERSION": "1.0",
  "FECHA": "2025-01-01",

  "INTRODUCCION_TEMATICA": "Párrafo narrativo que establece el contexto del juego...",
  "OBJETIVO_DEL_JUEGO": "El jugador que primero acumule 10 puntos de victoria gana la partida.",

  "COMPONENTES": [
    {"nombre": "Tablero principal", "cantidad": 1, "descripcion": "Tablero doble cara de 60x60cm"},
    {"nombre": "Cartas de acción", "cantidad": 48, "descripcion": "Divididas en 4 mazos de 12"},
    {"nombre": "Fichas de recurso", "cantidad": 60, "descripcion": "20 de cada tipo: madera, piedra, oro"},
    {"nombre": "Dados de 6 caras", "cantidad": 3, "descripcion": "Dados estándar numerados del 1 al 6"},
    {"nombre": "Marcadores de jugador", "cantidad": 4, "descripcion": "Uno por color: rojo, azul, verde, amarillo"}
  ],

  "PASOS_SETUP": [
    "Despliega el tablero en el centro de la mesa.",
    "Baraja cada mazo de cartas por separado y colócalos en sus espacios designados.",
    "Distribuye 5 fichas de cada recurso a cada jugador.",
    "Cada jugador coloca su marcador en la casilla de inicio del tablero.",
    "Coloca los dados en el centro de la mesa."
  ],
  "NOTA_SETUP": "Si es la primera partida, se recomienda usar la cara A del tablero (más simple).",
  "REGLA_PRIMER_JUGADOR": "El jugador que más recientemente haya jugado un juego de mesa comienza la partida.",

  "DESCRIPCION_COMPONENTES_VISUALES": "Descripción de cómo leer las cartas, fichas y otros componentes...",

  "RESUMEN_ACCIONES": "En tu turno debes realizar exactamente 2 de las siguientes 4 acciones: Explorar, Construir, Comerciar o Descansar.",

  "ACCIONES": [
    {
      "nombre": "Explorar",
      "descripcion": "Mueve tu marcador hasta 3 casillas en cualquier dirección ortogonal. Puedes robar una carta del mazo de exploración si terminas en una casilla marcada con el símbolo de lupa."
    },
    {
      "nombre": "Construir",
      "descripcion": "Gasta los recursos indicados en una carta de construcción para añadirla a tu área de juego. Cada construcción otorga beneficios pasivos o puntos de victoria."
    }
  ],

  "DESCRIPCION_ACCIONES_ESPECIALES": "Descripción de acciones fuera del turno normal...",

  "DESCRIPCION_FIN_DE_RONDA": "Al final de cada ronda, todos los jugadores roban 2 cartas y reponen los recursos del mercado central.",

  "CONDICION_FIN_DE_JUEGO": "un jugador alcanza 10 puntos de victoria al final de su turno",
  "DESCRIPCION_FIN_DE_JUEGO": "Cuando se activa el fin del juego, todos los demás jugadores completan su turno para igualar el número de turnos jugados.",

  "DESCRIPCION_PUNTUACION": "Suma tus puntos de victoria de construcciones, cartas de objetivo y bonificaciones de fin de partida.",
  "REGLA_DESEMPATE": "En caso de empate, gana el jugador con más recursos. Si persiste el empate, comparten la victoria.",

  "CASOS_ESPECIALES": "Descripción de situaciones excepcionales...",

  "GLOSARIO": [
    {"termino": "Casilla de inicio", "definicion": "La casilla marcada con una estrella donde cada jugador coloca su marcador al inicio."},
    {"termino": "Punto de victoria (PV)", "definicion": "Unidad de medida del progreso. El jugador con más PV al final gana."}
  ],

  "FAQ": [
    {
      "pregunta": "¿Puedo realizar la misma acción dos veces en mi turno?",
      "respuesta": "Sí, puedes elegir la misma acción dos veces, siempre que tengas los recursos necesarios para cada una."
    },
    {
      "pregunta": "¿Qué pasa si el mazo de exploración se agota?",
      "respuesta": "Baraja el descarte para formar un nuevo mazo. Si el descarte también está vacío, no se pueden robar cartas de exploración ese turno."
    }
  ]
}
```

## Campos Obligatorios

| Campo | Tipo | Descripción |
|---|---|---|
| `NOMBRE_DEL_JUEGO` | string | Nombre completo del juego |
| `MIN_JUGADORES` | string | Número mínimo de jugadores |
| `MAX_JUGADORES` | string | Número máximo de jugadores |
| `OBJETIVO_DEL_JUEGO` | string | Condición de victoria en una oración |

## Campos Recomendados

| Campo | Tipo | Descripción |
|---|---|---|
| `DURACION` | string | Duración estimada en minutos |
| `EDAD_MINIMA` | string | Edad mínima recomendada |
| `INTRODUCCION_TEMATICA` | string | Párrafo narrativo de contexto |
| `PASOS_SETUP` | array | Lista ordenada de pasos de preparación |
| `RESUMEN_ACCIONES` | string | Descripción breve del turno típico |
| `ACCIONES` | array | Lista de acciones con nombre y descripción |
| `CONDICION_FIN_DE_JUEGO` | string | Disparador del fin del juego |

## Notas de Uso

Cualquier campo no incluido en el JSON aparecerá en el manual como texto en cursiva gris indicando que está pendiente de completar. Esto permite generar un borrador con estructura completa aunque falte información.
