package com.example.flutter_ble_test

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import java.util.*

class LocationForegroundService : Service() {
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "location_foreground_service"
        private const val ACTION_START = "START_LOCATION_SERVICE"
        private const val ACTION_STOP = "STOP_LOCATION_SERVICE"
        
        fun startService(context: Context, intervalSeconds: Int) {
            val intent = Intent(context, LocationForegroundService::class.java).apply {
                action = ACTION_START
                putExtra("interval_seconds", intervalSeconds)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.stopService(intent)
        }
    }
    
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private var serviceJob = SupervisorJob()
    private var serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)
    private var intervalSeconds = 30
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    onLocationReceived(location)
                }
            }
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                intervalSeconds = intent.getIntExtra("interval_seconds", 30)
                startForegroundService()
                startLocationUpdates()
            }
            ACTION_STOP -> {
                stopLocationUpdates()
                stopSelf()
            }
        }
        return START_STICKY
    }
    
    private fun startForegroundService() {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Foreground Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "持續追蹤GPS位置"
                setSound(null, null)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GPS追蹤運行中")
            .setContentText("每${intervalSeconds}秒記錄一次位置")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
    
    private fun startLocationUpdates() {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            (intervalSeconds * 1000).toLong()
        ).apply {
            setMinUpdateDistanceMeters(0f)
            setMaxUpdateDelayMillis((intervalSeconds * 1000).toLong())
        }.build()
        
        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
        } catch (securityException: SecurityException) {
            // 權限不足時停止服務
            stopSelf()
        }
    }
    
    private fun stopLocationUpdates() {
        fusedLocationClient.removeLocationUpdates(locationCallback)
        serviceJob.cancel()
    }
    
    private fun onLocationReceived(location: Location) {
        serviceScope.launch {
            try {
                // 發送位置給 Flutter
                sendLocationToFlutter(location.latitude, location.longitude)
                
                // 同時直接上傳到服務器
                uploadLocationToServer(location.latitude, location.longitude)
                
                // 更新通知顯示最新位置時間
                updateNotification(location)
            } catch (e: Exception) {
                android.util.Log.e("LocationService", "處理位置更新失敗", e)
            }
        }
    }
    
    private suspend fun uploadLocationToServer(latitude: Double, longitude: Double) {
        withContext(Dispatchers.IO) {
            try {
                val userId = getUserId() ?: return@withContext
                
                val url = java.net.URL("https://near-ride-backend-api.onrender.com/gps/location?user_id=$userId")
                val connection = url.openConnection() as java.net.HttpURLConnection
                
                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    doOutput = true
                }
                
                val jsonBody = org.json.JSONObject().apply {
                    put("lat", latitude)
                    put("lng", longitude)
                    put("ts", System.currentTimeMillis())
                }
                
                connection.outputStream.use { outputStream ->
                    outputStream.write(jsonBody.toString().toByteArray())
                }
                
                val responseCode = connection.responseCode
                connection.disconnect()
                
                android.util.Log.d("LocationService", "位置上傳結果: $responseCode for $latitude, $longitude")
            } catch (e: Exception) {
                android.util.Log.e("LocationService", "位置上傳失敗: ${e.message}", e)
            }
        }
    }
    
    private fun getUserId(): String? {
        val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return sharedPref.getString("flutter.background_gps_user_id", null)
    }
    
    private fun sendLocationToFlutter(latitude: Double, longitude: Double) {
        // 通過 MainActivity 發送位置給 Flutter
        MainActivity.sendLocationToFlutter(latitude, longitude)
        
        // 同時記錄日誌
        android.util.Log.d("LocationService", "位置更新: $latitude, $longitude")
    }
    
    private fun updateNotification(location: Location) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GPS追蹤運行中")
            .setContentText("最新位置: ${String.format("%.6f", location.latitude)}, ${String.format("%.6f", location.longitude)}")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setSilent(true)
            .build()
            
        val notificationManager = NotificationManagerCompat.from(this)
        try {
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (securityException: SecurityException) {
            // 忽略通知權限問題
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopLocationUpdates()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}
