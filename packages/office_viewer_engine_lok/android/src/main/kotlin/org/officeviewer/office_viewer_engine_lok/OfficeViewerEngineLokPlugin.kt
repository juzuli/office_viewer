package org.officeviewer.office_viewer_engine_lok

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.libreoffice.kit.LibreOfficeKit

/** Android LOK bootstrap; Dart owns document FFI after init. */
class OfficeViewerEngineLokPlugin :
    FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var officePtr: Long = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "office_viewer_engine_lok/bootstrap")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                try {
                    val ctx = activity ?: appContext
                    if (ctx == null) {
                        result.error("no_context", "Android context not available", null)
                        return
                    }
                    val appInfo = ctx.applicationInfo
                    val dataDir = appInfo.dataDir
                    val cacheDir = ctx.cacheDir.absolutePath
                    val apkFile = ctx.packageResourcePath
                    val assets = ctx.assets
                    val prefs = ctx.getSharedPreferences(
                        "office_viewer_engine_lok",
                        android.content.Context.MODE_PRIVATE,
                    )
                    officePtr = LibreOfficeKit.init(dataDir, cacheDir, apkFile, assets, prefs)
                    result.success(
                        mapOf(
                            "officePtr" to officePtr,
                            "library" to "lo-native-code",
                        ),
                    )
                } catch (e: Throwable) {
                    result.error("init_failed", e.message, e.stackTraceToString())
                }
            }
            "isReady" -> result.success(officePtr != 0L && LibreOfficeKit.isInitialized())
            "officePtr" -> result.success(officePtr)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
