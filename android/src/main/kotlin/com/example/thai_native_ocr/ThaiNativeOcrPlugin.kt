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
import kotlin.math.max

/** Android implementation backed by Tesseract 5. */
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
        val imageBytes = call.argument<ByteArray>("imageBytes")
        if (imagePath.isNullOrBlank() && (imageBytes == null || imageBytes.isEmpty())) {
            result.error("INVALID_ARGUMENT", "imagePath or imageBytes is required.", null)
            return
        }

        val autoDetectThai = call.argument<Boolean>("autoDetectThai") ?: true
        val forceLanguage = call.argument<String>("forceLanguage")
        val preprocess = call.argument<Boolean>("preprocess") ?: false
        if (forceLanguage != null && forceLanguage !in setOf("th", "en", "mixed")) {
            result.error("INVALID_FORCE_LANGUAGE", "forceLanguage must be th, en, or mixed.", null)
            return
        }

        executor.execute {
            try {
                ensureTessdata()
                val bitmap = decodeBitmap(imagePath, imageBytes)

                try {
                    val output = recognize(bitmap, autoDetectThai, forceLanguage, preprocess)
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

    private fun recognize(
        bitmap: Bitmap,
        autoDetectThai: Boolean,
        forceLanguage: String?,
        preprocess: Boolean,
    ): Map<String, Any> {
        var stage1ContainsThai = false

        val stage2Language = when {
            forceLanguage == "en" -> "eng"
            forceLanguage == "th" || forceLanguage == "mixed" -> "tha+eng"
            !autoDetectThai -> "tha+eng"
            else -> {
                val detectorBitmap = downscaleForDetector(bitmap)
                try {
                    val stage1 = runTesseract(
                        bitmap = detectorBitmap,
                        language = "tha+eng",
                        pageSegMode = TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT,
                        dataPath = modelDataPath(ModelProfile.FAST),
                    )
                    stage1ContainsThai = THAI_REGEX.containsMatchIn(stage1.text)
                } finally {
                    if (detectorBitmap !== bitmap) detectorBitmap.recycle()
                }
                if (stage1ContainsThai) "tha+eng" else "eng"
            }
        }

        val stage2Bitmap = if (preprocess) adaptiveThreshold(bitmap) else bitmap
        val stage2 = try {
            runTesseract(
                bitmap = stage2Bitmap,
                language = stage2Language,
                pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO,
                dataPath = modelDataPath(ModelProfile.BEST),
            )
        } finally {
            if (stage2Bitmap !== bitmap) stage2Bitmap.recycle()
        }

        val finalContainsThai = stage1ContainsThai || THAI_REGEX.containsMatchIn(stage2.text)
        val detectedLanguage = detectLanguage(stage2.text, finalContainsThai)

        return mapOf(
            "text" to stage2.text,
            "containsThai" to finalContainsThai,
            "detectedLanguage" to detectedLanguage,
            "confidence" to stage2.confidence,
        )
    }

    private fun decodeBitmap(imagePath: String?, imageBytes: ByteArray?): Bitmap {
        if (imageBytes != null && imageBytes.isNotEmpty()) {
            return BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                ?: throw IllegalArgumentException("Unable to decode imageBytes.")
        }

        val path = imagePath ?: throw IllegalArgumentException("imagePath is required.")
        return BitmapFactory.decodeFile(normalizeImagePath(path))
            ?: throw IllegalArgumentException("Unable to decode imagePath: $path")
    }

    private fun downscaleForDetector(bitmap: Bitmap): Bitmap {
        val largest = max(bitmap.width, bitmap.height)
        if (largest <= DETECTOR_MAX_DIMENSION) return bitmap

        val scale = DETECTOR_MAX_DIMENSION.toDouble() / largest.toDouble()
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
    }

    private fun adaptiveThreshold(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val gray = IntArray(pixels.size)
        for (i in pixels.indices) {
            val color = pixels[i]
            val r = color shr 16 and 0xFF
            val g = color shr 8 and 0xFF
            val b = color and 0xFF
            gray[i] = (r * 299 + g * 587 + b * 114) / 1000
        }

        val integral = LongArray((width + 1) * (height + 1))
        for (y in 1..height) {
            var rowSum = 0L
            for (x in 1..width) {
                rowSum += gray[(y - 1) * width + (x - 1)]
                integral[y * (width + 1) + x] =
                    integral[(y - 1) * (width + 1) + x] + rowSum
            }
        }

        val output = IntArray(pixels.size)
        val radius = ADAPTIVE_BLOCK_SIZE / 2
        for (y in 0 until height) {
            val y0 = (y - radius).coerceAtLeast(0)
            val y1 = (y + radius).coerceAtMost(height - 1)
            for (x in 0 until width) {
                val x0 = (x - radius).coerceAtLeast(0)
                val x1 = (x + radius).coerceAtMost(width - 1)
                val area = (x1 - x0 + 1) * (y1 - y0 + 1)
                val stride = width + 1
                val sum = integral[(y1 + 1) * stride + (x1 + 1)] -
                    integral[y0 * stride + (x1 + 1)] -
                    integral[(y1 + 1) * stride + x0] +
                    integral[y0 * stride + x0]
                val threshold = (sum / area - ADAPTIVE_C).coerceIn(0L, 255L).toInt()
                val value = if (gray[y * width + x] > threshold) 255 else 0
                output[y * width + x] = 0xFF000000.toInt() or
                    (value shl 16) or (value shl 8) or value
            }
        }

        return Bitmap.createBitmap(output, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun runTesseract(
        bitmap: Bitmap,
        language: String,
        pageSegMode: Int,
        dataPath: String,
    ): OcrPass {
        val api = TessBaseAPI()
        try {
            val initialized = api.init(dataPath, language)
            if (!initialized) {
                throw IllegalStateException("Tesseract init failed for language: $language")
            }

            api.pageSegMode = pageSegMode
            api.setImage(bitmap)
            val text = api.utF8Text.orEmpty()
            val confidence = api.meanConfidence().coerceIn(0, 100) / 100.0
            api.clear()
            return OcrPass(text = text, confidence = confidence)
        } finally {
            api.recycle()
        }
    }

    /** Copies bundled fast detector and best recognition models once per revision. */
    private fun ensureTessdata() {
        ensureModelProfile(ModelProfile.FAST)
        ensureModelProfile(ModelProfile.BEST)
    }

    private fun ensureModelProfile(profile: ModelProfile) {
        val dataRoot = File(context.filesDir, "thai_native_ocr/${profile.directory}")
        val tessdataDir = File(dataRoot, "tessdata")
        if (!tessdataDir.exists() && !tessdataDir.mkdirs()) {
            throw IllegalStateException("Unable to create ${tessdataDir.absolutePath}")
        }

        val marker = File(dataRoot, ".model_version")
        val modelsReady = marker.takeIf { it.exists() }?.readText() == profile.version &&
            TRAINED_DATA_FILES.all { File(tessdataDir, it).length() > 0L }
        if (modelsReady) return

        for (name in TRAINED_DATA_FILES) {
            val target = File(tessdataDir, name)
            context.assets.open("${profile.assetDirectory}/$name").use { input ->
                FileOutputStream(target, false).use { output -> input.copyTo(output) }
            }
        }
        marker.writeText(profile.version)
    }

    private fun modelDataPath(profile: ModelProfile): String =
        File(context.filesDir, "thai_native_ocr/${profile.directory}").absolutePath

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

    private enum class ModelProfile(
        val directory: String,
        val assetDirectory: String,
        val version: String,
    ) {
        FAST("fast", "tessdata_fast", "tessdata_fast-v1"),
        BEST("best", "tessdata_best", "tessdata_best-v1"),
    }

    private companion object {
        const val DETECTOR_MAX_DIMENSION = 960
        const val ADAPTIVE_BLOCK_SIZE = 31
        const val ADAPTIVE_C = 10
        val THAI_REGEX = Regex("[\\u0E00-\\u0E7F]")
        val LATIN_REGEX = Regex("[A-Za-z]")
        val TRAINED_DATA_FILES = listOf("tha.traineddata", "eng.traineddata")
    }
}
