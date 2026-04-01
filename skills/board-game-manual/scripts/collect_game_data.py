#!/usr/bin/env python3
"""
Recopilador Interactivo de Datos para Manual de Juego de Mesa
Guía al usuario a través de preguntas para construir el game_data.json
necesario para generar el manual.

Uso:
    python collect_game_data.py [--output game_data.json]
"""

import json
import sys
import os
import argparse
from datetime import datetime


def ask(question: str, required: bool = False, default: str = None) -> str:
    """Hace una pregunta al usuario y retorna la respuesta."""
    suffix = ""
    if default:
        suffix = f" [{default}]"
    elif not required:
        suffix = " [dejar en blanco para completar después]"

    while True:
        print(f"\n{question}{suffix}")
        answer = input("> ").strip()

        if not answer:
            if default:
                return default
            elif not required:
                return ""
            else:
                print("  Este campo es obligatorio. Por favor, ingresa un valor.")
        else:
            return answer


def ask_list(question: str, item_prompt: str, required: bool = False) -> list:
    """Recopila una lista de elementos."""
    print(f"\n{question}")
    print("  (Escribe cada elemento y presiona Enter. Deja en blanco para terminar.)")
    items = []
    counter = 1
    while True:
        item = input(f"  {item_prompt} {counter}: ").strip()
        if not item:
            if not items and required:
                print("  Debes ingresar al menos un elemento.")
                continue
            break
        items.append(item)
        counter += 1
    return items


def ask_components() -> list:
    """Recopila la lista de componentes del juego."""
    print("\n=== COMPONENTES ===")
    print("Ingresa los componentes del juego (nombre, cantidad y descripción breve).")
    print("Deja el nombre en blanco para terminar.")
    components = []
    counter = 1
    while True:
        print(f"\n  Componente {counter}:")
        nombre = input("    Nombre (ej: 'Tablero principal'): ").strip()
        if not nombre:
            break
        cantidad_str = input("    Cantidad: ").strip()
        try:
            cantidad = int(cantidad_str) if cantidad_str else 1
        except ValueError:
            cantidad = cantidad_str if cantidad_str else 1
        descripcion = input("    Descripción breve: ").strip()
        components.append({
            "nombre": nombre,
            "cantidad": cantidad,
            "descripcion": descripcion
        })
        counter += 1
    return components


def ask_actions() -> list:
    """Recopila las acciones del turno."""
    print("\n=== ACCIONES DEL TURNO ===")
    print("Ingresa las acciones disponibles en el turno de cada jugador.")
    print("Deja el nombre en blanco para terminar.")
    actions = []
    counter = 1
    while True:
        print(f"\n  Acción {counter}:")
        nombre = input("    Nombre de la acción: ").strip()
        if not nombre:
            break
        descripcion = input("    Descripción detallada: ").strip()
        actions.append({"nombre": nombre, "descripcion": descripcion})
        counter += 1
    return actions


def ask_faq() -> list:
    """Recopila preguntas frecuentes."""
    print("\n=== PREGUNTAS FRECUENTES (FAQ) ===")
    print("Ingresa las preguntas frecuentes del juego.")
    print("Deja la pregunta en blanco para terminar.")
    faq = []
    counter = 1
    while True:
        print(f"\n  Pregunta {counter}:")
        pregunta = input("    Pregunta: ").strip()
        if not pregunta:
            break
        respuesta = input("    Respuesta: ").strip()
        faq.append({"pregunta": pregunta, "respuesta": respuesta})
        counter += 1
    return faq


def ask_glossary() -> list:
    """Recopila términos del glosario."""
    print("\n=== GLOSARIO ===")
    print("Ingresa los términos específicos del juego y sus definiciones.")
    print("Deja el término en blanco para terminar.")
    glossary = []
    counter = 1
    while True:
        print(f"\n  Término {counter}:")
        termino = input("    Término: ").strip()
        if not termino:
            break
        definicion = input("    Definición: ").strip()
        glossary.append({"termino": termino, "definicion": definicion})
        counter += 1
    return glossary


