package com.example.flutter_ble_test

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.android.gms.tasks.OnCompleteListener
import io.flutter.embedding.android.FlutterActivity
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

/**
 * 增強版前台定位服務 - 類似Google Maps的背景GPS追蹤
 * 特色：
 * 1. 真正的背景運行（關閉APP也能繼續）
 * 2. 高頻率定位（最低5秒間隔）
 * 3. 智能省電策略
 * 4. 防止系統殺死服務
 * 5. 自動重啟機制
 */
class EnhancedLocationForegroundService : Service() {

    companion object {
        private const val TAG = "EnhancedLocationService"
        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID = "enhanced_location_service"
        private const val LOCATION_REQUEST_CODE = 1000
        
        // 服務控制
        const val ACTION_START_SERVICE = "START_ENHANCED_LOCATION_SERVICE"
        const val ACTION_STOP_SERVICE = "STOP_ENHANCED_LOCATION_SERVICE"
        
        // 配置參數
        const val EXTRA_USER_ID = "user_id"
        const val EXTRA_INTERVAL_SECONDS = "interval_seconds"
        const val EXTRA_API_URL = "api_url"
        
        // 服務狀態
        var isServiceRunning = false
            private set
    }

    // 核心組件
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationRequest: LocationRequest
    private lateinit var locationCallback: LocationCallback
    private lateinit var notificationManager: NotificationManager
    private lateinit var wakeLock: PowerManager.WakeLock
    
    // HTTP客戶端
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    
    // 配置參數
    private var userId: String = ""
    private var intervalSeconds: Int = 30
    private var apiUrl: String = ""
    
    // 協程作用域
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // 統計數據
    private var locationUpdateCount = 0
    private var lastLocationTime = 0L
    private var uploadSuccessCount = 0
    private var uploadFailureCount = 0

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 Enhanced Location Service 創建中...")
        
        // 初始化核心組件
        initializeComponents()
        
        // 創建通知渠道
        createNotificationChannel()
        
