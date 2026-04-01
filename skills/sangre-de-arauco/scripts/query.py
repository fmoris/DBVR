#!/usr/bin/env python3
"""Query script for Sangre de Arauco knowledge base."""

import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: python query.py <knowledge.aura> <question>")
        sys.exit(1)

    aura_file = sys.argv[1]
    question = " ".join(sys.argv[2:])

    print(f"Pregunta: {question}")
    print("-" * 40)

    try:
        from aura.rag import query_knowledge
        results = query_knowledge(aura_file, question, top_k=3)
        
        for r in results:
            print(r.get('text', ''))
            if r.get('source'):
                print(f"Fuente: {r['source']}")
            print()
    except ImportError:
        print("[ERROR] auralith-aura no instalado")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()