def collect_data(mode: str = "full") -> dict:
    """
    Recopila datos del juego.
    mode: 'full' (todas las preguntas) o 'minimal' (solo campos obligatorios)
    """
    data = {}

    print("\n" + "=" * 60)
    print("  GENERADOR DE MANUAL DE JUEGO DE MESA")
    print("=" * 60)
    print("\nVoy a hacerte preguntas para generar el manual de tu juego.")
    print("Puedes dejar campos en blanco para completarlos después.")

    # Información básica (siempre obligatoria)
    print("\n--- INFORMACIÓN BÁSICA ---")
    data["NOMBRE_DEL_JUEGO"] = ask("¿Cuál es el nombre del juego?", required=True)
    data["MIN_JUGADORES"] = ask("¿Número mínimo de jugadores?", required=True)
    data["MAX_JUGADORES"] = ask("¿Número máximo de jugadores?", required=True)
    data["DURACION"] = ask("¿Duración estimada de la partida (en minutos)?")
    data["EDAD_MINIMA"] = ask("¿Edad mínima recomendada?")
    data["VERSION"] = ask("¿Versión del manual?", default="1.0")
    data["FECHA"] = ask("¿Fecha del manual?", default=datetime.now().strftime("%Y-%m-%d"))

    if mode == "minimal":
        return data

    # Introducción y objetivo
    print("\n--- INTRODUCCIÓN Y OBJETIVO ---")
    data["INTRODUCCION_TEMATICA"] = ask(
        "Escribe un párrafo de introducción temática (contexto narrativo del juego):"
    )
    data["OBJETIVO_DEL_JUEGO"] = ask(
        "¿Cuál es el objetivo del juego? (condición de victoria en una oración):",
        required=True
    )

    # Componentes
    print("\n¿Deseas ingresar los componentes ahora? (s/n)")
    if input("> ").strip().lower() in ("s", "si", "sí", "y", "yes"):
        data["COMPONENTES"] = ask_components()

    # Setup
    print("\n--- PREPARACIÓN ---")
    print("¿Deseas ingresar los pasos de preparación ahora? (s/n)")
    if input("> ").strip().lower() in ("s", "si", "sí", "y", "yes"):
        data["PASOS_SETUP"] = ask_list(
            "Pasos de preparación (en orden):",
            "Paso"
        )
    data["NOTA_SETUP"] = ask("¿Alguna nota especial sobre la preparación?")
    data["REGLA_PRIMER_JUGADOR"] = ask("¿Cómo se selecciona el primer jugador?")

    # Componentes visuales
    data["DESCRIPCION_COMPONENTES_VISUALES"] = ask(
        "Describe cómo leer los componentes (cartas, fichas, dados, etc.):"
    )

    # Turno de juego
    print("\n--- TURNO DE JUEGO ---")
    data["RESUMEN_ACCIONES"] = ask(
        "Describe brevemente qué puede hacer un jugador en su turno:"
    )
    print("\n¿Deseas ingresar las acciones detalladas ahora? (s/n)")
    if input("> ").strip().lower() in ("s", "si", "sí", "y", "yes"):
        data["ACCIONES"] = ask_actions()

    # Acciones especiales
    data["DESCRIPCION_ACCIONES_ESPECIALES"] = ask(
        "¿Hay acciones especiales fuera del turno normal? Descríbelas:"
    )

    # Fin de ronda y juego
    print("\n--- FIN DE RONDA Y FIN DEL JUEGO ---")
    data["DESCRIPCION_FIN_DE_RONDA"] = ask(
        "¿Qué ocurre al final de cada ronda? (dejar en blanco si no hay rondas):"
    )
    data["CONDICION_FIN_DE_JUEGO"] = ask(
        "¿Cuál es la condición que dispara el fin del juego?",
        required=True
    )
    data["DESCRIPCION_FIN_DE_JUEGO"] = ask(
        "¿Qué ocurre después de que se dispara el fin del juego?"
    )

    # Puntuación
    print("\n--- PUNTUACIÓN ---")
    data["DESCRIPCION_PUNTUACION"] = ask("¿Cómo se calcula la puntuación final?")
    data["REGLA_DESEMPATE"] = ask("¿Cómo se resuelven los empates?")

    # Apéndice
    print("\n--- APÉNDICE ---")
    data["CASOS_ESPECIALES"] = ask(
        "¿Hay casos especiales o situaciones excepcionales que mencionar?"
    )

    # Glosario
    print("\n¿Deseas ingresar términos del glosario ahora? (s/n)")
    if input("> ").strip().lower() in ("s", "si", "sí", "y", "yes"):
        data["GLOSARIO"] = ask_glossary()

    # FAQ
    print("\n¿Deseas ingresar preguntas frecuentes ahora? (s/n)")
    if input("> ").strip().lower() in ("s", "si", "sí", "y", "yes"):
        data["FAQ"] = ask_faq()

    return data


def main():
    parser = argparse.ArgumentParser(
        description="Recopilador interactivo de datos para manual de juego de mesa"
    )
    parser.add_argument(
        "--output",
        default="game_data.json",
        help="Ruta del archivo JSON de salida"
    )
    parser.add_argument(
        "--mode",
        choices=["full", "minimal"],
        default="full",
        help="Modo de recopilación: full (todas las preguntas) o minimal (solo obligatorios)"
    )
    args = parser.parse_args()

    try:
        data = collect_data(mode=args.mode)
    except KeyboardInterrupt:
        print("\n\n[Cancelado por el usuario]")
        sys.exit(0)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"\n[OK] Datos guardados en: {args.output}")
    print("\nPróximo paso: Genera el manual con:")
    print(f"  python generate_manual.py {args.output} --format both")


if __name__ == "__main__":
    main()
