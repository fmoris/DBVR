"""Regenera audio_manifest.json y audio_manifest.js agrupando los audios por carpeta."""

import json
import os
import re
from datetime import datetime

ROOT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BASE_DIR = os.path.join(ROOT_DIR, "assets", "audio")
SFX_DIR = os.path.join(ROOT_DIR, "assets", "sfx")
AUDIO_EXTS = {".wav", ".ogg", ".mp3", ".flac"}


def natural_key(text: str):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", text)]


def scan_folder(folder_path: str, res_prefix: str, rel_base: str) -> list:
    files = []
    for root, _, filenames in os.walk(folder_path):
        for fn in filenames:
            ext = os.path.splitext(fn)[1].lower()
            if ext in AUDIO_EXTS:
                full = os.path.join(root, fn)
                rel_from_folder = os.path.relpath(full, folder_path).replace("\\", "/")
                rel_from_audio = os.path.relpath(full, rel_base).replace("\\", "/")
                files.append({
                    "file": fn,
                    "path": rel_from_audio,
                    "res_path": f"{res_prefix}/{rel_from_folder}",
                    "ext": ext.lstrip("."),
                    "size_bytes": os.path.getsize(full),
                })
    files.sort(key=lambda x: natural_key(x["path"]))
    return files


def main() -> None:
    folders = {}
    if os.path.isdir(SFX_DIR):
        folders["sfx (En uso actual)"] = scan_folder(SFX_DIR, "res://assets/sfx", BASE_DIR)

    for entry in sorted(os.scandir(BASE_DIR), key=lambda e: natural_key(e.name)):
        if not entry.is_dir():
            continue
        folders[entry.name] = scan_folder(entry.path, f"res://assets/audio/{entry.name}", BASE_DIR)

    manifest = {
        "generated_at": datetime.now().astimezone().isoformat(),
        "base_res_path": "res://assets/audio",
        "total_files": sum(len(v) for v in folders.values()),
        "folders": folders,
    }

    out_dir = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(out_dir, "audio_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    with open(os.path.join(out_dir, "audio_manifest.js"), "w", encoding="utf-8") as f:
        f.write("// Auto-generated fallback for file:// protocol (CORS-free)\n")
        f.write("window.AUDIO_MANIFEST = ")
        json.dump(manifest, f, ensure_ascii=False)
        f.write(";\n")

    print(f"Manifest actualizado: {manifest['total_files']} archivos en {len(folders)} carpetas.")


if __name__ == "__main__":
    main()
