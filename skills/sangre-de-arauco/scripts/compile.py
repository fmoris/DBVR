#!/usr/bin/env python3
"""Compile script for Sangre de Arauco - writes directly to aura format."""

import sys
import os

def main():
    if len(sys.argv) < 3:
        print("Usage: python compile.py <input_dir> <output.aura>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_file = sys.argv[2]

    print(f"[*] Compilando: {input_dir} -> {output_file}")

    # Collect all text content
    all_text = []
    
    if os.path.exists(input_dir):
        for f in sorted(os.listdir(input_dir)):
            fpath = os.path.join(input_dir, f)
            if f.endswith('.txt'):
                try:
                    with open(fpath, 'r', encoding='utf-8') as file:
                        content = file.read()
                        all_text.append({
                            'source': f,
                            'content': content
                        })
                        print(f"[+] Agregado: {f} ({len(content)} caracteres)")
                except Exception as e:
                    print(f"[!] Error leyendo {f}: {e}")

    if not all_text:
        print("[!] No se encontraron archivos de texto")
        sys.exit(1)

    # Try to write to aura format
    try:
        from aura import AuraWriter
        
        aw = AuraWriter(output_file)
        for item in all_text:
            aw.write(item['content'], metadata={'source': item['source']})
        aw.close()
        
        print(f"[OK] Escrito a: {output_file}")
        
    except Exception as e:
        # Fallback: just save as combined text
        print(f"[!] Aura fallo: {e}")
        print("[*] Guardando como texto combinado...")
        
        combined_file = output_file.replace('.aura', '-completo.txt')
        with open(combined_file, 'w', encoding='utf-8') as f:
            for item in all_text:
                f.write(f"\n\n=== {item['source']} ===\n\n")
                f.write(item['content'])
        
        print(f"[OK] Guardado en: {combined_file}")

if __name__ == "__main__":
    main()