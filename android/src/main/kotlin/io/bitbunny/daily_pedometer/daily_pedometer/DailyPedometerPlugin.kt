package io.bitbunny.daily_pedometer.daily_pedometer

import android.content.Context
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** DailyPedometerPlugin */
class DailyPedometerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var stepCountChannel: EventChannel
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    private var stepCountHandler: SensorStreamHandler? = null
    private var bootCount: Int = 0

    override fun onAttachedToEngine(_flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("DailyPedometerPlugin", "onAttachedToEngine called")
        flutterPluginBinding = _flutterPluginBinding
        val context: Context = flutterPluginBinding.applicationContext
        bootCount =
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.BOOT_COUNT,
            )
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "daily_pedometer")
        methodChannel.setMethodCallHandler(this)
        stepCountChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "daily_pedometer_raw_step_count")

        attachStepStream()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stepCountChannel.setStreamHandler(null)
        dettachStepStream()
        if (::methodChannel.isInitialized) {
            methodChannel.setMethodCallHandler(null)
        }
    }

    fun attachStepStream() {
        if (stepCountHandler == null) {
            stepCountHandler = SensorStreamHandler(flutterPluginBinding)
            stepCountChannel.setStreamHandler(stepCountHandler)
        }
    }

    fun dettachStepStream() {
        stepCountHandler?.let {
            stepCountChannel.setStreamHandler(null)
            stepCountHandler!!.dispose()
            stepCountHandler = null
        }
    }

    // step 콜백이 풀리는 경우가 있어, 그런 경우에 대비하여 reattach한다.
    fun reattachStepStream() {
        dettachStepStream()
        attachStepStream()
    }

    override fun onMethodCall(
        @NonNull call: MethodCall,
        @NonNull result: Result,
    ) {
        when (call.method) {
            "reattachStepStream" -> {
                reattachStepStream()
                result.success(null)
            }
            "getBootCount" -> {
                result.success(bootCount)
            }
            "getPlatformVersion" -> {
                result.success(42)
            }
            else -> result.notImplemented()
        }
    }
}
