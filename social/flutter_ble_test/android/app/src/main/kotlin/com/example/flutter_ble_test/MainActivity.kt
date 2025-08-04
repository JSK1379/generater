package com.example.flutter_ble_test

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    companion object {
        private const val CHANNEL = "location_foreground_service"
        var methodChannel: MethodChannel? = null
        
        // 靜態方法供前台服務調用
        fun sendLocationToFlutter(latitude: Double, longitude: Double) {
            methodChannel?.invokeMethod("onLocationUpdate", mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 30
                    val userId = call.argument<String>("userId") ?: ""
                    
                    if (userId.isNotEmpty()) {
                        // 保存用戶ID到SharedPreferences
                        saveUserId(userId)
                        
                        LocationForegroundService.startService(this, intervalSeconds)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "UserId is required", null)
                    }
                }
                "stopForegroundService" -> {
                    LocationForegroundService.stopService(this)
                    result.success(true)
                }
                "uploadLocation" -> {
                    val latitude = call.argument<Double>("latitude") ?: 0.0
                    val longitude = call.argument<Double>("longitude") ?: 0.0
                    
                    serviceScope.launch {
                        val success = uploadLocationToServer(latitude, longitude)
                        withContext(Dispatchers.Main) {
                            result.success(success)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun saveUserId(userId: String) {
        val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        with(sharedPref.edit()) {
            putString("flutter.background_gps_user_id", userId)
            apply()
        }
    }
    
    private fun getUserId(): String? {
        val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return sharedPref.getString("flutter.background_gps_user_id", null)
    }
    
    private suspend fun uploadLocationToServer(latitude: Double, longitude: Double): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val userId = getUserId() ?: return@withContext false
                
                val url = URL("https://near-ride-backend-api.onrender.com/gps/location?user_id=$userId")
                val connection = url.openConnection() as HttpURLConnection
                
                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    doOutput = true
                }
                
                val jsonBody = JSONObject().apply {
                    put("lat", latitude)
                    put("lng", longitude)
                    put("ts", System.currentTimeMillis())
                }
                
                connection.outputStream.use { outputStream ->
                    outputStream.write(jsonBody.toString().toByteArray())
                }
                
                val responseCode = connection.responseCode
                connection.disconnect()
                
                android.util.Log.d("LocationUpload", "上傳結果: $responseCode for $latitude, $longitude")
                responseCode == HttpURLConnection.HTTP_OK
            } catch (e: Exception) {
                android.util.Log.e("LocationUpload", "上傳失敗: ${e.message}", e)
                false
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
