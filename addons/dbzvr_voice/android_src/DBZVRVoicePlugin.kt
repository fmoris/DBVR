package com.fmoris.dbzvr.voice

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.sqrt

class DBZVRVoicePlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val GRAMMAR_JSON = """[
            "kamehameha",
            "super kamehameha",
            "diez veces kamehameha",
            "juubai kamehameha",
            "genkidama",
            "kaioken",
            "galick ho",
            "gyarikku hou",
            "big bang",
            "ataque big bang",
            "final flash",
            "resplandor final",
            "final explosion",
            "explosion final",
            "[unk]"
        ]"""
    }

    private val isListening = AtomicBoolean(false)
    private var workerThread: Thread? = null
    private var voskModel: Model? = null

    override fun getPluginName(): String = "DBZVRVoice"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("voice_energy_updated", Float::class.javaObjectType),
        SignalInfo("keyword_detected", String::class.java, Float::class.javaObjectType)
    )

    @UsedByGodot
    fun startListening() {
        if (isListening.get()) return
        val act = activity ?: return
        if (ContextCompat.checkSelfPermission(act, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        isListening.set(true)
        workerThread = Thread({
            runCaptureLoop()
        }, "DBZVRVoiceThread").apply { start() }
    }

    @UsedByGodot
    fun stopListening() {
        isListening.set(false)
        workerThread?.interrupt()
        workerThread = null
    }

    private fun ensureModelLoaded(): Model? {
        if (voskModel != null) return voskModel
        val act = activity ?: return null
        val modelDir = File(act.filesDir, "vosk_model_dbzvr")
        if (modelDir.exists() && modelDir.isDirectory) {
            voskModel = Model(modelDir.absolutePath)
        }
        return voskModel
    }

    private fun runCaptureLoop() {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = maxOf(minBuf, 4096)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            isListening.set(false)
            return
        }

        val model = ensureModelLoaded()
        val recognizer = if (model != null) Recognizer(model, SAMPLE_RATE.toFloat(), GRAMMAR_JSON) else null
        val shortBuf = ShortArray(1024)
        recorder.startRecording()

        try {
            while (isListening.get()) {
                val read = recorder.read(shortBuf, 0, shortBuf.size)
                if (read <= 0) continue

                var sumSq = 0.0
                for (i in 0 until read) {
                    val norm = shortBuf[i] / 32768.0
                    sumSq += norm * norm
                }
                val rms = sqrt(sumSq / read.toDouble())
                val rmsDb = if (rms > 1e-5) (20.0 * log10(rms)).toFloat().coerceIn(-80f, 0f) else -80f
                emitSignal("voice_energy_updated", rmsDb)

                if (recognizer != null && recognizer.acceptWaveForm(shortBuf, read)) {
                    val text = JSONObject(recognizer.result).optString("text", "").trim()
                    if (text.isNotEmpty() && text != "[unk]") {
                        emitSignal("keyword_detected", text, 1.0f)
                    }
                }
            }
        } catch (_: InterruptedException) {
        } finally {
            try { recorder.stop() } catch (_: Exception) {}
            recorder.release()
            recognizer?.close()
        }
    }
}