        Log.d(TAG, "✅ Enhanced Location Service 初始化完成")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📱 收到服務命令: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START_SERVICE -> {
                // 提取配置參數
                userId = intent.getStringExtra(EXTRA_USER_ID) ?: ""
                intervalSeconds = intent.getIntExtra(EXTRA_INTERVAL_SECONDS, 30)
                apiUrl = intent.getStringExtra(EXTRA_API_URL) ?: ""
                
                if (userId.isEmpty() || apiUrl.isEmpty()) {
                    Log.e(TAG, "❌ 缺少必要參數: userId=$userId, apiUrl=$apiUrl")
                    stopSelf()
                    return START_NOT_STICKY
                }
                
                startLocationTracking()
            }
            ACTION_STOP_SERVICE -> {
                stopLocationTracking()
                stopSelf()
            }
        }
        
        // 返回 START_STICKY 確保服務被系統殺死後會重啟
        return START_STICKY
    }

    private fun initializeComponents() {
        // 初始化位置服務客戶端
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        
        // 獲取 WakeLock 防止CPU休眠
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$TAG:LocationWakeLock"
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Enhanced GPS Location Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "高頻率背景GPS定位服務（類似Google Maps）"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startLocationTracking() {
        if (isServiceRunning) {
            Log.w(TAG, "⚠️ 服務已在運行中")
            return
        }
        
        // 檢查權限
        if (!hasLocationPermissions()) {
            Log.e(TAG, "❌ 缺少定位權限")
            stopSelf()
            return
        }
        
        try {
            // 獲取 WakeLock
            if (!wakeLock.isHeld) {
                wakeLock.acquire(10*60*1000L /*10 minutes*/)
                Log.d(TAG, "🔒 WakeLock 已獲取")
            }
            
            // 配置位置請求
            setupLocationRequest()
            
            // 設置位置回調
            setupLocationCallback()
            
            // 開始前台服務
            startForeground(NOTIFICATION_ID, createNotification())
            
            // 開始位置更新
            startLocationUpdates()
            
            isServiceRunning = true
            Log.d(TAG, "✅ Enhanced Location Service 已啟動 - 間隔: ${intervalSeconds}秒")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 啟動位置追蹤失敗", e)
            stopSelf()
        }
    }

    private fun setupLocationRequest() {
        locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            (intervalSeconds * 1000).toLong() // 轉換為毫秒
        ).apply {
            setMinUpdateDistanceMeters(0f) // 不限制距離
            setMinUpdateIntervalMillis((intervalSeconds * 1000).toLong())
            setMaxUpdateDelayMillis((intervalSeconds * 2000).toLong()) // 最大延遲
            setWaitForAccurateLocation(false) // 不等待高精度
        }.build()
        
        Log.d(TAG, "📍 位置請求已配置 - 間隔: ${intervalSeconds}秒, 優先級: 高精度")
    }

    private fun setupLocationCallback() {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                super.onLocationResult(locationResult)
                
                locationResult.lastLocation?.let { location ->
                    handleLocationUpdate(location)
                }
            }
            
            override fun onLocationAvailability(availability: LocationAvailability) {
                super.onLocationAvailability(availability)
                Log.d(TAG, "📡 位置可用性: ${availability.isLocationAvailable}")
            }
        }
    }

    private fun startLocationUpdates() {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "❌ 權限檢查失敗")
            return
        }

        fusedLocationClient.requestLocationUpdates(
            locationRequest,
            locationCallback,
            Looper.getMainLooper()
        ).addOnCompleteListener { task ->
            if (task.isSuccessful) {
                Log.d(TAG, "🎯 位置更新請求成功")
            } else {
                Log.e(TAG, "❌ 位置更新請求失敗: ${task.exception}")
            }
        }
    }

    private fun handleLocationUpdate(location: Location) {
        locationUpdateCount++
        lastLocationTime = System.currentTimeMillis()
        
        Log.d(TAG, "📍 位置更新 #$locationUpdateCount: ${location.latitude}, ${location.longitude}")
        Log.d(TAG, "📊 精度: ${location.accuracy}m, 時間: ${Date(location.time)}")
        
        // 更新通知
        updateNotification(location)
        
        // 檢查通勤時段再決定是否上傳
        if (isInCommuteTime()) {
            Log.d(TAG, "✅ 在通勤時段內，上傳位置")
            // 異步上傳位置
            serviceScope.launch {
                uploadLocationToServer(location)
            }
        } else {
            Log.d(TAG, "⏰ 不在通勤時段內，跳過位置上傳")
        }
        
        // 重新獲取 WakeLock（延長持有時間）
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        wakeLock.acquire(10*60*1000L /*10 minutes*/)
    }

    private suspend fun uploadLocationToServer(location: Location) {
        try {
            val json = JSONObject().apply {
                put("lat", location.latitude)
                put("lng", location.longitude)
                put("ts", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.getDefault()).format(Date()))
                put("accuracy", location.accuracy)
                put("altitude", location.altitude)
                put("speed", location.speed)
                put("bearing", location.bearing)
            }
            
            val requestBody = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$apiUrl?user_id=$userId")
                .post(requestBody)
                .addHeader("Content-Type", "application/json")
                .build()
            
            withContext(Dispatchers.IO) {
                httpClient.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        uploadSuccessCount++
                        Log.d(TAG, "✅ 位置上傳成功 #$uploadSuccessCount")
                    } else {
                        uploadFailureCount++
                        Log.e(TAG, "❌ 位置上傳失敗 #$uploadFailureCount: HTTP ${response.code}")
                    }
                }
            }
            
        } catch (e: Exception) {
            uploadFailureCount++
            Log.e(TAG, "❌ 位置上傳異常 #$uploadFailureCount", e)
        }
    }

    private fun createNotification(): Notification {
        // 點擊通知打開應用
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // 停止服務的Action
        val stopIntent = Intent(this, EnhancedLocationForegroundService::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛰️ GPS追蹤運行中")
            .setContentText("高頻率背景定位 - 每${intervalSeconds}秒記錄")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "停止", stopPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(location: Location) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛰️ GPS追蹤運行中")
            .setContentText("已記錄 $locationUpdateCount 次 | 成功: $uploadSuccessCount | 失敗: $uploadFailureCount")
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                "位置: ${String.format("%.6f", location.latitude)}, ${String.format("%.6f", location.longitude)}\n" +
                "精度: ${String.format("%.1f", location.accuracy)}m | 間隔: ${intervalSeconds}秒\n" +
                "記錄次數: $locationUpdateCount | 成功: $uploadSuccessCount | 失敗: $uploadFailureCount"
            ))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun stopLocationTracking() {
        if (!isServiceRunning) {
            Log.w(TAG, "⚠️ 服務未在運行中")
            return
        }
        
        try {
            // 停止位置更新
            fusedLocationClient.removeLocationUpdates(locationCallback)
            
            // 釋放 WakeLock
            if (wakeLock.isHeld) {
                wakeLock.release()
                Log.d(TAG, "🔓 WakeLock 已釋放")
            }
            
            // 取消協程
            serviceScope.cancel()
            
            // 移除通知
            stopForeground(STOP_FOREGROUND_REMOVE)
            
            isServiceRunning = false
            
            Log.d(TAG, "✅ Enhanced Location Service 已停止")
            Log.d(TAG, "📊 最終統計 - 記錄: $locationUpdateCount, 成功: $uploadSuccessCount, 失敗: $uploadFailureCount")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 停止位置追蹤失敗", e)
        }
    }

    private fun hasLocationPermissions(): Boolean {
        return ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED &&
        ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * 檢查當前時間是否在通勤時段內
     */
    private fun isInCommuteTime(): Boolean {
        try {
            val sharedPreferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val now = Calendar.getInstance()
            val currentHour = now.get(Calendar.HOUR_OF_DAY)
            val currentMinute = now.get(Calendar.MINUTE)
            val currentTimeInMinutes = currentHour * 60 + currentMinute
            
            // 讀取早上通勤時段
            val morningStart = sharedPreferences.getString("flutter.commute_start_morning", null)
            val morningEnd = sharedPreferences.getString("flutter.commute_end_morning", null)
            
            if (morningStart != null && morningEnd != null) {
                val morningStartParts = morningStart.split(":")
                val morningEndParts = morningEnd.split(":")
                
                if (morningStartParts.size == 2 && morningEndParts.size == 2) {
                    val morningStartMinutes = morningStartParts[0].toInt() * 60 + morningStartParts[1].toInt()
                    val morningEndMinutes = morningEndParts[0].toInt() * 60 + morningEndParts[1].toInt()
                    
                    if (currentTimeInMinutes >= morningStartMinutes && currentTimeInMinutes <= morningEndMinutes) {
                        Log.d(TAG, "✅ 在早上通勤時段內 ($morningStart - $morningEnd)")
                        return true
                    }
                }
            }
            
            // 讀取晚上通勤時段
            val eveningStart = sharedPreferences.getString("flutter.commute_start_evening", null)
            val eveningEnd = sharedPreferences.getString("flutter.commute_end_evening", null)
            
            if (eveningStart != null && eveningEnd != null) {
                val eveningStartParts = eveningStart.split(":")
                val eveningEndParts = eveningEnd.split(":")
                
                if (eveningStartParts.size == 2 && eveningEndParts.size == 2) {
                    val eveningStartMinutes = eveningStartParts[0].toInt() * 60 + eveningStartParts[1].toInt()
                    val eveningEndMinutes = eveningEndParts[0].toInt() * 60 + eveningEndParts[1].toInt()
                    
                    if (currentTimeInMinutes >= eveningStartMinutes && currentTimeInMinutes <= eveningEndMinutes) {
                        Log.d(TAG, "✅ 在晚上通勤時段內 ($eveningStart - $eveningEnd)")
                        return true
                    }
                }
            }
            
            Log.d(TAG, "⏰ 不在任何通勤時段內")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 檢查通勤時段失敗", e)
            return true // 發生錯誤時默認允許記錄
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "🔄 Enhanced Location Service 正在銷毀...")
        stopLocationTracking()
        super.onDestroy()
    }

    // 系統資源不足時的處理
    override fun onLowMemory() {
        super.onLowMemory()
        Log.w(TAG, "⚠️ 系統內存不足")
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        Log.w(TAG, "⚠️ 系統要求釋放內存，級別: $level")
    }
}
