# 🚀 Flutter BLE 社交聊天應用

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.0+-blue.svg" alt="Flutter Version">
  <img src="https://img.shields.io/badge/Dart-2.17+-green.svg" alt="Dart Version">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License">
</p>

一個基於 Flutter 開發的多功能社交應用，整合了**藍牙低功耗（BLE）設備掃描**、**即時聊天**、**GPS 位置追蹤**、**用戶註冊系統**和**頭像管理**等功能。支援透過 BLE 廣播發現附近用戶並建立聊天連接。

## ✨ 主要特色

### 📡 藍牙低功耗（BLE）功能
- **設備掃描與發現**：掃描附近的 BLE 設備，顯示用戶暱稱和頭像
- **智能廣播**：透過 BLE 廣播個人資訊（暱稱、用戶ID、頭像）
- **自動連接請求**：發現感興趣的用戶後可直接發送連接請求

### 💬 即時聊天系統
- **WebSocket 即時通訊**：基於 WebSocket 的低延遲聊天體驗
- **多房間支援**：支援多個聊天室同時運行
- **訊息歷史記錄**：本地儲存聊天記錄，離線可查看
- **智能房間管理**：自動建立和管理聊天室

### 🗺️ GPS 位置服務
- **背景位置追蹤**：支援應用關閉後繼續 GPS 記錄
- **即時位置上傳**：將 GPS 座標即時上傳到後端伺服器
- **歷史軌跡查詢**：查看特定日期的位置記錄
- **高頻率追蹤模式**：提供高精度 GPS 追蹤選項

### 👤 用戶管理系統
- **郵箱註冊登入**：使用郵件地址和密碼註冊新帳號
- **用戶資料管理**：暱稱、頭像等個人資訊設定
- **頭像系統**：支援自訂頭像圖片並透過 BLE 廣播

### 📱 現代化介面
- **底部導覽列**：直觀的五個主要功能分頁
- **響應式設計**：適配不同螢幕尺寸和設備
- **安全區域適配**：完美支援有導覽列的手機

## 🏗️ 技術架構

### 前端技術棧
- **Flutter 3.0+** - 跨平台行動應用開發框架
- **Dart 2.17+** - 程式語言
- **Material Design** - Google 設計語言

### 核心依賴套件
```yaml
dependencies:
  flutter_blue_plus: ^1.35.5      # BLE 藍牙功能
  web_socket_channel: ^2.4.0      # WebSocket 通訊
  geolocator: ^14.0.1             # GPS 定位服務
  image_picker: ^1.0.7            # 圖片選擇器
  shared_preferences: ^2.0.0      # 本地資料儲存
  permission_handler: ^12.0.0+1   # 權限管理
  http: ^1.2.1                    # HTTP 網路請求
  workmanager: ^0.9.0             # 背景任務管理
  flutter_local_notifications: ^19.4.0  # 本地通知
```

### 後端 API 集成
- **用戶認證 API** - 郵箱註冊/登入系統
- **聊天記錄 API** - 訊息歷史同步
- **GPS 資料 API** - 位置資料上傳和查詢
- **WebSocket 伺服器** - 即時通訊後端

## 📂 專案結構

```
lib/
├── main.dart                          # 應用程式入口點
├── main_tab_page.dart                 # 主要分頁導覽
├── 
├── 🔵 BLE 相關
│   ├── ble_scan_body.dart             # BLE 設備掃描頁面
│   ├── ble_scan_helper.dart           # BLE 掃描輔助工具
│   └── settings_ble_helper.dart       # BLE 設定輔助工具
├── 
├── 💬 聊天功能
│   ├── chat_service.dart              # 聊天服務核心邏輯
│   ├── chat_service_singleton.dart    # 聊天服務單例模式
│   ├── chat_models.dart               # 聊天資料模型
│   ├── chat_page.dart                 # 聊天室頁面
│   ├── chat_room_list_page.dart       # 聊天室列表頁面
│   ├── chat_room_open_manager.dart    # 聊天室開啟管理器
│   └── websocket_service.dart         # WebSocket 通訊服務
├── 
├── 📍 GPS 定位
│   ├── gps_service.dart                        # GPS 服務邏輯
│   ├── background_gps_service.dart             # 背景 GPS 服務
│   ├── enhanced_foreground_location_service.dart  # 增強版前台定位
│   ├── foreground_location_service.dart        # 前台定位服務
│   ├── gps_background_settings_page.dart       # GPS 背景設定頁
│   └── high_frequency_gps_test_page.dart       # 高頻 GPS 測試頁
├── 
├── 👤 用戶系統
│   ├── user_api_service.dart          # 用戶 API 服務
│   ├── user_id_setup_page_new.dart    # 用戶註冊頁面
│   └── user_profile_edit_page.dart    # 用戶資料編輯頁
├── 
├── 🎨 介面頁面
│   ├── avatar_page.dart               # 頭像設定頁面
│   ├── avatar_utils.dart              # 頭像處理工具
│   ├── settings_page.dart             # 設定頁面
│   └── _test_tab.dart                 # 測試工具頁面
├── 
└── ⚙️ 配置與工具
    ├── api_config.dart                # API 端點配置
    └── image_api_service.dart         # 圖片上傳服務
```

