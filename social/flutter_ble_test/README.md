# Flutter BLE Test

這是一個 Flutter 應用程式，旨在測試和管理藍牙低能耗（BLE）設備。該應用提供了掃描、連接和與 BLE 設備互動的功能。

## 專案結構

```
flutter_ble_test
├── lib
│   ├── main.dart          # 應用程式的入口點
│   ├── ble
│   │   ├── ble_manager.dart  # 管理 BLE 連接的類
│   │   └── ble_device.dart    # 表示 BLE 設備的類
│   ├── screens
│   │   ├── home_screen.dart    # 主界面，顯示可用的 BLE 設備列表
│   │   └── device_screen.dart   # 顯示選定 BLE 設備的詳細信息
│   └── widgets
│       └── device_tile.dart     # 顯示 BLE 設備簡要信息的小部件
├── pubspec.yaml        # 專案的配置檔
└── README.md           # 專案文檔
```

## 環境設置

1. 確保已安裝 Flutter SDK。
2. 克隆此專案到本地：
   ```
   git clone <repository-url>
   ```
3. 進入專案目錄：
   ```
   cd flutter_ble_test
   ```
4. 安裝依賴項：
   ```
   flutter pub get
   ```

## 運行應用程式

使用以下命令運行應用程式：
```
flutter run
```

## 功能

- 掃描可用的 BLE 設備
- 連接和斷開 BLE 設備
- 顯示設備的詳細信息
- 與設備進行互動

## 貢獻

歡迎任何形式的貢獻！請提交問題或拉取請求。