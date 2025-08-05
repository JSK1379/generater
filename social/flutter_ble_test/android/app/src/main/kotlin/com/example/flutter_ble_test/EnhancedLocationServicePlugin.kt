package com.example.flutter_ble_test

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 增強版定位服務的Flutter方法通道處理器
 */
class EnhancedLocationServicePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "enhanced_location_service")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startEnhancedService" -> {
                startEnhancedService(call, result)
            }
            "stopEnhancedService" -> {
                stopEnhancedService(result)
            }
            "isEnhancedServiceRunning" -> {
                result.success(EnhancedLocationForegroundService.isServiceRunning)
            }
            "getEnhancedServiceStats" -> {
                getServiceStats(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startEnhancedService(call: MethodCall, result: Result) {
        try {
            val userId = call.argument<String>("userId")
            val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 30
            val apiUrl = call.argument<String>("apiUrl")
            val showDetailedStats = call.argument<Boolean>("showDetailedStats") ?: true

            if (userId.isNullOrEmpty() || apiUrl.isNullOrEmpty()) {
                result.error("INVALID_ARGS", "userId and apiUrl are required", null)
                return
            }

            val intent = Intent(context, EnhancedLocationForegroundService::class.java).apply {
                action = EnhancedLocationForegroundService.ACTION_START_SERVICE
                putExtra(EnhancedLocationForegroundService.EXTRA_USER_ID, userId)
                putExtra(EnhancedLocationForegroundService.EXTRA_INTERVAL_SECONDS, intervalSeconds)
                putExtra(EnhancedLocationForegroundService.EXTRA_API_URL, apiUrl)
            }

            context.startForegroundService(intent)
            result.success(true)

        } catch (e: Exception) {
            result.error("START_ERROR", "Failed to start enhanced service: ${e.message}", null)
        }
    }

    private fun stopEnhancedService(result: Result) {
        try {
            val intent = Intent(context, EnhancedLocationForegroundService::class.java).apply {
                action = EnhancedLocationForegroundService.ACTION_STOP_SERVICE
            }
            
            context.startService(intent)
            result.success(true)

        } catch (e: Exception) {
            result.error("STOP_ERROR", "Failed to stop enhanced service: ${e.message}", null)
        }
    }

    private fun getServiceStats(result: Result) {
        try {
            // 這裡可以返回服務的統計信息
            // 目前返回基本信息
            val stats = mapOf(
                "isRunning" to EnhancedLocationForegroundService.isServiceRunning,
                "timestamp" to System.currentTimeMillis()
            )
            result.success(stats)
        } catch (e: Exception) {
            result.error("STATS_ERROR", "Failed to get service stats: ${e.message}", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
