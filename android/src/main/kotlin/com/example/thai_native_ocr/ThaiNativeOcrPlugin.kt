package com.example.thai_native_ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Android implementation: Tesseract only. iOS intentionally uses Apple Vision instead. */
class ThaiNativeOcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "thai_native_ocr")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognize") {
            result.notImplemented()
            return
        }

        val imagePath = call.argument<String>("imagePath")
        if (imagePath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "imagePath is required.", null)
            return
        }

        val autoDetectThai = call.argument<Boolean>("autoDetectThai") ?: true
        val forceLanguage = call.argument<String>("forceLanguage")
        if (forceLanguage != null && forceLanguage !in setOf("th", "en", "mixed")) {
            result.error("INVALID_FORCE_LANGUAGE", "forceLanguage must be th, en, or mixed.", null)
            return
        }

        executor.execute {
            try {
                ensureTessdata()
                val bitmap = BitmapFactory.decodeFile(normalizeImagePath(imagePath))
                    ?: throw IllegalArgumentException("Unable to decode imagePath: $imagePath")

                try {
                    val output = recognize(bitmap, autoDetectThai, forceLanguage)
                    mainHandler.post { result.success(output) }
                } finally {
                    bitmap.recycle()
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("OCR_FAILED", error.message ?: "Android OCR failed.", null)
                }
            }
        }
    }

    /**
     * Two-stage OCR:
     * 1. Lightweight English pass used only as the Thai detector signal.
     * 2. Accurate pass using tha+eng when Thai was detected, otherwise eng.
     *
     * forceLanguage bypasses Stage 1. autoDetectThai=false also bypasses Stage 1
     * and directly runs the bilingual tha+eng pass. `th` is retained as a
     * backward-compatible alias for the bilingual tha+eng strategy.
     */
    private fun recognize(
        bitmap: Bitmap,
        autoDetectThai: Boolean,
        forceLanguage: String?,
    ): Map<String, Any> {
        var stage1ContainsThai = false

        val stage2Language = when {
            forceLanguage == "en" -> "eng"
            forceLanguage == "th" || forceLanguage == "mixed" -> "tha+eng"
            !autoDetectThai -> "tha+eng"
            else -> {
                // Stage 1: quick OCR with eng. PSM_AUTO is used instead of
                // PSM_AUTO_OSD because AUTO_OSD requires osd.traineddata,
                // which this package intentionally does not ship.
                val stage1 = runTesseract(
                    bitmap = bitmap,
                    language = "eng",
                    pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO,
                )
                stage1ContainsThai = THAI_REGEX.containsMatchIn(stage1.text)
                if (stage1ContainsThai) "tha+eng" else "eng"
            }
        }

        // Stage 2 has only two execution modes: bilingual Thai+English or English.
        val stage2 = runTesseract(
            bitmap = bitmap,
            language = stage2Language,
            pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO,
        )

        val finalContainsThai = stage1ContainsThai || THAI_REGEX.containsMatchIn(stage2.text)
        val detectedLanguage = detectLanguage(stage2.text, finalContainsThai)

        return mapOf(
            "text" to stage2.text,
            "containsThai" to finalContainsThai,
            "detectedLanguage" to detectedLanguage,
            "confidence" to stage2.confidence,
        )
    }

    private fun runTesseract(
        bitmap: Bitmap,
        language: String,
        pageSegMode: Int,
    ): OcrPass {
        val api = TessBaseAPI()
        try {
            val initialized = api.init(context.filesDir.absolutePath, language)
            if (!initialized) {
                throw IllegalStateException("Tesseract init failed for language: $language")
            }

            api.pageSegMode = pageSegMode
            api.setImage(bitmap)
            val text = api.utF8Text.orEmpty()
            val confidence = (api.meanConfidence().coerceIn(0, 100) / 100.0)
            api.clear()
            return OcrPass(text = text, confidence = confidence)
        } finally {
            api.end()
        }
    }

    /** Copies bundled tessdata_best files once into filesDir/tessdata/. */
    private fun ensureTessdata() {
        val tessdataDir = File(context.filesDir, "tessdata")
        if (!tessdataDir.exists() && !tessdataDir.mkdirs()) {
            throw IllegalStateException("Unable to create ${tessdataDir.absolutePath}")
        }

        for (name in TRAINED_DATA_FILES) {
            val target = File(tessdataDir, name)
            if (target.exists() && target.length() > 0L) continue

            context.assets.open("tessdata/$name").use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }
        }
    }

    private fun normalizeImagePath(path: String): String =
        if (path.startsWith("file://")) android.net.Uri.parse(path).path ?: path else path

    private fun detectLanguage(text: String, containsThai: Boolean): String {
        val containsLatin = LATIN_REGEX.containsMatchIn(text)
        return when {
            containsThai && containsLatin -> "mixed"
            containsThai -> "th"
            else -> "en"
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private data class OcrPass(val text: String, val confidence: Double)

    private companion object {
        val THAI_REGEX = Regex("[\\u0E00-\\u0E7F]")
        val LATIN_REGEX = Regex("[A-Za-z]")
        val TRAINED_DATA_FILES = listOf("tha.traineddata", "eng.traineddata")
    }
}
