package com.aeroflix.aeroflix

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aeroflix.app/pip"
    private var autoEnterPip = false
    private var pipEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature("android.software.picture_in_picture"))
                }
                "enterPip" -> result.success(enterPip())
                "setAutoEnterPip" -> {
                    autoEnterPip = call.argument<Boolean>("enabled") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setPictureInPictureParams(buildPipParams())
                    }
                    result.success(null)
                }
                "setPipEnabled" -> {
                    pipEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoEnterPip && pipEnabled)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature("android.software.picture_in_picture")) return false
        if (!pipEnabled) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val engine = flutterEngine ?: return
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
