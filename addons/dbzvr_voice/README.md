# DBZVR Voice Plugin (Vosk Offline — Latino / Japonés)

## Estado
- **Fase 1 (Activa por defecto):** `VoiceCombatManager.gd` usa `AudioStreamMicrophone` + `AudioEffectCapture` en el bus `MicCapture` (silenciado hacia `Master`) para detectar gritos sostenidos y *Kiai* en tiempo real tanto en escritorio como en Meta Quest 3.
- **Fase 2 (Andamiaje Android Vosk):** `android_src/DBZVRVoicePlugin.kt` implementa el singleton `DBZVRVoice` con gramática cerrada en Latino y Japonés (`com.alphacephei:vosk-android:0.3.47`).

## Para activar la Fase 2 en APK
1. Compilar `DBZVRVoicePlugin.kt` como `.aar` y copiarlo en `addons/dbzvr_voice/bin/debug/dbzvr_voice-debug.aar` y `bin/release/dbzvr_voice-release.aar`.
2. Copiar el modelo compacto Vosk (`vosk-model-small-es-0.42`) a `filesDir/vosk_model_dbzvr` en Android.
3. Activar el plugin `DBZVR Voice (Vosk Offline)` en *Project Settings -> Plugins*.
