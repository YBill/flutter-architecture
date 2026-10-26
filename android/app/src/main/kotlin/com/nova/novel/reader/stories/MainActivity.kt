package com.nova.novel.reader.stories

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var originalBrightness: Float? = null
    private var readerBrightness: Float? = null
    private var isForeground = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nova.novel.reader.stories/brightness")
        channel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getBrightness" -> {
                        val value = window.attributes.screenBrightness
                        result.success(if (value >= 0) value.toDouble() else
                            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS).coerceIn(0, 255) / 255.0)
                    }
                    "setBrightness" -> {
                        val value = call.argument<Double>("brightness")
                        if (value == null || !value.isFinite() || value !in 0.0..1.0) {
                            result.error("invalid_brightness", "Brightness must be between 0 and 1", null)
                        } else {
                            if (originalBrightness == null) originalBrightness = window.attributes.screenBrightness
                            readerBrightness = value.toFloat()
                            if (isForeground) setWindowBrightness(value.toFloat())
                            result.success(null)
                        }
                    }
                    "resetBrightness" -> {
                        resetBrightness()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("brightness_error", error.message, null)
            }
        }
    }

    private fun setWindowBrightness(value: Float) {
        val params = window.attributes
        params.screenBrightness = value
        window.attributes = params
    }

    private fun resetBrightness() {
        originalBrightness?.let { setWindowBrightness(it) }
        readerBrightness = null
        originalBrightness = null
    }

    override fun onPause() {
        isForeground = false
        originalBrightness?.let { setWindowBrightness(it) }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        readerBrightness?.let { setWindowBrightness(it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        resetBrightness()
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
