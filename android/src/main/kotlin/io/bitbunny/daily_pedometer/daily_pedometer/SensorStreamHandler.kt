package io.bitbunny.daily_pedometer.daily_pedometer

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

class SensorStreamHandler() : EventChannel.StreamHandler {
    private var sensorEventListener: SensorEventListener? = null
    private var sensorManager: SensorManager? = null
    private var sensor: Sensor? = null
    private var events: EventChannel.EventSink? = null

    constructor(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : this() {
        sensorManager =
            flutterPluginBinding.applicationContext.getSystemService(Context.SENSOR_SERVICE) as
                SensorManager
        sensor = sensorManager!!.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        this.events = events
        Log.d("DailyPedometerPlugin", "onListen")
        if (sensor == null) {
            events!!.error(
                "1",
                "StepCount not available",
                "StepCount is not available on this device",
            )
        } else {
            registerSensorListener()
        }
    }

    fun refreshSensorListener() {
        unregisterSensorListener()
        registerSensorListener()
    }

    fun registerSensorListener() {
        Log.d("DailyPedometerPlugin", "registerSensorListener")
        sensorEventListener = sensorEventListener(events!!)
        sensorManager!!.registerListener(
            sensorEventListener,
            sensor,
            SensorManager.SENSOR_DELAY_FASTEST,
        )
    }

    fun unregisterSensorListener() {
        Log.d("DailyPedometerPlugin", "unregisterSensorListener")
        sensorManager!!.unregisterListener(sensorEventListener)
    }

    override fun onCancel(arguments: Any?) {
        dispose()
    }

    fun dispose() {
        unregisterSensorListener()
    }
}