## 🚀 快速開始

### 環境需求
- Flutter 3.0 或更高版本
- Dart 2.17 或更高版本
- Android Studio / VS Code
- Android SDK（Android 開發）
- Xcode（iOS 開發）

### 安裝步驟

1. **克隆專案**
   ```bash
   git clone <repository-url>
   cd flutter_ble_test
   ```

2. **安裝依賴**
   ```bash
   flutter pub get
   ```

3. **配置 API 端點**
   
   編輯 `lib/api_config.dart`，設定您的後端 API 地址：
   ```dart
   class ApiConfig {
     static const String _baseUrl = 'https://your-api-server.com';
     static const String _wsBaseUrl = 'wss://your-websocket-server.com';
   }
   ```

4. **設定權限**

   **Android (`android/app/src/main/AndroidManifest.xml`)**
   ```xml
   <uses-permission android:name="android.permission.BLUETOOTH" />
   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
   ```

   **iOS (`ios/Runner/Info.plist`)**
   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>此應用需要藍牙權限來掃描附近的設備</string>
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>此應用需要位置權限來記錄 GPS 軌跡</string>
   ```

5. **運行應用**
   ```bash
   flutter run
   ```

## 💡 使用指南

### 📱 主要功能頁面

#### 1. **藍牙掃描頁** (🔵 藍牙)
- 點擊掃描按鈕開始搜尋附近的 BLE 設備
- 查看發現的用戶暱稱和頭像
- 點擊用戶發送連接請求

#### 2. **頭像設定頁** (🎨 Avatar)
- 上傳和編輯個人頭像
- 設定個人暱稱
- 頭像會透過 BLE 廣播給其他用戶

#### 3. **聊天室頁** (💬 聊天室)
- 查看所有聊天記錄
- 點擊進入特定聊天室
- 支援文字訊息和圖片（部分功能）

#### 4. **測試工具頁** (🔬 測試)
- 用戶註冊和登入測試
- GPS 位置上傳和查詢
- 系統功能調試工具

#### 5. **設定頁** (⚙️ 設置)
- BLE 廣播開關
- GPS 背景追蹤設定
- 系統偏好設定

### 🔧 開發者工具

#### GPS 測試功能
```dart
// 上傳當前 GPS 位置
await _uploadCurrentGPS(context);

// 查詢今日 GPS 記錄
await _getTodayGPSHistory(context);
```

#### WebSocket 連接測試
```dart
// 建立 WebSocket 連接並註冊用戶
final chatService = ChatServiceSingleton.instance;
await chatService.connectAndRegister(wsUrl, roomId, userId);
```

## 🔧 配置說明

### API 端點配置 (`lib/api_config.dart`)

```dart
class ApiConfig {
  // 🌐 基礎API端點
  static const String _baseUrl = 'https://your-backend-api.com';
  static const String _wsBaseUrl = 'wss://your-websocket-server.com';
  
  // 📍 GPS相關端點
  static String get gpsLocation => '$_baseUrl/gps/location';
  static String gpsUserLocations(String userId) => '$_baseUrl/gps/locations/$userId';
  
  // 💬 聊天相關端點
  static String get wsUrl => '$_wsBaseUrl/ws';
  static String friendsChatHistory(String roomId) => '$_baseUrl/friends/chat_history/$roomId';
  
  // 👤 用戶相關端點
  static String get userRegister => '$_baseUrl/users/register';
}
```

### 權限配置

應用需要以下權限：
- **藍牙權限** - BLE 設備掃描和廣播
- **位置權限** - GPS 追蹤功能
- **儲存權限** - 本地資料和圖片存取
- **網路權限** - API 通訊和 WebSocket 連接

## 🚀 部署說明

### Android 打包
```bash
flutter build apk --release
# 或
flutter build appbundle --release
```

### iOS 打包
```bash
flutter build ios --release
```

### 打包前檢查
- 確保所有 API 端點指向正式環境
- 檢查權限配置完整性
- 測試核心功能正常運作

## 🤝 開發參與

歡迎參與專案開發！請遵循以下步驟：

1. Fork 此專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 建立 Pull Request

### 開發規範
- 遵循 Dart 官方代碼風格
- 為新功能添加適當的註釋
- 確保代碼通過 `flutter analyze` 檢查
- 測試核心功能後再提交

## 📄 授權

此專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 文件

## 🐛 問題回報

如果您發現任何問題或有功能建議，請：

1. 檢查 [Issues](https://github.com/JSK1379/generator/issues) 是否已有相關問題
2. 如果沒有，請建立新的 Issue 並詳細描述問題
3. 提供復現步驟和設備資訊

## 📧 聯絡資訊

- **專案維護者**: JSK1379
- **GitHub**: [https://github.com/JSK1379/generator](https://github.com/JSK1379/generator)

---

<p align="center">
  ⭐ 如果這個專案對您有幫助，請給我們一個星星！ ⭐
</p>